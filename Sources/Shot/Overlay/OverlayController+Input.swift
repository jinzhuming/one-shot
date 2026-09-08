import AppKit
import ShotKit
import SwiftUI

@MainActor
extension OverlayController {
    func overlayMouseMoved(_ pointInScreen: CGPoint) {
        guard !dimOnly, !isFrozen else { return }
        updateModeBarVisibility(for: CoordinateSpace.screen(containing: pointInScreen))
        updateResizeCursor(at: pointInScreen)
        if !isDragging {
            if mode.allowsWindowClick, !isSelectionConfirmed {
                requestWindowRefreshForMouseMovement()
                scheduleHoverRefresh(at: pointInScreen)
            } else {
                cancelHoverRefresh()
            }
            if mode == .area || isSelectionConfirmed {
                scheduleVisuals()
            }
        } else {
            scheduleVisuals()
        }
    }

    func overlayMouseDown(_ pointInScreen: CGPoint) {
        guard !dimOnly, !isFrozen else { return }
        if copyColorFromHUD(at: pointInScreen) {
            return
        }
        cancelHoverRefresh()
        activeHandle = nil
        if isSelectionConfirmed, let rect = selectionRect {
            if let handle = SelectionHandleGeometry.handle(at: pointInScreen, in: rect) {
                activeHandle = handle
                isDragging = true
                isMovingSelection = false
                dragStart = pointInScreen
                hideModeBars()
                hideActionBars()
                applyVisuals()
                return
            }
            if SelectionHandleGeometry.contains(pointInScreen, in: rect) || spaceDown {
                isMovingSelection = true
                isDragging = true
                moveAnchor = pointInScreen
                dragStart = pointInScreen
                hideModeBars()
                hideActionBars()
                applyVisuals()
                return
            }
            clearConfirmedSelection()
            applyVisuals()
            return
        }
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

        if let handle = activeHandle, let rect = selectionRect {
            selectionRect = SelectionHandleGeometry.resize(
                rect,
                handle: handle,
                to: clampedSelectionPoint(pointInScreen),
                square: shiftDown,
                inside: selectionDisplayFrame ?? .null
            )
            isDragging = true
            highlighted = nil
            clickedWindow = nil
            scheduleVisuals()
            return
        }

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

        if isSelectionConfirmed, isMovingSelection, let rect = selectionRect, let anchor = moveAnchor {
            let boundedPoint = clampedSelectionPoint(pointInScreen)
            let translated = SelectionGeometry.translated(
                rect,
                by: CGSize(width: boundedPoint.x - anchor.x, height: boundedPoint.y - anchor.y)
            )
            selectionRect = clampedSelection(translated)
            moveAnchor = boundedPoint
            isDragging = true
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
        hideActionBars()
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
        // A confirm-clear click returns from mouseDown without `dragStart`.
        // Ignore that mouse-up so it cannot switch to window mode or capture.
        guard dragStart != nil else { return }
        if isDragging {
            overlayMouseDragged(pointInScreen)
        }
        visualUpdateTask?.cancel()
        visualUpdateTask = nil
        applyVisuals()
        let finishedHandleResize = activeHandle != nil
        defer {
            resetDragState()
        }

        if finishedHandleResize || (isSelectionConfirmed && selectionRect != nil) {
            if let rect = selectionRect, let displayID = selectionDisplayID {
                if rect.width > OverlayModeSwitch.dragThreshold,
                   rect.height > OverlayModeSwitch.dragThreshold {
                    persistLastSelection(RegionSelection(rect: rect, displayID: displayID))
                }
                resetDragState()
                enterConfirmedSelection()
            }
            return
        }

        if isDragging, let rect = selectionRect,
           rect.width > OverlayModeSwitch.dragThreshold,
           rect.height > OverlayModeSwitch.dragThreshold {
            guard let displayID = selectionDisplayID else {
                showHint(String(localized: "找不到选区所在的显示器。"))
                return
            }
            persistLastSelection(RegionSelection(rect: rect, displayID: displayID))
            resetDragState()
            enterConfirmedSelection()
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
        if copyColorIfNeeded(for: event) {
            return
        }
        if submitConfirmedSelectionIfNeeded(for: event) {
            return
        }
        if nudgeConfirmedSelectionIfNeeded(for: event) {
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
        if event.keyCode == 36, isSelectionConfirmed {
            submitConfirmedSelection(.default)
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

    func recomputeSelectionIfNeeded() {
        guard !dimOnly, isDragging, !spaceDown, activeHandle == nil, let start = dragStart else { return }
        let endpoint = clampedSelectionPoint(NSEvent.mouseLocation)
        selectionRect = SelectionGeometry.rect(from: start, to: endpoint, square: shiftDown)
        selectionRect = clampedSelection(selectionRect ?? .zero)
        scheduleVisuals()
    }

    func refreshHover(at point: CGPoint, preserveCycle: Bool) {
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

    func cycleHighlightedWindow(reverse: Bool) {
        guard !dimOnly, !isFrozen, mode.allowsWindowClick, !isDragging, !isSelectionConfirmed else { return }
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

    func persistLastSelection(_ selection: RegionSelection) {
        AppSettings.shared.lastSelection = selection
    }

    func resetDragState() {
        dragStart = nil
        isDragging = false
        isMovingSelection = false
        moveAnchor = nil
        clickedWindow = nil
        activeHandle = nil
    }

    func enterConfirmedSelection() {
        if confirmStyle == .screenshot {
            // Screenshot selection no longer needs a post-capture action bar.
            // Submit directly to the editor as soon as the region is complete.
            isSelectionConfirmed = true
            submitConfirmedSelection(.annotate)
            return
        }
        isSelectionConfirmed = true
        highlighted = nil
        hideModeBars()
        showActionBars()
        applyVisuals()
    }

    func clearConfirmedSelection() {
        isSelectionConfirmed = false
        activeHandle = nil
        selectionRect = nil
        selectionDisplayID = nil
        selectionDisplayFrame = nil
        hideActionBars()
        restoreModeBarsIfNeeded()
    }

    func submitConfirmedSelection(_ action: OverlayRegionAction) {
        guard isSelectionConfirmed,
              let rect = selectionRect,
              let displayID = selectionDisplayID else { return }
        let selection = RegionSelection(rect: rect, displayID: displayID)
        persistLastSelection(selection)
        freezeForCapture()
        delegate?.overlayDidSubmitRegion(selection: selection, action: action)
    }

    @discardableResult
    func submitConfirmedSelectionIfNeeded(for event: NSEvent) -> Bool {
        guard isSelectionConfirmed, event.modifierFlags.contains(.command) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == "c" {
            submitConfirmedSelection(.copy)
            return true
        }
        if key == "s" {
            submitConfirmedSelection(.save)
            return true
        }
        return false
    }

    @discardableResult
    func nudgeConfirmedSelectionIfNeeded(for event: NSEvent) -> Bool {
        guard isSelectionConfirmed, !isDragging, let rect = selectionRect else { return false }
        let shift = event.modifierFlags.contains(.shift) || shiftDown
        guard let delta = SelectionHandleGeometry.arrowDelta(keyCode: event.keyCode, shift: shift) else {
            return false
        }
        selectionRect = SelectionHandleGeometry.nudge(rect, delta: delta, inside: selectionDisplayFrame ?? rect)
        if let rect = selectionRect, let displayID = selectionDisplayID {
            persistLastSelection(RegionSelection(rect: rect, displayID: displayID))
        }
        showActionBars()
        applyVisuals()
        return true
    }

    @discardableResult
    func copyColorIfNeeded(for event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.option),
              event.charactersIgnoringModifiers?.lowercased() == "c",
              let sampledHex else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sampledHex, forType: .string)
        SaveLocationPresenter.showCopied(message: String(localized: "已复制颜色 \(sampledHex)"))
        return true
    }

    func copyColorFromHUD(at pointInScreen: CGPoint) -> Bool {
        guard let sampledHex, sampledHex.hasPrefix("#") else { return false }
        for (identifier, hud) in hudViews {
            guard !hud.isHidden, !hud.text.isEmpty, let swatch = hud.colorSwatchFrame else { continue }
            guard let window = overlayWindows.values.first(where: { ObjectIdentifier($0) == identifier }) else {
                continue
            }
            let swatchRect = window.convertToScreen(hud.convert(swatch, to: nil))
            guard swatchRect.contains(pointInScreen) else { continue }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(sampledHex, forType: .string)
            SaveLocationPresenter.showCopied(message: String(localized: "已复制颜色 \(sampledHex)"))
            return true
        }
        return false
    }

    func sampleColor(from view: SelectionOverlayView, at point: CGPoint) {
        guard let image = view.backgroundImage,
              var proposed = Optional(CGRect(origin: .zero, size: image.size)),
              let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let sample = PixelSampling.sample(image: cgImage, at: point, imageBounds: view.bounds)
        else {
            sampledHex = nil
            return
        }
        sampledHex = PixelSampling.hex(red: sample.red, green: sample.green, blue: sample.blue)
    }

    func updateResizeCursor(at point: CGPoint) {
        guard isSelectionConfirmed, let rect = selectionRect else {
            NSCursor.crosshair.set()
            return
        }
        if let handle = SelectionHandleGeometry.handle(at: point, in: rect) {
            cursor(for: handle).set()
        } else if SelectionHandleGeometry.contains(point, in: rect) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    func cursor(for handle: OverlaySelectionHandle) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch handle {
        case .top: position = .top
        case .bottom: position = .bottom
        case .left: position = .left
        case .right: position = .right
        case .topLeft: position = .topLeft
        case .topRight: position = .topRight
        case .bottomLeft: position = .bottomLeft
        case .bottomRight: position = .bottomRight
        }
        return NSCursor.frameResize(position: position, directions: [.inward, .outward])
    }

    static let startActionBarSize = NSSize(width: 120, height: 44)

}
