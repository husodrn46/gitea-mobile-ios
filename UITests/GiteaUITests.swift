import XCTest

final class GiteaUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false; app = XCUIApplication()
        app.launchEnvironment["GITEA_TEST_PREFERENCES"] = "test.ui.legacy." + UUID().uuidString
    }
    func shot(_ name: String) { let image = XCTAttachment(screenshot:app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image) }
    func testDarkPRFlowAndGlass() {
        app.launchArguments = ["-appearance","Koyu"]; app.launchArguments += ["--demo-gitea"]; app.launch()
        XCTAssertTrue(app.staticTexts["Önizleme · Örnek veriler"].waitForExistence(timeout:8))
        shot("01-koyu-bugun")
        app.staticTexts["Testler kendiliğinden çalışsın"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["pullTitle"].waitForExistence(timeout:4))
        shot("02-koyu-pr")
        app.buttons["Birleştirmeyi gözden geçir"].tap()
        XCTAssertTrue(app.staticTexts["Önce son bir bakış."].waitForExistence(timeout:3))
        XCTAssertTrue(app.buttons["Anladım"].exists)
        shot("03-birlestirme-onizlemesi")
        app.buttons["Anladım"].tap()
    }
    func testLightAppearanceAndAccent() {
        app.launchArguments = ["-appearance","Açık"]; app.launchArguments += ["--demo-gitea"]; app.launch()
        XCTAssertTrue(app.buttons["appearanceButton"].waitForExistence(timeout:5))
        shot("04-acik-bugun")
        app.buttons["appearanceButton"].tap()
        XCTAssertTrue(app.buttons["Mavi vurgu"].waitForExistence(timeout:3))
        app.buttons["Mavi vurgu"].tap()
        XCTAssertEqual(app.buttons["Mavi vurgu"].value as? String,"Seçili")
        shot("05-gorunum")
        app.buttons["Bitti"].tap()
    }
    func testDraftPersistsAndSearchWorks() {
        app.launchArguments += ["--demo-gitea"]; app.launch()
        XCTAssertTrue(app.buttons["ideaButton"].waitForExistence(timeout:5))
        app.buttons["ideaButton"].tap()
        let field = app.textFields["ideaTitle"]; XCTAssertTrue(field.waitForExistence(timeout:3)); field.tap(); field.typeText("Mobil fikir testi")
        app.buttons["saveIdea"].tap()
        app.terminate();app.launchArguments += ["--demo-gitea"]; app.launch()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Mobil fikir testi"].firstMatch.waitForExistence(timeout:4))
        app.tabBars.buttons["Projeler"].tap()
        shot("06-projeler")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:4));search.tap();search.typeText("OlmayanProje")
        XCTAssertFalse(app.staticTexts["Görev Takibi"].exists)
        shot("07-arama-bos")
    }
    func testEditIdeaAndPreventAccidentalDiscard() {
        app.launchArguments += ["--demo-gitea"]; app.launch()
        app.buttons["ideaButton"].tap()
        let name = "Fikir " + String(UUID().uuidString.prefix(5))
        let field = app.textFields["ideaTitle"]
        XCTAssertTrue(field.waitForExistence(timeout:3)); field.tap(); field.typeText(name)
        app.buttons["Vazgeç"].tap()
        XCTAssertTrue(app.buttons["Yazmaya devam et"].waitForExistence(timeout:3))
        app.buttons["Yazmaya devam et"].tap()
        app.buttons["saveIdea"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout:4))
        app.staticTexts[name].firstMatch.tap()
        app.buttons["editIdea"].tap()
        let edit = app.textFields["ideaTitle"]; XCTAssertTrue(edit.waitForExistence(timeout:3)); edit.tap(); edit.typeText(" tamam")
        app.buttons["saveIdea"].tap()
        XCTAssertTrue(app.staticTexts[name + " tamam"].waitForExistence(timeout:4))
        app.terminate(); app.launchArguments += ["--demo-gitea"]; app.launch(); app.swipeUp()
        XCTAssertTrue(app.staticTexts[name + " tamam"].firstMatch.waitForExistence(timeout:4))
        XCTAssertFalse(app.staticTexts[name].exists)
        shot("10-duzenlenmis-fikir")
    }
    func testRemotePRFilesAndInboxWithFixture() {
        app.launchArguments = ["--fixture-gitea","-appearance","Koyu"]; app.launchArguments += ["--demo-gitea"]; app.launch()
        app.tabBars.buttons["Projeler"].tap()
        app.staticTexts["Mobil"].firstMatch.tap()
        let title = app.staticTexts["Mobil inceleme akışı"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout:5)); title.tap()
        XCTAssertTrue(app.staticTexts["nextActionTitle"].waitForExistence(timeout:5))
        shot("11-gercek-api-akisi-ornek")
        XCTAssertTrue(app.buttons["prFilesShortcut"].isHittable)
        XCTAssertEqual(app.staticTexts["nextActionTitle"].label,"İnceleme senden bekleniyor")
        app.buttons["prFilesShortcut"].tap()
        XCTAssertTrue(app.staticTexts["App.swift"].waitForExistence(timeout:5))
        app.buttons["Kod farkını oku"].tap()
        XCTAssertTrue(app.staticTexts["+newTitle"].waitForExistence(timeout:5))
        let firstLine = app.staticTexts["diffLine-1"]
        XCTAssertLessThan(firstLine.frame.minY,350)
        XCTAssertLessThan(firstLine.frame.minX,35)
        XCTAssertLessThan(firstLine.frame.height,35)
        shot("12-kod-farki")
        app.terminate();app.launchArguments += ["--demo-gitea"]; app.launch();app.tabBars.buttons["Gelen kutusu"].tap()
        XCTAssertTrue(app.staticTexts["Mobil inceleme akışı"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["PR · Okunmamış"].exists)
        shot("13-gelen-kutusu")
        app.buttons["notification-1"].tap()
        XCTAssertTrue(app.staticTexts["nextActionTitle"].waitForExistence(timeout:5))
        XCTAssertTrue(app.navigationBars["PR #7"].exists)
        app.terminate()
        app.launchArguments = ["--fixture-gitea","--fixture-offline","-appearance","Koyu"]
        app.launchArguments += ["--demo-gitea"]; app.launch(); app.tabBars.buttons["Projeler"].tap(); app.staticTexts["Mobil"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Mobil inceleme akışı"].firstMatch.waitForExistence(timeout:5))
        app.staticTexts["Mobil inceleme akışı"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["nextActionTitle"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["freshnessLabel"].label.contains("Çevrimdışı"))
        app.buttons["Kaydın zamanı"].tap()
        XCTAssertTrue(app.buttons["Bitti"].waitForExistence(timeout:3))
        app.buttons["Bitti"].tap()
        shot("14-cevrimdisi-pr")
    }
    func testLongDiffDoesNotWrapAndScrollsHorizontally() {
        app.launchArguments = ["--fixture-gitea","--fixture-long-diff","-appearance","Açık"];app.launchArguments += ["--demo-gitea"]; app.launch()
        app.tabBars.buttons["Gelen kutusu"].tap()
        XCTAssertTrue(app.buttons["notification-1"].waitForExistence(timeout:5));app.buttons["notification-1"].tap()
        XCTAssertTrue(app.buttons["prFilesShortcut"].waitForExistence(timeout:5));app.buttons["prFilesShortcut"].tap()
        XCTAssertTrue(app.buttons["Kod farkını oku"].waitForExistence(timeout:5));app.buttons["Kod farkını oku"].tap()
        let longLine = app.staticTexts["diffLine-6"]
        XCTAssertTrue(longLine.waitForExistence(timeout:4))
        XCTAssertGreaterThan(longLine.frame.width,app.frame.width)
        XCTAssertLessThan(longLine.frame.height,35)
        XCTAssertLessThan(longLine.frame.minY,450)
        shot("15-uzun-kod-satiri")
        let before = longLine.frame.minX
        app.scrollViews["diffScroll"].swipeLeft()
        XCTAssertLessThan(longLine.frame.minX,before)
        shot("16-yatay-kod-kaydirma")
    }
    func testThemeAndMotionPersist() {
        app.launchArguments += ["--demo-gitea"]; app.launch()
        app.buttons["appearanceButton"].tap()
        let picker = app.segmentedControls["themePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout:4))
        picker.buttons["Koyu"].tap()
        let motion = app.switches["motionToggle"]
        if motion.value as? String == "1" { motion.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap() }
        XCTAssertEqual(motion.value as? String,"0")
        app.buttons["Bitti"].tap()
        app.terminate(); app.launchArguments += ["--demo-gitea"]; app.launch()
        app.buttons["appearanceButton"].tap()
        XCTAssertTrue(app.segmentedControls["themePicker"].buttons["Koyu"].isSelected)
        XCTAssertEqual(app.switches["motionToggle"].value as? String,"0")
        shot("09-koyu-tercihler")
        app.switches["motionToggle"].coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap()
        app.buttons["Mor vurgu"].tap()
        app.buttons["Bitti"].tap()
    }
    func testInsecureConnectionFailsBeforeNetwork() {
        app.launchArguments += ["--demo-gitea"]; app.launch(); app.tabBars.buttons["Profil"].tap()
        app.buttons["connectButton"].tap()
        let server = app.textFields["serverField"];XCTAssertTrue(server.waitForExistence(timeout:3))
        server.tap(); let current = server.value as? String ?? "";server.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:current.count));server.typeText("http://example.test")
        let token = app.secureTextFields["tokenField"];token.tap();token.typeText("synthetic-test-only")
        app.buttons["submitConnection"].tap()
        XCTAssertTrue(app.staticTexts["connectionError"].waitForExistence(timeout:5));shot("08-baglanti-hatasi")
    }
}
