import AppKit
import Vision
import VisionKit

/// On-device text recognition, two-tier:
/// 1. VisionKit ImageAnalyzer (the Live Text engine — what CleanShot X's quality
///    comes from; notably better with Vietnamese diacritics).
/// 2. Fallback: tuned VNRecognizeTextRequest (explicit vi/en, no auto-detect
///    override, diacritic-preferring candidate selection, row-based line assembly).
/// Small captures are upscaled 2× first — tiny UI text is the top accuracy killer.
enum OCRService {
    static func recognizeText(in image: CGImage) async throws -> String {
        let prepared = upscaledIfNeeded(image)

        if ImageAnalyzer.isSupported {
            let analyzer = ImageAnalyzer()
            var configuration = ImageAnalyzer.Configuration([.text])
            configuration.locales = ["vi-VN", "en-US"]
            if let analysis = try? await analyzer.analyze(
                prepared, orientation: .up, configuration: configuration
            ) {
                let transcript = analysis.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !transcript.isEmpty { return transcript }
            }
        }
        return try await visionFallback(prepared)
    }

    // MARK: - Preprocessing

    /// Upscales 2× (high-quality interpolation) when the capture is small.
    private static func upscaledIfNeeded(_ image: CGImage) -> CGImage {
        guard image.width < 1600, image.height < 1600 else { return image }
        let width = image.width * 2
        let height = image.height * 2
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    // MARK: - Vision fallback

    private static func visionFallback(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                continuation.resume(returning: assembleText(from: observations))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["vi-VN", "en-US"]
            // IMPORTANT: keep auto-detect OFF — it overrides recognitionLanguages
            // and cost us Vietnamese diacritics.
            request.automaticallyDetectsLanguage = false
            request.minimumTextHeight = 0.006

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Picks the candidate with the most diacritics among near-equal candidates
    /// (Vision often ranks the accent-stripped variant first for Vietnamese).
    private static func bestCandidate(for observation: VNRecognizedTextObservation) -> String? {
        let candidates = observation.topCandidates(3)
        guard let top = candidates.first else { return nil }
        let topFolded = folded(top.string)
        let best = candidates
            .filter { $0.confidence >= top.confidence - 0.25 && folded($0.string) == topFolded }
            .max { diacriticCount($0.string) < diacriticCount($1.string) }
        return (best ?? top).string
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { !$0.isWhitespace }
    }

    private static func diacriticCount(_ text: String) -> Int {
        text.decomposedStringWithCanonicalMapping.unicodeScalars
            .count { CharacterSet.nonBaseCharacters.contains($0) }
    }

    /// Groups observations into visual rows (y-overlap), sorts left-to-right within
    /// a row, rows top-to-bottom — instead of a naive vertical sort that breaks
    /// side-by-side text.
    private static func assembleText(from observations: [VNRecognizedTextObservation]) -> String {
        var rows: [(box: CGRect, items: [(x: CGFloat, text: String)])] = []

        for observation in observations.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            guard let text = bestCandidate(for: observation) else { continue }
            let box = observation.boundingBox
            if let index = rows.firstIndex(where: { row in
                let overlap = min(row.box.maxY, box.maxY) - max(row.box.minY, box.minY)
                return overlap > 0.5 * min(row.box.height, box.height)
            }) {
                rows[index].items.append((box.minX, text))
                rows[index].box = rows[index].box.union(box)
            } else {
                rows.append((box, [(box.minX, text)]))
            }
        }

        return rows
            .sorted { $0.box.midY > $1.box.midY }
            .map { row in
                row.items.sorted { $0.x < $1.x }.map(\.text).joined(separator: "  ")
            }
            .joined(separator: "\n")
    }
}
