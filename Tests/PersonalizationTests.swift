import XCTest
@testable import KisiselGitea

@MainActor final class PersonalizationTests: XCTestCase {
    var suite: String!
    var defaults: UserDefaults!
    override func setUp() {
        super.setUp(); suite = "test.personalization." + UUID().uuidString
        defaults = UserDefaults(suiteName:suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName:suite); super.tearDown() }
    func testUpgradePreservesExistingAppearanceAndDefaultDashboard() {
        defaults.set("Koyu",forKey:"appearance"); defaults.set("Mercan",forKey:"accent")
        defaults.set(false,forKey:"motion"); defaults.set(["demo|ornek/mobile":"Nane"],forKey:"projectColors")
        let value = Appearance(defaults:defaults)
        XCTAssertEqual(value.mode,"Koyu"); XCTAssertEqual(value.accentName,"Mercan")
        XCTAssertFalse(value.motion); XCTAssertEqual(value.projectColors["demo|ornek/mobile"],"Nane")
        XCTAssertEqual(value.layout.visibleSections,[.queue,.ideas]); XCTAssertEqual(value.layout.startPage,.today)
        XCTAssertNil(defaults.data(forKey:Appearance.personalizationKey))
    }
    func testSavedStyleRestoresFullAppearanceAndUndoSurvivesRestart() throws {
        let first = Appearance(defaults:defaults)
        first.mode = "Koyu"; first.accentName = "Özel"; first.customHex = "4488AA"
        first.layout.todayOrder = [.favorites,.ideas,.queue]; first.layout.hiddenSections = [.queue]
        first.layout.startPage = .projects; first.layout.density = .compact; first.layout.corners = 0
        first.layout.textStyle = .serif; first.projectColors = ["demo|sample/repo":"Nane"]
        let savedSnapshot = first.styleSnapshot
        try first.saveStyle(named:"Akşam")
        first.mode = "Açık"; first.layout = PersonalLayout(); first.projectColors = [:]
        let beforeApply = first.styleSnapshot
        let second = Appearance(defaults:defaults)
        XCTAssertEqual(second.savedStyles.count,1)
        try second.applyStyle(second.savedStyles[0])
        XCTAssertEqual(second.styleSnapshot,savedSnapshot)
        let third = Appearance(defaults:defaults)
        XCTAssertEqual(third.styleSnapshot,savedSnapshot)
        try third.undoStyle()
        XCTAssertEqual(third.styleSnapshot,beforeApply)
        XCTAssertNil(Appearance(defaults:defaults).previousStyle)
        XCTAssertEqual(third.savedStyles.count,1)
    }
    func testUnreadableOrFutureRecordsAreNotSilentlyOverwritten() throws {
        for raw in [Data("not json".utf8),try JSONEncoder().encode(PersonalizationArchive(version:99))] {
            defaults.set(raw,forKey:Appearance.personalizationKey)
            let value = Appearance(defaults:defaults)
            XCTAssertNotNil(value.personalizationError)
            value.layout.startPage = .inbox
            XCTAssertThrowsError(try value.saveStyle(named:"Yeni"))
            XCTAssertEqual(defaults.data(forKey:Appearance.personalizationKey),raw)
            value.recoverPersonalization()
            XCTAssertNil(value.personalizationError)
            XCTAssertEqual(Appearance(defaults:defaults).layout.startPage,.today)
            let backups = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix(Appearance.personalizationKey + ".unreadable.") }.values.compactMap { $0 as? Data }
            XCTAssertTrue(backups.contains(raw))
        }
    }
    func testNamedStyleIsNotOverwrittenAndResetKeepsLibrary() throws {
        let value = Appearance(defaults:defaults)
        value.layout.density = .spacious
        try value.saveStyle(named:"  Çalışma  ")
        XCTAssertThrowsError(try value.saveStyle(named:"Çalışma"))
        XCTAssertEqual(value.savedStyles.count,1)
        try value.resetStyle()
        XCTAssertEqual(value.layout.density,.balanced); XCTAssertEqual(value.savedStyles.count,1)
        try value.undoStyle(); XCTAssertEqual(value.layout.density,.spacious)
        try value.deleteStyle(value.savedStyles[0].id)
        XCTAssertTrue(Appearance(defaults:defaults).savedStyles.isEmpty)
        XCTAssertEqual(value.layout.density,.spacious)
    }
    func testLayoutNormalizesDuplicatesAndSortsWithoutChangingInput() {
        var value = PersonalLayout()
        value.todayOrder = [.ideas,.ideas]; value.corners = -20; value.ideaCount = 999
        let normalized = value.normalized()
        XCTAssertEqual(normalized.todayOrder,[.ideas,.queue,.favorites]); XCTAssertEqual(normalized.corners,0); XCTAssertEqual(normalized.ideaCount,20)
        let projects = [Project.samples[2],Project.samples[0],Project.samples[1]]
        value.projectSort = .favorites
        XCTAssertEqual(value.sortedProjects(projects,favorites:[Project.samples[1].fullName]).map(\.id),[2,1,3])
        value.projectSort = .issues
        XCTAssertEqual(value.sortedProjects(projects,favorites:[]).map(\.id),[1,3,2])
        value.projectSort = .server
        XCTAssertEqual(value.sortedProjects(projects,favorites:[]),projects)
    }
}
