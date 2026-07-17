import ServiceManagement
import SwiftUI

struct SettingsGeneralTabView: View {
    @AppStorage("copyToClipboardAfterCapture") private var copyToClipboard = true
    @AppStorage("showQuickAccessOverlay") private var showQuickAccess = true
    @AppStorage("quickAccessAutoDismiss") private var quickAccessAutoDismiss = true
    @AppStorage("quickAccessDismissSeconds") private var quickAccessDismissSeconds = 15.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { applyLaunchAtLogin() }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("After capture") {
                Toggle("Copy screenshot to clipboard", isOn: $copyToClipboard)
                Toggle("Show Quick Access overlay", isOn: $showQuickAccess)
                if showQuickAccess {
                    Toggle("Auto-hide Quick Access", isOn: $quickAccessAutoDismiss)
                    if quickAccessAutoDismiss {
                        HStack {
                            Text("Hide after")
                            Slider(value: $quickAccessDismissSeconds, in: 5...60, step: 5)
                            Text("\(Int(quickAccessDismissSeconds))s")
                                .font(.caption.monospacedDigit())
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = "Could not update login item: \(error.localizedDescription)"
        }
    }
}
