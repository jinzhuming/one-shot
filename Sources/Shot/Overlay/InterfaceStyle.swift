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
    static let bodySize: CGFloat = 13
    static let panelInset: CGFloat = 12
    static let compactPanelRadius: CGFloat = 6
    static let settingsSize = CGSize(width: 720, height: 560)
    static let settingsMinimumSize = CGSize(width: 640, height: 480)
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
    enum Surface {
        case darkHUD, adaptive, windowHeader
    }

    var surface: Surface = .darkHUD { didSet { updateSurface() } }
    var cornerRadius: CGFloat = InterfaceMetrics.panelRadius { didSet { updateSurface() } }
    private let solidBackground = NSView()
    private var preferencesObserver: AnyCancellable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        solidBackground.wantsLayer = true
        solidBackground.setAccessibilityElement(false)
        addSubview(solidBackground)
        setAccessibilityElement(false)
        preferencesObserver = InterfacePreferences.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSurface() }
        updateSurface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        solidBackground.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateSurface() {
        appearance = surface == .darkHUD ? NSAppearance(named: .vibrantDark) : nil
        material = surface == .darkHUD ? .hudWindow : (surface == .windowHeader ? .headerView : .popover)
        state = surface == .windowHeader ? .followsWindowActiveState : .active
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        applyAccessibility(reduceTransparency: InterfacePreferences.shared.reduceTransparency,
                           increaseContrast: InterfacePreferences.shared.increaseContrast)
    }

    func applyAccessibility(reduceTransparency: Bool, increaseContrast: Bool) {
        solidBackground.isHidden = !reduceTransparency
        layer?.borderWidth = increaseContrast ? 2 : 0
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            solidBackground.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}
