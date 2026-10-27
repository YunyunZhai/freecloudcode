# FreeCloudCode

一个预配置的 GitHub Codespace，包含所有你需要的云端开发工具。打开 Codespace，一切就绪。

## 包含工具

| 工具 | 命令 | 别名 |
|------|------|------|
| Claude Code | `claude` | `cc` |
| OpenAI Codex | `codex` | `codex` |
| OpenCode | `opencode` | `oc` |
| OmniRoute | `omniroute` | `or` |
| Orca Server | `orca-ide` | `sorca` / `xorca` |
| Tailscale | `tailscale` | — |

### 可选安装（默认不安装）

| 工具 | 命令 | 安装方式 |
|------|------|---------|
| CloudCLI | `cloudcli` / `ccli` | `npm install -g @cloudcli-ai/cloudcli` |
| CCPocket | `ccpocket` / `pocket` | `npm install -g @ccpocket/bridge` |
| cc-connect | `cc-connect` | `npm install -g cc-connect` |
| claude-sync | `claude-sync` | `npm install -g @tawandotorg/claude-sync` |

## 快速开始

1. 点击 **Code** → **Codespaces** → **Create codespace on main**
2. 首次安装约 2 分钟，安装完成后工具自动就绪
3. 每次打开终端都会自动启动服务

## 服务管理

每次重启后自动启动 Tailscale、**OmniRoute**（daemon）等服务。管理命令：

```
sor   — 启动 OmniRoute      xor   — 停止
sorca — 启动 Orca Server    xorca — 停止
saa   — 启动 AA-Server      xaa   — 停止
cr    — 重连 Claude 会话
```

## 架构说明

```
.devcontainer/
├── devcontainer.json    # Codespace 配置（host 模式，无 Docker）
├── setup.sh             # 一次性安装（首次创建时由 .bashrc 调用）
└── start.sh             # 每次启动（每次打开终端由 .bashrc 调用）

lib/
├── utils.sh             # 通用工具函数（日志、检查、目录操作）
├── install.sh           # 安装函数（系统依赖、工具安装）
├── start.sh             # 启动函数（服务启动、状态追踪）
└── status.sh            # 状态检测函数（HTTP 检查、实时状态）

tests/
├── test_utils.sh        # 测试框架
├── test_utils_functions.sh
├── test_install.sh
├── test_start.sh
└── test_status.sh
```

### 设计原则

1. **模块化**：每个功能封装为独立函数，便于测试和维护
2. **测试驱动**：所有函数都有单元测试，确保可靠性
3. **用户可见**：安装和启动过程在终端显示，可交互
4. **幂等性**：首次安装检测、重复运行安全

## 测试

运行所有测试：

```bash
bash run_tests.sh
```

测试覆盖：
- ✅ 通用工具函数（日志、文件检查、目录创建）
- ✅ 安装函数（依赖安装、配置生成）
- ✅ 启动函数（服务启动、状态报告）
- ✅ 状态检测函数

## 首次配置

```bash
sudo tailscale up --ssh    # Tailscale 认证
oc                         # 按提示配置 OmniRoute API key
```