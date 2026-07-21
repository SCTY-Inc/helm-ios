import Foundation
import Testing
@testable import Helm

@Suite("Wiki change requests")
struct WikiChangeRequestTests {
    @Test("Request records its target and remains readable by an agent")
    func requestDocument() {
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        let request = WikiChangeRequestFormatter().makeDocument(
            targetPath: "/home/deploy/wiki/pages/work/helm.html",
            targetTitle: "Helm",
            targetFormat: .html,
            instruction: "Move the chronology controls above search.",
            requestedAt: date
        )

        #expect(request.filename.hasSuffix("_helm-change-request.md"))
        #expect(request.markdown.contains("type: \"helm_change_request\""))
        #expect(request.markdown.contains("status: \"pending\""))
        #expect(request.markdown.contains("target_path: \"/home/deploy/wiki/pages/work/helm.html\""))
        #expect(request.markdown.contains("target_format: \"html\""))
        #expect(request.markdown.contains("Move the chronology controls above search."))
        #expect(request.markdown.contains("locate and edit its canonical source"))
    }

    @Test("YAML values are escaped")
    func yamlEscaping() {
        let request = WikiChangeRequestFormatter().makeDocument(
            targetPath: "wiki/\"quoted\".md",
            targetTitle: "Quoted",
            targetFormat: .markdown,
            instruction: "Use \\\"clear\\\" wording.",
            requestedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(request.markdown.contains("target_path: \"wiki/\\\"quoted\\\".md\""))
    }

    @Test("Host-relative paths resolve under the configured wiki root")
    func hostRelativePath() {
        let host = SSHHost(
            nickname: "Wiki",
            hostname: "wiki.example.ts.net",
            username: "ali",
            authMethod: .tailscaleSSH,
            startPath: "/home/deploy/wiki"
        )

        #expect(host.path(relativeToStart: "transcripts") == "/home/deploy/wiki/transcripts")
        #expect(host.path(relativeToStart: ".helm/requests/pending") == "/home/deploy/wiki/.helm/requests/pending")
        #expect(host.path(relativeToStart: "/tmp/notes") == "/tmp/notes")
    }

    @Test("Search hits sort newest first and leave unknown dates last")
    func chronologicalSearchSort() {
        let older = SearchHit(path: "older.md", name: "older.md", modified: Date(timeIntervalSince1970: 10))
        let newer = SearchHit(path: "newer.md", name: "newer.md", modified: Date(timeIntervalSince1970: 20))
        let unknown = SearchHit(path: "unknown.md", name: "unknown.md", modified: nil)

        #expect([older, unknown, newer].sorted(by: SearchHit.newestFirst).map(\.path) == ["newer.md", "older.md", "unknown.md"])
        #expect([older, unknown, newer].sorted(by: SearchHit.oldestFirst).map(\.path) == ["older.md", "newer.md", "unknown.md"])
    }

    @Test("Directory entries support chronological browsing in both directions")
    func chronologicalDirectorySort() {
        let older = RemoteFileEntry(
            name: "older.md",
            path: "/wiki/older.md",
            kind: .markdown,
            modified: Date(timeIntervalSince1970: 10)
        )
        let newerFolder = RemoteFileEntry(
            name: "newer-folder",
            path: "/wiki/newer-folder",
            kind: .directory,
            modified: Date(timeIntervalSince1970: 20)
        )
        let unknown = RemoteFileEntry(
            name: "unknown.md",
            path: "/wiki/unknown.md",
            kind: .markdown,
            modified: nil
        )

        let entries = [older, unknown, newerFolder]
        #expect(entries.sorted(by: RemoteFileEntry.newestFirst).map(\.path) == ["/wiki/newer-folder", "/wiki/older.md", "/wiki/unknown.md"])
        #expect(entries.sorted(by: RemoteFileEntry.oldestFirst).map(\.path) == ["/wiki/older.md", "/wiki/newer-folder", "/wiki/unknown.md"])
    }
}
