import AppKit

/// Borderless fullscreen overlay hosting the selection view for one screen.
/// NSPanel + .nonactivatingPanel: the overlay takes mouse/keyboard WITHOUT
/// activating the app. The old NSWindow + NSApp.activate(ignoringOtherApps:)
/// approach raced macOS 14's cooperative activation — when activation silently
/// failed, the first click was swallowed as an "activate" click and dragging
/// selected nothing (the intermittent "can't select area" bug).
final class AreaSelectionWindow: NSPanel {
    init(
        mode: AreaSelectionView.Mode,
        screen: NSScreen,
        visibleWindows: [OnScreenWindowInfo],
        onResult: @escaping (AreaSelectionResult?) -> Void
    ) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = AreaSelectionView(
            mode: mode,
            screen: screen,
            visibleWindows: visibleWindows,
            onResult: onResult
        )
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        (contentView as? AreaSelectionView)?.cancel()
    }
}
