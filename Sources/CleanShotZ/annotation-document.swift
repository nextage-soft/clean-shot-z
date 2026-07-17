import AppKit
import Combine

/// Editor state for one capture: base image + annotation layers + undo/redo.
/// All geometry is in base-image pixel coordinates.
@MainActor
final class AnnotationDocument: ObservableObject {
    @Published var baseImage: CGImage
    @Published var annotations: [Annotation] = []
    @Published var selectedTool: AnnotationTool = .arrow
    @Published var strokeColor: NSColor = .systemRed
    @Published var fillColor: NSColor = NSColor.systemRed.withAlphaComponent(0.3)
    @Published var lineWidth: CGFloat = 6
    @Published var filled: Bool = false
    @Published var fontSize: CGFloat = 36
    @Published var fontDesign: FontDesignChoice = .standard
    /// Number the next counter stamp will get (user-editable, auto-increments).
    @Published var counterNextNumber: Int = 1
    @Published var selectedAnnotationID: UUID?
    /// Gradient backdrop (padding + rounded corners + shadow) applied on export.
    @Published var background = BackgroundStyle()

    let fileURL: URL

    private struct Snapshot {
        let baseImage: CGImage
        let annotations: [Annotation]
        let counterNextNumber: Int
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var lastStyleUndoAnnotationID: UUID?
    private var lastStyleUndoAt = Date.distantPast

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(baseImage: CGImage, fileURL: URL) {
        self.baseImage = baseImage
        self.fileURL = fileURL
    }

    var currentStyle: AnnotationStyle {
        AnnotationStyle(
            color: strokeColor,
            fillColor: fillColor,
            lineWidth: lineWidth,
            filled: filled,
            fontSize: fontSize,
            fontDesign: fontDesign
        )
    }

    /// Live-applies the current style controls to the selected annotation
    /// (lets the user restyle an arrow/text/shape after drawing it).
    /// Registers ONE undo point per restyle burst (debounced), so a slider drag
    /// is a single undoable step and Cmd+Z actually reverts the color change.
    func applyCurrentStyleToSelection() {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        // Selecting an annotation syncs the controls TO its style, which fires
        // onChange with identical values — don't record a no-op undo for that.
        guard annotations[index].style != currentStyle else { return }
        if id != lastStyleUndoAnnotationID || Date().timeIntervalSince(lastStyleUndoAt) > 1.5 {
            registerUndoPoint()
        }
        lastStyleUndoAnnotationID = id
        lastStyleUndoAt = Date()
        annotations[index].style = currentStyle
    }

    // MARK: - Undo / redo

    /// Call BEFORE any mutation that should be undoable.
    func registerUndoPoint() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
    }

    /// Drops the most recent undo point — used when a gesture that registered
    /// one turns out to be a no-op (tiny drag discarded, empty text removed),
    /// so Cmd+Z never appears to "do nothing".
    func cancelLastUndoPoint() {
        _ = undoStack.popLast()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restore(snapshot)
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(baseImage: baseImage, annotations: annotations, counterNextNumber: counterNextNumber)
    }

    private func restore(_ snapshot: Snapshot) {
        baseImage = snapshot.baseImage
        annotations = snapshot.annotations
        counterNextNumber = snapshot.counterNextNumber
        selectedAnnotationID = nil
    }

    // MARK: - Mutations

    func add(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    func annotation(with id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func removeSelected() {
        guard let id = selectedAnnotationID else { return }
        registerUndoPoint()
        annotations.removeAll { $0.id == id }
        selectedAnnotationID = nil
    }

    /// Topmost annotation under the point, using stroke-accurate hit-testing.
    func hitTest(_ point: CGPoint, tolerance: CGFloat = 6) -> Annotation? {
        annotations.reversed().first { $0.containsPoint(point, tolerance: tolerance) }
    }

    /// Crops the base image and shifts all annotations accordingly.
    func applyCrop(_ rect: CGRect) {
        let pixelRect = rect.integral.intersection(
            CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        )
        guard !pixelRect.isEmpty, let cropped = baseImage.cropping(to: pixelRect) else { return }
        registerUndoPoint()
        baseImage = cropped
        let delta = CGPoint(x: -pixelRect.minX, y: -pixelRect.minY)
        annotations = annotations.map { annotation in
            var moved = annotation
            moved.translate(by: delta)
            return moved
        }
    }

    // MARK: - Output

    func flattenedImage() -> CGImage? {
        guard let content = AnnotationRenderer.flatten(baseImage: baseImage, annotations: annotations) else {
            return nil
        }
        return AnnotationRenderer.compose(content: content, background: background)
    }

    func saveToFile() throws {
        // Projects keep their layers; images get flattened in their own format.
        if fileURL.pathExtension.lowercased() == ProjectFileCodec.fileExtension {
            try ProjectFileCodec.write(projectPayload(), to: fileURL)
            return
        }
        guard let image = flattenedImage() else { return }
        let format = CaptureImageFormat.from(fileExtension: fileURL.pathExtension)
        guard let data = CaptureFileWriter.encode(image, format: format, quality: SettingsStore.imageQuality) else {
            return
        }
        try data.write(to: fileURL)
    }

    func projectPayload() -> ProjectFilePayload {
        ProjectFilePayload(
            baseImage: baseImage,
            annotations: annotations,
            background: background,
            counterNextNumber: counterNextNumber
        )
    }

    func restore(from payload: ProjectFilePayload) {
        annotations = payload.annotations
        background = payload.background
        counterNextNumber = payload.counterNextNumber
    }

    func copyToClipboard() {
        guard let image = flattenedImage() else { return }
        CaptureFileWriter.copyToClipboard(image)
    }
}
