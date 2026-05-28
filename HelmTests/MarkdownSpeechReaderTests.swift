import Testing
@testable import Helm

struct MarkdownSpeechReaderTests {
    @Test
    func buildsReadableTextFromMarkdown() {
        let text = MarkdownSpeechReader.speechText(
            title: "README",
            markdown: """
            # Heading

            This is **important**.

            Use `tailscale serve`.
            """
        )

        #expect(text == "README. Heading. This is important. Use tailscale serve.")
    }

    @Test
    func emptyMarkdownUsesTitle() {
        let text = MarkdownSpeechReader.speechText(title: "Only Title", markdown: "  \n")

        #expect(text == "Only Title.")
    }
}
