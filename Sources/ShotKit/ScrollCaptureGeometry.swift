import CoreGraphics

public enum ScrollDirection: String, Equatable, Sendable {
    case up
    case down
}

/// Geometry shared by the image stitcher and its tests. The image matching
/// implementation lives in the app target, while these rules stay platform
/// independent and deterministic.
public enum ScrollCaptureGeometry {
    public static func advance(viewportHeight: Int, overlap: Int) -> Int? {
        guard viewportHeight > 0,
              overlap > 0,
              overlap < viewportHeight else { return nil }
        return viewportHeight - overlap
    }

    public static func shiftedTop(
        direction: ScrollDirection,
        existingTop: Int,
        newStripHeight: Int
    ) -> Int {
        switch direction {
        case .down:
            return existingTop
        case .up:
            return existingTop + newStripHeight
        }
    }

    public static func newStripRect(
        direction: ScrollDirection,
        viewportSize: CGSize,
        overlap: CGFloat
    ) -> CGRect? {
        guard viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > 0,
              viewportSize.height > 0,
              overlap > 0,
              overlap < viewportSize.height else { return nil }

        let height = viewportSize.height - overlap
        switch direction {
        case .down:
            return CGRect(x: 0, y: overlap, width: viewportSize.width, height: height)
        case .up:
            return CGRect(x: 0, y: 0, width: viewportSize.width, height: height)
        }
    }
}
