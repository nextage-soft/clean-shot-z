import AppKit

/// The editor canvas: draws base image + annotation layers at a fixed fit scale.
/// Interaction model follows CleanShot X (see annotation-canvas-mouse-handling.swift):
/// - with ANY tool, clicking an existing annotation selects it; dragging moves it
/// - a freshly drawn annotation is auto-selected with grab handles for resizing
/// - drawing starts only from empty canvas space
/// View coordinates are image pixels * displayScale, flipped (top-left origin).
@MainActor
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    let document: AnnotationDocument
    let displayScale: CGFloat

    enum DragMode {
        case none
        case drawing(UUID)
        case moving(UUID)
        case resizing(UUID, Annotation.HandleKind)
        case cropping
    }

    var dragMode: DragMode = .none
    var dragStartPoint: CGPoint?
    var lastDragPoint: CGPoint?
    var cropRect: CGRect?
    /// Set on mouseDown for move/resize; the undo point is registered lazily on
    /// the FIRST actual drag, so a plain selection click never pollutes undo.
    var needsUndoRegistrationOnDrag = false
    private var textEditor: NSTextField?
    private var editingTextID: UUID?

    /// Handle sizes in image pixels, chosen so they stay constant on screen.
    var handleDrawRadius: CGFloat { 5 / displayScale }
    var handleHitRadius: CGFloat { 10 / displayScale }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(document: AnnotationDocument, displayScale: CGFloat) {
        self.document = document
        self.displayScale = displayScale
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Padding around the content when the background backdrop is on (image px).
    var backdropPadding: CGFloat {
        document.background.enabled ? document.background.padding : 0
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: (CGFloat(document.baseImage.width) + backdropPadding * 2) * displayScale,
            height: (CGFloat(document.baseImage.height) + backdropPadding * 2) * displayScale
        )
    }

    func documentDidChange() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: displayScale, y: displayScale)
        ctx.interpolationQuality = .high

        let contentSize = CGSize(
            width: document.baseImage.width,
            height: document.baseImage.height
        )
        if document.background.enabled {
            AnnotationRenderer.drawBackdrop(document.background, contentSize: contentSize, in: ctx)
            ctx.translateBy(x: backdropPadding, y: backdropPadding)
        }

        ctx.saveGState()
        if document.background.enabled {
            AnnotationRenderer.clipToRoundedContent(document.background, contentSize: contentSize, in: ctx)
        }
        AnnotationRenderer.drawBase(document.baseImage, in: ctx)
        for annotation in document.annotations {
            AnnotationRenderer.draw(annotation, baseImage: document.baseImage, in: ctx)
        }
        ctx.restoreGState()
        if let selectedID = document.selectedAnnotationID,
           let selected = document.annotation(with: selectedID) {
            AnnotationRenderer.drawSelectionIndicator(
                for: selected,
                handleRadius: handleDrawRadius,
                in: ctx
            )
        }
        if let crop = cropRect {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
            let outside = CGRect(x: 0, y: 0, width: document.baseImage.width, height: document.baseImage.height)
            ctx.saveGState()
            ctx.addRect(outside)
            ctx.addRect(crop)
            ctx.clip(using: .evenOdd)
            ctx.fill(outside)
            ctx.restoreGState()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(2 / displayScale)
            ctx.stroke(crop)
        }
        ctx.restoreGState()
    }

    // MARK: - Coordinate helpers

    func imagePoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: local.x / displayScale - backdropPadding,
            y: local.y / displayScale - backdropPadding
        )
    }

    /// Handle of the SELECTED annotation under the point, if any.
    func hitHandle(at point: CGPoint) -> Annotation.HandleKind? {
        guard let id = document.selectedAnnotationID,
              let annotation = document.annotation(with: id) else { return nil }
        return annotation.handles.first {
            hypot($0.position.x - point.x, $0.position.y - point.y) <= handleHitRadius
        }?.kind
    }

    /// Reflect the selected annotation's style in the top-bar controls.
    func loadStyleControls(from annotation: Annotation) {
        document.strokeColor = annotation.style.color
        document.fillColor = annotation.style.fillColor
        document.lineWidth = annotation.style.lineWidth
        document.filled = annotation.style.filled
        document.fontSize = annotation.style.fontSize
        document.fontDesign = annotation.style.fontDesign
    }

    // MARK: - Inline text editing

    var isEditingText: Bool { textEditor != nil }

    func beginTextEditing(annotation: Annotation) {
        guard case .text(let string, let origin) = annotation.shape else { return }
        commitTextEditing()
        let field = NSTextField(string: string)
        let editingFont = annotation.style.font
        field.font = NSFont(descriptor: editingFont.fontDescriptor, size: editingFont.pointSize * displayScale)
        field.textColor = annotation.style.color
        field.isBordered = true
        field.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.85)
        field.delegate = self
        field.frame = NSRect(
            x: (origin.x + backdropPadding) * displayScale - 2,
            y: (origin.y + backdropPadding) * displayScale - 2,
            width: max(160, CGFloat(string.count) * annotation.style.fontSize * displayScale * 0.6 + 40),
            height: annotation.style.fontSize * displayScale + 12
        )
        addSubview(field)
        window?.makeFirstResponder(field)
        textEditor = field
        editingTextID = annotation.id
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitTextEditing()
    }

    func commitTextEditing() {
        guard let field = textEditor, let id = editingTextID else { return }
        let value = field.stringValue
        field.removeFromSuperview()
        textEditor = nil
        editingTextID = nil
        if var annotation = document.annotation(with: id), case .text(_, let origin) = annotation.shape {
            if value.trimmingCharacters(in: .whitespaces).isEmpty {
                document.annotations.removeAll { $0.id == id }
                document.cancelLastUndoPoint() // empty text = the creation was a no-op
            } else {
                annotation.shape = .text(value, origin: origin)
                document.update(annotation)
            }
        }
        needsDisplay = true
    }
}
