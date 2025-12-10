import Foundation

/// All token types in Alloy 6.2
public enum TokenKind: Equatable, Hashable, Sendable {
    // MARK: - Literals and Identifiers

    /// An identifier (variable, type, function name, etc.)
    case identifier(String)
    /// An integer literal
    case integer(Int)
    /// A string literal
    case string(String)

    // MARK: - Keywords - Module System

    /// `module` keyword
    case module
    /// `open` keyword
    case open
    /// `as` keyword
    case `as`

    // MARK: - Keywords - Signatures

    /// `sig` keyword
    case sig
    /// `abstract` keyword
    case abstract
    /// `extends` keyword
    case extends
    /// `in` keyword (subset, membership)
    case `in`
    /// `var` keyword (mutable field/sig - Alloy 6)
    case `var`
    /// `enum` keyword
    case `enum`

    // MARK: - Keywords - Declarations

    /// `fact` keyword
    case fact
    /// `pred` keyword (predicate)
    case pred
    /// `fun` keyword (function)
    case fun
    /// `assert` keyword
    case assert

    // MARK: - Keywords - Commands

    /// `run` keyword
    case run
    /// `check` keyword
    case check
    /// `for` keyword (scope)
    case `for`
    /// `but` keyword (scope override)
    case but
    /// `exactly` keyword
    case exactly
    /// `steps` keyword (temporal bound - Alloy 6)
    case steps
    /// `expect` keyword
    case expect

    // MARK: - Keywords - Multiplicity

    /// `lone` keyword (0 or 1)
    case lone
    /// `one` keyword (exactly 1)
    case one
    /// `some` keyword (1 or more)
    case some
    /// `set` keyword (any number)
    case set
    /// `seq` keyword (sequence)
    case seq
    /// `disj` keyword (disjoint)
    case disj

    // MARK: - Keywords - Quantifiers

    /// `all` keyword
    case all
    /// `no` keyword
    case no
    /// `sum` keyword (integer sum)
    case sum

    // MARK: - Keywords - Logical

    /// `and` keyword
    case and
    /// `or` keyword
    case or
    /// `not` keyword
    case not
    /// `implies` keyword
    case implies
    /// `iff` keyword
    case iff
    /// `else` keyword
    case `else`
    /// `let` keyword
    case `let`

    // MARK: - Keywords - Temporal (Alloy 6)

    // Future operators
    /// `always` keyword
    case always
    /// `eventually` keyword
    case eventually
    /// `after` keyword
    case after
    /// `until` keyword
    case until
    /// `releases` keyword
    case releases

    // Past operators
    /// `historically` keyword
    case historically
    /// `once` keyword
    case once
    /// `before` keyword
    case before
    /// `since` keyword
    case since
    /// `triggered` keyword
    case triggered

    // MARK: - Keywords - Built-in Sets

    /// `univ` keyword (universal set)
    case univ
    /// `iden` keyword (identity relation)
    case iden
    /// `none` keyword (empty set)
    case none
    /// `Int` keyword (integer type)
    case int
    /// `this` keyword (current signature reference)
    case this

    // MARK: - Keywords - Visibility

    /// `private` keyword (visibility modifier)
    case `private`

    // MARK: - Keywords - Alloy 6 Event Idiom

    /// `enabled` keyword (event idiom)
    case enabled
    /// `event` keyword (event idiom)
    case event
    /// `invariant` keyword (temporal invariant)
    case invariant
    /// `modifies` keyword (frame condition)
    case modifies

    // MARK: - Operators - Relational

    /// `.` (join)
    case dot
    /// `->` (product)
    case arrow
    /// `~` (transpose)
    case tilde
    /// `^` (transitive closure)
    case caret
    /// `*` (reflexive-transitive closure)
    case star
    /// `#` (cardinality)
    case hash
    /// `'` (primed - next state value, Alloy 6)
    case prime

    // MARK: - Operators - Set

    /// `+` (union)
    case plus
    /// `-` (difference)
    case minus
    /// `&` (intersection)
    case ampersand
    /// `++` (override)
    case plusPlus

    // MARK: - Operators - Domain/Range Restriction

    /// `<:` (domain restriction)
    case leftRestrict
    /// `:>` (range restriction)
    case rightRestrict

    // MARK: - Operators - Comparison

    /// `=`
    case equal
    /// `!=`
    case notEqual
    /// `<`
    case less
    /// `>`
    case greater
    /// `=<` (Alloy uses =< not <=)
    case lessEqual
    /// `>=`
    case greaterEqual

    // MARK: - Operators - Logical

    /// `!`
    case bang
    /// `&&`
    case doubleAmp
    /// `||`
    case doublePipe
    /// `=>`
    case fatArrow
    /// `<=>`
    case doubleArrow

    // MARK: - Operators - Temporal

    /// `;` (sequencing: a ; b = a and after b)
    case semicolon

    // MARK: - Delimiters

    /// `{`
    case leftBrace
    /// `}`
    case rightBrace
    /// `[`
    case leftBracket
    /// `]`
    case rightBracket
    /// `(`
    case leftParen
    /// `)`
    case rightParen
    /// `,`
    case comma
    /// `:`
    case colon
    /// `|`
    case pipe
    /// `@` (for specific instantiation)
    case at
    /// `/` (for qualified names like util/ordering)
    case slash

    // MARK: - Special

    /// End of file
    case eof
    /// Invalid token (for error recovery)
    case invalid(String)
}

extension TokenKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .identifier(let name): return "identifier(\(name))"
        case .integer(let value): return "integer(\(value))"
        case .string(let value): return "string(\"\(value)\")"
        case .module: return "module"
        case .open: return "open"
        case .as: return "as"
        case .sig: return "sig"
        case .abstract: return "abstract"
        case .extends: return "extends"
        case .in: return "in"
        case .var: return "var"
        case .enum: return "enum"
        case .fact: return "fact"
        case .pred: return "pred"
        case .fun: return "fun"
        case .assert: return "assert"
        case .run: return "run"
        case .check: return "check"
        case .for: return "for"
        case .but: return "but"
        case .exactly: return "exactly"
        case .steps: return "steps"
        case .expect: return "expect"
        case .lone: return "lone"
        case .one: return "one"
        case .some: return "some"
        case .set: return "set"
        case .seq: return "seq"
        case .disj: return "disj"
        case .all: return "all"
        case .no: return "no"
        case .sum: return "sum"
        case .and: return "and"
        case .or: return "or"
        case .not: return "not"
        case .implies: return "implies"
        case .iff: return "iff"
        case .else: return "else"
        case .let: return "let"
        case .always: return "always"
        case .eventually: return "eventually"
        case .after: return "after"
        case .until: return "until"
        case .releases: return "releases"
        case .historically: return "historically"
        case .once: return "once"
        case .before: return "before"
        case .since: return "since"
        case .triggered: return "triggered"
        case .univ: return "univ"
        case .iden: return "iden"
        case .none: return "none"
        case .int: return "Int"
        case .this: return "this"
        case .private: return "private"
        case .enabled: return "enabled"
        case .event: return "event"
        case .invariant: return "invariant"
        case .modifies: return "modifies"
        case .dot: return "."
        case .arrow: return "->"
        case .tilde: return "~"
        case .caret: return "^"
        case .star: return "*"
        case .hash: return "#"
        case .prime: return "'"
        case .plus: return "+"
        case .minus: return "-"
        case .ampersand: return "&"
        case .plusPlus: return "++"
        case .leftRestrict: return "<:"
        case .rightRestrict: return ":>"
        case .equal: return "="
        case .notEqual: return "!="
        case .less: return "<"
        case .greater: return ">"
        case .lessEqual: return "=<"
        case .greaterEqual: return ">="
        case .bang: return "!"
        case .doubleAmp: return "&&"
        case .doublePipe: return "||"
        case .fatArrow: return "=>"
        case .doubleArrow: return "<=>"
        case .semicolon: return ";"
        case .leftBrace: return "{"
        case .rightBrace: return "}"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .leftParen: return "("
        case .rightParen: return ")"
        case .comma: return ","
        case .colon: return ":"
        case .pipe: return "|"
        case .at: return "@"
        case .slash: return "/"
        case .eof: return "EOF"
        case .invalid(let text): return "invalid(\(text))"
        }
    }
}

// MARK: - Keyword Lookup

extension TokenKind {
    /// Map from keyword strings to their token kinds
    static let keywords: [String: TokenKind] = [
        // Module system
        "module": .module,
        "open": .open,
        "as": .as,

        // Signatures
        "sig": .sig,
        "abstract": .abstract,
        "extends": .extends,
        "in": .in,
        "var": .var,
        "enum": .enum,

        // Declarations
        "fact": .fact,
        "pred": .pred,
        "fun": .fun,
        "assert": .assert,

        // Commands
        "run": .run,
        "check": .check,
        "for": .for,
        "but": .but,
        "exactly": .exactly,
        "steps": .steps,
        "expect": .expect,

        // Multiplicity
        "lone": .lone,
        "one": .one,
        "some": .some,
        "set": .set,
        "seq": .seq,
        "disj": .disj,

        // Quantifiers
        "all": .all,
        "no": .no,
        "sum": .sum,

        // Logical
        "and": .and,
        "or": .or,
        "not": .not,
        "implies": .implies,
        "iff": .iff,
        "else": .else,
        "let": .let,

        // Temporal (Alloy 6)
        "always": .always,
        "eventually": .eventually,
        "after": .after,
        "until": .until,
        "releases": .releases,
        "historically": .historically,
        "once": .once,
        "before": .before,
        "since": .since,
        "triggered": .triggered,

        // Built-in sets
        "univ": .univ,
        "iden": .iden,
        "none": .none,
        "Int": .int,
        "this": .this,

        // Visibility
        "private": .private,

        // Alloy 6 event idiom
        "enabled": .enabled,
        "event": .event,
        "invariant": .invariant,
        "modifies": .modifies,
    ]

    /// Look up a keyword, returning nil if not a keyword
    static func keyword(_ text: String) -> TokenKind? {
        keywords[text]
    }
}
