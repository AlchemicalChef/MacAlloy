import SwiftUI

/// Main entry point for the Alloy 6.2 macOS IDE
@main
struct AlloyMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        #if os(macOS)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        #endif
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    NotificationCenter.default.post(name: .newDocument, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open...") {
                    NotificationCenter.default.post(name: .openDocument, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    RecentFilesMenuContent()
                }

                Divider()

                Button("Save") {
                    NotificationCenter.default.post(name: .saveDocument, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    NotificationCenter.default.post(name: .saveAsDocument, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            // Run Menu
            CommandMenu("Run") {
                Button("Run Model") {
                    NotificationCenter.default.post(name: .runModel, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Check Assertion") {
                    NotificationCenter.default.post(name: .checkAssertion, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Next Instance") {
                    NotificationCenter.default.post(name: .nextInstance, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newDocument = Notification.Name("newDocument")
    static let openDocument = Notification.Name("openDocument")
    static let openRecentDocument = Notification.Name("openRecentDocument")
    static let saveDocument = Notification.Name("saveDocument")
    static let saveAsDocument = Notification.Name("saveAsDocument")
    static let runModel = Notification.Name("runModel")
    static let checkAssertion = Notification.Name("checkAssertion")
    static let nextInstance = Notification.Name("nextInstance")
}

// MARK: - Recent Files Menu Content

/// Menu content for the Open Recent menu in the menu bar
struct RecentFilesMenuContent: View {
    @ObservedObject var recentFilesManager = RecentFilesManager.shared

    var body: some View {
        if recentFilesManager.recentFiles.isEmpty {
            Text("No Recent Files")
                .foregroundColor(.secondary)
        } else {
            ForEach(recentFilesManager.recentFiles, id: \.path) { url in
                Button(url.lastPathComponent) {
                    NotificationCenter.default.post(name: .openRecentDocument, object: url)
                }
            }

            Divider()

            Button("Clear Menu") {
                recentFilesManager.clearRecentFiles()
            }
        }
    }
}
