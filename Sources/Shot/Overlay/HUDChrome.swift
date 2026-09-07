import AppKit
import SwiftUI

enum HUDChrome {
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    static var solidFill: Color { Color(white: 0.18).opacity(0.97) }

    static var liftFill: Color { Color.white.opacity(0.10) }

    static var hairline: Color { Color.white.opacity(0.26) }

    static var hoverFill: Color { Color.white.opacity(0.14) }

    static var pressFill: Color { Color.white.opacity(0.22) }

    static var selectedFill: Color { Color.accentColor.opacity(0.82) }

    struct PanelBackground: View {
        var cornerRadius: CGFloat

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                if HUDChrome.reduceTransparency {
                    shape.fill(HUDChrome.solidFill)
                } else {
                    VisualEffect(cornerRadius: cornerRadius)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    shape.fill(HUDChrome.liftFill)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(HUDChrome.hairline, lineWidth: 1)
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
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.38)
            .onHover { hovering in
                isHovered = isEnabled && hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isSelected)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = blendingMode
        view.state = .active
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
        view.appearance = NSAppearance(named: .vibrantDark)
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
    }
}
