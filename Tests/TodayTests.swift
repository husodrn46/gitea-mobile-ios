import XCTest
@testable import KisiselGitea

final class TodayTests: XCTestCase {
    func snapshot(head: String = "head-a",base: String = "base-a", requested: [String] = [],assigned: [String] = [],status: String? = nil,reviews: [PRReview] = [],draft: Bool = false) throws -> PRSnapshot {
        let raw: [String:Any] = ["number":1,"title":"PR","user":["login":"author"],"state":"open","head":["sha":head],"base":["sha":base],"updated_at":"2026-09-22T12:00:00Z","requested_reviewers":requested.map { ["login":$0] },"assignees":assigned.map { ["login":$0] },"draft":draft]
        let metadata = try JSONDecoder().decode(PRMetadata.self,from:JSONSerialization.data(withJSONObject:raw))
        return PRSnapshot(metadata:metadata,reviews:reviews,statuses:status.map { [PRStatus(id:1,context:"CI",status:$0,description:nil)] } ?? [],fetchedAt:Date())
    }
    func approval(head: String = "head-a", stale: Bool = false) -> PRReview {
        PRReview(id:1,user:nil,state:"APPROVED",body:nil,commit_id:head,stale:stale,dismissed:false,official:true,submitted_at:nil)
    }
    func testAssignmentDoesNotPutUserInReviewQueue() throws {
        let value = try snapshot(assigned:["me"])
        XCTAssertEqual(TodayCategory.classify(value,login:"me"),[.uncertain])
    }
    func testReadyOrActorLabelsDoNotInferAReviewRequest() throws {
        let raw = try snapshot()
        var metadata = raw.metadata
        metadata.labels = [PRLabel(name:"ready"),PRLabel(name:"needs-me")]
        let value = PRSnapshot(metadata:metadata,reviews:[],statuses:[],fetchedAt:Date())
        XCTAssertEqual(TodayCategory.classify(value,login:"me"),[.uncertain])
    }
    func testRequestedReviewAndPendingTestCanOverlap() throws {
        let value = try snapshot(requested:["ME","another"],status:"pending")
        XCTAssertEqual(TodayCategory.classify(value,login:"me"),[.mine,.others,.testing])
        XCTAssertEqual(TodayCategory.classify(try snapshot(requested:["me"],draft:true),login:"me"),[.uncertain])
    }
    func testFirstReadAndCachedReadInventNoHistory() throws {
        var baseline = TodayBaseline()
        XCTAssertTrue(baseline.observe(key:"repo#1",snapshot:try snapshot(status:"pending"),cached:true).isEmpty)
        XCTAssertTrue(baseline.records.isEmpty)
        XCTAssertTrue(baseline.observe(key:"repo#1",snapshot:try snapshot(status:"pending"),cached:false).isEmpty)
        XCTAssertTrue(baseline.observe(key:"repo#1",snapshot:try snapshot(head:"new",status:"success"),cached:true,acknowledge:true).isEmpty)
        XCTAssertEqual(baseline.records["repo#1"]?.head,"head-a")
        XCTAssertEqual(baseline.records["repo#1"]?.statuses["CI"],"pending")
    }
    func testChangesRemainUntilExplicitAcknowledgement() throws {
        var baseline = TodayBaseline()
        _ = baseline.observe(key:"r#1",snapshot:try snapshot(status:"pending",reviews:[approval()]),cached:false)
        let changed = try snapshot(head:"head-b",base:"base-b",status:"success",reviews:[approval()])
        let differences = baseline.observe(key:"r#1",snapshot:changed,cached:false)
        XCTAssertTrue(differences.contains { $0.contains("commit’i değişti") })
        XCTAssertTrue(differences.contains { $0.contains("Hedef dal") })
        XCTAssertTrue(differences.contains { $0.contains("sürüyor → geçti") })
        XCTAssertTrue(differences.contains { $0.contains("artık güncel") })
        XCTAssertEqual(baseline.observe(key:"r#1",snapshot:changed,cached:false),differences)
        _ = baseline.observe(key:"r#1",snapshot:changed,cached:false,acknowledge:true)
        XCTAssertTrue(baseline.observe(key:"r#1",snapshot:changed,cached:false).isEmpty)
    }
    func testReviewAdditionsAndMutationsAreDetected() throws {
        let first = TodayObservation(try snapshot())
        let approved = TodayObservation(try snapshot(reviews:[approval()]))
        XCTAssertTrue(approved.changes(since:first).contains { $0.contains("yeni inceleme") })
        let stale = TodayObservation(try snapshot(reviews:[approval(stale:true)]))
        XCTAssertTrue(stale.changes(since:approved).contains { $0.contains("inceleme kaydı değişti") })
        XCTAssertTrue(stale.changes(since:approved).contains { $0.contains("artık güncel") })
    }
    func testBaselineBoundAndAccountSeparation() throws {
        var baseline = TodayBaseline()
        for index in 0..<110 { _ = baseline.observe(key:"r#\(index)",snapshot:try snapshot(),cached:false) }
        XCTAssertEqual(baseline.records.count,100)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = SnapshotStore(root:root),origin = URL(string:"https://test.invalid")!
        try store.save(baseline,key:"today-observations-v1",identity:ConnectionIdentity(origin:origin,login:"first"))
        XCTAssertNil(try store.load(TodayBaseline.self,key:"today-observations-v1",identity:ConnectionIdentity(origin:origin,login:"second")))
        XCTAssertEqual(try store.load(TodayBaseline.self,key:"today-observations-v1",identity:ConnectionIdentity(origin:origin,login:"first"))?.records.count,100)
    }
}
