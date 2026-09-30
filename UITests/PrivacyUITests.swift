import XCTest

final class PrivacyUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false; app = XCUIApplication()
        app.launchArguments = ["--fixture-gitea","-appearance","Koyu"]
        app.launchEnvironment["GITEA_TEST_PREFERENCES"] = "test.ui.privacy." + UUID().uuidString
    }
    func settings() {
        app.tabBars.buttons["Profil"].tap()
        XCTAssertTrue(app.buttons["privacySettings"].waitForExistence(timeout:5)); app.buttons["privacySettings"].tap()
        XCTAssertTrue(app.switches["personalLock"].waitForExistence(timeout:3))
    }
    func tapSwitch(_ id: String) {
        let toggle = app.switches[id]
        if toggle.switches.firstMatch.exists { toggle.switches.firstMatch.tap() }
        else { toggle.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap() }
    }
    func expectSwitch(_ id: String,_ enabled: Bool) {
        let predicate = NSPredicate(format:"value == %@",enabled ? "1" : "0")
        expectation(for:predicate,evaluatedWith:app.switches[id]); waitForExpectations(timeout:5)
    }
    func shot(_ name: String) {
        let image = XCTAttachment(screenshot:app.screenshot()); image.name = "v8-" + name; image.lifetime = .keepAlways; add(image)
    }
    func testBackgroundLockCoversOpenSheetAndPreservesDraft() {
        app.launchEnvironment["GITEA_AUTH_FIXTURE"] = "success,fail,success"
        app.launch(); settings(); tapSwitch("personalLock"); expectSwitch("personalLock",true)
        shot("01-kilit-ayarlari")
        app.navigationBars.buttons.element(boundBy:0).tap(); app.tabBars.buttons["Bugün"].tap()
        app.buttons["ideaButton"].tap()
        let field = app.textFields["ideaTitle"]
        XCTAssertTrue(field.waitForExistence(timeout:3)); field.tap()
        let secret = "Saklı fikir " + String(UUID().uuidString.prefix(6)); field.typeText(secret)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for:.runningBackground,timeout:5))
        app.activate()
        XCTAssertTrue(app.buttons["unlockApp"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["lockError"].exists)
        XCTAssertFalse(app.textFields["ideaTitle"].exists)
        XCTAssertFalse(app.debugDescription.contains(secret))
        shot("02-kilitli-acik-form")
        app.buttons["unlockApp"].tap()
        XCTAssertTrue(field.waitForExistence(timeout:5)); XCTAssertEqual(field.value as? String,secret)
        shot("03-korunan-fikir")
        app.buttons["Vazgeç"].tap(); app.alerts.buttons["Değişiklikleri sil"].tap()
    }
    func testRestartRequiresUnlockAndCancelledDisableStaysEnabled() {
        app.launchEnvironment["GITEA_AUTH_FIXTURE"] = "success,cancel,success"
        app.launch(); settings(); tapSwitch("personalLock"); expectSwitch("personalLock",true)
        tapSwitch("autoUnlock"); expectSwitch("autoUnlock",false)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["unlockApp"].waitForExistence(timeout:5))
        XCTAssertFalse(app.tabBars.buttons["Profil"].exists)
        shot("04-yeniden-acilista-kilit")
        app.buttons["unlockApp"].tap(); settings()
        tapSwitch("personalLock"); expectSwitch("personalLock",true)
        XCTAssertTrue(app.staticTexts["privacyError"].waitForExistence(timeout:3))
        shot("05-kapatma-iptali")
        tapSwitch("personalLock"); expectSwitch("personalLock",false)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Profil"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["unlockApp"].exists)
    }
}
