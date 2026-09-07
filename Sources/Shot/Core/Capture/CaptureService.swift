import AppKit
import ScreenCaptureKit
import ShotKit

enum CaptureResultKind: Equatable {
    case standard
    case window
    case scrolling
}

struct CaptureResult {
    var image: NSImage
    var rect: CGRect
    var screen: NSScreen
    var kind: CaptureResultKind = .standard
    var hasAppliedBackground = false
}

struct RegionCaptureFrame {
    let image: CGImage
    let screen: NSScreen
    let scale: CGFloat
}

struct DisplayCaptureSnapshot {
    let screen: NSScreen
    let image: CGImage

    var scale: CGFloat { screen.backingScaleFactor }
}

private struct DisplayCaptureTaskResult: @unchecked Sendable {
    let screen: NSScreen
    let image: CGImage
}

struct CaptureSnapshot {
    let displays: [CGDirectDisplayID: DisplayCaptureSnapshot]
    let windows: [CapturableWindow]

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
    case timedOut
    case scrollCaptureTooLong
    case scrollCaptureDirectionChanged
    case scrollCaptureTargetMoved
    case scrollCaptureNeedsSlowerScrolling
    case scrollCaptureFailed
    case failed

    var errorDescription: String? {
        switch self {
        case .noDisplay: return String(localized: "找不到可用的显示器。")
        case .noWindow: return String(localized: "找不到要截取的窗口。")
        case .regionOutsideDisplay: return String(localized: "截图区域必须位于同一个显示器内。")
        case .timedOut: return String(localized: "截图处理超时，已自动取消。")
        case .scrollCaptureTooLong: return String(localized: "滚动截图已达到长度上限，请结束当前截图。")
        case .scrollCaptureDirectionChanged: return String(localized: "滚动方向发生变化，请保持同一方向完成截图。")
        case .scrollCaptureTargetMoved: return String(localized: "滚动截图目标窗口发生变化，请重新选择区域。")
        case .scrollCaptureNeedsSlowerScrolling: return String(localized: "滚动过快，无法稳定拼接，请减慢滚动速度。")
        case .scrollCaptureFailed: return String(localized: "滚动截图拼接失败。")
        case .failed: return String(localized: "截图失败。")
        }
    }
}

@MainActor
final class CaptureService {
    func captureSnapshot(catalog: WindowCatalog) async throws -> CaptureSnapshot {
        try await refreshCatalogLatest(catalog)
        try Task.checkCancellation()

        guard let content = catalog.content else {
            throw CaptureError.failed
        }

        let screens = NSScreen.screens
        let results = try await withThrowingTaskGroup(of: DisplayCaptureTaskResult.self) { group in
            for screen in screens {
                try Task.checkCancellation()
                guard let display = CoordinateSpace.display(matching: screen, in: catalog.displays) else {
                    throw CaptureError.noDisplay
                }
                group.addTask { [self] in
                    try Task.checkCancellation()
                    let image = try await captureDisplayImage(
                        display: display,
                        screen: screen,
                        content: content,
                        ignoreWindowShadows: false
                    )
                    try Task.checkCancellation()
                    return DisplayCaptureTaskResult(screen: screen, image: image)
                }
            }

            var results: [DisplayCaptureTaskResult] = []
            for try await result in group {
                guard screenConfigurationMatches(screens) else {
                    throw CaptureError.noDisplay
                }
                results.append(result)
            }
            return results
        }
        try Task.checkCancellation()

        var displays: [CGDirectDisplayID: DisplayCaptureSnapshot] = [:]
        for result in results {
            displays[result.screen.displayID] = DisplayCaptureSnapshot(
                screen: result.screen,
                image: result.image
            )
        }
        guard displays.count == screens.count else {
            throw CaptureError.noDisplay
        }

        return CaptureSnapshot(
            displays: displays,
            windows: catalog.windows
        )
    }

    func captureWindow(id: CGWindowID, catalog: WindowCatalog, includeShadow: Bool) async throws -> CaptureResult {
        try await ensureShareableContent(catalog)
        guard let scWindow = catalog.scWindow(id: id) else {
            try await refreshCatalog(catalog)
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
        // ScreenCaptureKit reports window bounds in the same top-left-origin
        // global space as kCGWindowBounds. CaptureResult and editor layout use
        // AppKit's bottom-left-origin Cocoa screen space, so convert exactly
        // once before selecting the display and handing the result downstream.
        guard let geometry = CoordinateSpace.windowGeometry(
            fromCGWindowBounds: scWindow.frame
        ) else {
            throw CaptureError.noDisplay
        }
        let cocoaFrame = geometry.frame
        let screen = geometry.screen
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.capturesAudio = false
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = WindowCapturePolicy.ignoresShadowsSingleWindow(
            includeShadow: includeShadow
        )
        config.width = pixelSize(scWindow.frame.width, scale: scale)
        config.height = pixelSize(scWindow.frame.height, scale: scale)
        if #available(macOS 15.0, *) {
            config.shouldBeOpaque = false
        }

        let cgImage = try await captureImage(filter: filter, configuration: config)
        let pointSize = CGSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
        let image = NSImage(cgImage: cgImage, size: pointSize)
        return CaptureResult(image: image, rect: cocoaFrame, screen: screen, kind: .window)
    }

    func captureRegionFrame(
        _ selection: RegionSelection,
        catalog: WindowCatalog
    ) async throws -> RegionCaptureFrame {
        try await ensureShareableContent(catalog)
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

        let cgImage = try await captureImage(filter: filter, configuration: config)
        return RegionCaptureFrame(image: cgImage, screen: screen, scale: scale)
    }

    func captureRegion(_ selection: RegionSelection, catalog: WindowCatalog) async throws -> CaptureResult {
        let frame = try await captureRegionFrame(selection, catalog: catalog)
        let image = NSImage(cgImage: frame.image, size: selection.rect.size)
        return CaptureResult(image: image, rect: selection.rect, screen: frame.screen)
    }

    func captureDisplay(_ screen: NSScreen, catalog: WindowCatalog) async throws -> CaptureResult {
        try await ensureShareableContent(catalog)
        guard let display = CoordinateSpace.display(matching: screen, in: catalog.displays) else {
            throw CaptureError.noDisplay
        }
        let cgImage = try await captureDisplayImage(
            display: display,
            screen: screen,
            content: catalog.content,
            ignoreWindowShadows: false
        )
        // `CaptureResult.rect` is consumed by AppKit window layout, so keep it
        // in the same global Cocoa coordinate space as `NSScreen.frame`.
        // ScreenCaptureKit's display frame can use a different origin on a
        // multi-display arrangement (notably for displays above/below the
        // primary display), even though its size matches the captured image.
        let image = NSImage(cgImage: cgImage, size: screen.frame.size)
        return CaptureResult(image: image, rect: screen.frame, screen: screen)
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
        return try await captureImage(filter: filter, configuration: config)
    }

    private func ensureShareableContent(_ catalog: WindowCatalog) async throws {
        try await AsyncTimeout.run(
            timeout: .seconds(15),
            timeoutError: CaptureError.timedOut
        ) {
            try await catalog.ensureShareableContent()
        }
    }

    private func refreshCatalog(_ catalog: WindowCatalog) async throws {
        try await AsyncTimeout.run(
            timeout: .seconds(15),
            timeoutError: CaptureError.timedOut
        ) {
            try await catalog.refresh()
        }
    }

    private func refreshCatalogLatest(_ catalog: WindowCatalog) async throws {
        try await AsyncTimeout.run(
            timeout: .seconds(15),
            timeoutError: CaptureError.timedOut
        ) {
            try await catalog.refreshLatest()
        }
    }

    private func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        try await AsyncTimeout.run(
            timeout: .seconds(15),
            timeoutError: CaptureError.timedOut
        ) {
            try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        }
    }

    private func contentFilter(display: SCDisplay, content: SCShareableContent?) -> SCContentFilter {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let ourWindows = content?.windows.filter { $0.owningApplication?.processID == ourPID } ?? []
        let statusItemWindowIDs = menuBarStatusItemWindowIDs(ownedBy: ourPID)
        let windowsToExclude = ourWindows.filter {
            !statusItemWindowIDs.contains($0.windowID)
        }

        // MenuBarExtra is represented by an app-owned status-window layer.
        // Excluding the whole application also removes Shot's own menu bar
        // icon from display captures, so exclude only our capture windows.
        let filter = SCContentFilter(display: display, excludingWindows: windowsToExclude)
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }
        return filter
    }

    private func menuBarStatusItemWindowIDs(ownedBy processID: pid_t) -> Set<CGWindowID> {
        let options: CGWindowListOption = [.optionOnScreenOnly]
        let dictionaries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let statusWindowLevel = Int(CGWindowLevelForKey(.statusWindow))

        return Set(dictionaries.compactMap { dictionary in
            guard let ownerPID = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == processID,
                  let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == statusWindowLevel,
                  let windowID = dictionary[kCGWindowNumber as String] as? CGWindowID else {
                return nil
            }
            return windowID
        })
    }

    private func pixelSize(_ points: CGFloat, scale: CGFloat) -> Int {
        max(1, Int((points * scale).rounded()))
    }

    private func screenConfigurationMatches(_ initialScreens: [NSScreen]) -> Bool {
        let currentScreens = NSScreen.screens
        guard currentScreens.count == initialScreens.count else { return false }
        return initialScreens.allSatisfy { initial in
            guard let current = currentScreens.first(where: { $0.displayID == initial.displayID }) else {
                return false
            }
            return current.frame == initial.frame
                && current.backingScaleFactor == initial.backingScaleFactor
        }
    }
}
