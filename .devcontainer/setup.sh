#!/bin/bash
# setup.sh — FreeCloudCode 一次性安装配置
# 由 ~/.bashrc 在首次打开终端时调用

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

source "$LIB_DIR/utils.sh"
source "$LIB_DIR/install.sh"

# 幂等检查
if [ -f "$SETUP_MARKER" ]; then
    exit 0
fi

ensure_dir "$LOG_DIR"

echo "========================================="
echo " FreeCloudCode — 初始安装配置"
echo "========================================="

FAILED_COUNT=$(run_setup)

# 写入完成标记
touch "$SETUP_MARKER"

# 显示配置提醒
echo ""
echo "========================================="
echo " 🔧 配置提醒"
echo "========================================="

# Tailscale
result=$(query_tailscale)
IFS='|' read -r status _ hint <<< "$result"
display_status_line "$status" "Tailscale" "$hint"
if [ "$status" = "skip" ]; then
    echo "     方式1: 设置环境变量 TAILSCALEAUTHKEY 后重新创建容器"
    echo "     方式2: 在终端运行: sudo tailscale up --ssh"
fi

# OmniRoute
result=$(query_omniroute)
IFS='|' read -r status _ hint <<< "$result"
if [ "$status" = "skip" ]; then
    display_status_line "skip" "OmniRoute" "未配置（首次使用需运行: oc）"
elif [ "$status" = "fail" ]; then
    display_status_line "ok" "OmniRoute" "已安装（首次使用需运行: oc 配置 API key）"
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
for cmd in tailscale claude omniroute cloudcli codex ccpocket-bridge claude-sync; do
    display_status_line "$([ $(check_command "$cmd" && echo ok || echo fail) = ok ] && echo ok || echo fail)" "$cmd" "$([ $(check_command "$cmd" && echo ok || echo fail) = ok ] && echo "✓" || echo "未找到")"
done

echo ""
if [ "$FAILED_COUNT" -eq 0 ]; then
    echo "✅ 所有工具安装成功！"
else
    echo "⚠️  有 $FAILED_COUNT 个工具安装失败，请查看上方日志"
fi
