import AVFoundation
import Foundation
import Testing
@testable import Helm

@Suite("Audio recorder")
struct AudioRecorderTests {
    @Test("Audio tap handler can deliver samples from a realtime queue", .timeLimit(.minutes(1)))
    @MainActor
    func tapHandlerExecutor() async throws {
        let recorder = AudioRecorder()
        let samples: [Int16] = await withCheckedContinuation { continuation in
            let handler = AudioTapInstaller.makeHandler(recorder: recorder) { samples in
                continuation.resume(returning: samples)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                guard
                    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4),
                    let channel = buffer.floatChannelData?[0]
                else {
                    return
                }

                buffer.frameLength = 4
                channel[0] = -1
                channel[1] = -0.5
                channel[2] = 0.5
                channel[3] = 1
                handler(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
            }
        }

        #expect(samples.count == 4)
        #expect(samples.first == Int16.min + 1)
        #expect(samples.last == Int16.max)
    }
}
