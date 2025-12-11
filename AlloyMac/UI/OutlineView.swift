import SwiftUI

// MARK: - Outline View

/// Document structure sidebar showing signatures, predicates, functions, etc.
public struct OutlineView: View {
    let symbolTable: SymbolTable
    let onItemSelected: (SourceSpan) -> Void

    public init(symbolTable: SymbolTable, onItemSelected: @escaping (SourceSpan) -> Void) {
        self.symbolTable = symbolTable
        self.onItemSelected = onItemSelected
    }

    public var body: some View {
        List {
            // Signatures - organized hierarchically
            if !symbolTable.signatures.isEmpty {
                Section("Signatures") {
                    // Show top-level signatures first, then nested children
                    ForEach(topLevelSignatures, id: \.name) { sig in
                        signatureHierarchyView(sig)
                    }
                }
            }

            // Predicates
            if !symbolTable.predicates.isEmpty {
                Section("Predicates") {
                    ForEach(symbolTable.predicates.values.sorted(by: { $0.name < $1.name }), id: \.name) { pred in
                        OutlineRow(
                            icon: "function",
                            iconColor: .purple,
                            title: pred.name,
                            subtitle: predSubtitle(pred)
                        ) {
                            onItemSelected(pred.definedAt)
                        }
                    }
                }
            }

            // Functions
            if !symbolTable.functions.isEmpty {
                Section("Functions") {
                    ForEach(symbolTable.functions.values.sorted(by: { $0.name < $1.name }), id: \.name) { fun in
                        OutlineRow(
                            icon: "f.cursive",
                            iconColor: .orange,
                            title: fun.name,
                            subtitle: funSubtitle(fun)
                        ) {
                            onItemSelected(fun.definedAt)
                        }
                    }
                }
            }

            // Facts
            if !symbolTable.facts.isEmpty {
                Section("Facts") {
                    ForEach(symbolTable.facts, id: \.name) { fact in
                        OutlineRow(
                            icon: "checkmark.seal",
                            iconColor: .green,
                            title: fact.name.isEmpty ? "(anonymous)" : fact.name
                        ) {
                            onItemSelected(fact.definedAt)
                        }
                    }
                }
            }

            // Assertions
            if !symbolTable.assertions.isEmpty {
                Section("Assertions") {
                    ForEach(symbolTable.assertions.values.sorted(by: { $0.name < $1.name }), id: \.name) { assertion in
                        OutlineRow(
                            icon: "exclamationmark.shield",
                            iconColor: .red,
                            title: assertion.name
                        ) {
                            onItemSelected(assertion.definedAt)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Signature Hierarchy Helpers

    /// Get top-level signatures (those without parents)
    private var topLevelSignatures: [SigSymbol] {
        symbolTable.signatures.values
            .filter { $0.parent == nil }
            .sorted(by: { $0.name < $1.name })
    }

    /// Get child signatures of a parent
    private func childSignatures(of parent: SigSymbol) -> [SigSymbol] {
        symbolTable.signatures.values
            .filter { $0.parent?.name == parent.name }
            .sorted(by: { $0.name < $1.name })
    }

    /// Get predicates with a specific receiver (method-style)
    private func predicates(for sig: SigSymbol) -> [PredSymbol] {
        symbolTable.predicates.values
            .filter { $0.receiver?.name == sig.name }
            .sorted(by: { $0.name < $1.name })
    }

    /// Get functions with a specific receiver (method-style)
    private func functions(for sig: SigSymbol) -> [FunSymbol] {
        symbolTable.functions.values
            .filter { $0.receiver?.name == sig.name }
            .sorted(by: { $0.name < $1.name })
    }

    /// Build hierarchical view for a signature and its children
    @ViewBuilder
    private func signatureHierarchyView(_ sig: SigSymbol, depth: Int = 0) -> some View {
        let children = childSignatures(of: sig)
        let sigPreds = predicates(for: sig)
        let sigFuns = functions(for: sig)
        let hasMembers = !sig.fields.isEmpty || !children.isEmpty || !sigPreds.isEmpty || !sigFuns.isEmpty

        DisclosureGroup {
            // Fields
            ForEach(sig.fields, id: \.name) { field in
                OutlineRow(
                    icon: "arrow.right.circle",
                    iconColor: .secondary,
                    title: field.name,
                    subtitle: "\(field.type)",
                    isVariable: field.isVariable
                ) {
                    onItemSelected(field.definedAt)
                }
                .padding(.leading, 8)
            }

            // Method-style predicates for this signature
            ForEach(sigPreds, id: \.name) { pred in
                OutlineRow(
                    icon: "function",
                    iconColor: .purple.opacity(0.7),
                    title: pred.name,
                    subtitle: predSubtitle(pred)
                ) {
                    onItemSelected(pred.definedAt)
                }
                .padding(.leading, 8)
            }

            // Method-style functions for this signature
            ForEach(sigFuns, id: \.name) { fun in
                OutlineRow(
                    icon: "f.cursive",
                    iconColor: .orange.opacity(0.7),
                    title: fun.name,
                    subtitle: funSubtitle(fun)
                ) {
                    onItemSelected(fun.definedAt)
                }
                .padding(.leading, 8)
            }

            // Child signatures (nested hierarchy)
            ForEach(children, id: \.name) { child in
                signatureHierarchyView(child, depth: depth + 1)
                    .padding(.leading, 4)
            }
        } label: {
            OutlineRow(
                icon: depth == 0 ? "cube" : "cube.fill",
                iconColor: depth == 0 ? .blue : .blue.opacity(0.7),
                title: sig.name,
                subtitle: sigSubtitle(sig),
                isVariable: sig.sigType.isVariable,
                isAbstract: sig.sigType.isAbstract
            ) {
                onItemSelected(sig.definedAt)
            }
        }
    }

    // MARK: - Helpers

    private func sigSubtitle(_ sig: SigSymbol) -> String? {
        var parts: [String] = []
        if sig.sigType.isAbstract { parts.append("abstract") }
        if let mult = sig.sigType.multiplicity { parts.append("\(mult)") }
        if let parent = sig.parent { parts.append("extends \(parent.name)") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func predSubtitle(_ pred: PredSymbol) -> String? {
        if pred.parameters.isEmpty { return nil }
        let params = pred.parameters.map { $0.name }.joined(separator: ", ")
        return "[\(params)]"
    }

    private func funSubtitle(_ fun: FunSymbol) -> String? {
        let params = fun.parameters.isEmpty ? "" : fun.parameters.map { $0.name }.joined(separator: ", ")
        return "[\(params)]: \(fun.type)"
    }
}

// MARK: - Outline Row

/// A single row in the outline view
struct OutlineRow: View {
    let icon: String
    var iconColor: Color = .primary
    let title: String
    var subtitle: String? = nil
    var isVariable: Bool = false
    var isAbstract: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title)
                            .fontWeight(.medium)
                            .italic(isAbstract)
                        if isVariable {
                            Text("var")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(3)
                        }
                        if isAbstract {
                            Text("abstract")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(3)
                        }
                    }
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

struct OutlineView_Previews: PreviewProvider {
    static var previews: some View {
        OutlineView(symbolTable: SymbolTable()) { _ in }
            .frame(width: 250)
    }
}
