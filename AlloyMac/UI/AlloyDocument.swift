import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Alloy File Type

/// UTType for Alloy source files
extension UTType {
    static var alloySource: UTType {
        UTType(exportedAs: "com.alloy.source", conformingTo: .sourceCode)
    }

    static var alloySourceAlt: UTType {
        UTType(filenameExtension: "als", conformingTo: .sourceCode) ?? .sourceCode
    }
}

// MARK: - Alloy Document

/// Observable document model for an Alloy file
/// Manages source code, parsing, analysis, and solving
@MainActor
public final class AlloyDocument: ObservableObject {
    /// The source code
    @Published public var sourceCode: String {
        didSet {
            scheduleAnalysis()
        }
    }

    /// File name
    @Published public var fileName: String

    /// Parser diagnostics
    @Published public private(set) var diagnostics: [Diagnostic] = []

    /// Current instances (if any)
    @Published public private(set) var instances: [AlloyInstance] = []

    /// Currently selected instance index
    @Published public var selectedInstanceIndex: Int = 0

    /// Current trace (for temporal models)
    @Published public private(set) var currentTrace: AlloyTrace?

    /// Validation report (generated on demand)
    @Published public private(set) var validationReport: ValidationReport?

    /// Last solver statistics
    private var lastSolverStats: ReportSolverStats?

    /// Last solve time in milliseconds
    private var lastSolveTimeMs: Double = 0

    /// Test results accumulated during session
    private var accumulatedTestResults: [TestResult] = []

    /// Whether analysis is in progress
    @Published public private(set) var isAnalyzing: Bool = false

    /// Whether solving is in progress
    @Published public private(set) var isSolving: Bool = false

    /// Whether saving is in progress
    @Published public private(set) var isSaving: Bool = false

    /// Status message
    @Published public private(set) var statusMessage: String = "Ready"

    /// The parsed module (if successful)
    public private(set) var module: ModuleNode?

    /// The symbol table (if analysis succeeded)
    public private(set) var symbolTable: SymbolTable?

    /// Analysis debounce timer
    private var analysisTask: Task<Void, Never>?

    /// Analysis delay in seconds
    private let analysisDelay: TimeInterval = AlloyConstants.analysisDebounceDelay

    // MARK: - Instance Enumeration State

    /// Stored translator for instance enumeration
    private var enumerationTranslator: AlloyTranslator?

    /// Original clauses for enumeration
    private var enumerationClauses: [[Int]]?

    /// Blocking clauses added for each found instance
    private var blockingClauses: [[Int]] = []

    /// Previous solutions (for generating blocking clauses)
    private var previousSolutions: [[Bool]] = []

    /// Whether we're in check mode (affects interpretation)
    private var wasCheckCommand: Bool = false

    // MARK: - Initialization

    public init(sourceCode: String = "", fileName: String = "untitled.als") {
        self.sourceCode = sourceCode
        self.fileName = fileName
    }

    deinit {
        analysisTask?.cancel()
    }

    // MARK: - Analysis

    /// Schedule analysis after a delay (debounced)
    private func scheduleAnalysis() {
        // Track unsaved changes
        checkForUnsavedChanges()

        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.analysisDelay ?? 0.3) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.analyze()
        }
    }

    /// Analyze the current source code
    public func analyze() async {
        isAnalyzing = true
        statusMessage = "Analyzing..."
        diagnostics = []
        module = nil
        symbolTable = nil

        // Parse
        let parser = Parser(source: sourceCode)
        let parsedModule = parser.parse()

        // Convert parse errors to diagnostics
        for error in parser.getErrors() {
            diagnostics.append(Diagnostic(
                severity: .error,
                code: .unexpectedToken,
                message: error.message,
                span: error.span
            ))
        }

        guard let mod = parsedModule else {
            isAnalyzing = false
            statusMessage = diagnostics.isEmpty ? "Ready" : "\(diagnostics.count) error(s)"
            return
        }

        self.module = mod

        // Semantic analysis
        let analyzer = SemanticAnalyzer()
        analyzer.analyze(mod)
        self.symbolTable = analyzer.symbolTable

        // Add any warnings from semantic analysis
        diagnostics.append(contentsOf: analyzer.diagnostics.diagnostics)

        if diagnostics.isEmpty {
            statusMessage = "Ready"
        } else {
            let errorCount = diagnostics.filter { $0.severity == .error }.count
            let warningCount = diagnostics.filter { $0.severity == .warning }.count
            if errorCount > 0 {
                statusMessage = "\(errorCount) error(s)"
            } else if warningCount > 0 {
                statusMessage = "\(warningCount) warning(s)"
            } else {
                statusMessage = "Ready"
            }
        }

        isAnalyzing = false
    }

    // MARK: - Commands

    /// Execute a run command
    public func executeRun(scope: Int = 3, steps: Int = 10) async {
        guard let symbolTable = symbolTable else {
            let errorSpan = SourceSpan(
                start: SourcePosition(line: 1, column: 1, offset: 0),
                end: SourcePosition(line: 1, column: 1, offset: 0)
            )
            diagnostics.append(Diagnostic(
                severity: .error,
                code: .unexpectedToken,
                message: "Cannot run: model has errors",
                span: errorSpan
            ))
            return
        }

        isSolving = true
        statusMessage = "Running..."
        instances = []
        currentTrace = nil
        wasCheckCommand = false

        // Reset enumeration state
        enumerationTranslator = nil
        enumerationClauses = nil
        blockingClauses = []
        previousSolutions = []

        // Create scope
        let commandScope = CommandScope(defaultScope: scope, steps: steps)

        do {
            let result = try await solve(symbolTable: symbolTable, scope: commandScope, isCheck: false)
            handleSolveResult(result)
        } catch {
            let errorSpan = SourceSpan(
                start: SourcePosition(line: 1, column: 1, offset: 0),
                end: SourcePosition(line: 1, column: 1, offset: 0)
            )
            diagnostics.append(Diagnostic(
                severity: .error,
                code: .unexpectedToken,
                message: "Solver error: \(error.localizedDescription)",
                span: errorSpan
            ))
            statusMessage = "Solver error"
        }

        isSolving = false
    }

    /// Execute a check command
    public func executeCheck(scope: Int = 3, steps: Int = 10) async {
        guard let symbolTable = symbolTable else {
            let errorSpan = SourceSpan(
                start: SourcePosition(line: 1, column: 1, offset: 0),
                end: SourcePosition(line: 1, column: 1, offset: 0)
            )
            diagnostics.append(Diagnostic(
                severity: .error,
                code: .unexpectedToken,
                message: "Cannot check: model has errors",
                span: errorSpan
            ))
            return
        }

        isSolving = true
        statusMessage = "Checking..."
        instances = []
        currentTrace = nil
        wasCheckCommand = true

        // Reset enumeration state
        enumerationTranslator = nil
        enumerationClauses = nil
        blockingClauses = []
        previousSolutions = []

        let commandScope = CommandScope(defaultScope: scope, steps: steps)

        do {
            let result = try await solve(symbolTable: symbolTable, scope: commandScope, isCheck: true)
            handleCheckResult(result)
        } catch {
            let errorSpan = SourceSpan(
                start: SourcePosition(line: 1, column: 1, offset: 0),
                end: SourcePosition(line: 1, column: 1, offset: 0)
            )
            diagnostics.append(Diagnostic(
                severity: .error,
                code: .unexpectedToken,
                message: "Solver error: \(error.localizedDescription)",
                span: errorSpan
            ))
            statusMessage = "Solver error"
        }

        isSolving = false
    }

    /// Internal solve result that includes enumeration state
    private struct SolveResultWithState: Sendable {
        let result: SolveResult
        let translator: AlloyTranslator
        let clauses: [[Int]]
        let solution: [Bool]?
    }

    /// Solve the model
    private func solve(symbolTable: SymbolTable, scope: CommandScope, isCheck: Bool) async throws -> SolveResult {
        // Run solver on background thread
        let resultWithState: SolveResultWithState = await Task.detached(priority: .userInitiated) {
            let translator = AlloyTranslator(symbolTable: symbolTable, scope: scope)

            if isCheck {
                // For check, we look for counterexamples to first assertion
                if let firstAssert = symbolTable.assertions.values.first {
                    translator.translateAssertion(firstAssert.name)
                } else {
                    translator.translateFacts()
                }
            } else {
                // For run, encode facts and first predicate
                if let firstPred = symbolTable.predicates.values.first {
                    translator.translatePredicate(firstPred.name)
                } else {
                    translator.translateFacts()
                }
            }

            // Solve
            let clauses = translator.clauses.map { $0.map { Int($0) } }
            let solver = CDCLSolver()
            let result = solver.solve(numVariables: translator.variableCount, clauses: clauses)

            switch result {
            case .satisfiable(let model):
                let instance = translator.extractInstance(solution: model)
                return SolveResultWithState(
                    result: .sat(instance),
                    translator: translator,
                    clauses: clauses,
                    solution: model
                )
            case .unsatisfiable:
                return SolveResultWithState(
                    result: .unsat,
                    translator: translator,
                    clauses: clauses,
                    solution: nil
                )
            case .unknown:
                return SolveResultWithState(
                    result: .unknown("Solver returned unknown"),
                    translator: translator,
                    clauses: clauses,
                    solution: nil
                )
            }
        }.value

        // Store enumeration state for subsequent calls to nextInstance()
        self.enumerationTranslator = resultWithState.translator
        self.enumerationClauses = resultWithState.clauses
        if let solution = resultWithState.solution {
            self.previousSolutions = [solution]
        }

        return resultWithState.result
    }

    /// Handle run result
    private func handleSolveResult(_ result: SolveResult) {
        switch result {
        case .sat(let instance):
            instances = [instance]
            selectedInstanceIndex = 0
            currentTrace = instance.trace
            statusMessage = "Instance found"
        case .unsat:
            statusMessage = "No instance found"
        case .unknown(let reason):
            statusMessage = "Unknown: \(reason)"
        }
    }

    /// Handle check result
    private func handleCheckResult(_ result: SolveResult) {
        switch result {
        case .sat(let instance):
            // For check, SAT means counterexample found
            instances = [instance]
            selectedInstanceIndex = 0
            currentTrace = instance.trace
            statusMessage = "Counterexample found!"
            let errorSpan = SourceSpan(
                start: SourcePosition(line: 1, column: 1, offset: 0),
                end: SourcePosition(line: 1, column: 1, offset: 0)
            )
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: .redundantConstraint,
                message: "Assertion may be invalid - counterexample found",
                span: errorSpan
            ))
        case .unsat:
            statusMessage = "No counterexample (assertion holds)"
        case .unknown(let reason):
            statusMessage = "Unknown: \(reason)"
        }
    }

    /// Get next instance (for enumeration)
    public func nextInstance() async {
        // Prevent calling during active solve operation
        guard !isSolving else {
            statusMessage = "Solving in progress..."
            return
        }

        guard let translator = enumerationTranslator,
              let baseClauses = enumerationClauses,
              let lastSolution = previousSolutions.last else {
            statusMessage = "No previous instance to enumerate from"
            return
        }

        isSolving = true
        statusMessage = "Finding next instance..."

        // Create blocking clause from the last solution
        // A blocking clause is a disjunction that says "at least one variable must differ"
        // For each variable v that is true in the solution, add -v to the clause
        // For each variable v that is false in the solution, add +v to the clause
        let blockingClause = createBlockingClause(from: lastSolution, numVariables: translator.variableCount)
        blockingClauses.append(blockingClause)

        // Combine original clauses with all blocking clauses
        let allClauses = baseClauses + blockingClauses

        // Solve with the new constraints
        let result: (SolveResult, [Bool]?) = await Task.detached(priority: .userInitiated) { [translator, allClauses] in
            let solver = CDCLSolver()
            let result = solver.solve(numVariables: translator.variableCount, clauses: allClauses)

            switch result {
            case .satisfiable(let model):
                let instance = translator.extractInstance(solution: model)
                return (SolveResult.sat(instance), model as [Bool]?)
            case .unsatisfiable:
                return (SolveResult.unsat, nil)
            case .unknown:
                return (SolveResult.unknown("Solver returned unknown"), nil)
            }
        }.value

        isSolving = false

        switch result.0 {
        case .sat(let instance):
            // Found a new instance
            instances.append(instance)
            selectedInstanceIndex = instances.count - 1
            currentTrace = instance.trace
            if let solution = result.1 {
                previousSolutions.append(solution)
            }
            let description = wasCheckCommand ? "counterexample" : "instance"
            statusMessage = "Found \(description) \(instances.count)"
        case .unsat:
            // No more instances
            statusMessage = "No more instances (found \(instances.count) total)"
        case .unknown(let reason):
            statusMessage = "Unknown: \(reason)"
        }
    }

    /// Create a blocking clause from a solution
    /// The blocking clause negates the entire solution to prevent it from being found again
    private func createBlockingClause(from solution: [Bool], numVariables: Int) -> [Int] {
        var clause: [Int] = []
        for v in 1...numVariables {
            if v < solution.count {
                // Negate the assignment: if solution[v] is true, add -v; if false, add +v
                if solution[v] {
                    clause.append(-v)
                } else {
                    clause.append(v)
                }
            }
        }
        return clause
    }

    // MARK: - Accessors

    /// Current instance (if any)
    public var currentInstance: AlloyInstance? {
        guard selectedInstanceIndex < instances.count else { return nil }
        return instances[selectedInstanceIndex]
    }

    /// Whether there are errors
    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }

    /// Whether there are warnings
    public var hasWarnings: Bool {
        diagnostics.contains { $0.severity == .warning }
    }

    // MARK: - File I/O

    /// URL of the currently open file (nil for unsaved documents)
    @Published public private(set) var fileURL: URL?

    /// Whether the document has unsaved changes
    @Published public private(set) var hasUnsavedChanges: Bool = false

    /// Track changes
    private var savedSourceCode: String = ""

    /// Load a document from a URL
    public func load(from url: URL) async throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw AlloyDocumentError.invalidEncoding
        }

        self.sourceCode = content
        self.savedSourceCode = content
        self.fileName = url.lastPathComponent
        self.fileURL = url
        self.hasUnsavedChanges = false

        // Clear enumeration state from previous document
        self.instances = []
        self.currentTrace = nil
        self.enumerationTranslator = nil
        self.enumerationClauses = nil
        self.blockingClauses = []
        self.previousSolutions = []
        self.wasCheckCommand = false

        // Add to recent files
        RecentFilesManager.shared.addRecentFile(url)

        await analyze()
    }

    /// Save the document to its current URL
    public func save() async throws {
        guard let url = fileURL else {
            throw AlloyDocumentError.noFileURL
        }
        try await save(to: url)
    }

    /// Save the document to a specific URL
    public func save(to url: URL) async throws {
        // Prevent concurrent saves
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = sourceCode.data(using: .utf8) else {
            throw AlloyDocumentError.invalidEncoding
        }

        try data.write(to: url, options: .atomic)

        self.savedSourceCode = sourceCode
        self.fileName = url.lastPathComponent
        self.fileURL = url
        self.hasUnsavedChanges = false
    }

    /// Create a new empty document
    public func newDocument() {
        sourceCode = "// New Alloy Model\nmodule untitled\n\n"
        savedSourceCode = ""
        fileName = "untitled.als"
        fileURL = nil
        hasUnsavedChanges = true
        diagnostics = []
        instances = []
        currentTrace = nil

        // Clear enumeration state to prevent stale data from previous document
        enumerationTranslator = nil
        enumerationClauses = nil
        blockingClauses = []
        previousSolutions = []
        wasCheckCommand = false

        Task {
            await analyze()
        }
    }

    /// Update unsaved changes tracking
    private func checkForUnsavedChanges() {
        hasUnsavedChanges = sourceCode != savedSourceCode
    }

    // MARK: - Report Generation

    /// Generate a validation report from the current state
    public func generateReport() {
        guard let symbolTable = symbolTable else {
            // Generate a minimal report even without a symbol table
            validationReport = ValidationReport(
                modelName: fileName,
                statistics: ModelStatistics(
                    errorCount: diagnostics.filter { $0.severity == .error }.count,
                    warningCount: diagnostics.filter { $0.severity == .warning }.count
                ),
                diagnostics: diagnostics
            )
            return
        }

        // Count commands from the AST paragraphs
        let commandCount = module?.paragraphs.filter { $0 is RunCmdNode || $0 is CheckCmdNode }.count ?? 0

        // Collect statistics
        let stats = ModelStatistics(
            signatureCount: symbolTable.signatures.count,
            predicateCount: symbolTable.predicates.count,
            functionCount: symbolTable.functions.count,
            assertionCount: symbolTable.assertions.count,
            commandCount: commandCount,
            factCount: symbolTable.facts.count,
            errorCount: diagnostics.filter { $0.severity == .error }.count,
            warningCount: diagnostics.filter { $0.severity == .warning }.count
        )

        // Collect signature info
        let signatureInfos: [SignatureInfo] = symbolTable.signatures.values.map { sig in
            var modifiers: [String] = []
            if sig.sigType.isAbstract { modifiers.append("abstract") }
            if sig.sigType.multiplicity == .one { modifiers.append("one") }
            if sig.sigType.multiplicity == .lone { modifiers.append("lone") }
            if sig.sigType.multiplicity == .some { modifiers.append("some") }

            return SignatureInfo(
                name: sig.name,
                modifiers: modifiers,
                extendsName: sig.parent?.name,
                fieldCount: sig.fields.count
            )
        }.sorted { $0.name < $1.name }

        // Collect predicate info
        let predicateInfos: [PredicateInfo] = symbolTable.predicates.values.map { pred in
            let params = pred.parameters.map { param in
                "\(param.name): \(param.type.description)"
            }
            return PredicateInfo(name: pred.name, parameters: params)
        }.sorted { $0.name < $1.name }

        // Collect function info
        let functionInfos: [FunctionInfo] = symbolTable.functions.values.map { fn in
            let params = fn.parameters.map { param in
                "\(param.name): \(param.type.description)"
            }
            return FunctionInfo(
                name: fn.name,
                parameters: params,
                returnType: fn.type.description
            )
        }.sorted { $0.name < $1.name }

        // Collect assertion info
        let assertionInfos: [AssertionInfo] = symbolTable.assertions.values.map { assertion in
            AssertionInfo(name: assertion.name)
        }.sorted { $0.name < $1.name }

        // Collect command info from AST paragraphs
        var commandInfos: [CommandInfo] = []
        if let paragraphs = module?.paragraphs {
            for para in paragraphs {
                if let runCmd = para as? RunCmdNode {
                    let scopeStr = runCmd.scope?.defaultScope.map { "\($0)" } ?? "default"
                    commandInfos.append(CommandInfo(
                        commandType: .run,
                        targetName: runCmd.name ?? runCmd.targetName?.simpleName ?? "(unnamed)",
                        scope: scopeStr
                    ))
                } else if let checkCmd = para as? CheckCmdNode {
                    let scopeStr = checkCmd.scope?.defaultScope.map { "\($0)" } ?? "default"
                    commandInfos.append(CommandInfo(
                        commandType: .check,
                        targetName: checkCmd.name ?? checkCmd.targetName?.simpleName ?? "(unnamed)",
                        scope: scopeStr
                    ))
                }
            }
        }

        // Build test results from accumulated results or current state
        var testResults = accumulatedTestResults

        // If we have a current instance/result that's not in accumulated, add it
        if testResults.isEmpty && !instances.isEmpty {
            let resultStatus: TestStatus = wasCheckCommand ? .warning : .pass
            let message = wasCheckCommand ? "Counterexample found" : "Instance found"
            testResults.append(TestResult(
                name: "Last run",
                commandType: wasCheckCommand ? .check : .run,
                status: resultStatus,
                message: message,
                solveTimeMs: lastSolveTimeMs,
                instanceCount: instances.count
            ))
        }

        // Create the report
        validationReport = ValidationReport(
            modelName: fileName,
            statistics: stats,
            testResults: testResults,
            signatures: signatureInfos,
            predicates: predicateInfos,
            functions: functionInfos,
            assertions: assertionInfos,
            commands: commandInfos,
            solverStats: lastSolverStats,
            diagnostics: diagnostics
        )
    }

    /// Clear the accumulated test results
    public func clearTestResults() {
        accumulatedTestResults = []
        validationReport = nil
    }

    /// Record a test result
    private func recordTestResult(name: String, commandType: ReportCommandType, status: TestStatus, message: String, solveTimeMs: Double?) {
        let result = TestResult(
            name: name,
            commandType: commandType,
            status: status,
            message: message,
            solveTimeMs: solveTimeMs,
            instanceCount: instances.count
        )
        accumulatedTestResults.append(result)
    }
}

// MARK: - Alloy Document Errors

public enum AlloyDocumentError: LocalizedError {
    case invalidEncoding
    case noFileURL

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The file encoding is not supported"
        case .noFileURL:
            return "No file URL to save to"
        }
    }
}
