import SwiftUI
import Combine

// MARK: - Trace View

/// Visualizes a temporal trace showing state evolution over time
public struct TraceView: View {
    let instance: AlloyInstance?
    @State private var currentState: Int = 0
    @State private var isPlaying: Bool = false
    @State private var playbackTask: Task<Void, Never>?

    public init(instance: AlloyInstance?) {
        self.instance = instance
    }

    public var body: some View {
        Group {
            if let instance = instance, let trace = instance.trace {
                traceContent(instance: instance, trace: trace)
            } else if instance != nil {
                nonTemporalView
            } else {
                emptyView
            }
        }
        .onChange(of: isPlaying) { _, playing in
            // Cancel any existing playback task
            playbackTask?.cancel()
            playbackTask = nil

            if playing {
                // Start Task-based playback timer
                playbackTask = Task { @MainActor in
                    while !Task.isCancelled && isPlaying {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        if !Task.isCancelled && isPlaying {
                            advanceState()
                        }
                    }
                }
            }
        }
        .onDisappear {
            // Clean up task on view dismissal
            playbackTask?.cancel()
            playbackTask = nil
            isPlaying = false
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No trace to display")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Run a temporal model to see the trace")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nonTemporalView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Non-temporal instance")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("This model doesn't use temporal operators")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func traceContent(instance: AlloyInstance, trace: AlloyTrace) -> some View {
        VStack(spacing: 0) {
            // Timeline header
            timelineHeader(trace: trace)

            Divider()

            // Main content
            HStack(spacing: 0) {
                // State timeline sidebar
                timelineSidebar(trace: trace)

                Divider()

                // State content
                stateContent(instance: instance, trace: trace)
            }

            Divider()

            // Playback controls
            playbackControls(trace: trace)
        }
    }

    private func timelineHeader(trace: AlloyTrace) -> some View {
        HStack {
            Text("Trace")
                .font(.headline)

            Spacer()

            Text("\(trace.length) states")
                .foregroundColor(.secondary)

            if trace.isLasso {
                Label("Loops to state \(trace.loopState ?? 0)", systemImage: "arrow.trianglehead.turn.up.right.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func timelineSidebar(trace: AlloyTrace) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<trace.length, id: \.self) { state in
                    Button(action: { currentState = state }) {
                        HStack {
                            if trace.loopState == state {
                                Image(systemName: "arrow.turn.up.left")
                                    .foregroundColor(.orange)
                            }

                            Text("State \(state)")
                                .fontWeight(state == currentState ? .bold : .regular)

                            Spacer()

                            if state == currentState {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(state == currentState ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(.plain)

                    if state < trace.length - 1 {
                        // Transition arrow
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Spacer()
                        }
                        .frame(height: 20)
                    }
                }

                // Loop back indicator
                if let loopState = trace.loopState {
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.turn.up.left")
                                .foregroundColor(.orange)
                            Text("→ State \(loopState)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        Spacer()
                    }
                    .frame(height: 40)
                }
            }
        }
        .frame(width: 140)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func stateContent(instance: AlloyInstance, trace: AlloyTrace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // State header
            HStack {
                Text("State \(currentState)")
                    .font(.title2.bold())

                if trace.loopState == currentState {
                    Label("Loop point", systemImage: "arrow.turn.up.left")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Field values at this state
            List {
                // Static signatures
                Section("Signatures") {
                    ForEach(Array(instance.signatures.keys.sorted()), id: \.self) { sigName in
                        HStack {
                            Text(sigName)
                                .fontWeight(.medium)
                            Spacer()
                            if let tuples = instance.signatures[sigName] {
                                Text(formatTupleSet(tuples))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Variable fields at current state
                Section("Fields at State \(currentState)") {
                    ForEach(Array(trace.fields.keys.sorted()), id: \.self) { fieldName in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(fieldName)
                                    .fontWeight(.medium)

                                // Show if changed from previous state
                                if currentState > 0, fieldChanged(fieldName, from: currentState - 1, to: currentState, in: trace) {
                                    Label("Changed", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }

                                Spacer()
                            }

                            if let stateValues = trace.fields[fieldName],
                               currentState < stateValues.count {
                                let tuples = stateValues[currentState]
                                if tuples.isEmpty {
                                    Text("(empty)")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.gray)
                                } else {
                                    ForEach(Array(tuples.sortedTuples.enumerated()), id: \.offset) { _, tuple in
                                        Text(tuple.description)
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func playbackControls(trace: AlloyTrace) -> some View {
        HStack(spacing: 20) {
            // Previous state
            Button(action: previousState) {
                Image(systemName: "backward.frame.fill")
            }
            .disabled(currentState == 0)

            // Play/Pause
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }

            // Next state
            Button(action: nextState) {
                Image(systemName: "forward.frame.fill")
            }
            .disabled(currentState >= trace.length - 1)

            Spacer()

            // State slider (only show if we have more than one state)
            if trace.length > 1 {
                Slider(value: Binding(
                    get: { Double(currentState) },
                    set: { currentState = Int($0) }
                ), in: 0...Double(trace.length - 1), step: 1)
                .frame(maxWidth: 300)

                Text("\(currentState) / \(trace.length - 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60)
            } else {
                Text("Single state")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Actions

    private func previousState() {
        if currentState > 0 {
            currentState -= 1
        }
    }

    private func nextState() {
        guard let trace = instance?.trace else { return }
        if currentState < trace.length - 1 {
            currentState += 1
        } else if let loopState = trace.loopState {
            currentState = loopState
        }
    }

    /// Called by timer publisher to advance state during playback
    private func advanceState() {
        nextState()
    }

    private func togglePlayback() {
        isPlaying.toggle()
    }

    // MARK: - Helpers

    private func formatTupleSet(_ tuples: TupleSet) -> String {
        if tuples.isEmpty {
            return "(empty)"
        }
        return tuples.sortedTuples.map { $0.description }.joined(separator: ", ")
    }

    private func fieldChanged(_ fieldName: String, from prevState: Int, to currState: Int, in trace: AlloyTrace) -> Bool {
        guard prevState >= 0,
              currState >= 0,
              let stateValues = trace.fields[fieldName],
              prevState < stateValues.count,
              currState < stateValues.count else {
            return false
        }
        return stateValues[prevState] != stateValues[currState]
    }
}

// MARK: - Trace Diff View

/// Shows differences between two states
public struct TraceDiffView: View {
    let trace: AlloyTrace
    let fromState: Int
    let toState: Int

    public var body: some View {
        List {
            ForEach(Array(trace.fields.keys.sorted()), id: \.self) { fieldName in
                if let stateValues = trace.fields[fieldName],
                   fromState < stateValues.count,
                   toState < stateValues.count {
                    let fromTuples = stateValues[fromState]
                    let toTuples = stateValues[toState]

                    if fromTuples != toTuples {
                        Section(fieldName) {
                            // Removed tuples
                            let removed = fromTuples.difference(toTuples)
                            ForEach(Array(removed.sortedTuples.enumerated()), id: \.offset) { _, tuple in
                                HStack {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                    Text(tuple.description)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }

                            // Added tuples
                            let added = toTuples.difference(fromTuples)
                            ForEach(Array(added.sortedTuples.enumerated()), id: \.offset) { _, tuple in
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                    Text(tuple.description)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Preview

struct TraceView_Previews: PreviewProvider {
    static var previews: some View {
        TraceView(instance: nil)
    }
}
