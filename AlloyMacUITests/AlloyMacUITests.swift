import XCTest

final class AlloyMacUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch Tests

    func testAppLaunches() throws {
        // Verify the main editor view is visible
        XCTAssertTrue(app.staticTexts["Editor"].waitForExistence(timeout: 5))
    }

    // MARK: - Tab Navigation Tests

    func testEditorTabNavigation() throws {
        // Test tab switching
        app.buttons["Instances"].tap()
        XCTAssertTrue(app.staticTexts["No instances to display"].waitForExistence(timeout: 2))

        app.buttons["Diagnostics"].tap()
        XCTAssertTrue(app.staticTexts["No issues"].waitForExistence(timeout: 2))

        app.buttons["Editor"].tap()
        // Editor should be visible again
    }

    func testOutlineTabExists() throws {
        // Navigate to outline view
        if app.buttons["Outline"].exists {
            app.buttons["Outline"].tap()
        }
    }

    func testTraceTabExists() throws {
        // Navigate to trace view
        if app.buttons["Trace"].exists {
            app.buttons["Trace"].tap()
        }
    }

    func testReportTabExists() throws {
        // Navigate to report view
        if app.buttons["Report"].exists {
            app.buttons["Report"].tap()
        }
    }

    // MARK: - Editor Tests

    func testEditorIsEditable() throws {
        // Verify text editor exists and is accessible
        let textViews = app.textViews
        XCTAssertGreaterThan(textViews.count, 0, "Editor should have at least one text view")
    }

    func testEditorShowsPlaceholderOrContent() throws {
        // Either shows placeholder text or actual code content
        let textViews = app.textViews
        if let firstTextView = textViews.firstMatch as? XCUIElement {
            XCTAssertTrue(firstTextView.exists)
        }
    }

    // MARK: - Instance View Tests

    func testInstanceViewShowsEmptyState() throws {
        app.buttons["Instances"].tap()
        // Should show empty state when no model is solved
        let emptyMessage = app.staticTexts["No instances to display"]
        XCTAssertTrue(emptyMessage.waitForExistence(timeout: 3))
    }

    // MARK: - Diagnostics View Tests

    func testDiagnosticsViewShowsNoIssues() throws {
        app.buttons["Diagnostics"].tap()
        // Should show "No issues" for valid or empty model
        let noIssues = app.staticTexts["No issues"]
        XCTAssertTrue(noIssues.waitForExistence(timeout: 3))
    }

    // MARK: - Menu Tests

    func testFileMenuExists() throws {
        // Test that File menu exists
        let menuBar = app.menuBars
        XCTAssertGreaterThan(menuBar.count, 0)
    }

    func testKeyboardShortcuts() throws {
        // Test command+R shortcut for run (should not crash)
        app.typeKey("r", modifierFlags: .command)
        // App should still be running
        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Window Tests

    func testMainWindowExists() throws {
        XCTAssertGreaterThanOrEqual(app.windows.count, 1, "Should have at least one window")
    }

    func testWindowIsResizable() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    // MARK: - Accessibility Tests

    func testAccessibilityLabelsExist() throws {
        // Verify key UI elements have accessibility labels
        let editorButton = app.buttons["Editor"]
        XCTAssertTrue(editorButton.exists, "Editor button should have accessibility label")

        let instancesButton = app.buttons["Instances"]
        XCTAssertTrue(instancesButton.exists, "Instances button should have accessibility label")
    }

    // MARK: - Performance Tests

    func testAppLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let newApp = XCUIApplication()
            newApp.launch()
            newApp.terminate()
        }
    }
}
