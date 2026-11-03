import XCTest

final class ReadAloudUITests: XCTestCase {
    func testReadAnswerAloudAndStop() throws {
        let modelDir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchArguments += ["-UITestInMemoryStore", "-UITestSeedMath", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wzory'")).firstMatch.tap()
        let read = app.buttons["Czytaj na głos"]
        XCTAssertTrue(read.waitForExistence(timeout: 10))
        read.tap()
        XCTAssertTrue(app.buttons["Zatrzymaj czytanie"].firstMatch.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "reading"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars.buttons["Zatrzymaj czytanie"].tap()
        XCTAssertTrue(app.buttons["Czytaj na głos"].waitForExistence(timeout: 5))

        // Settings section.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Ustawienia"].tap()
        let auto = app.switches["Czytaj odpowiedzi automatycznie"]
        for _ in 0..<6 where !auto.isHittable { app.swipeUp() }
        XCTAssertTrue(auto.exists)
        XCTAssertEqual(auto.value as? String, "0", "auto-read is off by default")
    }
}
