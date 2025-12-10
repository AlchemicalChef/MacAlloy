import Foundation

// MARK: - CDCL SAT Solver

/// Conflict-Driven Clause Learning SAT Solver
/// Implements modern SAT solving with:
/// - Two-watched literal scheme for efficient unit propagation
/// - VSIDS decision heuristic with activity decay
/// - First-UIP conflict analysis with learned clause minimization
/// - Non-chronological backtracking
/// - Luby restarts
///
/// Thread Safety: This class is marked @unchecked Sendable but is NOT thread-safe.
/// It must only be accessed from a single thread at a time.
/// External synchronization is required for concurrent access.
public final class CDCLSolver: @unchecked Sendable {
    /// Clause database
    private var clauseDB: ClauseDatabase

    /// Assignment trail
    private var trail: AssignmentTrail

    /// VSIDS heuristic
    private var heuristic: VSIDSHeuristic

    /// Conflict analyzer
    private var conflictAnalyzer: ConflictAnalyzer

    /// Restart sequence
    private var restartSequence: LubySequence

    /// Number of variables
    private var numVariables: Int = 0

    /// Solving statistics
    public private(set) var stats: SolverStats

    /// Conflict limit for restarts
    private var conflictsUntilRestart: Int = 0

    /// Learned clause limit for database reduction
    private var maxLearnedClauses: Int = 2000

    /// Learned clause increment
    private var learnedClauseInc: Int = 500

    /// Whether solver is cancelled
    private var cancelled: Bool = false

    /// Progress callback
    public var onProgress: ((SolverStats) -> Void)?

    public init() {
        self.clauseDB = ClauseDatabase()
        self.trail = AssignmentTrail()
        self.heuristic = VSIDSHeuristic()
        self.conflictAnalyzer = ConflictAnalyzer()
        self.restartSequence = LubySequence(baseInterval: 100)
        self.stats = SolverStats()
    }

    /// Cancel the solver
    public func cancel() {
        cancelled = true
    }

    // MARK: - Main Solve Interface

    /// Solve a CNF formula
    /// - Parameters:
    ///   - numVariables: Number of variables in the formula
    ///   - clauses: List of clauses, each clause is a list of literals (positive = var, negative = -var)
    /// - Returns: Solver result (SAT with model, UNSAT, or UNKNOWN if cancelled)
    public func solve(numVariables: Int, clauses: [[Int]]) -> SolverResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        cancelled = false
        stats = SolverStats()

        // Initialize data structures
        self.numVariables = numVariables
        clauseDB.initialize(numVariables: numVariables)
        trail.initialize(numVariables: numVariables)
        heuristic.initialize(numVariables: numVariables)
        conflictAnalyzer.initialize(numVariables: numVariables)
        restartSequence.reset()

        conflictsUntilRestart = restartSequence.next()
        maxLearnedClauses = 2000

        // Add clauses
        var unitClauses: [Literal] = []

        for clauseLiterals in clauses {
            if clauseLiterals.isEmpty {
                // Empty clause means UNSAT
                stats.solveTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return .unsatisfiable
            }

            let literals = clauseLiterals.map { intLit -> Literal in
                if intLit > 0 {
                    return Literal.pos(Int32(intLit))
                } else {
                    return Literal.neg(Int32(-intLit))
                }
            }

            if literals.count == 1 {
                unitClauses.append(literals[0])
            } else {
                let clause = Clause(literals: literals, isLearned: false)
                clauseDB.addOriginal(clause)
            }
        }

        // Process initial unit clauses
        // Add them to the clause database first to get valid ClauseRefs
        for unitLit in unitClauses {
            let varValue = trail.value(of: unitLit)
            if varValue == .undefined {
                // Create a unit clause and add it to the database for a valid ClauseRef
                let unitClause = Clause(literals: [unitLit], isLearned: false)
                let unitRef = clauseDB.addOriginal(unitClause)
                trail.propagate(unitLit, reason: unitRef)
            } else if !trail.isSatisfied(unitLit) {
                // Conflict with unit clause - literal is falsified
                stats.solveTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                return .unsatisfiable
            }
        }

        // Initial propagation
        if let conflict = propagate() {
            _ = conflict
            stats.solveTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return .unsatisfiable
        }

        // Main CDCL loop
        let result = cdclLoop()

        stats.solveTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return result
    }

    // MARK: - CDCL Loop

    private func cdclLoop() -> SolverResult {
        while !cancelled {
            // Propagate
            if let conflictRef = propagate() {
                stats.conflicts += 1

                // Conflict at level 0 means UNSAT
                if trail.currentLevel == 0 {
                    return .unsatisfiable
                }

                // Analyze conflict
                guard let (learnedClause, btLevel) = conflictAnalyzer.analyzeConflict(
                    conflictClause: conflictRef,
                    trail: trail,
                    clauseDB: clauseDB,
                    heuristic: heuristic
                ) else {
                    return .unsatisfiable
                }

                // Backtrack
                backtrack(to: btLevel)

                // Add learned clause
                let learnedRef = clauseDB.addLearned(learnedClause)
                stats.learnedClauses += 1

                // The asserting literal becomes unit (propagate with valid ClauseRef)
                trail.propagate(learnedClause.first, reason: learnedRef)

                // Decay activities
                heuristic.decayActivities()

                // Check restart
                conflictsUntilRestart -= 1
                if conflictsUntilRestart <= 0 {
                    restart()
                }

                // Check clause database reduction
                if clauseDB.learnedCount > maxLearnedClauses {
                    reduceDB()
                }

            } else {
                // No conflict - check if complete
                if trail.isComplete {
                    return .satisfiable(trail.model())
                }

                // Make a decision
                guard let decisionLit = heuristic.pickBranchVariable(trail: trail) else {
                    // All variables assigned but not complete?
                    // This shouldn't happen
                    return .satisfiable(trail.model())
                }

                stats.decisions += 1
                trail.decide(decisionLit)
            }

            // Progress callback
            if stats.conflicts % 1000 == 0 {
                onProgress?(stats)
            }
        }

        return .unknown
    }

    // MARK: - Unit Propagation

    /// Propagate unit clauses using two-watched literal scheme
    /// Returns conflicting clause reference or nil if no conflict
    private func propagate() -> ClauseRef? {
        while let propagatedLit = trail.nextPropagation() {
            stats.propagations += 1

            // Get clauses watching the negation of the propagated literal
            let falsifiedLit = propagatedLit.negated
            let watchers = clauseDB.watchers(of: falsifiedLit)
            var keepWatchers: [ClauseRef] = []
            var conflict: ClauseRef? = nil
            var watcherIndex = 0

            while watcherIndex < watchers.count {
                let clauseRef = watchers[watcherIndex]
                watcherIndex += 1

                var clause = clauseDB[clauseRef]

                // Skip empty clauses (deleted)
                if clause.isEmpty { continue }

                // Ensure falsified literal is in position 1
                if clause.first == falsifiedLit {
                    clause.swap(0, 1)
                    clauseDB[clauseRef] = clause
                }

                // If first literal is already true, clause is satisfied
                if trail.isSatisfied(clause.first) {
                    keepWatchers.append(clauseRef)
                    continue
                }

                // Look for new watch
                var foundWatch = false
                for i in 2..<clause.size {
                    if !trail.isFalsified(clause[i]) {
                        // Found new watch - swap to position 1
                        clause.swap(1, i)
                        clauseDB[clauseRef] = clause

                        // Move watch from falsifiedLit to clause[1]
                        clauseDB.moveWatch(clause: clauseRef, from: falsifiedLit, to: clause[1])
                        foundWatch = true
                        break
                    }
                }

                if foundWatch { continue }

                // No new watch found - this is unit or conflict
                keepWatchers.append(clauseRef)

                if trail.isFalsified(clause.first) {
                    // Conflict! All literals falsified
                    // Add remaining watchers before updating
                    while watcherIndex < watchers.count {
                        keepWatchers.append(watchers[watcherIndex])
                        watcherIndex += 1
                    }
                    conflict = clauseRef
                    break
                } else {
                    // Unit clause - propagate first literal
                    trail.propagate(clause.first, reason: clauseRef)
                }
            }

            // Update watch list
            clauseDB.updateWatches(for: falsifiedLit, keeping: keepWatchers)

            if let conflictRef = conflict {
                return conflictRef
            }
        }

        return nil
    }

    // MARK: - Backtracking

    private func backtrack(to level: Int) {
        // Save phases and re-insert variables into heap
        for i in stride(from: trail.assignedCount - 1, through: 0, by: -1) {
            let assignment = trail.assignment(at: i)
            if trail.level(of: assignment.variable) <= level {
                break
            }
            // Save phase
            heuristic.savePhase(of: assignment.variable, value: assignment.value)
            // Re-insert into heap
            heuristic.insertVariable(assignment.variable)
        }

        trail.backtrack(to: level)
    }

    // MARK: - Restart

    private func restart() {
        stats.restarts += 1
        backtrack(to: 0)
        conflictsUntilRestart = restartSequence.next()
    }

    // MARK: - Database Reduction

    private func reduceDB() {
        let deleted = clauseDB.reduceDB(keepRatio: 0.5)
        stats.deletedClauses += deleted
        maxLearnedClauses += learnedClauseInc
    }
}

// MARK: - DIMACS Parser

extension CDCLSolver {
    /// Parse DIMACS CNF format
    /// Returns (numVariables, clauses) or nil if invalid
    public static func parseDIMACS(_ input: String) -> (Int, [[Int]])? {
        var numVariables = 0
        var numClauses = 0
        var clauses: [[Int]] = []
        var currentClause: [Int] = []

        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("c") {
                continue
            }

            // Problem line
            if trimmed.hasPrefix("p") {
                let parts = trimmed.split(separator: " ")
                guard parts.count >= 4,
                      parts[1] == "cnf",
                      let vars = Int(parts[2]),
                      let cls = Int(parts[3]) else {
                    return nil
                }
                numVariables = vars
                numClauses = cls
                continue
            }

            // Clause line
            let literals = trimmed.split(separator: " ").compactMap { Int($0) }
            for lit in literals {
                if lit == 0 {
                    // End of clause
                    if !currentClause.isEmpty {
                        clauses.append(currentClause)
                        currentClause = []
                    }
                } else {
                    currentClause.append(lit)
                }
            }
        }

        // Handle clause without trailing 0
        if !currentClause.isEmpty {
            clauses.append(currentClause)
        }

        return (numVariables, clauses)
    }

    /// Solve from DIMACS string
    public func solveDIMACS(_ input: String) -> SolverResult {
        guard let (numVars, clauses) = CDCLSolver.parseDIMACS(input) else {
            return .unknown
        }
        return solve(numVariables: numVars, clauses: clauses)
    }
}

// MARK: - Convenience Methods

extension CDCLSolver {
    /// Create a simple CNF and solve
    /// Each inner array is a clause, each Int is a literal (positive = true, negative = false)
    public static func isSatisfiable(variables: Int, clauses: [[Int]]) -> Bool {
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: variables, clauses: clauses)
        switch result {
        case .satisfiable: return true
        case .unsatisfiable: return false
        case .unknown: return false
        }
    }
}
