import AppKit
import Carbon.HIToolbox

/// The app's remappable global hotkey actions.
enum HotkeyAction: String, CaseIterable, Identifiable {
    case allInOne
    case captureArea
    case captureFullscreen
    case captureTextOCR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allInOne: "All-in-One"
        case .captureArea: "Capture Area"
        case .captureFullscreen: "Capture Fullscreen"
        case .captureTextOCR: "Capture Text (OCR)"
        }
    }

    var defaultShortcut: StoredShortcut {
        let cmdShift = UInt32(cmdKey | shiftKey)
        switch self {
        case .allInOne: return StoredShortcut(keyCode: UInt32(kVK_ANSI_1), carbonModifiers: cmdShift)
        case .captureArea: return StoredShortcut(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: cmdShift)
        case .captureFullscreen: return StoredShortcut(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: cmdShift)
        case .captureTextOCR: return StoredShortcut(keyCode: UInt32(kVK_ANSI_2), carbonModifiers: cmdShift)
        }
    }

    /// Persisted shortcut, or the default when never customized.
    var shortcut: StoredShortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: "hotkey.\(rawValue)"),
                  let stored = try? JSONDecoder().decode(StoredShortcut.self, from: data)
            else { return defaultShortcut }
            return stored
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "hotkey.\(rawValue)")
            }
        }
    }
}

/// A key combination in Carbon terms (what RegisterEventHotKey wants).
struct StoredShortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Builds from an NSEvent (shortcut recorder input).
    init?(event: NSEvent) {
        var carbon: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        guard carbon != 0 else { return nil } // require at least one modifier
        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = carbon
    }

    /// Human-readable form, e.g. "⌘⇧4".
    var displayString: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
    ]

    static func keyName(for keyCode: UInt32) -> String {
        if let name = keyNames[keyCode] { return name }
        // Letters and everything else: resolve via the current keyboard layout.
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return "?"
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let error = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
            guard error == noErr, length > 0 else { return "?" }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}
