#!/bin/bash
# lib/install.sh — FreeCloudCode 安装函数

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# 安装系统依赖
install_system_deps() {
    if ! sudo apt-get update -qq 2>/dev/null; then
        log_warn "apt-get update 失败"
        return 1
    fi

    if sudo apt-get install -y -qq tmux curl wget jq >/dev/null 2>&1; then
        log_success "系统依赖已就绪"
        return 0
    else
        log_warn "系统依赖安装失败"
        return 1
    fi
}

# 安装 Tailscale
install_tailscale() {
    if check_command tailscale; then
        log_success "Tailscale 已存在 ($(tailscale version | head -1))"
        return 0
    fi

    if curl -fsSL https://tailscale.com/install.sh | sh 2>/dev/null; then
        log_success "Tailscale 已安装"
        return 0
    else
        log_warn "Tailscale 安装失败"
        return 1
    fi
}

# 认证 Tailscale
auth_tailscale() {
    if ! check_command tailscale; then
        log_warn "Tailscale 未安装，跳过认证"
        return 1
    fi

    # 已认证
    if sudo tailscale status >/dev/null 2>&1; then
        log_success "Tailscale 已认证连接"
        return 0
    fi

    # 尝试 authkey
    if [ -n "$TAILSCALEAUTHKEY" ]; then
        if sudo tailscale up --ssh --authkey="$TAILSCALEAUTHKEY" 2>/dev/null; then
            log_success "Tailscale 认证成功"
            return 0
        fi
    fi

    log_warn "Tailscale 未认证（需手动运行: sudo tailscale up --ssh）"
    return 1
}

# 安装 Claude Code
install_claude() {
    if check_command claude; then
        log_success "Claude Code 已存在"
        return 0
    fi

    if curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
        log_success "Claude Code 已安装"
        return 0
    else
        log_warn "Claude Code 安装失败"
        return 1
    fi
}

# 安装 npm 全局工具
install_npm_packages() {
    local packages=(
        "omniroute"
        "@cloudcli-ai/cloudcli"
        "@openai/codex"
        "@ccpocket/bridge"
        "@tawandotorg/claude-sync"
    )
    local failed=0

    for pkg in "${packages[@]}"; do
        # 取包名最后一段作为命令名（如 @openai/codex → codex）
        local bin_name="${pkg##*/}"
        if check_command "$bin_name" 2>/dev/null; then
            log_success "$pkg 已存在"
        elif npm install -g "$pkg" 2>&1 | tail -1 >/dev/null; then
            log_success "$pkg 已安装"
        else
            log_warn "$pkg 安装失败"
            failed=1
        fi
    done

    return $failed
}

# 创建目录结构
create_directories() {
    ensure_dir "$HOME/.freecloudcode/logs"
    ensure_dir "$HOME/.freecloudcode/config"

    # 初始化日志文件
    for logfile in claude_sync tailscale omniroute cloudcli bridge; do
        touch "$HOME/.freecloudcode/logs/${logfile}.log"
        chmod 644 "$HOME/.freecloudcode/logs/${logfile}.log"
    done

    log_success "目录结构已创建"
}

# 主安装流程
run_setup() {
    local failed=()

    # 将所有函数的 stdout 重定向到 stderr，避免 curl|sh 等命令的输出污染返回值
    {
        install_system_deps || failed+=("系统依赖")
        install_tailscale || failed+=("Tailscale")
        auth_tailscale || failed+=("Tailscale 认证")
        install_claude || failed+=("Claude Code")
        install_npm_packages || failed+=("npm 包")
        create_directories

        # 配置 Claude Code hooks
        configure_claude_code_hooks
    } 1>&2

    # 返回失败数量（只有这一行输出到 stdout）
    echo "${#failed[@]}"
}

# 配置 Claude Code hooks（Stop hook）
configure_claude_code_hooks() {
    local settings="$HOME/.claude/settings.json"
    ensure_dir "$HOME/.claude"

    local sync_cmd='if claude-sync status -q 2>/dev/null; then claude-sync pull -q && claude-sync push -q; fi'

    if [ -f "$settings" ]; then
        if ! jq -e '.hooks.Stop' "$settings" >/dev/null 2>&1; then
            # 没有 Stop hook，追加
            jq --arg cmd "$sync_cmd" \
               '.hooks += {"Stop": [{"hooks": [{"type": "command", "command": $cmd, "timeout": 30, "statusMessage": "claude-sync 同步中..."}]}]}' \
               "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
            log_success "Claude Code Stop hook 已配置"
        fi
    else
        cat > "$settings" << EOF
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$sync_cmd",
            "timeout": 30,
            "statusMessage": "claude-sync 同步中..."
          }
        ]
      }
    ]
  }
}
EOF
        log_success "Claude Code Stop hook 已配置"
    fi
}
