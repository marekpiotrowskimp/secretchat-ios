import XCTest

final class VoiceModeUITests: XCTestCase {
    func testVoiceModeShowsListeningAndTurnsOff() throws {
        let modelDir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchEnvironment["GEMMA_FAKE_DICTATION"] = "1" // no real microphone in UI tests
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        app.buttons["Nowa rozmowa"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Dyktuj"].waitForExistence(timeout: 5), "mic button in the composer")

        app.buttons["Tryb głosowy"].tap()
        XCTAssertTrue(app.staticTexts["Słucham…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Zakończ dyktowanie"].exists, "mic shows the listening state")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "voice-mode"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["Zakończ"].tap()
        XCTAssertTrue(app.buttons["Dyktuj"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Słucham…"].exists)
    }
}
