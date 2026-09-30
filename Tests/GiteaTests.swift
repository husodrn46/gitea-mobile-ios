import XCTest
@testable import KisiselGitea

final class GiteaTests: XCTestCase {
    func testLiveResponsibilityDoesNotGuessFromAuthorOrApproval() {
        let pull = PullRequest(id:5,title:"Real",project:Project.samples[0],author:"Claude",body:"Please merge",isDemo:false,checksPassed:true,approved:true)
        XCTAssertEqual(pull.nextActor,"Henüz bilinmiyor")
        XCTAssertTrue(pull.missing.contains("Güncel"))
    }
    func testOlderDraftStillDecodesWithoutNewFields() throws {
        let draft = try JSONDecoder().decode(DraftIdea.self,from:Data(#"{"id":"C3FD04F6-533B-458C-A04B-3A79D015B6AA","title":"Old","text":"Text","project":"Repo","date":0}"#.utf8))
        XCTAssertNil(draft.problem); XCTAssertNil(draft.acceptance)
        XCTAssertTrue(draft.markdown.contains("# Old"))
    }
    func testOriginRejectsCredentialsAndInsecureURLs() throws {
        for url in ["http://git.test", "https://me:secret@git.test", "https://git.test/path", "https://git.test?token=abc", "https://git.test/#fragment", "file:///tmp/test", "no URL"] {
            XCTAssertThrowsError(try GiteaClient.validatedOrigin(url),url)
        }
        XCTAssertEqual(try GiteaClient.validatedOrigin("https://git.test:8443").host,"git.test")
    }
    func testRepoPathCannotEscapeAPI() throws {
        for name in ["../x", "x/..", "x/y/z", "/x", "x/", "x\\y/z"] { XCTAssertThrowsError(try GiteaClient.repositoryPath(name)) }
        XCTAssertEqual(try GiteaClient.repositoryPath("me/my-repo"),"/repos/me/my-repo/pulls")
        XCTAssertEqual(try GiteaClient.repositoryPath("me/repo?token=x"),"/repos/me/repo%3Ftoken%3Dx/pulls")
    }
    func testUnauthenticatedResponseIsReadable() async {
        let client = GiteaClient(protocolClasses:[FixtureProtocol.self])
        do { let _ = try await client.user(origin:URL(string:"https://unauthorized.test")!,token:"synthetic-only"); XCTFail("Expected refusal") }
        catch { XCTAssertTrue(error.localizedDescription.contains("izinleri")) }
    }
    func testNonJSONRejected() async {
        let client = GiteaClient(protocolClasses:[FixtureProtocol.self])
        do { let _ = try await client.user(origin:URL(string:"https://invalid.test")!,token:"synthetic-only"); XCTFail("Expected refusal") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Gitea biçiminde")) }
    }
    func testGetOnlyWithTokenAndNoBody() async throws {
        let client = GiteaClient(protocolClasses:[FixtureProtocol.self])
        let user = try await client.user(origin:URL(string:"https://valid.test")!,token:"synthetic-only")
        XCTAssertEqual(user.login,"demo")
    }
    func testExternalPullLinkIsNotExposed() async throws {
        let client = GiteaClient(protocolClasses:[FixtureProtocol.self])
        let rows = try await client.pulls(project:Project.samples[0],origin:URL(string:"https://valid.test")!,token:"synthetic-only")
        XCTAssertEqual(rows.count,1); XCTAssertNil(rows[0].url)
        XCTAssertFalse(rows[0].isDemo); XCTAssertFalse(rows[0].approved); XCTAssertFalse(rows[0].checksPassed)
    }
    func testRedirectIsNotFollowed() async {
        let client = GiteaClient(protocolClasses:[FixtureProtocol.self])
        do { let _ = try await client.user(origin:URL(string:"https://redirect.test")!,token:"synthetic-only"); XCTFail("Expected refusal") }
        catch { XCTAssertTrue(error.localizedDescription.contains("yönlendiriyor")) }
    }
    func testKeychainRoundTrip() throws {
        let account = "unit-test-"+UUID().uuidString
        defer { try? TokenVault.delete(account:account) }
        try TokenVault.save("fake-test-token",account:account)
        XCTAssertEqual(try TokenVault.load(account:account),"fake-test-token")
        try TokenVault.save("fake-updated-token",account:account)
        XCTAssertEqual(try TokenVault.load(account:account),"fake-updated-token")
        try TokenVault.delete(account:account)
        XCTAssertNil(try TokenVault.load(account:account))
    }
}
final class FixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "GET",request.httpBody == nil,request.value(forHTTPHeaderField:"Authorization") == "token synthetic-only" else {
            client?.urlProtocol(self,didFailWithError:ClientError.message("invalid request")); return
        }
        let host = request.url!.host!
        let code = host == "unauthorized.test" ? 401 : (host == "redirect.test" ? 302 : 200)
        let body: String
        if host == "invalid.test" { body = "<html>Not Gitea</html>" }
        else if request.url!.path.hasSuffix("pulls") { body = #"[{"number":1,"title":"Test","body":"body","html_url":"https://untrusted.test/token","user":{"login":"demo"}}]"# }
        else { body = #"{"login":"demo"}"# }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
