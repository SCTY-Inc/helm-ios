import Foundation

@MainActor
protocol HostStore {
    func load() -> [SSHHost]
    func save(_ hosts: [SSHHost])
}

struct UserDefaultsHostStore: HostStore {
    private let key = "helm.hosts.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SSHHost] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([SSHHost].self, from: data)) ?? []
    }

    func save(_ hosts: [SSHHost]) {
        do {
            let data = try JSONEncoder().encode(hosts)
            defaults.set(data, forKey: key)
        } catch {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Secret material resolved from the Keychain for a single connection attempt.
/// Kept out of `SSHHost` so credentials never touch UserDefaults.
struct ResolvedCredentials: Sendable {
    enum Method: Sendable {
        case tailscaleSSH                                   // SSH "none" auth — Tailscale vouches
        case password(String)
        case privateKey(text: String, passphrase: String?)
    }

    let username: String
    let method: Method
}
