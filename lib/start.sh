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
    local host="${1:-localhost}"

    if ! check_command omniroute; then
        record "OmniRoute" "skip" "" "未安装"
        return
    fi

    if http_check_retry "http://localhost:20128" 3 2 2; then
        record "OmniRoute" "ok" "" "http://${host}:20128"
    else
        omniroute serve --daemon > "$LOG_DIR/omniroute.log" 2>&1
        sleep 8
        if http_check_retry "http://localhost:20128" 3 2 2; then
            record "OmniRoute" "ok" "" "http://${host}:20128"
        else
            record "OmniRoute" "fail" "$LOG_DIR/omniroute.log" "启动失败"
        fi
    fi
}

# 启动 tmux 服务（CloudCLI）
start_cloudcli() {
    local host="${1:-localhost}"

    if ! check_command cloudcli; then
        record "CloudCLI" "skip" "" "未安装"
        return
    fi

    if is_service_running cloudcli cloudcli; then
        record "CloudCLI" "ok" "" "http://${host}:3001"
        return
    fi

    if ss -tlnp 2>/dev/null | grep -q ":3001 "; then
        record "CloudCLI" "fail" "" "端口 3001 已被占用"
        return
    fi

    tmux_start "cloudcli" "cloudcli" "$LOG_DIR/cloudcli.log"
    if is_service_running cloudcli cloudcli; then
        record "CloudCLI" "ok" "" "http://${host}:3001"
    else
        record "CloudCLI" "fail" "$LOG_DIR/cloudcli.log" "启动失败"
    fi
}

# 启动 cc-connect
start_ccconnect() {
    if ! check_command cc-connect; then
        record "cc-connect" "skip" "" "未安装"
        return
    fi

    if is_service_running cc-connect cc-connect; then
        record "cc-connect" "ok" "" "已运行"
        return
    fi

    local log_dir="$HOME/.cc-connect/logs"
    ensure_dir "$log_dir"
    tmux_start "cc-connect" "cc-connect" "$log_dir/cc-connect.log"
    if is_service_running cc-connect cc-connect; then
        record "cc-connect" "ok" "" "已启动"
    else
        record "cc-connect" "fail" "$log_dir/cc-connect.log" "启动失败"
    fi
}

# 启动所有服务
start_services() {
    start_tailscale

    # 等待 Tailscale 获取到 IP（最多等 10 秒）
    local ts_ip
    for i in $(seq 1 20); do
        ts_ip=$(tailscale_ip)
        [ -n "$ts_ip" ] && break
        sleep 0.5
    done

    start_omniroute "${ts_ip:-localhost}"
    start_agentsanywhere
    # CloudCLI 和 cc-connect 不再自动启动，需要时手动运行: scc / sccn
}

# 启动 Agents-Anywhere（server + connector）
start_agentsanywhere() {
    local host="${1:-localhost}"

    # --- Server（Docker）---
    if ! check_command docker; then
        record "AA-Server" "skip" "" "Docker 未安装"
    else
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agents-anywhere-server$'; then
            record "AA-Server" "ok" "" "http://${host}:5174"
        else
            docker rm -f agents-anywhere-server >/dev/null 2>&1
            docker run -d \
                --name agents-anywhere-server \
                -p 5174:8000 \
                -v agents-anywhere-data:/data \
                -e AGENT_SERVER_SECRET=liuxu-1989 \
                agents-anywhere-server:latest >/dev/null 2>&1
            sleep 3
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agents-anywhere-server$'; then
                record "AA-Server" "ok" "" "http://${host}:5174"
            else
                record "AA-Server" "fail" "" "启动失败"
            fi
        fi
    fi

    # --- Connector（tmux）---
    local connector_dir="$HOME/Agents-Anywhere/connector"
    if [ ! -f "$connector_dir/start-cli.sh" ]; then
        record "AA-Connector" "skip" "" "start-cli.sh 未找到"
        return
    fi

    if is_service_running agents-anywhere-connector agents-anywhere-connector; then
        record "AA-Connector" "ok" "" "已运行"
        return
    fi

    local log_dir="$HOME/.agents-anywhere/logs"
    ensure_dir "$log_dir"
    tmux_start "agents-anywhere-connector" "cd '$connector_dir' && bash start-cli.sh" "$log_dir/connector.log"
    if is_service_running agents-anywhere-connector agents-anywhere-connector; then
        record "AA-Connector" "ok" "" "已启动"
    else
        record "AA-Connector" "fail" "$log_dir/connector.log" "启动失败"
    fi
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
