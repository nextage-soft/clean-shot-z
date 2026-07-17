import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarMenuController?
    private let captureCoordinator = CaptureCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarMenuController(coordinator: captureCoordinator)
        HotkeyManager.register(coordinator: captureCoordinator)
        // Trigger the Screen Recording permission prompt early (first launch UX,
        // same as CleanShot X onboarding).
        ScreenRecordingPermission.requestIfNeeded()
        CaptureHistoryStore.purgeOldEntries()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Double-clicked .cleanshotz projects (or images dropped on the app icon).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            StatusBarMenuController.openEditorFile(at: url)
        }
    }
}
