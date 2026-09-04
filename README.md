# Shot

macOS 菜单栏截图工具。用全局快捷键或状态菜单框选区域、点选窗口、截取全屏，然后标注、复制或保存。

## 要求

- macOS 15 或更高
- 屏幕录制权限（「系统设置 → 隐私与安全性 → 屏幕录制」）

第一次截取其他窗口内容前，Shot 会说明用途再请求权限。授权后 macOS 通常要求完全退出并重新打开应用后才生效。

## 构建

```bash
make app
open Shot.app
```

`make app` 使用 Swift Package Manager 编译，再由 `scripts/package-app.sh` 打成 `Shot.app`。包名固定为 `com.jinzhuming.shot`；本机有 Developer ID 时用该证书签名，屏幕录制权限在重打包后仍然有效。

## 录屏

从状态菜单或录屏快捷键进入录屏选择界面，可以拖拽区域、点选窗口或选择全屏。选定目标后立即开始录制，再次按录屏快捷键或从状态菜单停止。

录屏首版保存为 H.264 MP4，不包含系统音频或麦克风。录制完成后会在当前屏幕左下角显示悬浮视频窗口，可播放、复制视频文件或另存到其他位置。

测试：

```bash
swift test
```

Xcode 工程可由 `make generate`（XcodeGen）生成，含 App Icon 的 Asset catalog。日常打包以 `make app` 为准，图标来自 `Support/Shot.icns`。

## 快捷键

默认 All-in-One 为 **⌘⇧A**，录屏为 **⌘⇧6**，截图默认保存到 `~/Downloads`。不会注册系统截图快捷键 ⌘⇧3 / ⌘⇧4 / ⌘⇧5。

若快捷键被占用，设置里会显示「未生效」，状态菜单也不会展示该键。

## 分发

本机 `make app` 的 ad-hoc 签名只给开发者自己用。把包交给别人之前，需要 Developer ID 签名和公证（Hardened Runtime）。不要为此关闭 Gatekeeper。
