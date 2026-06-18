# FreeCloudCode

A pre-configured GitHub Codespace with all your favorite cloud development tools. Open a Codespace and everything is ready.

## What's Included

| Tool | Command | Alias |
|------|---------|-------|
| Claude Code | `claude` | `cc` |
| OpenAI Codex | `codex` | `codex` |
| OmniRoute | `omniroute` | `oc` |
| Tailscale | `tailscale` | — |
| CloudCLI | `cloudcli` | `ccli` |
| CCPocket | `ccpocket` | `pocket` |

## Quick Start

1. Click **Code** → **Codespaces** → **Create codespace on main**
2. Wait for first-time setup (~2 min, installs tools)
3. Done! All tools are ready.

## Services

On every restart, **OmniRoute** (daemon) and **CloudCLI** (tmux) auto-start. Manage them with:

```
scc  — start CloudCLI    xcc — stop
sbp  — start Bridge      xbp — stop
cr   — reconnect Claude session
```

## How It Works

- `.devcontainer/devcontainer.json` — Codespace config (host mode, no Docker)
- `.devcontainer/setup.sh` — **one-time** install (runs on first creation via `onCreateCommand`)
- `.devcontainer/start.sh` — **every boot** startup (runs via `postStartCommand`)

## 首次配置

```bash
sudo tailscale up --ssh    # Tailscale 认证
oc                         # 按提示配置 OmniRoute API key
```