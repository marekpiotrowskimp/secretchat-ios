import XCTest

/// Web search UX: off by default, warning before enabling, consent before every search, 🌐 + sources.
/// Uses the offline fake researcher (GEMMA_FAKE_WEB=1) and the real model.
final class WebSearchUITests: XCTestCase {
    func testEnableWarnConsentAndAnswerWithSources() throws {
        let modelDir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchEnvironment["GEMMA_FAKE_WEB"] = "1"
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        // Settings: off by default; enabling shows the privacy warning first.
        XCTAssertTrue(app.buttons["Ustawienia"].waitForExistence(timeout: 10))
        app.buttons["Ustawienia"].tap()
        let toggle = app.switches["Wyszukiwanie w internecie"]
        scroll(app, to: toggle)
        XCTAssertEqual(toggle.value as? String, "0", "web search must be off by default")
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["SecretChat jest zaprojektowany do pracy bez internetu"].waitForExistence(timeout: 5))
        attach(app, "web-warning")
        app.buttons["Rozumiem, włącz wyszukiwanie"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["Gotowe"].tap()

        // Ask about a current event → the model asks to search.
        app.buttons["Nowa rozmowa"].firstMatch.tap()
        let field = app.textFields["Wiadomość"].waitForExistence(timeout: 5) ? app.textFields["Wiadomość"] : app.textViews["Wiadomość"]
        field.tap()
        field.typeText("Kto wygrał wczorajszy mecz Legii Warszawa?")
        app.buttons["Wyślij"].tap()

        XCTAssertTrue(app.staticTexts["Model chce przeszukać internet"].waitForExistence(timeout: 300), "no consent card")
        attach(app, "web-consent")
        app.buttons["Szukaj…"].tap()
        XCTAssertTrue(app.staticTexts["Czy na pewno przeszukać internet?"].waitForExistence(timeout: 5))
        attach(app, "web-are-you-sure")
        app.buttons["Tak, szukaj w internecie"].tap()

        let badge = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Odpowiedź z internetu'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 300), "answer not marked as coming from the internet")
        attach(app, "web-answer")
        badge.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Legia – Lech 3:1'")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "web-sources")
    }

    private func scroll(_ app: XCUIApplication, to element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
