import SwiftUI
import AppKit

// MARK: - Editor View

/// A SwiftUI wrapper around NSTextView with syntax highlighting
public struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var diagnostics: [Diagnostic]
    var theme: AppKitSyntaxTheme
    var onTextChange: ((String) -> Void)?
    var scrollToLocation: SourceSpan?

    public init(
        text: Binding<String>,
        diagnostics: [Diagnostic] = [],
        theme: AppKitSyntaxTheme = .default,
        onTextChange: ((String) -> Void)? = nil,
        scrollToLocation: SourceSpan? = nil
    ) {
        self._text = text
        self.diagnostics = diagnostics
        self.theme = theme
        self.onTextChange = onTextChange
        self.scrollToLocation = scrollToLocation
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = AlloyScrollView()
        let textView = AlloyTextView()

        // Configure text view
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.backgroundColor = theme.backgroundColor
        textView.font = theme.font
        textView.textColor = theme.textColor
        textView.insertionPointColor = .labelColor

        // Disable smart text features
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        // Configure text container
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        // Set text container insets
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // Enable line numbers
        textView.showLineNumbers = true

        // Configure scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = theme.backgroundColor

        // Store reference for line number view
        scrollView.alloyTextView = textView

        // Apply initial highlighting
        context.coordinator.applyHighlighting(to: textView, text: text)

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AlloyTextView else { return }

        // Only update if text changed externally
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            context.coordinator.applyHighlighting(to: textView, text: text)
            // Restore selection if valid
            if let firstRange = selectedRanges.first as? NSRange,
               firstRange.location + firstRange.length <= text.count {
                textView.setSelectedRange(firstRange)
            }
        }

        // Update diagnostics overlay
        textView.diagnosticSpans = diagnostics.map { ($0.span, $0.severity) }
        textView.needsDisplay = true

        // Handle scroll to location
        if let location = scrollToLocation {
            textView.scrollToLocation(location)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        let highlighter: AppKitSyntaxHighlighter
        private var isUpdating = false

        init(_ parent: EditorView) {
            self.parent = parent
            self.highlighter = AppKitSyntaxHighlighter(theme: parent.theme)
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }

            let newText = textView.string
            parent.text = newText
            parent.onTextChange?(newText)

            // Re-apply highlighting
            applyHighlighting(to: textView, text: newText)
        }

        func applyHighlighting(to textView: NSTextView, text: String) {
            isUpdating = true
            defer { isUpdating = false }

            let selectedRanges = textView.selectedRanges
            let attributed = highlighter.highlight(text)

            // Use textStorage for proper NSTextView updates
            if let textStorage = textView.textStorage {
                textStorage.beginEditing()
                textStorage.setAttributedString(attributed)
                textStorage.endEditing()
            }

            // Restore selection
            if let firstRange = selectedRanges.first as? NSRange,
               firstRange.location + firstRange.length <= text.count {
                textView.setSelectedRange(firstRange)
            }
        }
    }
}

// MARK: - Alloy Scroll View

/// Custom NSScrollView that adds a line number ruler
class AlloyScrollView: NSScrollView {
    weak var alloyTextView: AlloyTextView?
    private var lineNumberView: LineNumberRulerView?

    override func tile() {
        super.tile()

        if let textView = alloyTextView, textView.showLineNumbers {
            if lineNumberView == nil {
                let ruler = LineNumberRulerView(textView: textView)
                lineNumberView = ruler
                self.verticalRulerView = ruler
                self.hasVerticalRuler = true
                self.rulersVisible = true
            }
            lineNumberView?.needsDisplay = true
        }
    }
}

// MARK: - Alloy Text View

/// Custom NSTextView with line numbers and error highlighting
class AlloyTextView: NSTextView {
    var showLineNumbers: Bool = false
    var diagnosticSpans: [(SourceSpan, DiagnosticSeverity)] = []

    private let lineNumberWidth: CGFloat = 44

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDiagnosticUnderlines(dirtyRect)
    }

    private func drawDiagnosticUnderlines(_ rect: NSRect) {
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer,
              let ctx = NSGraphicsContext.current?.cgContext else {
            return
        }

        let text = self.string

        for (span, severity) in diagnosticSpans {
            // Convert source location to text range
            let lineStart = lineStartOffset(for: span.start.line)
            let charOffset = lineStart + span.start.column - 1

            guard charOffset >= 0 && charOffset < text.count else { continue }

            // Get the glyph range for this location
            let length = min(max(span.end.offset - span.start.offset, 1), text.count - charOffset)
            let range = NSRange(location: charOffset, length: length)
            var glyphRange = NSRange()
            layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: &glyphRange)

            // Get bounding rect
            let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let adjustedRect = boundingRect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)

            // Draw underline
            let color: NSColor
            switch severity {
            case .error:
                color = .systemRed
            case .warning:
                color = .systemOrange
            case .info, .hint:
                color = .systemBlue
            }

            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(2)

            // Draw wavy underline
            let y = adjustedRect.maxY
            let startX = adjustedRect.minX
            let endX = adjustedRect.maxX

            ctx.move(to: CGPoint(x: startX, y: y))
            var x = startX
            var up = true
            while x < endX {
                let nextX = min(x + 3, endX)
                let nextY = up ? y - 2 : y + 2
                ctx.addLine(to: CGPoint(x: nextX, y: nextY))
                x = nextX
                up.toggle()
            }
            ctx.strokePath()
        }
    }

    private func lineStartOffset(for line: Int) -> Int {
        var offset = 0
        var currentLine = 1
        let text = self.string

        for char in text {
            if currentLine == line {
                return offset
            }
            if char == "\n" {
                currentLine += 1
            }
            offset += 1
        }

        return offset
    }

    /// Scroll the text view to show a specific source location
    func scrollToLocation(_ span: SourceSpan) {
        let text = self.string
        let lineStart = lineStartOffset(for: span.start.line)
        let charOffset = lineStart + span.start.column - 1

        guard charOffset >= 0 && charOffset < text.count,
              let layoutManager = self.layoutManager,
              let textContainer = self.textContainer else { return }

        // Calculate the length to highlight
        let length = max(span.end.offset - span.start.offset, 1)
        let safeLength = min(length, text.count - charOffset)
        let range = NSRange(location: charOffset, length: safeLength)

        // Get the bounding rect for this range
        var glyphRange = NSRange()
        layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: &glyphRange)
        let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let adjustedRect = boundingRect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)

        // Add some padding around the target
        let targetRect = adjustedRect.insetBy(dx: -20, dy: -50)

        // Scroll to make the target visible
        scrollToVisible(targetRect)

        // Select the range to highlight it
        setSelectedRange(range)

        // Flash the selection briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setSelectedRange(NSRange(location: charOffset, length: 0))
        }
    }
}

// MARK: - Line Number Ruler View

/// View that displays line numbers alongside the text
class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    private let lineNumberWidth: CGFloat = 44

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = lineNumberWidth
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        // Draw background
        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let text = textView.string
        let visibleRect = scrollView?.contentView.bounds ?? rect

        // Calculate visible range
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Find line numbers in visible range
        var lineNumber = 1

        // Count lines before visible range
        let textBeforeVisible = text.prefix(characterRange.location)
        lineNumber += textBeforeVisible.filter { $0 == "\n" }.count

        // Draw visible line numbers
        var currentLine = lineNumber
        var lastDrawnLine = -1
        let containerInset = textView.textContainerInset

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] (fragmentRect, usedRect, _, glyphRange, _) in
            guard let self = self else { return }

            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            if currentLine != lastDrawnLine {
                let lineStr = "\(currentLine)"
                let size = lineStr.size(withAttributes: attributes)
                let y = fragmentRect.origin.y + containerInset.height - visibleRect.origin.y + self.convert(NSPoint.zero, from: textView).y
                let x = self.ruleThickness - size.width - 8

                if y >= -20 && y <= rect.height + 20 {
                    lineStr.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
                }
                lastDrawnLine = currentLine
            }

            // Count newlines in this range
            let startIdx = text.index(text.startIndex, offsetBy: max(0, charRange.location))
            let endOffset = min(charRange.location + charRange.length, text.count)
            let endIdx = text.index(text.startIndex, offsetBy: endOffset)
            let substring = text[startIdx..<endIdx]
            currentLine += substring.filter { $0 == "\n" }.count
        }
    }

    override var isFlipped: Bool {
        return true
    }
}

// MARK: - Preview

struct EditorView_Previews: PreviewProvider {
    static var previews: some View {
        EditorView(
            text: .constant("""
            // Sample Alloy model
            sig Person {
                friends: set Person
            }

            fact NoSelfFriend {
                no p: Person | p in p.friends
            }

            run {} for 3
            """),
            diagnostics: []
        )
    }
}
