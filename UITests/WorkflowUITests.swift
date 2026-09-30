import XCTest
final class WorkflowUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false; app = XCUIApplication()
        app.launchEnvironment["GITEA_TEST_PREFERENCES"] = "test.ui.workflow." + UUID().uuidString
    }
    func launch(_ extra: [String] = []) { app.launchArguments = ["--fixture-gitea","-appearance","Açık"] + extra; app.launch() }
    func shot(_ name: String) { let a = XCTAttachment(screenshot:app.screenshot()); a.name = "v6-"+name; a.lifetime = .keepAlways; add(a) }
    func project() {
        app.tabBars.buttons["Projeler"].tap()
        XCTAssertTrue(app.staticTexts["Mobil"].firstMatch.waitForExistence(timeout:5));app.staticTexts["Mobil"].firstMatch.tap()
    }
    func selectToday() {
        app.buttons["todayProjects"].tap()
        let toggle = app.switches["ornek/mobile"]
        XCTAssertTrue(toggle.waitForExistence(timeout:5))
        if toggle.value as? String == "0" { toggle.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.5)).tap() }
        XCTAssertEqual(toggle.value as? String,"1")
        app.buttons["Uygula"].tap()
        XCTAssertTrue(app.staticTexts["Mobil inceleme akışı"].firstMatch.waitForExistence(timeout:8))
    }
    func testTodayAndChangedCommitAreLinked() {
        launch(["--fixture-reset-history"]); selectToday()
        XCTAssertTrue(app.staticTexts["Doğrulanmış yeni değişiklik yok."].exists)
        XCTAssertFalse(app.staticTexts["todayChangesTitle"].exists)
        XCTAssertEqual(app.staticTexts["todaySummary"].label,"1 inceleme senden bekleniyor")
        XCTAssertTrue(app.staticTexts["İncelemen bekleniyor"].isHittable)
        app.buttons["todaySource-7"].tap()
        XCTAssertTrue(app.buttons["Bitti"].waitForExistence(timeout:4))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","Atanmış: Codex")).firstMatch.exists)
        app.buttons["Bitti"].tap()
        shot("01-bugun")
        app.terminate(); launch(["--fixture-updated"])
        XCTAssertTrue(app.staticTexts["todayChangesTitle"].waitForExistence(timeout:8))
        app.staticTexts["todayChangesTitle"].tap()
        XCTAssertTrue(app.buttons["todayAcknowledge"].waitForExistence(timeout:3))
        XCTAssertEqual(app.staticTexts["todaySummary"].label,"1 inceleme senden bekleniyor · 1 PR testte")
        shot("02-ben-yokken")
        app.buttons["todayAcknowledge"].tap()
        XCTAssertTrue(app.staticTexts["Doğrulanmış yeni değişiklik yok."].waitForExistence(timeout:3))
        app.staticTexts["Mobil inceleme akışı"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["waitingSummary"].waitForExistence(timeout:5))
        shot("03-pr-ozeti")
        let segments = app.segmentedControls["prSections"]
        segments.buttons["Konuşma"].tap()
        XCTAssertTrue(app.staticTexts["Bu akışı telefonda deneyelim."].waitForExistence(timeout:5))
        shot("04-pr-konusma")
        segments.buttons["Dosyalar"].tap()
        app.buttons["Dosyaları ve kod farkını aç"].tap()
        XCTAssertTrue(app.staticTexts["App.swift"].waitForExistence(timeout:5))
    }
    func testIdeaCreatesIssueAndKeepsLocalDraft() {
        launch()
        app.buttons["ideaButton"].tap()
        let title = "Telefon fikri " + String(UUID().uuidString.prefix(5))
        let field = app.textFields["ideaTitle"];XCTAssertTrue(field.waitForExistence(timeout:4));field.tap();field.typeText(title)
        app.buttons["saveIdea"].tap()
        for _ in 0..<5 { if app.staticTexts[title].isHittable { break };app.swipeUp() }
        app.staticTexts[title].tap()
        app.buttons["publishIdea"].tap()
        XCTAssertTrue(app.textFields["issueTitle"].waitForExistence(timeout:5))
        // Saved idea defaults to the fixture project from the local idea picker.
        if !app.buttons["createIssue"].isEnabled {
            app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Depo")).firstMatch.tap()
            app.buttons["ornek/mobile"].tap()
        }
        for _ in 0..<4 { if app.buttons["createIssue"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["createIssue"].isHittable)
        shot("05-fikir-konu")
        app.buttons["createIssue"].tap()
        XCTAssertTrue(app.buttons["Konuşmayı aç"].waitForExistence(timeout:8))
        shot("06-konu-kaydedildi")
        app.buttons["Konuşmayı aç"].tap()
        XCTAssertTrue(app.navigationBars["Konu #99"].waitForExistence(timeout:5))
        app.terminate();launch();for _ in 0..<5 { if app.staticTexts[title].isHittable { break };app.swipeUp() }
        XCTAssertTrue(app.staticTexts[title].exists)
    }
    func testIssueReadAndComment() {
        launch();project();app.buttons["projectIssues"].tap()
        XCTAssertTrue(app.buttons["issue-12"].waitForExistence(timeout:5));app.buttons["issue-12"].tap()
        XCTAssertTrue(app.staticTexts["Bu akışı telefonda deneyelim."].waitForExistence(timeout:5))
        shot("07-konu")
        XCTAssertFalse(app.textViews["commentEditor"].exists)
        let expand = app.buttons["expandComment"]
        for _ in 0..<5 { if expand.isHittable { break };app.swipeUp() }
        expand.tap()
        let editor = app.textViews["commentEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout:3))
        editor.tap();editor.typeText("Telefon görüşü " + String(UUID().uuidString.prefix(5)))
        app.swipeUp()
        app.buttons["sendComment"].tap()
        XCTAssertTrue(app.staticTexts["Yorum sunucuya kaydedildi"].waitForExistence(timeout:8))
        shot("08-yorum-kaydedildi")
    }
    func testCollapsedCommentPreservesDraftAcrossRestart() {
        launch();project();app.buttons["projectIssues"].tap()
        XCTAssertTrue(app.buttons["issue-12"].waitForExistence(timeout:5));app.buttons["issue-12"].tap()
        let expand = app.buttons["expandComment"]
        for _ in 0..<5 { if expand.isHittable { break };app.swipeUp() }
        XCTAssertFalse(app.textViews["commentEditor"].exists)
        expand.tap()
        let editor = app.textViews["commentEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout:4))
        let text = "Saklanan görüş " + String(UUID().uuidString.prefix(5))
        editor.tap();editor.typeText(text)
        app.buttons["collapseComment"].tap()
        XCTAssertFalse(editor.exists)
        XCTAssertEqual(expand.label,"Taslağına devam et")
        shot("13-kucuk-yorum-taslagi")
        app.terminate();launch();project();app.buttons["projectIssues"].tap()
        XCTAssertTrue(app.buttons["issue-12"].waitForExistence(timeout:5));app.buttons["issue-12"].tap()
        for _ in 0..<5 { if expand.isHittable { break };app.swipeUp() }
        XCTAssertFalse(editor.exists);expand.tap()
        XCTAssertTrue(editor.waitForExistence(timeout:4))
        XCTAssertTrue((editor.value as? String ?? "").contains(text))
        shot("14-acilan-yorum-taslagi")
        // Leave the synthetic comment draft empty without dispatching it.
        editor.tap();let content = editor.value as? String ?? ""
        editor.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:content.count))
        app.buttons["collapseComment"].tap()
    }
    func testIssueNotificationOpensNativeConversation() {
        launch();app.tabBars.buttons["Gelen kutusu"].tap()
        XCTAssertTrue(app.buttons["notification-2"].waitForExistence(timeout:5))
        app.buttons["notification-2"].tap()
        XCTAssertTrue(app.navigationBars["Konu #12"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Bu akışı telefonda deneyelim."].waitForExistence(timeout:5))
        shot("11-konu-bildirimi")
    }
    func testProjectAccentPersists() {
        launch();project()
        app.buttons["projectAccent"].tap()
        app.buttons["Nane"].tap()
        XCTAssertTrue(app.buttons["projectAccent"].label.contains("Nane"))
        shot("12-proje-rengi")
        app.terminate();launch();project()
        XCTAssertTrue(app.buttons["projectAccent"].label.contains("Nane"))
    }
    func testLargeTextAndDarkProjectAccent() {
        launch(["-appearance","Koyu","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"])
        project()
        XCTAssertTrue(app.buttons["projectIssues"].waitForExistence(timeout:5))
        shot("09-buyuk-yazi-koyu")
        app.buttons["projectIssues"].tap()
        XCTAssertTrue(app.buttons["issue-12"].waitForExistence(timeout:5))
        shot("10-buyuk-yazi-konular")
    }
}
