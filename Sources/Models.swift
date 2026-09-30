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
    let cache = SnapshotStore()
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
        generation = UUID(); busy = false; identity = stored; login = stored.login
        favorites = Set(defaults.stringArray(forKey:"favorites." + stored.scope) ?? [])
        projects = catalog.projects; pulls = []; live = true; offlineOnly = true
        cacheNotice = "Çevrimdışı kayıt · " + catalog.fetchedAt.formatted(date:.abbreviated,time:.shortened)
    }
    func clearCache() throws {
        if let stored = identity ?? savedIdentity { try cache.remove(stored) }
        defaults.removeObject(forKey:"lastReadIdentity")
        cacheNotice = nil
        if offlineOnly { useDemo() }
    }
    func resource<T: Codable>(_ type: T.Type,key: String,fetch: (URL,String) async throws -> T) async throws -> ReadResult<T> {
        guard let selected = identity else { throw ClientError.message("Önce sunucuya bağlan.") }
        let version = generation
        if offlineOnly {
            guard let value = try cache.load(type,key:key,identity:selected) else { throw ClientError.message("Bu ekran daha önce kaydedilmemiş. İnternet bağlantısıyla bir kez aç.") }
            return ReadResult(value:value,cached:true,note:"Çevrimdışı kayıt; güncel olmayabilir.")
        }
        do {
            let (_,token) = try credentials()
            let value = try await fetch(selected.origin,token)
            try Task.checkCancellation()
            guard generation == version,identity == selected else { throw CancellationError() }
            var note: String?
            do { try cache.save(value,key:key,identity:selected) }
            catch { note = "Veri güncel; cihazdaki kopya kaydedilemedi." }
            return ReadResult(value:value,cached:false,note:note)
        } catch {
            guard !Task.isCancelled,generation == version,identity == selected else { throw CancellationError() }
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
            PullListSnapshot(pulls:try await self.client.pulls(project:project,origin:origin,token:token),fetchedAt:Date())
        }
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
    let client: GiteaClient
    var isFixture = false
    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? Appearance.appDefaults
        self.defaults = defaults
        hasChosenMode = defaults.bool(forKey:"onboarding.v1.completed")
        #if DEBUG
        isFixture = ProcessInfo.processInfo.arguments.contains("--fixture-gitea")
        client = GiteaClient(protocolClasses:isFixture ? [RemoteFixtureProtocol.self] : nil)
        #else
        client = GiteaClient()
        #endif
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
        }
        #endif
        if !isFixture, savedIdentity != nil, defaults.string(forKey:"workspace.mode") != "demo" {
            if let stored = savedIdentity, defaults.object(forKey:"favorites." + stored.scope) == nil,let previous = defaults.stringArray(forKey:"favorites") { defaults.set(previous,forKey:"favorites." + stored.scope) }
            try? openOffline(); hasChosenMode = live
        }
        let path = Self.draftURL
        if FileManager.default.fileExists(atPath:path.path) {
            do { drafts = try JSONDecoder().decode([DraftIdea].self,from:Data(contentsOf:path)) }
            catch { draftError = "Kaydedilmiş taslaklar okunamadı. Dosya korunuyor; üzerine yazılmayacak." }
        }
    }
    static var draftURL: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ideas.json") }
    func save(_ draft: DraftIdea) throws {
        guard draftError == nil else { throw ClientError.message(draftError!) }
        let next = drafts.contains(where: { $0.id == draft.id }) ? drafts.map { $0.id == draft.id ? draft : $0 } : [draft] + drafts
        try FileManager.default.createDirectory(at:Self.draftURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(next).write(to:Self.draftURL,options:[.atomic,.completeFileProtection])
        drafts = next
    }
    func toggleFavorite(_ project: Project) {
        if favorites.contains(project.fullName) { favorites.remove(project.fullName) } else { favorites.insert(project.fullName) }
    }
    func connect(server: String, token: String) async throws {
        guard !busy else { throw ClientError.message("Bir bağlantı isteği zaten sürüyor.") }
        let requestID = UUID(); generation = requestID
        busy = true; defer { if generation == requestID { busy = false } }
        let origin = try GiteaClient.validatedOrigin(server)
        let credential = token.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !credential.isEmpty else { throw ClientError.message("Erişim anahtarını gir.") }
        let user = try await client.user(origin:origin,token:credential)
        let repos = try await client.repositories(origin:origin,token:credential)
        try Task.checkCancellation()
        guard generation == requestID else { return }
        let connected = ConnectionIdentity(origin:origin,login:user.login)
        try TokenVault.save(credential,account:connected.credentialKey)
        defaults.set(origin.absoluteString,forKey:"server")
        projects = repos.enumerated().map { idx,repo in repo.project(index:idx) }
        identity = connected; offlineOnly = false; cacheNotice = nil
        do {
            try cache.save(CatalogSnapshot(projects:projects,fetchedAt:Date()),key:"catalog",identity:connected)
            defaults.set(try JSONEncoder().encode(connected),forKey:"lastReadIdentity")
        } catch { cacheNotice = "Bağlandın; çevrimdışı kopya kaydedilemedi." }
        favorites = Set(defaults.stringArray(forKey:"favorites." + connected.scope) ?? [])
        pulls = []; login = user.login; live = true; error = nil
        hasChosenMode = true; defaults.set(true,forKey:"onboarding.v1.completed"); defaults.set("connected",forKey:"workspace.mode")
    }
    func useDemo() {
        generation = UUID(); busy = false
        identity = nil; offlineOnly = false; cacheNotice = nil
        favorites = Set(defaults.stringArray(forKey:"favorites.demo") ?? [Project.samples[0].fullName])
        hasChosenMode = true; defaults.set(true,forKey:"onboarding.v1.completed")
        defaults.set("demo",forKey:"workspace.mode")
        live = false; login = "Demo"; projects = Project.samples; pulls = PullRequest.samples; error = nil
    }
    func loadPulls(_ project: Project) async throws -> [PullRequest] {
        guard live else { return pulls.filter { $0.project.id == project.id } }
        return try await loadPullList(project).value.pulls
    }
    func disconnect() throws {
        if let selected = identity ?? savedIdentity {
            try TokenVault.delete(account:selected.credentialKey)
            try TokenVault.delete(account:selected.origin.absoluteString)
        }
        try clearCache()
        defaults.removeObject(forKey:"server")
        useDemo()
        hasChosenMode = false; defaults.set(false,forKey:"onboarding.v1.completed")
    }
}
