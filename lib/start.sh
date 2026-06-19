#!/bin/bash
# lib/start.sh — FreeCloudCode 每次启动服务

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 状态追踪
declare -a SvcName=() SvcStatus=() SvcLog=() SvcHint=()
record() { SvcName+=("$1"); SvcStatus+=("$2"); SvcLog+=("${3:-}"); SvcHint+=("${4:-}"); }

# 启动 Tailscale
start_tailscale() {
    if ! check_command tailscale; then
        record "Tailscale" "skip" "" "未安装"
        return
    fi

    tailscale_ensure_daemon
    local result
    result=$(query_tailscale)
    IFS='|' read -r status name hint <<< "$result"
    record "$name" "$status" "$([ "$status" = "fail" ] && echo "$LOG_DIR/tailscale.log")" "$hint"
}

# 启动 OmniRoute
start_omniroute() {
    if ! check_command omniroute; then
        record "OmniRoute" "skip" "" "未安装"
        return
    fi

    if http_check_retry "http://localhost:20128" 3 2 2; then
        record "OmniRoute" "ok" "" "http://localhost:20128"
    else
        omniroute serve --daemon > "$LOG_DIR/omniroute.log" 2>&1
        sleep 8
        if http_check_retry "http://localhost:20128" 3 2 2; then
            record "OmniRoute" "ok" "" "http://localhost:20128"
        else
            record "OmniRoute" "fail" "$LOG_DIR/omniroute.log" "启动失败"
        fi
    fi
}

# 启动 tmux 服务（CloudCLI）
start_cloudcli() {
    if ! check_command cloudcli; then
        record "CloudCLI" "skip" "" "未安装"
        return
    fi

    if is_service_running cloudcli cloudcli; then
        record "CloudCLI" "ok" "" "已在运行"
        return
    fi

    if ss -tlnp 2>/dev/null | grep -q ":3001 "; then
        record "CloudCLI" "fail" "" "端口 3001 已被占用"
        return
    fi

    tmux_start "cloudcli" "cloudcli" "$LOG_DIR/cloudcli.log"
    if is_service_running cloudcli cloudcli; then
        record "CloudCLI" "ok" "" "已启动"
    else
        record "CloudCLI" "fail" "$LOG_DIR/cloudcli.log" "启动失败"
    fi
}

# 启动所有服务
start_services() {
    start_tailscale
    start_omniroute
    start_cloudcli
}

# 生成状态报告
generate_status_report() {
    local status_file="$HOME/.freecloudcode/startup-status.log"

    {
        echo "========================================="
        echo " 📋 启动状态报告"
        echo "========================================="

        local i
        for i in "${!SvcName[@]}"; do
            local name="${SvcName[$i]}" status="${SvcStatus[$i]}"
            local log="${SvcLog[$i]}" hint="${SvcHint[$i]}"

            display_status_line "$status" "$name" "$hint"
            if [ "$status" = "fail" ] && [ -n "$log" ] && [ -f "$log" ]; then
                echo "     📄 日志: $log"
                tail -5 "$log" 2>/dev/null | sed 's/^/        /'
            fi
        done

        echo ""
        echo "  🕐 $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================="
    } > "$status_file"

    cat "$status_file" >&2
}

# 主启动流程
run_start() {
    ensure_dir "$LOG_DIR"
    ensure_dir "$(dirname "$STARTUP_MARKER")"
    rm -f "$STARTUP_MARKER"

    start_services
    generate_status_report
    touch "$STARTUP_MARKER"
}
