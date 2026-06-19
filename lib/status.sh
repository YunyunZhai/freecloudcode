#!/bin/bash
# lib/status.sh — FreeCloudCode 服务状态检测

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 显示所有服务状态（并行查询）
show_status() {
    display_header

    # 并行查询所有服务状态
    local ts_result or_result cc_result
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
    wait

    # 读取结果并显示
    local status name hint
    if [ -f /tmp/fcc_ts_status ]; then
        IFS='|' read -r status name hint < /tmp/fcc_ts_status
        display_status_line "$status" "$name" "$hint"
        rm -f /tmp/fcc_ts_status
    fi
    if [ -f /tmp/fcc_or_status ]; then
        IFS='|' read -r status name hint < /tmp/fcc_or_status
        display_status_line "$status" "$name" "$hint"
        rm -f /tmp/fcc_or_status
    fi
    if [ -f /tmp/fcc_cc_status ]; then
        IFS='|' read -r status name hint < /tmp/fcc_cc_status
        display_status_line "$status" "$name" "$hint"
        rm -f /tmp/fcc_cc_status
    fi
}
