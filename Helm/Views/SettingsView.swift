import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @AppStorage("helm.readerTextScalePercent") private var textScalePercent: Int = 100
    @AppStorage(CaptureSettingsKey.hostID) private var captureHostID: String = ""
    @AppStorage(CaptureSettingsKey.path) private var capturePath: String = CaptureSettings.defaultPath
    @AppStorage(CaptureSettingsKey.cleanupEnabled) private var captureCleanupEnabled: Bool = true

    @State private var cacheBytes = 0

    private let cache = DocumentCache.shared
    private let scaleRange = 80...160
    private let scaleStep = 10

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $textScalePercent, in: scaleRange, step: scaleStep) {
                        HStack {
                            Text("Text Size")
                            Spacer()
                            Text("\(textScalePercent)%").foregroundStyle(.secondary)
                        }
                    }
                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.system(size: 17 * CGFloat(textScalePercent) / 100))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Reading")
                }

                Section {
                    Button(role: .destructive) {
                        cache.clearAll()
                        cacheBytes = 0
                    } label: {
                        HStack {
                            Text("Clear Cached Files")
                            Spacer()
                            Text(cacheLabel).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(cacheBytes == 0)
                } header: {
                    Text("Offline Cache")
                } footer: {
                    Text("Opened files are cached for instant reopen and offline reading.")
                }

                Section {
                    Picker("Default Host", selection: $captureHostID) {
                        Text("None").tag("")
                        ForEach(appState.hosts) { host in
                            Text(host.displayName).tag(host.id.uuidString)
                        }
                    }
                    TextField("Folder", text: $capturePath)
                    Toggle("Clean up with on-device AI", isOn: $captureCleanupEnabled)
                } header: {
                    Text("Voice Capture")
                } footer: {
                    Text("Voice notes default to the transcripts folder. Cleanup requires iOS 26 / Apple Intelligence; otherwise the raw transcript is saved.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                cacheBytes = cache.totalSizeBytes()
                capturePath = CaptureSettings.resolvedPath()
            }
        }
    }

    private var cacheLabel: String {
        cacheBytes == 0 ? "Empty" : ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)
    }
}
