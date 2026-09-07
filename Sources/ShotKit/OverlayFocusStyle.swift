import CoreGraphics

/// Opacity policy for the screenshot selection overlay.
///
/// Keeping this policy in ShotKit makes the visual hierarchy deterministic and
/// testable without constructing AppKit views.
public enum OverlayFocusStyle {
    public static let idleMaskOpacity: CGFloat = 0.34
    public static let focusedMaskOpacity: CGFloat = 0.42
    public static let dimOnlyMaskOpacity: CGFloat = 0.45
    public static let reducedTransparencyMaskOpacity: CGFloat = 0.52

    /// Keep accent color as a precise focus cue instead of using it as a
    /// saturated full-frame border over arbitrary desktop content.
    public static let selectionBorderOpacity: CGFloat = 0.76
    public static let selectionContrastOpacity: CGFloat = 0.48
    public static let selectionContrastLineWidth: CGFloat = 2
    public static let selectionBorderLineWidth: CGFloat = 1
    public static let selectionDashLength: CGFloat = 4
    public static let selectionDashGap: CGFloat = 3
    public static let selectionHandleDiameter: CGFloat = 6
    public static let selectionHandleMinimumDimension: CGFloat = 18

    /// Window focus uses a restrained tint so the captured content stays
    /// legible beneath a neutral semantic keyline.
    public static let windowHighlightOpacity: CGFloat = 0.08
    public static let reducedTransparencyWindowHighlightOpacity: CGFloat = 0.14
    public static let windowContrastOpacity: CGFloat = 0.48
    public static let windowBorderOpacity: CGFloat = 0.86
    public static let windowContrastLineWidth: CGFloat = 2
    public static let windowBorderLineWidth: CGFloat = 1

    /// The lens is a floating theme-adaptive inspection surface. Keep the
    /// chrome separate from the captured pixels so the content edge remains
    /// geometrically honest.
    public static let magnifierBezelInset: CGFloat = 6
    public static let magnifierBezelOpacity: CGFloat = 0.86
    public static let magnifierShadowOpacity: CGFloat = 0.34
    public static let magnifierOuterBorderOpacity: CGFloat = 0.30
    public static let magnifierInnerBorderOpacity: CGFloat = 0.82
    public static let magnifierBorderLineWidth: CGFloat = 1
    public static let magnifierContrastLineWidth: CGFloat = 2

    public static func maskOpacity(
        dimOnly: Bool,
        hasFocus: Bool,
        reduceTransparency: Bool
    ) -> CGFloat {
        if reduceTransparency {
            return reducedTransparencyMaskOpacity
        }
        if dimOnly {
            return dimOnlyMaskOpacity
        }
        return hasFocus ? focusedMaskOpacity : idleMaskOpacity
    }

    public static func windowHighlightOpacity(reduceTransparency: Bool) -> CGFloat {
        reduceTransparency
            ? reducedTransparencyWindowHighlightOpacity
            : windowHighlightOpacity
    }
}
