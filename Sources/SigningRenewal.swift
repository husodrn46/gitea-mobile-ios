import SwiftUI
import UserNotifications

enum ReminderAuthorization { case notDetermined, denied, allowed, quiet }

@MainActor protocol SigningNotifying: AnyObject {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func replace(_ reminders: [SigningReminder], expiration: Date) async throws -> [SigningReminder]
    func clear()
}

@MainActor final class SigningNotifications: NSObject, SigningNotifying, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self }
    func authorization() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .provisional, .ephemeral: return .quiet
        case .authorized: return settings.alertSetting == .enabled ? .allowed : .quiet
        @unknown default: return .denied
        }
    }
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options:[.alert,.sound])
    }
    func clear() {
        center.removePendingNotificationRequests(withIdentifiers:SigningReminderPlan.identifiers)
        center.removeDeliveredNotifications(withIdentifiers:SigningReminderPlan.identifiers)
    }
    func replace(_ reminders: [SigningReminder], expiration: Date) async throws -> [SigningReminder] {
        let obsolete = SigningReminderPlan.identifiers.filter { id in !reminders.contains { $0.id == id } }
        center.removePendingNotificationRequests(withIdentifiers:obsolete)
        let expiryText = expiration.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier:"tr_TR")))
        do {
            for reminder in reminders {
                let content = UNMutableNotificationContent()
                content.title = "Gitea’yı yenileme zamanı"
                content.body = "Kurulum süren \(expiryText) tarihinde doluyor. Uygulamayı kullanmaya devam etmek için Mac’inden yeniden imzala."
                content.sound = .default
                var parts = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second],from:reminder.date)
                parts.calendar = Calendar.current; parts.timeZone = .current
                let trigger = UNCalendarNotificationTrigger(dateMatching:parts,repeats:false)
                try await center.add(UNNotificationRequest(identifier:reminder.id,content:content,trigger:trigger))
            }
            let pending = await center.pendingNotificationRequests()
            let saved = pending.compactMap { request -> SigningReminder? in
                guard SigningReminderPlan.identifiers.contains(request.identifier),
                      let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return nil }
                return SigningReminder(id:request.identifier,date:date)
            }.sorted { $0.date < $1.date }
            guard saved.count == reminders.count,reminders.allSatisfy({ wanted in
                saved.contains { $0.id == wanted.id && abs($0.date.timeIntervalSince(wanted.date)) < 1 }
            }) else { throw ClientError.message("Hatırlatmalar cihazda doğrulanamadı.") }
            return saved
        } catch { clear(); throw error }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,willPresent notification: UNNotification,withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner,.sound,.list])
    }
}

@MainActor final class SigningRenewal: ObservableObject {
    static let enabledKey = "signingReminder.v1.enabled"
    @Published private(set) var expiration: Date?
    @Published private(set) var now: Date
    @Published private(set) var enabled: Bool
    @Published private(set) var busy = false
    @Published private(set) var authorization: ReminderAuthorization = .notDetermined
    @Published private(set) var scheduled: [SigningReminder] = []
    @Published private(set) var error: String?
    let isFixture: Bool
    private let defaults: UserDefaults
    private let notifications: SigningNotifying
    private let readExpiration: () -> Date?
    private let clock: () -> Date

    init(defaults: UserDefaults = .standard,notifications: SigningNotifying? = nil,readExpiration: (() -> Date?)? = nil,clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.notifications = notifications ?? SigningNotifications(); self.clock = clock
        var reader: () -> Date? = readExpiration ?? { SigningProfile.bundledExpiration() }
        var fixture = false
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if readExpiration == nil,ProcessInfo.processInfo.arguments.contains("--fixture-gitea"),
           environment["GITEA_TEST_PREFERENCES"]?.hasPrefix("test.") == true,
           let value = environment["GITEA_SIGNING_FIXTURE"] {
            let simulated = value == "missing" ? nil : clock().addingTimeInterval(value == "soon" ? 36 * 3600 : 7 * 86400)
            reader = { simulated }; fixture = true
        }
        #endif
        self.readExpiration = reader; isFixture = fixture
        expiration = reader(); now = clock(); enabled = defaults.bool(forKey:Self.enabledKey)
    }
    var isExpiringSoon: Bool { expiration.map { $0.timeIntervalSince(now) <= 3 * 86400 } ?? false }
    var canEnable: Bool { expiration.map { $0 > now } ?? false }
    var remaining: String {
        guard let expiration else { return "Süre bilgisi yok" }
        let seconds = expiration.timeIntervalSince(now)
        if seconds <= 0 { return "Yenileme gerekiyor" }
        if seconds < 86400 { return "Son 24 saat" }
        return "Yaklaşık \(Int(ceil(seconds / 86400))) gün kaldı"
    }
    func refresh() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        expiration = readExpiration(); now = clock(); error = nil
        authorization = await notifications.authorization()
        await reconcile()
    }
    func setEnabled(_ value: Bool) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        error = nil; expiration = readExpiration(); now = clock()
        if !value {
            enabled = false; defaults.set(false,forKey:Self.enabledKey)
            notifications.clear(); scheduled = []; return
        }
        guard canEnable else { return }
        authorization = await notifications.authorization()
        do {
            if authorization == .notDetermined { _ = try await notifications.requestAuthorization() }
            authorization = await notifications.authorization()
            guard authorization == .allowed || authorization == .quiet else {
                error = "Hatırlatma için iPhone Ayarları’ndan Gitea bildirimlerine izin ver."; return
            }
            enabled = true
            await reconcile()
            if error == nil { defaults.set(true,forKey:Self.enabledKey) }
            else { enabled = false; defaults.set(false,forKey:Self.enabledKey) }
        } catch {
            self.error = "Bildirim izni alınamadı. Yeniden deneyebilirsin."
        }
    }
    private func reconcile() async {
        guard enabled,let expiration,expiration > now,
              authorization == .allowed || authorization == .quiet else {
            notifications.clear(); scheduled = []; return
        }
        let plan = SigningReminderPlan.reminders(expiration:expiration,now:now)
        do { scheduled = try await notifications.replace(plan,expiration:expiration) }
        catch {
            notifications.clear(); scheduled = []
            self.error = "Hatırlatma kaydedilemedi. Yeniden dene; şu anda zamanlanmış bildirim yok."
        }
    }
}

struct SigningRenewalView: View {
    @EnvironmentObject private var renewal: SigningRenewal
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section {
                VStack(alignment:.leading,spacing:12) {
                    Image(systemName:"calendar.badge.clock").font(.largeTitle).foregroundStyle(renewal.isExpiringSoon ? Color.orange : Color.accentColor)
                    Text(renewal.remaining).font(.title2.bold()).accessibilityIdentifier("signingRemaining")
                    if let expiration = renewal.expiration {
                        Text(expiration.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier:"tr_TR")))).font(.headline).accessibilityIdentifier("signingExpiration")
                        Text("Bu tarihten önce Mac’inden kurulumunu yenile.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Bu kurulumun imza bitiş tarihi okunamıyor. Simülatörde süreli cihaz imzası bulunmaz.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if renewal.isFixture { Text("Önizleme · Örnek kurulum tarihi").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("signingFixture") }
                }.padding(.vertical,8)
            } header: { Text("Kurulumun") } footer: {
                Text("Tarih, bu uygulamanın kurulum profilinden okunur. Yeni imzayla yüklediğinde kendiliğinden güncellenir.")
            }
            Section {
                Toggle("İmza yenilemeyi hatırlat",isOn:Binding(get:{ renewal.enabled },set:{ value in Task { await renewal.setEnabled(value) } }))
                    .disabled(renewal.busy || (!renewal.canEnable && !renewal.enabled)).accessibilityIdentifier("signingReminderToggle")
                if renewal.busy { ProgressView("Kontrol ediliyor…") }
                if renewal.enabled && renewal.authorization == .notDetermined && !renewal.busy {
                    Button("Bildirim izni ver") { Task { await renewal.setEnabled(true) } }
                }
                if renewal.authorization == .denied || renewal.authorization == .quiet {
                    Text(renewal.authorization == .denied ? "Gitea bildirimleri iPhone Ayarları’nda kapalı." : "Bildirimler sessiz veya uyarısız gösterilebilir. Uyarı ayarlarını kontrol edebilirsin.").font(.footnote).foregroundStyle(.secondary)
                    Button("Bildirim ayarlarını aç") { if let url = URL(string:UIApplication.openNotificationSettingsURLString) { openURL(url) } }.accessibilityIdentifier("signingNotificationSettings")
                }
                if let error = renewal.error {
                    Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("signingReminderError")
                    Button("Yeniden dene") { Task { await renewal.setEnabled(true) } }.disabled(renewal.busy || !renewal.canEnable)
                }
            } header: { Text("Hatırlatma") } footer: {
                Text("İki gün ve bir gün önce, yerel saatle 10.00’da. iOS bildirim iznini yalnız bu seçeneği açtığında ister. Hatırlatma imza süresini uzatmaz.")
            }
            if !renewal.scheduled.isEmpty {
                Section("Cihazda zamanlandı") {
                    ForEach(renewal.scheduled,id:\.id) { reminder in
                        Label { Text(reminder.date.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier:"tr_TR")))) } icon: { Image(systemName:"bell.badge") }
                            .accessibilityIdentifier(reminder.id)
                    }
                }
            } else if renewal.enabled && renewal.canEnable && !renewal.busy && renewal.error == nil && (renewal.authorization == .allowed || renewal.authorization == .quiet) {
                Section { Text("Bu kurulum için hatırlatma saatleri geçmiş. Süre dolmadan Mac’inden yenileyebilirsin.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Nasıl yenilenir?") {
                Text("iPhone’u Mac’e bağla ve Gitea’yı yeniden imzalayıp üzerine yükle. Uygulamayı silmene gerek yok.")
                Text("Gitea erişim anahtarı ile Apple’ın kurulum imzası ayrı şeylerdir; imza yenilemek için yeni Gitea anahtarı oluşturman gerekmez.").font(.footnote).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(Color.canvas)
            .navigationTitle("Kurulum süresi").navigationBarTitleDisplayMode(.inline)
            .task { await renewal.refresh() }
    }
}

struct SigningExpiryNotice: View {
    @EnvironmentObject private var renewal: SigningRenewal
    var body: some View {
        if renewal.isExpiringSoon {
            NavigationLink { SigningRenewalView() } label: {
                HStack(spacing:12) {
                    Image(systemName:"calendar.badge.exclamationmark").foregroundStyle(.orange)
                    VStack(alignment:.leading,spacing:4) {
                        Text("Gitea kurulumunu yenile").font(.headline)
                        Text(renewal.remaining).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                }.padding(16).background(.orange.opacity(0.09),in:RoundedRectangle(cornerRadius:20))
            }.buttonStyle(.plain).accessibilityIdentifier("signingExpiryNotice")
        }
    }
}
