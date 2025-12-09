import Foundation

// MARK: - Alloy Instance

/// A satisfying instance of an Alloy model
public struct AlloyInstance: Sendable {
    /// The universe of atoms
    public let universe: Universe

    /// Signature assignments (which atoms belong to which signature)
    public let signatures: [String: TupleSet]

    /// Field assignments (relation values)
    public let fields: [String: TupleSet]

    /// For temporal models: trace of field values over time
    public let trace: AlloyTrace?

    /// Whether this is a temporal instance
    public var isTemporal: Bool { trace != nil }

    /// Create a non-temporal instance
    public init(universe: Universe, signatures: [String: TupleSet], fields: [String: TupleSet]) {
        self.universe = universe
        self.signatures = signatures
        self.fields = fields
        self.trace = nil
    }

    /// Create a temporal instance
    public init(universe: Universe, signatures: [String: TupleSet], trace: AlloyTrace) {
        self.universe = universe
        self.signatures = signatures
        self.fields = [:]  // Fields are in trace
        self.trace = trace
    }

    /// Get a signature's atoms
    public subscript(sig sigName: String) -> TupleSet? {
        signatures[sigName]
    }

    /// Get a field's value (for non-temporal instance)
    public subscript(field fieldName: String) -> TupleSet? {
        fields[fieldName]
    }

    /// Get a field's value at a specific state (for temporal instance)
    public func field(_ fieldName: String, at state: Int) -> TupleSet? {
        trace?.fields[fieldName]?[state]
    }
}

// MARK: - Alloy Trace

/// A trace of states for temporal instances
public struct AlloyTrace: Sendable {
    /// Length of the trace
    public let length: Int

    /// Loop-back state (for lasso traces)
    public let loopState: Int?

    /// Field values at each state
    public let fields: [String: [TupleSet]]

    /// Create a trace
    public init(length: Int, loopState: Int?, fields: [String: [TupleSet]]) {
        self.length = length
        self.loopState = loopState
        self.fields = fields
    }

    /// Whether this trace forms a lasso (loops back)
    public var isLasso: Bool { loopState != nil }
}

// MARK: - Instance Extractor

/// Extracts Alloy instances from SAT solutions
public struct InstanceExtractor {
    /// Extract an instance from a translation context and SAT solution
    public static func extract(context: TranslationContext, solution: [Bool]) -> AlloyInstance {
        let signatures = extractSignatures(context: context, solution: solution)

        if let trace = context.trace {
            // Temporal instance
            let alloyTrace = extractTrace(context: context, solution: solution, trace: trace)
            return AlloyInstance(universe: context.universe, signatures: signatures, trace: alloyTrace)
        } else {
            // Non-temporal instance
            let fields = extractFields(context: context, solution: solution)
            return AlloyInstance(universe: context.universe, signatures: signatures, fields: fields)
        }
    }

    /// Extract signature assignments
    private static func extractSignatures(context: TranslationContext, solution: [Bool]) -> [String: TupleSet] {
        var result: [String: TupleSet] = [:]

        for (sigName, matrix) in context.sigMatrices {
            result[sigName] = extractTupleSet(from: matrix, solution: solution)
        }

        return result
    }

    /// Extract field assignments (non-temporal)
    private static func extractFields(context: TranslationContext, solution: [Bool]) -> [String: TupleSet] {
        var result: [String: TupleSet] = [:]

        for (fieldName, matrix) in context.fieldMatrices {
            result[fieldName] = extractTupleSet(from: matrix, solution: solution)
        }

        return result
    }

    /// Extract a trace for temporal instance
    private static func extractTrace(
        context: TranslationContext,
        solution: [Bool],
        trace: Trace
    ) -> AlloyTrace {
        var fields: [String: [TupleSet]] = [:]

        // Extract non-variable fields (same at all states)
        for (fieldName, matrix) in context.fieldMatrices {
            let tupleSet = extractTupleSet(from: matrix, solution: solution)
            fields[fieldName] = Array(repeating: tupleSet, count: trace.length)
        }

        // Extract variable fields (per-state)
        for (fieldName, tempRel) in context.temporalRelations {
            var stateValues: [TupleSet] = []
            for state in 0..<trace.length {
                let matrix = tempRel.matrix(at: state)
                stateValues.append(extractTupleSet(from: matrix, solution: solution))
            }
            fields[fieldName] = stateValues
        }

        // Extract loop state
        let loopState = trace.extractLoopState(from: solution)

        return AlloyTrace(length: trace.length, loopState: loopState, fields: fields)
    }

    /// Extract a tuple set from a boolean matrix
    private static func extractTupleSet(from matrix: BooleanMatrix, solution: [Bool]) -> TupleSet {
        var tuples: [AtomTuple] = []

        for (i, tuple) in matrix.tuples.enumerated() {
            let value = matrix[i]
            let isTrue: Bool

            switch value {
            case .constant(let b):
                isTrue = b
            case .variable(let v):
                let idx = Int(abs(v))
                let varValue = idx < solution.count ? solution[idx] : false
                isTrue = v > 0 ? varValue : !varValue
            }

            if isTrue {
                tuples.append(tuple)
            }
        }

        return TupleSet(tuples)
    }
}

// MARK: - Instance Formatting

extension AlloyInstance: CustomStringConvertible {
    public var description: String {
        var result = "AlloyInstance {\n"

        // Signatures
        result += "  Signatures:\n"
        for (name, tuples) in signatures.sorted(by: { $0.key < $1.key }) {
            if !tuples.isEmpty {
                result += "    \(name) = \(tuples)\n"
            }
        }

        if let trace = trace {
            // Temporal fields
            result += "  Trace (length=\(trace.length)"
            if let loop = trace.loopState {
                result += ", loop->state\(loop)"
            }
            result += "):\n"

            for (name, values) in trace.fields.sorted(by: { $0.key < $1.key }) {
                result += "    \(name):\n"
                for (state, tupleSet) in values.enumerated() {
                    let loopMarker = (trace.loopState == state) ? " <-loop" : ""
                    result += "      [\(state)] \(tupleSet)\(loopMarker)\n"
                }
            }
        } else {
            // Non-temporal fields
            result += "  Fields:\n"
            for (name, tuples) in fields.sorted(by: { $0.key < $1.key }) {
                result += "    \(name) = \(tuples)\n"
            }
        }

        result += "}"
        return result
    }
}

// MARK: - Instance Visualization Helpers

extension AlloyInstance {
    /// Get all atoms in a signature (as strings)
    public func atomNames(in sigName: String) -> [String] {
        guard let tuples = signatures[sigName] else { return [] }
        return tuples.sortedTuples.map { $0.first.name }
    }

    /// Get all edges in a field (as pairs of atom names)
    public func edges(in fieldName: String) -> [(from: String, to: String)] {
        guard let tuples = fields[fieldName] else { return [] }
        return tuples.sortedTuples.compactMap { tuple in
            guard tuple.arity == 2 else { return nil }
            return (from: tuple.first.name, to: tuple.last.name)
        }
    }

    /// Get field edges at a specific state (for temporal instances)
    public func edges(in fieldName: String, at state: Int) -> [(from: String, to: String)] {
        guard let tuples = trace?.fields[fieldName]?[state] else { return [] }
        return tuples.sortedTuples.compactMap { tuple in
            guard tuple.arity == 2 else { return nil }
            return (from: tuple.first.name, to: tuple.last.name)
        }
    }
}

// MARK: - Solution Result

/// Result of solving an Alloy model
public enum SolveResult: Sendable {
    /// Satisfiable - instance found
    case sat(AlloyInstance)

    /// Unsatisfiable - no instance exists
    case unsat

    /// Unknown (timeout or error)
    case unknown(String)

    /// Whether a solution was found
    public var isSat: Bool {
        if case .sat = self { return true }
        return false
    }

    /// Get the instance if satisfiable
    public var instance: AlloyInstance? {
        if case .sat(let inst) = self { return inst }
        return nil
    }
}
