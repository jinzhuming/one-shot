import CoreGraphics

public enum RecordingIndicatorLayout {
    public static let defaultMaskOpacity: CGFloat = 0.12
    public static let reducedTransparencyMaskOpacity: CGFloat = 0.20

    /// Places the recording status HUD near the target while keeping it inside
    /// the display's visible frame and away from the interactive control bar.
    /// The target itself is allowed as a final fallback for small or edge-
    /// aligned selections, because the HUD is excluded from the recording.
    public static func badgeFrame(
        size: CGSize,
        targetRect: CGRect?,
        visibleFrame: CGRect,
        reservedFrame: CGRect? = nil,
        gap: CGFloat = 8,
        margin: CGFloat = 8
    ) -> CGRect {
        let safe = visibleFrame.standardized.insetBy(dx: margin, dy: margin)
        guard !safe.isEmpty else {
            return CGRect(origin: visibleFrame.origin, size: size)
        }

        let fittedSize = CGSize(
            width: min(max(size.width, 1), safe.width),
            height: min(max(size.height, 1), safe.height)
        )

        func isUsable(_ frame: CGRect, allowingTargetOverlap: Bool = false) -> Bool {
            guard safe.contains(frame) else { return false }
            if let reservedFrame, frame.intersects(reservedFrame) {
                return false
            }
            if !allowingTargetOverlap, let targetRect, frame.intersects(targetRect) {
                return false
            }
            return true
        }

        func clamped(_ frame: CGRect) -> CGRect {
            CGRect(
                origin: RectMath.clampedOrigin(frame.origin, size: fittedSize, in: safe),
                size: fittedSize
            )
        }

        if let targetRect {
            let target = targetRect.standardized
            let outsideCandidates = [
                // Prefer the space above the target, then below it.
                CGRect(
                    x: target.midX - fittedSize.width / 2,
                    y: target.maxY + gap,
                    width: fittedSize.width,
                    height: fittedSize.height
                ),
                CGRect(
                    x: target.midX - fittedSize.width / 2,
                    y: target.minY - gap - fittedSize.height,
                    width: fittedSize.width,
                    height: fittedSize.height
                )
            ]
            for candidate in outsideCandidates where isUsable(candidate) {
                return candidate
            }

            let insideCandidates = [
                CGRect(
                    x: target.minX + gap,
                    y: target.maxY - gap - fittedSize.height,
                    width: fittedSize.width,
                    height: fittedSize.height
                ),
                CGRect(
                    x: target.minX + gap,
                    y: target.minY + gap,
                    width: fittedSize.width,
                    height: fittedSize.height
                )
            ]
            for candidate in insideCandidates where isUsable(candidate, allowingTargetOverlap: true) {
                return candidate
            }
        }

        let displayCandidates = [
            CGRect(
                x: safe.maxX - fittedSize.width,
                y: safe.maxY - fittedSize.height,
                width: fittedSize.width,
                height: fittedSize.height
            ),
            CGRect(
                x: safe.minX,
                y: safe.maxY - fittedSize.height,
                width: fittedSize.width,
                height: fittedSize.height
            ),
            CGRect(
                x: safe.maxX - fittedSize.width,
                y: safe.minY,
                width: fittedSize.width,
                height: fittedSize.height
            ),
            CGRect(
                x: safe.minX,
                y: safe.minY,
                width: fittedSize.width,
                height: fittedSize.height
            )
        ]
        for candidate in displayCandidates where isUsable(candidate, allowingTargetOverlap: true) {
            return candidate
        }

        return clamped(
            CGRect(
                x: targetRect.map { $0.midX - fittedSize.width / 2 }
                    ?? visibleFrame.midX - fittedSize.width / 2,
                y: targetRect.map { $0.midY - fittedSize.height / 2 } ?? visibleFrame.midY - fittedSize.height / 2,
                width: fittedSize.width,
                height: fittedSize.height
            )
        )
    }
}
