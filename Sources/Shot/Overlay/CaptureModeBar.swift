import SwiftUI

@MainActor
final class OverlayModeState: ObservableObject {
    @Published var mode: CaptureMode = .allInOne
}

struct CaptureModeBar: View {
    @ObservedObject var state: OverlayModeState
    var onSelect: (CaptureMode) -> Void

    @ObservedObject private var settings = AppSettings.shared

    private var mode: CaptureMode { state.mode }

    private var caption: String? {
        OverlayModeHint.caption(for: mode, toggleKey: settings.areaWindowToggleHotkey.localizedDisplayString)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                modeButton(.area, systemImage: "rectangle.dashed")
                modeButton(.window, systemImage: "macwindow")
                modeButton(.fullscreen, systemImage: "rectangle")
            }
            .padding(4)
            .background(groupSelection, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            HUDChrome.PanelBackground(cornerRadius: 14)
        }
        .environment(\.colorScheme, .dark)
    }

    private var groupSelection: Color {
        mode == .allInOne ? Color.accentColor.opacity(0.22) : Color.clear
    }

    private func modeButton(_ value: CaptureMode, systemImage: String) -> some View {
        Button {
            onSelect(value)
        } label: {
            label(value.title, systemImage: systemImage)
        }
        .buttonStyle(HUDChrome.IconButtonStyle(isSelected: isSelected(value), cornerRadius: 8))
        .accessibilityLabel(value.title)
        .accessibilityValue(isSelected(value)
            ? String(localized: "已选中")
            : String(localized: "未选中"))
        .help(value.title)
        .accessibilityAddTraits(isSelected(value) ? [.isSelected] : [])
    }

    private func label(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.primary)
        .frame(width: 58, height: 44)
        .contentShape(Rectangle())
        .help(title)
    }

    private func isSelected(_ value: CaptureMode) -> Bool {
        if mode == .allInOne {
            return false
        }
        return mode == value
    }
}
