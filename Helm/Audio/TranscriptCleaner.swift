import Foundation
import FoundationModels

/// On-device cleanup of a raw voice-note transcript into readable Markdown,
/// using Apple's Foundation Models (iOS 26+). Mirrors DocumentChatView's
/// availability check and truncation pattern — no network, no key.
enum TranscriptCleaner {

    private static let contextCharacterLimit = 6000

    /// Returns cleaned Markdown, or `nil` if the on-device model is unavailable
    /// or generation fails. Callers should fall back to the raw transcript.
    @available(iOS 26.0, *)
    static func clean(rawTranscript: String, title: String) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else {
            return nil
        }

        let context = String(rawTranscript.prefix(contextCharacterLimit))
        let instructions = """
        You convert a raw voice-note transcript into clean Markdown body text. Fix punctuation
        and paragraph breaks, remove filler words and false starts, but PRESERVE the
        speaker's words and meaning. Add light structure with paragraphs and lists
        where the speaker clearly enumerates. Do NOT include YAML front matter or
        a title heading. Do NOT invent facts or add content that wasn't spoken.

        RAW TRANSCRIPT:
        \(context)
        """

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: "Clean up this transcript.")
            return response.content
        } catch {
            return nil
        }
    }
}
