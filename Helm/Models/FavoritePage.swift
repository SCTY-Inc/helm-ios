import Foundation

/// A saved shortcut — a file (opens in the reader) or a folder (jumps into the
/// browser at that path) — across all hosts.
struct FavoriteItem: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case file
        case directory
    }

    let hostID: UUID
    let path: String
    let title: String
    let kind: Kind
    let createdAt: Date

    var id: String { "\(kind.rawValue)|\(hostID.uuidString)|\(path)" }

    var systemImage: String {
        kind == .directory ? "folder.fill" : "doc.text.fill"
    }
}

@MainActor
protocol FavoritesStore {
    func load() -> [FavoriteItem]
    func save(_ favorites: [FavoriteItem])
}

struct UserDefaultsFavoritesStore: FavoritesStore {
    private let key = "helm.favorites.v3"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [FavoriteItem] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([FavoriteItem].self, from: data)) ?? []
    }

    func save(_ favorites: [FavoriteItem]) {
        do {
            let data = try JSONEncoder().encode(favorites)
            defaults.set(data, forKey: key)
        } catch {
            defaults.removeObject(forKey: key)
        }
    }
}
