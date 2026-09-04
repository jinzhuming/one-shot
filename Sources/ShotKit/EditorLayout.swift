import CoreGraphics

public enum ToolbarAnchor: Equatable, Sendable {
    case below
    case above
}

public struct EditorArrangement: Equatable, Sendable {
    public var windowFrame: CGRect
    public var canvasFrame: CGRect
    public var toolbarFrame: CGRect
    public var imageSize: CGSize
    public var toolbarAnchor: ToolbarAnchor
    public var keepsCaptureAligned: Bool

    public init(
        windowFrame: CGRect,
        canvasFrame: CGRect,
        toolbarFrame: CGRect,
        imageSize: CGSize,
        toolbarAnchor: ToolbarAnchor,
        keepsCaptureAligned: Bool
    ) {
        self.windowFrame = windowFrame
        self.canvasFrame = canvasFrame
        self.toolbarFrame = toolbarFrame
        self.imageSize = imageSize
        self.toolbarAnchor = toolbarAnchor
        self.keepsCaptureAligned = keepsCaptureAligned
    }
}

public enum EditorLayout {
    /// The toolbar shadow is rendered outside the toolbar view's bounds.
    /// Keep these values in sync with AnnotationToolbar so the shadow remains
    /// inside the transparent editor window instead of being clipped by it.
    public static let toolbarShadowRadius: CGFloat = 18
    public static let toolbarShadowOffsetY: CGFloat = 8
    public static let toolbarShadowBleed: CGFloat = 26

    /// Padding around the screenshot and toolbar, including toolbar shadow bleed.
    /// Unflipped window: origin at bottom-left.
    public static let chromePadding: CGFloat = 28
    public static let chromeGap: CGFloat = 10
    public static let minToolbarHeight: CGFloat = 44
    /// The annotation toolbar has a primary row and a fixed-height detail row.
    public static let estimatedToolbarHeight: CGFloat = 84
    public static let minContentWidth: CGFloat = 760

    public static func chromeSize(toolbarHeight: CGFloat) -> CGSize {
        CGSize(
            width: chromePadding * 2,
            height: chromePadding * 2 + chromeGap + toolbarHeight
        )
    }

    /// Canvas sits above the toolbar in an unflipped content view.
    public static func canvasFrame(
        imageSize: CGSize,
        toolbarHeight: CGFloat,
        in bounds: CGSize,
        padding: CGFloat = chromePadding,
        gap: CGFloat = chromeGap
    ) -> CGRect {
        let x = ((bounds.width - imageSize.width) / 2).rounded(.toNearestOrAwayFromZero)
        let y = padding + toolbarHeight + gap
        return CGRect(x: x, y: y, width: imageSize.width, height: imageSize.height)
    }

    /// Toolbar sits under the screenshot, origin at the bottom of the unflipped content view.
    public static func toolbarFrame(
        toolbarSize: CGSize,
        in bounds: CGSize,
        padding: CGFloat = chromePadding
    ) -> CGRect {
        let width = min(ceil(toolbarSize.width), max(1, bounds.width - padding * 2))
        let height = max(minToolbarHeight, ceil(toolbarSize.height))
        let x = ((bounds.width - width) / 2).rounded(.toNearestOrAwayFromZero)
        return CGRect(x: x, y: padding, width: width, height: height)
    }

    public static func fittedSize(imageSize: CGSize, in maxSize: CGSize) -> CGSize {
        let scale = min(
            1,
            maxSize.width / max(imageSize.width, 1),
            maxSize.height / max(imageSize.height, 1)
        )
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    public static func clampedOrigin(
        windowSize: CGSize,
        preferred: CGPoint,
        visibleFrame: CGRect,
        margin: CGFloat = 8
    ) -> CGPoint {
        RectMath.clampedOrigin(
            preferred,
            size: windowSize,
            in: visibleFrame.insetBy(dx: margin, dy: margin)
        )
    }

    public static func windowSize(
        imageSize: CGSize,
        chrome: CGSize,
        minContentWidth: CGFloat,
        maxSize: CGSize
    ) -> CGSize {
        let usableWidth = max(1, maxSize.width - chrome.width)
        let minWidth = min(minContentWidth, usableWidth)
        let width = min(max(imageSize.width, minWidth) + chrome.width, maxSize.width)
        let height = min(imageSize.height + chrome.height, maxSize.height)
        return CGSize(width: max(1, width), height: max(1, height))
    }

    /// Window / fullscreen editor: scale to fit, center in `visibleFrame`, toolbar below.
    public static func centered(
        imageSize: CGSize,
        toolbarSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat = 8
    ) -> EditorArrangement {
        let toolbar = normalizedToolbarSize(toolbarSize)
        let maxWindow = CGSize(
            width: max(1, visibleFrame.width - margin * 2),
            height: max(1, visibleFrame.height - margin * 2)
        )
        let chrome = chromeSize(toolbarHeight: toolbar.height)
        let maxImage = CGSize(
            width: max(1, maxWindow.width - chrome.width),
            height: max(1, maxWindow.height - chrome.height)
        )
        let fitted = fittedSize(imageSize: imageSize, in: maxImage)
        let size = CGSize(
            width: min(max(fitted.width, toolbar.width) + chrome.width, maxWindow.width),
            height: min(fitted.height + chrome.height, maxWindow.height)
        )
        let preferred = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        let origin = clampedOrigin(
            windowSize: size,
            preferred: preferred,
            visibleFrame: visibleFrame,
            margin: margin
        )
        return EditorArrangement(
            windowFrame: CGRect(origin: origin, size: size),
            canvasFrame: canvasFrame(imageSize: fitted, toolbarHeight: toolbar.height, in: size),
            toolbarFrame: toolbarFrame(toolbarSize: toolbar, in: size),
            imageSize: fitted,
            toolbarAnchor: .below,
            keepsCaptureAligned: false
        )
    }

    /// Region editor: keep the screenshot on the capture rect and put the toolbar
    /// in free space (below, otherwise above). Scale only when neither side fits.
    public static func inPlace(
        captureRect: CGRect,
        toolbarSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat = 8
    ) -> EditorArrangement {
        let padding = chromePadding
        let gap = chromeGap
        let toolbar = normalizedToolbarSize(toolbarSize)
        let stack = gap + toolbar.height
        let safe = visibleFrame.insetBy(dx: margin, dy: margin)

        let spaceBelow = captureRect.minY - safe.minY
        let spaceAbove = safe.maxY - captureRect.maxY

        var imageSize = captureRect.size
        var canvasScreen = captureRect
        var anchor: ToolbarAnchor
        var aligned = true

        if safe.width <= 0 || safe.height <= 0 {
            return centered(
                imageSize: captureRect.size,
                toolbarSize: toolbar,
                visibleFrame: visibleFrame,
                margin: margin
            )
        }

        if spaceBelow >= stack {
            anchor = .below
        } else if spaceAbove >= stack {
            anchor = .above
        } else {
            aligned = false
            anchor = spaceAbove > spaceBelow ? .above : .below
            let maxImage = CGSize(
                width: max(1, safe.width),
                height: max(1, safe.height - stack)
            )
            imageSize = fittedSize(imageSize: captureRect.size, in: maxImage)
            var canvasSafe = safe
            if anchor == .below {
                canvasSafe.origin.y += stack
                canvasSafe.size.height -= stack
            } else {
                canvasSafe.size.height -= stack
            }
            canvasScreen = CGRect(
                origin: RectMath.clampedOrigin(
                    CGPoint(
                        x: captureRect.midX - imageSize.width / 2,
                        y: captureRect.midY - imageSize.height / 2
                    ),
                    size: imageSize,
                    in: canvasSafe
                ),
                size: imageSize
            )
        }

        let toolbarScreen = toolbarRect(
            size: toolbar,
            around: canvasScreen,
            anchor: anchor,
            gap: gap,
            in: safe
        )

        if canvasScreen.intersects(toolbarScreen) {
            return centered(
                imageSize: captureRect.size,
                toolbarSize: toolbar,
                visibleFrame: visibleFrame,
                margin: margin
            )
        }

        let union = canvasScreen.union(toolbarScreen)
        let windowFrame = union.insetBy(dx: -padding, dy: -padding)
        return EditorArrangement(
            windowFrame: windowFrame,
            canvasFrame: canvasScreen.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY),
            toolbarFrame: toolbarScreen.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY),
            imageSize: imageSize,
            toolbarAnchor: anchor,
            keepsCaptureAligned: aligned && rectsAlign(canvasScreen, captureRect)
        )
    }

    private static func normalizedToolbarSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(1, ceil(size.width)),
            height: max(minToolbarHeight, ceil(size.height))
        )
    }

    private static func toolbarRect(
        size: CGSize,
        around canvas: CGRect,
        anchor: ToolbarAnchor,
        gap: CGFloat,
        in safe: CGRect
    ) -> CGRect {
        let x = RectMath.leadingX(for: size.width, centeringAt: canvas.midX, in: safe)
        let y: CGFloat
        switch anchor {
        case .below:
            y = canvas.minY - gap - size.height
        case .above:
            y = canvas.maxY + gap
        }
        return CGRect(
            origin: RectMath.clampedOrigin(
                CGPoint(x: x, y: y),
                size: size,
                in: safe
            ),
            size: size
        )
    }

    private static func rectsAlign(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5
            && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5
            && abs(a.height - b.height) < 0.5
    }
}
