import SwiftUI

struct SettingsShortcutsTabView: View {
    /// Bumped to force row refresh after a shortcut is recorded.
    @State private var reloadToken = 0

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorderView(action: action) {
                            HotkeyManager.reload()
                            reloadToken += 1
                        }
                        .frame(width: 110, height: 24)
                    }
                }
                .id(reloadToken)
            } footer: {
                Text("Click a field, then press the new key combination. Shortcuts need at least one modifier key (⌘⌥⌃⇧). Disable macOS's own screenshot shortcuts in System Settings → Keyboard → Keyboard Shortcuts → Screenshots to free up ⌘⇧3/4.")
            }
        }
        .formStyle(.grouped)
    }
}
