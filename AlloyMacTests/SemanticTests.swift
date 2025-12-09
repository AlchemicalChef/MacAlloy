import XCTest
@testable import AlloyMac

/// Tests for the Semantic Analyzer
final class SemanticTests: XCTestCase {

    // MARK: - Helper

    private func analyze(_ source: String) -> SemanticAnalyzer {
        let parser = Parser(source: source)
        let module = parser.parse()!
        let analyzer = SemanticAnalyzer()
        analyzer.analyze(module)
        return analyzer
    }

    // MARK: - Basic Symbol Table Tests

    func testEmptyModule() {
        let analyzer = analyze("")
        XCTAssertFalse(analyzer.hasErrors)
        XCTAssertTrue(analyzer.symbolTable.signatures.isEmpty)
    }

    func testSimpleSignature() {
        let analyzer = analyze("sig Person {}")
        XCTAssertFalse(analyzer.hasErrors)
        XCTAssertEqual(analyzer.symbolTable.signatures.count, 1)
        XCTAssertNotNil(analyzer.symbolTable.lookupSig("Person"))
    }

    func testMultipleSignatures() {
        let analyzer = analyze("""
            sig Person {}
            sig Animal {}
            sig Plant {}
            """)
        XCTAssertFalse(analyzer.hasErrors)
        XCTAssertEqual(analyzer.symbolTable.signatures.count, 3)
    }

    func testAbstractSignature() {
        let analyzer = analyze("abstract sig Animal {}")
        XCTAssertFalse(analyzer.hasErrors)
        let sig = analyzer.symbolTable.lookupSig("Animal")
        XCTAssertTrue(sig?.sigType.isAbstract ?? false)
    }

    func testOneSignature() {
        let analyzer = analyze("one sig Singleton {}")
        XCTAssertFalse(analyzer.hasErrors)
        let sig = analyzer.symbolTable.lookupSig("Singleton")
        XCTAssertEqual(sig?.sigType.multiplicity, .one)
    }

    func testVarSignature() {
        let analyzer = analyze("var sig State {}")
        XCTAssertFalse(analyzer.hasErrors)
        let sig = analyzer.symbolTable.lookupSig("State")
        XCTAssertTrue(sig?.sigType.isVariable ?? false)
    }

    // MARK: - Signature Inheritance Tests

    func testSignatureExtends() {
        let analyzer = analyze("""
            sig Animal {}
            sig Dog extends Animal {}
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let dog = analyzer.symbolTable.lookupSig("Dog")
        let animal = analyzer.symbolTable.lookupSig("Animal")
        XCTAssertEqual(dog?.parent?.name, "Animal")
        XCTAssertTrue(animal?.children.contains(where: { $0.name == "Dog" }) ?? false)
    }

    func testSignatureExtendsChain() {
        let analyzer = analyze("""
            sig Animal {}
            sig Mammal extends Animal {}
            sig Dog extends Mammal {}
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let dog = analyzer.symbolTable.lookupSig("Dog")
        XCTAssertEqual(dog?.ancestors.count, 2)
    }

    func testSignatureIn() {
        let analyzer = analyze("""
            sig Person {}
            sig Employee in Person {}
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let employee = analyzer.symbolTable.lookupSig("Employee")
        XCTAssertEqual(employee?.subsetOf.count, 1)
        XCTAssertEqual(employee?.subsetOf.first?.name, "Person")
    }

    func testUndefinedParent() {
        let analyzer = analyze("sig Dog extends Animal {}")
        XCTAssertTrue(analyzer.hasErrors)
        XCTAssertTrue(analyzer.diagnostics.errors.contains { $0.code == .undefinedSignature })
    }

    // MARK: - Field Tests

    func testSimpleField() {
        let analyzer = analyze("sig Person { name: String }")
        XCTAssertFalse(analyzer.hasErrors)
        let person = analyzer.symbolTable.lookupSig("Person")
        XCTAssertEqual(person?.fields.count, 1)
        XCTAssertEqual(person?.fields.first?.name, "name")
    }

    func testMultipleFields() {
        let analyzer = analyze("""
            sig Person {
                name: String,
                age: Int
            }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let person = analyzer.symbolTable.lookupSig("Person")
        XCTAssertEqual(person?.fields.count, 2)
    }

    func testRelationField() {
        let analyzer = analyze("""
            sig Person {
                friends: set Person
            }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let person = analyzer.symbolTable.lookupSig("Person")
        let friends = person?.fields.first
        XCTAssertNotNil(friends)
    }

    func testVarField() {
        let analyzer = analyze("""
            sig Mood {}
            sig Person {
                var mood: one Mood
            }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let person = analyzer.symbolTable.lookupSig("Person")
        XCTAssertTrue(person?.fields.first?.isVariable ?? false)
    }

    func testDisjField() {
        let analyzer = analyze("""
            sig Node {
                disj left, right: lone Node
            }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let node = analyzer.symbolTable.lookupSig("Node")
        XCTAssertEqual(node?.fields.count, 2)
        XCTAssertTrue(node?.fields.first?.isDisjoint ?? false)
    }

    func testInheritedFields() {
        let analyzer = analyze("""
            sig Animal { name: String }
            sig Dog extends Animal { breed: String }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let dog = analyzer.symbolTable.lookupSig("Dog")
        XCTAssertEqual(dog?.fields.count, 1)  // Only direct fields
        XCTAssertEqual(dog?.allFields.count, 2)  // Including inherited
    }

    // MARK: - Predicate Tests

    func testSimplePredicate() {
        let analyzer = analyze("pred show {}")
        XCTAssertFalse(analyzer.hasErrors)
        XCTAssertEqual(analyzer.symbolTable.predicates.count, 1)
        XCTAssertNotNil(analyzer.symbolTable.lookupPred("show"))
    }

    func testPredicateWithParams() {
        let analyzer = analyze("""
            sig Node {}
            pred connected[a, b: Node] { some a & b }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let pred = analyzer.symbolTable.lookupPred("connected")
        XCTAssertEqual(pred?.parameters.count, 2)
    }

    func testMethodStylePredicate() {
        let analyzer = analyze("""
            sig Person {}
            pred Person.greet[] {}
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let pred = analyzer.symbolTable.predicates["Person.greet"]
        XCTAssertNotNil(pred)
        XCTAssertEqual(pred?.receiver?.name, "Person")
    }

    // MARK: - Function Tests

    func testSimpleFunction() {
        let analyzer = analyze("""
            sig Person {}
            fun count: Int { #Person }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        XCTAssertEqual(analyzer.symbolTable.functions.count, 1)
    }

    func testFunctionWithParams() {
        let analyzer = analyze("fun add[x, y: Int]: Int { x }")
        XCTAssertFalse(analyzer.hasErrors)
        let fun = analyzer.symbolTable.lookupFun("add")
        XCTAssertEqual(fun?.parameters.count, 2)
    }

    // MARK: - Fact Tests

    func testAnonymousFact() {
        let analyzer = analyze("""
            sig Person {}
            fact { some Person }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        XCTAssertEqual(analyzer.symbolTable.facts.count, 1)
    }

    func testNamedFact() {
        let analyzer = analyze("""
            sig Person { friends: set Person }
            fact NoSelfFriend { no p: Person | p in p.friends }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        XCTAssertEqual(analyzer.symbolTable.facts.first?.name, "NoSelfFriend")
    }

    // MARK: - Assertion Tests

    func testSimpleAssertion() {
        let analyzer = analyze("""
            sig Person {}
            assert Safety { always some Person }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        XCTAssertNotNil(analyzer.symbolTable.lookupAssert("Safety"))
    }

    // MARK: - Enum Tests

    func testSimpleEnum() {
        let analyzer = analyze("enum Color { Red, Green, Blue }")
        XCTAssertFalse(analyzer.hasErrors)
        XCTAssertEqual(analyzer.symbolTable.enums.count, 1)
        let color = analyzer.symbolTable.enums["Color"]
        XCTAssertEqual(color?.values.count, 3)
    }

    func testEnumValuesAsSymbols() {
        let analyzer = analyze("enum Color { Red, Green, Blue }")
        XCTAssertFalse(analyzer.hasErrors)
        // Enum values should be accessible as symbols
        XCTAssertNotNil(analyzer.symbolTable.lookup("Red"))
        XCTAssertNotNil(analyzer.symbolTable.lookup("Green"))
        XCTAssertNotNil(analyzer.symbolTable.lookup("Blue"))
    }

    // MARK: - Duplicate Definition Tests

    func testDuplicateSignature() {
        let analyzer = analyze("""
            sig Person {}
            sig Person {}
            """)
        XCTAssertTrue(analyzer.hasErrors)
        XCTAssertTrue(analyzer.diagnostics.errors.contains { $0.code == .duplicateDefinition })
    }

    func testDuplicatePredicate() {
        let analyzer = analyze("""
            pred show {}
            pred show {}
            """)
        XCTAssertTrue(analyzer.hasErrors)
        XCTAssertTrue(analyzer.diagnostics.errors.contains { $0.code == .duplicateDefinition })
    }

    func testDuplicateField() {
        let analyzer = analyze("""
            sig Person {
                name: String,
                name: Int
            }
            """)
        XCTAssertTrue(analyzer.hasErrors)
        XCTAssertTrue(analyzer.diagnostics.errors.contains { $0.code == .duplicateDefinition })
    }

    // MARK: - Type System Tests

    func testSigTypeCreation() {
        let analyzer = analyze("sig Person {}")
        let person = analyzer.symbolTable.lookupSig("Person")
        XCTAssertEqual(person?.sigType.arity, 1)
    }

    func testRelationTypeArity() {
        let analyzer = analyze("""
            sig Node {}
            sig Graph { edges: Node -> Node }
            """)
        XCTAssertFalse(analyzer.hasErrors)
        let graph = analyzer.symbolTable.lookupSig("Graph")
        let edges = graph?.fields.first
        // edges type should be Node -> Node, arity 2
        XCTAssertEqual(edges?.type.arity, 2)
    }

    func testSubtypeRelationship() {
        let analyzer = analyze("""
            sig Animal {}
            sig Dog extends Animal {}
            """)
        let dog = analyzer.symbolTable.lookupSig("Dog")!
        let animal = analyzer.symbolTable.lookupSig("Animal")!
        XCTAssertTrue(dog.sigType.isSubtypeOf(animal.sigType))
        XCTAssertFalse(animal.sigType.isSubtypeOf(dog.sigType))
    }

    // MARK: - Type Checking Tests

    func testUndefinedName() {
        let analyzer = analyze("""
            fact { some Undefined }
            """)
        XCTAssertTrue(analyzer.hasErrors)
        XCTAssertTrue(analyzer.diagnostics.errors.contains { $0.code == .undefinedName })
    }

    func testValidNameReference() {
        let analyzer = analyze("""
            sig Person {}
            fact { some Person }
            """)
        XCTAssertFalse(analyzer.hasErrors)
    }

    func testQuantifiedVariables() {
        let analyzer = analyze("""
            sig Person { friends: set Person }
            fact { all p: Person | some p.friends }
            """)
        XCTAssertFalse(analyzer.hasErrors)
    }

    func testLetBinding() {
        let analyzer = analyze("""
            sig Person { friends: set Person }
            fact { let F = Person.friends | some F }
            """)
        XCTAssertFalse(analyzer.hasErrors)
    }

    // MARK: - Temporal Tests

    func testPrimedVariableField() {
        let analyzer = analyze("""
            sig State {}
            sig System {
                var current: one State
            }
            pred change { System.current' != System.current }
            """)
        XCTAssertFalse(analyzer.hasErrors)
    }

    func testPrimedNonVariableField() {
        let analyzer = analyze("""
            sig Person { name: String }
            pred change { Person.name' != Person.name }
            """)
        XCTAssertTrue(analyzer.hasErrors)
        XCTAssertTrue(analyzer.diagnostics.errors.contains { $0.code == .primedNonVariable })
    }

    func testPrimedVariableSignature() {
        let analyzer = analyze("""
            var sig Active {}
            pred change { Active' != Active }
            """)
        XCTAssertFalse(analyzer.hasErrors)
    }

    func testPrimedNonVariableSignature() {
        let analyzer = analyze("""
            sig Person {}
            pred change { Person' != Person }
            """)
        XCTAssertTrue(analyzer.hasErrors)
        XCTAssertTrue(analyzer.diagnostics.errors.contains { $0.code == .primedNonVariable })
    }

    // MARK: - Arity Checking Tests

    func testArityMismatchInComparison() {
        let analyzer = analyze("""
            sig A {}
            sig B {}
            sig R { r: A -> B }
            fact { A = R.r }
            """)
        XCTAssertTrue(analyzer.hasErrors)
        XCTAssertTrue(analyzer.diagnostics.errors.contains { $0.code == .arityMismatch })
    }

    func testValidArityComparison() {
        let analyzer = analyze("""
            sig A {}
            sig B {}
            fact { A = B }
            """)
        XCTAssertFalse(analyzer.hasErrors)
    }

    // MARK: - Full Model Tests

    func testCompleteModel() {
        let analyzer = analyze("""
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

            pred changeMood[p: Person, m: Mood] {
                p.mood' = m
            }

            assert AlwaysHappy {
                always some p: Person | p.mood = Happy
            }

            run changeMood for 3 Person, 5 steps
            check AlwaysHappy for 3 Person, 10 steps
            """)
        XCTAssertFalse(analyzer.hasErrors, "Errors: \(analyzer.diagnostics.errors.map { $0.message })")

        // Check symbol table contents
        XCTAssertEqual(analyzer.symbolTable.signatures.count, 4)  // Person, Mood, Happy, Sad
        XCTAssertEqual(analyzer.symbolTable.predicates.count, 1)  // changeMood
        XCTAssertEqual(analyzer.symbolTable.assertions.count, 1)  // AlwaysHappy
        XCTAssertEqual(analyzer.symbolTable.facts.count, 1)       // NoSelfFriend

        // Check inheritance
        let happy = analyzer.symbolTable.lookupSig("Happy")
        XCTAssertEqual(happy?.parent?.name, "Mood")
        XCTAssertEqual(happy?.sigType.multiplicity, .one)

        // Check abstract
        let mood = analyzer.symbolTable.lookupSig("Mood")
        XCTAssertTrue(mood?.sigType.isAbstract ?? false)

        // Check variable field
        let person = analyzer.symbolTable.lookupSig("Person")
        let moodField = person?.fields.first { $0.name == "mood" }
        XCTAssertTrue(moodField?.isVariable ?? false)
    }
}
