import XCTest

/// Reported on the phone: after a few questions the chat sometimes scrolled far below the messages,
/// leaving an empty screen. The newest question and answer must always be on screen.
final class ChatScrollUITests: XCTestCase {
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// On screen = inside the window and not hidden under the composer.
    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, "\(what) missing", file: file, line: line)
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        XCTAssertTrue(frame.maxY > window.minY + 80 && frame.minY < window.maxY - 120,
                      "\(what) is off screen: \(frame) in \(window)", file: file, line: line)
    }

    func testNewestMessagesStayVisible() throws {
        let modelDir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchArguments += ["-UITestInMemoryStore", "-UITestSeedLongChat", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Długa rozmowa'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let last = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Podsumowanie tematu 8'")).firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        assertOnScreen(last, in: app, "last answer after opening")
        screenshot(app, "01-opened")

        let field = app.textFields["Wiadomość"].waitForExistence(timeout: 3) ? app.textFields["Wiadomość"] : app.textViews["Wiadomość"]
        for (n, question) in ["Ile to 2+2? Odpowiedz tylko liczbą.", "Ile to 3+3? Odpowiedz tylko liczbą."].enumerated() {
            field.tap()
            field.typeText(question)
            app.buttons["Wyślij"].tap()

            let asked = app.staticTexts[question]
            XCTAssertTrue(asked.waitForExistence(timeout: 10))
            assertOnScreen(asked, in: app, "question \(n + 1) right after sending")

            let answer = app.staticTexts[n == 0 ? "4" : "6"]
            XCTAssertTrue(answer.waitForExistence(timeout: 1200), "answer \(n + 1) did not appear") // simulator CPU: prefill of the long chat takes minutes
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tok/s'")).element(boundBy: n).waitForExistence(timeout: 60))
            sleep(1) // let the layout settle after the streamed message becomes a stored one
            screenshot(app, "0\(n + 2)-answered")
            assertOnScreen(answer, in: app, "answer \(n + 1)")
            assertOnScreen(asked, in: app, "question \(n + 1) after the answer")
        }
    }
}
