import CoreGraphics

public enum OverlayChromeLayout {
    /// Places a size HUD around `target` inside `bounds` (same coordinate space).
    /// Prefers below; flips above when the bottom edge has no room; sits inside
    /// the target when both sides are blocked.
    public static func hudFrame(
        size: CGSize,
        around target: CGRect,
        in bounds: CGRect,
        avoiding: CGRect? = nil,
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

        var frame = CGRect(
            origin: RectMath.clampedOrigin(CGPoint(x: x, y: y), size: size, in: safe),
            size: size
        )
        if let avoiding, frame.intersects(avoiding) {
            let flippedY = y == belowY ? aboveY : belowY
            let flipped = CGRect(
                origin: RectMath.clampedOrigin(CGPoint(x: x, y: flippedY), size: size, in: safe),
                size: size
            )
            if safe.contains(flipped), !flipped.intersects(avoiding) {
                frame = flipped
            }
        }
        return frame
    }

    /// Places an action bar beside `target`, preferring the opposite side from
    /// `avoiding` when that frame sits on the preferred below-target slot.
    public static func actionBarFrame(
        size: CGSize,
        around target: CGRect,
        avoiding: CGRect? = nil,
        in bounds: CGRect,
        gap: CGFloat = 10,
        margin: CGFloat = 8
    ) -> CGRect {
        let safe = bounds.insetBy(dx: margin, dy: margin)
        guard safe.width > 0, safe.height > 0 else {
            return CGRect(origin: bounds.origin, size: size)
        }

        let x = RectMath.leadingX(for: size.width, centeringAt: target.midX, in: safe)
        let below = CGRect(
            x: x,
            y: target.minY - gap - size.height,
            width: size.width,
            height: size.height
        )
        let above = CGRect(
            x: x,
            y: target.maxY + gap,
            width: size.width,
            height: size.height
        )
        let preferAbove = avoiding.map { $0.maxY <= target.minY + 1 } ?? false
        let ordered = preferAbove ? [above, below] : [below, above]
        if let chosen = ordered.first(where: {
            safe.contains($0) && (avoiding == nil || !$0.intersects(avoiding!))
        }) {
            return chosen
        }
        if let chosen = ordered.first(where: { safe.contains($0) }) {
            return chosen
        }
        return hudFrame(size: size, around: target, in: bounds, gap: gap, margin: margin)
    }
}
