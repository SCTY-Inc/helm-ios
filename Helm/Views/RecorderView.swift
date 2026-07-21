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
                            .disabled(isDismissDisabled)
                    }
                }
        }
        .interactiveDismissDisabled(isDismissDisabled)
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

    private var isDismissDisabled: Bool {
        guard let session else { return true }
        switch session.phase {
        case .preparing, .recording, .transcribing, .cleaning, .saving:
            return true
        case .idle, .review, .done, .failed:
            return false
        }
    }

    // MARK: - Idle

    private func idleView(_ session: CaptureSession) -> some View {
        VStack(spacing: 18) {
            Spacer()

            Button {
                Task { await session.startRecording() }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Color.accentColor, in: .circle)
                    .shadow(color: Color.accentColor.opacity(0.22), radius: 18, y: 8)
            }
            .buttonStyle(HelmPressableButtonStyle())
            .accessibilityLabel("Start Recording")

            Text(targetFile == nil ? "Capture a voice note" : "Describe the change")
                .font(.title3.bold())

            Text(targetFile == nil
                 ? "Helm transcribes privately on this device, then lets you review before saving."
                 : "Your recording becomes a reviewable request attached to this page.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Recording

    private func recordingView(_ session: CaptureSession) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Label("Recording", systemImage: "waveform")
                .font(.subheadline.bold())
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.red.opacity(0.1), in: .capsule)

            Text(formattedElapsed(session.recorder.elapsed))
                .font(.system(size: 48, weight: .medium, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            VStack(alignment: .leading, spacing: 8) {
                Text("INPUT LEVEL")
                    .font(.caption2.bold())
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                levelIndicator(session.recorder.averagePower)
                    .frame(height: 8)
            }
            .frame(maxWidth: 300)

            Button {
                Task { await session.stopAndProcess() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Color.red, in: .circle)
                    .shadow(color: Color.red.opacity(0.2), radius: 16, y: 7)
            }
            .buttonStyle(HelmPressableButtonStyle())
            .accessibilityLabel("Stop Recording")

            Text("Tap stop when you’re finished")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
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
                .controlSize(.large)
            Text(label)
                .font(.headline)
            Text("Keep Helm open while this finishes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }

    // MARK: - Review

    private func reviewView(_ session: CaptureSession) -> some View {
        VStack(spacing: 0) {
            Label(destinationLabel(filename: session.draftFilename), systemImage: "arrow.up.doc")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial)

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
            HelmSymbolBadge(systemImage: "checkmark", tint: .green, size: 64)
            Text(targetFile == nil ? "Voice note saved" : "Change request queued")
                .font(.title3.bold())
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
            HelmSymbolBadge(systemImage: "exclamationmark.triangle.fill", tint: .red, size: 64)
            Text("Something went wrong")
                .font(.title3.bold())
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
