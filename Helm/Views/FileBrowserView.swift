import SwiftUI

/// Browses one directory on a host over SFTP. Folders push another browser;
/// markdown/HTML files push the reader. Used recursively for deep navigation.
struct FileBrowserView: View {
    @EnvironmentObject private var appState: AppState

    let host: SSHHost
    let path: String
    let title: String

    @State private var phase: Phase = .loading
    @State private var searchText = ""
    @State private var searchResults: [SearchHit]?
    @State private var isSearching = false

    private enum Phase {
        case loading
        case loaded([RemoteFileEntry])
        case failed(String)
    }

    var body: some View {
        Group {
            if let searchResults {
                searchResultsList(searchResults)
            } else {
                listing
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                appState.toggleFavoriteDirectory(hostID: host.id, path: path, title: title)
            } label: {
                let isFavorite = appState.isFavoriteDirectory(hostID: host.id, path: path)
                Label(
                    isFavorite ? "Remove Shortcut" : "Add Shortcut",
                    systemImage: isFavorite ? "star.fill" : "star"
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search this folder")
        .onSubmit(of: .search) {
            Task { await runSearch() }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty { searchResults = nil }
        }
        .task(id: path) {
            await load()
        }
    }

    @ViewBuilder
    private var listing: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(entries):
            if entries.isEmpty {
                ContentUnavailableView(
                    "No readable files",
                    systemImage: "folder",
                    description: Text("This folder has no sub-folders or Markdown/HTML files.")
                )
            } else {
                List(entries) { entry in
                    row(for: entry)
                }
                .listStyle(.plain)
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't open folder", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        }
    }

    @ViewBuilder
    private func searchResultsList(_ results: [SearchHit]) -> some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "magnifyingglass",
                description: Text("No Markdown or HTML files under this folder contain “\(searchText)”.")
            )
        } else {
            List(results) { hit in
                NavigationLink {
                    RemoteDocumentView(
                        host: host,
                        file: RemoteFileReference(hostID: host.id, path: hit.path, title: hit.name)
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.name).font(.body)
                        Text(hit.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        guard let credentials = appState.credentials(for: host) else {
            searchResults = []
            return
        }

        isSearching = true
        searchResults = []
        do {
            searchResults = try await SFTPBrowser.shared.search(
                host: host,
                credentials: credentials,
                query: query,
                path: path
            )
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    @ViewBuilder
    private func row(for entry: RemoteFileEntry) -> some View {
        if entry.isDirectory {
            NavigationLink {
                FileBrowserView(host: host, path: entry.path, title: entry.name)
            } label: {
                FileRow(entry: entry)
            }
        } else {
            NavigationLink {
                RemoteDocumentView(
                    host: host,
                    file: RemoteFileReference(hostID: host.id, path: entry.path, title: entry.name)
                )
            } label: {
                FileRow(entry: entry)
            }
        }
    }

    private func load() async {
        phase = .loading

        guard let credentials = appState.credentials(for: host) else {
            phase = .failed(SFTPBrowserError.missingCredentials.localizedDescription ?? "Missing credentials.")
            return
        }

        do {
            let entries = try await SFTPBrowser.shared.list(host: host, credentials: credentials, path: path)
            phase = .loaded(entries)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct FileRow: View {
    let entry: RemoteFileEntry

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.systemImage)
                .font(.title3)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                .frame(width: 26)

            Text(entry.name)
                .font(.body)

            Spacer()

            if let modified = entry.modified {
                Text(modified, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
