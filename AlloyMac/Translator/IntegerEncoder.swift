import Foundation

// MARK: - Integer Encoder

/// Encodes integer expressions using bit-vector arithmetic
/// Bridges between Alloy expressions (as matrices) and SAT encoding (as bit-vectors)
public final class IntegerEncoder {
    /// The translation context
    public let context: TranslationContext

    /// Integer arithmetic operations
    public var arithmetic: IntegerArithmetic? { context.integerArithmetic }

    /// Integer atom factory
    public var intFactory: IntegerAtomFactory? { context.integerFactory }

    /// CNF builder shorthand
    public var cnf: CNFBuilder { context.cnf }

    /// Universe shorthand
    public var universe: Universe { context.universe }

    /// Bit width
    public var bitWidth: Int { context.integerBitWidth }

    /// Create an integer encoder
    public init(context: TranslationContext) {
        self.context = context
    }

    // MARK: - Matrix to BitVector Conversion

    /// Convert a unary matrix (set of integer atoms) to a bit vector
    /// The matrix should represent exactly one integer atom
    /// Returns a fresh bit vector constrained to equal the integer value
    public func matrixToBitVector(_ matrix: BooleanMatrix) -> BitVector? {
        guard matrix.arity == 1, let factory = intFactory, let arith = arithmetic else {
            return nil
        }

        // Create a fresh bit vector for the result
        let result = BitVector.fresh(bitWidth: bitWidth, cnf: cnf)

        // For each possible integer atom, if it's in the matrix, constrain result to equal that value
        // This implements: result = ITE(matrix contains Int$n, n, result of other cases...)
        for intValue in factory.minValue...factory.maxValue {
            guard let atom = factory.atom(for: intValue) else { continue }
            let inMatrix = matrix[AtomTuple(atom)]

            // If this atom is in the matrix, result must equal this value
            let constant = BitVector.constant(intValue, bitWidth: bitWidth)
            let equality = arith.equals(result, constant)

            // inMatrix => equality
            cnf.assertTrue(BooleanFormula.from(inMatrix).implies(equality))
        }

        return result
    }

    /// Convert a bit vector back to a matrix (set containing the integer atom for the value)
    public func bitVectorToMatrix(_ bv: BitVector) -> BooleanMatrix {
        guard let factory = intFactory else {
            return context.emptyMatrix(arity: 1)
        }

        var matrix = BooleanMatrix(universe: universe, arity: 1)

        // For each possible integer value, the atom is in the result iff bv equals that value
        for intValue in factory.minValue...factory.maxValue {
            guard let atom = factory.atom(for: intValue),
                  let arith = arithmetic else { continue }

            let constant = BitVector.constant(intValue, bitWidth: bitWidth)
            let equality = arith.equals(bv, constant)

            // Convert equality formula to a boolean value
            let v = cnf.encode(equality)
            matrix[AtomTuple(atom)] = .variable(v)
        }

        return matrix
    }

    // MARK: - Integer Literal Encoding

    /// Encode an integer literal as a matrix
    public func encodeIntegerLiteral(_ value: Int) -> BooleanMatrix {
        guard let factory = intFactory else {
            return context.emptyMatrix(arity: 1)
        }

        // Clamp to valid range
        let clampedValue = min(max(value, factory.minValue), factory.maxValue)

        guard let atom = factory.atom(for: clampedValue) else {
            return context.emptyMatrix(arity: 1)
        }

        return context.atomMatrix(atom)
    }

    // MARK: - Arithmetic Operations

    /// Encode addition: plus[a, b]
    public func encodePlus(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic,
              let leftBV = matrixToBitVector(leftMatrix),
              let rightBV = matrixToBitVector(rightMatrix) else {
            return context.emptyMatrix(arity: 1)
        }

        let result = arith.add(leftBV, rightBV)
        return bitVectorToMatrix(result)
    }

    /// Encode subtraction: minus[a, b]
    public func encodeMinus(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic,
              let leftBV = matrixToBitVector(leftMatrix),
              let rightBV = matrixToBitVector(rightMatrix) else {
            return context.emptyMatrix(arity: 1)
        }

        let result = arith.subtract(leftBV, rightBV)
        return bitVectorToMatrix(result)
    }

    /// Encode multiplication: mul[a, b]
    public func encodeMul(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic,
              let leftBV = matrixToBitVector(leftMatrix),
              let rightBV = matrixToBitVector(rightMatrix) else {
            return context.emptyMatrix(arity: 1)
        }

        let result = arith.multiply(leftBV, rightBV)
        return bitVectorToMatrix(result)
    }

    /// Encode division: div[a, b]
    public func encodeDiv(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic,
              let leftBV = matrixToBitVector(leftMatrix),
              let rightBV = matrixToBitVector(rightMatrix) else {
            return context.emptyMatrix(arity: 1)
        }

        let (quotient, _) = arith.divRem(leftBV, rightBV)
        return bitVectorToMatrix(quotient)
    }

    /// Encode remainder: rem[a, b]
    public func encodeRem(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic,
              let leftBV = matrixToBitVector(leftMatrix),
              let rightBV = matrixToBitVector(rightMatrix) else {
            return context.emptyMatrix(arity: 1)
        }

        let (_, remainder) = arith.divRem(leftBV, rightBV)
        return bitVectorToMatrix(remainder)
    }

    /// Encode unary negation: -a
    public func encodeNegate(_ operandMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic,
              let operandBV = matrixToBitVector(operandMatrix) else {
            return context.emptyMatrix(arity: 1)
        }

        let result = arith.negate(operandBV)
        return bitVectorToMatrix(result)
    }

    // MARK: - Cardinality

    /// Encode cardinality: #set
    /// Returns a matrix representing the integer count of elements in the set
    public func encodeCardinality(_ setMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic else {
            return context.emptyMatrix(arity: 1)
        }

        // Collect membership values for all atoms in a unary set
        var membershipValues: [BooleanValue] = []
        if setMatrix.arity == 1 {
            // Unary relation - count atoms
            for atom in universe.atoms {
                let tuple = AtomTuple(atom)
                let value = setMatrix[tuple]
                // Include all values (even false ones contribute to the cardinality count)
                membershipValues.append(value)
            }
        } else {
            // Higher arity - count all tuples in the relation
            for tuple in setMatrix.tuples {
                membershipValues.append(setMatrix[tuple])
            }
        }

        // Compute cardinality using adder tree
        let cardinalityBV = arith.cardinality(of: membershipValues)
        return bitVectorToMatrix(cardinalityBV)
    }

    // MARK: - Comparison Operations

    /// Sum all integers in a matrix
    /// Per Alloy spec: sum is applied implicitly to arguments in comparisons
    /// If set contains multiple integers, their sum is compared
    private func sumOfIntegers(_ matrix: BooleanMatrix) -> BitVector? {
        guard matrix.arity == 1, let factory = intFactory, let arith = arithmetic else {
            return nil
        }

        // Start with zero
        var sumBV = BitVector.zero(bitWidth: bitWidth)

        // Add each integer value if it's in the matrix
        for intValue in factory.minValue...factory.maxValue {
            guard let atom = factory.atom(for: intValue) else { continue }
            let inMatrix = matrix[AtomTuple(atom)]

            // Skip if definitely not in matrix
            if case .constant(false) = inMatrix {
                continue
            }

            // Conditionally add: if atom is in matrix, add its value to sum
            let constant = BitVector.constant(intValue, bitWidth: bitWidth)
            let conditionalValue = arith.conditionalSelect(
                condition: inMatrix,
                ifTrue: constant,
                ifFalse: BitVector.zero(bitWidth: bitWidth)
            )
            sumBV = arith.add(sumBV, conditionalValue)
        }

        return sumBV
    }

    /// Encode less than: a < b
    /// Per Alloy spec: sum is applied implicitly to arguments
    public func encodeLessThan(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanFormula {
        guard let arith = arithmetic,
              let leftBV = sumOfIntegers(leftMatrix),
              let rightBV = sumOfIntegers(rightMatrix) else {
            return .constant(false)
        }

        return arith.lessThan(leftBV, rightBV)
    }

    /// Encode less than or equal: a <= b
    /// Per Alloy spec: sum is applied implicitly to arguments
    public func encodeLessThanOrEqual(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanFormula {
        guard let arith = arithmetic,
              let leftBV = sumOfIntegers(leftMatrix),
              let rightBV = sumOfIntegers(rightMatrix) else {
            return .constant(false)
        }

        return arith.lessThanOrEqual(leftBV, rightBV)
    }

    /// Encode greater than: a > b
    /// Per Alloy spec: sum is applied implicitly to arguments
    public func encodeGreaterThan(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanFormula {
        guard let arith = arithmetic,
              let leftBV = sumOfIntegers(leftMatrix),
              let rightBV = sumOfIntegers(rightMatrix) else {
            return .constant(false)
        }

        return arith.greaterThan(leftBV, rightBV)
    }

    /// Encode greater than or equal: a >= b
    /// Per Alloy spec: sum is applied implicitly to arguments
    public func encodeGreaterThanOrEqual(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanFormula {
        guard let arith = arithmetic,
              let leftBV = sumOfIntegers(leftMatrix),
              let rightBV = sumOfIntegers(rightMatrix) else {
            return .constant(false)
        }

        return arith.greaterThanOrEqual(leftBV, rightBV)
    }

    // MARK: - Bit Shift Operations

    /// Encode left shift: a << b (shl)
    public func encodeShiftLeft(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic,
              let leftBV = matrixToBitVector(leftMatrix),
              let rightBV = matrixToBitVector(rightMatrix) else {
            return context.emptyMatrix(arity: 1)
        }

        let result = arith.shiftLeftBV(leftBV, rightBV)
        return bitVectorToMatrix(result)
    }

    /// Encode arithmetic (signed) right shift: a >> b (sha)
    /// Sign-extends the result
    public func encodeShiftRightArithmetic(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic,
              let leftBV = matrixToBitVector(leftMatrix),
              let rightBV = matrixToBitVector(rightMatrix) else {
            return context.emptyMatrix(arity: 1)
        }

        let result = arith.shiftRightArithmetic(leftBV, rightBV)
        return bitVectorToMatrix(result)
    }

    /// Encode logical (unsigned) right shift: a >>> b (shr)
    /// Zero-fills the result
    public func encodeShiftRightLogical(_ leftMatrix: BooleanMatrix, _ rightMatrix: BooleanMatrix) -> BooleanMatrix {
        guard let arith = arithmetic,
              let leftBV = matrixToBitVector(leftMatrix),
              let rightBV = matrixToBitVector(rightMatrix) else {
            return context.emptyMatrix(arity: 1)
        }

        let result = arith.shiftRightLogical(leftBV, rightBV)
        return bitVectorToMatrix(result)
    }

    // MARK: - Sum Quantifier

    /// Encode sum quantifier: sum x: S | expr
    /// Returns a matrix representing the sum of expr for all x in S
    public func encodeSum(
        variable: String,
        domain: BooleanMatrix,
        body: @escaping () -> BooleanMatrix
    ) -> BooleanMatrix {
        guard let arith = arithmetic else {
            return context.emptyMatrix(arity: 1)
        }

        var sumBV = BitVector.zero(bitWidth: bitWidth)

        // For each atom in the domain, add the body value to the sum
        for atom in universe.atoms {
            let inDomain = domain[AtomTuple(atom)]

            // Skip if definitely not in domain
            if case .constant(false) = inDomain {
                continue
            }

            // Bind variable to this atom
            context.pushScope()
            context.bind(variable, to: context.atomMatrix(atom))

            // Evaluate body to get integer value
            let bodyMatrix = body()

            context.popScope()

            // Convert body to bit vector
            if let bodyBV = matrixToBitVector(bodyMatrix) {
                // Conditionally add: if atom is in domain, add bodyBV to sum
                let conditionalValue = arith.conditionalSelect(
                    condition: inDomain,
                    ifTrue: bodyBV,
                    ifFalse: BitVector.zero(bitWidth: bitWidth)
                )
                sumBV = arith.add(sumBV, conditionalValue)
            }
        }

        return bitVectorToMatrix(sumBV)
    }
}
