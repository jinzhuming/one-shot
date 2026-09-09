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
        clamped(
            magnification,
            min: minimumMagnification,
            max: maximumMagnification
        )
    }

    public static func clamped(
        _ magnification: CGFloat,
        min minimum: CGFloat,
        max maximum: CGFloat
    ) -> CGFloat {
        guard magnification.isFinite else { return 1 }
        let lower = min(minimum, maximum)
        let upper = max(minimum, maximum)
        return min(max(magnification, lower), upper)
    }

    /// Scale that shows the whole image inside `viewportSize` without upscaling.
    ///
    /// `viewportSize` must be in view coordinates (the scroll view's bounds).
    /// `NSClipView.bounds` is document-space and grows as magnification shrinks,
    /// so using it as the viewport makes a later fit pass return 1x and clip.
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
        guard fit.isFinite, fit > 0 else { return 1 }
        return min(fit, maximumMagnification)
    }

    /// User zoom can go slightly below the usual minimum when the default fit
    /// already needs a smaller scale, so a tall scrolling capture still fits.
    public static func minimumMagnification(fitting magnification: CGFloat) -> CGFloat {
        min(minimumMagnification, max(magnification, 0.001))
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
