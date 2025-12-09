import Foundation

/// Represents a position in source code
public struct SourcePosition: Equatable, Hashable, Sendable {
    /// 1-based line number
    public let line: Int
    /// 1-based column number
    public let column: Int
    /// 0-based byte offset from file start
    public let offset: Int

    public init(line: Int, column: Int, offset: Int) {
        self.line = line
        self.column = column
        self.offset = offset
    }

    public static let zero = SourcePosition(line: 1, column: 1, offset: 0)
}

/// Represents a span of source code
public struct SourceSpan: Equatable, Hashable, Sendable {
    public let start: SourcePosition
    public let end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }

    /// Length in bytes
    public var length: Int { end.offset - start.offset }

    /// Merge two spans into one that covers both
    public func merged(with other: SourceSpan) -> SourceSpan {
        SourceSpan(
            start: start.offset < other.start.offset ? start : other.start,
            end: end.offset > other.end.offset ? end : other.end
        )
    }

    /// Create a zero-length span at a position
    public static func at(_ position: SourcePosition) -> SourceSpan {
        SourceSpan(start: position, end: position)
    }

    /// Empty span at the beginning
    public static let empty = SourceSpan(start: .zero, end: .zero)

    /// Alias for empty span
    public static let zero = empty
}

extension SourcePosition: CustomStringConvertible {
    public var description: String {
        "\(line):\(column)"
    }
}

extension SourceSpan: CustomStringConvertible {
    public var description: String {
        if start.line == end.line {
            return "\(start.line):\(start.column)-\(end.column)"
        }
        return "\(start)-\(end)"
    }
}
