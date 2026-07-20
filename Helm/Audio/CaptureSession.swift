import Foundation
import Observation

/// Orchestrates one voice-note capture: record, transcribe, optionally clean
/// up on-device, then write the result to the default capture host over SFTP.
@MainActor @Observable
final class CaptureSession {

    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case transcribing
        case cleaning
        case review
        case saving
        case done(path: String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var draftMarkdown: String = ""
    private(set) var draftFilename: String = ""

    let recorder = AudioRecorder()

    private let appState: AppState
    private let targetFile: RemoteFileReference?
    private let transcription = TranscriptionService()
    private var startDate: Date?
    private var hasMicrophonePermission = false
    private var hasSpeechPermission = false

    init(appState: AppState, targetFile: RemoteFileReference? = nil) {
        self.appState = appState
        self.targetFile = targetFile
    }

    var isChangeRequest: Bool { targetFile != nil }

    // MARK: - Recording

    func prepareForRecording() async {
        guard phase == .idle else { return }
        phase = .preparing

        guard await recorder.requestPermission() else {
            phase = .failed("Microphone access is off. Enable it in Settings.")
            return
        }
        hasMicrophonePermission = true

        guard await transcription.requestAuthorization() else {
            phase = .failed("Speech recognition access is off. Enable it in Settings.")
            return
        }
        hasSpeechPermission = true

        phase = .idle
    }

    func startRecording() async {
        if !hasMicrophonePermission {
            guard await recorder.requestPermission() else {
                phase = .failed("Microphone access is off. Enable it in Settings.")
                return
            }
            hasMicrophonePermission = true
        }
        if !hasSpeechPermission {
            guard await transcription.requestAuthorization() else {
                phase = .failed("Speech recognition access is off. Enable it in Settings.")
                return
            }
            hasSpeechPermission = true
        }

        do {
            try recorder.start(
                configureTranscription: { [transcription] sampleRate in
                    transcription.startTranscription(sampleRate: sampleRate)
                },
                onSamples: { [transcription] samples in
                    transcription.appendAudio(samples: samples)
                }
            )
            if let error = transcription.lastError {
                recorder.stop()
                phase = .failed(error)
                return
            }
            startDate = Date.now
            phase = .recording
            DebugLog.write("voice recording started live-buffer")
        } catch {
            _ = await transcription.finishTranscription()
            phase = .failed("Couldn't start recording: \(error.localizedDescription)")
        }
    }

    func stopAndProcess() async {
        recorder.stop()
        guard let startDate else {
            phase = .failed("No recording to process.")
            return
        }
        let recordedDuration = Date().timeIntervalSince(startDate)
        DebugLog.write("voice recording stopped duration=\(String(format: "%.1f", recordedDuration))s")

        phase = .transcribing
        let snapshot = await transcription.finishTranscription()
        let endDate = Date.now
        let title = autoTitle(from: snapshot.fullText)
        let formatter = TranscriptFormatter()

        let transcriptDocument = formatter.makeDocument(
            title: title,
            startTime: startDate,
            endTime: endDate,
            fullText: snapshot.fullText,
            lines: snapshot.lines
        )

        var instruction = snapshot.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if instruction.isEmpty {
            instruction = "(No transcript)"
        }
        if shouldCleanUp() {
            phase = .cleaning
            if let cleaned = await cleanedTranscript(rawTranscript: snapshot.fullText, title: transcriptDocument.title) {
                instruction = cleaned
            }
        }

        if let targetFile, let format = RemoteFileFormat(path: targetFile.path) {
            let request = WikiChangeRequestFormatter().makeDocument(
                targetPath: targetFile.path,
                targetTitle: targetFile.title,
                targetFormat: format,
                instruction: instruction,
                requestedAt: startDate
            )
            draftFilename = request.filename
            draftMarkdown = request.markdown
        } else if instruction != snapshot.fullText.trimmingCharacters(in: .whitespacesAndNewlines) {
            let cleanedDocument = formatter.makeDocument(
                title: transcriptDocument.title,
                startTime: startDate,
                endTime: endDate,
                body: instruction
            )
            draftFilename = cleanedDocument.filename
            draftMarkdown = cleanedDocument.markdown
        } else {
            draftFilename = transcriptDocument.filename
            draftMarkdown = transcriptDocument.markdown
        }

        phase = .review
    }

    // MARK: - Save / discard

    func save() async {
        phase = .saving

        let hostID = targetFile?.hostID ?? CaptureSettings.defaultHostID
        guard
            let hostID,
            let host = appState.host(id: hostID),
            let credentials = appState.credentials(for: host)
        else {
            phase = .failed(targetFile == nil
                ? "Set a default capture host in Settings first."
                : "The page's wiki connection is unavailable.")
            return
        }

        let relativeDirectory = targetFile == nil
            ? CaptureSettings.resolvedPath()
            : ".helm/requests/pending"
        let directory = host.path(relativeToStart: relativeDirectory)
        let data = Data(draftMarkdown.utf8)

        do {
            let written = try await SFTPBrowser.shared.writeFile(
                host: host,
                credentials: credentials,
                directory: directory,
                filename: draftFilename,
                data: data
            )
            phase = .done(path: written)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func discard() {
        reset()
    }

    func reset() {
        phase = .idle
        draftMarkdown = ""
        draftFilename = ""
        startDate = nil
    }

    // MARK: - Cleanup

    private func shouldCleanUp() -> Bool {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: CaptureSettingsKey.cleanupEnabled) == nil
            ? true
            : defaults.bool(forKey: CaptureSettingsKey.cleanupEnabled)
        guard enabled else { return false }

        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    private func cleanedTranscript(rawTranscript: String, title: String) async -> String? {
        guard #available(iOS 26.0, *) else { return nil }
        return await TranscriptCleaner.clean(rawTranscript: rawTranscript, title: title.isEmpty ? "Voice note" : title)
    }

    private func autoTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(10)
        var title = words.joined(separator: " ")
        if title.count > 60 {
            title = String(title.prefix(57)) + "..."
        }
        return title.isEmpty ? "Voice note" : title
    }
}
