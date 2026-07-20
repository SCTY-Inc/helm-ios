import SwiftUI

struct MarkdownEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let file: RemoteFileReference
    let originalText: String
    let onSaved: (String) -> Void

    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(file: RemoteFileReference, markdown: String, onSaved: @escaping (String) -> Void) {
        self.file = file
        self.originalText = markdown
        self.onSaved = onSaved
        _text = State(initialValue: markdown)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .padding(.horizontal, 8)
                .navigationTitle(file.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(text == originalText || isSaving)
                    }
                }
                .overlay {
                    if isSaving {
                        ProgressView("Saving…")
                            .padding()
                            .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                }
                .alert("Couldn't save", isPresented: errorBinding) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "Unknown error")
                }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if $0 == false { errorMessage = nil } }
        )
    }

    private func save() async {
        guard
            let host = appState.host(id: file.hostID),
            let credentials = appState.credentials(for: host)
        else {
            errorMessage = "The wiki connection is unavailable."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await SFTPBrowser.shared.replaceFile(
                host: host,
                credentials: credentials,
                path: file.path,
                expected: Data(originalText.utf8),
                replacement: Data(text.utf8)
            )
            DocumentCache.shared.store(text, for: file)
            onSaved(text)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
