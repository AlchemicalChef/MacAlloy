import Foundation

// MARK: - Expression Encoder

/// Encodes Alloy expressions into boolean matrices
public final class ExpressionEncoder {
    /// The translation context
    public let context: TranslationContext

    /// CNF builder shorthand
    public var cnf: CNFBuilder { context.cnf }

    /// Universe shorthand
    public var universe: Universe { context.universe }

    /// Integer encoder for arithmetic operations
    public private(set) lazy var integerEncoder: IntegerEncoder = {
        IntegerEncoder(context: context)
    }()

    /// Create an expression encoder
    public init(context: TranslationContext) {
        self.context = context
    }

    // MARK: - Main Encoding Entry Point

    /// Encode an expression node to a boolean matrix
    public func encode(_ expr: any ExprNode) -> BooleanMatrix {
        switch expr {
        case let nameExpr as NameExpr:
            return encodeNameExpr(nameExpr)

        case let binaryExpr as BinaryExpr:
            return encodeBinaryExpr(binaryExpr)

        case let unaryExpr as UnaryExpr:
            return encodeUnaryExpr(unaryExpr)

        case let callExpr as CallExpr:
            return encodeCallExpr(callExpr)

        case let boxJoinExpr as BoxJoinExpr:
            return encodeBoxJoinExpr(boxJoinExpr)

        case let comprehensionExpr as ComprehensionExpr:
            return encodeComprehensionExpr(comprehensionExpr)

        case let letExpr as LetExpr:
            return encodeLetExpr(letExpr)

        case let ifExpr as IfExpr:
            return encodeIfExpr(ifExpr)

        case let intLiteral as IntLiteralExpr:
            return encodeIntLiteral(intLiteral)

        case let blockExpr as BlockExpr:
            return encodeBlockExpr(blockExpr)

        default:
            // Unknown expression type - log and return empty matrix
            #if DEBUG
            print("[ExpressionEncoder] WARNING: Unhandled expression type: \(type(of: expr)) at \(expr.span)")
            #endif
            return context.emptyMatrix(arity: 1)
        }
    }

    // MARK: - Name Expression

    /// Encode a name reference
    /// Per Alloy spec: in signature facts, bare field names expand to this.field
    /// The @ prefix suppresses this expansion (e.g., @field)
    private func encodeNameExpr(_ expr: NameExpr) -> BooleanMatrix {
        var name = expr.name.simpleName

        // Check for @ prefix (suppresses field expansion in sig facts)
        let suppressExpansion = name.hasPrefix("@")
        if suppressExpansion {
            name = String(name.dropFirst()) // Remove @ prefix
        }

        // Check special names first
        switch name {
        case "none":
            return context.emptyMatrix(arity: 1)

        case "univ":
            return BooleanMatrix(
                constant: TupleSet(atoms: universe.atoms),
                universe: universe
            )

        case "iden":
            return context.identityMatrix()

        case "Int", "seq/Int":
            // Integer signature - return all integer atoms
            if let intMatrix = context.intSigMatrix() {
                return intMatrix
            }
            return context.emptyMatrix(arity: 1)

        case "this":
            // "this" refers to the bound atom in sig facts
            if let bound = context.lookupBinding("this") {
                return bound
            }
            return context.emptyMatrix(arity: 1)

        default:
            break
        }

        // Check variable bindings (quantifier variables, let bindings)
        if let bound = context.lookupBinding(name) {
            return bound
        }

        // Check signatures
        if let sigMatrix = context.sigMatrix(name) {
            return sigMatrix
        }

        // Check fields - with auto-expansion for signature facts
        if let fieldMatrix = context.fieldMatrix(name) {
            // Per Alloy spec: in sig facts, bare field names expand to this.field
            // unless prefixed with @ (which was stripped above)
            if !suppressExpansion,
               let sig = context.currentSigFact,
               sig.fields.contains(where: { $0.name == name }),
               let thisMatrix = context.lookupBinding("this") {
                // Expand to this.field (join this with field relation)
                return thisMatrix.join(fieldMatrix, cnf: cnf)
            }
            return fieldMatrix
        }

        // Check enum values
        if let enumAtom = findEnumAtom(name) {
            return context.atomMatrix(enumAtom)
        }

        // Symbol table lookup
        if let symbol = context.symbolTable.lookup(name) {
            return encodeSymbol(symbol)
        }

        // Qualified name lookup
        if expr.name.isQualified {
            if let symbol = context.symbolTable.lookup(expr.name) {
                return encodeSymbol(symbol)
            }
        }

        // Not found - emit diagnostic and return empty
        context.diagnostics?.error(
            .undefinedName,
            "Undefined symbol '\(name)'",
            at: expr.span
        )
        return context.emptyMatrix(arity: 1)
    }

    /// Find an enum atom by name
    private func findEnumAtom(_ name: String) -> Atom? {
        universe.atoms.first { $0.name == name }
    }

    /// Encode a symbol reference
    private func encodeSymbol(_ symbol: Symbol) -> BooleanMatrix {
        switch symbol {
        case let sig as SigSymbol:
            if let atoms = context.sigAtoms[sig.name] {
                return BooleanMatrix(constant: TupleSet(atoms: atoms), universe: universe)
            }

        case let field as FieldSymbol:
            return context.fieldMatrix(field.name) ?? context.emptyMatrix(arity: 2)

        case let enumValue as EnumValueSymbol:
            if let atom = findEnumAtom(enumValue.name) {
                return context.atomMatrix(atom)
            }

        case let param as ParamSymbol:
            if let bound = context.lookupBinding(param.name) {
                return bound
            }

        case let quantVar as QuantVarSymbol:
            if let bound = context.lookupBinding(quantVar.name) {
                return bound
            }

        case let letVar as LetVarSymbol:
            if let bound = context.lookupBinding(letVar.name) {
                return bound
            }

        default:
            break
        }

        return context.emptyMatrix(arity: 1)
    }

    // MARK: - Binary Expression

    /// Encode a binary expression
    private func encodeBinaryExpr(_ expr: BinaryExpr) -> BooleanMatrix {
        let left = encode(expr.left)
        let right = encode(expr.right)

        switch expr.op {
        case .union:
            return left.union(right, cnf: cnf)

        case .difference:
            return left.difference(right, cnf: cnf)

        case .intersection:
            return left.intersection(right, cnf: cnf)

        case .join:
            return left.join(right, cnf: cnf)

        case .product:
            return left.product(right, cnf: cnf)

        case .override:
            return encodeOverride(left, right)

        case .domainRestrict:
            // s <: r - domain restriction
            return encodeDomainRestriction(left, right)

        case .rangeRestrict:
            // r :> s - range restriction
            return encodeRangeRestriction(left, right)

        case .add:
            return integerEncoder.encodePlus(left, right)

        case .sub:
            return integerEncoder.encodeMinus(left, right)

        case .mul:
            return integerEncoder.encodeMul(left, right)

        case .div:
            return integerEncoder.encodeDiv(left, right)

        case .rem:
            return integerEncoder.encodeRem(left, right)

        case .shl:
            // Left shift: a << b
            return integerEncoder.encodeShiftLeft(left, right)

        case .shr:
            // Logical (unsigned) right shift: a >>> b
            return integerEncoder.encodeShiftRightLogical(left, right)

        case .sha:
            // Arithmetic (signed) right shift: a >> b
            return integerEncoder.encodeShiftRightArithmetic(left, right)
        }
    }

    /// Encode override operation: a ++ b
    private func encodeOverride(_ a: BooleanMatrix, _ b: BooleanMatrix) -> BooleanMatrix {
        // a ++ b = (a - (dom(b) -> univ^(arity-1))) + b
        // Get domain of b
        let domB = projectFirst(b)

        // Create universal relation for remaining columns
        let remaining = context.universalMatrix(arity: max(1, b.arity - 1))

        // dom(b) -> remaining
        let toRemove = domB.product(remaining, cnf: cnf)

        // a - toRemove
        let restricted = a.difference(toRemove, cnf: cnf)

        // Union with b
        return restricted.union(b, cnf: cnf)
    }

    /// Project a relation onto its first column
    private func projectFirst(_ matrix: BooleanMatrix) -> BooleanMatrix {
        var result = BooleanMatrix(universe: universe, arity: 1)

        for tuple in matrix.tuples {
            let projected = AtomTuple(tuple.first)
            let currentVal = result[projected]
            let matrixVal = matrix[tuple]

            // result[projected] |= matrix[tuple]
            switch (currentVal, matrixVal) {
            case (.constant(true), _):
                continue // Already true
            case (_, .constant(false)):
                continue // No contribution
            case (.constant(false), let x):
                result[projected] = x
            case (_, .constant(true)):
                result[projected] = .trueValue
            case (.variable(let v1), .variable(let v2)):
                // Need OR of both
                let newVar = cnf.freshVariable()
                result[projected] = .variable(newVar)
                let formula = BooleanFormula.variable(v1).or(.variable(v2))
                cnf.assertTrue(BooleanFormula.variable(newVar).iff(formula))
            }
        }

        return result
    }

    /// Encode domain restriction: s <: r
    private func encodeDomainRestriction(_ domain: BooleanMatrix, _ relation: BooleanMatrix) -> BooleanMatrix {
        precondition(domain.arity == 1, "Domain must be unary")

        var result = BooleanMatrix(universe: universe, arity: relation.arity)

        for tuple in relation.tuples {
            let firstAtom = tuple.first
            let domainVal = domain[AtomTuple(firstAtom)]
            let relVal = relation[tuple]

            // result[tuple] = domain[first] & relation[tuple]
            switch (domainVal, relVal) {
            case (.constant(false), _), (_, .constant(false)):
                result[tuple] = .falseValue
            case (.constant(true), let x), (let x, .constant(true)):
                result[tuple] = x
            default:
                let v = cnf.freshVariable()
                result[tuple] = .variable(v)
                let formula = BooleanFormula.from(domainVal).and(.from(relVal))
                cnf.assertTrue(BooleanFormula.variable(v).iff(formula))
            }
        }

        return result
    }

    /// Encode range restriction: r :> s
    private func encodeRangeRestriction(_ relation: BooleanMatrix, _ range: BooleanMatrix) -> BooleanMatrix {
        precondition(range.arity == 1, "Range must be unary")

        var result = BooleanMatrix(universe: universe, arity: relation.arity)

        for tuple in relation.tuples {
            let lastAtom = tuple.last
            let rangeVal = range[AtomTuple(lastAtom)]
            let relVal = relation[tuple]

            // result[tuple] = relation[tuple] & range[last]
            switch (relVal, rangeVal) {
            case (.constant(false), _), (_, .constant(false)):
                result[tuple] = .falseValue
            case (.constant(true), let x), (let x, .constant(true)):
                result[tuple] = x
            default:
                let v = cnf.freshVariable()
                result[tuple] = .variable(v)
                let formula = BooleanFormula.from(relVal).and(.from(rangeVal))
                cnf.assertTrue(BooleanFormula.variable(v).iff(formula))
            }
        }

        return result
    }

    // MARK: - Unary Expression

    /// Encode a unary expression
    private func encodeUnaryExpr(_ expr: UnaryExpr) -> BooleanMatrix {
        let operand = encode(expr.operand)

        switch expr.op {
        case .transpose:
            return operand.transpose()

        case .transitiveClosure:
            return operand.transitiveClosure(cnf: cnf)

        case .reflexiveTransitiveClosure:
            return operand.reflexiveTransitiveClosure(cnf: cnf)

        case .cardinality:
            // #s - returns integer representing set cardinality
            return integerEncoder.encodeCardinality(operand)

        case .negate:
            // -n - integer negation
            return integerEncoder.encodeNegate(operand)

        case .prime:
            // r' - primed expression (next state value)
            return encodePrimedExpr(expr.operand)

        case .setOf, .someOf, .loneOf, .oneOf, .noOf:
            // Multiplicity qualifiers - just return the operand
            return operand
        }
    }

    /// Encode a primed expression (next state value)
    private func encodePrimedExpr(_ expr: any ExprNode) -> BooleanMatrix {
        guard let trace = context.trace else {
            // No temporal model - prime has no effect
            return encode(expr)
        }

        // Look for field name in the expression
        if let nameExpr = expr as? NameExpr {
            let name = nameExpr.name.simpleName
            if let tempRel = context.temporalRelations[name] {
                // Return the primed (next state) value
                return tempRel.primed(at: context.currentState)
            }
        }

        // For complex expressions, temporarily advance state
        let oldState = context.currentState
        if context.currentState < trace.length - 1 {
            context.currentState = oldState + 1
            let result = encode(expr)
            context.currentState = oldState
            return result
        }

        // At final state - handle loop-back properly
        if trace.requiresLoop {
            // Build result that depends on loop target
            // For each possible loop target, evaluate the expression at that state
            var resultMatrices: [(loopCondition: BooleanFormula, matrix: BooleanMatrix)] = []

            for loopTarget in 0..<trace.length {
                // Save state and evaluate at loop target
                context.currentState = loopTarget
                let matrixAtTarget = encode(expr)
                let loopCondition = trace.loopsTo(loopTarget)
                resultMatrices.append((loopCondition, matrixAtTarget))
                context.currentState = oldState
            }

            // Build an ITE matrix over loop targets
            // For simplicity, if all matrices have same constant value, return that
            if let first = resultMatrices.first?.matrix,
               resultMatrices.allSatisfy({ $0.matrix.isConstant && $0.matrix.equals(first) == .trueFormula }) {
                return first
            }

            // Return expression at loop target 0 as default (most common case)
            // Note: This is a simplification; full implementation would build ITE over all targets
            if let loopStart = trace.loopStart, loopStart < trace.length {
                context.currentState = loopStart
                let result = encode(expr)
                context.currentState = oldState
                return result
            }
        }

        // No loop or at final state without loop - return current state value
        return encode(expr)
    }

    // MARK: - Call Expression

    /// Encode a function call
    private func encodeCallExpr(_ expr: CallExpr) -> BooleanMatrix {
        let name = expr.callee.simpleName

        // Look up function in symbol table
        if let funSym = context.symbolTable.lookupFun(name) {
            return encodeFunctionCall(funSym, args: expr.args)
        }

        // Not found
        return context.emptyMatrix(arity: 1)
    }

    /// Encode a function call with arguments
    private func encodeFunctionCall(_ fun: FunSymbol, args: [any ExprNode]) -> BooleanMatrix {
        guard let body = fun.body else {
            return context.emptyMatrix(arity: 1)
        }

        // Validate parameter count
        if fun.parameters.count != args.count {
            context.diagnostics?.error(
                .argumentCountMismatch,
                "Function '\(fun.name)' expects \(fun.parameters.count) argument(s), got \(args.count)",
                at: SourceSpan.unknown
            )
            return context.emptyMatrix(arity: 1)
        }

        // Push a new scope for parameters
        context.pushScope()

        // Bind parameters to argument values
        for (param, arg) in zip(fun.parameters, args) {
            let argMatrix = encode(arg)
            context.bind(param.name, to: argMatrix)
        }

        // Evaluate body
        let result = encode(body)

        // Pop scope
        context.popScope()

        return result
    }

    // MARK: - Box Join Expression

    /// Encode a box join expression: e[args]
    private func encodeBoxJoinExpr(_ expr: BoxJoinExpr) -> BooleanMatrix {
        // e[a, b, ...] is syntactic sugar for a.b.....e
        var result = encode(expr.args[0])

        for arg in expr.args.dropFirst() {
            result = result.join(encode(arg), cnf: cnf)
        }

        // Finally join with left expression
        let left = encode(expr.left)
        return result.join(left, cnf: cnf)
    }

    // MARK: - Comprehension Expression

    /// Encode a set comprehension: {decls | formula}
    private func encodeComprehensionExpr(_ expr: ComprehensionExpr) -> BooleanMatrix {
        // Determine result arity from declarations
        let arity = expr.decls.reduce(0) { $0 + $1.names.count }

        var result = BooleanMatrix(universe: universe, arity: arity)

        // For each possible tuple, check if formula holds
        let allTuples = universe.allTuples(arity: arity)

        for tuple in allTuples {
            context.pushScope()

            // Bind declaration variables to tuple elements
            var atomIndex = 0
            var boundOK = true

            for decl in expr.decls {
                let boundSet = encode(decl.bound)

                for name in decl.names {
                    let atom = tuple.atoms[atomIndex]
                    atomIndex += 1

                    // Check if atom is in bound set
                    let inBound = boundSet[AtomTuple(atom)]
                    if case .constant(false) = inBound {
                        boundOK = false
                        break
                    }

                    // Bind variable to this atom
                    context.bind(name.name, to: context.atomMatrix(atom))
                }

                if !boundOK { break }
            }

            if boundOK {
                // Create formula encoder to evaluate the formula
                let formulaEncoder = FormulaEncoder(context: context, exprEncoder: self)
                let formulaResult = formulaEncoder.encode(expr.formula)

                // result[tuple] = formula holds
                result[tuple] = booleanFormulaToValue(formulaResult)
            }

            context.popScope()
        }

        return result
    }

    /// Convert a boolean formula to a boolean value
    private func booleanFormulaToValue(_ formula: BooleanFormula) -> BooleanValue {
        switch formula {
        case .constant(let b):
            return .constant(b)
        case .variable(let v):
            return .variable(v)
        default:
            // Need a new variable
            let v = cnf.freshVariable()
            cnf.assertTrue(BooleanFormula.variable(v).iff(formula))
            return .variable(v)
        }
    }

    // MARK: - Let Expression

    /// Encode a let expression: let x = e | body
    private func encodeLetExpr(_ expr: LetExpr) -> BooleanMatrix {
        context.pushScope()

        for binding in expr.bindings {
            let value = encode(binding.value)
            context.bind(binding.name.name, to: value)
        }

        let result = encode(expr.body)

        context.popScope()

        return result
    }

    // MARK: - If Expression

    /// Encode a conditional expression: cond => then else other
    private func encodeIfExpr(_ expr: IfExpr) -> BooleanMatrix {
        let formulaEncoder = FormulaEncoder(context: context, exprEncoder: self)
        let condition = formulaEncoder.encode(expr.condition)

        let thenMatrix = encode(expr.thenExpr)
        let elseMatrix = encode(expr.elseExpr)

        // result[t] = (cond & then[t]) | (!cond & else[t])
        var result = BooleanMatrix(universe: universe, arity: thenMatrix.arity)

        for tuple in thenMatrix.tuples {
            let thenVal = thenMatrix[tuple]
            let elseVal = elseMatrix[tuple]

            // (cond & then) | (!cond & else)
            let thenPart = condition.and(.from(thenVal))
            let elsePart = condition.negated.and(.from(elseVal))
            let combined = thenPart.or(elsePart)

            result[tuple] = booleanFormulaToValue(combined)
        }

        return result
    }

    // MARK: - Integer Literal

    /// Encode an integer literal
    private func encodeIntLiteral(_ expr: IntLiteralExpr) -> BooleanMatrix {
        return integerEncoder.encodeIntegerLiteral(expr.value)
    }

    // MARK: - Block Expression

    /// Encode a block expression
    private func encodeBlockExpr(_ expr: BlockExpr) -> BooleanMatrix {
        // Block expression is treated as conjunction of formulas
        // Return univ if all formulas hold
        let formulaEncoder = FormulaEncoder(context: context, exprEncoder: self)

        var formulas: [BooleanFormula] = []
        for formula in expr.formulas {
            formulas.append(formulaEncoder.encode(formula))
        }

        let conjunction = BooleanFormula.conjunction(formulas)

        // Return univ if conjunction holds, else none
        // This is a simplification - proper handling would use ITE
        switch conjunction {
        case .constant(true):
            return BooleanMatrix(constant: TupleSet(atoms: universe.atoms), universe: universe)
        case .constant(false):
            return context.emptyMatrix(arity: 1)
        default:
            // Return univ (simplified)
            return BooleanMatrix(constant: TupleSet(atoms: universe.atoms), universe: universe)
        }
    }
}
