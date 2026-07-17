import AppKit
import Carbon.HIToolbox

/// Minimal global-hotkey registry built directly on Carbon's RegisterEventHotKey.
/// (No third-party dependency: KeyboardShortcuts and friends need Xcode-only macros
/// to compile, and Command Line Tools alone can't build them.)
final class GlobalHotkeyCenter {
    static let shared = GlobalHotkeyCenter()

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerInstalled = false
    private var nextID: UInt32 = 1

    /// Registers a system-wide hotkey. `modifiers` are Carbon flags (cmdKey, shiftKey, ...).
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void) {
        installEventHandlerIfNeeded()
        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x43535A48), id: id) // 'CSZH'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            NSLog("GlobalHotkeyCenter: RegisterEventHotKey failed (\(status)) for keyCode \(keyCode)")
            return
        }
        handlers[id] = handler
        hotKeyRefs.append(ref)
    }

    /// Removes every registered hotkey (before re-registering with new bindings).
    func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    fileprivate func dispatch(id: UInt32) {
        guard let handler = handlers[id] else { return }
        Task { @MainActor in handler() }
    }

    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // C callback: no captures allowed, so it reaches back through the singleton.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                GlobalHotkeyCenter.shared.dispatch(id: hotKeyID.id)
            }
            return noErr
        }, 1, &eventType, nil, nil)
        eventHandlerInstalled = true
    }
}
