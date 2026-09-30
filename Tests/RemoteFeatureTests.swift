import XCTest
@testable import KisiselGitea

final class RemoteFeatureTests: XCTestCase {
    func testCurrentCommitSnapshotAndAssignment() async throws {
        let snapshot = try await GiteaClient(protocolClasses:[RemoteFixtureProtocol.self]).snapshot(pull,origin:origin,token:"fake")
        XCTAssertEqual(snapshot.nextActor,"reviewer")
        XCTAssertEqual(snapshot.assignees,["Codex"])
        XCTAssertTrue(snapshot.reviews[0].isCurrent(snapshot.metadata.head.sha))
        XCTAssertEqual(snapshot.latestStatuses[0].label,"Geçti")
    }
    func testOldAndDismissedApprovalsAreNotCurrent() throws {
        for mutation in [RemoteFixtureProtocol.review.replacingOccurrences(of:"\"stale\":false",with:"\"stale\":true"),RemoteFixtureProtocol.review.replacingOccurrences(of:"\"dismissed\":false",with:"\"dismissed\":true"),RemoteFixtureProtocol.review.replacingOccurrences(of:RemoteFixtureProtocol.sha,with:RemoteFixtureProtocol.base)] {
            let review = try JSONDecoder().decode(PRReview.self,from:Data(mutation.utf8))
            XCTAssertFalse(review.isCurrent(RemoteFixtureProtocol.sha))
        }
    }
    func testNoAssignmentDoesNotInventMergeReadiness() throws {
        let raw = RemoteFixtureProtocol.metadata.replacingOccurrences(of:"\"requested_reviewers\":[{\"login\":\"reviewer\"}]",with:"\"requested_reviewers\":[]").replacingOccurrences(of:"\"assignees\":[{\"login\":\"Codex\"}]",with:"\"assignees\":[]")
        let metadata = try JSONDecoder().decode(PRMetadata.self,from:Data(raw.utf8))
        let snapshot = PRSnapshot(metadata:metadata,reviews:[],statuses:[],fetchedAt:Date())
        XCTAssertEqual(snapshot.nextActor,"Sorumlu belirtilmemiş")
        XCTAssertTrue(snapshot.latestStatuses.isEmpty)
    }
    func testLatestContextStatusOverridesEarlierSuccess() throws {
        let metadata = try JSONDecoder().decode(PRMetadata.self,from:Data(RemoteFixtureProtocol.metadata.utf8))
        let statuses = [PRStatus(id:2,context:"ci",status:"failure",description:nil),PRStatus(id:1,context:"ci",status:"success",description:nil)]
        let snapshot = PRSnapshot(metadata:metadata,reviews:[],statuses:statuses,fetchedAt:Date())
        XCTAssertEqual(snapshot.latestStatuses.count,1)
        XCTAssertEqual(snapshot.latestStatuses[0].status,"failure")
    }
    func testDiffAndNotifications() async throws {
        let client = GiteaClient(protocolClasses:[RemoteFixtureProtocol.self])
        let files = try await client.files(pull,origin:origin,token:"fake")
        XCTAssertEqual(files.files[0].filename,"App.swift")
        XCTAssertTrue(files.diff.contains("+newTitle"))
        let inbox = try await client.notifications(origin:origin,token:"fake")
        XCTAssertEqual(inbox.threads.count,2)
        XCTAssertTrue(inbox.threads[0].unread)
    }
    func testCacheSeparatesAccountsAndServersAndDeletesOnlySelected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = SnapshotStore(root:root)
        let first = ConnectionIdentity(origin:origin,login:"one")
        let second = ConnectionIdentity(origin:origin,login:"two")
        let third = ConnectionIdentity(origin:URL(string:"https://elsewhere.test")!,login:"one")
        try store.save(["secret-one"],key:"same",identity:first)
        XCTAssertNil(try store.load([String].self,key:"same",identity:second))
        XCTAssertNil(try store.load([String].self,key:"same",identity:third))
        try store.save(["two"],key:"same",identity:second)
        try store.remove(first)
        XCTAssertNil(try store.load([String].self,key:"same",identity:first))
        XCTAssertEqual(try store.load([String].self,key:"same",identity:second),["two"])
    }
    func testUnsafeNotificationLinkRejected() {
        for link in ["http://fixture.invalid/x","https://other.test/x","https://user:pass@fixture.invalid/x"] { XCTAssertNil(GiteaClient.safeLink(link,origin:origin)) }
    }
    let origin = URL(string:"https://fixture.invalid")!
    var pull: PullRequest { PullRequest(id:7,title:"Test",project:Project.samples[0],author:"Claude",body:"",isDemo:false) }
}

final class BoundaryProtocol: URLProtocol {
    static let lock = NSLock()
    static var counts: [String:Int] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!,host = url.host!,path = url.path
        Self.lock.lock(); let count = (Self.counts[host+path] ?? 0)+1; Self.counts[host+path] = count; Self.lock.unlock()
        let body: String
        let page = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first { $0.name == "page" }?.value ?? "1"
        if path.hasSuffix("/reviews") {
            if host.hasPrefix("pages") && page == "1" { body = "[" + Array(repeating:RemoteFixtureProtocol.review,count:50).joined(separator:",") + "]" }
            else if host.hasPrefix("pages") && page == "2" { body = "[" + RemoteFixtureProtocol.review.replacingOccurrences(of:"\"id\":2",with:"\"id\":51") + "]" }
            else { body = "[]" }
        } else if path.hasSuffix("/statuses") { body = "[]" }
        else if host.hasPrefix("moving") && count > 1 { body = RemoteFixtureProtocol.metadata.replacingOccurrences(of:RemoteFixtureProtocol.sha,with:String(repeating:"c",count:40)) }
        else { body = RemoteFixtureProtocol.metadata }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(body.utf8));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension RemoteFeatureTests {
    func testHeadChangeDuringReadIsRejected() async {
        let origin = URL(string:"https://moving-\(UUID().uuidString).test")!
        do { _ = try await GiteaClient(protocolClasses:[BoundaryProtocol.self]).snapshot(pull,origin:origin,token:"fake"); XCTFail("Mixed heads accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("bu sırada değişti")) }
    }
    func testReviewPaginationIsNotSilentlyTruncated() async throws {
        let result = try await GiteaClient(protocolClasses:[BoundaryProtocol.self]).snapshot(pull,origin:URL(string:"https://pages-\(UUID().uuidString).test")!,token:"fake")
        XCTAssertEqual(result.reviews.count,51)
        XCTAssertEqual(result.reviews.last?.id,51)
    }
    func testCacheBoundAndCorruptRecordDoNotLookFresh() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let cache = SnapshotStore(root:root),identity = ConnectionIdentity(origin:origin,login:"test")
        for i in 0..<30 { try cache.save([i],key:"item-\(i)",identity:identity) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:cache.folder(identity).path).count,24)
        try Data("broken".utf8).write(to:cache.url("item-29",identity))
        XCTAssertThrowsError(try cache.load([Int].self,key:"item-29",identity:identity))
    }
}
extension RemoteFeatureTests {
    @MainActor func testOfflineResourceNeverUsesNetwork() async throws {
        let workspace = Workspace()
        let identity = ConnectionIdentity(origin:origin,login:"offline-"+UUID().uuidString)
        workspace.identity = identity;workspace.live = true;workspace.offlineOnly = true
        defer { try? workspace.cache.remove(identity) }
        try workspace.cache.save(["stored"],key:"test",identity:identity)
        let result = try await workspace.resource([String].self,key:"test") { _,_ in XCTFail("Offline attempted a request"); return ["network"] }
        XCTAssertTrue(result.cached);XCTAssertEqual(result.value,["stored"])
    }
    @MainActor func testFailedRefreshExplicitlyReturnsOldRecord() async throws {
        let workspace = Workspace()
        let identity = ConnectionIdentity(origin:URL(string:"https://\(UUID().uuidString).test")!,login:"test")
        workspace.identity = identity;workspace.live = true
        defer { try? workspace.cache.remove(identity);try? TokenVault.delete(account:identity.credentialKey) }
        try TokenVault.save("fake",account:identity.credentialKey)
        try workspace.cache.save(["stored"],key:"test",identity:identity)
        let result = try await workspace.resource([String].self,key:"test") { _,_ in throw URLError(.notConnectedToInternet) }
        XCTAssertTrue(result.cached);XCTAssertTrue(result.note?.contains("Saklanmış") == true)
    }
    @MainActor func testAccountChangeRejectsInFlightData() async throws {
        let workspace = Workspace()
        let identity = ConnectionIdentity(origin:URL(string:"https://\(UUID().uuidString).test")!,login:"test")
        workspace.identity = identity;workspace.live = true
        defer { try? workspace.cache.remove(identity);try? TokenVault.delete(account:identity.credentialKey) }
        try TokenVault.save("fake",account:identity.credentialKey)
        do {
            _ = try await workspace.resource([String].self,key:"test") { _,_ in workspace.useDemo();return ["wrong-account-data"] }
            XCTFail("Stale account data accepted")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(try workspace.cache.load([String].self,key:"test",identity:identity))
    }
}
extension RemoteFeatureTests {
    func testResponsibilityWordingSeparatesReviewFromAssignment() throws {
        let meta = try JSONDecoder().decode(PRMetadata.self,from:Data(RemoteFixtureProtocol.metadata.utf8))
        let value = PRSnapshot(metadata:meta,reviews:[],statuses:[],fetchedAt:Date())
        XCTAssertEqual(value.actionTitle(for:"REVIEWER"),"İnceleme senden bekleniyor")
        XCTAssertEqual(value.actionTitle(for:"Codex"),"İnceleme bekleniyor: reviewer")
        XCTAssertEqual(value.assignees,["Codex"])
        let assigned = RemoteFixtureProtocol.metadata.replacingOccurrences(of:"\"requested_reviewers\":[{\"login\":\"reviewer\"}]",with:"\"requested_reviewers\":[]")
        let other = PRSnapshot(metadata:try JSONDecoder().decode(PRMetadata.self,from:Data(assigned.utf8)),reviews:[],statuses:[],fetchedAt:Date())
        XCTAssertEqual(other.actionTitle(for:"Codex"),"İş sana atanmış")
    }
    func testNotificationRoutingRequiresMatchingServerRepoAndPositivePRNumber() throws {
        func row(_ url: String,_ type: String = "Pull") throws -> NotificationThread {
            let data = try JSONSerialization.data(withJSONObject:["id":1,"unread":true,"updated_at":"now","subject":["title":"Test","type":type,"html_url":url],"repository":["id":1,"name":"Mobile","full_name":"ornek/mobile","private":true]])
            return try JSONDecoder().decode(NotificationThread.self,from:data)
        }
        let good = try row("https://fixture.invalid/ornek/mobile/pulls/7")
        XCTAssertEqual(good.nativePull(origin:origin)?.id,7)
        XCTAssertEqual(good.typeLabel,"PR")
        for path in ["https://evil.test/ornek/mobile/pulls/7","https://fixture.invalid/other/mobile/pulls/7","https://fixture.invalid/ornek/mobile/issues/7","https://fixture.invalid/ornek/mobile/pulls/0","https://fixture.invalid/ornek/mobile/pulls/-1","https://fixture.invalid/ornek/mobile/pulls/7/extra","https://fixture.invalid/ornek/mobile/pulls/7?url=elsewhere"] {
            XCTAssertNil(try row(path).nativePull(origin:origin),path)
        }
        XCTAssertNil(try row("https://fixture.invalid/ornek/mobile/pulls/7","Issue").nativePull(origin:origin))
    }
}
