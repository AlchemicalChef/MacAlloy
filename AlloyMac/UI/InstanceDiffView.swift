import SwiftUI
import AppKit

// MARK: - Instance Comparator

/// Compares two Alloy instances and produces a diff
public struct InstanceComparator {

    public struct DiffResult {
        let addedAtoms: Set<String>
        let removedAtoms: Set<String>
        let unchangedAtoms: Set<String>
        let addedTuples: [String: Set<String>]      // fieldName -> set of tuple descriptions
        let removedTuples: [String: Set<String>]
        let unchangedTuples: [String: Set<String>]

        var hasChanges: Bool {
            !addedAtoms.isEmpty || !removedAtoms.isEmpty ||
            addedTuples.values.contains { !$0.isEmpty } ||
            removedTuples.values.contains { !$0.isEmpty }
        }
    }

    public static func compare(left: AlloyInstance?, right: AlloyInstance?) -> DiffResult {
        guard let left = left, let right = right else {
            return DiffResult(
                addedAtoms: [],
                removedAtoms: [],
                unchangedAtoms: [],
                addedTuples: [:],
                removedTuples: [:],
                unchangedTuples: [:]
            )
        }

        // Collect atoms from both instances
        let leftAtoms = collectAtoms(from: left)
        let rightAtoms = collectAtoms(from: right)

        let addedAtoms = rightAtoms.subtracting(leftAtoms)
        let removedAtoms = leftAtoms.subtracting(rightAtoms)
        let unchangedAtoms = leftAtoms.intersection(rightAtoms)

        // Collect tuples from fields
        var addedTuples: [String: Set<String>] = [:]
        var removedTuples: [String: Set<String>] = [:]
        var unchangedTuples: [String: Set<String>] = [:]

        let allFieldNames = Set(left.fields.keys).union(Set(right.fields.keys))

        for fieldName in allFieldNames {
            let leftTuples = tupleDescriptions(for: fieldName, in: left)
            let rightTuples = tupleDescriptions(for: fieldName, in: right)

            addedTuples[fieldName] = rightTuples.subtracting(leftTuples)
            removedTuples[fieldName] = leftTuples.subtracting(rightTuples)
            unchangedTuples[fieldName] = leftTuples.intersection(rightTuples)
        }

        return DiffResult(
            addedAtoms: addedAtoms,
            removedAtoms: removedAtoms,
            unchangedAtoms: unchangedAtoms,
            addedTuples: addedTuples,
            removedTuples: removedTuples,
            unchangedTuples: unchangedTuples
        )
    }

    private static func collectAtoms(from instance: AlloyInstance) -> Set<String> {
        var atoms: Set<String> = []
        for tuples in instance.signatures.values {
            for tuple in tuples.sortedTuples {
                atoms.insert(tuple.first.name)
            }
        }
        return atoms
    }

    private static func tupleDescriptions(for fieldName: String, in instance: AlloyInstance) -> Set<String> {
        guard let tuples = instance.fields[fieldName] else { return [] }
        var descriptions: Set<String> = []
        for tuple in tuples.sortedTuples {
            descriptions.insert(tuple.description)
        }
        return descriptions
    }
}

// MARK: - Instance Diff View

/// Side-by-side comparison of two Alloy instances
public struct InstanceDiffView: View {
    let instances: [AlloyInstance]
    @State private var leftIndex: Int = 0
    @State private var rightIndex: Int = 1
    @State private var syncNavigation: Bool = true
    @State private var showDiffPanel: Bool = true

    // Shared navigation state for synced pan/zoom
    @State private var sharedScale: CGFloat = 1.0
    @State private var sharedOffset: CGSize = .zero

    // Independent navigation state for each side
    @State private var leftScale: CGFloat = 1.0
    @State private var leftOffset: CGSize = .zero
    @State private var rightScale: CGFloat = 1.0
    @State private var rightOffset: CGSize = .zero

    public init(instances: [AlloyInstance]) {
        self.instances = instances
    }

    private var leftInstance: AlloyInstance? {
        guard leftIndex < instances.count else { return nil }
        return instances[leftIndex]
    }

    private var rightInstance: AlloyInstance? {
        guard rightIndex < instances.count else { return nil }
        return instances[rightIndex]
    }

    private var diff: InstanceComparator.DiffResult {
        InstanceComparator.compare(left: leftInstance, right: rightInstance)
    }

    public var body: some View {
        if instances.count < 2 {
            notEnoughInstancesView
        } else {
            mainDiffView
        }
    }

    private var notEnoughInstancesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Need at least 2 instances to compare")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Run commands to generate multiple instances")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainDiffView: some View {
        VStack(spacing: 0) {
            // Instance selectors and controls
            controlBar

            Divider()

            // Main content
            HSplitView {
                // Left instance
                VStack(spacing: 0) {
                    instanceHeader(title: "Instance \(leftIndex + 1)", isLeft: true)
                    DiffGraphView(
                        instance: leftInstance,
                        diff: diff,
                        isLeftSide: true,
                        scale: syncNavigation ? $sharedScale : $leftScale,
                        offset: syncNavigation ? $sharedOffset : $leftOffset
                    )
                }

                // Right instance
                VStack(spacing: 0) {
                    instanceHeader(title: "Instance \(rightIndex + 1)", isLeft: false)
                    DiffGraphView(
                        instance: rightInstance,
                        diff: diff,
                        isLeftSide: false,
                        scale: syncNavigation ? $sharedScale : $rightScale,
                        offset: syncNavigation ? $sharedOffset : $rightOffset
                    )
                }
            }
            .onChange(of: syncNavigation) { _, newSyncValue in
                // Transfer values when switching sync mode
                if newSyncValue {
                    // Switching to synced mode: use average of both sides
                    sharedScale = (leftScale + rightScale) / 2
                    sharedOffset = CGSize(
                        width: (leftOffset.width + rightOffset.width) / 2,
                        height: (leftOffset.height + rightOffset.height) / 2
                    )
                } else {
                    // Switching to independent mode: initialize from shared values
                    leftScale = sharedScale
                    leftOffset = sharedOffset
                    rightScale = sharedScale
                    rightOffset = sharedOffset
                }
            }

            // Diff summary panel
            if showDiffPanel {
                Divider()
                diffSummaryPanel
            }
        }
    }

    private var controlBar: some View {
        HStack {
            // Left instance picker
            Picker("Left:", selection: $leftIndex) {
                ForEach(0..<instances.count, id: \.self) { index in
                    Text("Instance \(index + 1)").tag(index)
                }
            }
            .frame(width: 180)

            Text("vs")
                .foregroundColor(.secondary)

            // Right instance picker
            Picker("Right:", selection: $rightIndex) {
                ForEach(0..<instances.count, id: \.self) { index in
                    Text("Instance \(index + 1)").tag(index)
                }
            }
            .frame(width: 180)

            Spacer()

            // Sync toggle
            Toggle(isOn: $syncNavigation) {
                Label("Sync Navigation", systemImage: "link")
            }
            .toggleStyle(.checkbox)

            // Show diff panel toggle
            Toggle(isOn: $showDiffPanel) {
                Label("Diff Panel", systemImage: "list.bullet.rectangle")
            }
            .toggleStyle(.checkbox)

            // Swap button
            Button(action: {
                let temp = leftIndex
                leftIndex = rightIndex
                rightIndex = temp
            }) {
                Label("Swap", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.bordered)

            // Reset view
            Button(action: {
                sharedScale = 1.0
                sharedOffset = .zero
                leftScale = 1.0
                leftOffset = .zero
                rightScale = 1.0
                rightOffset = .zero
            }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func instanceHeader(title: String, isLeft: Bool) -> some View {
        HStack {
            Text(title)
                .font(.headline)

            Spacer()

            if let instance = isLeft ? leftInstance : rightInstance {
                Text("\(countAtoms(in: instance)) atoms")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var diffSummaryPanel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                // Atoms summary
                VStack(alignment: .leading, spacing: 4) {
                    Text("Atoms")
                        .font(.caption.bold())

                    HStack(spacing: 12) {
                        diffBadge(count: diff.addedAtoms.count, label: "Added", color: .green)
                        diffBadge(count: diff.removedAtoms.count, label: "Removed", color: .red)
                        diffBadge(count: diff.unchangedAtoms.count, label: "Unchanged", color: .secondary)
                    }
                }

                Divider()
                    .frame(height: 40)

                // Tuple changes by field
                ForEach(Array(diff.addedTuples.keys.sorted()), id: \.self) { fieldName in
                    let added = diff.addedTuples[fieldName]?.count ?? 0
                    let removed = diff.removedTuples[fieldName]?.count ?? 0
                    let unchanged = diff.unchangedTuples[fieldName]?.count ?? 0

                    if added > 0 || removed > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fieldName)
                                .font(.caption.bold())

                            HStack(spacing: 12) {
                                if added > 0 {
                                    diffBadge(count: added, label: "+", color: .green)
                                }
                                if removed > 0 {
                                    diffBadge(count: removed, label: "-", color: .red)
                                }
                                if unchanged > 0 {
                                    diffBadge(count: unchanged, label: "=", color: .secondary)
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Overall status
                if diff.hasChanges {
                    Label("Differences found", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                } else {
                    Label("Instances are identical", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            .padding()
        }
        .frame(height: 70)
        .background(.ultraThinMaterial)
    }

    private func diffBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
            Text("\(count)")
                .font(.caption.monospacedDigit().bold())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .cornerRadius(4)
    }

    private func countAtoms(in instance: AlloyInstance) -> Int {
        var atoms: Set<String> = []
        for tuples in instance.signatures.values {
            for tuple in tuples.sortedTuples {
                atoms.insert(tuple.first.name)
            }
        }
        return atoms.count
    }
}

// MARK: - Diff Graph View

/// Graph view with diff highlighting
struct DiffGraphView: View {
    let instance: AlloyInstance?
    let diff: InstanceComparator.DiffResult
    let isLeftSide: Bool
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    var body: some View {
        GeometryReader { geometry in
            if let instance = instance {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                        .ignoresSafeArea()

                    Canvas { context, size in
                        let positions = computePositions(for: instance, in: size)

                        // Draw edges
                        for (fieldName, tuples) in instance.fields {
                            for tuple in tuples.sortedTuples where tuple.arity == 2 {
                                if let fromPos = positions[tuple.first.name],
                                   let toPos = positions[tuple.last.name] {
                                    let tupleDesc = tuple.description
                                    let diffState = getDiffState(for: tupleDesc, fieldName: fieldName)
                                    drawDiffEdge(context: context, from: fromPos, to: toPos, label: fieldName, diffState: diffState)
                                }
                            }
                        }

                        // Draw nodes
                        for (sigName, tuples) in instance.signatures {
                            let baseColor = colorForSignature(sigName)
                            for tuple in tuples.sortedTuples {
                                let atomName = tuple.first.name
                                if let pos = positions[atomName] {
                                    let diffState = getAtomDiffState(atomName)
                                    drawDiffNode(context: context, at: pos, name: atomName, color: baseColor, diffState: diffState)
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
                        Spacer()
                        HStack {
                            diffLegend
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                            Spacer()
                        }
                        .padding()
                    }
                }
            } else {
                Text("No instance")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var diffLegend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Added").font(.caption2)
            }
            HStack(spacing: 4) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Removed").font(.caption2)
            }
            HStack(spacing: 4) {
                Circle().fill(.secondary).frame(width: 8, height: 8)
                Text("Unchanged").font(.caption2)
            }
        }
    }

    private enum DiffState {
        case added, removed, unchanged
    }

    private func getAtomDiffState(_ atomName: String) -> DiffState {
        if isLeftSide {
            if diff.removedAtoms.contains(atomName) {
                return .removed
            }
        } else {
            if diff.addedAtoms.contains(atomName) {
                return .added
            }
        }
        return .unchanged
    }

    private func getDiffState(for tupleDesc: String, fieldName: String) -> DiffState {
        if isLeftSide {
            if diff.removedTuples[fieldName]?.contains(tupleDesc) == true {
                return .removed
            }
        } else {
            if diff.addedTuples[fieldName]?.contains(tupleDesc) == true {
                return .added
            }
        }
        return .unchanged
    }

    private func drawDiffNode(context: GraphicsContext, at point: CGPoint, name: String, color: Color, diffState: DiffState) {
        let nodeRadius: CGFloat = 25
        let rect = CGRect(x: point.x - nodeRadius, y: point.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)

        // Diff indicator ring
        switch diffState {
        case .added:
            context.fill(Circle().path(in: rect.insetBy(dx: -4, dy: -4)), with: .color(.green.opacity(0.3)))
            context.stroke(Circle().path(in: rect.insetBy(dx: -2, dy: -2)), with: .color(.green), lineWidth: 3)
        case .removed:
            context.fill(Circle().path(in: rect.insetBy(dx: -4, dy: -4)), with: .color(.red.opacity(0.3)))
            context.stroke(Circle().path(in: rect.insetBy(dx: -2, dy: -2)), with: .color(.red), lineWidth: 3)
        case .unchanged:
            break
        }

        // Main node
        context.fill(Circle().path(in: rect), with: .color(color))
        context.stroke(Circle().path(in: rect), with: .color(.primary.opacity(0.3)), lineWidth: 1)

        // Label
        let text = Text(name).font(.caption2).foregroundColor(.white)
        context.draw(text, at: point, anchor: .center)
    }

    private func drawDiffEdge(context: GraphicsContext, from: CGPoint, to: CGPoint, label: String, diffState: DiffState) {
        let edgeColor: Color
        let lineWidth: CGFloat

        switch diffState {
        case .added:
            edgeColor = .green
            lineWidth = 2.5
        case .removed:
            edgeColor = .red
            lineWidth = 2.5
        case .unchanged:
            edgeColor = .secondary
            lineWidth = 1.5
        }

        let path = Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }

        context.stroke(path, with: .color(edgeColor), lineWidth: lineWidth)

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

        context.stroke(arrowPath, with: .color(edgeColor), lineWidth: lineWidth)

        // Edge label
        let midPoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let text = Text(label).font(.caption2).foregroundColor(edgeColor)
        context.draw(text, at: CGPoint(x: midPoint.x, y: midPoint.y - 10), anchor: .center)
    }

    // MARK: - Position Calculation (copied from InstanceView)

    private func computePositions(for instance: AlloyInstance, in size: CGSize) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        let atoms = collectAllAtoms(from: instance)
        let edges = collectAllEdges(from: instance)

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.35

        for (index, atom) in atoms.enumerated() {
            let angle = 2 * .pi * Double(index) / Double(max(1, atoms.count))
            positions[atom] = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }

        // Force-directed iterations
        for _ in 0..<50 {
            var forces: [String: CGVector] = [:]
            for atom in atoms { forces[atom] = .zero }

            // Repulsion
            for i in 0..<atoms.count {
                for j in (i+1)..<atoms.count {
                    guard let p1 = positions[atoms[i]], let p2 = positions[atoms[j]] else { continue }
                    let dx = p2.x - p1.x, dy = p2.y - p1.y
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist > 1 {
                        let force = 5000 / (dist * dist)
                        let fx = (dx / dist) * force, fy = (dy / dist) * force
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

            // Attraction
            for edge in edges {
                guard let p1 = positions[edge.from], let p2 = positions[edge.to] else { continue }
                let dx = p2.x - p1.x, dy = p2.y - p1.y
                let dist = sqrt(dx * dx + dy * dy)
                if dist > 1 {
                    let force = dist * 0.01
                    let fx = (dx / dist) * force, fy = (dy / dist) * force
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

            // Apply
            for atom in atoms {
                guard var pos = positions[atom], let force = forces[atom] else { continue }
                pos.x += force.dx * 0.1
                pos.y += force.dy * 0.1
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

    private func colorForSignature(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.7)
    }
}
