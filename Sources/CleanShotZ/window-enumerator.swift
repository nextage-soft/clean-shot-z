import AppKit
import CoreGraphics

/// Info about an on-screen window, used for hover-highlight + click-to-capture
/// in the selection overlay (CleanShot X behavior).
struct OnScreenWindowInfo {
    let windowID: CGWindowID
    /// Frame in AppKit global coordinates (bottom-left origin).
    let frameAppKit: NSRect
    let ownerName: String
}

enum WindowEnumerator {
    /// Returns normal-level, on-screen windows (front-to-back order), excluding
    /// this app's own windows and tiny system chrome.
    static func visibleWindows() -> [OnScreenWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [OnScreenWindowInfo] = []
        for entry in list {
            guard
                let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                let pid = entry[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                let windowID = entry[kCGWindowNumber as String] as? UInt32,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let cgFrame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            // Skip tiny windows (menu bar items, invisible helpers).
            guard cgFrame.width >= 60, cgFrame.height >= 40 else { continue }

            result.append(OnScreenWindowInfo(
                windowID: windowID,
                frameAppKit: CoordinateSpaceConverter.appKitRect(fromCGRect: cgFrame),
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? ""
            ))
        }
        return result
    }

    /// Topmost window under the given AppKit-global point.
    static func window(at point: NSPoint, in windows: [OnScreenWindowInfo]) -> OnScreenWindowInfo? {
        windows.first { $0.frameAppKit.contains(point) }
    }
}
