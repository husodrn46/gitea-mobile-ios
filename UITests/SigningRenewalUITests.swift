import XCTest

final class SigningRenewalUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fixture-gitea","-appearance","Koyu"]
        app.launchEnvironment["GITEA_TEST_PREFERENCES"] = "test.ui.signing." + UUID().uuidString
        app.launchEnvironment["GITEA_SIGNING_FIXTURE"] = "week"
    }
    private func settings() {
        XCTAssertTrue(app.tabBars.buttons["Profil"].waitForExistence(timeout:5))
        app.tabBars.buttons["Profil"].tap()
        app.buttons["signingSettings"].tap()
        XCTAssertTrue(app.switches["signingReminderToggle"].waitForExistence(timeout:5))
    }
    private func toggle() { app.switches["signingReminderToggle"].coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap() }
    private func shot(_ name: String) {
        let image = XCTAttachment(screenshot:app.screenshot()); image.name = "v9-" + name; image.lifetime = .keepAlways; add(image)
    }
    func testSystemPermissionSchedulesBothRemindersAndDisablePersists() {
        addUIInterruptionMonitor(withDescription:"Bildirim izni") { alert in
            for title in ["Allow","İzin Ver","İzin ver"] where alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            return false
        }
        app.launch(); settings()
        let turkishMonth = Date().addingTimeInterval(7 * 86400).formatted(.dateTime.month(.wide).locale(Locale(identifier:"tr_TR")))
        XCTAssertTrue(app.staticTexts["signingExpiration"].label.contains(turkishMonth))
        toggle()
        let springboard = XCUIApplication(bundleIdentifier:"com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout:3) {
            let alert = springboard.alerts.firstMatch
            for title in ["Allow","İzin Ver","İzin ver"] where alert.buttons[title].exists { alert.buttons[title].tap(); break }
        }
        XCTAssertTrue(app.otherElements["gitea.signing.two-days"].waitForExistence(timeout:5) || app.staticTexts["gitea.signing.two-days"].exists)
        XCTAssertTrue(app.otherElements["gitea.signing.one-day"].exists || app.staticTexts["gitea.signing.one-day"].exists)
        XCTAssertFalse(app.staticTexts["signingReminderError"].exists)
        shot("01-hatirlatmalar-zamanlandi")
        toggle()
        XCTAssertEqual(app.switches["signingReminderToggle"].value as? String,"0")
        app.terminate(); app.launch(); settings()
        XCTAssertEqual(app.switches["signingReminderToggle"].value as? String,"0")
    }
    func testMissingProfileDoesNotInventExpirationAndTokenHelpIsAvailable() {
        app.launchEnvironment["GITEA_SIGNING_FIXTURE"] = "missing"
        app.launch(); settings()
        XCTAssertFalse(app.staticTexts["signingExpiration"].exists)
        XCTAssertFalse(app.switches["signingReminderToggle"].isEnabled)
        shot("02-profil-yok")
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["connectButton"].tap()
        let server = app.textFields["serverField"]; server.tap(); server.typeText("https://git.example.com")
        XCTAssertTrue(app.buttons["createAccessToken"].waitForExistence(timeout:3) || app.links["createAccessToken"].exists)
        XCTAssertTrue(app.secureTextFields["tokenField"].exists)
        shot("03-erisim-anahtari-yardimi")
    }
    func testExpiringNoticeNavigatesWithLargeText() {
        app.launchEnvironment["GITEA_SIGNING_FIXTURE"] = "soon"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["signingExpiryNotice"].waitForExistence(timeout:5))
        app.buttons["signingExpiryNotice"].tap()
        XCTAssertTrue(app.staticTexts["signingExpiration"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["signingFixture"].exists)
        shot("04-buyuk-yazi-yaklasan-sure")
        for _ in 0..<6 where !app.switches["signingReminderToggle"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.switches["signingReminderToggle"].isHittable)
        shot("05-buyuk-yazi-hatirlatma")
    }
}
