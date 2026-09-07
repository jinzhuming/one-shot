import CoreGraphics

public enum MagnifierLayout {
    public static let defaultSize = CGSize(width: 124, height: 124)
    public static let defaultGap: CGFloat = 18
    public static let defaultZoom: CGFloat = 8

    public static func frame(
        cursor: CGPoint,
        size: CGSize = defaultSize,
        visibleFrame: CGRect,
        gap: CGFloat = defaultGap,
        margin: CGFloat = 8
    ) -> CGRect {
        guard size.width > 0, size.height > 0, visibleFrame.width > 0, visibleFrame.height > 0 else {
            return .zero
        }

        let safe = visibleFrame.insetBy(dx: margin, dy: margin)
        var x = cursor.x - size.width / 2
        x = min(max(x, safe.minX), max(safe.minX, safe.maxX - size.width))

        let above = CGRect(
            x: x,
            y: cursor.y + gap,
            width: size.width,
            height: size.height
        )
        if safe.contains(above) {
            return above
        }

        let below = CGRect(
            x: x,
            y: cursor.y - gap - size.height,
            width: size.width,
            height: size.height
        )
        return RectMath.clampedRect(below, in: safe)
    }

    public static func sourceRect(
        cursor: CGPoint,
        imageBounds: CGRect,
        destinationSize: CGSize,
        zoom: CGFloat = defaultZoom
    ) -> CGRect {
        guard cursor.x.isFinite,
              cursor.y.isFinite,
              imageBounds.width > 0,
              imageBounds.height > 0,
              destinationSize.width > 0,
              destinationSize.height > 0,
              imageBounds.width.isFinite,
              imageBounds.height.isFinite,
              destinationSize.width.isFinite,
              destinationSize.height.isFinite,
              zoom.isFinite,
              zoom > 0
        else { return .zero }

        // The source must have the same aspect ratio as the lens. Otherwise
        // NSImage.draw(in:from:) stretches the captured content to fill the
        // lens, which is especially visible on 16:9 and 16:10 displays.
        // `zoom` is the number of lens points represented by one source point.
        let desiredSize = CGSize(
            width: destinationSize.width / zoom,
            height: destinationSize.height / zoom
        )
        guard desiredSize.width.isFinite, desiredSize.height.isFinite else { return .zero }
        let fitScale = min(
            1,
            imageBounds.width / desiredSize.width,
            imageBounds.height / desiredSize.height
        )
        let sourceSize = CGSize(
            width: desiredSize.width * fitScale,
            height: desiredSize.height * fitScale
        )
        let origin = CGPoint(
            x: cursor.x - sourceSize.width / 2,
            y: cursor.y - sourceSize.height / 2
        )
        return RectMath.clampedRect(
            CGRect(origin: origin, size: sourceSize),
            in: imageBounds
        )
    }

    /// Maps the cursor from the source image into the displayed lens. When a
    /// cursor is close to an image edge, the source rect is clamped and the
    /// cursor is no longer at the lens center.
    public static func cursorPosition(
        cursor: CGPoint,
        sourceRect: CGRect,
        destinationFrame: CGRect
    ) -> CGPoint {
        guard sourceRect.width > 0,
              sourceRect.height > 0,
              destinationFrame.width > 0,
              destinationFrame.height > 0,
              cursor.x.isFinite,
              cursor.y.isFinite else {
            return CGPoint(x: destinationFrame.midX, y: destinationFrame.midY)
        }

        let normalizedX = RectMath.clamped(
            (cursor.x - sourceRect.minX) / sourceRect.width,
            lower: 0,
            upper: 1
        )
        let normalizedY = RectMath.clamped(
            (cursor.y - sourceRect.minY) / sourceRect.height,
            lower: 0,
            upper: 1
        )
        return CGPoint(
            x: destinationFrame.minX + normalizedX * destinationFrame.width,
            y: destinationFrame.minY + normalizedY * destinationFrame.height
        )
    }
}
