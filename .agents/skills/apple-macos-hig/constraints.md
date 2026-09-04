# Shot 推荐约束

结合当前代码现状。新代码按「目标」写；改旧代码时顺手把同一文件里的违规清掉。

## 优先级

1. **苹果官方 HIG、隐私、打包与无障碍**（见 [hig-macos.md](hig-macos.md)、[packaging.md](packaging.md)）写明的规则优先。
2. **本文件的 Shot 硬约束** 其次。
3. **没有明确要求的地方，交互与信息架构跟随 CleanShot X**：All-in-One overlay、底部模式条、区域就地标注、窗口抽出居中、尺寸 HUD、标注工具条分组、状态菜单结构、截取上次区域。不要复制 CleanShot 的品牌、图标、配色商标或文案。

## 产品定位

- Shot 是菜单栏截图工具，不是文档型 App。不要加主窗口、多标签工作区、iOS 风 tab bar。
- 主路径：全局热键 → overlay 选区/窗口 → 就地标注 → 复制或保存。

## UI 约束

1. **系统外观优先**
   SwiftUI 用 `Form` / `TabView` / 系统 `Button`；AppKit 用标准控件。禁止引入第三方 UI 库。设置与引导用系统 spacing + `scenePadding`。捕获浮层（模式条、标注条、HUD）按 CleanShot X 使用深色 HUD material，即使系统是浅色模式。

2. **一条设置入口**
   只用 SwiftUI `Settings` scene。用 `showSettingsWindow:` 打开，窗口 identifier 为 `shot.settings`，标题为「设置」。不要再创建第二套设置 `NSWindow`。

3. **状态菜单**
   顺序：截取区域 / 窗口 / 全屏 / All-in-One / 录屏 / 截取上次区域 → 分隔线 → 设置… → 关于 Shot → 退出 Shot。退出必须是最后一项；只有已经实现并有完整取消/保存路径的功能才能放进状态菜单。

4. **Overlay 模式条**
   只放当前可用模式（区域、窗口、全屏）。未实现功能从主 HUD 移除。标签字号不要低于 11 pt。选中态用 accent。条定位在 `visibleFrame` 底部居中。

5. **HUD / 遮罩**
   尺寸 HUD 用 `NSVisualEffectView` 的 `.hudWindow`（深色 HUD），不要手绘纯黑底。遮罩用深色半透明；选区描边用 `controlAccentColor`。

6. **标注工具条**
   每个工具：SF Symbol、`.help`、选中态 accent。不要放未实现的钉图。「复制」用 prominent 主按钮，「保存」次之，关闭用 xmark + Esc。

7. **引导页**
   只讲用户价值与权限原因。不要出现竞品名称或实现备注。权限步骤：状态文字 + 请求按钮 + 打开系统设置。可跳过。

8. **文案与本地化**
   用户可见字符串用 `String(localized:)`，开发语言 `zh-Hans`。专有名词白名单：Shot、All-in-One、macOS。

9. **颜色与无障碍**
   权限指示灯必须伴随文字。自定义 `NSView` 必须有 accessibility 标签。

10. **多屏与安全区**
    Overlay 覆盖 `screen.frame`；模式条、编辑器、HUD 定位用 `visibleFrame`。编辑器超出屏幕时缩小并夹紧。

## 交互约束

- 捕获中：Esc 取消，十字光标，Space 移动选区，Shift 正方形。
- 全屏：点模式条「全屏」或 Return（全屏模式）才截，不要悬停即截。
- 未授予屏幕录制时：打开引导，不要空白失败。
- 保存：默认「图片/Shot」；`askWhereToSave` 时用 `NSSavePanel`。
- 复制到剪贴板用 `NSPasteboard` 写 `NSImage`。
- 全局热键录制：Esc 取消；必须有修饰键（或 F 键）。
- 「截取上次区域」仅在已有 `lastSelection` 时可用。

## 工程与捕获防回归

- 区域必须使用带 `rect + displayID` 的 `RegionSelection`。创建、移动、Space、历史恢复和录屏区域都只能在该 displayID 对应的 `screen.frame` 内；无法精确找到显示器时返回错误，禁止使用 `NSScreen.main` 或数组下标兜底。
- 窗口与显示器的定位按最大交集选择屏幕。窗口阴影只使用 ScreenCaptureKit 的 `ignoreShadowsSingleWindow`，不额外添加经验性边距。
- 编辑器鼠标事件只更新原图上的标注层和 draft；完整合成、渲染、编码和文件写入必须在复制/保存时通过不可变快照放入后台任务。
- 导出期间按钮必须禁用并能处理取消与错误；Backspace 不得映射成撤销，撤销只由 Command-Z 或工具栏触发。
- 设置入口只使用 `Settings` scene 的系统 action；窗口 identifier 固定为 `shot.settings`，不得再添加隐藏 helper、通知或菜单扫描兜底。
- 用户可见文案必须在 `Sources/Shot/Localizable.xcstrings` 中有 `zh-Hans` 单元；新增文案后运行 `make validate-localization`。

## 工程约束

- 捕获只走 `ScreenCaptureKit` + `SCScreenshotManager`。过滤本应用窗口。
- `NSWindow.sharingType = .none` 对 overlay、模式条、编辑器保持。
- 热键、权限、设置读写放在 `HotkeyCenter` / `PermissionService` / `AppSettings`。可测试逻辑放 `ShotKit`。
- 可测试逻辑改动后跑 `swift test`。UI 改动后 `make app`；无法点 GUI 时至少保证构建通过。
- 不把 `Shot.app`、`.build`、证书、公证凭证提交进 git。图标源文件（`Support/Shot.icns`、`Support/Assets.xcassets`）要提交。

## Shot 截图流程防回归

- 导出、复制、保存或从编辑器工具栏关闭前，必须先提交当前 NSTextView 中尚未完成的文字标注；编辑文字时第一次 Esc 只取消文字，下一次 Esc 才关闭编辑器。
- 空格移动必须覆盖两条路径：已有选区后按住空格拖动，以及框选拖拽中按下空格后继续拖动；两条路径都要保持选区尺寸不变并限制在起始显示器内。
- 选区创建、移动和「截取上次区域」恢复都必须夹紧到起始显示器的 `screen.frame`；`CaptureService.captureRegion` 必须再次拒绝跨显示器矩形。
- 显示器配置变化时，活动捕获浮层必须更新窗口和边界；窗口快照采用鼠标移动触发、低频兜底刷新，并丢弃过期异步快照。
- `Shot.xcodeproj` 只能由 `project.yml` 生成；不得保留不存在的 Swift 源码引用。版本、bundle id、最终 `Info.plist` 与资源必须由校验脚本自动核对，禁止静默漂移。
- SwiftPM 生成的 `Shot_Shot.bundle` 必须复制到最终 `.app/Contents/Resources/` 并参与签名校验；不能为了满足资源路径破坏 macOS app bundle 的签名结构。
- 新增或改造的动态可点击控件必须提供明确的 accessibility label 和 value；快捷键录制、清除、重置等状态型控件还要反映当前状态。
- 完成代码改动后必须运行 `make verify`。若环境没有完整 Xcode，必须明确记录只能完成 `swift test`、打包和静态签名校验，不能声称通过 `xcodebuild`。

## 明确不要做

- 不要做 iOS 风格大圆角卡片堆叠当设置页。
- 不要用自定义标题栏去重造交通灯，除非是无边框标注浮层。
- 不要隐藏系统屏幕录制隐私指示。
- 不要默认注册 Command-Shift-3/4/5。
- 不要在未公证包上教用户关 Gatekeeper。
- 不要复制 CleanShot X 的图标、商标或营销文案。
