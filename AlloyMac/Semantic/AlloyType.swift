import Foundation

// MARK: - Type Checking Context

/// Context for type checking operations
/// - `inference`: Permissive mode during type inference - unknown types are compatible with anything
/// - `validation`: Strict mode during validation - unknown types are not compatible
public enum TypeCheckingContext: Sendable {
    case inference
    case validation
}

// MARK: - Alloy Type Protocol

/// Base protocol for all Alloy types
public protocol AlloyType: CustomStringConvertible, Sendable {
    /// The arity (number of columns) of this type
    /// - Sets have arity 1
    /// - Binary relations have arity 2
    /// - Higher-arity relations have arity 3+
    var arity: Int { get }

    /// Check if this type is a subtype of another
    func isSubtypeOf(_ other: AlloyType) -> Bool

    /// The join of this type with another (for type inference)
    func join(with other: AlloyType) -> AlloyType?

    /// The product of this type with another (->)
    func product(with other: AlloyType) -> AlloyType
}

// MARK: - Primitive Types

/// The Boolean type for formulas
public struct BoolType: AlloyType {
    public static let instance = BoolType()

    public var arity: Int { 0 }

    public func isSubtypeOf(_ other: AlloyType) -> Bool {
        other is BoolType
    }

    public func join(with other: AlloyType) -> AlloyType? {
        nil // Cannot join with Bool
    }

    public func product(with other: AlloyType) -> AlloyType {
        other // Bool acts as identity for product in some contexts
    }

    public var description: String { "Bool" }
}

/// The Integer type
public struct IntType: AlloyType {
    public static let instance = IntType()

    public var arity: Int { 1 }

    public func isSubtypeOf(_ other: AlloyType) -> Bool {
        other is IntType || other is UnivType
    }

    public func join(with other: AlloyType) -> AlloyType? {
        guard other.arity >= 2 else { return nil }
        // Join with n-ary relation gives (n-1)-ary relation
        let resultArity = other.arity - 1
        if resultArity == 1 {
            return UnknownType(arity: 1)
        }
        return UnknownType(arity: resultArity)
    }

    public func product(with other: AlloyType) -> AlloyType {
        RelationType(columnTypes: [self, other])
    }

    public var description: String { "Int" }
}

// MARK: - Signature Type

/// A signature type (set of atoms)
public final class SigType: AlloyType, Equatable, Hashable {
    /// The name of the signature
    public let name: String

    /// Parent signature type (if extends)
    public weak var parent: SigType?

    /// Is this an abstract signature?
    public let isAbstract: Bool

    /// Is this a variable signature? (Alloy 6)
    public let isVariable: Bool

    /// Multiplicity constraint
    public let multiplicity: Multiplicity?

    public init(name: String,
                parent: SigType? = nil,
                isAbstract: Bool = false,
                isVariable: Bool = false,
                multiplicity: Multiplicity? = nil) {
        self.name = name
        self.parent = parent
        self.isAbstract = isAbstract
        self.isVariable = isVariable
        self.multiplicity = multiplicity
    }

    public var arity: Int { 1 }

    public func isSubtypeOf(_ other: AlloyType) -> Bool {
        if other is UnivType { return true }
        guard let otherSig = other as? SigType else { return false }
        if self === otherSig { return true }
        if let p = parent { return p.isSubtypeOf(otherSig) }
        return false
    }

    public func join(with other: AlloyType) -> AlloyType? {
        guard other.arity >= 2 else { return nil }
        // Join Sig (arity 1) with n-ary relation gives (n-1)-ary relation
        return UnknownType(arity: other.arity - 1)
    }

    public func product(with other: AlloyType) -> AlloyType {
        if let otherSig = other as? SigType {
            return RelationType(columnTypes: [self, otherSig])
        }
        return RelationType(columnTypes: [self, other])
    }

    public var description: String { name }

    public static func == (lhs: SigType, rhs: SigType) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// MARK: - Relation Type

/// A relation type (n-ary relation)
public struct RelationType: AlloyType {
    /// The types of each column
    public let columnTypes: [any AlloyType]

    public init(columnTypes: [any AlloyType]) {
        self.columnTypes = columnTypes
    }

    public var arity: Int { columnTypes.count }

    /// The domain type (first column)
    public var domain: AlloyType? { columnTypes.first }

    /// The range type (last column)
    public var range: AlloyType? { columnTypes.last }

    public func isSubtypeOf(_ other: AlloyType) -> Bool {
        guard let otherRel = other as? RelationType else {
            return other is UnivType
        }
        guard arity == otherRel.arity else { return false }
        return zip(columnTypes, otherRel.columnTypes).allSatisfy { $0.isSubtypeOf($1) }
    }

    public func join(with other: AlloyType) -> AlloyType? {
        guard arity >= 1 else {
            return nil
        }
        // a.b where a has arity m and b has arity n gives arity (m + n - 2)
        let resultArity = arity + other.arity - 2
        if resultArity < 1 { return nil }

        // Build result column types
        var resultCols: [any AlloyType] = []
        // Take all but last from self
        resultCols.append(contentsOf: columnTypes.dropLast())

        // Take all but first from other
        if let otherRel = other as? RelationType {
            resultCols.append(contentsOf: otherRel.columnTypes.dropFirst())
        } else if other.arity > 0 {
            // For non-RelationType with arity > 0, treat as unary relation
            // After dropping first column, nothing remains if arity is 1
            if other.arity > 1 {
                // Use UnknownType for remaining columns
                for _ in 1..<other.arity {
                    resultCols.append(UnknownType(arity: 1))
                }
            }
        }

        if resultCols.count == 1 {
            return resultCols[0]
        } else if resultCols.count == 0 {
            return nil
        }
        return RelationType(columnTypes: resultCols)
    }

    public func product(with other: AlloyType) -> AlloyType {
        if let otherRel = other as? RelationType {
            return RelationType(columnTypes: columnTypes + otherRel.columnTypes)
        }
        return RelationType(columnTypes: columnTypes + [other])
    }

    public var description: String {
        columnTypes.map { "\($0)" }.joined(separator: " -> ")
    }
}

// MARK: - Special Types

/// The universal set type (univ)
public struct UnivType: AlloyType {
    public static let instance = UnivType()

    public var arity: Int { 1 }

    public func isSubtypeOf(_ other: AlloyType) -> Bool {
        other is UnivType
    }

    public func join(with other: AlloyType) -> AlloyType? {
        guard other.arity >= 1 else { return nil }
        return UnknownType(arity: other.arity - 1)
    }

    public func product(with other: AlloyType) -> AlloyType {
        RelationType(columnTypes: [self, other])
    }

    public var description: String { "univ" }
}

/// The empty set type (none)
public struct NoneType: AlloyType {
    public static let instance = NoneType()

    public var arity: Int { 1 }

    public func isSubtypeOf(_ other: AlloyType) -> Bool {
        other.arity == 1 // none is subtype of all unary relations
    }

    public func join(with other: AlloyType) -> AlloyType? {
        guard other.arity >= 1 else { return nil }
        return NoneType.instance
    }

    public func product(with other: AlloyType) -> AlloyType {
        RelationType(columnTypes: [self, other])
    }

    public var description: String { "none" }
}

/// The identity relation type (iden)
public struct IdenType: AlloyType {
    public static let instance = IdenType()

    public var arity: Int { 2 }

    public func isSubtypeOf(_ other: AlloyType) -> Bool {
        guard let otherRel = other as? RelationType else {
            return other is UnivType
        }
        return otherRel.arity == 2
    }

    public func join(with other: AlloyType) -> AlloyType? {
        // iden.x = x (identity relation joined with x gives x)
        // But if x is unary, we should keep it unary; if x is n-ary, result is (n-1)-ary
        if other.arity == 1 {
            return other
        } else if other.arity > 1 {
            // Join iden (arity 2) with n-ary gives (n-1)-ary
            return UnknownType(arity: other.arity - 1)
        }
        return nil
    }

    public func product(with other: AlloyType) -> AlloyType {
        RelationType(columnTypes: [UnivType.instance, UnivType.instance, other])
    }

    public var description: String { "iden" }
}

/// Unknown type (used during type inference)
public struct UnknownType: AlloyType {
    public let arity: Int

    public init(arity: Int = 1) {
        self.arity = arity
    }

    public func isSubtypeOf(_ other: AlloyType) -> Bool {
        // Default to inference mode for backwards compatibility
        isSubtypeOf(other, context: .inference)
    }

    /// Check subtype relationship with explicit context
    /// - Parameters:
    ///   - other: The type to check against
    ///   - context: The type checking context (inference or validation)
    /// - Returns: true if this type is a subtype of other in the given context
    public func isSubtypeOf(_ other: AlloyType, context: TypeCheckingContext) -> Bool {
        switch context {
        case .inference:
            // During inference, unknown is compatible with anything
            return true
        case .validation:
            // During validation, unknown is only compatible with itself or univ
            return other is UnknownType || other is UnivType
        }
    }

    public func join(with other: AlloyType) -> AlloyType? {
        guard other.arity >= 1 else { return nil }
        let resultArity = arity + other.arity - 2
        return resultArity >= 1 ? UnknownType(arity: resultArity) : nil
    }

    public func product(with other: AlloyType) -> AlloyType {
        UnknownType(arity: arity + other.arity)
    }

    public var description: String { "?" }
}

/// Error type (represents a type error)
public struct ErrorType: AlloyType {
    public static let instance = ErrorType()

    public let message: String

    public init(message: String = "type error") {
        self.message = message
    }

    public var arity: Int { 0 }

    public func isSubtypeOf(_ other: AlloyType) -> Bool { false }
    public func join(with other: AlloyType) -> AlloyType? { nil }
    public func product(with other: AlloyType) -> AlloyType { self }

    public var description: String { "error: \(message)" }
}

// MARK: - Type Utilities

/// Compute the union type of two types
public func unionType(_ t1: AlloyType, _ t2: AlloyType) -> AlloyType? {
    guard t1.arity == t2.arity else { return nil }

    // If same type, return it
    if let s1 = t1 as? SigType, let s2 = t2 as? SigType, s1 === s2 {
        return s1
    }

    // Find common supertype for signatures
    if let s1 = t1 as? SigType, let s2 = t2 as? SigType {
        if s1.isSubtypeOf(s2) { return s2 }
        if s2.isSubtypeOf(s1) { return s1 }
        // No common type, return univ
        return UnivType.instance
    }

    // For relations, return Unknown
    return UnknownType(arity: t1.arity)
}

/// Compute the intersection type of two types
public func intersectionType(_ t1: AlloyType, _ t2: AlloyType) -> AlloyType? {
    guard t1.arity == t2.arity else { return nil }

    // If same type, return it
    if let s1 = t1 as? SigType, let s2 = t2 as? SigType, s1 === s2 {
        return s1
    }

    // Find common subtype for signatures
    if let s1 = t1 as? SigType, let s2 = t2 as? SigType {
        if s1.isSubtypeOf(s2) { return s1 }
        if s2.isSubtypeOf(s1) { return s2 }
        // No common type, return none
        return NoneType.instance
    }

    return UnknownType(arity: t1.arity)
}
