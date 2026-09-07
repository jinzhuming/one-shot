import CoreGraphics

public enum CanvasScrollAction: Equatable, Sendable {
    case zoom
    case pan
}

/// Pure rules shared by the annotation canvas and its tests.
public enum CanvasZoom {
    public static let minimumMagnification: CGFloat = 0.1
    public static let maximumMagnification: CGFloat = 4

    public static func clamped(_ magnification: CGFloat) -> CGFloat {
        guard magnification.isFinite else { return 1 }
        return min(
            max(magnification, minimumMagnification),
            maximumMagnification
        )
    }

    public static func fittedMagnification(
        imageSize: CGSize,
        viewportSize: CGSize
    ) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return 1
        }
        let fit = min(
            1,
            viewportSize.width / imageSize.width,
            viewportSize.height / imageSize.height
        )
        return clamped(fit)
    }

    /// Precise scrolling is produced by a trackpad and should pan the canvas.
    /// A non-precise event is normally produced by a mouse wheel and zooms.
    /// Command-scrolling is an optional additional zoom gesture.
    public static func scrollAction(
        hasPreciseScrollingDeltas: Bool,
        commandPressed: Bool,
        commandScrollEnabled: Bool
    ) -> CanvasScrollAction {
        if (commandPressed && commandScrollEnabled) || !hasPreciseScrollingDeltas {
            return .zoom
        }
        return .pan
    }
}
