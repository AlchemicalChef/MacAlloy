import Foundation

// MARK: - Relational Encoder

/// Encodes Alloy relational expressions into boolean formulas
/// This is the main interface for translating Alloy to SAT
public final class RelationalEncoder {
    /// The universe
    public let universe: Universe

    /// The bounds
    public let bounds: Bounds

    /// CNF builder for generating SAT clauses
    public let cnf: CNFBuilder

    /// Cache of encoded relations
    private var relationMatrices: [String: BooleanMatrix] = [:]

    /// Create an encoder with the given bounds
    public init(bounds: Bounds) {
        self.universe = bounds.universe
        self.bounds = bounds
        self.cnf = CNFBuilder()

        // Initialize matrices for all bounded relations
        for relationBounds in bounds.allBounds {
            let matrix = BooleanMatrix(bounds: relationBounds, universe: universe, cnf: cnf)
            relationMatrices[relationBounds.name] = matrix
        }
    }

    // MARK: - Relation Access

    /// Get the matrix for a relation
    public func relation(_ name: String) -> BooleanMatrix? {
        relationMatrices[name]
    }

    /// Get or create the identity relation
    public func identity() -> BooleanMatrix {
        if let cached = relationMatrices["iden"] {
            return cached
        }
        let iden = BooleanMatrix(constant: TupleSet(universe.identity()), universe: universe)
        relationMatrices["iden"] = iden
        return iden
    }

    /// Get a constant unary relation (set of atoms)
    public func constant(atoms: [Atom]) -> BooleanMatrix {
        BooleanMatrix(constant: TupleSet(atoms: atoms), universe: universe)
    }

    /// Get a constant relation from tuple set
    public func constant(tuples: TupleSet) -> BooleanMatrix {
        BooleanMatrix(constant: tuples, universe: universe)
    }

    // MARK: - Expression Encoding

    /// Encode union: a + b
    public func union(_ a: BooleanMatrix, _ b: BooleanMatrix) -> BooleanMatrix {
        a.union(b, cnf: cnf)
    }

    /// Encode intersection: a & b
    public func intersection(_ a: BooleanMatrix, _ b: BooleanMatrix) -> BooleanMatrix {
        a.intersection(b, cnf: cnf)
    }

    /// Encode difference: a - b
    public func difference(_ a: BooleanMatrix, _ b: BooleanMatrix) -> BooleanMatrix {
        a.difference(b, cnf: cnf)
    }

    /// Encode join: a.b
    public func join(_ a: BooleanMatrix, _ b: BooleanMatrix) -> BooleanMatrix {
        a.join(b, cnf: cnf)
    }

    /// Encode product: a -> b
    public func product(_ a: BooleanMatrix, _ b: BooleanMatrix) -> BooleanMatrix {
        a.product(b, cnf: cnf)
    }

    /// Encode transpose: ~a
    public func transpose(_ a: BooleanMatrix) -> BooleanMatrix {
        a.transpose()
    }

    /// Encode transitive closure: ^a
    public func transitiveClosure(_ a: BooleanMatrix) -> BooleanMatrix {
        a.transitiveClosure(cnf: cnf)
    }

    /// Encode reflexive transitive closure: *a
    public func reflexiveTransitiveClosure(_ a: BooleanMatrix) -> BooleanMatrix {
        a.reflexiveTransitiveClosure(cnf: cnf)
    }

    /// Encode domain restriction: s <: r
    public func domainRestriction(_ domain: BooleanMatrix, _ relation: BooleanMatrix) -> BooleanMatrix {
        // s <: r = s.r where s is unary
        join(domain, relation)
    }

    /// Encode range restriction: r :> s
    public func rangeRestriction(_ relation: BooleanMatrix, _ range: BooleanMatrix) -> BooleanMatrix {
        // r :> s = r.s where s is unary
        join(relation, range)
    }

    /// Encode override: a ++ b
    public func override(_ a: BooleanMatrix, _ b: BooleanMatrix) -> BooleanMatrix {
        // a ++ b = (a - dom(b) <: a) + b
        // = (dom(b) <: a) - part removed, then b added
        // Simpler: (a - (dom(b) -> univ)) + b for binary relations

        // First get domain of b
        let domB = b.join(constant(tuples: TupleSet(universe.allTuples(arity: 1))), cnf: cnf)

        // Then restrict a to exclude domain of b
        // a - (domB -> codomain)
        let restricted = a.difference(
            domB.product(constant(tuples: TupleSet(universe.allTuples(arity: 1))), cnf: cnf),
            cnf: cnf
        )

        // Union with b
        return restricted.union(b, cnf: cnf)
    }

    // MARK: - Formula Encoding

    /// Assert: a = b (relations are equal)
    public func assertEqual(_ a: BooleanMatrix, _ b: BooleanMatrix) {
        cnf.assertTrue(a.equals(b))
    }

    /// Assert: a in b (a is subset of b)
    public func assertSubset(_ a: BooleanMatrix, _ b: BooleanMatrix) {
        cnf.assertTrue(a.isSubset(of: b))
    }

    /// Assert: some a (a is non-empty)
    public func assertSome(_ a: BooleanMatrix) {
        cnf.assertTrue(a.isNonEmpty())
    }

    /// Assert: no a (a is empty)
    public func assertNo(_ a: BooleanMatrix) {
        cnf.assertTrue(a.isEmpty())
    }

    /// Assert: one a (a has exactly one element)
    public func assertOne(_ a: BooleanMatrix) {
        cnf.assertTrue(a.hasExactlyOne())
    }

    /// Assert: lone a (a has at most one element)
    public func assertLone(_ a: BooleanMatrix) {
        // At most one: for each pair, not both
        var formulas: [BooleanFormula] = []
        for i in 0..<a.count {
            for j in (i+1)..<a.count {
                let vi = BooleanFormula.from(a[i])
                let vj = BooleanFormula.from(a[j])
                formulas.append(.disjunction([vi.negated, vj.negated]))
            }
        }
        cnf.assertTrue(.conjunction(formulas))
    }

    /// Assert: a = b (formulas)
    public func assertFormula(_ formula: BooleanFormula) {
        cnf.assertTrue(formula)
    }

    // MARK: - Quantifier Encoding

    /// Encode: all x: S | F(x)
    /// Returns formula that is true iff F holds for all atoms in S
    public func forAll(
        over set: BooleanMatrix,
        body: (Atom) -> BooleanFormula
    ) -> BooleanFormula {
        precondition(set.arity == 1, "Quantifier domain must be unary")

        var conjuncts: [BooleanFormula] = []
        for atom in universe.atoms {
            let inSet = BooleanFormula.from(set[AtomTuple(atom)])
            let bodyFormula = body(atom)
            // atom in set => body(atom)
            conjuncts.append(inSet.implies(bodyFormula))
        }
        return .conjunction(conjuncts)
    }

    /// Encode: some x: S | F(x)
    /// Returns formula that is true iff F holds for some atom in S
    public func exists(
        over set: BooleanMatrix,
        body: (Atom) -> BooleanFormula
    ) -> BooleanFormula {
        precondition(set.arity == 1, "Quantifier domain must be unary")

        var disjuncts: [BooleanFormula] = []
        for atom in universe.atoms {
            let inSet = BooleanFormula.from(set[AtomTuple(atom)])
            let bodyFormula = body(atom)
            // atom in set & body(atom)
            disjuncts.append(inSet.and(bodyFormula))
        }
        return .disjunction(disjuncts)
    }

    /// Encode: no x: S | F(x) (equivalent to all x: S | !F(x))
    public func none(
        over set: BooleanMatrix,
        body: (Atom) -> BooleanFormula
    ) -> BooleanFormula {
        forAll(over: set) { atom in
            body(atom).negated
        }
    }

    /// Encode: one x: S | F(x)
    public func exactlyOne(
        over set: BooleanMatrix,
        body: (Atom) -> BooleanFormula
    ) -> BooleanFormula {
        // Exactly one = at least one AND at most one
        let atLeastOne = exists(over: set, body: body)

        // At most one: for each pair, not both satisfy
        var atMostOne: [BooleanFormula] = []
        for i in 0..<universe.atoms.count {
            for j in (i+1)..<universe.atoms.count {
                let ai = universe.atoms[i]
                let aj = universe.atoms[j]
                let inSetI = BooleanFormula.from(set[AtomTuple(ai)])
                let inSetJ = BooleanFormula.from(set[AtomTuple(aj)])
                let bodyI = body(ai)
                let bodyJ = body(aj)
                // Not both: ~(inSet[i] & body[i] & inSet[j] & body[j])
                atMostOne.append(.disjunction([
                    inSetI.negated, bodyI.negated,
                    inSetJ.negated, bodyJ.negated
                ]))
            }
        }

        return atLeastOne.and(.conjunction(atMostOne))
    }

    /// Encode: lone x: S | F(x) (at most one)
    public func atMostOne(
        over set: BooleanMatrix,
        body: (Atom) -> BooleanFormula
    ) -> BooleanFormula {
        var formulas: [BooleanFormula] = []
        for i in 0..<universe.atoms.count {
            for j in (i+1)..<universe.atoms.count {
                let ai = universe.atoms[i]
                let aj = universe.atoms[j]
                let inSetI = BooleanFormula.from(set[AtomTuple(ai)])
                let inSetJ = BooleanFormula.from(set[AtomTuple(aj)])
                let bodyI = body(ai)
                let bodyJ = body(aj)
                formulas.append(.disjunction([
                    inSetI.negated, bodyI.negated,
                    inSetJ.negated, bodyJ.negated
                ]))
            }
        }
        return .conjunction(formulas)
    }

    // MARK: - Solution Extraction

    /// Extract a tuple set from a matrix given a SAT solution
    public func extractTupleSet(from matrix: BooleanMatrix, solution: [Bool]) -> TupleSet {
        var tuples: [AtomTuple] = []
        for (i, tuple) in matrix.tuples.enumerated() {
            let value = matrix[i]
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

    /// Extract all relations from a SAT solution
    public func extractSolution(solution: [Bool]) -> [String: TupleSet] {
        var result: [String: TupleSet] = [:]
        for (name, matrix) in relationMatrices {
            result[name] = extractTupleSet(from: matrix, solution: solution)
        }
        return result
    }

    // MARK: - SAT Interface

    /// Get the number of SAT variables used
    public var variableCount: Int {
        Int(cnf.variableCount)
    }

    /// Get the number of clauses generated
    public var clauseCount: Int {
        cnf.allClauses.count
    }

    /// Get clauses for SAT solver (as array of int arrays)
    public var clauses: [[Int]] {
        cnf.allClauses.map { $0.map { Int($0) } }
    }

    /// Get DIMACS format string
    public var dimacs: String {
        cnf.toDIMACS()
    }
}

// MARK: - Instance

/// A satisfying instance extracted from SAT solution
public struct Instance: Sendable {
    /// The universe
    public let universe: Universe

    /// Relation assignments
    public let relations: [String: TupleSet]

    /// Get a relation by name
    public subscript(name: String) -> TupleSet? {
        relations[name]
    }
}

extension Instance: CustomStringConvertible {
    public var description: String {
        var result = "Instance {\n"
        for (name, tuples) in relations.sorted(by: { $0.key < $1.key }) {
            result += "  \(name) = \(tuples)\n"
        }
        result += "}"
        return result
    }
}
