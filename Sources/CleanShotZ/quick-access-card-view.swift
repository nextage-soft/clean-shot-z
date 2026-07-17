import SwiftUI

/// Compact post-capture card: just the thumbnail — actions appear as an
/// overlay ON the image when hovered (Copy / Edit centered, ✕ and pin in the
/// corners), right-click offers Close All, and the card auto-hides after a
/// configurable delay (hover pauses the countdown).
struct QuickAccessCardView: View {
    let image: NSImage
    let fileURL: URL
    /// Exact fitted size (controller computes it from the image's aspect ratio,
    /// so the panel hugs the thumbnail — no dead space around odd aspect ratios).
    let cardSize: CGSize
    /// Pixels-per-point of the source display (for natural-size pinning).
    var pointScale: CGFloat = 2
    let onClose: () -> Void
    var onCloseAll: () -> Void = {}

    @State private var hovering = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Image(nsImage: image)
            .resizable()
            // Fixed-size card, image fills and center-crops — every card in the
            // stack is the same shape regardless of the capture's aspect ratio.
            .aspectRatio(contentMode: .fill)
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .overlay { hoverActions }
            .onDrag { NSItemProvider(object: fileURL as NSURL) }
            .contextMenu {
                Button("Edit") { openEditor() }
                Button("Copy") { copyImage() }
                Button("Pin") { pin() }
                Divider()
                Button("Close") { onClose() }
                Button("Close All") { onCloseAll() }
            }
            .onHover { inside in
                hovering = inside
                // Hover pauses auto-dismiss; leaving restarts the full countdown.
                inside ? cancelAutoDismiss() : scheduleAutoDismiss()
            }
            .onAppear { scheduleAutoDismiss() }
            .onDisappear { cancelAutoDismiss() }
            .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
            .padding(8)
    }

    // MARK: - Hover overlay

    @ViewBuilder
    private var hoverActions: some View {
        if hovering {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))

                HStack(spacing: 10) {
                    overlayButton("doc.on.doc", "Copy") { copyImage() }
                    overlayButton("pencil.tip.crop.circle", "Edit") { openEditor() }
                }

                VStack {
                    HStack {
                        cornerButton("xmark", "Close") { onClose() }
                        Spacer()
                        cornerButton("pin", "Pin (always on top)") { pin() }
                    }
                    Spacer()
                }
                .padding(5)
            }
            .transition(.opacity)
        }
    }

    private func overlayButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 30)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func cornerButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Actions

    private func openEditor() {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        EditorWindowController.shared.open(image: cgImage, fileURL: fileURL)
        onClose()
    }

    private func copyImage() {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            CaptureFileWriter.copyToClipboard(cgImage)
            ToastHUDController.shared.show("Copied")
        }
    }

    private func pin() {
        PinWindowController.shared.pin(image: image, pointScale: pointScale)
        onClose()
    }

    // MARK: - Auto-dismiss

    private func scheduleAutoDismiss() {
        cancelAutoDismiss()
        guard SettingsStore.quickAccessAutoDismiss else { return }
        let seconds = SettingsStore.quickAccessDismissSeconds
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            onClose()
        }
    }

    private func cancelAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}
