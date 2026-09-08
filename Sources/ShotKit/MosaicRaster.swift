import CoreGraphics
import CoreImage

public enum MosaicRasterEffect: String, Equatable, Sendable {
    case pixelate
    case blur
}

public enum MosaicRaster {
    public static func pixelBlock(
        blockSizePoints: CGFloat,
        imagePointSize: CGSize,
        pixelWidth: Int
    ) -> Int {
        guard blockSizePoints.isFinite, blockSizePoints > 0,
              imagePointSize.width > 0, pixelWidth > 0 else {
            return 1
        }
        let scale = CGFloat(pixelWidth) / imagePointSize.width
        return max(1, Int((blockSizePoints * scale).rounded()))
    }

    public static func blurRadius(
        blockSizePoints: CGFloat,
        imagePointSize: CGSize,
        pixelWidth: Int
    ) -> CGFloat {
        CGFloat(pixelBlock(
            blockSizePoints: blockSizePoints,
            imagePointSize: imagePointSize,
            pixelWidth: pixelWidth
        ))
    }

    public static func pixelated(_ image: CGImage, pixelBlock: Int) -> CGImage? {
        let block = max(1, pixelBlock)
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let cols = max(1, Int(ceil(CGFloat(width) / CGFloat(block))))
        let rows = max(1, Int(ceil(CGFloat(height) / CGFloat(block))))
        let fullWidth = cols * block
        let fullHeight = rows * block
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let source = edgeExtended(image, width: fullWidth, height: fullHeight) else {
            return nil
        }
        guard let tiny = CGContext(
            data: nil,
            width: cols,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        tiny.interpolationQuality = .medium
        tiny.draw(source, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        guard let small = tiny.makeImage() else { return nil }

        guard let full = CGContext(
            data: nil,
            width: fullWidth,
            height: fullHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        full.interpolationQuality = .none
        full.draw(small, in: CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight))
        guard let enlarged = full.makeImage() else { return nil }
        if fullWidth == width, fullHeight == height {
            return enlarged
        }
        // Tiny content sits on the bottom-left of the unflipped bitmap, so the
        // extra grid padding is at the top of the CGImage (y = 0).
        return enlarged.cropping(
            to: CGRect(
                x: 0,
                y: fullHeight - height,
                width: width,
                height: height
            )
        )
    }

    public static func blurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let sigma = max(0.5, radius)
        let input = CIImage(cgImage: image)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        return ciContext.createCGImage(blurred, from: input.extent)
    }

    private static func edgeExtended(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        if width == image.width, height == image.height {
            return image
        }
        guard width >= image.width, height >= image.height else { return image }
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if width > image.width,
           let column = image.cropping(to: CGRect(x: image.width - 1, y: 0, width: 1, height: image.height)) {
            context.draw(
                column,
                in: CGRect(x: image.width, y: 0, width: width - image.width, height: image.height)
            )
        }
        if height > image.height,
           let row = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: 1)) {
            context.draw(
                row,
                in: CGRect(x: 0, y: image.height, width: image.width, height: height - image.height)
            )
        }
        if width > image.width,
           height > image.height,
           let corner = image.cropping(to: CGRect(x: image.width - 1, y: 0, width: 1, height: 1)) {
            context.draw(
                corner,
                in: CGRect(
                    x: image.width,
                    y: image.height,
                    width: width - image.width,
                    height: height - image.height
                )
            )
        }
        return context.makeImage()
    }

    public static func render(
        _ image: CGImage,
        effect: MosaicRasterEffect,
        blockSizePoints: CGFloat,
        imagePointSize: CGSize
    ) -> CGImage? {
        let block = pixelBlock(
            blockSizePoints: blockSizePoints,
            imagePointSize: imagePointSize,
            pixelWidth: image.width
        )
        switch effect {
        case .pixelate:
            return pixelated(image, pixelBlock: block)
        case .blur:
            return blurred(image, radius: CGFloat(block))
        }
    }

    private static let ciContext = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false
    ])
}

public final class MosaicRasterCache: @unchecked Sendable {
    public static let shared = MosaicRasterCache()

    private struct Key: Hashable {
        let imageID: ObjectIdentifier
        let effect: MosaicRasterEffect
        let parameter: Int
    }

    private let lock = NSLock()
    private var items: [Key: CGImage] = [:]
    private let limit = 6

    public init() {}

    public func image(
        for base: CGImage,
        effect: MosaicRasterEffect,
        blockSizePoints: CGFloat,
        imagePointSize: CGSize
    ) -> CGImage? {
        let parameter = MosaicRaster.pixelBlock(
            blockSizePoints: blockSizePoints,
            imagePointSize: imagePointSize,
            pixelWidth: base.width
        )
        let key = Key(imageID: ObjectIdentifier(base), effect: effect, parameter: parameter)
        lock.lock()
        if let cached = items[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let rendered = MosaicRaster.render(
            base,
            effect: effect,
            blockSizePoints: blockSizePoints,
            imagePointSize: imagePointSize
        ) else {
            return nil
        }

        lock.lock()
        if items.count >= limit, items[key] == nil, let evict = items.keys.first {
            items.removeValue(forKey: evict)
        }
        items[key] = rendered
        lock.unlock()
        return rendered
    }
}
