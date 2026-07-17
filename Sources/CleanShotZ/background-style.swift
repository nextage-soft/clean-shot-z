import AppKit

/// Gradient backdrop wrapped around a capture (CleanShot's Background tool):
/// padding + rounded corners + drop shadow over a preset gradient.
struct BackgroundStyle: Equatable {
    var enabled = false
    /// Padding around the content, in base-image pixels.
    var padding: CGFloat = 80
    var cornerRadius: CGFloat = 18
    var shadow = true
    var presetIndex = 0

    var preset: BackgroundGradientPreset {
        BackgroundGradientPreset.presets[min(presetIndex, BackgroundGradientPreset.presets.count - 1)]
    }
}

struct BackgroundGradientPreset: Equatable {
    let start: NSColor
    let end: NSColor

    static let presets: [BackgroundGradientPreset] = [
        .init(start: NSColor(red: 0.26, green: 0.51, blue: 0.99, alpha: 1),
              end: NSColor(red: 0.51, green: 0.27, blue: 0.95, alpha: 1)),   // blue → purple
        .init(start: NSColor(red: 0.99, green: 0.47, blue: 0.31, alpha: 1),
              end: NSColor(red: 0.95, green: 0.26, blue: 0.58, alpha: 1)),   // orange → pink
        .init(start: NSColor(red: 0.14, green: 0.76, blue: 0.61, alpha: 1),
              end: NSColor(red: 0.10, green: 0.47, blue: 0.86, alpha: 1)),   // teal → blue
        .init(start: NSColor(red: 0.99, green: 0.78, blue: 0.22, alpha: 1),
              end: NSColor(red: 0.97, green: 0.44, blue: 0.22, alpha: 1)),   // yellow → orange
        .init(start: NSColor(white: 0.22, alpha: 1),
              end: NSColor(white: 0.08, alpha: 1)),                          // graphite
        .init(start: NSColor(white: 0.96, alpha: 1),
              end: NSColor(white: 0.82, alpha: 1)),                          // silver
    ]
}
