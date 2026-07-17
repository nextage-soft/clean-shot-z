import AppKit

/// What the user picked in the selection overlay.
enum AreaSelectionResult {
    /// Dragged rectangle (immediate mode), in AppKit global coordinates.
    case area(NSRect, NSScreen)
    /// All-in-One mode: adjusted rectangle + the tool the user chose.
    case areaAction(NSRect, NSScreen, AreaSelectionAction)
    /// Clicked a window (hover-highlight mode, like CleanShot X).
    case window(CGWindowID)
}

/// Presents one dimmed overlay window per screen; the user drags an area or clicks a
/// highlighted window. Esc cancels.
@MainActor
final class AreaSelectionController {
    private var overlayWindows: [AreaSelectionWindow] = []
    private var completion: ((AreaSelectionResult?) -> Void)?
    private let windows = WindowEnumerator.visibleWindows()

    /// True while at least one overlay window is actually on screen. Used by the
    /// coordinator's self-heal: a controller that exists with no visible overlay
    /// is a stuck session and must not block new captures.
    var isPresenting: Bool {
        completion != nil && overlayWindows.contains { $0.isVisible }
    }

    func begin(
        mode: AreaSelectionView.Mode = .immediate,
        completion: @escaping (AreaSelectionResult?) -> Void
    ) {
        self.completion = completion
        // No NSApp.activate: the non-activating panels take input themselves,
        // and the user's current app keeps focus (same behavior as CleanShot X).
        for screen in NSScreen.screens {
            let window = AreaSelectionWindow(
                mode: mode,
                screen: screen,
                visibleWindows: windows
            ) { [weak self] result in
                self?.finish(with: result)
            }
            overlayWindows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
        // All-in-One: only one screen may hold the adjusting selection at a time.
        for window in overlayWindows {
            guard let view = window.contentView as? AreaSelectionView else { continue }
            view.onDidEnterAdjusting = { [weak self, weak view] in
                guard let self else { return }
                for other in self.overlayWindows {
                    if let otherView = other.contentView as? AreaSelectionView, otherView !== view {
                        otherView.resetToIdle()
                    }
                }
            }
        }
        NSCursor.crosshair.set()
    }

    /// Cancels the session from outside (self-heal / teardown).
    func dismiss() {
        finish(with: nil)
    }

    private func finish(with result: AreaSelectionResult?) {
        guard completion != nil else { return }
        let done = completion
        completion = nil
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        NSCursor.arrow.set()
        done?(result)
    }
}
