import AVFoundation
import Foundation

@MainActor
final class MarkdownSpeechReader: ObservableObject {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    func toggleReading(title: String, markdown: String) {
        if synthesizer.isSpeaking {
            stopReading()
            return
        }

        let text = Self.speechText(title: title, markdown: markdown)
        guard text.isEmpty == false else {
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopReading() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated static func speechText(title: String, markdown: String) -> String {
        let body = markdown
            .split(whereSeparator: \.isNewline)
            .map { speechLine(from: String($0)) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")

        return [sentence(from: title), body]
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private nonisolated static func speechLine(from line: String) -> String {
        let stripped = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(/^#{1,6}\s*/, with: "")
            .replacing(/\*\*/, with: "")
            .replacing(/`+/, with: "")

        return sentence(from: stripped)
    }

    private nonisolated static func sentence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return ""
        }

        if let last = trimmed.last, [".", "?", "!"].contains(last) {
            return trimmed
        }

        return "\(trimmed)."
    }
}
