import Foundation

/// How Helm authenticates to a host. The secret material itself (private key text,
/// passphrase, password) is never stored here — only in the Keychain, keyed by the
/// host's id. This struct records which method to use and whether a passphrase exists.
enum SSHAuthMethod: String, Codable, Hashable, Sendable {
    case tailscaleSSH
    case privateKey
    case password

    var displayName: String {
        switch self {
        case .tailscaleSSH: "Tailscale SSH"
        case .privateKey: "Key"
        case .password: "Password"
        }
    }
}

/// A remote machine Helm can browse over SFTP. Mirrors an `~/.ssh/config` entry:
/// a nickname, where to connect, who to log in as, and where to start browsing.
struct SSHHost: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var nickname: String
    var hostname: String
    var port: Int
    var username: String
    var authMethod: SSHAuthMethod
    var hasPassphrase: Bool
    var startPath: String

    init(
        id: UUID = UUID(),
        nickname: String,
        hostname: String,
        port: Int = 22,
        username: String,
        authMethod: SSHAuthMethod,
        hasPassphrase: Bool = false,
        startPath: String = "."
    ) {
        self.id = id
        self.nickname = nickname
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.hasPassphrase = hasPassphrase
        self.startPath = startPath
    }

    var displayName: String {
        nickname.isEmpty ? hostname : nickname
    }

    var subtitle: String {
        "\(username)@\(hostname)\(port == 22 ? "" : ":\(port)")"
    }

    /// A normalized starting directory; empty/blank falls back to the home directory.
    var normalizedStartPath: String {
        let trimmed = startPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "." : trimmed
    }
}
