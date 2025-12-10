import AppKit

// MARK: - Squiggle Layout Manager

/// Custom NSLayoutManager that draws wavy underlines for diagnostic ranges
public class SquiggleLayoutManager: NSLayoutManager {

    /// Represents a diagnostic range with its color
    struct DiagnosticRange {
        let range: NSRange
        let color: NSColor
    }

    /// Active diagnostic ranges to display as squiggles (thread-safe access via lock)
    private var _diagnosticRanges: [DiagnosticRange] = []
    private let lock = NSLock()

    /// Wave parameters
    private let waveHeight: CGFloat = 2.0
    private let waveLength: CGFloat = 4.0

    // MARK: - Public API

    /// Update the diagnostic ranges to display
    /// - Parameter ranges: Array of (NSRange, NSColor) tuples
    public func setDiagnosticRanges(_ ranges: [(NSRange, NSColor)]) {
        let newRanges = ranges.map { DiagnosticRange(range: $0.0, color: $0.1) }

        // Hold lock while updating, then invalidate after release
        lock.lock()
        _diagnosticRanges = newRanges
        lock.unlock()

        // Invalidate display for all new ranges to trigger redraw
        for range in newRanges {
            invalidateDisplay(forCharacterRange: range.range)
        }
    }

    /// Clear all diagnostic ranges
    public func clearDiagnostics() {
        // Get old ranges and clear under lock
        lock.lock()
        let oldRanges = _diagnosticRanges
        _diagnosticRanges = []
        lock.unlock()

        // Invalidate display for old ranges
        for range in oldRanges {
            invalidateDisplay(forCharacterRange: range.range)
        }
    }

    // MARK: - Drawing

    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        // Draw squiggles for diagnostic ranges that overlap with visible glyphs
        guard let textContainer = textContainers.first else { return }

        // Take a snapshot of ranges under lock to iterate safely
        lock.lock()
        let ranges = _diagnosticRanges
        lock.unlock()

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        for diagnostic in ranges {
            // Check if this diagnostic overlaps with the visible range
            let intersection = NSIntersectionRange(diagnostic.range, charRange)
            if intersection.length > 0 {
                drawSquiggle(for: intersection, color: diagnostic.color, in: textContainer, at: origin)
            }
        }
    }

    /// Draw a wavy underline for the given character range
    private func drawSquiggle(for charRange: NSRange, color: NSColor, in textContainer: NSTextContainer, at origin: NSPoint) {
        let glyphRange = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)

        // Enumerate line fragments to handle multi-line ranges
        enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] (rect, usedRect, container, lineGlyphRange, stop) in
            guard let self = self else { return }

            // Find the intersection of this line's glyph range with our target range
            let intersection = NSIntersectionRange(lineGlyphRange, glyphRange)
            guard intersection.length > 0 else { return }

            // Get the bounding rect for the glyphs we want to underline
            let boundingRect = self.boundingRect(forGlyphRange: intersection, in: container)

            // Calculate squiggle position (at baseline, below text)
            let baselineY = origin.y + rect.maxY - 2  // Just below the text
            let startX = origin.x + boundingRect.minX
            let endX = origin.x + boundingRect.maxX

            // Draw the wavy line
            self.drawWavyLine(from: startX, to: endX, y: baselineY, color: color)
        }
    }

    /// Draw a wavy line from startX to endX at y position
    private func drawWavyLine(from startX: CGFloat, to endX: CGFloat, y: CGFloat, color: NSColor) {
        guard endX > startX else { return }

        let path = NSBezierPath()
        path.lineWidth = 1.0

        // Start at baseline
        path.move(to: NSPoint(x: startX, y: y))

        var x = startX
        var phase: CGFloat = 0

        // Draw wave segments using sine-wave style peaks and troughs
        while x < endX {
            let segmentEnd = min(x + waveLength, endX)
            let halfWave = waveLength / 2

            // First half: go up (or down based on phase)
            let mid = min(x + halfWave, endX)
            let peakY = y + (phase == 0 ? -waveHeight : waveHeight)

            if mid > x {
                // Quadratic curve to peak
                path.curve(to: NSPoint(x: mid, y: peakY),
                           controlPoint1: NSPoint(x: x + halfWave * 0.5, y: peakY),
                           controlPoint2: NSPoint(x: mid - halfWave * 0.25, y: peakY))
            }

            // Second half: return to baseline
            if segmentEnd > mid {
                path.curve(to: NSPoint(x: segmentEnd, y: y),
                           controlPoint1: NSPoint(x: mid + halfWave * 0.25, y: peakY),
                           controlPoint2: NSPoint(x: segmentEnd - halfWave * 0.5, y: y))
            }

            x = segmentEnd
            phase = phase == 0 ? 1 : 0
        }

        color.setStroke()
        path.stroke()
    }
}

// MARK: - Diagnostic Severity Extension

extension SquiggleLayoutManager {
    /// Get color for diagnostic severity
    public static func color(for severity: DiagnosticSeverity) -> NSColor {
        switch severity {
        case .error:
            return .systemRed
        case .warning:
            return .systemOrange
        case .info, .hint:
            return .systemBlue
        }
    }
}
