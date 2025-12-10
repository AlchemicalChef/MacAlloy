import SwiftUI

// MARK: - Rename Symbol Dialog

/// Dialog for renaming a symbol across all references
public struct RenameSymbolDialog: View {
    let originalName: String
    let referenceCount: Int
    let onRename: (String) -> Void
    let onCancel: () -> Void

    @State private var newName: String
    @State private var validationError: String?
    @FocusState private var isTextFieldFocused: Bool

    public init(
        originalName: String,
        referenceCount: Int,
        onRename: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.originalName = originalName
        self.referenceCount = referenceCount
        self.onRename = onRename
        self.onCancel = onCancel
        self._newName = State(initialValue: originalName)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rename Symbol")
                        .font(.headline)

                    Text("\(referenceCount) occurrence\(referenceCount == 1 ? "" : "s") will be updated")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Current name
            HStack {
                Text("From:")
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)

                Text(originalName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }

            // New name input
            HStack(alignment: .top) {
                Text("To:")
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("New name", text: $newName)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .onChange(of: newName) { _, _ in
                            validateName()
                        }
                        .onSubmit {
                            if validationError == nil && !newName.isEmpty && newName != originalName {
                                onRename(newName)
                            }
                        }

                    if let error = validationError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            Divider()

            // Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    onRename(newName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isRenameEnabled)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear {
            isTextFieldFocused = true
        }
    }

    private var isRenameEnabled: Bool {
        !newName.isEmpty && newName != originalName && validationError == nil
    }

    private func validateName() {
        if newName.isEmpty {
            validationError = nil
            return
        }

        if newName == originalName {
            validationError = nil
            return
        }

        validationError = ReferenceSearchService.validateRename(newName)
    }
}

// MARK: - Preview

struct RenameSymbolDialog_Previews: PreviewProvider {
    static var previews: some View {
        RenameSymbolDialog(
            originalName: "Person",
            referenceCount: 5,
            onRename: { _ in },
            onCancel: { }
        )
    }
}
