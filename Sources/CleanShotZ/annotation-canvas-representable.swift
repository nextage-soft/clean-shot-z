import SwiftUI

/// Bridges the AppKit canvas into the SwiftUI editor layout and redraws it
/// whenever the document changes.
struct AnnotationCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var document: AnnotationDocument
    let displayScale: CGFloat

    func makeNSView(context: Context) -> AnnotationCanvasView {
        AnnotationCanvasView(document: document, displayScale: displayScale)
    }

    func updateNSView(_ view: AnnotationCanvasView, context: Context) {
        view.documentDidChange()
    }
}
