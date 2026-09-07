import AppKit
import ShotKit

enum AnnotationRenderer {
    static func draw(_ elements: [AnnotationObject], baseImage: NSImage, in bounds: CGRect) {
        for object in elements {
            draw(object.element, baseImage: baseImage, bounds: bounds)
        }
    }

    private static func draw(_ element: AnnotationElement, baseImage: NSImage, bounds: CGRect) {
        switch element {
        case .arrow(let start, let end, let style):
            strokeLine(from: start, to: end, style: style, arrow: true)
        case .rect(let rect, let style):
            stroke(NSBezierPath(rect: rect), style: style)
        case .ellipse(let rect, let style):
            stroke(NSBezierPath(ovalIn: rect), style: style)
        case .line(let start, let end, let style):
            strokeLine(from: start, to: end, style: style, arrow: false)
        case .pen(let points, let style):
            strokePolyline(points, style: style, alpha: 1, widthMultiplier: 1)
        case .highlighter(let points, let style):
            strokePolyline(points, style: style, alpha: style.highlighterOpacity, widthMultiplier: 3)
        case .text(let string, let origin, let style):
            drawText(string, at: origin, style: style)
        case .counter(let value, let center, let style):
            drawCounter(value, at: center, style: style)
        case .mosaic(let rect, let blockSize):
            drawMosaic(rect, blockSize: blockSize, from: baseImage)
        case .spotlight(let rect, let opacity):
            drawSpotlight(rect, opacity: opacity, bounds: bounds)
        }
    }

    private static func stroke(_ path: NSBezierPath, style: AnnotationStyle) {
        style.color.setStroke()
        path.lineWidth = style.lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    private static func strokeLine(from start: CGPoint, to end: CGPoint, style: AnnotationStyle, arrow: Bool) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        stroke(path, style: style)
        guard arrow else { return }
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(10, style.lineWidth * 4)
        let spread = CGFloat.pi / 7
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread)))
        head.line(to: CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread)))
        head.close()
        style.color.setFill()
        head.fill()
    }

    private static func strokePolyline(_ points: [CGPoint], style: AnnotationStyle, alpha: CGFloat, widthMultiplier: CGFloat) {
        guard points.count >= 2 else { return }
        let points = AnnotationGeometry.smoothedPath(points)
        let path = NSBezierPath()
        path.move(to: points[0])
        if points.count == 2 {
            path.line(to: points[1])
        } else {
            for index in 1..<(points.count - 1) {
                let current = points[index]
                let next = points[index + 1]
                let midpoint = CGPoint(
                    x: (current.x + next.x) / 2,
                    y: (current.y + next.y) / 2
                )
                path.curve(
                    to: midpoint,
                    controlPoint1: current,
                    controlPoint2: current
                )
            }
            let last = points[points.count - 1]
            let previous = points[points.count - 2]
            path.curve(to: last, controlPoint1: previous, controlPoint2: last)
        }
        style.color.withAlphaComponent(alpha).setStroke()
        path.lineWidth = max(1, style.lineWidth * widthMultiplier)
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    private static func drawText(_ string: String, at origin: CGPoint, style: AnnotationStyle) {
        let scale = min(max(style.textScale, AnnotationStyle.minimumAnnotationScale), AnnotationStyle.maximumAnnotationScale)
        let font = NSFont.systemFont(
            ofSize: AnnotationMath.fontSize(lineWidth: style.lineWidth) * scale,
            weight: .medium
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.color
        ]
        (string as NSString).draw(at: origin, withAttributes: attributes)
    }

    private static func drawCounter(_ value: Int, at center: CGPoint, style: AnnotationStyle) {
        let scale = min(max(style.counterScale, AnnotationStyle.minimumAnnotationScale), AnnotationStyle.maximumAnnotationScale)
        let radius = max(10, style.lineWidth * 5 * scale)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let circle = NSBezierPath(ovalIn: rect)
        style.color.setFill()
        circle.fill()
        let text = "\(value)" as NSString
        let font = NSFont.systemFont(ofSize: radius, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        text.draw(at: origin, withAttributes: attributes)
    }

    private static func drawMosaic(_ rect: CGRect, blockSize: CGFloat, from baseImage: NSImage) {
        guard rect.width > 1, rect.height > 1,
              blockSize.isFinite, blockSize > 1 else { return }
        let block = blockSize
        let cols = max(1, Int((rect.width / block).rounded(.down)))
        let rows = max(1, Int((rect.height / block).rounded(.down)))
        var proposed = CGRect(origin: .zero, size: baseImage.size)
        guard let baseCG = baseImage.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        let imageSize = baseImage.size
        // `rect` is top-left annotation space; `CGImage.cropping` is also top-left.
        let crop = CGRect(
            x: rect.minX / max(imageSize.width, 1) * CGFloat(baseCG.width),
            y: rect.minY / max(imageSize.height, 1) * CGFloat(baseCG.height),
            width: rect.width / max(imageSize.width, 1) * CGFloat(baseCG.width),
            height: rect.height / max(imageSize.height, 1) * CGFloat(baseCG.height)
        ).integral
        guard crop.width > 1, crop.height > 1, let cropped = baseCG.cropping(to: crop) else { return }
        guard let tiny = CGContext(
            data: nil,
            width: cols,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: baseCG.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        tiny.interpolationQuality = .none
        tiny.draw(cropped, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        guard let pixelated = tiny.makeImage() else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.interpolationQuality = .none
        ctx.draw(pixelated, in: rect)
        ctx.restoreGState()
    }

    private static func drawSpotlight(_ hole: CGRect, opacity: CGFloat, bounds: CGRect) {
        let overlay = NSBezierPath(rect: bounds)
        overlay.append(NSBezierPath(ovalIn: hole))
        overlay.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(opacity).setFill()
        overlay.fill()
    }
}
