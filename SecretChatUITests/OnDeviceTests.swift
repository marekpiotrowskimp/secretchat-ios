import XCTest

/// Runs only on a physical iPhone with the model already downloaded in the app:
/// a real chat turn, the model picker recommendation and the diagnostics benchmarks.
/// Results go to Documents/diagnostics.log (`scripts/device.sh pull-log`).
final class OnDeviceTests: XCTestCase {
    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("physical device only")
        #endif
        continueAfterFailure = false
    }

    /// Real web search on the phone (DuckDuckGo → Wikipedia fallback) with the full consent flow.
    func testRealWebSearchOnDevice() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        XCTAssertTrue(app.buttons["Ustawienia"].waitForExistence(timeout: 30))
        app.buttons["Ustawienia"].tap()
        let toggle = app.switches["Wyszukiwanie w internecie"]
        scroll(app, to: toggle)
        toggle.switches.firstMatch.tap()
        app.buttons["Rozumiem, włącz wyszukiwanie"].tap()
        app.buttons["Gotowe"].tap()

        app.buttons["Nowa rozmowa"].firstMatch.tap()
        let field = app.textFields["Wiadomość"].waitForExistence(timeout: 5) ? app.textFields["Wiadomość"] : app.textViews["Wiadomość"]
        field.tap()
        field.typeText("Jaki jest dzisiaj kurs euro w złotówkach?")
        app.buttons["Wyślij"].tap()

        XCTAssertTrue(app.staticTexts["Model chce przeszukać internet"].waitForExistence(timeout: 180), "model did not ask to search")
        screenshot(app, "device-web-consent")
        app.buttons["Szukaj…"].tap()
        app.buttons["Tak, szukaj w internecie"].tap()

        let badge = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Odpowiedź z internetu'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 300), "no answer from the internet")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tok/s'")).firstMatch.waitForExistence(timeout: 120))
        badge.tap()
        screenshot(app, "device-web-answer")
    }

    /// Lazy forms only create rows that are on screen — swipe until the element exists.
    private func scroll(_ app: XCUIApplication, to element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "could not scroll to \(element)")
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testChatPickerAndBenchmarksOnDevice() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        // Model is downloaded → conversation list, not onboarding.
        XCTAssertTrue(app.staticTexts["Brak rozmów"].waitForExistence(timeout: 30), "model not ready on device")
        app.buttons["Nowa rozmowa"].firstMatch.tap()
        let field = app.textFields["Wiadomość"].waitForExistence(timeout: 5) ? app.textFields["Wiadomość"] : app.textViews["Wiadomość"]
        field.tap()
        field.typeText("Ile to 2+2? Odpowiedz tylko liczbą.")
        app.buttons["Wyślij"].tap()
        XCTAssertTrue(app.staticTexts["4"].waitForExistence(timeout: 240), "no answer from the model on device")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tok/s'")).firstMatch.waitForExistence(timeout: 60))
        screenshot(app, "device-chat")

        // Model picker: the 12B model is the recommendation on a 12 GB phone.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Ustawienia"].tap()
        let modelLink = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Model,")).firstMatch
        scroll(app, to: modelLink)
        modelLink.tap()
        XCTAssertTrue(app.staticTexts["Najlepszy dla Twojego telefonu"].waitForExistence(timeout: 5))
        screenshot(app, "device-picker")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Diagnostics: benchmark + image test, written to diagnostics.log.
        let diagnostics = app.buttons["Diagnostyka i testy wydajności"]
        scroll(app, to: diagnostics)
        diagnostics.tap()
        for test in ["Benchmark (~500 + 256 tok)", "Test obrazu"] {
            let button = app.buttons[test]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            // Buttons are disabled while a test runs; wait for start, then for the end.
            let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: button)
            XCTAssertEqual(XCTWaiter().wait(for: [started], timeout: 10), .completed, "\(test) did not start")
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: button)
            XCTAssertEqual(XCTWaiter().wait(for: [finished], timeout: 600), .completed, "\(test) did not finish")
        }
        screenshot(app, "device-diagnostics")
    }
}
