import SwiftUI

@MainActor
final class OverlayModeState: ObservableObject {
    @Published private(set) var mode: CaptureMode

    init(mode: CaptureMode = .area) {
        self.mode = mode.interactiveMode
    }

    func select(_ mode: CaptureMode) {
        self.mode = mode.interactiveMode
    }
}

struct CaptureModeBar: View {
    @ObservedObject var state: OverlayModeState
    var onSelect: (CaptureMode) -> Void
    var availableWidth: CGFloat = 300

    @ObservedObject private var settings = AppSettings.shared

    private var mode: CaptureMode { state.mode }

    private var caption: String? {
        OverlayModeHint.caption(for: mode, toggleKey: settings.areaWindowToggleHotkey.localizedDisplayString)
    }

    var body: some View {
        VStack(spacing: 6) {
            Picker(
                String(localized: "截图模式"),
                selection: Binding(
                    get: { mode },
                    set: { onSelect($0) }
                )
            ) {
                ForEach(CaptureMode.selectableModes) { value in
                    Label(value.title, systemImage: systemImage(for: value))
                        .tag(value)
                        .help(value.title)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(height: 32)
            .accessibilityLabel(String(localized: "截图模式"))

            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: availableWidth)
        .background {
            HUDChrome.PanelBackground(
                cornerRadius: InterfaceMetrics.panelRadius,
                treatment: settings.useLightweightCaptureHUD ? .lightweight : .standard
            )
        }
        .environment(\.colorScheme, .dark)
    }

    private func systemImage(for mode: CaptureMode) -> String {
        switch mode {
        case .area:
            return "rectangle.dashed"
        case .window:
            return "macwindow"
        case .fullscreen:
            return "rectangle"
        case .allInOne:
            return "rectangle"
        }
    }
}
