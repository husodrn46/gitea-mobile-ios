import XCTest

final class IssueResolutionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testExplicitReadRemovesOnlyConfirmedNotification() {
        let app = XCUIApplication(); app.launchArguments = ["--fixture-gitea"]
        app.launchEnvironment["GITEA_TEST_PREFERENCES"] = "test.ui.notification."+UUID().uuidString
        app.launch(); app.tabBars.buttons["Gelen kutusu"].tap()
        let button = app.buttons["markRead-2"]
        XCTAssertTrue(button.waitForExistence(timeout:5)); button.tap()
        XCTAssertTrue(app.buttons["markRead-1"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["markRead-2"].exists)
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "explicit-notification-read"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testSavedAccountPickerShowsServerAndChangesSelectedAccount() {
        let app = XCUIApplication(); app.launchArguments = ["--fixture-gitea","--fixture-accounts"]
        app.launchEnvironment["GITEA_TEST_PREFERENCES"] = "test.ui.accounts."+UUID().uuidString
        app.launch(); app.tabBars.buttons["Profil"].tap(); app.buttons["savedAccounts"].tap()
        XCTAssertTrue(app.staticTexts["reader"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["https://second-fixture.invalid"].exists)
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "saved-account-picker"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons.matching(identifier:"Hesabı seç").element(boundBy:1).tap()
        XCTAssertTrue(app.staticTexts["reader"].firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["reconnectLive"].exists)
    }
    func testTodayLoadsDetailsInGroupsAndReportsUnverifiedPRs() {
        let app = XCUIApplication(); app.launchArguments = ["--fixture-gitea","--fixture-large-pulls"]
        app.launchEnvironment["GITEA_TEST_PREFERENCES"] = "test.ui.paging."+UUID().uuidString
        app.launch()
        app.buttons["todayProjects"].tap()
        let toggle = app.switches["ornek/mobile"]
        XCTAssertTrue(toggle.waitForExistence(timeout:4))
        if toggle.value as? String == "0" { toggle.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap() }
        app.buttons["Uygula"].tap()
        let more = app.buttons["moreTodayDetails"]
        XCTAssertTrue(more.waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["40 yüklenen PR henüz doğrulanmadı. Bu PR’lar hazır veya sağlıklı sayılmıyor."].exists)
        more.tap()
        XCTAssertTrue(app.staticTexts["30 yüklenen PR henüz doğrulanmadı. Bu PR’lar hazır veya sağlıklı sayılmıyor."].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["moreTodayPulls"].exists)
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "bounded-today-queue"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
