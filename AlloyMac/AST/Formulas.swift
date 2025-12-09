import Foundation

// MARK: - Logical Binary Operators

/// Binary logical operators
public enum LogicalOp: String, Sendable {
    case and = "&&"
    case or = "||"
    case implies = "=>"
    case iff = "<=>"

    // Keyword variants
    case andKeyword = "and"
    case orKeyword = "or"
}

// MARK: - Logical Unary Operators

/// Unary logical operators
public enum LogicalUnaryOp: String, Sendable {
    case not = "!"
    case notKeyword = "not"
}

// MARK: - Comparison Operators

/// Comparison operators
public enum CompareOp: String, Sendable {
    case equal = "="
    case notEqual = "!="
    case `in` = "in"
    case notIn = "not in"
    case less = "<"
    case lessEqual = "=<"
    case greater = ">"
    case greaterEqual = ">="
}

// MARK: - Quantifiers

/// Quantifier types
public enum Quantifier: String, Sendable {
    case all = "all"
    case some = "some"
    case no = "no"
    case one = "one"
    case lone = "lone"
    case sum = "sum"
}

// MARK: - Binary Formula

/// Binary formula: left op right
public final class BinaryFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var left: any FormulaNode
    public var op: LogicalOp
    public var right: any FormulaNode

    public init(span: SourceSpan, left: any FormulaNode, op: LogicalOp, right: any FormulaNode) {
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

// MARK: - Unary Formula

/// Unary formula: op operand
public final class UnaryFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var op: LogicalUnaryOp
    public var operand: any FormulaNode

    public init(span: SourceSpan, op: LogicalUnaryOp, operand: any FormulaNode) {
        self.span = span
        self.op = op
        self.operand = operand
    }

    public var children: [any ASTNode] { [operand] }
    public var description: String { "\(op.rawValue)\(operand)" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Quantified Formula

/// Quantified formula: quant decls | formula
public final class QuantifiedFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var quantifier: Quantifier
    public var decls: [QuantDecl]
    public var formula: any FormulaNode

    public init(span: SourceSpan,
                quantifier: Quantifier,
                decls: [QuantDecl],
                formula: any FormulaNode) {
        self.span = span
        self.quantifier = quantifier
        self.decls = decls
        self.formula = formula
    }

    public var children: [any ASTNode] { [formula] }
    public var description: String { "\(quantifier.rawValue) ... | ..." }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Comparison Formula

/// Comparison formula: left op right
public final class CompareFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var left: any ExprNode
    public var op: CompareOp
    public var right: any ExprNode

    public init(span: SourceSpan, left: any ExprNode, op: CompareOp, right: any ExprNode) {
        self.span = span
        self.left = left
        self.op = op
        self.right = right
    }

    public var children: [any ASTNode] { [left, right] }
    public var description: String { "\(left) \(op.rawValue) \(right)" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Let Formula

/// Let formula: let bindings | formula
public final class LetFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var bindings: [LetBinding]
    public var body: any FormulaNode

    public init(span: SourceSpan, bindings: [LetBinding], body: any FormulaNode) {
        self.span = span
        self.bindings = bindings
        self.body = body
    }

    public var children: [any ASTNode] { [body] }
    public var description: String { "let ... | ..." }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Block Formula

/// Block of formulas: { formula1 formula2 ... }
public final class BlockFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var formulas: [any FormulaNode]

    public init(span: SourceSpan, formulas: [any FormulaNode]) {
        self.span = span
        self.formulas = formulas
    }

    public var children: [any ASTNode] { formulas.map { $0 as any ASTNode } }
    public var description: String { "{ ... }" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Call Formula

/// Predicate call as formula: pred[args]
public final class CallFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var callee: QualifiedName
    public var args: [any ExprNode]

    public init(span: SourceSpan, callee: QualifiedName, args: [any ExprNode]) {
        self.span = span
        self.callee = callee
        self.args = args
    }

    public var children: [any ASTNode] { args.map { $0 as any ASTNode } }
    public var description: String { "\(callee.simpleName)[...]" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Multiplicity Formula

/// Multiplicity test as formula: some/no/one/lone expr
public final class MultFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var multiplicity: Quantifier  // some, no, one, lone
    public var expr: any ExprNode

    public init(span: SourceSpan, multiplicity: Quantifier, expr: any ExprNode) {
        self.span = span
        self.multiplicity = multiplicity
        self.expr = expr
    }

    public var children: [any ASTNode] { [expr] }
    public var description: String { "\(multiplicity.rawValue) \(expr)" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Expression as Formula

/// Wraps an expression to be used as a formula (for boolean expressions)
public final class ExprFormula: FormulaNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var expr: any ExprNode

    public init(span: SourceSpan, expr: any ExprNode) {
        self.span = span
        self.expr = expr
    }

    public var children: [any ASTNode] { [expr] }
    public var description: String { "\(expr)" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}
