import Foundation
import Security

enum ClientError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct GiteaUser: Codable, Hashable { let login: String }
struct GiteaRepository: Codable {
    let id: Int
    let name: String
    let full_name: String
    let description: String?
    let language: String?
    let open_issues_count: Int?
    let `private`: Bool
    func project(index: Int) -> Project {
        Project(id:id,name:name,fullName:full_name,summary:description?.isEmpty == false ? description! : "Henüz açıklama eklenmemiş",mark:index+4,language:language ?? "",issues:open_issues_count ?? 0,isPrivate:`private`)
    }
}
struct GiteaPull: Decodable {
    let number: Int
    let title: String
    let body: String?
    let html_url: String?
    let user: GiteaUser
}
/// Credentials never follow redirects, including same-host redirects. This transport is GET-only; explicit writes use IssueWriter.
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class GiteaClient: @unchecked Sendable {
    private let session: URLSession
    init(protocolClasses: [AnyClass]? = nil) {
        let config = URLSessionConfiguration.ephemeral
        if let protocolClasses { config.protocolClasses = protocolClasses }
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 45
        config.httpCookieStorage = nil; config.urlCache = nil
        session = URLSession(configuration:config,delegate:NoRedirect(),delegateQueue:nil)
    }
    static func validatedOrigin(_ input: String) throws -> URL {
        guard let components = URLComponents(string:input.trimmingCharacters(in:.whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/", let url = components.url
        else { throw ClientError.message("Sunucunun HTTPS adresini gir; örneğin https://git.example.com. Alt dizinli adresler bu sürümde desteklenmiyor.") }
        return url
    }
    static func repositoryPath(_ fullName: String) throws -> String {
        let parts = fullName.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }) else { throw ClientError.message("Depo adresi okunamadı.") }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-_."))
        guard let owner = String(parts[0]).addingPercentEncoding(withAllowedCharacters:allowed),let name = String(parts[1]).addingPercentEncoding(withAllowedCharacters:allowed) else { throw ClientError.message("Depo adresi okunamadı.") }
        return "/repos/\(owner)/\(name)/pulls"
    }
    func data(_ path: String, query: [URLQueryItem] = [], origin: URL, token: String, accept: String = "application/json") async throws -> Data {
        var parts = URLComponents(url:origin,resolvingAgainstBaseURL:false)!
        parts.path = "/api/v1" + path; parts.queryItems = query.isEmpty ? nil : query
        // repositoryPath returns escaped segments: retain the escaping exactly once.
        parts.percentEncodedPath = "/api/v1" + path
        var request = URLRequest(url:parts.url!)
        request.httpMethod = "GET"
        request.setValue("token " + token,forHTTPHeaderField:"Authorization")
        request.setValue(accept,forHTTPHeaderField:"Accept")
        let (bytes,response) = try await session.bytes(for:request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.message("Sunucudan yanıt alınamadı.") }
        switch http.statusCode {
        case 200: break
        case 401,403: throw ClientError.message("Erişim anahtarı veya okuma izinleri yeterli değil.")
        case 300...399: throw ClientError.message("Sunucu başka bir adrese yönlendiriyor. Doğrudan HTTPS adresini kullan.")
        default: throw ClientError.message("Sunucu isteği tamamlayamadı (\(http.statusCode)).")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 4_194_304 else { throw ClientError.message("Sunucu yanıtı bu ekran için fazla büyük.") }
            data.append(byte)
        }
        return data
    }
    func read<T: Decodable>(_ path: String, query: [URLQueryItem] = [], origin: URL, token: String) async throws -> T {
        let data = try await data(path,query:query,origin:origin,token:token)
        do { return try JSONDecoder().decode(T.self,from:data) }
        catch { throw ClientError.message("Sunucu Gitea biçiminde yanıt vermedi.") }
    }
    static func safeLink(_ value: String?,origin: URL) -> URL? {
        guard let value,let url = URL(string:value),url.scheme == "https",url.host == origin.host,url.port == origin.port,url.user == nil,url.password == nil else { return nil }
        return url
    }
    func pages<T: Decodable>(_ path: String,query: [URLQueryItem] = [],origin: URL,token: String) async throws -> [T] {
        var all: [T] = []
        for page in 1...20 {
            let rows: [T] = try await read(path,query:query + [.init(name:"page",value:String(page)),.init(name:"limit",value:"50")],origin:origin,token:token)
            all += rows
            if rows.count < 50 { return all }
        }
        throw ClientError.message("Liste 1.000 kayıttan büyük; eksik veriyi tamamlanmış saymamak için durduruldu. Gitea’da incele.")
    }
    func snapshot(_ pull: PullRequest,origin: URL,token: String) async throws -> PRSnapshot {
        let path = try Self.repositoryPath(pull.project.fullName) + "/\(pull.id)"
        let before: PRMetadata = try await read(path,origin:origin,token:token)
        guard Self.validSHA(before.head.sha),Self.validSHA(before.base.sha) else { throw ClientError.message("Commit kimliği doğrulanamadı.") }
        let repo = String(try Self.repositoryPath(pull.project.fullName).dropLast(6))
        async let reviews: [PRReview] = pages(path+"/reviews",origin:origin,token:token)
        async let statuses: [PRStatus] = pages(repo+"/commits/\(before.head.sha)/statuses",origin:origin,token:token)
        let result = try await (reviews,statuses)
        let after: PRMetadata = try await read(path,origin:origin,token:token)
        guard before.fingerprint == after.fingerprint else { throw ClientError.message("PR bu sırada değişti. Güncel bilgiyi almak için yenile.") }
        return PRSnapshot(metadata:after,reviews:result.0,statuses:result.1,fetchedAt:Date())
    }
    static func validSHA(_ sha: String) -> Bool { sha.count == 40 && sha.allSatisfy { $0.isHexDigit && $0.isASCII } }
    func files(_ pull: PullRequest,origin: URL,token: String) async throws -> FileSnapshot {
        let path = try Self.repositoryPath(pull.project.fullName) + "/\(pull.id)"
        let before: PRMetadata = try await read(path,origin:origin,token:token)
        let files: [ChangedFile] = try await pages(path+"/files",origin:origin,token:token)
        let bytes = try await data(path+".diff",origin:origin,token:token,accept:"text/plain")
        guard let diff = String(data:bytes,encoding:.utf8), !diff.lowercased().hasPrefix("<!doctype html"),diff.isEmpty || diff.hasPrefix("diff --git ") else { throw ClientError.message("Kod farkı geçerli metin olarak alınamadı. Gitea’da incele.") }
        let after: PRMetadata = try await read(path,origin:origin,token:token)
        guard before.fingerprint == after.fingerprint else { throw ClientError.message("Dosyalar alınırken PR değişti. Yenile.") }
        return FileSnapshot(files:files,diff:diff,head:before.head.sha,base:before.base.sha,fetchedAt:Date())
    }
    func notifications(origin: URL,token: String) async throws -> InboxSnapshot {
        let threads: [NotificationThread] = try await pages("/notifications",query:[.init(name:"all",value:"true")],origin:origin,token:token)
        return InboxSnapshot(threads:threads.sorted { $0.updated_at > $1.updated_at },fetchedAt:Date())
    }
    func user(origin: URL, token: String) async throws -> GiteaUser { try await read("/user",origin:origin,token:token) }
    func repositories(origin: URL,token: String) async throws -> [GiteaRepository] {
        var all: [GiteaRepository] = []
        for page in 1...20 {
            let rows: [GiteaRepository] = try await read("/user/repos",query:[.init(name:"limit",value:"50"),.init(name:"page",value:String(page))],origin:origin,token:token)
            all.append(contentsOf:rows)
            if rows.count < 50 { return all }
        }
        throw ClientError.message("1.000'den fazla depo var; bu sürüm bütün listeyi yükleyemiyor.")
    }
    func pulls(project: Project,origin: URL,token: String) async throws -> [PullRequest] {
        let rows: [GiteaPull] = try await read(Self.repositoryPath(project.fullName),query:[.init(name:"state",value:"open"),.init(name:"limit",value:"50")],origin:origin,token:token)
        return rows.map { row in
            let candidate = row.html_url.flatMap(URL.init(string:))
            let url = candidate?.scheme == "https" && candidate?.host == origin.host && candidate?.port == origin.port && candidate?.user == nil && candidate?.password == nil ? candidate : nil
            return PullRequest(id:row.number,title:row.title,project:project,author:row.user.login,body:row.body ?? "",isDemo:false,url:url)
        }
    }
}
enum TokenVault {
    static let service = "com.husodrn46.kisiselgitea.token"
    static func query(_ account: String) -> [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account] }
    static func save(_ value: String,account: String) throws {
        let q = query(account), data = Data(value.utf8)
        let updated = SecItemUpdate(q as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw ClientError.message("Anahtar güvenli olarak kaydedilemedi.") }
        var add = q; add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(add as CFDictionary,nil) == errSecSuccess else { throw ClientError.message("Anahtar güvenli olarak kaydedilemedi.") }
    }
    static func load(account: String) throws -> String? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary,&item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,let data = item as? Data,let result = String(data:data,encoding:.utf8) else { throw ClientError.message("Kaydedilmiş anahtar okunamadı.") }
        return result
    }
    static func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClientError.message("Anahtar kaldırılamadı.") }
    }
}
