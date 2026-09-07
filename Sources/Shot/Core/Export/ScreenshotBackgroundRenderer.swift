import AppKit
import ImageIO

enum ScreenshotBackgroundRenderer {
    static let defaultPadding: CGFloat = 48

    static func compose(
        screenshot: NSImage,
        background: NSImage,
        padding: CGFloat = defaultPadding
    ) -> NSImage? {
        guard let screenshotCGImage = cgImage(from: screenshot),
              let backgroundCGImage = cgImage(from: background) else {
            return nil
        }
        guard let output = composeCGImage(
            screenshot: screenshotCGImage,
            screenshotSize: screenshot.size,
            background: backgroundCGImage,
            backgroundSize: background.size,
            padding: padding
        ) else {
            return nil
        }
        let outputSize = CGSize(
            width: screenshot.size.width + padding * 2,
            height: screenshot.size.height + padding * 2
        )
        return NSImage(cgImage: output, size: outputSize)
    }

    static func composeCGImage(
        screenshot: CGImage,
        screenshotSize: CGSize,
        background: CGImage,
        backgroundSize: CGSize,
        padding: CGFloat = defaultPadding
    ) -> CGImage? {
        guard screenshotSize.width > 0,
              screenshotSize.height > 0,
              backgroundSize.width > 0,
              backgroundSize.height > 0,
              padding.isFinite,
              padding >= 0 else {
            return nil
        }

        let screenshotScaleX = CGFloat(screenshot.width) / screenshotSize.width
        let screenshotScaleY = CGFloat(screenshot.height) / screenshotSize.height
        let scaleX = max(screenshotScaleX.isFinite ? screenshotScaleX : 1, 1)
        let scaleY = max(screenshotScaleY.isFinite ? screenshotScaleY : 1, 1)
        let outputSize = CGSize(
            width: screenshotSize.width + padding * 2,
            height: screenshotSize.height + padding * 2
        )
        let pixelSize = CGSize(
            width: max(1, (outputSize.width * scaleX).rounded()),
            height: max(1, (outputSize.height * scaleY).rounded())
        )
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let canvas = CGRect(x: 0, y: 0, width: pixelSize.width, height: pixelSize.height)
        context.interpolationQuality = .high
        context.draw(
            background,
            in: aspectFillRect(imageSize: backgroundSize, in: canvas)
        )
        context.draw(
            screenshot,
            in: CGRect(
                x: padding * scaleX,
                y: padding * scaleY,
                width: screenshotSize.width * scaleX,
                height: screenshotSize.height * scaleY
            )
        )
        return context.makeImage()
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        guard image.size.width > 0,
              image.size.height > 0 else { return nil }
        var proposed = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    private static func aspectFillRect(imageSize: CGSize, in canvas: CGRect) -> CGRect {
        let scale = max(canvas.width / imageSize.width, canvas.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: canvas.midX - size.width / 2,
            y: canvas.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

struct ScreenshotBackgroundRenderSnapshot: @unchecked Sendable {
    let screenshot: CGImage
    let screenshotSize: CGSize
    let backgroundURL: URL

    init?(screenshot: NSImage, backgroundURL: URL) {
        let screenshotSize = screenshot.size
        var proposed = CGRect(origin: .zero, size: screenshotSize)
        guard let screenshot = screenshot.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }
        self.screenshot = screenshot
        self.screenshotSize = screenshotSize
        self.backgroundURL = backgroundURL
    }

    var renderedSize: CGSize {
        CGSize(
            width: screenshotSize.width + ScreenshotBackgroundRenderer.defaultPadding * 2,
            height: screenshotSize.height + ScreenshotBackgroundRenderer.defaultPadding * 2
        )
    }

    func renderedCGImage() -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(backgroundURL as CFURL, nil),
              let background = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let backgroundSize = CGSize(width: background.width, height: background.height)
        return ScreenshotBackgroundRenderer.composeCGImage(
            screenshot: screenshot,
            screenshotSize: screenshotSize,
            background: background,
            backgroundSize: backgroundSize
        )
    }
}
