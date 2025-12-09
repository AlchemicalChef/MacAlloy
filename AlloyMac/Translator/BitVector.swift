import Foundation

// MARK: - Bit Vector

/// A bit vector represents an integer using boolean values
/// Used for encoding integer arithmetic in SAT
/// LSB (least significant bit) is at index 0
public struct BitVector: Hashable, Sendable {
    /// The bits of this vector (LSB at index 0)
    public let bits: [BooleanValue]

    /// Number of bits
    public var bitWidth: Int { bits.count }

    // MARK: - Initialization

    /// Create a bit vector from boolean values
    public init(bits: [BooleanValue]) {
        precondition(!bits.isEmpty, "BitVector cannot be empty")
        self.bits = bits
    }

    /// Create a constant bit vector from an integer value
    /// Uses two's complement representation
    /// - Parameters:
    ///   - value: The integer value
    ///   - bitWidth: Number of bits
    public static func constant(_ value: Int, bitWidth: Int) -> BitVector {
        precondition(bitWidth > 0, "Bit width must be positive")

        // Two's complement encoding
        let unsigned = UInt(bitPattern: value) & UInt((1 << bitWidth) - 1)

        var bits: [BooleanValue] = []
        for i in 0..<bitWidth {
            let bit = (unsigned >> i) & 1 == 1
            bits.append(.constant(bit))
        }

        return BitVector(bits: bits)
    }

    /// Create a fresh bit vector with new SAT variables
    /// - Parameters:
    ///   - bitWidth: Number of bits
    ///   - cnf: The CNF builder to allocate variables from
    public static func fresh(bitWidth: Int, cnf: CNFBuilder) -> BitVector {
        precondition(bitWidth > 0, "Bit width must be positive")

        var bits: [BooleanValue] = []
        for _ in 0..<bitWidth {
            let variable = cnf.freshVariable()
            bits.append(.variable(variable))
        }

        return BitVector(bits: bits)
    }

    // MARK: - Accessors

    /// Get bit at index (0 = LSB)
    public subscript(index: Int) -> BooleanValue {
        bits[index]
    }

    /// Whether this is a constant (all bits are constants)
    public var isConstant: Bool {
        bits.allSatisfy { $0.isConstant }
    }

    /// Get the constant value if this is a constant bit vector
    /// Uses two's complement interpretation
    public func constantValue() -> Int? {
        guard isConstant else { return nil }

        var unsigned: UInt = 0
        for (i, bit) in bits.enumerated() {
            if let val = bit.constantValue, val {
                unsigned |= UInt(1 << i)
            }
        }

        // Sign extend if necessary (two's complement)
        if let signBit = bits.last?.constantValue, signBit {
            let signExtension = ~UInt((1 << bitWidth) - 1)
            unsigned |= signExtension
        }

        return Int(bitPattern: unsigned)
    }

    // MARK: - Bit Operations

    /// Get the sign bit (MSB)
    public var signBit: BooleanValue {
        bits[bitWidth - 1]
    }

    /// Negate this bit vector (logical NOT of each bit)
    /// Note: This is bitwise NOT, not arithmetic negation
    public var bitwiseNot: BitVector {
        BitVector(bits: bits.map(\.negated))
    }

    /// Zero-extend to a larger bit width
    public func zeroExtend(to newWidth: Int) -> BitVector {
        precondition(newWidth >= bitWidth, "Cannot zero-extend to smaller width")
        if newWidth == bitWidth { return self }

        var newBits = bits
        for _ in bitWidth..<newWidth {
            newBits.append(.constant(false))
        }
        return BitVector(bits: newBits)
    }

    /// Sign-extend to a larger bit width
    public func signExtend(to newWidth: Int) -> BitVector {
        precondition(newWidth >= bitWidth, "Cannot sign-extend to smaller width")
        if newWidth == bitWidth { return self }

        var newBits = bits
        let signBit = self.signBit
        for _ in bitWidth..<newWidth {
            newBits.append(signBit)
        }
        return BitVector(bits: newBits)
    }

    /// Truncate to a smaller bit width
    public func truncate(to newWidth: Int) -> BitVector {
        precondition(newWidth > 0 && newWidth <= bitWidth, "Invalid truncation width")
        if newWidth == bitWidth { return self }
        return BitVector(bits: Array(bits.prefix(newWidth)))
    }
}

// MARK: - Bit Vector Description

extension BitVector: CustomStringConvertible {
    public var description: String {
        if let value = constantValue() {
            return "BitVector(\(value), width: \(bitWidth))"
        }
        return "BitVector[\(bits.reversed().map(\.description).joined(separator: ""))]"
    }
}

// MARK: - Common Constants

extension BitVector {
    /// Zero constant of given bit width
    public static func zero(bitWidth: Int) -> BitVector {
        .constant(0, bitWidth: bitWidth)
    }

    /// One constant of given bit width
    public static func one(bitWidth: Int) -> BitVector {
        .constant(1, bitWidth: bitWidth)
    }

    /// All ones (which is -1 in two's complement)
    public static func allOnes(bitWidth: Int) -> BitVector {
        .constant(-1, bitWidth: bitWidth)
    }

    /// Minimum signed value for given bit width
    public static func minSigned(bitWidth: Int) -> BitVector {
        .constant(-(1 << (bitWidth - 1)), bitWidth: bitWidth)
    }

    /// Maximum signed value for given bit width
    public static func maxSigned(bitWidth: Int) -> BitVector {
        .constant((1 << (bitWidth - 1)) - 1, bitWidth: bitWidth)
    }
}
