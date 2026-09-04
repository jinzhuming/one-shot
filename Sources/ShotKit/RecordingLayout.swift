import CoreGraphics

public enum RecordingLayout {
    public static func evenPixelSize(points: CGFloat, scale: CGFloat) -> Int {
        guard points.isFinite, scale.isFinite, points > 0, scale > 0 else { return 2 }
        let rounded = max(2, Int((points * scale).rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }

    /// Returns frames in newest-first order, starting at the lower-left corner.
    public static func previewFrames(
        count: Int,
        windowSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat = 16,
        gap: CGFloat = 12
    ) -> [CGRect] {
        guard count > 0, !visibleFrame.isEmpty else { return [] }

        let width = min(max(windowSize.width, 1), max(1, visibleFrame.width - margin * 2))
        let height = min(max(windowSize.height, 1), max(1, visibleFrame.height - margin * 2))
        let rows = max(1, Int(floor((visibleFrame.height - margin * 2 + gap) / (height + gap))))

        return (0..<count).map { index in
            let column = index / rows
            let row = index % rows
            let origin = CGPoint(
                x: visibleFrame.minX + margin + CGFloat(column) * (width + gap),
                y: visibleFrame.minY + margin + CGFloat(row) * (height + gap)
            )
            return CGRect(origin: origin, size: CGSize(width: width, height: height))
        }
    }
}
