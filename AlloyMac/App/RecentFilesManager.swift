import Foundation
import SwiftUI

/// Manages recently opened files for the application
@MainActor
public final class RecentFilesManager: ObservableObject {
    /// Shared instance
    public static let shared = RecentFilesManager()

    /// Maximum number of recent files to store
    private let maxRecentFiles = 10

    /// UserDefaults key for storing recent files
    private let recentFilesKey = "com.alloy.recentFiles"

    /// List of recent file URLs (most recent first)
    @Published public private(set) var recentFiles: [URL] = []

    private init() {
        loadRecentFiles()
    }

    // MARK: - Public Methods

    /// Add a file to the recent files list
    public func addRecentFile(_ url: URL) {
        // Remove if already exists (will re-add at top)
        recentFiles.removeAll { $0.path == url.path }

        // Insert at beginning
        recentFiles.insert(url, at: 0)

        // Trim to max size
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }

        saveRecentFiles()
    }

    /// Remove a file from the recent files list
    public func removeRecentFile(_ url: URL) {
        recentFiles.removeAll { $0.path == url.path }
        saveRecentFiles()
    }

    /// Clear all recent files
    public func clearRecentFiles() {
        recentFiles = []
        saveRecentFiles()
    }

    /// Check if a file exists
    public func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Private Methods

    private func loadRecentFiles() {
        guard let data = UserDefaults.standard.data(forKey: recentFilesKey),
              let bookmarks = try? JSONDecoder().decode([Data].self, from: data) else {
            return
        }

        let loadedCount = bookmarks.count
        recentFiles = bookmarks.compactMap { bookmark -> URL? in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark,
                                     options: .withSecurityScope,
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale) else {
                return nil
            }
            // Only return if file still exists
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            return nil
        }

        // Clean up stale entries by re-saving if any were filtered out
        if recentFiles.count < loadedCount {
            saveRecentFiles()
        }
    }

    private func saveRecentFiles() {
        let bookmarks = recentFiles.compactMap { url -> Data? in
            do {
                return try url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            } catch {
                print("RecentFilesManager: Failed to create bookmark for \(url.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }

        do {
            let data = try JSONEncoder().encode(bookmarks)
            UserDefaults.standard.set(data, forKey: recentFilesKey)
        } catch {
            print("RecentFilesManager: Failed to save recent files: \(error.localizedDescription)")
        }
    }
}

// MARK: - Recent Files Menu View

/// A view that displays the recent files in a menu
struct RecentFilesMenu: View {
    @ObservedObject var recentFilesManager = RecentFilesManager.shared
    let onFileSelected: (URL) -> Void

    var body: some View {
        if recentFilesManager.recentFiles.isEmpty {
            Text("No Recent Files")
                .foregroundColor(.secondary)
        } else {
            ForEach(recentFilesManager.recentFiles, id: \.path) { url in
                Button(action: { onFileSelected(url) }) {
                    HStack {
                        Image(systemName: "doc.text")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Divider()

            Button("Clear Recent Files") {
                recentFilesManager.clearRecentFiles()
            }
        }
    }
}
