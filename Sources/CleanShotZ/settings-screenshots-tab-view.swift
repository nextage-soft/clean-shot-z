import AppKit
import SwiftUI

struct SettingsScreenshotsTabView: View {
    @AppStorage("saveDirectoryPath") private var saveDirectoryPath = ""
    @AppStorage("fileNamePrefix") private var fileNamePrefix = "CleanShot Z"
    @AppStorage("imageFormat") private var imageFormat = CaptureImageFormat.png.rawValue
    @AppStorage("imageQuality") private var imageQuality = 0.85
    @AppStorage("downscaleRetinaTo1x") private var downscaleRetina = false

    private var displayedDirectory: String {
        saveDirectoryPath.isEmpty ? "~/Desktop" : (saveDirectoryPath as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Save to") {
                    HStack(spacing: 8) {
                        Text(displayedDirectory)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseDirectory() }
                    }
                }
                LabeledContent("File name prefix") {
                    TextField("", text: $fileNamePrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            } footer: {
                Text("Example: \(fileNamePrefix) 2026-07-14 at 09.41.05.png")
            }

            Section {
                Picker("Format", selection: $imageFormat) {
                    ForEach(CaptureImageFormat.allCases) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }
                if imageFormat != CaptureImageFormat.png.rawValue {
                    HStack {
                        Text("Quality")
                        Slider(value: $imageQuality, in: 0.3...1.0)
                        Text("\(Int(imageQuality * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                Toggle("Downscale Retina screenshots to 1x", isOn: $downscaleRetina)
            } footer: {
                Text("HEIC is ~10× smaller than PNG. Downscaling to 1x quarters the pixel count — good for sharing, skip it if you need pixel-perfect zooming.")
            }

            Section {
                LabeledContent("History") {
                    Button("Open History Folder") {
                        NSWorkspace.shared.open(CaptureHistoryStore.directory)
                    }
                }
            } footer: {
                Text("Captures are kept in history for 30 days.")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = SettingsStore.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectoryPath = url.path
        }
    }
}
