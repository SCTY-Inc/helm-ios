import XCTest
@testable import Helm

final class SSHModelTests: XCTestCase {
    func testRemoteFileFormatDetectsMarkdownAndHTML() {
        XCTAssertEqual(RemoteFileFormat(path: "notes.md"), .markdown)
        XCTAssertEqual(RemoteFileFormat(path: "README.MARKDOWN"), .markdown)
        XCTAssertEqual(RemoteFileFormat(path: "page.html"), .html)
        XCTAssertEqual(RemoteFileFormat(path: "page.htm"), .html)
        XCTAssertNil(RemoteFileFormat(path: "archive.zip"))
        XCTAssertNil(RemoteFileFormat(path: "noextension"))
    }

    func testHostSubtitleOmitsDefaultPort() {
        let host = SSHHost(nickname: "server", hostname: "host.example", username: "admin", authMethod: .privateKey)
        XCTAssertEqual(host.subtitle, "admin@host.example")
    }

    func testHostSubtitleShowsNonDefaultPort() {
        let host = SSHHost(nickname: "x", hostname: "h", port: 2222, username: "me", authMethod: .password)
        XCTAssertEqual(host.subtitle, "me@h:2222")
    }

    func testNormalizedStartPathFallsBackToHome() {
        let host = SSHHost(nickname: "x", hostname: "h", username: "me", authMethod: .password, startPath: "   ")
        XCTAssertEqual(host.normalizedStartPath, ".")
    }

    func testDisplayNameFallsBackToHostname() {
        let host = SSHHost(nickname: "", hostname: "host.example", username: "me", authMethod: .password)
        XCTAssertEqual(host.displayName, "host.example")
    }

    func testRemoteFileReferenceIDIsStable() {
        let id = UUID()
        let ref = RemoteFileReference(hostID: id, path: "docs/a.md", title: "a")
        XCTAssertEqual(ref.id, "\(id.uuidString)|docs/a.md")
    }

    func testAuthMethodDisplayNames() {
        XCTAssertEqual(SSHAuthMethod.tailscaleSSH.displayName, "Tailscale SSH")
        XCTAssertEqual(SSHAuthMethod.privateKey.displayName, "Key")
        XCTAssertEqual(SSHAuthMethod.password.displayName, "Password")
    }

    @MainActor
    func testTailscaleSSHHostNeedsNoStoredSecret() {
        let state = AppState(
            hostStore: EphemeralHostStore(),
            favoritesStore: EphemeralFavoritesStore()
        )
        let host = SSHHost(nickname: "example", hostname: "example-host", username: "user", authMethod: .tailscaleSSH)
        state.saveHost(host)

        // No Keychain secret was stored, yet credentials resolve via the none method.
        let credentials = state.credentials(for: host)
        XCTAssertNotNil(credentials)
        if case .tailscaleSSH = credentials?.method {} else {
            XCTFail("expected tailscaleSSH credentials")
        }
        XCTAssertEqual(credentials?.username, "user")
    }
}

private struct EphemeralHostStore: HostStore {
    func load() -> [SSHHost] { [] }
    func save(_ hosts: [SSHHost]) {}
}

private struct EphemeralFavoritesStore: FavoritesStore {
    func load() -> [FavoriteItem] { [] }
    func save(_ favorites: [FavoriteItem]) {}
}


final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore(service: "org.scty.helm.tests")
    private let account = "unit-test-secret"

    override func tearDown() {
        store.delete(account: account)
        super.tearDown()
    }

    func testRoundTripAndDelete() {
        XCTAssertTrue(store.set("hunter2", account: account))
        XCTAssertEqual(store.get(account: account), "hunter2")

        XCTAssertTrue(store.set("changed", account: account))
        XCTAssertEqual(store.get(account: account), "changed")

        XCTAssertTrue(store.delete(account: account))
        XCTAssertNil(store.get(account: account))
    }

    func testEmptyValueClearsItem() {
        store.set("value", account: account)
        store.set("", account: account)
        XCTAssertNil(store.get(account: account))
    }
}
