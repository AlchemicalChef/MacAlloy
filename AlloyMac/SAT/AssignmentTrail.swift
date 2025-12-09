import Foundation

// MARK: - Assignment Trail

/// Tracks variable assignments in chronological order
/// Supports efficient backtracking and reason lookup
///
/// Thread Safety: This class is marked @unchecked Sendable but is NOT thread-safe.
/// It must only be accessed from a single thread at a time.
/// External synchronization is required for concurrent access.
public final class AssignmentTrail: @unchecked Sendable {
    /// The trail of assignments
    private var trail: [Assignment] = []

    /// Current values of variables (indexed by variable index)
    /// undefined = unassigned, true/false = assigned
    private var values: [LiftedBool] = []

    /// Decision level of each variable (indexed by variable index)
    private var levels: [Int] = []

    /// Reason clause for each variable (indexed by variable index)
    private var reasons: [ClauseRef?] = []

    /// Trail index for each variable (indexed by variable index)
    private var trailIndices: [Int] = []

    /// Indices in trail where each decision level starts
    private var levelStarts: [Int] = []

    /// Current decision level
    public private(set) var currentLevel: Int = 0

    /// Number of variables
    public private(set) var numVariables: Int = 0

    /// Head of propagation queue (index into trail)
    public var propagationHead: Int = 0

    public init() {}

    /// Initialize for a given number of variables
    public func initialize(numVariables: Int) {
        self.numVariables = numVariables
        let size = numVariables + 1  // 1-indexed

        values = Array(repeating: .undefined, count: size)
        levels = Array(repeating: -1, count: size)
        reasons = Array(repeating: nil, count: size)
        trailIndices = Array(repeating: -1, count: size)
        trail.removeAll()
        levelStarts = [0]  // Level 0 starts at index 0
        currentLevel = 0
        propagationHead = 0
    }

    /// Number of assigned variables
    public var assignedCount: Int { trail.count }

    /// Number of unassigned variables
    public var unassignedCount: Int { numVariables - trail.count }

    /// Whether all variables are assigned
    public var isComplete: Bool { trail.count == numVariables }

    // MARK: - Value Access

    /// Get the value of a variable
    public func value(of variable: Variable) -> LiftedBool {
        let idx = Int(variable.index)
        guard idx < values.count else { return .undefined }
        return values[idx]
    }

    /// Get the value of a literal under current assignment
    public func value(of literal: Literal) -> LiftedBool {
        let varValue = value(of: literal.variable)
        guard varValue.isDefined else { return .undefined }
        return literal.isNegated ? varValue.negated : varValue
    }

    /// Check if a variable is assigned
    public func isAssigned(_ variable: Variable) -> Bool {
        value(of: variable).isDefined
    }

    /// Check if a literal is satisfied
    public func isSatisfied(_ literal: Literal) -> Bool {
        value(of: literal) == .true
    }

    /// Check if a literal is falsified
    public func isFalsified(_ literal: Literal) -> Bool {
        value(of: literal) == .false
    }

    /// Get decision level of a variable
    public func level(of variable: Variable) -> Int {
        let idx = Int(variable.index)
        guard idx < levels.count else { return -1 }
        return levels[idx]
    }

    /// Get reason clause for a variable
    public func reason(of variable: Variable) -> ClauseRef? {
        let idx = Int(variable.index)
        guard idx < reasons.count else { return nil }
        return reasons[idx]
    }

    /// Get trail index of a variable
    public func trailIndex(of variable: Variable) -> Int {
        let idx = Int(variable.index)
        guard idx < trailIndices.count else { return -1 }
        return trailIndices[idx]
    }

    /// Check if assignment is a decision
    public func isDecision(_ variable: Variable) -> Bool {
        reason(of: variable) == nil && isAssigned(variable)
    }

    // MARK: - Assignment Operations

    /// Make a decision (assign with no reason)
    public func decide(_ literal: Literal) {
        currentLevel += 1
        levelStarts.append(trail.count)
        assign(literal, reason: nil)
    }

    /// Propagate (assign with a reason clause)
    public func propagate(_ literal: Literal, reason: ClauseRef) {
        assign(literal, reason: reason)
    }

    /// Internal assignment
    private func assign(_ literal: Literal, reason: ClauseRef?) {
        let variable = literal.variable
        let idx = Int(variable.index)
        let value: Bool = literal.isPositive

        let assignment = Assignment(
            variable: variable,
            value: value,
            level: currentLevel,
            reason: reason,
            trailIndex: trail.count
        )

        trail.append(assignment)
        values[idx] = LiftedBool(value)
        levels[idx] = currentLevel
        reasons[idx] = reason
        trailIndices[idx] = trail.count - 1
    }

    /// Get the next literal to propagate (nil if none)
    public func nextPropagation() -> Literal? {
        guard propagationHead < trail.count else { return nil }
        let assignment = trail[propagationHead]
        propagationHead += 1
        // Return the literal that was assigned true
        return assignment.value ?
            Literal(variable: assignment.variable, isNegated: false) :
            Literal(variable: assignment.variable, isNegated: true)
    }

    // MARK: - Backtracking

    /// Backtrack to a given decision level
    public func backtrack(to level: Int) {
        guard level >= 0 && level < currentLevel else { return }
        guard level + 1 < levelStarts.count else { return }

        let targetIndex = levelStarts[level + 1]

        // Unassign variables from trail
        while trail.count > targetIndex {
            let assignment = trail.removeLast()
            let idx = Int(assignment.variable.index)
            values[idx] = .undefined
            levels[idx] = -1
            reasons[idx] = nil
            trailIndices[idx] = -1
        }

        // Remove level markers
        while levelStarts.count > level + 1 {
            levelStarts.removeLast()
        }

        currentLevel = level
        propagationHead = min(propagationHead, trail.count)
    }

    /// Backtrack one level
    public func backtrackOne() {
        backtrack(to: currentLevel - 1)
    }

    /// Cancel all assignments (back to level 0)
    public func cancelAll() {
        backtrack(to: 0)
        // Also undo level 0 propagations
        while !trail.isEmpty {
            let assignment = trail.removeLast()
            let idx = Int(assignment.variable.index)
            values[idx] = .undefined
            levels[idx] = -1
            reasons[idx] = nil
            trailIndices[idx] = -1
        }
        propagationHead = 0
    }

    // MARK: - Trail Access

    /// Get assignment at trail index
    /// Precondition: index must be in bounds [0, assignedCount)
    public func assignment(at index: Int) -> Assignment {
        precondition(index >= 0 && index < trail.count, "Trail index \(index) out of bounds [0, \(trail.count))")
        return trail[index]
    }

    /// Iterate over trail from newest to oldest
    public func forEachReverse(_ body: (Assignment) -> Void) {
        for i in stride(from: trail.count - 1, through: 0, by: -1) {
            body(trail[i])
        }
    }

    /// Get trail slice from a given index
    public func trailFrom(_ index: Int) -> ArraySlice<Assignment> {
        guard index >= 0 && index <= trail.count else { return [] }
        return trail[index...]
    }

    /// Get current model (full assignment)
    /// Returns array where index i is the value of variable i (1-indexed)
    public func model() -> [Bool] {
        var result = Array(repeating: false, count: numVariables + 1)
        for assignment in trail {
            result[Int(assignment.variable.index)] = assignment.value
        }
        return result
    }

    // MARK: - Conflict Analysis Support

    /// Get all variables assigned at the current level
    public func variablesAtCurrentLevel() -> [Variable] {
        guard currentLevel < levelStarts.count else { return [] }
        let startIdx = levelStarts[currentLevel]
        return trail[startIdx...].map(\.variable)
    }

    /// Count literals in a set that are assigned at the current level
    public func countAtCurrentLevel(_ literals: [Literal]) -> Int {
        var count = 0
        for lit in literals {
            if level(of: lit.variable) == currentLevel {
                count += 1
            }
        }
        return count
    }
}

// MARK: - Debug

extension AssignmentTrail: CustomStringConvertible {
    public var description: String {
        var result = "Trail (level \(currentLevel)):\n"
        for (i, assignment) in trail.enumerated() {
            let marker = levelStarts.contains(i) ? "* " : "  "
            let value = assignment.value ? "T" : "F"
            let reason = assignment.reason.map { "\($0)" } ?? "decision"
            result += "\(marker)\(i): x\(assignment.variable.index)=\(value) @\(assignment.level) [\(reason)]\n"
        }
        return result
    }
}
