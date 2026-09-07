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
        displaySize: CGSize,
        zoom: CGFloat = defaultZoom
    ) -> CGRect {
        guard imageBounds.width > 0,
              imageBounds.height > 0,
              displaySize.width > 0,
              displaySize.height > 0,
              zoom.isFinite,
              zoom > 0
        else { return .zero }

        let width = min(displaySize.width, imageBounds.width / zoom)
        let height = min(displaySize.height, imageBounds.height / zoom)
        let origin = CGPoint(
            x: cursor.x - width / 2,
            y: cursor.y - height / 2
        )
        return RectMath.clampedRect(
            CGRect(origin: origin, size: CGSize(width: width, height: height)),
            in: imageBounds
        )
    }
}
