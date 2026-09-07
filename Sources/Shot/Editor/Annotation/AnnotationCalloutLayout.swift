import AppKit
import ShotKit

/// The single source of truth for callout text measurement and bubble geometry.
/// Keeping the editor, selection bounds, and export renderer on the same layout
/// prevents text from being clipped or rendered outside its selection frame.
struct AnnotationCalloutLayout {
    let body: CGRect
    let textRect: CGRect
    let tailCenterX: CGFloat
    let tailWidth: CGFloat
    let tailHeight: CGFloat

    var bounds: CGRect {
        body.union(CGRect(
            x: tailCenterX - tailWidth / 2,
            y: body.maxY,
            width: tailWidth,
            height: tailHeight
        )).insetBy(dx: 0, dy: 0)
    }

    static func layout(
        text: String,
        in rect: CGRect,
        style: AnnotationStyle,
        wrapsText: Bool = true
    ) -> AnnotationCalloutLayout {
        let font = font(for: style)
        let horizontalPadding = max(20, style.lineWidth * 5)
        let verticalPadding = max(16, style.lineWidth * 4)
        let minimumWidth = max(96, font.pointSize * 3 + horizontalPadding)
        let lineHeight = font.ascender - font.descender + font.leading
        let minimumHeight = max(44, lineHeight + verticalPadding)
        let requested = rect.standardized
        let baseWidth = max(minimumWidth, requested.width)
        let baseHeight = max(minimumHeight, requested.height)
        let attributes = textAttributes(font: font, color: style.color, wrapsText: wrapsText)

        let bodyWidth: CGFloat
        let measured: CGSize
        if wrapsText {
            bodyWidth = baseWidth
            let contentWidth = max(1, bodyWidth - horizontalPadding)
            measured = measure(
                text,
                constrainedTo: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                attributes: attributes
            )
        } else {
            measured = measure(
                text,
                constrainedTo: CGSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                ),
                attributes: attributes
            )
            bodyWidth = max(baseWidth, ceil(measured.width) + horizontalPadding)
        }

        let bodyHeight = max(baseHeight, ceil(measured.height) + verticalPadding)
        let body = CGRect(
            x: requested.minX,
            y: requested.minY,
            width: bodyWidth,
            height: bodyHeight
        )
        let tailWidth = max(14, min(24, body.width * 0.18))
        let tailOffset = min(28, max(12, body.width * 0.24))
        let tailCenterX = min(
            max(body.minX + tailOffset, body.minX + tailWidth / 2 + 6),
            body.maxX - tailWidth / 2 - 6
        )
        let tailHeight = max(10, style.lineWidth * 2.5)
        let textWidth = max(1, body.width - horizontalPadding)
        let finalTextSize = measure(
            text,
            constrainedTo: CGSize(
                width: textWidth,
                height: max(1, body.height - verticalPadding)
            ),
            attributes: attributes
        )
        let textRect = CGRect(
            x: body.minX + horizontalPadding / 2,
            y: body.midY - finalTextSize.height / 2,
            width: textWidth,
            height: max(1, finalTextSize.height)
        )
        return AnnotationCalloutLayout(
            body: body,
            textRect: textRect,
            tailCenterX: tailCenterX,
            tailWidth: tailWidth,
            tailHeight: tailHeight
        )
    }

    static func font(for style: AnnotationStyle) -> NSFont {
        let scale = min(
            max(style.textScale, AnnotationStyle.minimumAnnotationScale),
            AnnotationStyle.maximumAnnotationScale
        )
        return NSFont.systemFont(
            ofSize: AnnotationMath.fontSize(lineWidth: style.lineWidth) * scale,
            weight: .medium
        )
    }

    static func textAttributes(
        font: NSFont,
        color: NSColor,
        wrapsText: Bool
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = wrapsText ? .byWordWrapping : .byClipping
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    /// Builds one continuous outline. The tail replaces a section of the
    /// body's bottom edge, so it cannot double-draw the bubble border.
    static func path(for layout: AnnotationCalloutLayout, lineWidth: CGFloat) -> NSBezierPath {
        let body = layout.body
        let radius = min(16, max(6, body.height * 0.22))
        let kappa: CGFloat = 0.5522848
        let tailLeft = layout.tailCenterX - layout.tailWidth / 2
        let tailRight = layout.tailCenterX + layout.tailWidth / 2
        let path = NSBezierPath()

        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.line(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.curve(
            to: CGPoint(x: body.maxX, y: body.minY + radius),
            controlPoint1: CGPoint(x: body.maxX - radius + radius * kappa, y: body.minY),
            controlPoint2: CGPoint(x: body.maxX, y: body.minY + radius - radius * kappa)
        )
        path.line(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.curve(
            to: CGPoint(x: body.maxX - radius, y: body.maxY),
            controlPoint1: CGPoint(x: body.maxX, y: body.maxY - radius + radius * kappa),
            controlPoint2: CGPoint(x: body.maxX - radius + radius * kappa, y: body.maxY)
        )
        path.line(to: CGPoint(x: tailRight, y: body.maxY))
        path.line(to: CGPoint(x: layout.tailCenterX, y: body.maxY + layout.tailHeight))
        path.line(to: CGPoint(x: tailLeft, y: body.maxY))
        path.line(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.curve(
            to: CGPoint(x: body.minX, y: body.maxY - radius),
            controlPoint1: CGPoint(x: body.minX + radius - radius * kappa, y: body.maxY),
            controlPoint2: CGPoint(x: body.minX, y: body.maxY - radius + radius * kappa)
        )
        path.line(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.curve(
            to: CGPoint(x: body.minX + radius, y: body.minY),
            controlPoint1: CGPoint(x: body.minX, y: body.minY + radius - radius * kappa),
            controlPoint2: CGPoint(x: body.minX + radius - radius * kappa, y: body.minY)
        )
        path.close()
        path.lineWidth = max(1, lineWidth)
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        return path
    }

    private static func measure(
        _ text: String,
        constrainedTo size: CGSize,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGSize {
        let measured = (text as NSString).boundingRect(
            with: size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).integral
        return CGSize(width: max(1, measured.width), height: max(1, measured.height))
    }
}
