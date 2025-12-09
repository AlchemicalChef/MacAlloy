import Foundation

// MARK: - Symbol Table

/// The main symbol table for semantic analysis
public final class SymbolTable: @unchecked Sendable {
    /// The root module scope
    public let rootScope: Scope

    /// Current scope during analysis
    public private(set) var currentScope: Scope

    /// All signatures in the module
    public private(set) var signatures: [String: SigSymbol] = [:]

    /// All predicates in the module
    public private(set) var predicates: [String: PredSymbol] = [:]

    /// All functions in the module
    public private(set) var functions: [String: FunSymbol] = [:]

    /// All assertions in the module
    public private(set) var assertions: [String: AssertSymbol] = [:]

    /// All facts in the module
    public private(set) var facts: [FactSymbol] = []

    /// All enums in the module
    public private(set) var enums: [String: EnumSymbol] = [:]

    /// Imported modules
    public private(set) var imports: [String: ModuleSymbol] = [:]

    /// Built-in types
    private var builtins: [String: Symbol] = [:]

    // MARK: - Initialization

    public init() {
        self.rootScope = Scope(kind: .module)
        self.currentScope = rootScope
        registerBuiltins()
    }

    /// Register built-in signatures and symbols
    private func registerBuiltins() {
        // Built-in signatures: Int, String (if needed)
        // These are typically handled specially

        // univ, iden, none are handled as special expressions, not symbols
    }

    // MARK: - Scope Management

    /// Enter a new scope
    public func enterScope(_ kind: ScopeKind) -> Scope {
        let newScope = currentScope.child(kind)
        currentScope = newScope
        return newScope
    }

    /// Exit the current scope
    public func exitScope() {
        guard let parent = currentScope.parent else {
            assertionFailure("Cannot exit root scope")
            return
        }
        currentScope = parent
    }

    /// Execute a block in a new scope
    public func inScope<T>(_ kind: ScopeKind, _ body: () throws -> T) rethrows -> T {
        let _ = enterScope(kind)
        defer { exitScope() }
        return try body()
    }

    // MARK: - Symbol Registration

    /// Register a signature
    @discardableResult
    public func registerSig(_ symbol: SigSymbol) -> Symbol? {
        if let existing = currentScope.define(symbol) {
            return existing
        }
        signatures[symbol.name] = symbol
        return nil
    }

    /// Register a field
    @discardableResult
    public func registerField(_ symbol: FieldSymbol) -> Symbol? {
        return currentScope.define(symbol)
    }

    /// Register a predicate
    @discardableResult
    public func registerPred(_ symbol: PredSymbol) -> Symbol? {
        if let existing = currentScope.define(symbol) {
            return existing
        }
        predicates[symbol.fullName] = symbol
        return nil
    }

    /// Register a function
    @discardableResult
    public func registerFun(_ symbol: FunSymbol) -> Symbol? {
        if let existing = currentScope.define(symbol) {
            return existing
        }
        functions[symbol.fullName] = symbol
        return nil
    }

    /// Register an assertion
    @discardableResult
    public func registerAssert(_ symbol: AssertSymbol) -> Symbol? {
        if let existing = currentScope.define(symbol) {
            return existing
        }
        assertions[symbol.name] = symbol
        return nil
    }

    /// Register a fact
    @discardableResult
    public func registerFact(_ symbol: FactSymbol) -> Symbol? {
        if let existing = currentScope.define(symbol) {
            return existing
        }
        facts.append(symbol)
        return nil
    }

    /// Register an enum
    @discardableResult
    public func registerEnum(_ symbol: EnumSymbol) -> Symbol? {
        if let existing = currentScope.define(symbol) {
            return existing
        }
        enums[symbol.name] = symbol

        // Also register enum values
        for value in symbol.values {
            currentScope.define(value)
        }
        return nil
    }

    /// Register a parameter
    @discardableResult
    public func registerParam(_ symbol: ParamSymbol) -> Symbol? {
        return currentScope.define(symbol)
    }

    /// Register a quantifier variable
    @discardableResult
    public func registerQuantVar(_ symbol: QuantVarSymbol) -> Symbol? {
        return currentScope.define(symbol)
    }

    /// Register a let variable
    @discardableResult
    public func registerLetVar(_ symbol: LetVarSymbol) -> Symbol? {
        return currentScope.define(symbol)
    }

    /// Register an imported module
    @discardableResult
    public func registerImport(_ symbol: ModuleSymbol) -> Symbol? {
        if let existing = currentScope.define(symbol) {
            return existing
        }
        let key = symbol.alias ?? symbol.name
        imports[key] = symbol
        return nil
    }

    // MARK: - Symbol Lookup

    /// Look up a symbol by name
    public func lookup(_ name: String) -> Symbol? {
        // Check current scope chain
        if let sym = currentScope.lookup(name) {
            return sym
        }

        // Check builtins
        if let builtin = builtins[name] {
            return builtin
        }

        return nil
    }

    /// Look up a qualified name
    public func lookup(_ qualifiedName: QualifiedName) -> Symbol? {
        let parts = qualifiedName.parts.map(\.name)

        if parts.count == 1 {
            return lookup(parts[0])
        }

        // Handle qualified names like Module/Name or Sig.field
        let firstName = parts[0]
        if let module = imports[firstName] {
            // Module reference
            let remaining = parts.dropFirst().joined(separator: "/")
            return module.exports[remaining]
        }

        // Try as Sig.field or Sig.pred
        if let sig = lookupSig(firstName) {
            let secondName = parts[1]
            // Look for field
            for field in sig.allFields {
                if field.name == secondName {
                    return field
                }
            }
            // Look for method-style pred/fun
            if let pred = predicates["\(firstName).\(secondName)"] {
                return pred
            }
            if let fun = functions["\(firstName).\(secondName)"] {
                return fun
            }
        }

        return nil
    }

    /// Look up a signature
    public func lookupSig(_ name: String) -> SigSymbol? {
        signatures[name] ?? (lookup(name) as? SigSymbol)
    }

    /// Look up a predicate
    public func lookupPred(_ name: String) -> PredSymbol? {
        predicates[name] ?? (lookup(name) as? PredSymbol)
    }

    /// Look up a function
    public func lookupFun(_ name: String) -> FunSymbol? {
        functions[name] ?? (lookup(name) as? FunSymbol)
    }

    /// Look up an assertion
    public func lookupAssert(_ name: String) -> AssertSymbol? {
        assertions[name]
    }

    /// Look up a field in any visible signature
    public func lookupField(_ name: String) -> FieldSymbol? {
        // First check the scope chain
        if let field = currentScope.lookupField(name) {
            return field
        }
        // Then search all signatures in the module
        for sig in signatures.values {
            for field in sig.fields {
                if field.name == name {
                    return field
                }
            }
        }
        return nil
    }

    /// Look up a field in a specific signature
    public func lookupField(_ name: String, in sig: SigSymbol) -> FieldSymbol? {
        sig.allFields.first { $0.name == name }
    }

    // MARK: - Type Hierarchy

    /// Build the signature type hierarchy
    public func buildTypeHierarchy() {
        for sig in signatures.values {
            sig.children.removeAll()
        }

        for sig in signatures.values {
            if let parent = sig.parent {
                parent.children.append(sig)
            }
        }
    }

    /// Get all root signatures (those without parents)
    public var rootSignatures: [SigSymbol] {
        signatures.values.filter { $0.parent == nil && $0.subsetOf.isEmpty }
    }

    /// Check if one signature is a subtype of another
    public func isSubtype(_ sub: SigSymbol, of super_: SigSymbol) -> Bool {
        sub.sigType.isSubtypeOf(super_.sigType)
    }

    // MARK: - Debug

    /// Dump the symbol table for debugging
    public func dump() -> String {
        var result = "=== Symbol Table ===\n"

        result += "\nSignatures:\n"
        for sig in signatures.values.sorted(by: { $0.name < $1.name }) {
            result += "  \(sig)\n"
            for field in sig.fields {
                result += "    \(field)\n"
            }
        }

        result += "\nPredicates:\n"
        for pred in predicates.values.sorted(by: { $0.name < $1.name }) {
            result += "  \(pred)\n"
        }

        result += "\nFunctions:\n"
        for fun in functions.values.sorted(by: { $0.name < $1.name }) {
            result += "  \(fun)\n"
        }

        result += "\nAssertions:\n"
        for assert in assertions.values.sorted(by: { $0.name < $1.name }) {
            result += "  \(assert)\n"
        }

        result += "\nFacts:\n"
        for fact in facts {
            result += "  \(fact)\n"
        }

        result += "\nScope Hierarchy:\n"
        result += rootScope.dump()

        return result
    }
}

extension SymbolTable: CustomStringConvertible {
    public var description: String {
        "SymbolTable(sigs: \(signatures.count), preds: \(predicates.count), funs: \(functions.count), facts: \(facts.count))"
    }
}
