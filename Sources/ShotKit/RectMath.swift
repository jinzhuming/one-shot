import CoreGraphics

public enum RectMath {
    public static func cocoaRect(fromCGWindowBounds bounds: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: bounds.origin.x,
            y: primaryHeight - bounds.origin.y - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    public static func localRect(_ global: CGRect, in displayFrame: CGRect) -> CGRect {
        CGRect(
            x: global.minX - displayFrame.minX,
            y: global.minY - displayFrame.minY,
            width: global.width,
            height: global.height
        )
    }

    /// Returns the first frame with the largest positive intersection area.
    /// Keeping this calculation independent from `NSScreen` makes window-to-
    /// display routing deterministic and testable for arbitrary arrangements.
    public static func largestIntersectionIndex(of rect: CGRect, in frames: [CGRect]) -> Int? {
        guard rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0 else { return nil }

        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, frame) in frames.enumerated() {
            let intersection = frame.intersection(rect)
            guard !intersection.isNull,
                  intersection.width.isFinite,
                  intersection.height.isFinite,
                  intersection.width > 0,
                  intersection.height > 0 else { continue }
            let area = intersection.width * intersection.height
            guard area.isFinite else { continue }
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Cocoa global selection → ScreenCaptureKit `sourceRect` for one display.
    /// Overlay selection uses `NSScreen.frame` (origin bottom-left); SCK wants
    /// points in that display's logical space with origin at the top-left.
    public static func displaySourceRect(cocoaGlobal: CGRect, screenFrame: CGRect) -> CGRect {
        let local = localRect(cocoaGlobal, in: screenFrame)
        return CGRect(
            x: local.origin.x,
            y: screenFrame.height - local.origin.y - local.height,
            width: local.width,
            height: local.height
        )
    }

    /// Converts a Cocoa global rectangle into an integer pixel crop rectangle
    /// in a full-display image whose origin is at the top-left.
    public static func pixelCropRect(
        cocoaGlobal: CGRect,
        screenFrame: CGRect,
        pixelSize: CGSize,
        scale: CGFloat
    ) -> CGRect? {
        guard scale.isFinite, scale > 0,
              pixelSize.width > 0, pixelSize.height > 0,
              cocoaGlobal.width > 0, cocoaGlobal.height > 0,
              screenFrame.contains(cocoaGlobal) else {
            return nil
        }

        let local = localRect(cocoaGlobal, in: screenFrame)
        let left = (local.minX * scale).rounded(.down)
        let top = ((screenFrame.height - local.maxY) * scale).rounded(.down)
        let right = (local.maxX * scale).rounded(.up)
        let bottom = ((screenFrame.height - local.minY) * scale).rounded(.up)
        let crop = CGRect(
            x: left,
            y: top,
            width: right - left,
            height: bottom - top
        )
        let imageBounds = CGRect(origin: .zero, size: pixelSize)
        guard crop.width > 0, crop.height > 0,
              imageBounds.contains(crop) else {
            return nil
        }
        return crop
    }

    public static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        if upper < lower { return lower }
        return min(max(lower, value), upper)
    }

    /// Leading origin that keeps `size` inside `bounds`, preferring `preferred` origin.
    public static func clampedOrigin(_ preferred: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: clamped(preferred.x, lower: bounds.minX, upper: bounds.maxX - size.width),
            y: clamped(preferred.y, lower: bounds.minY, upper: bounds.maxY - size.height)
        )
    }

    /// Keeps a rectangle inside `bounds`, preserving its size whenever the
    /// rectangle can fit. Oversized rectangles are reduced to the bounds size.
    public static func clampedRect(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let normalizedBounds = bounds.standardized
        guard !normalizedBounds.isEmpty else { return .zero }

        let normalizedRect = rect.standardized
        let size = CGSize(
            width: min(max(normalizedRect.width, 0), normalizedBounds.width),
            height: min(max(normalizedRect.height, 0), normalizedBounds.height)
        )
        let origin = clampedOrigin(normalizedRect.origin, size: size, in: normalizedBounds)
        return CGRect(origin: origin, size: size)
    }

    public static func leadingX(for width: CGFloat, centeringAt midX: CGFloat, in bounds: CGRect) -> CGFloat {
        clampedOrigin(
            CGPoint(x: midX - width / 2, y: bounds.minY),
            size: CGSize(width: width, height: 1),
            in: bounds
        ).x
    }
}
