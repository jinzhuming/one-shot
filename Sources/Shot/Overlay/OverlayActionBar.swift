import SwiftUI
import ShotKit

struct OverlayActionBar: View {
    var style: OverlayConfirmStyle
    var defaultAction: OverlayRegionAction
    var onAction: (OverlayRegionAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if style == .start {
                actionButton(
                    title: String(localized: "开始"),
                    systemImage: "play.fill",
                    action: .start,
                    prominent: true
                )
            } else {
                actionButton(
                    title: String(localized: "标注"),
                    systemImage: "pencil.tip",
                    action: .annotate,
                    prominent: defaultAction == .annotate
                )
                actionButton(
                    title: String(localized: "复制"),
                    systemImage: "doc.on.clipboard",
                    action: .copy,
                    prominent: defaultAction == .copy
                )
                actionButton(
                    title: String(localized: "保存"),
                    systemImage: "square.and.arrow.down",
                    action: .save,
                    prominent: defaultAction == .save
                )
                actionButton(
                    title: String(localized: "钉图"),
                    systemImage: "pin",
                    action: .pin,
                    prominent: false
                )
                actionButton(
                    title: String(localized: "识别文字"),
                    systemImage: "text.viewfinder",
                    action: .ocr,
                    prominent: false
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            HUDChrome.PanelBackground(cornerRadius: 12)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "选区操作"))
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: OverlayRegionAction,
        prominent: Bool
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? Color.accentColor : Color.white.opacity(0.16))
        .help(help(for: action))
        .accessibilityLabel(title)
        .accessibilityHint(help(for: action))
    }

    private func help(for action: OverlayRegionAction) -> String {
        switch action {
        case .annotate:
            return defaultAction == .annotate
                ? String(localized: "打开标注（Return）")
                : String(localized: "打开标注")
        case .copy:
            return defaultAction == .copy
                ? String(localized: "复制到剪贴板（Return 或 ⌘C）")
                : String(localized: "复制到剪贴板（⌘C）")
        case .save:
            return defaultAction == .save
                ? String(localized: "保存到文件（Return 或 ⌘S）")
                : String(localized: "保存到文件（⌘S）")
        case .pin:
            return String(localized: "将截图钉在桌面上")
        case .ocr:
            return String(localized: "识别选区中的文字并复制")
        case .start:
            return String(localized: "开始（Return）")
        case .default:
            return String(localized: "使用默认操作（Return）")
        }
    }
}
