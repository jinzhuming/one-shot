# Apple HIG（Shot 相关摘录）

以官方 [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) 为准。这里只收菜单栏截图工具会用到的条文，不复述全站。HIG 没写到的截图交互跟随 CleanShot X，不要复制其品牌。

## 平台气质

- macOS 应用应像系统原生应用：指针优先、键盘完整、窗口可预期、菜单可发现。
- 使用 San Francisco / 系统字体，不要嵌入无关 UI 字体。
- 颜色用语义色：`NSColor.labelColor`、`secondaryLabelColor`、`controlAccentColor`、`separatorColor`、`windowBackgroundColor`。不要写死 RGB，除非是标注工具的用户所选描边色。
- 深色模式必须一等公民。设置窗与引导跟随系统外观。捕获 overlay 的模式条、标注条、尺寸 HUD 按 CleanShot X 使用深色 HUD material（`NSVisualEffectView.hudWindow` / `.ultraThinMaterial` + dark colorScheme），不要手绘纯色黑块。
- 材质用系统 material（`.regularMaterial` / `NSVisualEffectView` / 新 SDK 的 Liquid Glass）。不要用假毛玻璃（纯色 + 低透明度冒充）。
- 圆角用 continuous corner。控件圆角跟系统控件走，不要每个按钮一套半径。

## 菜单栏 extra

官方：[The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)

- 图标用 **template** SF Symbol 或黑/透明形状，系统会按浅色/深色菜单栏着色。菜单栏高度 22–24 pt，图标不要花、不要彩色。
- 点击后优先弹出 **菜单**。只有内容复杂到菜单装不下时才用 window-style extra。
- 不要假定 extra 永远可见：系统会折叠菜单栏项目；主路径还要能通过快捷键触发。
- 菜单栏 extra 不能替代标准菜单能力：设置（Command-,）、退出（Command-Q）、关于，都要能从状态菜单到达。
- 纯 accessory 应用仍应处理 Dock / 访达再次打开：`applicationShouldHandleReopen` 打开设置，而不是什么都不做。
- 让用户决定是否开机启动、是否常驻菜单栏；不要静默抢开机项。

## 菜单与快捷键

官方：[Menus](https://developer.apple.com/design/human-interface-guidelines/menus)

- 会打开窗口/面板的菜单项用省略号：「设置…」「选择…」。
- 快捷键展示系统标准修饰符顺序：Control, Option, Shift, Command。
- 不要占用系统截图：Command-Shift-3/4/5。默认 All-in-One 用 Command-Shift-2 可以。
- 编辑器保留系统习惯：Esc 关闭、Command-C 复制、Command-S 保存、Command-Z / Shift-Command-Z 撤销重做、Return 确认。
- 状态菜单里的快捷键是展示，真正全局热键走 `RegisterEventHotKey` / 等价 API；两者必须一致。
- 冲突时告诉用户，不要静默注册失败。

## 窗口

官方：[Windows](https://developer.apple.com/design/human-interface-guidelines/windows)

- 设置窗：标准标题栏（关闭/最小化即可），标题「设置」，`Form` + `.formStyle(.grouped)`，用 `TabView` 或侧栏分组。用 `.scenePadding()`，不要自己发明边距体系。
- 设置窗只应有 **一条** 打开路径。accessory 应用没有应用菜单时，以状态菜单 + SwiftUI `Settings` scene 为准，不要再维护第二套 `NSWindow`。
- 引导窗：第一次启动、可跳过、不要每次都挡路。权限步骤把「为什么需要」写清楚。
- 捕获 overlay / 标注浮层可以是无边框、高窗口层级的 utility/HUD，但必须：Esc 退出、不截到自己（`sharingType = .none`）、多屏各盖一屏、位置相对 `visibleFrame` 避开 Dock。
- 不要用 `.screenSaver` 层级去盖系统隐私指示点或强行压过锁屏。捕获 UI 用尽可能低、仍能盖住桌面的层级。
- 模态错误用 `NSAlert`；不要用自定义 toast 替代需要决策的错误。

## 布局与控件

官方：[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)

- 优先 SwiftUI `Form` / `Picker` / `Toggle` / `Button` 系统样式。工具条按钮用 `.borderless` + 固定命中区，不要 `.plain` 到看不出是按钮。
- 指针环境命中区至少约 20×20 pt，推荐 28×28 pt。标注工具条不要再缩小。
- 辅助说明用 `.help("…")`，不要只靠颜色表达状态。
- 未实现功能：从主路径拿掉，或 `disabled` + help 说明「后续版本」。不要做成和可用按钮一样可点、点了没反应。
- 主按钮用 `.keyboardShortcut(.defaultAction)`（Return）。破坏性操作用强调样式并二次确认。

## 图标与符号

官方：[App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)、[SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)

- 必须有 macOS App Icon（Assets 的 `AppIcon`）：圆角由系统裁，源图提供完整 1024 图层，不要自己预裁超圆角、不要把截图工具画成 iOS 应用图标。
- 界面图标一律 SF Symbols，weight 与相邻文字匹配。选中态可用 accent fill，不要换一套无关图标。
- 状态栏图标提供 `accessibilityDescription`。

## 无障碍

官方：[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

- 每个自定义 `NSView`（overlay、HUD、画布）设置 `accessibilityElement` / `accessibilityLabel` / 角色。
- 不要只靠颜色表示权限状态（绿点/橙点必须搭配文字）。
- 支持 VoiceOver 与全键盘：设置窗、引导、标注工具条都能 Tab / 快捷键操作。
- 尊重「减少透明度」：material 要有实色回退。
- 动态内容（尺寸 HUD `320 × 200`）用系统数字等宽字体，已符合；同时要能被辅助技术读出。

## 隐私

官方：[Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)

- 屏幕录制是敏感权限。先在引导里解释「为了截取其他窗口」，再调用 `CGRequestScreenCaptureAccess` / ScreenCaptureKit。
- 被拒绝后提供「打开系统设置」，不要死循环弹系统框。
- 截屏后不要上传、不要未经用户操作就写入用户未选择的位置以外的目录；默认目录用「图片/Shot」可以，但设置里必须能改。
- 尊重系统隐私指示（菜单栏橙点/录制指示）。不要尝试隐藏或绕过。
- 优先 ScreenCaptureKit，排除本应用窗口；不要用过时的全屏 `CGWindowListCreateImage` 扫桌面。

## 文案

- 用户可见字符串：简体中文。专有名词可保留英文（All-in-One、Shot）。
- 用「设置」不是「偏好设置」。
- 错误信息用 `LocalizedError`，面向用户，不要堆栈。
- 不要在 UI 里写实现细节（「对标 CleanShot X」属于开发备注，不应出现在引导页）。
