import Foundation

// MARK: - Boolean Value

/// A boolean value that can be true, false, or a SAT variable
public enum BooleanValue: Hashable, Sendable {
    /// Constant true
    case constant(Bool)

    /// SAT variable (positive = variable, negative = negated variable)
    case variable(Int32)

    /// True constant
    public static let trueValue = BooleanValue.constant(true)

    /// False constant
    public static let falseValue = BooleanValue.constant(false)

    /// Whether this is a constant
    public var isConstant: Bool {
        if case .constant = self { return true }
        return false
    }

    /// Get constant value if this is a constant
    public var constantValue: Bool? {
        if case .constant(let v) = self { return v }
        return nil
    }

    /// Get variable index if this is a variable
    public var variableIndex: Int32? {
        if case .variable(let v) = self { return abs(v) }
        return nil
    }

    /// Negate this value
    public var negated: BooleanValue {
        switch self {
        case .constant(let v):
            return .constant(!v)
        case .variable(let v):
            return .variable(-v)
        }
    }
}

extension BooleanValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .constant(true): return "T"
        case .constant(false): return "F"
        case .variable(let v) where v > 0: return "v\(v)"
        case .variable(let v): return "~v\(-v)"
        }
    }
}

// MARK: - Boolean Formula

/// Boolean formula in negation normal form (NNF)
/// Can be converted to CNF via Tseitin transformation
public indirect enum BooleanFormula: Hashable, Sendable {
    /// Constant true or false
    case constant(Bool)

    /// A variable (positive or negative)
    case variable(Int32)

    /// Conjunction (AND)
    case and([BooleanFormula])

    /// Disjunction (OR)
    case or([BooleanFormula])

    /// Implication (a => b)
    case implies(BooleanFormula, BooleanFormula)

    /// Biconditional (a <=> b)
    case iff(BooleanFormula, BooleanFormula)

    /// If-then-else
    case ite(BooleanFormula, BooleanFormula, BooleanFormula)

    // MARK: - Factory Methods

    /// True constant
    public static let trueFormula = BooleanFormula.constant(true)

    /// False constant
    public static let falseFormula = BooleanFormula.constant(false)

    /// Create a positive variable
    public static func pos(_ index: Int32) -> BooleanFormula {
        .variable(index)
    }

    /// Create a negative variable
    public static func neg(_ index: Int32) -> BooleanFormula {
        .variable(-index)
    }

    /// Create from boolean value
    public static func from(_ value: BooleanValue) -> BooleanFormula {
        switch value {
        case .constant(let b): return .constant(b)
        case .variable(let v): return .variable(v)
        }
    }

    // MARK: - Logical Operations

    /// Negation
    public var negated: BooleanFormula {
        switch self {
        case .constant(let v):
            return .constant(!v)
        case .variable(let v):
            return .variable(-v)
        case .and(let children):
            return .or(children.map(\.negated))
        case .or(let children):
            return .and(children.map(\.negated))
        case .implies(let a, let b):
            return .and([a, b.negated])
        case .iff(let a, let b):
            return .or([.and([a, b.negated]), .and([a.negated, b])])
        case .ite(let c, let t, let e):
            return .ite(c, t.negated, e.negated)
        }
    }

    /// Conjunction with another formula
    public func and(_ other: BooleanFormula) -> BooleanFormula {
        BooleanFormula.conjunction([self, other])
    }

    /// Disjunction with another formula
    public func or(_ other: BooleanFormula) -> BooleanFormula {
        BooleanFormula.disjunction([self, other])
    }

    /// Implication
    public func implies(_ other: BooleanFormula) -> BooleanFormula {
        .implies(self, other)
    }

    /// Biconditional
    public func iff(_ other: BooleanFormula) -> BooleanFormula {
        .iff(self, other)
    }

    // MARK: - Smart Constructors (with simplification)

    /// Create conjunction with simplification
    public static func conjunction(_ formulas: [BooleanFormula]) -> BooleanFormula {
        var result: [BooleanFormula] = []

        for f in formulas {
            switch f {
            case .constant(true):
                continue // Skip true
            case .constant(false):
                return .constant(false) // Short circuit
            case .and(let children):
                result.append(contentsOf: children) // Flatten
            default:
                result.append(f)
            }
        }

        switch result.count {
        case 0: return .constant(true)
        case 1: return result[0]
        default: return .and(result)
        }
    }

    /// Create disjunction with simplification
    public static func disjunction(_ formulas: [BooleanFormula]) -> BooleanFormula {
        var result: [BooleanFormula] = []

        for f in formulas {
            switch f {
            case .constant(false):
                continue // Skip false
            case .constant(true):
                return .constant(true) // Short circuit
            case .or(let children):
                result.append(contentsOf: children) // Flatten
            default:
                result.append(f)
            }
        }

        switch result.count {
        case 0: return .constant(false)
        case 1: return result[0]
        default: return .or(result)
        }
    }

    // MARK: - Properties

    /// Whether this is a constant
    public var isConstant: Bool {
        if case .constant = self { return true }
        return false
    }

    /// Get constant value if constant
    public var constantValue: Bool? {
        if case .constant(let v) = self { return v }
        return nil
    }

    /// Whether this is a literal (variable or negated variable)
    public var isLiteral: Bool {
        if case .variable = self { return true }
        return false
    }

    /// Whether this is a clause (disjunction of literals)
    public var isClause: Bool {
        switch self {
        case .variable: return true
        case .constant: return true
        case .or(let children): return children.allSatisfy(\.isLiteral)
        default: return false
        }
    }

    /// Whether this is in CNF (conjunction of clauses)
    public var isCNF: Bool {
        switch self {
        case .constant, .variable: return true
        case .or(let children): return children.allSatisfy(\.isLiteral)
        case .and(let children): return children.allSatisfy(\.isClause)
        default: return false
        }
    }
}

extension BooleanFormula: CustomStringConvertible {
    public var description: String {
        switch self {
        case .constant(true): return "TRUE"
        case .constant(false): return "FALSE"
        case .variable(let v) where v > 0: return "x\(v)"
        case .variable(let v): return "~x\(-v)"
        case .and(let children):
            return "(\(children.map(\.description).joined(separator: " & ")))"
        case .or(let children):
            return "(\(children.map(\.description).joined(separator: " | ")))"
        case .implies(let a, let b):
            return "(\(a) => \(b))"
        case .iff(let a, let b):
            return "(\(a) <=> \(b))"
        case .ite(let c, let t, let e):
            return "(if \(c) then \(t) else \(e))"
        }
    }
}

// MARK: - CNF Builder

/// Builds CNF formulas using Tseitin transformation
/// Converts arbitrary boolean formulas to equisatisfiable CNF
public final class CNFBuilder {
    /// Next variable index
    private var nextVar: Int32

    /// Generated clauses (each clause is a list of literals)
    private var clauses: [[Int32]] = []

    /// Cache for subformula variables (memoization)
    private var formulaCache: [BooleanFormula: Int32] = [:]

    /// Create a CNF builder starting at the given variable index
    public init(startingVariable: Int32 = 1) {
        self.nextVar = startingVariable
    }

    /// Get a fresh variable
    public func freshVariable() -> Int32 {
        let v = nextVar
        nextVar += 1
        return v
    }

    /// Current number of variables
    public var variableCount: Int32 { nextVar - 1 }

    /// Get all generated clauses
    public var allClauses: [[Int32]] { clauses }

    /// Add a clause directly
    public func addClause(_ literals: [Int32]) {
        guard !literals.isEmpty else { return }
        clauses.append(literals)
    }

    /// Add a unit clause (single literal)
    public func addUnit(_ literal: Int32) {
        clauses.append([literal])
    }

    /// Assert that a formula is true
    /// Returns the variable representing the formula
    @discardableResult
    public func assertTrue(_ formula: BooleanFormula) -> Int32 {
        let v = encode(formula)
        addUnit(v)
        return v
    }

    /// Assert that a formula is false
    @discardableResult
    public func assertFalse(_ formula: BooleanFormula) -> Int32 {
        let v = encode(formula)
        addUnit(-v)
        return v
    }

    /// Encode a formula and return the variable representing it
    /// Uses Tseitin transformation for subformulas
    public func encode(_ formula: BooleanFormula) -> Int32 {
        // Check cache
        if let cached = formulaCache[formula] {
            return cached
        }

        let result: Int32

        switch formula {
        case .constant(true):
            // Create a fresh variable and assert it true
            result = freshVariable()
            addUnit(result)

        case .constant(false):
            // Create a fresh variable and assert it false
            result = freshVariable()
            addUnit(-result)

        case .variable(let v):
            result = v

        case .and(let children):
            result = encodeAnd(children)

        case .or(let children):
            result = encodeOr(children)

        case .implies(let a, let b):
            // a => b is equivalent to ~a | b
            result = encodeOr([a.negated, b])

        case .iff(let a, let b):
            result = encodeIff(a, b)

        case .ite(let c, let t, let e):
            result = encodeITE(c, t, e)
        }

        formulaCache[formula] = result
        return result
    }

    /// Encode conjunction: v <=> (a1 & a2 & ... & an)
    private func encodeAnd(_ children: [BooleanFormula]) -> Int32 {
        if children.isEmpty {
            return encode(.constant(true))
        }
        if children.count == 1 {
            return encode(children[0])
        }

        let childVars = children.map { encode($0) }
        let v = freshVariable()

        // v => (a1 & a2 & ... & an)  ===  (~v | a1) & (~v | a2) & ... & (~v | an)
        for child in childVars {
            addClause([-v, child])
        }

        // (a1 & a2 & ... & an) => v  ===  ~a1 | ~a2 | ... | ~an | v
        addClause(childVars.map { -$0 } + [v])

        return v
    }

    /// Encode disjunction: v <=> (a1 | a2 | ... | an)
    private func encodeOr(_ children: [BooleanFormula]) -> Int32 {
        if children.isEmpty {
            return encode(.constant(false))
        }
        if children.count == 1 {
            return encode(children[0])
        }

        let childVars = children.map { encode($0) }
        let v = freshVariable()

        // v => (a1 | a2 | ... | an)  ===  ~v | a1 | a2 | ... | an
        addClause([-v] + childVars)

        // (a1 | a2 | ... | an) => v  ===  (~a1 | v) & (~a2 | v) & ... & (~an | v)
        for child in childVars {
            addClause([-child, v])
        }

        return v
    }

    /// Encode biconditional: v <=> (a <=> b)
    private func encodeIff(_ a: BooleanFormula, _ b: BooleanFormula) -> Int32 {
        let av = encode(a)
        let bv = encode(b)
        let v = freshVariable()

        // v <=> (a <=> b)
        // v => (a <=> b): v => ((a => b) & (b => a))
        //   = ~v | ((~a | b) & (~b | a))
        //   = (~v | ~a | b) & (~v | ~b | a)
        addClause([-v, -av, bv])
        addClause([-v, -bv, av])

        // (a <=> b) => v: ((~a | b) & (~b | a)) => v
        //   = ~(~a | b) | ~(~b | a) | v
        //   = (a & ~b) | (b & ~a) | v
        // This is: (a | b | v) & (~a | ~b | v) -- WRONG
        // Actually: v is true when a==b
        // So ~v means a != b, which is (a XOR b) = (a & ~b) | (~a & b)
        // So: (a <=> b) => v means ~(a XOR b) | v
        // = ~((a & ~b) | (~a & b)) | v
        // = (~a | b) & (a | ~b) | v
        // Converting to CNF:
        // (~a | b | v) & (a | ~b | v) -- these are the implications from iff
        addClause([av, bv, v])
        addClause([-av, -bv, v])

        return v
    }

    /// Encode if-then-else: v <=> ITE(c, t, e)
    private func encodeITE(_ c: BooleanFormula, _ t: BooleanFormula, _ e: BooleanFormula) -> Int32 {
        let cv = encode(c)
        let tv = encode(t)
        let ev = encode(e)
        let v = freshVariable()

        // ITE(c, t, e) = (c & t) | (~c & e)
        // v => ITE: ~v | (c & t) | (~c & e)
        // In CNF: (~v | c | e) & (~v | t | ~c) & (~v | t | e)
        // Actually simpler: v => (c => t) and v => (~c => e)
        // (~v | ~c | t) & (~v | c | e)
        addClause([-v, -cv, tv])
        addClause([-v, cv, ev])

        // ITE => v: ~(c & t) | v when ~c, and ~(~c & e) | v when c
        // (c & t) => v: ~c | ~t | v
        // (~c & e) => v: c | ~e | v
        addClause([-cv, -tv, v])
        addClause([cv, -ev, v])

        return v
    }

    /// Get the CNF as DIMACS format string
    public func toDIMACS() -> String {
        var result = "p cnf \(variableCount) \(clauses.count)\n"
        for clause in clauses {
            result += clause.map(String.init).joined(separator: " ") + " 0\n"
        }
        return result
    }
}

extension CNFBuilder: CustomStringConvertible {
    public var description: String {
        "CNFBuilder(vars: \(variableCount), clauses: \(clauses.count))"
    }
}
