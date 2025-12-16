import XCTest
@testable import AlloyMac

/// Tests for file I/O operations including loading, saving, and error handling
@MainActor
final class FileIOTests: XCTestCase {

    // MARK: - Test Fixtures

    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        // Create a temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    // MARK: - Document Loading Tests

    func testLoadValidAlloyFile() async throws {
        // Create a valid Alloy file
        let content = """
            module test
            sig Person {}
            fact { some Person }
            """
        let fileURL = tempDirectory.appendingPathComponent("test.als")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: fileURL)

        XCTAssertEqual(document.sourceCode, content, "Source code should match file contents")
        XCTAssertEqual(document.fileName, "test.als", "File name should be set")
        XCTAssertEqual(document.fileURL, fileURL, "File URL should be set")
        XCTAssertFalse(document.hasUnsavedChanges, "Should not have unsaved changes after load")
    }

    func testLoadEmptyFile() async throws {
        // Create an empty file
        let fileURL = tempDirectory.appendingPathComponent("empty.als")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: fileURL)

        XCTAssertEqual(document.sourceCode, "", "Source code should be empty")
        XCTAssertEqual(document.fileName, "empty.als", "File name should be set")
    }

    func testLoadFileWithUnicodeContent() async throws {
        // File with unicode characters
        let content = """
            // Comment with unicode: 日本語 🎵 ñ ü
            sig Bücher {}
            sig Ω {}
            """
        let fileURL = tempDirectory.appendingPathComponent("unicode.als")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: fileURL)

        XCTAssertEqual(document.sourceCode, content, "Unicode content should be preserved")
    }

    func testLoadLargeFile() async throws {
        // Create a large file (~1MB)
        var content = ""
        for i in 0..<10000 {
            content += "sig Sig\(i) { field\(i): set Sig\(i) }\n"
        }
        let fileURL = tempDirectory.appendingPathComponent("large.als")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: fileURL)

        XCTAssertEqual(document.sourceCode, content, "Large file content should be fully loaded")
    }

    func testLoadNonExistentFile() async {
        let document = AlloyDocument()
        let nonExistentURL = tempDirectory.appendingPathComponent("nonexistent.als")

        do {
            try await document.load(from: nonExistentURL)
            XCTFail("Loading non-existent file should throw")
        } catch {
            // Expected - file doesn't exist
            XCTAssertTrue(true)
        }
    }

    func testLoadInvalidUTF8File() async throws {
        // Create a file with invalid UTF-8 bytes
        let fileURL = tempDirectory.appendingPathComponent("invalid_utf8.als")
        let invalidData = Data([0xFF, 0xFE, 0x80, 0x81, 0x82]) // Invalid UTF-8 sequence
        try invalidData.write(to: fileURL)

        let document = AlloyDocument()

        do {
            try await document.load(from: fileURL)
            XCTFail("Loading file with invalid UTF-8 should throw")
        } catch let error as AlloyDocumentError {
            XCTAssertEqual(error, .invalidEncoding, "Should throw invalidEncoding error")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Document Saving Tests

    func testSaveNewDocument() async throws {
        let document = AlloyDocument(sourceCode: "sig A {}", fileName: "test.als")
        let saveURL = tempDirectory.appendingPathComponent("saved.als")

        try await document.save(to: saveURL)

        // Verify file was written
        let savedContent = try String(contentsOf: saveURL, encoding: .utf8)
        XCTAssertEqual(savedContent, "sig A {}", "Saved content should match")
        XCTAssertFalse(document.hasUnsavedChanges, "Should not have unsaved changes after save")
    }

    func testSaveOverwritesExistingFile() async throws {
        // Create initial file
        let fileURL = tempDirectory.appendingPathComponent("overwrite.als")
        try "old content".write(to: fileURL, atomically: true, encoding: .utf8)

        // Load and modify
        let document = AlloyDocument(sourceCode: "new content", fileName: "overwrite.als")
        try await document.save(to: fileURL)

        // Verify overwrite
        let savedContent = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(savedContent, "new content", "File should be overwritten")
    }

    func testSavePreservesUnicodeContent() async throws {
        let content = """
            // 日本語コメント
            sig Ωメガ { field: set Ωメガ }
            """
        let document = AlloyDocument(sourceCode: content, fileName: "unicode.als")
        let saveURL = tempDirectory.appendingPathComponent("unicode_saved.als")

        try await document.save(to: saveURL)

        let savedContent = try String(contentsOf: saveURL, encoding: .utf8)
        XCTAssertEqual(savedContent, content, "Unicode content should be preserved after save")
    }

    func testSaveWithoutURLThrows() async {
        let document = AlloyDocument(sourceCode: "sig A {}", fileName: "test.als")
        // Document has no fileURL set

        do {
            try await document.save()
            XCTFail("Saving without URL should throw")
        } catch let error as AlloyDocumentError {
            XCTAssertEqual(error, .noFileURL, "Should throw noFileURL error")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSaveToCurrentURL() async throws {
        // Load a file first to set the URL
        let content = "sig A {}"
        let fileURL = tempDirectory.appendingPathComponent("current.als")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: fileURL)

        // Modify content
        document.sourceCode = "sig B {}"

        // Wait a moment for the sourceCode change to propagate
        try await Task.sleep(nanoseconds: 100_000_000)

        // Save to current URL
        try await document.save()

        // Verify
        let savedContent = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(savedContent, "sig B {}", "Updated content should be saved")
    }

    // MARK: - Unsaved Changes Tracking Tests

    func testUnsavedChangesTracking() async throws {
        let content = "sig A {}"
        let fileURL = tempDirectory.appendingPathComponent("tracking.als")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: fileURL)

        XCTAssertFalse(document.hasUnsavedChanges, "Should not have unsaved changes after load")

        // Modify content
        document.sourceCode = "sig A {} sig B {}"

        // Wait for the change to be tracked
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(document.hasUnsavedChanges, "Should have unsaved changes after modification")

        // Save
        try await document.save()

        XCTAssertFalse(document.hasUnsavedChanges, "Should not have unsaved changes after save")
    }

    func testNewDocumentHasUnsavedChanges() {
        let document = AlloyDocument()
        document.newDocument()

        XCTAssertTrue(document.hasUnsavedChanges, "New document should have unsaved changes")
    }

    // MARK: - Concurrent Operation Tests

    func testMultipleSaveOperations() async throws {
        let document = AlloyDocument(sourceCode: "sig A {}", fileName: "concurrent.als")
        let saveURL = tempDirectory.appendingPathComponent("concurrent.als")
        document.fileURL = saveURL

        // Attempt multiple concurrent saves
        async let save1: () = document.save(to: saveURL)
        async let save2: () = document.save(to: saveURL)
        async let save3: () = document.save(to: saveURL)

        // All should complete without crash
        _ = try await (save1, save2, save3)

        // File should contain the content
        let savedContent = try String(contentsOf: saveURL, encoding: .utf8)
        XCTAssertEqual(savedContent, "sig A {}", "Content should be saved correctly")
    }

    func testLoadWhileAnalyzing() async throws {
        let content1 = "sig A {}"
        let file1 = tempDirectory.appendingPathComponent("file1.als")
        try content1.write(to: file1, atomically: true, encoding: .utf8)

        let content2 = "sig B {}"
        let file2 = tempDirectory.appendingPathComponent("file2.als")
        try content2.write(to: file2, atomically: true, encoding: .utf8)

        let document = AlloyDocument()

        // Load first file
        try await document.load(from: file1)

        // Immediately load second file while analysis might be running
        try await document.load(from: file2)

        // Should have the second file's content
        XCTAssertEqual(document.sourceCode, content2, "Should have second file's content")
        XCTAssertEqual(document.fileName, "file2.als", "Should have second file's name")
    }

    // MARK: - Recent Files Manager Tests

    func testAddRecentFile() async throws {
        let manager = RecentFilesManager.shared
        let initialCount = manager.recentFiles.count

        let fileURL = tempDirectory.appendingPathComponent("recent.als")
        try "sig A {}".write(to: fileURL, atomically: true, encoding: .utf8)

        manager.addRecentFile(fileURL)

        XCTAssertTrue(manager.recentFiles.contains { $0.path == fileURL.path },
                     "Recent files should contain added file")
    }

    func testRecentFilesLimit() async throws {
        let manager = RecentFilesManager.shared
        manager.clearRecentFiles()

        // Add more than the max (10)
        for i in 0..<15 {
            let fileURL = tempDirectory.appendingPathComponent("file\(i).als")
            try "sig A\(i) {}".write(to: fileURL, atomically: true, encoding: .utf8)
            manager.addRecentFile(fileURL)
        }

        XCTAssertLessThanOrEqual(manager.recentFiles.count, 10,
                                  "Recent files should be limited to 10")
    }

    func testRecentFilesOrderMostRecentFirst() async throws {
        let manager = RecentFilesManager.shared
        manager.clearRecentFiles()

        let file1 = tempDirectory.appendingPathComponent("first.als")
        let file2 = tempDirectory.appendingPathComponent("second.als")
        try "sig A {}".write(to: file1, atomically: true, encoding: .utf8)
        try "sig B {}".write(to: file2, atomically: true, encoding: .utf8)

        manager.addRecentFile(file1)
        manager.addRecentFile(file2)

        XCTAssertEqual(manager.recentFiles.first?.lastPathComponent, "second.als",
                      "Most recently added file should be first")
    }

    func testRemoveRecentFile() async throws {
        let manager = RecentFilesManager.shared
        manager.clearRecentFiles()

        let fileURL = tempDirectory.appendingPathComponent("remove.als")
        try "sig A {}".write(to: fileURL, atomically: true, encoding: .utf8)

        manager.addRecentFile(fileURL)
        XCTAssertTrue(manager.recentFiles.contains { $0.path == fileURL.path })

        manager.removeRecentFile(fileURL)
        XCTAssertFalse(manager.recentFiles.contains { $0.path == fileURL.path },
                      "Removed file should not be in recent files")
    }

    func testClearRecentFiles() async throws {
        let manager = RecentFilesManager.shared

        // Add some files
        for i in 0..<5 {
            let fileURL = tempDirectory.appendingPathComponent("clear\(i).als")
            try "sig A\(i) {}".write(to: fileURL, atomically: true, encoding: .utf8)
            manager.addRecentFile(fileURL)
        }

        manager.clearRecentFiles()

        XCTAssertTrue(manager.recentFiles.isEmpty, "Recent files should be empty after clear")
    }

    func testFileExistsCheck() async throws {
        let manager = RecentFilesManager.shared

        let existingFile = tempDirectory.appendingPathComponent("exists.als")
        try "sig A {}".write(to: existingFile, atomically: true, encoding: .utf8)

        let nonExistingFile = tempDirectory.appendingPathComponent("not_exists.als")

        XCTAssertTrue(manager.fileExists(existingFile), "Should return true for existing file")
        XCTAssertFalse(manager.fileExists(nonExistingFile), "Should return false for non-existing file")
    }

    func testReAddingExistingRecentFileMovesToTop() async throws {
        let manager = RecentFilesManager.shared
        manager.clearRecentFiles()

        let file1 = tempDirectory.appendingPathComponent("first.als")
        let file2 = tempDirectory.appendingPathComponent("second.als")
        try "sig A {}".write(to: file1, atomically: true, encoding: .utf8)
        try "sig B {}".write(to: file2, atomically: true, encoding: .utf8)

        manager.addRecentFile(file1)
        manager.addRecentFile(file2)
        // Re-add file1
        manager.addRecentFile(file1)

        XCTAssertEqual(manager.recentFiles.first?.lastPathComponent, "first.als",
                      "Re-added file should move to top")
        // Should not have duplicates
        let file1Count = manager.recentFiles.filter { $0.path == file1.path }.count
        XCTAssertEqual(file1Count, 1, "Should not have duplicate entries")
    }

    // MARK: - Edge Cases

    func testLoadFileWithLongPath() async throws {
        // Create nested directories with long names
        var nestedPath = tempDirectory!
        for i in 0..<10 {
            nestedPath = nestedPath.appendingPathComponent("long_directory_name_\(i)")
        }
        try FileManager.default.createDirectory(at: nestedPath, withIntermediateDirectories: true)

        let fileURL = nestedPath.appendingPathComponent("deep.als")
        try "sig Deep {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: fileURL)

        XCTAssertEqual(document.sourceCode, "sig Deep {}", "Should load file from deep path")
        XCTAssertEqual(document.fileName, "deep.als", "Should have correct file name")
    }

    func testLoadFileWithSpecialCharactersInName() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test file (1).als")
        try "sig A {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: fileURL)

        XCTAssertEqual(document.fileName, "test file (1).als",
                      "Should handle special characters in filename")
    }

    func testSaveLargeFile() async throws {
        // Generate large content
        var content = ""
        for i in 0..<10000 {
            content += "sig Sig\(i) { field\(i): set Sig\(i) }\n"
        }

        let document = AlloyDocument(sourceCode: content, fileName: "large.als")
        let saveURL = tempDirectory.appendingPathComponent("large_saved.als")

        try await document.save(to: saveURL)

        let savedContent = try String(contentsOf: saveURL, encoding: .utf8)
        XCTAssertEqual(savedContent, content, "Large file should be saved correctly")
    }

    func testNewDocumentClearsInstances() async throws {
        // First, create and load a file that might have analysis results
        let content = "sig A {}"
        let fileURL = tempDirectory.appendingPathComponent("with_instances.als")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: fileURL)

        // Now create a new document
        document.newDocument()

        XCTAssertTrue(document.instances.isEmpty, "New document should have no instances")
        XCTAssertNil(document.currentTrace, "New document should have no trace")
    }

    // MARK: - Atomic Write Tests

    func testAtomicWriteOnSave() async throws {
        let fileURL = tempDirectory.appendingPathComponent("atomic.als")
        let originalContent = "sig Original {}"
        try originalContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let document = AlloyDocument(sourceCode: "sig New {}", fileName: "atomic.als")
        document.fileURL = fileURL

        // Save should use atomic writes
        try await document.save(to: fileURL)

        let savedContent = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(savedContent, "sig New {}", "Atomic save should complete successfully")
    }

    // MARK: - File Extension Handling

    func testLoadFileWithDifferentExtension() async throws {
        // Alloy files can have .als extension
        let alsFile = tempDirectory.appendingPathComponent("model.als")
        try "sig A {}".write(to: alsFile, atomically: true, encoding: .utf8)

        let document = AlloyDocument()
        try await document.load(from: alsFile)

        XCTAssertEqual(document.sourceCode, "sig A {}")
    }

    func testSaveUpdatesFileName() async throws {
        let document = AlloyDocument(sourceCode: "sig A {}", fileName: "old_name.als")
        let saveURL = tempDirectory.appendingPathComponent("new_name.als")

        try await document.save(to: saveURL)

        XCTAssertEqual(document.fileName, "new_name.als",
                      "Filename should update after save to new location")
    }
}

// MARK: - AlloyDocumentError Equatable

extension AlloyDocumentError: Equatable {
    public static func == (lhs: AlloyDocumentError, rhs: AlloyDocumentError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidEncoding, .invalidEncoding):
            return true
        case (.noFileURL, .noFileURL):
            return true
        default:
            return false
        }
    }
}
