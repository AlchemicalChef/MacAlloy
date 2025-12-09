import XCTest

final class AlloyMacUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the main editor view is visible
        XCTAssertTrue(app.staticTexts["Editor"].waitForExistence(timeout: 5))
    }

    func testEditorTabNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // Test tab switching
        app.buttons["Instances"].tap()
        XCTAssertTrue(app.staticTexts["No instances to display"].waitForExistence(timeout: 2))

        app.buttons["Diagnostics"].tap()
        XCTAssertTrue(app.staticTexts["No issues"].waitForExistence(timeout: 2))

        app.buttons["Editor"].tap()
        // Editor should be visible again
    }
}
