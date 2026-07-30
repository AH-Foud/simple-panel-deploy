# Simple Panel Deploy

**One-command installer for a web panel on any Linux VPS.**

Just run one command and get a beautiful web panel running on your VPS in seconds.

## Features

- **Auto-detects** your VPS IP address (tries multiple IP-check services)
- **IP or Subdomain** - choose how to access your panel
- **Random port** - automatic high-port assignment (10000-60000)
- **Modern UI** - glassmorphism design with gradient background
- **Systemd service** - auto-starts on boot, restarts on failure
- **UFW integration** - auto-opens firewall port if UFW is active

## Requirements

- Ubuntu or Debian (other distros may work)
- Root access (sudo)
- Internet connection

## Quick Install

```bash
bash <(curl -s https://raw.githubusercontent.com/AH-Foud/simple-panel-deploy/main/install.sh)
```

Or clone and run:

```bash
git clone https://github.com/AH-Foud/simple-panel-deploy.git
cd simple-panel-deploy
sudo bash install.sh
```

## What Happens During Install

The installer will:

1. **Detect** your VPS IP using multiple IP-check services (with manual fallback)
2. **Ask** whether you want IP-based or subdomain-based access
3. **Warn** about DNS setup if using subdomain (especially Cloudflare)
4. **Assign** a random high port (10000-60000)
5. **Install** Python venv + Flask and create the panel app
6. **Create** a systemd service and start it
7. **Verify** the panel is running with a health check

## Access Options

### Option 1: Direct IP
```
http://YOUR_VPS_IP:RANDOM_PORT
```

### Option 2: Subdomain
First, create an **A record** in your DNS pointing to your VPS IP, then:
```
http://your-subdomain.example.com:RANDOM_PORT
```

> **Cloudflare users:** If using Cloudflare proxy (orange cloud), custom ports won't work. Use **DNS only** mode (gray cloud) or stick to Cloudflare-supported ports.

## Installation Details

| What | Where |
|------|-------|
| App directory | `/opt/simple-panel/` |
| Python venv | `/opt/simple-panel/venv/` |
| Systemd service | `/etc/systemd/system/simple-panel.service` |

## Manage the Panel

```bash
# Check status
systemctl status simple-panel

# Restart
systemctl restart simple-panel

# Stop
systemctl stop simple-panel

# View logs
journalctl -u simple-panel -f
```

## What the Panel Shows

- Online/Healthy status indicator with pulse animation
- Server hostname & IP
- Running port
- Uptime counter
- `/health` endpoint for monitoring

## License

MIT
