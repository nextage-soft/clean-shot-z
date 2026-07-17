import SwiftUI

/// What the user chose from the post-selection tool menu (All-in-One mode).
enum AreaSelectionAction {
    case capture
    case scroll
    case ocr
}

/// Floating tool menu attached to a confirmed selection:
/// Capture · Scroll · OCR · Cancel (CleanShot All-in-One style).
struct SelectionActionBarView: View {
    let onAction: (AreaSelectionAction) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            barButton("camera.fill", "Capture (↩)", prominent: true) { onAction(.capture) }
            barButton("arrow.up.and.down.text.horizontal", "Scrolling capture") { onAction(.scroll) }
            barButton("text.viewfinder", "Copy text (OCR)") { onAction(.ocr) }
            Divider().frame(height: 16)
            barButton("xmark", "Cancel (Esc)") { onCancel() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .padding(8)
    }

    private func barButton(
        _ symbol: String,
        _ help: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(prominent ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(prominent ? .white : .primary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
