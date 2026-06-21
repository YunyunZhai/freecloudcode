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

    # 确保 tailscaled 守护进程已启动
    tailscale_ensure_daemon

    # 已认证
    if sudo tailscale status >/dev/null 2>&1; then
        log_success "Tailscale 已认证连接"
        return 0
    fi

    # 尝试 authkey
    if tailscale_auth; then
        log_success "Tailscale 认证成功"
        return 0
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

# 安装 OpenCode CLI
install_opencode() {
    if check_command opencode; then
        log_success "OpenCode CLI 已存在"
        return 0
    fi

    if curl -fsSL https://opencode.ai/install | bash 2>/dev/null; then
        # 立即更新 PATH，确保后续 check_command 能找到
        export PATH="$HOME/.opencode/bin:$PATH"
        log_success "OpenCode CLI 已安装"
        return 0
    else
        log_warn "OpenCode CLI 安装失败"
        return 1
    fi
}

# 安装 npm 全局工具
install_npm_packages() {
    local failed=0

    for pkg in "${NPM_PACKAGES[@]}"; do
        local pkg_name="${pkg%%:*}"
        local bin_name
        bin_name=$(npm_bin_name "$pkg")

        if check_command "$bin_name" 2>/dev/null; then
            log_success "$pkg_name 已存在"
        elif npm install -g "$pkg_name" 2>&1 | tail -1 >/dev/null; then
            log_success "$pkg_name 已安装"
        else
            log_warn "$pkg_name 安装失败"
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
    local log_file="$LOG_DIR/setup.log"
    local fail_count_file="$LOG_DIR/.fail_count"
    ensure_dir "$LOG_DIR"

    echo "0" > "$fail_count_file"

    # 输出同时显示在终端和写入日志文件
    {
        install_system_deps || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_tailscale || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        auth_tailscale || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_claude || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_opencode || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        install_npm_packages || { echo $(( $(cat "$fail_count_file") + 1 )) > "$fail_count_file"; }
        create_directories

        configure_claude_code_hooks
    } 2>&1 | tee "$log_file"

    cat "$fail_count_file"
}

# 配置 Claude Code hooks（SessionStart + Stop + SessionEnd hook）
configure_claude_code_hooks() {
    local settings="$HOME/.claude/settings.json"
    ensure_dir "$HOME/.claude"

    if [ -f "$settings" ]; then
        if ! jq -e '.hooks.SessionStart' "$settings" >/dev/null 2>&1; then
            # 没有 SessionStart hook，追加（同时添加 Stop hook）
            jq '.hooks += {
                    "SessionStart": [{"hooks": [{"type": "command", "command": "claude-sync pull", "timeout": 30, "statusMessage": "🔄 同步云端配置..."}]}],
                    "Stop": [{"hooks": [{"type": "command", "command": "claude-sync push -q", "timeout": 30, "statusMessage": "📤 推送本地配置..."}]}],
                    "SessionEnd": [{"hooks": [{"type": "command", "command": "claude-sync push -q", "timeout": 30, "statusMessage": "📤 推送本地配置..."}]}]
                  }' \
               "$settings" > "${settings}.tmp" && mv "${settings}.tmp" "$settings"
            log_success "Claude Code hooks 已配置（SessionStart + Stop + SessionEnd）"
        fi
    else
        cat > "$settings" << EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "claude-sync pull",
            "timeout": 30,
            "statusMessage": "🔄 同步云端配置..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "claude-sync push -q",
            "timeout": 30,
            "statusMessage": "📤 推送本地配置..."
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "claude-sync push -q",
            "timeout": 30,
            "statusMessage": "📤 推送本地配置..."
          }
        ]
      }
    ]
  }
}
EOF
        log_success "Claude Code hooks 已配置（SessionStart + Stop + SessionEnd）"
    fi
}
