import Foundation

// MARK: - Temporal Unary Operators

/// Temporal unary operators (LTL)
public enum TemporalUnaryOp: String, Sendable {
    // Future operators
    case always = "always"
    case eventually = "eventually"
    case after = "after"

    // Past operators
    case historically = "historically"
    case once = "once"
    case before = "before"
}

// MARK: - Temporal Binary Operators

/// Temporal binary operators (LTL)
public enum TemporalBinaryOp: String, Sendable {
    // Future operators
    case until = "until"
    case releases = "releases"
    case semicolon = ";"     // a ; b  = a and after b

    // Past operators
    case since = "since"
    case triggered = "triggered"
}

// MARK: - Temporal Unary Formula

/// Temporal unary formula: always/eventually/after/... formula
public final class TemporalUnaryFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var op: TemporalUnaryOp
    public var operand: any FormulaNode

    public init(span: SourceSpan, op: TemporalUnaryOp, operand: any FormulaNode) {
        self.span = span
        self.op = op
        self.operand = operand
    }

    public var children: [any ASTNode] { [operand] }
    public var description: String { "\(op.rawValue) \(operand)" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Temporal Binary Formula

/// Temporal binary formula: left until/releases/since/... right
public final class TemporalBinaryFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var left: any FormulaNode
    public var op: TemporalBinaryOp
    public var right: any FormulaNode

    public init(span: SourceSpan, left: any FormulaNode, op: TemporalBinaryOp, right: any FormulaNode) {
        self.span = span
        self.left = left
        self.op = op
        self.right = right
    }

    public var children: [any ASTNode] { [left, right] }
    public var description: String { "(\(left) \(op.rawValue) \(right))" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}
