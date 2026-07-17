import AppKit
import SwiftUI

/// Small floating confirmation HUD ("Text Copied") that fades out on its own,
/// shown near the top of the screen like CleanShot's notifications.
@MainActor
final class ToastHUDController {
    static let shared = ToastHUDController()
    private var panel: NSPanel?

    func show(_ message: String, systemImage: String = "checkmark.circle.fill") {
        dismiss()

        let content = HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(.green)
            Text(message).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .padding(14)

        let hosting = NSHostingView(rootView: AnyView(content))
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.maxY - panel.frame.height - 12
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(1.8))
            if let panel, self?.panel === panel {
                panel.animator().alphaValue = 0
                try? await Task.sleep(for: .milliseconds(250))
                self?.dismiss()
            }
        }
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
