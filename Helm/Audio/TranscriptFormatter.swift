import Foundation

/// Formats voice-note transcript data into YAML front matter + timestamped markdown body.
struct TranscriptFormatter {

    struct TranscriptDocument {
        let title: String
        let filename: String
        let markdown: String
    }

    private let timeZone: TimeZone

    init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    /// Build a complete markdown transcript document.
    /// - Parameters:
    ///   - title: User-supplied or inferred title
    ///   - startTime: Recording start
    ///   - endTime: Recording end
    ///   - fullText: Complete transcript text
    ///   - lines: Timestamped transcript segments
    /// - Returns: TranscriptDocument with title, filename, and markdown content
    func makeDocument(
        title: String,
        startTime: Date,
        endTime: Date,
        fullText: String,
        lines: [TranscriptionService.TranscriptLine]
    ) -> TranscriptDocument {
        let body = makeBody(fullText: fullText, lines: lines)
        return makeDocument(title: title, startTime: startTime, endTime: endTime, body: body)
    }

    func makeDocument(
        title: String,
        startTime: Date,
        endTime: Date,
        body: String
    ) -> TranscriptDocument {
        let resolvedTitle = title.isEmpty ? "Voice note" : title
        let filename = makeFilename(title: resolvedTitle, date: startTime)
        let frontMatter = makeFrontMatter(title: resolvedTitle, startTime: startTime, endTime: endTime)

        let markdown = """
        \(frontMatter)

        # \(resolvedTitle)

        \(headingDateRange(startTime: startTime, endTime: endTime))

        \(body)
        """.replacingOccurrences(of: "        ", with: "")

        return TranscriptDocument(title: resolvedTitle, filename: filename, markdown: markdown)
    }

    // MARK: - Front matter

    /// Build YAML front matter block.
    private func makeFrontMatter(title: String, startTime: Date, endTime: Date) -> String {
        let yamlLines: [String?] = [
            "---",
            yamlScalar(key: "title", value: title),
            yamlScalar(key: "source", value: "manual_recording"),
            yamlScalar(key: "audio_source", value: "iphone_mic"),
            yamlScalar(key: "recording_started_at", value: iso8601(startTime)),
            yamlScalar(key: "recording_ended_at", value: iso8601(endTime)),
            "---"
        ]
        return yamlLines.compactMap { $0 }.joined(separator: "\n")
    }

    // MARK: - Body

    /// Collapse transcript lines into timestamped paragraphs (5-second grouping).
    private func makeBody(
        fullText: String,
        lines: [TranscriptionService.TranscriptLine]
    ) -> String {
        let filteredLines = lines.compactMap { line -> TranscriptionService.TranscriptLine? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptionService.TranscriptLine(timestamp: line.timestamp, text: text)
        }

        if filteredLines.isEmpty {
            let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(No transcript)" : trimmed
        }

        var result: [String] = []
        var currentChunk: [String] = []
        var chunkStart = filteredLines[0].timestamp

        for line in filteredLines {
            if line.timestamp - chunkStart > 5, !currentChunk.isEmpty {
                result.append("[\(formatTimestamp(chunkStart))] \(currentChunk.joined(separator: " "))")
                currentChunk = []
                chunkStart = line.timestamp
            }
            currentChunk.append(line.text)
        }

        if !currentChunk.isEmpty {
            result.append("[\(formatTimestamp(chunkStart))] \(currentChunk.joined(separator: " "))")
        }

        return result.joined(separator: "\n\n")
    }

    // MARK: - Filename

    /// Generate date-first filename: yyyy-MM-dd_HH-mm-ss-SSS_Title.md
    private func makeFilename(title: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"

        let datePart = formatter.string(from: date)
        let safeName = title
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: " +", with: "-", options: .regularExpression)
            .prefix(60)
        let filenameTitle = safeName.isEmpty ? "Voice-note" : String(safeName)
        return "\(datePart)_\(filenameTitle).md"
    }

    // MARK: - Helpers

    private func headingDateRange(startTime: Date, endTime: Date) -> String {
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.timeZone = timeZone
        dateFmt.dateFormat = "yyyy-MM-dd"

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.timeZone = timeZone
        timeFmt.dateFormat = "HH:mm"

        return "\(dateFmt.string(from: startTime)) \(timeFmt.string(from: startTime))\u{2013}\(timeFmt.string(from: endTime))"
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func escapeYAML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func yamlScalar(key: String, value: String?) -> String? {
        guard let value = trimmedOrNil(value) else { return nil }
        return "\(key): \"\(escapeYAML(value))\""
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
