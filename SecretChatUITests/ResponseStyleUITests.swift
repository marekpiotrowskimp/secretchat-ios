import XCTest

/// Settings → Styl odpowiedzi: pick a preset, write a custom style; the new chat shows the active style.
final class ResponseStyleUITests: XCTestCase {
    func testPickPresetAndCustomStyle() throws {
        let modelDir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        app.buttons["Ustawienia"].tap()
        let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Styl odpowiedzi'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.label.contains("Zrównoważony"), "default style: \(entry.label)")
        entry.tap()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Zwięzły'")).firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Zwięzły' AND selected == true")).firstMatch.waitForExistence(timeout: 3))

        // Custom: editor + examples appear; an example fills the editor.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Własny'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Jak model ma do Ciebie mówić?"].waitForExistence(timeout: 3))
        let example = app.buttons.matching(NSPredicate(format: "label CONTAINS 'jakbym miał 12 lat'")).firstMatch
        for _ in 0..<3 where !example.isHittable { app.swipeUp() }
        example.tap()
        let editor = app.textViews["Własny styl"]
        XCTAssertTrue((editor.value as? String)?.contains("jakbym miał 12 lat") == true)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "custom-style"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Styl odpowiedzi' AND label CONTAINS 'Własny'")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Gotowe"].tap()

        // The new chat shows the active style.
        app.buttons["Nowa rozmowa"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["O czym porozmawiamy?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Własny'")).firstMatch.exists)
    }
}
