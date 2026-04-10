# VlogClaw Studio Run Guide

本文说明如何在本地开发环境和部署场景下运行 `VlogClawStudio` 与 Go backend。默认方案是把 backend 和 `sib` 一起打进 `VlogClawStudio.app`，而不是依赖外部路径。

## 1. 环境准备

需要以下组件：

- macOS 14+
- Xcode 16+
- Go 1.25+
- CocoaPods
- `sib` / `sonic-ios-bridge`
- 真机可被 `sib devices -d` 识别

构建 `backend/bin/vlogclaw` 时，脚本会把 `sib` 一起复制到产物目录的 `plugins/sonic-ios-bridge`。默认查找顺序如下：

1. `SIB_SOURCE_PATH`
2. `SIB_PATH`
3. `PATH` 中的 `sib` 或 `sonic-ios-bridge`

backend 运行时的发现顺序则更简单：

1. `SIB_PATH`
2. backend binary 邻近的 `plugins/sonic-ios-bridge`
3. `PATH` 中的 `sib` 或 `sonic-ios-bridge`
4. 系统常见安装路径

如果你准备复用其他项目里的 binary，现在应由构建脚本把它复制进 backend 产物，而不是依赖运行时去外部项目找。

如果 iOS 17+ 真机需要启动 WDA，还需要先准备：

```bash
# 在仓库根目录执行
cd VlogClawAgent
pod install
```

## 2. 构建 Go backend 独立二进制

在仓库根目录执行：

```bash
./VlogClawStudio/scripts/build-backend.sh
```

默认会产出：

```text
backend/bin/vlogclaw
```

同时会产出：

```text
backend/bin/plugins/sonic-ios-bridge
```

也可以自定义输出路径：

```bash
./VlogClawStudio/scripts/build-backend.sh /custom/path/vlogclaw
```

## 3. 配置运行时环境变量

最少需要：

```bash
export OPENAI_API_KEY=your_key
```

常用可选变量：

```bash
export OPENAI_MODEL=gpt-4o
export CLAUDE_API_KEY=your_key
export SIB_PATH=/absolute/path/to/sonic-ios-bridge
export SIB_SOURCE_PATH=/absolute/path/to/sonic-ios-bridge
export WDA_XCODE_WORKSPACE_PATH=$(pwd)/VlogClawAgent/VlogClawAgent.xcworkspace
export VLOGCLAW_BACKEND_BINARY=$(pwd)/backend/bin/vlogclaw
export SERVER_PORT=8080
```

说明：

- `VLOGCLAW_BACKEND_BINARY` 是可选覆盖项；不设置时，macOS App 会优先从 `.app/Contents/Resources/Backend/vlogclaw` 启动内嵌 backend
- `SIB_SOURCE_PATH` 只在构建 backend 时使用，指定要打包进去的 `sib`
- `SIB_PATH` 供运行时显式指定 `sib` binary；若不设置，backend 会优先使用产物目录自带的 `plugins/sonic-ios-bridge`
- `WDA_XCODE_WORKSPACE_PATH` 建议显式设置，避免 App 从非仓库目录启动时找不到 workspace
- `OPENAI_API_KEY` 只影响文案生成，不影响 backend `/health` 与设备发现

## 4. 生成并打开 Xcode 工程

```bash
# 在仓库根目录执行
cd VlogClawStudio
xcodegen generate
open VlogClawStudio.xcodeproj
```

生成后使用 scheme `VlogClawStudio`。

## 5. 在 Xcode 中运行 App

建议在 Scheme 的 Run 环境变量中配置：

- `OPENAI_API_KEY`
- `WDA_XCODE_WORKSPACE_PATH`

如果你之前给 Scheme 配过 `VLOGCLAW_BACKEND_BINARY`，现在建议删除，让 App 直接使用 bundle 内自带的 backend。

启动后流程如下：

1. App 启动时尝试拉起 bundle 内的 backend；如果设置了 `VLOGCLAW_BACKEND_BINARY`，则使用覆盖路径
2. 后端监听 `SERVER_PORT`，默认 `8080`
3. 左栏显示真机列表
4. 点击 `Connect Device` 启动对应真机的 WDA
5. 中栏通过 MJPEG 预览真机画面
6. 右栏生成小红书文案并投递自动化任务

## 6. 纯命令行运行

如果不通过 Xcode，也可以先单独运行 backend：

```bash
# 在仓库根目录执行
cd backend
OPENAI_API_KEY=your_key ./bin/vlogclaw
```

然后在另一个终端运行 Swift Package 版本：

```bash
# 在仓库根目录执行
cd VlogClawStudio
swift run
```

## 7. 常见遗漏排查

如果 App 启动后仍然无法正常工作，优先检查这几项：

- `curl http://127.0.0.1:8080/health` 应返回 `{"status":"ok"}`；否则说明 backend 没有成功启动
- `sib devices -d` 或 `SIB_PATH=/path/to/sonic-ios-bridge /path/to/sonic-ios-bridge devices -d` 必须能看到真机
- `backend/bin/plugins/sonic-ios-bridge` 应存在且可执行；如果没有，重新执行 `./VlogClawStudio/scripts/build-backend.sh`
- `VlogClawAgent/VlogClawAgent.xcworkspace` 必须存在；如果不存在，先执行 `cd VlogClawAgent && pod install`
- `OPENAI_API_KEY` 未设置时，右侧 Xiaohongshu 文案生成会失败，但不会影响 backend 启动
- 如果 `8080` 已被其他服务占用，修改 `SERVER_PORT`，并在 App 中保持 Backend URL 一致

## 8. 部署建议

当前推荐的部署方式：

1. 先构建 `backend/bin/vlogclaw`
2. 用 Xcode Archive 构建 `VlogClawStudio.app`
3. 直接分发 `VlogClawStudio.app`；backend 和 `sib` 已随 app 一起打包
4. 通过启动器脚本或 LaunchAgent 为 App 注入：
   - `OPENAI_API_KEY`
   - `WDA_XCODE_WORKSPACE_PATH`

后续如果要做正式分发，建议进一步补：

- App 首选项界面化，替代依赖环境变量
- 更稳定的日志查看与重启策略