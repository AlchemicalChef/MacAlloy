import Foundation

// MARK: - Translation Context

/// Context for translating Alloy to SAT
/// Tracks all state needed during translation including universe, bounds, and encodings
public final class TranslationContext {
    /// The universe of atoms
    public let universe: Universe

    /// The bounds for all relations
    public let bounds: Bounds

    /// CNF builder for generating SAT clauses
    public let cnf: CNFBuilder

    /// The symbol table from semantic analysis
    public let symbolTable: SymbolTable

    /// Boolean matrices for each signature (set of atoms)
    public private(set) var sigMatrices: [String: BooleanMatrix] = [:]

    /// Boolean matrices for each field (relation)
    public private(set) var fieldMatrices: [String: BooleanMatrix] = [:]

    /// Atoms allocated to each signature
    public private(set) var sigAtoms: [String: [Atom]] = [:]

    /// Current variable bindings (for quantifiers and let)
    private var bindings: [[String: BooleanMatrix]] = [[:]]

    // MARK: - Integer Support

    /// Bit width for bounded integers (default 4 bits = -8 to 7)
    public let integerBitWidth: Int

    /// Factory for integer atoms (nil if integers not used)
    public private(set) var integerFactory: IntegerAtomFactory?

    /// Integer arithmetic operations
    public private(set) var integerArithmetic: IntegerArithmetic?

    /// Trace for temporal models (nil for non-temporal)
    public private(set) var trace: Trace?

    /// Temporal relations for variable fields
    public private(set) var temporalRelations: [String: TemporalRelation] = [:]

    /// The LTL encoder for temporal formulas
    public private(set) var ltlEncoder: LTLEncoder?

    /// Current state index for temporal evaluation (0 if non-temporal)
    public var currentState: Int = 0

    /// Whether this is a temporal model
    public var isTemporal: Bool { trace != nil }

    /// The signature whose fact is being evaluated (nil if not in a sig fact)
    /// When set, field names are auto-expanded to this.field per Alloy spec
    public var currentSigFact: SigSymbol? = nil

    // MARK: - Initialization

    /// Create a translation context from scopes
    public init(symbolTable: SymbolTable, scope: CommandScope?, integerBitWidth: Int = AlloyConstants.defaultIntegerBitWidth) {
        self.symbolTable = symbolTable
        self.cnf = CNFBuilder()
        self.integerBitWidth = integerBitWidth

        // Determine universe size and allocate atoms
        let (universe, sigAtoms, intFactory) = Self.createUniverse(
            symbolTable: symbolTable,
            defaultScope: scope?.defaultScope ?? AlloyConstants.defaultScope,
            typeScopes: scope?.typeScopes ?? [],
            integerBitWidth: integerBitWidth
        )
        self.universe = universe
        self.sigAtoms = sigAtoms
        self.integerFactory = intFactory

        // Create integer arithmetic if integers are used
        if intFactory != nil {
            self.integerArithmetic = IntegerArithmetic(cnf: cnf, bitWidth: integerBitWidth)
        }

        // Create bounds
        self.bounds = Self.createBounds(
            symbolTable: symbolTable,
            universe: universe,
            sigAtoms: sigAtoms
        )

        // Initialize matrices for signatures
        for (sigName, atoms) in sigAtoms {
            let tupleSet = TupleSet(atoms: atoms)
            sigMatrices[sigName] = BooleanMatrix(constant: tupleSet, universe: universe)
        }

        // Check if temporal model needed
        let needsTemporal = Self.checkTemporal(symbolTable: symbolTable)
        let traceLength = scope?.steps ?? (needsTemporal ? AlloyConstants.defaultTraceLength : 1)

        if needsTemporal {
            // Create trace and temporal relations
            let trace = Trace(universe: universe, length: traceLength, cnf: cnf, requiresLoop: true)
            self.trace = trace
            self.ltlEncoder = LTLEncoder(trace: trace)

            // Create temporal relations for variable fields
            for sig in symbolTable.signatures.values {
                for field in sig.fields {
                    if field.isVariable {
                        let fieldBounds = bounds[field.name]
                        // Create default empty bounds if not found
                        let defaultBounds = RelationBounds(name: field.name, upper: TupleSet(arity: 2))
                        let tempRel = TemporalRelation(
                            name: field.name,
                            bounds: fieldBounds ?? defaultBounds,
                            trace: trace,
                            isVariable: true
                        )
                        temporalRelations[field.name] = tempRel
                    }
                }
            }
        }

        // Initialize field matrices
        for relationBounds in bounds.allBounds {
            if temporalRelations[relationBounds.name] == nil {
                let matrix = BooleanMatrix(bounds: relationBounds, universe: universe, cnf: cnf)
                fieldMatrices[relationBounds.name] = matrix
            }
        }
    }

    // MARK: - Universe Creation

    /// Create universe and allocate atoms to signatures
    private static func createUniverse(
        symbolTable: SymbolTable,
        defaultScope: Int,
        typeScopes: [TypeScope],
        integerBitWidth: Int
    ) -> (Universe, [String: [Atom]], IntegerAtomFactory?) {
        var sigAtoms: [String: [Atom]] = [:]
        var allAtomNames: [String] = []

        // Build type scope map
        var scopeMap: [String: (Int, Bool)] = [:] // name -> (count, isExact)
        for ts in typeScopes {
            scopeMap[ts.typeName.simpleName] = (ts.count, ts.isExactly)
        }

        // Process signatures in topological order (parents first)
        let sortedSigs = topologicalSort(signatures: Array(symbolTable.signatures.values))

        for sig in sortedSigs {
            let sigName = sig.name

            // Skip abstract signatures with children
            if sig.sigType.isAbstract && !sig.children.isEmpty {
                // Abstract sig is the union of its children
                sigAtoms[sigName] = []
                continue
            }

            // Determine scope for this signature
            let (scope, isExact) = scopeMap[sigName] ?? (defaultScope, false)

            // Check multiplicity constraints
            var atomCount = scope
            if let mult = sig.sigType.multiplicity {
                switch mult {
                case .one:
                    atomCount = 1
                case .lone:
                    atomCount = min(1, scope)
                case .some:
                    atomCount = max(1, scope)
                default:
                    break
                }
            }

            // For exact scopes, use exact count
            if isExact {
                atomCount = scope
            }

            // Create atoms for this signature
            var atoms: [Atom] = []
            for i in 0..<atomCount {
                let atomName = "\(sigName)$\(i)"
                atoms.append(Atom(index: allAtomNames.count, name: atomName))
                allAtomNames.append(atomName)
            }
            sigAtoms[sigName] = atoms
        }

        // Now fix up abstract signatures to include child atoms
        for sig in sortedSigs {
            if sig.sigType.isAbstract && !sig.children.isEmpty {
                var childAtoms: [Atom] = []
                for child in sig.descendants {
                    childAtoms.append(contentsOf: sigAtoms[child.name] ?? [])
                }
                sigAtoms[sig.name] = childAtoms
            }
        }

        // Also fix up parent signatures to include all descendant atoms
        for sig in sortedSigs.reversed() {
            if let parent = sig.parent {
                var parentAtoms = sigAtoms[parent.name] ?? []
                parentAtoms.append(contentsOf: sigAtoms[sig.name] ?? [])
                sigAtoms[parent.name] = Array(Set(parentAtoms)).sorted { $0.index < $1.index }
            }
        }

        // Handle enum signatures
        for enumSym in symbolTable.enums.values {
            var atoms: [Atom] = []
            for value in enumSym.values {
                let atomName = value.name
                atoms.append(Atom(index: allAtomNames.count, name: atomName))
                allAtomNames.append(atomName)
            }
            sigAtoms[enumSym.name] = atoms
        }

        // Check if model uses integers and add integer atoms if needed
        var integerFactory: IntegerAtomFactory? = nil
        let usesIntegers = checkUsesIntegers(symbolTable: symbolTable)

        if usesIntegers {
            let startingIndex = allAtomNames.count
            let factory = IntegerAtomFactory(bitWidth: integerBitWidth, startingIndex: startingIndex)
            integerFactory = factory
            allAtomNames.append(contentsOf: factory.atomNames)

            // Add Int signature to sigAtoms
            sigAtoms["Int"] = factory.atoms
        }

        let universe = Universe(atomNames: allAtomNames)
        return (universe, sigAtoms, integerFactory)
    }

    /// Check if the model uses integers
    private static func checkUsesIntegers(symbolTable: SymbolTable) -> Bool {
        // Check for Int fields
        for sig in symbolTable.signatures.values {
            for field in sig.fields {
                if field.type.description.contains("Int") {
                    return true
                }
            }
        }

        // For now, always include integers to support cardinality operations
        // This could be optimized by checking if any cardinality, sum, or int expressions are used
        return true
    }

    /// Topological sort of signatures (parents before children)
    private static func topologicalSort(signatures: [SigSymbol]) -> [SigSymbol] {
        var result: [SigSymbol] = []
        var visited: Set<String> = []

        func visit(_ sig: SigSymbol) {
            guard !visited.contains(sig.name) else { return }
            visited.insert(sig.name)

            // Visit parent first
            if let parent = sig.parent {
                visit(parent)
            }

            result.append(sig)
        }

        for sig in signatures {
            visit(sig)
        }

        return result
    }

    // MARK: - Bounds Creation

    /// Create bounds for all relations
    private static func createBounds(
        symbolTable: SymbolTable,
        universe: Universe,
        sigAtoms: [String: [Atom]]
    ) -> Bounds {
        let bounds = Bounds(universe: universe)

        // Create bounds for each field
        for sig in symbolTable.signatures.values {
            let ownerAtoms = sigAtoms[sig.name] ?? []

            for field in sig.fields {
                // Determine target atoms based on field type
                let targetAtoms = determineTargetAtoms(
                    type: field.type,
                    sigAtoms: sigAtoms,
                    universe: universe
                )

                // Upper bound: all possible (owner, target) pairs
                var upperTuples: [AtomTuple] = []
                for owner in ownerAtoms {
                    for target in targetAtoms {
                        upperTuples.append(AtomTuple([owner, target]))
                    }
                }

                bounds.bound(field.name, upper: TupleSet(upperTuples))
            }
        }

        return bounds
    }

    /// Determine target atoms for a field type
    private static func determineTargetAtoms(
        type: AlloyType,
        sigAtoms: [String: [Atom]],
        universe: Universe
    ) -> [Atom] {
        if let sigType = type as? SigType {
            return sigAtoms[sigType.name] ?? universe.atoms
        } else if type is RelationType {
            // For higher-arity relations, use all atoms
            return universe.atoms
        }
        return universe.atoms
    }

    /// Check if model requires temporal logic
    private static func checkTemporal(symbolTable: SymbolTable) -> Bool {
        // Check for variable signatures
        for sig in symbolTable.signatures.values {
            if sig.sigType.isVariable {
                return true
            }
            for field in sig.fields {
                if field.isVariable {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Binding Management

    /// Push a new binding scope
    public func pushScope() {
        bindings.append([:])
    }

    /// Pop the current binding scope
    public func popScope() {
        guard bindings.count > 1 else { return }
        bindings.removeLast()
    }

    /// Bind a variable name to a matrix
    public func bind(_ name: String, to matrix: BooleanMatrix) {
        bindings[bindings.count - 1][name] = matrix
    }

    /// Look up a bound variable
    public func lookupBinding(_ name: String) -> BooleanMatrix? {
        for scope in bindings.reversed() {
            if let matrix = scope[name] {
                return matrix
            }
        }
        return nil
    }

    // MARK: - Relation Access

    /// Get the matrix for a signature
    public func sigMatrix(_ name: String) -> BooleanMatrix? {
        sigMatrices[name]
    }

    /// Get the matrix for a field at the current state
    public func fieldMatrix(_ name: String) -> BooleanMatrix? {
        if let tempRel = temporalRelations[name] {
            return tempRel.matrix(at: currentState)
        }
        return fieldMatrices[name]
    }

    /// Get the primed (next state) matrix for a field
    public func primedFieldMatrix(_ name: String) -> BooleanMatrix? {
        if let tempRel = temporalRelations[name], let trace = trace {
            if currentState < trace.length - 1 {
                return tempRel.matrix(at: currentState + 1)
            }
        }
        return nil
    }

    /// Get identity relation
    public func identityMatrix() -> BooleanMatrix {
        BooleanMatrix(constant: TupleSet(universe.identity()), universe: universe)
    }

    /// Get universal relation (all tuples)
    public func universalMatrix(arity: Int) -> BooleanMatrix {
        BooleanMatrix(constant: TupleSet(universe.allTuples(arity: arity)), universe: universe)
    }

    /// Get empty relation
    public func emptyMatrix(arity: Int) -> BooleanMatrix {
        BooleanMatrix(universe: universe, arity: arity)
    }

    /// Get constant matrix for a single atom
    public func atomMatrix(_ atom: Atom) -> BooleanMatrix {
        BooleanMatrix(constant: TupleSet(atoms: [atom]), universe: universe)
    }

    // MARK: - Temporal Helpers

    /// Execute a block at each state
    public func forEachState(_ body: (Int) throws -> Void) rethrows {
        guard let trace = trace else {
            try body(0)
            return
        }

        for state in 0..<trace.length {
            currentState = state
            try body(state)
        }
        currentState = 0
    }

    // MARK: - Integer Helpers

    /// Get the atom for an integer value
    public func integerAtom(_ value: Int) -> Atom? {
        integerFactory?.atom(for: value)
    }

    /// Get the integer value for an atom
    public func integerValue(_ atom: Atom) -> Int? {
        integerFactory?.value(for: atom)
    }

    /// Get matrix for a single integer constant
    public func integerMatrix(_ value: Int) -> BooleanMatrix? {
        guard let atom = integerAtom(value) else { return nil }
        return atomMatrix(atom)
    }

    /// Get the Int signature matrix
    public func intSigMatrix() -> BooleanMatrix? {
        sigMatrices["Int"]
    }
}
