import Foundation

// MARK: - Symbol Kind

/// The kind of symbol
public enum SymbolKind: String, Sendable {
    case signature
    case field
    case predicate
    case function
    case assertion
    case fact
    case enumType
    case enumValue
    case parameter
    case quantifierVar
    case letVar
    case module
}

// MARK: - Symbol Protocol

/// Base protocol for all symbols
public protocol Symbol: AnyObject, CustomStringConvertible, Sendable {
    /// The name of this symbol
    var name: String { get }

    /// The kind of symbol
    var kind: SymbolKind { get }

    /// The type of this symbol
    var type: AlloyType { get }

    /// Source location where this symbol was defined
    var definedAt: SourceSpan { get }

    /// The scope containing this symbol
    var scope: Scope? { get set }
}

// MARK: - Signature Symbol

/// A signature symbol
public final class SigSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.signature
    public let sigType: SigType
    public var type: AlloyType { sigType }
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// Fields declared in this signature
    public var fields: [FieldSymbol] = []

    /// Child signatures (that extend this one)
    public var children: [SigSymbol] = []

    /// Parent signature symbol (if extends)
    public weak var parent: SigSymbol? {
        didSet {
            sigType.parent = parent?.sigType
        }
    }

    /// Subset parents (for `in` clause)
    public var subsetOf: [SigSymbol] = []

    /// Appended signature fact
    public var sigFact: (any FormulaNode)?

    /// Whether this signature is private
    public let isPrivate: Bool

    public init(name: String,
                definedAt: SourceSpan,
                isAbstract: Bool = false,
                isVariable: Bool = false,
                isPrivate: Bool = false,
                multiplicity: Multiplicity? = nil) {
        self.name = name
        self.definedAt = definedAt
        self.isPrivate = isPrivate
        self.sigType = SigType(
            name: name,
            isAbstract: isAbstract,
            isVariable: isVariable,
            multiplicity: multiplicity
        )
    }

    public var description: String {
        var desc = ""
        if sigType.isAbstract { desc += "abstract " }
        if let mult = sigType.multiplicity { desc += "\(mult) " }
        if sigType.isVariable { desc += "var " }
        desc += "sig \(name)"
        if let p = parent { desc += " extends \(p.name)" }
        return desc
    }

    /// Get all ancestor signatures
    public var ancestors: [SigSymbol] {
        var result: [SigSymbol] = []
        var current = parent
        while let p = current {
            result.append(p)
            current = p.parent
        }
        return result
    }

    /// Get all descendant signatures
    public var descendants: [SigSymbol] {
        var result: [SigSymbol] = []
        for child in children {
            result.append(child)
            result.append(contentsOf: child.descendants)
        }
        return result
    }

    /// Get all fields including inherited
    public var allFields: [FieldSymbol] {
        var result = fields
        if let p = parent {
            result.append(contentsOf: p.allFields)
        }
        return result
    }
}

// MARK: - Field Symbol

/// A field symbol (relation from signature to type)
public final class FieldSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.field
    public var type: AlloyType
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// The signature containing this field
    public weak var owner: SigSymbol?

    /// Is this a variable (mutable) field?
    public let isVariable: Bool

    /// Is this field disjoint?
    public let isDisjoint: Bool

    public init(name: String,
                type: AlloyType,
                definedAt: SourceSpan,
                owner: SigSymbol? = nil,
                isVariable: Bool = false,
                isDisjoint: Bool = false) {
        self.name = name
        self.type = type
        self.definedAt = definedAt
        self.owner = owner
        self.isVariable = isVariable
        self.isDisjoint = isDisjoint
    }

    public var description: String {
        var desc = ""
        if isVariable { desc += "var " }
        if isDisjoint { desc += "disj " }
        desc += "\(name): \(type)"
        return desc
    }

    /// The full relation type including the owner signature
    public var fullType: AlloyType {
        guard let owner = owner else { return type }
        if type.arity == 1 {
            return RelationType(columnTypes: [owner.sigType, type])
        } else if let relType = type as? RelationType {
            return RelationType(columnTypes: [owner.sigType] + relType.columnTypes)
        }
        return type
    }
}

// MARK: - Predicate Symbol

/// A predicate symbol
public final class PredSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.predicate
    public var type: AlloyType { BoolType.instance }
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// Parameters
    public var parameters: [ParamSymbol] = []

    /// Receiver type (for method-style predicates)
    public var receiver: SigSymbol?

    /// The body AST node
    public var body: (any FormulaNode)?

    /// Whether this predicate is private
    public let isPrivate: Bool

    public init(name: String,
                definedAt: SourceSpan,
                receiver: SigSymbol? = nil,
                isPrivate: Bool = false) {
        self.name = name
        self.definedAt = definedAt
        self.receiver = receiver
        self.isPrivate = isPrivate
    }

    public var description: String {
        let recv = receiver.map { "\($0.name)." } ?? ""
        let params = parameters.map { $0.description }.joined(separator: ", ")
        return "pred \(recv)\(name)[\(params)]"
    }

    /// The full name including receiver
    public var fullName: String {
        if let recv = receiver {
            return "\(recv.name).\(name)"
        }
        return name
    }
}

// MARK: - Function Symbol

/// A function symbol
public final class FunSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.function
    public var type: AlloyType
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// Parameters
    public var parameters: [ParamSymbol] = []

    /// Receiver type (for method-style functions)
    public var receiver: SigSymbol?

    /// The body AST node
    public var body: (any ExprNode)?

    /// Whether this function is private
    public let isPrivate: Bool

    public init(name: String,
                returnType: AlloyType,
                definedAt: SourceSpan,
                receiver: SigSymbol? = nil,
                isPrivate: Bool = false) {
        self.name = name
        self.type = returnType
        self.definedAt = definedAt
        self.receiver = receiver
        self.isPrivate = isPrivate
    }

    public var description: String {
        let recv = receiver.map { "\($0.name)." } ?? ""
        let params = parameters.map { $0.description }.joined(separator: ", ")
        return "fun \(recv)\(name)[\(params)]: \(type)"
    }

    /// The full name including receiver
    public var fullName: String {
        if let recv = receiver {
            return "\(recv.name).\(name)"
        }
        return name
    }
}

// MARK: - Assertion Symbol

/// An assertion symbol
public final class AssertSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.assertion
    public var type: AlloyType { BoolType.instance }
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// The body formula
    public var body: (any FormulaNode)?

    public init(name: String, definedAt: SourceSpan) {
        self.name = name
        self.definedAt = definedAt
    }

    public var description: String { "assert \(name)" }
}

// MARK: - Fact Symbol

/// A fact symbol
public final class FactSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.fact
    public var type: AlloyType { BoolType.instance }
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// The body formula
    public var body: (any FormulaNode)?

    public init(name: String, definedAt: SourceSpan) {
        self.name = name
        self.definedAt = definedAt
    }

    public var description: String { "fact \(name)" }
}

// MARK: - Enum Symbol

/// An enum type symbol
public final class EnumSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.enumType
    public let sigType: SigType
    public var type: AlloyType { sigType }
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// The enum values
    public var values: [EnumValueSymbol] = []

    public init(name: String, definedAt: SourceSpan) {
        self.name = name
        self.definedAt = definedAt
        self.sigType = SigType(name: name, isAbstract: true)
    }

    public var description: String { "enum \(name)" }
}

/// An enum value symbol
public final class EnumValueSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.enumValue
    public let sigType: SigType
    public var type: AlloyType { sigType }
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// The parent enum
    public weak var enumSymbol: EnumSymbol?

    public init(name: String, enumSymbol: EnumSymbol, definedAt: SourceSpan) {
        self.name = name
        self.enumSymbol = enumSymbol
        self.definedAt = definedAt
        self.sigType = SigType(
            name: name,
            parent: enumSymbol.sigType,
            multiplicity: .one
        )
    }

    public var description: String { "enum value \(name)" }
}

// MARK: - Parameter Symbol

/// A parameter symbol (for predicates/functions)
public final class ParamSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.parameter
    public var type: AlloyType
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// Is this parameter disjoint?
    public let isDisjoint: Bool

    public init(name: String,
                type: AlloyType,
                definedAt: SourceSpan,
                isDisjoint: Bool = false) {
        self.name = name
        self.type = type
        self.definedAt = definedAt
        self.isDisjoint = isDisjoint
    }

    public var description: String {
        let disj = isDisjoint ? "disj " : ""
        return "\(disj)\(name): \(type)"
    }
}

// MARK: - Quantifier Variable Symbol

/// A quantifier-bound variable symbol
public final class QuantVarSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.quantifierVar
    public var type: AlloyType
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// Is this variable disjoint from others?
    public let isDisjoint: Bool

    public init(name: String,
                type: AlloyType,
                definedAt: SourceSpan,
                isDisjoint: Bool = false) {
        self.name = name
        self.type = type
        self.definedAt = definedAt
        self.isDisjoint = isDisjoint
    }

    public var description: String {
        let disj = isDisjoint ? "disj " : ""
        return "\(disj)\(name): \(type)"
    }
}

// MARK: - Let Variable Symbol

/// A let-bound variable symbol
public final class LetVarSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.letVar
    public var type: AlloyType
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// The expression bound to this variable
    public var boundExpr: (any ExprNode)?

    public init(name: String,
                type: AlloyType,
                definedAt: SourceSpan) {
        self.name = name
        self.type = type
        self.definedAt = definedAt
    }

    public var description: String { "let \(name) = ..." }
}

// MARK: - Module Symbol

/// A module symbol (for imports)
public final class ModuleSymbol: Symbol, @unchecked Sendable {
    public let name: String
    public let kind = SymbolKind.module
    public var type: AlloyType { UnknownType() }
    public let definedAt: SourceSpan
    public weak var scope: Scope?

    /// The path to this module
    public let path: [String]

    /// Alias for this module (from `as` clause)
    public var alias: String?

    /// Arguments passed to the module
    public var arguments: [SigSymbol] = []

    /// Symbols exported by this module
    public var exports: [String: Symbol] = [:]

    public init(name: String, path: [String], definedAt: SourceSpan) {
        self.name = name
        self.path = path
        self.definedAt = definedAt
    }

    public var description: String {
        let pathStr = path.joined(separator: "/")
        if let a = alias {
            return "module \(pathStr) as \(a)"
        }
        return "module \(pathStr)"
    }
}
