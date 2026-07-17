import AppKit
import os.log

/// Orchestrates the capture flows: selection overlay -> ScreenCaptureKit -> save/copy -> Quick Access.
@MainActor
final class CaptureCoordinator {
    static let log = Logger(subsystem: "com.tieuanhquoc.cleanshotz", category: "capture")

    let captureService = ScreenCaptureService()
    private var selectionController: AreaSelectionController?
    private var scrollCaptureController: ScrollCaptureController?

    /// True while any capture flow (selection overlay or scroll session) is active.
    /// Self-heals: a selection controller whose overlay is no longer on screen is
    /// a stuck session (it would silently block every capture forever) — drop it.
    private var sessionActive: Bool {
        if let controller = selectionController, !controller.isPresenting {
            Self.log.error("Stale selection session detected (controller alive, no visible overlay) — resetting")
            controller.dismiss()
            selectionController = nil
        }
        return selectionController != nil || scrollCaptureController != nil
    }

    /// Area mode: drag a rectangle, or click a hover-highlighted window.
    func captureArea() {
        Self.log.info("captureArea invoked")
        guard ScreenRecordingPermission.ensureGrantedOrExplain() else { return }
        guard !sessionActive else {
            Self.log.warning("captureArea blocked: session already active")
            return
        }
        let controller = AreaSelectionController()
        selectionController = controller
        controller.begin { [weak self] result in
            guard let self else { return }
            self.selectionController = nil
            guard let result else { return }
            Task { @MainActor in
                // Give WindowServer a beat to actually remove the overlay
                // so the dim layer doesn't appear in the screenshot.
                try? await Task.sleep(for: .milliseconds(80))
                await self.performCapture(for: result)
            }
        }
    }

    /// All-in-One (⌘⇧1): select + adjust an area with magnetic snapping, then pick
    /// a tool from the floating menu — Capture / Scroll / OCR (CleanShot style).
    func allInOneCapture() {
        guard ScreenRecordingPermission.ensureGrantedOrExplain() else { return }
        guard !sessionActive else { return }
        let controller = AreaSelectionController()
        selectionController = controller
        controller.begin(mode: .allInOne) { [weak self] result in
            guard let self else { return }
            self.selectionController = nil
            guard let result else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                switch result {
                case .window, .area:
                    await self.performCapture(for: result)
                case .areaAction(let rect, let screen, let action):
                    switch action {
                    case .capture:
                        await self.performCapture(for: .area(rect, screen))
                    case .ocr:
                        await self.performOCR(rect: rect, screen: screen)
                    case .scroll:
                        let scroll = ScrollCaptureController(captureService: self.captureService)
                        self.scrollCaptureController = scroll
                        scroll.begin(rect: rect, screen: screen) { [weak self] image in
                            self?.scrollCaptureController = nil
                            if let image { self?.handleCaptured(image) }
                        }
                    }
                }
            }
        }
    }

    private func performOCR(rect: NSRect, screen: NSScreen) async {
        do {
            let image = try await captureService.captureArea(rect, on: screen)
            let text = try await OCRService.recognizeText(in: image)
            if text.isEmpty {
                ToastHUDController.shared.show("No text found", systemImage: "text.magnifyingglass")
            } else {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                ToastHUDController.shared.show("Text Copied")
            }
        } catch {
            presentError(error)
        }
    }

    /// Self-timer: select an area, then capture it after a countdown —
    /// time to open menus/hover states that a normal capture would dismiss.
    func timedCapture(delaySeconds: Int = 5) {
        guard ScreenRecordingPermission.ensureGrantedOrExplain() else { return }
        guard !sessionActive else { return }
        let controller = AreaSelectionController()
        selectionController = controller
        controller.begin { [weak self] result in
            guard let self else { return }
            self.selectionController = nil
            guard let result else { return }
            Task { @MainActor in
                for remaining in stride(from: delaySeconds, through: 1, by: -1) {
                    ToastHUDController.shared.show("Capturing in \(remaining)…", systemImage: "timer")
                    try? await Task.sleep(for: .seconds(1))
                }
                await self.performCapture(for: result)
            }
        }
    }

    /// Scrolling capture: select an area, scroll through the content, get one tall image.
    func startScrollingCapture() {
        guard ScreenRecordingPermission.ensureGrantedOrExplain() else { return }
        guard !sessionActive else { return }
        let controller = ScrollCaptureController(captureService: captureService)
        scrollCaptureController = controller
        controller.begin { [weak self] image in
            guard let self else { return }
            self.scrollCaptureController = nil
            if let image {
                self.handleCaptured(image)
            }
        }
    }

    /// OCR mode: select an area (or click a window), recognize text on-device,
    /// copy straight to the clipboard.
    func captureTextOCR() {
        guard ScreenRecordingPermission.ensureGrantedOrExplain() else { return }
        guard !sessionActive else { return }
        let controller = AreaSelectionController()
        selectionController = controller
        controller.begin { [weak self] result in
            guard let self else { return }
            self.selectionController = nil
            guard let result else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                do {
                    let image: CGImage
                    switch result {
                    case .area(let rect, let screen), .areaAction(let rect, let screen, _):
                        image = try await self.captureService.captureArea(rect, on: screen)
                    case .window(let windowID):
                        image = try await self.captureService.captureWindow(windowID: windowID).image
                    }
                    let text = try await OCRService.recognizeText(in: image)
                    if text.isEmpty {
                        ToastHUDController.shared.show("No text found", systemImage: "text.magnifyingglass")
                    } else {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                        ToastHUDController.shared.show("Text Copied")
                    }
                } catch {
                    self.presentError(error)
                }
            }
        }
    }

    /// Fullscreen mode: captures the display currently containing the mouse cursor.
    func captureFullscreen() {
        guard ScreenRecordingPermission.ensureGrantedOrExplain() else { return }
        guard !sessionActive else { return } // would capture the dim overlay otherwise
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        Task { @MainActor in
            do {
                let image = try await captureService.captureDisplayImage(of: screen)
                handleCaptured(image, pointScale: screen.backingScaleFactor)
            } catch {
                presentError(error)
            }
        }
    }

    private func performCapture(for result: AreaSelectionResult) async {
        do {
            let image: CGImage
            let pointScale: CGFloat
            switch result {
            case .area(let rect, let screen), .areaAction(let rect, let screen, _):
                image = try await captureService.captureArea(rect, on: screen)
                pointScale = screen.backingScaleFactor
            case .window(let windowID):
                (image, pointScale) = try await captureService.captureWindow(windowID: windowID)
            }
            handleCaptured(image, pointScale: pointScale)
        } catch {
            presentError(error)
        }
    }

    private func handleCaptured(
        _ image: CGImage,
        pointScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    ) {
        do {
            let url = try CaptureFileWriter.save(image, pointScale: pointScale)
            if SettingsStore.copyToClipboardAfterCapture {
                CaptureFileWriter.copyToClipboard(image)
            }
            CaptureHistoryStore.record(fileURL: url)
            QuickAccessOverlayController.shared.show(image: image, fileURL: url, pointScale: pointScale)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Capture failed"
        alert.informativeText = String(describing: error)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
