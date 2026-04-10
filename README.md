# VlogClaw

智能 iOS UI 自动化框架，结合端侧 LLM（MLX/Gemma 4）与远端 LLM（OpenAI/Claude）实现屏幕截图分析和自主应用操作。基于 WebDriverAgent 扩展，提供 LLM 驱动的 agent 循环能力。

## 特性

- **端侧推理**：通过 MLX 框架在 Metal GPU 上运行 Gemma 4 模型，支持文本、图像、音频多模态输入
- **远端 LLM 集成**：支持 OpenAI 和 Claude API，用于复杂任务规划与内容生成
- **Agent 自动化**：截图 → LLM 分析 → 执行操作的自主循环
- **HTTP API**：通过 WebDriverAgent 暴露 REST 接口，便于外部调用

## 环境要求

- macOS 14.0+
- Xcode 15.0+
- iOS 17.0+（目标设备）
- CocoaPods
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（可选，修改 project.yml 时需要）
- `sib` / `sonic-ios-bridge`

## 构建

```bash
cd VlogClawAgent

# 安装依赖
pod install

# 打开 workspace
open VlogClawAgent.xcworkspace

# 或使用命令行构建
xcodebuild -workspace VlogClawAgent.xcworkspace \
  -scheme VlogClawAgentLib \
  -destination 'generic/platform=iOS' \
  build
```

如修改了 `project.yml`，需重新生成 Xcode 工程：

```bash
xcodegen generate
```

## macOS 控制台

仓库新增 `VlogClawStudio/`，这是一个 SwiftUI macOS MVP 控制台，用于：

- 浏览后端发现的 iPhone 真机和连接状态
- 点击连接后，直接通过 `WKWebView` 加载 WDA 的 MJPEG 流，实时查看真机画面
- 在右侧 LLM 工作台里根据描述和参考图生成小红书图文文案
- 将生成后的标题、正文、选图提示提交给小红书自动化工作流

运行：

```bash
cd VlogClawStudio
swift run
```

补充说明：

- App 会 spawn `backend/bin/vlogclaw`，backend 启动后再由它发现真机和启动 WDA
- `./VlogClawStudio/scripts/build-backend.sh` 会把 `sib` 一起复制到 `backend/bin/plugins/sonic-ios-bridge`
- 若未显式设置 `SIB_PATH`，backend 会优先使用产物目录自带的 `plugins/sonic-ios-bridge`，再回退到 `PATH` 和系统安装路径
- 右侧小红书文案生成功能需要 `OPENAI_API_KEY`

## 架构

```
HTTP API 层 (WebDriverAgent 路由)
    ↓
Swift/ObjC 桥接层 (VCLLMBridge)
    ↓
Agent 层 (AutomationAgent)
    ↓
LLM 服务层 (MLXLocalLLMService / RemoteLLMService)
    ↓
模型层 (Gemma 4 / OpenAI / Claude)
```

### 模块说明

| 模块 | 说明 |
|------|------|
| **Bridge** | Swift/ObjC 互操作桥接，单例模式，WDA ObjC 层通过此处调用所有 Swift 能力 |
| **LLM** | 本地 LLM 推理服务，管理 Gemma 4 模型加载、内存预算、分块预填充 |
| **RemoteLLM** | 远端 LLM 抽象层，支持 OpenAI 和 Claude 提供方 |
| **Agent** | 自动化编排器，包含截图分析、动作解析、工作流规划、内容生成等子模块 |
| **WebDriverAgent** | 扩展的 WDA 框架，新增 LLM 和 Agent 相关的 HTTP 路由 |

### 数据流

1. 外部请求到达 WDA 路由（如 `/agent/execute`）
2. `VCLLMBridge` 路由至 `AutomationAgent`
3. Agent 截取屏幕截图，发送给 LLM 进行分析
4. `ActionParser` 解析 LLM 响应中的结构化动作
5. 通过 XCTest UI API 执行动作（点击、输入、滑动等）
6. 循环重复直至目标完成或达到最大步数

## HTTP API

### LLM 相关

- `POST /llm/load` — 加载本地模型
- `POST /llm/remote/configure` — 配置远端 LLM 提供方

### Agent 相关

- `POST /agent/analyze` — 分析当前屏幕截图
- `POST /agent/execute` — 执行 agent 自动化循环

### 后端工作流 API

- `POST /api/v1/tasks` — 通用截图驱动自动化任务
- `POST /api/v1/workflows/xiaohongshu/copy` — 根据描述和参考图生成小红书图文文案
- `POST /api/v1/workflows/xiaohongshu/posts` — 小红书图文发布任务

小红书图文发布请求示例：

```json
{
  "model": "openai",
  "title": "春季通勤穿搭",
  "body": "今天分享一套适合上班的轻通勤穿搭。",
  "image_count": 3,
  "image_selection_hint": "选择设备相册里最新的三张穿搭图片",
  "publish_mode": "publish",
  "max_steps": 60
}
```

说明：

- 默认会启动小红书 `com.xingin.discover`
- `image_count` 和 `image_selection_hint` 用于指导 agent 在设备相册中选择图片
- 当前流程假设待发布图片已经存在于真机相册中

### 设备 API

- `GET /api/v1/devices` — 返回在线设备及当前连接状态
- 连接成功后，响应里会包含 `wda_url`、`mjpeg_port` 和 `mjpeg_url`，供桌面端实时预览使用

## 依赖

- **CocoaPods**：Yams (~> 5.0)
- **Swift Packages**：MLX Swift (v0.31.3)、Swift Syntax
- **系统框架**：XCTest（弱链接）、libxml2

## 许可证

私有项目，未公开授权。
