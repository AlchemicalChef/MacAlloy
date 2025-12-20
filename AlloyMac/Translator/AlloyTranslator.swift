import Foundation

// MARK: - Alloy Translator

/// Main translator from Alloy AST to SAT
/// Orchestrates the translation process and provides high-level API
public final class AlloyTranslator {
    /// The translation context
    public let context: TranslationContext

    /// The expression encoder
    public let exprEncoder: ExpressionEncoder

    /// The formula encoder
    public let formulaEncoder: FormulaEncoder

    /// The symbol table
    public var symbolTable: SymbolTable { context.symbolTable }

    /// CNF builder shorthand
    public var cnf: CNFBuilder { context.cnf }

    // MARK: - Initialization

    /// Create a translator for a module with given scope
    public init(symbolTable: SymbolTable, scope: CommandScope? = nil) {
        let integerBitWidth = scope?.intScope?.bitwidth ?? AlloyConstants.defaultIntegerBitWidth
        self.context = TranslationContext(symbolTable: symbolTable, scope: scope, integerBitWidth: integerBitWidth)
        self.exprEncoder = ExpressionEncoder(context: context)
        self.formulaEncoder = FormulaEncoder(context: context, exprEncoder: exprEncoder)
    }

    // MARK: - Translation

    /// Translate all facts and constraints to SAT clauses
    public func translateFacts() {
        // Encode signature constraints
        encodeSignatureConstraints()

        // Encode facts
        for fact in symbolTable.facts {
            if let body = fact.body {
                encodeFact(body)
            }
        }

        // Encode signature facts
        for sig in symbolTable.signatures.values {
            if let sigFact = sig.sigFact {
                encodeSignatureFact(sig, fact: sigFact)
            }
        }
    }

    /// Translate a run command
    public func translateRun(_ cmd: RunCmdNode) {
        // First translate facts
        translateFacts()

        // Then encode the command body or target predicate
        if let body = cmd.body {
            context.forEachState { _ in
                let formula = formulaEncoder.encode(body)
                cnf.assertTrue(formula)
            }
        } else if let targetName = cmd.targetName {
            // Look up and call the predicate
            if let pred = symbolTable.lookupPred(targetName.simpleName) {
                if let body = pred.body {
                    context.forEachState { _ in
                        let formula = formulaEncoder.encode(body)
                        cnf.assertTrue(formula)
                    }
                }
            }
        }
    }

    /// Translate a check command
    public func translateCheck(_ cmd: CheckCmdNode) {
        // First translate facts
        translateFacts()

        // Then encode the negation of the assertion
        if let body = cmd.body {
            // Check: find counterexample where body is false
            context.forEachState { _ in
                let formula = formulaEncoder.encode(body)
                cnf.assertTrue(formula.negated)
            }
        } else if let targetName = cmd.targetName {
            // Look up and negate the assertion
            if let assertion = symbolTable.lookupAssert(targetName.simpleName) {
                if let body = assertion.body {
                    context.forEachState { _ in
                        let formula = formulaEncoder.encode(body)
                        cnf.assertTrue(formula.negated)
                    }
                }
            }
        }
    }

    // MARK: - Signature Constraints

    /// Encode all signature constraints
    private func encodeSignatureConstraints() {
        // Encode multiplicity constraints
        for sig in symbolTable.signatures.values {
            encodeMultiplicityConstraint(sig)
        }

        // Encode hierarchy constraints (disjoint children, etc.)
        for sig in symbolTable.signatures.values {
            encodeHierarchyConstraints(sig)
        }

        // Encode field constraints
        for sig in symbolTable.signatures.values {
            for field in sig.fields {
                encodeFieldConstraints(field, owner: sig)
            }
        }
    }

    /// Encode multiplicity constraint for a signature
    private func encodeMultiplicityConstraint(_ sig: SigSymbol) {
        guard let mult = sig.sigType.multiplicity else { return }
        guard let sigMatrix = context.sigMatrix(sig.name) else { return }

        switch mult {
        case .one:
            // Exactly one atom in this signature
            cnf.assertTrue(sigMatrix.hasExactlyOne())

        case .lone:
            // At most one atom
            encodeAtMostOne(sigMatrix)

        case .some:
            // At least one atom
            cnf.assertTrue(sigMatrix.isNonEmpty())

        case .set, .seq:
            // No constraint (zero or more)
            break
        }
    }

    /// Encode at-most-one constraint for a matrix
    private func encodeAtMostOne(_ matrix: BooleanMatrix) {
        var constraints: [BooleanFormula] = []
        for i in 0..<matrix.count {
            for j in (i+1)..<matrix.count {
                let vi = BooleanFormula.from(matrix[i])
                let vj = BooleanFormula.from(matrix[j])
                constraints.append(.disjunction([vi.negated, vj.negated]))
            }
        }
        cnf.assertTrue(.conjunction(constraints))
    }

    /// Encode hierarchy constraints for a signature
    private func encodeHierarchyConstraints(_ sig: SigSymbol) {
        // Children of an abstract sig are disjoint
        if sig.sigType.isAbstract && sig.children.count > 1 {
            for i in 0..<sig.children.count {
                for j in (i+1)..<sig.children.count {
                    let childI = sig.children[i]
                    let childJ = sig.children[j]

                    guard let matrixI = context.sigMatrix(childI.name),
                          let matrixJ = context.sigMatrix(childJ.name) else { continue }

                    // Disjoint: no atom can be in both
                    for tuple in matrixI.tuples {
                        let inI = BooleanFormula.from(matrixI[tuple])
                        let inJ = BooleanFormula.from(matrixJ[tuple])
                        cnf.assertTrue(.disjunction([inI.negated, inJ.negated]))
                    }
                }
            }
        }

        // Abstract sig with children must be covered by children
        if sig.sigType.isAbstract && !sig.children.isEmpty {
            guard let sigMatrix = context.sigMatrix(sig.name) else { return }

            for tuple in sigMatrix.tuples {
                let inSig = BooleanFormula.from(sigMatrix[tuple])

                // If in sig, must be in some child
                var childFormulas: [BooleanFormula] = []
                for child in sig.children {
                    if let childMatrix = context.sigMatrix(child.name) {
                        childFormulas.append(BooleanFormula.from(childMatrix[tuple]))
                    }
                }

                if !childFormulas.isEmpty {
                    cnf.assertTrue(inSig.implies(.disjunction(childFormulas)))
                }
            }
        }
    }

    /// Encode field constraints
    private func encodeFieldConstraints(_ field: FieldSymbol, owner: SigSymbol) {
        // Field domain must be subset of owner signature
        guard let fieldMatrix = context.fieldMatrix(field.name),
              let ownerMatrix = context.sigMatrix(owner.name) else { return }

        // For each tuple (a, b, ...) in field, a must be in owner
        for tuple in fieldMatrix.tuples {
            let inField = BooleanFormula.from(fieldMatrix[tuple])
            let ownerAtom = AtomTuple(tuple.first)
            let inOwner = BooleanFormula.from(ownerMatrix[ownerAtom])

            // field(a, ...) => owner(a)
            cnf.assertTrue(inField.implies(inOwner))
        }

        // Handle disjointness if specified
        if field.isDisjoint {
            encodeDisjointField(field, owner: owner)
        }
    }

    /// Encode disjoint field constraint
    private func encodeDisjointField(_ field: FieldSymbol, owner: SigSymbol) {
        guard let fieldMatrix = context.fieldMatrix(field.name) else { return }

        // For disjoint fields: different owner atoms map to different targets
        // For all a1 != a2: field[a1] & field[a2] = empty

        guard let ownerAtoms = context.sigAtoms[owner.name] else { return }

        for i in 0..<ownerAtoms.count {
            for j in (i+1)..<ownerAtoms.count {
                let a1 = ownerAtoms[i]
                let a2 = ownerAtoms[j]

                // For all targets t: not (field(a1, t) & field(a2, t))
                for atom in context.universe.atoms {
                    let tuple1 = AtomTuple([a1, atom])
                    let tuple2 = AtomTuple([a2, atom])

                    let in1 = BooleanFormula.from(fieldMatrix[tuple1])
                    let in2 = BooleanFormula.from(fieldMatrix[tuple2])

                    cnf.assertTrue(.disjunction([in1.negated, in2.negated]))
                }
            }
        }
    }

    // MARK: - Fact Encoding

    /// Encode a fact body
    private func encodeFact(_ body: any FormulaNode) {
        context.forEachState { _ in
            let formula = formulaEncoder.encode(body)
            cnf.assertTrue(formula)
        }
    }

    /// Encode a signature fact
    /// Per Alloy spec: sig fact { F } becomes `always all this: S | F'`
    /// where field references f are expanded to this.f (unless prefixed with @)
    private func encodeSignatureFact(_ sig: SigSymbol, fact: any FormulaNode) {
        guard let sigAtoms = context.sigAtoms[sig.name] else { return }

        context.forEachState { _ in
            // The sig fact holds for all atoms in the signature
            for atom in sigAtoms {
                context.pushScope()
                context.bind("this", to: context.atomMatrix(atom))

                // Set context for field expansion per Alloy spec
                context.currentSigFact = sig

                // Handle BlockFormula specially for better encoding
                if let block = fact as? BlockFormula {
                    for formula in block.formulas {
                        let encoded = formulaEncoder.encode(formula)
                        cnf.assertTrue(encoded)
                    }
                } else {
                    let encoded = formulaEncoder.encode(fact)
                    cnf.assertTrue(encoded)
                }

                // Clear context
                context.currentSigFact = nil
                context.popScope()
            }
        }
    }

    // MARK: - Solution Extraction

    /// Extract an instance from a SAT solution
    public func extractInstance(solution: [Bool]) -> AlloyInstance {
        InstanceExtractor.extract(context: context, solution: solution)
    }

    // MARK: - SAT Interface

    /// Get the number of SAT variables
    public var variableCount: Int { Int(cnf.variableCount) }

    /// Get the number of clauses
    public var clauseCount: Int { cnf.allClauses.count }

    /// Get clauses as integer arrays
    public var clauses: [[Int32]] { cnf.allClauses }

    /// Get DIMACS format string
    public var dimacs: String { cnf.toDIMACS() }
}

// MARK: - Command Helpers

public extension AlloyTranslator {
    /// Translate and check a predicate by name
    func translatePredicate(_ name: String) {
        translateFacts()

        if let pred = symbolTable.lookupPred(name), let body = pred.body {
            context.forEachState { _ in
                let formula = formulaEncoder.encode(body)
                cnf.assertTrue(formula)
            }
        }
    }

    /// Translate and check an assertion by name (for finding counterexample)
    func translateAssertion(_ name: String) {
        translateFacts()

        if let assertion = symbolTable.lookupAssert(name), let body = assertion.body {
            // Negate to find counterexample
            context.forEachState { _ in
                let formula = formulaEncoder.encode(body)
                cnf.assertTrue(formula.negated)
            }
        }
    }

    /// Translate with an arbitrary formula
    func translateFormula(_ formula: any FormulaNode) {
        translateFacts()

        context.forEachState { _ in
            let encoded = formulaEncoder.encode(formula)
            cnf.assertTrue(encoded)
        }
    }
}
