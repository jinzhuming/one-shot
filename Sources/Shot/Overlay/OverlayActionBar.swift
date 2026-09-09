import SwiftUI
import ShotKit

struct OverlayActionBar: View {
    var onAction: (OverlayRegionAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            actionButton(
                title: String(localized: "开始"),
                systemImage: "play.fill",
                action: .start
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            HUDChrome.PanelBackground(cornerRadius: InterfaceMetrics.panelRadius)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "选区操作"))
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: OverlayRegionAction
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
                .frame(height: InterfaceMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(HUDChrome.ProminentButtonStyle())
        .help(help(for: action))
        .accessibilityLabel(title)
        .accessibilityHint(help(for: action))
    }

    private func help(for action: OverlayRegionAction) -> String {
        switch action {
        case .start:
            return String(localized: "开始（Return）")
        case .default:
            return String(localized: "使用默认操作（Return）")
        default:
            return ""
        }
    }
}
