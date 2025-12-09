import Foundation

// MARK: - Conflict Analyzer

/// First-UIP conflict analysis for CDCL
/// Learns clauses from conflicts and determines backtrack level
///
/// Thread Safety: This class is marked @unchecked Sendable but is NOT thread-safe.
/// It must only be accessed from a single thread at a time.
/// External synchronization is required for concurrent access.
public final class ConflictAnalyzer: @unchecked Sendable {
    /// Seen markers for conflict analysis (indexed by variable)
    private var seen: [Bool] = []

    /// Temporary storage for learned clause literals
    private var learntLiterals: [Literal] = []

    /// Number of variables
    private var numVariables: Int = 0

    /// Counter for variables at current decision level
    private var pathCount: Int = 0

    /// Abstract decision level markers for LBD computation
    private var levelMarkers: [UInt64] = []

    public init() {}

    /// Initialize for a given number of variables
    public func initialize(numVariables: Int) {
        self.numVariables = numVariables
        let size = numVariables + 1
        seen = Array(repeating: false, count: size)
        levelMarkers = Array(repeating: 0, count: size)
    }

    // MARK: - First-UIP Analysis

    /// Analyze a conflict and learn a clause
    /// Returns (learned clause, backtrack level) or nil if conflict at level 0
    public func analyzeConflict(
        conflictClause: ClauseRef,
        trail: AssignmentTrail,
        clauseDB: ClauseDatabase,
        heuristic: VSIDSHeuristic
    ) -> (Clause, Int)? {
        guard trail.currentLevel > 0 else {
            return nil  // Conflict at level 0 means UNSAT
        }

        // Reset state
        learntLiterals.removeAll(keepingCapacity: true)
        pathCount = 0

        // Clear all seen markers (in case of stale data from previous analysis)
        for i in 0..<seen.count {
            seen[i] = false
        }

        // Start with conflict clause
        var currentClause = clauseDB[conflictClause]
        var currentLiteral: Literal? = nil
        var trailIndex = trail.assignedCount

        // Process conflict clause
        // All literals in conflict clause are falsified, so we add them to learned clause
        for lit in currentClause.literals {
            let variable = lit.variable
            let level = trail.level(of: variable)

            if level == trail.currentLevel {
                pathCount += 1
                seen[Int(variable.index)] = true
                heuristic.bumpActivity(of: variable)
            } else if level > 0 {
                // Add to learned clause (literal as-is, not negated)
                learntLiterals.append(lit)
                seen[Int(variable.index)] = true
                heuristic.bumpActivity(of: variable)
            }
            // Level 0 literals are always satisfied/falsified, skip them
        }

        // Find first UIP
        while pathCount > 1 {
            // Reset currentLiteral for each iteration to avoid using stale data
            currentLiteral = nil

            // Find next literal on trail at current level that's been seen
            trailIndex -= 1
            while trailIndex >= 0 {
                let assignment = trail.assignment(at: trailIndex)
                if seen[Int(assignment.variable.index)] && trail.level(of: assignment.variable) == trail.currentLevel {
                    currentLiteral = assignment.value ?
                        Literal(variable: assignment.variable, isNegated: false) :
                        Literal(variable: assignment.variable, isNegated: true)
                    break
                }
                trailIndex -= 1
            }

            guard let lit = currentLiteral else { break }

            seen[Int(lit.variable.index)] = false
            pathCount -= 1

            if pathCount == 0 {
                break
            }

            // Get reason clause and resolve
            guard let reasonRef = trail.reason(of: lit.variable) else {
                // This is a decision, shouldn't happen in middle of path
                break
            }

            let reasonClause = clauseDB[reasonRef]

            // Resolve: add antecedent literals
            for reasonLit in reasonClause.literals {
                let variable = reasonLit.variable

                // Skip the pivot literal
                if variable == lit.variable { continue }

                // Skip already seen variables
                if seen[Int(variable.index)] { continue }

                let level = trail.level(of: variable)

                if level == trail.currentLevel {
                    pathCount += 1
                    seen[Int(variable.index)] = true
                    heuristic.bumpActivity(of: variable)
                } else if level > 0 {
                    // Add literal as-is (not negated)
                    learntLiterals.append(reasonLit)
                    seen[Int(variable.index)] = true
                    heuristic.bumpActivity(of: variable)
                }
            }
        }

        // Find the UIP (the single remaining variable at current level)
        trailIndex = trail.assignedCount - 1
        while trailIndex >= 0 {
            let assignment = trail.assignment(at: trailIndex)
            if seen[Int(assignment.variable.index)] && trail.level(of: assignment.variable) == trail.currentLevel {
                // This is the first UIP - add its negation as the asserting literal
                let uipLiteral = assignment.value ?
                    Literal(variable: assignment.variable, isNegated: true) :
                    Literal(variable: assignment.variable, isNegated: false)
                learntLiterals.insert(uipLiteral, at: 0)
                break
            }
            trailIndex -= 1
        }

        // Clear seen markers
        for lit in learntLiterals {
            seen[Int(lit.variable.index)] = false
        }

        // Compute backtrack level (second highest level in learned clause)
        // Position 0 is the UIP (asserting literal), so we find the highest level among positions 1..n
        var backtrackLevel = 0
        if learntLiterals.count > 1 {
            // Find the highest level among all literals except the UIP at position 0
            var maxLevel = 0
            var maxIdx = 1
            for i in 1..<learntLiterals.count {
                let level = trail.level(of: learntLiterals[i].variable)
                if level > maxLevel {
                    maxLevel = level
                    maxIdx = i
                }
            }
            backtrackLevel = maxLevel

            // Swap to position 1 for watched literal setup
            if maxIdx != 1 {
                learntLiterals.swapAt(1, maxIdx)
            }
        }

        // Create learned clause
        var learnedClause = Clause(literals: learntLiterals, isLearned: true)

        // Compute LBD
        learnedClause.computeLBD { variable in
            trail.level(of: variable)
        }

        return (learnedClause, backtrackLevel)
    }

    /// Minimize learned clause by removing redundant literals
    /// Uses self-subsuming resolution
    public func minimizeClause(_ clause: inout Clause, trail: AssignmentTrail, clauseDB: ClauseDatabase) {
        guard clause.size > 1 else { return }

        var minimized: [Literal] = [clause[0]]  // Keep asserting literal

        for i in 1..<clause.size {
            let lit = clause[i]
            if !isRedundant(lit, learntLiterals: clause.literals, trail: trail, clauseDB: clauseDB) {
                minimized.append(lit)
            }
        }

        if minimized.count < clause.literals.count {
            clause = Clause(literals: minimized, isLearned: true)
        }
    }

    /// Check if a literal is redundant (can be removed)
    private func isRedundant(
        _ lit: Literal,
        learntLiterals: [Literal],
        trail: AssignmentTrail,
        clauseDB: ClauseDatabase
    ) -> Bool {
        // A literal is redundant if its reason clause is subsumed by the learned clause
        guard let reasonRef = trail.reason(of: lit.variable) else {
            return false  // Decisions are never redundant
        }

        let reasonClause = clauseDB[reasonRef]

        // Check if all other literals in reason are in learned clause or level 0
        for reasonLit in reasonClause.literals {
            if reasonLit.variable == lit.variable { continue }

            let level = trail.level(of: reasonLit.variable)
            if level == 0 { continue }  // Level 0 literals are always satisfied

            // Check if in learned clause
            if !learntLiterals.contains(where: { $0.variable == reasonLit.variable }) {
                return false
            }
        }

        return true
    }
}

// MARK: - On-the-Fly Self-Subsuming Resolution

extension ConflictAnalyzer {
    /// Perform on-the-fly self-subsuming resolution during conflict analysis
    /// This strengthens the learned clause by removing redundant literals
    public func strengthenLearned(_ clause: inout Clause, with antecedent: Clause) {
        // If learned clause contains ~p and antecedent is (p | q1 | ... | qn)
        // where all qi are in learned clause, we can remove ~p
        // Not implemented for simplicity - basic conflict analysis suffices
    }
}
