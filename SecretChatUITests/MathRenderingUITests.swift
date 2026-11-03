import XCTest

/// Formulas in answers: display math typeset, inline math as Unicode, dollar amounts untouched.
final class MathRenderingUITests: XCTestCase {
    func testFormulasRender() throws {
        let modelDir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchArguments += ["-UITestInMemoryStore", "-UITestSeedMath", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wzory'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let any = app.descendants(matching: .any)
        // Inline math became Unicode; no raw LaTeX left anywhere.
        XCTAssertTrue(any.matching(NSPredicate(format: "label CONTAINS 'gdzie r to promień'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(any.matching(NSPredicate(format: "label CONTAINS 'ax² + bx + c = 0'")).firstMatch.exists)
        XCTAssertTrue(any.matching(NSPredicate(format: "label CONTAINS 'Δ = b² - 4ac'")).firstMatch.exists)
        // Display formulas are typeset (accessible via their Unicode reading).
        XCTAssertTrue(any.matching(NSPredicate(format: "label == 'x = (-b ± √Δ)/(2a)'")).firstMatch.exists)
        XCTAssertTrue(any.matching(NSPredicate(format: "label == 'P = πr²'")).firstMatch.exists)
        // Prices stay prices.
        XCTAssertTrue(any.matching(NSPredicate(format: "label CONTAINS 'kosztuje 5$ a karnet 10$'")).firstMatch.exists)
        XCTAssertFalse(any.matching(NSPredicate(format: "label CONTAINS '\\\\frac' OR label CONTAINS '\\\\pi'")).firstMatch.exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "math"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
