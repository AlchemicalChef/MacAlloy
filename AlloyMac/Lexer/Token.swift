import Foundation

/// A token with its kind and source location
public struct Token: Equatable, Hashable, Sendable {
    /// The type of token
    public let kind: TokenKind
    /// The source location span
    public let span: SourceSpan
    /// The original source text of the token
    public let text: String

    public init(kind: TokenKind, span: SourceSpan, text: String) {
        self.kind = kind
        self.span = span
        self.text = text
    }

    /// Convenience initializer with empty text (for error recovery)
    public init(kind: TokenKind, span: SourceSpan) {
        self.kind = kind
        self.span = span
        self.text = ""
    }
}

extension Token: CustomStringConvertible {
    public var description: String {
        "\(kind) at \(span)"
    }
}
