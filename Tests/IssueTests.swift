import XCTest
@testable import KisiselGitea

final class IssueTests: XCTestCase {
    @MainActor func testUncertainWritesSurviveNewLedgerAndAreAccountScoped() throws {
        let suite = "IssueTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let first = ConnectionIdentity(origin:URL(string:"https://git.test")!,login:"one")
        let second = ConnectionIdentity(origin:URL(string:"https://git.test")!,login:"two")
        let ledger = IssueWriteLedger(defaults:defaults)
        try ledger.begin(identity:first,operation:"create|owner/repo|draft")
        let reopened = IssueWriteLedger(defaults:defaults)
        XCTAssertThrowsError(try reopened.begin(identity:first,operation:"create|owner/repo|draft"))
        XCTAssertNoThrow(try reopened.begin(identity:second,operation:"create|owner/repo|draft"))
        reopened.refused(identity:first,operation:"create|owner/repo|draft")
        XCTAssertNoThrow(try reopened.begin(identity:first,operation:"create|owner/repo|draft"))
    }
    @MainActor func testConfirmedCreationKeepsReceiptAndCannotDuplicate() throws {
        let suite = "IssueTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let identity = ConnectionIdentity(origin:URL(string:"https://git.test")!,login:"one")
        let ledger = IssueWriteLedger(defaults:defaults)
        try ledger.begin(identity:identity,operation:"draft")
        try ledger.record(.init(state:"sent",number:42,date:Date()),identity:identity,operation:"draft")
        XCTAssertEqual(ledger.receipt(identity:identity,operation:"draft")?.number,42)
        XCTAssertThrowsError(try ledger.begin(identity:identity,operation:"draft"))
    }
    @MainActor func testCorruptLedgerFailsClosed() throws {
        let suite = "IssueTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let identity = ConnectionIdentity(origin:URL(string:"https://git.test")!,login:"one")
        let ledger = IssueWriteLedger(defaults:defaults)
        defaults.set(Data("corrupt".utf8),forKey:ledger.key(identity:identity,operation:"draft"))
        XCTAssertThrowsError(try ledger.begin(identity:identity,operation:"draft"))
    }
    @MainActor func testCommentAttemptPersistsAndAllowsDeliberateIdenticalNewComment() throws {
        let suite = "IssueTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let identity = ConnectionIdentity(origin:URL(string:"https://git.test")!,login:"one")
        let draft = IssueCommentDraft(text:"Aynı yorum")
        try draft.save(key:"draft",defaults:defaults,flush:true)
        let loaded = try IssueCommentDraft.load(key:"draft",defaults:defaults)
        XCTAssertEqual(loaded.attempt,draft.attempt); XCTAssertEqual(loaded.text,draft.text)
        let ledger = IssueWriteLedger(defaults:defaults)
        let operation = IssueWriteLedger.commentOperation(project:Project.samples[0],number:7,attempt:loaded.attempt)
        try ledger.begin(identity:identity,operation:operation)
        XCTAssertThrowsError(try ledger.begin(identity:identity,operation:operation))
        let next = IssueCommentDraft(text:"Aynı yorum")
        let nextOperation = IssueWriteLedger.commentOperation(project:Project.samples[0],number:7,attempt:next.attempt)
        XCTAssertNotEqual(operation,nextOperation)
        XCTAssertNoThrow(try ledger.begin(identity:identity,operation:nextOperation))
        // An uncertain attempt keeps its saved body and UUID across reopening.
        XCTAssertEqual(try IssueCommentDraft.load(key:"draft",defaults:defaults).attempt,loaded.attempt)
    }
    func testMetadataBaselineRejectsConcurrentLabelsAndAssignees() throws {
        let baseline = IssueMetadataBaseline(people:["alice"],labels:[1])
        func issue(_ label: Int,_ person: String) throws -> GiteaIssue {
            try JSONDecoder().decode(GiteaIssue.self,from:Data("{\"id\":1,\"number\":1,\"title\":\"Test\",\"state\":\"open\",\"labels\":[{\"id\":\(label),\"name\":\"Test\"}],\"assignees\":[{\"login\":\"\(person)\"}]}".utf8))
        }
        XCTAssertNoThrow(try baseline.validate(issue(1,"alice")))
        XCTAssertThrowsError(try baseline.validate(issue(2,"alice")))
        XCTAssertThrowsError(try baseline.validate(issue(1,"bob")))
    }
    func testCreateBodyOmitsPrivilegedFieldsWhenNotSelected() throws {
        let body = CreateIssueBody(title:"Fikir",body:"**Metin**",labels:nil,assignees:nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(body)) as? [String:Any])
        XCTAssertNil(json["labels"]); XCTAssertNil(json["assignees"])
        XCTAssertEqual(json["body"] as? String,"**Metin**")
    }
    func testIssueReadFiltersPullRequestsAndPreservesDiscussion() async throws {
        let client = GiteaClient(protocolClasses:[IssueTestProtocol.self])
        let origin = URL(string:"https://ok.test")!
        let list = try await client.issueList(Project.samples[0],origin:origin,token:"synthetic")
        XCTAssertEqual(list.issues.map(\.number),[7])
        let detail = try await client.issueDetail(Project.samples[0],number:7,origin:origin,token:"synthetic")
        XCTAssertEqual(detail.comments.first?.body,"**Merhaba**")
        XCTAssertEqual(detail.issue.number,7)
    }
    func testPermissionUnknownDoesNotOfferLabelsOrAssignees() async throws {
        let client = GiteaClient(protocolClasses:[IssueTestProtocol.self])
        let options = try await client.issueOptions(Project.samples[0],origin:URL(string:"https://no-permission.test")!,token:"synthetic")
        XCTAssertFalse(options.canManage); XCTAssertTrue(options.labels.isEmpty)
    }
    func testWriterUsesExplicitJSONPostAndDecodesSuccess() async throws {
        let writer = IssueWriter(protocolClasses:[IssueTestProtocol.self])
        let result = try await writer.send(CreateIssueBody(title:"Fikir",body:"Metin",labels:nil,assignees:nil),path:"/repos/owner/repo/issues",identity:ConnectionIdentity(origin:URL(string:"https://ok.test")!,login:"one"),token:"synthetic",as:GiteaIssue.self)
        XCTAssertEqual(result.number,7)
    }
    func testWriteRefusalDistinctFromUncertainServerError() async {
        let writer = IssueWriter(protocolClasses:[IssueTestProtocol.self])
        for (host,definite) in [("refused.test",true),("uncertain.test",false),("timeout.test",false),("request-timeout.test",false),("redirect.test",false)] {
            do {
                let _: GiteaIssue = try await writer.send(CommentBody(body:"Test"),path:"/repos/owner/repo/issues",identity:ConnectionIdentity(origin:URL(string:"https://\(host)")!,login:"one"),token:"synthetic",as:GiteaIssue.self)
                XCTFail("Expected failure")
            } catch { XCTAssertEqual(error is IssueWriteRefused,definite) }
        }
    }
}

final class IssueTestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        if url.host == "timeout.test" { client?.urlProtocol(self,didFailWithError:URLError(.timedOut)); return }
        var status = 200
        let issue = #"{"id":7,"number":7,"title":"Fikir","body":"Açıklama","state":"open","user":{"login":"one"}}"#
        var body = issue
        if request.httpMethod == "POST" {
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"token synthetic")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Content-Type"),"application/json")
            switch url.host { case "refused.test": status = 403; case "uncertain.test": status = 503; case "request-timeout.test": status = 408; case "redirect.test": status = 302; default: status = 201 }
        } else if url.path.hasSuffix("/comments") { body = #"[{"id":1,"body":"**Merhaba**","user":{"login":"two"}}]"# }
        else if url.path.hasSuffix("/issues") { body = "[" + issue + #",{"id":8,"number":8,"title":"PR","state":"open","pull_request":{"html_url":"https://ok.test/pulls/8"}}]"# }
        else if url.host == "no-permission.test" { body = #"{"permissions":{"pull":true}}"# }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:url,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
