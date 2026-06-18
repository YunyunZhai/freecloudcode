#!/bin/bash
# start.sh — FreeCloudCode 每次开机启动服务
# 由 devcontainer.json 的 postStartCommand 触发，异步执行

set -e

echo "========================================="
echo " FreeCloudCode — 启动服务"
echo "========================================="

# ===== 1. 启动 tailscaled =====
if ! pgrep -f "tailscaled" > /dev/null 2>&1; then
    echo "⟳ 启动 tailscaled..."
    nohup sudo tailscaled --tun=userspace-networking </dev/null > /tmp/tailscaled.log 2>&1 &
    disown
    sleep 2
    pgrep -f "tailscaled" > /dev/null 2>&1 && echo "✓ tailscaled 启动成功" || echo "✗ tailscaled 启动失败"
else
    echo "✓ tailscaled 已在运行"
fi

# ===== 2. tmux 启动辅助函数 =====
_tmux_run() {
    local name="$1" proc="$2" cmd="$3" label="$4" port="$5"
    if tmux has-session -t "$name" 2>/dev/null; then
        echo "✓ $label session 已存在"
    elif pgrep -f "$proc" > /dev/null 2>&1; then
        echo "✓ $label 已在运行"
    elif [ -n "$port" ] && (ss -tlnp 2>/dev/null | grep -q ":${port} "); then
        echo "⚠ $label 端口 ${port} 已被占用，跳过"
    else
        echo "⟳ 启动 $label..."
        tmux new-session -d -s "$name" "bash -c '$cmd 2>&1 | tee /tmp/${name}.log; sleep infinity'"
        sleep 2
        pgrep -f "$proc" > /dev/null 2>&1 && echo "✓ $label 启动成功" || echo "✗ $label 启动失败"
    fi
}

# ===== 3. 启动 OmniRoute + CloudCLI =====
_tmux_run omniroute "omniroute" "omniroute" "OmniRoute"
_tmux_run cloudcli  "cloudcli"  "cloudcli"  "CloudCLI" 3001

echo ""
echo "📌 服务已就绪"
echo "   手动控制: scli(启动CloudCLI) xcli(停止)  sbridge(启动Bridge) xbridge(停止)"
echo ""
