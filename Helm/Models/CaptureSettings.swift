import Foundation

/// UserDefaults keys for voice capture preferences. Views bind to these directly
/// via `@AppStorage(CaptureSettingsKey.*)`, matching the app's existing settings
/// idiom (see SettingsView's `helm.readerTextScalePercent`).
enum CaptureSettingsKey {
    /// String, UUID `uuidString` of the default capture host. "" = none.
    static let hostID = "helm.capture.hostID"
    /// String, folder name (relative to the host's start path) captures are saved into.
    static let path = "helm.capture.path"
    /// Bool, whether to clean up transcripts with on-device AI before saving.
    static let cleanupEnabled = "helm.capture.cleanup"
}

/// Resolved defaults for voice capture, read directly from `UserDefaults.standard`.
enum CaptureSettings {
    static let defaultPath = "transcripts"
    private static let legacyDefaultPath = "transcripta"

    /// The UUID of the default capture host, or `nil` if none is set.
    static var defaultHostID: UUID? {
        guard let raw = UserDefaults.standard.string(forKey: CaptureSettingsKey.hostID) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    static func resolvedPath(defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: CaptureSettingsKey.path)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty || raw == legacyDefaultPath {
            return defaultPath
        }
        return raw
    }
}
