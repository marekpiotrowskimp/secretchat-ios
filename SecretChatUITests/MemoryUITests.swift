import XCTest

final class MemoryUITests: XCTestCase {
    func testAddEditAndDeleteMemoryInSettings() throws {
        let modelDir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        app.buttons["Ustawienia"].tap()
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Zapisane wspomnienia'")).firstMatch
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(app.switches["Pamięć długotrwała"].exists)
        XCTAssertEqual(app.switches["Pamięć długotrwała"].value as? String, "1", "memory is on by default")
        link.tap()
        XCTAssertTrue(app.staticTexts["Pamięć jest pusta"].waitForExistence(timeout: 5))

        app.buttons["Dodaj wspomnienie"].tap()
        app.textFields["Nazwa"].tap()
        app.textFields["Nazwa"].typeText("ulubiona kawa")
        let summary = app.textFields["Kiedy się przyda"].exists ? app.textFields["Kiedy się przyda"] : app.textViews["Kiedy się przyda"]
        summary.tap()
        summary.typeText("Jaką kawę pije użytkownik.")
        app.textViews.element(boundBy: app.textViews.count - 1).tap()
        app.typeText("Flat white z mlekiem owsianym.")
        app.buttons["Zapisz"].tap()

        XCTAssertTrue(app.staticTexts["ulubiona kawa"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Jaką kawę pije użytkownik."].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "memory-list"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.staticTexts["ulubiona kawa"].swipeLeft()
        app.buttons["Usuń"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pamięć jest pusta"].waitForExistence(timeout: 5))
    }
}
