import Foundation

struct WikiChangeRequestFormatter {
    struct Document: Sendable {
        let filename: String
        let markdown: String
    }

    func makeDocument(
        targetPath: String,
        targetTitle: String,
        targetFormat: RemoteFileFormat,
        instruction: String,
        requestedAt: Date = .now
    ) -> Document {
        let timestamp = timestamp(requestedAt)
        let format = targetFormat == .html ? "html" : "markdown"
        let sourceGuidance = targetFormat == .html
            ? "Because this may be generated HTML, locate and edit its canonical source rather than the rendered artifact when possible."
            : "Edit the target Markdown file unless the request clearly points to another canonical source."

        let markdown = """
        ---
        type: "helm_change_request"
        status: "pending"
        target_path: "\(escapeYAML(targetPath))"
        target_title: "\(escapeYAML(targetTitle))"
        target_format: "\(format)"
        requested_at: "\(iso8601(requestedAt))"
        source: "helm_ios"
        ---

        # Change request: \(targetTitle)

        ## Requested change

        \(instruction.trimmingCharacters(in: .whitespacesAndNewlines))

        ## Agent guidance

        \(sourceGuidance)

        Inspect the target and its surrounding project context, make the smallest safe change, verify it, and leave a reviewable diff. Do not deploy or publish automatically.
        """

        return Document(
            filename: "\(timestamp)_helm-change-request.md",
            markdown: markdown
        )
    }

    private func escapeYAML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return formatter.string(from: date)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
