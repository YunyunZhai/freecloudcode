#!/bin/bash
# lib/start.sh — FreeCloudCode 每次启动服务

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

LOG_DIR="$HOME/.freecloudcode/logs"
STATUS_FILE="$HOME/.freecloudcode/startup-status.log"

# 状态追踪
declare -a SvcName=()
declare -a SvcStatus=()
declare -a SvcLog=()
declare -a SvcHint=()

# 记录服务状态
record() {
    SvcName+=("$1")
    SvcStatus+=("$2")
    SvcLog+=("${3:-}")
    SvcHint+=("${4:-}")
}

# 启动 Tailscale
start_tailscale() {
    if ! check_command tailscale; then
        record "Tailscale" "skip" "" "未安装"
        return
    fi

    # 启动守护进程
    if ! pgrep -x tailscaled >/dev/null 2>&1; then
        nohup sudo tailscaled </dev/null > "$LOG_DIR/tailscale.log" 2>&1 &
        disown
        sleep 2
    fi

    if pgrep -x tailscaled >/dev/null 2>&1; then
        if sudo tailscale status >/dev/null 2>&1; then
            record "Tailscale" "ok" "" "已连接"
        elif ip link show tailscale0 >/dev/null 2>&1; then
            record "Tailscale" "ok" "" "已连接（通过网络接口检测）"
        else
            if [ -n "$TAILSCALEAUTHKEY" ]; then
                if sudo tailscale up --ssh --authkey="$TAILSCALEAUTHKEY" 2>/dev/null; then
                    record "Tailscale" "ok" "" "已通过 authkey 认证"
                else
                    record "Tailscale" "fail" "$LOG_DIR/tailscale.log" \
                        "authkey 认证失败，检查 TAILSCALEAUTHKEY 是否有效"
                fi
            else
                record "Tailscale" "skip" "" \
                    "未认证，需设置 TAILSCALEAUTHKEY 或手动运行: sudo tailscale up --ssh"
            fi
        fi
    else
        record "Tailscale" "fail" "$LOG_DIR/tailscale.log" "tailscaled 启动失败"
    fi
}

# 启动 OmniRoute
start_omniroute() {
    if ! check_command omniroute; then
        record "OmniRoute" "skip" "" "未安装"
        return
    fi

    # 检测函数
    _or_check() {
        local code
        for _i in 1 2 3; do
            code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "http://localhost:20128" 2>/dev/null)
            [[ "$code" =~ ^[23] ]] && return 0
            sleep 2
        done
        return 1
    }

    if _or_check; then
        record "OmniRoute" "ok" "" "http://localhost:20128"
    else
        omniroute serve --daemon > "$LOG_DIR/omniroute.log" 2>&1
        sleep 8
        if _or_check; then
            record "OmniRoute" "ok" "" "http://localhost:20128"
        else
            record "OmniRoute" "fail" "$LOG_DIR/omniroute.log" "启动失败"
        fi
    fi
}

# 启动 tmux 服务
start_tmux_service() {
    local name="$1"
    local cmd="$2"
    local label="$3"
    local port="$4"

    local cmd_name="${cmd%% *}"
    if ! check_command "$cmd_name"; then
        record "$label" "skip" "" "未安装"
        return
    fi

    if tmux has-session -t "$name" 2>/dev/null; then
        record "$label" "ok" "" "tmux session '$name' 已存在"
    elif pgrep -f "$cmd" >/dev/null 2>&1; then
        record "$label" "ok" "" "已在运行"
    elif [ -n "$port" ] && ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        record "$label" "fail" "" "端口 ${port} 已被占用"
    else
        tmux new-session -d -s "$name" \
            "bash -c '$cmd 2>&1 | tee \"$LOG_DIR/${name}.log\"; sleep infinity'"
        sleep 2
        if pgrep -f "$cmd" >/dev/null 2>&1; then
            record "$label" "ok" "" "已启动"
        else
            record "$label" "fail" "$LOG_DIR/${name}.log" "启动失败"
        fi
    fi
}

# 启动所有服务
start_services() {
    start_tailscale
    start_omniroute
    start_tmux_service "cloudcli" "cloudcli" "CloudCLI" 3001
}

# 生成状态报告
generate_status_report() {
    {
        echo "========================================="
        echo " 📋 启动状态报告"
        echo "========================================="

        for i in "${!SvcName[@]}"; do
            _name="${SvcName[$i]}"
            _status="${SvcStatus[$i]}"
            _log="${SvcLog[$i]}"
            _hint="${SvcHint[$i]}"

            case "$_status" in
                ok)
                    echo "  ✅ $_name — $_hint"
                    ;;
                fail)
                    echo "  ❌ $_name — $_hint"
                    if [ -n "$_log" ] && [ -f "$_log" ]; then
                        echo "     📄 日志: $_log"
                        _tail=$(tail -5 "$_log" 2>/dev/null | sed 's/^/        /')
                        [ -n "$_tail" ] && echo "$_tail"
                    fi
                    ;;
                skip)
                    echo "  ⏭  $_name — $_hint"
                    ;;
            esac
        done

        echo ""
        echo "  🕐 $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================="
    } > "$STATUS_FILE"

    cat "$STATUS_FILE" >&2
}

# 主启动流程
run_start() {
    ensure_dir "$LOG_DIR"
    ensure_dir "$(dirname "$STATUS_FILE")"

    # 清除旧完成标记
    rm -f "$HOME/.freecloudcode/startup-done"

    # 启动服务
    start_services

    # 生成状态报告
    generate_status_report

    # 写入完成标记
    touch "$HOME/.freecloudcode/startup-done"
}
