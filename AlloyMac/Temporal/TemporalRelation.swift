import Foundation

// MARK: - Temporal Relation

/// A relation that can vary over time (mutable field in Alloy)
/// Represented as a sequence of boolean matrices, one per state
public final class TemporalRelation {
    /// The name of this relation
    public let name: String

    /// The trace this relation is defined over
    public let trace: Trace

    /// The arity of the relation
    public let arity: Int

    /// Boolean matrix for each state
    private var matrices: [BooleanMatrix]

    /// Whether this relation is variable (can change between states)
    public let isVariable: Bool

    /// Create a temporal relation from bounds
    /// - Parameters:
    ///   - name: Relation name
    ///   - bounds: The bounds defining possible values
    ///   - trace: The trace for temporal evolution
    ///   - isVariable: If true, relation can change between states; if false, constant
    public init(name: String, bounds: RelationBounds, trace: Trace, isVariable: Bool) {
        self.name = name
        self.trace = trace
        self.arity = bounds.arity
        self.isVariable = isVariable

        if isVariable {
            // Create separate matrices for each state
            matrices = (0..<trace.length).map { _ in
                BooleanMatrix(bounds: bounds, universe: trace.universe, cnf: trace.cnf)
            }
        } else {
            // Single matrix shared across all states
            let matrix = BooleanMatrix(bounds: bounds, universe: trace.universe, cnf: trace.cnf)
            matrices = [matrix]
        }
    }

    /// Create a constant temporal relation (same value at all states)
    public init(name: String, constant: TupleSet, trace: Trace) {
        self.name = name
        self.trace = trace
        self.arity = constant.arity > 0 ? constant.arity : 1
        self.isVariable = false
        let matrix = BooleanMatrix(constant: constant, universe: trace.universe)
        matrices = [matrix]
    }

    // MARK: - Access

    /// Get the matrix for a given state
    public func matrix(at state: Int) -> BooleanMatrix {
        if isVariable {
            precondition(state >= 0 && state < trace.length, "Invalid state index")
            return matrices[state]
        } else {
            return matrices[0] // Constant - same at all states
        }
    }

    /// Get membership formula for a tuple at a given state
    public func membership(_ tuple: AtomTuple, at state: Int) -> BooleanFormula {
        matrix(at: state).membership(tuple)
    }

    /// Get the "primed" value (value at next state)
    /// For state i, returns value at state i+1 (or loop target if at end)
    public func primed(at state: Int) -> BooleanMatrix {
        if state < trace.length - 1 {
            return matrix(at: state + 1)
        }

        // At final state - primed value depends on loop target
        if !trace.requiresLoop {
            // No loop - return empty matrix (no next state)
            return BooleanMatrix(universe: trace.universe, arity: arity)
        }

        // Build a matrix where each tuple's membership is an ITE over loop targets
        var result = BooleanMatrix(universe: trace.universe, arity: arity)
        let currentMatrix = matrix(at: state)

        for tuple in currentMatrix.tuples {
            // ITE over all possible loop targets
            var formulas: [BooleanFormula] = []
            for loopTarget in 0..<trace.length {
                let loopsHere = trace.loopsTo(loopTarget)
                let valueAtTarget = membership(tuple, at: loopTarget)
                formulas.append(loopsHere.and(valueAtTarget))
            }
            let primedValue = BooleanFormula.disjunction(formulas)

            // Encode the formula and store in result matrix
            let variable = trace.cnf.encode(primedValue)
            result[tuple] = .variable(variable)
        }

        return result
    }

    /// Get membership of primed value: tuple in r' at state
    public func primedMembership(_ tuple: AtomTuple, at state: Int) -> BooleanFormula {
        if state < trace.length - 1 {
            return membership(tuple, at: state + 1)
        }

        // At final state - primed value depends on loop target
        if !trace.requiresLoop {
            return .falseFormula // No next state
        }

        // ITE over all possible loop targets
        var formulas: [BooleanFormula] = []
        for loopTarget in 0..<trace.length {
            let loopsHere = trace.loopsTo(loopTarget)
            let valueAtTarget = membership(tuple, at: loopTarget)
            formulas.append(loopsHere.and(valueAtTarget))
        }
        return .disjunction(formulas)
    }

    // MARK: - Temporal Operations

    /// Assert that the relation value at state equals a specific tuple set
    public func assertEqual(at state: Int, to tuples: TupleSet, cnf: CNFBuilder) {
        let targetMatrix = BooleanMatrix(constant: tuples, universe: trace.universe)
        cnf.assertTrue(matrix(at: state).equals(targetMatrix))
    }

    /// Assert that the relation is empty at a state
    public func assertEmpty(at state: Int, cnf: CNFBuilder) {
        cnf.assertTrue(matrix(at: state).isEmpty())
    }

    /// Assert that the relation is non-empty at a state
    public func assertNonEmpty(at state: Int, cnf: CNFBuilder) {
        cnf.assertTrue(matrix(at: state).isNonEmpty())
    }

    /// Assert that the relation doesn't change between consecutive states
    /// Used for "stutter" steps or immutable portions
    public func assertUnchanged(from state1: Int, to state2: Int, cnf: CNFBuilder) {
        let m1 = matrix(at: state1)
        let m2 = matrix(at: state2)
        cnf.assertTrue(m1.equals(m2))
    }

    // MARK: - Solution Extraction

    /// Extract the relation value at a state from a SAT solution
    public func extractValue(at state: Int, solution: [Bool]) -> TupleSet {
        let m = matrix(at: state)
        var tuples: [AtomTuple] = []

        for (i, tuple) in m.tuples.enumerated() {
            let value = m[i]
            let isTrue: Bool
            switch value {
            case .constant(let b):
                isTrue = b
            case .variable(let v):
                let idx = Int(abs(v))
                let varValue = idx < solution.count ? solution[idx] : false
                isTrue = v > 0 ? varValue : !varValue
            }
            if isTrue {
                tuples.append(tuple)
            }
        }
        return TupleSet(tuples)
    }

    /// Extract values at all states
    public func extractAllValues(solution: [Bool]) -> [TupleSet] {
        (0..<trace.length).map { extractValue(at: $0, solution: solution) }
    }
}

extension TemporalRelation: CustomStringConvertible {
    public var description: String {
        let varStr = isVariable ? "var" : "const"
        return "TemporalRelation(\(name), \(varStr), arity=\(arity), states=\(trace.length))"
    }
}

// MARK: - Temporal Relation Set

/// Collection of temporal relations for a model
public final class TemporalRelationSet {
    /// The trace
    public let trace: Trace

    /// Relations by name
    private var relations: [String: TemporalRelation] = [:]

    public init(trace: Trace) {
        self.trace = trace
    }

    /// Add a variable relation
    public func addVariable(_ name: String, bounds: RelationBounds) {
        relations[name] = TemporalRelation(name: name, bounds: bounds, trace: trace, isVariable: true)
    }

    /// Add a constant relation
    public func addConstant(_ name: String, bounds: RelationBounds) {
        relations[name] = TemporalRelation(name: name, bounds: bounds, trace: trace, isVariable: false)
    }

    /// Add a constant with exact value
    public func addConstant(_ name: String, value: TupleSet) {
        relations[name] = TemporalRelation(name: name, constant: value, trace: trace)
    }

    /// Get relation by name
    public subscript(name: String) -> TemporalRelation? {
        relations[name]
    }

    /// All relation names
    public var names: [String] {
        Array(relations.keys)
    }

    /// Extract all relation values from solution
    public func extractAll(solution: [Bool]) -> [String: [TupleSet]] {
        var result: [String: [TupleSet]] = [:]
        for (name, rel) in relations {
            result[name] = rel.extractAllValues(solution: solution)
        }
        return result
    }
}
