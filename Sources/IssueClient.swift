import Foundation

extension GiteaClient {
    static func issueRepoPath(_ project: Project) throws -> String { String(try repositoryPath(project.fullName).dropLast(6)) }
    func issueList(_ project: Project,origin: URL,token: String) async throws -> IssueListSnapshot {
        let issues: [GiteaIssue] = try await pages(Self.issueRepoPath(project)+"/issues",query:[.init(name:"state",value:"all"),.init(name:"type",value:"issues")],origin:origin,token:token)
        return IssueListSnapshot(issues:issues.filter { $0.pull_request == nil },fetchedAt:Date())
    }
    func issueDetail(_ project: Project,number: Int,origin: URL,token: String) async throws -> IssueDetailSnapshot {
        guard number > 0 else { throw ClientError.message("Geçersiz konu numarası.") }
        let path = try Self.issueRepoPath(project)+"/issues/\(number)"
        async let issue: GiteaIssue = read(path,origin:origin,token:token)
        async let comments: [IssueComment] = pages(path+"/comments",origin:origin,token:token)
        return try await IssueDetailSnapshot(issue:issue,comments:comments,fetchedAt:Date())
    }
    func issueOptions(_ project: Project,origin: URL,token: String) async throws -> IssueOptions {
        let repo = try Self.issueRepoPath(project)
        let permissions: IssueRepositoryPermissions = try await read(repo,origin:origin,token:token)
        guard permissions.permissions?.push == true || permissions.permissions?.admin == true else {
            return IssueOptions(labels:[],assignees:[],canManage:false,note:"Etiket ve sorumlu yönetim izni doğrulanmadı. Yalnız konu veya yorum gönderebilirsin; son kararı sunucu verir.")
        }
        async let labels: [IssueLabel] = pages(repo+"/labels",origin:origin,token:token)
        async let people: [GiteaUser] = pages(repo+"/assignees",origin:origin,token:token)
        return try await IssueOptions(labels:labels,assignees:people,canManage:true,note:nil)
    }
}

struct IssueWriteRefused: LocalizedError {
    let status: Int
    var errorDescription: String? { "Sunucu gönderimi reddetti (\(status)). Anahtarın yazma iznini ve konu erişimini kontrol et. Taslağın korundu." }
}
final class IssueWriter: @unchecked Sendable {
    private let session: URLSession
    init(protocolClasses: [AnyClass]? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 45
        configuration.protocolClasses = protocolClasses
        session = URLSession(configuration:configuration,delegate:NoRedirect(),delegateQueue:nil)
    }
    func send<Body: Encodable,Result: Decodable>(_ body: Body,path: String,method: String = "POST",identity: ConnectionIdentity,token: String,as: Result.Type) async throws -> Result {
        let origin = try GiteaClient.validatedOrigin(identity.origin.absoluteString)
        guard path.hasPrefix("/repos/"), ["POST","PATCH","PUT"].contains(method) else { throw ClientError.message("Geçersiz gönderim.") }
        var components = URLComponents(url:origin,resolvingAgainstBaseURL:false)!
        components.percentEncodedPath = "/api/v1" + path
        var request = URLRequest(url:components.url!)
        request.httpMethod = method; request.httpBody = try JSONEncoder().encode(body)
        request.setValue("token " + token,forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        let (bytes,response) = try await session.bytes(for:request)
        guard let response = response as? HTTPURLResponse else { throw ClientError.message("Gönderimin sonucu bilinmiyor. Yeniden göndermeden Gitea’da kontrol et.") }
        if [400,401,403,404,405,409,410,413,415,422,429].contains(response.statusCode) { throw IssueWriteRefused(status:response.statusCode) }
        guard [200,201].contains(response.statusCode) else { throw ClientError.message("Gönderimin sonucu doğrulanamadı (\(response.statusCode)). Yinelenmemesi için tekrar gönderilmedi; Gitea’da kontrol et.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 4_194_304 else { throw ClientError.message("Yanıt fazla büyük. Gönderimi Gitea’da kontrol et.") }
            data.append(byte)
        }
        return try JSONDecoder().decode(Result.self,from:data)
    }
}

extension Workspace {
    func loadIssues(_ project: Project) async throws -> ReadResult<IssueListSnapshot> {
        try await resource(IssueListSnapshot.self,key:"issues|\(project.fullName)") { origin,token in try await self.client.issueList(project,origin:origin,token:token) }
    }
    func loadIssue(_ project: Project,number: Int) async throws -> ReadResult<IssueDetailSnapshot> {
        try await resource(IssueDetailSnapshot.self,key:"issue|\(project.fullName)|\(number)") { origin,token in try await self.client.issueDetail(project,number:number,origin:origin,token:token) }
    }
    /// This read deliberately bypasses the offline/cache fallback before a metadata write.
    func freshIssue(_ project: Project,number: Int) async throws -> GiteaIssue {
        guard !offlineOnly else { throw ClientError.message("Değişiklik için canlı bağlantı gerekli.") }
        let (selected,token) = try credentials()
        let revision = accountRevision
        let result = try await client.issueDetail(project,number:number,origin:selected.origin,token:token)
        guard isCurrent(selected,revision:revision) else { throw CancellationError() }
        return result.issue
    }
    func issueOptions(_ project: Project) async throws -> IssueOptions {
        guard !offlineOnly else { throw ClientError.message("Çevrimdışıyken gönderim ve yetki sorgusu yapılamaz.") }
        let (selected,token) = try credentials()
        let revision = accountRevision
        let options = try await client.issueOptions(project,origin:selected.origin,token:token)
        guard isCurrent(selected,revision:revision) else { throw CancellationError() }
        return options
    }
    func issueWrite<Body: Encodable,Result: Decodable>(_ body: Body,path: String,method: String = "POST",operation: String,as: Result.Type) async throws -> Result {
        guard !offlineOnly else { throw ClientError.message("Göndermek için internete bağlan.") }
        let (selected,token) = try credentials()
        let revision = accountRevision
        try IssueWriteLedger.shared.begin(identity:selected,operation:operation)
        do {
            #if DEBUG
            let writer = IssueWriter(protocolClasses:isFixture ? [IssueFixtureProtocol.self] : nil)
            #else
            let writer = IssueWriter()
            #endif
            let result = try await writer.send(body,path:path,method:method,identity:selected,token:token,as:Result.self)
            try IssueWriteLedger.shared.record(.init(state:"sent",number:(result as? GiteaIssue)?.number,date:Date()),identity:selected,operation:operation)
            guard isCurrent(selected,revision:revision) else { throw CancellationError() }
            return result
        } catch let error as IssueWriteRefused {
            IssueWriteLedger.shared.refused(identity:selected,operation:operation)
            throw error
        } catch {
            throw ClientError.message("Gönderim sonucu kesinleştirilemedi. Taslağın korundu; otomatik tekrar yapılmadı. Gitea’da kontrol et. " + error.localizedDescription)
        }
    }
    func createIssue(draft: DraftIdea,project: Project,labels: Set<Int>,assignees: Set<String>) async throws -> GiteaIssue {
        guard !draft.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw ClientError.message("Konu başlığı boş olamaz.") }
        // Preserve the local idea even when the request times out or succeeds.
        try save(draft)
        return try await issueWrite(CreateIssueBody(title:draft.title,body:draft.markdown,labels:labels.isEmpty ? nil : labels.sorted(),assignees:assignees.isEmpty ? nil : assignees.sorted()),path:GiteaClient.issueRepoPath(project)+"/issues",operation:"create|\(project.fullName)|\(draft.id)",as:GiteaIssue.self)
    }
    func postComment(project: Project,number: Int,text: String,attempt: UUID) async throws -> IssueComment {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw ClientError.message("Yorum boş olamaz.") }
        return try await issueWrite(CommentBody(body:text),path:GiteaClient.issueRepoPath(project)+"/issues/\(number)/comments",operation:IssueWriteLedger.commentOperation(project:project,number:number,attempt:attempt),as:IssueComment.self)
    }
}

#if DEBUG
/// Explicit UI fixture mode cannot dispatch writes to a real server.
final class IssueFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var comments: [String] = []
    private static var issues: [String] = []
    static var commentBodies: [String] { lock.withLock { comments } }
    static var createdBodies: [String] { lock.withLock { issues } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody
        if data == nil,let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var result = Data(); var buffer = [UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer,maxLength:buffer.count); if n <= 0 { break }; result.append(buffer,count:n) }
            data = result
        }
        let payload = data.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] } ?? [:]
        let json: [String:Any]
        let isComment = request.url!.path.hasSuffix("/comments")
        if isComment {
            json = ["id":501 + Self.commentBodies.count,"body":payload["body"] ?? "Örnek yorum","user":["login":"demo"],"html_url":"https://fixture.invalid/ornek/mobile/issues/7#issuecomment-501"]
        } else {
            json = ["id":99,"number":99,"title":payload["title"] ?? "Örnek fikir","body":payload["body"] ?? "Fixture gönderim","state":"open","user":["login":"demo"],"html_url":"https://fixture.invalid/ornek/mobile/issues/99","labels":[],"assignees":[]]
        }
        let object: Any = request.httpMethod == "PUT" ? [] as [String] : json
        let bytes = (try? JSONSerialization.data(withJSONObject:object)) ?? Data()
        let body = String(data:bytes,encoding:.utf8) ?? "{}"
        if request.httpMethod == "POST" { Self.lock.withLock { if isComment { Self.comments.append(body) } else { Self.issues.append(body) } } }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:request.httpMethod == "POST" ? 201 : 200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:bytes); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
