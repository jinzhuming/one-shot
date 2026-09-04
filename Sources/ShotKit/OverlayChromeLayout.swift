import CoreGraphics

public enum OverlayChromeLayout {
    /// Places a size HUD around `target` inside `bounds` (same coordinate space).
    /// Prefers below; flips above when the bottom edge has no room; sits inside
    /// the target when both sides are blocked.
    public static func hudFrame(
        size: CGSize,
        around target: CGRect,
        in bounds: CGRect,
        gap: CGFloat = 8,
        margin: CGFloat = 8
    ) -> CGRect {
        let safe = bounds.insetBy(dx: margin, dy: margin)
        guard safe.width > 0, safe.height > 0 else {
            return CGRect(origin: bounds.origin, size: size)
        }

        let x = RectMath.leadingX(for: size.width, centeringAt: target.midX, in: safe)
        let belowY = target.minY - gap - size.height
        let aboveY = target.maxY + gap

        let y: CGFloat
        if belowY >= safe.minY {
            y = belowY
        } else if aboveY + size.height <= safe.maxY {
            y = aboveY
        } else {
            let insideBottom = target.minY + gap
            let insideTop = target.maxY - gap - size.height
            if insideBottom + size.height <= target.maxY - gap {
                y = RectMath.clamped(insideBottom, lower: safe.minY, upper: safe.maxY - size.height)
            } else if insideTop >= target.minY + gap {
                y = RectMath.clamped(insideTop, lower: safe.minY, upper: safe.maxY - size.height)
            } else {
                y = RectMath.clamped(
                    target.midY - size.height / 2,
                    lower: safe.minY,
                    upper: safe.maxY - size.height
                )
            }
        }

        return CGRect(
            origin: RectMath.clampedOrigin(CGPoint(x: x, y: y), size: size, in: safe),
            size: size
        )
    }
}
