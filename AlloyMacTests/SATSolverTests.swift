import XCTest
@testable import AlloyMac

final class SATSolverTests: XCTestCase {

    // MARK: - Literal Tests

    func testLiteralCreation() {
        let v1 = Variable(1)
        let posLit = Literal(variable: v1)
        let negLit = Literal(variable: v1, isNegated: true)

        XCTAssertEqual(posLit.variable, v1)
        XCTAssertTrue(posLit.isPositive)
        XCTAssertFalse(posLit.isNegated)

        XCTAssertEqual(negLit.variable, v1)
        XCTAssertFalse(negLit.isPositive)
        XCTAssertTrue(negLit.isNegated)
    }

    func testLiteralNegation() {
        let lit = Literal.pos(5)
        let negated = lit.negated

        XCTAssertEqual(lit.variableIndex, negated.variableIndex)
        XCTAssertNotEqual(lit.isNegated, negated.isNegated)
        XCTAssertEqual(lit, negated.negated)
    }

    func testLiftedBool() {
        XCTAssertEqual(LiftedBool.true.negated, .false)
        XCTAssertEqual(LiftedBool.false.negated, .true)
        XCTAssertEqual(LiftedBool.undefined.negated, .undefined)

        XCTAssertTrue(LiftedBool.true.isDefined)
        XCTAssertTrue(LiftedBool.false.isDefined)
        XCTAssertFalse(LiftedBool.undefined.isDefined)
    }

    // MARK: - Assignment Trail Tests

    func testAssignmentTrailBasics() {
        let trail = AssignmentTrail()
        trail.initialize(numVariables: 5)

        let lit1 = Literal.pos(1)
        trail.decide(lit1)

        XCTAssertEqual(trail.currentLevel, 1)
        XCTAssertEqual(trail.assignedCount, 1)
        XCTAssertTrue(trail.isAssigned(Variable(1)))
        XCTAssertTrue(trail.isSatisfied(lit1))
        XCTAssertTrue(trail.isFalsified(lit1.negated))
    }

    func testAssignmentTrailPropagation() {
        let trail = AssignmentTrail()
        trail.initialize(numVariables: 5)

        let lit1 = Literal.pos(1)
        trail.decide(lit1)

        let lit2 = Literal.neg(2)
        let reason = ClauseRef(0)
        trail.propagate(lit2, reason: reason)

        XCTAssertEqual(trail.assignedCount, 2)
        XCTAssertEqual(trail.level(of: Variable(2)), 1)
        XCTAssertEqual(trail.reason(of: Variable(2)), reason)
        XCTAssertTrue(trail.isDecision(Variable(1)))
        XCTAssertFalse(trail.isDecision(Variable(2)))
    }

    func testAssignmentTrailBacktracking() {
        let trail = AssignmentTrail()
        trail.initialize(numVariables: 5)

        // Level 1
        trail.decide(Literal.pos(1))
        trail.propagate(Literal.pos(2), reason: ClauseRef(0))

        // Level 2
        trail.decide(Literal.pos(3))
        trail.propagate(Literal.pos(4), reason: ClauseRef(1))

        XCTAssertEqual(trail.currentLevel, 2)
        XCTAssertEqual(trail.assignedCount, 4)

        // Backtrack to level 1
        trail.backtrack(to: 1)

        XCTAssertEqual(trail.currentLevel, 1)
        XCTAssertEqual(trail.assignedCount, 2)
        XCTAssertTrue(trail.isAssigned(Variable(1)))
        XCTAssertTrue(trail.isAssigned(Variable(2)))
        XCTAssertFalse(trail.isAssigned(Variable(3)))
        XCTAssertFalse(trail.isAssigned(Variable(4)))
    }

    // MARK: - Clause Tests

    func testClauseCreation() {
        let lits = [Literal.pos(1), Literal.neg(2), Literal.pos(3)]
        let clause = Clause(literals: lits)

        XCTAssertEqual(clause.size, 3)
        XCTAssertFalse(clause.isUnit)
        XCTAssertFalse(clause.isBinary)
        XCTAssertFalse(clause.isEmpty)
    }

    func testClauseDatabase() {
        let db = ClauseDatabase()
        db.initialize(numVariables: 5)

        let clause1 = Clause(literals: [Literal.pos(1), Literal.neg(2)])
        let clause2 = Clause(literals: [Literal.pos(2), Literal.pos(3)])

        let ref1 = db.addOriginal(clause1)
        let ref2 = db.addOriginal(clause2)

        XCTAssertEqual(db.count, 2)
        XCTAssertEqual(db[ref1].size, 2)
        XCTAssertEqual(db[ref2].size, 2)

        // Check watches
        let watchers1 = db.watchers(of: Literal.pos(1))
        let watchers2 = db.watchers(of: Literal.neg(2))

        XCTAssertTrue(watchers1.contains(ref1))
        XCTAssertTrue(watchers2.contains(ref1))
    }

    // MARK: - VSIDS Tests

    func testVSIDSHeuristic() {
        let vsids = VSIDSHeuristic()
        vsids.initialize(numVariables: 5)

        let trail = AssignmentTrail()
        trail.initialize(numVariables: 5)

        // Initial pick should work
        let firstPick = vsids.pickBranchVariable(trail: trail)
        XCTAssertNotNil(firstPick)

        // Bump activity
        vsids.bumpActivity(of: Variable(3))
        vsids.bumpActivity(of: Variable(3))

        // Variable 3 should be picked (highest activity)
        let pick = vsids.pickBranchVariable(trail: trail)
        XCTAssertEqual(pick?.variableIndex, 3)
    }

    // MARK: - Luby Sequence Tests

    func testLubySequence() {
        var luby = LubySequence(baseInterval: 1)

        // Luby sequence: 1, 1, 2, 1, 1, 2, 4, 1, 1, 2, 1, 1, 2, 4, 8, ...
        let expected = [1, 1, 2, 1, 1, 2, 4, 1, 1, 2, 1, 1, 2, 4, 8]
        for e in expected {
            XCTAssertEqual(luby.next(), e)
        }
    }

    // MARK: - Simple SAT Tests

    func testEmptyCNF() {
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 0, clauses: [])
        if case .satisfiable = result {
            // Empty CNF is satisfiable
        } else {
            XCTFail("Empty CNF should be satisfiable")
        }
    }

    func testEmptyClause() {
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 1, clauses: [[]])
        XCTAssertEqual(result.description, "UNSAT")
    }

    func testSinglePositiveLiteral() {
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 1, clauses: [[1]])
        if case .satisfiable(let model) = result {
            XCTAssertTrue(model[1])
        } else {
            XCTFail("Should be satisfiable")
        }
    }

    func testSingleNegativeLiteral() {
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 1, clauses: [[-1]])
        if case .satisfiable(let model) = result {
            XCTAssertFalse(model[1])
        } else {
            XCTFail("Should be satisfiable")
        }
    }

    func testContradictoryUnitClauses() {
        let solver = CDCLSolver()
        // x1 AND NOT x1
        let result = solver.solve(numVariables: 1, clauses: [[1], [-1]])
        XCTAssertEqual(result.description, "UNSAT")
    }

    func testSimpleSAT() {
        let solver = CDCLSolver()
        // (x1 OR x2) AND (NOT x1 OR x2)
        let result = solver.solve(numVariables: 2, clauses: [[1, 2], [-1, 2]])
        if case .satisfiable(let model) = result {
            // x2 must be true
            XCTAssertTrue(model[2])
        } else {
            XCTFail("Should be satisfiable")
        }
    }

    func testSimpleUNSAT() {
        let solver = CDCLSolver()
        // (x1) AND (x2) AND (NOT x1 OR NOT x2)
        let result = solver.solve(numVariables: 2, clauses: [[1], [2], [-1, -2]])
        XCTAssertEqual(result.description, "UNSAT")
    }

    // MARK: - Classic Problems

    func testPigeonholePrinciple2x1() {
        // 2 pigeons, 1 hole - UNSAT
        // Variables: p_i_j = pigeon i in hole j
        // p11 (pigeon 1 in hole 1)
        // p21 (pigeon 2 in hole 1)
        // Clauses:
        // (p11) - pigeon 1 must be somewhere
        // (p21) - pigeon 2 must be somewhere
        // (-p11 OR -p21) - hole 1 can only have one pigeon
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 2, clauses: [
            [1],       // pigeon 1 in hole 1
            [2],       // pigeon 2 in hole 1
            [-1, -2]   // at most one pigeon in hole 1
        ])
        XCTAssertEqual(result.description, "UNSAT")
    }

    func testGraphColoring() {
        // Triangle with 3 colors - SAT
        // Variables: c_v_k = vertex v has color k
        // 1=A-red, 2=A-green, 3=A-blue, 4=B-red, 5=B-green, 6=B-blue, 7=C-red, 8=C-green, 9=C-blue
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 9, clauses: [
            // Each vertex has at least one color
            [1, 2, 3],     // A has a color
            [4, 5, 6],     // B has a color
            [7, 8, 9],     // C has a color
            // Adjacent vertices have different colors
            // Edge A-B
            [-1, -4],      // not both red
            [-2, -5],      // not both green
            [-3, -6],      // not both blue
            // Edge B-C
            [-4, -7],
            [-5, -8],
            [-6, -9],
            // Edge A-C
            [-1, -7],
            [-2, -8],
            [-3, -9]
        ])
        if case .satisfiable = result {
            // Good
        } else {
            XCTFail("Triangle should be 3-colorable")
        }
    }

    // MARK: - DIMACS Parser Tests

    func testDIMACSParser() {
        let dimacs = """
        c This is a comment
        p cnf 3 2
        1 -2 3 0
        -1 2 0
        """
        guard let (numVars, clauses) = CDCLSolver.parseDIMACS(dimacs) else {
            XCTFail("Failed to parse DIMACS")
            return
        }

        XCTAssertEqual(numVars, 3)
        XCTAssertEqual(clauses.count, 2)
        XCTAssertEqual(clauses[0], [1, -2, 3])
        XCTAssertEqual(clauses[1], [-1, 2])
    }

    func testSolveDIMACS() {
        let dimacs = """
        p cnf 3 3
        1 2 0
        -1 2 0
        1 -2 0
        """
        let solver = CDCLSolver()
        let result = solver.solveDIMACS(dimacs)
        if case .satisfiable(let model) = result {
            // Check that the model satisfies all clauses
            // (x1 OR x2) AND (NOT x1 OR x2) AND (x1 OR NOT x2)
            // Requires x1=true, x2=true
            XCTAssertTrue(model[1] || model[2])      // clause 1
            XCTAssertTrue(!model[1] || model[2])     // clause 2
            XCTAssertTrue(model[1] || !model[2])     // clause 3
        } else {
            XCTFail("Should be satisfiable")
        }
    }

    // MARK: - Model Verification

    func testModelVerification() {
        let solver = CDCLSolver()
        let clauses = [
            [1, 2, 3],
            [-1, -2],
            [-2, -3],
            [1, 3]
        ]
        let result = solver.solve(numVariables: 3, clauses: clauses)

        if case .satisfiable(let model) = result {
            // Verify each clause is satisfied
            for clause in clauses {
                var satisfied = false
                for lit in clause {
                    let varIdx = abs(lit)
                    let expected = lit > 0
                    if model[varIdx] == expected {
                        satisfied = true
                        break
                    }
                }
                XCTAssertTrue(satisfied, "Clause \(clause) not satisfied by model")
            }
        } else {
            XCTFail("Should be satisfiable")
        }
    }

    // MARK: - Random 3-SAT

    func testRandom3SAT() {
        // Generate a random satisfiable 3-SAT instance
        let numVars = 20
        let numClauses = 50
        var clauses: [[Int]] = []

        // Force a specific satisfying assignment first
        let assignment = (1...numVars).map { _ in Bool.random() }

        for _ in 0..<numClauses {
            var clause: [Int] = []
            var vars = Array(1...numVars).shuffled().prefix(3)

            // Make sure at least one literal is satisfied
            let forcedIdx = Int.random(in: 0..<3)
            for (i, v) in vars.enumerated() {
                if i == forcedIdx {
                    // Make this literal true in our assignment
                    clause.append(assignment[v-1] ? v : -v)
                } else {
                    // Random polarity
                    clause.append(Bool.random() ? v : -v)
                }
            }
            clauses.append(clause)
        }

        let solver = CDCLSolver()
        let result = solver.solve(numVariables: numVars, clauses: clauses)

        if case .satisfiable = result {
            // Good - we constructed it to be satisfiable
        } else {
            XCTFail("Constructed satisfiable instance should be SAT")
        }
    }

    // MARK: - Statistics

    func testStatistics() {
        let solver = CDCLSolver()
        // A problem that requires some work
        let result = solver.solve(numVariables: 5, clauses: [
            [1, 2], [-1, 2], [1, -2], [-1, -2, 3],
            [3, 4], [-3, 4], [3, -4], [-3, -4, 5],
            [-5]
        ])

        // Should be UNSAT
        XCTAssertEqual(result.description, "UNSAT")

        // Check that statistics were recorded
        XCTAssertGreaterThan(solver.stats.conflicts, 0)
    }

    // MARK: - Edge Cases

    func testAllUnitClauses() {
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 5, clauses: [
            [1], [2], [3], [-4], [-5]
        ])
        if case .satisfiable(let model) = result {
            XCTAssertTrue(model[1])
            XCTAssertTrue(model[2])
            XCTAssertTrue(model[3])
            XCTAssertFalse(model[4])
            XCTAssertFalse(model[5])
        } else {
            XCTFail("Should be satisfiable")
        }
    }

    func testAllBinaryClauses() {
        let solver = CDCLSolver()
        // Implication chain: x1 -> x2 -> x3 -> x4 -> x5
        // Plus x1 must be true
        let result = solver.solve(numVariables: 5, clauses: [
            [1],           // x1
            [-1, 2],       // x1 -> x2
            [-2, 3],       // x2 -> x3
            [-3, 4],       // x3 -> x4
            [-4, 5]        // x4 -> x5
        ])
        if case .satisfiable(let model) = result {
            // All should be true due to implication chain
            for i in 1...5 {
                XCTAssertTrue(model[i])
            }
        } else {
            XCTFail("Should be satisfiable")
        }
    }

    func testLargeClauses() {
        let solver = CDCLSolver()
        // One large clause with all positive, one large clause with all negative
        // Should be SAT - need at least one true and at least one false
        let result = solver.solve(numVariables: 10, clauses: [
            Array(1...10),           // At least one positive
            Array(1...10).map { -$0 } // At least one negative
        ])
        if case .satisfiable(let model) = result {
            // Check at least one true and one false
            XCTAssertTrue(model.dropFirst().contains(true))
            XCTAssertTrue(model.dropFirst().contains(false))
        } else {
            XCTFail("Should be satisfiable")
        }
    }

    // MARK: - Stress Tests for Bug Regression

    func testSolverReuse() {
        // Test that solver can be reused
        let solver = CDCLSolver()

        // First solve
        let result1 = solver.solve(numVariables: 3, clauses: [[1, 2], [-1, 2]])
        if case .satisfiable = result1 {
            // Good
        } else {
            XCTFail("First solve should be SAT")
        }

        // Second solve (different problem)
        let result2 = solver.solve(numVariables: 2, clauses: [[1], [-1]])
        XCTAssertEqual(result2.description, "UNSAT")

        // Third solve
        let result3 = solver.solve(numVariables: 1, clauses: [[1]])
        if case .satisfiable(let model) = result3 {
            XCTAssertTrue(model[1])
        } else {
            XCTFail("Third solve should be SAT")
        }
    }

    func testManyConflicts() {
        // Problem that requires many conflicts to solve
        let solver = CDCLSolver()

        // PHP(3,2) - 3 pigeons, 2 holes - UNSAT
        // Variables: p_i_j where i=1,2,3 and j=1,2
        // p11=1, p12=2, p21=3, p22=4, p31=5, p32=6
        let clauses: [[Int]] = [
            // Each pigeon must be in some hole
            [1, 2],       // pigeon 1
            [3, 4],       // pigeon 2
            [5, 6],       // pigeon 3
            // Each hole can have at most one pigeon
            [-1, -3], [-1, -5], [-3, -5],  // hole 1
            [-2, -4], [-2, -6], [-4, -6]   // hole 2
        ]

        let result = solver.solve(numVariables: 6, clauses: clauses)
        XCTAssertEqual(result.description, "UNSAT")
        XCTAssertGreaterThan(solver.stats.conflicts, 0)
    }

    func testDeepBacktracking() {
        // Problem requiring deep backtracking
        let solver = CDCLSolver()

        // Chain of implications with conflict at the end
        var clauses: [[Int]] = []
        let n = 15

        // x1 must be true
        clauses.append([1])

        // xi => x(i+1) for i=1..n-1
        for i in 1..<n {
            clauses.append([-i, i+1])
        }

        // xn must be false
        clauses.append([-n])

        let result = solver.solve(numVariables: n, clauses: clauses)
        XCTAssertEqual(result.description, "UNSAT")
    }

    func testBinaryClausesOnly() {
        // All binary clauses - common in real problems
        let solver = CDCLSolver()
        let clauses: [[Int]] = [
            [1, 2], [-1, 3], [-2, 3], [-3, 4], [1, -4],
            [2, 4], [-1, -2], [-3, -4], [1, 4], [-2, -4]
        ]

        let result = solver.solve(numVariables: 4, clauses: clauses)
        // Verify result makes sense (don't care if SAT or UNSAT, just shouldn't crash)
        switch result {
        case .satisfiable(let model):
            // Verify all clauses satisfied
            for clause in clauses {
                var satisfied = false
                for lit in clause {
                    let varIdx = abs(lit)
                    if (lit > 0 && model[varIdx]) || (lit < 0 && !model[varIdx]) {
                        satisfied = true
                        break
                    }
                }
                XCTAssertTrue(satisfied)
            }
        case .unsatisfiable:
            // Also valid
            break
        case .unknown:
            XCTFail("Should not return unknown")
        }
    }

    func testRestartBehavior() {
        // Problem that likely triggers restarts
        let solver = CDCLSolver()
        var clauses: [[Int]] = []

        // Create a moderately hard random problem
        let numVars = 30
        let numClauses = 100

        // Generate random 3-SAT
        for _ in 0..<numClauses {
            var clause: [Int] = []
            var usedVars = Set<Int>()
            while clause.count < 3 {
                let v = Int.random(in: 1...numVars)
                if !usedVars.contains(v) {
                    usedVars.insert(v)
                    clause.append(Bool.random() ? v : -v)
                }
            }
            clauses.append(clause)
        }

        let result = solver.solve(numVariables: numVars, clauses: clauses)

        // Just verify it completes without crashing
        switch result {
        case .satisfiable, .unsatisfiable:
            break // OK
        case .unknown:
            break // Also OK for random instances
        }
    }

    func testDuplicateLiterals() {
        // Clause with duplicate literals (shouldn't crash)
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 2, clauses: [
            [1, 1, 1],  // x1 or x1 or x1
            [-1, 2],
            [-2]
        ])
        XCTAssertEqual(result.description, "UNSAT")
    }

    func testTautologicalClauses() {
        // Clause with both x and -x (tautology)
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: 2, clauses: [
            [1, -1],  // Always true
            [2],      // x2 must be true
            [-2]      // x2 must be false
        ])
        // The tautology doesn't help, still UNSAT due to x2
        XCTAssertEqual(result.description, "UNSAT")
    }
}
