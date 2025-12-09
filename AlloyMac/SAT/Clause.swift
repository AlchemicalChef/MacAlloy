import Foundation

// MARK: - Clause

/// A disjunction of literals (clause in CNF)
/// Stored as a contiguous array of literal codes for cache efficiency
public struct Clause: Sendable {
    /// The literals in this clause
    public var literals: [Literal]

    /// Literal Block Distance (LBD) - measure of clause quality
    /// Lower LBD = more useful clause
    public var lbd: Int

    /// Whether this is a learned clause
    public let isLearned: Bool

    /// Activity score for clause deletion
    public var activity: Double

    /// Whether this clause has been deleted (lazy deletion)
    public var isDeleted: Bool

    /// Create a clause from literals
    public init(literals: [Literal], isLearned: Bool = false) {
        self.literals = literals
        self.isLearned = isLearned
        self.lbd = literals.count  // Will be computed properly during learning
        self.activity = 0
        self.isDeleted = false
    }

    /// Create a clause from literal codes
    public init(codes: [Int32], isLearned: Bool = false) {
        self.literals = codes.map { Literal(code: $0) }
        self.isLearned = isLearned
        self.lbd = literals.count
        self.activity = 0
        self.isDeleted = false
    }

    /// Number of literals
    @inlinable
    public var size: Int { literals.count }

    /// Whether this is a unit clause
    @inlinable
    public var isUnit: Bool { literals.count == 1 }

    /// Whether this is a binary clause
    @inlinable
    public var isBinary: Bool { literals.count == 2 }

    /// Whether this is the empty clause (conflict)
    @inlinable
    public var isEmpty: Bool { literals.isEmpty }

    /// Get literal at index
    @inlinable
    public subscript(index: Int) -> Literal {
        get { literals[index] }
        set { literals[index] = newValue }
    }

    /// First literal (first watched)
    public var first: Literal {
        precondition(!literals.isEmpty, "Cannot access first literal of empty clause")
        return literals[0]
    }

    /// Second literal (second watched, for non-unit clauses)
    public var second: Literal {
        precondition(literals.count >= 2, "Cannot access second literal of clause with fewer than 2 literals")
        return literals[1]
    }

    /// Swap literals at two positions
    public mutating func swap(_ i: Int, _ j: Int) {
        precondition(i >= 0 && i < literals.count, "Swap index i out of bounds")
        precondition(j >= 0 && j < literals.count, "Swap index j out of bounds")
        literals.swapAt(i, j)
    }

    /// Check if clause contains a literal
    @inlinable
    public func contains(_ literal: Literal) -> Bool {
        literals.contains(literal)
    }

    /// Check if clause contains a variable
    @inlinable
    public func contains(variable: Variable) -> Bool {
        literals.contains { $0.variable == variable }
    }

    /// Get all variables in this clause
    public var variables: Set<Variable> {
        Set(literals.map(\.variable))
    }

    /// Compute LBD given current decision levels
    public mutating func computeLBD(levels: (Variable) -> Int) {
        var seenLevels = Set<Int>()
        for lit in literals {
            seenLevels.insert(levels(lit.variable))
        }
        self.lbd = seenLevels.count
    }
}

extension Clause: CustomStringConvertible {
    public var description: String {
        if isEmpty { return "[]" }
        return "[\(literals.map(\.description).joined(separator: " | "))]"
    }
}

extension Clause: Equatable {
    public static func == (lhs: Clause, rhs: Clause) -> Bool {
        lhs.literals == rhs.literals
    }
}

// MARK: - Clause Database

/// Efficient storage for clauses with watched literal support
///
/// Thread Safety: This class is marked @unchecked Sendable but is NOT thread-safe.
/// It must only be accessed from a single thread at a time.
/// External synchronization is required for concurrent access.
public final class ClauseDatabase: @unchecked Sendable {
    /// All clauses (original + learned)
    private var clauses: [Clause] = []

    /// Number of original (non-learned) clauses
    private var numOriginal: Int = 0

    /// Watch lists: for each literal, list of clause refs watching it
    /// watchList[literal.code] = clauses where literal is watched
    private var watchLists: [[ClauseRef]] = []

    /// Maximum literal code seen
    private var maxLiteralCode: Int32 = 0

    /// Number of variables
    public private(set) var numVariables: Int = 0

    public init() {}

    /// Initialize for a given number of variables
    public func initialize(numVariables: Int) {
        self.numVariables = numVariables
        // Clear existing data
        self.clauses.removeAll()
        self.numOriginal = 0
        // Each variable can have positive and negative literal
        // Literal codes go from 2 to 2*numVariables + 1
        let numLiterals = (numVariables + 1) * 2
        self.watchLists = Array(repeating: [], count: numLiterals)
        self.maxLiteralCode = Int32(numLiterals - 1)
    }

    /// Number of clauses
    public var count: Int { clauses.count }

    /// Number of learned clauses (excluding deleted ones)
    public var learnedCount: Int {
        clauses[numOriginal...].filter { !$0.isDeleted && !$0.isEmpty }.count
    }

    /// Get clause by reference
    public subscript(ref: ClauseRef) -> Clause {
        get { clauses[Int(ref.index)] }
        set { clauses[Int(ref.index)] = newValue }
    }

    /// Add an original clause
    @discardableResult
    public func addOriginal(_ clause: Clause) -> ClauseRef {
        let ref = ClauseRef(Int32(clauses.count))
        clauses.append(clause)
        numOriginal += 1

        // Set up watches for non-unit clauses
        if clause.size >= 2 {
            addWatch(clause.first, ref)
            addWatch(clause.second, ref)
        }

        return ref
    }

    /// Add a learned clause
    @discardableResult
    public func addLearned(_ clause: Clause) -> ClauseRef {
        var learntClause = clause
        learntClause.activity = 1.0  // Initial activity

        let ref = ClauseRef(Int32(clauses.count))
        clauses.append(learntClause)

        // Set up watches for non-unit clauses
        if clause.size >= 2 {
            addWatch(clause.first, ref)
            addWatch(clause.second, ref)
        }

        return ref
    }

    /// Add a watch for a literal
    private func addWatch(_ literal: Literal, _ clauseRef: ClauseRef) {
        let code = Int(literal.code)
        if code < watchLists.count {
            watchLists[code].append(clauseRef)
        }
    }

    /// Remove a watch for a literal
    private func removeWatch(_ literal: Literal, _ clauseRef: ClauseRef) {
        let code = Int(literal.code)
        if code < watchLists.count {
            watchLists[code].removeAll { $0 == clauseRef }
        }
    }

    /// Get clauses watching a literal
    public func watchers(of literal: Literal) -> [ClauseRef] {
        let code = Int(literal.code)
        guard code < watchLists.count else { return [] }
        return watchLists[code]
    }

    /// Get mutable access to watch list
    public func watchList(for literal: Literal) -> ArraySlice<ClauseRef> {
        let code = Int(literal.code)
        guard code < watchLists.count else { return [] }
        return watchLists[code][...]
    }

    /// Update watch list after propagation
    /// Returns the new watch list for the literal
    public func updateWatches(for literal: Literal, keeping: [ClauseRef]) {
        let code = Int(literal.code)
        if code < watchLists.count {
            watchLists[code] = keeping
        }
    }

    /// Move watch from one literal to another within a clause
    public func moveWatch(clause ref: ClauseRef, from oldLit: Literal, to newLit: Literal) {
        removeWatch(oldLit, ref)
        addWatch(newLit, ref)
    }

    /// Iterate over all clauses
    public func forEach(_ body: (ClauseRef, Clause) -> Void) {
        for i in 0..<clauses.count {
            body(ClauseRef(Int32(i)), clauses[i])
        }
    }

    /// Get all clause references
    public var allRefs: [ClauseRef] {
        (0..<clauses.count).map { ClauseRef(Int32($0)) }
    }

    /// Get learned clause references for deletion
    public var learnedRefs: [ClauseRef] {
        (numOriginal..<clauses.count).map { ClauseRef(Int32($0)) }
    }

    /// Bump activity of a clause
    public func bumpActivity(_ ref: ClauseRef, by amount: Double) {
        clauses[Int(ref.index)].activity += amount
    }

    /// Decay all clause activities
    public func decayActivities(factor: Double) {
        for i in numOriginal..<clauses.count {
            clauses[i].activity *= factor
        }
    }

    /// Delete learned clauses below activity threshold
    /// Returns number of deleted clauses
    @discardableResult
    public func reduceDB(keepRatio: Double = 0.5) -> Int {
        guard learnedCount > 0 else { return 0 }

        // Get non-deleted learned clause indices and sort by activity (keep higher activity)
        var learnedIndices = (numOriginal..<clauses.count).filter {
            !clauses[$0].isDeleted && !clauses[$0].isEmpty
        }
        learnedIndices.sort { clauses[$0].activity > clauses[$1].activity }

        // Keep top half
        let keepCount = max(1, Int(Double(learnedIndices.count) * keepRatio))
        let toDelete = Set(learnedIndices.dropFirst(keepCount))

        // Remove watches and mark as deleted
        var deleted = 0
        for idx in toDelete {
            let clause = clauses[idx]
            if clause.size >= 2 {
                removeWatch(clause.first, ClauseRef(Int32(idx)))
                removeWatch(clause.second, ClauseRef(Int32(idx)))
            }
            clauses[idx].isDeleted = true
            deleted += 1
        }

        return deleted
    }

    /// Clear all clauses
    public func clear() {
        clauses.removeAll()
        numOriginal = 0
        for i in 0..<watchLists.count {
            watchLists[i].removeAll()
        }
    }
}
