---
name: apple-macos-hig
description: Applies Apple Human Interface Guidelines, macOS packaging/signing rules, and Shot-specific UI and engineering constraints. Use when writing or reviewing SwiftUI or AppKit UI, menu bar extras, overlays, settings, onboarding, accessibility, Info.plist, entitlements, app icons, XcodeGen, Package.swift, Makefile, package-app.sh, notarization, or when the user mentions HIG, Apple design, 苹果设计规范, 打包, or 构建.
---

# Apple macOS HIG + Shot 工程约束

Shot 是 macOS 菜单栏截图工具（`NSApplication.ActivationPolicy.accessory`）。改 UI、窗口、快捷键、权限、打包时必须先对照本 skill，再改代码。

官方入口（有冲突时以苹果文档为准）：

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

详细条文见 [hig-macos.md](hig-macos.md)、[packaging.md](packaging.md)、[constraints.md](constraints.md)。

## 何时读哪份

- 菜单栏、菜单、快捷键、设置窗、引导 → [hig-macos.md](hig-macos.md)
- Info.plist、entitlements、签名、`.app`、Makefile、`package-app.sh` → [packaging.md](packaging.md)
- 任意 UI / 权限 / 捕获 overlay → [constraints.md](constraints.md)

## 动手前清单

1. 优先用系统控件、系统字体、语义色、SF Symbols、系统 material；不要自绘一套 iOS/网页风皮肤。
2. 菜单栏 extra 点按后出 **菜单**，不要用 popover 塞复杂设置。
3. 用户可见文案走本地化（开发语言 `zh-Hans`），不要在代码里新增长硬编码中英混写。
4. 每个可点击控件有 `help` / accessibility 名称；自定义 `NSView` 补 VoiceOver。
5. 打包产物里的 `Info.plist` **不得**含未展开的 `$(PRODUCT_*)`。
6. 不要引入与系统截图冲突的默认快捷键（Command-Shift-3/4/5）。
7. 截图权限：先说明用途，再请求；失败时引导「系统设置 → 隐私与安全性 → 屏幕录制」。
8. 未完成功能不要做成看起来可点的同等按钮；隐藏或明确标成不可用。
9. 没有明确要求的交互，跟随 CleanShot X 的信息架构与操作路径，不要复制其品牌。

## 改完自检

- 浅色 / 深色下设置窗可读；捕获浮层用系统 HUD material，不要手绘纯黑底
- 遵守 `visibleFrame`（Dock、菜单栏、刘海）
- Esc 取消、Return 确认、Command-C / Command-S / Command-Z 在编辑器可用
- 设置窗只有一条打开路径，标题为「设置」
- 状态栏图标是 template SF Symbol，并带 accessibility 描述
- `.app` 的 bundle id / 版本号 / 图标 / `LSUIElement` 真实有效
