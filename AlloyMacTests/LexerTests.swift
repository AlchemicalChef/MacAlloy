import XCTest
@testable import AlloyMac

/// Tests for the Alloy 6.2 Lexer
final class LexerTests: XCTestCase {

    // MARK: - Basic Token Tests

    func testEmptySource() {
        let lexer = Lexer(source: "")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .eof)
    }

    func testWhitespaceOnly() {
        let lexer = Lexer(source: "   \t\n  ")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .eof)
    }

    // MARK: - Keyword Tests

    func testModuleKeyword() {
        let lexer = Lexer(source: "module")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .module)
    }

    func testSigKeyword() {
        let lexer = Lexer(source: "sig")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .sig)
    }

    func testAbstractKeyword() {
        let lexer = Lexer(source: "abstract")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .abstract)
    }

    func testExtendsKeyword() {
        let lexer = Lexer(source: "extends")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .extends)
    }

    func testVarKeyword() {
        let lexer = Lexer(source: "var")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .var)
    }

    func testFactKeyword() {
        let lexer = Lexer(source: "fact")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .fact)
    }

    func testPredKeyword() {
        let lexer = Lexer(source: "pred")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .pred)
    }

    func testFunKeyword() {
        let lexer = Lexer(source: "fun")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .fun)
    }

    func testAssertKeyword() {
        let lexer = Lexer(source: "assert")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .assert)
    }

    func testRunKeyword() {
        let lexer = Lexer(source: "run")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .run)
    }

    func testCheckKeyword() {
        let lexer = Lexer(source: "check")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .check)
    }

    // MARK: - Multiplicity Keywords

    func testLoneKeyword() {
        let lexer = Lexer(source: "lone")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .lone)
    }

    func testOneKeyword() {
        let lexer = Lexer(source: "one")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .one)
    }

    func testSomeKeyword() {
        let lexer = Lexer(source: "some")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .some)
    }

    func testSetKeyword() {
        let lexer = Lexer(source: "set")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .set)
    }

    func testAllKeyword() {
        let lexer = Lexer(source: "all")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .all)
    }

    func testNoKeyword() {
        let lexer = Lexer(source: "no")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .no)
    }

    // MARK: - Temporal Keywords (Alloy 6)

    func testAlwaysKeyword() {
        let lexer = Lexer(source: "always")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .always)
    }

    func testEventuallyKeyword() {
        let lexer = Lexer(source: "eventually")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .eventually)
    }

    func testAfterKeyword() {
        let lexer = Lexer(source: "after")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .after)
    }

    func testUntilKeyword() {
        let lexer = Lexer(source: "until")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .until)
    }

    func testReleasesKeyword() {
        let lexer = Lexer(source: "releases")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .releases)
    }

    func testHistoricallyKeyword() {
        let lexer = Lexer(source: "historically")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .historically)
    }

    func testOnceKeyword() {
        let lexer = Lexer(source: "once")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .once)
    }

    func testBeforeKeyword() {
        let lexer = Lexer(source: "before")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .before)
    }

    func testSinceKeyword() {
        let lexer = Lexer(source: "since")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .since)
    }

    func testTriggeredKeyword() {
        let lexer = Lexer(source: "triggered")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .triggered)
    }

    // MARK: - Identifier Tests

    func testSimpleIdentifier() {
        let lexer = Lexer(source: "Person")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .identifier("Person"))
    }

    func testIdentifierWithUnderscore() {
        let lexer = Lexer(source: "my_var")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .identifier("my_var"))
    }

    func testIdentifierWithNumbers() {
        let lexer = Lexer(source: "var123")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .identifier("var123"))
    }

    // MARK: - Operator Tests

    func testDotOperator() {
        let lexer = Lexer(source: ".")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .dot)
    }

    func testArrowOperator() {
        let lexer = Lexer(source: "->")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .arrow)
    }

    func testTildeOperator() {
        let lexer = Lexer(source: "~")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .tilde)
    }

    func testCaretOperator() {
        let lexer = Lexer(source: "^")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .caret)
    }

    func testStarOperator() {
        let lexer = Lexer(source: "*")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .star)
    }

    func testHashOperator() {
        let lexer = Lexer(source: "#")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .hash)
    }

    func testPrimeOperator() {
        let lexer = Lexer(source: "'")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .prime)
    }

    func testPlusOperator() {
        let lexer = Lexer(source: "+")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .plus)
    }

    func testMinusOperator() {
        let lexer = Lexer(source: "-")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .minus)
    }

    func testAmpersandOperator() {
        let lexer = Lexer(source: "&")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .ampersand)
    }

    func testPlusPlusOperator() {
        let lexer = Lexer(source: "++")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .plusPlus)
    }

    func testLeftRestrictOperator() {
        let lexer = Lexer(source: "<:")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .leftRestrict)
    }

    func testRightRestrictOperator() {
        let lexer = Lexer(source: ":>")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .rightRestrict)
    }

    func testEqualOperator() {
        let lexer = Lexer(source: "=")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .equal)
    }

    func testNotEqualOperator() {
        let lexer = Lexer(source: "!=")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .notEqual)
    }

    func testInOperator() {
        let lexer = Lexer(source: "in")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .in)
    }

    func testLessOperator() {
        let lexer = Lexer(source: "<")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .less)
    }

    func testGreaterOperator() {
        let lexer = Lexer(source: ">")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .greater)
    }

    func testLessEqualOperator() {
        let lexer = Lexer(source: "=<")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .lessEqual)
    }

    func testGreaterEqualOperator() {
        let lexer = Lexer(source: ">=")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .greaterEqual)
    }

    func testBangOperator() {
        let lexer = Lexer(source: "!")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .bang)
    }

    func testDoubleAmpOperator() {
        let lexer = Lexer(source: "&&")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .doubleAmp)
    }

    func testDoublePipeOperator() {
        let lexer = Lexer(source: "||")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .doublePipe)
    }

    func testFatArrowOperator() {
        let lexer = Lexer(source: "=>")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .fatArrow)
    }

    func testDoubleArrowOperator() {
        let lexer = Lexer(source: "<=>")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .doubleArrow)
    }

    // MARK: - Delimiter Tests

    func testLeftBrace() {
        let lexer = Lexer(source: "{")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .leftBrace)
    }

    func testRightBrace() {
        let lexer = Lexer(source: "}")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .rightBrace)
    }

    func testLeftBracket() {
        let lexer = Lexer(source: "[")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .leftBracket)
    }

    func testRightBracket() {
        let lexer = Lexer(source: "]")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .rightBracket)
    }

    func testLeftParen() {
        let lexer = Lexer(source: "(")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .leftParen)
    }

    func testRightParen() {
        let lexer = Lexer(source: ")")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .rightParen)
    }

    func testComma() {
        let lexer = Lexer(source: ",")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .comma)
    }

    func testColon() {
        let lexer = Lexer(source: ":")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .colon)
    }

    func testPipe() {
        let lexer = Lexer(source: "|")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .pipe)
    }

    func testAt() {
        let lexer = Lexer(source: "@")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .at)
    }

    func testSemicolon() {
        let lexer = Lexer(source: ";")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .semicolon)
    }

    // MARK: - Integer Tests

    func testZero() {
        let lexer = Lexer(source: "0")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .integer(0))
    }

    func testPositiveInteger() {
        let lexer = Lexer(source: "42")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .integer(42))
    }

    func testNegativeInteger() {
        let lexer = Lexer(source: "-7")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 3)
        XCTAssertEqual(tokens[0].kind, .minus)
        XCTAssertEqual(tokens[1].kind, .integer(7))
    }

    // MARK: - Comment Tests

    func testLineComment() {
        let lexer = Lexer(source: "// this is a comment\nsig")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .sig)
    }

    func testDashDashComment() {
        let lexer = Lexer(source: "-- this is a comment\nsig")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .sig)
    }

    func testBlockComment() {
        let lexer = Lexer(source: "/* this is a block comment */ sig")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .sig)
    }

    func testMultiLineBlockComment() {
        let lexer = Lexer(source: "/* this is\na multi-line\ncomment */ sig")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].kind, .sig)
    }

    // MARK: - Source Location Tests

    func testTokenSourceLocation() {
        let lexer = Lexer(source: "sig Person")
        let tokens = lexer.scanAllTokens()

        XCTAssertEqual(tokens[0].span.start.line, 1)
        XCTAssertEqual(tokens[0].span.start.column, 1)
        XCTAssertEqual(tokens[0].span.end.column, 4)

        XCTAssertEqual(tokens[1].span.start.line, 1)
        XCTAssertEqual(tokens[1].span.start.column, 5)
    }

    func testMultiLineSourceLocation() {
        let lexer = Lexer(source: "sig\nPerson")
        let tokens = lexer.scanAllTokens()

        XCTAssertEqual(tokens[0].span.start.line, 1)
        XCTAssertEqual(tokens[1].span.start.line, 2)
        XCTAssertEqual(tokens[1].span.start.column, 1)
    }

    // MARK: - Integration Tests

    func testSimpleSignature() {
        let lexer = Lexer(source: "sig Person { }")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 5)
        XCTAssertEqual(tokens[0].kind, .sig)
        XCTAssertEqual(tokens[1].kind, .identifier("Person"))
        XCTAssertEqual(tokens[2].kind, .leftBrace)
        XCTAssertEqual(tokens[3].kind, .rightBrace)
        XCTAssertEqual(tokens[4].kind, .eof)
    }

    func testSignatureWithField() {
        let lexer = Lexer(source: "sig Person { friends: set Person }")
        let tokens = lexer.scanAllTokens()
        XCTAssertEqual(tokens.count, 9) // sig, Person, {, friends, :, set, Person, }, EOF
        XCTAssertEqual(tokens[0].kind, .sig)
        XCTAssertEqual(tokens[1].kind, .identifier("Person"))
        XCTAssertEqual(tokens[2].kind, .leftBrace)
        XCTAssertEqual(tokens[3].kind, .identifier("friends"))
        XCTAssertEqual(tokens[4].kind, .colon)
        XCTAssertEqual(tokens[5].kind, .set)
        XCTAssertEqual(tokens[6].kind, .identifier("Person"))
        XCTAssertEqual(tokens[7].kind, .rightBrace)
    }

    func testTemporalFormula() {
        let lexer = Lexer(source: "always some p: Person | p.mood' = Happy")
        let tokens = lexer.scanAllTokens()
        XCTAssertTrue(tokens.contains { $0.kind == .always })
        XCTAssertTrue(tokens.contains { $0.kind == .some })
        XCTAssertTrue(tokens.contains { $0.kind == .prime })
    }

    func testRunCommand() {
        let lexer = Lexer(source: "run {} for 3 Person, 5 steps")
        let tokens = lexer.scanAllTokens()
        XCTAssertTrue(tokens.contains { $0.kind == .run })
        XCTAssertTrue(tokens.contains { $0.kind == .for })
        XCTAssertTrue(tokens.contains { $0.kind == .steps })
    }
}
