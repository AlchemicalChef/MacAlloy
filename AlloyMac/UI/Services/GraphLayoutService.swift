import Foundation
import SwiftUI
import AppKit

// MARK: - Graph Layout Service

/// Centralized service for graph layout computations used across InstanceView, InstanceDiffView, and GraphExporter.
/// Consolidates force-directed layout algorithm and utility functions that were previously duplicated.
public enum GraphLayoutService {

    // MARK: - Layout Constants

    /// Configuration for force-directed layout algorithm
    public struct LayoutConfig {
        /// Number of iterations for force simulation
        public var iterations: Int = UIConstants.Graph.forceIterations

        /// Repulsion force between nodes
        public var repulsionStrength: CGFloat = UIConstants.Graph.repulsionStrength

        /// Attraction force along edges
        public var attractionStrength: CGFloat = UIConstants.Graph.attractionStrength

        /// Force application damping factor
        public var damping: CGFloat = UIConstants.Graph.forceDamping

        /// Minimum distance between nodes to apply forces
        public var minDistance: CGFloat = UIConstants.Graph.minNodeDistance

        /// Padding from bounds
        public var boundaryPadding: CGFloat = UIConstants.Graph.boundaryPadding

        /// Radius multiplier for initial circular placement
        public var initialRadiusMultiplier: CGFloat = UIConstants.Graph.initialRadiusMultiplier

        public static let `default` = LayoutConfig()
    }

    // MARK: - Position Computation

    /// Compute node positions using force-directed layout
    /// - Parameters:
    ///   - instance: The Alloy instance to layout
    ///   - size: The canvas size
    ///   - config: Layout configuration (defaults to standard settings)
    /// - Returns: Dictionary mapping atom names to positions
    public static func computePositions(
        for instance: AlloyInstance,
        in size: CGSize,
        config: LayoutConfig = .default
    ) -> [String: CGPoint] {
        let atoms = collectAllAtoms(from: instance)
        let edges = collectAllEdges(from: instance)
        return computePositions(atoms: atoms, edges: edges, in: size, config: config)
    }

    /// Compute node positions using force-directed layout (lower-level API)
    /// - Parameters:
    ///   - atoms: List of atom names to position
    ///   - edges: List of edges as (from, to) tuples
    ///   - size: The canvas size
    ///   - config: Layout configuration
    /// - Returns: Dictionary mapping atom names to positions
    public static func computePositions(
        atoms: [String],
        edges: [(from: String, to: String)],
        in size: CGSize,
        config: LayoutConfig = .default
    ) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]

        guard !atoms.isEmpty else { return positions }

        // Initial placement in a circle
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * config.initialRadiusMultiplier

        for (index, atom) in atoms.enumerated() {
            let angle = 2 * .pi * Double(index) / Double(atoms.count)
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            positions[atom] = CGPoint(x: x, y: y)
        }

        // Force-directed iterations
        for _ in 0..<config.iterations {
            var forces: [String: CGVector] = [:]
            for atom in atoms {
                forces[atom] = .zero
            }

            // Repulsion between all nodes
            for i in 0..<atoms.count {
                for j in (i+1)..<atoms.count {
                    guard let p1 = positions[atoms[i]],
                          let p2 = positions[atoms[j]] else { continue }

                    let dx = p2.x - p1.x
                    let dy = p2.y - p1.y
                    let dist = sqrt(dx * dx + dy * dy)

                    if dist > config.minDistance {
                        let force = config.repulsionStrength / (dist * dist)
                        let fx = (dx / dist) * force
                        let fy = (dy / dist) * force

                        forces[atoms[i]]?.dx -= fx
                        forces[atoms[i]]?.dy -= fy
                        forces[atoms[j]]?.dx += fx
                        forces[atoms[j]]?.dy += fy
                    }
                }
            }

            // Attraction along edges
            for edge in edges {
                guard let p1 = positions[edge.from],
                      let p2 = positions[edge.to] else { continue }

                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                let dist = sqrt(dx * dx + dy * dy)

                if dist > config.minDistance {
                    let force = dist * config.attractionStrength
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force

                    forces[edge.from]?.dx += fx
                    forces[edge.from]?.dy += fy
                    forces[edge.to]?.dx -= fx
                    forces[edge.to]?.dy -= fy
                }
            }

            // Apply forces with damping and bounds
            for atom in atoms {
                guard var pos = positions[atom],
                      let force = forces[atom] else { continue }

                pos.x += force.dx * config.damping
                pos.y += force.dy * config.damping

                // Keep in bounds
                pos.x = max(config.boundaryPadding, min(size.width - config.boundaryPadding, pos.x))
                pos.y = max(config.boundaryPadding, min(size.height - config.boundaryPadding, pos.y))

                positions[atom] = pos
            }
        }

        return positions
    }

    // MARK: - Data Collection

    /// Collect all unique atom names from an instance
    /// - Parameter instance: The Alloy instance
    /// - Returns: Sorted array of atom names
    public static func collectAllAtoms(from instance: AlloyInstance) -> [String] {
        var atoms: Set<String> = []
        for tuples in instance.signatures.values {
            for tuple in tuples.sortedTuples {
                atoms.insert(tuple.first.name)
            }
        }
        return Array(atoms).sorted()
    }

    /// Collect all edges from an instance's fields
    /// - Parameter instance: The Alloy instance
    /// - Returns: Array of (from, to) tuples representing edges
    public static func collectAllEdges(from instance: AlloyInstance) -> [(from: String, to: String)] {
        var edges: [(from: String, to: String)] = []
        for tuples in instance.fields.values {
            for tuple in tuples.sortedTuples where tuple.arity == 2 {
                edges.append((from: tuple.first.name, to: tuple.last.name))
            }
        }
        return edges
    }

    /// Count total unique atoms in an instance
    /// - Parameter instance: The Alloy instance
    /// - Returns: Number of unique atoms
    public static func atomCount(in instance: AlloyInstance) -> Int {
        var atoms: Set<String> = []
        for tuples in instance.signatures.values {
            for tuple in tuples.sortedTuples {
                atoms.insert(tuple.first.name)
            }
        }
        return atoms.count
    }

    // MARK: - Color Generation

    /// Generate a consistent color for a signature based on its name
    /// - Parameter name: The signature name
    /// - Returns: A SwiftUI Color
    public static func colorForSignature(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.7)
    }

    /// Generate a consistent NSColor for a signature based on its name
    /// - Parameter name: The signature name
    /// - Returns: An NSColor
    public static func nsColorForSignature(_ name: String) -> NSColor {
        let hash = abs(name.hashValue)
        let hue = CGFloat(hash % 360) / 360.0
        return NSColor(hue: hue, saturation: 0.6, brightness: 0.7, alpha: 1.0)
    }
}
