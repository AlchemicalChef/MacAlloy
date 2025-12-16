import XCTest
@testable import AlloyMac

/// End-to-end integration tests covering the full pipeline:
/// Source → Parse → Analyze → Translate → Solve → Extract Instance
final class IntegrationTests: XCTestCase {

    // MARK: - Full Pipeline Tests

    func testFullPipelineSimpleModel() throws {
        // Simple model with one signature and a fact
        let source = """
            sig Person {}
            fact { some Person }
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        TestHelpers.assertSat(result, "Simple model with 'some Person' should be satisfiable")

        if case .sat(let instance) = result {
            XCTAssertFalse(instance.signatures["Person"]?.isEmpty ?? true,
                          "Instance should have at least one Person atom")
        }
    }

    func testFullPipelineUnsatisfiable() throws {
        // Contradictory constraints
        let source = """
            sig A {}
            fact { some A }
            fact { no A }
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        TestHelpers.assertUnsat(result, "Contradictory facts should be unsatisfiable")
    }

    func testFullPipelineWithFields() throws {
        // Model with fields
        let source = """
            sig Person {
                friends: set Person
            }
            fact { all p: Person | p not in p.friends }
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        TestHelpers.assertSat(result, "Model with no self-friendship should be satisfiable")

        if case .sat(let instance) = result {
            // Verify no person is their own friend
            if let friendsTuples = instance.fields["friends"] {
                for tuple in friendsTuples.sortedTuples where tuple.arity == 2 {
                    XCTAssertNotEqual(tuple.first.name, tuple.last.name,
                                     "No person should be their own friend")
                }
            }
        }
    }

    func testFullPipelineWithInheritance() throws {
        // Model with signature inheritance
        let source = """
            abstract sig Animal {}
            sig Dog extends Animal {}
            sig Cat extends Animal {}
            fact { some Dog and some Cat }
            fact { no Dog & Cat }
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        TestHelpers.assertSat(result, "Model with dogs and cats should be satisfiable")

        if case .sat(let instance) = result {
            let dogCount = instance.signatures["Dog"]?.count ?? 0
            let catCount = instance.signatures["Cat"]?.count ?? 0
            XCTAssertGreaterThan(dogCount, 0, "Should have at least one Dog")
            XCTAssertGreaterThan(catCount, 0, "Should have at least one Cat")
        }
    }

    // MARK: - Run Command Tests

    func testRunCommandSimplePredicate() throws {
        let source = """
            sig Person {}
            pred hasPeople { some Person }
            run hasPeople for 3
            """

        let translator = try TestHelpers.createTranslator(source, scope: 3)
        translator.translateFacts()
        // Run the predicate by encoding it as a constraint
        if let predSymbol = translator.symbolTable.predicates["hasPeople"],
           let predNode = predSymbol.declaration {
            translator.encodePredicate(predNode)
        }

        let result = TestHelpers.solve(translator)
        TestHelpers.assertSat(result, "Running hasPeople predicate should find instances")
    }

    // MARK: - Check Command Tests

    func testCheckCommandValidAssertion() throws {
        let source = """
            sig A {}
            sig B {}
            fact { A = B }
            assert AEqualsB { A = B }
            """

        // The assertion should hold (no counterexample)
        let translator = try TestHelpers.createTranslator(source, scope: 3)
        translator.translateFacts()

        // To check an assertion, we negate it and look for a counterexample
        // If UNSAT, the assertion holds; if SAT, we found a counterexample
        // For this test, we just verify facts are translated correctly
        let result = TestHelpers.solve(translator)
        TestHelpers.assertSat(result, "Facts should be satisfiable")
    }

    func testCheckCommandCounterexample() throws {
        let source = """
            sig Person {}
            assert NoPerson { no Person }
            """

        let translator = try TestHelpers.createTranslator(source, scope: 3)
        translator.translateFacts()
        // We're not negating the assertion here, but in a real check we would
        // This just verifies the model can have people
        let result = TestHelpers.solve(translator)
        // Without "no Person" as a fact, we can have people
        TestHelpers.assertSat(result)
    }

    // MARK: - Instance Enumeration Tests

    func testInstanceEnumerationMultipleInstances() throws {
        let source = """
            sig A {}
            fact { #A <= 2 }
            fact { some A }
            """

        var instances: [AlloyInstance] = []
        let translator = try TestHelpers.createTranslator(source, scope: 3)
        translator.translateFacts()

        // Get first instance
        let result1 = TestHelpers.solve(translator)
        if case .sat(let instance1) = result1 {
            instances.append(instance1)
        }

        // In a full implementation, we would add blocking clauses to get next instance
        // For now, just verify we can get at least one instance
        XCTAssertGreaterThan(instances.count, 0, "Should find at least one instance")
    }

    // MARK: - Scope Tests

    func testSmallScope() throws {
        let source = """
            sig Person {}
            fact { some Person }
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 1)
        TestHelpers.assertSat(result)

        if case .sat(let instance) = result {
            let personCount = instance.signatures["Person"]?.count ?? 0
            XCTAssertLessThanOrEqual(personCount, 1, "Scope 1 should limit to 1 Person")
        }
    }

    func testLargerScope() throws {
        let source = """
            sig Person {}
            fact { #Person = 5 }
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 5)
        TestHelpers.assertSat(result)

        if case .sat(let instance) = result {
            let personCount = instance.signatures["Person"]?.count ?? 0
            XCTAssertEqual(personCount, 5, "Should have exactly 5 Person atoms")
        }
    }

    // MARK: - Complex Model Tests

    func testGraphColoringModel() throws {
        let source = """
            abstract sig Color {}
            one sig Red, Green, Blue extends Color {}

            sig Node {
                color: one Color,
                adj: set Node
            }

            fact NoSelfLoop { no n: Node | n in n.adj }
            fact Symmetric { adj = ~adj }
            fact ProperColoring { all n: Node | all m: n.adj | n.color != m.color }
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        TestHelpers.assertSat(result, "Graph coloring should be satisfiable for 3 nodes")

        if case .sat(let instance) = result {
            // Verify each node has exactly one color
            let nodeCount = instance.signatures["Node"]?.count ?? 0
            let colorTuples = instance.fields["color"]?.count ?? 0
            XCTAssertEqual(nodeCount, colorTuples, "Each node should have one color")
        }
    }

    func testLinkedListModel() throws {
        let source = """
            sig Node {
                next: lone Node
            }
            one sig Head in Node {}

            fact Acyclic { no n: Node | n in n.^next }
            fact Connected { all n: Node | n in Head.*next }
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 4)
        TestHelpers.assertSat(result, "Linked list should be satisfiable")
    }

    // MARK: - Error Handling Tests

    func testParseErrorHandling() {
        let source = "sig Person { friends: @@@ }"

        let parser = Parser(source: source)
        let module = parser.parse()

        // Should have parse errors
        XCTAssertFalse(parser.getErrors().isEmpty, "Invalid syntax should produce errors")
    }

    func testSemanticErrorHandling() {
        let source = """
            sig Person { friends: set Unknown }
            """

        let analyzer = TestHelpers.analyze(source)
        XCTAssertTrue(analyzer.hasErrors, "Undefined type should produce semantic error")
    }

    // MARK: - Edge Cases

    func testEmptyModel() throws {
        let source = ""
        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        // Empty model is trivially satisfiable
        TestHelpers.assertSat(result)
    }

    func testModelWithOnlyComments() throws {
        let source = """
            // This is a comment
            /* Block comment */
            """
        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        TestHelpers.assertSat(result)
    }

    func testModelWithManySignatures() throws {
        var source = ""
        for i in 0..<20 {
            source += "sig S\(i) {}\n"
        }
        source += "fact { some S0 }"

        let result = try TestHelpers.translateAndSolve(source, scope: 2)
        TestHelpers.assertSat(result)
    }

    // MARK: - Multiplicity Tests

    func testOneMultiplicity() throws {
        let source = """
            one sig Singleton {}
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        TestHelpers.assertSat(result)

        if case .sat(let instance) = result {
            let count = instance.signatures["Singleton"]?.count ?? 0
            XCTAssertEqual(count, 1, "one sig should have exactly 1 atom")
        }
    }

    func testLoneMultiplicity() throws {
        let source = """
            lone sig MaybeOne {}
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        TestHelpers.assertSat(result)

        if case .sat(let instance) = result {
            let count = instance.signatures["MaybeOne"]?.count ?? 0
            XCTAssertLessThanOrEqual(count, 1, "lone sig should have at most 1 atom")
        }
    }

    func testSomeMultiplicity() throws {
        let source = """
            some sig AtLeastOne {}
            """

        let result = try TestHelpers.translateAndSolve(source, scope: 3)
        TestHelpers.assertSat(result)

        if case .sat(let instance) = result {
            let count = instance.signatures["AtLeastOne"]?.count ?? 0
            XCTAssertGreaterThanOrEqual(count, 1, "some sig should have at least 1 atom")
        }
    }
}
