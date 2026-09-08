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
        // In-place annotation has to stay above our dimming overlay, but it
        // must not sit near the screen-saver range. Keeping the level just
        // above our own capture chrome limits the blast radius if a teardown
        // path fails and still leaves system UI and privacy indicators alone.
        NSWindow.Level(rawValue: modeBar.rawValue + 1)
    }

    static var pin: NSWindow.Level {
        // A pinned image is persistent user content, so it must remain above
        // normal and application floating windows after Shot deactivates.
        // Keep it below the screen-saver range and the system privacy UI.
        NSWindow.Level(rawValue: editor.rawValue + 1)
    }
}
