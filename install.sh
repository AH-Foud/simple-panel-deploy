#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}     ${BOLD}Simple Panel Deploy v1.0${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
}

banner

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root!${NC}"
    echo -e "${YELLOW}  Run: sudo bash install.sh${NC}"
    exit 1
fi

# --- Detect OS ---
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        echo -e "${YELLOW}Warning: This script is tested on Ubuntu/Debian.${NC}"
        echo -e "${YELLOW}  Detected: $PRETTY_NAME${NC}"
        read -p "Continue anyway? [y/N]: " CONT
        if [[ ! "$CONT" =~ ^[Yy]$ ]]; then exit 0; fi
    fi
fi

# --- Detect VPS IP ---
echo -e "${CYAN}[1/6]${NC} Detecting VPS IP address..."

VPS_IP=""
for svc in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://checkip.amazonaws.com"; do
    VPS_IP=$(curl -s --connect-timeout 5 "$svc" 2>/dev/null)
    if [[ -n "$VPS_IP" ]] && [[ "$VPS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
done

if [[ -z "$VPS_IP" ]]; then
    echo -e "${RED}Could not detect VPS IP automatically.${NC}"
    read -p "Please enter your VPS IP manually: " VPS_IP
    if [[ ! "$VPS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Invalid IP format. Exiting.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}  VPS IP: ${BOLD}${VPS_IP}${NC}"

# --- Choose access method ---
echo ""
echo -e "${CYAN}[2/6]${NC} How do you want to access the panel?"
echo ""
echo -e "  ${BOLD}1)${NC} Direct IP   ->   http://${VPS_IP}:PORT"
echo -e "  ${BOLD}2)${NC} Subdomain    ->   http://your-subdomain.example.com:PORT"
echo ""
read -p "Enter your choice [1 or 2]: " ACCESS_CHOICE

HOST="$VPS_IP"
if [[ "$ACCESS_CHOICE" == "2" ]]; then
    echo ""
    read -p "Enter your subdomain (e.g. panel.yourdomain.com): " SUBDOMAIN
    
    if [[ -z "$SUBDOMAIN" ]]; then
        echo -e "${RED}No subdomain entered. Exiting.${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${YELLOW}============================================${NC}"
    echo -e "${YELLOW}  !!  BEFORE CONTINUING - DNS CHECK${NC}"
    echo -e "${YELLOW}============================================${NC}"
    echo ""
    echo -e "  Make sure you have created an ${BOLD}A record${NC} in your DNS:"
    echo -e "    ${CYAN}${SUBDOMAIN}${NC}  ->  ${CYAN}${VPS_IP}${NC}"
    echo ""
    echo -e "  ${YELLOW}Important for Cloudflare users:${NC}"
    echo -e "    - Use ${BOLD}DNS only${NC} (gray cloud) for custom ports to work"
    echo -e "    - Proxy (orange cloud) only works on standard ports 80/443"
    echo ""
    
    read -p "Have you already set up the DNS A record? [y/N]: " DNS_OK
    if [[ ! "$DNS_OK" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Please set up the DNS record first, then re-run this script.${NC}"
        exit 1
    fi
    
    HOST="$SUBDOMAIN"
fi

# --- Pick random port ---
echo ""
echo -e "${CYAN}[3/6]${NC} Assigning a random port..."

if command -v shuf &>/dev/null; then
    PANEL_PORT=$(shuf -i 10000-60000 -n 1)
else
    PANEL_PORT=$(( 10000 + (RANDOM % 50000) ))
fi

echo -e "${GREEN}  Port: ${BOLD}${PANEL_PORT}${NC}"

# --- Summary ---
echo ""
echo -e "${CYAN}[4/6]${NC} Installation summary:"
echo ""
echo -e "  Access URL:   ${BOLD}http://${HOST}:${PANEL_PORT}${NC}"
echo -e "  Install dir:  ${BOLD}/opt/simple-panel${NC}"
echo -e "  Service:      ${BOLD}simple-panel (systemd)${NC}"
echo ""

read -p "Proceed with installation? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# --- Install dependencies ---
echo ""
echo -e "${CYAN}[5/6]${NC} Installing dependencies..."

apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip curl > /dev/null 2>&1
echo -e "${GREEN}  System packages installed${NC}"

# --- Create app ---
APP_DIR="/opt/simple-panel"
mkdir -p "$APP_DIR"

python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install flask --quiet 2>&1 | grep -v "WARNING: You are using pip"
echo -e "${GREEN}  Python & Flask installed${NC}"

cat > "$APP_DIR/app.py" << 'PYEOF'
from flask import Flask, render_template_string
import socket, os, datetime

app = Flask(__name__)

HTML = r'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Panel - {{ host }}</title>
    <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{
            font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
            background:linear-gradient(135deg,#0d0d2b,#1a1a4e,#0d0d2b);
            min-height:100vh;display:flex;align-items:center;justify-content:center;
            color:#e0e0e0;
        }
        .card{
            background:rgba(255,255,255,0.04);
            backdrop-filter:blur(20px);
            -webkit-backdrop-filter:blur(20px);
            border-radius:20px;padding:50px 40px;text-align:center;
            border:1px solid rgba(255,255,255,0.08);
            box-shadow:0 25px 80px rgba(0,0,0,0.5);
            max-width:480px;width:90%;
        }
        .icon{font-size:60px;margin-bottom:16px}
        h1{
            font-size:26px;font-weight:700;margin-bottom:8px;
            background:linear-gradient(90deg,#6c63ff,#a78bfa);
            -webkit-background-clip:text;-webkit-text-fill-color:transparent;
        }
        .subtitle{font-size:14px;color:#888;margin-bottom:24px}
        .status{
            display:inline-flex;align-items:center;gap:8px;
            background:rgba(34,197,94,0.12);
            border:1px solid rgba(34,197,94,0.3);
            border-radius:20px;padding:10px 24px;margin-bottom:28px;
            font-size:14px;color:#4ade80;
        }
        .dot{width:9px;height:9px;background:#22c55e;border-radius:50%;animation:pulse 2s infinite}
        @keyframes pulse{0%,100%{opacity:1;box-shadow:0 0 8px #22c55e}50%{opacity:.4;box-shadow:0 0 2px #22c55e}}
        .info-grid{
            display:grid;grid-template-columns:1fr 1fr;gap:12px;
            margin-top:10px;text-align:left;
        }
        .info-item{
            background:rgba(255,255,255,0.03);
            border-radius:12px;padding:14px 16px;
            border:1px solid rgba(255,255,255,0.05);
        }
        .info-item .label{font-size:11px;color:#666;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px}
        .info-item .value{font-size:15px;color:#ccc;font-weight:500;word-break:break-all}
        .footer{margin-top:24px;font-size:12px;color:#555}
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">&#x1F680;</div>
        <h1>Panel is Running</h1>
        <div class="subtitle">{{ host }}</div>
        <div class="status"><span class="dot"></span> Online &amp; Healthy</div>
        <div class="info-grid">
            <div class="info-item">
                <div class="label">Hostname</div>
                <div class="value">{{ hostname }}</div>
            </div>
            <div class="info-item">
                <div class="label">IP Address</div>
                <div class="value">{{ ip }}</div>
            </div>
            <div class="info-item">
                <div class="label">Port</div>
                <div class="value">{{ port }}</div>
            </div>
            <div class="info-item">
                <div class="label">Uptime</div>
                <div class="value">{{ uptime }}</div>
            </div>
        </div>
        <div class="footer">Simple Panel Deploy v1.0 &middot; {{ date }}</div>
    </div>
</body>
</html>'''

start_time = datetime.datetime.now()

@app.route('/')
def index():
    uptime = datetime.datetime.now() - start_time
    hours, rem = divmod(int(uptime.total_seconds()), 3600)
    mins, secs = divmod(rem, 60)
    return render_template_string(
        HTML,
        host=os.environ.get('PANEL_HOST', 'N/A'),
        hostname=socket.gethostname(),
        ip=os.environ.get('PANEL_IP', 'N/A'),
        port=os.environ.get('PANEL_PORT', 'N/A'),
        uptime=f"{hours}h {mins}m {secs}s",
        date=datetime.datetime.now().strftime('%Y-%m-%d %H:%M UTC')
    )

@app.route('/health')
def health():
    return {"status": "ok", "uptime": str(datetime.datetime.now() - start_time)}

if __name__ == '__main__':
    port = int(os.environ.get('PANEL_PORT', 8080))
    app.run(host='0.0.0.0', port=port)
PYEOF

echo -e "${GREEN}  Panel app created${NC}"

# --- Create systemd service ---
cat > /etc/systemd/system/simple-panel.service << SERVEOF
[Unit]
Description=Simple Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/simple-panel
Environment="PANEL_IP=${VPS_IP}"
Environment="PANEL_PORT=${PANEL_PORT}"
Environment="PANEL_HOST=${HOST}"
ExecStart=/opt/simple-panel/venv/bin/python /opt/simple-panel/app.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVEOF

systemctl daemon-reload
systemctl enable simple-panel > /dev/null 2>&1
echo -e "${GREEN}  Systemd service created${NC}"

# --- Start service ---
echo ""
echo -e "${CYAN}[6/6]${NC} Starting panel..."

systemctl start simple-panel
sleep 2

# --- Verify ---
if systemctl is-active --quiet simple-panel; then
    if curl -s --connect-timeout 3 "http://127.0.0.1:${PANEL_PORT}/health" 2>/dev/null | grep -q "ok"; then
        echo -e "${GREEN}  Panel is running and responding!${NC}"
    else
        echo -e "${YELLOW}  Service is active but health check failed (may be normal).${NC}"
    fi
    
    # --- Firewall ---
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${YELLOW}  Opening port ${PANEL_PORT} in UFW...${NC}"
        ufw allow ${PANEL_PORT}/tcp > /dev/null 2>&1
        echo -e "${GREEN}  Port ${PANEL_PORT} opened${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}     PANEL INSTALLED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "  Access URL:"
    echo -e "      ${CYAN}http://${HOST}:${PANEL_PORT}${NC}"
    echo ""
    echo -e "  Useful commands:"
    echo -e "      systemctl status simple-panel"
    echo -e "      systemctl restart simple-panel"
    echo -e "      systemctl stop simple-panel"
    echo -e "      journalctl -u simple-panel -f"
    echo ""
    
    if command -v ufw &>/dev/null && ! ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "  ${YELLOW}Note: UFW is not active. Make sure port ${PANEL_PORT} is${NC}"
        echo -e "  ${YELLOW}open in your cloud provider's security group / firewall.${NC}"
        echo ""
    fi
    
    echo -e "  ${GREEN}Enjoy!${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}     PANEL FAILED TO START!${NC}"
    echo -e "${RED}============================================${NC}"
    echo ""
    echo -e "  Check logs:"
    echo -e "  ${YELLOW}journalctl -u simple-panel -n 50 --no-pager${NC}"
    echo ""
    exit 1
fi
