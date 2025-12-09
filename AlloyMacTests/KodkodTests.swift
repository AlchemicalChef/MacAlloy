import XCTest
@testable import AlloyMac

final class KodkodTests: XCTestCase {

    // MARK: - Universe Tests

    func testUniverseCreation() {
        let universe = Universe(atomNames: ["A0", "A1", "A2"])
        XCTAssertEqual(universe.size, 3)
        XCTAssertEqual(universe[0].name, "A0")
        XCTAssertEqual(universe[1].name, "A1")
        XCTAssertEqual(universe[2].name, "A2")
    }

    func testUniverseWithSize() {
        let universe = Universe(size: 4, prefix: "Node")
        XCTAssertEqual(universe.size, 4)
        XCTAssertEqual(universe[0].name, "Node0")
        XCTAssertEqual(universe[3].name, "Node3")
    }

    func testUniverseAtomLookup() {
        let universe = Universe(atomNames: ["Alice", "Bob", "Carol"])
        XCTAssertNotNil(universe.atom(named: "Alice"))
        XCTAssertNotNil(universe.atom(named: "Bob"))
        XCTAssertNil(universe.atom(named: "David"))
    }

    func testUniverseAllTuples() {
        let universe = Universe(size: 2)
        let unary = universe.allTuples(arity: 1)
        XCTAssertEqual(unary.count, 2)

        let binary = universe.allTuples(arity: 2)
        XCTAssertEqual(binary.count, 4) // 2x2

        let ternary = universe.allTuples(arity: 3)
        XCTAssertEqual(ternary.count, 8) // 2x2x2
    }

    func testUniverseIdentity() {
        let universe = Universe(size: 3)
        let identity = universe.identity()
        XCTAssertEqual(identity.count, 3)
        for tuple in identity {
            XCTAssertEqual(tuple.first, tuple.second)
        }
    }

    // MARK: - Tuple Tests

    func testTupleCreation() {
        let universe = Universe(size: 3)
        let tuple = AtomTuple(universe[0], universe[1])
        XCTAssertEqual(tuple.arity, 2)
        XCTAssertEqual(tuple.first, universe[0])
        XCTAssertEqual(tuple.second, universe[1])
    }

    func testTupleProduct() {
        let universe = Universe(size: 3)
        let t1 = AtomTuple(universe[0])
        let t2 = AtomTuple(universe[1], universe[2])
        let product = t1.product(with: t2)
        XCTAssertEqual(product.arity, 3)
        XCTAssertEqual(product[0], universe[0])
        XCTAssertEqual(product[1], universe[1])
        XCTAssertEqual(product[2], universe[2])
    }

    func testTupleJoin() {
        let universe = Universe(size: 3)
        let t1 = AtomTuple(universe[0], universe[1])
        let t2 = AtomTuple(universe[1], universe[2])
        let joined = t1.join(with: t2)
        XCTAssertNotNil(joined)
        XCTAssertEqual(joined?.arity, 2)
        XCTAssertEqual(joined?[0], universe[0])
        XCTAssertEqual(joined?[1], universe[2])
    }

    func testTupleJoinNoMatch() {
        let universe = Universe(size: 3)
        let t1 = AtomTuple(universe[0], universe[1])
        let t2 = AtomTuple(universe[2], universe[0])
        let joined = t1.join(with: t2)
        XCTAssertNil(joined) // No match: 1 != 2
    }

    func testTupleTranspose() {
        let universe = Universe(size: 3)
        let tuple = AtomTuple(universe[0], universe[1], universe[2])
        let transposed = tuple.transposed()
        XCTAssertEqual(transposed[0], universe[2])
        XCTAssertEqual(transposed[1], universe[1])
        XCTAssertEqual(transposed[2], universe[0])
    }

    // MARK: - TupleSet Tests

    func testTupleSetCreation() {
        let universe = Universe(size: 3)
        let tuples = TupleSet(atoms: [universe[0], universe[1]])
        XCTAssertEqual(tuples.arity, 1)
        XCTAssertEqual(tuples.count, 2)
        XCTAssertTrue(tuples.contains(AtomTuple(universe[0])))
        XCTAssertFalse(tuples.contains(AtomTuple(universe[2])))
    }

    func testTupleSetUnion() {
        let universe = Universe(size: 3)
        let a = TupleSet(atoms: [universe[0]])
        let b = TupleSet(atoms: [universe[1]])
        let c = a.union(b)
        XCTAssertEqual(c.count, 2)
        XCTAssertTrue(c.contains(AtomTuple(universe[0])))
        XCTAssertTrue(c.contains(AtomTuple(universe[1])))
    }

    func testTupleSetIntersection() {
        let universe = Universe(size: 3)
        let a = TupleSet(atoms: [universe[0], universe[1]])
        let b = TupleSet(atoms: [universe[1], universe[2]])
        let c = a.intersection(b)
        XCTAssertEqual(c.count, 1)
        XCTAssertTrue(c.contains(AtomTuple(universe[1])))
    }

    func testTupleSetDifference() {
        let universe = Universe(size: 3)
        let a = TupleSet(atoms: [universe[0], universe[1]])
        let b = TupleSet(atoms: [universe[1]])
        let c = a.difference(b)
        XCTAssertEqual(c.count, 1)
        XCTAssertTrue(c.contains(AtomTuple(universe[0])))
    }

    func testTupleSetJoin() {
        let universe = Universe(size: 3)
        // r = {(0,1), (1,2)}
        let r = TupleSet([
            AtomTuple(universe[0], universe[1]),
            AtomTuple(universe[1], universe[2])
        ])
        // r.r = {(0,2)}
        let rr = r.join(r)
        XCTAssertEqual(rr.count, 1)
        XCTAssertTrue(rr.contains(AtomTuple(universe[0], universe[2])))
    }

    func testTupleSetTransitiveClosure() {
        let universe = Universe(size: 3)
        // r = {(0,1), (1,2)}
        let r = TupleSet([
            AtomTuple(universe[0], universe[1]),
            AtomTuple(universe[1], universe[2])
        ])
        // ^r = {(0,1), (1,2), (0,2)}
        let closure = r.transitiveClosure()
        XCTAssertEqual(closure.count, 3)
        XCTAssertTrue(closure.contains(AtomTuple(universe[0], universe[1])))
        XCTAssertTrue(closure.contains(AtomTuple(universe[1], universe[2])))
        XCTAssertTrue(closure.contains(AtomTuple(universe[0], universe[2])))
    }

    // MARK: - Bounds Tests

    func testBoundsCreation() {
        let universe = Universe(size: 3)
        let bounds = Bounds(universe: universe)

        bounds.boundUnary("A", lower: [universe[0]], upper: [universe[0], universe[1], universe[2]])
        bounds.boundUnaryExact("B", atoms: [universe[1]])

        XCTAssertNotNil(bounds["A"])
        XCTAssertNotNil(bounds["B"])

        XCTAssertEqual(bounds["A"]?.freeCount, 2) // Upper - Lower
        XCTAssertEqual(bounds["B"]?.freeCount, 0) // Exact
        XCTAssertTrue(bounds["B"]?.isConstant ?? false)
    }

    func testBoundsBuilder() {
        let universe = Universe(size: 3)
        let bounds = BoundsBuilder(universe: universe)
            .unary("Set", lower: [0], upper: [0, 1, 2])
            .binary("Edge", lower: [], upper: [(0, 1), (1, 2), (2, 0)])
            .binaryExact("Identity", tuples: [(0, 0), (1, 1), (2, 2)])
            .build()

        XCTAssertEqual(bounds["Set"]?.arity, 1)
        XCTAssertEqual(bounds["Edge"]?.arity, 2)
        XCTAssertEqual(bounds["Identity"]?.freeCount, 0)
    }

    // MARK: - Boolean Formula Tests

    func testBooleanFormulaConstants() {
        XCTAssertEqual(BooleanFormula.trueFormula.constantValue, true)
        XCTAssertEqual(BooleanFormula.falseFormula.constantValue, false)
    }

    func testBooleanFormulaNegation() {
        let a = BooleanFormula.variable(1)
        let notA = a.negated
        XCTAssert(notA.description.contains("~"))
    }

    func testBooleanFormulaConjunction() {
        let a = BooleanFormula.variable(1)
        let b = BooleanFormula.variable(2)
        let conj = BooleanFormula.conjunction([a, b])
        XCTAssertFalse(conj.isLiteral)
    }

    func testBooleanFormulaSimplification() {
        // TRUE & a = a
        let a = BooleanFormula.variable(1)
        let simplified = BooleanFormula.conjunction([.trueFormula, a])
        XCTAssertTrue(simplified.isLiteral)

        // FALSE | a = a
        let simplified2 = BooleanFormula.disjunction([.falseFormula, a])
        XCTAssertTrue(simplified2.isLiteral)

        // FALSE & a = FALSE
        let simplified3 = BooleanFormula.conjunction([.falseFormula, a])
        XCTAssertEqual(simplified3.constantValue, false)

        // TRUE | a = TRUE
        let simplified4 = BooleanFormula.disjunction([.trueFormula, a])
        XCTAssertEqual(simplified4.constantValue, true)
    }

    // MARK: - CNF Builder Tests

    func testCNFBuilderBasic() {
        let cnf = CNFBuilder()

        let v1 = cnf.freshVariable()
        let v2 = cnf.freshVariable()
        XCTAssertEqual(v1, 1)
        XCTAssertEqual(v2, 2)

        cnf.addClause([v1, v2])
        cnf.addClause([-v1, v2])

        XCTAssertEqual(cnf.allClauses.count, 2)
    }

    func testCNFBuilderTseitin() {
        let cnf = CNFBuilder()

        // Encode: (a & b) | (c & d)
        let a = BooleanFormula.variable(cnf.freshVariable())
        let b = BooleanFormula.variable(cnf.freshVariable())
        let c = BooleanFormula.variable(cnf.freshVariable())
        let d = BooleanFormula.variable(cnf.freshVariable())

        let formula = BooleanFormula.disjunction([
            BooleanFormula.conjunction([a, b]),
            BooleanFormula.conjunction([c, d])
        ])

        let _ = cnf.assertTrue(formula)

        // Should have generated auxiliary variables and clauses
        XCTAssertGreaterThan(cnf.variableCount, 4)
        XCTAssertGreaterThan(cnf.allClauses.count, 0)
    }

    func testCNFBuilderDIMACS() {
        let cnf = CNFBuilder()
        let v1 = cnf.freshVariable()
        let v2 = cnf.freshVariable()
        cnf.addClause([v1, v2])
        cnf.addClause([-v1, -v2])

        let dimacs = cnf.toDIMACS()
        XCTAssertTrue(dimacs.contains("p cnf 2 2"))
    }

    // MARK: - Boolean Matrix Tests

    func testBooleanMatrixConstant() {
        let universe = Universe(size: 2)
        let tuples = TupleSet(atoms: [universe[0]])
        let matrix = BooleanMatrix(constant: tuples, universe: universe)

        XCTAssertEqual(matrix[AtomTuple(universe[0])].constantValue, true)
        XCTAssertEqual(matrix[AtomTuple(universe[1])].constantValue, false)
    }

    func testBooleanMatrixFromBounds() {
        let universe = Universe(size: 2)
        let bounds = RelationBounds(
            name: "R",
            lower: TupleSet(atoms: [universe[0]]),
            upper: TupleSet(atoms: [universe[0], universe[1]])
        )
        let cnf = CNFBuilder()
        let matrix = BooleanMatrix(bounds: bounds, universe: universe, cnf: cnf)

        // Lower bound atom should be constant true
        XCTAssertEqual(matrix[AtomTuple(universe[0])].constantValue, true)
        // Free atom should be a variable
        XCTAssertNotNil(matrix[AtomTuple(universe[1])].variableIndex)
    }

    func testBooleanMatrixUnion() {
        let universe = Universe(size: 2)
        let cnf = CNFBuilder()

        let a = BooleanMatrix(constant: TupleSet(atoms: [universe[0]]), universe: universe)
        let b = BooleanMatrix(constant: TupleSet(atoms: [universe[1]]), universe: universe)
        let c = a.union(b, cnf: cnf)

        XCTAssertEqual(c[AtomTuple(universe[0])].constantValue, true)
        XCTAssertEqual(c[AtomTuple(universe[1])].constantValue, true)
    }

    func testBooleanMatrixIntersection() {
        let universe = Universe(size: 3)
        let cnf = CNFBuilder()

        let a = BooleanMatrix(constant: TupleSet(atoms: [universe[0], universe[1]]), universe: universe)
        let b = BooleanMatrix(constant: TupleSet(atoms: [universe[1], universe[2]]), universe: universe)
        let c = a.intersection(b, cnf: cnf)

        XCTAssertEqual(c[AtomTuple(universe[0])].constantValue, false)
        XCTAssertEqual(c[AtomTuple(universe[1])].constantValue, true)
        XCTAssertEqual(c[AtomTuple(universe[2])].constantValue, false)
    }

    func testBooleanMatrixTranspose() {
        let universe = Universe(size: 2)
        let tuples = TupleSet([AtomTuple(universe[0], universe[1])])
        let matrix = BooleanMatrix(constant: tuples, universe: universe)
        let transposed = matrix.transpose()

        XCTAssertEqual(transposed[AtomTuple(universe[1], universe[0])].constantValue, true)
        XCTAssertEqual(transposed[AtomTuple(universe[0], universe[1])].constantValue, false)
    }

    // MARK: - Relational Encoder Tests

    func testEncoderBasic() {
        let universe = Universe(size: 3)
        let bounds = BoundsBuilder(universe: universe)
            .unary("Set", lower: [], upper: [0, 1, 2])
            .build()

        let encoder = RelationalEncoder(bounds: bounds)
        XCTAssertNotNil(encoder.relation("Set"))
        XCTAssertGreaterThan(encoder.variableCount, 0)
    }

    func testEncoderUnion() {
        let universe = Universe(size: 3)
        let bounds = BoundsBuilder(universe: universe)
            .unaryExact("A", atoms: [0])
            .unaryExact("B", atoms: [1])
            .build()

        let encoder = RelationalEncoder(bounds: bounds)
        let a = encoder.relation("A")!
        let b = encoder.relation("B")!
        let c = encoder.union(a, b)

        XCTAssertEqual(c[AtomTuple(universe[0])].constantValue, true)
        XCTAssertEqual(c[AtomTuple(universe[1])].constantValue, true)
        XCTAssertEqual(c[AtomTuple(universe[2])].constantValue, false)
    }

    func testEncoderJoin() {
        let universe = Universe(size: 3)
        let bounds = BoundsBuilder(universe: universe)
            .binaryExact("R", tuples: [(0, 1), (1, 2)])
            .build()

        let encoder = RelationalEncoder(bounds: bounds)
        let r = encoder.relation("R")!
        let rr = encoder.join(r, r)

        // R.R should have (0,2) since 0->1->2
        XCTAssertEqual(rr[AtomTuple(universe[0], universe[2])].constantValue, true)
        // Should not have (0,1) or (1,2) directly from R.R
        XCTAssertEqual(rr[AtomTuple(universe[0], universe[1])].constantValue, false)
    }

    func testEncoderAssertions() {
        let universe = Universe(size: 2)
        let bounds = BoundsBuilder(universe: universe)
            .unary("Set", lower: [], upper: [0, 1])
            .build()

        let encoder = RelationalEncoder(bounds: bounds)
        let set = encoder.relation("Set")!

        // Assert non-empty
        encoder.assertSome(set)

        XCTAssertGreaterThan(encoder.clauseCount, 0)
    }

    // MARK: - Integration with SAT Solver

    func testEncoderWithSATSolver() {
        let universe = Universe(size: 3)
        let bounds = BoundsBuilder(universe: universe)
            .unary("Set", lower: [], upper: [0, 1, 2])
            .build()

        let encoder = RelationalEncoder(bounds: bounds)
        let set = encoder.relation("Set")!

        // Assert: Set has exactly one element
        encoder.assertOne(set)

        // Solve
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: encoder.variableCount, clauses: encoder.clauses)

        switch result {
        case .satisfiable(let model):
            let solution = encoder.extractSolution(solution: model)
            let setTuples = solution["Set"]!
            XCTAssertEqual(setTuples.count, 1)
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testGraphColoringEncoding() {
        // 3-coloring a triangle graph
        let universe = Universe(size: 3) // 3 nodes
        let bounds = BoundsBuilder(universe: universe)
            // Each node can have one color: Red, Green, Blue
            // We'll model as: Red = {nodes colored red}, etc.
            .unary("Red", lower: [], upper: [0, 1, 2])
            .unary("Green", lower: [], upper: [0, 1, 2])
            .unary("Blue", lower: [], upper: [0, 1, 2])
            .build()

        let encoder = RelationalEncoder(bounds: bounds)
        let red = encoder.relation("Red")!
        let green = encoder.relation("Green")!
        let blue = encoder.relation("Blue")!

        // Each node has exactly one color
        for i in 0..<3 {
            let node = universe[i]
            let inRed = BooleanFormula.from(red[AtomTuple(node)])
            let inGreen = BooleanFormula.from(green[AtomTuple(node)])
            let inBlue = BooleanFormula.from(blue[AtomTuple(node)])

            // At least one
            encoder.assertFormula(.disjunction([inRed, inGreen, inBlue]))

            // At most one (pairwise)
            encoder.assertFormula(.disjunction([inRed.negated, inGreen.negated]))
            encoder.assertFormula(.disjunction([inRed.negated, inBlue.negated]))
            encoder.assertFormula(.disjunction([inGreen.negated, inBlue.negated]))
        }

        // Adjacent nodes have different colors
        // Triangle edges: (0,1), (1,2), (0,2)
        let edges = [(0, 1), (1, 2), (0, 2)]
        for (i, j) in edges {
            let ni = universe[i]
            let nj = universe[j]

            // Not both red
            encoder.assertFormula(.disjunction([
                BooleanFormula.from(red[AtomTuple(ni)]).negated,
                BooleanFormula.from(red[AtomTuple(nj)]).negated
            ]))
            // Not both green
            encoder.assertFormula(.disjunction([
                BooleanFormula.from(green[AtomTuple(ni)]).negated,
                BooleanFormula.from(green[AtomTuple(nj)]).negated
            ]))
            // Not both blue
            encoder.assertFormula(.disjunction([
                BooleanFormula.from(blue[AtomTuple(ni)]).negated,
                BooleanFormula.from(blue[AtomTuple(nj)]).negated
            ]))
        }

        // Solve
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: encoder.variableCount, clauses: encoder.clauses)

        switch result {
        case .satisfiable(let model):
            let solution = encoder.extractSolution(solution: model)
            let redNodes = solution["Red"]!
            let greenNodes = solution["Green"]!
            let blueNodes = solution["Blue"]!

            // Verify each node has exactly one color
            for i in 0..<3 {
                let tuple = AtomTuple(universe[i])
                let colorCount = [redNodes, greenNodes, blueNodes].filter { $0.contains(tuple) }.count
                XCTAssertEqual(colorCount, 1, "Node \(i) should have exactly one color")
            }

            // Verify adjacent nodes have different colors
            for (i, j) in edges {
                let ti = AtomTuple(universe[i])
                let tj = AtomTuple(universe[j])

                let iColor = redNodes.contains(ti) ? "R" : (greenNodes.contains(ti) ? "G" : "B")
                let jColor = redNodes.contains(tj) ? "R" : (greenNodes.contains(tj) ? "G" : "B")

                XCTAssertNotEqual(iColor, jColor, "Adjacent nodes \(i) and \(j) should have different colors")
            }
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testTransitiveClosureEncoding() {
        let universe = Universe(size: 3)
        let bounds = BoundsBuilder(universe: universe)
            .binaryExact("R", tuples: [(0, 1), (1, 2)])
            .build()

        let encoder = RelationalEncoder(bounds: bounds)
        let r = encoder.relation("R")!
        let closure = encoder.transitiveClosure(r)

        // ^R should contain: (0,1), (1,2), (0,2)
        XCTAssertEqual(closure[AtomTuple(universe[0], universe[1])].constantValue, true)
        XCTAssertEqual(closure[AtomTuple(universe[1], universe[2])].constantValue, true)
        XCTAssertEqual(closure[AtomTuple(universe[0], universe[2])].constantValue, true)
    }

    func testQuantifierEncoding() {
        let universe = Universe(size: 3)
        let bounds = BoundsBuilder(universe: universe)
            .unaryExact("All", atoms: [0, 1, 2])
            .unary("Subset", lower: [], upper: [0, 1, 2])
            .build()

        let encoder = RelationalEncoder(bounds: bounds)
        let all = encoder.relation("All")!
        let subset = encoder.relation("Subset")!

        // Assert: some x: All | x in Subset (Subset is non-empty)
        let existsFormula = encoder.exists(over: all) { atom in
            BooleanFormula.from(subset[AtomTuple(atom)])
        }
        encoder.assertFormula(existsFormula)

        // Assert: all x: Subset | x in All (trivially true but tests the encoding)
        let forallFormula = encoder.forAll(over: subset) { atom in
            BooleanFormula.from(all[AtomTuple(atom)])
        }
        encoder.assertFormula(forallFormula)

        // Solve
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: encoder.variableCount, clauses: encoder.clauses)

        switch result {
        case .satisfiable(let model):
            let solution = encoder.extractSolution(solution: model)
            let subsetTuples = solution["Subset"]!
            XCTAssertGreaterThan(subsetTuples.count, 0, "Subset should be non-empty")
        case .unsatisfiable:
            XCTFail("Expected satisfiable")
        case .unknown:
            XCTFail("Expected satisfiable")
        }
    }

    func testUnsatisfiableProblem() {
        let universe = Universe(size: 2)
        let bounds = BoundsBuilder(universe: universe)
            .unary("Set", lower: [], upper: [0, 1])
            .build()

        let encoder = RelationalEncoder(bounds: bounds)
        let set = encoder.relation("Set")!

        // Assert contradictory constraints: Set is both empty AND non-empty
        encoder.assertNo(set)
        encoder.assertSome(set)

        // Solve
        let solver = CDCLSolver()
        let result = solver.solve(numVariables: encoder.variableCount, clauses: encoder.clauses)

        switch result {
        case .unsatisfiable:
            // Expected
            break
        case .satisfiable:
            XCTFail("Expected unsatisfiable")
        case .unknown:
            XCTFail("Expected unsatisfiable")
        }
    }
}
