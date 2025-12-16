import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: - Report View

/// Aesthetically pleasing validation report view with dark/light mode support
public struct ReportView: View {
    let report: ValidationReport?
    @Environment(\.colorScheme) private var colorScheme

    public init(report: ValidationReport?) {
        self.report = report
    }

    public var body: some View {
        Group {
            if let report = report {
                reportContent(report)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No Report Generated")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Click \"Generate Report\" to analyze your model")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Report Content

    private func reportContent(_ report: ValidationReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                reportHeader(report)

                // Executive Summary
                executiveSummary(report)

                // Test Results Banner
                if !report.testResults.isEmpty {
                    testResultsBanner(report)
                }

                // Statistics Grid
                statisticsGrid(report)

                // Solver Stats (if available)
                if let solverStats = report.solverStats {
                    solverStatsSection(solverStats)
                }

                // Collapsible Sections
                detailSections(report)

                // Diagnostics (if any)
                if !report.diagnostics.isEmpty {
                    diagnosticsSection(report.diagnostics)
                }
            }
            .padding()
        }
        .background(backgroundColor)
    }

    // MARK: - Header

    private func reportHeader(_ report: ValidationReport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label("Validation Report", systemImage: "doc.badge.gearshape")
                    .font(.largeTitle.bold())
                    .foregroundColor(.primary)

                Text("Generated: \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Executive Summary

    private func executiveSummary(_ report: ValidationReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Executive Summary")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                summaryRow(label: "Model", value: report.modelName)
                summaryRow(label: "Total Signatures", value: "\(report.statistics.signatureCount)")
                summaryRow(label: "Total Predicates", value: "\(report.statistics.predicateCount)")
                summaryRow(label: "Syntax Errors", value: "\(report.statistics.errorCount)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(summaryGradient)
        .cornerRadius(12)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.white.opacity(0.9))
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .font(.subheadline)
    }

    // MARK: - Test Results Banner

    private func testResultsBanner(_ report: ValidationReport) -> some View {
        let passed = report.passedCount
        let total = report.testResults.count
        let status = report.overallStatus

        return HStack {
            Image(systemName: status.iconName)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle(for: status, passed: passed, total: total))
                    .font(.headline)
                if status == .pass {
                    Text("All tests completed successfully")
                        .font(.caption)
                        .opacity(0.9)
                }
            }
            Spacer()
        }
        .padding()
        .foregroundColor(.white)
        .background(bannerColor(for: status))
        .cornerRadius(10)
    }

    private func bannerTitle(for status: TestStatus, passed: Int, total: Int) -> String {
        switch status {
        case .pass:
            return "All Tests Passed (\(passed)/\(total))"
        case .fail:
            return "Tests Failed (\(passed)/\(total) passed)"
        case .warning:
            return "Tests Have Warnings (\(passed)/\(total) passed)"
        case .pending:
            return "Tests Pending"
        }
    }

    private func bannerColor(for status: TestStatus) -> Color {
        switch status {
        case .pass: return .green
        case .fail: return .red
        case .warning: return .orange
        case .pending: return .gray
        }
    }

    // MARK: - Statistics Grid

    private func statisticsGrid(_ report: ValidationReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Statistics")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                StatBox(value: "\(report.statistics.signatureCount)", label: "Signatures", color: .blue)
                StatBox(value: "\(report.statistics.predicateCount)", label: "Predicates", color: .purple)
                StatBox(value: "\(report.statistics.functionCount)", label: "Functions", color: .teal)
                StatBox(value: "\(report.statistics.assertionCount)", label: "Assertions", color: .indigo)
                StatBox(value: "\(report.statistics.commandCount)", label: "Commands", color: .cyan)
                StatBox(
                    value: "\(report.statistics.errorCount)",
                    label: "Errors",
                    color: report.statistics.errorCount == 0 ? .green : .red,
                    showCheckmark: report.statistics.errorCount == 0
                )
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Solver Stats Section

    private func solverStatsSection(_ stats: ReportSolverStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Solver Statistics")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                MiniStatBox(value: "\(stats.decisions)", label: "Decisions")
                MiniStatBox(value: "\(stats.propagations)", label: "Propagations")
                MiniStatBox(value: "\(stats.conflicts)", label: "Conflicts")
                MiniStatBox(value: stats.formattedSolveTime, label: "Solve Time")
                MiniStatBox(value: "\(stats.learnedClauses)", label: "Learned")
                MiniStatBox(value: "\(stats.restarts)", label: "Restarts")
                MiniStatBox(value: "\(stats.variableCount)", label: "Variables")
                MiniStatBox(value: "\(stats.clauseCount)", label: "Clauses")
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Detail Sections

    private func detailSections(_ report: ValidationReport) -> some View {
        VStack(spacing: 12) {
            // Signatures
            if !report.signatures.isEmpty {
                CollapsibleSection(
                    title: "Signatures",
                    count: report.signatures.count,
                    iconName: "square.stack.3d.up",
                    iconColor: .blue
                ) {
                    signaturesTable(report.signatures)
                }
            }

            // Predicates
            if !report.predicates.isEmpty {
                CollapsibleSection(
                    title: "Predicates",
                    count: report.predicates.count,
                    iconName: "function",
                    iconColor: .purple
                ) {
                    predicatesList(report.predicates)
                }
            }

            // Functions
            if !report.functions.isEmpty {
                CollapsibleSection(
                    title: "Functions",
                    count: report.functions.count,
                    iconName: "f.cursive",
                    iconColor: .teal
                ) {
                    functionsList(report.functions)
                }
            }

            // Commands
            if !report.commands.isEmpty {
                CollapsibleSection(
                    title: "Commands",
                    count: report.commands.count,
                    iconName: "play.rectangle",
                    iconColor: .cyan
                ) {
                    commandsTable(report.commands)
                }
            }

            // Test Results Detail
            if !report.testResults.isEmpty {
                CollapsibleSection(
                    title: "Test Results",
                    count: report.testResults.count,
                    iconName: "checkmark.circle",
                    iconColor: .green
                ) {
                    testResultsTable(report.testResults)
                }
            }
        }
    }

    // MARK: - Signatures Table

    private func signaturesTable(_ signatures: [SignatureInfo]) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Modifiers")
                    .frame(width: 120, alignment: .leading)
                Text("Extends")
                    .frame(width: 100, alignment: .leading)
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tableHeaderBackground)

            // Rows
            ForEach(signatures.prefix(20)) { sig in
                HStack {
                    Text(sig.name)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(sig.modifiersString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Text(sig.extendsName ?? "-")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            if signatures.count > 20 {
                Text("... and \(signatures.count - 20) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    // MARK: - Predicates List

    private func predicatesList(_ predicates: [PredicateInfo]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(predicates.prefix(30)) { pred in
                Text(pred.signature)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
            }
            if predicates.count > 30 {
                Text("... and \(predicates.count - 30) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(12)
    }

    // MARK: - Functions List

    private func functionsList(_ functions: [FunctionInfo]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(functions.prefix(20)) { fn in
                Text(fn.signature)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
            }
            if functions.count > 20 {
                Text("... and \(functions.count - 20) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(12)
    }

    // MARK: - Commands Table

    private func commandsTable(_ commands: [CommandInfo]) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Type")
                    .frame(width: 60, alignment: .leading)
                Text("Target")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Scope")
                    .frame(width: 150, alignment: .leading)
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tableHeaderBackground)

            // Rows
            ForEach(commands) { cmd in
                HStack {
                    Text(cmd.commandType.displayName)
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    Text(cmd.targetName)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(cmd.scope)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 150, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Test Results Table

    private func testResultsTable(_ results: [TestResult]) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Status")
                    .frame(width: 50, alignment: .center)
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Type")
                    .frame(width: 60, alignment: .leading)
                Text("Time")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tableHeaderBackground)

            // Rows
            ForEach(results) { result in
                HStack {
                    Image(systemName: result.status.iconName)
                        .foregroundColor(statusColor(result.status))
                        .frame(width: 50, alignment: .center)
                    Text(result.name)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(result.commandType.displayName)
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    Text(result.solveTimeMs.map { String(format: "%.1fms", $0) } ?? "-")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Diagnostics Section

    private func diagnosticsSection(_ diagnostics: [Diagnostic]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.headline)

            ForEach(diagnostics.prefix(10), id: \.message) { diagnostic in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: diagnosticIcon(diagnostic.severity))
                        .foregroundColor(diagnosticColor(diagnostic.severity))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.message)
                            .font(.body)
                        Text("Line \(diagnostic.span.start.line), Column \(diagnostic.span.start.column)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(cardBackground.opacity(0.5))
                .cornerRadius(6)
            }

            if diagnostics.count > 10 {
                Text("... and \(diagnostics.count - 10) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Helper Functions

    private func statusColor(_ status: TestStatus) -> Color {
        switch status {
        case .pass: return .green
        case .fail: return .red
        case .warning: return .orange
        case .pending: return .gray
        }
    }

    private func diagnosticIcon(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info, .hint: return "info.circle.fill"
        }
    }

    private func diagnosticColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info, .hint: return .blue
        }
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.1) : PlatformColors.windowBackground
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.15) : Color.white
    }

    private var tableHeaderBackground: Color {
        colorScheme == .dark ? Color(white: 0.2) : PlatformColors.controlBackground
    }

    private var summaryGradient: LinearGradient {
        LinearGradient(
            colors: [Color.purple, Color.indigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Stat Box

private struct StatBox: View {
    let value: String
    let label: String
    let color: Color
    var showCheckmark: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.title2.bold())
                        .foregroundColor(color)
                }
                Text(value)
                    .font(.title.bold())
                    .foregroundColor(color)
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(colorScheme == .dark ? Color(white: 0.12) : PlatformColors.controlBackground)
        .cornerRadius(8)
    }
}

// MARK: - Mini Stat Box

private struct MiniStatBox: View {
    let value: String
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(white: 0.12) : PlatformColors.controlBackground)
        .cornerRadius(6)
    }
}

// MARK: - Collapsible Section

private struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    let iconName: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header button
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: iconName)
                        .foregroundColor(iconColor)
                    Text("\(title) (\(count))")
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                content()
                    .background(colorScheme == .dark ? Color(white: 0.12) : PlatformColors.controlBackground.opacity(0.5))
            }
        }
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.9), lineWidth: 1)
        )
    }
}

// MARK: - Preview

struct ReportView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ReportView(report: sampleReport)
                .preferredColorScheme(.light)

            ReportView(report: sampleReport)
                .preferredColorScheme(.dark)

            ReportView(report: nil)
        }
    }

    static var sampleReport: ValidationReport {
        ValidationReport(
            modelName: "sample_model.als",
            statistics: ModelStatistics(
                signatureCount: 61,
                predicateCount: 51,
                functionCount: 3,
                assertionCount: 3,
                commandCount: 12,
                factCount: 5,
                errorCount: 0,
                warningCount: 1
            ),
            testResults: [
                TestResult(name: "testDenyBlocks", commandType: .run, status: .pass, message: "Instance found", solveTimeMs: 12.5),
                TestResult(name: "testEmptyDACL", commandType: .run, status: .pass, message: "Instance found", solveTimeMs: 8.2),
                TestResult(name: "checkAssertion", commandType: .check, status: .pass, message: "No counterexample", solveTimeMs: 45.0)
            ],
            signatures: [
                SignatureInfo(name: "Person", modifiers: [], extendsName: nil, fieldCount: 2),
                SignatureInfo(name: "Employee", modifiers: [], extendsName: "Person", fieldCount: 1),
                SignatureInfo(name: "Manager", modifiers: ["one"], extendsName: "Employee", fieldCount: 0)
            ],
            predicates: [
                PredicateInfo(name: "validModel", parameters: []),
                PredicateInfo(name: "hasManager", parameters: ["e: Employee"])
            ],
            functions: [
                FunctionInfo(name: "allManagers", parameters: [], returnType: "set Manager")
            ],
            commands: [
                CommandInfo(commandType: .run, targetName: "validModel", scope: "3"),
                CommandInfo(commandType: .check, targetName: "noOrphans", scope: "5")
            ],
            solverStats: ReportSolverStats(
                decisions: 1234,
                propagations: 5678,
                conflicts: 42,
                learnedClauses: 38,
                restarts: 2,
                solveTimeMs: 65.8,
                variableCount: 2048,
                clauseCount: 8192
            ),
            diagnostics: []
        )
    }
}
