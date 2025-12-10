import Foundation

// MARK: - Formula Encoder

/// Encodes Alloy formulas into boolean formulas for SAT solving
public final class FormulaEncoder {
    /// The translation context
    public let context: TranslationContext

    /// The expression encoder
    public let exprEncoder: ExpressionEncoder

    /// CNF builder shorthand
    public var cnf: CNFBuilder { context.cnf }

    /// Universe shorthand
    public var universe: Universe { context.universe }

    /// Create a formula encoder
    public init(context: TranslationContext, exprEncoder: ExpressionEncoder) {
        self.context = context
        self.exprEncoder = exprEncoder
    }

    /// Convenience initializer that creates its own expression encoder
    public convenience init(context: TranslationContext) {
        let exprEncoder = ExpressionEncoder(context: context)
        self.init(context: context, exprEncoder: exprEncoder)
    }

    // MARK: - Main Encoding Entry Point

    /// Encode a formula node to a boolean formula
    public func encode(_ formula: any FormulaNode) -> BooleanFormula {
        switch formula {
        case let binary as BinaryFormula:
            return encodeBinaryFormula(binary)

        case let unary as UnaryFormula:
            return encodeUnaryFormula(unary)

        case let quantified as QuantifiedFormula:
            return encodeQuantifiedFormula(quantified)

        case let compare as CompareFormula:
            return encodeCompareFormula(compare)

        case let letFormula as LetFormula:
            return encodeLetFormula(letFormula)

        case let block as BlockFormula:
            return encodeBlockFormula(block)

        case let call as CallFormula:
            return encodeCallFormula(call)

        case let temporalUnary as TemporalUnaryFormula:
            return encodeTemporalUnaryFormula(temporalUnary)

        case let temporalBinary as TemporalBinaryFormula:
            return encodeTemporalBinaryFormula(temporalBinary)

        case let mult as MultFormula:
            return encodeMultFormula(mult)

        case let exprForm as ExprFormula:
            return encodeExprFormula(exprForm)

        default:
            // Unknown formula type
            return .trueFormula
        }
    }

    // MARK: - Binary Formula

    /// Encode a binary logical formula
    private func encodeBinaryFormula(_ formula: BinaryFormula) -> BooleanFormula {
        let left = encode(formula.left)
        let right = encode(formula.right)

        switch formula.op {
        case .and, .andKeyword:
            return left.and(right)

        case .or, .orKeyword:
            return left.or(right)

        case .implies:
            return left.implies(right)

        case .iff:
            return left.iff(right)
        }
    }

    // MARK: - Unary Formula

    /// Encode a unary logical formula
    private func encodeUnaryFormula(_ formula: UnaryFormula) -> BooleanFormula {
        let operand = encode(formula.operand)

        switch formula.op {
        case .not, .notKeyword:
            return operand.negated
        }
    }

    // MARK: - Quantified Formula

    /// Encode a quantified formula
    private func encodeQuantifiedFormula(_ formula: QuantifiedFormula) -> BooleanFormula {
        // Handle multiplicity test on expression (no decls)
        if formula.decls.isEmpty {
            // This is a multiplicity test like "some x" or "no x"
            if let mult = formula.formula as? MultFormula {
                return encodeMultFormula(mult)
            }
            // Just encode the body
            return encode(formula.formula)
        }

        // Flatten all declarations into (name, bound) pairs
        var allDecls: [(String, BooleanMatrix, Bool)] = []
        for decl in formula.decls {
            let boundMatrix = exprEncoder.encode(decl.bound)
            for name in decl.names {
                allDecls.append((name.name, boundMatrix, decl.isDisjoint))
            }
        }

        return encodeQuantifierRecursive(
            quantifier: formula.quantifier,
            decls: allDecls,
            body: formula.formula,
            disjointSets: [:]
        )
    }

    /// Recursively encode a quantified formula
    private func encodeQuantifierRecursive(
        quantifier: Quantifier,
        decls: [(String, BooleanMatrix, Bool)],
        body: any FormulaNode,
        disjointSets: [String: Set<Atom>]
    ) -> BooleanFormula {
        guard let (name, boundMatrix, isDisjoint) = decls.first else {
            // No more variables - encode the body
            return encode(body)
        }

        let remainingDecls = Array(decls.dropFirst())

        var formulas: [BooleanFormula] = []

        for atom in universe.atoms {
            let inBound = boundMatrix[AtomTuple(atom)]

            // Check if this atom is valid (in bounds)
            guard !inBound.isFalse else { continue }

            // Check disjointness constraints
            var valid = true
            if isDisjoint {
                for (otherName, otherAtoms) in disjointSets {
                    if otherAtoms.contains(atom) {
                        valid = false
                        break
                    }
                }
            }

            if !valid { continue }

            // Update disjoint sets
            var newDisjointSets = disjointSets
            if isDisjoint {
                newDisjointSets[name, default: []].insert(atom)
            }

            // Bind this variable in a new scope
            context.pushScope()
            context.bind(name, to: context.atomMatrix(atom))

            // Recurse with the binding active
            let subFormula = encodeQuantifierRecursive(
                quantifier: quantifier,
                decls: remainingDecls,
                body: body,
                disjointSets: newDisjointSets
            )

            // Pop scope AFTER using the formula result
            context.popScope()

            // Include membership constraint
            let inBoundFormula = BooleanFormula.from(inBound)
            let combined: BooleanFormula

            switch quantifier {
            case .all:
                // all x: S | F  =>  for all atoms: (atom in S) => F
                combined = inBoundFormula.implies(subFormula)
            case .some:
                // some x: S | F  =>  exists atom: (atom in S) & F
                combined = inBoundFormula.and(subFormula)
            case .no:
                // no x: S | F  =>  for all atoms: (atom in S) => !F
                combined = inBoundFormula.implies(subFormula.negated)
            case .one:
                // one x: S | F  =>  exactly one atom: (atom in S) & F
                // Handled specially below
                combined = inBoundFormula.and(subFormula)
            case .lone:
                // lone x: S | F  =>  at most one atom: (atom in S) & F
                // Handled specially below
                combined = inBoundFormula.and(subFormula)
            case .sum:
                // sum quantifier - handled separately below
                combined = .trueFormula
            }

            formulas.append(combined)
        }

        // Combine based on quantifier
        switch quantifier {
        case .all, .no:
            return .conjunction(formulas)

        case .some:
            return .disjunction(formulas)

        case .one:
            return encodeExactlyOne(formulas)

        case .lone:
            return encodeAtMostOne(formulas)

        case .sum:
            // Sum quantifier is handled as an expression, not a formula
            // It should return a value, so when used as a formula, it's always true (no constraint)
            return .trueFormula
        }
    }

    /// Encode exactly-one constraint
    private func encodeExactlyOne(_ formulas: [BooleanFormula]) -> BooleanFormula {
        // At least one
        let atLeastOne = BooleanFormula.disjunction(formulas)

        // At most one: for each pair, not both
        var atMostOne: [BooleanFormula] = []
        for i in 0..<formulas.count {
            for j in (i+1)..<formulas.count {
                atMostOne.append(.disjunction([formulas[i].negated, formulas[j].negated]))
            }
        }

        return atLeastOne.and(.conjunction(atMostOne))
    }

    /// Encode at-most-one constraint
    private func encodeAtMostOne(_ formulas: [BooleanFormula]) -> BooleanFormula {
        var constraints: [BooleanFormula] = []
        for i in 0..<formulas.count {
            for j in (i+1)..<formulas.count {
                constraints.append(.disjunction([formulas[i].negated, formulas[j].negated]))
            }
        }
        return .conjunction(constraints)
    }

    // MARK: - Comparison Formula

    /// Encode a comparison formula
    private func encodeCompareFormula(_ formula: CompareFormula) -> BooleanFormula {
        let left = exprEncoder.encode(formula.left)
        let right = exprEncoder.encode(formula.right)

        switch formula.op {
        case .equal:
            return left.equals(right)

        case .notEqual:
            return left.equals(right).negated

        case .in:
            return left.isSubset(of: right)

        case .notIn:
            return left.isSubset(of: right).negated

        case .less:
            return exprEncoder.integerEncoder.encodeLessThan(left, right)

        case .lessEqual:
            return exprEncoder.integerEncoder.encodeLessThanOrEqual(left, right)

        case .greater:
            return exprEncoder.integerEncoder.encodeGreaterThan(left, right)

        case .greaterEqual:
            return exprEncoder.integerEncoder.encodeGreaterThanOrEqual(left, right)
        }
    }

    // MARK: - Let Formula

    /// Encode a let formula
    private func encodeLetFormula(_ formula: LetFormula) -> BooleanFormula {
        context.pushScope()

        for binding in formula.bindings {
            let value = exprEncoder.encode(binding.value)
            context.bind(binding.name.name, to: value)
        }

        let result = encode(formula.body)

        context.popScope()

        return result
    }

    // MARK: - Block Formula

    /// Encode a block formula (conjunction of formulas)
    private func encodeBlockFormula(_ formula: BlockFormula) -> BooleanFormula {
        var conjuncts: [BooleanFormula] = []
        for subFormula in formula.formulas {
            conjuncts.append(encode(subFormula))
        }
        return .conjunction(conjuncts)
    }

    // MARK: - Call Formula

    /// Encode a predicate call
    private func encodeCallFormula(_ formula: CallFormula) -> BooleanFormula {
        let name = formula.callee.simpleName

        // Look up predicate
        if let predSym = context.symbolTable.lookupPred(name) {
            return encodePredicateCall(predSym, args: formula.args)
        }

        // Try qualified name
        if let predSym = context.symbolTable.lookup(formula.callee) as? PredSymbol {
            return encodePredicateCall(predSym, args: formula.args)
        }

        // Not found - return true (no constraint)
        return .trueFormula
    }

    /// Encode a predicate call with arguments
    private func encodePredicateCall(_ pred: PredSymbol, args: [any ExprNode]) -> BooleanFormula {
        guard let body = pred.body else {
            return .trueFormula
        }

        context.pushScope()

        // Bind parameters
        for (param, arg) in zip(pred.parameters, args) {
            let argMatrix = exprEncoder.encode(arg)
            context.bind(param.name, to: argMatrix)
        }

        // Handle receiver for method-style predicates
        if let receiver = pred.receiver, args.count > pred.parameters.count {
            // First argument is the receiver
            let receiverArg = exprEncoder.encode(args[0])
            context.bind("this", to: receiverArg)
        }

        let result = encode(body)

        context.popScope()

        return result
    }

    // MARK: - Multiplicity Formula

    /// Encode a multiplicity test formula
    private func encodeMultFormula(_ formula: MultFormula) -> BooleanFormula {
        let matrix = exprEncoder.encode(formula.expr)

        switch formula.multiplicity {
        case .some:
            return matrix.isNonEmpty()

        case .no:
            return matrix.isEmpty()

        case .one:
            return matrix.hasExactlyOne()

        case .lone:
            return encodeAtMostOneInMatrix(matrix)

        case .all:
            // "all expr" doesn't make sense as a formula - return true
            return .trueFormula

        case .sum:
            // sum - not supported as formula
            return .trueFormula
        }
    }

    /// Encode at-most-one constraint for a matrix
    private func encodeAtMostOneInMatrix(_ matrix: BooleanMatrix) -> BooleanFormula {
        var constraints: [BooleanFormula] = []
        for i in 0..<matrix.count {
            for j in (i+1)..<matrix.count {
                let vi = BooleanFormula.from(matrix[i])
                let vj = BooleanFormula.from(matrix[j])
                constraints.append(.disjunction([vi.negated, vj.negated]))
            }
        }
        return .conjunction(constraints)
    }

    // MARK: - Expression as Formula

    /// Encode an expression used as a formula
    private func encodeExprFormula(_ formula: ExprFormula) -> BooleanFormula {
        let matrix = exprEncoder.encode(formula.expr)
        // An expression as a formula is true if non-empty
        return matrix.isNonEmpty()
    }

    // MARK: - Temporal Formulas

    /// Encode a temporal unary formula
    private func encodeTemporalUnaryFormula(_ formula: TemporalUnaryFormula) -> BooleanFormula {
        guard let ltlEncoder = context.ltlEncoder else {
            // No temporal model - just encode the body
            return encode(formula.operand)
        }

        let bodyEncoder: (Int) -> BooleanFormula = { [self] state in
            let oldState = context.currentState
            context.currentState = state
            let result = self.encode(formula.operand)
            context.currentState = oldState
            return result
        }

        let state = context.currentState

        switch formula.op {
        // Future operators
        case .always:
            return ltlEncoder.always(bodyEncoder, at: state)

        case .eventually:
            return ltlEncoder.eventually(bodyEncoder, at: state)

        case .after:
            return ltlEncoder.after(bodyEncoder, at: state)

        // Past operators
        case .historically:
            return ltlEncoder.historically(bodyEncoder, at: state)

        case .once:
            return ltlEncoder.once(bodyEncoder, at: state)

        case .before:
            return ltlEncoder.before(bodyEncoder, at: state)
        }
    }

    /// Encode a temporal binary formula
    private func encodeTemporalBinaryFormula(_ formula: TemporalBinaryFormula) -> BooleanFormula {
        guard let ltlEncoder = context.ltlEncoder else {
            // No temporal model - encode as conjunction
            return encode(formula.left).and(encode(formula.right))
        }

        let leftEncoder: (Int) -> BooleanFormula = { [self] state in
            let oldState = context.currentState
            context.currentState = state
            let result = self.encode(formula.left)
            context.currentState = oldState
            return result
        }

        let rightEncoder: (Int) -> BooleanFormula = { [self] state in
            let oldState = context.currentState
            context.currentState = state
            let result = self.encode(formula.right)
            context.currentState = oldState
            return result
        }

        let state = context.currentState

        switch formula.op {
        // Future operators
        case .until:
            return ltlEncoder.until(leftEncoder, rightEncoder, at: state)

        case .releases:
            return ltlEncoder.releases(leftEncoder, rightEncoder, at: state)

        case .semicolon:
            // a ; b = a and (after b)
            let aHere = encode(formula.left)
            let bAfter = ltlEncoder.after(rightEncoder, at: state)
            return aHere.and(bAfter)

        // Past operators
        case .since:
            return ltlEncoder.since(leftEncoder, rightEncoder, at: state)

        case .triggered:
            return ltlEncoder.triggered(leftEncoder, rightEncoder, at: state)
        }
    }
}

// MARK: - BooleanValue Extensions

extension BooleanValue {
    /// Check if this is a constant false value
    var isFalse: Bool {
        if case .constant(false) = self {
            return true
        }
        return false
    }
}
