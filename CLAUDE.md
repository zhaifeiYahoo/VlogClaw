# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库中工作时提供指导。

## 项目概述

VlogClaw 是一个 iOS UI 自动化框架，利用 LLM（本地端侧 MLX/Gemma 4 推理 + 远端 OpenAI/Claude API）分析屏幕截图并自主操作 iOS 应用。它扩展了 WebDriverAgent，新增了 LLM 驱动的 agent 循环相关 HTTP 路由。

## 构建与开发

```bash
cd VlogClawAgent

# 安装 CocoaPods 依赖
pod install

# 打开 workspace（不是 .xcodeproj）
open VlogClawAgent.xcworkspace

# 命令行构建
xcodebuild -workspace VlogClawAgent.xcworkspace -scheme VlogClawAgentLib -destination 'generic/platform=iOS' build
xcodebuild -workspace VlogClawAgent.xcworkspace -scheme VlogClawAgentRunner -destination 'generic/platform=iOS' build
```

项目使用 `project.yml`（XcodeGen 规范）生成 Xcode 工程。修改 `project.yml` 后需执行 `xcodegen generate` 重新生成。

## 架构

两个 target：
- **VlogClawAgentLib**（framework）— 全部核心逻辑，编译为 `WebDriverAgentLib` 模块
- **VlogClawAgentRunner**（UI testing bundle）— 轻量入口，启动 WDA 服务器

### 源码结构（`VlogClawAgent/VlogClawAgent/`）

| 目录 | 职责 |
|------|------|
| `Bridge/` | `VCLLMBridge` — 单例，将 Swift async API 桥接给 ObjC WDA 命令处理器 |
| `Lib/LLM/MLX/` | 基于 MLX（Metal GPU）的端侧推理。`MLXLocalLLMService` 管理 Gemma 4 模型加载、内存预算和分块预填充 |
| `Lib/RemoteLLM/` | 云端 LLM 提供方（`OpenAIProvider`、`ClaudeProvider`），遵循 `LLMProvider` 协议，由 `LLMProviderFactory` 创建 |
| `Lib/Agent/` | `AutomationAgent` 编排"截图→分析→执行"循环。还包含 `WorkflowPlanner`、`InstructionParser`、`ContentGenerator`、`ActionParser` |
| `Lib/WebDriverAgent/` | 扩展的 WDA，新增自定义 HTTP 路由（`/llm/*`、`/agent/*`）和截图捕获 |
| `Runner/` | XCTest bundle 入口，启动 WDA HTTP 服务器 |

### 数据流

1. HTTP 请求到达 WDA 路由（如 `/agent/execute`）
2. `VCLLMBridge`（ObjC→Swift 桥接）路由至 `AutomationAgent`
3. Agent 截取屏幕截图，发送给 LLM（本地 MLX 或远端提供方）
4. `ActionParser` 从 LLM 响应中解析结构化动作
5. 通过 XCTest UI API 执行动作
6. 循环重复直至目标完成或达到最大步数

### 关键模式

- 本地 LLM 使用分块预填充（256 tokens）以避免 iOS 上 OOM，并根据可用内存空间动态调整历史深度
- `PRODUCT_MODULE_NAME` 为 `WebDriverAgentLib` — Swift 中应 import 此模块名，而非 "VlogClawAgentLib"
- WDA ObjC 代码通过 `VCLLMBridge` 单例统一调用 Swift 层
- 远端 LLM 提供方采用工厂 + 协议模式（`LLMProvider` 协议）
- 不同模型配置（Gemma 4 E2B/E4B）有各自独立的运行时预算配置

## 依赖

- **CocoaPods**：Yams (~> 5.0)
- **Swift Packages**：MLX Swift (v0.31.3，本地副本位于 `Packages/InferenceKit`)、Swift Syntax
- **系统框架**：XCTest（弱链接）、libxml2
- 部署目标：iOS 17.0，Swift 5.9
