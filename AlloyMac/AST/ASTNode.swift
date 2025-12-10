import Foundation

// MARK: - AST Node ID

/// Unique identifier for AST nodes
public struct ASTNodeID: Hashable, Sendable {
    private let uuid: UUID

    public init() {
        self.uuid = UUID()
    }
}

// MARK: - Base AST Protocol

/// Base protocol for all AST nodes
public protocol ASTNode: AnyObject, CustomStringConvertible {
    /// Unique identifier for this node
    var id: ASTNodeID { get }

    /// Source location span
    var span: SourceSpan { get }

    /// All child nodes for traversal
    var children: [any ASTNode] { get }

    /// Accept a visitor
    func accept<V: ASTVisitor>(_ visitor: V) -> V.Result
}

// MARK: - Node Categories

/// Protocol for declaration nodes (sig, pred, fun, fact, etc.)
public protocol DeclNode: ASTNode {
    var name: String? { get }
}

/// Protocol for expression nodes (relational expressions)
public protocol ExprNode: ASTNode {}

/// Protocol for formula nodes (boolean constraints)
public protocol FormulaNode: ASTNode {}

/// Protocol for command nodes (run, check)
public protocol CommandNode: ASTNode {}

// MARK: - Identifier

/// An identifier with source location
public struct Identifier: Equatable, Hashable, Sendable {
    public let name: String
    public let span: SourceSpan

    public init(name: String, span: SourceSpan) {
        self.name = name
        self.span = span
    }

    public init(span: SourceSpan, name: String) {
        self.name = name
        self.span = span
    }
}

/// A qualified name (e.g., util/ordering or just Name)
public struct QualifiedName: Equatable, Hashable, Sendable {
    public let parts: [Identifier]
    public let span: SourceSpan

    public init(parts: [Identifier], span: SourceSpan) {
        self.parts = parts
        self.span = span
    }

    public init(parts: [Identifier]) {
        self.parts = parts
        if let first = parts.first, let last = parts.last {
            self.span = SourceSpan(start: first.span.start, end: last.span.end)
        } else {
            self.span = SourceSpan.zero
        }
    }

    public init(single: Identifier) {
        self.parts = [single]
        self.span = single.span
    }

    public var simpleName: String {
        parts.last?.name ?? ""
    }

    public var isQualified: Bool {
        parts.count > 1
    }
}

// MARK: - Multiplicity

/// Multiplicity keywords
public enum Multiplicity: String, Sendable {
    case set = "set"     // zero or more (default)
    case one = "one"     // exactly one
    case lone = "lone"   // zero or one
    case some = "some"   // one or more
    case seq = "seq"     // sequence
}

// MARK: - AST Visitor Protocol

/// Visitor pattern for AST traversal
public protocol ASTVisitor {
    associatedtype Result

    // Module level
    func visit(_ node: ModuleNode) -> Result
    func visit(_ node: ModuleDeclNode) -> Result
    func visit(_ node: OpenNode) -> Result

    // Declarations
    func visit(_ node: SigDeclNode) -> Result
    func visit(_ node: FieldDeclNode) -> Result
    func visit(_ node: FactDeclNode) -> Result
    func visit(_ node: PredDeclNode) -> Result
    func visit(_ node: FunDeclNode) -> Result
    func visit(_ node: AssertDeclNode) -> Result
    func visit(_ node: EnumDeclNode) -> Result

    // Commands
    func visit(_ node: RunCmdNode) -> Result
    func visit(_ node: CheckCmdNode) -> Result

    // Expressions
    func visit(_ node: NameExpr) -> Result
    func visit(_ node: BinaryExpr) -> Result
    func visit(_ node: UnaryExpr) -> Result
    func visit(_ node: MultExpr) -> Result
    func visit(_ node: ArrowExpr) -> Result
    func visit(_ node: CallExpr) -> Result
    func visit(_ node: BoxJoinExpr) -> Result
    func visit(_ node: ComprehensionExpr) -> Result
    func visit(_ node: LetExpr) -> Result
    func visit(_ node: IfExpr) -> Result
    func visit(_ node: IntLiteralExpr) -> Result
    func visit(_ node: BlockExpr) -> Result

    // Formulas
    func visit(_ node: BinaryFormula) -> Result
    func visit(_ node: UnaryFormula) -> Result
    func visit(_ node: QuantifiedFormula) -> Result
    func visit(_ node: MultFormula) -> Result
    func visit(_ node: ExprFormula) -> Result
    func visit(_ node: CompareFormula) -> Result
    func visit(_ node: LetFormula) -> Result
    func visit(_ node: BlockFormula) -> Result
    func visit(_ node: CallFormula) -> Result
    func visit(_ node: TemporalUnaryFormula) -> Result
    func visit(_ node: TemporalBinaryFormula) -> Result
}

// MARK: - Default Visitor Implementations

public extension ASTVisitor where Result == Void {
    func visit(_ node: ModuleNode) {
        node.moduleDecl?.accept(self)
        node.opens.forEach { $0.accept(self) }
        node.paragraphs.forEach { $0.accept(self) }
    }

    func visit(_ node: ModuleDeclNode) {}
    func visit(_ node: OpenNode) {}
    func visit(_ node: SigDeclNode) {
        node.fields.forEach { $0.accept(self) }
        node.sigFact?.accept(self)
    }
    func visit(_ node: FieldDeclNode) {}
    func visit(_ node: FactDeclNode) { node.body.accept(self) }
    func visit(_ node: PredDeclNode) { node.body?.accept(self) }
    func visit(_ node: FunDeclNode) { node.body?.accept(self) }
    func visit(_ node: AssertDeclNode) { node.body.accept(self) }
    func visit(_ node: EnumDeclNode) {}
    func visit(_ node: RunCmdNode) { node.body?.accept(self) }
    func visit(_ node: CheckCmdNode) { node.body?.accept(self) }
    func visit(_ node: NameExpr) {}
    func visit(_ node: BinaryExpr) {
        node.left.accept(self)
        node.right.accept(self)
    }
    func visit(_ node: UnaryExpr) { node.operand.accept(self) }
    func visit(_ node: MultExpr) { node.expr.accept(self) }
    func visit(_ node: ArrowExpr) {
        node.left.accept(self)
        node.right.accept(self)
    }
    func visit(_ node: CallExpr) { node.args.forEach { $0.accept(self) } }
    func visit(_ node: BoxJoinExpr) {
        node.left.accept(self)
        node.args.forEach { $0.accept(self) }
    }
    func visit(_ node: ComprehensionExpr) { node.formula.accept(self) }
    func visit(_ node: LetExpr) { node.body.accept(self) }
    func visit(_ node: IfExpr) {
        node.condition.accept(self)
        node.thenExpr.accept(self)
        node.elseExpr.accept(self)
    }
    func visit(_ node: IntLiteralExpr) {}
    func visit(_ node: BlockExpr) { node.formulas.forEach { $0.accept(self) } }
    func visit(_ node: BinaryFormula) {
        node.left.accept(self)
        node.right.accept(self)
    }
    func visit(_ node: UnaryFormula) { node.operand.accept(self) }
    func visit(_ node: QuantifiedFormula) { node.formula.accept(self) }
    func visit(_ node: MultFormula) { node.expr.accept(self) }
    func visit(_ node: ExprFormula) { node.expr.accept(self) }
    func visit(_ node: CompareFormula) {
        node.left.accept(self)
        node.right.accept(self)
    }
    func visit(_ node: LetFormula) { node.body.accept(self) }
    func visit(_ node: BlockFormula) { node.formulas.forEach { $0.accept(self) } }
    func visit(_ node: CallFormula) { node.args.forEach { $0.accept(self) } }
    func visit(_ node: TemporalUnaryFormula) { node.operand.accept(self) }
    func visit(_ node: TemporalBinaryFormula) {
        node.left.accept(self)
        node.right.accept(self)
    }
}
