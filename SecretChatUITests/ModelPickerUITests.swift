import XCTest

/// Model picker on simulated phones with nothing downloaded.
final class ModelPickerUITests: XCTestCase {
    private func launch(ramGB: Int, name: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = FileManager.default.temporaryDirectory.appending(path: "empty-models-\(UUID().uuidString)").path
        app.launchEnvironment["GEMMA_DEVICE_RAM_GB"] = "\(ramGB)"
        app.launchEnvironment["GEMMA_DEVICE_NAME"] = name
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()
        return app
    }

    private func card(_ app: XCUIApplication, _ predicate: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: predicate)).firstMatch
    }

    /// iPhone 17 Pro Max: E4B is the recommendation, 12B is available but experimental.
    func testTwelveGBPhoneRecommendsE4BAndMarks12BExperimental() throws {
        let app = launch(ramGB: 12, name: "iPhone 17 Pro Max")
        XCTAssertTrue(app.staticTexts["Twój telefon: iPhone 17 Pro Max · 12 GB RAM"].waitForExistence(timeout: 10))
        XCTAssertTrue(card(app, "label CONTAINS 'Gemma 4 E4B' AND label CONTAINS 'Najlepszy'").exists)
        XCTAssertTrue(app.buttons["Pobierz Gemma 4 E4B"].exists)
        XCTAssertTrue(card(app, "label CONTAINS 'Gemma 4 12B' AND label CONTAINS 'Eksperymentalny'").exists)
        XCTAssertFalse(app.staticTexts["Twój telefon może nie podołać temu modelowi"].exists, "12B fits, it is only experimental")
        attach(app, "picker-12gb")

        card(app, "label BEGINSWITH 'Gemma 4 12B'").tap()
        app.buttons["Pobierz Gemma 4 12B"].tap()
        XCTAssertTrue(app.staticTexts["Ten model jest eksperymentalny na Twoim telefonie"].waitForExistence(timeout: 5))
        attach(app, "picker-12gb-confirm")
        app.buttons["Wybierz Gemma 4 E4B"].tap()
        XCTAssertTrue(app.buttons["Pobierz Gemma 4 E4B"].waitForExistence(timeout: 5))
    }

    /// 8 GB phone: E2B recommended, E4B experimental, 12B too large (with a suggested phone).
    func testEightGBPhone() throws {
        let app = launch(ramGB: 8, name: "iPhone 16")
        XCTAssertTrue(app.staticTexts["Twój telefon: iPhone 16 · 8 GB RAM"].waitForExistence(timeout: 10))
        XCTAssertTrue(card(app, "label CONTAINS 'Gemma 4 E2B' AND label CONTAINS 'Najlepszy'").exists)
        XCTAssertTrue(card(app, "label CONTAINS 'Gemma 4 E4B' AND label CONTAINS 'Eksperymentalny'").exists)
        XCTAssertTrue(app.staticTexts["Twój telefon może nie podołać temu modelowi"].exists)
        XCTAssertTrue(app.staticTexts["Zalecany telefon: iPhone z 16 GB RAM"].exists)
        attach(app, "picker-8gb")

        card(app, "label BEGINSWITH 'Gemma 4 12B'").tap()
        app.buttons["Pobierz Gemma 4 12B"].tap()
        XCTAssertTrue(app.staticTexts["Ten model może być za duży dla Twojego telefonu"].waitForExistence(timeout: 5))
        app.buttons["Wybierz Gemma 4 E2B"].tap()
        XCTAssertTrue(app.buttons["Pobierz Gemma 4 E2B"].waitForExistence(timeout: 5))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
