import Foundation

// MARK: - Constraint Helpers

/// Centralized utilities for common constraint patterns used in formula encoding.
/// Consolidates at-most-one and exactly-one constraint generation that was previously duplicated.
public enum ConstraintHelpers {

    // MARK: - Cardinality Constraints

    /// Generate an at-most-one constraint over a list of formulas.
    /// At most one formula can be true: for each pair (i,j), not both can be true.
    /// - Parameter formulas: The formulas to constrain
    /// - Returns: A formula that is true iff at most one input formula is true
    public static func atMostOne(_ formulas: [BooleanFormula]) -> BooleanFormula {
        let constraints = atMostOneConstraints(formulas)
        return .conjunction(constraints)
    }

    /// Generate an exactly-one constraint over a list of formulas.
    /// Exactly one formula must be true: at least one is true AND at most one is true.
    /// - Parameter formulas: The formulas to constrain
    /// - Returns: A formula that is true iff exactly one input formula is true
    public static func exactlyOne(_ formulas: [BooleanFormula]) -> BooleanFormula {
        // At least one
        let atLeastOne = BooleanFormula.disjunction(formulas)

        // At most one
        let atMostOneConstraints = atMostOneConstraints(formulas)

        return atLeastOne.and(.conjunction(atMostOneConstraints))
    }

    /// Generate at-least-one constraint over a list of formulas.
    /// At least one formula must be true.
    /// - Parameter formulas: The formulas to constrain
    /// - Returns: A formula that is true iff at least one input formula is true
    public static func atLeastOne(_ formulas: [BooleanFormula]) -> BooleanFormula {
        .disjunction(formulas)
    }

    // MARK: - Internal Helpers

    /// Generate the pairwise mutual exclusion constraints for at-most-one.
    /// For each pair (i,j), generates: NOT(formulas[i]) OR NOT(formulas[j])
    /// - Parameter formulas: The formulas to constrain
    /// - Returns: Array of pairwise exclusion constraints
    private static func atMostOneConstraints(_ formulas: [BooleanFormula]) -> [BooleanFormula] {
        var constraints: [BooleanFormula] = []
        for i in 0..<formulas.count {
            for j in (i+1)..<formulas.count {
                constraints.append(.disjunction([formulas[i].negated, formulas[j].negated]))
            }
        }
        return constraints
    }
}
