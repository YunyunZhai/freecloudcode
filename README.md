# FreeCloudCode

A pre-configured GitHub Codespace with all your favorite cloud development tools. Open a Codespace and everything is ready.

## What's Included

| Tool | Command | Alias |
|------|---------|-------|
| Claude Code | `claude` | `cc` |
| OpenAI Codex | `openai-codex` | `codex` |
| OmniRoute | `omniroute` | `oc` |
| Tailscale | `tailscale` | — |
| CloudCLI | `cloudcli` | `ccli` |
| CCPocket | `ccpocket` | `pocket` |

## Quick Start

1. Click **Code** → **Codespaces** → **Create codespace on main**
2. Wait for first-time setup (~2 min, installs tools)
3. Done! All tools are ready.

## Services

On startup, **OmniRoute** and **CloudCLI** auto-launch in tmux sessions. Manage them with:

```
cc   — start CloudCLI    xcc — stop
cp   — start Bridge      xcp — stop
cr   — reconnect Claude session
```

## How It Works

- `.devcontainer/devcontainer.json` — Codespace config (host mode, no Docker)
- `.devcontainer/startservice.sh` — runs on every startup, installs tools + starts services
