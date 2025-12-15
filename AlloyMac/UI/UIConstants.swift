import Foundation
import SwiftUI

// MARK: - UI Constants

/// Centralized constants for UI layout, timing, and appearance.
/// Eliminates magic numbers scattered throughout the UI codebase.
public enum UIConstants {

    // MARK: - Graph Layout

    /// Constants for graph visualization (InstanceView, InstanceDiffView, GraphExporter)
    public enum Graph {
        /// Radius of atom nodes in graph views
        public static let nodeRadius: CGFloat = 25

        /// Number of iterations for force-directed layout simulation
        public static let forceIterations: Int = 50

        /// Repulsion force strength between nodes
        public static let repulsionStrength: CGFloat = 5000

        /// Attraction force strength along edges
        public static let attractionStrength: CGFloat = 0.01

        /// Force application damping factor
        public static let forceDamping: CGFloat = 0.1

        /// Minimum distance between nodes for force calculation
        public static let minNodeDistance: CGFloat = 1

        /// Padding from canvas boundaries
        public static let boundaryPadding: CGFloat = 50

        /// Initial radius multiplier for circular node placement
        public static let initialRadiusMultiplier: CGFloat = 0.35

        /// Arrow head length for edges
        public static let arrowLength: CGFloat = 10

        /// Arrow head angle (radians)
        public static let arrowAngle: CGFloat = .pi / 6

        /// Highlighted edge line width
        public static let highlightedLineWidth: CGFloat = 2.5

        /// Normal edge line width
        public static let normalLineWidth: CGFloat = 1.5

        /// Selection glow outer inset
        public static let selectionGlowOuterInset: CGFloat = -6

        /// Selection glow inner inset
        public static let selectionGlowInnerInset: CGFloat = -3

        /// Selection glow line width
        public static let selectionGlowLineWidth: CGFloat = 3

        /// Dimmed element opacity
        public static let dimmedOpacity: Double = 0.3
    }

    // MARK: - Editor Layout

    /// Constants for the code editor (EditorView)
    public enum Editor {
        /// Height of each line in the editor
        public static let lineHeight: CGFloat = 17

        /// Font size for line numbers
        public static let lineNumberFontSize: CGFloat = 12

        /// Width of the line number gutter
        public static let gutterWidth: CGFloat = 40

        /// Top padding for gutter content
        public static let gutterTopPadding: CGFloat = 8

        /// Trailing padding for line numbers
        public static let gutterTrailingPadding: CGFloat = 6

        /// Horizontal padding for scroll target rect
        public static let scrollPaddingHorizontal: CGFloat = 20

        /// Vertical padding for scroll target rect
        public static let scrollPaddingVertical: CGFloat = 50

        /// Delay before executing scroll (seconds)
        public static let scrollDelay: TimeInterval = 0.5

        /// Hover tooltip debounce delay (seconds)
        public static let hoverDebounceDelay: TimeInterval = 0.3

        /// Tooltip font size
        public static let tooltipFontSize: CGFloat = 11

        /// Font size for type annotations in tooltips
        public static let tooltipTypeFontSize: CGFloat = 10
    }

    // MARK: - Animation & Timing

    /// Constants for animations and timing
    public enum Animation {
        /// Interval between trace playback frames (seconds)
        public static let playbackInterval: TimeInterval = 1.0

        /// Playback interval in nanoseconds for Task.sleep
        public static let playbackIntervalNanoseconds: UInt64 = 1_000_000_000
    }

    // MARK: - Report Layout

    /// Constants for the report view
    public enum Report {
        /// Number of columns in stat grid
        public static let gridColumnCount: Int = 4

        /// Grid item spacing
        public static let gridSpacing: CGFloat = 12

        /// Default row width for table cells
        public static let tableRowWidth: CGFloat = 50

        /// Width for table column headers
        public static let tableColumnWidth: CGFloat = 150

        /// Maximum items to show in truncated lists
        public static let maxPreviewItems: Int = 20

        /// Maximum items for medium lists
        public static let maxMediumPreviewItems: Int = 30
    }

    // MARK: - Panel Layout

    /// Constants for panels and sidebars
    public enum Panel {
        /// Default filter panel width
        public static let filterPanelWidth: CGFloat = 200

        /// References panel height
        public static let referencesPanelHeight: CGFloat = 150

        /// References panel font size
        public static let referencesFontSize: CGFloat = 11

        /// Diff summary panel height
        public static let diffPanelHeight: CGFloat = 70

        /// Legend offset from right edge
        public static let legendOffsetFromRight: CGFloat = 150

        /// Instance picker width
        public static let instancePickerWidth: CGFloat = 180
    }

    // MARK: - Colors & Opacity

    /// Constants for colors and opacity values
    public enum Appearance {
        /// Opacity for secondary elements
        public static let secondaryOpacity: Double = 0.3

        /// Opacity for tertiary/dimmed elements
        public static let tertiaryOpacity: Double = 0.2

        /// Badge/pill horizontal padding
        public static let badgePaddingH: CGFloat = 6

        /// Badge/pill vertical padding
        public static let badgePaddingV: CGFloat = 2

        /// Standard corner radius
        public static let cornerRadius: CGFloat = 8

        /// Small corner radius for badges
        public static let smallCornerRadius: CGFloat = 4

        /// Badge corner radius
        public static let badgeCornerRadius: CGFloat = 3
    }

    // MARK: - Icons & Symbols

    /// Standard icon sizes
    public enum Icons {
        /// Small icon frame size
        public static let smallFrame: CGFloat = 10

        /// Medium icon frame size
        public static let mediumFrame: CGFloat = 12

        /// Large icon frame size
        public static let largeFrame: CGFloat = 16

        /// Extra large icon font size (for empty states)
        public static let emptyStateFontSize: CGFloat = 64
    }
}
