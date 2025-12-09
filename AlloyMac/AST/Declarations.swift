import Foundation

// MARK: - Module Node

/// Root AST node representing an Alloy module
public final class ModuleNode: ASTNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    /// Optional module declaration
    public var moduleDecl: ModuleDeclNode?

    /// Import statements (open ...)
    public var opens: [OpenNode]

    /// All top-level declarations (signatures, facts, predicates, etc.)
    public var paragraphs: [any DeclNode]

    public init(span: SourceSpan,
                moduleDecl: ModuleDeclNode? = nil,
                opens: [OpenNode] = [],
                paragraphs: [any DeclNode] = []) {
        self.span = span
        self.moduleDecl = moduleDecl
        self.opens = opens
        self.paragraphs = paragraphs
    }

    public var children: [any ASTNode] {
        var result: [any ASTNode] = []
        if let decl = moduleDecl { result.append(decl) }
        result.append(contentsOf: opens)
        result.append(contentsOf: paragraphs)
        return result
    }

    public var description: String { "Module" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Module Declaration

/// Module declaration: `module name[Params]`
public final class ModuleDeclNode: ASTNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var name: QualifiedName
    public var parameters: [Identifier]

    public init(span: SourceSpan, name: QualifiedName, parameters: [Identifier] = []) {
        self.span = span
        self.name = name
        self.parameters = parameters
    }

    public var children: [any ASTNode] { [] }
    public var description: String { "ModuleDecl(\(name.simpleName))" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Open (Import) Node

/// Import statement: `open library[Args] as alias`
public final class OpenNode: ASTNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var modulePath: QualifiedName
    public var arguments: [QualifiedName]
    public var alias: Identifier?

    public init(span: SourceSpan,
                modulePath: QualifiedName,
                arguments: [QualifiedName] = [],
                alias: Identifier? = nil) {
        self.span = span
        self.modulePath = modulePath
        self.arguments = arguments
        self.alias = alias
    }

    public var children: [any ASTNode] { [] }
    public var description: String { "Open(\(modulePath.simpleName))" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Signature Declaration

/// Signature extension type
public enum SigExtension {
    case extends(QualifiedName)        // extends Parent
    case subset([QualifiedName])       // in Parent1 + Parent2
}

/// Signature declaration: `[abstract] [mult] sig Name [extends Parent] { fields } [fact]`
public final class SigDeclNode: DeclNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    /// Is this an abstract signature?
    public var isAbstract: Bool

    /// Multiplicity constraint (one, lone, some)
    public var multiplicity: Multiplicity?

    /// Is this a variable signature? (Alloy 6)
    public var isVariable: Bool

    /// Signature names (can declare multiple: sig A, B, C {})
    public var names: [Identifier]

    /// Extension clause
    public var ext: SigExtension?

    /// Field declarations
    public var fields: [FieldDeclNode]

    /// Appended signature fact
    public var sigFact: BlockFormula?

    public init(span: SourceSpan,
                isAbstract: Bool = false,
                multiplicity: Multiplicity? = nil,
                isVariable: Bool = false,
                names: [Identifier],
                ext: SigExtension? = nil,
                fields: [FieldDeclNode] = [],
                sigFact: BlockFormula? = nil) {
        self.span = span
        self.isAbstract = isAbstract
        self.multiplicity = multiplicity
        self.isVariable = isVariable
        self.names = names
        self.ext = ext
        self.fields = fields
        self.sigFact = sigFact
    }

    public var name: String? { names.first?.name }

    public var children: [any ASTNode] {
        var result: [any ASTNode] = []
        result.append(contentsOf: fields)
        if let fact = sigFact { result.append(fact) }
        return result
    }

    public var description: String {
        let prefix = isAbstract ? "abstract " : ""
        let mult = multiplicity.map { "\($0) " } ?? ""
        return "\(prefix)\(mult)sig \(name ?? "?")"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Field Declaration

/// Field declaration: `[var] [disj] names: type`
public final class FieldDeclNode: ASTNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    /// Is this a variable (mutable) field? (Alloy 6)
    public var isVariable: Bool

    /// Is this disjoint?
    public var isDisjoint: Bool

    /// Field names
    public var names: [Identifier]

    /// Field type expression
    public var typeExpr: any ExprNode

    public init(span: SourceSpan,
                isVariable: Bool = false,
                isDisjoint: Bool = false,
                names: [Identifier],
                typeExpr: any ExprNode) {
        self.span = span
        self.isVariable = isVariable
        self.isDisjoint = isDisjoint
        self.names = names
        self.typeExpr = typeExpr
    }

    public var children: [any ASTNode] { [typeExpr] }

    public var description: String {
        let varStr = isVariable ? "var " : ""
        let disjStr = isDisjoint ? "disj " : ""
        let namesStr = names.map(\.name).joined(separator: ", ")
        return "\(varStr)\(disjStr)\(namesStr): ..."
    }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Fact Declaration

/// Fact declaration: `fact [name] { formula }`
public final class FactDeclNode: DeclNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var factName: Identifier?
    public var body: any FormulaNode

    public init(span: SourceSpan, name: Identifier? = nil, body: any FormulaNode) {
        self.span = span
        self.factName = name
        self.body = body
    }

    public var name: String? { factName?.name }
    public var children: [any ASTNode] { [body] }
    public var description: String { "fact \(name ?? "")" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Predicate Declaration

/// Parameter declaration for predicates/functions
public struct ParamDecl: Sendable {
    public var isDisjoint: Bool
    public var names: [Identifier]
    public var typeExpr: any ExprNode

    public init(isDisjoint: Bool = false, names: [Identifier], typeExpr: any ExprNode) {
        self.isDisjoint = isDisjoint
        self.names = names
        self.typeExpr = typeExpr
    }
}

/// Predicate declaration: `pred [Sig.]name[params] { formula }`
public final class PredDeclNode: DeclNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    /// For method-style: pred Sig.name
    public var receiver: QualifiedName?

    /// Predicate name
    public var predName: Identifier

    /// Parameters
    public var params: [ParamDecl]

    /// Body formula
    public var body: (any FormulaNode)?

    public init(span: SourceSpan,
                receiver: QualifiedName? = nil,
                name: Identifier,
                params: [ParamDecl] = [],
                body: (any FormulaNode)? = nil) {
        self.span = span
        self.receiver = receiver
        self.predName = name
        self.params = params
        self.body = body
    }

    public var name: String? { predName.name }

    public var children: [any ASTNode] {
        if let b = body { return [b] }
        return []
    }

    public var description: String {
        let recv = receiver.map { "\($0.simpleName)." } ?? ""
        return "pred \(recv)\(predName.name)"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Function Declaration

/// Function declaration: `fun [Sig.]name[params]: returnType { expr }`
public final class FunDeclNode: DeclNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    /// For method-style: fun Sig.name
    public var receiver: QualifiedName?

    /// Function name
    public var funName: Identifier

    /// Parameters
    public var params: [ParamDecl]

    /// Return type
    public var returnType: (any ExprNode)?

    /// Body expression
    public var body: (any ExprNode)?

    public init(span: SourceSpan,
                receiver: QualifiedName? = nil,
                name: Identifier,
                params: [ParamDecl] = [],
                returnType: (any ExprNode)? = nil,
                body: (any ExprNode)? = nil) {
        self.span = span
        self.receiver = receiver
        self.funName = name
        self.params = params
        self.returnType = returnType
        self.body = body
    }

    public var name: String? { funName.name }

    public var children: [any ASTNode] {
        var result: [any ASTNode] = []
        if let rt = returnType { result.append(rt) }
        if let b = body { result.append(b) }
        return result
    }

    public var description: String {
        let recv = receiver.map { "\($0.simpleName)." } ?? ""
        return "fun \(recv)\(funName.name)"
    }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Assertion Declaration

/// Assertion declaration: `assert [name] { formula }`
public final class AssertDeclNode: DeclNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var assertName: Identifier?
    public var body: any FormulaNode

    public init(span: SourceSpan, name: Identifier? = nil, body: any FormulaNode) {
        self.span = span
        self.assertName = name
        self.body = body
    }

    public var name: String? { assertName?.name }
    public var children: [any ASTNode] { [body] }
    public var description: String { "assert \(name ?? "")" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Enum Declaration

/// Enum declaration: `enum Name { Value1, Value2, ... }`
public final class EnumDeclNode: DeclNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var enumName: Identifier
    public var values: [Identifier]

    public init(span: SourceSpan, name: Identifier, values: [Identifier]) {
        self.span = span
        self.enumName = name
        self.values = values
    }

    public var name: String? { enumName.name }
    public var children: [any ASTNode] { [] }
    public var description: String { "enum \(enumName.name)" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Command Nodes

/// Scope bound for a type
public struct TypeScope: Sendable {
    public var isExactly: Bool
    public var count: Int
    public var typeName: QualifiedName

    public init(isExactly: Bool = false, count: Int, typeName: QualifiedName) {
        self.isExactly = isExactly
        self.count = count
        self.typeName = typeName
    }
}

/// Scope specification for commands
public struct CommandScope: Sendable {
    /// Default scope (for N)
    public var defaultScope: Int?

    /// Type-specific scopes
    public var typeScopes: [TypeScope]

    /// Temporal steps bound (Alloy 6)
    public var steps: Int?

    /// Expected result
    public var expect: Int?

    public init(defaultScope: Int? = nil,
                typeScopes: [TypeScope] = [],
                steps: Int? = nil,
                expect: Int? = nil) {
        self.defaultScope = defaultScope
        self.typeScopes = typeScopes
        self.steps = steps
        self.expect = expect
    }
}

/// Run command: `run [name] { formula } for scope`
public final class RunCmdNode: DeclNode, CommandNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var cmdName: Identifier?
    public var body: (any FormulaNode)?
    public var targetName: QualifiedName?
    public var scope: CommandScope?

    public init(span: SourceSpan,
                name: Identifier? = nil,
                body: (any FormulaNode)? = nil,
                targetName: QualifiedName? = nil,
                scope: CommandScope? = nil) {
        self.span = span
        self.cmdName = name
        self.body = body
        self.targetName = targetName
        self.scope = scope
    }

    public var name: String? { cmdName?.name }

    public var children: [any ASTNode] {
        if let b = body { return [b] }
        return []
    }

    public var description: String { "run \(name ?? targetName?.simpleName ?? "")" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

/// Check command: `check [name] { formula } for scope`
public final class CheckCmdNode: DeclNode, CommandNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var cmdName: Identifier?
    public var body: (any FormulaNode)?
    public var targetName: QualifiedName?
    public var scope: CommandScope?

    public init(span: SourceSpan,
                name: Identifier? = nil,
                body: (any FormulaNode)? = nil,
                targetName: QualifiedName? = nil,
                scope: CommandScope? = nil) {
        self.span = span
        self.cmdName = name
        self.body = body
        self.targetName = targetName
        self.scope = scope
    }

    public var name: String? { cmdName?.name }

    public var children: [any ASTNode] {
        if let b = body { return [b] }
        return []
    }

    public var description: String { "check \(name ?? targetName?.simpleName ?? "")" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}
