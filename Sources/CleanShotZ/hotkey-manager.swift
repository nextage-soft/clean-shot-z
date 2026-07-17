import AppKit

/// Registers the remappable global hotkeys (see hotkey-definitions.swift for
/// actions and persisted bindings). Defaults mirror CleanShot X; matching system
/// screenshot shortcuts must be disabled in System Settings > Keyboard.
@MainActor
enum HotkeyManager {
    private static weak var coordinator: CaptureCoordinator?

    static func register(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        reload()
    }

    /// Re-reads all bindings from settings and re-registers (called after the
    /// user records a new shortcut in Preferences).
    static func reload() {
        guard let coordinator else { return }
        GlobalHotkeyCenter.shared.unregisterAll()
        for action in HotkeyAction.allCases {
            let shortcut = action.shortcut
            GlobalHotkeyCenter.shared.register(
                keyCode: shortcut.keyCode,
                modifiers: shortcut.carbonModifiers
            ) {
                switch action {
                case .allInOne: coordinator.allInOneCapture()
                case .captureArea: coordinator.captureArea()
                case .captureFullscreen: coordinator.captureFullscreen()
                case .captureTextOCR: coordinator.captureTextOCR()
                }
            }
        }
    }
}
