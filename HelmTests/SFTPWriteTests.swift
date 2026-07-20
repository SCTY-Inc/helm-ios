import XCTest
@testable import Helm

final class SFTPWriteTests: XCTestCase {
    func testNoCollisionReturnsInput() {
        XCTAssertEqual(SFTPBrowser.uniqueFilename("note.md", existing: []), "note.md")
    }

    func testSingleCollisionAppendsDash2() {
        XCTAssertEqual(SFTPBrowser.uniqueFilename("note.md", existing: ["note.md"]), "note-2.md")
    }

    func testChainOfCollisionsSkipsToNextFreeIndex() {
        let existing: Set<String> = ["note.md", "note-2.md"]
        XCTAssertEqual(SFTPBrowser.uniqueFilename("note.md", existing: existing), "note-3.md")
    }

    func testNoExtensionAppendsDash2() {
        XCTAssertEqual(SFTPBrowser.uniqueFilename("note", existing: ["note"]), "note-2")
    }

    func testMultiDotSplitsOnLastDot() {
        XCTAssertEqual(SFTPBrowser.uniqueFilename("a.b.md", existing: ["a.b.md"]), "a.b-2.md")
    }
}
