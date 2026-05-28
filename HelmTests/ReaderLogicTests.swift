import XCTest
@testable import Helm

final class DocumentLinkTests: XCTestCase {
    func testRelativeMarkdownLinkOpensAsDocument() {
        // current file "wiki/index.md", link "page.md" resolves to "/wiki/page.md"
        let link = DocumentLink.classify(
            resolvedPath: "/wiki/page.md",
            fragment: nil,
            currentPath: "wiki/index.md"
        )
        XCTAssertEqual(link, .document("wiki/page.md"))
    }

    func testParentRelativeLinkResolves() {
        let link = DocumentLink.classify(
            resolvedPath: "/notes/other.html",
            fragment: nil,
            currentPath: "wiki/index.md"
        )
        XCTAssertEqual(link, .document("notes/other.html"))
    }

    func testAbsoluteCurrentPathKeepsLeadingSlash() {
        let link = DocumentLink.classify(
            resolvedPath: "/home/deploy/wiki/page.md",
            fragment: nil,
            currentPath: "/home/deploy/wiki/index.md"
        )
        XCTAssertEqual(link, .document("/home/deploy/wiki/page.md"))
    }

    func testSameDocumentFragmentIsAnchor() {
        let link = DocumentLink.classify(
            resolvedPath: "/wiki/index.md",
            fragment: "section",
            currentPath: "wiki/index.md"
        )
        XCTAssertEqual(link, .anchor)
    }

    func testNonReadableLinkIsIgnored() {
        let link = DocumentLink.classify(
            resolvedPath: "/wiki/image.png",
            fragment: nil,
            currentPath: "wiki/index.md"
        )
        XCTAssertEqual(link, .ignore)
    }
}

final class SearchCommandTests: XCTestCase {
    func testGrepCommandQuotesQueryAndHomeDir() {
        let command = SFTPBrowser.grepCommand(query: "deploy notes", path: ".")
        XCTAssertTrue(command.contains("grep -rIli"))
        XCTAssertTrue(command.contains("--include=*.md"))
        XCTAssertTrue(command.contains("-e 'deploy notes'"))
        XCTAssertTrue(command.hasSuffix("|| true"))
    }

    func testGrepCommandEscapesSingleQuotes() {
        let command = SFTPBrowser.grepCommand(query: "it's", path: "/home/x")
        XCTAssertTrue(command.contains("'it'\\''s'"))
        XCTAssertTrue(command.contains("'/home/x'"))
    }

    func testParseSearchHitsStripsDotSlashAndBlanks() {
        let output = "./wiki/a.md\nwiki/sub/b.html\n\n./c.md\n"
        let hits = SFTPBrowser.parseSearchHits(output)
        XCTAssertEqual(hits.map(\.path), ["wiki/a.md", "wiki/sub/b.html", "c.md"])
        XCTAssertEqual(hits[1].name, "b.html")
    }
}

final class DocumentCacheTests: XCTestCase {
    func testRoundTrip() {
        let cache = DocumentCache()
        let ref = RemoteFileReference(hostID: UUID(), path: "wiki/test-\(UUID().uuidString).md", title: "t")
        XCTAssertFalse(cache.hasCopy(for: ref))
        cache.store("# Hello", for: ref)
        XCTAssertTrue(cache.hasCopy(for: ref))
        XCTAssertEqual(cache.text(for: ref), "# Hello")
        cache.remove(for: ref)
        XCTAssertNil(cache.text(for: ref))
    }
}
