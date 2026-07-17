import AppKit

// Menu bar app (LSUIElement) — bootstrap NSApplication manually since this is an SPM executable.
@main
@MainActor
enum CleanShotZApp {
    static func main() {
        // Headless round-trip check of the .cleanshotz codec (CI/dev only).
        if CommandLine.arguments.contains("--selftest-project") {
            runProjectSelfTest()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static func runProjectSelfTest() {
        let ctx = CGContext(
            data: nil, width: 120, height: 90, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(NSColor.systemTeal.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
        let base = ctx.makeImage()!

        var background = BackgroundStyle()
        background.enabled = true
        background.padding = 42
        let payload = ProjectFilePayload(
            baseImage: base,
            annotations: [
                Annotation(shape: .arrow(from: .init(x: 5, y: 6), to: .init(x: 90, y: 40)), style: .init()),
                Annotation(shape: .text("Xin chào có dấu", origin: .init(x: 10, y: 20)), style: .init()),
                Annotation(shape: .counter(7, center: .init(x: 30, y: 30)), style: .init()),
                Annotation(shape: .blur(.init(x: 1, y: 2, width: 30, height: 20)), style: .init()),
            ],
            background: background,
            counterNextNumber: 8
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest.cleanshotz")
        do {
            try ProjectFileCodec.write(payload, to: url)
            let restored = try ProjectFileCodec.read(from: url)
            var failures: [String] = []
            if restored.annotations.count != 4 { failures.append("annotation count") }
            if restored.counterNextNumber != 8 { failures.append("counterNextNumber") }
            if restored.background.padding != 42 || !restored.background.enabled { failures.append("background") }
            if case .text(let string, _) = restored.annotations[1].shape, string == "Xin chào có dấu" {} else {
                failures.append("text content")
            }
            if restored.baseImage.width != 120 || restored.baseImage.height != 90 { failures.append("base image") }
            print(failures.isEmpty ? "PROJECT SELFTEST OK" : "PROJECT SELFTEST FAILED: \(failures)")
        } catch {
            print("PROJECT SELFTEST FAILED: \(error)")
        }
    }
}
