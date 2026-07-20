import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var activeSheet: ActiveSheet?
    @State private var hostStatus: [UUID: HostStatus] = [:]

    private enum ActiveSheet: Identifiable {
        case add
        case edit(SSHHost)
        case settings
        case record

        var id: String {
            switch self {
            case .add: "add"
            case let .edit(host): "edit-\(host.id.uuidString)"
            case .settings: "settings"
            case .record: "record"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.hosts.isEmpty {
                    emptyState
                } else {
                    mainList
                }
            }
            .navigationTitle("Helm")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .record
                    } label: {
                        Image(systemName: "waveform.badge.mic")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .add
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .add:
                    HostEditorView(host: nil)
                case let .edit(host):
                    HostEditorView(host: host)
                case .settings:
                    SettingsView()
                case .record:
                    RecorderView()
                }
            }
            .task(id: hostsKey) {
                await probeHosts()
            }
        }
    }

    private var hostsKey: String {
        appState.hosts.map { "\($0.id.uuidString):\($0.hostname):\($0.username)" }.joined(separator: "|")
    }

    private var mainList: some View {
        List {
            if !appState.favorites.isEmpty {
                Section("Shortcuts") {
                    ForEach(appState.favorites) { favorite in
                        shortcutRow(favorite)
                    }
                }
            }

            Section("Hosts") {
                ForEach(appState.hosts) { host in
                    NavigationLink {
                        FileBrowserView(host: host, path: host.normalizedStartPath, title: host.displayName)
                    } label: {
                        HostRow(host: host, status: hostStatus[host.id] ?? .checking)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            appState.removeHost(id: host.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            activeSheet = .edit(host)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.gray)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func shortcutRow(_ favorite: FavoriteItem) -> some View {
        if let host = appState.host(id: favorite.hostID) {
            NavigationLink {
                switch favorite.kind {
                case .directory:
                    FileBrowserView(host: host, path: favorite.path, title: favorite.title)
                case .file:
                    RemoteDocumentView(
                        host: host,
                        file: RemoteFileReference(hostID: host.id, path: favorite.path, title: favorite.title)
                    )
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: favorite.systemImage)
                        .foregroundStyle(favorite.kind == .directory ? Color.accentColor : .secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(favorite.title).font(.body)
                        Text("\(host.displayName) · \(favorite.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .swipeActions {
                Button(role: .destructive) {
                    removeFavorite(favorite)
                } label: {
                    Label("Remove", systemImage: "star.slash")
                }
            }
        }
    }

    private func removeFavorite(_ favorite: FavoriteItem) {
        switch favorite.kind {
        case .directory:
            appState.toggleFavoriteDirectory(hostID: favorite.hostID, path: favorite.path, title: favorite.title)
        case .file:
            appState.toggleFavoriteFile(RemoteFileReference(hostID: favorite.hostID, path: favorite.path, title: favorite.title))
        }
    }

    private func probeHosts() async {
        for host in appState.hosts {
            if hostStatus[host.id] != .reachable {
                hostStatus[host.id] = .checking
            }
            guard let credentials = appState.credentials(for: host) else {
                hostStatus[host.id] = .unreachable
                continue
            }
            let failure = await SFTPBrowser.shared.warmUp(host: host, credentials: credentials)
            hostStatus[host.id] = HostStatus(failure)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No hosts yet", systemImage: "server.rack")
        } description: {
            Text("Add a machine on your tailnet to browse its Markdown and HTML files over SSH.")
        } actions: {
            Button { activeSheet = .add } label: { Text("Add Host") }
                .buttonStyle(.borderedProminent)
        }
    }
}

enum HostStatus {
    case checking, reachable, unreachable, authFailed, hostNotFound

    /// Derives a host's status from a probe result: nil means it answered.
    init(_ failure: SFTPBrowserError?) {
        switch failure {
        case .none: self = .reachable
        case .authenticationFailed: self = .authFailed
        case .hostNotFound: self = .hostNotFound
        default: self = .unreachable
        }
    }

    var dotLevel: StatusDot.Level {
        switch self {
        case .checking: .idle
        case .reachable: .online
        case .unreachable, .authFailed, .hostNotFound: .offline
        }
    }

    var label: String {
        switch self {
        case .checking: "Checking…"
        case .reachable: "Connected"
        case .unreachable: "Unreachable"
        case .authFailed: "Auth failed"
        case .hostNotFound: "Host not found"
        }
    }

    var labelColor: Color {
        switch self {
        case .checking: .secondary
        case .reachable: .green
        case .unreachable, .authFailed, .hostNotFound: .red
        }
    }
}

private struct HostRow: View {
    let host: SSHHost
    let status: HostStatus

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(host.displayName).font(.headline)
                    StatusDot(level: status.dotLevel)
                }
                Text(host.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(status.labelColor)
            }
        }
        .helmRowInsets()
    }
}
