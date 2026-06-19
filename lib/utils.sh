#!/bin/bash
# lib/utils.sh — FreeCloudCode 工具函数

# 日志函数
log_info() {
    local msg="$1"
    echo "ℹ️  $msg"
}

log_success() {
    local msg="$1"
    echo "✅ $msg"
}

log_warn() {
    local msg="$1"
    echo "⚠️  $msg"
}

log_error() {
    local msg="$1"
    echo "❌ $msg"
}

# 检查命令是否存在
check_command() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null
}

# 检查文件是否存在
check_file() {
    local file="$1"
    [ -f "$file" ]
}

# 检查目录是否存在，不存在则创建
ensure_dir() {
    local dir="$1"
    mkdir -p "$dir"
}

# 运行命令并记录状态
run_or_warn() {
    local description="$1"
    local cmd="$2"

    if eval "$cmd" 2>/dev/null; then
        return 0
    else
        log_warn "$description"
        return 1
    fi
}

# 获取 tailscale IP（简化版）
get_tailscale_ip() {
    if check_command tailscale; then
        tailscale ip -4 2>/dev/null
    fi
}

# HTTP 健康检查
http_check() {
    local url="$1"
    local timeout="${2:-2}"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" --max-time "$timeout" "$url" 2>/dev/null)
    [[ "$code" =~ ^[23] ]]
}

# tmux 会话运行
tmux_run() {
    local name="$1"
    local cmd="$2"
    local log_file="$3"

    if tmux has-session -t "$name" 2>/dev/null; then
        return 0
    fi

    tmux new-session -d -s "$name" \
        "bash -c '$cmd 2>&1 | tee \"$log_file\"; sleep infinity'"
    sleep 2
    pgrep -f "$cmd" >/dev/null 2>&1
}
