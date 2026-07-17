import AppKit
import SwiftUI

/// The capture history browser window (grid of recent captures).
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Capture History"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: HistoryGridView())
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

/// Thumbnail grid; click opens the editor, hover reveals quick actions.
private struct HistoryGridView: View {
    @State private var entries: [URL] = CaptureHistoryStore.entries()

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 14)]

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No captures yet",
                    systemImage: "camera.viewfinder",
                    description: Text("Screenshots you take appear here for 30 days.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(entries, id: \.self) { url in
                            HistoryThumbnailCell(url: url) {
                                CaptureHistoryStore.delete(url)
                                entries = CaptureHistoryStore.entries()
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 380)
        .onAppear { entries = CaptureHistoryStore.entries() }
    }
}

private struct HistoryThumbnailCell: View {
    let url: URL
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncThumbnail(url: url)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                    .onTapGesture { openInEditor() }
                    .onDrag { NSItemProvider(object: url as NSURL) }

                if hovering {
                    HStack(spacing: 4) {
                        cellButton("doc.on.doc") {
                            if let image = NSImage(contentsOf: url),
                               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                                CaptureFileWriter.copyToClipboard(cg)
                                ToastHUDController.shared.show("Copied")
                            }
                        }
                        cellButton("magnifyingglass") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        cellButton("trash", role: .destructive) { onDelete() }
                    }
                    .padding(5)
                }
            }
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .onHover { hovering = $0 }
    }

    private func openInEditor() {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        EditorWindowController.shared.open(image: cg, fileURL: url)
    }

    private func cellButton(_ symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(5)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Loads thumbnails off the main thread so big grids stay responsive.
private struct AsyncThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.primary.opacity(0.06))
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: url) {
            let loaded = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceThumbnailMaxPixelSize: 400,
                      ] as CFDictionary) else { return nil }
                return NSImage(cgImage: thumb, size: .zero)
            }.value
            image = loaded
        }
    }
}
