import AppKit
import ShotKit
import SwiftUI

@MainActor
extension OverlayController {
    func showOverlays(interactive: Bool, snapshot: CaptureSnapshot? = nil) {
        let screens = NSScreen.screens
        let liveIDs = Set(screens.map(\.displayID))
        for id in overlayWindows.keys where !liveIDs.contains(id) {
            if let window = overlayWindows.removeValue(forKey: id) {
                tearDown(window)
            }
            if let bar = modeBarWindows.removeValue(forKey: id) {
                tearDown(bar)
            }
            if let bar = actionBarWindows.removeValue(forKey: id) {
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

    func destroyOverlays() {
        let overlays = Array(overlayWindows.values)
        overlayWindows.removeAll()
        overlays.forEach(tearDown)
        let bars = Array(modeBarWindows.values)
        modeBarWindows.removeAll()
        bars.forEach(tearDown)
        let actions = Array(actionBarWindows.values)
        actionBarWindows.removeAll()
        actions.forEach(tearDown)
    }

    func overlayWindow(for screen: NSScreen) -> OverlayWindow {
        if let existing = overlayWindows[screen.displayID] {
            return existing
        }
        let window = makeOverlayWindow(for: screen)
        overlayWindows[screen.displayID] = window
        return window
    }

    func makeOverlayWindow(for screen: NSScreen) -> OverlayWindow {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
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
        window.becomesKeyOnlyIfNeeded = false
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

    func showModeBar(on screen: NSScreen) {
        if let bar = modeBarWindows[screen.displayID] {
            positionModeBar(bar, on: screen)
            bar.orderFront(nil)
            if bar.frame.contains(NSEvent.mouseLocation) {
                NSCursor.arrow.set()
            }
            return
        }
        let hosting = CaptureChromeHostingView(rootView: modeBarRoot())
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
        if bar.frame.contains(NSEvent.mouseLocation) {
            NSCursor.arrow.set()
        }
        modeBarWindows[screen.displayID] = bar
    }

    func modeBarRoot() -> CaptureModeBar {
        CaptureModeBar(
            state: modeState,
            onSelect: { [weak self] selected in
                self?.applyMode(selected)
            }
        )
    }

    func positionModeBar(_ bar: NSWindow, on screen: NSScreen) {
        guard let hosting = bar.contentView as? CaptureChromeHostingView<CaptureModeBar> else { return }
        let width = min(300, max(1, screen.visibleFrame.width - 32))
        if hosting.rootView.availableWidth != width { hosting.rootView.availableWidth = width }
        let size = NSSize(width: width, height: max(64, ceil(hosting.fittingSize.height)))
        bar.setFrame(InterfaceLayout.bottomFrame(size: size, in: screen.visibleFrame), display: true)
    }

    static let modeBarSize = NSSize(width: 268, height: 86)

}
