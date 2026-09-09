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
    static let controlSize = InterfaceMetrics.controlSize
    static let symbolSize = InterfaceMetrics.symbolSize
    static let buttonCornerRadius = InterfaceMetrics.buttonRadius
    static let windowPrimaryRowHeight: CGFloat = 44
    static let windowDetailRowHeight: CGFloat = 44
    static let windowSeparatorHeight: CGFloat = 1
    static let windowToolbarHeight = windowPrimaryRowHeight
        + windowSeparatorHeight
        + windowDetailRowHeight
}

struct AnnotationToolbar: View {
    @ObservedObject var session: EditSession
    var onCopy: () -> Void
    var onSave: () -> Void
    var onPin: () -> Void
    var onOCR: () -> Void
    var onClose: () -> Void
    var presentation: AnnotationToolbarPresentation = .floatingHUD

    var availableWidth: CGFloat = 820
    @State private var showsParameters = false

    var body: some View {
        Group {
            if presentation.isFloating {
                toolbarRows
                    .background { HUDChrome.PanelBackground(cornerRadius: InterfaceMetrics.panelRadius) }
                    .environment(\.colorScheme, .dark)
                    .shadow(color: .black.opacity(0.28), radius: EditorLayout.toolbarShadowRadius,
                            y: EditorLayout.toolbarShadowOffsetY)
            } else {
                toolbarRows
                    .background { WindowHeaderVisualEffect() }
            }
        }
        .frame(width: availableWidth, height: AnnotationChromeMetrics.windowToolbarHeight)
        .controlSize(.small)
        .onChange(of: session.selectedTool) { _, _ in showsParameters = false }
    }

    private var toolbarRows: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                primaryRow(compact: false).fixedSize(horizontal: true, vertical: false)
                primaryRow(compact: true)
            }
            .padding(.horizontal, 10)
            .frame(height: AnnotationChromeMetrics.windowPrimaryRowHeight)
            Divider().accessibilityHidden(true)
            HStack(spacing: 8) {
                toolIdentity
                divider
                ViewThatFits(in: .horizontal) {
                    detailControls().fixedSize(horizontal: true, vertical: false)
                    HStack(spacing: 12) {
                        compactPrimaryParameter
                        parameterButton
                    }
                }
                Spacer(minLength: 0)
                if session.selectedTool == .select, session.hasSelection {
                    selectionActionGroup
                }
            }
            .padding(.horizontal, 10)
            .frame(height: AnnotationChromeMetrics.windowDetailRowHeight)
            .disabled(session.isExporting)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "工具详细设置"))
        }
        .frame(width: availableWidth)
    }

    private func primaryRow(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if compact {
                toolCluster([.select, .crop])
                compactToolMenu([.arrow, .rect, .ellipse, .line], title: String(localized: "形状"), symbol: "square.on.circle")
                compactToolMenu([.pen, .highlighter], title: String(localized: "绘制"), symbol: "pencil.tip")
                compactToolMenu([.text, .callout, .counter], title: String(localized: "文字"), symbol: "textformat")
                compactToolMenu([.mosaic, .spotlight], title: String(localized: "遮挡"), symbol: "square.grid.3x3")
            } else {
                ForEach(Array(AnnotationToolID.groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { divider }
                    toolCluster(group)
                }
            }
            Spacer(minLength: 8)
            historyGroup
            divider
            exportActions(compact: compact)
            if presentation.isFloating { closeButton }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "标注工具"))
    }

    private func compactToolMenu(_ tools: [AnnotationToolID], title: String, symbol: String) -> some View {
        let selected = tools.contains(session.selectedTool)
        return Menu {
            ForEach(tools) { tool in
                Button { session.selectedTool = tool } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                }
            }
        } label: {
            Image(systemName: selected ? session.selectedTool.systemImage : symbol)
                .font(.system(size: InterfaceMetrics.symbolSize))
                .frame(width: InterfaceMetrics.controlSize, height: InterfaceMetrics.controlSize)
                .background(selected ? Color.accentColor.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: InterfaceMetrics.buttonRadius))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? session.selectedTool.title : title)
        .disabled(session.isExporting)
    }

    private var parameterButton: some View {
        Button { showsParameters.toggle() } label: {
            Label(String(localized: "调整参数…"), systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
        .help(String(localized: "调整当前工具的颜色与样式"))
        .popover(isPresented: $showsParameters) {
            VStack(alignment: .leading, spacing: 16) {
                Text(session.selectedTool.title).font(.headline)
                detailControls(stacked: true)
            }
            .padding(16)
            .frame(width: 360, alignment: .leading)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .frame(width: InterfaceMetrics.controlSize, height: InterfaceMetrics.controlSize)
        }
        .buttonStyle(AnnotationIconButtonStyle(presentation: presentation))
        .help(String(localized: "关闭编辑器（Esc）"))
        .accessibilityLabel(String(localized: "关闭"))
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
    private func detailControls(stacked: Bool = false) -> some View {
        switch session.selectedTool {
        case .select:
            selectionDetailControls(stacked: stacked)
        case .arrow:
            parameterLayout(stacked: stacked) {
                windowColorControls
                arrowHeadPicker
                detailSlider(
                    label: String(localized: "箭头大小"),
                    value: $session.arrowHeadScale,
                    range: 0.6...1.8,
                    step: 0.1,
                    valueText: multiplierText(session.arrowHeadScale)
                )
                detailSlider(
                    label: String(localized: "线宽（pt）"),
                    value: $session.lineWidth,
                    range: 1...24,
                    step: 1,
                    valueText: numberText(session.lineWidth)
                )
            }
        case .rect, .ellipse:
            parameterLayout(stacked: stacked) {
                windowColorControls
                detailSlider(
                    label: String(localized: "填充"),
                    value: $session.shapeFillOpacity,
                    range: 0...1,
                    step: 0.05,
                    valueText: percentageText(session.shapeFillOpacity)
                )
                detailSlider(
                    label: String(localized: "线宽（pt）"),
                    value: $session.lineWidth,
                    range: 1...24,
                    step: 1,
                    valueText: numberText(session.lineWidth)
                )
            }
        case .line:
            parameterLayout(stacked: stacked) {
                windowColorControls
                linePatternPicker
                detailSlider(
                    label: String(localized: "线宽（pt）"),
                    value: $session.lineWidth,
                    range: 1...24,
                    step: 1,
                    valueText: numberText(session.lineWidth)
                )
            }
        case .pen:
            parameterLayout(stacked: stacked) {
                windowColorControls
                detailSlider(
                    label: String(localized: "画笔粗细（pt）"),
                    value: $session.lineWidth,
                    range: 1...24,
                    step: 1,
                    valueText: numberText(session.lineWidth)
                )
                detailSlider(
                    label: String(localized: "平滑度"),
                    value: $session.penSmoothing,
                    range: 0...1,
                    step: 0.1,
                    valueText: percentageText(session.penSmoothing)
                )
                detailSlider(
                    label: String(localized: "不透明度"),
                    value: $session.penOpacity,
                    range: 0.1...1,
                    step: 0.05,
                    valueText: percentageText(session.penOpacity)
                )
            }
        case .highlighter:
            parameterLayout(stacked: stacked) {
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
            parameterLayout(stacked: stacked) {
                windowColorControls
                detailSlider(
                    label: String(localized: "文字大小（pt）"),
                    value: $session.lineWidth,
                    range: 1...12,
                    step: 1,
                    valueText: numberText(AnnotationMath.fontSize(lineWidth: CGFloat(session.lineWidth)))
                )
            }
        case .callout:
            parameterLayout(stacked: stacked) {
                windowColorControls
                detailSlider(
                    label: String(localized: "气泡填充"),
                    value: $session.calloutFillOpacity,
                    range: 0...0.6,
                    step: 0.05,
                    valueText: percentageText(session.calloutFillOpacity)
                )
                detailSlider(
                    label: String(localized: "线宽（pt）"),
                    value: $session.lineWidth,
                    range: 1...24,
                    step: 1,
                    valueText: numberText(session.lineWidth)
                )
                calloutWrapToggle
            }
        case .counter:
            parameterLayout(stacked: stacked) {
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
            parameterLayout(stacked: stacked) {
                mosaicShapePicker
                mosaicEffectPicker
                detailSlider(
                    label: mosaicSizeLabel,
                    value: $session.mosaicBlockSize,
                    range: 2...32,
                    step: 1,
                    valueText: numberText(session.mosaicBlockSize)
                )
            }
        case .spotlight:
            detailSlider(
                label: String(localized: "遮罩不透明度"),
                value: $session.spotlightOpacity,
                range: 0.1...0.9,
                step: 0.05,
                valueText: percentageText(session.spotlightOpacity)
            )
        case .crop:
            parameterLayout(stacked: stacked) {
                Text(String(localized: "拖拽边缘或手柄调整，拖动框内移动"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button(String(localized: "应用")) {
                    _ = session.commitCrop()
                    session.selectedTool = .select
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(String(localized: "应用裁剪（Return）"))
                .accessibilityLabel(String(localized: "应用裁剪"))
                Button(String(localized: "取消")) {
                    session.cancelCrop()
                    session.selectedTool = .select
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(String(localized: "取消裁剪（Esc）"))
                .accessibilityLabel(String(localized: "取消裁剪"))
            }
        }
    }

    @ViewBuilder
    private func selectionDetailControls(stacked: Bool) -> some View {
        if let selected = session.document.selectedObject {
            parameterLayout(stacked: stacked) {
                Text(String(localized: "已选择"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                switch selected.element {
                case .mosaic(_, _, _):
                    mosaicEffectPicker
                    detailSlider(
                        label: mosaicSizeLabel,
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
                case .callout(_, _, _):
                    windowColorControls
                    detailSlider(
                        label: String(localized: "气泡填充"),
                        value: $session.calloutFillOpacity,
                        range: 0...0.6,
                        step: 0.05,
                        valueText: percentageText(session.calloutFillOpacity)
                    )
                    detailSlider(
                        label: String(localized: "线宽（pt）"),
                        value: $session.lineWidth,
                        range: 1...24,
                        step: 1,
                        valueText: numberText(session.lineWidth)
                    )
                    calloutWrapToggle
                case .counter(_, _, _):
                    windowColorControls
                    detailSlider(
                        label: String(localized: "序号大小"),
                        value: $session.lineWidth,
                        range: 1...12,
                        step: 1,
                        valueText: numberText(max(10, session.lineWidth * 10))
                    )
                case .arrow(_, _, _):
                    windowColorControls
                    arrowHeadPicker
                    detailSlider(
                        label: String(localized: "箭头大小"),
                        value: $session.arrowHeadScale,
                        range: 0.6...1.8,
                        step: 0.1,
                        valueText: multiplierText(session.arrowHeadScale)
                    )
                    detailSlider(
                        label: String(localized: "线宽（pt）"),
                        value: $session.lineWidth,
                        range: 1...24,
                        step: 1,
                        valueText: numberText(session.lineWidth)
                    )
                case .line(_, _, _):
                    windowColorControls
                    linePatternPicker
                    detailSlider(
                        label: String(localized: "线宽（pt）"),
                        value: $session.lineWidth,
                        range: 1...24,
                        step: 1,
                        valueText: numberText(session.lineWidth)
                    )
                case .pen(_, _):
                    windowColorControls
                    detailSlider(
                        label: String(localized: "线宽（pt）"),
                        value: $session.lineWidth,
                        range: 1...24,
                        step: 1,
                        valueText: numberText(session.lineWidth)
                    )
                    detailSlider(
                        label: String(localized: "平滑度"),
                        value: $session.penSmoothing,
                        range: 0...1,
                        step: 0.1,
                        valueText: percentageText(session.penSmoothing)
                    )
                    detailSlider(
                        label: String(localized: "不透明度"),
                        value: $session.penOpacity,
                        range: 0.1...1,
                        step: 0.05,
                        valueText: percentageText(session.penOpacity)
                    )
                case .rect(_, _), .ellipse(_, _):
                    windowColorControls
                    detailSlider(
                        label: String(localized: "填充"),
                        value: $session.shapeFillOpacity,
                        range: 0...1,
                        step: 0.05,
                        valueText: percentageText(session.shapeFillOpacity)
                    )
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
        colorSwatches
    }

    private func parameterLayout<Content: View>(stacked: Bool, @ViewBuilder content: () -> Content) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout { content() }
    }

    @ViewBuilder
    private var compactPrimaryParameter: some View {
        switch session.selectedTool {
        case .arrow, .rect, .ellipse, .line, .pen, .highlighter, .callout:
            NativeAnnotationColorWell(color: $session.color, accessibilityLabel: String(localized: "颜色"))
                .frame(width: 28, height: 28)
                .help(String(localized: "选择自定义颜色"))
            detailSlider(label: String(localized: "线宽（pt）"), value: $session.lineWidth,
                         range: session.selectedTool == .highlighter ? 1...32 : 1...24,
                         step: 1, valueText: numberText(session.lineWidth))
        case .text, .counter:
            NativeAnnotationColorWell(color: $session.color, accessibilityLabel: String(localized: "颜色"))
                .frame(width: 28, height: 28)
                .help(String(localized: "选择自定义颜色"))
        case .mosaic:
            detailSlider(label: mosaicSizeLabel, value: $session.mosaicBlockSize,
                         range: 2...32, step: 1, valueText: numberText(session.mosaicBlockSize))
        case .spotlight, .select, .crop:
            EmptyView()
        }
    }

    private var arrowHeadPicker: some View {
        Picker(String(localized: "箭头尖端"), selection: $session.arrowHeadStyle) {
            ForEach(AnnotationArrowHeadStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.menu)
        .help(String(localized: "选择箭头尖端样式"))
        .accessibilityLabel(String(localized: "箭头尖端"))
    }

    private var linePatternPicker: some View {
        Picker(String(localized: "线型"), selection: $session.linePattern) {
            ForEach(AnnotationStrokePattern.allCases) { pattern in
                Text(pattern.title).tag(pattern)
            }
        }
        .pickerStyle(.menu)
        .help(String(localized: "选择直线样式"))
        .accessibilityLabel(String(localized: "线型"))
    }

    private var mosaicSizeLabel: String {
        session.mosaicEffect == .blur
            ? String(localized: "模糊半径（pt）")
            : String(localized: "颗粒大小（pt）")
    }

    private var mosaicShapePicker: some View {
        compactMenuPicker(
            label: String(localized: "形状"),
            selection: $session.mosaicShape,
            help: session.mosaicShape.helpText,
            accessibilityLabel: String(localized: "马赛克形状")
        ) {
            ForEach(MosaicShapeKind.allCases) { shape in
                Text(shape.title).tag(shape)
            }
        }
    }

    private var mosaicEffectPicker: some View {
        compactMenuPicker(
            label: String(localized: "效果"),
            selection: $session.mosaicEffect,
            help: session.mosaicEffect.helpText,
            accessibilityLabel: String(localized: "马赛克效果")
        ) {
            ForEach(MosaicEffect.allCases) { effect in
                Text(effect.title).tag(effect)
            }
        }
    }

    private func compactMenuPicker<Value: Hashable>(
        label: String,
        selection: Binding<Value>,
        help: String,
        accessibilityLabel: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: presentation.isFloating ? 6 : 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker(accessibilityLabel, selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .controlSize(.small)
            .help(help)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var calloutWrapToggle: some View {
        Toggle(String(localized: "自动换行"), isOn: $session.calloutWrapText)
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .help(String(localized: "控制气泡文字是否自动换行"))
            .accessibilityLabel(String(localized: "自动换行"))
            .accessibilityValue(
                session.calloutWrapText
                    ? String(localized: "开启")
                    : String(localized: "关闭")
            )
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
            .frame(width: 84)
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

    private func multiplierText(_ value: Double) -> String {
        String(format: String(localized: "%.1f×"), value)
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
        .disabled(session.isExporting)
        .help(tool.helpText)
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.helpText)
        .accessibilityAddTraits(session.selectedTool == tool ? [.isSelected] : [])
        .background {
            NativeToolTip(text: tool.helpText)
        }
    }

    private var colorSwatches: some View {
        HStack(spacing: presentation.isFloating ? 5 : 4) {
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
            NativeAnnotationColorWell(
                color: $session.color,
                accessibilityLabel: String(localized: "选择自定义颜色")
            )
            .frame(
                width: AnnotationChromeMetrics.controlSize,
                height: AnnotationChromeMetrics.controlSize
            )
            .padding(.horizontal, presentation.isFloating ? 5 : 4)
            .help(String(localized: "选择自定义颜色"))
            .accessibilityLabel(String(localized: "选择自定义颜色"))
        }
        .padding(.horizontal, presentation.isFloating ? 6 : 4)
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
            .disabled(!session.canUndo || session.isExporting)
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
            .disabled(!session.canRedo || session.isExporting)
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

    private func exportActions(compact: Bool) -> some View {
        HStack(spacing: presentation.isFloating ? 6 : 4) {
            if session.isExporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "正在导出"))
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
            if compact {
                Menu {
                    Button(String(localized: "钉图"), action: onPin)
                    Button(String(localized: "识别文字"), action: onOCR)
                } label: {
                    Image(systemName: "ellipsis").frame(width: InterfaceMetrics.controlSize, height: InterfaceMetrics.controlSize)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(String(localized: "更多操作"))
                .help(String(localized: "更多操作"))
                .disabled(session.isExporting)
            } else {
            Button {
                onPin()
            } label: {
                Image(systemName: "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: AnnotationChromeMetrics.controlSize, height: AnnotationChromeMetrics.controlSize)
            }
            .buttonStyle(AnnotationIconButtonStyle(presentation: presentation))
            .help(String(localized: "将截图钉在桌面上"))
            .accessibilityLabel(String(localized: "钉图"))
            .disabled(session.isExporting)
            Button {
                onOCR()
            } label: {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: AnnotationChromeMetrics.controlSize, height: AnnotationChromeMetrics.controlSize)
            }
            .buttonStyle(AnnotationIconButtonStyle(presentation: presentation))
            .help(String(localized: "识别文字并复制"))
            .accessibilityLabel(String(localized: "识别文字"))
            .disabled(session.isExporting)
            }
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
}

/// The minimal AppKit color well uses the control itself as the popover anchor.
/// Keep a reference so editor teardown can also deactivate a picker that is open.
@MainActor
enum AnnotationColorPickerController {
    static weak var activeWell: NSColorWell?

    static func dismiss() {
        activeWell?.deactivate()
        if NSColorPanel.sharedColorPanelExists {
            NSColorPanel.shared.close()
        }
        activeWell = nil
    }
}

private final class AnnotationColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        AnnotationColorPickerController.activeWell = self
        super.activate(exclusive)
    }

    override func deactivate() {
        super.deactivate()
        if AnnotationColorPickerController.activeWell === self {
            AnnotationColorPickerController.activeWell = nil
        }
    }
}

private struct NativeAnnotationColorWell: NSViewRepresentable {
    @Binding var color: Color
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let well = AnnotationColorWell(style: .minimal)
        well.color = NSColor(color)
        well.supportsAlpha = false
        well.isContinuous = true
        well.focusRingType = .exterior
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.setAccessibilityElement(true)
        well.setAccessibilityRole(NSAccessibility.Role.button)
        well.setAccessibilityLabel(accessibilityLabel)
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.color = $color
        well.setAccessibilityLabel(accessibilityLabel)
        let newColor = NSColor(color)
        if !well.color.isEqual(newColor) {
            well.color = newColor
        }
    }

    static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) {
        well.deactivate()
        if AnnotationColorPickerController.activeWell === well {
            AnnotationColorPickerController.activeWell = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var color: Binding<Color>

        init(color: Binding<Color>) {
            self.color = color
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            color.wrappedValue = Color(nsColor: sender.color)
        }
    }
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
    @ObservedObject private var preferences = InterfacePreferences.shared
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
        let view = HUDMaterialView()
        view.surface = .windowHeader
        view.cornerRadius = 0
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
