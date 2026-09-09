import AppKit
import SwiftUI

@MainActor
enum HUDChrome {
    enum PanelTreatment: Equatable {
        case standard
        case lightweight
    }

    static var reduceTransparency: Bool {
        InterfacePreferences.shared.reduceTransparency
    }

    static var solidFill: Color { Color(nsColor: .windowBackgroundColor) }

    static var liftFill: Color { Color.primary.opacity(0.04) }

    static var hairline: Color { Color.primary.opacity(InterfacePreferences.shared.increaseContrast ? 0.65 : 0.16) }

    static var hoverFill: Color { Color.primary.opacity(0.12) }

    static var pressFill: Color { Color.primary.opacity(0.18) }

    static var selectedFill: Color { Color.accentColor.opacity(0.82) }

    struct PanelBackground: View {
        @ObservedObject private var preferences = InterfacePreferences.shared
        var cornerRadius: CGFloat
        var treatment: PanelTreatment = .standard

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                if preferences.reduceTransparency {
                    shape.fill(HUDChrome.solidFill)
                } else {
                    VisualEffect(
                        cornerRadius: cornerRadius,
                        opacity: treatment == .lightweight ? 0.88 : 1
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    shape.fill(treatment == .lightweight ? .clear : HUDChrome.liftFill)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    treatment == .lightweight && !preferences.increaseContrast
                        ? Color.white.opacity(0.16)
                        : HUDChrome.hairline,
                    lineWidth: 1
                )
            }
        }
    }

    struct IconButtonStyle: ButtonStyle {
        var isSelected = false
        var cornerRadius: CGFloat = 6
        var tintsLabel = true

        func makeBody(configuration: Configuration) -> some View {
            IconButtonBody(
                configuration: configuration,
                isSelected: isSelected,
                cornerRadius: cornerRadius,
                tintsLabel: tintsLabel
            )
        }
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    var isSelected: Bool
    var cornerRadius: CGFloat
    var tintsLabel: Bool
    @State private var isHovered = false
    @ObservedObject private var preferences = InterfacePreferences.shared
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: InterfaceMetrics.buttonRadius, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor : .clear, lineWidth: 2)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovering in
                isHovered = isEnabled && hovering
            }
            .animation(preferences.animation(0.12), value: isHovered)
            .animation(preferences.animation(0.12), value: isSelected)
            .animation(preferences.animation(0.08), value: configuration.isPressed)
    }

    @ViewBuilder
    private var label: some View {
        if tintsLabel {
            configuration.label.foregroundStyle(Color.primary)
        } else {
            configuration.label
        }
    }

    private var fill: Color {
        if isSelected {
            if configuration.isPressed { return Color.accentColor }
            if isHovered { return Color.accentColor.opacity(0.92) }
            return HUDChrome.selectedFill
        }
        if !isEnabled {
            return .clear
        }
        if configuration.isPressed {
            return HUDChrome.pressFill
        }
        if isHovered {
            return HUDChrome.hoverFill
        }
        return .clear
    }
}

private struct VisualEffect: NSViewRepresentable {
    var cornerRadius: CGFloat
    var opacity: CGFloat = 1
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = HUDMaterialView()
        view.blendingMode = blendingMode
        view.state = .active
        view.alphaValue = opacity
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        apply(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        apply(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSVisualEffectView, context: Context) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    private func apply(_ view: NSVisualEffectView) {
        view.material = .hudWindow
        view.blendingMode = blendingMode
        view.state = .active
        view.alphaValue = opacity
        view.appearance = NSAppearance(named: .vibrantDark)
        (view as? HUDMaterialView)?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
    }
}
