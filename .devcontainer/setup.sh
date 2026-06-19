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
    "@tawandotorg/claude-sync"
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
# 防止重复加载（login shell 可能同时有 .profile 和 .bashrc 都 source）
if [ -z "$_FCC_LOADED" ]; then
export _FCC_LOADED=1

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
xor()  {
    # 优先尝试 omniroute 自带的停止命令
    if omniroute stop 2>/dev/null; then
        echo "✓ OmniRoute 已停止"
        return
    fi
    # 尝试读取 PID 文件精确杀死 daemon
    local pidfile="$HOME/.omniroute/omniroute.pid"
    if [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null; then
        echo "✓ OmniRoute 已停止 (PID: $(cat "$pidfile"))"
        rm -f "$pidfile"
        return
    fi
    # 兜底：精确匹配 daemon 进程（不误杀交互式 omniroute）
    local pid
    pid=$(pgrep -f "omniroute.*serve.*--daemon" 2>/dev/null | head -1)
    if [ -n "$pid" ] && kill "$pid" 2>/dev/null; then
        echo "✓ OmniRoute 已停止 (PID: $pid)"
    else
        echo "⚠ OmniRoute 未运行或停止失败"
    fi
}

# 实时检查服务运行状态
_fcc_check_services() {
    local ts_ip=""

    # 获取 Tailscale IP（用于其他服务的地址）
    if command -v tailscale &>/dev/null; then
        ts_ip=$(tailscale ip -4 2>/dev/null)
    fi

    echo "📋 服务状态:"
    # Tailscale
    if command -v tailscale &>/dev/null; then
        if pgrep -x tailscaled >/dev/null 2>&1; then
            if sudo tailscale status >/dev/null 2>&1; then
                echo "  ✅ Tailscale — ${ts_ip:-已连接}"
            else
                echo "  ⚠️  Tailscale — 守护进程运行但未认证"
            fi
        else
            echo "  ❌ Tailscale — 未运行"
        fi
    fi
    # OmniRoute（HTTP 检测）
    if command -v omniroute &>/dev/null; then
        local or_addr="${ts_ip:-localhost}"
        local or_code
        or_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "http://${or_addr}:20128" 2>/dev/null)
        if [[ "$or_code" =~ ^(200|301|302|304)$ ]]; then
            echo "  ✅ OmniRoute — http://${or_addr}:20128"
        else
            echo "  ❌ OmniRoute — 未运行 (http://${or_addr}:20128)"
        fi
    fi
    # CloudCLI（HTTP 检测）
    local cc_addr="${ts_ip:-localhost}"
    local cc_code
    cc_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "http://${cc_addr}:3001" 2>/dev/null)
    if [[ "$cc_code" =~ ^(200|301|302|304)$ ]]; then
        echo "  ✅ CloudCLI — http://${cc_addr}:3001"
    else
        echo "  ❌ CloudCLI — 未运行 (http://${cc_addr}:3001)"
    fi
}

# claude-sync 自动同步
if command -v claude-sync &>/dev/null; then
    (claude-sync pull -q && claude-sync push -q) &>/dev/null &
fi

# 交互式终端才显示状态和命令速查
if [[ $- == *i* ]]; then
    echo ""
    _fcc_check_services
    echo ""
    echo "📌 命令: cc(claude) codex oc(omniroute) ccli(cloudcli) pocket(bridge) cr(重连)"
    echo "   服务: scc/xcc(CloudCLI) sbp/xbp(Bridge) xor(OmniRoute)"
    echo ""
fi

fi  # _FCC_LOADED guard
# <<< FreeCloudCode <<<
BASHRC_BLOCK
echo "✅ .bashrc 已配置"

# ===== 5b. 配置 .profile（login shell，如 SSH） =====
PROFILE="$HOME/.profile"
PROFILE_MARKER="# >>> FreeCloudCode >>>"

# 先清理旧的 FreeCloudCode .profile 块
if grep -q "$PROFILE_MARKER" "$PROFILE" 2>/dev/null; then
    sed -i "/# >>> FreeCloudCode >>>/,/# <<< FreeCloudCode <<</d" "$PROFILE"
fi

# 注意：Ubuntu 默认 .profile 已经会 source .bashrc，不需要重复添加
# 如果 .profile 中没有 source .bashrc 的逻辑，才添加
if ! grep -q '\.bashrc' "$PROFILE" 2>/dev/null || grep -q "$PROFILE_MARKER" "$PROFILE" 2>/dev/null; then
    cat >> "$PROFILE" << 'PROFILE_BLOCK'

# >>> FreeCloudCode >>>
# Login shell 需要手动 source .bashrc（别名和服务管理函数在 .bashrc 中定义）
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
# <<< FreeCloudCode <<<
PROFILE_BLOCK
    echo "✅ .profile 已配置（login shell 生效）"
else
    echo "✅ .profile 已有 .bashrc source，跳过"
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
        claude-sync) ALL_FAILED+=("claude-sync: npm install -g @tawandotorg/claude-sync") ;;
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
