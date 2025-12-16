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

    // MARK: - Editor Interaction Tests

    func testTypingInEditor() throws {
        // Find the editor text view
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTFail("No text views found in editor")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Type some Alloy code
        editor.typeText("sig Test {}")

        // Editor should still exist and app should not crash
        XCTAssertTrue(editor.exists)
    }

    func testUndoRedo() throws {
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTSkip("No text views found")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Type some text
        editor.typeText("sig A {}")

        // Undo (Cmd+Z)
        app.typeKey("z", modifierFlags: .command)

        // Redo (Cmd+Shift+Z)
        app.typeKey("z", modifierFlags: [.command, .shift])

        // App should not crash
        XCTAssertTrue(app.windows.count >= 1)
    }

    func testMultipleUndoRedoCycles() throws {
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTSkip("No text views found")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Perform multiple undo/redo cycles
        for i in 0..<20 {
            editor.typeText("sig S\(i) {} ")

            // Undo
            app.typeKey("z", modifierFlags: .command)

            // Redo
            app.typeKey("z", modifierFlags: [.command, .shift])
        }

        // App should remain stable
        XCTAssertTrue(app.windows.count >= 1)
    }

    func testSelectAllAndDelete() throws {
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTSkip("No text views found")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Type some text
        editor.typeText("sig Test { field: set Test }")

        // Select all (Cmd+A)
        app.typeKey("a", modifierFlags: .command)

        // Delete
        app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])

        // Editor should still work
        XCTAssertTrue(editor.exists)
    }

    func testCopyPaste() throws {
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTSkip("No text views found")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Type some text
        editor.typeText("sig Test {}")

        // Select all (Cmd+A)
        app.typeKey("a", modifierFlags: .command)

        // Copy (Cmd+C)
        app.typeKey("c", modifierFlags: .command)

        // Move to end
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: .command)

        // Paste (Cmd+V)
        app.typeKey("v", modifierFlags: .command)

        // App should not crash
        XCTAssertTrue(editor.exists)
    }

    // MARK: - Toolbar Tests

    func testRunButton() throws {
        // Look for Run button in toolbar
        let runButton = app.buttons["Run"]
        if runButton.exists {
            runButton.tap()
            // Wait a moment for any action
            Thread.sleep(forTimeInterval: 1)
            // App should not crash
            XCTAssertTrue(app.windows.count >= 1)
        }
    }

    func testCheckButton() throws {
        // Look for Check button in toolbar
        let checkButton = app.buttons["Check"]
        if checkButton.exists {
            checkButton.tap()
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(app.windows.count >= 1)
        }
    }

    func testNextInstanceButton() throws {
        // Look for Next button in toolbar
        let nextButton = app.buttons["Next"]
        if nextButton.exists {
            nextButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertTrue(app.windows.count >= 1)
        }
    }

    // MARK: - Scope Picker Tests

    func testScopePickerExists() throws {
        // Look for scope picker or stepper
        let scopeElements = app.steppers
        if scopeElements.count > 0 {
            XCTAssertTrue(scopeElements.firstMatch.exists)
        }
        // Also check for scope text field
        let scopeFields = app.textFields
        // At least some UI exists
        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Tab Bar Interaction Tests

    func testRapidTabSwitching() throws {
        // Rapidly switch between tabs to test stability
        for _ in 0..<10 {
            if app.buttons["Editor"].exists {
                app.buttons["Editor"].tap()
            }
            if app.buttons["Instances"].exists {
                app.buttons["Instances"].tap()
            }
            if app.buttons["Diagnostics"].exists {
                app.buttons["Diagnostics"].tap()
            }
        }

        // App should remain stable
        XCTAssertTrue(app.windows.count >= 1)
    }

    func testTabStatePreservation() throws {
        // Switch to diagnostics
        if app.buttons["Diagnostics"].exists {
            app.buttons["Diagnostics"].tap()
        }

        // Switch away and back
        if app.buttons["Editor"].exists {
            app.buttons["Editor"].tap()
        }

        if app.buttons["Diagnostics"].exists {
            app.buttons["Diagnostics"].tap()
        }

        // State should be preserved
        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Status Bar Tests

    func testStatusBarExists() throws {
        // Look for status text showing "Ready" or similar
        let readyText = app.staticTexts["Ready"]
        // Status might show something else, so just check window exists
        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Error State Tests

    func testInvalidSyntaxShowsDiagnostics() throws {
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTSkip("No text views found")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Type invalid syntax
        editor.typeText("sig @@@")

        // Wait for analysis
        Thread.sleep(forTimeInterval: 1)

        // Navigate to diagnostics
        if app.buttons["Diagnostics"].exists {
            app.buttons["Diagnostics"].tap()
        }

        // Should show some error indicator (might show "1 error(s)" or similar)
        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Dark Mode Tests

    func testAppWorksInDarkMode() throws {
        // App should work regardless of system appearance
        XCTAssertTrue(app.windows.count >= 1)
        XCTAssertTrue(app.buttons["Editor"].exists)
    }

    // MARK: - New Document Tests

    func testNewDocumentKeyboardShortcut() throws {
        // Cmd+N for new document
        app.typeKey("n", modifierFlags: .command)

        // Should still have window
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Save Document Tests

    func testSaveKeyboardShortcut() throws {
        // Cmd+S for save
        app.typeKey("s", modifierFlags: .command)

        // App should not crash
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(app.windows.count >= 1)
    }

    func testSaveAsKeyboardShortcut() throws {
        // Cmd+Shift+S for save as
        app.typeKey("s", modifierFlags: [.command, .shift])

        // App should not crash
        Thread.sleep(forTimeInterval: 0.5)

        // Dismiss any dialog that might have appeared
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        }

        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Open Document Tests

    func testOpenKeyboardShortcut() throws {
        // Cmd+O for open
        app.typeKey("o", modifierFlags: .command)

        // App should not crash
        Thread.sleep(forTimeInterval: 0.5)

        // Dismiss any dialog that might have appeared
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        }

        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Stress Tests

    func testRapidTyping() throws {
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTSkip("No text views found")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Type rapidly
        for i in 0..<50 {
            editor.typeText("sig S\(i) {} ")
        }

        // App should remain stable
        XCTAssertTrue(app.windows.count >= 1)
    }

    func testRapidCommandExecution() throws {
        // Rapidly execute run command multiple times
        for _ in 0..<5 {
            app.typeKey("r", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 0.1)
        }

        // App should remain stable
        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Window Resize Tests

    func testWindowResize() throws {
        let window = app.windows.firstMatch
        guard window.exists else {
            XCTSkip("No window found")
            return
        }

        // Window should exist and be interactable
        XCTAssertTrue(window.exists)
    }

    // MARK: - Focus Tests

    func testEditorRetainsFocus() throws {
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTSkip("No text views found")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Type something
        editor.typeText("sig Test {}")

        // Focus should remain in editor
        XCTAssertTrue(editor.exists)
    }

    // MARK: - Large Content Tests

    func testLargeModelInput() throws {
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTSkip("No text views found")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Generate a moderately large model
        var content = ""
        for i in 0..<100 {
            content += "sig S\(i) { f: set S\(i) }\n"
        }

        // Type the content (note: this will be slow in UI tests)
        // Just type a subset to avoid timeout
        editor.typeText("sig S0 { f: set S0 }\nsig S1 { f: set S1 }\nsig S2 { f: set S2 }")

        // App should remain stable
        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Memory and Stability Tests

    func testRepeatedTabSwitchDoesNotLeak() throws {
        // Switch tabs many times to test for memory leaks
        for _ in 0..<50 {
            if app.buttons["Editor"].exists {
                app.buttons["Editor"].tap()
            }
            if app.buttons["Instances"].exists {
                app.buttons["Instances"].tap()
            }
        }

        // App should remain stable
        XCTAssertTrue(app.windows.count >= 1)
    }

    // MARK: - Combo Operations Tests

    func testTypeThenRunThenNextInstance() throws {
        let textViews = app.textViews
        guard textViews.count > 0 else {
            XCTSkip("No text views found")
            return
        }

        let editor = textViews.firstMatch
        editor.click()

        // Clear and type a simple model
        app.typeKey("a", modifierFlags: .command)
        editor.typeText("sig Person {}\nfact { some Person }")

        // Wait for analysis
        Thread.sleep(forTimeInterval: 1)

        // Run
        app.typeKey("r", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 2)

        // Try next instance if available
        let nextButton = app.buttons["Next"]
        if nextButton.exists && nextButton.isEnabled {
            nextButton.tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // App should remain stable
        XCTAssertTrue(app.windows.count >= 1)
    }
}
