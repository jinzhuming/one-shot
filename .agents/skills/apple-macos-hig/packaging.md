# macOS 打包与基础工程化

官方：

- [Information Property List](https://developer.apple.com/documentation/bundleresources/information_property_list)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## 当前工程形态

- 源码：`Sources/Shot`，Swift 5，macOS 15+。
- 双入口：`Package.swift`（`swift build`）+ `project.yml`（XcodeGen → `Shot.xcodeproj`）。
- 日常：`make app` → `swift build` + `scripts/package-app.sh` → `Shot.app`。
- 不要再引入第三套构建系统。改配置时 **同时** 改 `Package.swift` 与 `project.yml`。

## Info.plist 硬规则

`Support/Info.plist` 是同时供 Xcode 使用的模板，可以含 `$(PRODUCT_BUNDLE_IDENTIFIER)` 等宏。`package-app.sh` **禁止**将模板原样拷进 `Shot.app`，必须先写入展开后的值。TCC 屏幕录制权限绑定真实 bundle id；宏未展开等于没有身份。

打包脚本必须写出已展开的 plist，至少包含：

- `CFBundleIdentifier` = `com.jinzhuming.shot`
- `CFBundleName` / `CFBundleDisplayName` = `Shot`
- `CFBundleExecutable` = `Shot`
- `CFBundlePackageType` = `APPL`
- `CFBundleShortVersionString` 与 `MARKETING_VERSION` **同一来源**，目前均为 `0.1.0`
- `CFBundleVersion` 每次分发递增
- `LSUIElement` = `true`（菜单栏应用，避免启动时闪 Dock）
- `LSMinimumSystemVersion` = `15.0`
- `NSHighResolutionCapable` = `true`
- `NSSupportsAutomaticTermination` / `NSSupportsSuddenTermination` 对常驻热键工具设为 `false`
- `CFBundleIconFile` = `Shot`，`CFBundleIconName` = `AppIcon`
- 开发语言：`zh-Hans`

`Support/Shot.xcconfig` 是 Bundle ID、营销版本和构建号的唯一来源。`project.yml` 通过 `configFiles` 引用它；`Support/Info.plist` 只保留 Xcode 模板宏。改版本号只改 xcconfig，然后运行 `make generate` 和 `make verify`。

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

本地日常包也要固定身份：`CFBundleIdentifier` 与 `codesign --identifier` 必须是 `com.jinzhuming.shot`。Debug 允许 Ad-hoc 签名；Release 必须使用 Developer ID Application，不能用 Apple Development 或 `-` 代替。Ad-hoc（`-`）的 designated requirement 是每次变化的 CDHash，TCC 屏幕录制会当成新 App。**任何离开本机的包**：

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
- 单一来源：`Support/Shot.xcconfig`；`project.yml` 和 `package-app.sh` 都读它，禁止 Info.plist 手写另一套。

## 推荐工程约束

- 最低系统跟 `Package.swift` platforms 与 `project.yml` `deploymentTarget` 锁死，改一处必须改另一处。
- Swift 语言模式保持显式（现在 tools 6.0 + language mode v5）；升 Swift 6 并发检查要单独做，不要夹在 UI 改动里。
- 捕获继续用 ScreenCaptureKit，不要退回 `CGDisplayCreateImage` / `CGWindowListCreateImage`。
- 新增权限、URL scheme、文件类型关联时，先改 plist + entitlements，再写代码。
- 可测试逻辑放 `ShotKit`，改动后跑 `swift test`。至少覆盖：坐标换算、热键编解码、导出文件名。
- `make clean` 可删 `.build`、`Shot.app`、`Shot.xcodeproj`；不要删 `Sources/`、`Support/`、`scripts/`。
- 图标用 `make icon`（`scripts/generate-icon.swift`）生成 `Support/Shot.icns` 与 `Support/Assets.xcassets`。

## package-app.sh 必须做的事

1. 确认二进制和 SwiftPM 资源包存在。
2. 从模板写出 **展开后** 的 Info.plist（禁止把含 `$()` 的 `Support/Info.plist` 原样留在 app 中）。
3. 拷贝 Resources（图标、隐私清单、lproj）。
4. 写入 `PkgInfo`。
5. 始终 `codesign --identifier com.jinzhuming.shot`；Debug 可使用 ad-hoc，Release 必须是 Developer ID Application。`CONFIG=release` 再加 `--timestamp`。
6. 打印 bundle id、签名身份与 designated requirement，便于核对 TCC。

## 工程校验

- 不得手改生成的 `Shot.xcodeproj`；改 `project.yml` 后运行 `make generate`。
- 资源必须显式进入 XcodeGen 的 resources build phase；SwiftPM 的 `Shot_Shot.bundle` 必须复制到最终 app 并参与签名。
- 每次改构建、资源、权限或 plist，运行 `make verify`；它会校验源码引用、版本、bundle id、资源、宏和签名。
