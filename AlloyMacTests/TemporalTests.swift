import XCTest
@testable import AlloyMac

final class TemporalTests: XCTestCase {

    // MARK: - Trace Tests

    func testTraceCreation() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: true)

        XCTAssertEqual(trace.length, 3)
        XCTAssertTrue(trace.requiresLoop)
        XCTAssertTrue(trace.isValidState(0))
        XCTAssertTrue(trace.isValidState(2))
        XCTAssertFalse(trace.isValidState(3))
    }

    func testTraceLoopVariables() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: true)

        // Should have loop variables for states 0, 1, 2
        XCTAssertNotNil(trace.loopVariable(to: 0))
        XCTAssertNotNil(trace.loopVariable(to: 1))
        XCTAssertNotNil(trace.loopVariable(to: 2))
        XCTAssertNil(trace.loopVariable(to: 3))

        // Exactly-one constraint should be encoded
        XCTAssertGreaterThan(cnf.allClauses.count, 0)
    }

    func testTraceWithoutLoop() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)

        XCTAssertFalse(trace.requiresLoop)
        XCTAssertNil(trace.loopVariable(to: 0))
    }

    func testTraceFutureStates() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 4, cnf: cnf, requiresLoop: true)

        let future = trace.futureStates(from: 1)
        XCTAssertEqual(future, [1, 2, 3])

        let pastFrom2 = trace.pastStates(from: 2)
        XCTAssertEqual(pastFrom2, [0, 1, 2])
    }

    // MARK: - Temporal Relation Tests

    func testTemporalRelationVariable() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: true)

        let bounds = RelationBounds(
            name: "flag",
            lower: TupleSet(arity: 1),
            upper: TupleSet(atoms: [universe[0], universe[1]])
        )
        let rel = TemporalRelation(name: "flag", bounds: bounds, trace: trace, isVariable: true)

        XCTAssertTrue(rel.isVariable)
        XCTAssertEqual(rel.arity, 1)

        // Each state should have different variables
        let m0 = rel.matrix(at: 0)
        let m1 = rel.matrix(at: 1)
        let m2 = rel.matrix(at: 2)

        // Verify they can have different values (different SAT variables)
        XCTAssertNotNil(m0[0].variableIndex)
        XCTAssertNotNil(m1[0].variableIndex)
        XCTAssertNotNil(m2[0].variableIndex)
    }

    func testTemporalRelationConstant() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: true)

        let value = TupleSet(atoms: [universe[0]])
        let rel = TemporalRelation(name: "const", constant: value, trace: trace)

        XCTAssertFalse(rel.isVariable)

        // All states should have the same constant value
        for i in 0..<3 {
            XCTAssertEqual(rel.membership(AtomTuple(universe[0]), at: i).constantValue, true)
            XCTAssertEqual(rel.membership(AtomTuple(universe[1]), at: i).constantValue, false)
        }
    }

    func testTemporalRelationPrimed() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)

        let bounds = RelationBounds(
            name: "x",
            lower: TupleSet(arity: 1),
            upper: TupleSet(atoms: [universe[0], universe[1]])
        )
        let rel = TemporalRelation(name: "x", bounds: bounds, trace: trace, isVariable: true)

        // x' at state 0 should equal x at state 1
        let xPrimedAt0 = rel.primedMembership(AtomTuple(universe[0]), at: 0)
        let xAt1 = rel.membership(AtomTuple(universe[0]), at: 1)

        // They should be equivalent (same variable)
        XCTAssertEqual(xPrimedAt0.description, xAt1.description)
    }

    // MARK: - LTL Encoder Tests

    func testAfterOperator() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        // Create a simple proposition for each state
        let props = (0..<3).map { _ in cnf.freshVariable() }

        // after(props) at state 0 should be props[1]
        let afterAt0 = encoder.after({ props[$0] > 0 ? .variable(props[$0]) : .falseFormula }, at: 0)
        XCTAssertEqual(afterAt0.description, "x\(props[1])")

        // after at last state of finite trace should be false
        let afterAt2 = encoder.after({ props[$0] > 0 ? .variable(props[$0]) : .falseFormula }, at: 2)
        XCTAssertEqual(afterAt2.constantValue, false)
    }

    func testBeforeOperator() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        let props = (0..<3).map { _ in cnf.freshVariable() }

        // before at state 0 should be false (no previous state)
        let beforeAt0 = encoder.before({ .variable(props[$0]) }, at: 0)
        XCTAssertEqual(beforeAt0.constantValue, false)

        // before at state 1 should be props[0]
        let beforeAt1 = encoder.before({ .variable(props[$0]) }, at: 1)
        XCTAssertEqual(beforeAt1.description, "x\(props[0])")
    }

    func testAlwaysOperatorFinite() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        let props = (0..<3).map { _ in cnf.freshVariable() }

        // always from state 1 in finite trace = props[1] & props[2]
        let alwaysFrom1 = encoder.always({ .variable(props[$0]) }, at: 1)

        // Should be a conjunction
        XCTAssertFalse(alwaysFrom1.isLiteral)
    }

    func testEventuallyOperatorFinite() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        let props = (0..<3).map { _ in cnf.freshVariable() }

        // eventually from state 1 = props[1] | props[2]
        let eventuallyFrom1 = encoder.eventually({ .variable(props[$0]) }, at: 1)

        // Should be a disjunction
        XCTAssertFalse(eventuallyFrom1.isLiteral)
    }

    func testHistoricallyOperator() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        let props = (0..<3).map { _ in cnf.freshVariable() }

        // historically at state 2 = props[0] & props[1] & props[2]
        let hist = encoder.historically({ .variable(props[$0]) }, at: 2)

        XCTAssertFalse(hist.isLiteral)
    }

    func testOnceOperator() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        let props = (0..<3).map { _ in cnf.freshVariable() }

        // once at state 2 = props[0] | props[1] | props[2]
        let onceFormula = encoder.once({ .variable(props[$0]) }, at: 2)

        XCTAssertFalse(onceFormula.isLiteral)
    }

    // MARK: - Integration Tests with SAT Solver

    func testSimpleTemporalModel() {
        // Model a simple counter that can be 0 or 1, and toggles each step
        let universe = Universe(size: 2) // atoms: 0, 1 representing counter values
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        // Add relation: counter (unary, the current value)
        let bounds = RelationBounds(
            name: "counter",
            lower: TupleSet(arity: 1),
            upper: TupleSet(atoms: [universe[0], universe[1]])
        )
        encoder.relations.addVariable("counter", bounds: bounds)
        let counter = encoder.relations["counter"]!

        // Initial condition: counter = {0}
        let m0 = counter.matrix(at: 0)
        cnf.assertTrue(m0.membership(AtomTuple(universe[0])))
        cnf.assertTrue(m0.nonMembership(AtomTuple(universe[1])))

        // Transition: counter toggles (exactly one value at each state)
        for i in 0..<trace.length {
            let m = counter.matrix(at: i)
            // Exactly one
            cnf.assertTrue(m.hasExactlyOne())
        }

        // Transition: if counter=0 then counter'=1 and vice versa
        for i in 0..<(trace.length - 1) {
            let curr = counter.matrix(at: i)
            let next = counter.matrix(at: i + 1)

            // counter[0] => next_counter[1]
            cnf.assertTrue(BooleanFormula.from(curr[AtomTuple(universe[0])])
                .implies(.from(next[AtomTuple(universe[1])])))

            // counter[1] => next_counter[0]
            cnf.assertTrue(BooleanFormula.from(curr[AtomTuple(universe[1])])
                .implies(.from(next[AtomTuple(universe[0])])))
        }

        // Solve
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: Int(cnf.variableCount), clauses: cnf.allClauses.map { $0.map { Int($0) } })

        switch result {
        case .satisfiable(let model):
            // Extract values
            let v0 = counter.extractValue(at: 0, solution: model)
            let v1 = counter.extractValue(at: 1, solution: model)
            let v2 = counter.extractValue(at: 2, solution: model)

            // Should alternate: {0} -> {1} -> {0}
            XCTAssertTrue(v0.contains(AtomTuple(universe[0])))
            XCTAssertTrue(v1.contains(AtomTuple(universe[1])))
            XCTAssertTrue(v2.contains(AtomTuple(universe[0])))
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testAlwaysEventuallyWithLasso() {
        // Test: always eventually p (infinitely often p)
        // With lasso trace, this should be satisfiable if p holds somewhere in the loop
        let universe = Universe(size: 1)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: true)
        let encoder = LTLEncoder(trace: trace)

        // Create proposition p for each state
        let p = (0..<3).map { _ in cnf.freshVariable() }

        // Assert: p is true at state 1 (to make eventually p satisfiable)
        cnf.addUnit(p[1])

        // Assert: always eventually p at state 0
        // For finite approximation with lasso:
        // This is complex in general, but we can check that eventually p holds from each state
        for i in 0..<trace.length {
            let eventuallyP = encoder.eventually({ .variable(p[$0]) }, at: i)
            cnf.assertTrue(eventuallyP)
        }

        // Solve
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: Int(cnf.variableCount), clauses: cnf.allClauses.map { $0.map { Int($0) } })

        switch result {
        case .satisfiable(let model):
            // p[1] should be true
            let p1Value = model[Int(p[1])]
            XCTAssertTrue(p1Value)

            // Check loop state
            let loopState = trace.extractLoopState(from: model)
            XCTAssertNotNil(loopState)
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testUntilOperator() {
        // Test: p until q
        // p should hold until q becomes true
        let universe = Universe(size: 1)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 4, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        let p = (0..<4).map { _ in cnf.freshVariable() }
        let q = (0..<4).map { _ in cnf.freshVariable() }

        // Assert p until q at state 0
        let pUntilQ = encoder.until({ .variable(p[$0]) }, { .variable(q[$0]) }, at: 0)
        cnf.assertTrue(pUntilQ)

        // Make q true only at state 2
        cnf.addUnit(-q[0])
        cnf.addUnit(-q[1])
        cnf.addUnit(q[2])
        cnf.addUnit(-q[3])

        // Solve
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: Int(cnf.variableCount), clauses: cnf.allClauses.map { $0.map { Int($0) } })

        switch result {
        case .satisfiable(let model):
            // p should be true at states 0 and 1 (before q)
            XCTAssertTrue(model[Int(p[0])])
            XCTAssertTrue(model[Int(p[1])])
            // q is true at state 2
            XCTAssertTrue(model[Int(q[2])])
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testSinceOperator() {
        // Test: p since q
        // q should have held at some past point, and p since then
        let universe = Universe(size: 1)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 4, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        let p = (0..<4).map { _ in cnf.freshVariable() }
        let q = (0..<4).map { _ in cnf.freshVariable() }

        // Assert p since q at state 3
        let pSinceQ = encoder.since({ .variable(p[$0]) }, { .variable(q[$0]) }, at: 3)
        cnf.assertTrue(pSinceQ)

        // Make q true only at state 1
        cnf.addUnit(-q[0])
        cnf.addUnit(q[1])
        cnf.addUnit(-q[2])
        cnf.addUnit(-q[3])

        // Solve
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: Int(cnf.variableCount), clauses: cnf.allClauses.map { $0.map { Int($0) } })

        switch result {
        case .satisfiable(let model):
            // q is true at state 1
            XCTAssertTrue(model[Int(q[1])])
            // p should be true at states 2 and 3 (since q at 1)
            XCTAssertTrue(model[Int(p[2])])
            XCTAssertTrue(model[Int(p[3])])
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testMutualExclusionProtocol() {
        // Simple mutual exclusion with 2 processes
        // Each process can be in state: idle, trying, critical
        // Safety: never both in critical
        let universe = Universe(size: 2) // 2 processes

        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 4, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        // Relations for each process state
        let idleBounds = RelationBounds(name: "idle",
                                        lower: TupleSet(arity: 1),
                                        upper: TupleSet(atoms: [universe[0], universe[1]]))
        let criticalBounds = RelationBounds(name: "critical",
                                            lower: TupleSet(arity: 1),
                                            upper: TupleSet(atoms: [universe[0], universe[1]]))

        encoder.relations.addVariable("idle", bounds: idleBounds)
        encoder.relations.addVariable("critical", bounds: criticalBounds)

        let idle = encoder.relations["idle"]!
        let critical = encoder.relations["critical"]!

        // Initial: both idle
        let idle0 = idle.matrix(at: 0)
        cnf.assertTrue(idle0.membership(AtomTuple(universe[0])))
        cnf.assertTrue(idle0.membership(AtomTuple(universe[1])))

        let crit0 = critical.matrix(at: 0)
        cnf.assertTrue(crit0.nonMembership(AtomTuple(universe[0])))
        cnf.assertTrue(crit0.nonMembership(AtomTuple(universe[1])))

        // Safety invariant: at most one in critical at any state
        for i in 0..<trace.length {
            let critI = critical.matrix(at: i)
            let both = BooleanFormula.from(critI[AtomTuple(universe[0])])
                .and(.from(critI[AtomTuple(universe[1])]))
            cnf.assertTrue(both.negated)
        }

        // Solve (should be satisfiable)
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: Int(cnf.variableCount),
                                  clauses: cnf.allClauses.map { $0.map { Int($0) } })

        switch result {
        case .satisfiable(let model):
            // Verify mutual exclusion at all states
            for i in 0..<trace.length {
                let crit = critical.extractValue(at: i, solution: model)
                XCTAssertLessThanOrEqual(crit.count, 1, "At most one process in critical at state \(i)")
            }
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testLassoTraceExtraction() {
        let universe = Universe(size: 1)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: true)

        // Force loop to state 1
        if let loopVar0 = trace.loopVariable(to: 0) {
            cnf.addUnit(-loopVar0)
        }
        if let loopVar1 = trace.loopVariable(to: 1) {
            cnf.addUnit(loopVar1)
        }
        if let loopVar2 = trace.loopVariable(to: 2) {
            cnf.addUnit(-loopVar2)
        }

        let solver = CDCLSolver()
        let result = solver.solve(numVariables: Int(cnf.variableCount),
                                  clauses: cnf.allClauses.map { $0.map { Int($0) } })

        switch result {
        case .satisfiable(let model):
            let loopState = trace.extractLoopState(from: model)
            XCTAssertEqual(loopState, 1)
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testEventuallyAlwaysPattern() {
        // Test: eventually always p (p eventually becomes true and stays true)
        // Common liveness pattern
        let universe = Universe(size: 1)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 4, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        let p = (0..<4).map { _ in cnf.freshVariable() }

        // eventually always p at state 0:
        // There exists j >= 0 such that for all k >= j: p(k)
        // In finite trace: p holds from some point onwards

        var disjuncts: [BooleanFormula] = []
        for j in 0..<trace.length {
            var conjuncts: [BooleanFormula] = []
            for k in j..<trace.length {
                conjuncts.append(.variable(p[k]))
            }
            disjuncts.append(.conjunction(conjuncts))
        }
        cnf.assertTrue(.disjunction(disjuncts))

        // Force p to be false initially
        cnf.addUnit(-p[0])

        let solver = CDCLSolver()
        let result = solver.solve(numVariables: Int(cnf.variableCount),
                                  clauses: cnf.allClauses.map { $0.map { Int($0) } })

        switch result {
        case .satisfiable(let model):
            // p[0] is false
            XCTAssertFalse(model[Int(p[0])])

            // p should be true from some point onwards
            var foundStart = false
            for i in 1..<4 {
                if model[Int(p[i])] {
                    foundStart = true
                    // All subsequent should be true
                    for j in i..<4 {
                        XCTAssertTrue(model[Int(p[j])], "p should stay true from state \(i)")
                    }
                    break
                }
            }
            XCTAssertTrue(foundStart, "p should eventually become true")
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testTransitionAssertion() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()
        let trace = Trace(universe: universe, length: 3, cnf: cnf, requiresLoop: false)
        let encoder = LTLEncoder(trace: trace)

        // Create a proposition that must stay the same
        let p = (0..<3).map { _ in cnf.freshVariable() }

        // Assert: p stays constant (frame condition)
        encoder.assertTransition { curr, next in
            // p at curr <=> p at next
            BooleanFormula.variable(p[curr]).iff(.variable(p[next]))
        }

        // Set initial value
        cnf.addUnit(p[0])

        let solver = CDCLSolver()
        let result = solver.solve(numVariables: Int(cnf.variableCount),
                                  clauses: cnf.allClauses.map { $0.map { Int($0) } })

        switch result {
        case .satisfiable(let model):
            // All states should have the same value
            XCTAssertTrue(model[Int(p[0])])
            XCTAssertTrue(model[Int(p[1])])
            XCTAssertTrue(model[Int(p[2])])
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }
}
