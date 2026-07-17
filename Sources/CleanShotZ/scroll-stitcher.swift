import CoreGraphics
import Foundation

/// Stitches a sequence of same-width frames captured while the user scrolls.
/// For each new frame it finds the vertical scroll offset against the previous
/// frame (grayscale row matching) and appends only the newly revealed rows.
actor ScrollStitcher {
    /// First entry is the full first frame; the rest are new-content strips.
    private var strips: [CGImage] = []
    private var lastGray: GrayImage?
    private(set) var totalHeight = 0
    private var frameWidth = 0
    private var frameHeight = 0

    /// Grayscale copy, full height but width/4 — exact vertical matching, 4× less work.
    private struct GrayImage {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    private static let minOverlapRows = 60
    private static let maxScrollPerFrame = 1400
    private static let maxTotalHeight = 40000
    private static let acceptableMeanDiff: Double = 14

    /// Adds a frame; returns the number of new pixel rows appended (0 = duplicate/unmatched).
    func add(_ frame: CGImage) -> Int {
        guard totalHeight < Self.maxTotalHeight else { return 0 }
        guard let gray = Self.grayscale(frame) else { return 0 }

        guard let last = lastGray else {
            strips = [frame]
            lastGray = gray
            frameWidth = frame.width
            frameHeight = frame.height
            totalHeight = frame.height
            return frame.height
        }
        guard frame.width == frameWidth, frame.height == frameHeight else { return 0 }

        guard let dy = Self.findScrollOffset(previous: last, current: gray) else {
            // Content changed without a clean vertical match (jump/animation) — hold position.
            lastGray = gray
            return 0
        }
        lastGray = gray
        guard dy > 0 else { return 0 }

        let stripRect = CGRect(x: 0, y: frameHeight - dy, width: frameWidth, height: dy)
        // CGImage.cropping shares (and pins) the whole parent frame's backing store —
        // materialize the strip into its own bitmap so each captured frame can free.
        guard let cropped = frame.cropping(to: stripRect),
              let ctx = CGContext(
                  data: nil, width: frameWidth, height: dy,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return 0 }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: frameWidth, height: dy))
        guard let strip = ctx.makeImage() else { return 0 }
        strips.append(strip)
        totalHeight += dy
        return dy
    }

    /// Draws all strips top-to-bottom into the final tall image.
    func finalImage() -> CGImage? {
        guard !strips.isEmpty else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: frameWidth,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        var yFromTop = 0
        for strip in strips {
            let rect = CGRect(
                x: 0,
                y: totalHeight - yFromTop - strip.height, // CG bottom-left origin
                width: strip.width,
                height: strip.height
            )
            ctx.draw(strip, in: rect)
            yFromTop += strip.height
        }
        return ctx.makeImage()
    }

    // MARK: - Matching

    /// Finds dy such that previous[dy + i] ≈ current[i] (user scrolled DOWN by dy rows).
    /// Returns nil when nothing matches well; 0 when the best match is "no movement".
    private static func findScrollOffset(previous: GrayImage, current: GrayImage) -> Int? {
        let height = previous.height
        let width = previous.width
        let maxDy = min(maxScrollPerFrame, height - minOverlapRows)
        guard maxDy > 0 else { return nil }

        var bestDy = 0
        var bestDiff = Double.greatestFiniteMagnitude

        for dy in 0...maxDy {
            let overlap = height - dy
            var sum = 0
            var count = 0
            // Sample every 8th row of the overlap; all columns (width is already /4).
            var row = 0
            while row < overlap {
                let prevBase = (dy + row) * width
                let curBase = row * width
                for x in stride(from: 0, to: width, by: 2) {
                    sum += abs(Int(previous.pixels[prevBase + x]) - Int(current.pixels[curBase + x]))
                    count += 1
                }
                row += 8
            }
            guard count > 0 else { continue }
            let mean = Double(sum) / Double(count)
            if mean < bestDiff {
                bestDiff = mean
                bestDy = dy
            }
            if mean < 1.0 && dy == 0 { return 0 } // perfectly still — bail out early
        }
        return bestDiff <= acceptableMeanDiff ? bestDy : nil
    }

    private static func grayscale(_ image: CGImage) -> GrayImage? {
        let width = max(1, image.width / 4)
        let height = image.height
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        let pixels = [UInt8](UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: width * height
        ))
        return GrayImage(width: width, height: height, pixels: pixels)
    }
}
