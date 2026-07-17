import AppKit
import SwiftUI

/// Shows floating thumbnail panels at the bottom-left of the screen after each
/// capture, stacking upwards. Closing any card re-flows the ones above it down.
@MainActor
final class QuickAccessOverlayController {
    static let shared = QuickAccessOverlayController()
    private var panels: [NSPanel] = [] // index 0 = bottom of the stack

    /// Keep at most this many before dropping the oldest.
    private static let maxStackedPanels = 5
    private static let margin: CGFloat = 8
    private static let spacing: CGFloat = 4

    func show(image: CGImage, fileURL: URL, pointScale: CGFloat = 2) {
        guard SettingsStore.showQuickAccessOverlay else { return }
        while panels.count >= Self.maxStackedPanels {
            dismiss(panels[0], animated: false)
        }
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 160),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false // the SwiftUI card draws its own shadow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        // One fixed card size for the whole stack; the image fills & center-crops.
        let cardSize = CGSize(width: 190, height: 120)

        let card = QuickAccessCardView(
            image: nsImage,
            fileURL: fileURL,
            cardSize: cardSize,
            pointScale: pointScale,
            onClose: { [weak self, weak panel] in
                guard let panel else { return }
                self?.dismiss(panel)
            },
            onCloseAll: { [weak self] in
                self?.closeAll()
            }
        )
        let hosting = NSHostingView(rootView: card)
        panel.contentView = hosting
        // Card padding is 8 per side; panel hugs image + shadow padding exactly.
        panel.setContentSize(NSSize(width: cardSize.width + 16, height: cardSize.height + 16))

        panels.append(panel)
        relayout(animated: false)
        panel.orderFrontRegardless()
    }

    func closeAll() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func dismiss(_ panel: NSPanel, animated: Bool = true) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
        relayout(animated: animated)
    }

    /// Positions the whole stack bottom-up; cards above a removed one slide down.
    private func relayout(animated: Bool) {
        guard let screen = NSScreen.main else { return }
        var y = screen.visibleFrame.minY + Self.margin
        let x = screen.visibleFrame.minX + Self.margin

        // NSWindow's animator only honors setFrame(_:display:) — animating
        // setFrameOrigin silently does nothing, which left closed gaps unfilled.
        let apply = {
            for panel in self.panels {
                let target = NSRect(origin: NSPoint(x: x, y: y), size: panel.frame.size)
                if animated {
                    panel.animator().setFrame(target, display: true)
                } else {
                    panel.setFrame(target, display: true)
                }
                y += panel.frame.height + Self.spacing
            }
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                apply()
            }
        } else {
            apply()
        }
    }
}
