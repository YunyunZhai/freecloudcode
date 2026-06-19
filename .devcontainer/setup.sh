#!/bin/bash
# setup.sh — FreeCloudCode 一次性安装配置
# 由 ~/.bashrc 在首次打开终端时调用

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/utils.sh"
source "$LIB_DIR/install.sh"

# 幂等检查 — 已完成则跳过
if [ -f "$SETUP_MARKER" ]; then
    exit 0
fi

# 并发锁 — 防止多个终端同时运行 setup.sh
LOCK_FILE="$LOG_DIR/setup.lock"
ensure_dir "$LOG_DIR"
if [ -f "$LOCK_FILE" ]; then
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        echo "⏳ 安装进行中（PID $lock_pid），跳过..." >&2
        exit 0
    fi
    # 旧锁，进程已不存在，清理
    rm -f "$LOCK_FILE"
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

echo "========================================="
echo " FreeCloudCode — 初始安装配置"
echo "========================================="

FAILED_COUNT=$(run_setup)
FAILED_COUNT="${FAILED_COUNT:-0}"

# 写入完成标记
touch "$SETUP_MARKER"

# 显示配置提醒
echo ""
echo "========================================="
echo " 🔧 配置提醒"
echo "========================================="

# Tailscale
ts_ip=$(tailscale_ip)
result=$(query_tailscale)
IFS='|' read -r status _ hint <<< "$result"
display_status_line "$status" "Tailscale" "$hint"
if [ "$status" = "skip" ]; then
    echo "     方式1（推荐）: 创建容器时设置环境变量 TAILSCALEAUTHKEY"
    echo "     方式2: 终端运行: sudo tailscale up --ssh"
    echo "     认证后可从其他设备通过 Tailscale IP 访问服务"
fi

# OmniRoute
result=$(query_omniroute "${ts_ip:-localhost}")
IFS='|' read -r status _ hint <<< "$result"
if [ "$status" = "skip" ]; then
    display_status_line "skip" "OmniRoute" "未配置"
    echo "     运行: oc（首次使用需配置 API key）"
    echo "     迁移旧数据: scp storage.sqlite codespace@<tailscale-ip>:~/.omniroute/"
    echo "                  scp .env codespace@<tailscale-ip>:~/.omniroute/"
elif [ "$status" = "fail" ]; then
    display_status_line "ok" "OmniRoute" "已安装"
    echo "     运行: oc（配置 API key）"
    echo "     迁移旧数据: scp ~/.omniroute/storage.sqlite codespace@<tailscale-ip>:~/.omniroute/"
    echo "                  scp ~/.omniroute/.env codespace@<tailscale-ip>:~/.omniroute/"
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
echo ""
echo "========================================="
echo " 📋 安装检查"
echo "========================================="
for cmd in tailscale claude opencode omniroute cloudcli codex ccpocket-bridge claude-sync; do
    if check_command "$cmd"; then
        display_status_line "ok" "$cmd" "✓"
    else
        display_status_line "fail" "$cmd" "未找到"
    fi
done

echo ""
if [ "$FAILED_COUNT" -eq 0 ]; then
    echo "✅ 所有工具安装成功！"
else
    echo "⚠️  有 $FAILED_COUNT 个工具安装失败，日志: ~/.freecloudcode/logs/setup.log"
fi
