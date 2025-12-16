import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Editor View (with line numbers)

#if os(macOS)
/// Editor view with line number gutter (macOS)
public struct EditorView: View {
    @Binding var text: String
    var diagnostics: [Diagnostic]
    var theme: AppKitSyntaxTheme
    var onTextChange: ((String) -> Void)?
    var scrollToLocation: SourceSpan?
    var symbolTable: SymbolTable?
    var onGoToDefinition: ((SourceSpan) -> Void)?
    var onFindReferences: ((String, [Reference]) -> Void)?
    var onRenameSymbol: ((String, [Reference]) -> Void)?

    @State private var scrollOffset: CGFloat = 0

    public init(
        text: Binding<String>,
        diagnostics: [Diagnostic] = [],
        theme: AppKitSyntaxTheme = .default,
        onTextChange: ((String) -> Void)? = nil,
        scrollToLocation: SourceSpan? = nil,
        symbolTable: SymbolTable? = nil,
        onGoToDefinition: ((SourceSpan) -> Void)? = nil,
        onFindReferences: ((String, [Reference]) -> Void)? = nil,
        onRenameSymbol: ((String, [Reference]) -> Void)? = nil
    ) {
        self._text = text
        self.diagnostics = diagnostics
        self.theme = theme
        self.onTextChange = onTextChange
        self.scrollToLocation = scrollToLocation
        self.symbolTable = symbolTable
        self.onGoToDefinition = onGoToDefinition
        self.onFindReferences = onFindReferences
        self.onRenameSymbol = onRenameSymbol
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Line number gutter
            LineNumberGutter(text: text, scrollOffset: scrollOffset)

            // Editor
            EditorTextView(
                text: $text,
                diagnostics: diagnostics,
                theme: theme,
                onTextChange: onTextChange,
                scrollToLocation: scrollToLocation,
                symbolTable: symbolTable,
                onGoToDefinition: onGoToDefinition,
                onFindReferences: onFindReferences,
                onRenameSymbol: onRenameSymbol,
                onScrollChange: { offset in
                    scrollOffset = offset
                }
            )
        }
    }
}
#else
/// Editor view with line number gutter (iOS)
public struct EditorView: View {
    @Binding var text: String
    var diagnostics: [Diagnostic]
    var onTextChange: ((String) -> Void)?
    var scrollToLocation: SourceSpan?
    var symbolTable: SymbolTable?
    var onGoToDefinition: ((SourceSpan) -> Void)?
    var onFindReferences: ((String, [Reference]) -> Void)?
    var onRenameSymbol: ((String, [Reference]) -> Void)?

    @State private var scrollOffset: CGFloat = 0

    public init(
        text: Binding<String>,
        diagnostics: [Diagnostic] = [],
        onTextChange: ((String) -> Void)? = nil,
        scrollToLocation: SourceSpan? = nil,
        symbolTable: SymbolTable? = nil,
        onGoToDefinition: ((SourceSpan) -> Void)? = nil,
        onFindReferences: ((String, [Reference]) -> Void)? = nil,
        onRenameSymbol: ((String, [Reference]) -> Void)? = nil
    ) {
        self._text = text
        self.diagnostics = diagnostics
        self.onTextChange = onTextChange
        self.scrollToLocation = scrollToLocation
        self.symbolTable = symbolTable
        self.onGoToDefinition = onGoToDefinition
        self.onFindReferences = onFindReferences
        self.onRenameSymbol = onRenameSymbol
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Line number gutter
            LineNumberGutter(text: text, scrollOffset: scrollOffset)

            // iOS Editor using TextEditor
            iPadEditorTextView(
                text: $text,
                diagnostics: diagnostics,
                onTextChange: onTextChange,
                onScrollChange: { offset in
                    scrollOffset = offset
                }
            )
        }
    }
}
#endif

// MARK: - Line Number Gutter

/// SwiftUI view showing line numbers that syncs with editor scroll
struct LineNumberGutter: View {
    let text: String
    let scrollOffset: CGFloat

    private var lineCount: Int {
        max(1, text.components(separatedBy: "\n").count)
    }

    private let lineHeight: CGFloat = UIConstants.Editor.lineHeight

    var body: some View {
        GeometryReader { geometry in
            let visibleLines = Int(geometry.size.height / lineHeight) + 2
            let firstVisibleLine = max(0, Int(scrollOffset / lineHeight))

            VStack(alignment: .trailing, spacing: 0) {
                ForEach(0..<lineCount, id: \.self) { index in
                    let lineNumber = index + 1
                    Text("\(lineNumber)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(height: lineHeight)
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 6)
            .offset(y: -scrollOffset)
        }
        .frame(width: 40)
        .background(PlatformColors.controlBackground)
        .clipped()
    }
}

#if os(macOS)
// MARK: - Editor Text View (NSViewRepresentable)

/// The actual NSTextView wrapper
struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var diagnostics: [Diagnostic]
    var theme: AppKitSyntaxTheme
    var onTextChange: ((String) -> Void)?
    var scrollToLocation: SourceSpan?
    var symbolTable: SymbolTable?
    var onGoToDefinition: ((SourceSpan) -> Void)?
    var onFindReferences: ((String, [Reference]) -> Void)?
    var onRenameSymbol: ((String, [Reference]) -> Void)?
    var onScrollChange: ((CGFloat) -> Void)?

    public func makeNSView(context: Context) -> NSScrollView {
        // Create custom text system with SquiggleLayoutManager for diagnostic underlines
        let textStorage = NSTextStorage()
        let layoutManager = SquiggleLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        // Create scroll view first to get proper sizing
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = theme.backgroundColor

        // Create text container that tracks width but allows unlimited height for scrolling
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        // Create text view with our custom text system
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
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

        // Configure text view sizing for vertical scrolling
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Set document view after text view is configured
        scrollView.documentView = textView

        // Set initial text
        textView.string = text

        // Apply syntax highlighting
        context.coordinator.applyHighlighting(to: textView, text: text)

        // Store references in coordinator
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.layoutManager = layoutManager
        context.coordinator.onScrollChange = onScrollChange
        context.coordinator.symbolTable = symbolTable
        context.coordinator.onGoToDefinition = onGoToDefinition
        context.coordinator.onFindReferences = onFindReferences
        context.coordinator.onRenameSymbol = onRenameSymbol

        // Apply initial squiggles
        context.coordinator.updateSquiggles(diagnostics: diagnostics, text: text)

        // Observe scroll changes (store observer for cleanup in deinit)
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            coordinator?.handleScrollNotification()
        }

        // Setup click monitor for Cmd+Click go-to-definition
        context.coordinator.setupClickMonitor()

        // Setup context menu
        context.coordinator.setupContextMenu(for: textView)

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Clean up old observer if scroll view changed
        if context.coordinator.scrollView !== scrollView {
            if let observer = context.coordinator.scrollObserver {
                NotificationCenter.default.removeObserver(observer)
                context.coordinator.scrollObserver = nil
            }

            // Set up new observer for new scroll view
            context.coordinator.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak coordinator = context.coordinator] _ in
                coordinator?.handleScrollNotification()
            }
        }

        // Update coordinator references
        context.coordinator.symbolTable = symbolTable
        context.coordinator.onGoToDefinition = onGoToDefinition
        context.coordinator.onFindReferences = onFindReferences
        context.coordinator.onRenameSymbol = onRenameSymbol

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

        // Update squiggles when diagnostics change
        context.coordinator.updateSquiggles(diagnostics: diagnostics, text: text)

        // Handle scroll to location
        if let location = scrollToLocation {
            scrollToSourceLocation(location, in: textView)
        }
    }

    /// Scroll to a source location in the text view
    private func scrollToSourceLocation(_ span: SourceSpan, in textView: NSTextView) {
        let text = textView.string
        let lineStart = lineStartOffset(for: span.start.line, in: text)
        let charOffset = lineStart + span.start.column - 1

        guard charOffset >= 0 && charOffset < text.count,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Calculate the length to highlight
        // Ensure end is after start to avoid negative length
        guard span.end.offset >= span.start.offset else { return }
        let length = max(span.end.offset - span.start.offset, 1)
        let safeLength = min(length, text.count - charOffset)
        let range = NSRange(location: charOffset, length: safeLength)

        // Get the bounding rect for this range
        var glyphRange = NSRange()
        layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: &glyphRange)
        let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let adjustedRect = boundingRect.offsetBy(dx: textView.textContainerInset.width, dy: textView.textContainerInset.height)

        // Add some padding around the target
        let targetRect = adjustedRect.insetBy(dx: -20, dy: -50)

        // Scroll to make the target visible
        textView.scrollToVisible(targetRect)

        // Select the range to highlight it
        textView.setSelectedRange(range)

        // Flash the selection briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak textView] in
            textView?.setSelectedRange(NSRange(location: charOffset, length: 0))
        }
    }

    /// Calculate line start offset
    private func lineStartOffset(for line: Int, in text: String) -> Int {
        var offset = 0
        var currentLine = 1

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

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, NSTextViewDelegate {
        // Note: EditorTextView is a struct, so no retain cycle risk with parent
        var parentView: EditorTextView?
        let highlighter: AppKitSyntaxHighlighter
        private var isUpdating = false
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        weak var layoutManager: SquiggleLayoutManager?
        var onScrollChange: ((CGFloat) -> Void)?
        var symbolTable: SymbolTable?
        var onGoToDefinition: ((SourceSpan) -> Void)?
        var onFindReferences: ((String, [Reference]) -> Void)?
        var onRenameSymbol: ((String, [Reference]) -> Void)?

        // Hover tooltip support
        private var hoverPopover: NSPopover?
        private var hoverDebounceWorkItem: DispatchWorkItem?
        private var lastHoveredWord: String?
        private var mouseMonitor: Any?
        private var keyMonitor: Any?
        private var clickMonitor: Any?
        var scrollObserver: NSObjectProtocol?

        // Track current diagnostics to avoid redundant updates
        private var lastDiagnosticCount: Int = 0
        private var lastDiagnosticHash: Int = 0

        init(_ parent: EditorTextView) {
            self.parentView = parent
            self.highlighter = AppKitSyntaxHighlighter(theme: parent.theme)
            super.init()
            setupMouseMonitor()
            setupKeyMonitor()
        }

        deinit {
            hoverDebounceWorkItem?.cancel()
            hoverPopover?.close()
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        // MARK: - Squiggle Management

        /// Update squiggles based on diagnostics
        func updateSquiggles(diagnostics: [Diagnostic], text: String) {
            guard let layoutManager = layoutManager else { return }

            // Quick check: if count differs, definitely need update
            // If count same, compute hash of diagnostic data
            let newCount = diagnostics.count
            var hasher = Hasher()
            for d in diagnostics {
                // Combine all diagnostic fields into hash to avoid collisions
                hasher.combine(d.span.start.offset)
                hasher.combine(d.span.end.offset)
                hasher.combine(d.severity)
                hasher.combine(d.message)
                hasher.combine(d.code)
            }
            let newHash = hasher.finalize()

            if newCount == lastDiagnosticCount && newHash == lastDiagnosticHash {
                return
            }
            lastDiagnosticCount = newCount
            lastDiagnosticHash = newHash

            // Convert diagnostics to NSRanges with colors
            var ranges: [(NSRange, NSColor)] = []
            let textLength = text.count

            for diagnostic in diagnostics {
                let location = diagnostic.span.start.offset
                let length = max(1, diagnostic.span.end.offset - diagnostic.span.start.offset)

                // Ensure range is valid (use <= to allow squiggling the last character)
                guard location >= 0 && location + length <= textLength else { continue }

                let range = NSRange(location: location, length: length)
                let color = SquiggleLayoutManager.color(for: diagnostic.severity)
                ranges.append((range, color))
            }

            layoutManager.setDiagnosticRanges(ranges)
        }

        // MARK: - Context Menu

        /// Setup right-click context menu
        func setupContextMenu(for textView: NSTextView) {
            let menu = NSMenu()

            let findRefsItem = NSMenuItem(
                title: "Find All References",
                action: #selector(findAllReferencesAction(_:)),
                keyEquivalent: ""
            )
            findRefsItem.keyEquivalentModifierMask = [.command, .shift]
            findRefsItem.target = self
            menu.addItem(findRefsItem)

            let renameItem = NSMenuItem(
                title: "Rename Symbol...",
                action: #selector(renameSymbolAction(_:)),
                keyEquivalent: "r"
            )
            renameItem.keyEquivalentModifierMask = [.command]
            renameItem.target = self
            menu.addItem(renameItem)

            menu.addItem(NSMenuItem.separator())

            let goToDefItem = NSMenuItem(
                title: "Go to Definition",
                action: #selector(goToDefinitionAction(_:)),
                keyEquivalent: ""
            )
            goToDefItem.target = self
            menu.addItem(goToDefItem)

            textView.menu = menu
        }

        @objc private func findAllReferencesAction(_ sender: Any?) {
            guard let textView = textView,
                  let onFindReferences = onFindReferences else { return }

            let symbolName = getSymbolAtCursor(in: textView)
            guard !symbolName.isEmpty else { return }

            let text = textView.string
            let references = ReferenceSearchService.findReferences(symbolName: symbolName, in: text)
            onFindReferences(symbolName, references)
        }

        @objc private func renameSymbolAction(_ sender: Any?) {
            guard let textView = textView,
                  let onRenameSymbol = onRenameSymbol else { return }

            let symbolName = getSymbolAtCursor(in: textView)
            guard !symbolName.isEmpty else { return }

            let text = textView.string
            let references = ReferenceSearchService.findReferences(symbolName: symbolName, in: text)
            onRenameSymbol(symbolName, references)
        }

        @objc private func goToDefinitionAction(_ sender: Any?) {
            guard let textView = textView,
                  let symbolTable = symbolTable,
                  let onGoToDefinition = onGoToDefinition else { return }

            let symbolName = getSymbolAtCursor(in: textView)
            guard !symbolName.isEmpty else { return }

            if let symbol = lookupSymbol(named: symbolName, in: symbolTable) {
                onGoToDefinition(symbol.definedAt)
            }
        }

        /// Get the symbol name at the current cursor position
        private func getSymbolAtCursor(in textView: NSTextView) -> String {
            let selectedRange = textView.selectedRange()
            let text = textView.string
            let textLength = text.count

            // Validate selectedRange bounds - must be within text
            guard selectedRange.location < textLength else { return "" }

            // If there's a selection, use the selected text (if valid)
            if selectedRange.length > 0 {
                // Ensure selection doesn't extend beyond text and has valid length
                guard selectedRange.location >= 0,
                      selectedRange.location + selectedRange.length <= textLength else { return "" }
                let nsText = text as NSString
                return nsText.substring(with: selectedRange)
            }

            // Otherwise find the word at cursor
            let cursorPosition = selectedRange.location

            // If cursor is at end, look at previous position
            let lookupPosition = cursorPosition == textLength && cursorPosition > 0 ? cursorPosition - 1 : cursorPosition
            return findWordAt(index: lookupPosition, in: text)
        }

        private func setupMouseMonitor() {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                self?.handleHover(with: event)
                return event
            }
        }

        private func setupKeyMonitor() {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self = self else { return event }

                // Check if our text view is the first responder
                // Handle both direct first responder and field editor cases
                guard let textView = self.textView,
                      let firstResponder = textView.window?.firstResponder else {
                    return event
                }

                let isTextViewActive = firstResponder === textView ||
                    (firstResponder is NSTextView && (firstResponder as? NSTextView)?.delegate === self)

                guard isTextViewActive else { return event }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                // Cmd+Shift+F: Find All References (keyCode 3 = F key)
                if modifiers == [.command, .shift] && event.keyCode == 3 {
                    self.findAllReferencesAction(nil)
                    return nil  // Consume the event
                }

                // Cmd+R: Rename Symbol (keyCode 15 = R key)
                if modifiers == [.command] && event.keyCode == 15 {
                    self.renameSymbolAction(nil)
                    return nil  // Consume the event
                }

                return event
            }
        }

        func setupClickMonitor() {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self = self else { return event }

                // Only handle Cmd+Click
                guard event.modifierFlags.contains(.command),
                      let textView = self.textView,
                      event.window === textView.window else {
                    return event  // Let normal clicks pass through
                }

                // Check if click is within text view
                let windowPoint = event.locationInWindow
                let viewPoint = textView.convert(windowPoint, from: nil)
                guard textView.bounds.contains(viewPoint) else {
                    return event
                }

                // Handle Cmd+Click for go-to-definition
                self.handleCmdClick(at: viewPoint)
                return nil  // Consume the event
            }
        }

        private func handleCmdClick(at point: NSPoint) {
            guard let textView = textView,
                  let symbolTable = symbolTable,
                  let onGoToDefinition = onGoToDefinition,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            // Adjust for text container inset
            let adjustedPoint = NSPoint(
                x: point.x - textView.textContainerInset.width,
                y: point.y - textView.textContainerInset.height
            )

            let charIndex = layoutManager.characterIndex(
                for: adjustedPoint,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            // Find the word at this position
            let text = textView.string
            guard charIndex < text.count else { return }

            let word = findWordAt(index: charIndex, in: text)
            guard !word.isEmpty else { return }

            // Look up the symbol
            if let symbol = lookupSymbol(named: word, in: symbolTable) {
                onGoToDefinition(symbol.definedAt)
            }
        }

        /// Handle scroll notification (called from NotificationCenter observer)
        func handleScrollNotification() {
            guard let scrollView = scrollView else { return }
            let offset = scrollView.contentView.bounds.origin.y
            onScrollChange?(offset)
            // Hide popover on scroll
            hidePopover()
        }

        private func handleHover(with event: NSEvent) {
            guard let textView = textView,
                  let symbolTable = symbolTable else { return }

            // Cancel any pending hover
            hoverDebounceWorkItem?.cancel()

            // Only handle events for our window
            guard event.window === textView.window else {
                return
            }

            // Get mouse location in text view coordinates
            let windowPoint = event.locationInWindow
            let viewPoint = textView.convert(windowPoint, from: nil)

            // Check if point is within text view's visible bounds
            // The text view may be larger than the scroll view's visible area
            guard textView.bounds.contains(viewPoint) else {
                hidePopover()
                return
            }

            // Also verify mouse is over the scroll view's visible content area
            if let scrollView = textView.enclosingScrollView {
                let scrollViewPoint = scrollView.convert(windowPoint, from: nil)
                guard scrollView.bounds.contains(scrollViewPoint) else {
                    hidePopover()
                    return
                }
            }

            // Debounce hover to prevent flickering
            let workItem = DispatchWorkItem { [weak self] in
                self?.showTooltipAt(point: viewPoint, in: textView, symbolTable: symbolTable)
            }
            hoverDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }

        private func showTooltipAt(point: NSPoint, in textView: NSTextView, symbolTable: SymbolTable) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            // Adjust for text container inset
            let adjustedPoint = NSPoint(
                x: point.x - textView.textContainerInset.width,
                y: point.y - textView.textContainerInset.height
            )

            let charIndex = layoutManager.characterIndex(
                for: adjustedPoint,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            let text = textView.string
            guard charIndex < text.count else {
                hidePopover()
                return
            }

            let word = findWordAt(index: charIndex, in: text)
            guard !word.isEmpty else {
                hidePopover()
                return
            }

            // Don't re-show if same word
            if word == lastHoveredWord && hoverPopover?.isShown == true {
                return
            }
            lastHoveredWord = word

            // Look up symbol
            guard let symbol = lookupSymbol(named: word, in: symbolTable) else {
                hidePopover()
                return
            }

            // Create tooltip content
            let tooltipText = formatSymbolTooltip(symbol)

            // Get rect for popover positioning
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect = rect.offsetBy(dx: textView.textContainerInset.width, dy: textView.textContainerInset.height)

            // Show popover
            showPopover(with: tooltipText, at: rect, in: textView)
        }

        private func formatSymbolTooltip(_ symbol: any Symbol) -> NSAttributedString {
            let result = NSMutableAttributedString()

            let titleFont = NSFont.boldSystemFont(ofSize: 12)
            let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let dimColor = NSColor.secondaryLabelColor

            // Add kind label
            let kindLabel: String
            switch symbol.kind {
            case .signature: kindLabel = "sig"
            case .field: kindLabel = "field"
            case .predicate: kindLabel = "pred"
            case .function: kindLabel = "fun"
            case .assertion: kindLabel = "assert"
            case .fact: kindLabel = "fact"
            case .enumType: kindLabel = "enum"
            case .enumValue: kindLabel = "enum value"
            case .parameter: kindLabel = "param"
            case .quantifierVar: kindLabel = "var"
            case .letVar: kindLabel = "let"
            case .module: kindLabel = "module"
            }

            result.append(NSAttributedString(
                string: "\(kindLabel) ",
                attributes: [.font: titleFont, .foregroundColor: dimColor]
            ))

            result.append(NSAttributedString(
                string: symbol.name,
                attributes: [.font: titleFont, .foregroundColor: NSColor.labelColor]
            ))

            // Add type info
            if symbol.kind != .fact && symbol.kind != .assertion {
                result.append(NSAttributedString(
                    string: "\n\(symbol.type)",
                    attributes: [.font: bodyFont, .foregroundColor: dimColor]
                ))
            }

            // Add extra info for specific symbol types
            if let sig = symbol as? SigSymbol {
                var extras: [String] = []
                if sig.sigType.isAbstract { extras.append("abstract") }
                if sig.sigType.isVariable { extras.append("var") }
                if let mult = sig.sigType.multiplicity { extras.append("\(mult)") }
                if let parent = sig.parent { extras.append("extends \(parent.name)") }
                if !extras.isEmpty {
                    result.append(NSAttributedString(
                        string: "\n" + extras.joined(separator: ", "),
                        attributes: [.font: bodyFont, .foregroundColor: dimColor]
                    ))
                }
            } else if let field = symbol as? FieldSymbol {
                var extras: [String] = []
                if field.isVariable { extras.append("var") }
                if field.isDisjoint { extras.append("disj") }
                if let owner = field.owner { extras.append("in \(owner.name)") }
                if !extras.isEmpty {
                    result.append(NSAttributedString(
                        string: "\n" + extras.joined(separator: ", "),
                        attributes: [.font: bodyFont, .foregroundColor: dimColor]
                    ))
                }
            } else if let pred = symbol as? PredSymbol {
                if !pred.parameters.isEmpty {
                    let params = pred.parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
                    result.append(NSAttributedString(
                        string: "\n[\(params)]",
                        attributes: [.font: bodyFont, .foregroundColor: dimColor]
                    ))
                }
            } else if let fun = symbol as? FunSymbol {
                if !fun.parameters.isEmpty {
                    let params = fun.parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
                    result.append(NSAttributedString(
                        string: "\n[\(params)]",
                        attributes: [.font: bodyFont, .foregroundColor: dimColor]
                    ))
                }
            }

            return result
        }

        private func showPopover(with content: NSAttributedString, at rect: NSRect, in view: NSView) {
            hidePopover()

            let popover = NSPopover()
            popover.behavior = .semitransient
            popover.animates = true

            let label = NSTextField(labelWithAttributedString: content)
            label.translatesAutoresizingMaskIntoConstraints = false

            let contentView = NSView()
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
                label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10)
            ])

            let controller = NSViewController()
            controller.view = contentView
            popover.contentViewController = controller

            hoverPopover = popover
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        }

        private func hidePopover() {
            hoverPopover?.close()
            hoverPopover = nil
        }

        /// Find the word at a given character index
        private func findWordAt(index: Int, in text: String) -> String {
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)

            var wordRange = NSRange(location: NSNotFound, length: 0)
            if index < nsText.length {
                // Find word boundaries
                var start = index
                var end = index

                // Go backwards to find start
                while start > 0 {
                    let char = nsText.character(at: start - 1)
                    if !isIdentifierChar(char) { break }
                    start -= 1
                }

                // Go forwards to find end
                while end < nsText.length {
                    let char = nsText.character(at: end)
                    if !isIdentifierChar(char) { break }
                    end += 1
                }

                if start < end {
                    wordRange = NSRange(location: start, length: end - start)
                }
            }

            if wordRange.location != NSNotFound {
                return nsText.substring(with: wordRange)
            }
            return ""
        }

        /// Check if a character is valid in an identifier
        private func isIdentifierChar(_ char: unichar) -> Bool {
            guard let scalar = UnicodeScalar(char) else { return false }
            let c = Character(scalar)
            return c.isLetter || c.isNumber || c == "_" || c == "'"
        }

        /// Look up a symbol by name
        private func lookupSymbol(named name: String, in symbolTable: SymbolTable) -> (any Symbol)? {
            // Try signatures
            if let sig = symbolTable.signatures[name] { return sig }
            // Try predicates
            if let pred = symbolTable.predicates[name] { return pred }
            // Try functions
            if let fun = symbolTable.functions[name] { return fun }
            // Try assertions
            if let assertion = symbolTable.assertions[name] { return assertion }
            // Try fields in all signatures
            for sig in symbolTable.signatures.values {
                for field in sig.fields {
                    if field.name == name { return field }
                }
            }
            // Try general lookup
            return symbolTable.lookup(name)
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView,
                  let parent = parentView else { return }

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
            } else {
                // Fallback: set text directly if textStorage is unavailable
                textView.string = text
            }

            // Restore selection
            if let firstRange = selectedRanges.first as? NSRange,
               firstRange.location + firstRange.length <= text.count {
                textView.setSelectedRange(firstRange)
            }
        }
    }
}
#else
// MARK: - iPad Editor Text View (UIViewRepresentable)

/// iOS UITextView wrapper for iPad
struct iPadEditorTextView: UIViewRepresentable {
    @Binding var text: String
    var diagnostics: [Diagnostic]
    var onTextChange: ((String) -> Void)?
    var onScrollChange: ((CGFloat) -> Void)?

    func makeUIView(context: Context) -> UIScrollView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = .systemBackground
        textView.text = text

        // Apply initial syntax highlighting
        applySyntaxHighlighting(to: textView)

        return textView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        guard let textView = uiView as? UITextView else { return }

        // Only update if text changed externally
        if textView.text != text {
            let selectedRange = textView.selectedRange
            textView.text = text
            applySyntaxHighlighting(to: textView)

            // Try to restore selection
            if selectedRange.location + selectedRange.length <= text.count {
                textView.selectedRange = selectedRange
            }
        }

        // Notify scroll position
        onScrollChange?(textView.contentOffset.y)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applySyntaxHighlighting(to textView: UITextView) {
        // Use UIKitSyntaxHighlighter for syntax highlighting
        let highlighter = UIKitSyntaxHighlighter()
        let attributedText = highlighter.highlight(text)
        textView.attributedText = attributedText
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: iPadEditorTextView

        init(_ parent: iPadEditorTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onTextChange?(textView.text)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScrollChange?(scrollView.contentOffset.y)
        }
    }
}
#endif

// MARK: - Preview

#if os(macOS)
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
#endif
