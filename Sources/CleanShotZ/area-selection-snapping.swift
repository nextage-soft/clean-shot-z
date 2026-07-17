import AppKit

/// Magnetic edge snapping for the selection overlay: while creating, resizing,
/// or moving a selection, edges within `threshold` of a window edge (or the
/// screen edge) snap onto it — CleanShot's "hít vào cạnh cửa sổ".
struct SelectionSnapGuides {
    /// Candidate edges in view-local coordinates.
    let xs: [CGFloat]
    let ys: [CGFloat]
    static let threshold: CGFloat = 10

    /// Builds candidates from the visible windows overlapping this screen.
    init(visibleWindows: [OnScreenWindowInfo], screen: NSScreen) {
        var xCandidates: Set<CGFloat> = [0, screen.frame.width]
        var yCandidates: Set<CGFloat> = [0, screen.frame.height]
        for window in visibleWindows {
            let local = window.frameAppKit.offsetBy(
                dx: -screen.frame.minX,
                dy: -screen.frame.minY
            )
            guard local.intersects(NSRect(origin: .zero, size: screen.frame.size)) else { continue }
            xCandidates.insert(local.minX)
            xCandidates.insert(local.maxX)
            yCandidates.insert(local.minY)
            yCandidates.insert(local.maxY)
        }
        xs = xCandidates.sorted()
        ys = yCandidates.sorted()
    }

    /// Snaps a point's x/y independently. Returns the snapped values and which
    /// guide lines are active (for drawing).
    func snapPoint(_ point: NSPoint) -> (point: NSPoint, guideX: CGFloat?, guideY: CGFloat?) {
        let sx = Self.nearest(point.x, in: xs)
        let sy = Self.nearest(point.y, in: ys)
        return (
            NSPoint(x: sx ?? point.x, y: sy ?? point.y),
            sx, sy
        )
    }

    /// Snaps a whole rect being MOVED: picks the smallest delta that aligns any
    /// vertical/horizontal edge with a candidate.
    func snapRectForMove(_ rect: NSRect) -> (rect: NSRect, guideX: CGFloat?, guideY: CGFloat?) {
        var dx: CGFloat? = nil
        var guideX: CGFloat? = nil
        for edge in [rect.minX, rect.maxX] {
            if let candidate = Self.nearest(edge, in: xs) {
                let delta = candidate - edge
                if dx == nil || abs(delta) < abs(dx!) { dx = delta; guideX = candidate }
            }
        }
        var dy: CGFloat? = nil
        var guideY: CGFloat? = nil
        for edge in [rect.minY, rect.maxY] {
            if let candidate = Self.nearest(edge, in: ys) {
                let delta = candidate - edge
                if dy == nil || abs(delta) < abs(dy!) { dy = delta; guideY = candidate }
            }
        }
        return (rect.offsetBy(dx: dx ?? 0, dy: dy ?? 0), guideX, guideY)
    }

    private static func nearest(_ value: CGFloat, in candidates: [CGFloat]) -> CGFloat? {
        var best: CGFloat?
        for candidate in candidates where abs(candidate - value) <= threshold {
            if best == nil || abs(candidate - value) < abs(best! - value) {
                best = candidate
            }
        }
        return best
    }
}
