import Foundation

/// UserDefaults-backed app settings. M1 keeps this minimal — a Settings UI arrives later.
enum SettingsStore {
    private static let defaults = UserDefaults.standard

    /// Directory screenshots are saved into. Default: ~/Desktop (same as CleanShot X default).
    static var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: "saveDirectoryPath") {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set { defaults.set(newValue.path, forKey: "saveDirectoryPath") }
    }

    /// File name prefix, e.g. "CleanShot Z 2026-07-14 at 10.30.45.png"
    static var fileNamePrefix: String {
        defaults.string(forKey: "fileNamePrefix") ?? "CleanShot Z"
    }

    /// Copy captured image to clipboard right after capture.
    static var copyToClipboardAfterCapture: Bool {
        defaults.object(forKey: "copyToClipboardAfterCapture") as? Bool ?? true
    }

    /// Show the floating Quick Access thumbnail after capture.
    static var showQuickAccessOverlay: Bool {
        defaults.object(forKey: "showQuickAccessOverlay") as? Bool ?? true
    }

    /// Auto-hide Quick Access cards after a delay (hovering pauses the timer).
    static var quickAccessAutoDismiss: Bool {
        defaults.object(forKey: "quickAccessAutoDismiss") as? Bool ?? true
    }

    /// Seconds before a Quick Access card hides itself.
    static var quickAccessDismissSeconds: Double {
        let value = defaults.object(forKey: "quickAccessDismissSeconds") as? Double ?? 15
        return min(max(value, 5), 120)
    }

    /// Output format for saved captures (file-size vs compatibility trade-off).
    static var imageFormat: CaptureImageFormat {
        CaptureImageFormat(rawValue: defaults.string(forKey: "imageFormat") ?? "") ?? .png
    }

    /// Lossy quality for JPEG/HEIC (ignored for PNG).
    static var imageQuality: Double {
        let value = defaults.object(forKey: "imageQuality") as? Double ?? 0.85
        return min(max(value, 0.3), 1.0)
    }

    /// Save Retina (2x) captures at 1x pixel size — ~4× smaller files.
    static var downscaleRetinaTo1x: Bool {
        defaults.object(forKey: "downscaleRetinaTo1x") as? Bool ?? false
    }
}
