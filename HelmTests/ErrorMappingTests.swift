import XCTest
@testable import Helm

final class SFTPBrowserErrorMappingTests: XCTestCase {
    /// Regression: the unreachable-host string NIOConnectionError bridges to must map
    /// to the friendly connection message, not leak raw "(NIOPosix...)" to the UI.
    func testNIOConnectionErrorMapsToFriendlyMessage() {
        let raw = "the operation couldn't be completed. (nioposix.nioconnectionerror error 1.)"
        XCTAssertEqual(SFTPBrowser.classify(raw), .connectionFailed(SFTPBrowser.unreachableMessage))
    }

    func testAuthFailuresTakePriority() {
        XCTAssertEqual(SFTPBrowser.classify("permission denied (publickey)"), .authenticationFailed)
        XCTAssertEqual(SFTPBrowser.classify("authentication failed"), .authenticationFailed)
    }

    func testCommonConnectionKeywordsMapToConnectionFailed() {
        let cases = [
            "connection refused",
            "operation timed out",
            "host is unreachable",
            "connection closed",
            "unexpected eof",
            "no route to host",
        ]
        for text in cases {
            XCTAssertEqual(
                SFTPBrowser.classify(text),
                .connectionFailed(SFTPBrowser.unreachableMessage),
                "expected \"\(text)\" to classify as a connection failure"
            )
        }
    }

    func testUnrecognizedErrorReturnsNil() {
        XCTAssertNil(SFTPBrowser.classify("some entirely unrelated failure"))
    }
}
