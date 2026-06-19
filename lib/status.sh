#!/bin/bash
# lib/status.sh — FreeCloudCode 服务状态检测

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 显示所有服务状态
show_status() {
    local ts_ip
    ts_ip=$(tailscale_ip)

    display_header

    # Tailscale
    local result
    result=$(query_tailscale)
    IFS='|' read -r status name hint <<< "$result"
    display_status_line "$status" "$name" "$hint"

    # OmniRoute
    result=$(query_omniroute "${ts_ip:-localhost}")
    IFS='|' read -r status name hint <<< "$result"
    display_status_line "$status" "$name" "$hint"

    # CloudCLI
    result=$(query_cloudcli "${ts_ip:-localhost}")
    IFS='|' read -r status name hint <<< "$result"
    display_status_line "$status" "$name" "$hint"
}
