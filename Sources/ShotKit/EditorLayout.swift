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

/// Layout for the standard, resizable annotation window. Frames are local to
/// the window's content view, whose origin is the bottom-left corner.
public struct EditorWindowLayout: Equatable, Sendable {
    public var contentSize: CGSize
    public var canvasFrame: CGRect
    public var toolbarFrame: CGRect
    public var imageSize: CGSize

    public init(
        contentSize: CGSize,
        canvasFrame: CGRect,
        toolbarFrame: CGRect,
        imageSize: CGSize
    ) {
        self.contentSize = contentSize
        self.canvasFrame = canvasFrame
        self.toolbarFrame = toolbarFrame
        self.imageSize = imageSize
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
    /// The window toolbar has a 44 pt primary row, a one-point separator, and
    /// a stable 36 pt contextual row so switching tools never moves the canvas.
    public static let estimatedToolbarHeight: CGFloat = 81
    public static let minContentWidth: CGFloat = 760
    /// The standard editor uses a full-width toolbar at the top of the content
    /// view and a neutral workspace with a modest inset around the screenshot.
    public static let windowedWorkspacePadding: CGFloat = 16
    public static let windowedToolbarGap: CGFloat = 0
    public static let windowedMinimumWorkspaceHeight: CGFloat = 160

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

    /// Chooses the initial content size for the standard editor window. The
    /// image stays at 1x whenever it fits, while large captures are reduced to
    /// the visible display area. The full-width toolbar is docked above the
    /// workspace and determines the minimum useful width.
    public static func windowedInitialContentSize(
        imageSize: CGSize,
        toolbarSize: CGSize,
        maxContentSize: CGSize,
        padding: CGFloat = windowedWorkspacePadding,
        minimumWorkspaceHeight: CGFloat = windowedMinimumWorkspaceHeight
    ) -> CGSize {
        let maxSize = CGSize(
            width: max(1, maxContentSize.width),
            height: max(1, maxContentSize.height)
        )
        let toolbar = normalizedToolbarSize(toolbarSize)
        let maxImage = CGSize(
            width: max(1, maxSize.width - padding * 2),
            height: max(1, maxSize.height - toolbar.height - windowedToolbarGap - padding * 2)
        )
        let fitted = fittedSize(imageSize: imageSize, in: maxImage)
        let minimumWidth = min(maxSize.width, max(minContentWidth, toolbar.width))
        let naturalWidth = max(fitted.width + padding * 2, minimumWidth)
        let naturalHeight = max(
            fitted.height + toolbar.height + windowedToolbarGap + padding * 2,
            toolbar.height + windowedToolbarGap + minimumWorkspaceHeight + padding * 2
        )
        return CGSize(
            width: min(maxSize.width, max(1, naturalWidth)),
            height: min(maxSize.height, max(1, naturalHeight))
        )
    }

    /// Computes the top toolbar and canvas frames for the current content size.
    /// This is called again after every window resize.
    public static func windowed(
        imageSize: CGSize,
        toolbarSize: CGSize,
        contentSize: CGSize,
        padding: CGFloat = windowedWorkspacePadding
    ) -> EditorWindowLayout {
        let size = CGSize(width: max(1, contentSize.width), height: max(1, contentSize.height))
        let toolbar = normalizedToolbarSize(toolbarSize)
        let toolbarHeight = min(toolbar.height, size.height)
        let toolbarFrame = CGRect(
            x: 0,
            y: size.height - toolbarHeight,
            width: size.width,
            height: toolbarHeight
        )
        let workspace = CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: max(1, toolbarFrame.minY - windowedToolbarGap)
        )
        let maxImage = CGSize(
            width: max(1, workspace.width - padding * 2),
            height: max(1, workspace.height - padding * 2)
        )
        let fitted = fittedSize(imageSize: imageSize, in: maxImage)
        let canvasFrame = CGRect(
            x: workspace.midX - fitted.width / 2,
            y: workspace.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        ).standardized
        return EditorWindowLayout(
            contentSize: size,
            canvasFrame: canvasFrame,
            toolbarFrame: toolbarFrame,
            imageSize: fitted
        )
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

    /// Centered floating editor fallback: scale to fit, center in `visibleFrame`, toolbar below.
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
        // The capture may touch the display's visible edges (so do not use
        // `safe` here), but it must still be wholly on this display before we
        // preserve its original size and position. This also covers full
        // display captures that include the menu bar or Dock area.
        let captureFitsVisibleFrame = visibleFrame.contains(captureRect)

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
        // A very narrow display cannot host the full toolbar beside an
        // in-place capture. Let the existing centered layout reduce the
        // toolbar frame and image together instead of allowing the toolbar to
        // extend beyond the source display.
        guard toolbar.width <= safe.width, toolbar.height <= safe.height else {
            return centered(
                imageSize: captureRect.size,
                toolbarSize: toolbar,
                visibleFrame: visibleFrame,
                margin: margin
            )
        }

        if captureFitsVisibleFrame, spaceBelow >= stack {
            anchor = .below
        } else if captureFitsVisibleFrame, spaceAbove >= stack {
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
