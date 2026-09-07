import AppKit
import ScreenCaptureKit
import ShotKit

struct RegionSelection: Equatable {
    let rect: CGRect
    let displayID: CGDirectDisplayID
}

enum CoordinateSpace {
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    static func screen(for rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = RectMath.largestIntersectionIndex(
            of: rect,
            in: screens.map(\.frame)
        ) else { return nil }
        return screens[index]
    }

    static func display(matching screen: NSScreen, in displays: [SCDisplay]) -> SCDisplay? {
        let screenID = screen.displayID
        return displays.first(where: { $0.displayID == screenID })
    }

    static func cocoaRect(fromCGWindowBounds bounds: CGRect) -> CGRect {
        RectMath.cocoaRect(fromCGWindowBounds: bounds, primaryHeight: primaryDisplayHeight)
    }

    static func windowGeometry(
        fromCGWindowBounds bounds: CGRect
    ) -> (frame: CGRect, screen: NSScreen)? {
        let frame = cocoaRect(fromCGWindowBounds: bounds)
        guard let screen = screen(for: frame) else { return nil }
        return (frame, screen)
    }

    static var primaryDisplayHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? 0
    }

    static func localRect(_ global: CGRect, in displayFrame: CGRect) -> CGRect {
        RectMath.localRect(global, in: displayFrame)
    }

    static func displaySourceRect(_ cocoaGlobal: CGRect, on screen: NSScreen) -> CGRect {
        RectMath.displaySourceRect(cocoaGlobal: cocoaGlobal, screenFrame: screen.frame)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}
