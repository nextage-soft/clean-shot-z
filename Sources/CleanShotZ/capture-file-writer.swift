import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Output formats for saved captures.
enum CaptureImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    var displayName: String {
        switch self {
        case .png: "PNG (lossless)"
        case .jpeg: "JPEG"
        case .heic: "HEIC (smallest)"
        }
    }

    static func from(fileExtension: String) -> CaptureImageFormat {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "heic": .heic
        default: .png
        }
    }
}

/// Saves captures (format/quality/downscale per settings) and copies to clipboard.
enum CaptureFileWriter {

    /// Saves to the configured directory with a CleanShot-style timestamp name.
    /// `pointScale` is the source display's pixels-per-point — used for the
    /// optional Retina→1x downscale.
    static func save(_ image: CGImage, pointScale: CGFloat = 2) throws -> URL {
        let directory = SettingsStore.saveDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var output = image
        if SettingsStore.downscaleRetinaTo1x, pointScale > 1 {
            output = resized(image, factor: 1 / pointScale) ?? image
        }
        let format = SettingsStore.imageFormat
        guard let data = encode(output, format: format, quality: SettingsStore.imageQuality) else {
            throw ScreenCaptureError.cropFailed
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        var name = "\(SettingsStore.fileNamePrefix) \(formatter.string(from: Date())).\(format.fileExtension)"
        var url = directory.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            name = "\(SettingsStore.fileNamePrefix) \(formatter.string(from: Date())) (\(counter)).\(format.fileExtension)"
            url = directory.appendingPathComponent(name)
            counter += 1
        }
        try data.write(to: url)
        return url
    }

    /// Encodes with an explicit format (used by the editor's Save, which keeps
    /// the file's existing extension).
    static func encode(_ image: CGImage, format: CaptureImageFormat, quality: Double) -> Data? {
        switch format {
        case .png:
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        case .jpeg:
            return NSBitmapImageRep(cgImage: image).representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            )
        case .heic:
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data, UTType.heic.identifier as CFString, 1, nil
            ) else { return nil }
            CGImageDestinationAddImage(destination, image, [
                kCGImageDestinationLossyCompressionQuality: quality
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return data as Data
        }
    }

    static func copyToClipboard(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: .zero)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
    }

    private static func resized(_ image: CGImage, factor: CGFloat) -> CGImage? {
        let width = max(1, Int(CGFloat(image.width) * factor))
        let height = max(1, Int(CGFloat(image.height) * factor))
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
