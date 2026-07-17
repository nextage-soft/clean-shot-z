import AppKit

/// AppKit (NSScreen/NSEvent) uses a global coordinate space with origin at the
/// bottom-left of the primary display, Y going up. CoreGraphics / ScreenCaptureKit /
/// CGWindowList use origin at the top-left of the primary display, Y going down.
/// All conversions between the two live here.
enum CoordinateSpaceConverter {
    /// Height of the primary display in points (the flip axis).
    private static var primaryScreenHeight: CGFloat {
        // NSScreen.screens.first is always the primary display (origin 0,0 in AppKit space).
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// AppKit global rect -> CoreGraphics global rect (top-left origin).
    static func cgRect(fromAppKitRect rect: NSRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// CoreGraphics global rect -> AppKit global rect (bottom-left origin).
    static func appKitRect(fromCGRect rect: CGRect) -> NSRect {
        NSRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Converts an AppKit global rect into a pixel rect local to the given screen,
    /// with top-left origin — ready for CGImage cropping.
    static func pixelRect(fromAppKitRect rect: NSRect, on screen: NSScreen) -> CGRect {
        let scale = screen.backingScaleFactor
        let localX = rect.minX - screen.frame.minX
        let localYTopLeft = screen.frame.maxY - rect.maxY
        return CGRect(
            x: localX * scale,
            y: localYTopLeft * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// CGDirectDisplayID of an NSScreen.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
