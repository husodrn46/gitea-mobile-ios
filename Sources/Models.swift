import SwiftUI

struct Project: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let fullName: String
    let summary: String
    let mark: Int
    let language: String
    let issues: Int
    let isPrivate: Bool
    static let samples: [Project] = [
        .init(id:1,name:"Görev Takibi",fullName:"ornek/gorev-takibi",summary:"Sipariş ve iş takibi",mark:4,language:"PHP",issues:12,isPrivate:true),
        .init(id:2,name:"Kişisel Site",fullName:"ornek/kisisel-site",summary:"İnternette bana ait bir köşe",mark:0,language:"TypeScript",issues:4,isPrivate:false),
        .init(id:3,name:"Not Defteri",fullName:"ornek/not-defteri",summary:"Aklıma gelenler, bir arada",mark:5,language:"Swift",issues:6,isPrivate:true),
        .init(id:4,name:"Ev Otomasyonu",fullName:"ornek/ev-otomasyonu",summary:"Küçük şeyler kendiliğinden olsun",mark:2,language:"Python",issues:3,isPrivate:true)
    ]
}
struct PullRequest: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    let project: Project
    let author: String
    let body: String
    let isDemo: Bool
    var checksPassed: Bool = false
    var approved: Bool = false
    var url: URL? = nil
    static var samples: [PullRequest] { [
        .init(id:179,title:"Testler kendiliğinden çalışsın",project:Project.samples[0],author:"Codex",body:"Her değişiklik ayrı bir test ortamında kontrol ediliyor. Testler bitince geçici kaynaklar temizleniyor.",isDemo:true,checksPassed:true,approved:true),
        .init(id:12,title:"Yeni ana sayfaya bir göz at",project:Project.samples[1],author:"Claude",body:"Proje kartları sadeleşti. Mobil ekranda gezinmek artık daha kolay.",isDemo:true,checksPassed:true,approved:false)
    ] }
}
extension PullRequest {
    var nextActor: String { isDemo ? (approved ? "Senin kararın" : "Senin incelemen") : "Henüz bilinmiyor" }
    var nextReason: String {
        guard isDemo else { return "Güncel incelemeler ve görev ataması henüz alınmadı. PR yazarından sorumlu kişi çıkarılmadı." }
        return approved ? "Örnek senaryoda testler ve inceleme tamam. Son kararı sen veriyorsun." : "Örnek senaryoda testler geçti; tasarıma bakıp görüşünü vermen bekleniyor."
    }
    var impact: String { isDemo ? (id == 179 ? "Yeni değişikliklerin test sonucu PR üzerinde görünür." : "Mobilde proje kartlarını bulmak ve açmak kolaylaşır.") : "Etki ayrıca doğrulanmadı. Aşağıdaki PR açıklamasını incele." }
    var missing: String { isDemo ? (approved ? "Son kararın; bu örnekten gerçek merge yapılamaz." : "Senin incelemen ve son kararın.") : "Güncel test, onay ve birleşebilirlik bilgileri." }
}
struct DraftIdea: Identifiable, Codable {
    var id = UUID()
    var title: String
    var text: String
    var project: String
    var date = Date()
    var problem: String? = nil
    var acceptance: String? = nil
    var markdown: String {
        "# \(title)\n\nProje: \(project)\n\n## Fikir\n\(text)\n\n## Hangi sorunu çözer?\n\(problem ?? "")\n\n## Ne zaman tamam?\n\(acceptance ?? "")"
    }
}
@MainActor final class Workspace: ObservableObject {
    @Published var projects = Project.samples
    @Published var pulls = PullRequest.samples
    @Published var live = false
    @Published var offlineOnly = false
    @Published var identity: ConnectionIdentity?
    @Published var cacheNotice: String?
    let cache: SnapshotStore
    let draftRoot: URL
    @Published var accounts: [ConnectionIdentity] = []
    @Published var deviceDrafts: [DraftIdea] = []
    var accountRevision = UUID()
    func isCurrent(_ selected: ConnectionIdentity, revision: UUID) -> Bool { identity == selected && accountRevision == revision }
    let defaults: UserDefaults
    @Published var hasChosenMode: Bool
    var requiresOnboarding: Bool { !hasChosenMode && !isFixture }
    func chooseDemo() { useDemo() }
    var savedIdentity: ConnectionIdentity? {
        guard let data = defaults.data(forKey:"lastReadIdentity") else { return nil }
        return try? JSONDecoder().decode(ConnectionIdentity.self,from:data)
    }
    func credentials() throws -> (ConnectionIdentity,String) {
        guard let identity,live else { throw ClientError.message("Önce sunucuya bağlan.") }
        #if DEBUG
        if isFixture { return (identity,"synthetic-only") }
        #endif
        guard let token = try TokenVault.load(account:identity.credentialKey) else { throw ClientError.message("Kayıtlı anahtar yok. Yeniden bağlan.") }
        return (identity,token)
    }
    func openOffline() throws {
        guard let stored = savedIdentity,let catalog = try cache.load(CatalogSnapshot.self,key:"catalog",identity:stored) else { throw ClientError.message("Bu cihazda saklanmış bir sunucu kaydı yok.") }
        generation = UUID(); accountRevision = UUID(); busy = false; identity = stored; login = stored.login
        favorites = Set(defaults.stringArray(forKey:"favorites." + stored.scope) ?? [])
        projects = catalog.projects; pulls = []; live = true; offlineOnly = true
        cacheNotice = "Çevrimdışı kayıt · " + catalog.fetchedAt.formatted(date:.abbreviated,time:.shortened)
        hasChosenMode = true; defaults.set(true,forKey:"onboarding.v1.completed"); defaults.set("connected",forKey:"workspace.mode")
        loadDrafts()
    }
    func clearCache() throws {
        if let stored = identity ?? savedIdentity { try cache.remove(stored) }
        defaults.removeObject(forKey:"lastReadIdentity")
        cacheNotice = nil
        if offlineOnly { useDemo() }
    }
    func resource<T: Codable>(_ type: T.Type,key: String,fetch: (URL,String) async throws -> T) async throws -> ReadResult<T> {
        guard let selected = identity else { throw ClientError.message("Önce sunucuya bağlan.") }
        try Task.checkCancellation()
        let version = generation; let readVersion = UUID(); resourceVersions[key] = readVersion
        if offlineOnly {
            guard let value = try cache.load(type,key:key,identity:selected) else { throw ClientError.message("Bu ekran daha önce kaydedilmemiş. İnternet bağlantısıyla bir kez aç.") }
            return ReadResult(value:value,cached:true,note:"Çevrimdışı kayıt; güncel olmayabilir.")
        }
        do {
            let (_,token) = try credentials()
            let value = try await fetch(selected.origin,token)
            try Task.checkCancellation()
            guard generation == version,identity == selected,resourceVersions[key] == readVersion else { throw CancellationError() }
            var note: String?
            do { try cache.save(value,key:key,identity:selected) }
            catch { note = "Veri güncel; cihazdaki kopya kaydedilemedi." }
            return ReadResult(value:value,cached:false,note:note)
        } catch {
            guard !Task.isCancelled,!(error is CancellationError),generation == version,identity == selected,resourceVersions[key] == readVersion else { throw CancellationError() }
            if let saved = try? cache.load(type,key:key,identity:selected) {
                return ReadResult(value:saved,cached:true,note:"Yenileme başarısız: \(error.localizedDescription) Saklanmış kayıt gösteriliyor.")
            }
            throw error
        }
    }
    func loadSnapshot(_ pull: PullRequest) async throws -> ReadResult<PRSnapshot> {
        let key = "pr|\(pull.project.fullName)|\(pull.id)"
        let previous = identity.flatMap { try? cache.load(PRSnapshot.self,key:key,identity:$0) }
        return try await resource(PRSnapshot.self,key:key) { origin,token in
            var snapshot = try await self.client.snapshot(pull,origin:origin,token:token)
            snapshot.observedBaseChange = previous?.observedBaseChange == true || (previous != nil && previous?.metadata.base.sha != snapshot.metadata.base.sha)
            return snapshot
        }
    }
    func loadFiles(_ pull: PullRequest) async throws -> ReadResult<FileSnapshot> {
        try await resource(FileSnapshot.self,key:"diff|\(pull.project.fullName)|\(pull.id)") { origin,token in try await self.client.files(pull,origin:origin,token:token) }
    }
    func loadInbox() async throws -> ReadResult<InboxSnapshot> {
        try await resource(InboxSnapshot.self,key:"inbox") { origin,token in try await self.client.notifications(origin:origin,token:token) }
    }
    func loadPullList(_ project: Project) async throws -> ReadResult<PullListSnapshot> {
        try await resource(PullListSnapshot.self,key:"pulls|\(project.fullName)") { origin,token in
            try await self.client.pullPage(project:project,origin:origin,token:token)
        }
    }
    /// A failed page never replaces the already verified list or advances its cursor.
    func loadMorePulls(_ project: Project,previous: PullListSnapshot,previousCached: Bool = false) async throws -> ReadResult<PullListSnapshot> {
        guard !offlineOnly,previous.hasMore else { throw ClientError.message("Sonraki sayfa için canlı bağlantı gerekli.") }
        let (selected,token) = try credentials(); let revision = accountRevision; let version = generation
        let key = "pulls|\(project.fullName)"; let readVersion = UUID(); resourceVersions[key] = readVersion
        let page = try await client.pullPage(project:project,origin:selected.origin,token:token,page:previous.nextPage)
        try Task.checkCancellation()
        guard generation == version,isCurrent(selected,revision:revision),resourceVersions[key] == readVersion,!offlineOnly else { throw CancellationError() }
        let merged = previous.appending(page)
        var note: String? = previousCached ? "Önceki sayfalar saklanmış kayıttan; en eski alınma zamanı korunuyor." : nil
        do { try cache.save(merged,key:"pulls|\(project.fullName)",identity:selected) } catch { note = "Yeni sayfa alındı; cihazdaki kopya kaydedilemedi." }
        return ReadResult(value:merged,cached:previousCached,note:note)
    }
    @Published var login = "Demo"
    @Published var busy = false
    @Published var error: String?
    @Published var draftError: String?
    @Published var drafts: [DraftIdea] = []
    @Published var readActivities: Set<Int> = []
    @Published var favorites: Set<String> = [] {
        didSet { defaults.set(Array(favorites),forKey:"favorites." + (identity?.scope ?? "demo")) }
    }
    private var generation = UUID()
    private var resourceVersions: [String:UUID] = [:]
    let client: GiteaClient
    var isFixture = false
    init(defaults: UserDefaults? = nil, client: GiteaClient? = nil, cache: SnapshotStore = SnapshotStore(), draftRoot: URL? = nil) {
        let defaults = defaults ?? Appearance.appDefaults
        self.defaults = defaults
        self.cache = cache; self.draftRoot = draftRoot ?? Self.draftURL.deletingLastPathComponent()
        accounts = (defaults.data(forKey:"accounts.v1").flatMap { try? JSONDecoder().decode([ConnectionIdentity].self,from:$0) }) ?? []
        hasChosenMode = defaults.bool(forKey:"onboarding.v1.completed")
        #if DEBUG
        isFixture = ProcessInfo.processInfo.arguments.contains("--fixture-gitea")
        self.client = client ?? GiteaClient(protocolClasses:isFixture ? [RemoteFixtureProtocol.self] : nil)
        #else
        self.client = client ?? GiteaClient()
        #endif
        if let old = savedIdentity, !accounts.contains(where: { $0.scope == old.scope }) { accounts.append(old); persistAccounts() }
        favorites = Set(defaults.stringArray(forKey:"favorites.demo") ?? [Project.samples[0].fullName])
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-gitea"),ProcessInfo.processInfo.environment["GITEA_TEST_PREFERENCES"]?.hasPrefix("test.") == true { hasChosenMode = true }
        #endif
        #if DEBUG
        if isFixture {
            let selected = ConnectionIdentity(origin:URL(string:"https://fixture.invalid")!,login:"reviewer")
            identity = selected; login = "Örnek API"; live = true
            if ProcessInfo.processInfo.arguments.contains("--fixture-reset-history") {
                try? FileManager.default.removeItem(at:cache.url("today-observations-v1",selected))
            }
            offlineOnly = ProcessInfo.processInfo.arguments.contains("--fixture-offline")
            projects = [Project(id:1,name:"Mobil",fullName:"ornek/mobile",summary:"Test deposu",mark:4,language:"Swift",issues:1,isPrivate:true)]
            pulls = []
            if ProcessInfo.processInfo.arguments.contains("--fixture-accounts") {
                accounts = [selected,ConnectionIdentity(origin:selected.origin,login:"reader"),ConnectionIdentity(origin:URL(string:"https://second-fixture.invalid")!,login:"reviewer")]
                for account in accounts { try? cache.save(CatalogSnapshot(projects:projects,fetchedAt:Date()),key:"catalog",identity:account) }
            }
        }
        #endif
        if !isFixture, savedIdentity != nil, defaults.string(forKey:"workspace.mode") != "demo" {
            if let stored = savedIdentity, defaults.object(forKey:"favorites." + stored.scope) == nil,let previous = defaults.stringArray(forKey:"favorites") { defaults.set(previous,forKey:"favorites." + stored.scope) }
            if let stored = savedIdentity { try? selectAccount(stored) }; hasChosenMode = live
        }
        loadDrafts()
    }
    func persistAccounts() { if let data = try? JSONEncoder().encode(accounts) { defaults.set(data,forKey:"accounts.v1") } }
    var activeDraftURL: URL {
        guard let identity else { return draftRoot.appendingPathComponent("ideas.json") }
        return draftRoot.appendingPathComponent("AccountIdeas").appendingPathComponent(cache.digest(identity.scope) + ".json")
    }
    func loadDrafts() {
        drafts = []; deviceDrafts = []; draftError = nil
        do {
            let legacy = draftRoot.appendingPathComponent("ideas.json")
            if FileManager.default.fileExists(atPath:legacy.path) { deviceDrafts = try JSONDecoder().decode([DraftIdea].self,from:Data(contentsOf:legacy)) }
            if identity == nil { drafts = deviceDrafts }
            else if FileManager.default.fileExists(atPath:activeDraftURL.path) { drafts = try JSONDecoder().decode([DraftIdea].self,from:Data(contentsOf:activeDraftURL)) }
        } catch { draftError = "Kaydedilmiş taslaklar okunamadı. Dosya korunuyor; üzerine yazılmayacak." }
    }
    /// Explicit copy; the original device library remains intact.
    func copyDeviceDraftsToAccount() throws {
        guard identity != nil else { throw ClientError.message("Önce bir hesap seç.") }
        for draft in deviceDrafts where !drafts.contains(where: { $0.id == draft.id }) { try save(draft) }
    }
    func selectAccount(_ selected: ConnectionIdentity) throws {
        guard accounts.contains(where: { $0.scope == selected.scope }) else { throw ClientError.message("Hesap kayıtlı değil.") }
        let catalog = try? cache.load(CatalogSnapshot.self,key:"catalog",identity:selected)
        generation = UUID(); accountRevision = UUID(); busy = false
        identity = selected; login = selected.login; live = true; offlineOnly = true
        projects = catalog?.projects ?? []; pulls = []
        favorites = Set(defaults.stringArray(forKey:"favorites." + selected.scope) ?? [])
        cacheNotice = catalog.map { "Çevrimdışı kayıt · " + $0.fetchedAt.formatted(date:.abbreviated,time:.shortened) } ?? "Bu hesabın çevrimdışı proje kaydı yok. Canlı bağlantıya geç."
        defaults.set(try JSONEncoder().encode(selected),forKey:"lastReadIdentity")
        hasChosenMode = true; defaults.set(true,forKey:"onboarding.v1.completed"); defaults.set("connected",forKey:"workspace.mode")
        loadDrafts()
    }
    func reconnect(_ selected: ConnectionIdentity? = nil) async throws {
        guard let expected = selected ?? identity ?? savedIdentity else { throw ClientError.message("Kayıtlı hesap yok.") }
        guard let token = try TokenVault.load(account:expected.credentialKey) else { throw ClientError.message("Kayıtlı anahtar yok. Bağlantıyı yönet bölümünden yeniden giriş yap.") }
        try await connect(server:expected.origin.absoluteString,token:token,expected:expected)
    }
    func removeAccount(_ selected: ConnectionIdentity) throws {
        try TokenVault.delete(account:selected.credentialKey)
        try cache.remove(selected)
        let file = draftRoot.appendingPathComponent("AccountIdeas").appendingPathComponent(cache.digest(selected.scope) + ".json")
        if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
        defaults.removeObject(forKey:"favorites." + selected.scope)
        accounts.removeAll { $0.scope == selected.scope }; persistAccounts()
        if savedIdentity?.scope == selected.scope { defaults.removeObject(forKey:"lastReadIdentity") }
        if identity?.scope == selected.scope { useDemo() }
    }

    static var draftURL: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ideas.json") }
    func save(_ draft: DraftIdea) throws {
        guard draftError == nil else { throw ClientError.message(draftError!) }
        let next = drafts.contains(where: { $0.id == draft.id }) ? drafts.map { $0.id == draft.id ? draft : $0 } : [draft] + drafts
        try FileManager.default.createDirectory(at:activeDraftURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(next).write(to:activeDraftURL,options:[.atomic,.completeFileProtection])
        drafts = next
        if identity == nil { deviceDrafts = next }
    }
    func toggleFavorite(_ project: Project) {
        if favorites.contains(project.fullName) { favorites.remove(project.fullName) } else { favorites.insert(project.fullName) }
    }
    func connect(server: String, token: String, expected: ConnectionIdentity? = nil) async throws {
        guard !busy else { throw ClientError.message("Bir bağlantı isteği zaten sürüyor.") }
        let requestID = UUID(); generation = requestID; accountRevision = UUID()
        busy = true; defer { if generation == requestID { busy = false } }
        let origin = try GiteaClient.validatedOrigin(server)
        let credential = token.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !credential.isEmpty else { throw ClientError.message("Erişim anahtarını gir.") }
        let user = try await client.user(origin:origin,token:credential)
        try Task.checkCancellation()
        guard generation == requestID else { throw CancellationError() }
        if let expected, user.login.caseInsensitiveCompare(expected.login) != .orderedSame {
            throw ClientError.message("Anahtar kayıtlı hesapla eşleşmiyor. Hesap verileri değiştirilmedi; bağlantıyı yönet bölümünden yeniden giriş yap.")
        }
        let repos = try await client.repositories(origin:origin,token:credential)
        try Task.checkCancellation()
        guard generation == requestID else { throw CancellationError() }
        let connected = ConnectionIdentity(origin:origin,login:user.login)
        try TokenVault.save(credential,account:connected.credentialKey)
        defaults.set(origin.absoluteString,forKey:"server")
        projects = repos.enumerated().map { idx,repo in repo.project(index:idx) }
        accountRevision = UUID(); identity = connected; offlineOnly = false; cacheNotice = nil
        defaults.set(try JSONEncoder().encode(connected),forKey:"lastReadIdentity")
        do {
            try cache.save(CatalogSnapshot(projects:projects,fetchedAt:Date()),key:"catalog",identity:connected)
        } catch { cacheNotice = "Bağlandın; çevrimdışı kopya kaydedilemedi." }
        favorites = Set(defaults.stringArray(forKey:"favorites." + connected.scope) ?? [])
        pulls = []; login = user.login; live = true; error = nil
        hasChosenMode = true; defaults.set(true,forKey:"onboarding.v1.completed"); defaults.set("connected",forKey:"workspace.mode")
        accounts.removeAll { $0.scope == connected.scope }; accounts.append(connected); persistAccounts(); loadDrafts()
    }
    func useDemo() {
        generation = UUID(); accountRevision = UUID(); busy = false
        identity = nil; offlineOnly = false; cacheNotice = nil
        favorites = Set(defaults.stringArray(forKey:"favorites.demo") ?? [Project.samples[0].fullName])
        hasChosenMode = true; defaults.set(true,forKey:"onboarding.v1.completed")
        defaults.set("demo",forKey:"workspace.mode")
        live = false; login = "Demo"; projects = Project.samples; pulls = PullRequest.samples; error = nil
        loadDrafts()
    }
    func loadPulls(_ project: Project) async throws -> [PullRequest] {
        guard live else { return pulls.filter { $0.project.id == project.id } }
        return try await loadPullList(project).value.pulls
    }
    func disconnect() throws {
        if let selected = identity ?? savedIdentity { try removeAccount(selected) }
    }
}
