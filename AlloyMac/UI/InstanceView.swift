import SwiftUI
import AppKit

// MARK: - Instance View

/// Visualizes an Alloy instance as a graph
public struct InstanceView: View {
    let instance: AlloyInstance?
    @State private var selectedAtoms: Set<String> = []
    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var hiddenSignatures: Set<String> = []
    @State private var hiddenFields: Set<String> = []
    @State private var showFilterPanel: Bool = false

    public init(instance: AlloyInstance?) {
        self.instance = instance
    }

    public var body: some View {
        Group {
            if let instance = instance {
                instanceGraph(instance)
            } else {
                emptyView
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.grid.3x3")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No instances to display")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Run a command to find instances")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func instanceGraph(_ instance: AlloyInstance) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Main graph area
                ZStack {
                    // Background
                    Color(nsColor: .windowBackgroundColor)
                        .ignoresSafeArea()

                    // Graph canvas
                    Canvas { context, size in
                        let positions = computePositions(for: instance, in: size)

                        // Compute visible atoms based on signature filters
                        let visibleAtoms = computeVisibleAtoms(from: instance)

                        // Draw edges first (filtered and highlighted)
                        for (fieldName, tuples) in instance.fields {
                            guard !hiddenFields.contains(fieldName) else { continue }
                            for tuple in tuples.sortedTuples where tuple.arity == 2 {
                                let fromName = tuple.first.name
                                let toName = tuple.last.name
                                guard visibleAtoms.contains(fromName) && visibleAtoms.contains(toName) else { continue }
                                if let fromPos = positions[fromName],
                                   let toPos = positions[toName] {
                                    let isHighlighted = selectedAtoms.contains(fromName) || selectedAtoms.contains(toName)
                                    drawEdge(context: context, from: fromPos, to: toPos, label: fieldName, isHighlighted: isHighlighted)
                                }
                            }
                        }

                        // Draw nodes (filtered)
                        for (sigName, tuples) in instance.signatures {
                            guard !hiddenSignatures.contains(sigName) else { continue }
                            let color = colorForSignature(sigName)
                            for tuple in tuples.sortedTuples {
                                let atomName = tuple.first.name
                                if let pos = positions[atomName] {
                                    let isSelected = selectedAtoms.contains(atomName)
                                    let isDimmed = !selectedAtoms.isEmpty && !isSelected && !isConnectedToSelection(atomName, in: instance)
                                    drawNode(context: context, at: pos, name: atomName, color: color, isSelected: isSelected, isDimmed: isDimmed)
                                }
                            }
                        }
                    }
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = value.magnification
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                offset = value.translation
                            }
                    )
                    .onTapGesture { location in
                        handleTap(at: location, in: geometry.size, instance: instance)
                    }

                    // Selection info overlay
                    if !selectedAtoms.isEmpty {
                        VStack {
                            HStack {
                                selectionInfoView(for: instance)
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding()
                    }

                    // Controls
                    VStack {
                        Spacer()
                        HStack {
                            Button(action: { scale *= 1.2 }) {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .buttonStyle(.bordered)

                            Button(action: { scale /= 1.2 }) {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .buttonStyle(.bordered)

                            Button(action: { scale = 1.0; offset = .zero; selectedAtoms.removeAll() }) {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .help("Reset view and selection")

                            if !selectedAtoms.isEmpty {
                                Button(action: { selectedAtoms.removeAll() }) {
                                    Label("Clear Selection", systemImage: "xmark.circle")
                                }
                                .buttonStyle(.bordered)
                            }

                            Spacer()

                            Button(action: { showFilterPanel.toggle() }) {
                                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                            }
                            .buttonStyle(.bordered)

                            Button(action: {
                                GraphExporter.showExportPanel(instance: instance, size: geometry.size)
                            }) {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                }

                // Filter panel (collapsible sidebar)
                if showFilterPanel {
                    filterPanelView(for: instance)
                        .frame(width: 200)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    // MARK: - Interaction Helpers

    private func handleTap(at location: CGPoint, in size: CGSize, instance: AlloyInstance) {
        let positions = computePositions(for: instance, in: size)

        // Transform location based on current scale and offset
        // scaleEffect scales around center, offset is applied after
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let locationMinusOffset = CGPoint(x: location.x - offset.width, y: location.y - offset.height)
        let transformedX = center.x + (locationMinusOffset.x - center.x) / scale
        let transformedY = center.y + (locationMinusOffset.y - center.y) / scale

        // Find if we tapped on a node
        let nodeRadius: CGFloat = 25
        for (atomName, pos) in positions {
            let dx = transformedX - pos.x
            let dy = transformedY - pos.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance <= nodeRadius {
                // Selection behavior:
                // - Shift+Click: Toggle atom in multi-select (add/remove from selection)
                // - Click on selected atom when it's the only selection: Deselect
                // - Click on any atom: Select only that atom
                if NSEvent.modifierFlags.contains(.shift) {
                    // Multi-select mode: toggle the atom
                    if selectedAtoms.contains(atomName) {
                        selectedAtoms.remove(atomName)
                    } else {
                        selectedAtoms.insert(atomName)
                    }
                } else {
                    // Single-select mode
                    if selectedAtoms.contains(atomName) && selectedAtoms.count == 1 {
                        // Clicking the only selected atom deselects it
                        selectedAtoms.removeAll()
                    } else {
                        // Select only this atom
                        selectedAtoms = [atomName]
                    }
                }
                return
            }
        }

        // Tapped on empty space - clear selection
        if !NSEvent.modifierFlags.contains(.shift) {
            selectedAtoms.removeAll()
        }
    }

    private func computeVisibleAtoms(from instance: AlloyInstance) -> Set<String> {
        var visible: Set<String> = []
        for (sigName, tuples) in instance.signatures {
            guard !hiddenSignatures.contains(sigName) else { continue }
            for tuple in tuples.sortedTuples {
                visible.insert(tuple.first.name)
            }
        }
        return visible
    }

    private func isConnectedToSelection(_ atomName: String, in instance: AlloyInstance) -> Bool {
        for tuples in instance.fields.values {
            for tuple in tuples.sortedTuples where tuple.arity == 2 {
                if (tuple.first.name == atomName && selectedAtoms.contains(tuple.last.name)) ||
                   (tuple.last.name == atomName && selectedAtoms.contains(tuple.first.name)) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Selection Info View

    private func selectionInfoView(for instance: AlloyInstance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selection")
                .font(.caption.bold())

            ForEach(Array(selectedAtoms.sorted()), id: \.self) { atomName in
                HStack {
                    Circle()
                        .fill(colorForAtom(atomName, in: instance))
                        .frame(width: 10, height: 10)
                    Text(atomName)
                        .font(.caption)
                }
            }

            if selectedAtoms.count == 1, let atom = selectedAtoms.first {
                Divider()
                Text("Relations")
                    .font(.caption.bold())

                let relations = getRelationsForAtom(atom, in: instance)
                if relations.isEmpty {
                    Text("No relations")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(relations, id: \.self) { relation in
                        Text(relation)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func colorForAtom(_ atomName: String, in instance: AlloyInstance) -> Color {
        for (sigName, tuples) in instance.signatures {
            for tuple in tuples.sortedTuples {
                if tuple.first.name == atomName {
                    return colorForSignature(sigName)
                }
            }
        }
        return .gray
    }

    private func getRelationsForAtom(_ atomName: String, in instance: AlloyInstance) -> [String] {
        var relations: [String] = []
        for (fieldName, tuples) in instance.fields {
            for tuple in tuples.sortedTuples where tuple.arity == 2 {
                if tuple.first.name == atomName {
                    relations.append("\(fieldName) → \(tuple.last.name)")
                } else if tuple.last.name == atomName {
                    relations.append("\(tuple.first.name) → \(fieldName)")
                }
            }
        }
        return relations
    }

    // MARK: - Filter Panel

    private func filterPanelView(for instance: AlloyInstance) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Filters")
                        .font(.headline)
                    Spacer()
                    Button(action: { showFilterPanel = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // Signatures section
                Text("Signatures")
                    .font(.subheadline.bold())

                ForEach(Array(instance.signatures.keys.sorted()), id: \.self) { sigName in
                    Toggle(isOn: Binding(
                        get: { !hiddenSignatures.contains(sigName) },
                        set: { visible in
                            if visible {
                                hiddenSignatures.remove(sigName)
                            } else {
                                hiddenSignatures.insert(sigName)
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colorForSignature(sigName))
                                .frame(width: 12, height: 12)
                            Text(sigName)
                                .font(.caption)
                            Text("(\(instance.signatures[sigName]?.count ?? 0))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                if !instance.fields.isEmpty {
                    Divider()

                    // Fields section
                    Text("Fields")
                        .font(.subheadline.bold())

                    ForEach(Array(instance.fields.keys.sorted()), id: \.self) { fieldName in
                        Toggle(isOn: Binding(
                            get: { !hiddenFields.contains(fieldName) },
                            set: { visible in
                                if visible {
                                    hiddenFields.remove(fieldName)
                                } else {
                                    hiddenFields.insert(fieldName)
                                }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Rectangle()
                                    .fill(Color.secondary)
                                    .frame(width: 12, height: 2)
                                Text(fieldName)
                                    .font(.caption)
                                Text("(\(instance.fields[fieldName]?.count ?? 0))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }

                Divider()

                // Quick actions
                Button(action: {
                    hiddenSignatures.removeAll()
                    hiddenFields.removeAll()
                }) {
                    Label("Show All", systemImage: "eye")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    hiddenSignatures = Set(instance.signatures.keys)
                    hiddenFields = Set(instance.fields.keys)
                }) {
                    Label("Hide All", systemImage: "eye.slash")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private func computePositions(for instance: AlloyInstance, in size: CGSize) -> [String: CGPoint] {
        // Check if cached positions are still valid - must have same atoms, not just same count
        let currentAtoms = Set(collectAllAtoms(from: instance))
        let cachedAtoms = Set(nodePositions.keys)
        if !nodePositions.isEmpty && currentAtoms == cachedAtoms {
            return nodePositions
        }

        var positions: [String: CGPoint] = [:]

        // Use force-directed layout simulation
        let atoms = collectAllAtoms(from: instance)
        let edges = collectAllEdges(from: instance)

        // Initial placement in a circle
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.35

        for (index, atom) in atoms.enumerated() {
            let angle = 2 * .pi * Double(index) / Double(max(1, atoms.count))
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            positions[atom] = CGPoint(x: x, y: y)
        }

        // Simple force-directed iterations
        for _ in 0..<50 {
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
                    if dist > 1 {
                        let force = 5000 / (dist * dist)
                        let fx = (dx / dist) * force
                        let fy = (dy / dist) * force

                        if var forceI = forces[atoms[i]] {
                            forceI.dx -= fx
                            forceI.dy -= fy
                            forces[atoms[i]] = forceI
                        }
                        if var forceJ = forces[atoms[j]] {
                            forceJ.dx += fx
                            forceJ.dy += fy
                            forces[atoms[j]] = forceJ
                        }
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
                if dist > 1 {
                    let force = dist * 0.01
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force

                    if var forceFrom = forces[edge.from] {
                        forceFrom.dx += fx
                        forceFrom.dy += fy
                        forces[edge.from] = forceFrom
                    }
                    if var forceTo = forces[edge.to] {
                        forceTo.dx -= fx
                        forceTo.dy -= fy
                        forces[edge.to] = forceTo
                    }
                }
            }

            // Apply forces
            for atom in atoms {
                guard var pos = positions[atom],
                      let force = forces[atom] else { continue }

                pos.x += force.dx * 0.1
                pos.y += force.dy * 0.1

                // Keep in bounds
                pos.x = max(50, min(size.width - 50, pos.x))
                pos.y = max(50, min(size.height - 50, pos.y))

                positions[atom] = pos
            }
        }

        return positions
    }

    private func collectAllAtoms(from instance: AlloyInstance) -> [String] {
        var atoms: Set<String> = []
        for tuples in instance.signatures.values {
            for tuple in tuples.sortedTuples {
                atoms.insert(tuple.first.name)
            }
        }
        return Array(atoms).sorted()
    }

    private func collectAllEdges(from instance: AlloyInstance) -> [(from: String, to: String)] {
        var edges: [(from: String, to: String)] = []
        for tuples in instance.fields.values {
            for tuple in tuples.sortedTuples where tuple.arity == 2 {
                edges.append((from: tuple.first.name, to: tuple.last.name))
            }
        }
        return edges
    }

    private func totalAtomCount(_ instance: AlloyInstance) -> Int {
        var atoms: Set<String> = []
        for tuples in instance.signatures.values {
            for tuple in tuples.sortedTuples {
                atoms.insert(tuple.first.name)
            }
        }
        return atoms.count
    }

    private func drawNode(context: GraphicsContext, at point: CGPoint, name: String, color: Color, isSelected: Bool, isDimmed: Bool = false) {
        let nodeRadius: CGFloat = 25
        let opacity: Double = isDimmed ? 0.3 : 1.0

        // Node circle
        let rect = CGRect(x: point.x - nodeRadius, y: point.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)

        // Selection glow
        if isSelected {
            // Outer glow
            context.fill(Circle().path(in: rect.insetBy(dx: -6, dy: -6)), with: .color(.accentColor.opacity(0.3)))
            context.stroke(Circle().path(in: rect.insetBy(dx: -3, dy: -3)), with: .color(.accentColor), lineWidth: 3)
        }

        context.fill(Circle().path(in: rect), with: .color(color.opacity(opacity)))
        context.stroke(Circle().path(in: rect), with: .color(.primary.opacity(0.3 * opacity)), lineWidth: 1)

        // Node label
        let text = Text(name).font(.caption2).foregroundColor(.white.opacity(opacity))
        context.draw(text, at: point, anchor: .center)
    }

    private func drawEdge(context: GraphicsContext, from: CGPoint, to: CGPoint, label: String, isHighlighted: Bool = false) {
        let edgeColor: Color = isHighlighted ? .accentColor : .secondary
        let lineWidth: CGFloat = isHighlighted ? 2.5 : 1.5
        let opacity: Double = selectedAtoms.isEmpty ? 1.0 : (isHighlighted ? 1.0 : 0.3)

        let path = Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }

        context.stroke(path, with: .color(edgeColor.opacity(opacity)), lineWidth: lineWidth)

        // Arrow head
        let angle = atan2(to.y - from.y, to.x - from.x)
        let arrowLength: CGFloat = isHighlighted ? 12 : 10
        let arrowAngle: CGFloat = .pi / 6

        let endPoint = CGPoint(
            x: to.x - 25 * cos(angle),
            y: to.y - 25 * sin(angle)
        )

        let arrowPath = Path { p in
            p.move(to: endPoint)
            p.addLine(to: CGPoint(
                x: endPoint.x - arrowLength * cos(angle - arrowAngle),
                y: endPoint.y - arrowLength * sin(angle - arrowAngle)
            ))
            p.move(to: endPoint)
            p.addLine(to: CGPoint(
                x: endPoint.x - arrowLength * cos(angle + arrowAngle),
                y: endPoint.y - arrowLength * sin(angle + arrowAngle)
            ))
        }

        context.stroke(arrowPath, with: .color(edgeColor.opacity(opacity)), lineWidth: lineWidth)

        // Edge label
        let midPoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let labelColor: Color = isHighlighted ? .accentColor : .secondary
        let text = Text(label).font(.caption2).foregroundColor(labelColor.opacity(opacity))
        context.draw(text, at: CGPoint(x: midPoint.x, y: midPoint.y - 10), anchor: .center)
    }

    private func colorForSignature(_ name: String) -> Color {
        // Generate consistent color based on name hash
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.7)
    }
}

// MARK: - Instance Table View

/// Alternative table-based view of an instance
public struct InstanceTableView: View {
    let instance: AlloyInstance

    public init(instance: AlloyInstance) {
        self.instance = instance
    }

    public var body: some View {
        List {
            Section("Signatures") {
                ForEach(Array(instance.signatures.keys.sorted()), id: \.self) { sigName in
                    DisclosureGroup {
                        if let tuples = instance.signatures[sigName] {
                            ForEach(Array(tuples.sortedTuples.enumerated()), id: \.offset) { _, tuple in
                                Text(tuple.description)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    } label: {
                        HStack {
                            Text(sigName)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(instance.signatures[sigName]?.count ?? 0)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Fields") {
                ForEach(Array(instance.fields.keys.sorted()), id: \.self) { fieldName in
                    DisclosureGroup {
                        if let tuples = instance.fields[fieldName] {
                            ForEach(Array(tuples.sortedTuples.enumerated()), id: \.offset) { _, tuple in
                                Text(tuple.description)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    } label: {
                        HStack {
                            Text(fieldName)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(instance.fields[fieldName]?.count ?? 0)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Preview

struct InstanceView_Previews: PreviewProvider {
    static var previews: some View {
        InstanceView(instance: nil)
    }
}
