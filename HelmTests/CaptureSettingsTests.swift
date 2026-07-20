import Foundation
import Testing
@testable import Helm

@Suite("CaptureSettings")
struct CaptureSettingsTests {
    @Test("Voice captures default to transcripts")
    func defaultPathIsTranscripts() {
        #expect(CaptureSettings.defaultPath == "transcripts")
    }

    @Test("Empty saved path resolves to transcripts")
    func emptySavedPathResolvesToDefault() throws {
        let defaults = try makeDefaults()
        defaults.set("", forKey: CaptureSettingsKey.path)

        #expect(CaptureSettings.resolvedPath(defaults: defaults) == "transcripts")
    }

    @Test("Legacy transcripta path resolves to transcripts")
    func legacyTypoResolvesToTranscripts() throws {
        let defaults = try makeDefaults()
        defaults.set("transcripta", forKey: CaptureSettingsKey.path)

        #expect(CaptureSettings.resolvedPath(defaults: defaults) == "transcripts")
    }

    @Test("Custom saved path is preserved")
    func customSavedPathIsPreserved() throws {
        let defaults = try makeDefaults()
        defaults.set("notes/transcripts", forKey: CaptureSettingsKey.path)

        #expect(CaptureSettings.resolvedPath(defaults: defaults) == "notes/transcripts")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "helm-capture-settings-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
