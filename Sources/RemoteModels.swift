import Foundation
import CryptoKit

struct PRLabel: Codable, Hashable { let name: String }
struct PRBranch: Codable, Hashable { let sha: String }
struct ReviewTeam: Codable, Hashable { let name: String }
struct PRMetadata: Codable, Hashable {
    let number: Int
    let title: String
    let body: String?
    let user: GiteaUser
    let state: String
    let merged: Bool?
    let draft: Bool?
    let mergeable: Bool?
    let head: PRBranch
    let base: PRBranch
    let updated_at: String
    let assignees: [GiteaUser]?
    let requested_reviewers: [GiteaUser]?
    let requested_reviewers_teams: [ReviewTeam]?
    var labels: [PRLabel]? = nil
    var fingerprint: String { [head.sha,base.sha,updated_at,state,String(merged ?? false)].joined(separator:"|") }
}
struct PRReview: Codable, Identifiable, Hashable {
    let id: Int
    let user: GiteaUser?
    let state: String
    let body: String?
    let commit_id: String?
    let stale: Bool?
    let dismissed: Bool?
    let official: Bool?
    let submitted_at: String?
    var label: String {
        switch state.uppercased() { case "APPROVED": return "Onay"; case "REQUEST_CHANGES": return "Düzeltme istendi"; case "COMMENT": return "Görüş"; case "PENDING": return "Taslak inceleme"; default:return state }
    }
    func isCurrent(_ head: String) -> Bool { stale == false && dismissed == false && commit_id == head }
}
struct PRStatus: Codable, Identifiable, Hashable {
    let id: Int
    let context: String
    let status: String
    let description: String?
    var label: String {
        switch status { case "success":return "Geçti";case "pending":return "Sürüyor";case "failure","error":return "Başarısız";default:return "Bilinmiyor (\(status))" }
    }
}
struct PRSnapshot: Codable {
    let metadata: PRMetadata
    let reviews: [PRReview]
    let statuses: [PRStatus]
    let fetchedAt: Date
    var observedBaseChange: Bool? = nil
    var latestStatuses: [PRStatus] {
        Dictionary(grouping:statuses,by:{$0.context}).compactMap { $0.value.max(by:{$0.id < $1.id}) }.sorted { $0.context < $1.context }
    }
    var requested: [String] { (metadata.requested_reviewers ?? []).map(\.login) + (metadata.requested_reviewers_teams ?? []).map { "\($0.name) ekibi" } }
    var assignees: [String] { (metadata.assignees ?? []).map(\.login) }
    var nextActor: String {
        if metadata.merged == true { return "Birleştirilmiş" }
        if metadata.state == "closed" { return "Kapatılmış" }
        if metadata.draft == true { return "Taslak PR" }
        if !requested.isEmpty { return requested.joined(separator:", ") }
        if !assignees.isEmpty { return assignees.joined(separator:", ") }
        return "Sorumlu belirtilmemiş"
    }
    func actionTitle(for login: String) -> String {
        if metadata.merged == true || metadata.state == "closed" || metadata.draft == true { return nextActor }
        if !requested.isEmpty {
            if (metadata.requested_reviewers ?? []).contains(where: { $0.login.caseInsensitiveCompare(login) == .orderedSame }) { return "İnceleme senden bekleniyor" }
            return "İnceleme bekleniyor: " + requested.joined(separator:", ")
        }
        if !assignees.isEmpty { return assignees.count == 1 && assignees[0].caseInsensitiveCompare(login) == .orderedSame ? "İş sana atanmış" : "İş atanmış" }
        return "Sonraki adım belirtilmemiş"
    }
    var reason: String {
        if metadata.merged == true || metadata.state == "closed" { return "Kaynak: Gitea PR durumu." }
        if metadata.draft == true { return "Kaynak: Gitea taslak işareti. Henüz incelemeye hazır olduğu varsayılmaz." }
        if !requested.isEmpty { return "Kaynak: Gitea’daki açık inceleme istekleri. Görev atamasıyla aynı şey değildir." }
        if !assignees.isEmpty { return "Kaynak: Gitea görev ataması. Sıradaki eylemin ne olduğu ayrıca belirtilmemiş." }
        return "Açık inceleme isteği veya görev ataması yok. PR yazarından sorumlu tahmin edilmedi."
    }
}
struct ChangedFile: Codable, Identifiable {
    let filename: String
    let previous_filename: String?
    let status: String
    let additions: Int
    let deletions: Int
    var id: String { filename }
}
struct FileSnapshot: Codable {
    let files: [ChangedFile]
    let diff: String
    let head: String
    let base: String
    let fetchedAt: Date
}
struct NotificationSubject: Codable {
    let title: String
    let type: String
    let html_url: String?
}
struct NotificationThread: Codable, Identifiable {
    let id: Int
    let unread: Bool
    let updated_at: String
    let subject: NotificationSubject
    let repository: GiteaRepository
    var typeLabel: String {
        switch subject.type.lowercased() { case "pull":return "PR";case "issue":return "Konu";case "commit":return "Commit";case "repository":return "Depo";default:return "Bildirim" }
    }
    func nativePull(origin: URL) -> PullRequest? {
        guard subject.type.lowercased() == "pull",let url = GiteaClient.safeLink(subject.html_url,origin:origin),url.query == nil else { return nil }
        let parts = url.path.split(separator:"/",omittingEmptySubsequences:false)
        let repo = repository.full_name.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count == 5,parts[0].isEmpty,repo.count == 2,parts[1] == repo[0],parts[2] == repo[1],parts[3] == "pulls",
              !parts[4].isEmpty,parts[4].allSatisfy({ $0.isASCII && $0.isNumber }),let number = Int(parts[4]),number > 0 else { return nil }
        return PullRequest(id:number,title:subject.title,project:repository.project(index:0),author:"",body:"",isDemo:false,url:url)
    }
    func nativeIssue(origin: URL) -> Int? {
        guard subject.type.lowercased() == "issue",let url = GiteaClient.safeLink(subject.html_url,origin:origin),url.query == nil else { return nil }
        let parts = url.path.split(separator:"/",omittingEmptySubsequences:false)
        let repo = repository.full_name.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count == 5,parts[0].isEmpty,repo.count == 2,parts[1] == repo[0],parts[2] == repo[1],parts[3] == "issues",!parts[4].isEmpty,parts[4].allSatisfy({ $0.isASCII && $0.isNumber }),let number = Int(parts[4]),number > 0 else { return nil }
        return number
    }
    var readKey: String { "\(id)|\(updated_at)" }
}
struct InboxSnapshot: Codable { let threads: [NotificationThread]; let fetchedAt: Date }
struct ConnectionIdentity: Codable, Equatable {
    let origin: URL
    let login: String
    var credentialKey: String { "v2|" + scope }
    var scope: String { origin.absoluteString + "|" + login.lowercased() }
}
/// Device-protected, account-scoped snapshots. No credentials, no HTTP cache, no background requests.
struct SnapshotStore {
    let root: URL
    init(root: URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ReadCache")) { self.root = root }
    func digest(_ value: String) -> String { SHA256.hash(data:Data(value.utf8)).map { String(format:"%02x",$0) }.joined() }
    func folder(_ identity: ConnectionIdentity) -> URL { root.appendingPathComponent(digest(identity.scope)) }
    func url(_ key: String,_ identity: ConnectionIdentity) -> URL { folder(identity).appendingPathComponent(digest(key)+".json") }
    func save<T: Encodable>(_ value: T,key: String,identity: ConnectionIdentity) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 6_000_000 else { throw ClientError.message("Bu kayıt çevrimdışı saklamak için fazla büyük.") }
        let fm = FileManager.default,dir = folder(identity)
        try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        var backup = dir; var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try backup.setResourceValues(flags)
        try data.write(to:url(key,identity),options:[.atomic,.completeFileProtection])
        // Keep catalog and comparison metadata plus at most 24 recently saved content records.
        let entries = try fm.contentsOfDirectory(at:dir,includingPropertiesForKeys:[.contentModificationDateKey])
            .filter { !["catalog","today-observations-v1"].map { digest($0)+".json" }.contains($0.lastPathComponent) }
            .sorted { (try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast > (try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        for old in entries.dropFirst(24) { try fm.removeItem(at:old) }
    }
    func load<T: Decodable>(_ type: T.Type,key: String,identity: ConnectionIdentity) throws -> T? {
        let file = url(key,identity)
        guard FileManager.default.fileExists(atPath:file.path) else { return nil }
        return try JSONDecoder().decode(type,from:Data(contentsOf:file))
    }
    func remove(_ identity: ConnectionIdentity) throws {
        let path = folder(identity)
        if FileManager.default.fileExists(atPath:path.path) { try FileManager.default.removeItem(at:path) }
    }
}
struct CatalogSnapshot: Codable { let projects: [Project]; let fetchedAt: Date }
struct PullListSnapshot: Codable { let pulls: [PullRequest]; let fetchedAt: Date }
struct ReadResult<Value> {
    let value: Value
    let cached: Bool
    let note: String?
}
