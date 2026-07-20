import SwiftUI

/// Voice-note capture sheet: record, transcribe on-device, review/edit the
/// resulting Markdown, then save it to the default capture host over SFTP.
struct RecorderView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var targetFile: RemoteFileReference?

    @State private var session: CaptureSession?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(targetFile == nil ? "Voice Note" : "Suggest Change")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .task {
            if session == nil {
                let session = CaptureSession(appState: appState, targetFile: targetFile)
                self.session = session
                await session.prepareForRecording()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session {
            switch session.phase {
            case .idle:
                idleView(session)
            case .preparing:
                progressView("Preparing…")
            case .recording:
                recordingView(session)
            case .transcribing:
                progressView("Transcribing…")
            case .cleaning:
                progressView("Cleaning up…")
            case .review:
                reviewView(session)
            case .saving:
                progressView("Saving…")
            case let .done(path):
                doneView(path: path)
            case let .failed(message):
                failedView(session, message: message)
            }
        } else {
            progressView("Preparing…")
        }
    }

    // MARK: - Idle

    private func idleView(_ session: CaptureSession) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Button {
                Task { await session.startRecording() }
            } label: {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 88))
            }
            .buttonStyle(.plain)
            Text(targetFile == nil ? "Tap to start recording" : "Describe what should change")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Recording

    private func recordingView(_ session: CaptureSession) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Text(formattedElapsed(session.recorder.elapsed))
                .font(.system(size: 44, weight: .medium, design: .monospaced))
                .monospacedDigit()

            levelIndicator(session.recorder.averagePower)
                .frame(height: 8)
                .padding(.horizontal, 40)

            Button {
                Task { await session.stopAndProcess() }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding()
    }

    private func levelIndicator(_ averagePower: Float) -> some View {
        // averagePower is in dBFS, roughly -60 (silence) to 0 (peak).
        let normalized = max(0, min(1, (averagePower + 60) / 60))
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(normalized))
            }
        }
    }

    private func formattedElapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Progress

    private func progressView(_ label: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text(label).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Review

    private func reviewView(_ session: CaptureSession) -> some View {
        VStack(spacing: 0) {
            Text(destinationLabel(filename: session.draftFilename))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            TextEditor(text: Binding(
                get: { session.draftMarkdown },
                set: { session.draftMarkdown = $0 }
            ))
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)

            Divider()

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    session.discard()
                } label: {
                    Text("Discard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await session.save() }
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func destinationLabel(filename: String) -> String {
        let hostID = targetFile?.hostID ?? CaptureSettings.defaultHostID
        guard let hostID, let host = appState.host(id: hostID) else {
            return filename
        }
        let relativeDirectory = targetFile == nil
            ? CaptureSettings.resolvedPath()
            : ".helm/requests/pending"
        return "\(host.displayName):\(host.path(relativeToStart: relativeDirectory))/\(filename)"
    }

    // MARK: - Done / Failed

    private func doneView(path: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(targetFile == nil ? "Saved" : "Request queued").font(.headline)
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
        }
        .padding()
    }

    private func failedView(_ session: CaptureSession, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            HStack(spacing: 12) {
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Try Again") { session.reset() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.bottom)
        }
        .padding()
    }
}
