import Foundation
import Crypto

/// On-disk cache of fetched document text, keyed by host + path. Lets a file
/// reopen instantly and stay readable when the host is unreachable (offline).
struct DocumentCache: Sendable {
    static let shared = DocumentCache()

    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("HelmDocumentCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func text(for reference: RemoteFileReference) -> String? {
        try? String(contentsOf: fileURL(for: reference), encoding: .utf8)
    }

    func hasCopy(for reference: RemoteFileReference) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: reference).path)
    }

    func store(_ text: String, for reference: RemoteFileReference) {
        try? text.write(to: fileURL(for: reference), atomically: true, encoding: .utf8)
    }

    func remove(for reference: RemoteFileReference) {
        try? FileManager.default.removeItem(at: fileURL(for: reference))
    }

    func clearAll() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Total bytes of cached documents, for the Settings readout.
    func totalSizeBytes() -> Int {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return contents.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func fileURL(for reference: RemoteFileReference) -> URL {
        let key = "\(reference.hostID.uuidString)|\(reference.path)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }
}
