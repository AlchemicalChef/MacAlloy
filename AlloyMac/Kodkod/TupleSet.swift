import Foundation

// MARK: - Tuple Set

/// A set of tuples with uniform arity
/// Used for representing concrete relation values
public struct TupleSet: Hashable, Sendable {
    /// The tuples in this set
    private var tuples: Set<AtomTuple>

    /// The arity of all tuples (0 if empty)
    public let arity: Int

    /// Create an empty tuple set with given arity
    public init(arity: Int) {
        self.tuples = []
        self.arity = arity
    }

    /// Create from a collection of tuples
    public init<C: Collection>(_ tuples: C) where C.Element == AtomTuple {
        if let first = tuples.first {
            self.arity = first.arity
            self.tuples = Set(tuples)
            // Verify uniform arity
            precondition(self.tuples.allSatisfy { $0.arity == self.arity },
                        "All tuples must have same arity")
        } else {
            self.arity = 0
            self.tuples = []
        }
    }

    /// Create a unary tuple set from atoms
    public init(atoms: [Atom]) {
        self.arity = 1
        self.tuples = Set(atoms.map { AtomTuple($0) })
    }

    // MARK: - Basic Properties

    /// Number of tuples
    public var count: Int { tuples.count }

    /// Whether empty
    public var isEmpty: Bool { tuples.isEmpty }

    /// Check membership
    public func contains(_ tuple: AtomTuple) -> Bool {
        tuples.contains(tuple)
    }

    /// Get all tuples as array (sorted)
    public var sortedTuples: [AtomTuple] {
        tuples.sorted()
    }

    /// Iterate over tuples
    public func forEach(_ body: (AtomTuple) -> Void) {
        tuples.forEach(body)
    }

    // MARK: - Set Operations

    /// Union of two tuple sets
    public func union(_ other: TupleSet) -> TupleSet {
        if isEmpty { return other }
        if other.isEmpty { return self }
        precondition(arity == other.arity, "Cannot union tuple sets of different arity")
        return TupleSet(tuples.union(other.tuples))
    }

    /// Intersection of two tuple sets
    public func intersection(_ other: TupleSet) -> TupleSet {
        precondition(arity == other.arity, "Cannot intersect tuple sets of different arity")
        if isEmpty || other.isEmpty {
            return TupleSet(arity: arity)
        }
        return TupleSet(tuples.intersection(other.tuples))
    }

    /// Difference of two tuple sets
    public func difference(_ other: TupleSet) -> TupleSet {
        precondition(arity == other.arity, "Cannot subtract tuple sets of different arity")
        if isEmpty { return self }
        if other.isEmpty { return self }
        return TupleSet(tuples.subtracting(other.tuples))
    }

    /// Check if subset
    public func isSubset(of other: TupleSet) -> Bool {
        if isEmpty { return true }
        if other.isEmpty { return false }
        precondition(arity == other.arity, "Cannot compare tuple sets of different arity")
        return tuples.isSubset(of: other.tuples)
    }

    // MARK: - Relational Operations

    /// Cartesian product: r x s = {(a1,...,an,b1,...,bm) | (a1,...,an) in r, (b1,...,bm) in s}
    public func product(_ other: TupleSet) -> TupleSet {
        if isEmpty || other.isEmpty {
            return TupleSet(arity: arity + other.arity)
        }

        var result: [AtomTuple] = []
        for t1 in tuples {
            for t2 in other.tuples {
                result.append(t1.product(with: t2))
            }
        }
        return TupleSet(result)
    }

    /// Relational join: r.s = {(a1,...,an-1,b2,...,bm) | (a1,...,an) in r, (b1,...,bm) in s, an = b1}
    public func join(_ other: TupleSet) -> TupleSet {
        if isEmpty || other.isEmpty {
            let newArity = Swift.max(0, arity + other.arity - 2)
            return TupleSet(arity: newArity)
        }

        var result: [AtomTuple] = []
        for t1 in tuples {
            for t2 in other.tuples {
                if let joined = t1.join(with: t2) {
                    result.append(joined)
                }
            }
        }

        // Handle case where join produces scalars (empty tuples)
        if result.isEmpty && arity >= 1 && other.arity >= 1 {
            return TupleSet(arity: Swift.max(0, arity + other.arity - 2))
        }

        return TupleSet(result)
    }

    /// Transpose (reverse all tuples)
    public func transposed() -> TupleSet {
        TupleSet(tuples.map { $0.transposed() })
    }

    /// Domain restriction: s <: r = {t in r | t[0] in s}
    public func domainRestriction(by domain: TupleSet) -> TupleSet {
        precondition(domain.arity == 1, "Domain must be unary")
        if isEmpty || domain.isEmpty { return TupleSet(arity: arity) }

        let domainAtoms = Set(domain.tuples.map { $0.first })
        return TupleSet(tuples.filter { domainAtoms.contains($0.first) })
    }

    /// Range restriction: r :> s = {t in r | t[arity-1] in s}
    public func rangeRestriction(by range: TupleSet) -> TupleSet {
        precondition(range.arity == 1, "Range must be unary")
        if isEmpty || range.isEmpty { return TupleSet(arity: arity) }

        let rangeAtoms = Set(range.tuples.map { $0.first })
        return TupleSet(tuples.filter { rangeAtoms.contains($0.last) })
    }

    /// Override: r ++ s = (r - dom(s) <: r) + s
    public func override(_ other: TupleSet) -> TupleSet {
        precondition(arity == other.arity, "Cannot override relations of different arity")
        if isEmpty { return other }
        if other.isEmpty { return self }

        // Get domain of other
        let otherDomain = Set(other.tuples.map { $0.first })

        // Remove tuples from self whose first element is in other's domain
        let filtered = tuples.filter { !otherDomain.contains($0.first) }

        // Union with other
        return TupleSet(filtered.union(other.tuples))
    }

    /// Transitive closure
    public func transitiveClosure() -> TupleSet {
        precondition(arity == 2, "Transitive closure requires binary relation")
        if isEmpty { return self }

        var result = self
        var prev = TupleSet(arity: 2)

        // Collect unique atoms to determine max iterations
        // The longest chain is at most the number of unique atoms
        var atoms = Set<Atom>()
        for tuple in tuples {
            atoms.insert(tuple.first)
            if tuple.arity > 1 {
                atoms.insert(tuple.atoms[1])
            }
        }
        let maxIterations = Swift.max(atoms.count, 1)

        // Fixed point iteration with safety limit
        var iteration = 0
        while result != prev && iteration < maxIterations {
            prev = result
            result = result.union(result.join(self))
            iteration += 1
        }

        return result
    }

    /// Reflexive transitive closure (includes identity)
    public func reflexiveTransitiveClosure(universe: Universe) -> TupleSet {
        let identity = TupleSet(universe.identity())
        return transitiveClosure().union(identity)
    }

    // MARK: - Projection

    /// Project onto specified columns
    public func project(_ columns: [Int]) -> TupleSet {
        if isEmpty { return TupleSet(arity: columns.count) }
        return TupleSet(tuples.map { $0.project(columns) })
    }

    /// Domain projection: {t[0] | t in r}
    public var domain: TupleSet {
        project([0])
    }

    /// Range projection: {t[arity-1] | t in r}
    public var range: TupleSet {
        guard arity > 0 else { return TupleSet(arity: 1) }
        return project([arity - 1])
    }

    // MARK: - Mutating Operations

    /// Insert a tuple
    public mutating func insert(_ tuple: AtomTuple) {
        precondition(tuple.arity == arity || isEmpty, "Tuple arity mismatch")
        tuples.insert(tuple)
    }

    /// Remove a tuple
    public mutating func remove(_ tuple: AtomTuple) {
        tuples.remove(tuple)
    }
}

extension TupleSet: CustomStringConvertible {
    public var description: String {
        if isEmpty { return "{}" }
        return "{\(sortedTuples.map(\.description).joined(separator: ", "))}"
    }
}

extension TupleSet: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: AtomTuple...) {
        self.init(elements)
    }
}

// MARK: - Sequence Conformance

extension TupleSet: Sequence {
    public func makeIterator() -> Set<AtomTuple>.Iterator {
        tuples.makeIterator()
    }
}
