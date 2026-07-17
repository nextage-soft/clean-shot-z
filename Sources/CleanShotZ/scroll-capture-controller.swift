import AppKit
import SwiftUI

/// Scrolling capture flow: select an area → a floating control panel appears →
/// the user scrolls through the content while frames are captured (~3/s) and
/// stitched live → Done produces one tall image.
@MainActor
final class ScrollCaptureController {
    /// Observable stats for the panel. Separate object so the SwiftUI panel view
    /// never holds the controller strongly (controller → panel → view → controller
    /// would be a retain cycle keeping the capture loop alive forever).
    final class Status: ObservableObject {
        @Published var stitchedHeight = 0
    }

    private let status = Status()
    private let captureService: ScreenCaptureService
    private var selectionController: AreaSelectionController?
    private var panel: NSPanel?
    private var captureTask: Task<Void, Never>?
    private var stitcher: ScrollStitcher?
    private var onComplete: ((CGImage?) -> Void)?

    init(captureService: ScreenCaptureService) {
        self.captureService = captureService
    }

    func begin(onComplete: @escaping (CGImage?) -> Void) {
        guard panel == nil, selectionController == nil else { return }
        self.onComplete = onComplete
        let selection = AreaSelectionController()
        selectionController = selection
        selection.begin { [weak self] result in
            guard let self else { return }
            self.selectionController = nil
            guard case .area(let rect, let screen) = result else {
                // Scrolling capture needs a dragged area; window click / Esc cancels.
                self.finish(with: nil)
                return
            }
            self.startCapturing(rect: rect, screen: screen)
        }
    }

    /// Starts a scroll session with an already-selected area (All-in-One flow).
    func begin(rect: NSRect, screen: NSScreen, onComplete: @escaping (CGImage?) -> Void) {
        guard panel == nil else { return }
        self.onComplete = onComplete
        startCapturing(rect: rect, screen: screen)
    }

    deinit {
        captureTask?.cancel()
    }

    private func startCapturing(rect: NSRect, screen: NSScreen) {
        let stitcher = ScrollStitcher()
        self.stitcher = stitcher
        status.stitchedHeight = 0
        showPanel(near: rect, on: screen)

        captureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            while let self, !Task.isCancelled {
                do {
                    let frame = try await self.captureService.captureArea(
                        rect, on: screen, excludingOwnWindows: true
                    )
                    _ = await stitcher.add(frame)
                    self.status.stitchedHeight = await stitcher.totalHeight
                } catch {
                    // Transient capture failure — keep trying until Done/Cancel.
                }
                try? await Task.sleep(for: .milliseconds(320))
            }
        }
    }

    func done() {
        let task = captureTask
        captureTask = nil
        task?.cancel()
        let stitcher = self.stitcher
        Task { @MainActor [weak self] in
            // Wait for any in-flight frame to land before flattening, so the
            // final image deterministically includes the last strip.
            _ = await task?.value
            let image = await stitcher?.finalImage()
            self?.finish(with: image)
        }
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
        finish(with: nil)
    }

    private func finish(with image: CGImage?) {
        panel?.orderOut(nil)
        panel = nil
        stitcher = nil
        let completion = onComplete
        onComplete = nil
        completion?(image)
    }

    /// Non-activating control panel placed below the capture area (or above if no room),
    /// so scrolling focus stays in the target app.
    private func showPanel(near rect: NSRect, on screen: NSScreen) {
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
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: ScrollCapturePanelView(
            status: status,
            onDone: { [weak self] in self?.done() },
            onCancel: { [weak self] in self?.cancel() }
        ))
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        var origin = NSPoint(x: rect.midX - panel.frame.width / 2, y: rect.minY - panel.frame.height - 10)
        if origin.y < screen.visibleFrame.minY {
            origin.y = min(rect.maxY + 10, screen.visibleFrame.maxY - panel.frame.height)
        }
        origin.x = max(screen.visibleFrame.minX + 8,
                       min(origin.x, screen.visibleFrame.maxX - panel.frame.width - 8))
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

private struct ScrollCapturePanelView: View {
    @ObservedObject var status: ScrollCaptureController.Status
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.and.down.text.horizontal")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Scroll through the content")
                    .font(.system(size: 12, weight: .medium))
                Text("\(status.stitchedHeight) px captured")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .padding(12)
    }
}
