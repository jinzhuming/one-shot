import AppKit
import ShotKit

@MainActor
final class RecordingClickHighlightController {
    private var window: NSWindow?
    private var view: ClickHighlightView?
    private var monitors: [Any] = []

    var windowID: CGWindowID? {
        window.map { CGWindowID($0.windowNumber) }
    }

    func present(in frame: CGRect) {
        dismiss()
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = CaptureWindowLevels.overlay
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        // Read-only sharing lets ScreenCaptureKit include the ripples without
        // exposing a writable window surface.
        window.sharingType = .readOnly
        let highlight = ClickHighlightView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = highlight
        window.orderFrontRegardless()
        self.window = window
        self.view = highlight

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.addRipple(at: point)
            }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.addRipple(at: point)
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    func dismiss() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        view?.stop()
        window?.orderOut(nil)
        window?.contentView = nil
        window?.close()
        window = nil
        view = nil
    }

    private func addRipple(at screenPoint: CGPoint) {
        guard let window else { return }
        let local = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
        view?.addRipple(at: local)
    }
}

private final class ClickHighlightView: NSView {
    private var ripples: [Ripple] = []
    private var timer: Timer?

    private struct Ripple {
        var center: CGPoint
        var start: TimeInterval
    }

    override var isOpaque: Bool { false }

    func stop() {
        timer?.invalidate()
        timer = nil
        ripples.removeAll()
    }

    func addRipple(at point: CGPoint) {
        ripples.append(Ripple(center: point, start: CACurrentMediaTime()))
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.needsDisplay = true
                }
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let now = CACurrentMediaTime()
        ripples.removeAll { now - $0.start > 0.45 }
        if ripples.isEmpty {
            timer?.invalidate()
            timer = nil
        }
        let accent = NSColor.controlAccentColor
        for ripple in ripples {
            let progress = min(1, (now - ripple.start) / 0.45)
            let radius = 8 + CGFloat(progress) * 28
            let path = NSBezierPath(ovalIn: CGRect(
                x: ripple.center.x - radius,
                y: ripple.center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            accent.withAlphaComponent(0.45 * (1 - progress)).setStroke()
            path.lineWidth = 3
            path.stroke()
        }
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }
}
