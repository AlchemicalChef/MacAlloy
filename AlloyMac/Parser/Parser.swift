import Foundation

// MARK: - Parser

/// Recursive descent parser for Alloy 6.2
public final class Parser {
    private let lexer: Lexer
    private var tokens: [Token] = []
    private var current: Int = 0
    private var errors: [ParseError] = []

    // MARK: - Initialization

    public init(source: String) {
        self.lexer = Lexer(source: source)
        self.tokens = lexer.scanAllTokens()
    }

    // MARK: - Main Entry Point

    public func parse() -> ModuleNode? {
        let startSpan = currentToken.span

        // Parse module declaration
        let moduleDecl = parseModuleDecl()

        // Parse opens
        var opens: [OpenNode] = []
        while check(.open) {
            if let open = parseOpen() {
                opens.append(open)
            }
        }

        // Parse paragraphs
        var paragraphs: [any DeclNode] = []
        while !isAtEnd {
            if let para = parseParagraph() {
                paragraphs.append(para)
            } else {
                synchronize()
            }
        }

        let endSpan = previous.span
        return ModuleNode(
            span: SourceSpan(start: startSpan.start, end: endSpan.end),
            moduleDecl: moduleDecl,
            opens: opens,
            paragraphs: paragraphs
        )
    }

    // MARK: - Module Declaration

    private func parseModuleDecl() -> ModuleDeclNode? {
        guard match(.module) else { return nil }
        let startSpan = previous.span

        guard let name = parseQualifiedName() else {
            error("Expected module name")
            return nil
        }

        // Parse optional parameters [Param1, Param2]
        var params: [Identifier] = []
        if match(.leftBracket) {
            repeat {
                if let param = expectIdentifier("parameter name") {
                    params.append(param)
                }
            } while match(.comma)
            expect(.rightBracket, "Expected ']' after module parameters")
        }

        return ModuleDeclNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            name: name,
            parameters: params
        )
    }

    // MARK: - Open Declaration

    private func parseOpen() -> OpenNode? {
        guard match(.open) else { return nil }
        let startSpan = previous.span

        guard let modulePath = parseQualifiedName() else {
            error("Expected module path")
            return nil
        }

        // Parse optional arguments [Arg1, Arg2]
        var args: [QualifiedName] = []
        if match(.leftBracket) {
            repeat {
                if let arg = parseQualifiedName() {
                    args.append(arg)
                }
            } while match(.comma)
            expect(.rightBracket, "Expected ']' after open arguments")
        }

        // Parse optional alias
        var alias: Identifier? = nil
        if match(.as) {
            alias = expectIdentifier("alias name")
        }

        return OpenNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            modulePath: modulePath,
            arguments: args,
            alias: alias
        )
    }

    // MARK: - Paragraph Parsing

    private func parseParagraph() -> (any DeclNode)? {
        // Check for sig modifiers first
        if check(.abstract) || check(.one) || check(.lone) || check(.some) ||
           check(.var) || check(.sig) {
            return parseSigDecl()
        }

        switch currentToken.kind {
        case .fact: return parseFactDecl()
        case .pred: return parsePredDecl()
        case .fun: return parseFunDecl()
        case .assert: return parseAssertDecl()
        case .run: return parseRunCmd()
        case .check: return parseCheckCmd()
        case .enum: return parseEnumDecl()
        default:
            error("Expected declaration")
            return nil
        }
    }

    // MARK: - Signature Declaration

    private func parseSigDecl() -> SigDeclNode? {
        let startSpan = currentToken.span

        // Parse modifiers
        var isAbstract = false
        var multiplicity: Multiplicity? = nil
        var isVariable = false

        while true {
            if match(.abstract) {
                isAbstract = true
            } else if match(.one) {
                multiplicity = .one
            } else if match(.lone) {
                multiplicity = .lone
            } else if match(.some) {
                multiplicity = .some
            } else if match(.var) {
                isVariable = true
            } else {
                break
            }
        }

        guard match(.sig) else {
            error("Expected 'sig' keyword")
            return nil
        }

        // Parse signature names
        var names: [Identifier] = []
        repeat {
            if let name = expectIdentifier("signature name") {
                names.append(name)
            }
        } while match(.comma)

        guard !names.isEmpty else { return nil }

        // Parse extension clause
        var ext: SigExtension? = nil
        if match(.extends) {
            if let parent = parseQualifiedName() {
                ext = .extends(parent)
            }
        } else if match(.in) {
            var parents: [QualifiedName] = []
            repeat {
                if let parent = parseQualifiedName() {
                    parents.append(parent)
                }
            } while match(.plus)
            ext = .subset(parents)
        }

        // Parse body
        expect(.leftBrace, "Expected '{' to start signature body")

        var fields: [FieldDeclNode] = []
        while !check(.rightBrace) && !isAtEnd {
            if let field = parseFieldDecl() {
                fields.append(field)
            }
            // Fields can be separated by comma
            match(.comma)
        }

        expect(.rightBrace, "Expected '}' to end signature body")

        // Parse optional signature fact
        var sigFact: BlockFormula? = nil
        if check(.leftBrace) {
            sigFact = parseBlockFormula()
        }

        return SigDeclNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            isAbstract: isAbstract,
            multiplicity: multiplicity,
            isVariable: isVariable,
            names: names,
            ext: ext,
            fields: fields,
            sigFact: sigFact
        )
    }

    // MARK: - Field Declaration

    private func parseFieldDecl() -> FieldDeclNode? {
        let startSpan = currentToken.span

        let isVariable = match(.var)
        let isDisjoint = match(.disj)

        // Parse field names
        var names: [Identifier] = []
        repeat {
            if let name = expectIdentifier("field name") {
                names.append(name)
            }
        } while match(.comma) && !check(.colon)

        guard !names.isEmpty else { return nil }

        expect(.colon, "Expected ':' after field name(s)")

        // Parse type expression
        guard let typeExpr = parseExpr() else {
            error("Expected type expression")
            return nil
        }

        return FieldDeclNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            isVariable: isVariable,
            isDisjoint: isDisjoint,
            names: names,
            typeExpr: typeExpr
        )
    }

    // MARK: - Fact Declaration

    private func parseFactDecl() -> FactDeclNode? {
        guard match(.fact) else { return nil }
        let startSpan = previous.span

        // Optional name
        var name: Identifier? = nil
        if case .identifier = currentToken.kind {
            name = parseIdentifier()
        }

        // Body
        guard let body = parseBlockFormula() else {
            error("Expected fact body")
            return nil
        }

        return FactDeclNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            name: name,
            body: body
        )
    }

    // MARK: - Predicate Declaration

    private func parsePredDecl() -> PredDeclNode? {
        guard match(.pred) else { return nil }
        let startSpan = previous.span

        // Parse name (possibly with receiver: Sig.name)
        var receiver: QualifiedName? = nil
        guard let name = expectIdentifier("predicate name") else { return nil }

        var predName = name
        if match(.dot) {
            receiver = QualifiedName(single: name)
            guard let n = expectIdentifier("predicate name") else { return nil }
            predName = n
        }

        // Parse parameters
        var params: [ParamDecl] = []
        if match(.leftBracket) {
            if !check(.rightBracket) {
                repeat {
                    if let param = parseParamDecl() {
                        params.append(param)
                    }
                } while match(.comma)
            }
            expect(.rightBracket, "Expected ']' after parameters")
        }

        // Parse body
        var body: (any FormulaNode)? = nil
        if check(.leftBrace) {
            body = parseBlockFormula()
        }

        return PredDeclNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            receiver: receiver,
            name: predName,
            params: params,
            body: body
        )
    }

    // MARK: - Function Declaration

    private func parseFunDecl() -> FunDeclNode? {
        guard match(.fun) else { return nil }
        let startSpan = previous.span

        // Parse name (possibly with receiver)
        var receiver: QualifiedName? = nil
        guard let name = expectIdentifier("function name") else { return nil }

        var funName = name
        if match(.dot) {
            receiver = QualifiedName(single: name)
            guard let n = expectIdentifier("function name") else { return nil }
            funName = n
        }

        // Parse parameters
        var params: [ParamDecl] = []
        if match(.leftBracket) {
            if !check(.rightBracket) {
                repeat {
                    if let param = parseParamDecl() {
                        params.append(param)
                    }
                } while match(.comma)
            }
            expect(.rightBracket, "Expected ']' after parameters")
        }

        // Parse return type
        var returnType: (any ExprNode)? = nil
        if match(.colon) {
            returnType = parseExpr()
        }

        // Parse body
        var body: (any ExprNode)? = nil
        if check(.leftBrace) {
            body = parseBlockAsExpr()
        }

        return FunDeclNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            receiver: receiver,
            name: funName,
            params: params,
            returnType: returnType,
            body: body
        )
    }

    // MARK: - Assertion Declaration

    private func parseAssertDecl() -> AssertDeclNode? {
        guard match(.assert) else { return nil }
        let startSpan = previous.span

        // Optional name
        var name: Identifier? = nil
        if case .identifier = currentToken.kind {
            name = parseIdentifier()
        }

        // Body
        guard let body = parseBlockFormula() else {
            error("Expected assertion body")
            return nil
        }

        return AssertDeclNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            name: name,
            body: body
        )
    }

    // MARK: - Enum Declaration

    private func parseEnumDecl() -> EnumDeclNode? {
        guard match(.enum) else { return nil }
        let startSpan = previous.span

        guard let name = expectIdentifier("enum name") else { return nil }

        expect(.leftBrace, "Expected '{' after enum name")

        var values: [Identifier] = []
        if !check(.rightBrace) {
            repeat {
                if let value = expectIdentifier("enum value") {
                    values.append(value)
                }
            } while match(.comma)
        }

        expect(.rightBrace, "Expected '}' after enum values")

        return EnumDeclNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            name: name,
            values: values
        )
    }

    // MARK: - Command Parsing

    private func parseRunCmd() -> RunCmdNode? {
        guard match(.run) else { return nil }
        let startSpan = previous.span

        var cmdName: Identifier? = nil
        var body: (any FormulaNode)? = nil
        var targetName: QualifiedName? = nil

        // Either a name or a block
        if case .identifier = currentToken.kind {
            guard let name = parseIdentifier() else {
                return nil  // Failed to parse expected identifier
            }
            if check(.leftBrace) || check(.for) || isAtEnd || isParagraphStart() {
                targetName = QualifiedName(single: name)
            } else {
                cmdName = name
                if case .identifier = currentToken.kind {
                    targetName = parseQualifiedName()
                }
            }
        }

        if check(.leftBrace) {
            body = parseBlockFormula()
        }

        // Parse scope
        var scope: CommandScope? = nil
        if match(.for) {
            scope = parseScope()
        }

        return RunCmdNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            name: cmdName,
            body: body,
            targetName: targetName,
            scope: scope
        )
    }

    private func parseCheckCmd() -> CheckCmdNode? {
        guard match(.check) else { return nil }
        let startSpan = previous.span

        var cmdName: Identifier? = nil
        var body: (any FormulaNode)? = nil
        var targetName: QualifiedName? = nil

        // Either a name or a block
        if case .identifier = currentToken.kind {
            guard let name = parseIdentifier() else {
                return nil  // Failed to parse expected identifier
            }
            if check(.leftBrace) || check(.for) || isAtEnd || isParagraphStart() {
                targetName = QualifiedName(single: name)
            } else {
                cmdName = name
                if case .identifier = currentToken.kind {
                    targetName = parseQualifiedName()
                }
            }
        }

        if check(.leftBrace) {
            body = parseBlockFormula()
        }

        // Parse scope
        var scope: CommandScope? = nil
        if match(.for) {
            scope = parseScope()
        }

        return CheckCmdNode(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            name: cmdName,
            body: body,
            targetName: targetName,
            scope: scope
        )
    }

    // MARK: - Scope Parsing

    private func parseScope() -> CommandScope {
        var defaultScope: Int? = nil
        var typeScopes: [TypeScope] = []
        var steps: Int? = nil
        var expect: Int? = nil

        // Check for initial exactly modifier
        let initialExactly = match(.exactly)

        // First element could be default or typed
        if case .integer(let n) = currentToken.kind {
            advance()
            if case .identifier = currentToken.kind {
                // Typed scope
                if let typeName = parseQualifiedName() {
                    typeScopes.append(TypeScope(isExactly: initialExactly, count: n, typeName: typeName))
                }
            } else {
                defaultScope = n
            }
        }

        // Parse additional type scopes
        while match(.comma) || match(.but) {
            let isExactly = match(.exactly)

            if case .integer(let n) = currentToken.kind {
                advance()

                // Check for 'steps'
                if match(.steps) {
                    steps = n
                } else if case .identifier = currentToken.kind {
                    if let typeName = parseQualifiedName() {
                        typeScopes.append(TypeScope(isExactly: isExactly, count: n, typeName: typeName))
                    }
                }
            }
        }

        // Check for expect
        if match(.expect) {
            if case .integer(let n) = currentToken.kind {
                advance()
                expect = n
            }
        }

        return CommandScope(
            defaultScope: defaultScope,
            typeScopes: typeScopes,
            steps: steps,
            expect: expect
        )
    }

    // MARK: - Parameter Declaration

    private func parseParamDecl() -> ParamDecl? {
        let isDisjoint = match(.disj)

        var names: [Identifier] = []
        repeat {
            if let name = expectIdentifier("parameter name") {
                names.append(name)
            }
        } while match(.comma) && !check(.colon)

        guard !names.isEmpty else { return nil }

        expect(.colon, "Expected ':' after parameter name(s)")

        guard let typeExpr = parseExpr() else {
            error("Expected parameter type")
            return nil
        }

        return ParamDecl(isDisjoint: isDisjoint, names: names, typeExpr: typeExpr)
    }

    // MARK: - Block Parsing

    private func parseBlockFormula() -> BlockFormula? {
        guard match(.leftBrace) else { return nil }
        let startSpan = previous.span

        var formulas: [any FormulaNode] = []
        while !check(.rightBrace) && !isAtEnd {
            if let formula = parseFormula() {
                formulas.append(formula)
            } else {
                // Error recovery: skip tokens until we find something parseable or block end
                synchronizeInBlock()
            }
        }

        expect(.rightBrace, "Expected '}' to close block")

        return BlockFormula(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            formulas: formulas
        )
    }

    private func parseBlockAsExpr() -> BlockExpr? {
        guard match(.leftBrace) else { return nil }
        let startSpan = previous.span

        var formulas: [any FormulaNode] = []
        while !check(.rightBrace) && !isAtEnd {
            if let formula = parseFormula() {
                formulas.append(formula)
            } else {
                // Error recovery: skip tokens until we find something parseable or block end
                synchronizeInBlock()
            }
        }

        expect(.rightBrace, "Expected '}' to close block")

        return BlockExpr(
            span: SourceSpan(start: startSpan.start, end: previous.span.end),
            formulas: formulas
        )
    }

    // MARK: - Formula Parsing

    private func parseFormula() -> (any FormulaNode)? {
        parseIffFormula()
    }

    // Lowest precedence: <=>
    private func parseIffFormula() -> (any FormulaNode)? {
        var left = parseImpliesFormula()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.doubleArrow) || match(.iff) {
            let startSpan = left?.span ?? previous.span
            guard let right = parseImpliesFormula() else {
                error("Expected formula after '<=>'")
                return left
            }
            left = BinaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: .iff,
                right: right
            )
        }

        return left
    }

    // =>
    private func parseImpliesFormula() -> (any FormulaNode)? {
        var left = parseOrFormula()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.fatArrow) || match(.implies) {
            let startSpan = left?.span ?? previous.span
            guard let right = parseOrFormula() else {
                error("Expected formula after '=>'")
                return left
            }
            left = BinaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: .implies,
                right: right
            )
        }

        return left
    }

    // || or
    private func parseOrFormula() -> (any FormulaNode)? {
        var left = parseAndFormula()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.doublePipe) || match(.or) {
            let op: LogicalOp = previous.kind == .or ? .orKeyword : .or
            let startSpan = left?.span ?? previous.span
            guard let right = parseAndFormula() else {
                error("Expected formula after 'or'")
                return left
            }
            left = BinaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: op,
                right: right
            )
        }

        return left
    }

    // && and
    private func parseAndFormula() -> (any FormulaNode)? {
        var left = parseTemporalBinaryFormula()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.doubleAmp) || match(.and) {
            let op: LogicalOp = previous.kind == .and ? .andKeyword : .and
            let startSpan = left?.span ?? previous.span
            guard let right = parseTemporalBinaryFormula() else {
                error("Expected formula after 'and'")
                return left
            }
            left = BinaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: op,
                right: right
            )
        }

        return left
    }

    // Temporal binary: until, releases, since, triggered
    private func parseTemporalBinaryFormula() -> (any FormulaNode)? {
        var left = parseUnaryFormula()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while true {
            var op: TemporalBinaryOp? = nil
            if match(.until) { op = .until }
            else if match(.releases) { op = .releases }
            else if match(.since) { op = .since }
            else if match(.triggered) { op = .triggered }
            else if match(.semicolon) { op = .semicolon }
            else { break }

            let startSpan = left?.span ?? previous.span
            guard let right = parseUnaryFormula() else {
                error("Expected formula after temporal operator")
                return left
            }
            left = TemporalBinaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: op!,
                right: right
            )
        }

        return left
    }

    // Unary: ! not, temporal unary
    private func parseUnaryFormula() -> (any FormulaNode)? {
        let startSpan = currentToken.span

        // Negation
        if match(.bang) || match(.not) {
            let op: LogicalUnaryOp = previous.kind == .not ? .notKeyword : .not
            guard let operand = parseUnaryFormula() else {
                error("Expected formula after negation")
                return nil
            }
            return UnaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: op,
                operand: operand
            )
        }

        // Temporal unary operators
        if match(.always) {
            guard let operand = parseUnaryFormula() else {
                error("Expected formula after 'always'")
                return nil
            }
            return TemporalUnaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .always,
                operand: operand
            )
        }
        if match(.eventually) {
            guard let operand = parseUnaryFormula() else {
                error("Expected formula after 'eventually'")
                return nil
            }
            return TemporalUnaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .eventually,
                operand: operand
            )
        }
        if match(.after) {
            guard let operand = parseUnaryFormula() else {
                error("Expected formula after 'after'")
                return nil
            }
            return TemporalUnaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .after,
                operand: operand
            )
        }
        if match(.historically) {
            guard let operand = parseUnaryFormula() else {
                error("Expected formula after 'historically'")
                return nil
            }
            return TemporalUnaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .historically,
                operand: operand
            )
        }
        if match(.once) {
            guard let operand = parseUnaryFormula() else {
                error("Expected formula after 'once'")
                return nil
            }
            return TemporalUnaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .once,
                operand: operand
            )
        }
        if match(.before) {
            guard let operand = parseUnaryFormula() else {
                error("Expected formula after 'before'")
                return nil
            }
            return TemporalUnaryFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .before,
                operand: operand
            )
        }

        return parseQuantifiedFormula()
    }

    // Quantified formulas: all/some/no/one/lone x: T | F
    // Also handles let formulas: let x = e | F
    private func parseQuantifiedFormula() -> (any FormulaNode)? {
        let startSpan = currentToken.span

        // Let formula: let x = e | formula
        if match(.let) {
            var bindings: [LetBinding] = []
            repeat {
                guard let name = expectIdentifier("variable name") else { return nil }
                expect(.equal, "Expected '=' in let binding")
                guard let value = parseExpr() else {
                    error("Expected expression in let binding")
                    return nil
                }
                bindings.append(LetBinding(name: name, value: value))
            } while match(.comma)

            expect(.pipe, "Expected '|' after let bindings")

            guard let body = parseFormula() else {
                error("Expected formula body after '|'")
                return nil
            }

            return LetFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                bindings: bindings,
                body: body
            )
        }

        var quantifier: Quantifier? = nil

        if match(.all) { quantifier = .all }
        else if match(.some) { quantifier = .some }
        else if match(.no) { quantifier = .no }
        else if match(.one) { quantifier = .one }
        else if match(.lone) { quantifier = .lone }
        else if match(.sum) { quantifier = .sum }

        if let q = quantifier {
            // Check if this is a quantified formula (has ':' for decls) or multiplicity formula
            // Look ahead to see if there's a colon after potential variable names
            if isQuantifiedDecl() {
                var decls: [QuantDecl] = []
                repeat {
                    guard let decl = parseQuantDecl() else {
                        break // Stop parsing on incomplete declaration
                    }
                    decls.append(decl)
                } while match(.comma) && isQuantifiedDecl()

                expect(.pipe, "Expected '|' after quantifier declarations")

                guard let body = parseFormula() else {
                    error("Expected formula body")
                    return nil
                }

                return QuantifiedFormula(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    quantifier: q,
                    decls: decls,
                    formula: body
                )
            } else {
                // Multiplicity formula: some/no/one/lone expr
                guard let expr = parseExpr() else {
                    error("Expected expression after multiplicity")
                    return nil
                }
                return MultFormula(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    multiplicity: q,
                    expr: expr
                )
            }
        }

        return parseCompareFormula()
    }

    private func isQuantifiedDecl() -> Bool {
        // Look ahead to see if we have pattern: [disj] name [, name]* : type
        var i = current
        if i < tokens.count && tokens[i].kind == .disj { i += 1 }
        // Skip identifiers and commas
        while i < tokens.count {
            if case .identifier = tokens[i].kind {
                i += 1
                if i < tokens.count && tokens[i].kind == .comma {
                    i += 1
                } else {
                    break
                }
            } else {
                break
            }
        }
        // Check for colon
        return i < tokens.count && tokens[i].kind == .colon
    }

    private func parseQuantDecl() -> QuantDecl? {
        let isDisjoint = match(.disj)

        var names: [Identifier] = []
        repeat {
            if let name = expectIdentifier("variable name") {
                names.append(name)
            }
        } while match(.comma) && !check(.colon)

        guard !names.isEmpty else { return nil }

        expect(.colon, "Expected ':' in quantifier declaration")

        guard let bound = parseExpr() else {
            error("Expected bound expression")
            return nil
        }

        return QuantDecl(isDisjoint: isDisjoint, names: names, bound: bound)
    }

    // Comparison: expr (= != in < > =< >=) expr
    private func parseCompareFormula() -> (any FormulaNode)? {
        guard let left = parseExpr() else { return nil }
        let startSpan = left.span

        var op: CompareOp? = nil
        if match(.equal) { op = .equal }
        else if match(.notEqual) { op = .notEqual }
        else if match(.in) { op = .in }
        else if match(.less) { op = .less }
        else if match(.lessEqual) { op = .lessEqual }
        else if match(.greater) { op = .greater }
        else if match(.greaterEqual) { op = .greaterEqual }
        else if match(.not) && match(.in) { op = .notIn }

        if let op = op {
            guard let right = parseExpr() else {
                error("Expected expression after comparison operator")
                return nil
            }
            return CompareFormula(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left,
                op: op,
                right: right
            )
        }

        // Wrap expression as formula
        return ExprFormula(span: left.span, expr: left)
    }

    // MARK: - Expression Parsing (Pratt-style precedence)

    private func parseExpr() -> (any ExprNode)? {
        parseConditionalExpr()
    }

    // Conditional expression: cond => thenExpr else elseExpr
    private func parseConditionalExpr() -> (any ExprNode)? {
        // In Alloy, conditional expressions have the form: formula => expr else expr
        // The condition is a formula, and the then/else parts are expressions.
        // We detect this by: if after parsing a union expression we see => and later else,
        // we interpret it as a conditional expression.

        // First parse what might be the start of a conditional or a regular expression
        let startSpan = currentToken.span

        // Check for common formula-only patterns that would indicate a conditional
        // These include: quantifiers (all, some, no, lone, one), negation (not/!), etc.
        if check(.all) || check(.no) || check(.lone) || check(.one) ||
           check(.not) || check(.bang) ||
           check(.always) || check(.eventually) || check(.historically) || check(.once) {
            // This looks like a formula-first conditional expression
            guard let condition = parseFormula() else {
                return nil
            }

            // Check for => thenExpr else elseExpr
            if match(.fatArrow) || match(.implies) {
                guard let thenExpr = parseUnionExpr() else {
                    error("Expected expression after '=>'")
                    return nil
                }

                if match(.else) {
                    guard let elseExpr = parseUnionExpr() else {
                        error("Expected expression after 'else'")
                        return nil
                    }
                    return IfExpr(
                        span: SourceSpan(start: startSpan.start, end: previous.span.end),
                        condition: condition,
                        thenExpr: thenExpr,
                        elseExpr: elseExpr
                    )
                }

                // No else - this is unusual in expression context
                // Wrap condition and thenExpr as best we can
                // Return thenExpr but this is technically an error for expressions
                return thenExpr
            }

            // No =>, so this was just a formula in expression context
            // Wrap it as an ExprFormula (formula used as expression)
            return wrapFormulaAsExpr(condition)
        }

        // Parse as regular expression
        guard let expr = parseUnionExpr() else {
            return nil
        }

        // Check for conditional expression syntax after a simple expression
        // e.g., "x.f != none => x.f else default"
        // IMPORTANT: Only consume => if followed by expr AND else
        // Otherwise, leave => for formula implication parsing
        if check(.fatArrow) || check(.implies) {
            // Look ahead to see if there's an else after the =>
            // Save position
            let savedPos = current
            advance() // consume => or implies

            guard let thenExpr = parseUnionExpr() else {
                // Parsing failed, restore and return expr
                current = savedPos
                return expr
            }

            if match(.else) {
                guard let elseExpr = parseUnionExpr() else {
                    error("Expected expression after 'else'")
                    return thenExpr
                }
                // Convert expr to a formula condition
                let condition = ExprFormula(span: expr.span, expr: expr)
                return IfExpr(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    condition: condition,
                    thenExpr: thenExpr,
                    elseExpr: elseExpr
                )
            }

            // No else found - this is formula implication, not conditional expression
            // Restore position so formula parser can handle it
            current = savedPos
        }

        return expr
    }

    // Helper to wrap a formula as an expression for expression context
    private func wrapFormulaAsExpr(_ formula: any FormulaNode) -> any ExprNode {
        // Create a block expression with the single formula
        return BlockExpr(span: formula.span, formulas: [formula])
    }

    // + (union)
    private func parseUnionExpr() -> (any ExprNode)? {
        var left = parseDifferenceExpr()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.plus) {
            let startSpan = left?.span ?? currentToken.span
            guard let right = parseDifferenceExpr() else {
                error("Expected expression after '+'")
                return left
            }
            left = BinaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: .union,
                right: right
            )
        }

        return left
    }

    // - (difference)
    private func parseDifferenceExpr() -> (any ExprNode)? {
        var left = parseIntersectionExpr()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.minus) {
            let startSpan = left?.span ?? currentToken.span
            guard let right = parseIntersectionExpr() else {
                error("Expected expression after '-'")
                return left
            }
            left = BinaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: .difference,
                right: right
            )
        }

        return left
    }

    // & (intersection)
    private func parseIntersectionExpr() -> (any ExprNode)? {
        var left = parseOverrideExpr()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.ampersand) {
            let startSpan = left?.span ?? currentToken.span
            guard let right = parseOverrideExpr() else {
                error("Expected expression after '&'")
                return left
            }
            left = BinaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: .intersection,
                right: right
            )
        }

        return left
    }

    // ++ (override)
    private func parseOverrideExpr() -> (any ExprNode)? {
        var left = parseArrowExpr()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.plusPlus) {
            let startSpan = left?.span ?? currentToken.span
            guard let right = parseArrowExpr() else {
                error("Expected expression after '++'")
                return left
            }
            left = BinaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: .override,
                right: right
            )
        }

        return left
    }

    // -> (product/arrow)
    private func parseArrowExpr() -> (any ExprNode)? {
        var left = parseRestrictionExpr()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.arrow) {
            let startSpan = left?.span ?? currentToken.span
            guard let right = parseRestrictionExpr() else {
                error("Expected expression after '->'")
                return left
            }
            left = BinaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: .product,
                right: right
            )
        }

        return left
    }

    // <: :> (domain/range restriction)
    private func parseRestrictionExpr() -> (any ExprNode)? {
        var left = parseJoinExpr()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while true {
            if match(.leftRestrict) {
                let startSpan = left?.span ?? currentToken.span
                guard let right = parseJoinExpr() else {
                    error("Expected expression after '<:'")
                    return left
                }
                left = BinaryExpr(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    left: left!,
                    op: .domainRestrict,
                    right: right
                )
            } else if match(.rightRestrict) {
                let startSpan = left?.span ?? currentToken.span
                guard let right = parseJoinExpr() else {
                    error("Expected expression after ':>'")
                    return left
                }
                left = BinaryExpr(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    left: left!,
                    op: .rangeRestrict,
                    right: right
                )
            } else {
                break
            }
        }

        return left
    }

    // . (join)
    private func parseJoinExpr() -> (any ExprNode)? {
        var left = parseUnaryExpr()

        // Guard against nil left before entering operator loop
        guard left != nil else { return nil }

        while match(.dot) {
            let startSpan = left?.span ?? currentToken.span
            guard let right = parseUnaryExpr() else {
                error("Expected expression after '.'")
                return left
            }
            left = BinaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                left: left!,
                op: .join,
                right: right
            )
        }

        return left
    }

    // Unary: ~ ^ * # - ' set some lone one no
    private func parseUnaryExpr() -> (any ExprNode)? {
        let startSpan = currentToken.span

        // Prefix unary operators
        if match(.tilde) {
            guard let operand = parseUnaryExpr() else {
                error("Expected expression after '~'")
                return nil
            }
            return UnaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .transpose,
                operand: operand
            )
        }
        if match(.caret) {
            guard let operand = parseUnaryExpr() else {
                error("Expected expression after '^'")
                return nil
            }
            return UnaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .transitiveClosure,
                operand: operand
            )
        }
        if match(.star) {
            guard let operand = parseUnaryExpr() else {
                error("Expected expression after '*'")
                return nil
            }
            return UnaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .reflexiveTransitiveClosure,
                operand: operand
            )
        }
        if match(.hash) {
            guard let operand = parseUnaryExpr() else {
                error("Expected expression after '#'")
                return nil
            }
            return UnaryExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                op: .cardinality,
                operand: operand
            )
        }

        // Multiplicity expressions (used in field types)
        if match(.set) {
            guard let operand = parseUnaryExpr() else {
                error("Expected expression after 'set'")
                return nil
            }
            return MultExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                multiplicity: .set,
                expr: operand
            )
        }
        // Check lookahead BEFORE consuming the token to avoid losing it
        if check(.lone) && !isQuantifiedDecl() {
            advance() // Now safe to consume
            guard let operand = parseUnaryExpr() else {
                error("Expected expression after 'lone'")
                return nil
            }
            return MultExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                multiplicity: .lone,
                expr: operand
            )
        }
        if check(.one) && !isQuantifiedDecl() {
            advance() // Now safe to consume
            guard let operand = parseUnaryExpr() else {
                error("Expected expression after 'one'")
                return nil
            }
            return MultExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                multiplicity: .one,
                expr: operand
            )
        }
        if check(.some) && !isQuantifiedDecl() {
            advance() // Now safe to consume
            guard let operand = parseUnaryExpr() else {
                error("Expected expression after 'some'")
                return nil
            }
            return MultExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                multiplicity: .some,
                expr: operand
            )
        }

        return parsePrimaryExpr()
    }

    // Primary: identifier, integer, (expr), {comprehension}, let, if
    private func parsePrimaryExpr() -> (any ExprNode)? {
        let startSpan = currentToken.span

        // Integer literal
        if case .integer(let n) = currentToken.kind {
            advance()
            return IntLiteralExpr(span: previous.span, value: n)
        }

        // Built-in constants
        if match(.none) {
            return NameExpr(
                span: previous.span,
                name: QualifiedName(single: Identifier(span: previous.span, name: "none"))
            )
        }
        if match(.univ) {
            return NameExpr(
                span: previous.span,
                name: QualifiedName(single: Identifier(span: previous.span, name: "univ"))
            )
        }
        if match(.iden) {
            return NameExpr(
                span: previous.span,
                name: QualifiedName(single: Identifier(span: previous.span, name: "iden"))
            )
        }
        if match(.int) {
            return NameExpr(
                span: previous.span,
                name: QualifiedName(single: Identifier(span: previous.span, name: "Int"))
            )
        }

        // Parenthesized expression
        if match(.leftParen) {
            guard let expr = parseExpr() else {
                error("Expected expression after '('")
                return nil
            }
            expect(.rightParen, "Expected ')' after expression")
            return expr
        }

        // Set comprehension: {decls | formula}
        if match(.leftBrace) {
            // Could be comprehension or block - check for decl pattern
            if isComprehensionStart() {
                var decls: [QuantDecl] = []
                repeat {
                    guard let decl = parseQuantDecl() else {
                        break // Stop parsing on incomplete declaration
                    }
                    decls.append(decl)
                } while match(.comma) && isQuantifiedDecl()

                expect(.pipe, "Expected '|' in comprehension")

                guard let formula = parseFormula() else {
                    error("Expected formula in comprehension")
                    return nil
                }

                expect(.rightBrace, "Expected '}' after comprehension")

                return ComprehensionExpr(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    decls: decls,
                    formula: formula
                )
            } else {
                // Block expression
                var formulas: [any FormulaNode] = []
                while !check(.rightBrace) && !isAtEnd {
                    if let formula = parseFormula() {
                        formulas.append(formula)
                    } else {
                        break
                    }
                }
                expect(.rightBrace, "Expected '}'")
                return BlockExpr(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    formulas: formulas
                )
            }
        }

        // Let expression
        if match(.let) {
            var bindings: [LetBinding] = []
            repeat {
                guard let name = expectIdentifier("variable name") else { return nil }
                expect(.equal, "Expected '=' in let binding")
                guard let value = parseExpr() else {
                    error("Expected expression in let binding")
                    return nil
                }
                bindings.append(LetBinding(name: name, value: value))
            } while match(.comma)

            expect(.pipe, "Expected '|' after let bindings")

            guard let body = parseExpr() else {
                error("Expected body expression after '|'")
                return nil
            }

            return LetExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                bindings: bindings,
                body: body
            )
        }

        // Identifier / Qualified name
        if case .identifier = currentToken.kind {
            guard let name = parseQualifiedName() else { return nil }
            var result: any ExprNode = NameExpr(
                span: SourceSpan(start: startSpan.start, end: previous.span.end),
                name: name
            )

            // Check for box join: expr[args]
            while match(.leftBracket) {
                var args: [any ExprNode] = []
                if !check(.rightBracket) {
                    repeat {
                        if let arg = parseExpr() {
                            args.append(arg)
                        }
                    } while match(.comma)
                }
                expect(.rightBracket, "Expected ']' after arguments")
                result = BoxJoinExpr(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    left: result,
                    args: args
                )
            }

            // Check for prime (next state)
            if match(.prime) {
                result = UnaryExpr(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    op: .prime,
                    operand: result
                )
            }

            return result
        }

        // @name - suppresses field expansion in sig facts (Alloy spec)
        // Handles @this, @field, etc.
        if check(.at) {
            let nextIdx = current + 1
            if nextIdx < tokens.count,
               case .identifier(let identName) = tokens[nextIdx].kind {
                advance() // consume @
                advance() // consume identifier
                // Store with @ prefix to indicate suppressed expansion
                return NameExpr(
                    span: SourceSpan(start: startSpan.start, end: previous.span.end),
                    name: QualifiedName(single: Identifier(span: previous.span, name: "@\(identName)"))
                )
            }
        }

        return nil
    }

    private func isComprehensionStart() -> Bool {
        // Look for pattern: [disj] name [, name]* : ... | ...
        var i = current
        if i < tokens.count && tokens[i].kind == .disj { i += 1 }
        // Need at least one identifier
        guard i < tokens.count, case .identifier = tokens[i].kind else { return false }
        i += 1
        // Skip more identifiers with commas
        while i < tokens.count {
            if tokens[i].kind == .comma {
                i += 1
                if i < tokens.count, case .identifier = tokens[i].kind {
                    i += 1
                } else {
                    break
                }
            } else {
                break
            }
        }
        // Must have colon
        return i < tokens.count && tokens[i].kind == .colon
    }

    // MARK: - Token Helpers

    private var currentToken: Token {
        guard current < tokens.count else {
            return tokens.last ?? Token(kind: .eof, span: SourceSpan.zero)
        }
        return tokens[current]
    }

    private var previous: Token {
        guard current > 0 else {
            return tokens.first ?? Token(kind: .eof, span: SourceSpan.zero)
        }
        return tokens[current - 1]
    }

    private var isAtEnd: Bool {
        currentToken.kind == .eof
    }

    @discardableResult
    private func advance() -> Token {
        if !isAtEnd {
            current += 1
        }
        return previous
    }

    private func check(_ kind: TokenKind) -> Bool {
        if isAtEnd { return false }
        return currentToken.kind == kind
    }

    private func match(_ kind: TokenKind) -> Bool {
        if check(kind) {
            advance()
            return true
        }
        return false
    }

    @discardableResult
    private func expect(_ kind: TokenKind, _ message: String) -> Token? {
        if check(kind) {
            return advance()
        }
        error(message)
        return nil
    }

    private func expectIdentifier(_ context: String) -> Identifier? {
        if case .identifier(let name) = currentToken.kind {
            let span = currentToken.span
            advance()
            return Identifier(span: span, name: name)
        }
        error("Expected \(context)")
        return nil
    }

    private func parseIdentifier() -> Identifier? {
        if case .identifier(let name) = currentToken.kind {
            let span = currentToken.span
            advance()
            return Identifier(span: span, name: name)
        }
        return nil
    }

    private func parseQualifiedName() -> QualifiedName? {
        guard let first = parseIdentifier() else { return nil }

        var parts: [Identifier] = [first]
        while match(.slash) {
            if let part = expectIdentifier("qualified name part") {
                parts.append(part)
            } else {
                break // Stop parsing on error
            }
        }

        return QualifiedName(parts: parts)
    }

    private func isParagraphStart() -> Bool {
        switch currentToken.kind {
        case .fact, .pred, .fun, .assert, .run, .check, .enum,
             .sig, .abstract, .one, .lone, .some, .var:
            return true
        default:
            return false
        }
    }

    // MARK: - Error Handling

    private func error(_ message: String) {
        let err = ParseError(message: message, span: currentToken.span)
        errors.append(err)
    }

    private func synchronize() {
        advance()

        while !isAtEnd {
            // Synchronize on paragraph boundaries
            if isParagraphStart() {
                return
            }
            advance()
        }
    }

    /// Synchronize within a block - skip tokens until we find something that could start a formula
    private func synchronizeInBlock() {
        // Report error for the current token if not already at a synchronization point
        if !check(.rightBrace) && !isAtEnd {
            error("Unexpected token '\(currentToken.text)'")
            advance()
        }

        while !isAtEnd {
            // Stop at block end
            if check(.rightBrace) {
                return
            }
            // Stop at tokens that could start a new formula
            if isFormulaStart() || isParagraphStart() {
                return
            }
            advance()
        }
    }

    /// Check if current token could start a formula
    private func isFormulaStart() -> Bool {
        switch currentToken.kind {
        // Quantifiers
        case .all, .some, .no, .lone, .one, .sum:
            return true
        // Temporal operators
        case .always, .eventually, .after, .historically, .once, .before:
            return true
        // Logical operators (unary)
        case .not, .bang:
            return true
        // Let expression
        case .let:
            return true
        // Parentheses and braces
        case .leftParen, .leftBrace:
            return true
        // Identifiers (could be predicate call or comparison start)
        case .identifier:
            return true
        // Built-ins
        case .none, .univ, .iden, .int:
            return true
        // Literals
        case .integer:
            return true
        // Unary operators that could start an expression
        case .hash, .tilde, .caret, .star, .minus:
            return true
        default:
            return false
        }
    }

    public func getErrors() -> [ParseError] {
        errors
    }
}

// MARK: - Parse Error

public struct ParseError: Error, Sendable {
    public let message: String
    public let span: SourceSpan
}

