import CoreGraphics

public enum MagnifierLayout {
    /// Size of the captured content inside the lens. The returned frame also
    /// includes the surrounding HUD chrome.
    public static let defaultSize = CGSize(width: 124, height: 124)
    /// Distance between the pointer anchor and the nearest lens edge.
    public static let defaultGap: CGFloat = 20
    public static let defaultZoom: CGFloat = 8
    public static let defaultChromeInset: CGFloat = 4

    public static func frame(
        cursor: CGPoint,
        size: CGSize = defaultSize,
        visibleFrame: CGRect,
        gap: CGFloat = defaultGap,
        margin: CGFloat = 8,
        chromeInset: CGFloat = defaultChromeInset
    ) -> CGRect {
        guard size.width > 0,
              size.height > 0,
              visibleFrame.width > 0,
              visibleFrame.height > 0,
              cursor.x.isFinite,
              cursor.y.isFinite,
              gap.isFinite,
              gap >= 0,
              margin.isFinite,
              margin >= 0,
              chromeInset.isFinite,
              chromeInset >= 0
        else {
            return .zero
        }

        let outerSize = CGSize(
            width: size.width + chromeInset * 2,
            height: size.height + chromeInset * 2
        )
        guard outerSize.width.isFinite, outerSize.height.isFinite else { return .zero }

        let safe = visibleFrame.insetBy(dx: margin, dy: margin)
        // Keep the cursor as the visual anchor. The stable lower-right
        // placement matches the common macOS capture pattern and avoids the
        // lens jumping to a different anchor once a drag creates a selection.
        // The remaining candidates are only fallbacks for screen edges.
        let candidates = [
            CGRect(
                x: cursor.x + gap,
                y: cursor.y - gap - outerSize.height,
                width: outerSize.width,
                height: outerSize.height
            ),
            CGRect(
                x: cursor.x - gap - outerSize.width,
                y: cursor.y - gap - outerSize.height,
                width: outerSize.width,
                height: outerSize.height
            ),
            CGRect(
                x: cursor.x + gap,
                y: cursor.y + gap,
                width: outerSize.width,
                height: outerSize.height
            ),
            CGRect(
                x: cursor.x - gap - outerSize.width,
                y: cursor.y + gap,
                width: outerSize.width,
                height: outerSize.height
            )
        ]

        return candidates.first(where: safe.contains)
            ?? RectMath.clampedRect(candidates[0], in: safe)
    }

    /// Places the lens outside a live selection, preferring the selection's
    /// lower-right corner. The zero rect means there is no unobstructed
    /// placement in the visible area.
    public static func frame(
        nextTo selectionRect: CGRect,
        size: CGSize = defaultSize,
        visibleFrame: CGRect,
        gap: CGFloat = defaultGap,
        margin: CGFloat = 8,
        chromeInset: CGFloat = defaultChromeInset
    ) -> CGRect {
        guard size.width > 0,
              size.height > 0,
              visibleFrame.width > 0,
              visibleFrame.height > 0,
              selectionRect.width > 0,
              selectionRect.height > 0,
              selectionRect.minX.isFinite,
              selectionRect.minY.isFinite,
              selectionRect.maxX.isFinite,
              selectionRect.maxY.isFinite,
              gap.isFinite,
              gap >= 0,
              margin.isFinite,
              margin >= 0,
              chromeInset.isFinite,
              chromeInset >= 0
        else {
            return .zero
        }

        let outerSize = CGSize(
            width: size.width + chromeInset * 2,
            height: size.height + chromeInset * 2
        )
        guard outerSize.width.isFinite, outerSize.height.isFinite else { return .zero }

        let safe = visibleFrame.insetBy(dx: margin, dy: margin)
        let selection = selectionRect.standardized
        let candidates = [
            // Keep the lens visually tied to the requested lower-right corner
            // while placing the entire HUD below the captured area.
            CGRect(
                x: selection.maxX - outerSize.width,
                y: selection.minY - gap - outerSize.height,
                width: outerSize.width,
                height: outerSize.height
            ),
            // If the bottom edge is unavailable, keep it beside the right edge.
            CGRect(
                x: selection.maxX + gap,
                y: selection.minY,
                width: outerSize.width,
                height: outerSize.height
            ),
            // Then try the matching position above the selection.
            CGRect(
                x: selection.maxX - outerSize.width,
                y: selection.maxY + gap,
                width: outerSize.width,
                height: outerSize.height
            ),
            // Last resort: the lower-left side still keeps the image unobscured.
            CGRect(
                x: selection.minX - gap - outerSize.width,
                y: selection.minY,
                width: outerSize.width,
                height: outerSize.height
            )
        ]

        return candidates.first {
            safe.contains($0) && !$0.intersects(selection)
        } ?? .zero
    }

    /// Returns the screenshot window inside the outer HUD frame.
    public static func contentFrame(
        for outerFrame: CGRect,
        chromeInset: CGFloat = defaultChromeInset
    ) -> CGRect {
        guard outerFrame.width > chromeInset * 2,
              outerFrame.height > chromeInset * 2,
              chromeInset.isFinite,
              chromeInset >= 0
        else { return .zero }
        return outerFrame.insetBy(dx: chromeInset, dy: chromeInset)
    }

    public static func sourceRect(
        cursor: CGPoint,
        imageBounds: CGRect,
        destinationSize: CGSize,
        zoom: CGFloat = defaultZoom
    ) -> CGRect {
        guard cursor.x.isFinite,
              cursor.y.isFinite,
              imageBounds.width > 0,
              imageBounds.height > 0,
              destinationSize.width > 0,
              destinationSize.height > 0,
              imageBounds.width.isFinite,
              imageBounds.height.isFinite,
              destinationSize.width.isFinite,
              destinationSize.height.isFinite,
              zoom.isFinite,
              zoom > 0
        else { return .zero }

        // The source must have the same aspect ratio as the lens. Otherwise
        // NSImage.draw(in:from:) stretches the captured content to fill the
        // lens, which is especially visible on 16:9 and 16:10 displays.
        // `zoom` is the number of lens points represented by one source point.
        let desiredSize = CGSize(
            width: destinationSize.width / zoom,
            height: destinationSize.height / zoom
        )
        guard desiredSize.width.isFinite, desiredSize.height.isFinite else { return .zero }
        let fitScale = min(
            1,
            imageBounds.width / desiredSize.width,
            imageBounds.height / desiredSize.height
        )
        let sourceSize = CGSize(
            width: desiredSize.width * fitScale,
            height: desiredSize.height * fitScale
        )
        let origin = CGPoint(
            x: cursor.x - sourceSize.width / 2,
            y: cursor.y - sourceSize.height / 2
        )
        return RectMath.clampedRect(
            CGRect(origin: origin, size: sourceSize),
            in: imageBounds
        )
    }

    /// Maps the cursor from the source image into the displayed lens. When a
    /// cursor is close to an image edge, the source rect is clamped and the
    /// cursor is no longer at the lens center.
    public static func cursorPosition(
        cursor: CGPoint,
        sourceRect: CGRect,
        destinationFrame: CGRect
    ) -> CGPoint {
        guard sourceRect.width > 0,
              sourceRect.height > 0,
              destinationFrame.width > 0,
              destinationFrame.height > 0,
              cursor.x.isFinite,
              cursor.y.isFinite else {
            return CGPoint(x: destinationFrame.midX, y: destinationFrame.midY)
        }

        let normalizedX = RectMath.clamped(
            (cursor.x - sourceRect.minX) / sourceRect.width,
            lower: 0,
            upper: 1
        )
        let normalizedY = RectMath.clamped(
            (cursor.y - sourceRect.minY) / sourceRect.height,
            lower: 0,
            upper: 1
        )
        return CGPoint(
            x: destinationFrame.minX + normalizedX * destinationFrame.width,
            y: destinationFrame.minY + normalizedY * destinationFrame.height
        )
    }
}
