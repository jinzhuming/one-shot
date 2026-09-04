# macOS 打包与基础工程化

官方：

- [Information Property List](https://developer.apple.com/documentation/bundleresources/information_property_list)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## 当前工程形态

- 源码：`Sources/Shot`，Swift 5，macOS 14+。
- 双入口：`Package.swift`（`swift build`）+ `project.yml`（XcodeGen → `Shot.xcodeproj`）。
- 日常：`make app` → `swift build` + `scripts/package-app.sh` → `Shot.app`。
- 不要再引入第三套构建系统。改配置时 **同时** 改 `Package.swift` 与 `project.yml`。

## Info.plist 硬规则

`Support/Info.plist` 若含 Xcode 宏（`$(PRODUCT_BUNDLE_IDENTIFIER)` 等），**禁止**被 `package-app.sh` 原样拷进 `Shot.app`。TCC 屏幕录制权限绑定真实 bundle id；宏未展开等于没有身份。

打包脚本必须写出已展开的 plist，至少包含：

- `CFBundleIdentifier` = `com.jinzhuming.shot`
- `CFBundleName` / `CFBundleDisplayName` = `Shot`
- `CFBundleExecutable` = `Shot`
- `CFBundlePackageType` = `APPL`
- `CFBundleShortVersionString` 与 `project.yml` 的 `MARKETING_VERSION` **同一来源**，目前均为 `0.1.0`
- `CFBundleVersion` 每次分发递增
- `LSUIElement` = `true`（菜单栏应用，避免启动时闪 Dock）
- `LSMinimumSystemVersion` = `14.0`
- `NSHighResolutionCapable` = `true`
- `NSSupportsAutomaticTermination` / `NSSupportsSuddenTermination` 对常驻热键工具设为 `false`
- `CFBundleIconFile` = `Shot`，`CFBundleIconName` = `AppIcon`
- 开发语言：`zh-Hans`

`Support/Info.plist` 必须是已展开的字面量，作为 `package-app.sh` 与 Xcode 的同一来源。改版本号时同时改 plist 和 `project.yml`。

屏幕录制没有独立的 `NSScreenCaptureUsageDescription` 键，但引导文案必须说明用途。若将来加麦克风/相机/辅助功能，必须先加对应 usage description，否则直接拒审。

## 应用包结构

`Shot.app/Contents/` 最低要求：

```
MacOS/Shot          # 可执行文件
Info.plist          # 已展开
PkgInfo             # APPL????
Resources/          # AppIcon、本地化、隐私清单
```

- `make app` 只负责本地可运行包；分发包必须再签名 + 公证。
- 不要把 `.build/`、`Shot.xcodeproj`、`Shot.app` 当源码提交（已在 `.gitignore`）。
- 图标用 `Assets.xcassets` / `AppIcon`；不要只靠 SF Symbol 当应用图标。

## 签名、Hardened Runtime、公证

本地日常包也要固定身份：`CFBundleIdentifier` 与 `codesign --identifier` 必须是 `com.jinzhuming.shot`，并用稳定证书签名（优先 Developer ID Application，可用 `CODESIGN_IDENTITY` 覆盖）。Ad-hoc（`-`）的 designated requirement 是每次变化的 CDHash，TCC 屏幕录制会当成新 App。**任何离开本机的包**：

1. `ENABLE_HARDENED_RUNTIME = true`
2. Developer ID Application 签名
3. `entitlements` 只开用到的能力；空文件可以，但不要关 Hardened Runtime 来「图省事」
4. `notarytool submit` + `stapler staple`
5. 公证失败先看日志，不要 `--force` 跳过

ScreenCaptureKit 不需要把沙盒当前提。若将来 Mac App Store：再开 App Sandbox，并配 `com.apple.security.device.screen-capture` 等对应 entitlement。现在非 MAS 分发不要假装已沙盒。

## 隐私清单

分发前加 `PrivacyInfo.xcprivacy`（已放在 `Support/PrivacyInfo.xcprivacy`）。用到 UserDefaults、文件时间戳、磁盘空间等 Required Reason API 必须申报。不要等 App Store Connect 报缺失再补。

## 版本号

- 用户可见：`MARKETING_VERSION`（例如 `0.1.0`）
- 构建号：`CURRENT_PROJECT_VERSION`（整数递增）
- 单一来源：`project.yml`（Xcode）与 `package-app.sh`（SPM 包）都读同一处，禁止 Info.plist 手写另一套。

## 推荐工程约束

- 最低系统跟 `Package.swift` platforms 与 `project.yml` `deploymentTarget` 锁死，改一处必须改另一处。
- Swift 语言模式保持显式（现在 tools 6.0 + language mode v5）；升 Swift 6 并发检查要单独做，不要夹在 UI 改动里。
- 捕获继续用 ScreenCaptureKit，不要退回 `CGDisplayCreateImage` / `CGWindowListCreateImage`。
- 新增权限、URL scheme、文件类型关联时，先改 plist + entitlements，再写代码。
- 可测试逻辑放 `ShotKit`，改动后跑 `swift test`。至少覆盖：坐标换算、热键编解码、导出文件名。
- `make clean` 可删 `.build`、`Shot.app`、`Shot.xcodeproj`；不要删 `Sources/`、`Support/`、`scripts/`。
- 图标用 `make icon`（`scripts/generate-icon.swift`）生成 `Support/Shot.icns` 与 `Support/Assets.xcassets`。

## package-app.sh 必须做的事

1. 确认二进制存在。
2. 写出 **展开后** 的 Info.plist（禁止 `cp Support/Info.plist` 若其中含 `$()`）。
3. 拷贝 Resources（图标、隐私清单、lproj）。
4. 写入 `PkgInfo`。
5. 始终 `codesign --identifier com.jinzhuming.shot`；有 Developer ID / Apple Development 时用证书签，避免 ad-hoc。`CONFIG=release` 再加 `--timestamp`。
6. 打印 bundle id、签名身份与 designated requirement，便于核对 TCC。
