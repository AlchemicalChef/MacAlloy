import Foundation

// MARK: - Validation Report

/// Complete validation report for an Alloy model analysis
public struct ValidationReport: Sendable {
    public let generatedAt: Date
    public let modelName: String
    public let statistics: ModelStatistics
    public let testResults: [TestResult]
    public let signatures: [SignatureInfo]
    public let predicates: [PredicateInfo]
    public let functions: [FunctionInfo]
    public let assertions: [AssertionInfo]
    public let commands: [CommandInfo]
    public let solverStats: ReportSolverStats?
    public let diagnostics: [Diagnostic]

    public init(
        generatedAt: Date = Date(),
        modelName: String,
        statistics: ModelStatistics,
        testResults: [TestResult] = [],
        signatures: [SignatureInfo] = [],
        predicates: [PredicateInfo] = [],
        functions: [FunctionInfo] = [],
        assertions: [AssertionInfo] = [],
        commands: [CommandInfo] = [],
        solverStats: ReportSolverStats? = nil,
        diagnostics: [Diagnostic] = []
    ) {
        self.generatedAt = generatedAt
        self.modelName = modelName
        self.statistics = statistics
        self.testResults = testResults
        self.signatures = signatures
        self.predicates = predicates
        self.functions = functions
        self.assertions = assertions
        self.commands = commands
        self.solverStats = solverStats
        self.diagnostics = diagnostics
    }

    /// Overall test status based on all test results
    public var overallStatus: TestStatus {
        if testResults.isEmpty { return .pending }
        if testResults.contains(where: { $0.status == .fail }) { return .fail }
        if testResults.contains(where: { $0.status == .warning }) { return .warning }
        if testResults.allSatisfy({ $0.status == .pass }) { return .pass }
        return .pending
    }

    /// Count of passed tests
    public var passedCount: Int {
        testResults.filter { $0.status == .pass }.count
    }

    /// Count of failed tests
    public var failedCount: Int {
        testResults.filter { $0.status == .fail }.count
    }
}

// MARK: - Model Statistics

/// Statistics about the model structure
public struct ModelStatistics: Sendable {
    public let signatureCount: Int
    public let predicateCount: Int
    public let functionCount: Int
    public let assertionCount: Int
    public let commandCount: Int
    public let factCount: Int
    public let errorCount: Int
    public let warningCount: Int

    public init(
        signatureCount: Int = 0,
        predicateCount: Int = 0,
        functionCount: Int = 0,
        assertionCount: Int = 0,
        commandCount: Int = 0,
        factCount: Int = 0,
        errorCount: Int = 0,
        warningCount: Int = 0
    ) {
        self.signatureCount = signatureCount
        self.predicateCount = predicateCount
        self.functionCount = functionCount
        self.assertionCount = assertionCount
        self.commandCount = commandCount
        self.factCount = factCount
        self.errorCount = errorCount
        self.warningCount = warningCount
    }
}

// MARK: - Test Result

/// Result of a single run or check command
public struct TestResult: Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let commandType: ReportCommandType
    public let status: TestStatus
    public let message: String
    public let solveTimeMs: Double?
    public let instanceCount: Int

    public init(
        name: String,
        commandType: ReportCommandType,
        status: TestStatus,
        message: String,
        solveTimeMs: Double? = nil,
        instanceCount: Int = 0
    ) {
        self.name = name
        self.commandType = commandType
        self.status = status
        self.message = message
        self.solveTimeMs = solveTimeMs
        self.instanceCount = instanceCount
    }
}

/// Type of command (run or check)
public enum ReportCommandType: String, Sendable {
    case run = "run"
    case check = "check"

    public var displayName: String {
        rawValue.capitalized
    }

    public var iconName: String {
        switch self {
        case .run: return "play.fill"
        case .check: return "checkmark.shield.fill"
        }
    }
}

/// Status of a test result
public enum TestStatus: String, Sendable {
    case pass = "pass"
    case fail = "fail"
    case warning = "warning"
    case pending = "pending"

    public var iconName: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .pending: return "clock.fill"
        }
    }
}

// MARK: - Signature Info

/// Information about a signature for the report
public struct SignatureInfo: Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let modifiers: [String]
    public let extendsName: String?
    public let fieldCount: Int

    public init(name: String, modifiers: [String] = [], extendsName: String? = nil, fieldCount: Int = 0) {
        self.name = name
        self.modifiers = modifiers
        self.extendsName = extendsName
        self.fieldCount = fieldCount
    }

    public var modifiersString: String {
        modifiers.isEmpty ? "-" : modifiers.joined(separator: ", ")
    }
}

// MARK: - Predicate Info

/// Information about a predicate for the report
public struct PredicateInfo: Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let parameters: [String]

    public init(name: String, parameters: [String] = []) {
        self.name = name
        self.parameters = parameters
    }

    public var signature: String {
        if parameters.isEmpty {
            return "pred \(name)"
        } else {
            return "pred \(name)[\(parameters.joined(separator: ", "))]"
        }
    }
}

// MARK: - Function Info

/// Information about a function for the report
public struct FunctionInfo: Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let parameters: [String]
    public let returnType: String

    public init(name: String, parameters: [String] = [], returnType: String = "univ") {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
    }

    public var signature: String {
        if parameters.isEmpty {
            return "fun \(name): \(returnType)"
        } else {
            return "fun \(name)[\(parameters.joined(separator: ", "))]: \(returnType)"
        }
    }
}

// MARK: - Assertion Info

/// Information about an assertion for the report
public struct AssertionInfo: Sendable, Identifiable {
    public let id = UUID()
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

// MARK: - Command Info

/// Information about a command for the report
public struct CommandInfo: Sendable, Identifiable {
    public let id = UUID()
    public let commandType: ReportCommandType
    public let targetName: String
    public let scope: String
    public let result: TestStatus?

    public init(commandType: ReportCommandType, targetName: String, scope: String, result: TestStatus? = nil) {
        self.commandType = commandType
        self.targetName = targetName
        self.scope = scope
        self.result = result
    }
}

// MARK: - Solver Stats

/// Solver statistics for the report
public struct ReportSolverStats: Sendable {
    public let decisions: Int
    public let propagations: Int
    public let conflicts: Int
    public let learnedClauses: Int
    public let restarts: Int
    public let solveTimeMs: Double
    public let variableCount: Int
    public let clauseCount: Int

    public init(
        decisions: Int = 0,
        propagations: Int = 0,
        conflicts: Int = 0,
        learnedClauses: Int = 0,
        restarts: Int = 0,
        solveTimeMs: Double = 0,
        variableCount: Int = 0,
        clauseCount: Int = 0
    ) {
        self.decisions = decisions
        self.propagations = propagations
        self.conflicts = conflicts
        self.learnedClauses = learnedClauses
        self.restarts = restarts
        self.solveTimeMs = solveTimeMs
        self.variableCount = variableCount
        self.clauseCount = clauseCount
    }

    /// Formatted solve time string
    public var formattedSolveTime: String {
        if solveTimeMs < 1000 {
            return String(format: "%.1f ms", solveTimeMs)
        } else {
            return String(format: "%.2f s", solveTimeMs / 1000)
        }
    }
}
