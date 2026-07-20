import Foundation
import Testing
@testable import Helm

@Suite("TranscriptFormatter")
struct TranscriptFormatterTests {
    private static let utc = TimeZone(secondsFromGMT: 0) ?? .current

    /// 2023-11-14T22:13:20Z
    private static let fixedStart = Date(timeIntervalSince1970: 1_700_000_000)
    /// 2023-11-14T22:43:20Z
    private static let fixedEnd = Date(timeIntervalSince1970: 1_700_001_800)

    private static func makeFormatter() -> TranscriptFormatter {
        TranscriptFormatter(timeZone: utc)
    }

    private static func line(_ text: String, at timestamp: TimeInterval) -> TranscriptionService.TranscriptLine {
        TranscriptionService.TranscriptLine(timestamp: timestamp, text: text)
    }

    @Test("Filename is date-first, millisecond precise, and sanitized")
    func filenameFormatAndSanitization() {
        let doc = Self.makeFormatter().makeDocument(
            title: "Cafe Walk: Ideas!",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "Some thoughts",
            lines: []
        )

        #expect(doc.filename == "2023-11-14_22-13-20-000_Cafe-Walk-Ideas.md")
    }

    @Test("Sub-second recordings get distinct filenames")
    func filenamesDisambiguateWithinSameSecond() {
        let formatter = Self.makeFormatter()
        let first = formatter.makeDocument(
            title: "Quick Note",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "",
            lines: []
        )
        let second = formatter.makeDocument(
            title: "Quick Note",
            startTime: Self.fixedStart.addingTimeInterval(0.123),
            endTime: Self.fixedEnd.addingTimeInterval(0.123),
            fullText: "",
            lines: []
        )

        #expect(first.filename != second.filename)
        #expect(second.filename == "2023-11-14_22-13-20-123_Quick-Note.md")
    }

    @Test("Empty title falls back to Voice note")
    func emptyTitleFallsBackToVoiceNote() {
        let doc = Self.makeFormatter().makeDocument(
            title: "",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "Some thoughts",
            lines: []
        )

        #expect(doc.title == "Voice note")
        #expect(doc.markdown.contains("# Voice note"))
        #expect(doc.filename == "2023-11-14_22-13-20-000_Voice-note.md")
    }

    @Test("Front matter identifies manual iPhone microphone recordings")
    func frontMatterKeysPresentWithExpectedValues() {
        let doc = Self.makeFormatter().makeDocument(
            title: "Morning Walk",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "Some thoughts",
            lines: []
        )

        #expect(doc.markdown.hasPrefix("---\n"))
        #expect(doc.markdown.contains(#"title: "Morning Walk""#))
        #expect(doc.markdown.contains(#"source: "manual_recording""#))
        #expect(doc.markdown.contains(#"audio_source: "iphone_mic""#))
        #expect(doc.markdown.contains("recording_started_at: \"2023-11-14T22:13:20Z\""))
        #expect(doc.markdown.contains("recording_ended_at: \"2023-11-14T22:43:20Z\""))
    }

    @Test("YAML double quotes in title are escaped")
    func yamlEscapesQuotesInTitle() {
        let doc = Self.makeFormatter().makeDocument(
            title: #"She said "hello""#,
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "",
            lines: []
        )

        #expect(doc.markdown.contains(#"title: "She said \"hello\"""#))
    }

    @Test("Lines within five seconds collapse into one timestamped chunk")
    func linesWithinWindowCollapseIntoOneChunk() {
        let lines = [
            Self.line("Hello", at: 0),
            Self.line("world", at: 2),
            Self.line("again", at: 4)
        ]
        let doc = Self.makeFormatter().makeDocument(
            title: "Test",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "Hello world again",
            lines: lines
        )

        #expect(doc.markdown.contains("[00:00] Hello world again"))
    }

    @Test("Lines across gaps split into separate timestamped chunks")
    func linesAcrossGapSplitIntoSeparateChunks() {
        let lines = [
            Self.line("First", at: 0),
            Self.line("Second", at: 10),
            Self.line("Third", at: 20)
        ]
        let doc = Self.makeFormatter().makeDocument(
            title: "Test",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "",
            lines: lines
        )

        #expect(doc.markdown.contains("[00:00] First"))
        #expect(doc.markdown.contains("[00:10] Second"))
        #expect(doc.markdown.contains("[00:20] Third"))
    }

    @Test("Timestamps past one hour use h:mm:ss")
    func longTimestampsUseHourFormat() {
        let lines = [Self.line("Deep work", at: 3725)]
        let doc = Self.makeFormatter().makeDocument(
            title: "Long",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "",
            lines: lines
        )

        #expect(doc.markdown.contains("[1:02:05] Deep work"))
    }

    @Test("Empty transcript emits placeholder")
    func emptyTranscriptEmitsPlaceholder() {
        let doc = Self.makeFormatter().makeDocument(
            title: "Empty",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "",
            lines: []
        )

        #expect(doc.markdown.contains("(No transcript)"))
    }

    @Test("Full text is used when timestamped lines are absent")
    func fullTextUsedVerbatimWhenNoTimestampedLines() {
        let doc = Self.makeFormatter().makeDocument(
            title: "Plain",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "   Just some free-form text.\n",
            lines: []
        )

        #expect(doc.markdown.contains("Just some free-form text."))
        #expect(doc.markdown.contains("(No transcript)") == false)
    }

    @Test("Whitespace-only timestamped lines fall back to full text")
    func whitespaceOnlyLinesFallBackToFullText() {
        let doc = Self.makeFormatter().makeDocument(
            title: "Plain",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "Recovered transcript",
            lines: [Self.line("   ", at: 0)]
        )

        #expect(doc.markdown.contains("Recovered transcript"))
        #expect(doc.markdown.contains("[00:00]") == false)
    }

    @Test("Cleaned body keeps the Helm document wrapper")
    func explicitBodyKeepsFrontMatterAndHeading() {
        let doc = Self.makeFormatter().makeDocument(
            title: "Cleaned",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            body: "Cleaned paragraph."
        )

        #expect(doc.markdown.contains(#"title: "Cleaned""#))
        #expect(doc.markdown.contains("# Cleaned"))
        #expect(doc.markdown.contains("Cleaned paragraph."))
    }

    @Test("Non-ASCII is stripped from filenames but preserved in document text")
    func nonASCIIHandling() {
        let doc = Self.makeFormatter().makeDocument(
            title: "Cafe resume 日本語",
            startTime: Self.fixedStart,
            endTime: Self.fixedEnd,
            fullText: "",
            lines: []
        )

        #expect(doc.filename.contains("日") == false)
        #expect(doc.markdown.contains("# Cafe resume 日本語"))
        #expect(doc.markdown.contains("title: \"Cafe resume 日本語\""))
    }
}
