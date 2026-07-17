import SwiftUI

/// Editor layout modeled on CleanShot X: tool column on the left,
/// style/actions bar on top, canvas in the center.
struct EditorRootView: View {
    @ObservedObject var document: AnnotationDocument
    let displayScale: CGFloat
    let onSave: () -> Void
    let onClose: () -> Void
    @State private var showsBackgroundPopover = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                toolColumn
                Divider()
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        AnnotationCanvasRepresentable(document: document, displayScale: displayScale)
                            .padding(16)
                            .frame(
                                minWidth: proxy.size.width,
                                minHeight: proxy.size.height
                            )
                    }
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
    }

    // MARK: - Top bar (style controls + actions)

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!document.canUndo)
                .keyboardShortcut("z", modifiers: [.command])
            Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!document.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider().frame(height: 18)

            ColorSwatchRow(selection: document.strokeColor) { document.strokeColor = $0 }
                .help("Stroke / text color")

            HStack(spacing: 6) {
                Image(systemName: "lineweight").font(.system(size: 11))
                Slider(value: $document.lineWidth, in: 2...16)
                    .frame(width: 70)
            }

            if showsShapeControls {
                Divider().frame(height: 18)
                Toggle(isOn: $document.filled) {
                    Image(systemName: "square.fill")
                }
                .toggleStyle(.button)
                .help("Fill shapes")

                if document.filled {
                    ColorSwatchRow(selection: document.fillColor, presetAlpha: 0.4) {
                        document.fillColor = $0
                    }
                    .help("Fill (background) color")
                }
            }

            if showsTextControls {
                Divider().frame(height: 18)
                Picker("", selection: $document.fontDesign) {
                    ForEach(FontDesignChoice.allCases) { design in
                        Text(design.rawValue).tag(design)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
                .help("Font")
                HStack(spacing: 4) {
                    Image(systemName: "textformat.size").font(.system(size: 11))
                    Slider(value: $document.fontSize, in: 16...96)
                        .frame(width: 80)
                    Text("\(Int(document.fontSize))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 24, alignment: .trailing)
                }
            }

            if document.selectedTool == .counter {
                Divider().frame(height: 18)
                Stepper(value: $document.counterNextNumber, in: 1...999) {
                    Text("Next: \(document.counterNextNumber)")
                        .font(.caption.monospacedDigit())
                }
                .help("Number for the next counter stamp")
            }

            Spacer()

            Button {
                showsBackgroundPopover.toggle()
            } label: {
                Label("Background", systemImage: "photo.on.rectangle")
                    .foregroundStyle(document.background.enabled ? Color.accentColor : Color.primary)
            }
            .popover(isPresented: $showsBackgroundPopover, arrowEdge: .bottom) {
                BackgroundOptionsView(document: document)
            }

            Button {
                document.copyToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .buttonStyle(.borderedProminent)

            Menu {
                Button("Save as Project… (.cleanshotz)") { saveAsProject() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Export Image…") { exportImage() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .help("Project & export options")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Restyle the selected annotation live when any style control changes.
        .onChange(of: document.strokeColor) { document.applyCurrentStyleToSelection() }
        .onChange(of: document.fillColor) { document.applyCurrentStyleToSelection() }
        .onChange(of: document.lineWidth) { document.applyCurrentStyleToSelection() }
        .onChange(of: document.filled) { document.applyCurrentStyleToSelection() }
        .onChange(of: document.fontSize) { document.applyCurrentStyleToSelection() }
        .onChange(of: document.fontDesign) { document.applyCurrentStyleToSelection() }
    }

    // MARK: - Tool column

    private var toolColumn: some View {
        VStack(spacing: 6) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    document.selectedTool = tool
                    document.selectedAnnotationID = nil
                } label: {
                    Image(systemName: tool.symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(document.selectedTool == tool
                                      ? Color.accentColor.opacity(0.25)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tool.helpText)
            }
            Spacer()
        }
        .padding(6)
    }

    // MARK: - Project / export

    /// Saves layers + base image into an editable .cleanshotz project.
    private func saveAsProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = document.fileURL
            .deletingPathExtension().lastPathComponent + ".cleanshotz"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension.lowercased() != ProjectFileCodec.fileExtension {
            url.appendPathExtension(ProjectFileCodec.fileExtension)
        }
        do {
            try ProjectFileCodec.write(document.projectPayload(), to: url)
        } catch {
            NSSound.beep()
        }
    }

    /// Exports the flattened result to a new image file (format by extension).
    private func exportImage() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.fileURL
            .deletingPathExtension().lastPathComponent + ".png"
        guard panel.runModal() == .OK, let url = panel.url,
              let image = document.flattenedImage() else { return }
        let format = CaptureImageFormat.from(fileExtension: url.pathExtension)
        guard let data = CaptureFileWriter.encode(image, format: format, quality: SettingsStore.imageQuality) else {
            NSSound.beep()
            return
        }
        try? data.write(to: url)
    }

    // MARK: - Helpers

    /// Show fill controls for shape-ish tools or when a shape is selected.
    private var showsShapeControls: Bool {
        switch document.selectedTool {
        case .rect, .ellipse, .select: true
        default: false
        }
    }

    /// Show font controls for the text tool or when a text annotation is selected.
    private var showsTextControls: Bool {
        if document.selectedTool == .text { return true }
        if let id = document.selectedAnnotationID,
           let annotation = document.annotation(with: id),
           case .text = annotation.shape { return true }
        return false
    }

}
