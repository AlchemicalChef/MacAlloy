import Foundation

// MARK: - Alloy Constants

/// Global constants for AlloyiPad configuration
public enum AlloyConstants {
    // MARK: - Integer Encoding

    /// Default bit width for bounded integers (4 bits = range -8 to 7)
    public static let defaultIntegerBitWidth = 4

    // MARK: - Scope Defaults

    /// Default scope for signatures when not specified
    public static let defaultScope = 3

    /// Default trace length for temporal models
    public static let defaultTraceLength = 10

    // MARK: - Analysis

    /// Delay before re-analyzing after source code changes (in seconds)
    public static let analysisDebounceDelay: TimeInterval = 0.3

    // MARK: - SAT Solver Limits

    /// Maximum number of tuples to process in join operations
    public static let maxJoinTuples = 1_000_000
}
