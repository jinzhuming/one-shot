public enum WindowCaptureRoute: Equatable, Sendable {
    case displaySnapshot
    case singleWindow
}

public enum WindowCapturePolicy {
    /// Interactive window captures use ScreenCaptureKit's single-window route
    /// for both shadow preferences. This isolates the target from overlapping
    /// windows and keeps the capture bounds consistent.
    public static func route(includeShadow _: Bool) -> WindowCaptureRoute {
        .singleWindow
    }

    /// Maps the user-facing shadow preference to ScreenCaptureKit's single-
    /// window configuration. Shadow bounds are owned entirely by
    /// `ignoreShadowsSingleWindow`; callers must not add padding.
    public static func ignoresShadowsSingleWindow(includeShadow: Bool) -> Bool {
        switch route(includeShadow: includeShadow) {
        case .singleWindow:
            return !includeShadow
        case .displaySnapshot:
            return false
        }
    }
}
