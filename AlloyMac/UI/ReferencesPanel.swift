import SwiftUI

// MARK: - References Panel

/// Panel showing all references to a symbol
public struct ReferencesPanel: View {
    let symbolName: String
    let references: [Reference]
    let onNavigate: (SourceSpan) -> Void
    let onClose: () -> Void

    public init(
        symbolName: String,
        references: [Reference],
        onNavigate: @escaping (SourceSpan) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.symbolName = symbolName
        self.references = references
        self.onNavigate = onNavigate
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                Text("\(references.count) reference\(references.count == 1 ? "" : "s") to")
                    .foregroundColor(.secondary)

                Text(symbolName)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // References list
            if references.isEmpty {
                VStack {
                    Spacer()
                    Text("No references found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(references) { reference in
                            ReferenceRow(
                                reference: reference,
                                symbolName: symbolName,
                                onTap: { onNavigate(reference.span) }
                            )
                        }
                    }
                }
            }
        }
        .frame(height: 150)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Reference Row

/// A single row showing a reference with context
struct ReferenceRow: View {
    let reference: Reference
    let symbolName: String
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Line number
                Text(":\(reference.lineNumber)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)

                // Context with highlighted symbol
                highlightedContext
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var highlightedContext: some View {
        // Split context by symbol name and highlight matches
        let parts = splitContextBySymbol(reference.context, symbolName: symbolName)

        return parts.reduce(Text("")) { result, part in
            if part.isMatch {
                return result + Text(part.text)
                    .foregroundColor(.accentColor)
                    .fontWeight(.medium)
            } else {
                return result + Text(part.text)
                    .foregroundColor(.primary)
            }
        }
    }

    private func splitContextBySymbol(_ context: String, symbolName: String) -> [(text: String, isMatch: Bool)] {
        var result: [(String, Bool)] = []
        var currentIndex = context.startIndex

        while currentIndex < context.endIndex {
            // Look for the symbol name starting from current position
            if let range = context.range(of: symbolName, range: currentIndex..<context.endIndex) {
                // Check if this is a whole word match (not part of a larger identifier)
                let isWordStart = range.lowerBound == context.startIndex ||
                    !isIdentifierChar(context[context.index(before: range.lowerBound)])
                let isWordEnd = range.upperBound == context.endIndex ||
                    !isIdentifierChar(context[range.upperBound])

                if isWordStart && isWordEnd {
                    // Add text before match
                    if currentIndex < range.lowerBound {
                        result.append((String(context[currentIndex..<range.lowerBound]), false))
                    }
                    // Add the match
                    result.append((symbolName, true))
                    currentIndex = range.upperBound
                } else {
                    // Not a word boundary match - skip past this occurrence and continue
                    // Add text up to and including this non-boundary match as non-match text
                    // (will be merged by mergeNonMatches if needed)
                    result.append((String(context[currentIndex..<range.upperBound]), false))
                    currentIndex = range.upperBound
                }
            } else {
                // No more matches - add remaining text
                result.append((String(context[currentIndex..<context.endIndex]), false))
                break
            }
        }

        // Merge consecutive non-match segments for efficiency
        return mergeNonMatches(result)
    }

    private func isIdentifierChar(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || char == "'"
    }

    private func mergeNonMatches(_ parts: [(String, Bool)]) -> [(text: String, isMatch: Bool)] {
        guard !parts.isEmpty else { return [] }

        var merged: [(String, Bool)] = []
        var currentText = parts[0].0
        var currentIsMatch = parts[0].1

        for (text, isMatch) in parts.dropFirst() {
            if isMatch == currentIsMatch && !isMatch {
                // Merge consecutive non-matches
                currentText += text
            } else {
                // Different type - flush current and start new
                merged.append((currentText, currentIsMatch))
                currentText = text
                currentIsMatch = isMatch
            }
        }

        // Append the final segment
        merged.append((currentText, currentIsMatch))

        return merged
    }
}

// MARK: - Preview

struct ReferencesPanel_Previews: PreviewProvider {
    static var previews: some View {
        let start1 = SourcePosition(line: 1, column: 5, offset: 4)
        let end1 = SourcePosition(line: 1, column: 11, offset: 10)
        let start2 = SourcePosition(line: 2, column: 18, offset: 30)
        let end2 = SourcePosition(line: 2, column: 24, offset: 36)
        let start3 = SourcePosition(line: 5, column: 8, offset: 60)
        let end3 = SourcePosition(line: 5, column: 14, offset: 66)

        return ReferencesPanel(
            symbolName: "Person",
            references: [
                Reference(
                    span: SourceSpan(start: start1, end: end1),
                    context: "sig Person {",
                    lineNumber: 1
                ),
                Reference(
                    span: SourceSpan(start: start2, end: end2),
                    context: "    friends: set Person",
                    lineNumber: 2
                ),
                Reference(
                    span: SourceSpan(start: start3, end: end3),
                    context: "no p: Person | p in p.friends",
                    lineNumber: 5
                )
            ],
            onNavigate: { _ in },
            onClose: { }
        )
    }
}
