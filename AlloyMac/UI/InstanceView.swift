import SwiftUI

// MARK: - Instance View

/// Visualizes an Alloy instance as a graph
public struct InstanceView: View {
    let instance: AlloyInstance?
    @State private var selectedAtom: String?
    @State private var nodePositions: [String: CGPoint] = [:]
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

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
            ZStack {
                // Background
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                // Graph canvas
                Canvas { context, size in
                    let positions = computePositions(for: instance, in: size)

                    // Draw edges first
                    for (fieldName, tuples) in instance.fields {
                        for tuple in tuples.sortedTuples where tuple.arity == 2 {
                            if let fromPos = positions[tuple.first.name],
                               let toPos = positions[tuple.last.name] {
                                drawEdge(context: context, from: fromPos, to: toPos, label: fieldName)
                            }
                        }
                    }

                    // Draw nodes
                    for (sigName, tuples) in instance.signatures {
                        let color = colorForSignature(sigName)
                        for tuple in tuples.sortedTuples {
                            let atomName = tuple.first.name
                            if let pos = positions[atomName] {
                                drawNode(context: context, at: pos, name: atomName, color: color, isSelected: atomName == selectedAtom)
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

                // Legend
                VStack {
                    HStack {
                        Spacer()
                        legendView(for: instance)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding()

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

                        Button(action: { scale = 1.0; offset = .zero }) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                    .padding()
                }
            }
        }
    }

    private func legendView(for instance: AlloyInstance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Signatures")
                .font(.caption.bold())

            ForEach(Array(instance.signatures.keys.sorted()), id: \.self) { sigName in
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

            if !instance.fields.isEmpty {
                Divider()
                Text("Fields")
                    .font(.caption.bold())

                ForEach(Array(instance.fields.keys.sorted()), id: \.self) { fieldName in
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
            }
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
            let angle = 2 * .pi * Double(index) / Double(atoms.count)
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

                        forces[atoms[i]]!.dx -= fx
                        forces[atoms[i]]!.dy -= fy
                        forces[atoms[j]]!.dx += fx
                        forces[atoms[j]]!.dy += fy
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

                    forces[edge.from]!.dx += fx
                    forces[edge.from]!.dy += fy
                    forces[edge.to]!.dx -= fx
                    forces[edge.to]!.dy -= fy
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

    private func drawNode(context: GraphicsContext, at point: CGPoint, name: String, color: Color, isSelected: Bool) {
        let nodeRadius: CGFloat = 25

        // Node circle
        let rect = CGRect(x: point.x - nodeRadius, y: point.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)

        if isSelected {
            context.stroke(Circle().path(in: rect.insetBy(dx: -3, dy: -3)), with: .color(.accentColor), lineWidth: 3)
        }

        context.fill(Circle().path(in: rect), with: .color(color))
        context.stroke(Circle().path(in: rect), with: .color(.primary.opacity(0.3)), lineWidth: 1)

        // Node label
        let text = Text(name).font(.caption2).foregroundColor(.white)
        context.draw(text, at: point, anchor: .center)
    }

    private func drawEdge(context: GraphicsContext, from: CGPoint, to: CGPoint, label: String) {
        let path = Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }

        context.stroke(path, with: .color(.secondary), lineWidth: 1.5)

        // Arrow head
        let angle = atan2(to.y - from.y, to.x - from.x)
        let arrowLength: CGFloat = 10
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

        context.stroke(arrowPath, with: .color(.secondary), lineWidth: 1.5)

        // Edge label
        let midPoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let text = Text(label).font(.caption2).foregroundColor(.secondary)
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
