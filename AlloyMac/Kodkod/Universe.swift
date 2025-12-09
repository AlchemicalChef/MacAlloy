import Foundation

// MARK: - Atom

/// An atom is a primitive element in the universe
/// Each atom has a unique index and a name for display
public struct Atom: Hashable, Sendable {
    /// Unique index within the universe (0-indexed)
    public let index: Int

    /// Display name for the atom
    public let name: String

    public init(index: Int, name: String) {
        self.index = index
        self.name = name
    }
}

extension Atom: CustomStringConvertible {
    public var description: String { name }
}

extension Atom: Comparable {
    public static func < (lhs: Atom, rhs: Atom) -> Bool {
        lhs.index < rhs.index
    }
}

// MARK: - Tuple

/// A tuple is an ordered sequence of atoms
/// Arity 1 = unary relation (set), Arity 2 = binary relation, etc.
public struct AtomTuple: Hashable, Sendable {
    /// The atoms in this tuple, in order
    public let atoms: [Atom]

    /// Arity (number of columns)
    public var arity: Int { atoms.count }

    public init(_ atoms: [Atom]) {
        precondition(!atoms.isEmpty, "Tuple cannot be empty")
        self.atoms = atoms
    }

    public init(_ atoms: Atom...) {
        self.init(atoms)
    }

    /// Get atom at index
    public subscript(index: Int) -> Atom {
        atoms[index]
    }

    /// First atom (for unary/binary relations)
    public var first: Atom { atoms[0] }

    /// Second atom (for binary+ relations)
    public var second: Atom {
        precondition(arity >= 2, "Tuple must have arity >= 2")
        return atoms[1]
    }

    /// Last atom
    public var last: Atom { atoms[atoms.count - 1] }

    /// Create product of two tuples: (a, b) x (c, d) = (a, b, c, d)
    public func product(with other: AtomTuple) -> AtomTuple {
        AtomTuple(atoms + other.atoms)
    }

    /// Join two tuples if last of self equals first of other
    /// Returns (a1, ..., an-1, b2, ..., bm) if an == b1, else nil
    public func join(with other: AtomTuple) -> AtomTuple? {
        guard last == other.first else { return nil }
        if atoms.count == 1 && other.atoms.count == 1 {
            return nil // Join of two unary tuples with same element is empty
        }
        var result = Array(atoms.dropLast())
        result.append(contentsOf: other.atoms.dropFirst())
        guard !result.isEmpty else { return nil }
        return AtomTuple(result)
    }

    /// Transpose (reverse) this tuple
    public func transposed() -> AtomTuple {
        AtomTuple(atoms.reversed())
    }

    /// Project onto specified columns (0-indexed)
    public func project(_ columns: [Int]) -> AtomTuple {
        precondition(columns.allSatisfy { $0 >= 0 && $0 < arity }, "Invalid column index")
        return AtomTuple(columns.map { atoms[$0] })
    }
}

extension AtomTuple: CustomStringConvertible {
    public var description: String {
        if atoms.count == 1 {
            return atoms[0].description
        }
        return "(\(atoms.map(\.description).joined(separator: ", ")))"
    }
}

extension AtomTuple: Comparable {
    public static func < (lhs: AtomTuple, rhs: AtomTuple) -> Bool {
        // Lexicographic comparison
        for (a, b) in zip(lhs.atoms, rhs.atoms) {
            if a < b { return true }
            if a > b { return false }
        }
        return lhs.arity < rhs.arity
    }
}

// MARK: - Universe

/// The universe defines all possible atoms
/// All relations are over subsets of the universe
public final class Universe: Sendable {
    /// All atoms in the universe
    public let atoms: [Atom]

    /// Map from atom name to atom
    private let nameToAtom: [String: Atom]

    /// Number of atoms
    public var size: Int { atoms.count }

    /// Create a universe with the given atom names
    public init(atomNames: [String]) {
        var atoms: [Atom] = []
        var nameToAtom: [String: Atom] = [:]

        for (index, name) in atomNames.enumerated() {
            let atom = Atom(index: index, name: name)
            atoms.append(atom)
            nameToAtom[name] = atom
        }

        self.atoms = atoms
        self.nameToAtom = nameToAtom
    }

    /// Create a universe with numbered atoms
    public convenience init(size: Int, prefix: String = "A") {
        let names = (0..<size).map { "\(prefix)\($0)" }
        self.init(atomNames: names)
    }

    /// Get atom by index
    public subscript(index: Int) -> Atom {
        atoms[index]
    }

    /// Get atom by name
    public func atom(named name: String) -> Atom? {
        nameToAtom[name]
    }

    /// Check if atom is in universe
    public func contains(_ atom: Atom) -> Bool {
        atom.index >= 0 && atom.index < atoms.count && atoms[atom.index] == atom
    }

    /// Generate all possible tuples of given arity
    public func allTuples(arity: Int) -> [AtomTuple] {
        guard arity > 0 else { return [] }

        if arity == 1 {
            return atoms.map { AtomTuple($0) }
        }

        // Generate Cartesian product
        var result: [[Atom]] = [[]]
        for _ in 0..<arity {
            var newResult: [[Atom]] = []
            for prefix in result {
                for atom in atoms {
                    newResult.append(prefix + [atom])
                }
            }
            result = newResult
        }

        return result.map { AtomTuple($0) }
    }

    /// Identity relation: {(a, a) | a in universe}
    public func identity() -> [AtomTuple] {
        atoms.map { AtomTuple($0, $0) }
    }
}

extension Universe: CustomStringConvertible {
    public var description: String {
        "Universe[\(atoms.map(\.name).joined(separator: ", "))]"
    }
}

// MARK: - Factory for Atoms by Signature

/// Factory for creating atoms grouped by signature
public final class AtomFactory {
    private var nextIndex: Int = 0
    private var atoms: [Atom] = []
    private var sigAtoms: [String: [Atom]] = [:]

    public init() {}

    /// Create atoms for a signature
    public func createAtoms(for sigName: String, count: Int) -> [Atom] {
        var created: [Atom] = []
        for i in 0..<count {
            let name = "\(sigName)$\(i)"
            let atom = Atom(index: nextIndex, name: name)
            nextIndex += 1
            atoms.append(atom)
            created.append(atom)
        }
        sigAtoms[sigName] = created
        return created
    }

    /// Get atoms for a signature
    public func atoms(for sigName: String) -> [Atom] {
        sigAtoms[sigName] ?? []
    }

    /// Build universe from all created atoms
    public func buildUniverse() -> Universe {
        Universe(atomNames: atoms.map(\.name))
    }

    /// Get all atoms created so far
    public var allAtoms: [Atom] { atoms }
}
