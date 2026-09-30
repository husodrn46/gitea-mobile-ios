import XCTest

final class PersonalizationUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["GITEA_TEST_PREFERENCES"] = "test.ui.personalization." + UUID().uuidString
    }
    func shot(_ name: String) {
        let image = XCTAttachment(screenshot:app.screenshot()); image.name = "v7-" + name; image.lifetime = .keepAlways; add(image)
    }
    func openSettings() {
        app.tabBars.buttons["Profil"].tap()
        XCTAssertTrue(app.buttons["profileAppearance"].waitForExistence(timeout:5)); app.buttons["profileAppearance"].tap()
    }
    func openPage(_ id: String) {
        let entry = app.buttons[id]
        for _ in 0..<4 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout:3)); entry.tap()
    }
    func back() { app.navigationBars.buttons.element(boundBy:0).tap() }
    func toggle(_ id: String,to on: Bool) {
        let item = app.switches[id]
        for _ in 0..<5 { if item.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(item.exists)
        if (item.value as? String == "1") != on { item.switches.firstMatch.exists ? item.switches.firstMatch.tap() : item.coordinate(withNormalizedOffset:CGVector(dx:0.84,dy:0.5)).tap() }
        XCTAssertEqual(item.value as? String,on ? "1" : "0")
    }
    func testLayoutCardsSavedStyleAndRestart() {
        app.launchArguments += ["--demo-gitea"]; app.launch(); openSettings(); openPage("cardSettings")
        app.segmentedControls["densityPicker"].buttons["Sık"].tap()
        app.segmentedControls["textStylePicker"].buttons["Serif"].tap()
        app.sliders["cornerSlider"].adjust(toNormalizedSliderPosition:0)
        shot("01-kart-onizleme")
        back(); openPage("layoutSettings")
        app.buttons["startPagePicker"].tap(); app.collectionViews.buttons["Projeler"].tap()
        toggle("section-favorites",to:true)
        let favorite = app.buttons["Reorder Favori projelerin"]
        let queue = app.buttons["Reorder İş kuyruğun"]
        XCTAssertTrue(favorite.exists); XCTAssertTrue(queue.exists)
        favorite.press(forDuration:0.5,thenDragTo:queue)
        XCTAssertLessThan(favorite.frame.minY,queue.frame.minY)
        shot("02-bolum-sirasi")
        toggle("defaultFavorites",to:true)
        back(); openPage("savedStyles")
        app.textFields["styleName"].tap(); app.textFields["styleName"].typeText("Benim düzenim")
        app.buttons["saveStyle"].tap()
        XCTAssertTrue(app.staticTexts["Düzen kaydedildi."].waitForExistence(timeout:3))
        app.terminate(); app.launchArguments += ["--demo-gitea"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Projeler"].isSelected)
        XCTAssertTrue(app.staticTexts["Görev Takibi"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["Kişisel Site"].exists)
        app.tabBars.buttons["Bugün"].tap()
        XCTAssertTrue(app.staticTexts["todayFavoritesTitle"].waitForExistence(timeout:3))
        XCTAssertLessThan(app.staticTexts["todayFavoritesTitle"].frame.minY,app.staticTexts["Sıra kimde?"].frame.minY)
        shot("03-kisisel-bugun")
        openSettings(); openPage("cardSettings")
        XCTAssertTrue(app.segmentedControls["densityPicker"].buttons["Sık"].isSelected)
        XCTAssertTrue(app.segmentedControls["textStylePicker"].buttons["Serif"].isSelected)
        app.segmentedControls["densityPicker"].buttons["Ferah"].tap()
        back(); openPage("savedStyles")
        app.buttons["applyStyle-Benim düzenim"].tap()
        XCTAssertTrue(app.staticTexts["Benim düzenim uygulandı."].waitForExistence(timeout:3))
        shot("04-kayitli-duzen")
        back(); openPage("cardSettings")
        XCTAssertTrue(app.segmentedControls["densityPicker"].buttons["Sık"].isSelected)
        back(); openPage("savedStyles"); app.buttons["undoStyle"].tap()
        back(); openPage("cardSettings")
        XCTAssertTrue(app.segmentedControls["densityPicker"].buttons["Ferah"].isSelected)
    }
    func testDashboardVisibilityAndDefaultFilter() {
        app.launchArguments = ["--fixture-gitea"]
        app.launchArguments += ["--demo-gitea"]; app.launch(); openSettings(); openPage("layoutSettings")
        toggle("showDailySummary",to:false)
        toggle("showChanges",to:false)
        app.buttons["queueFilterPicker"].tap(); app.buttons["Testleri süren"].tap()
        back(); app.buttons["Bitti"].tap(); app.tabBars.buttons["Bugün"].tap()
        XCTAssertTrue(app.staticTexts["Bu filtrede PR yok."].waitForExistence(timeout:6))
        XCTAssertFalse(app.staticTexts["todaySummary"].exists)
        XCTAssertFalse(app.staticTexts["todayNoChanges"].exists)
        app.buttons["Tümü"].tap()
        XCTAssertTrue(app.staticTexts["Mobil inceleme akışı"].waitForExistence(timeout:3))
        openSettings(); openPage("layoutSettings")
        toggle("section-queue",to:false); toggle("section-ideas",to:false)
        back(); app.buttons["Bitti"].tap(); app.tabBars.buttons["Bugün"].tap()
        XCTAssertTrue(app.buttons["Bölümleri seç"].waitForExistence(timeout:3))
        XCTAssertTrue(app.buttons["appearanceButton"].exists)
        shot("05-bos-duzen-erisimi")
    }
    func testLargeTypeCardControlsRemainReachable() {
        app.launchArguments = ["--fixture-gitea","-appearance","Koyu","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchArguments += ["--demo-gitea"]; app.launch(); openSettings(); openPage("cardSettings")
        XCTAssertTrue(app.staticTexts["Kendi çalışma alanın"].waitForExistence(timeout:3))
        shot("06-buyuk-yazi-onizleme")
        let density = app.segmentedControls["densityPicker"]
        for _ in 0..<5 { if density.buttons["Ferah"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(density.buttons["Ferah"].isHittable)
        density.buttons["Ferah"].tap()
        XCTAssertTrue(density.buttons["Ferah"].isSelected)
        shot("07-buyuk-yazi-kontroller")
    }
}
