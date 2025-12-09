import Foundation

// MARK: - Boolean Matrix

/// A matrix of boolean values representing a relation
/// Each cell corresponds to a tuple and contains either:
/// - A constant (true/false) for fixed tuples
/// - A SAT variable for free tuples
public struct BooleanMatrix: Sendable {
    /// The universe this matrix is defined over
    public let universe: Universe

    /// Arity of the relation
    public let arity: Int

    /// All possible tuples (in order)
    public let tuples: [AtomTuple]

    /// Map from tuple to index
    private let tupleIndex: [AtomTuple: Int]

    /// The boolean value for each tuple
    private var values: [BooleanValue]

    /// Create an empty matrix (all cells false)
    public init(universe: Universe, arity: Int) {
        self.universe = universe
        self.arity = arity
        self.tuples = universe.allTuples(arity: arity)

        var tupleIndex: [AtomTuple: Int] = [:]
        for (i, tuple) in tuples.enumerated() {
            tupleIndex[tuple] = i
        }
        self.tupleIndex = tupleIndex

        self.values = Array(repeating: .falseValue, count: tuples.count)
    }

    /// Create from bounds, assigning SAT variables to free tuples
    public init(bounds: RelationBounds, universe: Universe, cnf: CNFBuilder) {
        self.universe = universe
        self.arity = bounds.arity
        self.tuples = universe.allTuples(arity: bounds.arity)

        var tupleIndex: [AtomTuple: Int] = [:]
        for (i, tuple) in tuples.enumerated() {
            tupleIndex[tuple] = i
        }
        self.tupleIndex = tupleIndex

        var values: [BooleanValue] = []
        for tuple in tuples {
            if bounds.lower.contains(tuple) {
                // Must be in relation
                values.append(.trueValue)
            } else if bounds.upper.contains(tuple) {
                // May be in relation - create variable
                values.append(.variable(cnf.freshVariable()))
            } else {
                // Cannot be in relation
                values.append(.falseValue)
            }
        }
        self.values = values
    }

    /// Create a constant matrix from a tuple set
    public init(constant: TupleSet, universe: Universe) {
        self.universe = universe
        self.arity = constant.arity > 0 ? constant.arity : 1
        self.tuples = universe.allTuples(arity: arity)

        var tupleIndex: [AtomTuple: Int] = [:]
        for (i, tuple) in tuples.enumerated() {
            tupleIndex[tuple] = i
        }
        self.tupleIndex = tupleIndex

        var values: [BooleanValue] = []
        for tuple in tuples {
            values.append(constant.contains(tuple) ? .trueValue : .falseValue)
        }
        self.values = values
    }

    // MARK: - Access

    /// Get the index for a tuple
    public func index(of tuple: AtomTuple) -> Int? {
        tupleIndex[tuple]
    }

    /// Get boolean value for a tuple
    public subscript(tuple: AtomTuple) -> BooleanValue {
        get {
            guard let idx = tupleIndex[tuple] else { return .falseValue }
            return values[idx]
        }
        set {
            guard let idx = tupleIndex[tuple] else { return }
            values[idx] = newValue
        }
    }

    /// Get boolean value at index
    public subscript(index: Int) -> BooleanValue {
        get { values[index] }
        set { values[index] = newValue }
    }

    /// Number of tuples
    public var count: Int { tuples.count }

    /// Whether this matrix is a constant (no variables)
    public var isConstant: Bool {
        values.allSatisfy(\.isConstant)
    }

    /// Get all SAT variables used in this matrix
    public var variables: [Int32] {
        values.compactMap(\.variableIndex)
    }

    // MARK: - Formula Building

    /// Create formula asserting tuple membership
    public func membership(_ tuple: AtomTuple) -> BooleanFormula {
        .from(self[tuple])
    }

    /// Create formula asserting tuple is NOT in relation
    public func nonMembership(_ tuple: AtomTuple) -> BooleanFormula {
        membership(tuple).negated
    }

    /// Formula: this matrix is empty
    public func isEmpty() -> BooleanFormula {
        .conjunction(values.map { BooleanFormula.from($0).negated })
    }

    /// Formula: this matrix has at least one tuple
    public func isNonEmpty() -> BooleanFormula {
        .disjunction(values.map { BooleanFormula.from($0) })
    }

    /// Formula: this matrix has exactly one tuple
    public func hasExactlyOne() -> BooleanFormula {
        // At least one AND at most one
        var formulas: [BooleanFormula] = []

        // At least one
        formulas.append(isNonEmpty())

        // At most one: for each pair (i, j), not both
        for i in 0..<values.count {
            for j in (i+1)..<values.count {
                let vi = BooleanFormula.from(values[i])
                let vj = BooleanFormula.from(values[j])
                formulas.append(.disjunction([vi.negated, vj.negated]))
            }
        }

        return .conjunction(formulas)
    }

    /// Formula: this matrix is a subset of other
    public func isSubset(of other: BooleanMatrix) -> BooleanFormula {
        precondition(arity == other.arity && universe.size == other.universe.size,
                    "Matrices must have same shape")

        var formulas: [BooleanFormula] = []
        for (i, tuple) in tuples.enumerated() {
            // self[tuple] => other[tuple]
            let selfVal = BooleanFormula.from(values[i])
            let otherVal = BooleanFormula.from(other[tuple])
            formulas.append(selfVal.implies(otherVal))
        }
        return .conjunction(formulas)
    }

    /// Formula: this matrix equals other
    public func equals(_ other: BooleanMatrix) -> BooleanFormula {
        precondition(arity == other.arity && universe.size == other.universe.size,
                    "Matrices must have same shape")

        var formulas: [BooleanFormula] = []
        for (i, tuple) in tuples.enumerated() {
            let selfVal = BooleanFormula.from(values[i])
            let otherVal = BooleanFormula.from(other[tuple])
            formulas.append(selfVal.iff(otherVal))
        }
        return .conjunction(formulas)
    }

    // MARK: - Relational Operations (produce new matrices)

    /// Union: result[t] <=> self[t] | other[t]
    public func union(_ other: BooleanMatrix, cnf: CNFBuilder) -> BooleanMatrix {
        precondition(arity == other.arity, "Arity mismatch")

        var result = BooleanMatrix(universe: universe, arity: arity)
        for (i, tuple) in tuples.enumerated() {
            let a = values[i]
            let b = other[tuple]

            switch (a, b) {
            case (.constant(true), _), (_, .constant(true)):
                result[i] = .trueValue
            case (.constant(false), let x), (let x, .constant(false)):
                result[i] = x
            default:
                // Need a new variable for a | b
                let v = cnf.freshVariable()
                result[i] = .variable(v)
                // v <=> a | b
                let formula = BooleanFormula.from(a).or(.from(b))
                cnf.assertTrue(BooleanFormula.variable(v).iff(formula))
            }
        }
        return result
    }

    /// Intersection: result[t] <=> self[t] & other[t]
    public func intersection(_ other: BooleanMatrix, cnf: CNFBuilder) -> BooleanMatrix {
        precondition(arity == other.arity, "Arity mismatch")

        var result = BooleanMatrix(universe: universe, arity: arity)
        for (i, tuple) in tuples.enumerated() {
            let a = values[i]
            let b = other[tuple]

            switch (a, b) {
            case (.constant(false), _), (_, .constant(false)):
                result[i] = .falseValue
            case (.constant(true), let x), (let x, .constant(true)):
                result[i] = x
            default:
                // Need a new variable for a & b
                let v = cnf.freshVariable()
                result[i] = .variable(v)
                let formula = BooleanFormula.from(a).and(.from(b))
                cnf.assertTrue(BooleanFormula.variable(v).iff(formula))
            }
        }
        return result
    }

    /// Difference: result[t] <=> self[t] & ~other[t]
    public func difference(_ other: BooleanMatrix, cnf: CNFBuilder) -> BooleanMatrix {
        precondition(arity == other.arity, "Arity mismatch")

        var result = BooleanMatrix(universe: universe, arity: arity)
        for (i, tuple) in tuples.enumerated() {
            let a = values[i]
            let b = other[tuple]

            switch (a, b) {
            case (.constant(false), _):
                result[i] = .falseValue
            case (_, .constant(true)):
                result[i] = .falseValue
            case (let x, .constant(false)):
                result[i] = x
            case (.constant(true), .variable(let v)):
                result[i] = .variable(-v)
            default:
                let v = cnf.freshVariable()
                result[i] = .variable(v)
                let formula = BooleanFormula.from(a).and(.from(b).negated)
                cnf.assertTrue(BooleanFormula.variable(v).iff(formula))
            }
        }
        return result
    }

    /// Transpose (for binary relations)
    public func transpose() -> BooleanMatrix {
        precondition(arity == 2, "Transpose requires binary relation")

        var result = BooleanMatrix(universe: universe, arity: 2)
        for tuple in tuples {
            let transposed = tuple.transposed()
            result[transposed] = self[tuple]
        }
        return result
    }

    /// Relational join: self . other
    public func join(_ other: BooleanMatrix, cnf: CNFBuilder) -> BooleanMatrix {
        let resultArity = arity + other.arity - 2
        guard resultArity >= 1 else {
            // Join of unary relations - result is scalar (empty matrix indicates exists)
            return BooleanMatrix(universe: universe, arity: 1)
        }

        // Check for potential memory exhaustion before computing
        let estimatedTupleCount = Int(pow(Double(universe.size), Double(resultArity)))
        guard estimatedTupleCount <= AlloyConstants.maxJoinTuples else {
            // Return empty matrix to prevent memory exhaustion
            // This is a conservative safe behavior - the caller should use bounded scopes
            return BooleanMatrix(universe: universe, arity: resultArity)
        }

        var result = BooleanMatrix(universe: universe, arity: resultArity)
        let resultTuples = universe.allTuples(arity: resultArity)

        for resultTuple in resultTuples {
            // result[a1,...,an-1,b2,...,bm] = OR over c: self[a1,...,an-1,c] & other[c,b2,...,bm]
            var disjuncts: [BooleanFormula] = []

            for c in universe.atoms {
                // Build the tuple for self: (a1,...,an-1,c)
                var selfAtoms = Array(resultTuple.atoms.prefix(arity - 1))
                selfAtoms.append(c)
                let selfTuple = AtomTuple(selfAtoms)

                // Build the tuple for other: (c,b2,...,bm)
                var otherAtoms = [c]
                otherAtoms.append(contentsOf: resultTuple.atoms.suffix(other.arity - 1))
                let otherTuple = AtomTuple(otherAtoms)

                let selfVal = self[selfTuple]
                let otherVal = other[otherTuple]

                // Optimize constants
                if case .constant(false) = selfVal { continue }
                if case .constant(false) = otherVal { continue }

                if case .constant(true) = selfVal, case .constant(true) = otherVal {
                    // This disjunct is always true
                    result[resultTuple] = .trueValue
                    break
                }

                disjuncts.append(BooleanFormula.from(selfVal).and(.from(otherVal)))
            }

            if case .trueValue = result[resultTuple] { continue }

            if disjuncts.isEmpty {
                result[resultTuple] = .falseValue
            } else if disjuncts.count == 1, case .variable(let v) = disjuncts[0] {
                result[resultTuple] = .variable(v)
            } else {
                let v = cnf.freshVariable()
                result[resultTuple] = .variable(v)
                let formula = BooleanFormula.disjunction(disjuncts)
                cnf.assertTrue(BooleanFormula.variable(v).iff(formula))
            }
        }

        return result
    }

    /// Cartesian product: self -> other
    public func product(_ other: BooleanMatrix, cnf: CNFBuilder) -> BooleanMatrix {
        let resultArity = arity + other.arity
        var result = BooleanMatrix(universe: universe, arity: resultArity)

        for selfTuple in tuples {
            let selfVal = self[selfTuple]
            if case .constant(false) = selfVal { continue }

            for otherTuple in other.tuples {
                let otherVal = other[otherTuple]
                if case .constant(false) = otherVal { continue }

                let resultTuple = selfTuple.product(with: otherTuple)

                switch (selfVal, otherVal) {
                case (.constant(true), .constant(true)):
                    result[resultTuple] = .trueValue
                case (.constant(true), let x), (let x, .constant(true)):
                    result[resultTuple] = x
                default:
                    let v = cnf.freshVariable()
                    result[resultTuple] = .variable(v)
                    let formula = BooleanFormula.from(selfVal).and(.from(otherVal))
                    cnf.assertTrue(BooleanFormula.variable(v).iff(formula))
                }
            }
        }

        return result
    }

    /// Transitive closure (binary relations only)
    public func transitiveClosure(cnf: CNFBuilder) -> BooleanMatrix {
        precondition(arity == 2, "Transitive closure requires binary relation")

        // Use iterative squaring: r+ = r ∪ r² ∪ r³ ∪ ...
        // By computing result = result ∪ result.result, we get:
        //   Iter 0: r (paths of length 1)
        //   Iter 1: r ∪ r² (paths of length 1-2)
        //   Iter 2: r ∪ r² ∪ r³ ∪ r⁴ (paths of length 1-4)
        //   After log(n) iterations: all paths up to length n
        var result = self

        // log2(universe.size) iterations suffice
        let iterations = Int(ceil(log2(Double(max(1, universe.size)))))

        for _ in 0..<iterations {
            result = result.union(result.join(result, cnf: cnf), cnf: cnf)
        }

        return result
    }

    /// Reflexive transitive closure
    public func reflexiveTransitiveClosure(cnf: CNFBuilder) -> BooleanMatrix {
        let identity = BooleanMatrix(constant: TupleSet(universe.identity()), universe: universe)
        return transitiveClosure(cnf: cnf).union(identity, cnf: cnf)
    }
}

extension BooleanMatrix: CustomStringConvertible {
    public var description: String {
        var result = "Matrix(\(arity)):\n"
        for (i, tuple) in tuples.enumerated() {
            result += "  \(tuple): \(values[i])\n"
        }
        return result
    }
}
