import Foundation

/// Lexer for Alloy 6.2 source code
public final class Lexer: @unchecked Sendable {
    private let source: String
    private var currentIndex: String.Index
    private var currentLine: Int = 1
    private var currentColumn: Int = 1
    private var currentOffset: Int = 0

    // MARK: - Initialization

    public init(source: String) {
        self.source = source
        self.currentIndex = source.startIndex
    }

    // MARK: - Public API

    /// Scan all tokens from the source
    public func scanAllTokens() -> [Token] {
        var tokens: [Token] = []
        while true {
            let token = nextToken()
            tokens.append(token)
            if token.kind == .eof {
                break
            }
        }
        return tokens
    }

    /// Get the next token
    public func nextToken() -> Token {
        skipWhitespaceAndComments()

        // Check for unterminated block comment
        if unterminatedComment {
            unterminatedComment = false
            return Token(
                kind: .invalid("Unterminated block comment"),
                span: SourceSpan(start: currentPosition, end: currentPosition),
                text: ""
            )
        }

        guard !isAtEnd else {
            return makeToken(.eof, text: "")
        }

        let startPosition = currentPosition
        let char = advance()

        // Single-character tokens
        switch char {
        case "{": return makeToken(.leftBrace, from: startPosition)
        case "}": return makeToken(.rightBrace, from: startPosition)
        case "[": return makeToken(.leftBracket, from: startPosition)
        case "]": return makeToken(.rightBracket, from: startPosition)
        case "(": return makeToken(.leftParen, from: startPosition)
        case ")": return makeToken(.rightParen, from: startPosition)
        case ",": return makeToken(.comma, from: startPosition)
        case ";": return makeToken(.semicolon, from: startPosition)
        case "@": return makeToken(.at, from: startPosition)
        case ".": return makeToken(.dot, from: startPosition)
        case "~": return makeToken(.tilde, from: startPosition)
        case "^": return makeToken(.caret, from: startPosition)
        case "#": return makeToken(.hash, from: startPosition)
        case "'": return makeToken(.prime, from: startPosition)
        case "\"": return scanString(startPosition: startPosition)

        // Potentially multi-character tokens
        case "+":
            if match("+") { return makeToken(.plusPlus, from: startPosition) }
            return makeToken(.plus, from: startPosition)

        case "-":
            if match(">") { return makeToken(.arrow, from: startPosition) }
            return makeToken(.minus, from: startPosition)

        case "*":
            return makeToken(.star, from: startPosition)

        case "&":
            if match("&") { return makeToken(.doubleAmp, from: startPosition) }
            return makeToken(.ampersand, from: startPosition)

        case "|":
            if match("|") { return makeToken(.doublePipe, from: startPosition) }
            return makeToken(.pipe, from: startPosition)

        case "!":
            if match("=") { return makeToken(.notEqual, from: startPosition) }
            return makeToken(.bang, from: startPosition)

        case "=":
            if match(">") { return makeToken(.fatArrow, from: startPosition) }
            return makeToken(.equal, from: startPosition)

        case "<":
            if match("=") {
                if match(">") { return makeToken(.doubleArrow, from: startPosition) }
                return makeToken(.lessEqual, from: startPosition)
            }
            if match(":") { return makeToken(.leftRestrict, from: startPosition) }
            return makeToken(.less, from: startPosition)

        case ">":
            if match("=") { return makeToken(.greaterEqual, from: startPosition) }
            return makeToken(.greater, from: startPosition)

        case ":":
            if match(">") { return makeToken(.rightRestrict, from: startPosition) }
            return makeToken(.colon, from: startPosition)

        case "/":
            // Note: Comments are already handled in skipWhitespaceAndComments,
            // so if we get here, it's a standalone slash for qualified names
            return makeToken(.slash, from: startPosition)

        default:
            // Identifiers and keywords (including $ prefix for special variables)
            if char.isLetter || char == "_" || char == "$" {
                return scanIdentifier(startPosition: startPosition, firstChar: char)
            }

            // Numbers
            if char.isNumber {
                return scanNumber(startPosition: startPosition, firstChar: char)
            }

            // Unknown character
            return makeToken(.invalid(String(char)), from: startPosition)
        }
    }

    // MARK: - Private Helpers

    private var isAtEnd: Bool {
        currentIndex >= source.endIndex
    }

    private var currentPosition: SourcePosition {
        SourcePosition(line: currentLine, column: currentColumn, offset: currentOffset)
    }

    private func peek() -> Character? {
        guard !isAtEnd else { return nil }
        return source[currentIndex]
    }

    private func peekNext() -> Character? {
        let nextIndex = source.index(after: currentIndex)
        guard nextIndex < source.endIndex else { return nil }
        return source[nextIndex]
    }

    @discardableResult
    private func advance() -> Character {
        let char = source[currentIndex]
        currentIndex = source.index(after: currentIndex)
        currentOffset += 1

        if char == "\n" {
            currentLine += 1
            currentColumn = 1
        } else {
            currentColumn += 1
        }

        return char
    }

    private func retreat() {
        currentIndex = source.index(before: currentIndex)
        currentOffset -= 1

        // Check if we're backing up over a newline
        let retreatedChar = source[currentIndex]
        if retreatedChar == "\n" || retreatedChar == "\r" {
            // Backing up over newline - decrement line and scan back for column
            currentLine -= 1
            // Find the start of the previous line to calculate column
            var lineStart = currentIndex
            while lineStart > source.startIndex {
                let prevIndex = source.index(before: lineStart)
                let prevChar = source[prevIndex]
                if prevChar == "\n" || prevChar == "\r" {
                    break
                }
                lineStart = prevIndex
            }
            currentColumn = source.distance(from: lineStart, to: currentIndex) + 1
        } else {
            currentColumn -= 1
        }
    }

    private func match(_ expected: Character) -> Bool {
        guard !isAtEnd, source[currentIndex] == expected else { return false }
        advance()
        return true
    }

    private func makeToken(_ kind: TokenKind, text: String) -> Token {
        Token(kind: kind, span: .at(currentPosition), text: text)
    }

    private func makeToken(_ kind: TokenKind, from startPosition: SourcePosition) -> Token {
        let span = SourceSpan(start: startPosition, end: currentPosition)
        let text = String(source[source.index(source.startIndex, offsetBy: startPosition.offset)..<source.index(source.startIndex, offsetBy: currentOffset)])
        return Token(kind: kind, span: span, text: text)
    }

    // MARK: - Whitespace and Comments

    private func skipWhitespaceAndComments() {
        while !isAtEnd {
            guard let char = peek() else { break }

            switch char {
            case " ", "\t", "\r", "\n":
                advance()

            case "/":
                if peekNext() == "/" {
                    skipLineComment()
                } else if peekNext() == "*" {
                    if !skipBlockComment() {
                        unterminatedComment = true
                        return
                    }
                } else {
                    return
                }

            case "-":
                if peekNext() == "-" {
                    skipLineComment()
                } else {
                    return
                }

            default:
                return
            }
        }
    }

    private func skipLineComment() {
        // Skip the comment start (// or --)
        advance()
        advance()

        // Skip until end of line
        while !isAtEnd, peek() != "\n" {
            advance()
        }
    }

    /// Skip block comment. Returns true if properly terminated, false if EOF reached.
    private func skipBlockComment() -> Bool {
        // Skip /*
        advance()
        advance()

        // Skip until */
        while !isAtEnd {
            if peek() == "*", peekNext() == "/" {
                advance() // *
                advance() // /
                return true
            }
            advance()
        }
        // Reached EOF without finding */
        return false
    }

    /// Tracks if we encountered an unterminated comment
    private var unterminatedComment = false

    // MARK: - Identifiers and Keywords

    private func scanIdentifier(startPosition: SourcePosition, firstChar: Character) -> Token {
        var text = String(firstChar)

        while !isAtEnd {
            guard let char = peek() else { break }
            if char.isLetter || char.isNumber || char == "_" || char == "$" {
                text.append(advance())
            } else {
                break
            }
        }

        // Check if it's a keyword
        let kind = TokenKind.keyword(text) ?? .identifier(text)
        let span = SourceSpan(start: startPosition, end: currentPosition)
        return Token(kind: kind, span: span, text: text)
    }

    // MARK: - Numbers

    private func scanNumber(startPosition: SourcePosition, firstChar: Character) -> Token {
        var text = String(firstChar)

        while !isAtEnd {
            guard let char = peek(), char.isNumber else { break }
            text.append(advance())
        }

        let span = SourceSpan(start: startPosition, end: currentPosition)

        // Handle integer overflow - report error instead of silently returning 0
        guard let value = Int(text) else {
            return Token(kind: .invalid("Integer literal too large: \(text)"), span: span, text: text)
        }

        return Token(kind: .integer(value), span: span, text: text)
    }

    // MARK: - Strings

    private func scanString(startPosition: SourcePosition) -> Token {
        var text = ""

        while !isAtEnd {
            guard let char = peek() else { break }

            if char == "\"" {
                advance() // consume closing quote
                let span = SourceSpan(start: startPosition, end: currentPosition)
                return Token(kind: .string(text), span: span, text: "\"\(text)\"")
            }

            if char == "\\" {
                // Handle escape sequences
                advance() // consume backslash
                if let escaped = peek() {
                    advance()
                    switch escaped {
                    case "n": text.append("\n")
                    case "t": text.append("\t")
                    case "r": text.append("\r")
                    case "\\": text.append("\\")
                    case "\"": text.append("\"")
                    default: text.append(escaped)
                    }
                }
            } else if char == "\n" {
                // Unterminated string (newline before closing quote)
                let span = SourceSpan(start: startPosition, end: currentPosition)
                return Token(kind: .invalid("Unterminated string literal"), span: span, text: "\"\(text)")
            } else {
                text.append(advance())
            }
        }

        // Reached EOF without closing quote
        let span = SourceSpan(start: startPosition, end: currentPosition)
        return Token(kind: .invalid("Unterminated string literal"), span: span, text: "\"\(text)")
    }
}
