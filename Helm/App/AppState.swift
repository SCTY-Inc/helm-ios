import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var hosts: [SSHHost]
    @Published private(set) var favorites: [FavoriteItem]

    private let hostStore: HostStore
    private let favoritesStore: FavoritesStore
    private let keychain: KeychainStore

    init(
        hostStore: HostStore = UserDefaultsHostStore(),
        favoritesStore: FavoritesStore = UserDefaultsFavoritesStore(),
        keychain: KeychainStore = KeychainStore()
    ) {
        self.hostStore = hostStore
        self.favoritesStore = favoritesStore
        self.keychain = keychain
        self.hosts = hostStore.load().sorted(by: Self.byDisplayName)
        self.favorites = favoritesStore.load()
    }

    func host(id: UUID) -> SSHHost? {
        hosts.first { $0.id == id }
    }

    // MARK: - Hosts

    /// Adds or replaces a host and writes any provided secrets to the Keychain.
    /// Passing `nil` for a secret leaves the existing Keychain value untouched;
    /// pass an empty string to clear it.
    func saveHost(
        _ host: SSHHost,
        privateKey: String? = nil,
        passphrase: String? = nil,
        password: String? = nil
    ) {
        if let privateKey {
            keychain.set(privateKey, account: HostSecret.privateKey(host.id))
        }
        if let passphrase {
            keychain.set(passphrase, account: HostSecret.passphrase(host.id))
        }
        if let password {
            keychain.set(password, account: HostSecret.password(host.id))
        }

        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }

        hosts.sort(by: Self.byDisplayName)
        hostStore.save(hosts)
    }

    func removeHost(id: UUID) {
        hosts.removeAll { $0.id == id }
        hostStore.save(hosts)
        for account in HostSecret.all(id) {
            keychain.delete(account: account)
        }
        favorites.removeAll { $0.hostID == id }
        favoritesStore.save(favorites)
    }

    /// Reads a host's secrets from the Keychain to build connection credentials.
    func credentials(for host: SSHHost) -> ResolvedCredentials? {
        switch host.authMethod {
        case .tailscaleSSH:
            return ResolvedCredentials(username: host.username, method: .tailscaleSSH)
        case .password:
            guard let password = keychain.get(account: HostSecret.password(host.id)) else {
                return nil
            }
            return ResolvedCredentials(username: host.username, method: .password(password))
        case .privateKey:
            guard let key = keychain.get(account: HostSecret.privateKey(host.id)) else {
                return nil
            }
            let passphrase = host.hasPassphrase ? keychain.get(account: HostSecret.passphrase(host.id)) : nil
            return ResolvedCredentials(username: host.username, method: .privateKey(text: key, passphrase: passphrase))
        }
    }

    // MARK: - Favorites

    func isFavoriteFile(_ file: RemoteFileReference) -> Bool {
        isFavorite(hostID: file.hostID, path: file.path, kind: .file)
    }

    func toggleFavoriteFile(_ file: RemoteFileReference) {
        toggleFavorite(hostID: file.hostID, path: file.path, title: file.title, kind: .file)
    }

    func isFavoriteDirectory(hostID: UUID, path: String) -> Bool {
        isFavorite(hostID: hostID, path: path, kind: .directory)
    }

    func toggleFavoriteDirectory(hostID: UUID, path: String, title: String) {
        toggleFavorite(hostID: hostID, path: path, title: title, kind: .directory)
    }

    private func isFavorite(hostID: UUID, path: String, kind: FavoriteItem.Kind) -> Bool {
        favorites.contains { $0.hostID == hostID && $0.path == path && $0.kind == kind }
    }

    private func toggleFavorite(hostID: UUID, path: String, title: String, kind: FavoriteItem.Kind) {
        if let index = favorites.firstIndex(where: { $0.hostID == hostID && $0.path == path && $0.kind == kind }) {
            favorites.remove(at: index)
        } else {
            favorites.append(FavoriteItem(hostID: hostID, path: path, title: title, kind: kind, createdAt: Date()))
        }
        favoritesStore.save(favorites)
    }

    private static func byDisplayName(_ lhs: SSHHost, _ rhs: SSHHost) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}
