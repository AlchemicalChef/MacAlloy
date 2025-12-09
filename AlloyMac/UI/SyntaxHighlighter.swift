import SwiftUI
import AppKit

// MARK: - Syntax Highlighter

/// Provides syntax highlighting for Alloy code
public struct SyntaxHighlighter {
    /// Theme for syntax highlighting
    public let theme: SyntaxTheme

    public init(theme: SyntaxTheme = .default) {
        self.theme = theme
    }

    /// Highlight Alloy source code
    public func highlight(_ source: String) -> AttributedString {
        var result = AttributedString(source)

        // Apply base font
        result.font = theme.font
        result.foregroundColor = theme.textColor

        // Handle comments first (before tokenization)
        highlightComments(in: source, result: &result)

        // Tokenize and apply colors
        let lexer = Lexer(source: source)
        let tokens = lexer.scanAllTokens()

        for token in tokens {
            guard let range = range(for: token, in: source, attributedString: result) else {
                continue
            }

            let color = color(for: token.kind)
            result[range].foregroundColor = color

            // Bold for keywords
            if isKeyword(token.kind) {
                result[range].font = theme.boldFont
            }
        }

        return result
    }

    /// Highlight comments (// and /* */)
    private func highlightComments(in source: String, result: inout AttributedString) {
        // Line comments
        var i = source.startIndex
        while i < source.endIndex {
            if source[i] == "/" && source.index(after: i) < source.endIndex && source[source.index(after: i)] == "/" {
                // Found line comment
                let start = i
                var end = i
                while end < source.endIndex && source[end] != "\n" {
                    end = source.index(after: end)
                }
                if let attrStart = AttributedString.Index(start, within: result),
                   let attrEnd = AttributedString.Index(end, within: result) {
                    result[attrStart..<attrEnd].foregroundColor = theme.commentColor
                }
                i = end
            } else if source[i] == "/" && source.index(after: i) < source.endIndex && source[source.index(after: i)] == "*" {
                // Found block comment
                let start = i
                i = source.index(i, offsetBy: 2)
                while i < source.endIndex {
                    if source[i] == "*" && source.index(after: i) < source.endIndex && source[source.index(after: i)] == "/" {
                        i = source.index(i, offsetBy: 2)
                        break
                    }
                    i = source.index(after: i)
                }
                if let attrStart = AttributedString.Index(start, within: result),
                   let attrEnd = AttributedString.Index(i, within: result) {
                    result[attrStart..<attrEnd].foregroundColor = theme.commentColor
                }
            } else {
                i = source.index(after: i)
            }
        }
    }

    /// Get the color for a token kind
    private func color(for kind: TokenKind) -> Color {
        switch kind {
        // Keywords
        case .module, .open, .as:
            return theme.keywordColor
        case .sig, .abstract, .extends, .in:
            return theme.keywordColor
        case .fact, .pred, .fun, .assert:
            return theme.keywordColor
        case .run, .check, .for, .but, .exactly, .expect:
            return theme.keywordColor
        case .let, .disj, .var:
            return theme.keywordColor
        case .enum:
            return theme.keywordColor

        // Quantifiers and multiplicity
        case .all, .some, .no, .one, .lone, .set, .seq, .sum:
            return theme.quantifierColor

        // Temporal keywords
        case .always, .eventually, .after, .until, .releases:
            return theme.temporalColor
        case .historically, .once, .before, .since, .triggered:
            return theme.temporalColor
        case .steps:
            return theme.temporalColor

        // Boolean operators
        case .and, .or, .not, .implies, .iff, .else:
            return theme.operatorColor

        // Special values
        case .none, .univ, .iden, .int:
            return theme.builtinColor

        // Literals
        case .integer:
            return theme.numberColor
        case .string:
            return theme.stringColor

        // Identifiers
        case .identifier:
            return theme.textColor

        // Operators
        case .plus, .minus, .ampersand, .arrow, .dot, .tilde:
            return theme.operatorColor
        case .caret, .star, .hash, .prime, .plusPlus, .rightRestrict, .leftRestrict:
            return theme.operatorColor
        case .equal, .notEqual, .less, .greater, .lessEqual, .greaterEqual:
            return theme.operatorColor
        case .bang, .doubleAmp, .doublePipe, .fatArrow, .doubleArrow:
            return theme.operatorColor
        case .semicolon:
            return theme.operatorColor

        // Delimiters
        case .leftBrace, .rightBrace, .leftBracket, .rightBracket:
            return theme.delimiterColor
        case .leftParen, .rightParen, .comma, .colon, .pipe, .at, .slash:
            return theme.delimiterColor

        case .eof, .invalid:
            return theme.textColor
        }
    }

    /// Check if a token kind is a keyword
    private func isKeyword(_ kind: TokenKind) -> Bool {
        switch kind {
        case .module, .open, .as, .sig, .abstract, .extends, .in,
             .fact, .pred, .fun, .assert, .run, .check, .for,
             .but, .exactly, .let, .disj, .var, .enum, .expect,
             .all, .some, .no, .one, .lone, .set, .seq, .sum,
             .always, .eventually, .after, .until, .releases,
             .historically, .once, .before, .since, .triggered, .steps,
             .and, .or, .not, .implies, .iff, .else:
            return true
        default:
            return false
        }
    }

    /// Convert token position to AttributedString range
    private func range(for token: Token, in source: String, attributedString: AttributedString) -> Range<AttributedString.Index>? {
        let startOffset = token.span.start.offset
        let endOffset = token.span.end.offset

        guard startOffset >= 0 && endOffset <= source.count else {
            return nil
        }

        let sourceStart = source.index(source.startIndex, offsetBy: startOffset)
        let sourceEnd = source.index(source.startIndex, offsetBy: endOffset)

        // Convert to AttributedString indices
        guard let attrStart = AttributedString.Index(sourceStart, within: attributedString),
              let attrEnd = AttributedString.Index(sourceEnd, within: attributedString) else {
            return nil
        }

        return attrStart..<attrEnd
    }
}

// MARK: - Syntax Theme

/// Theme configuration for syntax highlighting
public struct SyntaxTheme {
    public let font: Font
    public let boldFont: Font
    public let textColor: Color
    public let keywordColor: Color
    public let quantifierColor: Color
    public let temporalColor: Color
    public let operatorColor: Color
    public let builtinColor: Color
    public let numberColor: Color
    public let stringColor: Color
    public let commentColor: Color
    public let delimiterColor: Color
    public let backgroundColor: Color

    public init(
        font: Font = .system(.body, design: .monospaced),
        boldFont: Font = .system(.body, design: .monospaced).bold(),
        textColor: Color = .primary,
        keywordColor: Color = .purple,
        quantifierColor: Color = .blue,
        temporalColor: Color = .orange,
        operatorColor: Color = .secondary,
        builtinColor: Color = .teal,
        numberColor: Color = .cyan,
        stringColor: Color = .green,
        commentColor: Color = .gray,
        delimiterColor: Color = .secondary,
        backgroundColor: Color = Color(nsColor: .windowBackgroundColor)
    ) {
        self.font = font
        self.boldFont = boldFont
        self.textColor = textColor
        self.keywordColor = keywordColor
        self.quantifierColor = quantifierColor
        self.temporalColor = temporalColor
        self.operatorColor = operatorColor
        self.builtinColor = builtinColor
        self.numberColor = numberColor
        self.stringColor = stringColor
        self.commentColor = commentColor
        self.delimiterColor = delimiterColor
        self.backgroundColor = backgroundColor
    }

    /// Default light theme
    public static let `default` = SyntaxTheme()

    /// Dark theme
    public static let dark = SyntaxTheme(
        textColor: Color(white: 0.9),
        keywordColor: Color(red: 0.8, green: 0.4, blue: 0.9),
        quantifierColor: Color(red: 0.4, green: 0.6, blue: 1.0),
        temporalColor: Color(red: 1.0, green: 0.6, blue: 0.2),
        operatorColor: Color(white: 0.7),
        builtinColor: Color(red: 0.3, green: 0.8, blue: 0.8),
        numberColor: Color(red: 0.4, green: 0.9, blue: 0.9),
        stringColor: Color(red: 0.5, green: 0.9, blue: 0.5),
        commentColor: Color(white: 0.5),
        delimiterColor: Color(white: 0.6),
        backgroundColor: Color(white: 0.1)
    )

    /// Xcode-like theme
    public static let xcode = SyntaxTheme(
        keywordColor: Color(red: 0.72, green: 0.2, blue: 0.66),
        quantifierColor: Color(red: 0.72, green: 0.2, blue: 0.66),
        temporalColor: Color(red: 0.6, green: 0.4, blue: 0.0),
        operatorColor: .primary,
        builtinColor: Color(red: 0.44, green: 0.26, blue: 0.76),
        numberColor: Color(red: 0.11, green: 0.43, blue: 0.69),
        stringColor: Color(red: 0.77, green: 0.1, blue: 0.09),
        commentColor: Color(red: 0.42, green: 0.47, blue: 0.44)
    )
}

// MARK: - AppKit Highlighter (for NSTextView)

/// AppKit-based syntax highlighter for use with NSTextView
public final class AppKitSyntaxHighlighter {
    public let theme: AppKitSyntaxTheme

    public init(theme: AppKitSyntaxTheme = .default) {
        self.theme = theme
    }

    /// Highlight source code and return NSAttributedString
    public func highlight(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source)

        // Apply base attributes
        let fullRange = NSRange(location: 0, length: source.utf16.count)
        result.addAttribute(.font, value: theme.font, range: fullRange)
        result.addAttribute(.foregroundColor, value: theme.textColor, range: fullRange)

        // Highlight comments
        highlightComments(in: source, result: result)

        // Tokenize and apply colors
        let lexer = Lexer(source: source)
        let tokens = lexer.scanAllTokens()

        for token in tokens {
            let startOffset = token.span.start.offset
            let endOffset = token.span.end.offset

            guard startOffset >= 0 && endOffset <= source.count else {
                continue
            }

            // Convert character offset to UTF-16 offset for NSRange
            let startIndex = source.index(source.startIndex, offsetBy: startOffset)
            let endIndex = source.index(source.startIndex, offsetBy: endOffset)
            let nsRange = NSRange(startIndex..<endIndex, in: source)

            let color = color(for: token.kind)
            result.addAttribute(.foregroundColor, value: color, range: nsRange)

            if isKeyword(token.kind) {
                result.addAttribute(.font, value: theme.boldFont, range: nsRange)
            }
        }

        return result
    }

    /// Highlight comments
    private func highlightComments(in source: String, result: NSMutableAttributedString) {
        var i = source.startIndex
        while i < source.endIndex {
            if source[i] == "/" && source.index(after: i) < source.endIndex && source[source.index(after: i)] == "/" {
                let start = i
                var end = i
                while end < source.endIndex && source[end] != "\n" {
                    end = source.index(after: end)
                }
                let nsRange = NSRange(start..<end, in: source)
                result.addAttribute(.foregroundColor, value: theme.commentColor, range: nsRange)
                i = end
            } else if source[i] == "/" && source.index(after: i) < source.endIndex && source[source.index(after: i)] == "*" {
                let start = i
                i = source.index(i, offsetBy: 2)
                while i < source.endIndex {
                    if source[i] == "*" && source.index(after: i) < source.endIndex && source[source.index(after: i)] == "/" {
                        i = source.index(i, offsetBy: 2)
                        break
                    }
                    i = source.index(after: i)
                }
                let nsRange = NSRange(start..<i, in: source)
                result.addAttribute(.foregroundColor, value: theme.commentColor, range: nsRange)
            } else {
                i = source.index(after: i)
            }
        }
    }

    private func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .module, .open, .as, .sig, .abstract, .extends, .in,
             .fact, .pred, .fun, .assert, .run, .check, .for,
             .but, .exactly, .let, .disj, .var, .enum, .expect:
            return theme.keywordColor

        case .all, .some, .no, .one, .lone, .set, .seq, .sum:
            return theme.quantifierColor

        case .always, .eventually, .after, .until, .releases,
             .historically, .once, .before, .since, .triggered, .steps:
            return theme.temporalColor

        case .and, .or, .not, .implies, .iff, .else:
            return theme.operatorColor

        case .none, .univ, .iden, .int:
            return theme.builtinColor

        case .integer:
            return theme.numberColor

        case .plus, .minus, .ampersand, .arrow, .dot, .tilde,
             .caret, .star, .hash, .prime, .plusPlus, .rightRestrict, .leftRestrict,
             .equal, .notEqual, .less, .greater, .lessEqual, .greaterEqual,
             .bang, .doubleAmp, .doublePipe, .fatArrow, .doubleArrow, .semicolon:
            return theme.operatorColor

        case .leftBrace, .rightBrace, .leftBracket, .rightBracket,
             .leftParen, .rightParen, .comma, .colon, .pipe, .at, .slash:
            return theme.delimiterColor

        default:
            return theme.textColor
        }
    }

    private func isKeyword(_ kind: TokenKind) -> Bool {
        switch kind {
        case .module, .open, .as, .sig, .abstract, .extends, .in,
             .fact, .pred, .fun, .assert, .run, .check, .for,
             .but, .exactly, .let, .disj, .var, .enum, .expect,
             .all, .some, .no, .one, .lone, .set, .seq, .sum,
             .always, .eventually, .after, .until, .releases,
             .historically, .once, .before, .since, .triggered, .steps,
             .and, .or, .not, .implies, .iff, .else:
            return true
        default:
            return false
        }
    }
}

// MARK: - AppKit Syntax Theme

/// AppKit theme for syntax highlighting
public struct AppKitSyntaxTheme {
    public let font: NSFont
    public let boldFont: NSFont
    public let textColor: NSColor
    public let keywordColor: NSColor
    public let quantifierColor: NSColor
    public let temporalColor: NSColor
    public let operatorColor: NSColor
    public let builtinColor: NSColor
    public let numberColor: NSColor
    public let stringColor: NSColor
    public let commentColor: NSColor
    public let delimiterColor: NSColor
    public let backgroundColor: NSColor

    public init(
        font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular),
        boldFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .bold),
        textColor: NSColor = .labelColor,
        keywordColor: NSColor = .systemPurple,
        quantifierColor: NSColor = .systemBlue,
        temporalColor: NSColor = .systemOrange,
        operatorColor: NSColor = .secondaryLabelColor,
        builtinColor: NSColor = .systemTeal,
        numberColor: NSColor = .systemCyan,
        stringColor: NSColor = .systemGreen,
        commentColor: NSColor = .systemGray,
        delimiterColor: NSColor = .secondaryLabelColor,
        backgroundColor: NSColor = .windowBackgroundColor
    ) {
        self.font = font
        self.boldFont = boldFont
        self.textColor = textColor
        self.keywordColor = keywordColor
        self.quantifierColor = quantifierColor
        self.temporalColor = temporalColor
        self.operatorColor = operatorColor
        self.builtinColor = builtinColor
        self.numberColor = numberColor
        self.stringColor = stringColor
        self.commentColor = commentColor
        self.delimiterColor = delimiterColor
        self.backgroundColor = backgroundColor
    }

    public static let `default` = AppKitSyntaxTheme()
}
