#!/bin/bash
# startservice.sh — Codespace 启动脚本（主机模式）
# 每次打开 Codespace 时自动安装 + 启动服务

[[ -n "$_START_SERVICES_LOADED" ]] && return 0
_START_SERVICES_LOADED=1

echo "========================================="
echo " FreeCloudCode — Setting up..."
echo "========================================="

# ===== 1. 系统依赖 =====
echo "⟳ 检查系统依赖..."
sudo apt-get update -qq && sudo apt-get install -y -qq tmux curl wget jq > /dev/null 2>&1
echo "✓ 系统依赖已就绪"

# ===== 2. Tailscale =====
if ! command -v tailscale &>/dev/null; then
    echo "⟳ 安装 Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "✓ Tailscale 已安装"
else
    echo "✓ Tailscale 已存在 ($(tailscale version | head -1))"
fi

# ===== 3. Claude Code（独立二进制，非 npm） =====
if ! command -v claude &>/dev/null; then
    echo "⟳ 安装 Claude Code..."
    mkdir -p ~/.local/share/claude/versions ~/.local/bin
    CLAUDE_URL="https://storage.googleapis.com/anthropic-cli-releases/latest/claude-linux-x64"
    curl -fsSL "$CLAUDE_URL" -o ~/.local/bin/claude 2>/dev/null || {
        # 备用：尝试 npm 方式
        npm install -g @anthropic-ai/claude-code 2>/dev/null && echo "✓ Claude Code 已安装 (npm)" || echo "✗ Claude Code 安装失败"
    }
    if [ -f ~/.local/bin/claude ]; then
        chmod +x ~/.local/bin/claude
        echo "✓ Claude Code 已安装"
    fi
else
    echo "✓ Claude Code 已存在"
fi

# ===== 4. npm 全局工具（正确包名） =====
echo "⟳ 检查 npm 工具..."
NPM_PACKAGES=(
    "omniroute"
    "@cloudcli-ai/cloudcli"
    "@openai/codex"
    "@ccpocket/bridge"
)
NEED_INSTALL=false
for pkg in "${NPM_PACKAGES[@]}"; do
    if ! npm list -g "$pkg" &>/dev/null; then
        NEED_INSTALL=true
        break
    fi
done

if [ "$NEED_INSTALL" = true ]; then
    echo "⟳ 安装全局 npm 工具（首次约 1-2 分钟）..."
    for pkg in "${NPM_PACKAGES[@]}"; do
        echo "   → $pkg"
        npm install -g "$pkg" 2>&1 | tail -1
    done
    echo "✓ npm 工具安装完成"
else
    echo "✓ npm 工具已存在"
fi

# ===== 5. 配置 .bashrc =====
BASHRC="$HOME/.bashrc"
MARKER="# >>> FreeCloudCode >>>"

if ! grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "$MARKER" >> "$BASHRC"
    echo "alias cc='claude'" >> "$BASHRC"
    echo "alias codex='openai-codex'" >> "$BASHRC"
    echo "alias oc='omniroute'" >> "$BASHRC"
    echo "alias ccli='cloudcli'" >> "$BASHRC"
    echo "alias pocket='ccpocket-bridge'" >> "$BASHRC"
    echo "alias cr='CLAUDE_CODE_ENTRYPOINT=sdk-cli claude -r'" >> "$BASHRC"
    echo 'echo "🌊 FreeCloudCode ready! cc/codex/oc/ccli/pocket"' >> "$BASHRC"
    echo "# <<< FreeCloudCode <<<" >> "$BASHRC"
    echo "✅ Bashrc 已配置（新终端生效）"
fi

# ===== 6. 启动 Tailscale =====
if ! pgrep -f "tailscaled" > /dev/null 2>&1; then
    echo "⟳ 启动 tailscaled..."
    nohup sudo tailscaled --tun=userspace-networking </dev/null > /tmp/tailscaled.log 2>&1 &
    disown
    sleep 2
    pgrep -f "tailscaled" > /dev/null 2>&1 && echo "✓ tailscaled 启动成功" || echo "✗ tailscaled 启动失败"
else
    echo "✓ tailscaled 已在运行"
fi

# ===== 7. tmux 服务管理 =====
_tmux_run() {
    local name="$1" proc="$2" cmd="$3" label="$4" port="$5"
    if tmux has-session -t "$name" 2>/dev/null; then
        echo "✓ $label session 已存在"
    elif pgrep -f "$proc" > /dev/null 2>&1; then
        echo "✓ $label 已在运行"
    elif [ -n "$port" ] && (ss -tlnp 2>/dev/null | grep -q ":${port} "); then
        echo "⚠ $label 端口 ${port} 已被占用，跳过"
    else
        echo "⟳ 启动 $label..."
        tmux new-session -d -s "$name" "bash -c '$cmd 2>&1 | tee /tmp/${name}.log; sleep infinity'"
        sleep 2
        pgrep -f "$proc" > /dev/null 2>&1 && echo "✓ $label 启动成功" || echo "✗ $label 启动失败"
    fi
}

# ===== 8. 自动启动 OmniRoute + CloudCLI =====
_tmux_run omniroute "omniroute" "omniroute" "OmniRoute"
_tmux_run cloudcli  "cloudcli"  "cloudcli"  "CloudCLI" 3001

# ===== 手动启动命令 =====
cc()  { _tmux_run cloudcli "cloudcli" "cloudcli" "CloudCLI"; }
xcc() { tmux kill-session -t cloudcli 2>/dev/null; pkill -f cloudcli 2>/dev/null; echo "✓ CloudCLI 已停止"; }
cp()  { _tmux_run bridge "@ccpocket/bridge" "ccpocket-bridge" "CC Pocket Bridge"; }
xcp() { tmux kill-session -t bridge 2>/dev/null; pkill -f "ccpocket-bridge" 2>/dev/null; echo "✓ Bridge 已停止"; }

echo ""
echo "📌 可用命令:"
echo "  cc  — 启动 CloudCLI   xcc — 停止"
echo "  cp  — 启动 Bridge     xcp — 停止"
echo "  cr  — 重连 Claude 会话"
echo ""
