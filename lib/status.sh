#!/bin/bash
# lib/status.sh — FreeCloudCode 服务状态检测

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 显示所有服务状态（并行查询）
show_status() {
    display_header

    # 并行查询所有服务状态
    local ts_result or_result
    (
        ts_result=$(query_tailscale)
        echo "$ts_result" > /tmp/fcc_ts_status
    ) &
    (
        or_result=$(query_omniroute "localhost")
        echo "$or_result" > /tmp/fcc_or_status
    ) &
    wait

    # 读取结果并显示
    local status name hint
    for f in /tmp/fcc_ts_status /tmp/fcc_or_status; do
        if [ -f "$f" ]; then
            IFS='|' read -r status name hint < "$f"
            display_status_line "$status" "$name" "$hint"
            rm -f "$f"
        fi
    done
}
