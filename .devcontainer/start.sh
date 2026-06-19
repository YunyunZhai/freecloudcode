#!/bin/bash
# start.sh — FreeCloudCode 每次开机启动服务
# 由 devcontainer.json 的 postStartCommand 触发
# 设计原则：不能阻塞启动流程，所有服务快速后台启动

# 确保 npm 全局命令在 PATH 中
export PATH="$PATH:$HOME/.local/bin:$(npm config get prefix 2>/dev/null)/bin"

# 等待 setup.sh 完成（首次创建时可能还在安装）
SETUP_MARKER="$HOME/.freecloudcode.setup.done"
if [ ! -f "$SETUP_MARKER" ]; then
    echo "⟳ 等待 setup.sh 完成安装..."
    for i in $(seq 1 60); do
        [ -f "$SETUP_MARKER" ] && break
        sleep 5
    done
    if [ ! -f "$SETUP_MARKER" ]; then
        echo "⚠ setup.sh 超时（5分钟），跳过服务启动"
        echo "⚠ 请在新终端运行: bash .devcontainer/setup.sh"
        exit 0
    fi
fi

echo "========================================="
echo " FreeCloudCode — 启动服务"
echo "========================================="

# --- 状态追踪 ---
declare -a SvcName=()
declare -a SvcStatus=()   # ok / fail / skip
declare -a SvcLog=()      # 日志路径
declare -a SvcHint=()     # 启动命令或说明

# 辅助：记录服务状态
record() { SvcName+=("$1"); SvcStatus+=("$2"); SvcLog+=("${3:-}"); SvcHint+=("${4:-}"); }

# ===== 1. Tailscale =====
if command -v tailscale &>/dev/null; then
    # 先确保 tailscaled 守护进程运行
    if ! pgrep -x tailscaled >/dev/null 2>&1; then
        echo "⟳ 启动 tailscaled..."
        nohup sudo tailscaled </dev/null >/tmp/tailscaled.log 2>&1 &
        disown
        sleep 2
    fi

    if pgrep -x tailscaled >/dev/null 2>&1; then
        # 检查是否已认证连接
        if sudo tailscale status >/dev/null 2>&1; then
            record "Tailscale" "ok" "" "已连接"
        else
            record "Tailscale" "fail" "/tmp/tailscaled.log" \
                "守护进程运行中但未认证，需要运行: sudo tailscale up --ssh"
        fi
    else
        record "Tailscale" "fail" "/tmp/tailscaled.log" "tailscaled 启动失败"
    fi
else
    record "Tailscale" "skip" "" "未安装"
fi

# ===== 2. OmniRoute =====
if command -v omniroute &>/dev/null; then
    if pgrep -f "omniroute" >/dev/null 2>&1; then
        record "OmniRoute" "ok" "" "http://localhost:20128"
    else
        echo "⟳ 启动 OmniRoute..."
        omniroute serve --daemon >/tmp/omniroute.log 2>&1
        sleep 2
        if pgrep -f "omniroute" >/dev/null 2>&1; then
            record "OmniRoute" "ok" "" "http://localhost:20128"
        else
            record "OmniRoute" "fail" "/tmp/omniroute.log" "启动失败"
        fi
    fi
else
    record "OmniRoute" "skip" "" "未安装"
fi

# ===== 3. tmux 启动辅助函数 =====
_tmux_run() {
    local name="$1" proc="$2" cmd="$3" label="$4" port="$5"

    local cmd_name="${cmd%% *}"
    if ! command -v "$cmd_name" &>/dev/null; then
        record "$label" "skip" "" "未安装"
        return 0
    fi

    if tmux has-session -t "$name" 2>/dev/null; then
        record "$label" "ok" "" "tmux session '$name' 已存在"
    elif pgrep -f "$proc" >/dev/null 2>&1; then
        record "$label" "ok" "" "已在运行"
    elif [ -n "$port" ] && ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        record "$label" "fail" "" "端口 ${port} 已被占用"
    else
        echo "⟳ 启动 $label..."
        tmux new-session -d -s "$name" \
            "bash -c '$cmd 2>&1 | tee /tmp/${name}.log; sleep infinity'"
        sleep 2
        if pgrep -f "$proc" >/dev/null 2>&1; then
            record "$label" "ok" "" "已启动"
        else
            record "$label" "fail" "/tmp/${name}.log" "启动失败"
        fi
    fi
}

# ===== 4. CloudCLI =====
_tmux_run cloudcli "cloudcli" "cloudcli" "CloudCLI" 3001

# ===== 统一状态报告 =====
echo ""
echo "========================================="
echo " 📋 启动状态报告"
echo "========================================="

for i in "${!SvcName[@]}"; do
    _name="${SvcName[$i]}"
    _status="${SvcStatus[$i]}"
    _log="${SvcLog[$i]}"
    _hint="${SvcHint[$i]}"

    case "$_status" in
        ok)
            echo "  ✅ $_name — $_hint"
            ;;
        fail)
            echo "  ❌ $_name — $_hint"
            [ -n "$_log" ] && echo "     📄 日志: $_log"
            ;;
        skip)
            echo "  ⏭  $_name — $_hint"
            ;;
    esac
done

echo ""
echo "📌 命令速查:"
echo "  启动:  scc(CloudCLI)  sbp(Bridge)"
echo "  停止:  xcc(CloudCLI)  xbp(Bridge)  xor(OmniRoute)"
echo "  别名:  cc(claude)  codex  oc(omniroute)  ccli(cloudcli)"
echo ""
