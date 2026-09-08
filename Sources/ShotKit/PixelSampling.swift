import CoreGraphics

public enum PixelSampling {
    public static func hex(red: UInt8, green: UInt8, blue: UInt8) -> String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// Samples `image` at a point in the same coordinate space as `imageBounds`.
    /// `imageBounds` uses a bottom-left origin to match an unflipped overlay view.
    public static func sample(
        image: CGImage,
        at point: CGPoint,
        imageBounds: CGRect
    ) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard imageBounds.width > 0, imageBounds.height > 0,
              point.x.isFinite, point.y.isFinite,
              image.width > 0, image.height > 0 else {
            return nil
        }
        let normalizedX = (point.x - imageBounds.minX) / imageBounds.width
        let normalizedY = (point.y - imageBounds.minY) / imageBounds.height
        guard normalizedX >= 0, normalizedX <= 1, normalizedY >= 0, normalizedY <= 1 else {
            return nil
        }
        let pixelX = min(image.width - 1, max(0, Int((normalizedX * CGFloat(image.width)).rounded(.down))))
        let pixelY = min(
            image.height - 1,
            max(0, Int(((1 - normalizedY) * CGFloat(image.height)).rounded(.down)))
        )
        return samplePixel(image, x: pixelX, y: pixelY)
    }

    public static func displayPoint(global: CGPoint, screenFrame: CGRect) -> CGPoint {
        CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
    }

    public static func samplePixel(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (pixel[0], pixel[1], pixel[2])
    }
}
