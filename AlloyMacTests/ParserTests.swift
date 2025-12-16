import XCTest
@testable import AlloyMac

/// Tests for the Alloy 6.2 Parser
final class ParserTests: XCTestCase {

    // MARK: - Helper

    private func parse(_ source: String) -> ModuleNode? {
        let parser = Parser(source: source)
        return parser.parse()
    }

    // MARK: - Empty Module

    func testEmptyModule() {
        let module = parse("")
        XCTAssertNotNil(module)
        XCTAssertNil(module?.moduleDecl)
        XCTAssertTrue(module?.opens.isEmpty ?? false)
        XCTAssertTrue(module?.paragraphs.isEmpty ?? false)
    }

    // MARK: - Module Declaration

    func testModuleDeclaration() {
        let module = parse("module example")
        XCTAssertNotNil(module?.moduleDecl)
        XCTAssertEqual(module?.moduleDecl?.name.simpleName, "example")
    }

    func testQualifiedModuleName() {
        let module = parse("module util/ordering")
        XCTAssertNotNil(module?.moduleDecl)
        XCTAssertEqual(module?.moduleDecl?.name.parts.count, 2)
    }

    func testParameterizedModule() {
        let module = parse("module util/ordering[Elem]")
        XCTAssertNotNil(module?.moduleDecl)
        XCTAssertEqual(module?.moduleDecl?.parameters.count, 1)
        XCTAssertEqual(module?.moduleDecl?.parameters.first?.name, "Elem")
    }

    // MARK: - Open (Import) Statements

    func testSimpleOpen() {
        let module = parse("open util/ordering")
        XCTAssertEqual(module?.opens.count, 1)
        XCTAssertEqual(module?.opens.first?.modulePath.simpleName, "ordering")
    }

    func testOpenWithArguments() {
        let module = parse("open util/ordering[State]")
        XCTAssertEqual(module?.opens.first?.arguments.count, 1)
        XCTAssertEqual(module?.opens.first?.arguments.first?.simpleName, "State")
    }

    func testOpenWithAlias() {
        let module = parse("open util/ordering[State] as ord")
        XCTAssertEqual(module?.opens.first?.alias?.name, "ord")
    }

    // MARK: - Signature Declarations

    func testSimpleSignature() {
        let module = parse("sig Person {}")
        XCTAssertEqual(module?.paragraphs.count, 1)
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertNotNil(sig)
        XCTAssertEqual(sig?.name, "Person")
        XCTAssertFalse(sig?.isAbstract ?? true)
    }

    func testAbstractSignature() {
        let module = parse("abstract sig Animal {}")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertTrue(sig?.isAbstract ?? false)
    }

    func testOneSignature() {
        let module = parse("one sig Singleton {}")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.multiplicity, .one)
    }

    func testLoneSignature() {
        let module = parse("lone sig Optional {}")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.multiplicity, .lone)
    }

    func testSomeSignature() {
        let module = parse("some sig Required {}")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.multiplicity, .some)
    }

    func testVarSignature() {
        let module = parse("var sig State {}")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertTrue(sig?.isVariable ?? false)
    }

    func testSignatureExtends() {
        let module = parse("sig Student extends Person {}")
        let sig = module?.paragraphs.first as? SigDeclNode
        if case .extends(let parent) = sig?.ext {
            XCTAssertEqual(parent.simpleName, "Person")
        } else {
            XCTFail("Expected extends clause")
        }
    }

    func testSignatureIn() {
        let module = parse("sig Employee in Person {}")
        let sig = module?.paragraphs.first as? SigDeclNode
        if case .subset(let parents) = sig?.ext {
            XCTAssertEqual(parents.count, 1)
            XCTAssertEqual(parents.first?.simpleName, "Person")
        } else {
            XCTFail("Expected in clause")
        }
    }

    func testMultipleSignatureNames() {
        let module = parse("sig A, B, C {}")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.names.count, 3)
    }

    // MARK: - Field Declarations

    func testSimpleField() {
        let module = parse("sig Person { name: String }")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.fields.count, 1)
        XCTAssertEqual(sig?.fields.first?.names.first?.name, "name")
    }

    func testSetField() {
        let module = parse("sig Person { friends: set Person }")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.fields.count, 1)
    }

    func testLoneField() {
        let module = parse("sig Person { spouse: lone Person }")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.fields.count, 1)
    }

    func testVarField() {
        let module = parse("sig Person { var mood: Mood }")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertTrue(sig?.fields.first?.isVariable ?? false)
    }

    func testDisjField() {
        let module = parse("sig Node { disj left, right: lone Node }")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertTrue(sig?.fields.first?.isDisjoint ?? false)
        XCTAssertEqual(sig?.fields.first?.names.count, 2)
    }

    func testRelationField() {
        let module = parse("sig Graph { edges: Node -> Node }")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.fields.count, 1)
    }

    func testMultipleFields() {
        let module = parse("sig Person { name: String, age: Int }")
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.fields.count, 2)
    }

    // MARK: - Fact Declarations

    func testAnonymousFact() {
        let module = parse("fact { some Person }")
        let fact = module?.paragraphs.first as? FactDeclNode
        XCTAssertNotNil(fact)
        XCTAssertNil(fact?.name)
    }

    func testNamedFact() {
        let module = parse("fact NoSelfFriend { no p: Person | p in p.friends }")
        let fact = module?.paragraphs.first as? FactDeclNode
        XCTAssertEqual(fact?.name, "NoSelfFriend")
    }

    // MARK: - Predicate Declarations

    func testSimplePredicate() {
        let module = parse("pred show {}")
        let pred = module?.paragraphs.first as? PredDeclNode
        XCTAssertNotNil(pred)
        XCTAssertEqual(pred?.name, "show")
        XCTAssertTrue(pred?.params.isEmpty ?? false)
    }

    func testPredicateWithParams() {
        let module = parse("pred connect[a, b: Node] { a->b in edges }")
        let pred = module?.paragraphs.first as? PredDeclNode
        XCTAssertEqual(pred?.params.count, 1)  // a, b combined in one decl
    }

    func testMethodStylePredicate() {
        let module = parse("pred Person.greet[other: Person] {}")
        let pred = module?.paragraphs.first as? PredDeclNode
        XCTAssertEqual(pred?.receiver?.simpleName, "Person")
    }

    // MARK: - Function Declarations

    func testSimpleFunction() {
        let module = parse("fun count: Int { #Person }")
        let fun = module?.paragraphs.first as? FunDeclNode
        XCTAssertNotNil(fun)
        XCTAssertEqual(fun?.name, "count")
    }

    func testFunctionWithParams() {
        let module = parse("fun add[x, y: Int]: Int { x.plus[y] }")
        let fun = module?.paragraphs.first as? FunDeclNode
        XCTAssertEqual(fun?.params.count, 1)
    }

    // MARK: - Assertion Declarations

    func testSimpleAssertion() {
        let module = parse("assert Safety { always some Person }")
        let assertion = module?.paragraphs.first as? AssertDeclNode
        XCTAssertNotNil(assertion)
        XCTAssertEqual(assertion?.name, "Safety")
    }

    // MARK: - Run Commands

    func testSimpleRun() {
        let module = parse("run {}")
        let cmd = module?.paragraphs.first as? RunCmdNode
        XCTAssertNotNil(cmd)
    }

    func testRunWithScope() {
        let module = parse("run {} for 3")
        let cmd = module?.paragraphs.first as? RunCmdNode
        XCTAssertEqual(cmd?.scope?.defaultScope, 3)
    }

    func testRunWithTypedScope() {
        let module = parse("run {} for 3 Person, 2 Group")
        let cmd = module?.paragraphs.first as? RunCmdNode
        XCTAssertEqual(cmd?.scope?.typeScopes.count, 2)
    }

    func testRunWithExactScope() {
        let module = parse("run {} for exactly 3 Person")
        let cmd = module?.paragraphs.first as? RunCmdNode
        XCTAssertTrue(cmd?.scope?.typeScopes.first?.isExactly ?? false)
    }

    func testRunWithSteps() {
        let module = parse("run {} for 3 but 10 steps")
        let cmd = module?.paragraphs.first as? RunCmdNode
        XCTAssertEqual(cmd?.scope?.steps, 10)
    }

    func testRunNamedPredicate() {
        let module = parse("run show for 3")
        let cmd = module?.paragraphs.first as? RunCmdNode
        XCTAssertEqual(cmd?.targetName?.simpleName, "show")
    }

    // MARK: - Check Commands

    func testSimpleCheck() {
        let module = parse("check Safety")
        let cmd = module?.paragraphs.first as? CheckCmdNode
        XCTAssertNotNil(cmd)
        XCTAssertEqual(cmd?.targetName?.simpleName, "Safety")
    }

    func testCheckWithScope() {
        let module = parse("check Safety for 5")
        let cmd = module?.paragraphs.first as? CheckCmdNode
        XCTAssertEqual(cmd?.scope?.defaultScope, 5)
    }

    // MARK: - Enum Declarations

    func testSimpleEnum() {
        let module = parse("enum Color { Red, Green, Blue }")
        let enumDecl = module?.paragraphs.first as? EnumDeclNode
        XCTAssertNotNil(enumDecl)
        XCTAssertEqual(enumDecl?.name, "Color")
        XCTAssertEqual(enumDecl?.values.count, 3)
    }

    // MARK: - Expression Parsing

    func testJoinExpression() {
        let module = parse("fact { p.friends = none }")
        XCTAssertNotNil(module)
    }

    func testUnionExpression() {
        let module = parse("fact { A + B = C }")
        XCTAssertNotNil(module)
    }

    func testProductExpression() {
        let module = parse("fact { A -> B in rel }")
        XCTAssertNotNil(module)
    }

    func testTransposeExpression() {
        let module = parse("fact { ~rel = rel }")
        XCTAssertNotNil(module)
    }

    func testClosureExpression() {
        let module = parse("fact { a in b.^next }")
        XCTAssertNotNil(module)
    }

    func testReflexiveClosureExpression() {
        let module = parse("fact { a in b.*next }")
        XCTAssertNotNil(module)
    }

    func testCardinalityExpression() {
        let module = parse("fact { #Person > 0 }")
        XCTAssertNotNil(module)
    }

    // MARK: - Formula Parsing

    func testAndFormula() {
        let module = parse("fact { A && B }")
        XCTAssertNotNil(module)
    }

    func testOrFormula() {
        let module = parse("fact { A || B }")
        XCTAssertNotNil(module)
    }

    func testImpliesFormula() {
        let module = parse("fact { A => B }")
        XCTAssertNotNil(module)
    }

    func testIffFormula() {
        let module = parse("fact { A <=> B }")
        XCTAssertNotNil(module)
    }

    func testNotFormula() {
        let module = parse("fact { !A }")
        XCTAssertNotNil(module)
    }

    func testAllQuantifier() {
        let module = parse("fact { all p: Person | some p.friends }")
        XCTAssertNotNil(module)
    }

    func testSomeQuantifier() {
        let module = parse("fact { some p: Person | p.age > 18 }")
        XCTAssertNotNil(module)
    }

    func testNoQuantifier() {
        let module = parse("fact { no p: Person | p in p.friends }")
        XCTAssertNotNil(module)
    }

    func testOneQuantifier() {
        let module = parse("fact { one p: Person | p.isLeader = True }")
        XCTAssertNotNil(module)
    }

    func testLoneQuantifier() {
        let module = parse("fact { lone p: Person | p.spouse != none }")
        XCTAssertNotNil(module)
    }

    func testDisjointQuantifier() {
        let module = parse("fact { all disj a, b: Person | a != b }")
        XCTAssertNotNil(module)
    }

    // MARK: - Temporal Formulas (Alloy 6)

    func testAlwaysFormula() {
        let module = parse("fact { always some Person }")
        XCTAssertNotNil(module)
    }

    func testEventuallyFormula() {
        let module = parse("fact { eventually no Person }")
        XCTAssertNotNil(module)
    }

    func testAfterFormula() {
        let module = parse("fact { after some Person }")
        XCTAssertNotNil(module)
    }

    func testUntilFormula() {
        let module = parse("fact { A until B }")
        XCTAssertNotNil(module)
    }

    func testReleasesFormula() {
        let module = parse("fact { A releases B }")
        XCTAssertNotNil(module)
    }

    func testHistoricallyFormula() {
        let module = parse("fact { historically some Person }")
        XCTAssertNotNil(module)
    }

    func testOnceFormula() {
        let module = parse("fact { once no Person }")
        XCTAssertNotNil(module)
    }

    func testSinceFormula() {
        let module = parse("fact { A since B }")
        XCTAssertNotNil(module)
    }

    func testPrimeExpression() {
        let module = parse("pred change { state' != state }")
        XCTAssertNotNil(module)
    }

    // MARK: - Complex Examples

    func testFullModel() {
        let source = """
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
        """

        let module = parse(source)
        XCTAssertNotNil(module)
        XCTAssertNotNil(module?.moduleDecl)
        XCTAssertEqual(module?.paragraphs.count, 8)  // 3 sigs, 1 fact, 1 pred, 1 assert, 2 commands = 8
    }

    // MARK: - Let Expressions and Formulas

    func testLetExpression() {
        let module = parse("fun f[x: A]: B { let y = x.field | y }")
        XCTAssertNotNil(module)
        let fun = module?.paragraphs.first as? FunDeclNode
        XCTAssertNotNil(fun)
        // Body should contain a let expression
        XCTAssertNotNil(fun?.body)
    }

    func testLetFormula() {
        let module = parse("fact { let x = Person | some x }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        XCTAssertNotNil(fact?.body)
        let block = fact?.body as? BlockFormula
        XCTAssertEqual(block?.formulas.count, 1)
        let letFormula = block?.formulas.first as? LetFormula
        XCTAssertNotNil(letFormula)
        XCTAssertEqual(letFormula?.bindings.count, 1)
        XCTAssertEqual(letFormula?.bindings.first?.name.name, "x")
    }

    func testMultipleLetBindings() {
        let module = parse("fact { let x = A, y = B | x != y }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let letFormula = block?.formulas.first as? LetFormula
        XCTAssertEqual(letFormula?.bindings.count, 2)
    }

    // MARK: - Comprehension Expressions

    func testSetComprehension() {
        let module = parse("fun adults: set Person { { p: Person | p.age > 18 } }")
        XCTAssertNotNil(module)
        let fun = module?.paragraphs.first as? FunDeclNode
        XCTAssertNotNil(fun?.body)
    }

    func testComprehensionWithDisjoint() {
        let module = parse("fun pairs: set Person -> Person { { disj a, b: Person | a != b } }")
        XCTAssertNotNil(module)
    }

    func testComprehensionMultipleDecls() {
        let module = parse("fact { some { x: A, y: B | x.r = y } }")
        XCTAssertNotNil(module)
    }

    // MARK: - If-Then-Else Expressions

    func testIfThenElseExpression() {
        let module = parse("fun choose[cond: Bool, a: A, b: A]: A { some cond => a else b }")
        XCTAssertNotNil(module)
    }

    func testConditionalExpressionWithComparison() {
        let module = parse("fun max[x: Int, y: Int]: Int { x > y => x else y }")
        XCTAssertNotNil(module)
    }

    // MARK: - Override Operator (++)

    func testOverrideOperator() {
        let module = parse("fact { r' = r ++ (x -> y) }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        XCTAssertNotNil(fact?.body)
    }

    // MARK: - Domain and Range Restriction Operators

    func testDomainRestriction() {
        let module = parse("fact { some S <: r }")
        XCTAssertNotNil(module)
    }

    func testRangeRestriction() {
        let module = parse("fact { some r :> S }")
        XCTAssertNotNil(module)
    }

    func testCombinedRestrictions() {
        let module = parse("fact { A <: rel :> B = rel }")
        XCTAssertNotNil(module)
    }

    // MARK: - Additional Temporal Operators

    func testBeforeFormula() {
        let module = parse("fact { before some Person }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalUnaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .before)
    }

    func testTriggeredFormula() {
        let module = parse("fact { A triggered B }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalBinaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .triggered)
    }

    func testSemicolonSequencing() {
        let module = parse("fact { A ; B }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalBinaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .semicolon)
    }

    // MARK: - Sum Quantifier

    func testSumQuantifier() {
        let module = parse("fact { sum x: Int | x > 0 }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? QuantifiedFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.quantifier, .sum)
    }

    // MARK: - String Literals

    func testStringLiteral() {
        let lexer = Lexer(source: "\"hello world\"")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2) // string + eof
        if case .string(let value) = tokens.first?.kind {
            XCTAssertEqual(value, "hello world")
        } else {
            XCTFail("Expected string token")
        }
    }

    func testStringWithEscapes() {
        let lexer = Lexer(source: "\"line1\\nline2\\ttab\"")
        let tokens = lexer.scanAllTokens()
        if case .string(let value) = tokens.first?.kind {
            XCTAssertEqual(value, "line1\nline2\ttab")
        } else {
            XCTFail("Expected string token")
        }
    }

    func testUnterminatedString() {
        let lexer = Lexer(source: "\"unterminated")
        let tokens = lexer.scanAllTokens()
        if case .invalid(let msg) = tokens.first?.kind {
            XCTAssertTrue(msg.contains("Unterminated"))
        } else {
            XCTFail("Expected invalid token for unterminated string")
        }
    }

    // MARK: - Dollar Sign Identifiers

    func testDollarSignIdentifier() {
        let lexer = Lexer(source: "$var")
        let tokens = lexer.scanAllTokens()
        if case .identifier(let name) = tokens.first?.kind {
            XCTAssertEqual(name, "$var")
        } else {
            XCTFail("Expected identifier starting with $")
        }
    }

    // MARK: - Integer Overflow

    func testIntegerOverflow() {
        let lexer = Lexer(source: "99999999999999999999999999")
        let tokens = lexer.scanAllTokens()
        if case .invalid(let msg) = tokens.first?.kind {
            XCTAssertTrue(msg.contains("too large"))
        } else {
            XCTFail("Expected invalid token for integer overflow")
        }
    }

    // MARK: - Unterminated Block Comment

    func testUnterminatedBlockComment() {
        let lexer = Lexer(source: "/* unterminated comment")
        let tokens = lexer.scanAllTokens()
        // Should have an invalid token for the unterminated comment
        let hasInvalid = tokens.contains { token in
            if case .invalid(let msg) = token.kind {
                return msg.contains("Unterminated") || msg.contains("comment")
            }
            return false
        }
        XCTAssertTrue(hasInvalid, "Expected error for unterminated block comment")
    }

    // MARK: - @this Expression

    func testAtThisExpression() {
        let module = parse("sig A { f: set @this.B }")
        XCTAssertNotNil(module)
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.fields.count, 1)
    }

    // MARK: - Block Expression

    func testBlockExpression() {
        let module = parse("fun f: Bool { { some A and some B } }")
        XCTAssertNotNil(module)
    }

    // MARK: - Strengthened Temporal Tests

    func testAlwaysFormulaStructure() {
        let module = parse("fact { always some Person }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        XCTAssertNotNil(fact?.body)
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalUnaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .always)
        // Check inner formula is a multiplicity formula
        XCTAssertNotNil(formula?.operand)
    }

    func testEventuallyFormulaStructure() {
        let module = parse("fact { eventually no Person }")
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalUnaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .eventually)
    }

    func testHistoricallyFormulaStructure() {
        let module = parse("fact { historically some Person }")
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalUnaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .historically)
    }

    func testOnceFormulaStructure() {
        let module = parse("fact { once no Person }")
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalUnaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .once)
    }

    func testUntilFormulaStructure() {
        let module = parse("fact { A until B }")
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalBinaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .until)
    }

    func testReleasesFormulaStructure() {
        let module = parse("fact { A releases B }")
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalBinaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .releases)
    }

    func testSinceFormulaStructure() {
        let module = parse("fact { A since B }")
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? TemporalBinaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .since)
    }

    // MARK: - Implication and Biconditional

    func testImplicationFormula() {
        let module = parse("fact { A => B }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? BinaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .implies)
    }

    func testBiconditionalFormula() {
        let module = parse("fact { A <=> B }")
        XCTAssertNotNil(module)
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? BinaryFormula
        XCTAssertNotNil(formula)
        XCTAssertEqual(formula?.op, .iff)
    }

    func testImplicationWithKeyword() {
        let module = parse("fact { A implies B }")
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? BinaryFormula
        XCTAssertEqual(formula?.op, .implies)
    }

    func testBiconditionalWithKeyword() {
        let module = parse("fact { A iff B }")
        let fact = module?.paragraphs.first as? FactDeclNode
        let block = fact?.body as? BlockFormula
        let formula = block?.formulas.first as? BinaryFormula
        XCTAssertEqual(formula?.op, .iff)
    }

    // MARK: - Arrow Expression Tests (Alloy 6.2)

    func testArrowExprWithMultiplicities() {
        let module = parse("sig A { r: A -> lone B }")
        XCTAssertNotNil(module)
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.fields.count, 1)
    }

    func testArrowExprBothMultiplicities() {
        let module = parse("sig A { r: A some -> one B }")
        XCTAssertNotNil(module)
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.fields.count, 1)
    }

    func testArrowExprLeftMultiplicity() {
        let module = parse("sig A { r: A one -> B }")
        XCTAssertNotNil(module)
    }

    func testArrowExprInFact() {
        let module = parse("fact { A -> lone B in rel }")
        XCTAssertNotNil(module)
    }

    func testChainedArrowExpr() {
        let module = parse("sig A { r: A -> B -> C }")
        XCTAssertNotNil(module)
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.fields.count, 1)
    }

    // MARK: - Error Recovery

    func testErrorRecoveryInBlock() {
        // Parser should recover from errors and continue parsing
        let parser = Parser(source: "fact { @@@ some Person }")
        let module = parser.parse()
        XCTAssertNotNil(module)
        // Should have errors but still produce a module
        XCTAssertFalse(parser.getErrors().isEmpty)
    }

    func testErrorRecoveryBetweenDeclarations() {
        // Parser should recover and parse subsequent declarations
        let parser = Parser(source: """
            fact { @@@ }
            sig Person {}
            """)
        let module = parser.parse()
        XCTAssertNotNil(module)
        // Should have at least the sig
        XCTAssertGreaterThanOrEqual(module?.paragraphs.count ?? 0, 1)
    }

    // MARK: - Crash Resistance Tests

    func testUnterminatedStringAtEOF() {
        // Parser should not crash on unterminated string at end of file
        let parser = Parser(source: """
            sig A { name: "unterminated
            """)
        _ = parser.parse()
        // Should produce errors but not crash
        XCTAssertFalse(parser.getErrors().isEmpty)
    }

    func testUnterminatedBlockCommentAtEOF() {
        // Parser should not crash on unterminated block comment
        let parser = Parser(source: """
            sig A {}
            /* this comment is never closed
            """)
        let module = parser.parse()
        // Should handle gracefully
        XCTAssertNotNil(module)
    }

    func testMixedLineEndings() {
        // Parser should handle mixed CRLF and LF line endings
        let source = "sig A {}\r\nsig B {}\nsig C {}\r\n"
        let module = parse(source)
        XCTAssertNotNil(module)
        XCTAssertEqual(module?.paragraphs.count, 3)
    }

    func testEmptySource() {
        let module = parse("")
        XCTAssertNotNil(module)
        XCTAssertEqual(module?.paragraphs.count, 0)
    }

    func testOnlyWhitespace() {
        let module = parse("   \n\t\n   ")
        XCTAssertNotNil(module)
        XCTAssertEqual(module?.paragraphs.count, 0)
    }

    func testOnlyComments() {
        let module = parse("""
            // Line comment
            /* Block comment */
            -- Another line comment
            """)
        XCTAssertNotNil(module)
        XCTAssertEqual(module?.paragraphs.count, 0)
    }

    func testDeeplyNestedParentheses() {
        // Generate deeply nested expression
        var source = "fact { "
        for _ in 0..<100 {
            source += "(("
        }
        source += "A"
        for _ in 0..<100 {
            source += "))"
        }
        source += " }"

        let parser = Parser(source: source)
        let module = parser.parse()
        // Should handle deep nesting without stack overflow
        XCTAssertNotNil(module)
    }

    func testDeeplyNestedBraces() {
        // Nested blocks
        var source = ""
        for _ in 0..<50 {
            source += "fact { "
        }
        source += "A = A"
        for _ in 0..<50 {
            source += " }"
        }

        let parser = Parser(source: source)
        _ = parser.parse()
        // Should not crash
    }

    func testMalformedUTF8Recovery() {
        // Test with some unusual unicode
        let source = "sig Prénom { émoji: set 日本語 }"
        let module = parse(source)
        XCTAssertNotNil(module)
    }

    func testUnexpectedEOFInSignature() {
        let parser = Parser(source: "sig A {")
        _ = parser.parse()
        // Should report error but not crash
        XCTAssertFalse(parser.getErrors().isEmpty)
    }

    func testUnexpectedEOFInPredicate() {
        let parser = Parser(source: "pred foo {")
        _ = parser.parse()
        XCTAssertFalse(parser.getErrors().isEmpty)
    }

    func testUnexpectedEOFInQuantifier() {
        let parser = Parser(source: "fact { all x:")
        _ = parser.parse()
        XCTAssertFalse(parser.getErrors().isEmpty)
    }

    func testConsecutiveOperators() {
        // Multiple operators in a row - should error gracefully
        let parser = Parser(source: "fact { A ++ -- !! B }")
        _ = parser.parse()
        // Should not crash
    }

    func testVeryLongIdentifier() {
        let longName = String(repeating: "a", count: 10000)
        let source = "sig \(longName) {}"
        let module = parse(source)
        XCTAssertNotNil(module)
        let sig = module?.paragraphs.first as? SigDeclNode
        XCTAssertEqual(sig?.names.first?.name, longName)
    }

    func testVeryLongInteger() {
        let parser = Parser(source: "fact { #A = 99999999999999999999999999999999 }")
        let module = parser.parse()
        // Should handle large integer somehow (truncate, error, or parse)
        XCTAssertNotNil(module)
    }
}
