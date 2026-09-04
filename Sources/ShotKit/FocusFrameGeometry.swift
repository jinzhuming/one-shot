import CoreGraphics

public struct FocusFrameSegment: Equatable, Sendable {
    public let start: CGPoint
    public let end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

public enum FocusFrameGeometry {
    public static let defaultArmLength: CGFloat = 20

    /// Returns the eight line segments that make up a four-corner focus frame.
    ///
    /// Segments are ordered clockwise, starting at the top-left corner. The
    /// arm length is capped at half of the rectangle's shortest side so that
    /// small selections never produce crossing corner marks.
    public static func cornerSegments(
        in rect: CGRect,
        armLength: CGFloat = defaultArmLength
    ) -> [FocusFrameSegment] {
        guard rect.width > 0, rect.height > 0,
              rect.minX.isFinite, rect.minY.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite,
              armLength > 0, armLength.isFinite
        else {
            return []
        }

        let length = min(armLength, min(rect.width, rect.height) / 2)
        guard length > 0, length.isFinite else { return [] }

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        return [
            // Top-left
            FocusFrameSegment(
                start: CGPoint(x: minX, y: maxY - length),
                end: CGPoint(x: minX, y: maxY)
            ),
            FocusFrameSegment(
                start: CGPoint(x: minX, y: maxY),
                end: CGPoint(x: minX + length, y: maxY)
            ),
            // Top-right
            FocusFrameSegment(
                start: CGPoint(x: maxX - length, y: maxY),
                end: CGPoint(x: maxX, y: maxY)
            ),
            FocusFrameSegment(
                start: CGPoint(x: maxX, y: maxY),
                end: CGPoint(x: maxX, y: maxY - length)
            ),
            // Bottom-right
            FocusFrameSegment(
                start: CGPoint(x: maxX, y: minY + length),
                end: CGPoint(x: maxX, y: minY)
            ),
            FocusFrameSegment(
                start: CGPoint(x: maxX, y: minY),
                end: CGPoint(x: maxX - length, y: minY)
            ),
            // Bottom-left
            FocusFrameSegment(
                start: CGPoint(x: minX + length, y: minY),
                end: CGPoint(x: minX, y: minY)
            ),
            FocusFrameSegment(
                start: CGPoint(x: minX, y: minY),
                end: CGPoint(x: minX, y: minY + length)
            )
        ]
    }
}
