import Foundation

// MARK: - Scope Kind

/// The kind of scope
public enum ScopeKind: String, Sendable {
    case module      // Top-level module scope
    case signature   // Inside a signature declaration
    case predicate   // Inside a predicate body
    case function    // Inside a function body
    case quantifier  // Inside a quantifier body
    case letBinding  // Inside a let expression
    case block       // Inside a block
}

// MARK: - Scope

/// A lexical scope containing symbol definitions
public final class Scope: @unchecked Sendable {
    /// The kind of this scope
    public let kind: ScopeKind

    /// The parent scope (nil for module scope)
    public weak var parent: Scope?

    /// Child scopes
    public var children: [Scope] = []

    /// Symbols defined in this scope
    private var symbols: [String: Symbol] = [:]

    /// The AST node associated with this scope
    public weak var node: (any ASTNode)?

    public init(kind: ScopeKind, parent: Scope? = nil) {
        self.kind = kind
        self.parent = parent
        parent?.children.append(self)
    }

    // MARK: - Symbol Management

    /// Define a symbol in this scope
    /// - Returns: The existing symbol if there's a conflict, nil otherwise
    @discardableResult
    public func define(_ symbol: Symbol) -> Symbol? {
        if let existing = symbols[symbol.name] {
            return existing
        }
        symbols[symbol.name] = symbol
        symbol.scope = self
        return nil
    }

    /// Look up a symbol by name in this scope only
    public func lookupLocal(_ name: String) -> Symbol? {
        symbols[name]
    }

    /// Look up a symbol by name, searching parent scopes
    public func lookup(_ name: String) -> Symbol? {
        if let symbol = symbols[name] {
            return symbol
        }
        return parent?.lookup(name)
    }

    /// Look up a signature symbol
    public func lookupSig(_ name: String) -> SigSymbol? {
        lookup(name) as? SigSymbol
    }

    /// Look up a predicate symbol
    public func lookupPred(_ name: String) -> PredSymbol? {
        lookup(name) as? PredSymbol
    }

    /// Look up a function symbol
    public func lookupFun(_ name: String) -> FunSymbol? {
        lookup(name) as? FunSymbol
    }

    /// Look up a field by name in the current context
    public func lookupField(_ name: String, in sig: SigSymbol? = nil) -> FieldSymbol? {
        // If a signature is specified, search there first
        if let sig = sig {
            for field in sig.allFields {
                if field.name == name {
                    return field
                }
            }
        }

        // Search all signatures in scope
        for sym in allSymbols {
            if let sigSym = sym as? SigSymbol {
                for field in sigSym.fields {
                    if field.name == name {
                        return field
                    }
                }
            }
        }

        return parent?.lookupField(name, in: sig)
    }

    /// Get all symbols in this scope
    public var localSymbols: [Symbol] {
        Array(symbols.values)
    }

    /// Get all symbols visible in this scope (including parent scopes)
    public var allSymbols: [Symbol] {
        var result = Array(symbols.values)
        if let p = parent {
            // Parent symbols that aren't shadowed
            for sym in p.allSymbols {
                if symbols[sym.name] == nil {
                    result.append(sym)
                }
            }
        }
        return result
    }

    /// Get all signature symbols visible in this scope
    public var allSignatures: [SigSymbol] {
        allSymbols.compactMap { $0 as? SigSymbol }
    }

    /// Get all predicate symbols visible in this scope
    public var allPredicates: [PredSymbol] {
        allSymbols.compactMap { $0 as? PredSymbol }
    }

    /// Get all function symbols visible in this scope
    public var allFunctions: [FunSymbol] {
        allSymbols.compactMap { $0 as? FunSymbol }
    }

    // MARK: - Scope Navigation

    /// Find the nearest enclosing scope of a given kind
    public func enclosing(_ kind: ScopeKind) -> Scope? {
        if self.kind == kind { return self }
        return parent?.enclosing(kind)
    }

    /// Get the module scope (root)
    public var moduleScope: Scope {
        if kind == .module { return self }
        return parent?.moduleScope ?? self
    }

    /// Get the signature scope we're inside (if any)
    public var signatureScope: Scope? {
        enclosing(.signature)
    }

    /// Get the current signature symbol (if inside a signature)
    public var currentSignature: SigSymbol? {
        var scope: Scope? = self
        while let s = scope {
            if s.kind == .signature {
                // Find the sig symbol that owns this scope by looking at parent's symbols
                // The signature symbol is defined in the parent (module) scope
                if let parentScope = s.parent {
                    for sym in parentScope.localSymbols {
                        if let sig = sym as? SigSymbol {
                            return sig
                        }
                    }
                }
                return nil
            }
            scope = s.parent
        }
        return nil
    }

    // MARK: - Scope Creation

    /// Create a child scope
    public func child(_ kind: ScopeKind) -> Scope {
        Scope(kind: kind, parent: self)
    }
}

// MARK: - CustomStringConvertible

extension Scope: CustomStringConvertible {
    public var description: String {
        let symNames = symbols.keys.sorted().joined(separator: ", ")
        return "Scope(\(kind): [\(symNames)])"
    }

    /// Pretty print the scope hierarchy
    public func dump(indent: Int = 0) -> String {
        let prefix = String(repeating: "  ", count: indent)
        var result = "\(prefix)\(kind):\n"
        for (name, sym) in symbols.sorted(by: { $0.key < $1.key }) {
            result += "\(prefix)  \(name): \(sym.kind)\n"
        }
        for child in children {
            result += child.dump(indent: indent + 1)
        }
        return result
    }
}
