import AppKit
import ShotKit
import SwiftUI

@MainActor
protocol OverlayControllerDelegate: AnyObject {
    func overlayDidCancel()
    func overlayDidPickWindow(id: CGWindowID)
    func overlayDidSubmitRegion(selection: RegionSelection, action: OverlayRegionAction)
    func overlayDidPickFullscreen(screen: NSScreen)
    func overlayDidInvalidateDisplayConfiguration()
}

@MainActor
final class OverlayController: NSObject, SelectionOverlayDelegate {
    weak var delegate: OverlayControllerDelegate?

    var overlayWindows: [CGDirectDisplayID: OverlayWindow] = [:]
    var hudViews: [ObjectIdentifier: CaptureHUDView] = [:]
    var modeBarWindows: [CGDirectDisplayID: NSWindow] = [:]
    var actionBarWindows: [CGDirectDisplayID: NSWindow] = [:]
    let modeState = OverlayModeState()
    var confirmStyle: OverlayConfirmStyle = .screenshot
    var isSelectionConfirmed = false
    var activeHandle: OverlaySelectionHandle?
    var sampledHex: String?

    var mode: CaptureMode {
        get { modeState.mode }
        set { modeState.select(newValue) }
    }
    let catalog = WindowCatalog.shared
    var highlighted: CapturableWindow?
    var overlapIDs: [CGWindowID] = []
    var overlapIndex = 0
    var selectionRect: CGRect?
    var selectionDisplayID: CGDirectDisplayID?
    var selectionDisplayFrame: CGRect?
    var dragStart: CGPoint?
    var clickedWindow: CapturableWindow?
    var isDragging = false
    var isMovingSelection = false
    var moveAnchor: CGPoint?
    var spaceDown = false
    var shiftDown = false
    var dimOnly = false
    var isFrozen = false
    lazy var snapshotRefresher = WindowSnapshotRefresher(
        catalog: catalog,
        mayRefresh: { [weak self] in
            guard let self else { return false }
            return !self.dimOnly && !self.isFrozen && !self.isDragging && !self.isSelectionConfirmed
        },
        onChange: { [weak self] in
            guard let self else { return }
            if self.mode.allowsWindowClick { self.scheduleHoverRefresh(at: NSEvent.mouseLocation) }
            self.applyVisuals()
        }
    )
    var hoverTask: Task<Void, Never>?
    var isSnapshotBacked = false
    var modeBarEnabled = true
    var hint: String?
    var hintTask: Task<Void, Never>?
    var screenParametersObserver: NSObjectProtocol?
    var modeShortcutMonitor: Any?
    let preparationHUD = CapturePreparationHUD()
    let scrollingHUD = ScrollCaptureHUD()
    var preparationHUDTask: Task<Void, Never>?
    var visualUpdateTask: Task<Void, Never>?

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
        hintOverride: String? = nil,
        confirmStyle: OverlayConfirmStyle = .screenshot
    ) {
        hidePreparationHUD()
        stopCatalogRefresh()
        cancelHoverRefresh()
        installModeShortcutMonitor()
        hintTask?.cancel()
        hintTask = nil
        self.mode = mode
        self.confirmStyle = confirmStyle
        modeBarEnabled = allowsModeSwitch
        if !allowsModeSwitch {
            removeModeShortcutMonitor()
        }
        isSnapshotBacked = snapshot != nil
        dimOnly = false
        isFrozen = false
        isSelectionConfirmed = false
        activeHandle = nil
        sampledHex = nil
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
        hideActionBars()
        hideHUDs()
        applyVisuals()
        stopCatalogRefresh()
    }

    func freezeForCapture() {
        isFrozen = true
        isSelectionConfirmed = false
        activeHandle = nil
        removeModeShortcutMonitor()
        hideModeBars()
        hideActionBars()
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
        isSelectionConfirmed = false
        activeHandle = nil
        sampledHex = nil
        hint = nil
        hideActionBars()
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
        isSelectionConfirmed = false
        activeHandle = nil
        sampledHex = nil
        confirmStyle = .screenshot
        modeBarEnabled = true
        spaceDown = false
        hint = nil
        NSCursor.arrow.set()
    }

    func showActionBars() {
        guard isSelectionConfirmed, let selectionRect, let selectionDisplayID else { return }
        for screen in NSScreen.screens {
            if screen.displayID == selectionDisplayID {
                showActionBar(on: screen, around: selectionRect)
            } else {
                actionBarWindows[screen.displayID]?.orderOut(nil)
            }
        }
    }

    func hideActionBars() {
        actionBarWindows.values.forEach { $0.orderOut(nil) }
    }

    func showActionBar(on screen: NSScreen, around rect: CGRect) {
        let minimumSize = Self.startActionBarSize
        let hosting = CaptureChromeHostingView(rootView: OverlayActionBar(
            onAction: { [weak self] action in
                self?.submitConfirmedSelection(action == .start ? .start : action)
            }
        ))
        hosting.appearance = NSAppearance(named: .vibrantDark)
        let fittedSize = hosting.fittingSize
        let size = NSSize(
            width: max(minimumSize.width, ceil(fittedSize.width)),
            height: max(minimumSize.height, ceil(fittedSize.height))
        )
        let bar: NSWindow
        if let existing = actionBarWindows[screen.displayID] {
            bar = existing
            bar.contentView = hosting
        } else {
            let window = CaptureModeBarWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.acceptsMouseMovedEvents = true
            window.isRestorable = false
            window.level = CaptureWindowLevels.modeBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.sharingType = .none
            window.animationBehavior = .none
            actionBarWindows[screen.displayID] = window
            bar = window
        }
        hosting.frame = NSRect(origin: .zero, size: size)
        bar.contentView = hosting
        bar.setContentSize(size)
        // The selection overlay owns the crosshair while choosing a region;
        // the confirmed-state controls use the normal macOS arrow cursor.
        NSCursor.arrow.set()
        let visible = screen.visibleFrame
        let hudSize = liveHUDSize(on: screen) ?? CGSize(width: 220, height: 24)
        let hud = OverlayChromeLayout.hudFrame(size: hudSize, around: rect, in: visible)
        let frame = OverlayChromeLayout.actionBarFrame(
            size: size,
            around: rect,
            avoiding: hud,
            in: visible
        )
        bar.setFrame(frame, display: true)
        bar.orderFront(nil)
        if frame.contains(NSEvent.mouseLocation) {
            NSCursor.arrow.set()
        } else {
            updateResizeCursor(at: NSEvent.mouseLocation)
        }
    }

    func liveHUDSize(on screen: NSScreen) -> CGSize? {
        guard let window = overlayWindows[screen.displayID] else { return nil }
        guard let hud = hudViews[ObjectIdentifier(window)], !hud.isHidden else { return nil }
        let size = hud.intrinsicContentSize
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    func setSelectionDisplay(for point: CGPoint) {
        guard let screen = CoordinateSpace.screen(containing: point) else {
            selectionDisplayID = nil
            selectionDisplayFrame = nil
            return
        }
        selectionDisplayID = screen.displayID
        selectionDisplayFrame = screen.frame
    }

    func clampedSelectionPoint(_ point: CGPoint) -> CGPoint {
        guard let frame = selectionDisplayFrame else { return point }
        return CGPoint(
            x: RectMath.clamped(point.x, lower: frame.minX, upper: frame.maxX),
            y: RectMath.clamped(point.y, lower: frame.minY, upper: frame.maxY)
        )
    }

    func clampedSelection(_ rect: CGRect) -> CGRect {
        guard let frame = selectionDisplayFrame else { return rect }
        return RectMath.clampedRect(rect, in: frame)
    }

    func showHint(_ text: String) {
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

    func applyVisuals() {
        let visual = OverlayVisualState(
            highlightedWindow: isDragging || isSelectionConfirmed ? nil : highlighted,
            selectionRect: selectionRect,
            dimOnly: dimOnly,
            holeIsWindow: !isDragging && !isSelectionConfirmed && selectionRect == nil && highlighted != nil,
            showsHandles: isSelectionConfirmed && !isDragging
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

    func scheduleVisuals() {
        guard visualUpdateTask == nil else { return }
        visualUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, !Task.isCancelled else { return }
            self.visualUpdateTask = nil
            self.applyVisuals()
        }
    }

    func updateMagnifier(
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
        // The lens follows the pointer throughout the gesture. Anchoring it
        // to the completed selection makes it jump as soon as a drag starts,
        // which breaks the precision feedback loop used by the crosshair.
        let globalFrame = MagnifierLayout.frame(
            cursor: cursor,
            visibleFrame: screen.visibleFrame,
            chromeInset: OverlayFocusStyle.magnifierBezelInset
        )
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
        sampleColor(from: view, at: cursorInView)
    }

    func updateHUD(on screen: NSScreen, window: OverlayWindow, mouseScreen: NSScreen?) {
        guard let hud = hudViews[ObjectIdentifier(window)], let view = window.contentView else { return }
        let targetRect: CGRect?
        let text: String
        if let hint, screen == mouseScreen ?? screen {
            targetRect = CGRect(x: screen.frame.midX - 1, y: screen.frame.midY - 1, width: 2, height: 2)
            text = hint
        } else if let rect = selectionRect, rect.width > 2, rect.height > 2 {
            targetRect = rect
            let sizeText = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
            if let mouseScreen, mouseScreen.displayID == screen.displayID {
                let local = PixelSampling.displayPoint(global: NSEvent.mouseLocation, screenFrame: screen.frame)
                var parts = [
                    sizeText,
                    "\(Int(local.x.rounded())), \(Int(local.y.rounded()))"
                ]
                if let sampledHex {
                    parts.append(sampledHex)
                }
                text = parts.joined(separator: " · ")
            } else {
                text = sizeText
            }
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
        hud.sampledHex = selectionRect == nil ? nil : sampledHex
        if hud.frame.size != hud.intrinsicContentSize {
            hud.invalidateIntrinsicContentSize()
            hud.frame.size = hud.intrinsicContentSize
        }
        let inWindow = window.convertFromScreen(targetRect)
        let inView = view.convert(inWindow, from: nil)
        let visInView = view.convert(window.convertFromScreen(screen.visibleFrame), from: nil)
        let container = visInView.isNull || visInView.isEmpty ? view.bounds : visInView
        var avoiding: CGRect?
        if isSelectionConfirmed, let bar = actionBarWindows[screen.displayID], bar.isVisible {
            avoiding = view.convert(window.convertFromScreen(bar.frame), from: nil)
        }
        hud.frame = OverlayChromeLayout.hudFrame(
            size: hud.frame.size,
            around: inView,
            in: container,
            avoiding: avoiding
        )
    }

    func applyMode(_ newMode: CaptureMode) {
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
        isSelectionConfirmed = false
        activeHandle = nil
        sampledHex = nil
        clickedWindow = nil
        overlapIDs = []
        overlapIndex = 0
        hint = nil
        hideActionBars()
        refreshHover(at: NSEvent.mouseLocation, preserveCycle: false)
        applyVisuals()
        restoreOverlayFocus()
    }

    func restoreOverlayFocus() {
        guard let screen = CoordinateSpace.screen(containing: NSEvent.mouseLocation),
              let window = overlayWindows[screen.displayID],
              let contentView = window.contentView else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(contentView)
        updateModeBarVisibility(for: screen)
    }

    func installModeShortcutMonitor() {
        removeModeShortcutMonitor()
        modeShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.toggleModeIfNeeded(for: event) {
                return nil
            }
            if self.isSelectionConfirmed,
               event.modifierFlags.contains(.command)
                || event.modifierFlags.contains(.option)
                || event.keyCode == 36
                || SelectionHandleGeometry.arrowDelta(keyCode: event.keyCode, shift: false) != nil {
                self.overlayKeyDown(event)
                return nil
            }
            return event
        }
    }

    func removeModeShortcutMonitor() {
        if let modeShortcutMonitor {
            NSEvent.removeMonitor(modeShortcutMonitor)
            self.modeShortcutMonitor = nil
        }
    }

    @discardableResult
    func toggleModeIfNeeded(for event: NSEvent) -> Bool {
        guard !event.isARepeat,
              !isDragging,
              !isSelectionConfirmed,
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

    func hideModeBars() {
        modeBarWindows.values.forEach { $0.orderOut(nil) }
    }

    func restoreModeBarsIfNeeded() {
        guard !dimOnly, !isFrozen else { return }
        updateModeBarVisibility(for: CoordinateSpace.screen(containing: NSEvent.mouseLocation))
    }

    func updateModeBarVisibility(for mouseScreen: NSScreen?) {
        guard !dimOnly, !isFrozen, !isDragging, !isSelectionConfirmed else {
            hideModeBars()
            return
        }
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

    func hideHUDs() {
        hudViews.values.forEach { $0.isHidden = true }
    }

    func tearDown(_ window: NSWindow) {
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

    func startCatalogRefresh() { snapshotRefresher.start() }
    func requestWindowRefreshForMouseMovement() { snapshotRefresher.mouseMoved() }
    func stopCatalogRefresh() {
        snapshotRefresher.stop()
        cancelHoverRefresh()
    }

    func scheduleHoverRefresh(at point: CGPoint) {
        guard !dimOnly, !isFrozen, !isDragging, !isSelectionConfirmed, mode.allowsWindowClick else { return }
        hoverTask?.cancel()
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, !Task.isCancelled, !self.dimOnly, !self.isFrozen, !self.isDragging, !self.isSelectionConfirmed else { return }
            let previousID = self.highlighted?.windowID
            self.refreshHover(at: point, preserveCycle: true)
            guard self.highlighted?.windowID != previousID else { return }
            self.applyVisuals()
        }
    }

    func cancelHoverRefresh() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    func hidePreparationHUD() {
        preparationHUDTask?.cancel()
        preparationHUDTask = nil
        preparationHUD.hide()
    }

    func handleScreenParametersChanged() {
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
        if !dimOnly, !isDragging, !isSelectionConfirmed {
            cancelHoverRefresh()
            refreshHover(at: NSEvent.mouseLocation, preserveCycle: true)
        }
        if isSelectionConfirmed {
            showActionBars()
        }
        applyVisuals()
    }
}
