# VlogClawStudio

macOS SwiftUI MVP，用来给 VlogClaw 提供一个桌面控制台：

- 左侧列出当前连接的 iPhone 真机和 WDA / MJPEG 信息
- 中间通过 `WKWebView` 直接加载 WDA 的 MJPEG 流，实时查看真机画面
- 右侧提供 LLM 对话式的小红书工作台，支持根据描述和参考图生成文案，并将任务投递给后端自动化流程

## 运行

```bash
cd VlogClawStudio
swift run
```

默认后端地址是 `http://127.0.0.1:8080`。通过 Xcode 构建 `VlogClawStudio.app` 时，会自动把 Go backend 和 `sib` 打进 `.app/Contents/Resources/Backend/`，运行时默认从 app bundle 内启动，不需要再手填外部 binary 路径。

建议先执行：

```bash
# 在仓库根目录执行
./VlogClawStudio/scripts/build-backend.sh
```

这会同时生成：

- `backend/bin/vlogclaw`
- `backend/bin/plugins/sonic-ios-bridge`

如果你使用的是 `swift run`，仍然建议先执行上面的脚本，或者手动启动仓库里的 backend。
