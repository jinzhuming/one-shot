import AppKit
import CoreGraphics

enum CaptureWindowLevels {
    /// High enough to cover the desktop and most app windows, below the screen-recording privacy indicator.
    static var overlay: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 8)
    }

    static var modeBar: NSWindow.Level {
        NSWindow.Level(rawValue: overlay.rawValue + 1)
    }

    static var editor: NSWindow.Level {
        NSWindow.Level(rawValue: overlay.rawValue + 2)
    }
}
