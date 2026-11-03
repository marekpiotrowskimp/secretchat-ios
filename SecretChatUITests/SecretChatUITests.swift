import XCTest

/// Drives the real app in the simulator with the real model (GEMMA_MODEL_DIR).
final class SecretChatUITests: XCTestCase {
    private var modelDir: String {
        // The test runner's environment carries the scheme variable; forward it to the app.
        ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
    }

    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "pl" ? "pl_PL" : "en_US"]
        app.launch()
        return app
    }

    /// A vertical-axis TextField may surface as a text view.
    private func composer(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["Wiadomość"]
        return field.waitForExistence(timeout: 3) ? field : app.textViews["Wiadomość"]
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testChatFlowInPolish() throws {
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = launch(language: "pl")

        // Empty state → new conversation.
        XCTAssertTrue(app.staticTexts["Brak rozmów"].waitForExistence(timeout: 10))
        screenshot(app, "01-empty")
        app.buttons["Nowa rozmowa"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["O czym porozmawiamy?"].waitForExistence(timeout: 5))
        // New-chat summary reflects the active model and state (simulator host: 12B selected, web off).
        let summary = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Gemma 4 12B' AND label CONTAINS 'W pełni offline'")).firstMatch
        XCTAssertTrue(summary.exists, "new chat must show the model actually in use")
        screenshot(app, "01b-new-chat")
        let field = composer(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Ile to 2+2? Odpowiedz tylko liczbą.")
        screenshot(app, "02-typed")
        app.buttons["Wyślij"].tap()

        // The model loads (first time) and answers.
        let answer = app.staticTexts["4"]
        XCTAssertTrue(answer.waitForExistence(timeout: 240), "model answer did not appear")
        // Stats line appears once generation finished.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tok/s'")).firstMatch.waitForExistence(timeout: 30))
        screenshot(app, "03-answer")

        // Follow-up with markdown list.
        field.tap()
        field.typeText("Wymień trzy kolory jako listę punktowaną.")
        app.buttons["Wyślij"].tap()
        XCTAssertTrue(app.staticTexts["•"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["Wyślij"].waitForExistence(timeout: 120)) // generation done → send button back
        screenshot(app, "04-markdown")

        // Back to the list: the conversation is titled after the first message.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Ile to 2+2? Odpowiedz tylko liczbą."].waitForExistence(timeout: 5))
        screenshot(app, "05-list")

        // Settings sheet.
        app.buttons["Ustawienia"].tap()
        XCTAssertTrue(app.staticTexts["Prompt systemowy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Tryb myślenia"].exists)
        screenshot(app, "06-settings")
        app.buttons["Gotowe"].tap()
    }

    func testEnglishLocalization() throws {
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = launch(language: "en")
        XCTAssertTrue(app.staticTexts["No Conversations"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["System Prompt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Thinking Mode"].exists)
        screenshot(app, "en-settings")
    }
}
