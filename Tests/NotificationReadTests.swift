import XCTest
@testable import KisiselGitea

extension AccountAndPagingTests {
    func thread(unread: Bool = true) throws -> NotificationThread {
        try JSONDecoder().decode(NotificationThread.self,from:Data(notificationJSON(unread:unread).utf8))
    }
    func notificationJSON(unread: Bool) -> String {
        "{\"id\":1,\"unread\":\(unread),\"updated_at\":\"2026-09-30T10:00:00Z\",\"subject\":{\"title\":\"Test\",\"type\":\"Issue\"},\"repository\":{\"id\":1,\"name\":\"Test\",\"full_name\":\"alice/test\",\"private\":true}}"
    }
    func testNotificationReadRequiresServerReadbackAndExplicitGesture() async throws {
        try seed([first]); let work = workspace(); work.offlineOnly = false
        let unread = notificationJSON(unread:true),read = notificationJSON(unread:false); var methods: [String] = []; var marked = false
        ProductProtocol.handler = { request in
            methods.append(request.httpMethod!)
            if request.httpMethod == "PATCH" {
                XCTAssertEqual(request.url!.path,"/api/v1/notifications/threads/1")
                XCTAssertEqual(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems?.first?.value,"read")
                marked = true; return (205,read)
            }
            return (200,marked ? read : unread)
        }
        XCTAssertTrue(methods.isEmpty)
        let verified = try await work.markNotificationRead(thread(),writer:NotificationWriter(protocolClasses:[ProductProtocol.self]))
        XCTAssertFalse(verified.unread); XCTAssertEqual(methods,["GET","PATCH","GET"])
    }
    func testNotificationWritePermissionDeniedDoesNotPreventReading() async throws {
        try seed([first]); let work = workspace(); work.offlineOnly = false; let unread = notificationJSON(unread:true)
        ProductProtocol.handler = { request in request.httpMethod == "PATCH" ? (403,"") : (200,unread) }
        do { _ = try await work.markNotificationRead(thread(),writer:NotificationWriter(protocolClasses:[ProductProtocol.self])); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("notification yazma")) }
        let after: NotificationThread = try await work.client.read("/notifications/threads/1",origin:first.origin,token:first.login)
        XCTAssertTrue(after.unread)
    }
    func testAmbiguousNotificationRetryReadsStateBeforeAnySecondWrite() async throws {
        try seed([first]); let work = workspace(); work.offlineOnly = false
        let unread = notificationJSON(unread:true),read = notificationJSON(unread:false); var marked = false; var denyReadback = true; var writes = 0
        ProductProtocol.handler = { request in
            if request.httpMethod == "PATCH" { writes += 1; marked = true; return (205,read) }
            if marked && denyReadback { return (0,"") }
            return (200,marked ? read : unread)
        }
        let writer = NotificationWriter(protocolClasses:[ProductProtocol.self])
        do { _ = try await work.markNotificationRead(thread(),writer:writer); XCTFail("Unverified success") } catch { }
        XCTAssertEqual(writes,1); denyReadback = false
        let verified = try await work.markNotificationRead(thread(),writer:writer)
        XCTAssertFalse(verified.unread); XCTAssertEqual(writes,1)
    }
    func testUnchangedUnreadReadbackIsNeverSuccessAndOfflineNeverWrites() async throws {
        try seed([first]); let work = workspace(); let unread = notificationJSON(unread:true); var calls = 0
        ProductProtocol.handler = { request in calls += 1; return (request.httpMethod == "PATCH" ? 205 : 200,unread) }
        do { _ = try await work.markNotificationRead(thread(),writer:NotificationWriter(protocolClasses:[ProductProtocol.self])); XCTFail() } catch { }
        XCTAssertEqual(calls,0)
        work.offlineOnly = false
        do { _ = try await work.markNotificationRead(thread(),writer:NotificationWriter(protocolClasses:[ProductProtocol.self])); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("doğrulamadı")) }
        XCTAssertEqual(calls,3)
    }
    func testNotificationAccountChangeDuringPreflightDoesNotWrite() async throws {
        try seed([first,second]); let work = workspace(); work.offlineOnly = false
        let unread = notificationJSON(unread:true),arrived = expectation(description:"notification request"); var writes = 0
        ProductProtocol.delay = 0.15
        ProductProtocol.handler = { request in if request.httpMethod == "PATCH" { writes += 1 } else { arrived.fulfill() }; return (200,unread) }
        let original = try thread(); let task = Task { try await work.markNotificationRead(original,writer:NotificationWriter(protocolClasses:[ProductProtocol.self])) }
        await fulfillment(of:[arrived],timeout:2); try work.selectAccount(second)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(writes,0); XCTAssertEqual(work.identity,second)
    }
}
