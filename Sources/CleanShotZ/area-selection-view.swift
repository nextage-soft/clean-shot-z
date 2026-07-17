import AppKit
import SwiftUI

/// Selection overlay, CleanShot-style. Two modes:
/// - `.immediate`: drag → release → done (quick ⌘⇧4 capture / OCR)
/// - `.allInOne`: drag → selection stays with resize handles + magnetic edge
///   snapping + a floating tool menu (Capture / Scroll / OCR); Enter captures.
/// Clicking a hover-highlighted window (tiny drag) captures that window in both modes.
final class AreaSelectionView: NSView {
    enum Mode { case immediate, allInOne }

    enum SelectionHandle: CaseIterable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    }

    private enum Phase {
        case idle
        case creating
        case adjusting
        case movingSelection
        case resizing(SelectionHandle)
    }

    private let mode: Mode
    private let screen: NSScreen
    private let visibleWindows: [OnScreenWindowInfo]
    private let snapGuides: SelectionSnapGuides
    private let onResult: (AreaSelectionResult?) -> Void

    private var phase: Phase = .idle
    private var selection: NSRect?
    private var cursorPoint: NSPoint?
    private var dragAnchor: NSPoint?      // fixed corner while creating
    private var resizeOriginal: NSRect?   // selection at the moment a resize began
    private var lastDragPoint: NSPoint?
    private var hoveredWindow: OnScreenWindowInfo?
    private var activeGuideX: CGFloat?
    private var activeGuideY: CGFloat?
    private var actionBar: NSHostingView<SelectionActionBarView>?
    private var finished = false

    /// Set by the controller: fired when this screen's view enters `.adjusting`,
    /// so overlays on OTHER screens can drop their own selections/action bars.
    var onDidEnterAdjusting: (() -> Void)?

    private let dimColor = NSColor.black.withAlphaComponent(0.35)
    private let accent = NSColor.systemBlue
    private let handleRadius: CGFloat = 5
    private let handleHitRadius: CGFloat = 10

    init(
        mode: Mode,
        screen: NSScreen,
        visibleWindows: [OnScreenWindowInfo],
        onResult: @escaping (AreaSelectionResult?) -> Void
    ) {
        self.mode = mode
        self.screen = screen
        self.visibleWindows = visibleWindows
        self.snapGuides = SelectionSnapGuides(visibleWindows: visibleWindows, screen: screen)
        self.onResult = onResult
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    /// The very first click must start the drag even if our app isn't active —
    /// without this, that click only "activates" and the drag selects nothing.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func cancel() { finish(nil) }

    /// Drops any in-progress selection and returns to idle (another screen's
    /// overlay took over the adjusting session).
    func resetToIdle() {
        removeActionBar()
        selection = nil
        phase = .idle
        needsDisplay = true
    }

    private func finish(_ result: AreaSelectionResult?) {
        guard !finished else { return }
        finished = true
        onResult(result)
    }

    // MARK: - Coordinates

    private func globalRect(_ local: NSRect) -> NSRect {
        local.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    private func globalPoint(_ local: NSPoint) -> NSPoint {
        NSPoint(x: local.x + screen.frame.minX, y: local.y + screen.frame.minY)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        if case .idle = phase, let point = cursorPoint {
            hoveredWindow = WindowEnumerator.window(at: globalPoint(point), in: visibleWindows)
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastDragPoint = point

        if case .adjusting = phase, let selection {
            if let handle = handleHit(at: point, selection: selection) {
                resizeOriginal = selection
                phase = .resizing(handle)
                return
            }
            if selection.contains(point) {
                phase = .movingSelection
                return
            }
        }
        // Start a fresh selection.
        removeActionBar()
        selection = nil
        dragAnchor = point
        phase = .creating
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        var point = convert(event.locationInWindow, from: nil)
        cursorPoint = point
        activeGuideX = nil
        activeGuideY = nil

        switch phase {
        case .creating:
            let snapped = snapGuides.snapPoint(point)
            point = snapped.point
            activeGuideX = snapped.guideX
            activeGuideY = snapped.guideY
            if let anchor = dragAnchor {
                selection = NSRect(
                    x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                    width: abs(anchor.x - point.x), height: abs(anchor.y - point.y)
                )
            }

        case .resizing(let handle):
            let snapped = snapGuides.snapPoint(point)
            point = snapped.point
            activeGuideX = snapped.guideX
            activeGuideY = snapped.guideY
            if let original = resizeOriginal {
                selection = Self.resize(original, handle: handle, to: point)
            }

        case .movingSelection:
            if var rect = selection, let last = lastDragPoint {
                rect = rect.offsetBy(dx: point.x - last.x, dy: point.y - last.y)
                let snapped = snapGuides.snapRectForMove(rect)
                selection = snapped.rect
                activeGuideX = snapped.guideX
                activeGuideY = snapped.guideY
                // Keep the raw (unsnapped) point as reference so it doesn't drift.
            }

        default:
            break
        }
        lastDragPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { lastDragPoint = nil }
        activeGuideX = nil
        activeGuideY = nil

        switch phase {
        case .creating:
            CaptureCoordinator.log.info(
                "selection mouseUp: rect=\(self.selection.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil", privacy: .public) hovered=\(self.hoveredWindow?.ownerName ?? "none", privacy: .public)"
            )
            guard let rect = selection, rect.width >= 4, rect.height >= 4 else {
                // Tiny drag = click → capture the hovered window.
                selection = nil
                phase = .idle
                if let window = hoveredWindow {
                    CaptureCoordinator.log.info("treated as window click → \(window.ownerName, privacy: .public)")
                    finish(.window(window.windowID))
                }
                needsDisplay = true
                return
            }
            if mode == .immediate {
                finish(.area(globalRect(rect), screen))
            } else {
                phase = .adjusting
                showActionBar()
                onDidEnterAdjusting?()
            }

        case .resizing:
            // Don't let a handle drag collapse the selection to nothing —
            // an invisible selection with a live action bar is a trap.
            if let rect = selection, (rect.width < 8 || rect.height < 8), let original = resizeOriginal {
                selection = original
            }
            resizeOriginal = nil
            phase = .adjusting
            layoutActionBar()

        case .movingSelection:
            phase = .adjusting
            layoutActionBar()

        default:
            break
        }
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // esc
            if case .adjusting = phase {
                removeActionBar()
                selection = nil
                phase = .idle
                needsDisplay = true
            } else {
                finish(nil)
            }
        case 36, 76: // return / keypad enter
            if case .adjusting = phase { performAction(.capture) }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Action bar

    private func performAction(_ action: AreaSelectionAction) {
        guard let selection, selection.width >= 4, selection.height >= 4 else { return }
        finish(.areaAction(globalRect(selection), screen, action))
    }

    private func showActionBar() {
        removeActionBar()
        let bar = NSHostingView(rootView: SelectionActionBarView(
            onAction: { [weak self] action in self?.performAction(action) },
            onCancel: { [weak self] in self?.finish(nil) }
        ))
        bar.frame.size = bar.fittingSize
        addSubview(bar)
        actionBar = bar
        layoutActionBar()
        window?.makeFirstResponder(self)
    }

    private func layoutActionBar() {
        guard let bar = actionBar, let selection else { return }
        var origin = NSPoint(
            x: selection.midX - bar.frame.width / 2,
            y: selection.minY - bar.frame.height - 2
        )
        if origin.y < 0 { origin.y = min(selection.maxY + 2, bounds.height - bar.frame.height) }
        origin.x = max(4, min(origin.x, bounds.width - bar.frame.width - 4))
        bar.setFrameOrigin(origin)
    }

    private func removeActionBar() {
        actionBar?.removeFromSuperview()
        actionBar = nil
    }

    // MARK: - Handles

    private static func handlePoints(for rect: NSRect) -> [(SelectionHandle, NSPoint)] {
        [
            (.topLeft, NSPoint(x: rect.minX, y: rect.maxY)),
            (.top, NSPoint(x: rect.midX, y: rect.maxY)),
            (.topRight, NSPoint(x: rect.maxX, y: rect.maxY)),
            (.left, NSPoint(x: rect.minX, y: rect.midY)),
            (.right, NSPoint(x: rect.maxX, y: rect.midY)),
            (.bottomLeft, NSPoint(x: rect.minX, y: rect.minY)),
            (.bottom, NSPoint(x: rect.midX, y: rect.minY)),
            (.bottomRight, NSPoint(x: rect.maxX, y: rect.minY)),
        ]
    }

    private func handleHit(at point: NSPoint, selection: NSRect) -> SelectionHandle? {
        Self.handlePoints(for: selection).first {
            hypot($0.1.x - point.x, $0.1.y - point.y) <= handleHitRadius
        }?.0
    }

    /// Resizes from the original rect: corner handles move two edges,
    /// mid-edge handles move exactly one axis (the other stays fixed).
    private static func resize(_ rect: NSRect, handle: SelectionHandle, to p: NSPoint) -> NSRect {
        var minX = rect.minX, maxX = rect.maxX
        var minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .topLeft: minX = p.x; maxY = p.y
        case .top: maxY = p.y
        case .topRight: maxX = p.x; maxY = p.y
        case .left: minX = p.x
        case .right: maxX = p.x
        case .bottomLeft: minX = p.x; minY = p.y
        case .bottom: minY = p.y
        case .bottomRight: maxX = p.x; minY = p.y
        }
        return NSRect(
            x: min(minX, maxX), y: min(minY, maxY),
            width: abs(maxX - minX), height: abs(maxY - minY)
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let hasSelection = selection.map { $0.width >= 4 || $0.height >= 4 } ?? false

        dimColor.setFill()
        if let rect = selection, hasSelection {
            fillAround(rect)
            drawSelectionBorder(rect)
            drawSizeLabel(for: rect, near: rect)
            if case .adjusting = phase { drawHandles(rect) }
            if case .movingSelection = phase { drawHandles(rect) }
            if case .resizing = phase { drawHandles(rect) }
        } else if let hovered = hoveredWindow, case .idle = phase,
                  case let rect = localRect(fromGlobal: hovered.frameAppKit).intersection(bounds),
                  !rect.isNull, !rect.isEmpty {
            fillAround(rect)
            accent.withAlphaComponent(0.18).setFill()
            rect.fill()
            drawSelectionBorder(rect)
            drawSizeLabel(for: rect, near: rect)
        } else {
            bounds.fill()
        }

        // Snap guide lines.
        accent.withAlphaComponent(0.85).setStroke()
        if let gx = activeGuideX {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: gx, y: 0))
            path.line(to: NSPoint(x: gx, y: bounds.height))
            path.lineWidth = 1
            path.stroke()
        }
        if let gy = activeGuideY {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: gy))
            path.line(to: NSPoint(x: bounds.width, y: gy))
            path.lineWidth = 1
            path.stroke()
        }

        // Crosshair while nothing is being adjusted.
        if let cursor = cursorPoint, case .idle = phase {
            accent.withAlphaComponent(0.8).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: cursor.x, y: 0))
            path.line(to: NSPoint(x: cursor.x, y: bounds.height))
            path.move(to: NSPoint(x: 0, y: cursor.y))
            path.line(to: NSPoint(x: bounds.width, y: cursor.y))
            path.stroke()
        }
    }

    private func localRect(fromGlobal rect: NSRect) -> NSRect {
        rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    private func fillAround(_ hole: NSRect) {
        let clamped = hole.intersection(bounds)
        guard !clamped.isNull else { bounds.fill(); return }
        NSRect(x: 0, y: 0, width: bounds.width, height: clamped.minY).fill()
        NSRect(x: 0, y: clamped.maxY, width: bounds.width, height: bounds.height - clamped.maxY).fill()
        NSRect(x: 0, y: clamped.minY, width: clamped.minX, height: clamped.height).fill()
        NSRect(x: clamped.maxX, y: clamped.minY, width: bounds.width - clamped.maxX, height: clamped.height).fill()
    }

    private func drawSelectionBorder(_ rect: NSRect) {
        accent.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawHandles(_ rect: NSRect) {
        for (_, point) in Self.handlePoints(for: rect) {
            let handleRect = NSRect(
                x: point.x - handleRadius, y: point.y - handleRadius,
                width: handleRadius * 2, height: handleRadius * 2
            )
            NSColor.white.setFill()
            NSBezierPath(ovalIn: handleRect).fill()
            accent.setStroke()
            let ring = NSBezierPath(ovalIn: handleRect)
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    private func drawSizeLabel(for rect: NSRect, near anchor: NSRect) {
        guard rect.width.isFinite, rect.height.isFinite,
              anchor.midX.isFinite, anchor.minY.isFinite else { return }
        let scale = screen.backingScaleFactor
        let text = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 6
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 8)
        if origin.y + size.height > bounds.height - 4 { origin.y = anchor.maxY - size.height - 12 }
        origin.x = max(4, min(origin.x, bounds.width - size.width - 4))
        let background = NSRect(
            x: origin.x - padding, y: origin.y - padding / 2,
            width: size.width + padding * 2, height: size.height + padding
        )
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
