import XCTest
@testable import KisiselGitea
final class PRWaitingTests: XCTestCase {
    func snapshot(reviews: [PRReview] = [],statuses: [PRStatus] = []) throws -> PRSnapshot {
        PRSnapshot(metadata:try JSONDecoder().decode(PRMetadata.self,from:Data(RemoteFixtureProtocol.metadata.utf8)),reviews:reviews,statuses:statuses,fetchedAt:Date())
    }
    func testUnknownConditionsStayUnknown() throws {
        let value = PRWaitingSummary(snapshot:try snapshot())
        XCTAssertTrue(value.testText.contains("Bilinmiyor"))
        XCTAssertTrue(value.reviewText.contains("doğrulanmadı"))
        XCTAssertTrue(value.conflictText.contains("bilinmiyor"))
    }
    func testNewerChangeRequestOverridesOldApprovalAndBaseChangeWarns() throws {
        let review = try JSONDecoder().decode(PRReview.self,from:Data(RemoteFixtureProtocol.review.utf8))
        let newer = PRReview(id:3,user:review.user,state:"REQUEST_CHANGES",body:nil,commit_id:review.commit_id,stale:false,dismissed:false,official:true,submitted_at:nil)
        let value = PRWaitingSummary(snapshot:try snapshot(reviews:[review,newer]))
        XCTAssertTrue(value.reviewText.contains("Düzeltme"))
        XCTAssertTrue(PRWaitingSummary(snapshot:try snapshot(reviews:[review]),baseChanged:true).reviewText.contains("Taban dal değişti"))
    }
    func testAssignmentsDoNotBecomeNextActor() throws {
        let raw = RemoteFixtureProtocol.metadata.replacingOccurrences(of:"\"requested_reviewers\":[{\"login\":\"reviewer\"}]",with:"\"requested_reviewers\":[]")
        let pr = PRSnapshot(metadata:try JSONDecoder().decode(PRMetadata.self,from:Data(raw.utf8)),reviews:[],statuses:[],fetchedAt:Date())
        XCTAssertTrue(PRWaitingSummary(snapshot:pr).actorText.contains("bilinmiyor"))
        XCTAssertFalse(PRWaitingSummary(snapshot:pr).actorText.contains("Codex"))
    }
    func testIssueNotificationRejectsWrongRepoAndHost() throws {
        let repo = GiteaRepository(id:1,name:"x",full_name:"a/b",description:nil,language:nil,open_issues_count:nil,private:true)
        for (link,expected) in [("https://fixture.invalid/a/b/issues/3",3),("https://fixture.invalid/a/c/issues/3",nil),("https://other.test/a/b/issues/3",nil)] as [(String,Int?)] {
            let n = NotificationThread(id:1,unread:true,updated_at:"",subject:NotificationSubject(title:"x",type:"Issue",html_url:link),repository:repo)
            XCTAssertEqual(n.nativeIssue(origin:URL(string:"https://fixture.invalid")!),expected)
        }
    }
}
