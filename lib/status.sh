#!/bin/bash
# lib/status.sh — FreeCloudCode 服务状态检测

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 显示服务状态
show_status() {
    local ts_ip=""

    # 获取 Tailscale IP
    if check_command tailscale; then
        ts_ip=$(tailscale ip -4 2>/dev/null)
    fi

    echo "📋 服务状态:"

    # Tailscale
    if check_command tailscale; then
        if pgrep -x tailscaled >/dev/null 2>&1; then
            if sudo tailscale status >/dev/null 2>&1 || ip link show tailscale0 >/dev/null 2>&1; then
                echo "  ✅ Tailscale — ${ts_ip:-已连接}"
            else
                echo "  ⚠️  Tailscale — 守护进程运行但未认证"
            fi
        else
            echo "  ❌ Tailscale — 未运行"
        fi
    fi

    # OmniRoute（HTTP 检测，带重试）
    if check_command omniroute; then
        local or_addr="${ts_ip:-localhost}"
        local or_code=""
        for _or_try in 1 2 3; do
            or_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "http://${or_addr}:20128" 2>/dev/null)
            [[ "$or_code" =~ ^[23] ]] && break
            sleep 2
        done
        if [[ "$or_code" =~ ^[23] ]]; then
            echo "  ✅ OmniRoute — http://${or_addr}:20128"
        else
            echo "  ❌ OmniRoute — 未运行 (http://${or_addr}:20128)"
        fi
    fi

    # CloudCLI（HTTP 检测，fallback tmux session）
    local cc_addr="${ts_ip:-localhost}"
    local cc_code
    cc_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "http://${cc_addr}:3001" 2>/dev/null)
    if [[ "$cc_code" =~ ^[23] ]]; then
        echo "  ✅ CloudCLI — http://${cc_addr}:3001"
    elif tmux has-session -t cloudcli 2>/dev/null || pgrep -f cloudcli >/dev/null 2>&1; then
        echo "  ✅ CloudCLI — http://${cc_addr}:3001"
    else
        echo "  ❌ CloudCLI — 未运行"
    fi
}

# 等待启动完成（带超时）
wait_for_startup() {
    local timeout="${1:-30}"
    local done_file="$HOME/.freecloudcode/startup-done"

    if [ -f "$done_file" ]; then
        return 0
    fi

    if ! pgrep -f "start.sh" >/dev/null 2>&1; then
        return 0
    fi

    echo "⏳ 等待服务启动..."
    for _w in $(seq 1 "$timeout"); do
        [ -f "$done_file" ] && break
        sleep 1
    done
}

# 显示命令速查
show_commands() {
    echo ""
    echo "📌 命令: cc(claude) codex oc(omniroute) ccli(cloudcli) pocket(bridge) cr(重连)"
    echo "   服务: scc/xcc(CloudCLI) sbp/xbp(Bridge) xor(OmniRoute)"
}
