import AppKit
import SwiftUI

/// Floating pinned screenshots (CleanShot's "Pin"): always-on-top borderless
/// panels you can drag anywhere; hover shows a close button; double-click closes.
@MainActor
final class PinWindowController {
    static let shared = PinWindowController()
    private var panels: [NSPanel] = []

    func pin(image: NSImage, pointScale: CGFloat = 2) {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let card = PinCardView(image: image) { [weak self, weak panel] in
            guard let panel else { return }
            self?.close(panel)
        }
        let hosting = NSHostingView(rootView: card)
        panel.contentView = hosting

        // Natural size: image pixels ÷ the SOURCE display's scale (not NSScreen.main's,
        // which is wrong on mixed-DPI setups). Capped to 55% of the screen.
        let screen = NSScreen.main
        var size = NSSize(width: image.size.width / pointScale, height: image.size.height / pointScale)
        if let visible = screen?.visibleFrame.size {
            let cap = min(visible.width * 0.55 / size.width, visible.height * 0.55 / size.height, 1)
            size = NSSize(width: size.width * cap, height: size.height * cap)
        }
        panel.setContentSize(size)
        panel.aspectRatio = size

        if let visible = screen?.visibleFrame {
            let offset = CGFloat(panels.count % 5) * 24
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2 + offset,
                y: visible.midY - size.height / 2 - offset
            ))
        }
        panels.append(panel)
        panel.orderFrontRegardless()
    }

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
    }
}

/// Pinned image with border, shadow, and a hover close button.
private struct PinCardView: View {
    let image: NSImage
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(hovering ? 0.9 : 0.4), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .overlay(alignment: .topLeading) {
                if hovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) { onClose() }
            .padding(10)
    }
}
