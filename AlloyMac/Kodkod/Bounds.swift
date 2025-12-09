import Foundation

// MARK: - Relation Bounds

/// Bounds define the possible values for a relation
/// Lower bound = tuples that MUST be in the relation
/// Upper bound = tuples that MAY be in the relation
/// The actual relation value is: lower <= value <= upper
public struct RelationBounds: Hashable, Sendable {
    /// The name of this relation
    public let name: String

    /// Tuples that must be in the relation
    public let lower: TupleSet

    /// Tuples that may be in the relation
    public let upper: TupleSet

    /// Arity of the relation
    public var arity: Int { upper.arity }

    /// Create bounds with explicit lower and upper
    public init(name: String, lower: TupleSet, upper: TupleSet) {
        precondition(lower.isEmpty || upper.isEmpty || lower.arity == upper.arity,
                    "Lower and upper bounds must have same arity")
        precondition(lower.isSubset(of: upper),
                    "Lower bound must be subset of upper bound")
        self.name = name
        self.lower = lower
        self.upper = upper
    }

    /// Create exact bounds (lower == upper, relation is constant)
    public init(name: String, exact: TupleSet) {
        self.name = name
        self.lower = exact
        self.upper = exact
    }

    /// Create bounds with empty lower and given upper
    public init(name: String, upper: TupleSet) {
        self.name = name
        self.lower = TupleSet(arity: upper.arity)
        self.upper = upper
    }

    /// Whether this relation is a constant (lower == upper)
    public var isConstant: Bool {
        lower == upper
    }

    /// Tuples that are "free" - may or may not be in relation
    public var free: TupleSet {
        upper.difference(lower)
    }

    /// Number of free tuples (SAT variables needed)
    public var freeCount: Int {
        free.count
    }
}

extension RelationBounds: CustomStringConvertible {
    public var description: String {
        if isConstant {
            return "\(name) = \(lower)"
        }
        return "\(name): \(lower) <= x <= \(upper)"
    }
}

// MARK: - Bounds Collection

/// Collection of bounds for all relations in a problem
public final class Bounds: @unchecked Sendable {
    /// The universe
    public let universe: Universe

    /// Bounds for each relation, keyed by name
    private var relationBounds: [String: RelationBounds] = [:]

    /// Order of relations (for consistent iteration)
    private var relationOrder: [String] = []

    public init(universe: Universe) {
        self.universe = universe
    }

    /// Add bounds for a relation
    public func bound(_ name: String, lower: TupleSet, upper: TupleSet) {
        let bounds = RelationBounds(name: name, lower: lower, upper: upper)
        addBounds(bounds)
    }

    /// Add exact bounds for a relation
    public func boundExact(_ name: String, exact: TupleSet) {
        let bounds = RelationBounds(name: name, exact: exact)
        addBounds(bounds)
    }

    /// Add bounds with empty lower
    public func bound(_ name: String, upper: TupleSet) {
        let bounds = RelationBounds(name: name, upper: upper)
        addBounds(bounds)
    }

    /// Add bounds for unary relation (set) from atoms
    public func boundUnary(_ name: String, lower: [Atom], upper: [Atom]) {
        bound(name,
              lower: TupleSet(atoms: lower),
              upper: TupleSet(atoms: upper))
    }

    /// Add exact unary relation
    public func boundUnaryExact(_ name: String, atoms: [Atom]) {
        boundExact(name, exact: TupleSet(atoms: atoms))
    }

    private func addBounds(_ bounds: RelationBounds) {
        if relationBounds[bounds.name] == nil {
            relationOrder.append(bounds.name)
        }
        relationBounds[bounds.name] = bounds
    }

    /// Get bounds for a relation
    public subscript(name: String) -> RelationBounds? {
        relationBounds[name]
    }

    /// All relation names in order
    public var relationNames: [String] {
        relationOrder
    }

    /// All bounds in order
    public var allBounds: [RelationBounds] {
        relationOrder.compactMap { relationBounds[$0] }
    }

    /// Total number of free tuples across all relations
    public var totalFreeCount: Int {
        allBounds.reduce(0) { $0 + $1.freeCount }
    }

    /// Check if bounds are satisfiable (lower <= upper for all)
    public var isSatisfiable: Bool {
        allBounds.allSatisfy { $0.lower.isSubset(of: $0.upper) }
    }
}

extension Bounds: CustomStringConvertible {
    public var description: String {
        var result = "Bounds {\n"
        result += "  universe: \(universe)\n"
        for bounds in allBounds {
            result += "  \(bounds)\n"
        }
        result += "}"
        return result
    }
}

// MARK: - Bounds Builder

/// Fluent builder for creating bounds
public final class BoundsBuilder {
    private let universe: Universe
    private let bounds: Bounds

    public init(universe: Universe) {
        self.universe = universe
        self.bounds = Bounds(universe: universe)
    }

    /// Add bounds for a binary relation over all atoms
    @discardableResult
    public func binary(_ name: String, lower: [(Int, Int)] = [], upper: [(Int, Int)]? = nil) -> Self {
        let lowerTuples = lower.map { AtomTuple(universe[$0.0], universe[$0.1]) }
        let upperTuples: [AtomTuple]
        if let upper = upper {
            upperTuples = upper.map { AtomTuple(universe[$0.0], universe[$0.1]) }
        } else {
            upperTuples = universe.allTuples(arity: 2)
        }
        bounds.bound(name, lower: TupleSet(lowerTuples), upper: TupleSet(upperTuples))
        return self
    }

    /// Add bounds for a unary relation
    @discardableResult
    public func unary(_ name: String, lower: [Int] = [], upper: [Int]? = nil) -> Self {
        let lowerAtoms = lower.map { universe[$0] }
        let upperAtoms: [Atom]
        if let upper = upper {
            upperAtoms = upper.map { universe[$0] }
        } else {
            upperAtoms = Array(universe.atoms)
        }
        bounds.boundUnary(name, lower: lowerAtoms, upper: upperAtoms)
        return self
    }

    /// Add exact unary relation
    @discardableResult
    public func unaryExact(_ name: String, atoms: [Int]) -> Self {
        bounds.boundUnaryExact(name, atoms: atoms.map { universe[$0] })
        return self
    }

    /// Add exact binary relation
    @discardableResult
    public func binaryExact(_ name: String, tuples: [(Int, Int)]) -> Self {
        let ts = tuples.map { AtomTuple(universe[$0.0], universe[$0.1]) }
        bounds.boundExact(name, exact: TupleSet(ts))
        return self
    }

    /// Build the bounds
    public func build() -> Bounds {
        bounds
    }
}
