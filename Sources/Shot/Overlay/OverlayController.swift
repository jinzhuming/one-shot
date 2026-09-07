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
        set { modeState.select(newValue) }
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
    private var hoverTask: Task<Void, Never>?
    private var windowSnapshotRevision = 0
    private var isSnapshotBacked = false
    private var modeBarEnabled = true
    private var hint: String?
    private var hintTask: Task<Void, Never>?
    private var screenParametersObserver: NSObjectProtocol?
    private var modeShortcutMonitor: Any?
    private let preparationHUD = CapturePreparationHUD()
    private let scrollingHUD = ScrollCaptureHUD()
    private var preparationHUDTask: Task<Void, Never>?
    private var visualUpdateTask: Task<Void, Never>?

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
        if let modeShortcutMonitor {
            NSEvent.removeMonitor(modeShortcutMonitor)
        }
        visualUpdateTask?.cancel()
    }

    func present(
        mode: CaptureMode,
        snapshot: CaptureSnapshot? = nil,
        allowsModeSwitch: Bool = true,
        hintOverride: String? = nil
    ) {
        hidePreparationHUD()
        stopCatalogRefresh()
        cancelHoverRefresh()
        installModeShortcutMonitor()
        hintTask?.cancel()
        hintTask = nil
        self.mode = mode
        modeBarEnabled = allowsModeSwitch
        if !allowsModeSwitch {
            removeModeShortcutMonitor()
        }
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
        hint = hintOverride
        if let snapshot {
            catalog.applyWindowsSnapshot(snapshot.windows)
        } else {
            catalog.refreshWindowsFromCG()
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
        showOverlays(interactive: true, snapshot: snapshot)
        if snapshot == nil, mode.allowsWindowClick {
            startCatalogRefresh()
        }
        refreshHover(at: NSEvent.mouseLocation, preserveCycle: false)
        applyVisuals()
    }

    func beginScrolling(on screen: NSScreen, onFinish: @escaping @MainActor () -> Void) {
        dismiss()
        scrollingHUD.show(on: screen, onFinish: onFinish)
    }

    func updateScrollingCapture(_ progress: ScrollCaptureProgress) {
        scrollingHUD.update(progress: progress)
    }

    func clearSelectionHole() {
        selectionRect = nil
        highlighted = nil
        applyVisuals()
    }

    func showPreparationHUD() {
        hidePreparationHUD()
        preparationHUDTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            self.preparationHUD.show()
        }
    }

    func enterDimOnly() {
        hidePreparationHUD()
        removeModeShortcutMonitor()
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
        removeModeShortcutMonitor()
        hideModeBars()
        stopCatalogRefresh()
    }

    func suspendForModal() {
        hidePreparationHUD()
        removeModeShortcutMonitor()
        overlayWindows.values.forEach { $0.orderOut(nil) }
        modeBarWindows.values.forEach { $0.orderOut(nil) }
    }

    func resumeAfterModal() {
        for screen in NSScreen.screens {
            overlayWindows[screen.displayID]?.orderFront(nil)
        }
        updateModeBarVisibility(for: CoordinateSpace.screen(containing: NSEvent.mouseLocation))
    }

    func presentDimBackdrop() {
        hidePreparationHUD()
        removeModeShortcutMonitor()
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
        hidePreparationHUD()
        scrollingHUD.hide()
        stopCatalogRefresh()
        cancelHoverRefresh()
        removeModeShortcutMonitor()
        visualUpdateTask?.cancel()
        visualUpdateTask = nil
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
        modeBarEnabled = true
        spaceDown = false
        hint = nil
        NSCursor.arrow.set()
    }

    func overlayMouseMoved(_ pointInScreen: CGPoint) {
        guard !dimOnly, !isFrozen else { return }
        updateModeBarVisibility(for: CoordinateSpace.screen(containing: pointInScreen))
        if !isDragging {
            if mode.allowsWindowClick {
                requestWindowRefreshForMouseMovement()
                scheduleHoverRefresh(at: pointInScreen)
            } else {
                cancelHoverRefresh()
            }
            if mode == .area {
                scheduleVisuals()
            }
        } else {
            scheduleVisuals()
        }
    }

    func overlayMouseDown(_ pointInScreen: CGPoint) {
        guard !dimOnly, !isFrozen else { return }
        cancelHoverRefresh()
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
            cancelHoverRefresh()
            highlighted = nil
            clickedWindow = nil
            scheduleVisuals()
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
        cancelHoverRefresh()
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
        scheduleVisuals()
    }

    func overlayMouseUp(_ pointInScreen: CGPoint) {
        guard !dimOnly, !isFrozen else { return }
        if isDragging {
            // Mouse-up is the authoritative final coordinate even when the
            // event stream skipped the last drag event.
            overlayMouseDragged(pointInScreen)
        }
        visualUpdateTask?.cancel()
        visualUpdateTask = nil
        applyVisuals()
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
        if toggleModeIfNeeded(for: event) {
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
        scheduleVisuals()
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
        AppSettings.shared.lastSelection = selection
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
        hintTask = Task { @MainActor [weak self] in
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
            updateMagnifier(on: screen, window: window, view: view, mouseScreen: mouseScreen)
            updateHUD(on: screen, window: window, mouseScreen: mouseScreen)
        }
    }

    private func scheduleVisuals() {
        guard visualUpdateTask == nil else { return }
        visualUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, !Task.isCancelled else { return }
            self.visualUpdateTask = nil
            self.applyVisuals()
        }
    }

    private func updateMagnifier(
        on screen: NSScreen,
        window: OverlayWindow,
        view: SelectionOverlayView,
        mouseScreen: NSScreen?
    ) {
        guard !dimOnly,
              !isFrozen,
              (mode == .area || isDragging),
              let mouseScreen,
              mouseScreen.displayID == screen.displayID,
              view.backgroundImage != nil
        else {
            view.magnifierFrame = nil
            view.magnifierSourceRect = nil
            view.magnifierCursor = nil
            return
        }

        let cursor = NSEvent.mouseLocation
        let globalFrame: CGRect
        if let selectionRect, selectionRect.width > 2, selectionRect.height > 2 {
            globalFrame = MagnifierLayout.frame(
                nextTo: selectionRect,
                visibleFrame: screen.visibleFrame,
                chromeInset: OverlayFocusStyle.magnifierBezelInset
            )
        } else {
            globalFrame = MagnifierLayout.frame(
                cursor: cursor,
                visibleFrame: screen.visibleFrame,
                chromeInset: OverlayFocusStyle.magnifierBezelInset
            )
        }
        guard !globalFrame.isEmpty else {
            view.magnifierFrame = nil
            view.magnifierSourceRect = nil
            view.magnifierCursor = nil
            return
        }
        let inWindow = window.convertFromScreen(globalFrame)
        let outerFrameInView = view.convert(inWindow, from: nil)
        let contentFrameInView = MagnifierLayout.contentFrame(
            for: outerFrameInView,
            chromeInset: OverlayFocusStyle.magnifierBezelInset
        )
        let cursorInWindow = window.convertFromScreen(NSRect(origin: cursor, size: .zero)).origin
        let cursorInView = view.convert(cursorInWindow, from: nil)
        let source = MagnifierLayout.sourceRect(
            cursor: cursorInView,
            imageBounds: view.bounds,
            destinationSize: contentFrameInView.size
        )
        view.magnifierFrame = outerFrameInView
        view.magnifierSourceRect = source
        view.magnifierCursor = cursorInView
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
            if interactive, modeBarEnabled {
                showModeBar(on: screen)
            } else {
                modeBarWindows[screen.displayID]?.orderOut(nil)
            }
        }

        if interactive {
            let mouseScreen = CoordinateSpace.screen(containing: NSEvent.mouseLocation)
            updateModeBarVisibility(for: mouseScreen)
            if let mouseScreen {
                let window = overlayWindows[mouseScreen.displayID]
                window?.makeKeyAndOrderFront(nil)
                window?.makeFirstResponder(window?.contentView)
            }
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
        window.onRequestCancel = { [weak self] in
            self?.delegate?.overlayDidCancel()
        }
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
        let bar = CaptureModeBarWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
        cancelHoverRefresh()
        mode = newMode
        if mode.allowsWindowClick {
            startCatalogRefresh()
        } else {
            stopCatalogRefresh()
        }
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
        restoreOverlayFocus()
    }

    private func restoreOverlayFocus() {
        guard let screen = CoordinateSpace.screen(containing: NSEvent.mouseLocation),
              let window = overlayWindows[screen.displayID],
              let contentView = window.contentView else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
        updateModeBarVisibility(for: screen)
    }

    private func installModeShortcutMonitor() {
        removeModeShortcutMonitor()
        modeShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.toggleModeIfNeeded(for: event) ? nil : event
        }
    }

    private func removeModeShortcutMonitor() {
        if let modeShortcutMonitor {
            NSEvent.removeMonitor(modeShortcutMonitor)
            self.modeShortcutMonitor = nil
        }
    }

    @discardableResult
    private func toggleModeIfNeeded(for event: NSEvent) -> Bool {
        guard !event.isARepeat,
              !isDragging,
              AppSettings.shared.areaWindowToggleHotkey.matches(event),
              let next = OverlayModeSwitch.toggled(from: mode.overlayKind) else {
            return false
        }
        switch next {
        case .area:
            applyMode(.area)
        case .window:
            applyMode(.window)
        case .other:
            return false
        }
        return true
    }

    private func hideModeBars() {
        modeBarWindows.values.forEach { $0.orderOut(nil) }
    }

    private func restoreModeBarsIfNeeded() {
        guard !dimOnly, !isFrozen else { return }
        updateModeBarVisibility(for: CoordinateSpace.screen(containing: NSEvent.mouseLocation))
    }

    private func updateModeBarVisibility(for mouseScreen: NSScreen?) {
        guard !dimOnly, !isFrozen, !isDragging else { return }
        let activeDisplayID = mouseScreen?.displayID
        for screen in NSScreen.screens {
            guard let bar = modeBarWindows[screen.displayID] else { continue }
            if screen.displayID == activeDisplayID {
                positionModeBar(bar, on: screen)
                bar.orderFront(nil)
            } else {
                bar.orderOut(nil)
            }
        }
    }

    private func hideHUDs() {
        hudViews.values.forEach { $0.isHidden = true }
    }

    private func tearDown(_ window: NSWindow) {
        hudViews.removeValue(forKey: ObjectIdentifier(window))
        if let overlay = window as? OverlayWindow {
            overlay.onRequestCancel = nil
        }
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    private func startCatalogRefresh() {
        stopCatalogRefresh()
        refreshTask = Task { @MainActor [weak self] in
            await self?.refreshShareableOnce()
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled else { return }
                guard !self.dimOnly, !self.isFrozen, !self.isDragging else { continue }
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
        mouseRefreshTask = Task { @MainActor [weak self] in
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
        let allowedWindowIDs = catalog.shareableWindowIDs
        let snapshot = await Task.detached(priority: .userInitiated) {
            WindowSnapshotBuilder.build(
                primaryDisplayHeight: primaryHeight,
                ourPID: ourPID,
                allowedWindowIDs: allowedWindowIDs
            )
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
            scheduleHoverRefresh(at: NSEvent.mouseLocation)
        }
        applyVisuals()
    }

    private func refreshShareableOnce() async {
        guard !dimOnly, !isFrozen else { return }
        try? await catalog.refresh()
        guard !Task.isCancelled, !dimOnly, !isFrozen else { return }
        if mode.allowsWindowClick, !isDragging {
            scheduleHoverRefresh(at: NSEvent.mouseLocation)
        }
        applyVisuals()
    }

    private func stopCatalogRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        mouseRefreshTask?.cancel()
        mouseRefreshTask = nil
        cancelHoverRefresh()
        windowSnapshotRevision += 1
    }

    private func scheduleHoverRefresh(at point: CGPoint) {
        guard !dimOnly, !isFrozen, !isDragging, mode.allowsWindowClick else { return }
        hoverTask?.cancel()
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, !Task.isCancelled, !self.dimOnly, !self.isFrozen, !self.isDragging else { return }
            let previousID = self.highlighted?.windowID
            self.refreshHover(at: point, preserveCycle: true)
            guard self.highlighted?.windowID != previousID else { return }
            self.applyVisuals()
        }
    }

    private func cancelHoverRefresh() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    private func hidePreparationHUD() {
        preparationHUDTask?.cancel()
        preparationHUDTask = nil
        preparationHUD.hide()
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
            cancelHoverRefresh()
            refreshHover(at: NSEvent.mouseLocation, preserveCycle: true)
        }
        applyVisuals()
    }
}
