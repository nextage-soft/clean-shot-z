import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The `.cleanshotz` non-destructive project format.
/// Layout: "CSZP" magic (4 bytes) + big-endian UInt32 JSON length + JSON + PNG.
/// JSON holds the annotation layers/background; PNG is the untouched base image.
enum ProjectFileError: Error {
    case invalidFormat
    case encodingFailed
}

struct ProjectFilePayload {
    let baseImage: CGImage
    let annotations: [Annotation]
    let background: BackgroundStyle
    let counterNextNumber: Int
}

enum ProjectFileCodec {
    static let fileExtension = "cleanshotz"
    private static let magic = Array("CSZP".utf8)

    // MARK: - Write

    static func write(_ payload: ProjectFilePayload, to url: URL) throws {
        let root = RootDTO(
            version: 1,
            background: BackgroundDTO(payload.background),
            counterNextNumber: payload.counterNextNumber,
            annotations: payload.annotations.map(AnnotationDTO.init)
        )
        let json = try JSONEncoder().encode(root)
        guard let png = CaptureFileWriter.encode(payload.baseImage, format: .png, quality: 1) else {
            throw ProjectFileError.encodingFailed
        }
        var data = Data(magic)
        var length = UInt32(json.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(json)
        data.append(png)
        try data.write(to: url)
    }

    // MARK: - Read

    static func read(from url: URL) throws -> ProjectFilePayload {
        let data = try Data(contentsOf: url)
        guard data.count > 8, Array(data.prefix(4)) == magic else {
            throw ProjectFileError.invalidFormat
        }
        let length = data.subdata(in: 4..<8).withUnsafeBytes {
            UInt32(bigEndian: $0.load(as: UInt32.self))
        }
        let jsonEnd = 8 + Int(length)
        guard data.count > jsonEnd else { throw ProjectFileError.invalidFormat }
        let root = try JSONDecoder().decode(RootDTO.self, from: data.subdata(in: 8..<jsonEnd))
        let pngData = data.subdata(in: jsonEnd..<data.count)
        guard
            let source = CGImageSourceCreateWithData(pngData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ProjectFileError.invalidFormat }

        return ProjectFilePayload(
            baseImage: image,
            annotations: root.annotations.compactMap { $0.annotation },
            background: root.background.style,
            counterNextNumber: root.counterNextNumber
        )
    }
}

// MARK: - DTOs

private struct RootDTO: Codable {
    let version: Int
    let background: BackgroundDTO
    let counterNextNumber: Int
    let annotations: [AnnotationDTO]
}

private struct ColorDTO: Codable {
    let r, g, b, a: CGFloat

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        r = srgb.redComponent; g = srgb.greenComponent
        b = srgb.blueComponent; a = srgb.alphaComponent
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

private struct StyleDTO: Codable {
    let color: ColorDTO
    let fillColor: ColorDTO
    let lineWidth: CGFloat
    let filled: Bool
    let fontSize: CGFloat
    let fontDesign: String

    init(_ style: AnnotationStyle) {
        color = ColorDTO(style.color)
        fillColor = ColorDTO(style.fillColor)
        lineWidth = style.lineWidth
        filled = style.filled
        fontSize = style.fontSize
        fontDesign = style.fontDesign.rawValue
    }

    var style: AnnotationStyle {
        AnnotationStyle(
            color: color.nsColor,
            fillColor: fillColor.nsColor,
            lineWidth: lineWidth,
            filled: filled,
            fontSize: fontSize,
            fontDesign: FontDesignChoice(rawValue: fontDesign) ?? .standard
        )
    }
}

private struct BackgroundDTO: Codable {
    let enabled: Bool
    let padding: CGFloat
    let cornerRadius: CGFloat
    let shadow: Bool
    let presetIndex: Int

    init(_ style: BackgroundStyle) {
        enabled = style.enabled
        padding = style.padding
        cornerRadius = style.cornerRadius
        shadow = style.shadow
        presetIndex = style.presetIndex
    }

    var style: BackgroundStyle {
        BackgroundStyle(
            enabled: enabled, padding: padding, cornerRadius: cornerRadius,
            shadow: shadow, presetIndex: presetIndex
        )
    }
}

private struct AnnotationDTO: Codable {
    let kind: String
    var points: [CGPoint]?
    var rect: [CGFloat]?
    var text: String?
    var number: Int?
    let style: StyleDTO

    init(_ annotation: Annotation) {
        style = StyleDTO(annotation.style)
        switch annotation.shape {
        case .arrow(let from, let to): kind = "arrow"; points = [from, to]
        case .line(let from, let to): kind = "line"; points = [from, to]
        case .rect(let r): kind = "rect"; rect = [r.minX, r.minY, r.width, r.height]
        case .ellipse(let r): kind = "ellipse"; rect = [r.minX, r.minY, r.width, r.height]
        case .blur(let r): kind = "blur"; rect = [r.minX, r.minY, r.width, r.height]
        case .pixelate(let r): kind = "pixelate"; rect = [r.minX, r.minY, r.width, r.height]
        case .pencil(let pts): kind = "pencil"; points = pts
        case .highlighter(let pts): kind = "highlighter"; points = pts
        case .text(let string, let origin): kind = "text"; text = string; points = [origin]
        case .counter(let n, let center): kind = "counter"; number = n; points = [center]
        }
    }

    var annotation: Annotation? {
        func cgRect() -> CGRect? {
            guard let rect, rect.count == 4 else { return nil }
            return CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
        }
        let shape: AnnotationShape?
        switch kind {
        case "arrow": shape = points.flatMap { $0.count == 2 ? .arrow(from: $0[0], to: $0[1]) : nil }
        case "line": shape = points.flatMap { $0.count == 2 ? .line(from: $0[0], to: $0[1]) : nil }
        case "rect": shape = cgRect().map { .rect($0) }
        case "ellipse": shape = cgRect().map { .ellipse($0) }
        case "blur": shape = cgRect().map { .blur($0) }
        case "pixelate": shape = cgRect().map { .pixelate($0) }
        case "pencil": shape = points.map { .pencil($0) }
        case "highlighter": shape = points.map { .highlighter($0) }
        case "text": shape = points?.first.map { .text(text ?? "", origin: $0) }
        case "counter": shape = points?.first.map { .counter(number ?? 1, center: $0) }
        default: shape = nil
        }
        guard let shape else { return nil }
        return Annotation(shape: shape, style: style.style)
    }
}
