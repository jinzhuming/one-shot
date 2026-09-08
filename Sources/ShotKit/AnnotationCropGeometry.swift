import CoreGraphics

public enum AnnotationCropGeometry {
    public static func translated(_ point: CGPoint, subtracting origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    public static func translated(_ rect: CGRect, subtracting origin: CGPoint) -> CGRect {
        CGRect(
            x: rect.minX - origin.x,
            y: rect.minY - origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    public static func translated(_ points: [CGPoint], subtracting origin: CGPoint) -> [CGPoint] {
        points.map { translated($0, subtracting: origin) }
    }

    public static func shouldKeep(bounds: CGRect, in crop: CGRect) -> Bool {
        guard crop.width > 0, crop.height > 0, bounds.width.isFinite, bounds.height.isFinite else {
            return false
        }
        return bounds.intersects(crop)
    }

    public static func pixelCropRect(
        imageRect: CGRect,
        imageSize: CGSize,
        pixelSize: CGSize
    ) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0,
              pixelSize.width > 0, pixelSize.height > 0,
              imageRect.width > 0, imageRect.height > 0 else {
            return nil
        }
        let scaleX = pixelSize.width / imageSize.width
        let scaleY = pixelSize.height / imageSize.height
        let crop = CGRect(
            x: (imageRect.minX * scaleX).rounded(.down),
            y: (imageRect.minY * scaleY).rounded(.down),
            width: (imageRect.maxX * scaleX).rounded(.up) - (imageRect.minX * scaleX).rounded(.down),
            height: (imageRect.maxY * scaleY).rounded(.up) - (imageRect.minY * scaleY).rounded(.down)
        )
        let bounds = CGRect(origin: .zero, size: pixelSize)
        guard crop.width > 0, crop.height > 0, bounds.contains(crop) else { return nil }
        return crop
    }
}
