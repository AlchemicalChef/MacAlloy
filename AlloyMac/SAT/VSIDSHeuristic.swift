import Foundation

// MARK: - VSIDS Heuristic

/// Variable State Independent Decaying Sum (VSIDS) heuristic
/// Picks the unassigned variable with highest activity score
/// Activities are bumped during conflict analysis and decayed periodically
///
/// Thread Safety: This class is marked @unchecked Sendable but is NOT thread-safe.
/// It must only be accessed from a single thread at a time.
/// External synchronization is required for concurrent access.
public final class VSIDSHeuristic: @unchecked Sendable {
    /// Activity score for each variable (1-indexed)
    private var activities: [Double] = []

    /// Priority heap for quick selection of highest activity unassigned variable
    /// Heap contains variable indices (not Variable structs for efficiency)
    private var heap: [Int32] = []

    /// Position of each variable in the heap (-1 if not in heap)
    private var heapPosition: [Int] = []

    /// Activity increment (increases over time due to decay)
    private var activityIncrement: Double = 1.0

    /// Decay factor (applied after each conflict)
    private let decayFactor: Double = 0.95

    /// Inverse of decay factor (for efficient bump)
    private let inverseDecay: Double

    /// Number of variables
    private var numVariables: Int = 0

    /// Phase saving: last polarity for each variable
    private var savedPhases: [Bool] = []

    /// Whether to use phase saving
    public var usePhaseSaving: Bool = true

    public init() {
        self.inverseDecay = 1.0 / decayFactor
    }

    /// Initialize for a given number of variables
    public func initialize(numVariables: Int) {
        self.numVariables = numVariables
        let size = numVariables + 1

        activities = Array(repeating: 0.0, count: size)
        heapPosition = Array(repeating: -1, count: size)
        savedPhases = Array(repeating: true, count: size)  // Default to positive
        activityIncrement = 1.0

        // Build initial heap with all variables
        if numVariables > 0 {
            heap = Array(1...Int32(numVariables))
            for i in 0..<numVariables {
                heapPosition[Int(heap[i])] = i
            }

            // Heapify (though initially all activities are 0)
            buildHeap()
        } else {
            heap = []
        }
    }

    // MARK: - Activity Management

    /// Bump activity of a variable (called during conflict analysis)
    public func bumpActivity(of variable: Variable) {
        let idx = Int(variable.index)
        guard idx < activities.count else { return }

        activities[idx] += activityIncrement

        // Rescale if activities get too large
        if activities[idx] > 1e100 {
            rescaleActivities()
        }

        // Update heap position
        guard idx < heapPosition.count else { return }
        if heapPosition[idx] >= 0 {
            siftUp(heapPosition[idx])
        }
    }

    /// Bump activity of a literal's variable
    @inlinable
    public func bumpActivity(of literal: Literal) {
        bumpActivity(of: literal.variable)
    }

    /// Decay all activities (called after each conflict)
    public func decayActivities() {
        activityIncrement *= inverseDecay
        // Rescale if activityIncrement is getting too large (prevents overflow)
        if activityIncrement > 1e90 {
            rescaleActivities()
        }
    }

    /// Rescale all activities to prevent overflow
    private func rescaleActivities() {
        guard numVariables > 0 else { return }
        let scale = 1e-100
        for i in 1...numVariables {
            activities[i] *= scale
        }
        activityIncrement *= scale
    }

    /// Get activity of a variable
    public func activity(of variable: Variable) -> Double {
        let idx = Int(variable.index)
        guard idx < activities.count else { return 0 }
        return activities[idx]
    }

    // MARK: - Variable Selection

    /// Pick the next unassigned variable (or nil if all assigned)
    /// Uses phase saving for polarity
    public func pickBranchVariable(trail: AssignmentTrail) -> Literal? {
        // Remove assigned variables from heap top
        while !heap.isEmpty {
            let varIdx = Int(heap[0])
            guard varIdx > 0 && varIdx <= numVariables else {
                // Invalid variable index in heap, remove and continue
                _ = extractMax()
                continue
            }
            let topVar = Variable(Int32(varIdx))
            if !trail.isAssigned(topVar) {
                let phase = usePhaseSaving && varIdx < savedPhases.count ? savedPhases[varIdx] : true
                return Literal(variable: topVar, isNegated: !phase)
            }
            // Remove from heap
            _ = extractMax()
        }
        return nil
    }

    /// Save the phase of a variable (called during backtracking)
    public func savePhase(of variable: Variable, value: Bool) {
        let idx = Int(variable.index)
        guard idx > 0 && idx < savedPhases.count else { return }
        savedPhases[idx] = value
    }

    /// Insert a variable back into the heap (called during backtracking)
    public func insertVariable(_ variable: Variable) {
        let idx = Int(variable.index)
        guard idx > 0 && idx < heapPosition.count else { return }  // Bounds check
        guard heapPosition[idx] < 0 else { return }  // Already in heap

        heap.append(Int32(idx))
        heapPosition[idx] = heap.count - 1
        siftUp(heap.count - 1)
    }

    /// Remove a variable from the heap (called when assigned)
    public func removeVariable(_ variable: Variable) {
        let idx = Int(variable.index)
        guard idx > 0 && idx < heapPosition.count else { return }  // Bounds check
        let pos = heapPosition[idx]
        guard pos >= 0 else { return }  // Not in heap

        // Swap with last element
        let lastIdx = heap.count - 1
        if pos != lastIdx {
            swap(pos, lastIdx)
        }

        heap.removeLast()
        heapPosition[idx] = -1

        if pos < heap.count {
            // After swapping, the element may need to go up or down
            // Check if parent is smaller (need to sift up) or children are larger (need to sift down)
            let parent = (pos - 1) / 2
            if pos > 0 && activities[Int(heap[pos])] > activities[Int(heap[parent])] {
                siftUp(pos)
            } else {
                siftDown(pos)
            }
        }
    }

    // MARK: - Heap Operations

    private func buildHeap() {
        for i in stride(from: heap.count / 2 - 1, through: 0, by: -1) {
            siftDown(i)
        }
    }

    private func extractMax() -> Int32? {
        guard !heap.isEmpty else { return nil }

        let max = heap[0]
        let lastIdx = heap.count - 1
        if lastIdx > 0 {
            heap[0] = heap[lastIdx]
            heapPosition[Int(heap[0])] = 0
        }
        heap.removeLast()
        heapPosition[Int(max)] = -1

        if !heap.isEmpty {
            siftDown(0)
        }

        return max
    }

    private func siftUp(_ pos: Int) {
        guard pos >= 0 && pos < heap.count else { return }
        var i = pos
        let varIdx = heap[i]
        let varIdxInt = Int(varIdx)
        guard varIdxInt >= 0 && varIdxInt < activities.count else { return }
        let activity = activities[varIdxInt]

        while i > 0 {
            let parent = (i - 1) / 2
            let parentVarIdx = Int(heap[parent])
            guard parentVarIdx >= 0 && parentVarIdx < activities.count else { break }
            if activities[parentVarIdx] >= activity {
                break
            }
            heap[i] = heap[parent]
            heapPosition[Int(heap[i])] = i
            i = parent
        }

        heap[i] = varIdx
        if varIdxInt < heapPosition.count {
            heapPosition[varIdxInt] = i
        }
    }

    private func siftDown(_ pos: Int) {
        guard pos >= 0 && pos < heap.count else { return }
        var i = pos
        let varIdx = heap[i]
        let varIdxInt = Int(varIdx)
        guard varIdxInt >= 0 && varIdxInt < activities.count else { return }
        let activity = activities[varIdxInt]

        while true {
            let left = 2 * i + 1
            let right = 2 * i + 2

            var largest = i
            var largestActivity = activity

            if left < heap.count {
                let leftVarIdx = Int(heap[left])
                if leftVarIdx >= 0 && leftVarIdx < activities.count && activities[leftVarIdx] > largestActivity {
                    largest = left
                    largestActivity = activities[leftVarIdx]
                }
            }

            if right < heap.count {
                let rightVarIdx = Int(heap[right])
                if rightVarIdx >= 0 && rightVarIdx < activities.count && activities[rightVarIdx] > largestActivity {
                    largest = right
                    largestActivity = activities[rightVarIdx]
                }
            }

            if largest == i {
                break
            }

            heap[i] = heap[largest]
            let swappedVarIdx = Int(heap[i])
            if swappedVarIdx >= 0 && swappedVarIdx < heapPosition.count {
                heapPosition[swappedVarIdx] = i
            }
            i = largest
        }

        heap[i] = varIdx
        if varIdxInt < heapPosition.count {
            heapPosition[varIdxInt] = i
        }
    }

    private func swap(_ i: Int, _ j: Int) {
        let tmp = heap[i]
        heap[i] = heap[j]
        heap[j] = tmp
        heapPosition[Int(heap[i])] = i
        heapPosition[Int(heap[j])] = j
    }
}

// MARK: - Luby Restart Sequence

/// Luby restart sequence for CDCL restarts
/// Produces: 1, 1, 2, 1, 1, 2, 4, 1, 1, 2, 1, 1, 2, 4, 8, ...
public struct LubySequence: Sendable {
    /// Base unit for restart interval
    public let baseInterval: Int

    /// Current position in sequence
    private var position: Int = 0

    public init(baseInterval: Int = 100) {
        self.baseInterval = baseInterval
    }

    /// Get next restart interval
    public mutating func next() -> Int {
        position += 1
        return luby(position) * baseInterval
    }

    /// Compute Luby number at position k (1-indexed)
    /// Sequence: 1, 1, 2, 1, 1, 2, 4, 1, 1, 2, 1, 1, 2, 4, 8, ...
    private func luby(_ k: Int) -> Int {
        var x = k
        var size = 1
        var seq = 0

        // Maximum safe sequence value to prevent overflow (2^30 is safe on all platforms)
        let maxSeq = 30

        // Find the smallest power of 2 - 1 that is >= x
        while size < x {
            seq += 1
            // Check for potential overflow: 2 * size + 1 would overflow if size > Int.max / 2 - 1
            if seq > maxSeq || size > Int.max / 2 - 1 {
                // Return a large but safe value for very large positions
                return 1 << min(seq, maxSeq)
            }
            size = 2 * size + 1
        }

        // Now work backwards
        while size != x {
            size = size / 2
            seq -= 1
            if size < x {
                x -= size
            }
        }

        return 1 << seq
    }

    /// Reset the sequence
    public mutating func reset() {
        position = 0
    }
}
