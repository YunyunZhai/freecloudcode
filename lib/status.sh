#!/bin/bash
# lib/status.sh — FreeCloudCode 服务状态检测

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 查询 AA-Server 状态
query_aa_server() {
    if ! check_command docker; then
        echo "skip|AA-Server|Docker 未安装"
        return
    fi
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agents-anywhere-server$'; then
        echo "ok|AA-Server|http://localhost:5174"
    else
        echo "fail|AA-Server|未运行"
    fi
}

# 查询 AA-Connector 状态
query_aa_connector() {
    if is_service_running agents-anywhere-connector agents-anywhere-connector; then
        echo "ok|AA-Connector|已运行"
    else
        echo "fail|AA-Connector|未运行"
    fi
}

# 显示所有服务状态（并行查询）
show_status() {
    display_header

    # 并行查询所有服务状态
    local ts_result or_result cc_result aa_s_result aa_c_result
    (
        ts_result=$(query_tailscale)
        echo "$ts_result" > /tmp/fcc_ts_status
    ) &
    (
        or_result=$(query_omniroute "localhost")
        echo "$or_result" > /tmp/fcc_or_status
    ) &
    (
        cc_result=$(query_cloudcli "localhost")
        echo "$cc_result" > /tmp/fcc_cc_status
    ) &
    (
        aa_s_result=$(query_aa_server)
        echo "$aa_s_result" > /tmp/fcc_aas_status
    ) &
    (
        aa_c_result=$(query_aa_connector)
        echo "$aa_c_result" > /tmp/fcc_aac_status
    ) &
    wait

    # 读取结果并显示
    local status name hint
    for f in /tmp/fcc_ts_status /tmp/fcc_or_status /tmp/fcc_cc_status /tmp/fcc_aas_status /tmp/fcc_aac_status; do
        if [ -f "$f" ]; then
            IFS='|' read -r status name hint < "$f"
            display_status_line "$status" "$name" "$hint"
            rm -f "$f"
        fi
    done
}
