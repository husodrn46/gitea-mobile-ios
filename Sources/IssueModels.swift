import Foundation
import CryptoKit

struct IssueLabel: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let color: String?
}
struct GiteaIssue: Codable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let user: GiteaUser?
    let labels: [IssueLabel]?
    let assignees: [GiteaUser]?
    let html_url: String?
    let updated_at: String?
    let pull_request: IssuePullMarker?
}
struct IssuePullMarker: Codable { let html_url: String? }
struct IssueComment: Codable, Identifiable {
    let id: Int
    let body: String
    let user: GiteaUser?
    let html_url: String?
    let created_at: String?
}
struct IssueListSnapshot: Codable { let issues: [GiteaIssue]; let fetchedAt: Date }
struct IssueDetailSnapshot: Codable { let issue: GiteaIssue; let comments: [IssueComment]; let fetchedAt: Date }
struct IssueOptions: Codable {
    let labels: [IssueLabel]
    let assignees: [GiteaUser]
    let canManage: Bool
    let note: String?
}
struct IssueRepositoryPermissions: Decodable {
    struct Permissions: Decodable { let admin: Bool?; let push: Bool? }
    let permissions: Permissions?
}
struct CreateIssueBody: Encodable {
    let title: String
    let body: String
    let labels: [Int]?
    let assignees: [String]?
}
struct CommentBody: Encodable { let body: String }
struct EditIssuePeopleBody: Encodable { let assignees: [String] }
struct EditIssueLabelsBody: Encodable { let labels: [Int] }

/// Persist before dispatch. An ambiguous response never causes an automatic retry.
/// Successful issue creation is also retained, so reopening a draft cannot duplicate it.
@MainActor final class IssueWriteLedger {
    static let shared = IssueWriteLedger()
    struct Receipt: Codable { var state: String; var number: Int?; var date: Date }
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func key(identity: ConnectionIdentity, operation: String) -> String {
        "issueWrite." + SHA256.hash(data:Data((identity.scope + "|" + operation).utf8)).map { String(format:"%02x",$0) }.joined()
    }
    func receipt(identity: ConnectionIdentity, operation: String) -> Receipt? {
        guard let bytes = defaults.data(forKey:key(identity:identity,operation:operation)) else { return nil }
        // Corruption must fail closed rather than permit a duplicate.
        return (try? JSONDecoder().decode(Receipt.self,from:bytes)) ?? Receipt(state:"uncertain",number:nil,date:Date())
    }
    func begin(identity: ConnectionIdentity, operation: String) throws {
        guard receipt(identity:identity,operation:operation) == nil else { throw ClientError.message("Bu gönderim daha önce başlatılmış. Yinelenmesini önlemek için durduruldu. Konuyu Gitea’da kontrol et.") }
        try record(Receipt(state:"uncertain",number:nil,date:Date()),identity:identity,operation:operation)
        // Force a durable preference flush before any network dispatch.
        guard defaults.synchronize() else { throw ClientError.message("Gönderim kaydı cihazda saklanamadı; istek gönderilmedi.") }
    }
    func record(_ receipt: Receipt,identity: ConnectionIdentity,operation: String) throws {
        defaults.set(try JSONEncoder().encode(receipt),forKey:key(identity:identity,operation:operation))
    }
    func refused(identity: ConnectionIdentity,operation: String) { defaults.removeObject(forKey:key(identity:identity,operation:operation)); defaults.synchronize() }
    static func commentOperation(project: Project,number: Int,attempt: UUID) -> String {
        "comment|\(project.fullName)|\(number)|\(attempt.uuidString)"
    }
}

struct IssueCommentDraft: Codable {
    var attempt = UUID()
    var text = ""
    @MainActor static func load(key: String,defaults: UserDefaults = .standard) throws -> Self {
        if let data = defaults.data(forKey:key) { return try JSONDecoder().decode(Self.self,from:data) }
        return Self(text:defaults.string(forKey:key) ?? "")
    }
    @MainActor func save(key: String,defaults: UserDefaults = .standard,flush: Bool = false) throws {
        defaults.set(try JSONEncoder().encode(self),forKey:key)
        if flush && !defaults.synchronize() { throw ClientError.message("Yorum taslağı kaydedilemedi; istek gönderilmedi.") }
    }
}
struct IssueMetadataBaseline {
    let people: Set<String>
    let labels: Set<Int>
    func validate(_ issue: GiteaIssue) throws {
        guard people == Set((issue.assignees ?? []).map(\.login)),labels == Set((issue.labels ?? []).map(\.id)) else {
            throw ClientError.message("Etiket veya sorumlular başka bir yerde değişti. Üzerine yazılmadı; kapatıp güncel konuyu yeniden aç.")
        }
    }
}
