import AppKit

/// Stroke-accurate hit-testing so clicking behaves the way it looks:
/// lines/arrows hit near the stroke, hollow shapes hit near the border only,
/// filled/area shapes hit anywhere inside.
extension Annotation {
    func containsPoint(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let strokeReach = style.lineWidth / 2 + tolerance
        switch shape {
        case .arrow(let from, let to), .line(let from, let to):
            return Self.distanceToSegment(point, from, to) <= strokeReach

        case .rect(let rect):
            if style.filled { return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
            return Self.isNearRectBorder(point, rect: rect, reach: strokeReach)

        case .ellipse(let rect):
            guard rect.width > 0, rect.height > 0 else { return false }
            // Normalize to a unit circle and compare radial distance.
            let dx = (point.x - rect.midX) / (rect.width / 2)
            let dy = (point.y - rect.midY) / (rect.height / 2)
            let radial = sqrt(dx * dx + dy * dy)
            if style.filled { return radial <= 1 + tolerance / min(rect.width, rect.height) * 2 }
            let border = strokeReach / (min(rect.width, rect.height) / 2)
            return abs(radial - 1) <= border

        case .pencil(let points), .highlighter(let points):
            let reach: CGFloat = {
                if case .highlighter = shape { return style.lineWidth * 2 + tolerance }
                return strokeReach
            }()
            guard points.count > 1 else {
                return points.first.map { hypot($0.x - point.x, $0.y - point.y) <= reach } ?? false
            }
            for index in 0..<points.count - 1 {
                if Self.distanceToSegment(point, points[index], points[index + 1]) <= reach {
                    return true
                }
            }
            return false

        case .text, .counter, .blur, .pixelate:
            return boundingRect.contains(point)
        }
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abX = b.x - a.x
        let abY = b.y - a.y
        let lengthSquared = abX * abX + abY * abY
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * abX + (p.y - a.y) * abY) / lengthSquared))
        let closest = CGPoint(x: a.x + t * abX, y: a.y + t * abY)
        return hypot(p.x - closest.x, p.y - closest.y)
    }

    private static func isNearRectBorder(_ point: CGPoint, rect: CGRect, reach: CGFloat) -> Bool {
        let outer = rect.insetBy(dx: -reach, dy: -reach)
        let inner = rect.insetBy(dx: reach, dy: reach)
        return outer.contains(point) && !(inner.width > 0 && inner.height > 0 && inner.contains(point))
    }
}
