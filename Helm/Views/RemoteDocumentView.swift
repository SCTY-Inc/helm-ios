import SwiftUI

/// Loads a file over SFTP and renders it in the markdown or HTML reader.
/// Uses the on-disk cache for instant reopen and offline fallback, and pushes
/// in-document relative links onto its own navigation stack.
struct RemoteDocumentView: View {
    @EnvironmentObject private var appState: AppState

    let host: SSHHost
    let file: RemoteFileReference

    @State private var phase: Phase = .loading
    @State private var isOffline = false
    @State private var linkedFile: RemoteFileReference?

    private let cache = DocumentCache.shared

    private enum Phase {
        case loading
        case markdown(String)
        case html(String)
        case failed(String)
    }

    var body: some View {
        content
            .navigationTitle(file.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $linkedFile) { linked in
                RemoteDocumentView(host: host, file: linked)
            }
            .task(id: file.id) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .markdown(text):
            reader {
                MarkdownReaderView(
                    file: file,
                    markdown: text,
                    onOpenDocument: open,
                    onMarkdownSaved: showSavedMarkdown
                )
            }
        case let .html(text):
            reader {
                HTMLReaderView(file: file, html: text, onOpenDocument: open)
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't open file", systemImage: "doc.questionmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        }
    }

    @ViewBuilder
    private func reader<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .safeAreaInset(edge: .top) {
                if isOffline {
                    Label("Offline — showing cached copy", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                }
            }
    }

    /// Opens a relative document link in a pushed reader.
    private func open(_ path: String) {
        let title = (path as NSString).lastPathComponent
        linkedFile = RemoteFileReference(hostID: host.id, path: path, title: title)
    }

    private func load() async {
        isOffline = false

        // Show a cached copy instantly while we try to refresh.
        if case .loading = phase, let cached = cache.text(for: file) {
            render(cached)
        }

        guard let credentials = appState.credentials(for: host) else {
            if !cache.hasCopy(for: file) {
                phase = .failed(SFTPBrowserError.missingCredentials.localizedDescription)
            } else {
                isOffline = true
            }
            return
        }

        do {
            let data = try await SFTPBrowser.shared.readFile(host: host, credentials: credentials, path: file.path)
            guard let text = String(data: data, encoding: .utf8) else {
                phase = .failed(SFTPBrowserError.notReadable.localizedDescription)
                return
            }
            cache.store(text, for: file)
            isOffline = false
            render(text)
        } catch {
            // Fall back to a cached copy if we have one; otherwise surface the error.
            if let cached = cache.text(for: file) {
                isOffline = true
                render(cached)
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func showSavedMarkdown(_ text: String) {
        cache.store(text, for: file)
        phase = .markdown(text)
        isOffline = false
    }

    private func render(_ text: String) {
        switch RemoteFileFormat(path: file.path) {
        case .html:
            phase = .html(text)
        case .markdown, .none:
            phase = .markdown(text)
        }
    }
}
