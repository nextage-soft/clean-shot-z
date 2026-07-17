import AppKit
import CoreGraphics

/// Screen Recording (TCC) permission helper.
/// macOS shows the system prompt once; afterwards the user must enable the app in
/// System Settings > Privacy & Security > Screen & System Audio Recording, then relaunch.
@MainActor
enum ScreenRecordingPermission {
    static func isGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestIfNeeded() {
        guard !isGranted() else { return }
        CGRequestScreenCaptureAccess()
    }

    /// Returns true when capture can proceed; otherwise guides the user to System Settings.
    @discardableResult
    static func ensureGrantedOrExplain() -> Bool {
        if isGranted() { return true }
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = "CleanShot Z cần quyền Screen Recording"
        alert.informativeText = "Mở System Settings → Privacy & Security → Screen & System Audio Recording, bật CleanShot Z rồi mở lại app."
        alert.addButton(withTitle: "Mở System Settings")
        alert.addButton(withTitle: "Để sau")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
