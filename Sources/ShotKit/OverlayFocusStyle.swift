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
    /// Window focus uses a restrained tint so the captured content stays
    /// legible beneath the semantic accent-color ring.
    public static let windowHighlightOpacity: CGFloat = 0.08
    public static let reducedTransparencyWindowHighlightOpacity: CGFloat = 0.14

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
