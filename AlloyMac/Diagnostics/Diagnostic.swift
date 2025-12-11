import Foundation

// MARK: - Diagnostic Severity

/// The severity level of a diagnostic
public enum DiagnosticSeverity: String, Sendable, Comparable {
    case error
    case warning
    case info
    case hint

    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        let order: [DiagnosticSeverity] = [.hint, .info, .warning, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - Diagnostic Code

/// Diagnostic error codes
public enum DiagnosticCode: String, Sendable {
    // Lexer errors (1xx)
    case invalidCharacter = "E101"
    case unterminatedComment = "E102"
    case invalidNumber = "E103"

    // Parser errors (2xx)
    case unexpectedToken = "E201"
    case expectedExpression = "E202"
    case expectedStatement = "E203"
    case expectedIdentifier = "E204"
    case expectedType = "E205"
    case missingClosingBrace = "E206"
    case missingClosingBracket = "E207"
    case missingClosingParen = "E208"

    // Semantic errors - Names (3xx)
    case undefinedName = "E301"
    case duplicateDefinition = "E302"
    case undefinedSignature = "E303"
    case undefinedField = "E304"
    case undefinedPredicate = "E305"
    case undefinedFunction = "E306"
    case undefinedAssertion = "E307"
    case cyclicInheritance = "E308"
    case ambiguousReference = "E309"

    // Semantic errors - Types (4xx)
    case typeMismatch = "E401"
    case arityMismatch = "E402"
    case invalidJoin = "E403"
    case invalidUnion = "E404"
    case invalidIntersection = "E405"
    case invalidProduct = "E406"
    case invalidComparison = "E407"
    case expectedRelation = "E408"
    case expectedSet = "E409"
    case expectedFormula = "E410"
    case expectedInteger = "E411"
    case argumentCountMismatch = "E412"
    case privateAccess = "E413"

    // Semantic errors - Multiplicity (5xx)
    case invalidMultiplicity = "E501"
    case multiplicityViolation = "E502"

    // Semantic errors - Temporal (6xx)
    case primedNonVariable = "E601"
    case temporalInNonTemporalContext = "E602"
    case missingSteps = "E603"

    // Semantic errors - Scope (7xx)
    case invalidScope = "E701"
    case scopeTooSmall = "E702"

    // Warnings (Wxxx)
    case unusedSignature = "W101"
    case unusedField = "W102"
    case unusedPredicate = "W103"
    case unusedFunction = "W104"
    case shadowedName = "W201"
    case redundantConstraint = "W301"
    case emptySignature = "W302"
}

// MARK: - Diagnostic

/// A diagnostic message (error, warning, etc.)
public struct Diagnostic: Sendable, CustomStringConvertible {
    /// The severity of the diagnostic
    public let severity: DiagnosticSeverity

    /// The error code
    public let code: DiagnosticCode

    /// The human-readable message
    public let message: String

    /// The source location
    public let span: SourceSpan

    /// Related locations (e.g., previous definition)
    public var relatedSpans: [SourceSpan]

    /// Notes providing additional context
    public var notes: [String]

    /// Suggested fix
    public var fix: String?

    public init(severity: DiagnosticSeverity,
                code: DiagnosticCode,
                message: String,
                span: SourceSpan,
                relatedSpans: [SourceSpan] = [],
                notes: [String] = [],
                fix: String? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.span = span
        self.relatedSpans = relatedSpans
        self.notes = notes
        self.fix = fix
    }

    public var description: String {
        let loc = "\(span.start.line):\(span.start.column)"
        return "\(loc): \(severity): [\(code.rawValue)] \(message)"
    }

    // MARK: - Convenience Constructors

    /// Create an error diagnostic
    public static func error(_ code: DiagnosticCode,
                              _ message: String,
                              at span: SourceSpan) -> Diagnostic {
        Diagnostic(severity: .error, code: code, message: message, span: span)
    }

    /// Create a warning diagnostic
    public static func warning(_ code: DiagnosticCode,
                                _ message: String,
                                at span: SourceSpan) -> Diagnostic {
        Diagnostic(severity: .warning, code: code, message: message, span: span)
    }

    /// Create an info diagnostic
    public static func info(_ code: DiagnosticCode,
                            _ message: String,
                            at span: SourceSpan) -> Diagnostic {
        Diagnostic(severity: .info, code: code, message: message, span: span)
    }
}

// MARK: - Diagnostic Collector

/// Collects diagnostics during analysis
public final class DiagnosticCollector: @unchecked Sendable {
    /// All collected diagnostics
    public private(set) var diagnostics: [Diagnostic] = []

    /// Whether any errors have been reported
    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }

    /// The number of errors
    public var errorCount: Int {
        diagnostics.count { $0.severity == .error }
    }

    /// The number of warnings
    public var warningCount: Int {
        diagnostics.count { $0.severity == .warning }
    }

    public init() {}

    /// Add a diagnostic
    public func add(_ diagnostic: Diagnostic) {
        diagnostics.append(diagnostic)
    }

    /// Report an error
    public func error(_ code: DiagnosticCode, _ message: String, at span: SourceSpan) {
        add(.error(code, message, at: span))
    }

    /// Report a warning
    public func warning(_ code: DiagnosticCode, _ message: String, at span: SourceSpan) {
        add(.warning(code, message, at: span))
    }

    /// Report an info message
    public func info(_ code: DiagnosticCode, _ message: String, at span: SourceSpan) {
        add(.info(code, message, at: span))
    }

    /// Clear all diagnostics
    public func clear() {
        diagnostics.removeAll()
    }

    /// Get diagnostics sorted by location
    public var sortedDiagnostics: [Diagnostic] {
        diagnostics.sorted { d1, d2 in
            if d1.span.start.line != d2.span.start.line {
                return d1.span.start.line < d2.span.start.line
            }
            return d1.span.start.column < d2.span.start.column
        }
    }

    /// Get only errors
    public var errors: [Diagnostic] {
        diagnostics.filter { $0.severity == .error }
    }

    /// Get only warnings
    public var warnings: [Diagnostic] {
        diagnostics.filter { $0.severity == .warning }
    }
}

// MARK: - Diagnostic Formatter

/// Formats diagnostics for display
public struct DiagnosticFormatter {
    /// The source code (for context)
    public let source: String

    /// Lines of source code
    private let lines: [Substring]

    public init(source: String) {
        self.source = source
        self.lines = source.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Format a single diagnostic
    public func format(_ diagnostic: Diagnostic) -> String {
        var result = "\(diagnostic)\n"

        // Add source context
        let line = diagnostic.span.start.line
        if line > 0 && line <= lines.count {
            let sourceLine = lines[line - 1]
            result += "  \(line) | \(sourceLine)\n"

            // Add caret
            let col = diagnostic.span.start.column
            let padding = String(repeating: " ", count: col + String(line).count + 3)
            let width = max(1, diagnostic.span.end.column - diagnostic.span.start.column)
            let carets = String(repeating: "^", count: width)
            result += "\(padding)\(carets)\n"
        }

        // Add notes
        for note in diagnostic.notes {
            result += "  note: \(note)\n"
        }

        // Add fix suggestion
        if let fix = diagnostic.fix {
            result += "  fix: \(fix)\n"
        }

        return result
    }

    /// Format all diagnostics
    public func formatAll(_ diagnostics: [Diagnostic]) -> String {
        diagnostics.map { format($0) }.joined(separator: "\n")
    }
}
