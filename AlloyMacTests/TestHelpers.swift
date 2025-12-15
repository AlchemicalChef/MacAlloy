import XCTest
@testable import AlloyMac

// MARK: - Test Error

/// Error type for test failures
enum TestError: Error, LocalizedError {
    case parseFailed
    case analysisError(String)
    case translationError(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed:
            return "Failed to parse Alloy source"
        case .analysisError(let message):
            return "Semantic analysis failed: \(message)"
        case .translationError(let message):
            return "Translation failed: \(message)"
        }
    }
}

// MARK: - Test Helpers

/// Common test helper functions for AlloyMac tests
enum TestHelpers {

    // MARK: - Parsing

    /// Parse Alloy source code into an AST
    /// - Parameter source: The Alloy source code
    /// - Returns: The parsed ModuleNode, or nil if parsing failed
    static func parse(_ source: String) -> ModuleNode? {
        let parser = Parser(source: source)
        return parser.parse()
    }

    /// Parse Alloy source code, throwing if parsing fails
    /// - Parameter source: The Alloy source code
    /// - Returns: The parsed ModuleNode
    /// - Throws: TestError.parseFailed if parsing fails
    static func parseOrThrow(_ source: String) throws -> ModuleNode {
        guard let module = parse(source) else {
            throw TestError.parseFailed
        }
        return module
    }

    // MARK: - Semantic Analysis

    /// Perform semantic analysis on Alloy source code
    /// - Parameter source: The Alloy source code
    /// - Returns: The SemanticAnalyzer with results
    static func analyze(_ source: String) -> SemanticAnalyzer {
        let parser = Parser(source: source)
        let module = parser.parse()!
        let analyzer = SemanticAnalyzer()
        analyzer.analyze(module)
        return analyzer
    }

    /// Parse and analyze source, returning just the symbol table
    /// - Parameter source: The Alloy source code
    /// - Returns: The populated SymbolTable
    /// - Throws: TestError if parsing or analysis fails
    static func analyzeModel(_ source: String) throws -> SymbolTable {
        let parser = Parser(source: source)
        guard let module = parser.parse() else {
            throw TestError.parseFailed
        }
        let analyzer = SemanticAnalyzer()
        try analyzer.analyze(module)
        return analyzer.symbolTable
    }

    // MARK: - Translation

    /// Create a translator for the given Alloy source
    /// - Parameters:
    ///   - source: The Alloy source code
    ///   - scope: The default scope (default: 3)
    /// - Returns: An AlloyTranslator ready for use
    /// - Throws: TestError if parsing or analysis fails
    static func createTranslator(_ source: String, scope: Int = 3) throws -> AlloyTranslator {
        let symbolTable = try analyzeModel(source)
        let cmdScope = CommandScope(defaultScope: scope)
        return AlloyTranslator(symbolTable: symbolTable, scope: cmdScope)
    }

    // MARK: - Solving

    /// Solve a translated model using the SAT solver
    /// - Parameter translator: The translator with encoded constraints
    /// - Returns: The solve result (sat/unsat/unknown)
    static func solve(_ translator: AlloyTranslator) -> SolveResult {
        let clauses = translator.clauses.map { $0.map { Int($0) } }
        let solver = CDCLSolver()

        let result = solver.solve(numVariables: translator.variableCount, clauses: clauses)

        switch result {
        case .satisfiable(let model):
            let instance = translator.extractInstance(solution: model)
            return .sat(instance)
        case .unsatisfiable:
            return .unsat
        case .unknown:
            return .unknown("unknown")
        }
    }

    /// Translate facts and solve in one step
    /// - Parameters:
    ///   - source: The Alloy source code
    ///   - scope: The default scope (default: 3)
    /// - Returns: The solve result
    /// - Throws: TestError if translation fails
    static func translateAndSolve(_ source: String, scope: Int = 3) throws -> SolveResult {
        let translator = try createTranslator(source, scope: scope)
        translator.translateFacts()
        return solve(translator)
    }

    // MARK: - Assertions

    /// Assert that a solve result is satisfiable
    /// - Parameters:
    ///   - result: The solve result to check
    ///   - message: Optional failure message
    ///   - file: Source file (for XCTest)
    ///   - line: Source line (for XCTest)
    static func assertSat(
        _ result: SolveResult,
        _ message: String = "Expected satisfiable result",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(result.isSat, message, file: file, line: line)
    }

    /// Assert that a solve result is unsatisfiable
    /// - Parameters:
    ///   - result: The solve result to check
    ///   - message: Optional failure message
    ///   - file: Source file (for XCTest)
    ///   - line: Source line (for XCTest)
    static func assertUnsat(
        _ result: SolveResult,
        _ message: String = "Expected unsatisfiable result",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertFalse(result.isSat, message, file: file, line: line)
    }
}

