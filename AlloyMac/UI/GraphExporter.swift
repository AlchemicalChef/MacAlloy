import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Graph Exporter

/// Exports instance graphs to PDF and SVG formats
public struct GraphExporter {

    // MARK: - Export to PDF

    /// Export an instance graph to PDF
    /// - Parameters:
    ///   - instance: The Alloy instance to export
    ///   - size: The size of the output PDF
    /// - Returns: PDF data
    public static func exportToPDF(instance: AlloyInstance, size: CGSize) -> Data? {
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }

        let mediaBox = CGRect(origin: .zero, size: size)
        pdfContext.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)

        // Flip coordinate system for PDF
        pdfContext.translateBy(x: 0, y: size.height)
        pdfContext.scaleBy(x: 1, y: -1)

        // Draw the graph
        drawGraph(instance: instance, context: pdfContext, size: size)

        pdfContext.endPDFPage()
        pdfContext.closePDF()

        return pdfData as Data
    }

    // MARK: - Export to SVG

    /// Export an instance graph to SVG
    /// - Parameters:
    ///   - instance: The Alloy instance to export
    ///   - size: The size of the output SVG
    /// - Returns: SVG string
    public static func exportToSVG(instance: AlloyInstance, size: CGSize) -> String {
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(size.width))" height="\(Int(size.height))" viewBox="0 0 \(Int(size.width)) \(Int(size.height))">
        <rect width="100%" height="100%" fill="#1e1e1e"/>
        <defs>
            <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
                <polygon points="0 0, 10 3.5, 0 7" fill="#888"/>
            </marker>
        </defs>

        """

        let positions = computePositions(for: instance, in: size)

        // Draw edges
        for (fieldName, tuples) in instance.fields {
            for tuple in tuples.sortedTuples where tuple.arity == 2 {
                if let fromPos = positions[tuple.first.name],
                   let toPos = positions[tuple.last.name] {
                    svg += svgEdge(from: fromPos, to: toPos, label: fieldName)
                }
            }
        }

        // Draw nodes
        for (sigName, tuples) in instance.signatures {
            let color = colorForSignature(sigName)
            for tuple in tuples.sortedTuples {
                let atomName = tuple.first.name
                if let pos = positions[atomName] {
                    svg += svgNode(at: pos, name: atomName, color: color)
                }
            }
        }

        // Draw legend
        svg += svgLegend(for: instance, at: CGPoint(x: size.width - 150, y: 20))

        svg += "</svg>"
        return svg
    }

    // MARK: - Save Panel

    #if os(macOS)
    /// Show save panel and export the graph (macOS)
    /// - Parameters:
    ///   - instance: The instance to export
    ///   - size: The size for export
    public static func showExportPanel(instance: AlloyInstance, size: CGSize) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf, .svg]
        savePanel.nameFieldStringValue = "instance"
        savePanel.title = "Export Instance Graph"
        savePanel.message = "Choose a location to save the graph"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            let ext = url.pathExtension.lowercased()

            do {
                if ext == "pdf" {
                    if let data = exportToPDF(instance: instance, size: size) {
                        try data.write(to: url)
                    }
                } else if ext == "svg" {
                    let svg = exportToSVG(instance: instance, size: size)
                    try svg.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                // Show error alert on main thread
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    #else
    /// Export data for sharing (iOS) - returns PDF data for use with share sheet
    /// - Parameters:
    ///   - instance: The instance to export
    ///   - size: The size for export
    /// - Returns: PDF data that can be shared via UIActivityViewController
    public static func exportDataForSharing(instance: AlloyInstance, size: CGSize) -> Data? {
        return exportToPDF(instance: instance, size: size)
    }

    /// Placeholder for iOS - actual export UI should be handled by SwiftUI's fileExporter or share sheet
    public static func showExportPanel(instance: AlloyInstance, size: CGSize) {
        // On iOS, use SwiftUI's .fileExporter() modifier or UIActivityViewController
        // This is a no-op placeholder; the actual export should be triggered from SwiftUI
    }
    #endif

    // MARK: - Private Drawing Helpers

    private static func drawGraph(instance: AlloyInstance, context: CGContext, size: CGSize) {
        let positions = computePositions(for: instance, in: size)

        // Draw edges
        context.setStrokeColor(NativeColor.gray.cgColor)
        context.setLineWidth(1.5)

        for (fieldName, tuples) in instance.fields {
            for tuple in tuples.sortedTuples where tuple.arity == 2 {
                if let fromPos = positions[tuple.first.name],
                   let toPos = positions[tuple.last.name] {
                    // Draw line
                    context.move(to: fromPos)
                    context.addLine(to: toPos)
                    context.strokePath()

                    // Draw arrow
                    drawArrow(context: context, from: fromPos, to: toPos)

                    // Draw label
                    let midPoint = CGPoint(x: (fromPos.x + toPos.x) / 2, y: (fromPos.y + toPos.y) / 2)
                    drawText(context: context, text: fieldName, at: CGPoint(x: midPoint.x, y: midPoint.y - 10), color: .gray, size: 10)
                }
            }
        }

        // Draw nodes
        for (sigName, tuples) in instance.signatures {
            let color = colorForSignature(sigName)
            for tuple in tuples.sortedTuples {
                let atomName = tuple.first.name
                if let pos = positions[atomName] {
                    drawNode(context: context, at: pos, name: atomName, color: color)
                }
            }
        }
    }

    private static func drawNode(context: CGContext, at point: CGPoint, name: String, color: NativeColor) {
        let radius: CGFloat = 25
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)

        // Fill
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)

        // Stroke
        context.setStrokeColor(NativeColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: rect)

        // Label
        drawText(context: context, text: name, at: point, color: .white, size: 10, centered: true)
    }

    private static func drawArrow(context: CGContext, from: CGPoint, to: CGPoint) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let arrowLength: CGFloat = 10
        let arrowAngle: CGFloat = .pi / 6

        let endPoint = CGPoint(
            x: to.x - 25 * cos(angle),
            y: to.y - 25 * sin(angle)
        )

        context.move(to: endPoint)
        context.addLine(to: CGPoint(
            x: endPoint.x - arrowLength * cos(angle - arrowAngle),
            y: endPoint.y - arrowLength * sin(angle - arrowAngle)
        ))
        context.strokePath()

        context.move(to: endPoint)
        context.addLine(to: CGPoint(
            x: endPoint.x - arrowLength * cos(angle + arrowAngle),
            y: endPoint.y - arrowLength * sin(angle + arrowAngle)
        ))
        context.strokePath()
    }

    private static func drawText(context: CGContext, text: String, at point: CGPoint, color: NativeColor, size: CGFloat, centered: Bool = false) {
        let font = NativeFont.systemFont(ofSize: size)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()

        let x = centered ? point.x - textSize.width / 2 : point.x
        let y = centered ? point.y - textSize.height / 2 : point.y

        // Use Core Text for drawing
        let line = CTLineCreateWithAttributedString(attributedString)
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }

    // MARK: - SVG Helpers

    private static func svgNode(at point: CGPoint, name: String, color: NativeColor) -> String {
        let components = color.rgbComponents
        let r = Int(components.red * 255)
        let g = Int(components.green * 255)
        let b = Int(components.blue * 255)
        let colorStr = "rgb(\(r),\(g),\(b))"

        return """
        <circle cx="\(Int(point.x))" cy="\(Int(point.y))" r="25" fill="\(colorStr)" stroke="rgba(255,255,255,0.3)" stroke-width="1"/>
        <text x="\(Int(point.x))" y="\(Int(point.y))" fill="white" font-size="10" text-anchor="middle" dominant-baseline="middle">\(escapeXML(name))</text>

        """
    }

    private static func svgEdge(from: CGPoint, to: CGPoint, label: String) -> String {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let endX = to.x - 25 * cos(angle)
        let endY = to.y - 25 * sin(angle)

        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2

        return """
        <line x1="\(Int(from.x))" y1="\(Int(from.y))" x2="\(Int(endX))" y2="\(Int(endY))" stroke="#888" stroke-width="1.5" marker-end="url(#arrowhead)"/>
        <text x="\(Int(midX))" y="\(Int(midY - 10))" fill="#888" font-size="10" text-anchor="middle">\(escapeXML(label))</text>

        """
    }

    private static func svgLegend(for instance: AlloyInstance, at origin: CGPoint) -> String {
        let sigCount = instance.signatures.count
        let fieldCount = instance.fields.count
        let fieldsHeight = instance.fields.isEmpty ? 0 : 20 + fieldCount * 20
        let totalHeight = 20 + sigCount * 20 + fieldsHeight

        let rectX = Int(origin.x - 10)
        let rectY = Int(origin.y - 10)
        let textX = Int(origin.x)
        let textY = Int(origin.y + 5)

        var svg = "<rect x=\"\(rectX)\" y=\"\(rectY)\" width=\"140\" height=\"\(totalHeight)\" fill=\"rgba(0,0,0,0.5)\" rx=\"5\"/>\n"
        svg += "<text x=\"\(textX)\" y=\"\(textY)\" fill=\"white\" font-size=\"10\" font-weight=\"bold\">Signatures</text>\n"

        var y = origin.y + 25
        for sigName in instance.signatures.keys.sorted() {
            let color = colorForSignature(sigName)
            let components = color.rgbComponents
            let r = Int(components.red * 255)
            let g = Int(components.green * 255)
            let b = Int(components.blue * 255)

            let cx = Int(origin.x + 6)
            let cy = Int(y - 4)
            let labelX = Int(origin.x + 18)
            let labelY = Int(y)

            svg += "<circle cx=\"\(cx)\" cy=\"\(cy)\" r=\"6\" fill=\"rgb(\(r),\(g),\(b))\"/>\n"
            svg += "<text x=\"\(labelX)\" y=\"\(labelY)\" fill=\"white\" font-size=\"10\">\(escapeXML(sigName))</text>\n"
            y += 20
        }

        if !instance.fields.isEmpty {
            let fieldsLabelX = Int(origin.x)
            let fieldsLabelY = Int(y + 5)
            svg += "<text x=\"\(fieldsLabelX)\" y=\"\(fieldsLabelY)\" fill=\"white\" font-size=\"10\" font-weight=\"bold\">Fields</text>\n"
            y += 25

            for fieldName in instance.fields.keys.sorted() {
                let lineX1 = Int(origin.x)
                let lineY = Int(y - 4)
                let lineX2 = Int(origin.x + 12)
                let labelX = Int(origin.x + 18)
                let labelY = Int(y)

                svg += "<line x1=\"\(lineX1)\" y1=\"\(lineY)\" x2=\"\(lineX2)\" y2=\"\(lineY)\" stroke=\"#888\" stroke-width=\"2\"/>\n"
                svg += "<text x=\"\(labelX)\" y=\"\(labelY)\" fill=\"white\" font-size=\"10\">\(escapeXML(fieldName))</text>\n"
                y += 20
            }
        }

        return svg
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Layout Helpers (delegated to GraphLayoutService)

    private static func computePositions(for instance: AlloyInstance, in size: CGSize) -> [String: CGPoint] {
        GraphLayoutService.computePositions(for: instance, in: size)
    }

    private static func colorForSignature(_ name: String) -> NativeColor {
        GraphLayoutService.nativeColorForSignature(name)
    }
}

// MARK: - UTType Extension

import UniformTypeIdentifiers

extension UTType {
    static var svg: UTType {
        UTType(filenameExtension: "svg") ?? .xml
    }
}
