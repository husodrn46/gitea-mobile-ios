import SwiftUI

struct AppearanceSheet: View {
    @EnvironmentObject var appearance: Appearance
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var reduced
    @Environment(\.dismiss) var dismiss
    @State private var recovering = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Tema") {
                    Picker("Tema",selection:$appearance.mode) { ForEach(["Sistem","Açık","Koyu"],id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("themePicker")
                }
                Section("Vurgu rengi") {
                    HStack(spacing:0) {
                        ForEach(["Mor","Mavi","Nane","Mercan","Pembe"],id:\.self) { name in
                            Button {
                                withAnimation(appearance.animation(reduced:reduced)) { appearance.accentName = name }; appearance.tap()
                            } label: {
                                ZStack {
                                    Circle().fill(swatch(name)).frame(width:38,height:38)
                                    if appearance.accentName == name { Image(systemName:"checkmark").font(.system(size:15,weight:.bold)).foregroundStyle(scheme == .dark ? .black : .white) }
                                }.frame(maxWidth:.infinity,minHeight:48)
                            }.buttonStyle(.plain).accessibilityLabel("\(name) vurgu").accessibilityValue(appearance.accentName == name ? "Seçili" : "")
                        }
                    }
                    ColorPicker("Kendi rengin",selection:Binding(get:{ Color(hex:appearance.customHex) },set:{ color in
                        var r: CGFloat = 0,g: CGFloat = 0,b: CGFloat = 0,a: CGFloat = 0
                        UIColor(color).getRed(&r,green:&g,blue:&b,alpha:&a)
                        appearance.customHex = String(format:"%02X%02X%02X",Int(r*255),Int(g*255),Int(b*255)); appearance.accentName = "Özel"
                    }),supportsOpacity:false)
                }
                Section {
                    Toggle("Animasyonlar",isOn:$appearance.motion).accessibilityIdentifier("motionToggle")
                    Toggle("Dokunma titreşimi",isOn:$appearance.haptics)
                } header: { Text("Hareket ve his") } footer: {
                    Text(reduced ? "iPhone’da Hareketi Azalt açık. Uygulama animasyonları da azaltılır." : "Ekran geçişleri iOS’a aittir. Bu ayar uygulama içindeki renk, filtre ve favori animasyonlarını kontrol eder.")
                }
                Section("Düzenini kur") {
                    NavigationLink("Ekran düzeni") { LayoutSettingsView() }.accessibilityIdentifier("layoutSettings")
                    NavigationLink("Kartlar ve yazı") { CardSettingsView() }.accessibilityIdentifier("cardSettings")
                    NavigationLink("Kayıtlı düzenler") { SavedStylesView() }.accessibilityIdentifier("savedStyles")
                }.disabled(appearance.personalizationError != nil)
                if let error = appearance.personalizationError {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(Color.waiting)
                        Button("Yeni düzenle devam et") { recovering = true }
                    }
                }
                Section {
                    HStack(spacing:14) {
                        ProjectMark(kind:4,color:appearance.accent(scheme))
                        VStack(alignment:.leading,spacing:4) { Text("Tam senin rengin.").font(.headline); Text("Başarı ve uyarı renkleri sabit kalır.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical,7)
                }
            }
            .navigationTitle("Kişiselleştir").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Bitti") { dismiss() } } }
            .tint(appearance.accent(scheme))
        }.preferredColorScheme(appearance.scheme).fontDesign(appearance.layout.textStyle.design).presentationDetents([.large]).presentationDragIndicator(.visible)
            .confirmationDialog("Yeni düzen başlatılsın mı?",isPresented:$recovering,titleVisibility:.visible) {
                Button("Eski kaydı koru ve başlat") { appearance.recoverPersonalization() }
            } message: { Text("Okunamayan ayarlar bu cihazda ayrı bir kayıt olarak korunur. Yeni düzen varsayılanlarla başlar.") }
    }
    func swatch(_ name: String) -> Color {
        let light = ["Mor":"7044BC","Mavi":"225EB0","Nane":"16745C","Mercan":"AD4838","Pembe":"A0367D"]
        let dark = ["Mor":"BC9CFF","Mavi":"83B5FF","Nane":"75D6BA","Mercan":"FFA18E","Pembe":"F1A6D7"]
        return Color(hex:(scheme == .dark ? dark : light)[name]!)
    }
}
struct IdeaSheet: View {
    @EnvironmentObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    let existing: DraftIdea?
    @State private var title: String
    @State private var problem: String
    @State private var acceptance: String
    @State private var discardShown = false
    @State private var draftScope: String?
    @State private var scopeCaptured = false
    init(existing: DraftIdea? = nil,initialProject: String = "") {
        self.existing = existing
        _title = State(initialValue:existing?.title ?? "")
        _text = State(initialValue:existing?.text ?? "")
        _project = State(initialValue:existing?.project ?? initialProject)
        _problem = State(initialValue:existing?.problem ?? "")
        _acceptance = State(initialValue:existing?.acceptance ?? "")
    }
    var hasChanges: Bool {
        title != (existing?.title ?? "") || text != (existing?.text ?? "") || problem != (existing?.problem ?? "") || acceptance != (existing?.acceptance ?? "") || (existing != nil && project != existing?.project)
    }
    @State private var text = ""
    @State private var project = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Aklındaki ne?") {
                    TextField("Fikrine bir başlık ver",text:$title).accessibilityIdentifier("ideaTitle")
                    TextEditor(text:$text).frame(minHeight:100).accessibilityLabel("Fikir açıklaması")
                }
                Section {
                    DisclosureGroup("Fikri netleştir · İsteğe bağlı") {
                        TextField("Hangi sorunu çözer?",text:$problem,axis:.vertical).lineLimit(2...5).accessibilityIdentifier("ideaProblem")
                        TextField("Ne olunca tamam diyeceksin?",text:$acceptance,axis:.vertical).lineLimit(2...5).accessibilityIdentifier("ideaAcceptance")
                    }
                }
                Section("Proje") {
                    Picker("İlgili proje",selection:$project) { Text("Genel fikir").tag(""); if !project.isEmpty && !workspace.projects.contains(where: { $0.fullName == project }) { Text(project).tag(project) }; ForEach(workspace.projects) { p in Text(p.name).tag(p.fullName) } }
                }
                Section { Text("Taslak yalnız bu cihazda saklanır. Henüz Gitea’ya issue gönderilmez.").font(.footnote).foregroundStyle(.secondary) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(existing == nil ? "Yeni fikir" : "Fikri düzenle").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Vazgeç") { if hasChanges { discardShown = true } else { dismiss() } } }
                    ToolbarItem(placement:.confirmationAction) {
                        Button("Kaydet") {
                            do {
                                guard scopeCaptured,draftScope == workspace.identity?.scope else { throw ClientError.message("Hesap değişti. Fikri kaydetmek için formu yeniden aç.") }
                                var draft = existing ?? DraftIdea(title:"",text:"",project:"")
                                draft.title = title.trimmingCharacters(in:.whitespacesAndNewlines)
                                draft.text = text; draft.project = project.isEmpty ? "Genel fikir" : project
                                draft.problem = problem; draft.acceptance = acceptance
                                try workspace.save(draft); dismiss()
                            }
                            catch { self.error = error.localizedDescription }
                        }.disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveIdea")
                    }
                }
        }.onAppear { if !scopeCaptured { draftScope = workspace.identity?.scope; scopeCaptured = true } }.presentationDragIndicator(.visible).interactiveDismissDisabled(hasChanges)
            .alert("Kaydedilmemiş değişiklikler silinsin mi?",isPresented:$discardShown) {
                Button("Değişiklikleri sil",role:.destructive) { dismiss() }
                Button("Yazmaya devam et",role:.cancel) { }
            }
    }
}
struct DraftDetail: View {
    let draft: DraftIdea
    @EnvironmentObject var workspace: Workspace
    @State private var editing = false
    @State private var publishing = false
    var current: DraftIdea { workspace.drafts.first { $0.id == draft.id } ?? draft }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                StatusPill(text:"Cihazındaki taslak",color:.secondary)
                Text(current.title).font(.largeTitle.bold())
                Text(current.project).foregroundStyle(.secondary)
                Text(current.text.isEmpty ? "Açıklama eklenmemiş." : current.text).textSelection(.enabled)
                if let problem = current.problem, !problem.isEmpty { Text("Hangi sorunu çözer?").font(.headline); Text(problem) }
                if let acceptance = current.acceptance, !acceptance.isEmpty { Text("Ne zaman tamam?").font(.headline); Text(acceptance) }
                if workspace.live { Button("Gitea’da konu oluştur") { publishing = true }.buttonStyle(.glassProminent).accessibilityIdentifier("publishIdea") }
                Text("Paylaşmak Gitea’da issue oluşturmaz. Göndereceğin yeri paylaşım panelinde sen seçersin.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
        }.background(Color.canvas).navigationTitle("Fikir").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Düzenle") { editing = true }.accessibilityIdentifier("editIdea")
            ShareLink(item:current.markdown) { Label("Paylaş",systemImage:"square.and.arrow.up") }
        }
        .sheet(isPresented:$editing) { IdeaSheet(existing:current) }
        .sheet(isPresented:$publishing) { NavigationStack { IssueComposer(draft:current) } }
    }
}
struct InboxView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var appearance: Appearance
    @Environment(\.accessibilityReduceMotion) var reduced
    @State private var ideaShown = false
    @State private var unreadOnly = false
    let messages = ["Claude incelemeni bekliyor", "111 kontrol başarıyla geçti", "Yeni tasarım hazır"]
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                DemoCaption()
                if workspace.live {
                    RemoteInboxView()
                } else {
                    Toggle("Yalnız okunmamış",isOn:$unreadOnly).font(.subheadline)
                    ForEach((0..<3).filter { !unreadOnly || !workspace.readActivities.contains($0) },id:\.self) { i in
                        Button {
                            withAnimation(appearance.animation(reduced:reduced)) { _ = workspace.readActivities.insert(i) }; appearance.tap()
                        } label: {
                            Surface {
                                HStack(spacing:14) {
                                    MarkView(kind:i+2).foregroundStyle(workspace.readActivities.contains(i) ? Color.secondary : Color.accentColor)
                                    VStack(alignment:.leading,spacing:7) { Text(messages[i]).font(.headline).foregroundStyle(.primary); Text(workspace.readActivities.contains(i) ? "Okundu" : "Okundu olarak işaretlemek için dokun").font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); if !workspace.readActivities.contains(i) { Circle().fill(.tint).frame(width:7,height:7) }
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    if unreadOnly && workspace.readActivities.count == 3 { ContentUnavailableView("Hepsi tamam",systemImage:"checkmark",description:Text("Okunmamış örnek bildirim kalmadı.")) }
                }
            }.padding(22)
        }.background(Color.canvas).navigationTitle("Gelen kutusu")
        .toolbar { Button("Yeni fikir",systemImage:"plus") { ideaShown = true } }
        .sheet(isPresented:$ideaShown) { IdeaSheet() }
    }
}
struct ProfileView: View {
    @EnvironmentObject var workspace: Workspace
    @EnvironmentObject var appearance: Appearance
    @Environment(\.colorScheme) var scheme
    @State private var appearanceShown = false
    @State private var connectionShown = false
    @State private var ideaShown = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                HStack(spacing:17) {
                    MarkView(kind:3,size:42).foregroundStyle(appearance.accent(scheme)).frame(width:66,height:66).glassEffect(.regular.tint(appearance.accent(scheme).opacity(0.12)),in:Circle())
                    VStack(alignment:.leading,spacing:5) { Text(workspace.login).font(.title3.bold()); DemoCaption() }
                }.padding(.vertical,8)
            }
            Section("Sana göre") {
                NavigationLink("Kayıtlı hesaplar") { AccountManagerView() }.accessibilityIdentifier("savedAccounts")
                Button { appearanceShown = true } label: { Label("Kişiselleştir",systemImage:"slider.horizontal.3") }.accessibilityIdentifier("profileAppearance")
                NavigationLink { PrivacySettingsView() } label: { Label("Gizlilik ve kilit",systemImage:"lock.shield") }.accessibilityIdentifier("privacySettings")
                NavigationLink { SigningRenewalView() } label: { Label("Kurulum süresi",systemImage:"calendar.badge.clock") }.accessibilityIdentifier("signingSettings")
                Button { connectionShown = true } label: { Label(workspace.live ? "Bağlantıyı yönet" : "Gitea’ya bağlan",systemImage:"link") }.accessibilityIdentifier("connectButton")
            }
            Section("Çevrimdışı") {
                if let saved = workspace.savedIdentity {
                    Text(saved.origin.host ?? "Sunucu").font(.subheadline)
                    Text(saved.login).font(.caption).foregroundStyle(.secondary)
                    Button("Saklanmış kaydı aç") { do { try workspace.openOffline() } catch { self.error = error.localizedDescription } }
                    Button("Çevrimdışı kayıtları temizle",role:.destructive) { do { try workspace.clearCache() } catch { self.error = error.localizedDescription } }
                } else { Text("Bağlanıp okuduğun ekranlar, son alınma zamanı ile bu cihazda saklanır.").font(.footnote) }
                if workspace.offlineOnly {
                    Button("Canlı bağlantıya geç") { Task { do { try await workspace.reconnect() } catch { self.error = error.localizedDescription } } }.disabled(workspace.busy).accessibilityIdentifier("reconnectLive")
                }
                if let note = workspace.cacheNotice { Text(note).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Bu sürüm") {
                Text("SwiftUI · iOS Liquid Glass").font(.subheadline)
                Text("Kişisel iş kuyruğunu ve değişiklikleri izle. Fikirlerini konuya dönüştür, konuşmalara katıl. Gönderimler yalnız açık hareketinle yapılır; gerçek merge yoktur.").font(.footnote).foregroundStyle(.secondary)
            }
            if workspace.live {
                Section {
                    Button("Örnek ekranlara dön") { workspace.useDemo() }
                    NavigationLink("Hesapları yönet veya kaldır") { AccountManagerView() }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.scrollContentBackground(.hidden).background(Color.canvas).navigationTitle("Profil")
            .toolbar { Button("Yeni fikir",systemImage:"plus") { ideaShown = true } }
            .sheet(isPresented:$ideaShown) { IdeaSheet() }
            .sheet(isPresented:$appearanceShown) { AppearanceSheet() }
            .sheet(isPresented:$connectionShown) { ConnectionSheet() }
    }
}
struct ConnectionSheet: View {
    @EnvironmentObject var workspace: Workspace
    @Environment(\.dismiss) var dismiss
    @State private var server = ""
    @State private var token = ""
    @State private var error: String?
    @State private var task: Task<Void,Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("Sunucun") {
                    TextField("https://git.example.com",text:$server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("serverField")
                    SecureField("Erişim anahtarı",text:$token).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("tokenField")
                    Button("Kayıtlı anahtarı kullan") {
                        do {
                            let origin = try GiteaClient.validatedOrigin(server)
                            if let selected = workspace.identity ?? workspace.savedIdentity,selected.origin == origin,let value = try (TokenVault.load(account:selected.credentialKey) ?? TokenVault.load(account:origin.absoluteString)) { token = value; error = nil }
                            else { error = "Bu sunucudaki hesap için kayıtlı anahtar yok. Anahtarını yeniden gir." }
                        } catch { self.error = error.localizedDescription }
                    }
                }
                Section {
                    if let origin = try? GiteaClient.validatedOrigin(server) {
                        Link("Erişim anahtarı oluştur",destination:origin.appending(path:"user/settings/applications")).accessibilityIdentifier("createAccessToken")
                    }
                    Text("Gitea’da anahtara Gitea Mobile adını verebilirsin. user ve repository için Okuma; issue için Okuma ve yazma seç. notification için Okuma yeterli; bildirimleri okundu işaretlemek istersen Okuma ve yazma seç. Yalnız görüntülemek istersen issue için de Okuma yeterli. Özel depoların için erişimi yalnız herkese açık depolarla sınırlama.").font(.footnote).foregroundStyle(.secondary)
                    Text("Anahtar yalnız oluşturulurken gösterilir. Kopyalayıp yukarıya yapıştır. Bu cihazın Keychain’inde saklanır ve yalnız girdiğin sunucuya gönderilir. Yönetici veya depo yazma izni gerekmez.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("connectionError") } }
                Section {
                    Button {
                        error = nil
                        task = Task {
                            do { try await workspace.connect(server:server,token:token); if !Task.isCancelled { token = ""; dismiss() } }
                            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                        }
                    } label: { HStack { Text("Bağlan ve projeleri getir"); Spacer(); if workspace.busy { ProgressView() } } }
                    .disabled(workspace.busy || token.isEmpty).accessibilityIdentifier("submitConnection")
                }
            }.navigationTitle("Gitea bağlantısı").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Kapat") { task?.cancel(); dismiss() } } }
        }.onAppear { server = workspace.defaults.string(forKey:"server") ?? "" }.onDisappear { task?.cancel(); token = "" }.interactiveDismissDisabled(workspace.busy)
    }
}
