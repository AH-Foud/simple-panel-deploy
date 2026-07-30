# Simple Panel Deploy v2

**One command → a beautiful web panel on your Linux VPS.**

Zero dependencies. Pure Python 3 standard library. Always works.

## Features

- **Auto-detects** VPS IP using multiple services (manual fallback available)
- **IP or Subdomain** access modes
- **Random high port** assignment (15000–55000)
- **Glassmorphism UI** with live uptime counter
- **Systemd service** — auto-start on boot, restart on crash
- **UFW integration** — auto-opens firewall port
- **Zero dependencies** — only Python 3 required (pre-installed on Ubuntu)

## Quick Install

```bash
sudo bash -c "$(curl -s https://raw.githubusercontent.com/AH-Foud/simple-panel-deploy/main/install.sh)"
```

## Requirements

- Ubuntu / Debian (any version with Python 3)
- Root (sudo) access
- Python 3 (installed automatically if missing)

## What It Does

1. Detects VPS IP (4 services + manual fallback)
2. Asks: IP or subdomain?
3. If subdomain → DNS setup warning (especially Cloudflare)
4. Assigns random port
5. Creates Python HTTP server using stdlib
6. Sets up systemd service
7. Starts and verifies the panel

## Access

```
http://<IP_OR_DOMAIN>:<PORT>
```

The panel shows hostname, IP, port, and live uptime. A `/health` endpoint returns JSON status.

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
| `/etc/systemd/system/simple-panel.service` | Systemd unit |

## License

MIT
