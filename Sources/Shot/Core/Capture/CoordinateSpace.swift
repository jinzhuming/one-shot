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
        NSScreen.screens
            .map { screen in
                (screen: screen, area: screen.frame.intersection(rect).area)
            }
            .max { lhs, rhs in lhs.area < rhs.area }
            .flatMap { $0.area > 0 ? $0.screen : nil }
    }

    static func display(matching screen: NSScreen, in displays: [SCDisplay]) -> SCDisplay? {
        let screenID = screen.displayID
        return displays.first(where: { $0.displayID == screenID })
    }

    static func cocoaRect(fromCGWindowBounds bounds: CGRect) -> CGRect {
        RectMath.cocoaRect(fromCGWindowBounds: bounds, primaryHeight: primaryDisplayHeight)
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

private extension CGRect {
    var area: CGFloat { width * height }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}
