import SwiftUI
import UniformTypeIdentifiers

/// Main content view for the Alloy IDE
struct ContentView: View {
    @StateObject private var document = AlloyDocument(
        sourceCode: sampleAlloyCode,
        fileName: "example.als"
    )
    @State private var selectedTab: Tab = .editor
    @State private var showSettings = false
    @State private var showScopeConfig = false
    @State private var scope: Int = 3
    @State private var steps: Int = 10
    @State private var scrollTarget: SourceSpan?
    @State private var showOpenPicker = false
    @State private var showSavePicker = false
    @State private var showFileError: String?
    @State private var showUnsavedChangesAlert = false
    @State private var pendingAction: PendingAction?
    @State private var pendingRecentFileURL: URL?
    @State private var isDroppingFile = false

    /// Pending action after unsaved changes confirmation
    enum PendingAction {
        case new
        case open
        case openRecent
    }

    enum Tab {
        case editor
        case instances
        case trace
        case diagnostics
        case report
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            mainContent
        }
        .task {
            await document.analyze()
        }
        .sheet(isPresented: $showScopeConfig) {
            scopeConfigSheet
        }
        .fileImporter(
            isPresented: $showOpenPicker,
            allowedContentTypes: [.alloySource, .alloySourceAlt, .sourceCode, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleOpenFile(result)
        }
        .fileExporter(
            isPresented: $showSavePicker,
            document: AlloyFileDocument(content: document.sourceCode),
            contentType: .alloySourceAlt,
            defaultFilename: document.fileName
        ) { result in
            handleSaveFile(result)
        }
        .alert("File Error", isPresented: .constant(showFileError != nil), presenting: showFileError) { _ in
            Button("OK") { showFileError = nil }
        } message: { error in
            Text(error)
        }
        // Unsaved changes confirmation
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Don't Save", role: .destructive) {
                performPendingAction()
            }
            Button("Save") {
                Task {
                    if document.fileURL != nil {
                        do {
                            try await document.save()
                            performPendingAction()
                        } catch {
                            showFileError = error.localizedDescription
                        }
                    } else {
                        showSavePicker = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text("Do you want to save changes to \"\(document.fileName)\" before closing?")
        }
        // Drag and drop support
        .onDrop(of: [.fileURL], isTargeted: $isDroppingFile) { providers in
            handleFileDrop(providers)
        }
        .overlay {
            if isDroppingFile {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .padding(4)
            }
        }
        // Menu bar keyboard shortcut handlers
        .onReceive(NotificationCenter.default.publisher(for: .newDocument)) { _ in
            handleNewDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDocument)) { _ in
            handleOpenDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecentDocument)) { notification in
            if let url = notification.object as? URL {
                openRecentFile(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveDocument)) { _ in
            handleSaveDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveAsDocument)) { _ in
            showSavePicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .runModel)) { _ in
            Task { await document.executeRun(scope: scope, steps: steps) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkAssertion)) { _ in
            Task { await document.executeCheck(scope: scope, steps: steps) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextInstance)) { _ in
            Task { await document.nextInstance() }
        }
    }

    // MARK: - File Handling

    private func handleOpenFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    try await document.load(from: url)
                } catch {
                    showFileError = error.localizedDescription
                }
            }
        case .failure(let error):
            showFileError = error.localizedDescription
        }
    }

    private func handleSaveFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    try await document.save(to: url)
                    // If we had a pending action after save, perform it
                    if pendingAction != nil {
                        performPendingAction()
                    }
                } catch {
                    showFileError = error.localizedDescription
                }
            }
        case .failure(let error):
            showFileError = error.localizedDescription
        }
    }

    /// Handle new document action (with unsaved changes check)
    private func handleNewDocument() {
        if document.hasUnsavedChanges {
            pendingAction = .new
            showUnsavedChangesAlert = true
        } else {
            document.newDocument()
        }
    }

    /// Handle open document action (with unsaved changes check)
    private func handleOpenDocument() {
        if document.hasUnsavedChanges {
            pendingAction = .open
            showUnsavedChangesAlert = true
        } else {
            showOpenPicker = true
        }
    }

    /// Handle save document action
    private func handleSaveDocument() {
        if document.fileURL != nil {
            Task {
                do {
                    try await document.save()
                } catch {
                    showFileError = error.localizedDescription
                }
            }
        } else {
            showSavePicker = true
        }
    }

    /// Perform the pending action after save confirmation
    private func performPendingAction() {
        let action = pendingAction
        let recentURL = pendingRecentFileURL
        pendingAction = nil
        pendingRecentFileURL = nil

        switch action {
        case .new:
            document.newDocument()
        case .open:
            showOpenPicker = true
        case .openRecent:
            if let url = recentURL {
                Task {
                    do {
                        try await document.load(from: url)
                    } catch {
                        RecentFilesManager.shared.removeRecentFile(url)
                        showFileError = error.localizedDescription
                    }
                }
            }
        case .none:
            break
        }
    }

    /// Open a recent file
    private func openRecentFile(_ url: URL) {
        if document.hasUnsavedChanges {
            // Store the URL for later use
            pendingRecentFileURL = url
            pendingAction = .openRecent
            showUnsavedChangesAlert = true
        } else {
            Task {
                do {
                    try await document.load(from: url)
                } catch {
                    // Remove from recent files if it can't be opened
                    RecentFilesManager.shared.removeRecentFile(url)
                    showFileError = error.localizedDescription
                }
            }
        }
    }

    /// Handle file drop
    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            // Check if it's an Alloy file
            let ext = url.pathExtension.lowercased()
            guard ext == "als" || ext == "alloy" || ext == "txt" else {
                DispatchQueue.main.async {
                    showFileError = "Only .als, .alloy, and .txt files are supported"
                }
                return
            }

            DispatchQueue.main.async {
                if document.hasUnsavedChanges {
                    // Store the URL and show confirmation
                    pendingRecentFileURL = url
                    pendingAction = .openRecent
                    showUnsavedChangesAlert = true
                } else {
                    Task {
                        do {
                            try await document.load(from: url)
                        } catch {
                            showFileError = error.localizedDescription
                        }
                    }
                }
            }
        }
        return true
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            Section("File") {
                HStack {
                    Label(document.fileName, systemImage: "doc.text")
                        .foregroundColor(.accentColor)
                    if document.hasUnsavedChanges {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                    }
                }

                Button(action: handleNewDocument) {
                    Label("New", systemImage: "doc.badge.plus")
                }

                Button(action: handleOpenDocument) {
                    Label("Open...", systemImage: "folder")
                }

                Button(action: handleSaveDocument) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!document.hasUnsavedChanges && document.fileURL != nil)

                Button(action: { showSavePicker = true }) {
                    Label("Save As...", systemImage: "square.and.arrow.down.on.square")
                }
            }

            // Recent Files Section
            Section("Recent Files") {
                RecentFilesMenu(onFileSelected: openRecentFile)
            }

            Section("Status") {
                HStack {
                    if document.isAnalyzing || document.isSolving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        DiagnosticsSummary(diagnostics: document.diagnostics)
                    }
                    Spacer()
                    Text(document.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Scope") {
                Stepper("Atoms: \(scope)", value: $scope, in: 1...10)
                Stepper("Steps: \(steps)", value: $steps, in: 1...20)
            }
        }
        .navigationTitle("Alloy IDE")
        .listStyle(.sidebar)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Tab bar with actions
            toolbar

            Divider()

            // Content area
            switch selectedTab {
            case .editor:
                EditorView(
                    text: $document.sourceCode,
                    diagnostics: document.diagnostics,
                    scrollToLocation: scrollTarget
                )
                .onChange(of: scrollTarget) { _, _ in
                    // Clear scroll target after a brief delay to allow re-triggering
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        scrollTarget = nil
                    }
                }
            case .instances:
                if document.currentInstance?.isTemporal == true {
                    TraceView(instance: document.currentInstance)
                } else {
                    InstanceView(instance: document.currentInstance)
                }
            case .trace:
                TraceView(instance: document.currentInstance)
            case .diagnostics:
                DiagnosticsView(diagnostics: document.diagnostics) { diagnostic in
                    // Navigate to error location and scroll to it
                    scrollTarget = diagnostic.span
                    selectedTab = .editor
                }
            case .report:
                if let report = document.validationReport {
                    ReportView(report: report)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text("No Report Generated")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Click 'Generate Report' to analyze your model")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button(action: {
                            document.generateReport()
                        }) {
                            Label("Generate Report", systemImage: "doc.badge.gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            // Tab buttons
            TabButton(title: "Editor", systemImage: "doc.text", isSelected: selectedTab == .editor) {
                selectedTab = .editor
            }
            TabButton(title: "Instances", systemImage: "circle.grid.3x3", isSelected: selectedTab == .instances) {
                selectedTab = .instances
            }
            if document.currentInstance?.isTemporal == true {
                TabButton(title: "Trace", systemImage: "clock.arrow.circlepath", isSelected: selectedTab == .trace) {
                    selectedTab = .trace
                }
            }
            TabButton(title: "Diagnostics", systemImage: "exclamationmark.triangle", isSelected: selectedTab == .diagnostics) {
                selectedTab = .diagnostics
            }
            .overlay(alignment: .topTrailing) {
                if document.hasErrors {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -4)
                }
            }

            TabButton(title: "Report", systemImage: "doc.text.magnifyingglass", isSelected: selectedTab == .report) {
                selectedTab = .report
            }
            .overlay(alignment: .topTrailing) {
                if document.validationReport != nil {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -4)
                }
            }

            Spacer()

            // Status indicator
            if document.isAnalyzing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Analyzing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if document.isSolving {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Solving...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Instance counter
            if !document.instances.isEmpty {
                HStack(spacing: 4) {
                    Text("Instance \(document.selectedInstanceIndex + 1)/\(document.instances.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        Task { await document.nextInstance() }
                    }) {
                        Image(systemName: "arrow.right.circle")
                    }
                    .disabled(document.isSolving)
                }
            }

            Divider()
                .frame(height: 20)

            // Run/Check buttons
            Button(action: {
                Task { await document.executeRun(scope: scope, steps: steps) }
            }) {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(document.hasErrors || document.isSolving)

            Button(action: {
                Task { await document.executeCheck(scope: scope, steps: steps) }
            }) {
                Label("Check", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)
            .disabled(document.hasErrors || document.isSolving)

            Divider()
                .frame(height: 20)

            Button(action: {
                document.generateReport()
                selectedTab = .report
            }) {
                Label("Report", systemImage: "doc.badge.gearshape")
            }
            .buttonStyle(.bordered)
            .disabled(document.isAnalyzing || document.isSolving)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Scope Configuration

    private var scopeConfigSheet: some View {
        VStack {
            Form {
                Section("Default Scope") {
                    Stepper("Atoms: \(scope)", value: $scope, in: 1...20)
                }

                Section("Temporal") {
                    Stepper("Max Steps: \(steps)", value: $steps, in: 1...50)
                }

                Section(footer: Text("Higher values increase search space exponentially")) {
                    EmptyView()
                }
            }
            .navigationTitle("Scope Configuration")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showScopeConfig = false
                    }
                }
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : .secondary)
    }
}

// MARK: - Sample Code

private let sampleAlloyCode = """
// Alloy 6.2 Sample Model
module example

sig Person {
    friends: set Person,
    var mood: one Mood
}

abstract sig Mood {}
one sig Happy, Sad extends Mood {}

fact NoSelfFriend {
    no p: Person | p in p.friends
}

fact Symmetric {
    friends = ~friends
}

pred changeMood[p: Person, m: Mood] {
    p.mood' = m
    all other: Person - p | other.mood' = other.mood
}

assert AlwaysSomeoneHappy {
    always some p: Person | p.mood = Happy
}

run {} for 3 Person, 5 steps
check AlwaysSomeoneHappy for 3 Person, 10 steps
"""

// MARK: - Alloy File Document

/// FileDocument wrapper for exporting Alloy source files
struct AlloyFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.alloySource, .alloySourceAlt, .sourceCode, .plainText] }
    static var writableContentTypes: [UTType] { [.alloySourceAlt, .sourceCode, .plainText] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            content = string
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = content.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    ContentView()
}
