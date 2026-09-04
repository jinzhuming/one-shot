public enum WindowCaptureRoute: Equatable, Sendable {
    case displaySnapshot
    case singleWindow
}

public enum WindowCapturePolicy {
    /// Display snapshots are safe for no-shadow crops. A shadow extends beyond
    /// the window frame and must be rendered by ScreenCaptureKit's single-window
    /// capture path instead of being cropped from a display image.
    public static func route(includeShadow: Bool) -> WindowCaptureRoute {
        includeShadow ? .singleWindow : .displaySnapshot
    }
}
