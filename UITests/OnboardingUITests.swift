import XCTest

final class OnboardingUITests: XCTestCase {
    func testFreshInstallHasNoPersonalServerAndExplicitDemoSurvivesRestart() {
        let app = XCUIApplication()
        app.launchEnvironment["GITEA_TEST_PREFERENCES"] = "test.ui.product." + UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["welcomeConnect"].waitForExistence(timeout:5))
        XCTAssertFalse(app.tabBars.buttons["Projeler"].exists)
        app.buttons["welcomeConnect"].tap()
        let server = app.textFields["serverField"]
        XCTAssertTrue(server.waitForExistence(timeout:3))
        XCTAssertEqual(server.value as? String,"https://git.example.com") // placeholder; no saved server
        XCTAssertFalse(app.buttons["submitConnection"].isEnabled)
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.buttons["welcomeDemo"].waitForExistence(timeout:3))
        app.buttons["welcomeDemo"].tap()
        XCTAssertTrue(app.staticTexts["Önizleme · Örnek veriler"].waitForExistence(timeout:5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Projeler"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["welcomeConnect"].exists)
        let image = XCTAttachment(screenshot:app.screenshot()); image.name = "general-client-demo"; image.lifetime = .keepAlways; add(image)
    }
}
