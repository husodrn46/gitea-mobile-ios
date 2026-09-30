import SwiftUI
import LocalAuthentication
import Combine

enum LockDelay: Int, Codable, CaseIterable, Identifiable {
    case immediately = 0, seconds30 = 30, minute = 60, minutes5 = 300
    var id: Int { rawValue }
    var title: String {
        switch self { case .immediately: "Hemen"; case .seconds30: "30 saniye sonra"; case .minute: "1 dakika sonra"; case .minutes5: "5 dakika sonra" }
    }
}
struct PrivacyPreferences: Codable, Equatable {
    var version = 1
    var enabled = false
    var delay: LockDelay = .immediately
    var hidePreview = true
    var automaticUnlock = true
}
enum AccessActivity { case active, inactive, background }

@MainActor protocol DeviceAuthenticating: AnyObject {
    func authenticate(reason: String) async throws -> Bool
    func cancel()
}
@MainActor final class DeviceAuthenticator: DeviceAuthenticating {
    private var context: LAContext?
    func authenticate(reason: String) async throws -> Bool {
        let next = LAContext()
        next.localizedCancelTitle = "Vazgeç"
        next.touchIDAuthenticationAllowableReuseDuration = 0
        var failure: NSError?
        guard next.canEvaluatePolicy(.deviceOwnerAuthentication,error:&failure) else {
            throw failure ?? ClientError.message("Bu cihazda kimlik doğrulama kullanılamıyor.") as NSError
        }
        context = next
        defer { if context === next { context = nil }; next.invalidate() }
        return try await next.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:reason)
    }
    func cancel() { context?.invalidate(); context = nil }
}

@MainActor final class AppAccess: ObservableObject {
    static let preferencesKey = "privacy.v1"
    @Published private(set) var preferences: PrivacyPreferences
    @Published private(set) var locked: Bool
    @Published private(set) var contentHasOpened: Bool
    @Published private(set) var authenticating = false
    @Published private(set) var activity: AccessActivity = .active
    @Published private(set) var error: String?
    @Published private(set) var storageNotice: String?
    @Published private(set) var activationID = UUID()
    let isFixture: Bool
    private let defaults: UserDefaults
    private let authenticator: DeviceAuthenticating
    private let clock: () -> TimeInterval
    private var inactiveAt: TimeInterval?
    private var operationID: UUID?
    private var autoAttempted = false
    private var authenticationInterruption = false

    init(defaults: UserDefaults = .standard,authenticator: DeviceAuthenticating? = nil,clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults; self.clock = clock
        var value = PrivacyPreferences()
        if defaults.object(forKey:Self.preferencesKey) != nil {
            do {
                guard let raw = defaults.data(forKey:Self.preferencesKey) else { throw ClientError.message("Geçersiz kilit kaydı.") }
                value = try JSONDecoder().decode(PrivacyPreferences.self,from:raw)
                guard value.version == 1 else { throw ClientError.message("Desteklenmeyen kilit kaydı.") }
            } catch {
                value = PrivacyPreferences(enabled:true,automaticUnlock:false)
                storageNotice = "Kilit ayarları okunamadı. Kimliğini doğrulayarak açabilirsin; önceki kayıt korunuyor."
            }
        }
        preferences = value; locked = value.enabled; contentHasOpened = !value.enabled
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if authenticator == nil,ProcessInfo.processInfo.arguments.contains("--fixture-gitea"),
           environment["GITEA_TEST_PREFERENCES"]?.hasPrefix("test.") == true,
           let sequence = environment["GITEA_AUTH_FIXTURE"] {
            self.authenticator = FixtureDeviceAuthenticator(sequence:sequence); isFixture = true
        } else { self.authenticator = authenticator ?? DeviceAuthenticator(); isFixture = false }
        #else
        self.authenticator = authenticator ?? DeviceAuthenticator(); isFixture = false
        #endif
    }
    var shouldCover: Bool { locked || (activity != .active && (preferences.hidePreview || preferences.enabled)) }
    func changeActivity(_ next: AccessActivity) {
        guard activity != next else { return }
        activity = next
        switch next {
        case .inactive:
            authenticationInterruption = authenticating
            if !authenticating {
                autoAttempted = false
                if preferences.enabled {
                    inactiveAt = inactiveAt ?? clock()
                    if preferences.delay == .immediately { locked = true }
                }
            }
        case .background:
            let hadAuthentication = authenticating
            cancelAuthentication()
            authenticationInterruption = false; autoAttempted = false
            if preferences.enabled {
                inactiveAt = inactiveAt ?? clock()
                if hadAuthentication || preferences.delay == .immediately { locked = true }
            }
        case .active:
            if preferences.enabled,let inactiveAt {
                let elapsed = clock() - inactiveAt
                if !elapsed.isFinite || elapsed < 0 || elapsed >= Double(preferences.delay.rawValue) { locked = true }
            }
            inactiveAt = nil
            if !authenticationInterruption { activationID = UUID() }
            authenticationInterruption = false
        }
    }
    func tryAutomaticUnlock() async {
        guard preferences.automaticUnlock,locked,!autoAttempted,activity == .active else { return }
        await unlock()
    }
    func unlock() async {
        guard locked,activity == .active,!authenticating else { return }
        autoAttempted = true
        guard await verify("Kişisel Gitea alanını açmak için kimliğini doğrula.") else { return }
        if storageNotice != nil { guard persist(preferences) else { return } }
        locked = false; contentHasOpened = true; inactiveAt = nil
    }
    func setEnabled(_ enabled: Bool) async {
        guard !locked,enabled != preferences.enabled else { return }
        guard await verify(enabled ? "Kişisel kilidi etkinleştirmek için kimliğini doğrula." : "Kişisel kilidi kapatmak için kimliğini doğrula.") else { return }
        var next = preferences; next.enabled = enabled
        if persist(next) { locked = false; contentHasOpened = true; autoAttempted = true }
    }
    func setDelay(_ delay: LockDelay) async {
        guard preferences.enabled,!locked,delay != preferences.delay else { return }
        guard await verify("Kilit süresini değiştirmek için kimliğini doğrula.") else { return }
        var next = preferences; next.delay = delay; _ = persist(next)
    }
    func setAutomaticUnlock(_ automatic: Bool) {
        guard !locked else { return }
        var next = preferences; next.automaticUnlock = automatic; _ = persist(next)
    }
    func setHidePreview(_ hidden: Bool) {
        guard !locked,!preferences.enabled else { return }
        var next = preferences; next.hidePreview = hidden; _ = persist(next)
    }
    func lockNow() {
        guard preferences.enabled else { return }
        cancelAuthentication(); locked = true; autoAttempted = true; error = nil
    }
    private func verify(_ reason: String) async -> Bool {
        guard !authenticating,activity == .active else { return false }
        let id = UUID(); operationID = id; authenticating = true; error = nil
        do {
            let success = try await authenticator.authenticate(reason:reason)
            guard operationID == id,activity != .background else { return false }
            operationID = nil; authenticating = false
            if !success { error = "Kimliğin doğrulanamadı. Yeniden deneyebilirsin." }
            return success
        } catch {
            guard operationID == id else { return false }
            operationID = nil; authenticating = false
            self.error = Self.message(for:error)
            return false
        }
    }
    private func cancelAuthentication() {
        operationID = nil; authenticating = false; authenticator.cancel()
    }
    private func persist(_ value: PrivacyPreferences) -> Bool {
        do {
            let data = try JSONEncoder().encode(value)
            if storageNotice != nil,let original = defaults.object(forKey:Self.preferencesKey) {
                defaults.set(original,forKey:Self.preferencesKey + ".unreadable." + UUID().uuidString)
            }
            defaults.set(data,forKey:Self.preferencesKey); preferences = value; storageNotice = nil
            return true
        } catch { self.error = "Kilit ayarı kaydedilemedi. Önceki ayar korunuyor."; return false }
    }
    static func message(for error: Error) -> String {
        guard let error = error as? LAError else { return "Kimlik doğrulama tamamlanamadı. Yeniden deneyebilirsin." }
        switch error.code {
        case .userCancel,.systemCancel,.appCancel: return "Doğrulama iptal edildi. Yeniden deneyebilirsin."
        case .passcodeNotSet: return "Önce iPhone veya iPad Ayarları’nda bir aygıt parolası ayarla."
        case .biometryNotAvailable,.biometryNotEnrolled: return "Biyometri kullanılamıyor. Aygıt parolası seçeneğini veya Ayarlar’daki Face ID / Touch ID izinlerini kontrol et."
        case .biometryLockout: return "Biyometri geçici olarak kilitli. Aygıt parolanla yeniden doğrula."
        default: return "Kimliğin doğrulanamadı. Yeniden deneyebilirsin."
        }
    }
}

#if DEBUG
@MainActor private final class FixtureDeviceAuthenticator: DeviceAuthenticating {
    private var responses: [String]
    init(sequence: String) { responses = sequence.split(separator:",").map(String.init) }
    func authenticate(reason: String) async throws -> Bool {
        let response = responses.isEmpty ? "fail" : responses.removeFirst()
        if response == "cancel" { throw LAError(.userCancel) }
        return response == "success"
    }
    func cancel() { }
}
#endif

struct PrivacySettingsView: View {
    @EnvironmentObject private var access: AppAccess
    var body: some View {
        Form {
            Section {
                Toggle("Kişisel kilit",isOn:Binding(get:{ access.preferences.enabled },set:{ value in Task { await access.setEnabled(value) } }))
                    .accessibilityIdentifier("personalLock")
                if access.authenticating { ProgressView("Kimliğin doğrulanıyor…") }
            } header: { Text("Yalnız cihaz kimliğinle") } footer: {
                Text("Face ID, Touch ID veya aygıt parolası kullanılır. Bu cihazda tanımlı biyometri ya da parolayla açılır; uygulama parolanı veya biyometrini saklamaz.")
            }.disabled(access.authenticating)
            if access.preferences.enabled {
                Section {
                    Picker("Yeniden kilitle",selection:Binding(get:{ access.preferences.delay },set:{ value in Task { await access.setDelay(value) } })) {
                        ForEach(LockDelay.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("lockDelay")
                    Toggle("Açarken doğrulamayı başlat",isOn:Binding(get:{ access.preferences.automaticUnlock },set:{ access.setAutomaticUnlock($0) }))
                        .accessibilityIdentifier("autoUnlock")
                    Button("Şimdi kilitle",systemImage:"lock.fill") { access.lockNow() }.accessibilityIdentifier("lockNow")
                } footer: { Text("Süre, uygulamadan ayrıldığın andan başlar. Uygulamayı yeniden başlatmak her zaman doğrulama ister.") }.disabled(access.authenticating)
            }
            Section {
                Toggle("Uygulama değiştiricide gizle",isOn:Binding(get:{ access.preferences.enabled || access.preferences.hidePreview },set:{ access.setHidePreview($0) }))
                    .disabled(access.preferences.enabled || access.authenticating).accessibilityIdentifier("hidePreview")
            } footer: { Text(access.preferences.enabled ? "Kilit açıkken içerik arka planda her zaman örtülür. Yazdığın metin açınca yerinde kalır." : "Başka uygulamaya geçerken açık ekranını ve formlarını örter.") }
            if let error = access.error { Section { Text(error).foregroundStyle(Color.waiting).accessibilityIdentifier("privacyError") } }
            if let notice = access.storageNotice { Section { Text(notice).foregroundStyle(Color.waiting) } }
            if access.isFixture { Section { Text("Örnek doğrulama · Gerçek aygıt kimliği kullanılmıyor.").font(.footnote) } }
        }.navigationTitle("Gizlilik ve kilit").navigationBarTitleDisplayMode(.inline)
    }
}

struct AppPrivacyGate<Content: View>: View {
    @EnvironmentObject private var access: AppAccess
    @EnvironmentObject private var appearance: Appearance
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()
            if access.contentHasOpened {
                content.allowsHitTesting(!access.shouldCover).accessibilityHidden(access.shouldCover)
            }
        }
        .background(PrivacyWindowBridge(access:access,appearance:appearance))
        .task(id:access.activationID) { await access.tryAutomaticUnlock() }
    }
}
private struct PrivacyCoverView: View {
    @ObservedObject var access: AppAccess
    @ObservedObject var appearance: Appearance
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(spacing:24) {
                Image(systemName:"lock.fill").font(.system(size:44,weight:.medium)).foregroundStyle(appearance.accent(scheme)).accessibilityHidden(true)
                Text("Kişisel alanın").font(.largeTitle.bold()).accessibilityIdentifier("privacyCoverTitle")
                if access.activity == .active && access.locked {
                    Text("Face ID, Touch ID veya aygıt parolanla aç.").foregroundStyle(.secondary)
                    if access.authenticating { ProgressView("Kimliğin doğrulanıyor…").accessibilityIdentifier("authenticating") }
                    else { Button("Kilidi aç") { Task { await access.unlock() } }.buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("unlockApp") }
                    if let error = access.error { Text(error).foregroundStyle(Color.waiting).accessibilityIdentifier("lockError") }
                    if let notice = access.storageNotice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                    if access.isFixture { Text("Örnek doğrulama").font(.caption).foregroundStyle(.secondary) }
                } else { Text("İçerik gizlendi").foregroundStyle(.secondary) }
            }.multilineTextAlignment(.center).frame(maxWidth:.infinity).padding(30).padding(.top,70)
        }.background(Color.canvas.ignoresSafeArea()).tint(appearance.accent(scheme))
            .preferredColorScheme(appearance.scheme).fontDesign(appearance.layout.textStyle.design)
    }
}

/// A separate opaque window covers sheets; per-window masks also cover app-switcher snapshots.
private struct PrivacyWindowBridge: UIViewRepresentable {
    let access: AppAccess
    let appearance: Appearance
    func makeCoordinator() -> PrivacyWindowCoordinator { PrivacyWindowCoordinator(access:access,appearance:appearance) }
    func makeUIView(context: Context) -> PrivacyMountView {
        let view = PrivacyMountView(); view.attached = { [weak coordinator = context.coordinator] window in coordinator?.attach(to:window) }
        return view
    }
    func updateUIView(_ uiView: PrivacyMountView,context: Context) { context.coordinator.refresh() }
    static func dismantleUIView(_ uiView: PrivacyMountView,coordinator: PrivacyWindowCoordinator) { coordinator.detach() }
}
private final class PrivacyMountView: UIView {
    var attached: ((UIWindow) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); if let window { attached?(window) } }
}
private final class PrivacyWindow: UIWindow { override var canBecomeKey: Bool { false } }
@MainActor private final class PrivacyWindowCoordinator: NSObject {
    private let access: AppAccess
    private let appearance: Appearance
    private weak var sourceWindow: UIWindow?
    private var cover: PrivacyWindow?
    private var subscription: AnyCancellable?
    private var masks: [(window: UIWindow,view: UIView,accessibilityHidden: Bool)] = []
    init(access: AppAccess,appearance: Appearance) {
        self.access = access; self.appearance = appearance; super.init()
        let center = NotificationCenter.default
        center.addObserver(self,selector:#selector(resign),name:UIApplication.willResignActiveNotification,object:nil)
        center.addObserver(self,selector:#selector(background),name:UIApplication.didEnterBackgroundNotification,object:nil)
        center.addObserver(self,selector:#selector(activate),name:UIApplication.didBecomeActiveNotification,object:nil)
        center.addObserver(self,selector:#selector(windowAppeared),name:UIWindow.didBecomeVisibleNotification,object:nil)
        center.addObserver(self,selector:#selector(sceneResigned),name:UIScene.willDeactivateNotification,object:nil)
        center.addObserver(self,selector:#selector(sceneBackgrounded),name:UIScene.didEnterBackgroundNotification,object:nil)
        center.addObserver(self,selector:#selector(sceneActivated),name:UIScene.didActivateNotification,object:nil)
        subscription = access.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
    }
    func attach(to window: UIWindow) {
        guard cover == nil,let scene = window.windowScene else { return }
        sourceWindow = window
        let overlay = PrivacyWindow(windowScene:scene)
        overlay.frame = scene.effectiveGeometry.coordinateSpace.bounds
        overlay.windowLevel = .init(rawValue:UIWindow.Level.alert.rawValue + 1)
        let host = UIHostingController(rootView:PrivacyCoverView(access:access,appearance:appearance))
        host.view.isOpaque = true; host.view.accessibilityViewIsModal = true
        overlay.rootViewController = host; overlay.isOpaque = true; cover = overlay
        let state = UIApplication.shared.applicationState
        access.changeActivity(state == .active ? .active : state == .background ? .background : .inactive)
        refresh()
    }
    func refresh() {
        guard let cover,let scene = sourceWindow?.windowScene else { return }
        let protected = access.shouldCover || (scene.activationState != .foregroundActive && (access.preferences.enabled || access.preferences.hidePreview))
        let style: UIUserInterfaceStyle = appearance.mode == "Koyu" ? .dark : appearance.mode == "Açık" ? .light : sourceWindow?.traitCollection.userInterfaceStyle ?? .unspecified
        cover.overrideUserInterfaceStyle = style
        let color = UIColor(Color.canvas).resolvedColor(with:UITraitCollection(userInterfaceStyle:style))
        cover.backgroundColor = color; cover.rootViewController?.view.backgroundColor = color
        cover.frame = scene.effectiveGeometry.coordinateSpace.bounds
        if protected {
            for window in scene.windows where window !== cover {
                if !masks.contains(where:{ $0.window === window }) {
                    let mask = UIView(frame:window.bounds)
                    mask.autoresizingMask = [.flexibleWidth,.flexibleHeight]; mask.isOpaque = true
                    masks.append((window,mask,window.accessibilityElementsHidden))
                    window.endEditing(true); window.addSubview(mask)
                }
                if let item = masks.first(where:{ $0.window === window }) {
                    item.view.backgroundColor = color; window.bringSubviewToFront(item.view)
                    window.accessibilityElementsHidden = true
                }
            }
            cover.isHidden = false
            cover.rootViewController?.view.layoutIfNeeded()
        } else {
            cover.isHidden = true
            removeMasks()
        }
    }
    private func removeMasks() {
        for item in masks { item.view.removeFromSuperview(); item.window.accessibilityElementsHidden = item.accessibilityHidden }
        masks.removeAll()
    }
    func detach() {
        NotificationCenter.default.removeObserver(self); subscription?.cancel(); subscription = nil
        cover?.isHidden = true; cover = nil; removeMasks(); sourceWindow = nil
    }
    @objc private func resign() { access.changeActivity(.inactive); refresh() }
    @objc private func background() { access.changeActivity(.background); refresh() }
    @objc private func activate() { access.changeActivity(.active); refresh() }
    @objc private func sceneResigned(_ note: Notification) { if note.object as? UIScene === sourceWindow?.windowScene { resign() } }
    @objc private func sceneBackgrounded(_ note: Notification) { if note.object as? UIScene === sourceWindow?.windowScene { background() } }
    @objc private func sceneActivated(_ note: Notification) { if note.object as? UIScene === sourceWindow?.windowScene { activate() } }
    @objc private func windowAppeared(_ note: Notification) {
        guard let window = note.object as? UIWindow,window !== cover,window.windowScene === sourceWindow?.windowScene else { return }
        refresh()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
