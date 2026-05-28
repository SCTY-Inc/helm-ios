import XCTest
@testable import Helm

final class MarkdownHTMLRendererTests: XCTestCase {
    private func render(_ markdown: String) -> String {
        MarkdownHTMLRenderer(title: nil).makeDocument(from: markdown)
    }

    func testHeadingsRenderWithLevelsAndSlugIDs() {
        let html = render("# Title\n\n## A Section")
        XCTAssertTrue(html.contains("<h1 id=\"title\">Title</h1>"))
        XCTAssertTrue(html.contains("<h2 id=\"a-section\">A Section</h2>"))
    }

    func testEmphasisAndStrongAndInlineCode() {
        let html = render("This is *italic*, **bold**, and `code`.")
        XCTAssertTrue(html.contains("<em>italic</em>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
    }

    func testFencedCodeBlockKeepsLanguageAndEscapes() {
        let html = render("```swift\nlet x = a < b && c > d\n```")
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">"))
        XCTAssertTrue(html.contains("a &lt; b &amp;&amp; c &gt; d"))
    }

    func testUnorderedListRendersItems() {
        let html = render("- one\n- two")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>one</li>"))
        XCTAssertTrue(html.contains("<li>two</li>"))
    }

    func testGFMTableRendersHeaderAndRows() {
        let markdown = """
        | Name | Role |
        | --- | --- |
        | alpha | host |
        """
        let html = render(markdown)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>Name</th>"))
        XCTAssertTrue(html.contains("<td>alpha</td>"))
    }

    func testRawHTMLInTextIsEscaped() {
        let html = render("A <script>alert(1)</script> tag")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testDocumentIncludesViewportAndStylesheet() {
        let html = render("# Hi")
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("viewport"))
        XCTAssertTrue(html.contains("prefers-color-scheme"))
    }
}
