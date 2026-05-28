import SwiftUI
import FoundationModels

/// A minimal "ask about this document" prototype using Apple's on-device
/// Foundation Models (iOS 26+). The document text is passed as context; the model
/// runs entirely on-device — no network, no key. Large documents are truncated to
/// fit the on-device model's modest context window.
@available(iOS 26.0, *)
struct DocumentChatView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let documentText: String

    @State private var question = ""
    @State private var answer = ""
    @State private var isThinking = false
    @State private var errorText: String?

    private let contextCharacterLimit = 6000

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Ask about this doc")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch SystemLanguageModel.default.availability {
        case .available:
            chat
        case .unavailable(let reason):
            ContentUnavailableView {
                Label("On-device AI unavailable", systemImage: "sparkles")
            } description: {
                Text(Self.message(for: reason))
            }
        @unknown default:
            ContentUnavailableView("On-device AI unavailable", systemImage: "sparkles")
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollView {
                if !answer.isEmpty {
                    Text(answer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                } else if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    Text("Ask a question about “\(title)”. Answers come from this document, on-device.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Ask a question", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { Task { await ask() } }

                Button {
                    Task { await ask() }
                } label: {
                    if isThinking {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
            }
            .padding()
        }
    }

    private func ask() async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isThinking = true
        errorText = nil
        answer = ""

        let context = String(documentText.prefix(contextCharacterLimit))
        let instructions = """
        You answer questions about a single document the user is reading. Use only the
        document content below; if the answer isn't there, say so briefly. Be concise.

        DOCUMENT TITLE: \(title)
        ---
        \(context)
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: trimmed)
            answer = response.content
        } catch {
            errorText = "Couldn't generate an answer: \(error.localizedDescription)"
        }

        isThinking = false
    }

    private static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to ask questions about documents."
        case .modelNotReady:
            "The on-device model is still downloading. Try again shortly."
        @unknown default:
            "The on-device model isn't available right now."
        }
    }
}
