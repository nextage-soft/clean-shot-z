import AppKit

/// Menu bar entry mirroring CleanShot X's menu structure (screenshot section only for M1).
@MainActor
final class StatusBarMenuController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: CaptureCoordinator

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "CleanShot Z"
            )
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(sectionHeader("Screenshot"))
        menu.addItem(item("All-in-One", #selector(allInOne), key: "1", modifiers: [.command, .shift]))
        menu.addItem(item("Capture Area", #selector(captureArea), key: "4", modifiers: [.command, .shift]))
        menu.addItem(item("Capture Fullscreen", #selector(captureFullscreen), key: "3", modifiers: [.command, .shift]))
        menu.addItem(item("Scrolling Capture", #selector(scrollingCapture)))
        menu.addItem(item("Timed Capture (5s)", #selector(timedCapture)))
        menu.addItem(.separator())

        menu.addItem(sectionHeader("Text"))
        menu.addItem(item("Capture Text (OCR)", #selector(captureTextOCR), key: "2", modifiers: [.command, .shift]))
        menu.addItem(.separator())

        menu.addItem(item("Open Image or Project…", #selector(openFile), key: "o", modifiers: [.command]))
        menu.addItem(item("History…", #selector(showHistory)))
        menu.addItem(item("Open Screenshots Folder", #selector(openSaveFolder)))
        menu.addItem(.separator())

        menu.addItem(item("Preferences…", #selector(showPreferences), key: ",", modifiers: [.command]))
        menu.addItem(.separator())

        menu.addItem(item("Quit CleanShot Z", #selector(quit), key: "q", modifiers: [.command]))
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        return header
    }

    private func item(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    // MARK: - Actions

    @objc private func captureArea() { coordinator.captureArea() }
    @objc private func allInOne() { coordinator.allInOneCapture() }
    @objc private func captureFullscreen() { coordinator.captureFullscreen() }
    @objc private func captureTextOCR() { coordinator.captureTextOCR() }
    @objc private func scrollingCapture() { coordinator.startScrollingCapture() }
    @objc private func timedCapture() { coordinator.timedCapture() }
    @objc private func showPreferences() { SettingsWindowController.shared.show() }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Self.openEditorFile(at: url)
    }

    /// Routes a file (image or .cleanshotz project) into the editor.
    static func openEditorFile(at url: URL) {
        if url.pathExtension.lowercased() == ProjectFileCodec.fileExtension {
            EditorWindowController.shared.open(projectURL: url)
        } else if let image = NSImage(contentsOf: url),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            EditorWindowController.shared.open(image: cg, fileURL: url)
        } else {
            NSSound.beep()
        }
    }
    @objc private func showHistory() { HistoryWindowController.shared.show() }

    @objc private func openSaveFolder() {
        NSWorkspace.shared.open(SettingsStore.saveDirectory)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
