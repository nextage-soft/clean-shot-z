import AppKit

/// Mouse & keyboard interaction for the editor canvas (CleanShot-style):
/// - handle under cursor → resize; annotation under cursor → select + move
/// - empty canvas + drawing tool → draw new annotation (auto-selected on mouse-up)
/// - single-letter tool shortcuts, Delete removes, Esc deselects
extension AnnotationCanvasView {

    // MARK: - Mouse down

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // Clicking anywhere while editing text just commits the text —
        // it never creates a new annotation in the same click (Snapzy behavior).
        if isEditingText {
            commitTextEditing()
            dragMode = .none
            needsDisplay = true
            return
        }
        let point = imagePoint(event)
        dragStartPoint = point
        lastDragPoint = point

        // 1. Grab handle of the selected annotation → resize.
        if let selectedID = document.selectedAnnotationID, let handleKind = hitHandle(at: point) {
            needsUndoRegistrationOnDrag = true
            dragMode = .resizing(selectedID, handleKind)
            return
        }

        // 2. Crop tool always drags a crop region.
        if document.selectedTool == .crop {
            dragMode = .cropping
            cropRect = CGRect(origin: point, size: .zero)
            needsDisplay = true
            return
        }

        // 3. Existing annotation under cursor → select + move (works with ANY tool).
        if let hit = document.hitTest(point, tolerance: handleHitRadius) {
            if event.clickCount == 2, case .text = hit.shape {
                document.selectedAnnotationID = hit.id
                beginTextEditing(annotation: hit)
                dragMode = .none
                return
            }
            document.selectedAnnotationID = hit.id
            loadStyleControls(from: hit)
            syncToolbarTool(to: hit)
            needsUndoRegistrationOnDrag = true
            dragMode = .moving(hit.id)
            needsDisplay = true
            return
        }

        // 4. Empty canvas → draw with the active tool (or deselect for Select).
        document.selectedAnnotationID = nil
        let style = document.currentStyle

        switch document.selectedTool {
        case .select, .crop:
            dragMode = .none

        case .arrow, .line:
            document.registerUndoPoint()
            let shape: AnnotationShape = document.selectedTool == .arrow
                ? .arrow(from: point, to: point) : .line(from: point, to: point)
            let annotation = Annotation(shape: shape, style: style)
            document.add(annotation)
            dragMode = .drawing(annotation.id)

        case .rect, .ellipse, .blur, .pixelate:
            document.registerUndoPoint()
            let rect = CGRect(origin: point, size: .zero)
            let shape: AnnotationShape = switch document.selectedTool {
            case .rect: .rect(rect)
            case .ellipse: .ellipse(rect)
            case .blur: .blur(rect)
            default: .pixelate(rect)
            }
            let annotation = Annotation(shape: shape, style: style)
            document.add(annotation)
            dragMode = .drawing(annotation.id)

        case .pencil, .highlighter:
            document.registerUndoPoint()
            let shape: AnnotationShape = document.selectedTool == .pencil
                ? .pencil([point]) : .highlighter([point])
            let annotation = Annotation(shape: shape, style: style)
            document.add(annotation)
            dragMode = .drawing(annotation.id)

        case .text:
            document.registerUndoPoint()
            let annotation = Annotation(shape: .text("", origin: point), style: style)
            document.add(annotation)
            document.selectedAnnotationID = annotation.id
            beginTextEditing(annotation: annotation)
            dragMode = .none

        case .counter:
            document.registerUndoPoint()
            let annotation = Annotation(
                shape: .counter(document.counterNextNumber, center: point),
                style: style
            )
            document.add(annotation)
            document.counterNextNumber += 1
            document.selectedAnnotationID = annotation.id
            dragMode = .moving(annotation.id)
        }
        needsDisplay = true
    }

    // MARK: - Mouse drag

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartPoint else { return }
        var point = imagePoint(event)
        let shiftHeld = event.modifierFlags.contains(.shift)

        if needsUndoRegistrationOnDrag {
            needsUndoRegistrationOnDrag = false
            document.registerUndoPoint()
        }

        switch dragMode {
        case .none:
            break

        case .resizing(let id, let handleKind):
            guard var annotation = document.annotation(with: id) else { break }
            if shiftHeld { point = shiftConstrainedResizePoint(point, annotation: annotation, handle: handleKind) }
            annotation.moveHandle(handleKind, to: point)
            document.update(annotation)

        case .moving(let id):
            guard var annotation = document.annotation(with: id), let last = lastDragPoint else { break }
            annotation.translate(by: CGPoint(x: point.x - last.x, y: point.y - last.y))
            document.update(annotation)

        case .cropping:
            if shiftHeld { point = squareConstrained(point, from: start) }
            cropRect = normalizedRect(from: start, to: point)

        case .drawing(let id):
            guard var annotation = document.annotation(with: id) else { break }
            if shiftHeld {
                switch document.selectedTool {
                case .rect, .ellipse, .blur, .pixelate: point = squareConstrained(point, from: start)
                case .arrow, .line: point = angleSnapped(point, from: start)
                default: break
                }
            }
            let dragRect = normalizedRect(from: start, to: point)
            switch annotation.shape {
            case .arrow(let from, _): annotation.shape = .arrow(from: from, to: point)
            case .line(let from, _): annotation.shape = .line(from: from, to: point)
            case .rect: annotation.shape = .rect(dragRect)
            case .ellipse: annotation.shape = .ellipse(dragRect)
            case .blur: annotation.shape = .blur(dragRect)
            case .pixelate: annotation.shape = .pixelate(dragRect)
            case .pencil(var points): points.append(point); annotation.shape = .pencil(points)
            case .highlighter(var points): points.append(point); annotation.shape = .highlighter(points)
            default: break
            }
            document.update(annotation)
        }
        lastDragPoint = point
        needsDisplay = true
    }

    // MARK: - Mouse up

    override func mouseUp(with event: NSEvent) {
        defer {
            dragMode = .none
            dragStartPoint = nil
            lastDragPoint = nil
            needsUndoRegistrationOnDrag = false
        }

        switch dragMode {
        case .cropping:
            if let crop = cropRect, crop.width > 8, crop.height > 8 {
                document.applyCrop(crop)
            }
            cropRect = nil

        case .drawing(let id):
            guard document.annotation(with: id) != nil else { break }
            // A shape only counts if the mouse actually traveled (~3px in image space);
            // stray clicks with a drag tool produce nothing (Snapzy: 2px display threshold).
            var travel: CGFloat = 0
            if let start = dragStartPoint, let last = lastDragPoint {
                travel = hypot(start.x - last.x, start.y - last.y)
            }
            if travel < 3 / displayScale {
                document.annotations.removeAll { $0.id == id }
                document.cancelLastUndoPoint() // the gesture ended up a no-op
            } else {
                // Auto-select the fresh annotation so handles appear immediately.
                document.selectedAnnotationID = id
            }

        default:
            break
        }
        needsDisplay = true
    }

    // MARK: - Cursor feedback

    override func mouseMoved(with event: NSEvent) {
        let point = imagePoint(event)
        if hitHandle(at: point) != nil {
            NSCursor.crosshair.set()
        } else if let hover = document.hitTest(point, tolerance: handleHitRadius) {
            // Open hand on the selected item (grab to move), pointing hand on others.
            (hover.id == document.selectedAnnotationID ? NSCursor.openHand : NSCursor.pointingHand).set()
        } else if document.selectedTool == .select {
            NSCursor.arrow.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Single-letter tool shortcuts (same spirit as CleanShot: A, R, O, T, N, B...).
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let characters = event.charactersIgnoringModifiers?.lowercased(),
           let tool = Self.toolShortcuts[characters] {
            document.selectedTool = tool
            return
        }
        switch event.keyCode {
        case 51, 117: // delete / forward delete
            document.removeSelected()
            needsDisplay = true
        case 53: // esc
            document.selectedAnnotationID = nil
            cropRect = nil
            commitTextEditing()
            needsDisplay = true
        case 123, 124, 125, 126: // arrow keys → nudge selection (Shift = 10px)
            nudgeSelection(keyCode: event.keyCode, big: event.modifierFlags.contains(.shift))
        default:
            super.keyDown(with: event)
        }
    }

    private func nudgeSelection(keyCode: UInt16, big: Bool) {
        guard let id = document.selectedAnnotationID,
              var annotation = document.annotation(with: id) else { return }
        let step: CGFloat = big ? 10 : 1
        let delta: CGPoint = switch keyCode {
        case 123: CGPoint(x: -step, y: 0)
        case 124: CGPoint(x: step, y: 0)
        case 125: CGPoint(x: 0, y: step)
        default: CGPoint(x: 0, y: -step)
        }
        document.registerUndoPoint()
        annotation.translate(by: delta)
        document.update(annotation)
        needsDisplay = true
    }

    /// Selecting an item switches the toolbar to that item's tool (Snapzy behavior),
    /// so the contextual style controls always match what's selected.
    private func syncToolbarTool(to annotation: Annotation) {
        switch annotation.shape {
        case .arrow: document.selectedTool = .arrow
        case .line: document.selectedTool = .line
        case .rect: document.selectedTool = .rect
        case .ellipse: document.selectedTool = .ellipse
        case .pencil: document.selectedTool = .pencil
        case .highlighter: document.selectedTool = .highlighter
        case .text: document.selectedTool = .text
        case .counter: document.selectedTool = .counter
        case .blur: document.selectedTool = .blur
        case .pixelate: document.selectedTool = .pixelate
        }
    }

    private static let toolShortcuts: [String: AnnotationTool] = [
        "v": .select, "a": .arrow, "l": .line, "r": .rect, "o": .ellipse,
        "p": .pencil, "h": .highlighter, "t": .text, "n": .counter,
        "b": .blur, "x": .pixelate, "c": .crop,
    ]

    // MARK: - Geometry helpers

    private func normalizedRect(from start: CGPoint, to point: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, point.x), y: min(start.y, point.y),
            width: abs(start.x - point.x), height: abs(start.y - point.y)
        )
    }

    private func squareConstrained(_ point: CGPoint, from start: CGPoint) -> CGPoint {
        let side = max(abs(point.x - start.x), abs(point.y - start.y))
        return CGPoint(
            x: start.x + (point.x < start.x ? -side : side),
            y: start.y + (point.y < start.y ? -side : side)
        )
    }

    private func angleSnapped(_ point: CGPoint, from origin: CGPoint) -> CGPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let distance = hypot(dx, dy)
        let snapped = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        return CGPoint(x: origin.x + cos(snapped) * distance, y: origin.y + sin(snapped) * distance)
    }

    /// Shift while resizing: squares for rect-ish shapes, 45° snap for line/arrow endpoints.
    private func shiftConstrainedResizePoint(
        _ point: CGPoint,
        annotation: Annotation,
        handle: Annotation.HandleKind
    ) -> CGPoint {
        switch annotation.shape {
        case .arrow(let from, let to), .line(let from, let to):
            let fixed = handle == .start ? to : from
            return angleSnapped(point, from: fixed)
        case .rect, .ellipse, .blur, .pixelate:
            // Anchor = the corner opposite the dragged handle.
            guard let anchor = annotation.handles.first(where: { $0.kind == oppositeCorner(of: handle) })?.position
            else { return point }
            return squareConstrained(point, from: anchor)
        default:
            return point
        }
    }

    private func oppositeCorner(of kind: Annotation.HandleKind) -> Annotation.HandleKind {
        switch kind {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        case .start: .end
        case .end: .start
        }
    }
}
