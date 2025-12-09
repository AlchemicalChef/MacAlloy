import Foundation

// MARK: - Variable

/// A boolean variable in the SAT problem
/// Variables are 1-indexed (0 is reserved)
public struct Variable: Hashable, Comparable, Sendable {
    /// Raw variable index (1-indexed)
    public let index: Int32

    /// Create a variable with the given index
    public init(_ index: Int32) {
        precondition(index > 0, "Variable index must be positive")
        self.index = index
    }

    /// Create a variable from an integer
    public init(_ index: Int) {
        self.init(Int32(index))
    }

    public static func < (lhs: Variable, rhs: Variable) -> Bool {
        lhs.index < rhs.index
    }
}

extension Variable: CustomStringConvertible {
    public var description: String { "x\(index)" }
}

// MARK: - Literal

/// A literal is a variable or its negation
/// Encoded as: variable * 2 + (isNegated ? 1 : 0)
/// This allows efficient polarity extraction and negation
public struct Literal: Hashable, Comparable, Sendable {
    /// Raw encoded value
    /// Bit 0: polarity (0 = positive, 1 = negative)
    /// Bits 1+: variable index
    public let code: Int32

    /// Create a literal from its encoded value
    @inlinable
    public init(code: Int32) {
        self.code = code
    }

    /// Create a positive literal for a variable
    @inlinable
    public init(variable: Variable) {
        self.code = variable.index << 1
    }

    /// Create a literal with specified polarity
    @inlinable
    public init(variable: Variable, isNegated: Bool) {
        self.code = (variable.index << 1) | (isNegated ? 1 : 0)
    }

    /// Create a positive literal for variable index
    @inlinable
    public static func pos(_ varIndex: Int32) -> Literal {
        Literal(code: varIndex << 1)
    }

    /// Create a negative literal for variable index
    @inlinable
    public static func neg(_ varIndex: Int32) -> Literal {
        Literal(code: (varIndex << 1) | 1)
    }

    /// The variable of this literal
    @inlinable
    public var variable: Variable {
        Variable(code >> 1)
    }

    /// The variable index
    @inlinable
    public var variableIndex: Int32 {
        code >> 1
    }

    /// Whether this literal is negated
    @inlinable
    public var isNegated: Bool {
        (code & 1) == 1
    }

    /// Whether this literal is positive (not negated)
    @inlinable
    public var isPositive: Bool {
        (code & 1) == 0
    }

    /// The negation of this literal
    @inlinable
    public var negated: Literal {
        Literal(code: code ^ 1)
    }

    /// The polarity as a sign (+1 or -1)
    @inlinable
    public var sign: Int {
        isNegated ? -1 : 1
    }

    public static func < (lhs: Literal, rhs: Literal) -> Bool {
        lhs.code < rhs.code
    }

    /// Undefined literal (used as sentinel)
    public static let undefined = Literal(code: 0)
}

extension Literal: CustomStringConvertible {
    public var description: String {
        isNegated ? "~x\(variableIndex)" : "x\(variableIndex)"
    }
}

// MARK: - Lifted Boolean (Three-valued logic)

/// Three-valued truth value for partial assignments
public enum LiftedBool: Int8, Sendable {
    case `false` = 0
    case `true` = 1
    case undefined = 2

    /// Negate the value
    @inlinable
    public var negated: LiftedBool {
        switch self {
        case .true: return .false
        case .false: return .true
        case .undefined: return .undefined
        }
    }

    /// Convert from Bool
    @inlinable
    public init(_ value: Bool) {
        self = value ? .true : .false
    }

    /// Convert to Bool (undefined becomes false)
    @inlinable
    public var boolValue: Bool {
        self == .true
    }

    /// Is this value defined?
    @inlinable
    public var isDefined: Bool {
        self != .undefined
    }
}

// MARK: - Assignment

/// Represents an assignment of a variable
public struct Assignment: Sendable {
    /// The assigned variable
    public let variable: Variable

    /// The assigned value
    public let value: Bool

    /// The decision level at which this assignment was made
    public let level: Int

    /// The reason clause (nil for decisions)
    public let reason: ClauseRef?

    /// Position in the trail
    public let trailIndex: Int

    public init(variable: Variable, value: Bool, level: Int, reason: ClauseRef?, trailIndex: Int) {
        self.variable = variable
        self.value = value
        self.level = level
        self.reason = reason
        self.trailIndex = trailIndex
    }

    /// Whether this is a decision (not a propagation)
    public var isDecision: Bool {
        reason == nil
    }
}

// MARK: - Clause Reference

/// A reference to a clause in the clause database
public struct ClauseRef: Hashable, Sendable {
    /// Index into the clause database
    public let index: Int32

    public init(_ index: Int32) {
        self.index = index
    }

    public init(_ index: Int) {
        self.index = Int32(index)
    }

    /// Invalid clause reference
    public static let invalid = ClauseRef(-1)
}

extension ClauseRef: CustomStringConvertible {
    public var description: String { "C\(index)" }
}

// MARK: - Solver Result

/// The result of SAT solving
public enum SolverResult: Sendable {
    case satisfiable([Bool])    // SAT with model (1-indexed)
    case unsatisfiable          // UNSAT
    case unknown                // Timeout or resource limit
}

extension SolverResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .satisfiable(let model):
            return "SAT: \(model.enumerated().dropFirst().filter { $0.element }.map { "x\($0.offset)" }.joined(separator: " "))"
        case .unsatisfiable:
            return "UNSAT"
        case .unknown:
            return "UNKNOWN"
        }
    }
}

// MARK: - Solver Statistics

/// Statistics about the solving process
public struct SolverStats: Sendable {
    public var decisions: Int = 0
    public var propagations: Int = 0
    public var conflicts: Int = 0
    public var learnedClauses: Int = 0
    public var restarts: Int = 0
    public var deletedClauses: Int = 0
    public var solveTimeMs: Double = 0

    public init() {}
}

extension SolverStats: CustomStringConvertible {
    public var description: String {
        """
        Decisions: \(decisions)
        Propagations: \(propagations)
        Conflicts: \(conflicts)
        Learned clauses: \(learnedClauses)
        Restarts: \(restarts)
        Deleted clauses: \(deletedClauses)
        Solve time: \(String(format: "%.2f", solveTimeMs)) ms
        """
    }
}
