import Foundation
import Markdown

/// Converts CommonMark/GFM markdown into a styled, self-contained HTML document
/// suitable for display in a `WKWebView`. Parsing is handled by swift-markdown;
/// this type walks the resulting AST and serializes it to HTML.
struct MarkdownHTMLRenderer {
    var title: String?

    func makeDocument(from markdown: String) -> String {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        var visitor = HTMLVisitor()
        let body = visitor.visit(document)
        return HTMLTheme.wrap(body: body, title: title)
    }

    /// Heading outline for a table of contents. Slugs match the `id` attributes
    /// the renderer emits, so they can be scrolled to in the web view.
    func outline(from markdown: String) -> [DocumentHeading] {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        var headings: [DocumentHeading] = []

        func walk(_ markup: Markup) {
            for child in markup.children {
                if let heading = child as? Heading {
                    headings.append(
                        DocumentHeading(
                            order: headings.count,
                            level: heading.level,
                            title: heading.plainText,
                            slug: HTMLTheme.slug(for: heading.plainText)
                        )
                    )
                }
                walk(child)
            }
        }

        walk(document)
        return headings
    }
}

struct DocumentHeading: Identifiable, Hashable, Sendable {
    let order: Int
    let level: Int
    let title: String
    let slug: String

    var id: Int { order }
}

/// Walks a swift-markdown AST and produces an HTML fragment.
private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    mutating func defaultVisit(_ markup: Markup) -> String {
        renderChildren(of: markup)
    }

    private mutating func renderChildren(of markup: Markup) -> String {
        var html = ""
        for child in markup.children {
            html += visit(child)
        }
        return html
    }

    mutating func visitDocument(_ document: Document) -> String {
        renderChildren(of: document)
    }

    mutating func visitText(_ text: Text) -> String {
        HTMLTheme.escape(text.string)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(renderChildren(of: paragraph))</p>\n"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(max(heading.level, 1), 6)
        let inner = renderChildren(of: heading)
        let slug = HTMLTheme.slug(for: heading.plainText)
        return "<h\(level) id=\"\(slug)\">\(inner)</h\(level)>\n"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(renderChildren(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(renderChildren(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(renderChildren(of: strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(HTMLTheme.escape(inlineCode.code))</code>"
    }

    // Raw HTML embedded in markdown is escaped rather than passed through, so a
    // wiki page can never inject live markup into the reader's web view.
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        HTMLTheme.escape(inlineHTML.rawHTML)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        "<p>\(HTMLTheme.escape(html.rawHTML))</p>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let language = codeBlock.language.map { HTMLTheme.escape($0) } ?? ""
        let classAttribute = language.isEmpty ? "" : " class=\"language-\(language)\""
        let code = HTMLTheme.escape(codeBlock.code)
        return "<pre><code\(classAttribute)>\(code)</code></pre>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(renderChildren(of: blockQuote))</blockquote>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitLink(_ link: Link) -> String {
        let destination = link.destination.map { HTMLTheme.escapeAttribute($0) } ?? ""
        return "<a href=\"\(destination)\">\(renderChildren(of: link))</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let source = image.source.map { HTMLTheme.escapeAttribute($0) } ?? ""
        let alt = HTMLTheme.escapeAttribute(image.plainText)
        return "<img src=\"\(source)\" alt=\"\(alt)\">"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        "<ul>\n\(renderChildren(of: unorderedList))</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let start = orderedList.startIndex
        let startAttribute = start == 1 ? "" : " start=\"\(start)\""
        return "<ol\(startAttribute)>\n\(renderChildren(of: orderedList))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let inner = renderListItemContent(of: listItem)
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            return "<li class=\"task\"><input type=\"checkbox\" disabled\(checked)>\(inner)</li>\n"
        }
        return "<li>\(inner)</li>\n"
    }

    /// Renders a list item's content, unwrapping the implicit `Paragraph` that
    /// swift-markdown places around item text so tight lists read as `<li>text</li>`
    /// while still allowing nested blocks (sub-lists, code) to render normally.
    private mutating func renderListItemContent(of listItem: ListItem) -> String {
        var html = ""
        for child in listItem.children {
            if let paragraph = child as? Paragraph {
                html += renderChildren(of: paragraph)
            } else {
                html += visit(child)
            }
        }
        return html
    }

    mutating func visitTable(_ table: Table) -> String {
        var html = "<table>\n"
        html += "<thead>\(visit(table.head))</thead>\n"
        html += "<tbody>\(visit(table.body))</tbody>\n"
        html += "</table>\n"
        return html
    }

    mutating func visitTableHead(_ head: Table.Head) -> String {
        var row = "<tr>"
        for cell in head.cells {
            row += "<th>\(renderChildren(of: cell))</th>"
        }
        row += "</tr>\n"
        return row
    }

    mutating func visitTableBody(_ body: Table.Body) -> String {
        renderChildren(of: body)
    }

    mutating func visitTableRow(_ row: Table.Row) -> String {
        var html = "<tr>"
        for cell in row.cells {
            html += "<td>\(renderChildren(of: cell))</td>"
        }
        html += "</tr>\n"
        return html
    }

    mutating func visitTableCell(_ cell: Table.Cell) -> String {
        renderChildren(of: cell)
    }
}
