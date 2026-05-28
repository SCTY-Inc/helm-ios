import SwiftUI
import UniformTypeIdentifiers

/// Add or edit a host. Mirrors an ~/.ssh/config entry. Secrets are written to the
/// Keychain via AppState and never shown back once saved.
struct HostEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let host: SSHHost?

    @State private var nickname: String
    @State private var hostname: String
    @State private var port: String
    @State private var username: String
    @State private var authMethod: SSHAuthMethod
    @State private var startPath: String

    @State private var privateKey: String = ""
    @State private var passphrase: String = ""
    @State private var password: String = ""
    @State private var isImportingKey = false
    @State private var importError: String?

    init(host: SSHHost?) {
        self.host = host
        _nickname = State(initialValue: host?.nickname ?? "")
        _hostname = State(initialValue: host?.hostname ?? "")
        _port = State(initialValue: host.map { String($0.port) } ?? "22")
        _username = State(initialValue: host?.username ?? "")
        _authMethod = State(initialValue: host?.authMethod ?? .tailscaleSSH)
        _startPath = State(initialValue: host?.startPath ?? ".")
    }

    private var isEditing: Bool { host != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Nickname", text: $nickname)
                        .textInputAutocapitalization(.never)
                    TextField("Hostname or 100.x IP", text: $hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Picker("Method", selection: $authMethod) {
                        Text("Tailscale").tag(SSHAuthMethod.tailscaleSSH)
                        Text("Key").tag(SSHAuthMethod.privateKey)
                        Text("Password").tag(SSHAuthMethod.password)
                    }
                    .pickerStyle(.segmented)

                    switch authMethod {
                    case .tailscaleSSH:
                        Text("No key needed — Tailscale authenticates this device. The host must have Tailscale SSH enabled (green “SSH” badge in the Tailscale admin console).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .privateKey:
                        privateKeySection
                    case .password:
                        SecureField(isEditing ? "Password (leave blank to keep)" : "Password", text: $password)
                    }
                } header: {
                    Text("Authentication")
                }

                Section {
                    TextField("Start directory", text: $startPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Browse from")
                } footer: {
                    Text("Where browsing begins. Use \".\" for the home directory or an absolute path like /home/deploy/wiki.")
                }
            }
            .navigationTitle(isEditing ? "Edit Host" : "Add Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $isImportingKey,
                allowedContentTypes: [.data, .text, .item],
                allowsMultipleSelection: false
            ) { result in
                importKey(result)
            }
        }
    }

    @ViewBuilder
    private var privateKeySection: some View {
        if isEditing && privateKey.isEmpty {
            Text("A key is saved for this host. Paste or import a new one to replace it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Button {
            isImportingKey = true
        } label: {
            Label("Import Key from Files", systemImage: "doc.badge.plus")
        }

        ZStack(alignment: .topLeading) {
            if privateKey.isEmpty {
                Text("-----BEGIN OPENSSH PRIVATE KEY-----")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            TextEditor(text: $privateKey)
                .font(.caption.monospaced())
                .frame(minHeight: 120)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }

        SecureField("Key passphrase (optional)", text: $passphrase)

        if let importError {
            Text(importError)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private var canSave: Bool {
        guard !hostname.trimmingCharacters(in: .whitespaces).isEmpty,
              !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }

        if isEditing {
            return true
        }

        switch authMethod {
        case .tailscaleSSH: return true
        case .privateKey: return !privateKey.isEmpty
        case .password: return !password.isEmpty
        }
    }

    private func importKey(_ result: Result<[URL], Error>) {
        importError = nil
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let contents = try String(contentsOf: url, encoding: .utf8)
            privateKey = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            importError = "Couldn't read that key file."
        }
    }

    private func save() {
        let trimmedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPassphrase: Bool
        if authMethod == .privateKey {
            hasPassphrase = privateKey.isEmpty ? (host?.hasPassphrase ?? false) : !trimmedPassphrase.isEmpty
        } else {
            hasPassphrase = false
        }

        let newHost = SSHHost(
            id: host?.id ?? UUID(),
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            authMethod: authMethod,
            hasPassphrase: hasPassphrase,
            startPath: startPath
        )

        appState.saveHost(
            newHost,
            privateKey: authMethod == .privateKey && !privateKey.isEmpty ? privateKey : nil,
            passphrase: authMethod == .privateKey && !privateKey.isEmpty ? trimmedPassphrase : nil,
            password: authMethod == .password && !password.isEmpty ? password : nil
        )

        dismiss()
    }
}
