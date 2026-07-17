import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws annotations into a CGContext. The context is expected to be in a FLIPPED
/// coordinate space (top-left origin, y down) matching the annotation coordinates,
/// with `NSGraphicsContext.current` set so AppKit text drawing works.
/// Shared by the on-screen canvas and the export path so screen == output.
enum AnnotationRenderer {
    private static let ciContext = CIContext()

    /// Blur/pixelate results are cached — CIFilter re-rendering on EVERY canvas
    /// draw made editors with several redactions visibly laggy.
    private final class ImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static let filterCache: NSCache<NSString, ImageBox> = {
        let cache = NSCache<NSString, ImageBox>()
        cache.countLimit = 60
        return cache
    }()

    // MARK: - Base image

    /// Draws the base image at (0,0) in a flipped context.
    static func drawBase(_ image: CGImage, in ctx: CGContext) {
        drawImage(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), ctx: ctx)
    }

    /// CGContext.draw is bottom-up; un-flip locally so the image lands upright.
    private static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    // MARK: - Annotations

    static func draw(_ annotation: Annotation, baseImage: CGImage, in ctx: CGContext) {
        let style = annotation.style
        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch annotation.shape {
        case .arrow(let from, let to):
            // Shorten the shaft so its round cap doesn't poke through the head tip.
            let angle = atan2(to.y - from.y, to.x - from.x)
            let headLength = arrowHeadLength(for: style)
            let shaftEnd = CGPoint(
                x: to.x - cos(angle) * headLength * 0.75,
                y: to.y - sin(angle) * headLength * 0.75
            )
            strokeLine(from: from, to: shaftEnd, style: style, ctx: ctx)
            drawArrowHead(from: from, to: to, style: style, ctx: ctx)

        case .line(let from, let to):
            strokeLine(from: from, to: to, style: style, ctx: ctx)

        case .rect(let rect):
            applyStroke(style, ctx: ctx)
            if style.filled {
                ctx.setFillColor(style.fillColor.cgColor)
                ctx.fill(rect)
            }
            ctx.stroke(rect)

        case .ellipse(let rect):
            applyStroke(style, ctx: ctx)
            if style.filled {
                ctx.setFillColor(style.fillColor.cgColor)
                ctx.fillEllipse(in: rect)
            }
            ctx.strokeEllipse(in: rect)

        case .pencil(let points):
            strokePath(points, width: style.lineWidth, color: style.color, ctx: ctx)

        case .highlighter(let points):
            ctx.setBlendMode(.multiply)
            strokePath(
                points,
                width: style.lineWidth * 4,
                color: style.color.withAlphaComponent(0.4),
                ctx: ctx
            )

        case .text(let string, let origin):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: style.font,
                .foregroundColor: style.color,
                .shadow: {
                    let shadow = NSShadow()
                    shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
                    shadow.shadowBlurRadius = 2
                    shadow.shadowOffset = NSSize(width: 0, height: -1)
                    return shadow
                }(),
            ]
            (string as NSString).draw(at: origin, withAttributes: attributes)

        case .counter(let number, let center):
            let radius = style.fontSize * 0.75
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.setFillColor(style.color.cgColor)
            ctx.fillEllipse(in: circle)
            let text = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: radius),
                .foregroundColor: NSColor.white,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                withAttributes: attributes
            )

        case .blur(let rect):
            drawFilteredRegion(rect, baseImage: baseImage, cacheKey: cacheKey("blur", annotation, rect, baseImage), ctx: ctx) { input in
                let filter = CIFilter.gaussianBlur()
                filter.inputImage = input.clampedToExtent()
                filter.radius = 14
                return filter.outputImage?.cropped(to: input.extent)
            }

        case .pixelate(let rect):
            drawFilteredRegion(rect, baseImage: baseImage, cacheKey: cacheKey("pixelate", annotation, rect, baseImage), ctx: ctx) { input in
                let filter = CIFilter.pixellate()
                filter.inputImage = input.clampedToExtent()
                filter.scale = Float(max(12, min(rect.width, rect.height) / 12))
                filter.center = CGPoint(x: input.extent.midX, y: input.extent.midY)
                return filter.outputImage?.cropped(to: input.extent)
            }
        }
    }

    /// Renders the selection indicator: thin dashed outline + white grab handles
    /// (CleanShot-style). `handleRadius` is in image pixels so handles keep a
    /// constant on-screen size regardless of zoom.
    static func drawSelectionIndicator(
        for annotation: Annotation,
        handleRadius: CGFloat,
        in ctx: CGContext
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(handleRadius / 3)
        ctx.setLineDash(phase: 0, lengths: [handleRadius, handleRadius * 0.8])
        ctx.stroke(annotation.boundingRect)
        ctx.setLineDash(phase: 0, lengths: [])

        for handle in annotation.handles {
            let rect = CGRect(
                x: handle.position.x - handleRadius,
                y: handle.position.y - handleRadius,
                width: handleRadius * 2,
                height: handleRadius * 2
            )
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(handleRadius / 3)
            ctx.strokeEllipse(in: rect)
        }
        ctx.restoreGState()
    }

    // MARK: - Background backdrop

    /// Draws the gradient backdrop plus the content's shadow plate, sized
    /// `contentSize + 2*padding`, into a flipped context at origin (0,0).
    /// Caller then translates by (padding, padding), clips to the rounded
    /// content rect, and draws the content.
    static func drawBackdrop(_ background: BackgroundStyle, contentSize: CGSize, in ctx: CGContext) {
        let totalSize = CGSize(
            width: contentSize.width + background.padding * 2,
            height: contentSize.height + background.padding * 2
        )
        let colors = [background.preset.start.cgColor, background.preset.end.cgColor] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0, 1]
        ) {
            ctx.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: totalSize.width, y: totalSize.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        if background.shadow {
            let contentRect = CGRect(
                x: background.padding, y: background.padding,
                width: contentSize.width, height: contentSize.height
            )
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: background.padding * 0.12),
                blur: background.padding * 0.5,
                color: NSColor.black.withAlphaComponent(0.4).cgColor
            )
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(CGPath(
                roundedRect: contentRect,
                cornerWidth: background.cornerRadius, cornerHeight: background.cornerRadius,
                transform: nil
            ))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    /// Applies the rounded-corner clip for the content area at (0,0)…contentSize.
    static func clipToRoundedContent(_ background: BackgroundStyle, contentSize: CGSize, in ctx: CGContext) {
        ctx.addPath(CGPath(
            roundedRect: CGRect(origin: .zero, size: contentSize),
            cornerWidth: background.cornerRadius, cornerHeight: background.cornerRadius,
            transform: nil
        ))
        ctx.clip()
    }

    /// Wraps a flattened content image in the backdrop for export.
    static func compose(content: CGImage, background: BackgroundStyle) -> CGImage? {
        guard background.enabled else { return content }
        let padding = Int(background.padding)
        let width = content.width + padding * 2
        let height = content.height + padding * 2
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return content }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let contentSize = CGSize(width: content.width, height: content.height)
        drawBackdrop(background, contentSize: contentSize, in: ctx)
        ctx.translateBy(x: CGFloat(padding), y: CGFloat(padding))
        clipToRoundedContent(background, contentSize: contentSize, in: ctx)
        drawImage(content, in: CGRect(origin: .zero, size: contentSize), ctx: ctx)
        return ctx.makeImage() ?? content
    }

    // MARK: - Flatten (export)

    static func flatten(baseImage: CGImage, annotations: [Annotation]) -> CGImage? {
        let width = baseImage.width
        let height = baseImage.height
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip to top-left origin so coordinates match the canvas.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.current = previous }

        drawBase(baseImage, in: ctx)
        for annotation in annotations {
            draw(annotation, baseImage: baseImage, in: ctx)
        }
        return ctx.makeImage()
    }

    // MARK: - Helpers

    private static func applyStroke(_ style: AnnotationStyle, ctx: CGContext) {
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
    }

    private static func strokeLine(from: CGPoint, to: CGPoint, style: AnnotationStyle, ctx: CGContext) {
        applyStroke(style, ctx: ctx)
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
    }

    private static func strokePath(_ points: [CGPoint], width: CGFloat, color: NSColor, ctx: CGContext) {
        guard points.count > 1 else { return }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: points[0])
        // Midpoint smoothing gives the pencil a soft, CleanShot-like stroke.
        for index in 1..<points.count - 1 {
            let mid = CGPoint(
                x: (points[index].x + points[index + 1].x) / 2,
                y: (points[index].y + points[index + 1].y) / 2
            )
            ctx.addQuadCurve(to: mid, control: points[index])
        }
        ctx.addLine(to: points[points.count - 1])
        ctx.strokePath()
    }

    private static func arrowHeadLength(for style: AnnotationStyle) -> CGFloat {
        max(16, style.lineWidth * 4)
    }

    private static func drawArrowHead(from: CGPoint, to: CGPoint, style: AnnotationStyle, ctx: CGContext) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength = arrowHeadLength(for: style)
        let headAngle: CGFloat = .pi / 6
        let point1 = CGPoint(
            x: to.x - headLength * cos(angle - headAngle),
            y: to.y - headLength * sin(angle - headAngle)
        )
        let point2 = CGPoint(
            x: to.x - headLength * cos(angle + headAngle),
            y: to.y - headLength * sin(angle + headAngle)
        )
        ctx.setFillColor(style.color.cgColor)
        ctx.move(to: to)
        ctx.addLine(to: point1)
        ctx.addLine(to: point2)
        ctx.closePath()
        ctx.fillPath()
    }

    /// Cache key: annotation + geometry + base-image dims (crop invalidates it).
    private static func cacheKey(
        _ kind: String, _ annotation: Annotation, _ rect: CGRect, _ base: CGImage
    ) -> NSString {
        "\(kind)-\(annotation.id)-\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))-\(base.width)x\(base.height)" as NSString
    }

    /// Crops the base image to `rect`, runs a CIFilter over it, and draws the result back.
    private static func drawFilteredRegion(
        _ rect: CGRect,
        baseImage: CGImage,
        cacheKey: NSString,
        ctx: CGContext,
        filter: (CIImage) -> CIImage?
    ) {
        let bounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        let clamped = rect.integral.intersection(bounds)
        guard !clamped.isEmpty else { return }

        if let cached = filterCache.object(forKey: cacheKey) {
            drawImage(cached.image, in: clamped, ctx: ctx)
            return
        }
        guard let cropped = baseImage.cropping(to: clamped) else { return }
        let input = CIImage(cgImage: cropped)
        guard
            let output = filter(input),
            let rendered = ciContext.createCGImage(output, from: input.extent)
        else { return }
        filterCache.setObject(ImageBox(rendered), forKey: cacheKey)
        drawImage(rendered, in: clamped, ctx: ctx)
    }
}
