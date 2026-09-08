import CoreGraphics

/// Overlay selection uses Cocoa coordinates: `minY` is the visual bottom.
public enum OverlaySelectionHandle: String, CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

public enum OverlayConfirmStyle: String, Sendable {
    case screenshot
    case start
}

public enum OverlayRegionAction: String, Sendable {
    case `default`
    case annotate
    case copy
    case save
    case pin
    case ocr
    case start
}

public enum SelectionHandleGeometry {
    public static let visualDiameter: CGFloat = 6
    public static let hitTargetSize: CGFloat = 20
    public static let minimumSize: CGFloat = 4
    public static let nudgeStep: CGFloat = 1
    public static let nudgeShiftStep: CGFloat = 10

    public static func points(in rect: CGRect) -> [(OverlaySelectionHandle, CGPoint)] {
        [
            (.topLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.top, CGPoint(x: rect.midX, y: rect.maxY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY))
        ]
    }

    public static func handle(
        at point: CGPoint,
        in rect: CGRect,
        hitSize: CGFloat = hitTargetSize
    ) -> OverlaySelectionHandle? {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return nil
        }
        let radius = max(hitSize, 1) / 2
        return points(in: rect).first { _, origin in
            hypot(point.x - origin.x, point.y - origin.y) <= radius
        }?.0
    }

    public static func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        rect.contains(point)
    }

    public static func nudge(
        _ rect: CGRect,
        delta: CGSize,
        inside bounds: CGRect
    ) -> CGRect {
        RectMath.clampedRect(rect.offsetBy(dx: delta.width, dy: delta.height), in: bounds)
    }

    public static func arrowDelta(keyCode: UInt16, shift: Bool) -> CGSize? {
        let step = shift ? nudgeShiftStep : nudgeStep
        switch keyCode {
        case 123: return CGSize(width: -step, height: 0)
        case 124: return CGSize(width: step, height: 0)
        case 125: return CGSize(width: 0, height: -step)
        case 126: return CGSize(width: 0, height: step)
        default: return nil
        }
    }

    public static func resize(
        _ original: CGRect,
        handle: OverlaySelectionHandle,
        to point: CGPoint,
        square: Bool,
        inside bounds: CGRect,
        minimumSize: CGFloat = minimumSize
    ) -> CGRect {
        let original = original.standardized
        guard original.width > 0, original.height > 0 else { return original }
        let point = CGPoint(
            x: RectMath.clamped(point.x, lower: bounds.minX, upper: bounds.maxX),
            y: RectMath.clamped(point.y, lower: bounds.minY, upper: bounds.maxY)
        )

        let movesLeft = handle == .topLeft || handle == .left || handle == .bottomLeft
        let movesRight = handle == .topRight || handle == .right || handle == .bottomRight
        let movesTop = handle == .topLeft || handle == .top || handle == .topRight
        let movesBottom = handle == .bottomLeft || handle == .bottom || handle == .bottomRight

        var minX = original.minX
        var maxX = original.maxX
        var minY = original.minY
        var maxY = original.maxY
        if movesLeft { minX = point.x }
        if movesRight { maxX = point.x }
        if movesBottom { minY = point.y }
        if movesTop { maxY = point.y }

        if square, (movesLeft || movesRight), (movesTop || movesBottom) {
            let size = max(abs(maxX - minX), abs(maxY - minY))
            if movesLeft { minX = maxX - size } else { maxX = minX + size }
            if movesBottom { minY = maxY - size } else { maxY = minY + size }
        }

        var rect = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
        if rect.width < minimumSize {
            if movesLeft {
                rect.origin.x = original.maxX - minimumSize
            }
            rect.size.width = minimumSize
        }
        if rect.height < minimumSize {
            if movesBottom {
                rect.origin.y = original.maxY - minimumSize
            }
            rect.size.height = minimumSize
        }
        return RectMath.clampedRect(rect, in: bounds)
    }
}
