import Foundation

// MARK: - LTL Encoder

/// Encodes Linear Temporal Logic (LTL) formulas for bounded model checking
/// Supports both future-time and past-time operators as in Alloy 6
public final class LTLEncoder {
    /// The trace
    public let trace: Trace

    /// CNF builder
    public var cnf: CNFBuilder { trace.cnf }

    /// The universe
    public var universe: Universe { trace.universe }

    /// Temporal relations
    public let relations: TemporalRelationSet

    /// Cache for auxiliary temporal variables
    private var temporalVarCache: [String: [[Int32]]] = [:]

    /// Create an LTL encoder
    public init(trace: Trace) {
        self.trace = trace
        self.relations = TemporalRelationSet(trace: trace)
    }

    // MARK: - Future-Time Operators

    /// Encode: after F (F holds at the next state)
    /// Also known as X (next) in standard LTL
    public func after(_ formula: @escaping (Int) -> BooleanFormula, at state: Int) -> BooleanFormula {
        if state < trace.length - 1 {
            // Simple case: next state exists
            return formula(state + 1)
        }

        // At final state - next depends on loop target
        if !trace.requiresLoop {
            return .falseFormula // No next state in finite trace
        }

        // after F at final state = OR over loop targets: (loopsTo(i) & F(i))
        var disjuncts: [BooleanFormula] = []
        for i in 0..<trace.length {
            let loopsHere = trace.loopsTo(i)
            let fAtI = formula(i)
            disjuncts.append(loopsHere.and(fAtI))
        }
        return .disjunction(disjuncts)
    }

    /// Encode: always F (F holds at this state and all future states)
    /// Also known as G (globally) in standard LTL
    public func always(_ formula: @escaping (Int) -> BooleanFormula, at state: Int) -> BooleanFormula {
        guard trace.requiresLoop else {
            // Finite trace: F must hold at all states from 'state' onwards
            var conjuncts: [BooleanFormula] = []
            for i in state..<trace.length {
                conjuncts.append(formula(i))
            }
            return .conjunction(conjuncts)
        }

        // Lasso trace: F must hold at all states from 'state' onwards
        // Since trace is infinite via loop, we need F at all states in [state, length-1]
        // AND for each loop target l, if loop goes to l and l <= state, then F at all [l, state-1] too
        // Actually simpler: F must hold at ALL states (since from any state we can reach all states in loop)

        // For bounded model checking with lasso:
        // always F at state s = F holds at all states in [s, length-1]
        //                      AND if loop target < s, then F holds at [loopTarget, s-1] too
        // Simplified: for always, F must hold at all reachable states

        var conjuncts: [BooleanFormula] = []

        // F must hold at states [state, length-1]
        for i in state..<trace.length {
            conjuncts.append(formula(i))
        }

        // If loop goes to a state < state, F must hold there too (already covered if state=0)
        // Actually for "always" starting at state s, if we loop back to l < s,
        // then states [l, s-1] are also in the future, so F must hold there
        for l in 0..<state {
            // If loopsTo(l), then F must hold at states [l, state-1]
            let loopsToL = trace.loopsTo(l)
            for i in l..<state {
                // loopsTo(l) => F(i)
                conjuncts.append(loopsToL.implies(formula(i)))
            }
        }

        return .conjunction(conjuncts)
    }

    /// Encode: eventually F (F holds at this state or some future state)
    /// Also known as F (finally) in standard LTL
    public func eventually(_ formula: @escaping (Int) -> BooleanFormula, at state: Int) -> BooleanFormula {
        guard trace.requiresLoop else {
            // Finite trace: F must hold at some state from 'state' onwards
            var disjuncts: [BooleanFormula] = []
            for i in state..<trace.length {
                disjuncts.append(formula(i))
            }
            return .disjunction(disjuncts)
        }

        // Lasso trace: F holds somewhere in the future
        // The future from state s includes:
        // 1. States [s, length-1]
        // 2. If loop target l <= s, then the loop portion [l, s-1] is NOT in the future
        // 3. If loop target l > s, then states [loopTarget, length-1] ARE in the future (already covered in step 1)
        // Corrected semantics: The future is [state, length-1] AND if loop goes to l < state,
        // then [l, state-1] are NOT reachable in the future from state s
        var disjuncts: [BooleanFormula] = []

        // F at some state in [state, length-1]
        for i in state..<trace.length {
            disjuncts.append(formula(i))
        }

        // For loop-back: if we loop to l and l < state, then states [l, state-1] are also in the future
        // This is correct: after reaching the end, we loop back to l, and from l we can reach [l, state-1]
        for l in 0..<state {
            let loopsToL = trace.loopsTo(l)
            for i in l..<state {
                disjuncts.append(loopsToL.and(formula(i)))
            }
        }

        return .disjunction(disjuncts)
    }

    /// Encode: F until G (F holds until G becomes true, and G eventually holds)
    /// Standard LTL U operator
    public func until(
        _ f: @escaping (Int) -> BooleanFormula,
        _ g: @escaping (Int) -> BooleanFormula,
        at state: Int
    ) -> BooleanFormula {
        // F U G at state s = exists j >= s: G(j) AND forall i in [s, j): F(i)

        var disjuncts: [BooleanFormula] = []

        // For each possible position j where G first holds
        for j in state..<trace.length {
            var conjuncts: [BooleanFormula] = []
            conjuncts.append(g(j)) // G holds at j

            // F holds at all states before j
            for i in state..<j {
                conjuncts.append(f(i))
            }

            disjuncts.append(.conjunction(conjuncts))
        }

        // For lasso: G could also hold at a state in the loop
        if trace.requiresLoop {
            for l in 0..<state {
                // If we loop to l, G could hold at some j in [l, state)
                for j in l..<state {
                    var conjuncts: [BooleanFormula] = []
                    conjuncts.append(trace.loopsTo(l))
                    conjuncts.append(g(j))

                    // F must hold at [state, length-1] and [l, j)
                    for i in state..<trace.length {
                        conjuncts.append(f(i))
                    }
                    for i in l..<j {
                        conjuncts.append(f(i))
                    }

                    disjuncts.append(.conjunction(conjuncts))
                }
            }
        }

        return .disjunction(disjuncts)
    }

    /// Encode: F releases G (G holds until and including when F first holds, or G holds forever)
    /// Standard LTL R operator (dual of until)
    public func releases(
        _ f: @escaping (Int) -> BooleanFormula,
        _ g: @escaping (Int) -> BooleanFormula,
        at state: Int
    ) -> BooleanFormula {
        // F R G = ~(~F U ~G)
        // G holds at all states until and including when F holds (or forever if F never holds)

        // Option 1: G holds forever (always G)
        let gForever = always(g, at: state)

        // Option 2: F holds at some point j, and G holds at all points up to and including j
        var disjuncts: [BooleanFormula] = [gForever]

        for j in state..<trace.length {
            var conjuncts: [BooleanFormula] = []
            conjuncts.append(f(j)) // F holds at j

            // G holds at all states from state to j (inclusive)
            for i in state...j {
                conjuncts.append(g(i))
            }

            disjuncts.append(.conjunction(conjuncts))
        }

        // Handle lasso for F occurring in loop portion
        if trace.requiresLoop {
            for l in 0..<state {
                for j in l..<state {
                    var conjuncts: [BooleanFormula] = []
                    conjuncts.append(trace.loopsTo(l))
                    conjuncts.append(f(j))

                    // G holds at [state, length-1] and [l, j]
                    for i in state..<trace.length {
                        conjuncts.append(g(i))
                    }
                    for i in l...j {
                        conjuncts.append(g(i))
                    }

                    disjuncts.append(.conjunction(conjuncts))
                }
            }
        }

        return .disjunction(disjuncts)
    }

    // MARK: - Past-Time Operators

    /// Encode: before F (F held at the previous state)
    /// Also known as Y (yesterday) in past LTL
    public func before(_ formula: @escaping (Int) -> BooleanFormula, at state: Int) -> BooleanFormula {
        if state == 0 {
            return .falseFormula // No previous state at initial state
        }
        return formula(state - 1)
    }

    /// Encode: historically F (F has held at all past states including this one)
    /// Also known as H in past LTL
    public func historically(_ formula: @escaping (Int) -> BooleanFormula, at state: Int) -> BooleanFormula {
        var conjuncts: [BooleanFormula] = []
        for i in 0...state {
            conjuncts.append(formula(i))
        }
        return .conjunction(conjuncts)
    }

    /// Encode: once F (F held at some past state or this state)
    /// Also known as O in past LTL
    public func once(_ formula: @escaping (Int) -> BooleanFormula, at state: Int) -> BooleanFormula {
        var disjuncts: [BooleanFormula] = []
        for i in 0...state {
            disjuncts.append(formula(i))
        }
        return .disjunction(disjuncts)
    }

    /// Encode: F since G (G held at some past state, and F has held since then)
    /// Standard past LTL S operator
    public func since(
        _ f: @escaping (Int) -> BooleanFormula,
        _ g: @escaping (Int) -> BooleanFormula,
        at state: Int
    ) -> BooleanFormula {
        // F S G at state s = exists j <= s: G(j) AND forall i in (j, s]: F(i)

        var disjuncts: [BooleanFormula] = []

        for j in 0...state {
            var conjuncts: [BooleanFormula] = []
            conjuncts.append(g(j)) // G held at j

            // F held at all states after j up to and including state
            if j < state {
                for i in (j+1)...state {
                    conjuncts.append(f(i))
                }
            }
            // If j == state, no F constraints needed (G just happened)

            disjuncts.append(.conjunction(conjuncts))
        }

        return .disjunction(disjuncts)
    }

    /// Encode: F triggered G (G held since F first held, or G has always held)
    /// Past LTL T operator (dual of since)
    public func triggered(
        _ f: @escaping (Int) -> BooleanFormula,
        _ g: @escaping (Int) -> BooleanFormula,
        at state: Int
    ) -> BooleanFormula {
        // F T G = ~(~F S ~G)

        // Option 1: G has always held (historically G)
        let gAlways = historically(g, at: state)

        // Option 2: F held at some j, and G held from j to state
        var disjuncts: [BooleanFormula] = [gAlways]

        for j in 0...state {
            var conjuncts: [BooleanFormula] = []
            conjuncts.append(f(j))

            for i in j...state {
                conjuncts.append(g(i))
            }

            disjuncts.append(.conjunction(conjuncts))
        }

        return .disjunction(disjuncts)
    }

    // MARK: - Primed Expressions

    /// Get the primed (next state) value of a relation membership
    public func primed(_ relation: TemporalRelation, tuple: AtomTuple, at state: Int) -> BooleanFormula {
        relation.primedMembership(tuple, at: state)
    }

    // MARK: - Assertion Helpers

    /// Assert a formula at the initial state
    public func assertInitially(_ formula: BooleanFormula) {
        cnf.assertTrue(formula)
    }

    /// Assert a formula holds at all states (invariant)
    public func assertInvariant(_ formula: @escaping (Int) -> BooleanFormula) {
        for i in 0..<trace.length {
            cnf.assertTrue(formula(i))
        }
    }

    /// Assert a transition constraint (holds for all consecutive state pairs)
    public func assertTransition(_ formula: @escaping (Int, Int) -> BooleanFormula) {
        for i in 0..<(trace.length - 1) {
            cnf.assertTrue(formula(i, i + 1))
        }

        // Handle transition from last state via loop-back
        if trace.requiresLoop {
            for l in 0..<trace.length {
                let loopsToL = trace.loopsTo(l)
                let transitionFormula = formula(trace.length - 1, l)
                // loopsTo(l) => transition(length-1, l)
                cnf.assertTrue(loopsToL.implies(transitionFormula))
            }
        }
    }

    /// Assert an LTL property at the initial state
    public func assertProperty(_ property: BooleanFormula) {
        cnf.assertTrue(property)
    }
}

// MARK: - Temporal Instance

/// Result of temporal model checking - a trace with concrete values
public struct TemporalInstance {
    /// The universe
    public let universe: Universe

    /// Trace length
    public let length: Int

    /// Loop-back state (nil if finite trace)
    public let loopState: Int?

    /// Relation values at each state
    public let relations: [String: [TupleSet]]

    /// Get relation value at a state
    public func value(of relation: String, at state: Int) -> TupleSet? {
        guard let values = relations[relation], state < values.count else {
            return nil
        }
        return values[state]
    }

    /// Check if this is a lasso trace
    public var isLasso: Bool {
        loopState != nil
    }
}

extension TemporalInstance: CustomStringConvertible {
    public var description: String {
        var result = "TemporalInstance {\n"
        result += "  length: \(length)\n"
        if let loop = loopState {
            result += "  loop: -> state \(loop)\n"
        }
        for (name, values) in relations.sorted(by: { $0.key < $1.key }) {
            result += "  \(name):\n"
            for (i, value) in values.enumerated() {
                let loopMarker = (loopState == i) ? " <-loop" : ""
                result += "    [\(i)] \(value)\(loopMarker)\n"
            }
        }
        result += "}"
        return result
    }
}
