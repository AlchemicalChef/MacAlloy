import Foundation

// MARK: - Integer Atom Factory

/// Factory for creating integer atoms for bounded integer support
/// Uses two's complement representation with configurable bit width
public final class IntegerAtomFactory: Sendable {
    /// Number of bits for integer representation
    public let bitWidth: Int

    /// Minimum representable value (e.g., -8 for 4-bit)
    public let minValue: Int

    /// Maximum representable value (e.g., 7 for 4-bit)
    public let maxValue: Int

    /// Number of integer values (2^bitWidth)
    public let count: Int

    /// The integer atoms, indexed by (value - minValue)
    public let atoms: [Atom]

    /// Map from integer value to atom
    private let valueToAtom: [Int: Atom]

    /// Map from atom index to integer value
    private let atomIndexToValue: [Int: Int]

    /// Starting index in the universe for integer atoms
    public let startingIndex: Int

    // MARK: - Initialization

    /// Create an integer atom factory
    /// - Parameters:
    ///   - bitWidth: Number of bits (default 4 for range -8 to 7)
    ///   - startingIndex: Starting atom index in the universe
    public init(bitWidth: Int = 4, startingIndex: Int) {
        precondition(bitWidth > 0 && bitWidth <= 16, "Bit width must be 1-16")

        self.bitWidth = bitWidth
        self.startingIndex = startingIndex
        self.count = 1 << bitWidth  // 2^bitWidth

        // Two's complement range
        self.minValue = -(1 << (bitWidth - 1))      // -2^(n-1)
        self.maxValue = (1 << (bitWidth - 1)) - 1   // 2^(n-1) - 1

        // Create atoms for each integer value
        var atoms: [Atom] = []
        var valueToAtom: [Int: Atom] = [:]
        var atomIndexToValue: [Int: Int] = [:]

        for value in minValue...maxValue {
            let atomIndex = startingIndex + (value - minValue)
            let atom = Atom(index: atomIndex, name: "Int$\(value)")
            atoms.append(atom)
            valueToAtom[value] = atom
            atomIndexToValue[atomIndex] = value
        }

        self.atoms = atoms
        self.valueToAtom = valueToAtom
        self.atomIndexToValue = atomIndexToValue
    }

    // MARK: - Atom Access

    /// Get the atom representing an integer value
    /// - Parameter value: The integer value
    /// - Returns: The atom, or nil if value is out of range
    public func atom(for value: Int) -> Atom? {
        valueToAtom[value]
    }

    /// Get the integer value for an atom
    /// - Parameter atom: The atom
    /// - Returns: The integer value, or nil if atom is not an integer atom
    public func value(for atom: Atom) -> Int? {
        atomIndexToValue[atom.index]
    }

    /// Check if an atom is an integer atom
    public func isIntegerAtom(_ atom: Atom) -> Bool {
        atomIndexToValue[atom.index] != nil
    }

    /// Get the atom at a specific offset (0 = minValue)
    public subscript(offset: Int) -> Atom {
        precondition(offset >= 0 && offset < count, "Offset out of range")
        return atoms[offset]
    }

    // MARK: - Bit Operations

    /// Convert an integer value to its bit representation
    /// - Parameter value: The integer value (must be in range)
    /// - Returns: Array of bits, LSB at index 0
    public func toBits(_ value: Int) -> [Bool] {
        precondition(value >= minValue && value <= maxValue, "Value out of range")

        // Two's complement: for negative numbers, this naturally works
        // because Swift uses two's complement internally
        let unsigned = UInt(bitPattern: value) & UInt((1 << bitWidth) - 1)

        var bits: [Bool] = []
        for i in 0..<bitWidth {
            bits.append((unsigned >> i) & 1 == 1)
        }
        return bits
    }

    /// Convert bits back to an integer value
    /// - Parameter bits: Array of bits, LSB at index 0
    /// - Returns: The signed integer value
    public func fromBits(_ bits: [Bool]) -> Int {
        precondition(bits.count == bitWidth, "Wrong number of bits")

        var unsigned: UInt = 0
        for (i, bit) in bits.enumerated() {
            if bit {
                unsigned |= UInt(1 << i)
            }
        }

        // Sign extend if necessary
        if bits[bitWidth - 1] {  // Sign bit is set
            // Extend sign bit for Swift's Int
            let signExtension = ~UInt((1 << bitWidth) - 1)
            unsigned |= signExtension
        }

        return Int(bitPattern: unsigned)
    }

    // MARK: - Universe Integration

    /// Get all atom names for adding to universe
    public var atomNames: [String] {
        atoms.map(\.name)
    }

    /// Create atoms starting from a given index (for fresh universe creation)
    /// Returns the atoms that should be added to the universe
    public static func createIntegerAtoms(
        bitWidth: Int = 4,
        startingIndex: Int
    ) -> (atoms: [Atom], factory: IntegerAtomFactory) {
        let factory = IntegerAtomFactory(bitWidth: bitWidth, startingIndex: startingIndex)
        return (factory.atoms, factory)
    }
}

// MARK: - Integer Atom Factory Description

extension IntegerAtomFactory: CustomStringConvertible {
    public var description: String {
        "IntegerAtomFactory(bitWidth: \(bitWidth), range: \(minValue)...\(maxValue))"
    }
}
