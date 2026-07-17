import SwiftUI

/// One-click preset color palette (CleanShot-style) with a small custom picker at the end.
/// Avoids the heavyweight system color panel for the common case.
struct ColorSwatchRow: View {
    static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .systemPink, .black, .white,
    ]

    let selection: NSColor
    /// Alpha applied when a preset is picked (fill colors want semi-transparency).
    var presetAlpha: CGFloat = 1
    let onPick: (NSColor) -> Void

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(Self.palette.enumerated()), id: \.offset) { _, color in
                let candidate = presetAlpha < 1 ? color.withAlphaComponent(presetAlpha) : color
                let isSelected = selection.isClose(to: candidate)
                Button {
                    onPick(candidate)
                } label: {
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .padding(3)
                        .overlay(
                            Circle().strokeBorder(
                                Color.accentColor,
                                lineWidth: isSelected ? 1.5 : 0
                            )
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }
            Divider().frame(height: 14)
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(nsColor: selection) },
                    set: { onPick(NSColor($0)) }
                ),
                supportsOpacity: presetAlpha < 1
            )
            .labelsHidden()
            .frame(width: 30)
            .help("Custom color")
        }
    }
}

extension NSColor {
    /// Approximate equality in sRGB space (survives round-trips through SwiftUI Color).
    func isClose(to other: NSColor) -> Bool {
        guard
            let a = usingColorSpace(.sRGB),
            let b = other.usingColorSpace(.sRGB)
        else { return self == other }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
            && abs(a.alphaComponent - b.alphaComponent) < 0.05
    }
}
