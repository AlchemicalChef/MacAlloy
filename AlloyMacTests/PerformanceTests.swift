import XCTest
@testable import AlloyMac

/// Performance and stress tests for MacAlloy
final class PerformanceTests: XCTestCase {

    // MARK: - Lexer Performance

    func testLexerPerformanceMediumFile() {
        // Generate a medium-sized source file (~50KB)
        var source = ""
        for i in 0..<500 {
            source += """
                sig Signature\(i) {
                    field\(i): set Signature\(i)
                }

                """
        }

        measure {
            let lexer = Lexer(source: source)
            _ = lexer.scanAllTokens()
        }
    }

    func testLexerPerformanceLargeFile() {
        // Generate a larger source file (~200KB)
        var source = ""
        for i in 0..<2000 {
            source += "sig S\(i) { f\(i): set S\(i) }\n"
        }

        let lexer = Lexer(source: source)
        let start = CFAbsoluteTimeGetCurrent()
        let tokens = lexer.scanAllTokens()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertGreaterThan(tokens.count, 10000, "Should produce many tokens")
        XCTAssertLessThan(elapsed, 5.0, "Lexer should complete in under 5 seconds")
    }

    // MARK: - Parser Performance

    func testParserPerformanceManySignatures() {
        var source = ""
        for i in 0..<200 {
            source += "sig S\(i) {}\n"
        }

        measure {
            let parser = Parser(source: source)
            _ = parser.parse()
        }
    }

    func testParserPerformanceDeepNesting() {
        var source = "fact { "
        for _ in 0..<50 {
            source += "("
        }
        source += "A"
        for _ in 0..<50 {
            source += ")"
        }
        source += " }"

        let start = CFAbsoluteTimeGetCurrent()
        let parser = Parser(source: source)
        _ = parser.parse()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 1.0, "Deep nesting should parse quickly")
    }

    func testParserPerformanceComplexExpressions() {
        // Complex expression with many joins
        var source = "fact { "
        source += "A"
        for _ in 0..<100 {
            source += ".field"
        }
        source += " = none }"

        let start = CFAbsoluteTimeGetCurrent()
        let parser = Parser(source: source)
        _ = parser.parse()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 1.0, "Long join chains should parse quickly")
    }

    // MARK: - Semantic Analysis Performance

    func testSemanticAnalysisPerformanceManyFields() {
        var source = "sig Big {\n"
        for i in 0..<100 {
            source += "    field\(i): set Big"
            if i < 99 { source += "," }
            source += "\n"
        }
        source += "}\n"

        measure {
            let parser = Parser(source: source)
            if let module = parser.parse() {
                let analyzer = SemanticAnalyzer()
                analyzer.analyze(module)
            }
        }
    }

    func testSemanticAnalysisPerformanceDeepInheritance() {
        var source = "sig Base {}\n"
        for i in 1..<50 {
            source += "sig Level\(i) extends Level\(i-1 == 0 ? "Base" : "\(i-1)") {}\n"
        }

        let start = CFAbsoluteTimeGetCurrent()
        let parser = Parser(source: source)
        if let module = parser.parse() {
            let analyzer = SemanticAnalyzer()
            analyzer.analyze(module)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 2.0, "Deep inheritance should analyze quickly")
    }

    // MARK: - SAT Solver Performance

    func testSATSolverPerformanceSmallProblem() {
        // Simple satisfiable problem
        let clauses: [[Int]] = [
            [1, 2],
            [-1, 2],
            [1, -2]
        ]

        measure {
            let solver = CDCLSolver()
            _ = solver.solve(numVariables: 2, clauses: clauses)
        }
    }

    func testSATSolverPerformancePigeonhole3x2() {
        // PHP(3,2) - 3 pigeons, 2 holes - unsatisfiable
        // Variables: x_i_j means pigeon i is in hole j
        // Each pigeon must be in some hole (3 clauses)
        // No two pigeons in same hole (3 clauses per hole = 6 clauses)
        let clauses: [[Int]] = [
            // Pigeon 1 in some hole
            [1, 2],
            // Pigeon 2 in some hole
            [3, 4],
            // Pigeon 3 in some hole
            [5, 6],
            // No two pigeons in hole 1
            [-1, -3], [-1, -5], [-3, -5],
            // No two pigeons in hole 2
            [-2, -4], [-2, -6], [-4, -6]
        ]

        let start = CFAbsoluteTimeGetCurrent()
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 6, clauses: clauses)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        if case .unsatisfiable = result {
            XCTAssertLessThan(elapsed, 1.0, "PHP(3,2) should solve quickly")
        } else {
            XCTFail("PHP(3,2) should be unsatisfiable")
        }
    }

    func testSATSolverPerformanceManyVariables() {
        // Random 3-SAT instance with 50 variables and 200 clauses
        var clauses: [[Int]] = []
        for _ in 0..<200 {
            var clause: [Int] = []
            for _ in 0..<3 {
                let variable = Int.random(in: 1...50)
                let sign = Bool.random() ? 1 : -1
                clause.append(sign * variable)
            }
            clauses.append(clause)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let solver = CDCLSolver()
        _ = solver.solve(numVariables: 50, clauses: clauses)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 5.0, "Random 3-SAT should complete in reasonable time")
    }

    // MARK: - Translation Performance

    func testTranslationPerformanceSimpleModel() throws {
        let source = """
            sig Person { friends: set Person }
            fact { no p: Person | p in p.friends }
            """

        measure {
            do {
                let translator = try TestHelpers.createTranslator(source, scope: 4)
                translator.translateFacts()
            } catch {
                XCTFail("Translation failed: \(error)")
            }
        }
    }

    func testTranslationPerformanceManySignatures() throws {
        var source = ""
        for i in 0..<20 {
            source += "sig S\(i) {}\n"
        }
        source += "fact { some S0 }\n"

        let start = CFAbsoluteTimeGetCurrent()
        let translator = try TestHelpers.createTranslator(source, scope: 3)
        translator.translateFacts()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 2.0, "Many signatures should translate quickly")
    }

    // MARK: - End-to-End Performance

    func testEndToEndPerformanceSimple() throws {
        let source = """
            sig A { b: set B }
            sig B {}
            fact { some A.b }
            """

        measure {
            do {
                _ = try TestHelpers.translateAndSolve(source, scope: 3)
            } catch {
                XCTFail("End-to-end failed: \(error)")
            }
        }
    }

    func testEndToEndPerformanceGraphColoring() throws {
        let source = """
            abstract sig Color {}
            one sig Red, Green, Blue extends Color {}
            sig Node { color: one Color, adj: set Node }
            fact { no n: Node | n in n.adj }
            fact { adj = ~adj }
            fact { all n: Node, m: n.adj | n.color != m.color }
            """

        let start = CFAbsoluteTimeGetCurrent()
        let result = try TestHelpers.translateAndSolve(source, scope: 4)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        TestHelpers.assertSat(result, "Graph coloring should be satisfiable")
        XCTAssertLessThan(elapsed, 10.0, "Graph coloring should complete in reasonable time")
    }

    // MARK: - Memory Stress Tests

    func testMemoryUsageRepeatedSolves() throws {
        let source = """
            sig A {}
            fact { some A }
            """

        // Run many solves to check for memory leaks
        for _ in 0..<100 {
            _ = try TestHelpers.translateAndSolve(source, scope: 3)
        }
        // If we get here without crashing, memory is being managed
    }

    func testMemoryUsageLargeInstance() throws {
        let source = """
            sig Node { next: lone Node }
            fact { #Node = 10 }
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 10)
        TestHelpers.assertSat(result, "Large instance should be satisfiable")

        if case .sat(let instance) = result {
            let nodeCount = instance.signatures["Node"]?.count ?? 0
            XCTAssertEqual(nodeCount, 10, "Should have exactly 10 nodes")
        }
    }

    // MARK: - Timeout Resistance

    func testSolverDoesNotHangOnHardProblem() {
        // Create a problem that could be slow but should terminate
        // PHP(4,3) is harder than PHP(3,2) but still tractable
        var clauses: [[Int]] = []

        // 4 pigeons, 3 holes
        // Variables 1-3: pigeon 1 in holes 1-3
        // Variables 4-6: pigeon 2 in holes 1-3
        // etc.

        // Each pigeon in some hole
        clauses.append([1, 2, 3])      // Pigeon 1
        clauses.append([4, 5, 6])      // Pigeon 2
        clauses.append([7, 8, 9])      // Pigeon 3
        clauses.append([10, 11, 12])   // Pigeon 4

        // No two pigeons in same hole
        for hole in 0..<3 {
            for p1 in 0..<4 {
                for p2 in (p1+1)..<4 {
                    let v1 = p1 * 3 + hole + 1
                    let v2 = p2 * 3 + hole + 1
                    clauses.append([-v1, -v2])
                }
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 12, clauses: clauses)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        if case .unsatisfiable = result {
            XCTAssertLessThan(elapsed, 10.0, "PHP(4,3) should complete quickly")
        } else {
            XCTFail("PHP(4,3) should be unsatisfiable")
        }
    }
}
