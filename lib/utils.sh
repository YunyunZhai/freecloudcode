#!/bin/bash
# lib/utils.sh — FreeCloudCode 共享工具函数

# ===== 常量 =====
SETUP_MARKER="$HOME/.freecloudcode.setup.done"
STARTUP_MARKER="$HOME/.freecloudcode/startup-done"
LOG_DIR="$HOME/.freecloudcode/logs"

# ===== 日志函数（输出到 stderr，避免污染 $() 捕获） =====
log_success() { echo "✅ $1" >&2; }
log_warn()    { echo "⚠️  $1" >&2; }

# ===== 基础检查 =====
check_command() { command -v "$1" &>/dev/null; }
ensure_dir()    { mkdir -p "$1"; }

# ===== HTTP 检查 =====
# http_check URL [timeout] — 单次 HTTP 检查
http_check() {
    local url="$1" timeout="${2:-1}"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" --max-time "$timeout" "$url" 2>/dev/null)
    [[ "$code" =~ ^[23] ]]
}

# http_check_retry URL [attempts] [interval] [timeout] — 带重试的 HTTP 检查
http_check_retry() {
    local url="$1" attempts="${2:-2}" interval="${3:-1}" timeout="${4:-1}"
    local i code
    for i in $(seq 1 "$attempts"); do
        code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" --max-time "$timeout" "$url" 2>/dev/null)
        [[ "$code" =~ ^[23] ]] && return 0
        sleep "$interval"
    done
    return 1
}

# ===== 服务运行检测 =====
# is_service_running NAME [cmd] — tmux session 或进程检查
is_service_running() {
    local name="$1" cmd="${2:-$1}"
    tmux has-session -t "$name" 2>/dev/null || pgrep -f "$cmd" >/dev/null 2>&1
}

# ===== tmux 服务管理 =====
# tmux_start NAME CMD LOG_FILE — 启动 tmux 服务
tmux_start() {
    local name="$1" cmd="$2" log_file="$3"

    if is_service_running "$name" "$cmd"; then
        return 0  # 已在运行
    fi

    tmux new-session -d -s "$name" \
        "bash -c '$cmd 2>&1 | tee \"$log_file\"; sleep infinity'"
    sleep 2
    is_service_running "$name" "$cmd"
}

# tmux_stop NAME [cmd] — 停止 tmux 服务
tmux_stop() {
    local name="$1" cmd="${2:-$1}"
    tmux kill-session -t "$name" 2>/dev/null
    pkill -f "$cmd" 2>/dev/null
}

# ===== Tailscale =====
# tailscale_ip — 获取 Tailscale IPv4
tailscale_ip() {
    check_command tailscale && tailscale ip -4 2>/dev/null
}

# tailscale_is_connected — 检查 Tailscale 是否已连接（成功返回 0）
tailscale_is_connected() {
    check_command tailscale || return 1
    # 方法1: tailscale status
    sudo tailscale status >/dev/null 2>&1 && return 0
    # 方法2: 网络接口检测（非交互式环境可能 status 失败）
    ip link show tailscale0 >/dev/null 2>&1 && return 0
    return 1
}

# tailscale_is_daemon_running — tailscaled 守护进程是否运行
tailscale_is_daemon_running() {
    pgrep -x tailscaled >/dev/null 2>&1
}

# tailscale_ensure_daemon — 确保 tailscaled 守护进程运行
tailscale_ensure_daemon() {
    if ! tailscale_is_daemon_running; then
        nohup sudo tailscaled </dev/null > "$LOG_DIR/tailscale.log" 2>&1 &
        disown
        sleep 2
    fi
}

# tailscale_auth — 尝试 authkey 认证（成功返回 0）
tailscale_auth() {
    if [ -n "$TAILSCALEAUTHKEY" ]; then
        sudo tailscale up --ssh --authkey="$TAILSCALEAUTHKEY" 2>/dev/null
    else
        return 1
    fi
}

# ===== 服务状态查询 =====
# query_tailscale — 输出 Tailscale 状态行
query_tailscale() {
    local ts_ip
    ts_ip=$(tailscale_ip)

    if ! check_command tailscale; then
        echo "skip|Tailscale|未安装"
        return
    fi

    if ! tailscale_is_daemon_running; then
        echo "fail|Tailscale|未运行"
        return
    fi

    if tailscale_is_connected; then
        echo "ok|Tailscale|${ts_ip:-已连接}"
    elif [ -n "$TAILSCALEAUTHKEY" ] && tailscale_auth; then
        echo "ok|Tailscale|已通过 authkey 认证"
    else
        echo "skip|Tailscale|未认证"
    fi
}

# query_omniroute [addr] — 输出 OmniRoute 状态行
# 优先用 omniroute health CLI 检测（更准确），fallback 到 HTTP 检查
query_omniroute() {
    local addr="${1:-localhost}"

    if ! check_command omniroute; then
        echo "skip|OmniRoute|未安装"
        return
    fi

    # 优先: omniroute health（CLI 直接检测服务状态）
    if omniroute health -q >/dev/null 2>&1; then
        echo "ok|OmniRoute|http://${addr}:20128"
        return
    fi

    # Fallback: HTTP 检查（health 可能因版本不支持而失败，OmniRoute 只监听 localhost）
    if http_check_retry "http://localhost:20128" 2 2 2; then
        echo "ok|OmniRoute|http://${addr}:20128"
    else
        echo "fail|OmniRoute|http://${addr}:20128"
    fi
}

# query_cloudcli [addr] — 输出 CloudCLI 状态行
query_cloudcli() {
    local addr="${1:-localhost}"

    if http_check "http://${addr}:3001" 2 || is_service_running cloudcli cloudcli; then
        echo "ok|CloudCLI|http://${addr}:3001"
    else
        echo "fail|CloudCLI|http://${addr}:3001"
    fi
}

# ===== npm 包管理 =====
# 格式: "包名" 或 "包名:命令名"
NPM_PACKAGES=(
    "omniroute"
    "@cloudcli-ai/cloudcli"
    "@openai/codex"
    "@ccpocket/bridge:ccpocket-bridge"
    "cc-connect"
    "@tawandotorg/claude-sync"
)

# npm_bin_name PKG_SPEC — 从包规格中提取命令名
npm_bin_name() {
    local pkg="$1"
    local pkg_name="${pkg%%:*}"
    local bin_name="${pkg#*:}"
    [ "$bin_name" = "$pkg_name" ] && bin_name="${pkg_name##*/}"
    echo "$bin_name"
}

# ===== 状态显示 =====
# display_status_line STATUS NAME HINT — 格式化显示一行状态
display_status_line() {
    local status="$1" name="$2" hint="$3"
    case "$status" in
        ok)   echo "  ✅ $name — $hint" ;;
        fail) echo "  ❌ $name — $hint" ;;
        skip) echo "  ⏭  $name — $hint" ;;
    esac
}

# display_header — 显示状态标题
display_header() {
    echo "📋 服务状态:"
}
