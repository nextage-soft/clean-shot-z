import AppKit
import SwiftUI

/// The Preferences window (tabbed, CleanShot-style).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CleanShot Z Preferences"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsRootView())
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct SettingsRootView: View {
    var body: some View {
        TabView {
            SettingsGeneralTabView()
                .tabItem { Label("General", systemImage: "gearshape") }
            SettingsScreenshotsTabView()
                .tabItem { Label("Screenshots", systemImage: "camera") }
            SettingsShortcutsTabView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        // Fixed size keeps the window compact; grouped forms inside supply padding.
        .frame(width: 520, height: 380)
    }
}
