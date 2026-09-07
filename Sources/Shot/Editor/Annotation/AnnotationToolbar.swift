import AppKit
import Combine
import ShotKit
import SwiftUI

enum AnnotationToolbarPresentation: Equatable {
    case floatingHUD
    case windowAdaptive

    var isFloating: Bool { self == .floatingHUD }
}

enum AnnotationChromeMetrics {
    static let controlSize: CGFloat = 28
    static let symbolSize: CGFloat = 14
    static let buttonCornerRadius: CGFloat = 6
    static let windowPrimaryRowHeight: CGFloat = 44
    static let windowDetailRowHeight: CGFloat = 36
    static let windowSeparatorHeight: CGFloat = 1
    static let windowToolbarHeight = windowPrimaryRowHeight
        + windowSeparatorHeight
        + windowDetailRowHeight
}

struct AnnotationToolbar: View {
    @ObservedObject var session: EditSession
    var onCopy: () -> Void
    var onSave: () -> Void
    var onClose: () -> Void
    var presentation: AnnotationToolbarPresentation = .floatingHUD

    @State private var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    var body: some View {
        Group {
            switch presentation {
            case .floatingHUD:
                floatingToolbar
            case .windowAdaptive:
                windowToolbar
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            )
        ) { _ in
            reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
    }

    private var floatingToolbar: some View {
        VStack(spacing: 5) {
            floatingPrimaryToolbar
            detailToolbar
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.22), radius: 1)
        .shadow(
            color: .black.opacity(0.42),
            radius: EditorLayout.toolbarShadowRadius,
            y: EditorLayout.toolbarShadowOffsetY
        )
    }

    private var windowToolbar: some View {
        VStack(spacing: 0) {
            windowPrimaryToolbar
                .frame(height: AnnotationChromeMetrics.windowPrimaryRowHeight)
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: AnnotationChromeMetrics.windowSeparatorHeight)
                .accessibilityHidden(true)
            windowDetailToolbar
                .frame(height: AnnotationChromeMetrics.windowDetailRowHeight)
        }
        .frame(
            minWidth: EditorLayout.minContentWidth,
            idealWidth: EditorLayout.minContentWidth,
            maxWidth: .infinity
        )
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                WindowHeaderVisualEffect()
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: AnnotationChromeMetrics.windowSeparatorHeight)
                .accessibilityHidden(true)
        }
    }

    private var floatingPrimaryToolbar: some View {
        HStack(spacing: 8) {
            ForEach(Array(AnnotationToolID.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { divider }
                toolCluster(group)
            }
            divider
            floatingStyleGroup
            divider
            historyGroup
            divider
            floatingActionGroup
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background {
            HUDChrome.PanelBackground(cornerRadius: 12)
        }
    }

    private var windowPrimaryToolbar: some View {
        ZStack {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(Array(AnnotationToolID.groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 {
                            Color.clear.frame(width: 4)
                        }
                        toolCluster(group)
                    }
                }
                Spacer(minLength: 12)
                exportActionGroup
            }
            historyGroup
        }
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "标注工具"))
    }

    private var detailToolbar: some View {
        HStack(spacing: 10) {
            toolIdentity
            divider
            detailControls
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .background {
            HUDChrome.PanelBackground(cornerRadius: 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "工具详细设置"))
    }

    private var windowDetailToolbar: some View {
        HStack(spacing: 8) {
            toolIdentity
            divider
            detailControls
                .layoutPriority(1)
            Spacer(minLength: 8)
            if session.selectedTool == .select, session.hasSelection {
                selectionActionGroup
            }
        }
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "工具详细设置"))
    }

    private var toolIdentity: some View {
        HStack(spacing: 4) {
            Image(systemName: session.selectedTool.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(session.selectedTool.title)
                .font(.system(size: 11, weight: .semibold))
                .frame(minWidth: 42, alignment: .leading)
        }
    }

    @ViewBuilder
    private var detailControls: some View {
        switch session.selectedTool {
        case .select:
            selectionDetailControls
        case .arrow, .rect, .ellipse, .line:
            HStack(spacing: detailSpacing) {
                windowColorControls
                detailSlider(
                    label: String(localized: "线宽（pt）"),
                    value: $session.lineWidth,
                    range: 1...24,
                    step: 1,
                    valueText: numberText(session.lineWidth)
                )
            }
        case .pen:
            HStack(spacing: detailSpacing) {
                windowColorControls
                detailSlider(
                    label: String(localized: "画笔粗细（pt）"),
                    value: $session.lineWidth,
                    range: 1...24,
                    step: 1,
                    valueText: numberText(session.lineWidth)
                )
            }
        case .highlighter:
            HStack(spacing: detailSpacing) {
                windowColorControls
                detailSlider(
                    label: String(localized: "荧光笔粗细（pt）"),
                    value: $session.lineWidth,
                    range: 1...32,
                    step: 1,
                    valueText: numberText(session.lineWidth)
                )
                detailSlider(
                    label: String(localized: "透明度"),
                    value: $session.highlighterOpacity,
                    range: 0.1...1,
                    step: 0.05,
                    valueText: percentageText(session.highlighterOpacity)
                )
            }
        case .text:
            HStack(spacing: detailSpacing) {
                windowColorControls
                detailSlider(
                    label: String(localized: "文字大小（pt）"),
                    value: $session.lineWidth,
                    range: 1...12,
                    step: 1,
                    valueText: numberText(AnnotationMath.fontSize(lineWidth: CGFloat(session.lineWidth)))
                )
            }
        case .counter:
            HStack(spacing: detailSpacing) {
                windowColorControls
                detailSlider(
                    label: String(localized: "序号大小"),
                    value: $session.lineWidth,
                    range: 1...12,
                    step: 1,
                    valueText: numberText(max(10, session.lineWidth * 10))
                )
            }
        case .mosaic:
            detailSlider(
                label: String(localized: "颗粒大小（pt）"),
                value: $session.mosaicBlockSize,
                range: 2...32,
                step: 1,
                valueText: numberText(session.mosaicBlockSize)
            )
        case .spotlight:
            detailSlider(
                label: String(localized: "遮罩不透明度"),
                value: $session.spotlightOpacity,
                range: 0.1...0.9,
                step: 0.05,
                valueText: percentageText(session.spotlightOpacity)
            )
        }
    }

    @ViewBuilder
    private var selectionDetailControls: some View {
        if let selected = session.document.selectedObject {
            HStack(spacing: detailSpacing) {
                Text(String(localized: "已选择"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                switch selected.element {
                case .mosaic(_, _):
                    detailSlider(
                        label: String(localized: "颗粒大小（pt）"),
                        value: $session.mosaicBlockSize,
                        range: 2...32,
                        step: 1,
                        valueText: numberText(session.mosaicBlockSize)
                    )
                case .spotlight(_, _):
                    detailSlider(
                        label: String(localized: "遮罩不透明度"),
                        value: $session.spotlightOpacity,
                        range: 0.1...0.9,
                        step: 0.05,
                        valueText: percentageText(session.spotlightOpacity)
                    )
                case .highlighter(_, _):
                    windowColorControls
                    detailSlider(
                        label: String(localized: "荧光笔粗细（pt）"),
                        value: $session.lineWidth,
                        range: 1...32,
                        step: 1,
                        valueText: numberText(session.lineWidth)
                    )
                    detailSlider(
                        label: String(localized: "透明度"),
                        value: $session.highlighterOpacity,
                        range: 0.1...1,
                        step: 0.05,
                        valueText: percentageText(session.highlighterOpacity)
                    )
                case .text(_, _, _):
                    windowColorControls
                    detailSlider(
                        label: String(localized: "文字大小（pt）"),
                        value: $session.lineWidth,
                        range: 1...12,
                        step: 1,
                        valueText: numberText(AnnotationMath.fontSize(lineWidth: CGFloat(session.lineWidth)))
                    )
                case .counter(_, _, _):
                    windowColorControls
                    detailSlider(
                        label: String(localized: "序号大小"),
                        value: $session.lineWidth,
                        range: 1...12,
                        step: 1,
                        valueText: numberText(max(10, session.lineWidth * 10))
                    )
                case .arrow(_, _, _), .rect(_, _), .ellipse(_, _), .line(_, _, _), .pen(_, _):
                    windowColorControls
                    detailSlider(
                        label: String(localized: "线宽（pt）"),
                        value: $session.lineWidth,
                        range: 1...24,
                        step: 1,
                        valueText: numberText(session.lineWidth)
                    )
                }
            }
        } else {
            Text(String(localized: "点击标注以选择"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var windowColorControls: some View {
        if presentation == .windowAdaptive {
            colorSwatches
        }
    }

    private var detailSpacing: CGFloat {
        presentation.isFloating ? 12 : 8
    }

    private func detailSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        HStack(spacing: presentation.isFloating ? 6 : 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            Slider(value: value, in: range, step: step, onEditingChanged: { editing in
                if editing {
                    session.beginStyleAdjustment()
                } else {
                    session.endStyleAdjustment()
                }
            })
            .frame(width: presentation.isFloating ? 120 : 84)
            .help(label)
            .accessibilityLabel(label)
            .accessibilityValue(valueText)
            Text(valueText)
                .font(.system(size: 11, design: .monospaced))
                .frame(minWidth: presentation.isFloating ? 34 : 30, alignment: .trailing)
                .foregroundStyle(.primary)
        }
    }

    private func numberText(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func percentageText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func toolCluster(_ tools: [AnnotationToolID]) -> some View {
        HStack(spacing: presentation.isFloating ? 2 : 1) {
            ForEach(tools) { tool in
                toolButton(tool)
            }
        }
    }

    private func toolButton(_ tool: AnnotationToolID) -> some View {
        Button {
            session.selectedTool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: AnnotationChromeMetrics.symbolSize, weight: .medium))
                .frame(
                    width: AnnotationChromeMetrics.controlSize,
                    height: AnnotationChromeMetrics.controlSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(AnnotationIconButtonStyle(
            presentation: presentation,
            isSelected: session.selectedTool == tool
        ))
        .help(tool.helpText)
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.helpText)
        .accessibilityAddTraits(session.selectedTool == tool ? [.isSelected] : [])
        .background {
            NativeToolTip(text: tool.helpText)
        }
    }

    private var floatingStyleGroup: some View {
        HStack(spacing: 8) {
            colorSwatches
            strokePresets
        }
    }

    private var colorSwatches: some View {
        HStack(spacing: presentation.isFloating ? 5 : 2) {
            ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                Button {
                    session.color = Color(nsColor: swatch.color)
                } label: {
                    Circle()
                        .fill(Color(nsColor: swatch.color))
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    colorRing(for: swatch.color),
                                    lineWidth: isSelected(swatch.color) ? 2 : 1
                                )
                        }
                        .frame(
                            width: AnnotationChromeMetrics.controlSize,
                            height: AnnotationChromeMetrics.controlSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(AnnotationIconButtonStyle(
                    presentation: presentation,
                    tintsLabel: false
                ))
                .help(swatch.help)
                .accessibilityLabel(swatch.help)
                .accessibilityAddTraits(isSelected(swatch.color) ? [.isSelected] : [])
            }
        }
    }

    private var strokePresets: some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.strokeSizes.enumerated()), id: \.offset) { _, size in
                Button {
                    session.lineWidth = size.width
                } label: {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 1.5)
                        .background(
                            Circle().fill(
                                Color.primary.opacity(session.lineWidth == size.width ? 0.9 : 0.15)
                            )
                        )
                        .frame(width: size.dot, height: size.dot)
                        .frame(
                            width: AnnotationChromeMetrics.controlSize,
                            height: AnnotationChromeMetrics.controlSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(AnnotationIconButtonStyle(
                    presentation: presentation,
                    isSelected: session.lineWidth == size.width
                ))
                .help(size.help)
                .accessibilityLabel(size.help)
                .accessibilityAddTraits(session.lineWidth == size.width ? [.isSelected] : [])
            }
        }
    }

    private var historyGroup: some View {
        HStack(spacing: presentation.isFloating ? 2 : 1) {
            Button {
                session.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: AnnotationChromeMetrics.symbolSize, weight: .medium))
                    .frame(
                        width: AnnotationChromeMetrics.controlSize,
                        height: AnnotationChromeMetrics.controlSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(AnnotationIconButtonStyle(presentation: presentation))
            .disabled(!session.canUndo)
            .help(String(localized: "撤销（⌘Z）"))
            .accessibilityLabel(String(localized: "撤销"))

            Button {
                session.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: AnnotationChromeMetrics.symbolSize, weight: .medium))
                    .frame(
                        width: AnnotationChromeMetrics.controlSize,
                        height: AnnotationChromeMetrics.controlSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(AnnotationIconButtonStyle(presentation: presentation))
            .disabled(!session.canRedo)
            .help(String(localized: "重做（⇧⌘Z）"))
            .accessibilityLabel(String(localized: "重做"))
        }
    }

    private var selectionActionGroup: some View {
        HStack(spacing: 1) {
            duplicateButton
            deleteButton
        }
    }

    private var floatingActionGroup: some View {
        HStack(spacing: 6) {
            duplicateButton
            deleteButton
            exportActionGroup
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(
                        width: AnnotationChromeMetrics.controlSize,
                        height: AnnotationChromeMetrics.controlSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(AnnotationIconButtonStyle(presentation: presentation))
            .help(String(localized: "关闭编辑器（Esc）"))
            .accessibilityLabel(String(localized: "关闭"))
        }
        .controlSize(.small)
    }

    private var exportActionGroup: some View {
        HStack(spacing: presentation.isFloating ? 6 : 4) {
            Button(String(localized: "复制"), action: onCopy)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help(String(localized: "将最终图片复制到剪贴板（⌘C 或 Return）"))
                .accessibilityLabel(String(localized: "复制最终图片"))
                .accessibilityHint(String(localized: "提交未完成的文字标注后复制"))
                .disabled(session.isExporting)
            Button(String(localized: "保存"), action: onSave)
                .buttonStyle(.bordered)
                .help(String(localized: "将最终图片保存到文件（⌘S）"))
                .accessibilityLabel(String(localized: "保存最终图片"))
                .accessibilityHint(String(localized: "提交未完成的文字标注后保存"))
                .disabled(session.isExporting)
        }
        .controlSize(.small)
    }

    private var duplicateButton: some View {
        Button {
            session.duplicateSelection()
        } label: {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: 13, weight: .medium))
                .frame(
                    width: AnnotationChromeMetrics.controlSize,
                    height: AnnotationChromeMetrics.controlSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(AnnotationIconButtonStyle(presentation: presentation))
        .help(String(localized: "复制选中标注（⌘D）"))
        .accessibilityLabel(String(localized: "复制选中标注"))
        .disabled(session.isExporting || !session.hasSelection)
    }

    private var deleteButton: some View {
        Button {
            session.deleteSelection()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .medium))
                .frame(
                    width: AnnotationChromeMetrics.controlSize,
                    height: AnnotationChromeMetrics.controlSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(AnnotationIconButtonStyle(presentation: presentation))
        .help(String(localized: "删除选中标注（Delete）"))
        .accessibilityLabel(String(localized: "删除选中标注"))
        .disabled(session.isExporting || !session.hasSelection)
    }

    private var divider: some View {
        Rectangle()
            .fill(
                presentation.isFloating
                    ? Color.white.opacity(0.28)
                    : Color(nsColor: .separatorColor)
            )
            .frame(width: 1, height: presentation.isFloating ? 18 : 16)
            .accessibilityHidden(true)
    }

    private func isSelected(_ color: NSColor) -> Bool {
        colorDistance(NSColor(session.color), color) < 0.08
    }

    private func colorRing(for color: NSColor) -> Color {
        if isSelected(color) {
            return presentation.isFloating ? .white : .accentColor
        }
        if colorDistance(color, .white) < 0.08 {
            return Color.black.opacity(0.35)
        }
        return presentation.isFloating
            ? Color.white.opacity(0.28)
            : Color(nsColor: .separatorColor)
    }

    private func colorDistance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        guard
            let lhs = a.usingColorSpace(.deviceRGB),
            let rhs = b.usingColorSpace(.deviceRGB)
        else {
            return 1
        }
        let dr = lhs.redComponent - rhs.redComponent
        let dg = lhs.greenComponent - rhs.greenComponent
        let db = lhs.blueComponent - rhs.blueComponent
        return sqrt(dr * dr + dg * dg + db * db)
    }

    private static let swatches: [(color: NSColor, help: String)] = [
        (.systemRed, String(localized: "使用红色")),
        (.systemOrange, String(localized: "使用橙色")),
        (.systemYellow, String(localized: "使用黄色")),
        (.systemGreen, String(localized: "使用绿色")),
        (.systemBlue, String(localized: "使用蓝色")),
        (.white, String(localized: "使用白色")),
        (.black, String(localized: "使用黑色"))
    ]

    private static let strokeSizes: [(width: CGFloat, dot: CGFloat, help: String)] = [
        (AnnotationMath.strokePresets[0], 8, String(localized: "使用细线（2 pt）")),
        (AnnotationMath.strokePresets[1], 12, String(localized: "使用中等线宽（4 pt）")),
        (AnnotationMath.strokePresets[2], 16, String(localized: "使用粗线（8 pt）"))
    ]
}

private struct AnnotationIconButtonStyle: ButtonStyle {
    let presentation: AnnotationToolbarPresentation
    var isSelected = false
    var tintsLabel = true

    func makeBody(configuration: Configuration) -> some View {
        AnnotationIconButtonBody(
            configuration: configuration,
            presentation: presentation,
            isSelected: isSelected,
            tintsLabel: tintsLabel
        )
    }
}

private struct AnnotationIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let presentation: AnnotationToolbarPresentation
    var isSelected: Bool
    var tintsLabel: Bool

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label
            .background(
                fill,
                in: RoundedRectangle(
                    cornerRadius: AnnotationChromeMetrics.buttonCornerRadius,
                    style: .continuous
                )
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: AnnotationChromeMetrics.buttonCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: AnnotationChromeMetrics.buttonCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    isFocused && isEnabled ? Color.accentColor : .clear,
                    lineWidth: 2
                )
                .padding(1)
            }
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
            configuration.label.foregroundStyle(foreground)
        } else {
            configuration.label
        }
    }

    private var foreground: Color {
        if presentation == .windowAdaptive, isSelected {
            return .accentColor
        }
        return .primary
    }

    private var fill: Color {
        if presentation.isFloating {
            if isSelected {
                if configuration.isPressed { return Color.accentColor }
                if isHovered { return Color.accentColor.opacity(0.92) }
                return HUDChrome.selectedFill
            }
            if !isEnabled { return .clear }
            if configuration.isPressed { return HUDChrome.pressFill }
            if isHovered { return HUDChrome.hoverFill }
            return .clear
        }

        if isSelected {
            if configuration.isPressed { return Color.accentColor.opacity(0.28) }
            if isHovered { return Color.accentColor.opacity(0.22) }
            return Color.accentColor.opacity(0.16)
        }
        if !isEnabled { return .clear }
        if configuration.isPressed { return Color.primary.opacity(0.14) }
        if isHovered { return Color.primary.opacity(0.08) }
        return .clear
    }
}

private struct WindowHeaderVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
    }
}

/// SwiftUI's `.help` is normally enough, but a borderless AppKit window with a
/// hosting view can lose the underlying tooltip tracking view. Keep a native
/// tooltip on the same 28x28 button area as a compatibility fallback.
private struct NativeToolTip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NativeToolTipView {
        NativeToolTipView(text: text)
    }

    func updateNSView(_ nsView: NativeToolTipView, context: Context) {
        nsView.text = text
    }
}

private final class NativeToolTipView: NSView {
    var text: String {
        didSet { toolTip = text }
    }

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        toolTip = text
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // This bridge must never steal the button's mouse events.
        nil
    }
}
