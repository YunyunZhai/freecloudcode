#!/bin/bash
# setup.sh — FreeCloudCode 一次性安装配置
# 由 devcontainer.json 的 onCreateCommand 触发，仅首次创建 Codespace 时运行

SETUP_MARKER="$HOME/.freecloudcode.setup.done"

# 幂等检查：只执行一次
if [ -f "$SETUP_MARKER" ]; then
    echo "✓ FreeCloudCode 已初始化，跳过 setup"
    exit 0
fi

FAILED=()  # 记录安装失败的项目

echo "========================================="
echo " FreeCloudCode — 初始安装配置"
echo "========================================="

# ===== 1. 系统依赖 =====
echo "⟳ 安装系统依赖..."
if sudo apt-get update -qq && sudo apt-get install -y -qq tmux curl wget jq > /dev/null 2>&1; then
    echo "✓ 系统依赖已就绪"
else
    echo "⚠ 系统依赖安装失败"
    FAILED+=("系统依赖: sudo apt-get install -y tmux curl wget jq")
fi

# ===== 2. Tailscale =====
if ! command -v tailscale &>/dev/null; then
    echo "⟳ 安装 Tailscale..."
    if curl -fsSL https://tailscale.com/install.sh | sh; then
        echo "✓ Tailscale 已安装"
    else
        echo "⚠ Tailscale 安装失败"
        FAILED+=("Tailscale: curl -fsSL https://tailscale.com/install.sh | sh")
    fi
else
    echo "✓ Tailscale 已存在 ($(tailscale version | head -1))"
fi

# ===== 3. Claude Code =====
if ! command -v claude &>/dev/null; then
    echo "⟳ 安装 Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
        echo "✓ Claude Code 已安装"
    else
        echo "⚠ Claude Code 安装失败"
        FAILED+=("Claude Code: curl -fsSL https://claude.ai/install.sh | bash")
    fi
else
    echo "✓ Claude Code 已存在"
fi

# ===== 4. npm 全局工具 =====
echo "⟳ 检查 npm 全局工具..."
NPM_PACKAGES=(
    "omniroute"
    "@cloudcli-ai/cloudcli"
    "@openai/codex"
    "@ccpocket/bridge"
    "claude-sync"
)
for pkg in "${NPM_PACKAGES[@]}"; do
    if ! npm list -g "$pkg" &>/dev/null; then
        echo "⟳ 安装 $pkg..."
        if npm install -g "$pkg" 2>&1 | tail -1; then
            echo "✓ $pkg 已安装"
        else
            echo "⚠ $pkg 安装失败"
            FAILED+=("$pkg: npm install -g $pkg")
        fi
    else
        echo "✓ $pkg 已存在"
    fi
done

# ===== 5. 配置 .bashrc =====
BASHRC="$HOME/.bashrc"
MARKER="# >>> FreeCloudCode >>>"

# 先删除旧配置块（如果存在），再写入新配置
if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    sed -i "/# >>> FreeCloudCode >>>/,/# <<< FreeCloudCode <<</d" "$BASHRC"
fi

cat >> "$BASHRC" << 'BASHRC_BLOCK'

# >>> FreeCloudCode >>>
alias cc='claude'
alias codex='codex'
alias oc='omniroute'
alias ccli='cloudcli'
alias pocket='ccpocket-bridge'
alias cr='CLAUDE_CODE_ENTRYPOINT=sdk-cli claude -r'

# 服务管理函数（写入 bashrc，每个终端可用）
scc()  { tmux new-session -d -s cloudcli "cloudcli 2>&1 | tee /tmp/cloudcli.log; sleep infinity" && echo "✓ CloudCLI 已启动"; }
xcc()  { tmux kill-session -t cloudcli 2>/dev/null; pkill -f cloudcli 2>/dev/null; echo "✓ CloudCLI 已停止"; }
sbp()  { tmux new-session -d -s bridge "ccpocket-bridge 2>&1 | tee /tmp/bridge.log; sleep infinity" && echo "✓ Bridge 已启动"; }
xbp()  { tmux kill-session -t bridge 2>/dev/null; pkill -f "ccpocket-bridge" 2>/dev/null; echo "✓ Bridge 已停止"; }

# claude-sync 自动同步
if command -v claude-sync &>/dev/null; then
    (claude-sync pull -q && claude-sync push -q) &>/dev/null &
fi

echo "🌊 FreeCloudCode ready! cc/codex/oc/ccli/pocket"
# <<< FreeCloudCode <<<
BASHRC_BLOCK
echo "✅ .bashrc 已配置"

# ===== 5b. 配置 .profile（login shell，如 SSH） =====
PROFILE="$HOME/.profile"
PROFILE_MARKER="# >>> FreeCloudCode >>>"

if grep -q "$PROFILE_MARKER" "$PROFILE" 2>/dev/null; then
    sed -i "/# >>> FreeCloudCode >>>/,/# <<< FreeCloudCode <<</d" "$PROFILE"
fi

cat >> "$PROFILE" << 'PROFILE_BLOCK'

# >>> FreeCloudCode >>>
alias cc='claude'
alias codex='codex'
alias oc='omniroute'
alias ccli='cloudcli'
alias pocket='ccpocket-bridge'
alias cr='CLAUDE_CODE_ENTRYPOINT=sdk-cli claude -r'

# claude-sync 自动同步
if command -v claude-sync &>/dev/null; then
    (claude-sync pull -q && claude-sync push -q) &>/dev/null &
fi

echo "🌊 FreeCloudCode ready! cc/codex/oc/ccli/pocket"
# <<< FreeCloudCode <<<
PROFILE_BLOCK
    echo "✅ .profile 已配置（login shell 生效）"
else
    echo "✓ .profile 已配置"
fi

# ===== 6. 安装检查 =====
echo ""
echo "========================================="
echo " 📋 安装检查"
echo "========================================="
MISSING=()
for cmd in tailscale claude omniroute cloudcli codex ccpocket-bridge claude-sync; do
    if command -v "$cmd" &>/dev/null; then
        echo "  ✅ $cmd"
    else
        echo "  ❌ $cmd  — 未找到"
        MISSING+=("$cmd")
    fi
done

# 合并失败列表
ALL_FAILED=("${FAILED[@]}")
for cmd in "${MISSING[@]}"; do
    case "$cmd" in
        tailscale)   ALL_FAILED+=("Tailscale: curl -fsSL https://tailscale.com/install.sh | sh") ;;
        claude)      ALL_FAILED+=("Claude Code: curl -fsSL https://claude.ai/install.sh | bash") ;;
        omniroute)   ALL_FAILED+=("omniroute: npm install -g omniroute") ;;
        cloudcli)    ALL_FAILED+=("cloudcli: npm install -g @cloudcli-ai/cloudcli") ;;
        codex)       ALL_FAILED+=("codex: npm install -g @openai/codex") ;;
        ccpocket-bridge) ALL_FAILED+=("ccpocket-bridge: npm install -g @ccpocket/bridge") ;;
        claude-sync) ALL_FAILED+=("claude-sync: npm install -g claude-sync") ;;
    esac
done

# 去重
declare -A SEEN
UNIQUE_FAILED=()
for item in "${ALL_FAILED[@]}"; do
    if [ -z "${SEEN[$item]+x}" ]; then
        SEEN[$item]=1
        UNIQUE_FAILED+=("$item")
    fi
done

echo ""
if [ ${#UNIQUE_FAILED[@]} -eq 0 ]; then
    echo "✅ 所有工具安装成功！"
else
    echo "⚠️  以下工具安装失败，请手动执行："
    echo ""
    for item in "${UNIQUE_FAILED[@]}"; do
        echo "  $item"
    done
fi

# 写入完成标记，确保下次不重复执行
touch "$SETUP_MARKER"
