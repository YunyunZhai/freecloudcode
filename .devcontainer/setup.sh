#!/bin/bash
# setup.sh — FreeCloudCode 一次性安装配置
# 由 devcontainer.json 的 onCreateCommand 触发，仅首次创建 Codespace 时运行

SETUP_MARKER="$HOME/.freecloudcode.setup.done"

# 幂等检查：只执行一次
if [ -f "$SETUP_MARKER" ]; then
    echo "✓ FreeCloudCode 已初始化，跳过 setup"
    exit 0
fi

# 确保目录存在（日志要写文件）
mkdir -p "$HOME/.freecloudcode/logs"

# 日志同时输出到终端和文件
SETUP_LOG="$HOME/.freecloudcode/logs/setup.log"
exec > >(tee "$SETUP_LOG") 2>&1

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

# 启动 tailscaled 并认证
if command -v tailscale &>/dev/null; then
    # 确保 tailscaled 守护进程运行
    if ! pgrep -x tailscaled >/dev/null 2>&1; then
        nohup sudo tailscaled </dev/null > /tmp/tailscaled-setup.log 2>&1 &
        disown
        sleep 3
    fi

    # 检查是否已认证（非交互式脚本，只能用 authkey 认证）
    if sudo tailscale status >/dev/null 2>&1; then
        echo "✓ Tailscale 已认证连接"
    elif [ -n "$TAILSCALEAUTHKEY" ]; then
        echo "⟳ 使用 TAILSCALEAUTHKEY 认证..."
        if sudo tailscale up --ssh --authkey="$TAILSCALEAUTHKEY" 2>/dev/null; then
            echo "✓ Tailscale 认证成功"
        else
            echo "⚠ Tailscale authkey 认证失败"
            FAILED+=("Tailscale 认证: 检查 TAILSCALEAUTHKEY 是否有效")
        fi
    else
        echo "⚠ Tailscale 未认证（非交互式环境无法浏览器认证）"
        echo "  → 设置环境变量 TAILSCALEAUTHKEY 后重新创建容器"
        echo "  → 或在终端手动运行: sudo tailscale up --ssh"
    fi
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
scc()  { tmux new-session -d -s cloudcli "cloudcli 2>&1 | tee ~/.freecloudcode/logs/cloudcli.log; sleep infinity" && echo "✓ CloudCLI 已启动"; }
xcc()  { tmux kill-session -t cloudcli 2>/dev/null; pkill -f cloudcli 2>/dev/null; echo "✓ CloudCLI 已停止"; }
sbp()  { tmux new-session -d -s bridge "ccpocket-bridge 2>&1 | tee ~/.freecloudcode/logs/bridge.log; sleep infinity" && echo "✓ Bridge 已启动"; }
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
        if [[ "$or_code" =~ ^[23] ]]; then
            echo "  ✅ OmniRoute — http://${or_addr}:20128"
        else
            echo "  ❌ OmniRoute — 未运行 (http://${or_addr}:20128)"
        fi
    fi
    # CloudCLI（HTTP 检测）
    local cc_addr="${ts_ip:-localhost}"
    local cc_code
    cc_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "http://${cc_addr}:3001" 2>/dev/null)
    if [[ "$cc_code" =~ ^[23] ]]; then
        echo "  ✅ CloudCLI — http://${cc_addr}:3001"
    else
        echo "  ❌ CloudCLI — 未运行 (http://${cc_addr}:3001)"
    fi
}

# claude-sync 自动同步（未配置则跳过）
if command -v claude-sync &>/dev/null; then
    if claude-sync status -q 2>/dev/null; then
        (claude-sync pull -q && claude-sync push -q) &>/dev/null &
    fi
fi

# 交互式终端才显示状态和命令速查
if [[ $- == *i* ]]; then
    echo ""
    # 显示上次启动状态（如果有）
    _STATUS_FILE="$HOME/.freecloudcode/startup-status.log"
    if [ -f "$_STATUS_FILE" ]; then
        cat "$_STATUS_FILE"
        echo ""
    fi
    # 实时探测服务状态
    _fcc_check_services
    echo ""
    # 显示待配置项（仅影响功能的服务）
    _NEEDS_CONFIG=()
    if command -v claude-sync &>/dev/null && ! claude-sync status -q 2>/dev/null; then
        _NEEDS_CONFIG+=("claude-sync 未配置 → claude-sync init")
    fi
    if [ ${#_NEEDS_CONFIG[@]} -gt 0 ]; then
        echo "⚠️  待配置:"
        for item in "${_NEEDS_CONFIG[@]}"; do
            echo "   $item"
        done
        echo ""
    fi
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

# ===== 5c. Claude Code hooks 配置 =====
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"

# Stop hook: 先检测 claude-sync 是否已配置，未配置则跳过
FCC_SYNC_CMD='if claude-sync status -q 2>/dev/null; then claude-sync pull -q && claude-sync push -q; fi'

# 合并 Stop hook（保留已有配置）
if [ -f "$CLAUDE_SETTINGS" ]; then
    # 已有配置，检查是否已有 Stop hook
    if ! jq -e '.hooks.Stop' "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
        # 没有 Stop hook，追加
        jq --arg cmd "$FCC_SYNC_CMD" '.hooks += {"Stop": [{"hooks": [{"type": "command", "command": $cmd, "timeout": 30, "statusMessage": "claude-sync 同步中..."}]}]}' "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
        echo "✅ Claude Code Stop hook 已配置"
    else
        echo "✅ Claude Code Stop hook 已存在"
    fi
else
    # 不存在，创建
    cat > "$CLAUDE_SETTINGS" << SETTINGS_EOF
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$FCC_SYNC_CMD",
            "timeout": 30,
            "statusMessage": "claude-sync 同步中..."
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
    echo "✅ Claude Code Stop hook 已配置"
fi

# ===== 6. 配置提醒 =====
echo ""
echo "========================================="
echo " 🔧 配置提醒"
echo "========================================="

# Tailscale 认证状态
if command -v tailscale &>/dev/null; then
    if sudo tailscale status >/dev/null 2>&1; then
        echo "  ✅ Tailscale — 已认证"
    else
        echo "  ⚠️  Tailscale — 需要认证"
        echo "     方式1: 设置环境变量 TAILSCALEAUTHKEY 后重新创建容器"
        echo "     方式2: 在终端运行: sudo tailscale up --ssh"
    fi
else
    echo "  ⏭  Tailscale — 未安装"
fi

# OmniRoute 配置
if command -v omniroute &>/dev/null; then
    if [ -f "$HOME/.omniroute/config.yaml" ] || [ -f "$HOME/.omniroute/config.json" ]; then
        echo "  ✅ OmniRoute — 已配置"
    else
        echo "  ⚠️  OmniRoute — 未配置（首次使用需运行: oc）"
    fi
else
    echo "  ⏭  OmniRoute — 未安装"
fi

# claude-sync 配置
if command -v claude-sync &>/dev/null; then
    if [ -f "$HOME/.claude-sync/config.json" ] || [ -d "$HOME/.claude-sync" ] && ls "$HOME/.claude-sync/"*.json >/dev/null 2>&1; then
        echo "  ✅ claude-sync — 已配置"
    else
        echo "  ⚠️  claude-sync — 未配置"
        echo "     首次使用需运行: claude-sync init"
    fi
else
    echo "  ⏭  claude-sync — 未安装"
fi

# ===== 7. 安装检查 =====
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

# 创建 .freecloudcode 目录结构
mkdir -p ~/.freecloudcode/{logs,config}
chmod 755 ~/.freecloudcode
chmod 755 ~/.freecloudcode/logs
chmod 755 ~/.freecloudcode/config

# 初始化日志文件
for logfile in claude_sync tailscale omniroute cloudcli bridge; do
    touch ~/.freecloudcode/logs/"${logfile}.log"
    chmod 644 ~/.freecloudcode/logs/"${logfile}.log"
done

# 写入完成标记，确保下次不重复执行
touch "$SETUP_MARKER"
