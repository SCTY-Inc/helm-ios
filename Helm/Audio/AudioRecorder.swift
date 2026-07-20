import Foundation
import AVFoundation
import Observation
import Darwin

/// Captures microphone audio through `AVAudioEngine`.
@MainActor @Observable
final class AudioRecorder {

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var averagePower: Float = -60

    private var audioEngine: AVAudioEngine?
    private var meterTimer: Timer?
    private var startedAt: Date?

    // MARK: - Permission

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Start / Stop

    func start(
        configureTranscription: (Double) -> Void,
        onSamples: @escaping @MainActor @Sendable ([Int16]) -> Void
    ) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw AudioRecorderError.failedToStart
        }

        configureTranscription(format.sampleRate)

        AudioTapInstaller.install(
            on: inputNode,
            format: format,
            recorder: self,
            onSamples: onSamples
        )

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }

        audioEngine = engine
        startedAt = Date.now
        elapsed = 0
        averagePower = -60
        isRecording = true
        startMeterTimer()
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        stopMeterTimer()
        isRecording = false
        startedAt = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Metering

    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateElapsed()
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func updateElapsed() {
        guard let startedAt else { return }
        elapsed = Date.now.timeIntervalSince(startedAt)
    }

    fileprivate func receive(
        samples: [Int16],
        power: Float,
        onSamples: @MainActor @Sendable ([Int16]) -> Void
    ) {
        averagePower = power
        onSamples(samples)
    }

}

enum AudioRecorderError: Error {
    case failedToStart
}

enum AudioTapInstaller {
    nonisolated static func install(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        recorder: AudioRecorder,
        onSamples: @escaping @MainActor @Sendable ([Int16]) -> Void
    ) {
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: format,
            block: makeHandler(recorder: recorder, onSamples: onSamples)
        )
    }

    nonisolated static func makeHandler(
        recorder: AudioRecorder?,
        onSamples: @escaping @MainActor @Sendable ([Int16]) -> Void
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { [weak recorder] buffer, _ in
            let samples = AudioSampleConverter.samples(from: buffer)
            let power = AudioSampleMeter.averagePower(buffer)
            guard !samples.isEmpty else { return }

            Task { @MainActor [weak recorder] in
                recorder?.receive(samples: samples, power: power, onSamples: onSamples)
            }
        }
    }
}

private enum AudioSampleConverter {
    nonisolated static func samples(from buffer: AVAudioPCMBuffer) -> [Int16] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }

        if let channelData = buffer.int16ChannelData {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        if let channelData = buffer.floatChannelData {
            return UnsafeBufferPointer(start: channelData[0], count: frameCount).map { sample in
                let normalized = max(-1, min(1, sample))
                return Int16(normalized * Float(Int16.max))
            }
        }

        return []
    }
}

private enum AudioSampleMeter {
    nonisolated static func averagePower(_ buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return -60 }

        if let channelData = buffer.floatChannelData {
            let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)
            let meanSquare = samples.reduce(Double(0)) { partial, sample in
                let normalized = Double(max(-1, min(1, sample)))
                return partial + normalized * normalized
            } / Double(samples.count)
            return decibels(meanSquare: meanSquare)
        }

        if let channelData = buffer.int16ChannelData {
            let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)
            let meanSquare = samples.reduce(Double(0)) { partial, sample in
                let normalized = Double(sample) / Double(Int16.max)
                return partial + normalized * normalized
            } / Double(samples.count)
            return decibels(meanSquare: meanSquare)
        }

        return -60
    }

    nonisolated private static func decibels(meanSquare: Double) -> Float {
        guard meanSquare > 0 else { return -60 }
        let rms = sqrt(meanSquare)
        return max(-60, Float(20 * Darwin.log10(rms)))
    }
}
