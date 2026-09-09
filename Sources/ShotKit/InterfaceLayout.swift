import CoreGraphics

/// Shared sizing for transient chrome, using the source display's safe area.
public enum InterfaceLayout {
    public static func fittedSize(_ preferred: CGSize, in available: CGSize, inset: CGFloat = 0) -> CGSize {
        CGSize(width: min(max(1, preferred.width), max(1, available.width - inset * 2)),
               height: min(max(1, preferred.height), max(1, available.height - inset * 2)))
    }

    public static func bottomFrame(size: CGSize, in visibleFrame: CGRect, margin: CGFloat = 16,
                                   trailing: Bool = false) -> CGRect {
        let fitted = fittedSize(size, in: visibleFrame.size, inset: margin)
        let origin = CGPoint(x: trailing ? visibleFrame.maxX - margin - fitted.width : visibleFrame.midX - fitted.width / 2,
                             y: visibleFrame.minY + margin)
        return CGRect(origin: RectMath.clampedOrigin(origin, size: fitted, in: visibleFrame), size: fitted)
    }

    public static func toolbarWidth(preferred: CGFloat = 820, available: CGFloat) -> CGFloat {
        max(1, min(preferred, available))
    }
}
