import AppKit
import ScreenCaptureKit
import ShotKit

struct CaptureResult {
    var image: NSImage
    var rect: CGRect
    var screen: NSScreen
}

struct DisplayCaptureSnapshot {
    let screen: NSScreen
    let image: CGImage
    let imageWithoutWindowShadows: CGImage?

    var scale: CGFloat { screen.backingScaleFactor }
}

struct CaptureSnapshot {
    let displays: [CGDirectDisplayID: DisplayCaptureSnapshot]
    let windows: [CapturableWindow]
    let windowFrames: [CGWindowID: CGRect]

    var matchesCurrentScreens: Bool {
        let currentScreens = NSScreen.screens
        guard currentScreens.count == displays.count else { return false }
        return currentScreens.allSatisfy { screen in
            guard let captured = displays[screen.displayID] else { return false }
            return captured.screen.frame == screen.frame
                && captured.scale == screen.backingScaleFactor
        }
    }

    func cropRegion(_ selection: RegionSelection) throws -> CaptureResult {
        guard let display = displays[selection.displayID],
              let crop = cropRect(selection.rect, in: display) else {
            throw CaptureError.regionOutsideDisplay
        }
        return result(from: display.image, crop: crop, rect: selection.rect, screen: display.screen)
    }

    func cropWindow(id: CGWindowID, includeShadow: Bool) throws -> CaptureResult {
        guard let frame = windowFrames[id],
              let display = display(containing: frame),
              let crop = cropRect(frame, in: display) else {
            throw CaptureError.regionOutsideDisplay
        }
        let image = includeShadow
            ? display.image
            : (display.imageWithoutWindowShadows ?? display.image)
        return result(from: image, crop: crop, rect: frame, screen: display.screen)
    }

    private func display(containing rect: CGRect) -> DisplayCaptureSnapshot? {
        var best: (display: DisplayCaptureSnapshot, area: CGFloat)?
        for display in displays.values {
            let intersection = display.screen.frame.intersection(rect)
            let area = intersection.width * intersection.height
            guard area > 0, display.screen.frame.contains(rect) else { continue }
            if best == nil || area > best!.area {
                best = (display, area)
            }
        }
        return best?.display
    }

    private func cropRect(_ rect: CGRect, in display: DisplayCaptureSnapshot) -> CGRect? {
        RectMath.pixelCropRect(
            cocoaGlobal: rect,
            screenFrame: display.screen.frame,
            pixelSize: CGSize(width: display.image.width, height: display.image.height),
            scale: display.scale
        )
    }

    private func result(
        from image: CGImage,
        crop: CGRect,
        rect: CGRect,
        screen: NSScreen
    ) -> CaptureResult {
        let cropped = image.cropping(to: crop) ?? image
        let scale = screen.backingScaleFactor
        let pointSize = CGSize(
            width: CGFloat(cropped.width) / scale,
            height: CGFloat(cropped.height) / scale
        )
        return CaptureResult(
            image: NSImage(cgImage: cropped, size: pointSize),
            rect: rect,
            screen: screen
        )
    }
}

enum CaptureError: LocalizedError {
    case noDisplay
    case noWindow
    case regionOutsideDisplay
    case failed

    var errorDescription: String? {
        switch self {
        case .noDisplay: return String(localized: "找不到可用的显示器。")
        case .noWindow: return String(localized: "找不到要截取的窗口。")
        case .regionOutsideDisplay: return String(localized: "截图区域必须位于同一个显示器内。")
        case .failed: return String(localized: "截图失败。")
        }
    }
}

@MainActor
final class CaptureService {
    func captureSnapshot(
        catalog: WindowCatalog,
        needsNoShadowVariant: Bool
    ) async throws -> CaptureSnapshot {
        try await catalog.refreshLatest()
        try Task.checkCancellation()

        guard let content = catalog.content else {
            throw CaptureError.failed
        }

        var displays: [CGDirectDisplayID: DisplayCaptureSnapshot] = [:]
        for screen in NSScreen.screens {
            try Task.checkCancellation()
            guard let display = CoordinateSpace.display(matching: screen, in: catalog.displays) else {
                throw CaptureError.noDisplay
            }
            let image = try await captureDisplayImage(
                display: display,
                screen: screen,
                content: content,
                ignoreWindowShadows: false
            )
            var imageWithoutWindowShadows: CGImage?
            if needsNoShadowVariant {
                imageWithoutWindowShadows = try await captureDisplayImage(
                    display: display,
                    screen: screen,
                    content: content,
                    ignoreWindowShadows: true
                )
            }
            displays[screen.displayID] = DisplayCaptureSnapshot(
                screen: screen,
                image: image,
                imageWithoutWindowShadows: imageWithoutWindowShadows
            )
        }

        let windowFrames = Dictionary(
            uniqueKeysWithValues: content.windows.map { ($0.windowID, $0.frame) }
        )
        return CaptureSnapshot(
            displays: displays,
            windows: catalog.windows,
            windowFrames: windowFrames
        )
    }

    func captureWindow(id: CGWindowID, catalog: WindowCatalog, includeShadow: Bool) async throws -> CaptureResult {
        try await catalog.ensureShareableContent()
        guard let scWindow = catalog.scWindow(id: id) else {
            try await catalog.refresh()
            guard let scWindow = catalog.scWindow(id: id) else {
                throw CaptureError.noWindow
            }
            return try await captureResolvedWindow(scWindow, includeShadow: includeShadow)
        }
        return try await captureResolvedWindow(scWindow, includeShadow: includeShadow)
    }

    private func captureResolvedWindow(
        _ scWindow: SCWindow,
        includeShadow: Bool
    ) async throws -> CaptureResult {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        guard let screen = CoordinateSpace.screen(for: scWindow.frame) else {
            throw CaptureError.noDisplay
        }
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.capturesAudio = false
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = !includeShadow
        config.width = pixelSize(scWindow.frame.width, scale: scale)
        config.height = pixelSize(scWindow.frame.height, scale: scale)
        if #available(macOS 15.0, *) {
            config.shouldBeOpaque = false
        }

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let pointSize = CGSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
        let image = NSImage(cgImage: cgImage, size: pointSize)
        return CaptureResult(image: image, rect: scWindow.frame, screen: screen)
    }

    func captureRegion(_ selection: RegionSelection, catalog: WindowCatalog) async throws -> CaptureResult {
        try await catalog.ensureShareableContent()
        let rect = selection.rect
        guard rect.width > 0, rect.height > 0 else {
            throw CaptureError.regionOutsideDisplay
        }
        guard let screen = NSScreen.screens.first(where: { $0.displayID == selection.displayID }) else {
            throw CaptureError.noDisplay
        }
        guard screen.frame.contains(rect) else {
            throw CaptureError.regionOutsideDisplay
        }
        guard let display = CoordinateSpace.display(matching: screen, in: catalog.displays) else {
            throw CaptureError.noDisplay
        }

        let filter = contentFilter(display: display, content: catalog.content)
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.capturesAudio = false
        config.showsCursor = false
        config.sourceRect = CoordinateSpace.displaySourceRect(rect, on: screen)
        config.width = pixelSize(rect.width, scale: scale)
        config.height = pixelSize(rect.height, scale: scale)

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let image = NSImage(cgImage: cgImage, size: rect.size)
        return CaptureResult(image: image, rect: rect, screen: screen)
    }

    func captureDisplay(_ screen: NSScreen, catalog: WindowCatalog) async throws -> CaptureResult {
        try await catalog.ensureShareableContent()
        guard let display = CoordinateSpace.display(matching: screen, in: catalog.displays) else {
            throw CaptureError.noDisplay
        }
        let cgImage = try await captureDisplayImage(
            display: display,
            screen: screen,
            content: catalog.content,
            ignoreWindowShadows: false
        )
        let image = NSImage(cgImage: cgImage, size: display.frame.size)
        return CaptureResult(image: image, rect: display.frame, screen: screen)
    }

    private func captureDisplayImage(
        display: SCDisplay,
        screen: NSScreen,
        content: SCShareableContent?,
        ignoreWindowShadows: Bool
    ) async throws -> CGImage {
        let filter = contentFilter(display: display, content: content)
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.capturesAudio = false
        config.showsCursor = false
        config.ignoreShadowsDisplay = ignoreWindowShadows
        config.width = pixelSize(display.frame.width, scale: scale)
        config.height = pixelSize(display.frame.height, scale: scale)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func contentFilter(display: SCDisplay, content: SCShareableContent?) -> SCContentFilter {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let ourWindows = content?.windows.filter { $0.owningApplication?.processID == ourPID } ?? []
        if let app = content?.applications.first(where: { $0.processID == ourPID }) {
            return SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
        }
        return SCContentFilter(display: display, excludingWindows: ourWindows)
    }

    private func pixelSize(_ points: CGFloat, scale: CGFloat) -> Int {
        max(1, Int((points * scale).rounded()))
    }
}
