import XCTest

/// Regression: picking a photo from the library did nothing (PhotosPicker inside a Menu never presented).
final class PhotoLibraryUITests: XCTestCase {
    func testPickPhotoFromLibraryAndSendIt() throws {
        let modelDir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] ?? ""
        try XCTSkipIf(modelDir.isEmpty, "GEMMA_MODEL_DIR not set")
        let app = XCUIApplication()
        app.launchEnvironment["GEMMA_MODEL_DIR"] = modelDir
        app.launchArguments += ["-UITestInMemoryStore", "-AppleLanguages", "(pl)", "-AppleLocale", "pl_PL"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Brak rozmów"].waitForExistence(timeout: 10))
        app.buttons["Nowa rozmowa"].firstMatch.tap()

        app.buttons["Dodaj zdjęcie"].tap()
        let library = app.buttons["Biblioteka zdjęć"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()

        // System photo picker (out of process): wait for it, tap the first photo of the grid, confirm with ✓.
        // Its elements are not in our accessibility tree, so give it time to appear.
        sleep(4)
        attach(app, "picker-open")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.45)).tap() // first grid cell
        attach(app, "picker-selected")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.155)).tap() // ✓ (top right)

        // Thumbnail in the composer.
        XCTAssertTrue(app.buttons["Usuń zdjęcie"].waitForExistence(timeout: 15), "picked photo was not attached")
        attach(app, "photo-attached")

        let field = app.textFields["Wiadomość"].waitForExistence(timeout: 3) ? app.textFields["Wiadomość"] : app.textViews["Wiadomość"]
        field.tap()
        field.typeText("Opisz to zdjęcie jednym zdaniem.")
        app.buttons["Wyślij"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tok/s'")).firstMatch.waitForExistence(timeout: 300),
                      "no answer for the photo")
        attach(app, "photo-answer")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
