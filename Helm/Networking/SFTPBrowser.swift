import Foundation
import Citadel
import Crypto
import NIOCore
@preconcurrency import NIOSSH

/// Offers the SSH "none" authentication method once. This is how Tailscale SSH
/// works: the tailnet has already authenticated the device, so the SSH server
/// accepts with no key or password.
private final class NoneAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private var offered = false

    init(username: String) {
        self.username = username
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !offered else {
            nextChallengePromise.succeed(nil)
            return
        }
        offered = true
        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: .none)
        )
    }
}

/// Errors surfaced to the UI, mapped from lower-level SSH/SFTP failures.
enum SFTPBrowserError: LocalizedError, Equatable {
    case missingCredentials
    case unsupportedKey
    case authenticationFailed
    case connectionFailed(String)
    case notReadable
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "No saved credentials for this host. Edit the host and add a key or password."
        case .unsupportedKey:
            "Helm couldn't read this private key. Use an OpenSSH ed25519 or RSA key, and check the passphrase."
        case .authenticationFailed:
            "Authentication failed. Check the username, key, and passphrase."
        case let .connectionFailed(message):
            message
        case .notReadable:
            "This file couldn't be read as text."
        case let .underlying(message):
            message
        }
    }
}

/// One match from a remote search.
struct SearchHit: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    var id: String { path }
}

/// Reads remote machines over SFTP, caching one live connection per host so
/// navigation stays fast. A dead/stale connection is evicted and reconnected once.
///
/// This is a plain `final class` rather than an actor on purpose: Citadel's
/// `SSHClient`/`SFTPClient` are non-Sendable, and storing them as actor-isolated
/// state then awaiting their nonisolated methods is rejected by Swift 6. As a
/// non-isolated class with lock-guarded storage and an `@unchecked Sendable`
/// connection wrapper (NIO objects are EventLoop-thread-safe), the clients are
/// used as ordinary locals — no isolation crossing.
final class SFTPBrowser: @unchecked Sendable {
    static let shared = SFTPBrowser()

    private struct Connection: @unchecked Sendable {
        let client: SSHClient
        let sftp: SFTPClient
    }

    private let lock = NSLock()
    private var connections: [UUID: Connection] = [:]

    // MARK: - Public operations

    func list(host: SSHHost, credentials: ResolvedCredentials, path: String) async throws -> [RemoteFileEntry] {
        try await perform(host: host, credentials: credentials) { connection in
            let names = try await connection.sftp.listDirectory(atPath: path)
            let entries = names
                .flatMap(\.components)
                .compactMap { Self.entry(from: $0, parentPath: path) }

            return entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    func readFile(host: SSHHost, credentials: ResolvedCredentials, path: String) async throws -> Data {
        try await perform(host: host, credentials: credentials) { connection in
            let file = try await connection.sftp.openFile(filePath: path, flags: .read)
            let buffer = try await file.readAll()
            try? await file.close()
            return Data(buffer.readableBytesView)
        }
    }

    /// Full-text search via remote `grep` over the start directory, returning
    /// matching markdown/HTML file paths.
    func search(host: SSHHost, credentials: ResolvedCredentials, query: String, path: String) async throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let command = Self.grepCommand(query: trimmed, path: path)

        return try await perform(host: host, credentials: credentials) { connection in
            let buffer = try await connection.client.executeCommand(command)
            let output = String(buffer: buffer)
            return Self.parseSearchHits(output)
        }
    }

    /// Opens (and caches) a connection just to confirm reachability. Returns true
    /// if the host answered, warming the pool so the first browse is instant.
    func warmUp(host: SSHHost, credentials: ResolvedCredentials) async -> Bool {
        do {
            _ = try await openConnection(for: host, credentials: credentials)
            return true
        } catch {
            return false
        }
    }

    func disconnect(hostID: UUID) async {
        let connection = withLock { connections.removeValue(forKey: hostID) }
        if let connection {
            try? await connection.sftp.close()
            try? await connection.client.close()
        }
    }

    // MARK: - Connection lifecycle

    private func perform<T: Sendable>(
        host: SSHHost,
        credentials: ResolvedCredentials,
        _ body: @Sendable (Connection) async throws -> T
    ) async throws -> T {
        let connection = try await openConnection(for: host, credentials: credentials)
        do {
            return try await body(connection)
        } catch {
            let mapped = Self.map(error)
            // A cached connection may have died (host slept, network changed).
            // Drop it and try once more with a fresh one.
            guard case .connectionFailed = mapped else {
                throw mapped
            }
            await disconnect(hostID: host.id)
            let fresh = try await openConnection(for: host, credentials: credentials)
            do {
                return try await body(fresh)
            } catch {
                throw Self.map(error)
            }
        }
    }

    private func openConnection(for host: SSHHost, credentials: ResolvedCredentials) async throws -> Connection {
        if let cached = withLock({ connections[host.id] }) {
            return cached
        }

        let authentication = try Self.authentication(for: credentials)
        let client: SSHClient
        do {
            client = try await SSHClient.connect(
                host: host.hostname,
                port: host.port,
                authenticationMethod: authentication,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never
            )
        } catch {
            throw Self.map(error)
        }

        do {
            let sftp = try await client.openSFTP()
            let connection = Connection(client: client, sftp: sftp)
            withLock { connections[host.id] = connection }
            return connection
        } catch {
            try? await client.close()
            throw Self.map(error)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - Auth

    private static func authentication(for credentials: ResolvedCredentials) throws -> SSHAuthenticationMethod {
        switch credentials.method {
        case .tailscaleSSH:
            return .custom(NoneAuthenticationDelegate(username: credentials.username))
        case let .password(password):
            return .passwordBased(username: credentials.username, password: password)
        case let .privateKey(text, passphrase):
            let decryptionKey = passphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }

            if let ed25519 = try? Curve25519.Signing.PrivateKey(sshEd25519: text, decryptionKey: decryptionKey) {
                return .ed25519(username: credentials.username, privateKey: ed25519)
            }

            if let rsa = try? Insecure.RSA.PrivateKey(sshRsa: text, decryptionKey: decryptionKey) {
                return .rsa(username: credentials.username, privateKey: rsa)
            }

            throw SFTPBrowserError.unsupportedKey
        }
    }

    // MARK: - Listing helpers

    private static func entry(from component: SFTPPathComponent, parentPath: String) -> RemoteFileEntry? {
        let name = component.filename
        guard name != ".", name != ".." else {
            return nil
        }

        let kind: RemoteFileEntry.Kind
        if isDirectory(component) {
            kind = .directory
        } else {
            switch RemoteFileFormat(path: name) {
            case .markdown: kind = .markdown
            case .html: kind = .html
            case .none: return nil
            }
        }

        return RemoteFileEntry(
            name: name,
            path: join(parentPath, name),
            kind: kind,
            modified: component.attributes.accessModificationTime?.modificationTime
        )
    }

    private static func isDirectory(_ component: SFTPPathComponent) -> Bool {
        if let permissions = component.attributes.permissions {
            return (permissions & 0o170000) == 0o040000
        }
        return component.longname.first == "d"
    }

    static func join(_ base: String, _ name: String) -> String {
        if base == "." || base.isEmpty {
            return name
        }
        if base.hasSuffix("/") {
            return base + name
        }
        return base + "/" + name
    }

    // MARK: - Search helpers

    static func grepCommand(query: String, path: String) -> String {
        let directory = (path.isEmpty || path == ".") ? "." : shellQuote(path)
        let needle = shellQuote(query)
        // -r recursive, -I skip binary, -l names only, -i case-insensitive, -e literal pattern.
        // `|| true` so a no-match exit code (1) isn't treated as a command failure.
        return "grep -rIli --include=*.md --include=*.markdown --include=*.html -e \(needle) \(directory) 2>/dev/null || true"
    }

    static func parseSearchHits(_ output: String) -> [SearchHit] {
        output
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                var path = String(line)
                if path.hasPrefix("./") {
                    path.removeFirst(2)
                }
                return path
            }
            .filter { !$0.isEmpty }
            .map { path in
                let name = (path as NSString).lastPathComponent
                return SearchHit(path: path, name: name)
            }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Error mapping

    private static func map(_ error: Error) -> SFTPBrowserError {
        if let browserError = error as? SFTPBrowserError {
            return browserError
        }

        let description = String(describing: error).lowercased()
        if description.contains("auth") || description.contains("permission denied") {
            return .authenticationFailed
        }
        if description.contains("refused") || description.contains("timed out")
            || description.contains("timeout") || description.contains("unreachable")
            || description.contains("connect") || description.contains("closed")
            || description.contains("notconnected") || description.contains("eof") {
            return .connectionFailed("Couldn't reach the host. Check that it's online and that Tailscale is connected on this device.")
        }
        return .underlying(error.localizedDescription)
    }
}
