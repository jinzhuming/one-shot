import AppKit
import ShotKit
import SwiftUI

@MainActor
protocol OverlayControllerDelegate: AnyObject {
    func overlayDidCancel()
    func overlayDidPickWindow(id: CGWindowID)
    func overlayDidPickRegion(selection: RegionSelection)
    func overlayDidPickFullscreen(screen: NSScreen)
    func overlayDidInvalidateDisplayConfiguration()
}

@MainActor
final class OverlayController: NSObject, SelectionOverlayDelegate {
    weak var delegate: OverlayControllerDelegate?

    private var overlayWindows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var hudViews: [ObjectIdentifier: CaptureHUDView] = [:]
    private var modeBarWindows: [CGDirectDisplayID: NSWindow] = [:]
    private let modeState = OverlayModeState()

    private var mode: CaptureMode {
        get { modeState.mode }
        set { modeState.mode = newValue }
    }
    private let catalog = WindowCatalog.shared
    private var highlighted: CapturableWindow?
    private var overlapIDs: [CGWindowID] = []
    private var overlapIndex = 0
    private var selectionRect: CGRect?
    private var selectionDisplayID: CGDirectDisplayID?
    private var selectionDisplayFrame: CGRect?
    private var dragStart: CGPoint?
    private var clickedWindow: CapturableWindow?
    private var isDragging = false
    private var isMovingSelection = false
    private var moveAnchor: CGPoint?
    private var spaceDown = false
    private var shiftDown = false
    private var dimOnly = false
    private var isFrozen = false
    private var refreshTask: Task<Void, Never>?
    private var mouseRefreshTask: Task<Void, Never>?
    private var windowSnapshotRevision = 0
    private var isSnapshotBacked = false
    private var hint: String?
    private var hintTask: Task<Void, Never>?
    private var screenParametersObserver: NSObjectProtocol?

    var windowCatalog: WindowCatalog { catalog }

    override init() {
        super.init()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenParametersChanged()
            }
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    func present(mode: CaptureMode, snapshot: CaptureSnapshot? = nil) {
        stopCatalogRefresh()
        hintTask?.cancel()
        hintTask = nil
        self.mode = mode
        isSnapshotBacked = snapshot != nil
        dimOnly = false
        isFrozen = false
        highlighted = nil
        overlapIDs = []
        overlapIndex = 0
        selectionRect = nil
        selectionDisplayID = nil
        selectionDisplayFrame = nil
        clickedWindow = nil
        dragStart = nil
        isDragging = false
        isMovingSelection = false
        moveAnchor = nil
        spaceDown = false
        hint = nil
        if let snapshot {
            catalog.applyWindowsSnapshot(snapshot.windows)
        } else {
            catalog.refreshWindowsFromCG()
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
        showOverlays(interactive: true, snapshot: snapshot)
        if snapshot == nil {
            startCatalogRefresh()
        }
        refreshHover(at: NSEvent.mouseLocation, preserveCycle: false)
        applyVisuals()
    }

    func clearSelectionHole() {
        selectionRect = nil
        highlighted = nil
        applyVisuals()
    }

    func enterDimOnly() {
        if overlayWindows.isEmpty {
            presentDimBackdrop()
            return
        }
        dimOnly = true
        isSnapshotBacked = false
        highlighted = nil
        overlapIDs = []
        overlapIndex = 0
        clickedWindow = nil
        isDragging = false
        hint = nil
        for window in overlayWindows.values {
            window.ignoresMouseEvents = true
        }
        hideModeBars()
        hideHUDs()
        applyVisuals()
        stopCatalogRefresh()
    }

    func freezeForCapture() {
        isFrozen = true
        hideModeBars()
        stopCatalogRefresh()
    }

    func suspendForModal() {
        overlayWindows.values.forEach { $0.orderOut(nil) }
        modeBarWindows.values.forEach { $0.orderOut(nil) }
    }

    func resumeAfterModal() {
        for screen in NSScreen.screens {
            overlayWindows[screen.displayID]?.orderFront(nil)
            modeBarWindows[screen.displayID]?.orderFront(nil)
        }
    }

    func presentDimBackdrop() {
        stopCatalogRefresh()
        hintTask?.cancel()
        hintTask = nil
        dimOnly = true
        isFrozen = false
        isSnapshotBacked = false
        highlighted = nil
        overlapIDs = []
        overlapIndex = 0
        selectionRect = nil
        selectionDisplayID = nil
        selectionDisplayFrame = nil
        clickedWindow = nil
        dragStart = nil
        isDragging = false
        hint = nil
        showOverlays(interactive: false)
        applyVisuals()
    }

    func dismiss() {
        stopCatalogRefresh()
        hintTask?.cancel()
        hintTask = nil
        destroyOverlays()
        highlighted = nil
        overlapIDs = []
        overlapIndex = 0
        selectionRect = nil
        selectionDisplayID = nil
        selectionDisplayFrame = nil
        dragStart = nil
        clickedWindow = nil
        isDragging = false
        dimOnly = false
        isFrozen = false
        isSnapshotBacked = false
        spaceDown = false
        hint = nil
        NSCursor.arrow.set()
    }

    func overlayMouseMoved(_ pointInScreen: CGPoint) {
        guard !dimOnly, !isFrozen, !isDragging else { return }
        requestWindowRefreshForMouseMovement()
        let previousID = highlighted?.windowID
        refreshHover(at: pointInScreen, preserveCycle: true)
        guard highlighted?.windowID != previousID else { return }
        applyVisuals()
    }

    func overlayMouseDown(_ pointInScreen: CGPoint) {
        guard !dimOnly, !isFrozen else { return }
        dragStart = pointInScreen
        isDragging = false
        isMovingSelection = spaceDown && selectionRect != nil
        if isMovingSelection {
            moveAnchor = pointInScreen
        } else {
            setSelectionDisplay(for: pointInScreen)
        }
        refreshHover(at: pointInScreen, preserveCycle: true)
        clickedWindow = highlighted
        applyVisuals()
    }

    func overlayMouseDragged(_ pointInScreen: CGPoint) {
        guard !dimOnly, !isFrozen, dragStart != nil else { return }

        if spaceDown, isMovingSelection, let rect = selectionRect {
            if let anchor = moveAnchor {
                let boundedPoint = clampedSelectionPoint(pointInScreen)
                let translated = SelectionGeometry.translated(
                    rect,
                    by: CGSize(width: boundedPoint.x - anchor.x, height: boundedPoint.y - anchor.y)
                )
                selectionRect = clampedSelection(translated)
                moveAnchor = boundedPoint
            }
            isDragging = true
            highlighted = nil
            clickedWindow = nil
            applyVisuals()
            return
        }

        guard let start = dragStart else { return }
        let endpoint = clampedSelectionPoint(pointInScreen)
        let distance = hypot(endpoint.x - start.x, endpoint.y - start.y)
        if OverlayModeSwitch.dragEntersArea(kind: mode.overlayKind, distance: distance) {
            mode = .area
            highlighted = nil
            clickedWindow = nil
            overlapIDs = []
            overlapIndex = 0
        }
        guard mode.allowsAreaDrag, distance > OverlayModeSwitch.dragThreshold else { return }

        isDragging = true
        highlighted = nil
        clickedWindow = nil
        overlapIDs = []
        overlapIndex = 0
        hideModeBars()
        selectionRect = clampedSelection(
            SelectionGeometry.rect(from: start, to: endpoint, square: shiftDown)
        )
        if spaceDown {
            isMovingSelection = true
            moveAnchor = pointInScreen
        }
        applyVisuals()
    }

    func overlayMouseUp(_ pointInScreen: CGPoint) {
        guard !dimOnly, !isFrozen else { return }
        defer {
            dragStart = nil
            isDragging = false
            isMovingSelection = false
            moveAnchor = nil
            clickedWindow = nil
        }

        if isDragging, let rect = selectionRect,
           rect.width > OverlayModeSwitch.dragThreshold,
           rect.height > OverlayModeSwitch.dragThreshold {
            guard let displayID = selectionDisplayID else {
                showHint(String(localized: "找不到选区所在的显示器。"))
                return
            }
            let selection = RegionSelection(rect: rect, displayID: displayID)
            persistLastSelection(selection)
            freezeForCapture()
            delegate?.overlayDidPickRegion(selection: selection)
            return
        }

        restoreModeBarsIfNeeded()

        if mode == .fullscreen, let screen = CoordinateSpace.screen(containing: pointInScreen) {
            freezeForCapture()
            delegate?.overlayDidPickFullscreen(screen: screen)
            return
        }

        if OverlayModeSwitch.clickWithoutDragEntersWindow(kind: mode.overlayKind, isDragging: isDragging) {
            applyMode(.window)
            return
        }

        if mode.allowsWindowClick, let window = clickedWindow ?? highlighted {
            freezeForCapture()
            delegate?.overlayDidPickWindow(id: window.windowID)
            return
        }

        if mode == .window {
            showHint(String(localized: "未命中窗口，请点击窗口。"))
        } else if mode == .allInOne {
            showHint(String(localized: "未命中窗口，请点窗口或拖拽区域。"))
        }
    }

    func overlayKeyDown(_ event: NSEvent) {
        if event.type == .keyUp {
            if event.keyCode == 49 {
                spaceDown = false
                if isDragging, let rect = selectionRect {
                    dragStart = SelectionGeometry.resizeAnchor(
                        for: rect,
                        mouse: clampedSelectionPoint(NSEvent.mouseLocation)
                    )
                    isMovingSelection = false
                    moveAnchor = nil
                    recomputeSelectionIfNeeded()
                }
            }
            return
        }
        if event.keyCode == 53 {
            delegate?.overlayDidCancel()
            return
        }
        if event.keyCode == 48 {
            cycleHighlightedWindow(reverse: event.modifierFlags.contains(.shift) || shiftDown)
            return
        }
        if !event.isARepeat,
           !isDragging,
           AppSettings.shared.areaWindowToggleHotkey.matches(event),
           let next = OverlayModeSwitch.toggled(from: mode.overlayKind) {
            switch next {
            case .area:
                applyMode(.area)
            case .window:
                applyMode(.window)
            case .other:
                break
            }
            return
        }
        if event.keyCode == 49 {
            spaceDown = true
            if isDragging, selectionRect != nil {
                isMovingSelection = true
                moveAnchor = clampedSelectionPoint(NSEvent.mouseLocation)
            }
            return
        }
        if event.keyCode == 36, mode == .fullscreen,
           let screen = CoordinateSpace.screen(containing: NSEvent.mouseLocation) {
            freezeForCapture()
            delegate?.overlayDidPickFullscreen(screen: screen)
        }
    }

    func overlayFlagsChanged(_ event: NSEvent) {
        shiftDown = event.modifierFlags.contains(.shift)
        recomputeSelectionIfNeeded()
    }

    private func recomputeSelectionIfNeeded() {
        guard !dimOnly, isDragging, !spaceDown, let start = dragStart else { return }
        let endpoint = clampedSelectionPoint(NSEvent.mouseLocation)
        selectionRect = SelectionGeometry.rect(from: start, to: endpoint, square: shiftDown)
        selectionRect = clampedSelection(selectionRect ?? .zero)
        applyVisuals()
    }

    private func refreshHover(at point: CGPoint, preserveCycle: Bool) {
        guard mode.allowsWindowClick, !isDragging else {
            highlighted = nil
            overlapIDs = []
            overlapIndex = 0
            return
        }
        let stack = catalog.windows(at: point)
        let ids = stack.map(\.windowID)
        if preserveCycle, ids == overlapIDs, overlapIndex < stack.count {
            highlighted = stack[overlapIndex]
        } else {
            overlapIDs = ids
            overlapIndex = 0
            highlighted = stack.first
        }
    }

    private func cycleHighlightedWindow(reverse: Bool) {
        guard !dimOnly, !isFrozen, mode.allowsWindowClick, !isDragging else { return }
        let stack = catalog.windows(at: NSEvent.mouseLocation)
        guard stack.count > 1 else { return }
        overlapIDs = stack.map(\.windowID)
        if let highlighted,
           let current = stack.firstIndex(where: { $0.windowID == highlighted.windowID }) {
            overlapIndex = current
        }
        overlapIndex = WindowHitTesting.cycledIndex(current: overlapIndex, count: stack.count, reverse: reverse)
        highlighted = stack[overlapIndex]
        applyVisuals()
    }

    private func persistLastSelection(_ selection: RegionSelection) {
        AppSettings.shared.lastSelection = LastSelection(
            rect: selection.rect,
            displayID: selection.displayID
        )
    }

    private func setSelectionDisplay(for point: CGPoint) {
        guard let screen = CoordinateSpace.screen(containing: point) else {
            selectionDisplayID = nil
            selectionDisplayFrame = nil
            return
        }
        selectionDisplayID = screen.displayID
        selectionDisplayFrame = screen.frame
    }

    private func clampedSelectionPoint(_ point: CGPoint) -> CGPoint {
        guard let frame = selectionDisplayFrame else { return point }
        return CGPoint(
            x: RectMath.clamped(point.x, lower: frame.minX, upper: frame.maxX),
            y: RectMath.clamped(point.y, lower: frame.minY, upper: frame.maxY)
        )
    }

    private func clampedSelection(_ rect: CGRect) -> CGRect {
        guard let frame = selectionDisplayFrame else { return rect }
        return RectMath.clampedRect(rect, in: frame)
    }

    private func showHint(_ text: String) {
        hint = text
        applyVisuals()
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.hint = nil
            self.applyVisuals()
        }
    }

    private func applyVisuals() {
        let visual = OverlayVisualState(
            highlightedWindow: isDragging ? nil : highlighted,
            selectionRect: selectionRect,
            dimOnly: dimOnly,
            holeIsWindow: !isDragging && selectionRect == nil && highlighted != nil
        )
        let mouseScreen = CoordinateSpace.screen(containing: NSEvent.mouseLocation)
        for screen in NSScreen.screens {
            guard let window = overlayWindows[screen.displayID] else { continue }
            guard let view = window.contentView as? SelectionOverlayView else { continue }
            view.visual = visual
            updateHUD(on: screen, window: window, mouseScreen: mouseScreen)
        }
    }

    private func updateHUD(on screen: NSScreen, window: OverlayWindow, mouseScreen: NSScreen?) {
        guard let hud = hudViews[ObjectIdentifier(window)], let view = window.contentView else { return }
        let targetRect: CGRect?
        let text: String
        if let hint, screen == mouseScreen ?? screen {
            targetRect = CGRect(x: screen.frame.midX - 1, y: screen.frame.midY - 1, width: 2, height: 2)
            text = hint
        } else if let rect = selectionRect, rect.width > 2, rect.height > 2 {
            targetRect = rect
            text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        } else if let highlighted, screen.frame.intersects(highlighted.frame) {
            targetRect = highlighted.frame
            text = highlighted.title.isEmpty ? String(localized: "窗口") : String(highlighted.title.prefix(40))
        } else if let idle = OverlayModeHint.caption(
            for: mode,
            toggleKey: AppSettings.shared.areaWindowToggleHotkey.localizedDisplayString
        ), !isDragging {
            if screen != mouseScreen {
                hud.isHidden = true
                return
            }
            targetRect = CGRect(
                x: screen.visibleFrame.midX - 1,
                y: screen.visibleFrame.minY + 110,
                width: 2,
                height: 2
            )
            text = idle
        } else {
            hud.isHidden = true
            return
        }
        guard let targetRect, screen.frame.intersects(targetRect) else {
            hud.isHidden = true
            return
        }
        hud.isHidden = false
        hud.text = text
        if hud.frame.size != hud.intrinsicContentSize {
            hud.invalidateIntrinsicContentSize()
            hud.frame.size = hud.intrinsicContentSize
        }
        let inWindow = window.convertFromScreen(targetRect)
        let inView = view.convert(inWindow, from: nil)
        let visInView = view.convert(window.convertFromScreen(screen.visibleFrame), from: nil)
        let container = visInView.isNull || visInView.isEmpty ? view.bounds : visInView
        hud.frame = OverlayChromeLayout.hudFrame(
            size: hud.frame.size,
            around: inView,
            in: container
        )
    }

    private func showOverlays(interactive: Bool, snapshot: CaptureSnapshot? = nil) {
        let screens = NSScreen.screens
        let liveIDs = Set(screens.map(\.displayID))
        for id in overlayWindows.keys where !liveIDs.contains(id) {
            if let window = overlayWindows.removeValue(forKey: id) {
                tearDown(window)
            }
            if let bar = modeBarWindows.removeValue(forKey: id) {
                tearDown(bar)
            }
        }

        for screen in screens {
            let window = overlayWindow(for: screen)
            window.setFrame(screen.frame, display: false)
            if let view = window.contentView {
                view.setFrameSize(screen.frame.size)
                if let view = view as? SelectionOverlayView {
                    let image = snapshot?.displays[screen.displayID].map {
                        NSImage(cgImage: $0.image, size: screen.frame.size)
                    }
                    view.backgroundImage = image
                }
            }
            window.ignoresMouseEvents = !interactive
            window.orderFront(nil)
            if interactive {
                showModeBar(on: screen)
            } else {
                modeBarWindows[screen.displayID]?.orderOut(nil)
            }
        }

        if interactive, let mouseScreen = CoordinateSpace.screen(containing: NSEvent.mouseLocation) {
            let window = overlayWindows[mouseScreen.displayID]
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(window?.contentView)
        }
    }

    private func destroyOverlays() {
        let overlays = Array(overlayWindows.values)
        overlayWindows.removeAll()
        overlays.forEach(tearDown)
        let bars = Array(modeBarWindows.values)
        modeBarWindows.removeAll()
        bars.forEach(tearDown)
    }

    private func overlayWindow(for screen: NSScreen) -> OverlayWindow {
        if let existing = overlayWindows[screen.displayID] {
            return existing
        }
        let window = makeOverlayWindow(for: screen)
        overlayWindows[screen.displayID] = window
        return window
    }

    private func makeOverlayWindow(for screen: NSScreen) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.setFrame(screen.frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isRestorable = false
        window.level = CaptureWindowLevels.overlay
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Programmatic windows are ARC-owned. `isReleasedWhenClosed = true` extra-releases
        // on close and SIGSEGVs in the next NSApp autorelease drain (OverlayWindow).
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.animationBehavior = .none

        let view = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.delegate = self
        window.contentView = view

        let hud = CaptureHUDView(frame: .zero)
        hud.isHidden = true
        view.addSubview(hud)
        hudViews[ObjectIdentifier(window)] = hud

        return window
    }

    private func showModeBar(on screen: NSScreen) {
        if let bar = modeBarWindows[screen.displayID] {
            positionModeBar(bar, on: screen)
            bar.orderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: modeBarRoot())
        hosting.appearance = NSAppearance(named: .vibrantDark)
        hosting.frame = NSRect(origin: .zero, size: Self.modeBarSize)
        let bar = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        bar.isOpaque = false
        bar.backgroundColor = .clear
        bar.hasShadow = true
        bar.acceptsMouseMovedEvents = true
        bar.isRestorable = false
        bar.level = CaptureWindowLevels.modeBar
        bar.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        bar.isReleasedWhenClosed = false
        bar.sharingType = .none
        bar.animationBehavior = .none
        bar.contentView = hosting
        positionModeBar(bar, on: screen)
        bar.orderFront(nil)
        modeBarWindows[screen.displayID] = bar
    }

    private func modeBarRoot() -> CaptureModeBar {
        CaptureModeBar(
            state: modeState,
            onSelect: { [weak self] selected in
                self?.applyMode(selected)
            }
        )
    }

    private func positionModeBar(_ bar: NSWindow, on screen: NSScreen) {
        let origin = CGPoint(
            x: screen.visibleFrame.midX - Self.modeBarSize.width / 2,
            y: screen.visibleFrame.minY + 16
        )
        bar.setFrameOrigin(origin)
    }

    private static let modeBarSize = NSSize(width: 268, height: 86)

    private func applyMode(_ newMode: CaptureMode) {
        mode = newMode
        highlighted = nil
        selectionRect = nil
        selectionDisplayID = nil
        selectionDisplayFrame = nil
        clickedWindow = nil
        overlapIDs = []
        overlapIndex = 0
        hint = nil
        refreshHover(at: NSEvent.mouseLocation, preserveCycle: false)
        applyVisuals()
    }

    private func hideModeBars() {
        modeBarWindows.values.forEach { $0.orderOut(nil) }
    }

    private func restoreModeBarsIfNeeded() {
        guard !dimOnly, !isFrozen else { return }
        for screen in NSScreen.screens {
            guard let bar = modeBarWindows[screen.displayID] else { continue }
            positionModeBar(bar, on: screen)
            bar.orderFront(nil)
        }
    }

    private func hideHUDs() {
        hudViews.values.forEach { $0.isHidden = true }
    }

    private func tearDown(_ window: NSWindow) {
        hudViews.removeValue(forKey: ObjectIdentifier(window))
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    private func startCatalogRefresh() {
        stopCatalogRefresh()
        refreshTask = Task { [weak self] in
            await self?.refreshShareableOnce()
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !self.dimOnly, !self.isFrozen, !self.isDragging else { continue }
                await self.refreshWindowSnapshot()
                ticks += 1
                if ticks % 4 == 0 {
                    await self.refreshShareableOnce()
                }
            }
        }
    }

    private func requestWindowRefreshForMouseMovement() {
        mouseRefreshTask?.cancel()
        mouseRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.refreshWindowSnapshot()
        }
    }

    private func refreshWindowSnapshot() async {
        guard !dimOnly, !isFrozen, !isDragging else { return }
        windowSnapshotRevision += 1
        let revision = windowSnapshotRevision
        let primaryHeight = CoordinateSpace.primaryDisplayHeight
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let snapshot = await Task.detached(priority: .userInitiated) {
            WindowSnapshotBuilder.build(primaryDisplayHeight: primaryHeight, ourPID: ourPID)
        }.value
        guard !Task.isCancelled,
              revision == windowSnapshotRevision,
              !dimOnly,
              !isFrozen,
              !isDragging
        else { return }

        let previous = catalog.windows
        catalog.applyWindowsSnapshot(snapshot)
        guard previous != snapshot else { return }
        if mode.allowsWindowClick {
            refreshHover(at: NSEvent.mouseLocation, preserveCycle: true)
        }
        applyVisuals()
    }

    private func refreshShareableOnce() async {
        guard !dimOnly, !isFrozen else { return }
        try? await catalog.refresh()
        guard !Task.isCancelled, !dimOnly, !isFrozen else { return }
        if mode.allowsWindowClick, !isDragging {
            refreshHover(at: NSEvent.mouseLocation, preserveCycle: true)
        }
        applyVisuals()
    }

    private func stopCatalogRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        mouseRefreshTask?.cancel()
        mouseRefreshTask = nil
        windowSnapshotRevision += 1
    }

    private func handleScreenParametersChanged() {
        guard !overlayWindows.isEmpty, !isFrozen else { return }

        if isSnapshotBacked {
            delegate?.overlayDidInvalidateDisplayConfiguration()
            return
        }

        if let selectionRect,
           let selectionDisplayID,
           let screen = NSScreen.screens.first(where: { $0.displayID == selectionDisplayID }) {
            selectionDisplayFrame = screen.frame
            let clamped = RectMath.clampedRect(selectionRect, in: screen.frame)
            if clamped != selectionRect {
                self.selectionRect = clamped
                persistLastSelection(RegionSelection(rect: clamped, displayID: selectionDisplayID))
            }
        } else if selectionRect != nil {
            self.selectionRect = nil
            selectionDisplayID = nil
            selectionDisplayFrame = nil
        }

        showOverlays(interactive: !dimOnly)
        if !dimOnly, !isDragging {
            refreshHover(at: NSEvent.mouseLocation, preserveCycle: true)
        }
        applyVisuals()
    }
}
