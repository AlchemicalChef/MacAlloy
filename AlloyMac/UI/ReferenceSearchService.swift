import Foundation

// MARK: - Reference Model

/// Represents a single reference to a symbol in the source code
public struct Reference: Identifiable, Equatable {
    public let id: UUID
    public let span: SourceSpan
    public let context: String  // Line preview
    public let lineNumber: Int

    public init(span: SourceSpan, context: String, lineNumber: Int) {
        self.id = UUID()
        self.span = span
        self.context = context
        self.lineNumber = lineNumber
    }
}

// MARK: - Reference Search Service

/// Service for finding all references to a symbol in source code
public struct ReferenceSearchService {

    // MARK: - Constants

    /// Reserved Alloy keywords that cannot be used as identifiers
    private static let keywords: Set<String> = [
        "sig", "extends", "abstract", "one", "lone", "some", "set",
        "pred", "fun", "fact", "assert", "check", "run", "for",
        "but", "exactly", "all", "no", "sum", "let", "in", "and",
        "or", "not", "iff", "implies", "else", "open", "as", "module",
        "private", "enum", "var", "disj", "this", "univ", "Int", "none",
        "iden", "String"
    ]

    // MARK: - Public API

    /// Find all references to a symbol name in the source code
    /// - Parameters:
    ///   - symbolName: The name of the symbol to find
    ///   - source: The source code to search
    /// - Returns: Array of references found
    public static func findReferences(symbolName: String, in source: String) -> [Reference] {
        guard !symbolName.isEmpty else { return [] }

        var references: [Reference] = []
        let lines = source.components(separatedBy: "\n")

        // Precompute line start offsets for O(1) line number lookup
        let lineStartOffsets = computeLineStartOffsets(in: source)

        // Tokenize the source to find identifier tokens
        let lexer = Lexer(source: source)
        let tokens = lexer.scanAllTokens()

        for token in tokens {
            // Only consider identifier tokens
            guard case .identifier(let name) = token.kind,
                  name == symbolName else { continue }

            // Calculate line number using precomputed offsets
            let lineNumber = findLineNumber(for: token.span.start.offset, in: lineStartOffsets)
            let context = lines.indices.contains(lineNumber - 1) ? lines[lineNumber - 1] : ""

            let reference = Reference(
                span: token.span,
                context: context.trimmingCharacters(in: CharacterSet.whitespaces),
                lineNumber: lineNumber
            )
            references.append(reference)
        }

        return references
    }

    /// Get the symbol name at a given character offset
    /// - Parameters:
    ///   - offset: Character offset in the source
    ///   - source: The source code
    /// - Returns: The symbol name at that position, if any
    public static func getSymbolAtPosition(offset: Int, in source: String) -> String? {
        let lexer = Lexer(source: source)
        let tokens = lexer.scanAllTokens()

        for token in tokens {
            guard case .identifier(let name) = token.kind else { continue }

            if token.span.start.offset <= offset && offset < token.span.end.offset {
                return name
            }
        }

        return nil
    }

    // MARK: - Validation

    /// Check if a string is a valid Alloy identifier
    /// - Parameter name: The name to check
    /// - Returns: True if valid, false otherwise
    public static func isValidIdentifier(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }

        // Check it's not a reserved keyword
        if keywords.contains(name) {
            return false
        }

        // Check first character is letter or underscore
        guard let first = name.first,
              first.isLetter || first == "_" else {
            return false
        }

        // Check remaining characters are valid identifier chars
        for char in name.dropFirst() {
            if !char.isLetter && !char.isNumber && char != "_" && char != "'" {
                return false
            }
        }

        return true
    }

    /// Validate a new name for rename
    /// - Parameter name: The proposed new name
    /// - Returns: Error message if invalid, nil if valid
    public static func validateRename(_ name: String) -> String? {
        if name.isEmpty {
            return "Name cannot be empty"
        }

        if keywords.contains(name) {
            return "'\(name)' is a reserved keyword"
        }

        if !isValidIdentifier(name) {
            if name.first?.isNumber == true {
                return "Name cannot start with a number"
            }
            return "Invalid identifier name"
        }

        return nil
    }

    // MARK: - Rename

    /// Apply a rename operation to the source code
    /// - Parameters:
    ///   - oldName: The original symbol name
    ///   - newName: The new symbol name
    ///   - references: The references to rename (will be re-validated against source)
    ///   - source: The source code
    /// - Returns: The modified source code, or original if references are stale
    public static func applyRename(
        from oldName: String,
        to newName: String,
        references: [Reference],
        in source: String
    ) -> String {
        // Validate that references are still valid in the current source
        // This prevents crashes if the source was edited after finding references
        for ref in references {
            let start = ref.span.start.offset
            let end = ref.span.end.offset

            // Check bounds
            guard start >= 0, end <= source.count, start < end else {
                // Stale reference - re-find and apply
                return applyFreshRename(from: oldName, to: newName, in: source)
            }

            // Verify the text at this location still matches
            let startIdx = source.index(source.startIndex, offsetBy: start)
            let endIdx = source.index(source.startIndex, offsetBy: end)
            let textAtLocation = String(source[startIdx..<endIdx])

            if textAtLocation != oldName {
                // Source has changed - re-find and apply
                return applyFreshRename(from: oldName, to: newName, in: source)
            }
        }

        // References are valid - apply the rename
        return replaceReferences(references, with: newName, in: source)
    }

    /// Re-find references and apply rename (fallback when references are stale)
    private static func applyFreshRename(from oldName: String, to newName: String, in source: String) -> String {
        let freshRefs = findReferences(symbolName: oldName, in: source)
        guard !freshRefs.isEmpty else { return source }
        return replaceReferences(freshRefs, with: newName, in: source)
    }

    /// Replace all references with a new name (sorted by offset descending to preserve positions)
    private static func replaceReferences(_ references: [Reference], with newName: String, in source: String) -> String {
        let sortedRefs = references.sorted { $0.span.start.offset > $1.span.start.offset }
        var result = source

        for ref in sortedRefs {
            let startIndex = result.index(result.startIndex, offsetBy: ref.span.start.offset)
            let endIndex = result.index(result.startIndex, offsetBy: ref.span.end.offset)
            result.replaceSubrange(startIndex..<endIndex, with: newName)
        }

        return result
    }

    // MARK: - Helpers

    /// Compute the starting offset of each line (O(n) once, then O(log n) lookups)
    private static func computeLineStartOffsets(in source: String) -> [Int] {
        var offsets: [Int] = [0]  // Line 1 starts at offset 0
        var currentOffset = 0

        for char in source {
            currentOffset += 1
            if char == "\n" {
                offsets.append(currentOffset)
            }
        }

        return offsets
    }

    /// Find line number for an offset using binary search (O(log n))
    private static func findLineNumber(for offset: Int, in lineStartOffsets: [Int]) -> Int {
        // Binary search for the largest line start <= offset
        var low = 0
        var high = lineStartOffsets.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return low + 1  // Convert 0-based index to 1-based line number
    }
}
