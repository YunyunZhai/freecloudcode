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
    if [ "$status" = "ok" ] && [ -n "$ts_ip" ]; then
        display_status_line "ok" "Tailscale" "$ts_ip"
    elif [ "$status" = "skip" ]; then
        display_status_line "skip" "Tailscale" "未认证"
        echo "     方式1（推荐）: 创建容器时设置环境变量 TAILSCALEAUTHKEY" >&2
        echo "     方式2: 终端运行: sudo tailscale up --ssh" >&2
    else
        display_status_line "$status" "Tailscale" "$hint"
    fi

    # OmniRoute
    result=$(query_omniroute "${ts_ip:-localhost}")
    IFS='|' read -r status _ hint <<< "$result"
    if [ "$status" = "ok" ]; then
        display_status_line "ok" "OmniRoute" "$hint"
        echo "     迁移旧数据（可选）:" >&2
        echo "       ⚠️  重要: 迁移前必须关闭两边的 OmniRoute" >&2
        echo "       scp storage.sqlite codespace@${ts_ip}:~/.omniroute/" >&2
        echo "       scp .env codespace@${ts_ip}:~/.omniroute/" >&2
    elif [ "$status" = "skip" ]; then
        display_status_line "skip" "OmniRoute" "未安装"
    else
        display_status_line "$status" "OmniRoute" "$hint"
    fi

    # CloudCLI
    result=$(query_cloudcli "${ts_ip:-localhost}")
    IFS='|' read -r status _ hint <<< "$result"
    if [ "$status" = "ok" ]; then
        display_status_line "ok" "CloudCLI" "$hint"
    else
        display_status_line "$status" "CloudCLI" "$hint"
    fi

    # claude-sync
    if check_command claude-sync; then
        if claude-sync status -q 2>/dev/null; then
            display_status_line "ok" "claude-sync" "已配置"
            echo "     同步方案: 开启终端自动同步 + claude stop 时同步" >&2
        else
            display_status_line "skip" "claude-sync" "未配置"
            echo "     方式1（推荐）: 在 Codespace 环境变量中设置:" >&2
            echo "       CLAUDE_SYNC_ACCOUNT_ID, CLAUDE_SYNC_ACCESS_KEY," >&2
            echo "       CLAUDE_SYNC_SECRET_KEY, CLAUDE_SYNC_BUCKET" >&2
            echo "     方式2: 终端运行: claude-sync init" >&2
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
