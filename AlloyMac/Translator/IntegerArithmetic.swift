import Foundation

// MARK: - Integer Arithmetic

/// Implements boolean circuits for integer arithmetic operations
/// All operations use two's complement representation
public struct IntegerArithmetic {
    /// The CNF builder for creating intermediate variables
    public let cnf: CNFBuilder

    /// Bit width for operations
    public let bitWidth: Int

    public init(cnf: CNFBuilder, bitWidth: Int = 4) {
        self.cnf = cnf
        self.bitWidth = bitWidth
    }

    // MARK: - Boolean Logic Helpers

    /// XOR of two boolean values: a XOR b
    /// Returns a fresh variable constrained to be a XOR b
    public func xor(_ a: BooleanValue, _ b: BooleanValue) -> BooleanValue {
        // Optimize constant cases
        if case .constant(let av) = a {
            return av ? b.negated : b
        }
        if case .constant(let bv) = b {
            return bv ? a.negated : a
        }

        // Create fresh variable for result
        let result = cnf.freshVariable()

        // a XOR b = (a OR b) AND NOT(a AND b)
        // CNF encoding of result <=> (a XOR b):
        // (~result | ~a | ~b) & (~result | a | b) & (result | ~a | b) & (result | a | ~b)
        let av = variableLiteral(a)
        let bv = variableLiteral(b)

        cnf.addClause([-result, -av, -bv])  // result => ~(a & b)
        cnf.addClause([-result, av, bv])    // result => (a | b)
        cnf.addClause([result, -av, bv])    // ~result => (a => b)
        cnf.addClause([result, av, -bv])    // ~result => (b => a)

        return .variable(result)
    }

    /// AND of two boolean values: a AND b
    public func and(_ a: BooleanValue, _ b: BooleanValue) -> BooleanValue {
        // Optimize constant cases
        if case .constant(let av) = a {
            return av ? b : .constant(false)
        }
        if case .constant(let bv) = b {
            return bv ? a : .constant(false)
        }

        let result = cnf.freshVariable()
        let av = variableLiteral(a)
        let bv = variableLiteral(b)

        // result <=> (a & b)
        cnf.addClause([-result, av])        // result => a
        cnf.addClause([-result, bv])        // result => b
        cnf.addClause([result, -av, -bv])   // (a & b) => result

        return .variable(result)
    }

    /// OR of two boolean values: a OR b
    public func or(_ a: BooleanValue, _ b: BooleanValue) -> BooleanValue {
        // Optimize constant cases
        if case .constant(let av) = a {
            return av ? .constant(true) : b
        }
        if case .constant(let bv) = b {
            return bv ? .constant(true) : a
        }

        let result = cnf.freshVariable()
        let av = variableLiteral(a)
        let bv = variableLiteral(b)

        // result <=> (a | b)
        cnf.addClause([-result, av, bv])    // result => (a | b)
        cnf.addClause([result, -av])        // a => result
        cnf.addClause([result, -bv])        // b => result

        return .variable(result)
    }

    /// Get the literal for a boolean value
    private func variableLiteral(_ v: BooleanValue) -> Int32 {
        switch v {
        case .constant(let b):
            // Create a fresh variable constrained to the constant
            let fresh = cnf.freshVariable()
            cnf.addUnit(b ? fresh : -fresh)
            return fresh
        case .variable(let lit):
            return lit
        }
    }

    // MARK: - Adder Circuits

    /// Half adder: computes sum and carry for two single bits
    /// - Returns: (sum, carry) where sum = a XOR b, carry = a AND b
    public func halfAdder(_ a: BooleanValue, _ b: BooleanValue) -> (sum: BooleanValue, carry: BooleanValue) {
        let sum = xor(a, b)
        let carry = and(a, b)
        return (sum, carry)
    }

    /// Full adder: computes sum and carry-out for two bits plus carry-in
    /// - Returns: (sum, carry_out) where:
    ///   - sum = a XOR b XOR carry_in
    ///   - carry_out = (a AND b) OR (carry_in AND (a XOR b))
    public func fullAdder(_ a: BooleanValue, _ b: BooleanValue, _ carryIn: BooleanValue) -> (sum: BooleanValue, carryOut: BooleanValue) {
        // sum = a XOR b XOR carry_in
        let axorb = xor(a, b)
        let sum = xor(axorb, carryIn)

        // carry_out = (a AND b) OR (carry_in AND (a XOR b))
        let aandb = and(a, b)
        let cinAndXor = and(carryIn, axorb)
        let carryOut = or(aandb, cinAndXor)

        return (sum, carryOut)
    }

    // MARK: - Arithmetic Operations

    /// Add two bit vectors: a + b
    /// Per Alloy spec: overflow makes the model UNSAT
    public func add(_ a: BitVector, _ b: BitVector) -> BitVector {
        precondition(a.bitWidth == b.bitWidth, "Bit widths must match")

        var resultBits: [BooleanValue] = []
        var carry: BooleanValue = .constant(false)

        for i in 0..<a.bitWidth {
            let (sum, carryOut) = fullAdder(a[i], b[i], carry)
            resultBits.append(sum)
            carry = carryOut
        }

        let result = BitVector(bits: resultBits)

        // Detect signed overflow per Alloy spec: analysis fails on overflow
        // Overflow occurs when: sign(a) == sign(b) AND sign(a) != sign(result)
        // This is equivalent to: carry into MSB != carry out of MSB
        // Or: (a_sign XOR result_sign) AND (b_sign XOR result_sign)
        let aSign = a.signBit
        let bSign = b.signBit
        let resultSign = result.signBit

        // overflow = (aSign == bSign) AND (aSign != resultSign)
        // overflow = NOT(aSign XOR bSign) AND (aSign XOR resultSign)
        let sameInputSigns = xor(aSign, bSign).negated  // NOT(aSign XOR bSign)
        let signChanged = xor(aSign, resultSign)         // aSign XOR resultSign
        let overflow = and(sameInputSigns, signChanged)

        // Constrain: overflow must be false (no overflow allowed)
        // This makes model UNSAT if any addition overflows
        constrainFalse(overflow)

        return result
    }

    /// Constrain a boolean value to be false
    private func constrainFalse(_ value: BooleanValue) {
        switch value {
        case .constant(false):
            // Already false, nothing to do
            break
        case .constant(true):
            // Constant true constrained to false - add empty clause to make UNSAT
            cnf.addClause([])
        case .variable(let v):
            // Add unit clause: NOT v
            cnf.addClause([-v])
        }
    }

    /// Negate a bit vector (two's complement negation): -x = ~x + 1
    public func negate(_ x: BitVector) -> BitVector {
        let inverted = x.bitwiseNot
        let one = BitVector.one(bitWidth: x.bitWidth)
        return add(inverted, one)
    }

    /// Subtract two bit vectors: a - b = a + (-b)
    public func subtract(_ a: BitVector, _ b: BitVector) -> BitVector {
        let negB = negate(b)
        return add(a, negB)
    }

    /// Multiply two bit vectors: a * b
    /// Uses shift-and-add algorithm
    /// Per Alloy spec: overflow makes the model UNSAT, handled by add() overflow detection
    /// Note: Each intermediate add() will detect overflow and constrain it to be false
    public func multiply(_ a: BitVector, _ b: BitVector) -> BitVector {
        precondition(a.bitWidth == b.bitWidth, "Bit widths must match")
        let width = a.bitWidth

        // Start with zero
        var result = BitVector.zero(bitWidth: width)

        // For each bit of b, if it's 1, add (a << position) to result
        // Note: We only iterate over bits where shifting won't immediately overflow
        // For signed multiplication, we need to be careful about sign extension
        for i in 0..<width {
            // Skip if this bit of b is definitely false
            if case .constant(false) = b[i] {
                continue
            }

            // Shift a left by i positions (with truncation)
            let shifted = shiftLeft(a, by: i)

            // Conditionally add: if b[i], add shifted to result
            // The add() function will detect overflow and make model UNSAT if it occurs
            let toAdd = conditionalSelect(condition: b[i], ifTrue: shifted, ifFalse: BitVector.zero(bitWidth: width))
            result = add(result, toAdd)
        }

        return result
    }

    /// Shift left by constant amount
    private func shiftLeft(_ x: BitVector, by amount: Int) -> BitVector {
        if amount >= x.bitWidth {
            return BitVector.zero(bitWidth: x.bitWidth)
        }

        var bits: [BooleanValue] = []
        // Low bits become zero
        for _ in 0..<amount {
            bits.append(.constant(false))
        }
        // Copy remaining bits (truncating high bits that shift out)
        for i in 0..<(x.bitWidth - amount) {
            bits.append(x[i])
        }

        return BitVector(bits: bits)
    }

    /// Conditional select: returns ifTrue if condition is true, else ifFalse
    public func conditionalSelect(condition: BooleanValue, ifTrue: BitVector, ifFalse: BitVector) -> BitVector {
        precondition(ifTrue.bitWidth == ifFalse.bitWidth, "Bit widths must match")

        // Optimize for constant condition
        if case .constant(let c) = condition {
            return c ? ifTrue : ifFalse
        }

        var resultBits: [BooleanValue] = []
        for i in 0..<ifTrue.bitWidth {
            // result[i] = (condition AND ifTrue[i]) OR (NOT condition AND ifFalse[i])
            let selected = ite(condition, ifTrue[i], ifFalse[i])
            resultBits.append(selected)
        }

        return BitVector(bits: resultBits)
    }

    /// If-then-else for boolean values
    public func ite(_ condition: BooleanValue, _ ifTrue: BooleanValue, _ ifFalse: BooleanValue) -> BooleanValue {
        // result = (c AND t) OR (NOT c AND f)
        if case .constant(let c) = condition {
            return c ? ifTrue : ifFalse
        }

        let candt = and(condition, ifTrue)
        let notcandf = and(condition.negated, ifFalse)
        return or(candt, notcandf)
    }

    /// Division and remainder: a / b and a % b
    /// Uses restoring division algorithm
    /// Per Alloy spec: Division by zero behavior - we add a constraint to make the model UNSAT
    /// if division by zero occurs, matching Alloy's semantics
    public func divRem(_ a: BitVector, _ b: BitVector) -> (quotient: BitVector, remainder: BitVector) {
        precondition(a.bitWidth == b.bitWidth, "Bit widths must match")
        let width = a.bitWidth

        // Check for division by zero early: if b == 0, constrain model to be UNSAT
        let bIsZero = isZero(b)
        // Add constraint: bIsZero must be false (i.e., b must not be zero)
        // This makes the model UNSAT if division by zero would occur
        constrainFalse(bIsZero)

        // Handle signs for signed division
        // |a| / |b| = |q|, sign(q) = sign(a) XOR sign(b)
        // |a| % |b| = |r|, sign(r) = sign(a)

        let aSign = a.signBit
        let bSign = b.signBit

        // Get absolute values
        let absA = conditionalSelect(condition: aSign, ifTrue: negate(a), ifFalse: a)
        let absB = conditionalSelect(condition: bSign, ifTrue: negate(b), ifFalse: b)

        // Perform unsigned division
        let (unsignedQ, unsignedR) = unsignedDivRem(absA, absB)

        // Apply signs to results
        let qSign = xor(aSign, bSign)
        let quotient = conditionalSelect(condition: qSign, ifTrue: negate(unsignedQ), ifFalse: unsignedQ)
        let remainder = conditionalSelect(condition: aSign, ifTrue: negate(unsignedR), ifFalse: unsignedR)

        return (quotient, remainder)
    }

    /// Check if a bit vector is zero
    private func isZero(_ x: BitVector) -> BooleanValue {
        // x is zero iff all bits are 0
        var allZero: BooleanValue = .constant(true)
        for i in 0..<x.bitWidth {
            allZero = and(allZero, x[i].negated)
        }
        return allZero
    }

    /// Unsigned division using restoring division
    private func unsignedDivRem(_ a: BitVector, _ b: BitVector) -> (quotient: BitVector, remainder: BitVector) {
        let width = a.bitWidth

        var quotientBits: [BooleanValue] = Array(repeating: .constant(false), count: width)
        var remainder = BitVector.zero(bitWidth: width)

        // Process from MSB to LSB
        for i in stride(from: width - 1, through: 0, by: -1) {
            // Shift remainder left and bring in next bit of a
            remainder = shiftLeftAndInsert(remainder, bit: a[i])

            // Try to subtract b from remainder
            let diff = subtract(remainder, b)

            // If remainder >= b (i.e., diff is non-negative), use diff and set quotient bit
            // For unsigned, this means the sign bit of diff is 0
            let canSubtract = diff.signBit.negated

            // Update remainder: use diff if we can subtract, else keep remainder
            remainder = conditionalSelect(condition: canSubtract, ifTrue: diff, ifFalse: remainder)

            // Set quotient bit
            quotientBits[i] = canSubtract
        }

        return (BitVector(bits: quotientBits), remainder)
    }

    /// Shift left by 1 and insert a bit at LSB
    private func shiftLeftAndInsert(_ x: BitVector, bit: BooleanValue) -> BitVector {
        var bits: [BooleanValue] = [bit]
        for i in 0..<(x.bitWidth - 1) {
            bits.append(x[i])
        }
        return BitVector(bits: bits)
    }

    // MARK: - Comparison Operations

    /// Equality: a == b
    public func equals(_ a: BitVector, _ b: BitVector) -> BooleanFormula {
        precondition(a.bitWidth == b.bitWidth, "Bit widths must match")

        var conjuncts: [BooleanFormula] = []
        for i in 0..<a.bitWidth {
            // a[i] <=> b[i]
            let eq = BooleanFormula.iff(.from(a[i]), .from(b[i]))
            conjuncts.append(eq)
        }

        return BooleanFormula.conjunction(conjuncts)
    }

    /// Signed less than: a < b
    /// For two's complement: if signs differ, negative < positive
    /// Otherwise, compare as unsigned
    public func lessThan(_ a: BitVector, _ b: BitVector) -> BooleanFormula {
        precondition(a.bitWidth == b.bitWidth, "Bit widths must match")

        let aSign = a.signBit
        let bSign = b.signBit

        // If signs are different: a < b iff a is negative (aSign && !bSign)
        let signsDiffer = xor(aSign, bSign)
        let aIsNegative = aSign

        // If signs are same: compare magnitudes (unsigned comparison)
        let unsignedLess = unsignedLessThan(a, b)

        // result = (signsDiffer AND aIsNegative) OR (NOT signsDiffer AND unsignedLess)
        let differentSignsCase = BooleanFormula.conjunction([.from(signsDiffer), .from(aIsNegative)])
        let sameSignsCase = BooleanFormula.conjunction([.from(signsDiffer.negated), unsignedLess])

        return BooleanFormula.disjunction([differentSignsCase, sameSignsCase])
    }

    /// Unsigned less than for comparison of magnitudes
    private func unsignedLessThan(_ a: BitVector, _ b: BitVector) -> BooleanFormula {
        // a < b unsigned
        // Starting from MSB, find first differing bit
        // a < b iff at that bit, a has 0 and b has 1

        // Build formula: there exists some bit i where:
        // - all higher bits are equal
        // - a[i] = 0 and b[i] = 1

        var result: [BooleanFormula] = []

        for i in stride(from: a.bitWidth - 1, through: 0, by: -1) {
            // Condition: bits above i are equal, a[i] = 0, b[i] = 1
            var conditions: [BooleanFormula] = []

            // All bits above i are equal
            for j in (i + 1)..<a.bitWidth {
                conditions.append(BooleanFormula.iff(.from(a[j]), .from(b[j])))
            }

            // a[i] = 0 and b[i] = 1
            conditions.append(.from(a[i].negated))
            conditions.append(.from(b[i]))

            result.append(BooleanFormula.conjunction(conditions))
        }

        return BooleanFormula.disjunction(result)
    }

    /// Signed less than or equal: a <= b
    public func lessThanOrEqual(_ a: BitVector, _ b: BitVector) -> BooleanFormula {
        // a <= b  ===  (a < b) OR (a == b)
        let lt = lessThan(a, b)
        let eq = equals(a, b)
        return BooleanFormula.disjunction([lt, eq])
    }

    /// Signed greater than: a > b  ===  b < a
    public func greaterThan(_ a: BitVector, _ b: BitVector) -> BooleanFormula {
        return lessThan(b, a)
    }

    /// Signed greater than or equal: a >= b  ===  b <= a
    public func greaterThanOrEqual(_ a: BitVector, _ b: BitVector) -> BooleanFormula {
        return lessThanOrEqual(b, a)
    }

    // MARK: - Bit Shift Operations

    /// Left shift by variable amount: a << b (Alloy shl)
    /// Shifts in zeros from the right
    public func shiftLeftBV(_ a: BitVector, _ b: BitVector) -> BitVector {
        precondition(a.bitWidth == b.bitWidth, "Bit widths must match")
        let width = a.bitWidth

        // Start with the input value
        var result = a

        // Barrel shifter: for each bit position i of b, if b[i] is set,
        // shift result left by 2^i positions
        for i in 0..<width {
            let shiftAmount = 1 << i
            if shiftAmount >= width {
                // Shift by this amount would clear all bits
                let cleared = BitVector.zero(bitWidth: width)
                result = conditionalSelect(condition: b[i], ifTrue: cleared, ifFalse: result)
            } else {
                let shifted = shiftLeft(result, by: shiftAmount)
                result = conditionalSelect(condition: b[i], ifTrue: shifted, ifFalse: result)
            }
        }

        return result
    }

    /// Arithmetic (signed) right shift by variable amount: a >> b (Alloy sha)
    /// Sign-extends: fills vacated high bits with the sign bit
    public func shiftRightArithmetic(_ a: BitVector, _ b: BitVector) -> BitVector {
        precondition(a.bitWidth == b.bitWidth, "Bit widths must match")
        let width = a.bitWidth
        let signBit = a.signBit

        // Start with the input value
        var result = a

        // Barrel shifter: for each bit position i of b, if b[i] is set,
        // shift result right by 2^i positions (with sign extension)
        for i in 0..<width {
            let shiftAmount = 1 << i
            if shiftAmount >= width {
                // Shift by this amount fills all bits with sign
                var allSignBits: [BooleanValue] = []
                for _ in 0..<width {
                    allSignBits.append(signBit)
                }
                let filled = BitVector(bits: allSignBits)
                result = conditionalSelect(condition: b[i], ifTrue: filled, ifFalse: result)
            } else {
                let shifted = shiftRightArithmeticConst(result, by: shiftAmount)
                result = conditionalSelect(condition: b[i], ifTrue: shifted, ifFalse: result)
            }
        }

        return result
    }

    /// Logical (unsigned) right shift by variable amount: a >>> b (Alloy shr)
    /// Zero-fills: fills vacated high bits with zeros
    public func shiftRightLogical(_ a: BitVector, _ b: BitVector) -> BitVector {
        precondition(a.bitWidth == b.bitWidth, "Bit widths must match")
        let width = a.bitWidth

        // Start with the input value
        var result = a

        // Barrel shifter: for each bit position i of b, if b[i] is set,
        // shift result right by 2^i positions (with zero fill)
        for i in 0..<width {
            let shiftAmount = 1 << i
            if shiftAmount >= width {
                // Shift by this amount clears all bits
                let cleared = BitVector.zero(bitWidth: width)
                result = conditionalSelect(condition: b[i], ifTrue: cleared, ifFalse: result)
            } else {
                let shifted = shiftRightLogicalConst(result, by: shiftAmount)
                result = conditionalSelect(condition: b[i], ifTrue: shifted, ifFalse: result)
            }
        }

        return result
    }

    /// Arithmetic right shift by constant amount (sign extends)
    private func shiftRightArithmeticConst(_ x: BitVector, by amount: Int) -> BitVector {
        if amount >= x.bitWidth {
            // Fill with sign bit
            var bits: [BooleanValue] = []
            for _ in 0..<x.bitWidth {
                bits.append(x.signBit)
            }
            return BitVector(bits: bits)
        }

        var bits: [BooleanValue] = []
        // Copy higher bits, shifting down
        for i in amount..<x.bitWidth {
            bits.append(x[i])
        }
        // Fill high bits with sign bit
        for _ in 0..<amount {
            bits.append(x.signBit)
        }

        return BitVector(bits: bits)
    }

    /// Logical right shift by constant amount (zero fills)
    private func shiftRightLogicalConst(_ x: BitVector, by amount: Int) -> BitVector {
        if amount >= x.bitWidth {
            return BitVector.zero(bitWidth: x.bitWidth)
        }

        var bits: [BooleanValue] = []
        // Copy higher bits, shifting down
        for i in amount..<x.bitWidth {
            bits.append(x[i])
        }
        // Fill high bits with zeros
        for _ in 0..<amount {
            bits.append(.constant(false))
        }

        return BitVector(bits: bits)
    }

    // MARK: - Cardinality

    /// Compute cardinality (population count) of a boolean matrix
    /// Returns a bit vector representing the count of true entries
    public func cardinality(of values: [BooleanValue]) -> BitVector {
        if values.isEmpty {
            return BitVector.zero(bitWidth: bitWidth)
        }

        // Convert each boolean to a 1-bit number, then sum with tree of adders
        var currentLevel: [BitVector] = values.map { value in
            // Single bit: the value itself
            BitVector(bits: [value])
        }

        // Extend all to target bit width and sum using adder tree
        currentLevel = currentLevel.map { $0.zeroExtend(to: bitWidth) }

        // Pair-wise addition until we have a single result
        while currentLevel.count > 1 {
            var nextLevel: [BitVector] = []

            for i in stride(from: 0, to: currentLevel.count, by: 2) {
                if i + 1 < currentLevel.count {
                    nextLevel.append(add(currentLevel[i], currentLevel[i + 1]))
                } else {
                    nextLevel.append(currentLevel[i])
                }
            }

            currentLevel = nextLevel
        }

        return currentLevel[0]
    }

    /// Sum an array of bit vectors
    public func sum(_ vectors: [BitVector]) -> BitVector {
        if vectors.isEmpty {
            return BitVector.zero(bitWidth: bitWidth)
        }

        var result = vectors[0]
        for i in 1..<vectors.count {
            result = add(result, vectors[i])
        }
        return result
    }
}
