# KMPanel Deploy v3

**One command → a login-protected web dashboard on your Linux VPS.**

Zero dependencies. Pure Python 3 standard library. Includes the `kmpanel` CLI tool for managing credentials from the terminal.

## Features

- **Login page** — username/password authentication with session management
- **Session cookies** — secure HttpOnly cookies, 24h timeout
- **Modern UI** — glassmorphism design with gradient backgrounds
- **Auto-detects** VPS IP using 4 services (manual fallback available)
- **IP or Subdomain** access modes
- **Random high port** assignment (15000–55000)
- **Systemd service** — auto-start on boot, restart on crash
- **UFW integration** — auto-opens firewall port
- **`kmpanel` CLI** — view/reset credentials from terminal
- **Zero dependencies** — only Python 3 required

## Quick Install

```bash
sudo bash -c "$(curl -s https://raw.githubusercontent.com/AH-Foud/simple-panel-deploy/main/install.sh)"
```

## Requirements

- Ubuntu / Debian
- Root (sudo) access
- Python 3 (installed automatically if missing)

## kmpanel CLI

After installation, use the `kmpanel` command from anywhere:

```bash
kmpanel                 # Show status, URL, username & password
kmpanel reset           # Reset password (needs sudo)
kmpanel url             # Print the panel URL only
kmpanel restart         # Restart the panel service
kmpanel help            # Show help
```

## Access

Open the URL shown after installation in your browser. You'll see a **login page**:

1. Enter the username and password shown during install
2. After login, you'll see the dashboard with system info and uptime
3. Sessions last 24 hours

## Cloudflare Note

If using Cloudflare proxy (orange cloud), use **DNS-only mode** (gray cloud) — custom ports don't work through the proxy.

## Manage

```bash
systemctl status simple-panel    # check status
systemctl restart simple-panel   # restart
systemctl stop simple-panel      # stop
journalctl -u simple-panel -f    # live logs
```

## Files

| Path | Purpose |
|------|---------|
| `/opt/simple-panel/server.py` | The panel server |
| `/opt/simple-panel/.credentials` | Username & password (root-only) |
| `/opt/simple-panel/.config` | Host & port config |
| `/usr/local/bin/kmpanel` | CLI management tool |
| `/etc/systemd/system/simple-panel.service` | Systemd unit |

## License

MIT
