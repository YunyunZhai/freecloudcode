#!/bin/bash
# start.sh — FreeCloudCode 每次开机启动服务
# 由 devcontainer.json 的 postStartCommand 触发
# 设计原则：不能阻塞启动流程，所有服务快速后台启动
# 状态报告写入文件，由 ~/.bashrc 在每次登录时显示

LOG_DIR="$HOME/.freecloudcode/logs"
STATUS_DIR="$HOME/.freecloudcode"
STATUS_FILE="$STATUS_DIR/startup-status.log"
mkdir -p "$LOG_DIR" "$STATUS_DIR"

# 确保 npm 全局命令在 PATH 中
export PATH="$PATH:$HOME/.local/bin:$(npm config get prefix 2>/dev/null)/bin"

# 等待 setup.sh 完成（首次创建时可能还在安装）
SETUP_MARKER="$HOME/.freecloudcode.setup.done"
if [ ! -f "$SETUP_MARKER" ]; then
    echo "⟳ 等待 setup.sh 完成安装..." >&2
    for i in $(seq 1 60); do
        [ -f "$SETUP_MARKER" ] && break
        sleep 5
    done
    if [ ! -f "$SETUP_MARKER" ]; then
        echo "⚠ setup.sh 超时（5分钟），跳过服务启动" >&2
        echo "⚠ 请在新终端运行: bash .devcontainer/setup.sh" >&2
        exit 0
    fi
fi

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
        nohup sudo tailscaled </dev/null > "$LOG_DIR/tailscale.log" 2>&1 &
        disown
        sleep 2
    fi

    if pgrep -x tailscaled >/dev/null 2>&1; then
        # 检查是否已认证连接
        if sudo tailscale status >/dev/null 2>&1; then
            record "Tailscale" "ok" "" "已连接"
        else
            record "Tailscale" "fail" "$LOG_DIR/tailscale.log" \
                "守护进程运行中但未认证，需要运行: sudo tailscale up --ssh"
        fi
    else
        record "Tailscale" "fail" "$LOG_DIR/tailscale.log" "tailscaled 启动失败"
    fi
else
    record "Tailscale" "skip" "" "未安装"
fi

# ===== 2. OmniRoute =====
if command -v omniroute &>/dev/null; then
    if curl -s -o /dev/null -w "" --connect-timeout 1 --max-time 2 "http://localhost:20128" 2>/dev/null; then
        record "OmniRoute" "ok" "" "http://localhost:20128"
    else
        omniroute serve --daemon > "$LOG_DIR/omniroute.log" 2>&1
        sleep 3
        if curl -s -o /dev/null -w "" --connect-timeout 2 --max-time 3 "http://localhost:20128" 2>/dev/null; then
            record "OmniRoute" "ok" "" "http://localhost:20128"
        else
            record "OmniRoute" "fail" "$LOG_DIR/omniroute.log" "启动失败"
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
        tmux new-session -d -s "$name" \
            "bash -c '$cmd 2>&1 | tee \"$LOG_DIR/${name}.log\"; sleep infinity'"
        sleep 2
        if pgrep -f "$proc" >/dev/null 2>&1; then
            record "$label" "ok" "" "已启动"
        else
            record "$label" "fail" "$LOG_DIR/${name}.log" "启动失败"
        fi
    fi
}

# ===== 4. CloudCLI =====
_tmux_run cloudcli "cloudcli" "cloudcli" "CloudCLI" 3001

# ===== 写入状态文件（供 ~/.bashrc 登录时显示） =====
{
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
                if [ -n "$_log" ] && [ -f "$_log" ]; then
                    echo "     📄 日志: $_log"
                    # 显示最后 5 行错误信息
                    _tail=$(tail -5 "$_log" 2>/dev/null | sed 's/^/        /')
                    [ -n "$_tail" ] && echo "$_tail"
                fi
                ;;
            skip)
                echo "  ⏭  $_name — $_hint"
                ;;
        esac
    done

    echo ""
    echo "  🕐 $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="
} > "$STATUS_FILE"

# 同时输出到 stderr（devcontainer 日志可查）
cat "$STATUS_FILE" >&2
