import Foundation

// MARK: - Semantic Analyzer

/// Main semantic analysis entry point
public final class SemanticAnalyzer: @unchecked Sendable {
    /// The symbol table
    public let symbolTable: SymbolTable

    /// Diagnostics collector
    public let diagnostics: DiagnosticCollector

    /// The AST being analyzed
    private var module: ModuleNode?

    // MARK: - Initialization

    public init() {
        self.symbolTable = SymbolTable()
        self.diagnostics = DiagnosticCollector()
    }

    // MARK: - Analysis Entry Point

    /// Analyze a module
    public func analyze(_ module: ModuleNode) {
        self.module = module
        diagnostics.clear()

        // Phase 1: Collect all declarations
        collectDeclarations(module)

        // Phase 2: Resolve inheritance
        resolveInheritance()

        // Phase 3: Type check expressions and formulas
        typeCheck(module)

        // Phase 4: Additional semantic checks
        performSemanticChecks(module)
    }

    /// Get analysis result
    public var hasErrors: Bool { diagnostics.hasErrors }
}

// MARK: - Phase 1: Declaration Collection

extension SemanticAnalyzer {
    /// Collect all declarations and build symbol table
    private func collectDeclarations(_ module: ModuleNode) {
        // Process imports
        for open in module.opens {
            collectOpen(open)
        }

        // First pass: collect all signature names (needed for extends/in)
        for paragraph in module.paragraphs {
            if let sigDecl = paragraph as? SigDeclNode {
                collectSigNames(sigDecl)
            } else if let enumDecl = paragraph as? EnumDeclNode {
                collectEnum(enumDecl)
            }
        }

        // Second pass: collect fields and other declarations
        for paragraph in module.paragraphs {
            if let sigDecl = paragraph as? SigDeclNode {
                collectSigFields(sigDecl)
            } else if let factDecl = paragraph as? FactDeclNode {
                collectFact(factDecl)
            } else if let predDecl = paragraph as? PredDeclNode {
                collectPred(predDecl)
            } else if let funDecl = paragraph as? FunDeclNode {
                collectFun(funDecl)
            } else if let assertDecl = paragraph as? AssertDeclNode {
                collectAssert(assertDecl)
            }
            // RunCmdNode and CheckCmdNode don't create symbols
        }
    }

    private func collectOpen(_ open: OpenNode) {
        let name = open.modulePath.simpleName
        let path = open.modulePath.parts.map(\.name)

        let sym = ModuleSymbol(name: name, path: path, definedAt: open.span)
        sym.alias = open.alias?.name

        if let existing = symbolTable.registerImport(sym) {
            diagnostics.error(.duplicateDefinition,
                              "Module '\(name)' already imported",
                              at: open.span)
            diagnostics.info(.duplicateDefinition,
                             "Previous import here",
                             at: existing.definedAt)
        }
    }

    private func collectSigNames(_ sigDecl: SigDeclNode) {
        for nameIdent in sigDecl.names {
            let sym = SigSymbol(
                name: nameIdent.name,
                definedAt: nameIdent.span,
                isAbstract: sigDecl.isAbstract,
                isVariable: sigDecl.isVariable,
                multiplicity: sigDecl.multiplicity
            )

            if let existing = symbolTable.registerSig(sym) {
                diagnostics.error(.duplicateDefinition,
                                  "Signature '\(nameIdent.name)' already defined",
                                  at: nameIdent.span)
                diagnostics.info(.duplicateDefinition,
                                 "Previous definition here",
                                 at: existing.definedAt)
            }
        }
    }

    private func collectSigFields(_ sigDecl: SigDeclNode) {
        for nameIdent in sigDecl.names {
            guard let sigSym = symbolTable.lookupSig(nameIdent.name) else { continue }

            // Enter signature scope for fields
            let sigScope = symbolTable.enterScope(.signature)
            sigScope.node = sigDecl

            // Collect fields
            for fieldDecl in sigDecl.fields {
                collectField(fieldDecl, owner: sigSym)
            }

            // Store signature fact if present
            sigSym.sigFact = sigDecl.sigFact

            symbolTable.exitScope()
        }
    }

    private func collectField(_ fieldDecl: FieldDeclNode, owner: SigSymbol) {
        // Infer field type from type expression
        let fieldType = inferType(fieldDecl.typeExpr)

        for nameIdent in fieldDecl.names {
            let sym = FieldSymbol(
                name: nameIdent.name,
                type: fieldType,
                definedAt: nameIdent.span,
                owner: owner,
                isVariable: fieldDecl.isVariable,
                isDisjoint: fieldDecl.isDisjoint
            )

            owner.fields.append(sym)

            if let existing = symbolTable.registerField(sym) {
                diagnostics.error(.duplicateDefinition,
                                  "Field '\(nameIdent.name)' already defined in signature '\(owner.name)'",
                                  at: nameIdent.span)
                diagnostics.info(.duplicateDefinition,
                                 "Previous definition here",
                                 at: existing.definedAt)
            }
        }
    }

    private func collectFact(_ factDecl: FactDeclNode) {
        let name = factDecl.factName?.name ?? "anonymous_\(symbolTable.facts.count)"
        let sym = FactSymbol(name: name, definedAt: factDecl.span)
        sym.body = factDecl.body

        if let existing = symbolTable.registerFact(sym), factDecl.factName != nil {
            diagnostics.error(.duplicateDefinition,
                              "Fact '\(name)' already defined",
                              at: factDecl.span)
            diagnostics.info(.duplicateDefinition,
                             "Previous definition here",
                             at: existing.definedAt)
        }
    }

    private func collectPred(_ predDecl: PredDeclNode) {
        // Resolve receiver if method-style
        var receiver: SigSymbol?
        if let recvName = predDecl.receiver {
            receiver = symbolTable.lookupSig(recvName.simpleName)
            if receiver == nil {
                diagnostics.error(.undefinedSignature,
                                  "Undefined signature '\(recvName.simpleName)'",
                                  at: recvName.span)
            }
        }

        let sym = PredSymbol(
            name: predDecl.predName.name,
            definedAt: predDecl.span,
            receiver: receiver
        )
        sym.body = predDecl.body

        // Enter predicate scope for parameters
        let predScope = symbolTable.enterScope(.predicate)
        predScope.node = predDecl

        // Collect parameters
        for paramDecl in predDecl.params {
            collectParams(paramDecl, into: &sym.parameters)
        }

        symbolTable.exitScope()

        if let existing = symbolTable.registerPred(sym) {
            diagnostics.error(.duplicateDefinition,
                              "Predicate '\(sym.fullName)' already defined",
                              at: predDecl.span)
            diagnostics.info(.duplicateDefinition,
                             "Previous definition here",
                             at: existing.definedAt)
        }
    }

    private func collectFun(_ funDecl: FunDeclNode) {
        // Resolve receiver if method-style
        var receiver: SigSymbol?
        if let recvName = funDecl.receiver {
            receiver = symbolTable.lookupSig(recvName.simpleName)
            if receiver == nil {
                diagnostics.error(.undefinedSignature,
                                  "Undefined signature '\(recvName.simpleName)'",
                                  at: recvName.span)
            }
        }

        // Infer return type
        let returnType: AlloyType
        if let rtExpr = funDecl.returnType {
            returnType = inferType(rtExpr)
        } else {
            returnType = UnknownType()
        }

        let sym = FunSymbol(
            name: funDecl.funName.name,
            returnType: returnType,
            definedAt: funDecl.span,
            receiver: receiver
        )
        sym.body = funDecl.body

        // Enter function scope for parameters
        let funScope = symbolTable.enterScope(.function)
        funScope.node = funDecl

        // Collect parameters
        for paramDecl in funDecl.params {
            collectParams(paramDecl, into: &sym.parameters)
        }

        symbolTable.exitScope()

        if let existing = symbolTable.registerFun(sym) {
            diagnostics.error(.duplicateDefinition,
                              "Function '\(sym.fullName)' already defined",
                              at: funDecl.span)
            diagnostics.info(.duplicateDefinition,
                             "Previous definition here",
                             at: existing.definedAt)
        }
    }

    private func collectParams(_ paramDecl: ParamDecl, into params: inout [ParamSymbol]) {
        let paramType = inferType(paramDecl.typeExpr)

        for nameIdent in paramDecl.names {
            let sym = ParamSymbol(
                name: nameIdent.name,
                type: paramType,
                definedAt: nameIdent.span,
                isDisjoint: paramDecl.isDisjoint
            )
            params.append(sym)

            if let existing = symbolTable.registerParam(sym) {
                diagnostics.error(.duplicateDefinition,
                                  "Parameter '\(nameIdent.name)' already defined",
                                  at: nameIdent.span)
                diagnostics.info(.duplicateDefinition,
                                 "Previous definition here",
                                 at: existing.definedAt)
            }
        }
    }

    private func collectAssert(_ assertDecl: AssertDeclNode) {
        guard let nameIdent = assertDecl.assertName else {
            // Anonymous assertion - unusual but allowed
            return
        }

        let sym = AssertSymbol(name: nameIdent.name, definedAt: assertDecl.span)
        sym.body = assertDecl.body

        if let existing = symbolTable.registerAssert(sym) {
            diagnostics.error(.duplicateDefinition,
                              "Assertion '\(nameIdent.name)' already defined",
                              at: assertDecl.span)
            diagnostics.info(.duplicateDefinition,
                             "Previous definition here",
                             at: existing.definedAt)
        }
    }

    private func collectEnum(_ enumDecl: EnumDeclNode) {
        let sym = EnumSymbol(name: enumDecl.enumName.name, definedAt: enumDecl.span)

        // Create enum value symbols
        for valueIdent in enumDecl.values {
            let valueSym = EnumValueSymbol(
                name: valueIdent.name,
                enumSymbol: sym,
                definedAt: valueIdent.span
            )
            sym.values.append(valueSym)
        }

        if let existing = symbolTable.registerEnum(sym) {
            diagnostics.error(.duplicateDefinition,
                              "Enum '\(enumDecl.enumName.name)' already defined",
                              at: enumDecl.span)
            diagnostics.info(.duplicateDefinition,
                             "Previous definition here",
                             at: existing.definedAt)
        }
    }
}

// MARK: - Phase 2: Resolve Inheritance

extension SemanticAnalyzer {
    /// Resolve signature inheritance relationships
    private func resolveInheritance() {
        // Process extends and in clauses
        guard let module = self.module else { return }

        for paragraph in module.paragraphs {
            guard let sigDecl = paragraph as? SigDeclNode else { continue }
            guard let ext = sigDecl.ext else { continue }

            for nameIdent in sigDecl.names {
                guard let sigSym = symbolTable.lookupSig(nameIdent.name) else { continue }

                switch ext {
                case .extends(let parentName):
                    if let parentSym = symbolTable.lookupSig(parentName.simpleName) {
                        sigSym.parent = parentSym
                    } else {
                        diagnostics.error(.undefinedSignature,
                                          "Undefined signature '\(parentName.simpleName)'",
                                          at: parentName.span)
                    }

                case .subset(let parentNames):
                    for parentName in parentNames {
                        if let parentSym = symbolTable.lookupSig(parentName.simpleName) {
                            sigSym.subsetOf.append(parentSym)
                        } else {
                            diagnostics.error(.undefinedSignature,
                                              "Undefined signature '\(parentName.simpleName)'",
                                              at: parentName.span)
                        }
                    }
                }
            }
        }

        // Build type hierarchy and check for cycles
        symbolTable.buildTypeHierarchy()
        checkForCyclicInheritance()
    }

    /// Check for cyclic inheritance
    private func checkForCyclicInheritance() {
        for sig in symbolTable.signatures.values {
            var visited = Set<ObjectIdentifier>()
            var current: SigSymbol? = sig

            while let s = current {
                let id = ObjectIdentifier(s)
                if visited.contains(id) {
                    diagnostics.error(.cyclicInheritance,
                                      "Cyclic inheritance detected for signature '\(sig.name)'",
                                      at: sig.definedAt)
                    break
                }
                visited.insert(id)
                current = s.parent
            }
        }
    }
}

// MARK: - Phase 3: Type Checking

extension SemanticAnalyzer {
    /// Type check all expressions and formulas
    private func typeCheck(_ module: ModuleNode) {
        let checker = TypeChecker(symbolTable: symbolTable, diagnostics: diagnostics)
        checker.check(module)
    }
}

// MARK: - Phase 4: Semantic Checks

extension SemanticAnalyzer {
    /// Perform additional semantic validation
    private func performSemanticChecks(_ module: ModuleNode) {
        checkTemporalConstraints(module)
        checkMultiplicityConstraints()
        checkUnusedDeclarations()
    }

    /// Check temporal operator usage
    private func checkTemporalConstraints(_ module: ModuleNode) {
        // Check that primed expressions only apply to variable fields
        let temporalChecker = TemporalChecker(symbolTable: symbolTable, diagnostics: diagnostics)
        temporalChecker.check(module)
    }

    /// Check multiplicity constraints
    private func checkMultiplicityConstraints() {
        // Verify multiplicity declarations are valid
        for sig in symbolTable.signatures.values {
            // Abstract signatures shouldn't have multiplicity
            if sig.sigType.isAbstract && sig.sigType.multiplicity != nil {
                diagnostics.warning(.invalidMultiplicity,
                                    "Abstract signature '\(sig.name)' has multiplicity constraint",
                                    at: sig.definedAt)
            }
        }
    }

    /// Check for unused declarations
    private func checkUnusedDeclarations() {
        // This would require usage tracking during type checking
        // For now, we skip this check
    }
}

// MARK: - Type Inference Helper

extension SemanticAnalyzer {
    /// Infer the type of an expression (basic version for field types)
    func inferType(_ expr: any ExprNode) -> AlloyType {
        if let nameExpr = expr as? NameExpr {
            let name = nameExpr.name.simpleName

            // Check for signature
            if let sig = symbolTable.lookupSig(name) {
                return sig.sigType
            }

            // Check for built-in types
            switch name {
            case "Int": return IntType.instance
            case "univ": return UnivType.instance
            case "none": return NoneType.instance
            case "iden": return IdenType.instance
            default: break
            }

            // Unknown type - will be resolved during type checking
            return UnknownType()
        }

        if let binaryExpr = expr as? BinaryExpr {
            let leftType = inferType(binaryExpr.left)
            let rightType = inferType(binaryExpr.right)

            switch binaryExpr.op {
            case .product:
                // Product creates relation
                return leftType.product(with: rightType)
            case .join:
                // Join reduces arity
                return leftType.join(with: rightType) ?? UnknownType()
            case .union, .intersection, .difference, .override:
                // Set operations and override preserve type
                return leftType
            default:
                return UnknownType()
            }
        }

        if let unaryExpr = expr as? UnaryExpr {
            let operandType = inferType(unaryExpr.operand)

            switch unaryExpr.op {
            case .transpose:
                // Transpose swaps columns
                if let relType = operandType as? RelationType, relType.arity == 2 {
                    return RelationType(columnTypes: relType.columnTypes.reversed())
                }
                return operandType
            case .transitiveClosure, .reflexiveTransitiveClosure:
                return operandType
            case .cardinality:
                return IntType.instance
            default:
                return operandType
            }
        }

        return UnknownType()
    }
}

// MARK: - Type Checker

/// Type checker for expressions and formulas
final class TypeChecker: @unchecked Sendable {
    let symbolTable: SymbolTable
    let diagnostics: DiagnosticCollector

    init(symbolTable: SymbolTable, diagnostics: DiagnosticCollector) {
        self.symbolTable = symbolTable
        self.diagnostics = diagnostics
    }

    func check(_ module: ModuleNode) {
        // Check all facts
        for paragraph in module.paragraphs {
            if let fact = paragraph as? FactDeclNode {
                checkFormula(fact.body)
            } else if let pred = paragraph as? PredDeclNode {
                if let body = pred.body {
                    // Enter predicate scope and register parameters
                    _ = symbolTable.enterScope(.predicate)

                    // Register parameters
                    for paramDecl in pred.params {
                        let paramType = inferType(paramDecl.typeExpr)
                        for name in paramDecl.names {
                            let paramSym = ParamSymbol(
                                name: name.name,
                                type: paramType,
                                definedAt: name.span,
                                isDisjoint: paramDecl.isDisjoint
                            )
                            symbolTable.registerParam(paramSym)
                        }
                    }

                    checkFormula(body)
                    symbolTable.exitScope()
                }
            } else if let assert = paragraph as? AssertDeclNode {
                checkFormula(assert.body)
            } else if let sig = paragraph as? SigDeclNode {
                if let sigFact = sig.sigFact {
                    checkFormula(sigFact)
                }
            } else if let run = paragraph as? RunCmdNode {
                if let body = run.body {
                    checkFormula(body)
                }
            } else if let check = paragraph as? CheckCmdNode {
                if let body = check.body {
                    checkFormula(body)
                }
            }
        }
    }

    func checkFormula(_ formula: any FormulaNode) {
        // Type check the formula - ensure it's a boolean expression
        if let binary = formula as? BinaryFormula {
            checkFormula(binary.left)
            checkFormula(binary.right)
        } else if let unary = formula as? UnaryFormula {
            checkFormula(unary.operand)
        } else if let quant = formula as? QuantifiedFormula {
            // Enter scope for quantified variables
            _ = symbolTable.enterScope(.quantifier)

            // Register quantified variables
            for decl in quant.decls {
                let type = inferType(decl.bound)
                for name in decl.names {
                    let sym = QuantVarSymbol(
                        name: name.name,
                        type: type,
                        definedAt: name.span,
                        isDisjoint: decl.isDisjoint
                    )
                    symbolTable.registerQuantVar(sym)
                }
            }

            checkFormula(quant.formula)
            symbolTable.exitScope()
        } else if let compare = formula as? CompareFormula {
            let leftType = checkExpr(compare.left)
            let rightType = checkExpr(compare.right)

            // Ensure arities match for comparison
            if leftType.arity != rightType.arity && leftType.arity != 0 && rightType.arity != 0 {
                diagnostics.error(.arityMismatch,
                                  "Cannot compare expressions of arity \(leftType.arity) and \(rightType.arity)",
                                  at: compare.span)
            }
        } else if let block = formula as? BlockFormula {
            for f in block.formulas {
                checkFormula(f)
            }
        } else if let letFormula = formula as? LetFormula {
            _ = symbolTable.enterScope(.letBinding)

            for binding in letFormula.bindings {
                let type = checkExpr(binding.value)
                let sym = LetVarSymbol(
                    name: binding.name.name,
                    type: type,
                    definedAt: binding.name.span
                )
                sym.boundExpr = binding.value
                symbolTable.registerLetVar(sym)
            }

            checkFormula(letFormula.body)
            symbolTable.exitScope()
        } else if let call = formula as? CallFormula {
            // Check predicate call
            let predName = call.callee.simpleName
            if symbolTable.lookupPred(predName) == nil && symbolTable.lookup(predName) == nil {
                diagnostics.error(.undefinedPredicate,
                                  "Undefined predicate '\(predName)'",
                                  at: call.callee.span)
            }

            for arg in call.args {
                _ = checkExpr(arg)
            }
        } else if let temporal = formula as? TemporalUnaryFormula {
            checkFormula(temporal.operand)
        } else if let temporal = formula as? TemporalBinaryFormula {
            checkFormula(temporal.left)
            checkFormula(temporal.right)
        } else if let mult = formula as? MultFormula {
            // Multiplicity formula: some/no/one/lone expr
            _ = checkExpr(mult.expr)
        } else if let exprF = formula as? ExprFormula {
            // Expression used as formula
            _ = checkExpr(exprF.expr)
        }
    }

    @discardableResult
    func checkExpr(_ expr: any ExprNode) -> AlloyType {
        if let nameExpr = expr as? NameExpr {
            let name = nameExpr.name.simpleName

            // Check for symbol in current scope
            if let sym = symbolTable.lookup(name) {
                return sym.type
            }

            // Check for field in any visible signature
            if let field = symbolTable.lookupField(name) {
                return field.fullType
            }

            // Check for built-in
            switch name {
            case "Int": return IntType.instance
            case "univ": return UnivType.instance
            case "none": return NoneType.instance
            case "iden": return IdenType.instance
            case "True", "False":
                return BoolType.instance
            default:
                diagnostics.error(.undefinedName,
                                  "Undefined name '\(name)'",
                                  at: nameExpr.span)
                return ErrorType(message: "undefined: \(name)")
            }
        }

        if let binary = expr as? BinaryExpr {
            let leftType = checkExpr(binary.left)
            let rightType = checkExpr(binary.right)

            switch binary.op {
            case .join:
                guard let result = leftType.join(with: rightType) else {
                    diagnostics.error(.invalidJoin,
                                      "Cannot join expressions of arity \(leftType.arity) and \(rightType.arity)",
                                      at: binary.span)
                    return ErrorType(message: "invalid join")
                }
                return result

            case .product:
                return leftType.product(with: rightType)

            case .union:
                if leftType.arity != rightType.arity {
                    diagnostics.error(.invalidUnion,
                                      "Cannot union expressions of different arities (\(leftType.arity) and \(rightType.arity))",
                                      at: binary.span)
                }
                return leftType

            case .intersection:
                if leftType.arity != rightType.arity {
                    diagnostics.error(.invalidIntersection,
                                      "Cannot intersect expressions of different arities (\(leftType.arity) and \(rightType.arity))",
                                      at: binary.span)
                }
                return leftType

            case .difference:
                if leftType.arity != rightType.arity {
                    diagnostics.error(.invalidUnion,
                                      "Cannot subtract expressions of different arities (\(leftType.arity) and \(rightType.arity))",
                                      at: binary.span)
                }
                return leftType

            case .override:
                return leftType

            case .domainRestrict, .rangeRestrict:
                // A <: B filters A to tuples with first element in B
                // A :> B filters A to tuples with last element in B
                // Both return a subset of A, so return leftType
                return leftType

            case .add, .sub, .mul, .div, .rem:
                // Integer arithmetic
                return IntType.instance

            case .shl, .shr, .sha:
                // Bit shift operations
                return IntType.instance
            }
        }

        if let unary = expr as? UnaryExpr {
            let operandType = checkExpr(unary.operand)

            switch unary.op {
            case .transpose:
                if operandType.arity != 2 {
                    diagnostics.error(.arityMismatch,
                                      "Transpose requires arity 2, got \(operandType.arity)",
                                      at: unary.span)
                }
                if let relType = operandType as? RelationType, relType.arity == 2 {
                    return RelationType(columnTypes: relType.columnTypes.reversed())
                }
                return operandType

            case .transitiveClosure, .reflexiveTransitiveClosure:
                if operandType.arity != 2 {
                    diagnostics.error(.arityMismatch,
                                      "Closure requires arity 2, got \(operandType.arity)",
                                      at: unary.span)
                }
                return operandType

            case .cardinality:
                return IntType.instance

            case .negate:
                if operandType is IntType {
                    return IntType.instance
                }
                diagnostics.error(.expectedInteger,
                                  "Negation requires integer, got \(operandType)",
                                  at: unary.span)
                return ErrorType(message: "invalid negation")

            case .prime:
                // Prime expression - checked separately
                return operandType

            case .setOf, .someOf, .loneOf, .oneOf, .noOf:
                // Multiplicity operators - return the operand type
                return operandType
            }
        }

        if let intLit = expr as? IntLiteralExpr {
            _ = intLit.value
            return IntType.instance
        }

        if let call = expr as? CallExpr {
            // Check function call
            if let funSym = symbolTable.lookupFun(call.callee.simpleName) {
                for arg in call.args {
                    _ = checkExpr(arg)
                }
                return funSym.type
            }

            // Look up the callee name
            if let sym = symbolTable.lookup(call.callee) {
                for arg in call.args {
                    _ = checkExpr(arg)
                }
                return sym.type
            }

            diagnostics.error(.undefinedFunction,
                              "Undefined function '\(call.callee.simpleName)'",
                              at: call.span)
            return ErrorType(message: "undefined function")
        }

        if let boxJoin = expr as? BoxJoinExpr {
            var resultType = checkExpr(boxJoin.left)
            for arg in boxJoin.args {
                let argType = checkExpr(arg)
                if let joined = argType.join(with: resultType) {
                    resultType = joined
                } else {
                    diagnostics.error(.invalidJoin,
                                      "Cannot perform box join",
                                      at: boxJoin.span)
                }
            }
            return resultType
        }

        if let comp = expr as? ComprehensionExpr {
            _ = symbolTable.enterScope(.quantifier)

            var resultType: AlloyType = UnknownType()
            for decl in comp.decls {
                let type = inferType(decl.bound)
                for name in decl.names {
                    let sym = QuantVarSymbol(
                        name: name.name,
                        type: type,
                        definedAt: name.span,
                        isDisjoint: decl.isDisjoint
                    )
                    symbolTable.registerQuantVar(sym)
                    resultType = type
                }
            }

            checkFormula(comp.formula)
            symbolTable.exitScope()

            return resultType
        }

        if let letExpr = expr as? LetExpr {
            _ = symbolTable.enterScope(.letBinding)

            for binding in letExpr.bindings {
                let type = checkExpr(binding.value)
                let sym = LetVarSymbol(
                    name: binding.name.name,
                    type: type,
                    definedAt: binding.name.span
                )
                sym.boundExpr = binding.value
                symbolTable.registerLetVar(sym)
            }

            let result = checkExpr(letExpr.body)
            symbolTable.exitScope()
            return result
        }

        if let ifExpr = expr as? IfExpr {
            checkFormula(ifExpr.condition)
            let thenType = checkExpr(ifExpr.thenExpr)
            let elseType = checkExpr(ifExpr.elseExpr)

            if thenType.arity != elseType.arity {
                diagnostics.error(.typeMismatch,
                                  "If-then-else branches have different arities (\(thenType.arity) and \(elseType.arity))",
                                  at: ifExpr.span)
            }
            return thenType
        }

        if let block = expr as? BlockExpr {
            // Block expression evaluates formulas and returns the last expression value
            // This is somewhat unusual in Alloy
            for formula in block.formulas {
                checkFormula(formula)
            }
            return UnknownType()
        }

        return UnknownType()
    }

    private func inferType(_ expr: any ExprNode) -> AlloyType {
        if let nameExpr = expr as? NameExpr {
            let name = nameExpr.name.simpleName
            if let sig = symbolTable.lookupSig(name) {
                return sig.sigType
            }
            switch name {
            case "Int": return IntType.instance
            case "univ": return UnivType.instance
            case "none": return NoneType.instance
            case "iden": return IdenType.instance
            default: return UnknownType()
            }
        }

        if let binary = expr as? BinaryExpr {
            let leftType = inferType(binary.left)
            let rightType = inferType(binary.right)

            switch binary.op {
            case .product:
                return leftType.product(with: rightType)
            case .join:
                return leftType.join(with: rightType) ?? UnknownType()
            default:
                return leftType
            }
        }

        return UnknownType()
    }
}

// MARK: - Temporal Checker

/// Checks temporal operator constraints
final class TemporalChecker: @unchecked Sendable {
    let symbolTable: SymbolTable
    let diagnostics: DiagnosticCollector

    init(symbolTable: SymbolTable, diagnostics: DiagnosticCollector) {
        self.symbolTable = symbolTable
        self.diagnostics = diagnostics
    }

    func check(_ module: ModuleNode) {
        for paragraph in module.paragraphs {
            if let fact = paragraph as? FactDeclNode {
                checkFormulaForPrime(fact.body)
            } else if let pred = paragraph as? PredDeclNode {
                if let body = pred.body {
                    checkFormulaForPrime(body)
                }
            } else if let assert = paragraph as? AssertDeclNode {
                checkFormulaForPrime(assert.body)
            }
        }
    }

    private func checkFormulaForPrime(_ formula: any FormulaNode) {
        // Check for primed expressions in formulas
        if let compare = formula as? CompareFormula {
            checkExprForPrime(compare.left)
            checkExprForPrime(compare.right)
        } else if let binary = formula as? BinaryFormula {
            checkFormulaForPrime(binary.left)
            checkFormulaForPrime(binary.right)
        } else if let unary = formula as? UnaryFormula {
            checkFormulaForPrime(unary.operand)
        } else if let quant = formula as? QuantifiedFormula {
            checkFormulaForPrime(quant.formula)
        } else if let block = formula as? BlockFormula {
            for f in block.formulas {
                checkFormulaForPrime(f)
            }
        } else if let letF = formula as? LetFormula {
            checkFormulaForPrime(letF.body)
        } else if let temporal = formula as? TemporalUnaryFormula {
            checkFormulaForPrime(temporal.operand)
        } else if let temporal = formula as? TemporalBinaryFormula {
            checkFormulaForPrime(temporal.left)
            checkFormulaForPrime(temporal.right)
        }
    }

    private func checkExprForPrime(_ expr: any ExprNode) {
        if let unary = expr as? UnaryExpr {
            if unary.op == .prime {
                // Check that the operand is a variable field
                checkPrimedExpr(unary.operand, at: unary.span)
            }
            checkExprForPrime(unary.operand)
        } else if let binary = expr as? BinaryExpr {
            checkExprForPrime(binary.left)
            checkExprForPrime(binary.right)
        } else if let call = expr as? CallExpr {
            for arg in call.args {
                checkExprForPrime(arg)
            }
        } else if let boxJoin = expr as? BoxJoinExpr {
            checkExprForPrime(boxJoin.left)
            for arg in boxJoin.args {
                checkExprForPrime(arg)
            }
        }
    }

    private func checkPrimedExpr(_ expr: any ExprNode, at span: SourceSpan) {
        // The primed expression should ultimately reference a variable field or signature
        if let nameExpr = expr as? NameExpr {
            let name = nameExpr.name.simpleName

            // Check if it's a variable signature
            if let sig = symbolTable.lookupSig(name) {
                if !sig.sigType.isVariable {
                    diagnostics.error(.primedNonVariable,
                                      "Cannot prime non-variable signature '\(name)'",
                                      at: span)
                }
                return
            }

            // Check if it's a variable field
            if let field = symbolTable.lookupField(name) {
                if !field.isVariable {
                    diagnostics.error(.primedNonVariable,
                                      "Cannot prime non-variable field '\(name)'",
                                      at: span)
                }
                return
            }

            // Might be a local variable - allow priming
        } else if let binary = expr as? BinaryExpr, binary.op == .join {
            // For join expressions like p.field, check the last part
            checkPrimedExpr(binary.right, at: span)
        }
    }
}
