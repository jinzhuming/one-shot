import CoreGraphics

/// Maps a flipped annotation view (origin top-left, y down) onto image point space
/// with the same origin. `NSView.convert(_:from: nil)` already yields that view space.
public enum CanvasMapping {
    public static func imagePoint(viewPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        return CGPoint(
            x: viewPoint.x / viewSize.width * imageSize.width,
            y: viewPoint.y / viewSize.height * imageSize.height
        )
    }

    public static func viewPoint(imagePoint: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        return CGPoint(
            x: imagePoint.x / imageSize.width * viewSize.width,
            y: imagePoint.y / imageSize.height * viewSize.height
        )
    }
}
