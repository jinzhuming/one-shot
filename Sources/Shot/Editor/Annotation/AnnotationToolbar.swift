import SwiftUI
import AppKit
import ShotKit

enum AnnotationToolbarPresentation {
    case floating
    case docked
}

struct AnnotationToolbar: View {
    @ObservedObject var session: EditSession
    var onCopy: () -> Void
    var onSave: () -> Void
    var onClose: () -> Void
    var presentation: AnnotationToolbarPresentation = .floating

    var body: some View {
        VStack(spacing: presentation == .docked ? 2 : 5) {
            primaryToolbar
            if presentation == .floating
                || session.selectedTool != .select
                || session.hasSelection {
                detailToolbar
            }
        }
        .environment(\.colorScheme, .dark)
        .background {
            if presentation == .docked {
                HUDChrome.DockedBackground()
            }
        }
        .shadow(
            color: .black.opacity(presentation == .floating ? 0.22 : 0.28),
            radius: presentation == .floating ? 1 : 14,
            y: 0
        )
        .shadow(
            color: .black.opacity(presentation == .floating ? 0.42 : 0.16),
            radius: presentation == .floating ? EditorLayout.toolbarShadowRadius : 6,
            y: presentation == .floating ? EditorLayout.toolbarShadowOffsetY : 2
        )
    }

    private var primaryToolbar: some View {
        HStack(spacing: presentation == .docked ? 6 : 8) {
            ForEach(Array(AnnotationToolID.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { divider }
                toolCluster(group)
            }
            divider
            styleGroup
            divider
            historyGroup
            divider
            actionGroup
        }
        .padding(.horizontal, presentation == .docked ? 8 : 10)
        .padding(.vertical, presentation == .docked ? 5 : 7)
        .contentShape(Rectangle())
        .background {
            if presentation == .floating {
                HUDChrome.PanelBackground(cornerRadius: 12)
            }
        }
    }

    private var detailToolbar: some View {
        HStack(spacing: presentation == .docked ? 6 : 10) {
            Image(systemName: session.selectedTool.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(session.selectedTool.title)
                .font(.system(size: 11, weight: .semibold))
                .frame(minWidth: 42, alignment: .leading)
            divider
            detailControls
        }
        .frame(minHeight: presentation == .docked ? 30 : 34)
        .padding(.horizontal, presentation == .docked ? 8 : 10)
        .contentShape(Rectangle())
        .background {
            if presentation == .floating {
                HUDChrome.PanelBackground(cornerRadius: 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "工具详细设置"))
    }

    @ViewBuilder
    private var detailControls: some View {
        switch session.selectedTool {
        case .select:
            selectionDetailControls
        case .arrow, .rect, .ellipse, .line:
            detailSlider(
                label: String(localized: "线宽（pt）"),
                value: $session.lineWidth,
                range: 1...24,
                step: 1,
                valueText: numberText(session.lineWidth)
            )
        case .pen:
            detailSlider(
                label: String(localized: "画笔粗细（pt）"),
                value: $session.lineWidth,
                range: 1...24,
                step: 1,
                valueText: numberText(session.lineWidth)
            )
        case .highlighter:
            HStack(spacing: presentation == .docked ? 8 : 12) {
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
            detailSlider(
                label: String(localized: "文字大小（pt）"),
                value: $session.lineWidth,
                range: 1...12,
                step: 1,
                valueText: numberText(AnnotationMath.fontSize(lineWidth: CGFloat(session.lineWidth)))
            )
        case .counter:
            detailSlider(
                label: String(localized: "序号大小"),
                value: $session.lineWidth,
                range: 1...12,
                step: 1,
                valueText: numberText(max(10, session.lineWidth * 10))
            )
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
            HStack(spacing: presentation == .docked ? 8 : 12) {
                Text(String(localized: "已选择"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                switch selected.element {
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
                default:
                    detailSlider(
                        label: String(localized: "线宽（pt）"),
                        value: $session.lineWidth,
                        range: 1...24,
                        step: 1,
                        valueText: numberText(session.lineWidth)
                    )
                    if case .highlighter = selected.element {
                        detailSlider(
                            label: String(localized: "透明度"),
                            value: $session.highlighterOpacity,
                            range: 0.1...1,
                            step: 0.05,
                            valueText: percentageText(session.highlighterOpacity)
                        )
                    }
                }
            }
        } else {
            Text(String(localized: "点击标注以选择"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func detailSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        HStack(spacing: presentation == .docked ? 4 : 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(value: value, in: range, step: step, onEditingChanged: { editing in
                if editing {
                    session.beginStyleAdjustment()
                } else {
                    session.endStyleAdjustment()
                }
            })
                .frame(width: presentation == .docked ? 96 : 120)
                .help(label)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
            Text(valueText)
                .font(.system(size: 11, design: .monospaced))
                .frame(minWidth: presentation == .docked ? 30 : 34, alignment: .trailing)
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
        HStack(spacing: presentation == .docked ? 1 : 2) {
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
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HUDChrome.IconButtonStyle(isSelected: session.selectedTool == tool))
        .help(tool.helpText)
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.helpText)
        .accessibilityAddTraits(session.selectedTool == tool ? [.isSelected] : [])
        .background {
            NativeToolTip(text: tool.helpText)
        }
    }

    private var styleGroup: some View {
        HStack(spacing: presentation == .docked ? 6 : 8) {
            HStack(spacing: presentation == .docked ? 4 : 5) {
                ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                    Button {
                        session.color = Color(nsColor: swatch.color)
                    } label: {
                        Circle()
                            .fill(Color(nsColor: swatch.color))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        colorRing(for: swatch.color),
                                        lineWidth: isSelected(swatch.color) ? 2 : 1
                                    )
                            )
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HUDChrome.IconButtonStyle(tintsLabel: false))
                    .help(swatch.help)
                    .accessibilityLabel(swatch.help)
                    .accessibilityAddTraits(isSelected(swatch.color) ? [.isSelected] : [])
                }
            }
            HStack(spacing: presentation == .docked ? 1 : 2) {
                ForEach(Array(Self.strokeSizes.enumerated()), id: \.offset) { _, size in
                    Button {
                        session.lineWidth = size.width
                    } label: {
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 1.5)
                            .background(Circle().fill(Color.primary.opacity(session.lineWidth == size.width ? 0.9 : 0.15)))
                            .frame(width: size.dot, height: size.dot)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HUDChrome.IconButtonStyle(isSelected: session.lineWidth == size.width))
                    .help(size.help)
                    .accessibilityLabel(size.help)
                    .accessibilityAddTraits(session.lineWidth == size.width ? [.isSelected] : [])
                }
            }
        }
    }

    private var historyGroup: some View {
        HStack(spacing: presentation == .docked ? 1 : 2) {
            Button {
                session.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HUDChrome.IconButtonStyle())
            .disabled(!session.canUndo)
            .help(String(localized: "撤销（⌘Z）"))
            .accessibilityLabel(String(localized: "撤销"))

            Button {
                session.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HUDChrome.IconButtonStyle())
            .disabled(!session.canRedo)
            .help(String(localized: "重做（⇧⌘Z）"))
            .accessibilityLabel(String(localized: "重做"))
        }
    }

    private var actionGroup: some View {
        HStack(spacing: presentation == .docked ? 4 : 6) {
            if presentation == .floating || session.hasSelection {
                Button {
                    session.duplicateSelection()
                } label: {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HUDChrome.IconButtonStyle())
                .help(String(localized: "复制选中标注（⌘D）"))
                .accessibilityLabel(String(localized: "复制选中标注"))
                .disabled(session.isExporting)

                Button {
                    session.deleteSelection()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HUDChrome.IconButtonStyle())
                .help(String(localized: "删除选中标注（Delete）"))
                .accessibilityLabel(String(localized: "删除选中标注"))
                .disabled(session.isExporting)
            }

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
            if presentation == .floating {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HUDChrome.IconButtonStyle())
                .help(String(localized: "关闭编辑器（Esc）"))
                .accessibilityLabel(String(localized: "关闭"))
            }
        }
        .controlSize(.small)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.28))
            .frame(width: 1, height: presentation == .docked ? 16 : 18)
    }

    private func isSelected(_ color: NSColor) -> Bool {
        colorDistance(NSColor(session.color), color) < 0.08
    }

    private func colorRing(for color: NSColor) -> Color {
        if isSelected(color) {
            return Color.white
        }
        if colorDistance(color, .white) < 0.08 {
            return Color.black.opacity(0.35)
        }
        return Color.white.opacity(0.28)
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
