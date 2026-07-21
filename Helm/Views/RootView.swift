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
                    Button("Settings", systemImage: "gearshape") {
                        activeSheet = .settings
                    }
                }
                if !appState.hosts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Record Voice Note", systemImage: "waveform.badge.mic") {
                            activeSheet = .record
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Host", systemImage: "plus") {
                        activeSheet = .add
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
                    HelmSymbolBadge(
                        systemImage: favorite.systemImage,
                        tint: favorite.kind == .directory ? .accentColor : .secondary
                    )
                    VStack(alignment: .leading, spacing: 2) {
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
            Label("Your wiki, anywhere", systemImage: "server.rack")
        } description: {
            Text("Connect a machine on your tailnet to browse, read, and capture notes over SSH.")
        } actions: {
            Button("Add Your First Host", systemImage: "plus") {
                activeSheet = .add
            }
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

    var systemImage: String {
        switch self {
        case .checking: "clock"
        case .reachable: "checkmark.circle.fill"
        case .unreachable: "wifi.slash"
        case .authFailed: "lock.trianglebadge.exclamationmark"
        case .hostNotFound: "questionmark.circle"
        }
    }
}

private struct HostRow: View {
    let host: SSHHost
    let status: HostStatus

    var body: some View {
        HStack(spacing: 12) {
            HelmSymbolBadge(systemImage: "server.rack", tint: .secondary, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(host.displayName)
                    .font(.headline)
                Text(host.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Label(status.label, systemImage: status.systemImage)
                    .font(.caption)
                    .foregroundStyle(status.labelColor)
            }
        }
        .helmRowInsets()
    }
}
