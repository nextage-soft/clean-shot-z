import AppKit
import SwiftUI

/// Opens and tracks annotation editor windows (one per capture).
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    static let shared = EditorWindowController()
    private var windows: [NSWindow] = []

    /// Opens a `.cleanshotz` project — layers come back fully editable.
    func open(projectURL: URL) {
        do {
            let payload = try ProjectFileCodec.read(from: projectURL)
            let document = AnnotationDocument(baseImage: payload.baseImage, fileURL: projectURL)
            document.restore(from: payload)
            present(document)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not open project"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }

    func open(image: CGImage, fileURL: URL) {
        let document = AnnotationDocument(baseImage: image, fileURL: fileURL)
        present(document)
    }

    private func present(_ document: AnnotationDocument) {
        let image = document.baseImage
        let fileURL = document.fileURL

        // Fit the image on screen: image is in pixels, screen works in points.
        let screen = NSScreen.main
        let backing = screen?.backingScaleFactor ?? 2
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let chromeAllowance = NSSize(width: 90, height: 120) // toolbar + top bar + padding
        let maxCanvas = NSSize(
            width: visible.width * 0.85 - chromeAllowance.width,
            height: visible.height * 0.85 - chromeAllowance.height
        )
        let naturalScale = 1 / backing
        let fitScale = min(
            naturalScale,
            maxCanvas.width / CGFloat(image.width),
            maxCanvas.height / CGFloat(image.height)
        )

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = fileURL.lastPathComponent
        window.isReleasedWhenClosed = false
        window.delegate = self

        let root = EditorRootView(
            document: document,
            displayScale: fitScale,
            onSave: { [weak self, weak window] in
                do {
                    try document.saveToFile()
                    if let window { self?.close(window) }
                } catch {
                    NSSound.beep()
                }
            },
            onClose: { [weak self, weak window] in
                if let window { self?.close(window) }
            }
        )
        window.contentView = NSHostingView(rootView: root)
        // Comfortable default size: fit the image, but never open tiny —
        // small captures get a roomy window with the canvas centered.
        let contentSize = NSSize(
            width: min(max(CGFloat(image.width) * fitScale + chromeAllowance.width, 1000), visible.width * 0.9),
            height: min(max(CGFloat(image.height) * fitScale + chromeAllowance.height, 680), visible.height * 0.9)
        )
        window.setContentSize(contentSize)
        window.minSize = NSSize(width: 720, height: 480)
        window.center()

        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close(_ window: NSWindow) {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === window }
    }
}
