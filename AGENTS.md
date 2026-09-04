# Shot 工程约束

这些规则用于防止截图坐标、构建产物和编辑器性能问题回归。

## 架构与构建

- UI、打包、权限、捕获和 macOS 窗口改动前，先阅读 `.agents/skills/apple-macos-hig/SKILL.md` 及其相关约束。
- 保留 SwiftPM 与 XcodeGen 两条构建链路。`Package.swift`、`project.yml` 和 `Support/Shot.xcconfig` 必须保持一致。
- `Support/Shot.xcconfig` 是 Bundle ID、营销版本和构建号的唯一来源；`Support/Info.plist` 是 Xcode 模板，最终 `.app` 中必须是展开后的值。
- `Shot.xcodeproj` 是生成物，禁止手工编辑；修改 `project.yml` 后运行 `make generate`。
- 修改源码、资源、plist、权限或签名配置后，至少运行 `make verify`；没有完整 Xcode 时，不得声称 `xcodebuild` 已通过。

## 截图与显示器

- 所有区域选区必须使用带明确 `displayID` 的 `RegionSelection`；禁止通过主屏幕或 `NSScreen.screens` 数组下标猜测显示器。
- 创建、拖动、Space 移动和历史恢复的选区都必须限制在起始显示器的 `screen.frame` 内；捕获服务还要再次校验。
- 窗口截图按窗口与显示器的最大交集定位屏幕。窗口阴影只使用 ScreenCaptureKit 的 `ignoreShadowsSingleWindow` 语义，不添加未定义的 padding。

## 编辑器与测试

- 鼠标事件中不得同步生成完整 flatten 图片；画布绘制原图、标注元素和 draft，复制/保存时才生成不可变导出快照。
- 编码和文件写入放到后台任务，主线程只处理 UI、剪贴板和保存面板；导出必须有忙碌态、取消和错误恢复。
- Backspace 不是撤销；撤销仅由 Command-Z 或工具栏触发。
- 新增可测试的纯逻辑放入 `ShotKit` 并补测试。可见文案统一使用 `String(localized:)`，新增后运行 `make validate-localization`。

## 设置与发布

- 设置只使用 SwiftUI `Settings` scene，窗口 identifier 固定为 `shot.settings`，保持单一路径。
- 不新增屏幕录制以外的权限，不启用 App Sandbox，不扩展为 Universal Binary。
- Debug 可以使用 Ad-hoc 签名；Release 没有 Developer ID Application 证书时必须失败。
- 最终应用必须包含 `Shot_Shot.bundle`、隐私清单、图标和本地化资源，并通过 plist、资源和签名校验。
