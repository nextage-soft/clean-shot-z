import AppKit

/// Tools available in the editor (mirrors CleanShot X's left toolbar).
enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rect, ellipse, pencil, highlighter, text, counter, blur, pixelate, crop

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .pencil: "pencil"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .blur: "drop.halffull"
        case .pixelate: "mosaic"
        case .crop: "crop"
        }
    }

    var helpText: String {
        switch self {
        case .select: "Select & move"
        case .arrow: "Arrow"
        case .line: "Line"
        case .rect: "Rectangle"
        case .ellipse: "Ellipse"
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .counter: "Counter"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        case .crop: "Crop"
        }
    }
}

/// Font family choice for the text tool.
enum FontDesignChoice: String, CaseIterable, Identifiable {
    case standard = "System"
    case rounded = "Rounded"
    case serif = "Serif"
    case monospaced = "Mono"

    var id: String { rawValue }

    var systemDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

/// Visual style shared by annotations. Coordinates/sizes are in base-image pixels.
struct AnnotationStyle: Equatable {
    /// Stroke / foreground color (border of shapes, line color, text color).
    var color: NSColor = .systemRed
    /// Background color for filled shapes.
    var fillColor: NSColor = NSColor.systemRed.withAlphaComponent(0.3)
    var lineWidth: CGFloat = 6
    var filled: Bool = false
    var fontSize: CGFloat = 36
    var fontDesign: FontDesignChoice = .standard

    /// Font used by the text tool (bold, honoring the chosen design).
    var font: NSFont {
        let base = NSFont.boldSystemFont(ofSize: fontSize)
        guard fontDesign != .standard,
              let descriptor = base.fontDescriptor.withDesign(fontDesign.systemDesign),
              let designed = NSFont(descriptor: descriptor, size: fontSize)
        else { return base }
        return designed
    }
}

/// Geometry of one annotation layer, in base-image pixel coordinates (top-left origin).
enum AnnotationShape {
    case arrow(from: CGPoint, to: CGPoint)
    case line(from: CGPoint, to: CGPoint)
    case rect(CGRect)
    case ellipse(CGRect)
    case pencil([CGPoint])
    case highlighter([CGPoint])
    case text(String, origin: CGPoint)
    case counter(Int, center: CGPoint)
    case blur(CGRect)
    case pixelate(CGRect)
}

struct Annotation: Identifiable {
    let id: UUID
    var shape: AnnotationShape
    var style: AnnotationStyle

    init(shape: AnnotationShape, style: AnnotationStyle) {
        self.id = UUID()
        self.shape = shape
        self.style = style
    }

    /// Approximate bounds used for hit-testing and the selection indicator.
    var boundingRect: CGRect {
        switch shape {
        case .arrow(let from, let to), .line(let from, let to):
            return CGRect(origin: from, size: .zero).union(CGRect(origin: to, size: .zero))
                .insetBy(dx: -style.lineWidth * 2, dy: -style.lineWidth * 2)
        case .rect(let rect), .ellipse(let rect), .blur(let rect), .pixelate(let rect):
            return rect.insetBy(dx: -style.lineWidth, dy: -style.lineWidth)
        case .pencil(let points), .highlighter(let points):
            guard let first = points.first else { return .zero }
            var rect = CGRect(origin: first, size: .zero)
            for point in points.dropFirst() {
                rect = rect.union(CGRect(origin: point, size: .zero))
            }
            return rect.insetBy(dx: -style.lineWidth * 2.5, dy: -style.lineWidth * 2.5)
        case .text(let string, let origin):
            let size = (string as NSString).size(withAttributes: [.font: style.font])
            return CGRect(origin: origin, size: size).insetBy(dx: -6, dy: -6)
        case .counter(_, let center):
            let radius = style.fontSize * 0.75
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    // MARK: - Resize handles (CleanShot-style: every annotation is adjustable after drawing)

    enum HandleKind: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight // rect-ish shapes
        case start, end                                 // lines & arrows
    }

    /// Grabbable handles for this annotation (empty = move-only).
    var handles: [(kind: HandleKind, position: CGPoint)] {
        switch shape {
        case .arrow(let from, let to), .line(let from, let to):
            return [(.start, from), (.end, to)]
        case .rect(let rect), .ellipse(let rect), .blur(let rect), .pixelate(let rect):
            return [
                (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
                (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
                (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
                (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            ]
        default:
            return []
        }
    }

    /// Drags one handle to a new position, reshaping the annotation.
    mutating func moveHandle(_ kind: HandleKind, to point: CGPoint) {
        func resized(_ rect: CGRect) -> CGRect {
            // The dragged corner follows the mouse; the opposite corner stays put.
            let anchor: CGPoint = switch kind {
            case .topLeft: CGPoint(x: rect.maxX, y: rect.maxY)
            case .topRight: CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomLeft: CGPoint(x: rect.maxX, y: rect.minY)
            default: CGPoint(x: rect.minX, y: rect.minY)
            }
            return CGRect(
                x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                width: abs(anchor.x - point.x), height: abs(anchor.y - point.y)
            )
        }
        switch shape {
        case .arrow(let from, let to):
            shape = kind == .start ? .arrow(from: point, to: to) : .arrow(from: from, to: point)
        case .line(let from, let to):
            shape = kind == .start ? .line(from: point, to: to) : .line(from: from, to: point)
        case .rect(let rect): shape = .rect(resized(rect))
        case .ellipse(let rect): shape = .ellipse(resized(rect))
        case .blur(let rect): shape = .blur(resized(rect))
        case .pixelate(let rect): shape = .pixelate(resized(rect))
        default: break
        }
    }

    /// Moves the whole annotation by a delta (select tool drag).
    mutating func translate(by delta: CGPoint) {
        func moved(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.x, y: p.y + delta.y) }
        func moved(_ r: CGRect) -> CGRect { r.offsetBy(dx: delta.x, dy: delta.y) }
        switch shape {
        case .arrow(let from, let to): shape = .arrow(from: moved(from), to: moved(to))
        case .line(let from, let to): shape = .line(from: moved(from), to: moved(to))
        case .rect(let rect): shape = .rect(moved(rect))
        case .ellipse(let rect): shape = .ellipse(moved(rect))
        case .pencil(let points): shape = .pencil(points.map(moved))
        case .highlighter(let points): shape = .highlighter(points.map(moved))
        case .text(let string, let origin): shape = .text(string, origin: moved(origin))
        case .counter(let number, let center): shape = .counter(number, center: moved(center))
        case .blur(let rect): shape = .blur(moved(rect))
        case .pixelate(let rect): shape = .pixelate(moved(rect))
        }
    }
}
