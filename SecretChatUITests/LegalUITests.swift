import XCTest

/// Settings → Licenses & legal shows every component with its full license text (Apache 2.0 for Gemma 4).
final class LegalUITests: XCTestCase {
    func testLicensesAreShown() throws {
        let modelDir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        app.buttons["Ustawienia"].tap()
        let link = app.buttons["Licencje i informacje prawne"]
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        link.tap()

        XCTAssertTrue(app.staticTexts["Gemma jest znakiem towarowym Google LLC. SecretChat nie jest powiązany z Google ani przez Google sponsorowany."].waitForExistence(timeout: 5))
        for name in ["Gemma 4 (12B, E4B, E2B)", "llama.cpp / ggml", "SwiftMath", "Latin Modern Math"] {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            for _ in 0..<4 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.exists, "\(name) missing")
        }
        for _ in 0..<4 { app.swipeDown() }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gemma 4 (12B, E4B, E2B)'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Apache License' AND label CONTAINS 'Version 2.0, January 2004'")).firstMatch.waitForExistence(timeout: 5),
                      "full Apache 2.0 text must be bundled")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let llama = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'llama.cpp'")).firstMatch
        llama.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Copyright (c) 2023-2026 The ggml authors'")).firstMatch.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
