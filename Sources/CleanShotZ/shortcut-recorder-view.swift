import AppKit
import SwiftUI

/// Click-to-record shortcut field (like CleanShot's Preferences):
/// click → "Type shortcut…" → press keys → binding saved. Esc cancels recording.
struct ShortcutRecorderView: NSViewRepresentable {
    let action: HotkeyAction
    let onChange: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderField {
        ShortcutRecorderField(action: action, onChange: onChange)
    }

    func updateNSView(_ view: ShortcutRecorderField, context: Context) {}
}

final class ShortcutRecorderField: NSView {
    private let action: HotkeyAction
    private let onChange: () -> Void
    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    init(action: HotkeyAction, onChange: @escaping () -> Void) {
        self.action = action
        self.onChange = onChange
        super.init(frame: .zero)
        setFrameSize(NSSize(width: 110, height: 24))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 110, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // esc cancels recording
            isRecording = false
            return
        }
        guard let shortcut = StoredShortcut(event: event) else {
            NSSound.beep() // needs at least one modifier
            return
        }
        action.shortcut = shortcut
        isRecording = false
        onChange()
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        background.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        background.lineWidth = 1
        background.stroke()

        let text = isRecording ? "Type shortcut…" : action.shortcut.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
