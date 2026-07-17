import SwiftUI

/// Popover controls for the Background tool: enable, gradient preset,
/// padding, corner radius, shadow.
struct BackgroundOptionsView: View {
    @ObservedObject var document: AnnotationDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Background", isOn: $document.background.enabled)
                .font(.system(size: 13, weight: .semibold))

            if document.background.enabled {
                HStack(spacing: 8) {
                    ForEach(Array(BackgroundGradientPreset.presets.enumerated()), id: \.offset) { index, preset in
                        Button {
                            document.background.presetIndex = index
                        } label: {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(nsColor: preset.start), Color(nsColor: preset.end)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle().strokeBorder(
                                        Color.accentColor,
                                        lineWidth: document.background.presetIndex == index ? 2 : 0
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("Padding").frame(width: 60, alignment: .leading)
                    Slider(value: $document.background.padding, in: 20...200)
                    Text("\(Int(document.background.padding))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 30, alignment: .trailing)
                }
                HStack {
                    Text("Corners").frame(width: 60, alignment: .leading)
                    Slider(value: $document.background.cornerRadius, in: 0...60)
                    Text("\(Int(document.background.cornerRadius))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 30, alignment: .trailing)
                }
                Toggle("Drop shadow", isOn: $document.background.shadow)
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 300)
    }
}
