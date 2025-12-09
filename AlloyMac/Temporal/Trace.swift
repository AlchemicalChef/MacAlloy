import Foundation

// MARK: - Trace

/// A finite trace represents a sequence of states for bounded model checking
/// The trace may form a lasso: states 0, 1, ..., k-1, then loop back to state l (l <= k-1)
/// This allows finite representation of infinite behaviors
public final class Trace {
    /// The universe for this trace
    public let universe: Universe

    /// Number of states in the trace (trace length)
    public let length: Int

    /// The loop-back state index (nil if no loop, meaning finite trace)
    /// If set to l, then state (length-1) transitions back to state l
    public private(set) var loopStart: Int?

    /// CNF builder for generating SAT clauses
    public let cnf: CNFBuilder

    /// Loop-back variables: loopVar[i] is true iff the trace loops back to state i
    /// Only one can be true (or none if finite trace)
    private var loopVars: [Int32] = []

    /// Whether loop-back is required (infinite trace semantics)
    public let requiresLoop: Bool

    /// Create a trace with the given parameters
    /// - Parameters:
    ///   - universe: The universe of atoms
    ///   - length: Number of states (must be >= 1)
    ///   - cnf: CNF builder for generating clauses
    ///   - requiresLoop: If true, trace must loop back (for LTL on infinite traces)
    public init(universe: Universe, length: Int, cnf: CNFBuilder, requiresLoop: Bool = true) {
        precondition(length >= 1, "Trace must have at least one state")
        self.universe = universe
        self.length = length
        self.cnf = cnf
        self.requiresLoop = requiresLoop

        // Create loop-back variables if required
        if requiresLoop {
            setupLoopVariables()
        }
    }

    // MARK: - Loop-back Setup

    /// Create SAT variables for loop-back selection
    private func setupLoopVariables() {
        // loopVar[i] = true means trace loops from state (length-1) back to state i
        for _ in 0..<length {
            loopVars.append(cnf.freshVariable())
        }

        // Exactly one loop variable must be true
        assertExactlyOneLoop()
    }

    /// Assert that exactly one loop variable is true
    private func assertExactlyOneLoop() {
        guard !loopVars.isEmpty else { return }

        // At least one
        cnf.addClause(loopVars)

        // At most one (pairwise exclusion)
        for i in 0..<loopVars.count {
            for j in (i+1)..<loopVars.count {
                cnf.addClause([-loopVars[i], -loopVars[j]])
            }
        }
    }

    /// Get the loop variable for state i
    /// Returns the SAT variable that is true iff trace loops back to state i
    public func loopVariable(to state: Int) -> Int32? {
        guard state >= 0 && state < loopVars.count else { return nil }
        return loopVars[state]
    }

    /// Get boolean formula for "trace loops back to state i"
    public func loopsTo(_ state: Int) -> BooleanFormula {
        guard let v = loopVariable(to: state) else {
            return .falseFormula
        }
        return .variable(v)
    }

    // MARK: - State Access

    /// Check if a state index is valid
    public func isValidState(_ state: Int) -> Bool {
        state >= 0 && state < length
    }

    /// Get the successor state index
    /// For the last state, this depends on the loop-back
    /// Returns nil if at last state with no loop (finite trace)
    /// For lasso traces at last state, returns loopStart if known, otherwise nil
    /// (the actual loop target is a SAT variable - use loopVariable() for encoding)
    public func successor(of state: Int) -> Int? {
        guard isValidState(state) else { return nil }
        if state < length - 1 {
            return state + 1
        }
        // At last state - successor depends on loop
        if requiresLoop {
            // Return loop start if known (set after SAT solving)
            // During encoding, caller should use loopVariable() to handle all possible targets
            return loopStart
        }
        return nil  // Finite trace has no successor at last state
    }

    /// Set the loop start after extracting from SAT solution
    public func setLoopStart(_ state: Int) {
        guard isValidState(state) else { return }
        loopStart = state
    }

    /// Get the predecessor state index
    public func predecessor(of state: Int) -> Int? {
        guard isValidState(state) && state > 0 else { return nil }
        return state - 1
    }

    // MARK: - Temporal Iteration

    /// Iterate over all states
    public func forEachState(_ body: (Int) -> Void) {
        for i in 0..<length {
            body(i)
        }
    }

    /// Iterate over pairs of consecutive states (for transition constraints)
    public func forEachTransition(_ body: (Int, Int) -> Void) {
        for i in 0..<(length - 1) {
            body(i, i + 1)
        }
        // Last state's successor handled specially via loop-back
    }

    /// Get all states that could be "in the future" from a given state
    /// For lasso traces, this includes states reachable via the loop
    public func futureStates(from state: Int) -> [Int] {
        guard isValidState(state) else { return [] }
        // All states from 'state' onwards
        return Array(state..<length)
    }

    /// Get all states that could be "in the past" from a given state
    public func pastStates(from state: Int) -> [Int] {
        guard isValidState(state) else { return [] }
        return Array(0...state)
    }

    // MARK: - Solution Extraction

    /// Extract the loop-back state from a SAT solution
    public func extractLoopState(from solution: [Bool]) -> Int? {
        for (i, loopVar) in loopVars.enumerated() {
            let idx = Int(loopVar)
            if idx < solution.count && solution[idx] {
                return i
            }
        }
        return nil
    }
}

extension Trace: CustomStringConvertible {
    public var description: String {
        if requiresLoop {
            return "Trace(length: \(length), lasso)"
        } else {
            return "Trace(length: \(length), finite)"
        }
    }
}

// MARK: - Trace State

/// Represents a single state in a trace
/// Used for organizing per-state relation values
public struct TraceState {
    /// The state index (0-based)
    public let index: Int

    /// The trace this state belongs to
    public weak var trace: Trace?

    /// Whether this is the initial state
    public var isInitial: Bool { index == 0 }

    /// Whether this is the final state (before potential loop-back)
    public var isFinal: Bool { index == (trace?.length ?? 1) - 1 }

    public init(index: Int, trace: Trace) {
        self.index = index
        self.trace = trace
    }
}
