import AppKit
import ScreenCaptureKit

enum ScreenCaptureError: Error {
    case displayNotFound
    case windowNotFound
    case cropFailed
}

/// Thin wrapper over ScreenCaptureKit's SCScreenshotManager (macOS 14+).
final class ScreenCaptureService {
    /// SCShareableContent enumeration can intermittently take seconds (it walks
    /// every window in the session). Displays/applications barely change, so
    /// cache the content briefly — this is what made captures feel randomly
    /// slow, and scrolling capture was paying it 3×/second.
    private var cachedContent: SCShareableContent?
    private var cachedContentAt = Date.distantPast

    private func shareableContent() async throws -> SCShareableContent {
        if let cachedContent, Date().timeIntervalSince(cachedContentAt) < 15 {
            return cachedContent
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = content
        cachedContentAt = Date()
        return content
    }

    /// Full image of the display backing the given NSScreen (native pixel resolution).
    /// `excludingOwnWindows` hides this app's panels/overlays from the capture
    /// (used by scrolling capture, whose control panel floats on screen).
    func captureDisplayImage(of screen: NSScreen, excludingOwnWindows: Bool = false) async throws -> CGImage {
        let content = try await shareableContent()
        guard let displayID = CoordinateSpaceConverter.displayID(of: screen),
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayNotFound
        }
        let filter: SCContentFilter
        if excludingOwnWindows {
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownApps = content.applications.filter { $0.processID == ownPID }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Captures an area given in AppKit global coordinates, constrained to one screen.
    /// Strategy: capture the whole display, then crop — avoids sourceRect coordinate pitfalls.
    func captureArea(
        _ rectAppKit: NSRect,
        on screen: NSScreen,
        excludingOwnWindows: Bool = false
    ) async throws -> CGImage {
        let fullImage = try await captureDisplayImage(of: screen, excludingOwnWindows: excludingOwnWindows)
        var pixelRect = CoordinateSpaceConverter.pixelRect(fromAppKitRect: rectAppKit, on: screen)
        // Clamp to image bounds to survive off-by-one at screen edges.
        let imageBounds = CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height)
        pixelRect = pixelRect.intersection(imageBounds).integral
        guard !pixelRect.isEmpty, let cropped = fullImage.cropping(to: pixelRect) else {
            throw ScreenCaptureError.cropFailed
        }
        return cropped
    }

    /// Captures a single window (without background) by CGWindowID.
    /// Also returns the pixels-per-point scale of the window's display,
    /// so downstream UI (pin, sizing) can convert pixels back to points.
    /// NOTE: window capture needs FRESH content (the target's frame moves) —
    /// no cache here, only display lookups are cached.
    func captureWindow(windowID: CGWindowID) async throws -> (image: CGImage, pointScale: CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Use the scale of the display the window actually lives on (mixed-DPI setups).
        let frameAppKit = CoordinateSpaceConverter.appKitRect(fromCGRect: window.frame)
        let scale = (NSScreen.screens.first { $0.frame.intersects(frameAppKit) } ?? NSScreen.main)?
            .backingScaleFactor ?? 2
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, scale)
    }

}
