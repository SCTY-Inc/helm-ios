import Foundation

/// A pointer to a readable file on a specific host. Used by the reader and favorites.
struct RemoteFileReference: Identifiable, Codable, Hashable, Sendable {
    let hostID: UUID
    let path: String
    let title: String

    var id: String { "\(hostID.uuidString)|\(path)" }
}

/// What kind of readable document a path resolves to.
enum RemoteFileFormat: Sendable {
    case markdown
    case html

    init?(path: String) {
        switch (path as NSString).pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd":
            self = .markdown
        case "html", "htm":
            self = .html
        default:
            return nil
        }
    }
}

/// One entry in an SFTP directory listing, already filtered to things Helm shows:
/// directories and readable markdown/HTML files.
struct RemoteFileEntry: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case directory
        case markdown
        case html
    }

    let name: String
    let path: String
    let kind: Kind
    let modified: Date?

    var id: String { path }

    var isDirectory: Bool { kind == .directory }

    var systemImage: String {
        switch kind {
        case .directory: "folder"
        case .markdown: "doc.text"
        case .html: "doc.richtext"
        }
    }

    static func newestFirst(_ lhs: RemoteFileEntry, _ rhs: RemoteFileEntry) -> Bool {
        compare(lhs, rhs, newestFirst: true)
    }

    static func oldestFirst(_ lhs: RemoteFileEntry, _ rhs: RemoteFileEntry) -> Bool {
        compare(lhs, rhs, newestFirst: false)
    }

    private static func compare(
        _ lhs: RemoteFileEntry,
        _ rhs: RemoteFileEntry,
        newestFirst: Bool
    ) -> Bool {
        switch (lhs.modified, rhs.modified) {
        case let (left?, right?):
            if left != right { return newestFirst ? left > right : left < right }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }
}
