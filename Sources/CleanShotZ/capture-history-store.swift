import AppKit

/// Capture history: every capture is mirrored into Application Support/CleanShotZ/History,
/// kept for 30 days (like CleanShot's one-month history). No index file — the
/// directory itself is the source of truth, sorted by modification date.
enum CaptureHistoryStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CleanShotZ/History", isDirectory: true)
    }

    /// Mirrors a saved capture into history (called after each capture).
    static func record(fileURL: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(fileURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.copyItem(at: fileURL, to: target)
            }
        } catch {
            NSLog("CaptureHistoryStore: failed to record \(fileURL.lastPathComponent): \(error)")
        }
    }

    /// Newest-first list of history files.
    static func entries() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        let extensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
        return files
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { modificationDate($0) > modificationDate($1) }
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes entries older than 30 days (run at launch).
    static func purgeOldEntries() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        for url in entries() where modificationDate(url) < cutoff {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
