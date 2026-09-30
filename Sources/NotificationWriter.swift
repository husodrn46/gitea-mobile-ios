import Foundation

final class NotificationWriter: @unchecked Sendable {
    private let session: URLSession
    init(protocolClasses: [AnyClass]? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = protocolClasses; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 45
        session = URLSession(configuration:config,delegate:NoRedirect(),delegateQueue:nil)
    }
    func markRead(id: Int,identity: ConnectionIdentity,token: String) async throws {
        guard id > 0 else { throw ClientError.message("Geçersiz bildirim.") }
        let origin = try GiteaClient.validatedOrigin(identity.origin.absoluteString)
        var url = URLComponents(url:origin,resolvingAgainstBaseURL:false)!
        url.path = "/api/v1/notifications/threads/\(id)"; url.queryItems = [.init(name:"to-status",value:"read")]
        var request = URLRequest(url:url.url!); request.httpMethod = "PATCH"
        request.setValue("token " + token,forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        let (_,response) = try await session.data(for:request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.message("Bildirim işleminin sonucu belirsiz. Tekrar denemeden önce sunucudaki durum okunacak.") }
        if [401,403].contains(http.statusCode) { throw ClientError.message("Okundu işaretlemek için anahtarın notification yazma izni gerekli. Bildirimleri okumaya devam edebilirsin.") }
        guard [200,205].contains(http.statusCode) else { throw ClientError.message("Bildirim işlemi doğrulanamadı (\(http.statusCode)). Tekrar denemeden önce durum okunacak.") }
    }
}
extension Workspace {
    /// Every explicit attempt starts with a fresh read, including retries after uncertain writes.
    func markNotificationRead(_ thread: NotificationThread,writer: NotificationWriter? = nil) async throws -> NotificationThread {
        guard !offlineOnly else { throw ClientError.message("Okundu işaretlemek için canlı bağlantı gerekli.") }
        let (selected,token) = try credentials(); let revision = accountRevision
        let before: NotificationThread = try await client.read("/notifications/threads/\(thread.id)",origin:selected.origin,token:token)
        try Task.checkCancellation()
        guard isCurrent(selected,revision:revision),!offlineOnly else { throw CancellationError() }
        guard before.id == thread.id,before.repository.full_name == thread.repository.full_name else { throw ClientError.message("Bildirim hedefi değişti. Listeyi yenile.") }
        if !before.unread { return before }
        guard before.updated_at == thread.updated_at else { throw ClientError.message("Yeni bir bildirim gelmiş. Güncel listeyi inceleyip yeniden işaretle.") }
        #if DEBUG
        let transport = writer ?? NotificationWriter(protocolClasses:isFixture ? [RemoteFixtureProtocol.self] : nil)
        #else
        let transport = writer ?? NotificationWriter()
        #endif
        try await transport.markRead(id:thread.id,identity:selected,token:token)
        try Task.checkCancellation()
        guard isCurrent(selected,revision:revision),!offlineOnly else { throw CancellationError() }
        let after: NotificationThread = try await client.read("/notifications/threads/\(thread.id)",origin:selected.origin,token:token)
        try Task.checkCancellation()
        guard isCurrent(selected,revision:revision),!offlineOnly else { throw CancellationError() }
        guard after.id == thread.id,after.repository.full_name == thread.repository.full_name,!after.unread else { throw ClientError.message("Sunucu okundu durumunu doğrulamadı. Listeyi yenile; otomatik tekrar yapılmadı.") }
        return after
    }
}
