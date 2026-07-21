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
    @State private var chronologyOrder: ChronologyOrder = .newest

    private enum ChronologyOrder: String, CaseIterable, Identifiable {
        case newest = "Newest first"
        case oldest = "Oldest first"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .newest: "arrow.down"
            case .oldest: "arrow.up"
            }
        }
    }

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

            Menu {
                Picker("Chronology", selection: $chronologyOrder) {
                    ForEach(ChronologyOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            } label: {
                Label(chronologyOrder.rawValue, systemImage: chronologyOrder.systemImage)
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
                List(sortedEntries(entries)) { entry in
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
            List(sortedSearchResults(results)) { hit in
                NavigationLink {
                    RemoteDocumentView(
                        host: host,
                        file: RemoteFileReference(hostID: host.id, path: hit.path, title: hit.name)
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(hit.name)
                                .font(.body)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if let modified = hit.modified {
                                Text(modified, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(hit.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
            .listStyle(.plain)
        }
    }

    private func sortedEntries(_ entries: [RemoteFileEntry]) -> [RemoteFileEntry] {
        switch chronologyOrder {
        case .newest:
            entries.sorted(by: RemoteFileEntry.newestFirst)
        case .oldest:
            entries.sorted(by: RemoteFileEntry.oldestFirst)
        }
    }

    private func sortedSearchResults(_ results: [SearchHit]) -> [SearchHit] {
        switch chronologyOrder {
        case .newest:
            results.sorted(by: SearchHit.newestFirst)
        case .oldest:
            results.sorted(by: SearchHit.oldestFirst)
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
            phase = .failed(SFTPBrowserError.missingCredentials.localizedDescription)
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
        HStack(spacing: 12) {
            HelmSymbolBadge(
                systemImage: entry.systemImage,
                tint: entry.isDirectory ? .accentColor : .secondary,
                size: 34
            )

            Text(entry.name)
                .font(.body)
                .lineLimit(2)

            Spacer(minLength: 8)

            if let modified = entry.modified {
                Text(modified, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
