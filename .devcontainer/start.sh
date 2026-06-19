#!/bin/bash
# start.sh — FreeCloudCode 每次开机启动服务
# 由 ~/.bashrc 每次打开终端时调用

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# 加载库
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/start.sh"

# 确保 npm 全局命令在 PATH 中
export PATH="$PATH:$HOME/.local/bin:$(npm config get prefix 2>/dev/null)/bin"

# 等待 setup.sh 完成（首次创建时可能还在安装）
if [ ! -f "$SETUP_MARKER" ]; then
    echo "⏳ 安装进行中，服务暂未启动" >&2
    echo "   查看进度: tail -f ~/.freecloudcode/logs/setup.log" >&2
    echo "   安装完成后运行: bash ~/freecloudcode/.devcontainer/start.sh" >&2
    exit 0
fi

# 运行服务启动流程
run_start

# 首次安装完成后显示配置提醒（只显示一次）
CONFIG_HINT_SHOWN="$HOME/.freecloudcode/.config-hint-shown"
if [ ! -f "$CONFIG_HINT_SHOWN" ]; then
    ts_ip=$(tailscale_ip)

    echo "" >&2
    echo "=========================================" >&2
    echo " 🔧 配置提醒" >&2
    echo "=========================================" >&2

    # Tailscale
    result=$(query_tailscale)
    IFS='|' read -r status _ hint <<< "$result"
    display_status_line "$status" "Tailscale" "$hint"
    if [ "$status" = "skip" ]; then
        echo "     方式1（推荐）: 创建容器时设置环境变量 TAILSCALEAUTHKEY" >&2
        echo "     方式2: 终端运行: sudo tailscale up --ssh" >&2
        echo "     认证后可从其他设备通过 Tailscale IP 访问服务" >&2
    elif [ "$status" = "ok" ] && [ -n "$ts_ip" ]; then
        echo "     访问地址: http://${ts_ip}:20128 (OmniRoute) http://${ts_ip}:3001 (CloudCLI)" >&2
    fi

    # OmniRoute
    result=$(query_omniroute "${ts_ip:-localhost}")
    IFS='|' read -r status _ hint <<< "$result"
    if [ "$status" = "skip" ]; then
        display_status_line "skip" "OmniRoute" "未配置"
        echo "     运行: oc（首次使用需配置 API key）" >&2
        echo "     迁移旧数据: scp storage.sqlite codespace@<tailscale-ip>:~/.omniroute/" >&2
        echo "                  scp .env codespace@<tailscale-ip>:~/.omniroute/" >&2
    elif [ "$status" = "fail" ]; then
        display_status_line "fail" "OmniRoute" "$hint"
        echo "     运行: oc（配置 API key）" >&2
    else
        display_status_line "$status" "OmniRoute" "$hint"
    fi

    # claude-sync
    if check_command claude-sync; then
        if claude-sync status -q 2>/dev/null; then
            display_status_line "ok" "claude-sync" "已配置"
        else
            display_status_line "skip" "claude-sync" "未配置（需运行: claude-sync init）"
        fi
    fi

    # 安装检查
    echo "" >&2
    echo "=========================================" >&2
    echo " 📋 安装检查" >&2
    echo "=========================================" >&2
    for cmd in tailscale claude opencode omniroute cloudcli codex ccpocket-bridge claude-sync; do
        if check_command "$cmd"; then
            display_status_line "ok" "$cmd" "✓"
        else
            display_status_line "fail" "$cmd" "未找到"
        fi
    done

    # 常用命令
    echo "" >&2
    echo "📌 常用命令:" >&2
    echo "   cc(claude) codex opencode oc(omniroute) ccli(cloudcli) pocket(bridge)" >&2
    echo "   scc/xcc(CloudCLI) sbp/xbp(Bridge) son/xor(OmniRoute) fcc(状态)" >&2

    echo "" >&2
    touch "$CONFIG_HINT_SHOWN"
fi
