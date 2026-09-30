import XCTest
@testable import KisiselGitea

final class ProductProtocol: URLProtocol {
    static let lock = NSLock()
    static var handler: ((URLRequest) -> (Int,String))?
    static var delay: TimeInterval = 0
    static var headers: [String:String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let reply = Self.handler?(request) ?? (500,""); let delay = Self.delay; let headers = Self.headers; Self.lock.unlock()
        let deliver = { [self] in
            if reply.0 == 0 { client?.urlProtocol(self,didFailWithError:URLError(.notConnectedToInternet)); return }
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:reply.0,httpVersion:nil,headerFields:headers)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:Data(reply.1.utf8)); client?.urlProtocolDidFinishLoading(self)
        }
        if delay > 0 { DispatchQueue.global().asyncAfter(deadline:.now()+delay,execute:deliver) } else { deliver() }
    }
    override func stopLoading() {}
}

@MainActor final class AccountAndPagingTests: XCTestCase {
    var root: URL!
    var defaults: UserDefaults!
    var suite: String!
    var first: ConnectionIdentity!
    var second: ConnectionIdentity!
    var third: ConnectionIdentity!
    override func setUp() {
        super.setUp()
        suite = "test.accounts." + UUID().uuidString; defaults = UserDefaults(suiteName:suite)!
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        first = .init(origin:URL(string:"https://first.test")!,login:"alice-"+UUID().uuidString)
        second = .init(origin:first.origin,login:"bob-"+UUID().uuidString)
        third = .init(origin:URL(string:"https://second.test")!,login:first.login)
        ProductProtocol.handler = nil; ProductProtocol.delay = 0; ProductProtocol.headers = [:]
    }
    override func tearDown() {
        for identity in [first,second,third].compactMap({$0}) { try? TokenVault.delete(account:identity.credentialKey) }
        defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root)
        ProductProtocol.handler = nil; ProductProtocol.delay = 0; ProductProtocol.headers = [:]
        super.tearDown()
    }
    func workspace() -> Workspace { Workspace(defaults:defaults,client:GiteaClient(protocolClasses:[ProductProtocol.self]),cache:SnapshotStore(root:root.appendingPathComponent("cache")),draftRoot:root) }
    func seed(_ identities: [ConnectionIdentity]) throws {
        defaults.set(try JSONEncoder().encode(identities),forKey:"accounts.v1")
        defaults.set(try JSONEncoder().encode(identities[0]),forKey:"lastReadIdentity")
        defaults.set("connected",forKey:"workspace.mode")
        for identity in identities {
            try TokenVault.save(identity.login,account:identity.credentialKey)
            try SnapshotStore(root:root.appendingPathComponent("cache")).save(CatalogSnapshot(projects:Project.samples,fetchedAt:Date(timeIntervalSince1970:123)),key:"catalog",identity:identity)
        }
    }
    func testThreeAccountSwitchingSeparatesIdeasFavoritesAndRemoval() throws {
        try seed([first,second,third]); let work = workspace()
        XCTAssertTrue(work.offlineOnly); XCTAssertEqual(work.accounts.count,3)
        try work.save(DraftIdea(title:"Alice",text:"",project:"")); work.favorites = ["alice/repo"]
        try work.selectAccount(second); XCTAssertTrue(work.drafts.isEmpty); XCTAssertTrue(work.favorites.isEmpty)
        try work.save(DraftIdea(title:"Bob",text:"",project:"")); work.favorites = ["bob/repo"]
        try work.selectAccount(third); XCTAssertTrue(work.drafts.isEmpty)
        try work.selectAccount(first); XCTAssertEqual(work.drafts.map(\.title),["Alice"]); XCTAssertEqual(work.favorites,["alice/repo"])
        try work.removeAccount(first)
        XCTAssertNil(try TokenVault.load(account:first.credentialKey))
        XCTAssertEqual(try TokenVault.load(account:second.credentialKey),second.login)
        try work.selectAccount(second); XCTAssertEqual(work.drafts.map(\.title),["Bob"]); XCTAssertEqual(work.favorites,["bob/repo"])
        XCTAssertNotNil(try work.cache.load(CatalogSnapshot.self,key:"catalog",identity:third))
        XCTAssertEqual(workspace().accounts.count,2)
    }
    func testLegacyIdentityAndDeviceIdeasMigrateOnlyOnExplicitCopy() throws {
        try seed([first]); defaults.removeObject(forKey:"accounts.v1")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let original = try JSONEncoder().encode([DraftIdea(title:"Eski fikir",text:"Yerel",project:"")])
        let file = root.appendingPathComponent("ideas.json"); try original.write(to:file)
        let work = workspace(); XCTAssertEqual(work.accounts,[first]); XCTAssertTrue(work.drafts.isEmpty); XCTAssertEqual(work.deviceDrafts.count,1)
        try work.copyDeviceDraftsToAccount(); try work.copyDeviceDraftsToAccount()
        XCTAssertEqual(work.drafts.count,1); XCTAssertEqual(try Data(contentsOf:file),original)
        try work.removeAccount(first); XCTAssertEqual(work.deviceDrafts.count,1); XCTAssertEqual(try Data(contentsOf:file),original)
    }
    func testRelaunchReconnectVerifiesIdentityWithoutReenteringToken() async throws {
        try seed([first]); let login = first.login
        ProductProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"token " + login)
            return request.url!.path.hasSuffix("/user") ? (200,"{\"login\":\"\(login)\"}") : (200,"[]")
        }
        let work = workspace(); XCTAssertTrue(work.offlineOnly)
        try await work.reconnect(); XCTAssertFalse(work.offlineOnly); XCTAssertEqual(work.identity,first)
        let reopened = workspace(); XCTAssertTrue(reopened.offlineOnly); XCTAssertEqual(reopened.identity,first)
    }
    func testRefusedMismatchedAndNetworkReconnectPreserveOldCacheAndMode() async throws {
        try seed([first]); let work = workspace(); let before = work.cacheNotice
        for response in [(401,""),(200,"{\"login\":\"wrong-account\"}"),(0,"")] {
            ProductProtocol.handler = { _ in response }
            do { try await work.reconnect(); XCTFail("Reconnect should fail") } catch { }
            XCTAssertTrue(work.offlineOnly); XCTAssertEqual(work.identity,first); XCTAssertEqual(work.cacheNotice,before)
            XCTAssertEqual(try work.cache.load(CatalogSnapshot.self,key:"catalog",identity:first)?.fetchedAt,Date(timeIntervalSince1970:123))
        }
    }
    func testAccountSwitchDuringReconnectRejectsLateResult() async throws {
        try seed([first,second]); let work = workspace(); let arrived = expectation(description:"request started"); let login = first.login
        ProductProtocol.delay = 0.15
        ProductProtocol.handler = { request in
            if request.url!.path.hasSuffix("/user") { arrived.fulfill(); return (200,"{\"login\":\"\(login)\"}") }
            return (200,"[]")
        }
        let task = Task { try await work.reconnect() }
        await fulfillment(of:[arrived],timeout:2)
        try work.selectAccount(second)
        do { try await task.value; XCTFail("Old reconnect accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(work.identity,second); XCTAssertTrue(work.offlineOnly)
    }
    func testPagination51And101AndOfflineCoverage() async throws {
        for total in [51,101] {
            try seed([first]); let work = workspace(); work.offlineOnly = false
            ProductProtocol.handler = { request in
                let page = Int(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first { $0.name == "page" }!.value!)!
                let begin = (page-1)*50+1; let end = min(page*50,total)
                let rows = begin <= end ? (begin...end).map { "{\"number\":\($0),\"title\":\"PR\",\"user\":{\"login\":\"alice\"}}" } : []
                return (200,"["+rows.joined(separator:",")+"]")
            }
            var list = try await work.loadPullList(Project.samples[0]); let firstDate = list.value.fetchedAt
            while list.value.hasMore { list = try await work.loadMorePulls(Project.samples[0],previous:list.value) }
            XCTAssertEqual(list.value.pulls.count,total); XCTAssertEqual(Set(list.value.pulls.map(\.id)).count,total)
            XCTAssertEqual(list.value.fetchedAt,firstDate)
            try work.openOffline(); ProductProtocol.handler = { _ in XCTFail("Offline network"); return (500,"") }
            let offline = try await work.loadPullList(Project.samples[0]); XCTAssertTrue(offline.cached); XCTAssertEqual(offline.value.pulls.count,total); XCTAssertFalse(offline.value.hasMore); XCTAssertEqual(offline.value.fetchedAt,firstDate)
        }
    }
    func testFailedNextPageKeepsCursorAndRetryOnlyFetchesFailedPage() async throws {
        try seed([first]); let work = workspace(); work.offlineOnly = false; var pages: [Int] = []; var fail = true
        ProductProtocol.handler = { request in
            let page = Int(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first { $0.name == "page" }!.value!)!; pages.append(page)
            if page == 2 && fail { return (500,"") }
            let rows = page == 1 ? (1...50).map { "{\"number\":\($0),\"title\":\"PR\",\"user\":{\"login\":\"a\"}}" } : ["{\"number\":51,\"title\":\"PR\",\"user\":{\"login\":\"a\"}}"]
            return (200,"["+rows.joined(separator:",")+"]")
        }
        let list = try await work.loadPullList(Project.samples[0])
        do { _ = try await work.loadMorePulls(Project.samples[0],previous:list.value); XCTFail() } catch { }
        XCTAssertEqual(try work.cache.load(PullListSnapshot.self,key:"pulls|\(Project.samples[0].fullName)",identity:first)?.nextPage,2)
        fail = false; let next = try await work.loadMorePulls(Project.samples[0],previous:list.value)
        XCTAssertEqual(next.value.pulls.count,51); XCTAssertEqual(pages,[1,2,2])
    }
    func testLegacyListCoverageAndOverlappingPageDeduplicate() throws {
        let old = PullListSnapshot(pulls:PullRequest.samples,fetchedAt:Date(timeIntervalSince1970:12))
        let json = try JSONEncoder().encode(old); let decoded = try JSONDecoder().decode(PullListSnapshot.self,from:json)
        XCTAssertEqual(decoded.nextPage,2)
        let combined = old.appending(PullListSnapshot(pulls:PullRequest.samples,fetchedAt:Date(),lastPage:2,moreAvailable:false))
        XCTAssertEqual(combined.pulls.count,2); XCTAssertEqual(combined.fetchedAt,old.fetchedAt)
    }
}

extension AccountAndPagingTests {
    func testLatePageCannotOverwriteRefreshOrSwitchedAccount() async throws {
        try seed([first,second]); let work = workspace(); work.offlineOnly = false
        let initial = PullListSnapshot(pulls:PullRequest.samples,fetchedAt:Date(timeIntervalSince1970:10),lastPage:1,moreAvailable:true)
        for changeAccount in [false,true] {
            try work.selectAccount(first); work.offlineOnly = false
            let arrived = expectation(description:"next page started")
            ProductProtocol.delay = 0.15
            ProductProtocol.handler = { request in
                let page = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems?.first { $0.name == "page" }?.value
                if page == "2" { arrived.fulfill(); return (200,"[{\"number\":51,\"title\":\"Late\",\"user\":{\"login\":\"a\"}}]") }
                return (200,"[]")
            }
            let task = Task { try await work.loadMorePulls(Project.samples[0],previous:initial) }
            await fulfillment(of:[arrived],timeout:2)
            if changeAccount { try work.selectAccount(second) }
            else { _ = try await work.loadPullList(Project.samples[0]) }
            do { _ = try await task.value; XCTFail("Late page accepted") } catch { XCTAssertTrue(error is CancellationError) }
            if !changeAccount { XCTAssertEqual(try work.cache.load(PullListSnapshot.self,key:"pulls|\(Project.samples[0].fullName)",identity:first)?.pulls.count,0) }
        }
    }
    func testCancelledPageNeverUpdatesCache() async throws {
        try seed([first]); let work = workspace(); work.offlineOnly = false
        let initial = PullListSnapshot(pulls:PullRequest.samples,fetchedAt:Date(),lastPage:1,moreAvailable:true)
        let arrived = expectation(description:"page requested"); ProductProtocol.delay = 0.15
        ProductProtocol.handler = { _ in arrived.fulfill(); return (200,"[]") }
        let task = Task { try await work.loadMorePulls(Project.samples[0],previous:initial) }
        await fulfillment(of:[arrived],timeout:2); task.cancel()
        do { _ = try await task.value; XCTFail() } catch { }
        XCTAssertNil(try work.cache.load(PullListSnapshot.self,key:"pulls|\(Project.samples[0].fullName)",identity:first))
    }
    func testNotificationAccountChangeAfterWriteDoesNotReportSuccess() async throws {
        try seed([first,second]); let work = workspace(); work.offlineOnly = false
        let unread = notificationJSON(unread:true),read = notificationJSON(unread:false),arrived = expectation(description:"write requested"); var writes = 0
        ProductProtocol.delay = 0.15
        ProductProtocol.handler = { request in
            if request.httpMethod == "PATCH" { writes += 1; arrived.fulfill(); return (205,read) }
            return (200,unread)
        }
        let original = try thread(); let task = Task { try await work.markNotificationRead(original,writer:NotificationWriter(protocolClasses:[ProductProtocol.self])) }
        await fulfillment(of:[arrived],timeout:2); try work.selectAccount(second)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(writes,1); XCTAssertEqual(work.identity,second)
    }
}

extension AccountAndPagingTests {
    func testServerCappedPageSizeRequiresPaginationEvidence() async throws {
        let client = GiteaClient(protocolClasses:[ProductProtocol.self])
        let body = "[" + (1...10).map { "{\"number\":\($0),\"title\":\"PR\",\"user\":{\"login\":\"a\"}}" }.joined(separator:",") + "]"
        ProductProtocol.handler = { _ in (200,body) }
        let unknown = try await client.pullPage(project:Project.samples[0],origin:first.origin,token:"synthetic")
        XCTAssertTrue(unknown.hasMore,"A short page is not proof when the server caps limit")
        ProductProtocol.headers = ["Link":"<https://first.test/api/v1/repos/a/b/pulls?page=2>; rel=\"next\""]
        let next = try await client.pullPage(project:Project.samples[0],origin:first.origin,token:"synthetic")
        XCTAssertTrue(next.hasMore)
        ProductProtocol.headers = ["Link":"<https://first.test/api/v1/repos/a/b/pulls?page=1>; rel=\"prev\""]
        let last = try await client.pullPage(project:Project.samples[0],origin:first.origin,token:"synthetic",page:2)
        XCTAssertFalse(last.hasMore)
    }
}

extension AccountAndPagingTests {
    func testExplicitOfflineSelectionSurvivesRestartAfterDemo() throws {
        try seed([first]); let work = workspace(); work.useDemo()
        try work.openOffline()
        XCTAssertEqual(defaults.string(forKey:"workspace.mode"),"connected")
        let reopened = workspace(); XCTAssertTrue(reopened.offlineOnly); XCTAssertEqual(reopened.identity,first)
    }
    func testAppendingFreshPageDoesNotMakeCachedEarlierPagesLookFresh() async throws {
        try seed([first]); let work = workspace(); work.offlineOnly = false
        ProductProtocol.handler = { _ in (200,"[]") }
        let earlier = PullListSnapshot(pulls:PullRequest.samples,fetchedAt:Date(timeIntervalSince1970:10),lastPage:1,moreAvailable:true)
        let merged = try await work.loadMorePulls(Project.samples[0],previous:earlier,previousCached:true)
        XCTAssertTrue(merged.cached); XCTAssertEqual(merged.value.fetchedAt,earlier.fetchedAt)
        XCTAssertTrue(merged.note?.contains("saklanmış") == true)
    }
}
