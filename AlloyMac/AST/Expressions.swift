import Foundation

// MARK: - Binary Operators

/// Binary operators for expressions
public enum BinaryOp: String, Sendable {
    // Set operations
    case union = "+"           // a + b
    case difference = "-"      // a - b
    case intersection = "&"    // a & b
    case override = "++"       // a ++ b

    // Relational
    case join = "."            // a.b
    case product = "->"        // a -> b
    case domainRestrict = "<:" // a <: b
    case rangeRestrict = ":>"  // a :> b

    // Arithmetic (integers)
    case add = "plus"
    case sub = "minus"
    case mul = "mul"
    case div = "div"
    case rem = "rem"

    // Shift
    case shl = "<<"
    case shr = ">>"
    case sha = ">>>"
}

// MARK: - Unary Operators

/// Unary operators for expressions
public enum UnaryOp: String, Sendable {
    case transpose = "~"                    // ~r
    case transitiveClosure = "^"            // ^r
    case reflexiveTransitiveClosure = "*"   // *r
    case cardinality = "#"                  // #s
    case negate = "-"                       // -n (integer)
    case prime = "'"                        // r' (next state, Alloy 6)

    // Set/multiplicity tests used as expressions
    case setOf = "set"
    case someOf = "some"
    case loneOf = "lone"
    case oneOf = "one"
    case noOf = "no"
}

// MARK: - Name Expression

/// Name reference: identifier or qualified name
public final class NameExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var name: QualifiedName

    public init(span: SourceSpan, name: QualifiedName) {
        self.span = span
        self.name = name
    }

    public convenience init(span: SourceSpan, identifier: Identifier) {
        self.init(span: span, name: QualifiedName(single: identifier))
    }

    public var children: [any ASTNode] { [] }
    public var description: String { name.simpleName }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Binary Expression

/// Binary expression: left op right
public final class BinaryExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var left: any ExprNode
    public var op: BinaryOp
    public var right: any ExprNode

    public init(span: SourceSpan, left: any ExprNode, op: BinaryOp, right: any ExprNode) {
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

// MARK: - Unary Expression

/// Unary expression: op operand
public final class UnaryExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var op: UnaryOp
    public var operand: any ExprNode

    public init(span: SourceSpan, op: UnaryOp, operand: any ExprNode) {
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

// MARK: - Call Expression

/// Function call: name[args] (also used for predicate invocation)
public final class CallExpr: ExprNode {
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

// MARK: - Box Join Expression

/// Box join: expr[args] (e.g., s.f[x] becomes f[s, x])
public final class BoxJoinExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var left: any ExprNode
    public var args: [any ExprNode]

    public init(span: SourceSpan, left: any ExprNode, args: [any ExprNode]) {
        self.span = span
        self.left = left
        self.args = args
    }

    public var children: [any ASTNode] {
        var result: [any ASTNode] = [left]
        result.append(contentsOf: args.map { $0 as any ASTNode })
        return result
    }

    public var description: String { "\(left)[...]" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Comprehension Expression

/// Quantifier variable declaration
public struct QuantDecl: Sendable {
    public var isDisjoint: Bool
    public var names: [Identifier]
    public var bound: any ExprNode

    public init(isDisjoint: Bool = false, names: [Identifier], bound: any ExprNode) {
        self.isDisjoint = isDisjoint
        self.names = names
        self.bound = bound
    }
}

/// Set comprehension: {decls | formula}
public final class ComprehensionExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var decls: [QuantDecl]
    public var formula: any FormulaNode

    public init(span: SourceSpan, decls: [QuantDecl], formula: any FormulaNode) {
        self.span = span
        self.decls = decls
        self.formula = formula
    }

    public var children: [any ASTNode] { [formula] }
    public var description: String { "{... | ...}" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Let Expression

/// Let binding
public struct LetBinding: Sendable {
    public var name: Identifier
    public var value: any ExprNode

    public init(name: Identifier, value: any ExprNode) {
        self.name = name
        self.value = value
    }
}

/// Let expression: let x = e | body
public final class LetExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var bindings: [LetBinding]
    public var body: any ExprNode

    public init(span: SourceSpan, bindings: [LetBinding], body: any ExprNode) {
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

// MARK: - Conditional Expression

/// Conditional expression: condition => thenExpr else elseExpr
public final class IfExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var condition: any FormulaNode
    public var thenExpr: any ExprNode
    public var elseExpr: any ExprNode

    public init(span: SourceSpan,
                condition: any FormulaNode,
                thenExpr: any ExprNode,
                elseExpr: any ExprNode) {
        self.span = span
        self.condition = condition
        self.thenExpr = thenExpr
        self.elseExpr = elseExpr
    }

    public var children: [any ASTNode] { [condition, thenExpr, elseExpr] }
    public var description: String { "... => ... else ..." }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Integer Literal

/// Integer literal expression
public final class IntLiteralExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var value: Int

    public init(span: SourceSpan, value: Int) {
        self.span = span
        self.value = value
    }

    public var children: [any ASTNode] { [] }
    public var description: String { "\(value)" }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Block Expression

/// Block of expressions/formulas treated as expression
public final class BlockExpr: ExprNode {
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

// MARK: - Arrow Expression

/// Arrow product expression with optional multiplicities: A [mult] -> [mult] B
/// Supports syntax like: A -> B, A -> lone B, A some -> one B
public final class ArrowExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var left: any ExprNode
    public var leftMult: Multiplicity?   // Optional multiplicity before ->
    public var rightMult: Multiplicity?  // Optional multiplicity after ->
    public var right: any ExprNode

    public init(span: SourceSpan,
                left: any ExprNode,
                leftMult: Multiplicity? = nil,
                rightMult: Multiplicity? = nil,
                right: any ExprNode) {
        self.span = span
        self.left = left
        self.leftMult = leftMult
        self.rightMult = rightMult
        self.right = right
    }

    public var children: [any ASTNode] { [left, right] }
    public var description: String {
        var result = "\(left)"
        if let lm = leftMult { result += " \(lm.rawValue)" }
        result += " ->"
        if let rm = rightMult { result += " \(rm.rawValue)" }
        result += " \(right)"
        return result
    }

    public func accept<V: ASTVisitor>(_ visitor: V) -> V.Result {
        visitor.visit(self)
    }
}

// MARK: - Multiplicity Expression

/// Multiplicity-qualified type expression (for field types)
public final class MultExpr: ExprNode {
    public let id = ASTNodeID()
    public let span: SourceSpan

    public var multiplicity: Multiplicity
    public var expr: any ExprNode

    public init(span: SourceSpan, multiplicity: Multiplicity, expr: any ExprNode) {
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
