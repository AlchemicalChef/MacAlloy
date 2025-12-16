#if os(iOS)
import UIKit

// MARK: - UIKit Syntax Highlighter

/// UIKit-based syntax highlighter for use with UITextView on iOS
public final class UIKitSyntaxHighlighter {
    public let theme: UIKitSyntaxTheme

    public init(theme: UIKitSyntaxTheme = .default) {
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

    // MARK: - Comment Highlighting

    private func highlightComments(in source: String, result: NSMutableAttributedString) {
        // Line comments: // ...
        let lineCommentPattern = "//[^\n]*"
        if let regex = try? NSRegularExpression(pattern: lineCommentPattern) {
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            for match in matches {
                result.addAttribute(.foregroundColor, value: theme.commentColor, range: match.range)
            }
        }

        // Block comments: /* ... */
        let blockCommentPattern = "/\\*[\\s\\S]*?\\*/"
        if let regex = try? NSRegularExpression(pattern: blockCommentPattern) {
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            for match in matches {
                result.addAttribute(.foregroundColor, value: theme.commentColor, range: match.range)
            }
        }

        // Doc comments: /** ... */
        let docCommentPattern = "/\\*\\*[\\s\\S]*?\\*/"
        if let regex = try? NSRegularExpression(pattern: docCommentPattern) {
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            for match in matches {
                result.addAttribute(.foregroundColor, value: theme.commentColor, range: match.range)
            }
        }
    }

    // MARK: - Token Color Mapping

    private func color(for kind: TokenKind) -> UIColor {
        switch kind {
        // Keywords
        case .module, .open, .as, .sig, .abstract, .extends, .in,
             .fact, .pred, .fun, .assert, .run, .check, .for,
             .but, .exactly, .let, .disj, .var, .enum, .expect:
            return theme.keywordColor

        // Quantifiers
        case .all, .some, .no, .one, .lone, .set, .seq, .sum:
            return theme.quantifierColor

        // Temporal operators
        case .always, .eventually, .after, .until, .releases,
             .historically, .once, .before, .since, .triggered, .steps:
            return theme.temporalColor

        // Logical operators
        case .and, .or, .not, .implies, .iff, .else:
            return theme.operatorColor

        // Builtins
        case .none, .univ, .iden, .int:
            return theme.builtinColor

        // Numbers
        case .integer:
            return theme.numberColor

        // Delimiters
        case .leftBrace, .rightBrace, .leftParen, .rightParen,
             .leftBracket, .rightBracket, .comma, .colon, .pipe, .at, .slash:
            return theme.delimiterColor

        // Operators
        case .plus, .minus, .ampersand, .arrow, .dot, .tilde,
             .caret, .star, .hash, .prime, .plusPlus, .rightRestrict, .leftRestrict,
             .equal, .notEqual, .less, .greater, .lessEqual, .greaterEqual,
             .bang, .doubleAmp, .doublePipe, .fatArrow, .doubleArrow, .semicolon:
            return theme.operatorColor

        // Default
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

// MARK: - UIKit Syntax Theme

/// UIKit theme for syntax highlighting on iOS
public struct UIKitSyntaxTheme {
    public let font: UIFont
    public let boldFont: UIFont
    public let textColor: UIColor
    public let keywordColor: UIColor
    public let quantifierColor: UIColor
    public let temporalColor: UIColor
    public let operatorColor: UIColor
    public let builtinColor: UIColor
    public let numberColor: UIColor
    public let stringColor: UIColor
    public let commentColor: UIColor
    public let delimiterColor: UIColor
    public let backgroundColor: UIColor

    public init(
        font: UIFont = .monospacedSystemFont(ofSize: 14, weight: .regular),
        boldFont: UIFont = .monospacedSystemFont(ofSize: 14, weight: .bold),
        textColor: UIColor = .label,
        keywordColor: UIColor = .systemPurple,
        quantifierColor: UIColor = .systemBlue,
        temporalColor: UIColor = .systemOrange,
        operatorColor: UIColor = .secondaryLabel,
        builtinColor: UIColor = .systemTeal,
        numberColor: UIColor = .systemCyan,
        stringColor: UIColor = .systemGreen,
        commentColor: UIColor = .systemGray,
        delimiterColor: UIColor = .secondaryLabel,
        backgroundColor: UIColor = .systemBackground
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

    public static let `default` = UIKitSyntaxTheme()
}
#endif
