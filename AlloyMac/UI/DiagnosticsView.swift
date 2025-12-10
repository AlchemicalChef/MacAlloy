import SwiftUI

// MARK: - Diagnostics View

/// View that displays parser/semantic errors and warnings
public struct DiagnosticsView: View {
    let diagnostics: [Diagnostic]
    var onDiagnosticTap: ((Diagnostic) -> Void)?

    public init(diagnostics: [Diagnostic], onDiagnosticTap: ((Diagnostic) -> Void)? = nil) {
        self.diagnostics = diagnostics
        self.onDiagnosticTap = onDiagnosticTap
    }

    public var body: some View {
        Group {
            if diagnostics.isEmpty {
                emptyView
            } else {
                diagnosticsList
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("No issues")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Your model has no errors or warnings")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diagnosticsList: some View {
        List {
            // Group by severity
            let errors = diagnostics.filter { $0.severity == .error }
            let warnings = diagnostics.filter { $0.severity == .warning }
            let infos = diagnostics.filter { $0.severity == .info || $0.severity == .hint }

            if !errors.isEmpty {
                Section {
                    ForEach(Array(errors.enumerated()), id: \.offset) { index, error in
                        DiagnosticRow(diagnostic: error)
                            .onTapGesture {
                                onDiagnosticTap?(error)
                            }
                    }
                } header: {
                    Label("\(errors.count) Error\(errors.count == 1 ? "" : "s")", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }

            if !warnings.isEmpty {
                Section {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { index, warning in
                        DiagnosticRow(diagnostic: warning)
                            .onTapGesture {
                                onDiagnosticTap?(warning)
                            }
                    }
                } header: {
                    Label("\(warnings.count) Warning\(warnings.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }

            if !infos.isEmpty {
                Section {
                    ForEach(Array(infos.enumerated()), id: \.offset) { index, info in
                        DiagnosticRow(diagnostic: info)
                            .onTapGesture {
                                onDiagnosticTap?(info)
                            }
                    }
                } header: {
                    Label("\(infos.count) Info", systemImage: "info.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Diagnostic Row

/// A single diagnostic row
struct DiagnosticRow: View {
    let diagnostic: Diagnostic

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Severity icon
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                // Message
                Text(diagnostic.message)
                    .font(.body)
                    .foregroundColor(.primary)

                // Location
                Text("Line \(diagnostic.span.start.line), Column \(diagnostic.span.start.column)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Code
                Text("[\(diagnostic.code.rawValue)]")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Navigation indicator
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch diagnostic.severity {
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info, .hint:
            return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch diagnostic.severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info, .hint:
            return .blue
        }
    }
}

// MARK: - Diagnostics Summary

/// Compact summary of diagnostics for display in toolbar
public struct DiagnosticsSummary: View {
    let diagnostics: [Diagnostic]

    public init(diagnostics: [Diagnostic]) {
        self.diagnostics = diagnostics
    }

    public var body: some View {
        HStack(spacing: 8) {
            let errorCount = diagnostics.filter { $0.severity == .error }.count
            let warningCount = diagnostics.filter { $0.severity == .warning }.count

            if errorCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("\(errorCount)")
                        .foregroundColor(.red)
                }
            }

            if warningCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("\(warningCount)")
                        .foregroundColor(.orange)
                }
            }

            if errorCount == 0 && warningCount == 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("OK")
                        .foregroundColor(.green)
                }
            }
        }
        .font(.caption)
    }
}

// MARK: - Preview

struct DiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        DiagnosticsView(diagnostics: [])
    }
}
