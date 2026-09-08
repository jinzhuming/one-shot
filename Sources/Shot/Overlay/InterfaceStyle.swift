import AppKit
import Combine
import SwiftUI

enum InterfaceMetrics {
    static let controlSize: CGFloat = 28
    static let symbolSize: CGFloat = 14
    static let buttonRadius: CGFloat = 6
    static let panelRadius: CGFloat = 12
    static let spacing: CGFloat = 8
    static let captionSize: CGFloat = 11
}

@MainActor
final class InterfacePreferences: ObservableObject {
    static let shared = InterfacePreferences()
    @Published private(set) var reduceTransparency = false
    @Published private(set) var increaseContrast = false
    @Published private(set) var reduceMotion = false
    private var observer: AnyCancellable?

    private init() {
        refresh()
        observer = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let workspace = NSWorkspace.shared
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
    }

    func animation(_ duration: Double) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}

/// Shared AppKit HUD material. System accessibility changes apply to windows
/// that are already visible, including transient progress and preview panels.
final class HUDMaterialView: NSVisualEffectView {
    private var preferencesObserver: AnyCancellable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .vibrantDark)
        material = .hudWindow
        state = .active
        preferencesObserver = InterfacePreferences.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if InterfacePreferences.shared.reduceTransparency {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        if InterfacePreferences.shared.increaseContrast {
            NSColor.separatorColor.setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: layer?.cornerRadius ?? 0, yRadius: layer?.cornerRadius ?? 0)
            outline.lineWidth = 2
            outline.stroke()
        }
    }
}
