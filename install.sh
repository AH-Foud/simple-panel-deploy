#!/bin/bash

# ============================================
#  Simple Panel Deploy v2.0
#  Pure Python stdlib - zero dependencies
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${RED}[X]${NC} $1"; }

banner() {
    echo ""
    echo -e "${CYAN}  ==========================================${NC}"
    echo -e "${CYAN}     Simple Panel Deploy v2.0${NC}"
    echo -e "${CYAN}  ==========================================${NC}"
    echo ""
}

banner

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    log_err "This script must be run as root!"
    echo -e "${YELLOW}       Run: sudo bash install.sh${NC}"
    exit 1
fi

# --- Check Python3 ---
if ! command -v python3 &>/dev/null; then
    log_info "Python3 not found, installing..."
    apt-get update -qq
    apt-get install -y -qq python3 || {
        log_err "Failed to install python3"
        exit 1
    }
fi
log_ok "Python3: $(python3 --version)"

# --- Detect VPS IP ---
log_info "Detecting VPS IP address..."

VPS_IP=""
for svc in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://checkip.amazonaws.com"; do
    IP_CANDIDATE=$(curl -s --connect-timeout 5 --max-time 10 "$svc" 2>/dev/null)
    if [[ -n "$IP_CANDIDATE" ]] && [[ "$IP_CANDIDATE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        VPS_IP="$IP_CANDIDATE"
        break
    fi
done

if [[ -z "$VPS_IP" ]]; then
    log_warn "Could not auto-detect IP."
    read -p "Enter your VPS IP manually: " VPS_IP
    if [[ ! "$VPS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_err "Invalid IP format. Exiting."
        exit 1
    fi
fi

log_ok "VPS IP: ${BOLD}${VPS_IP}${NC}"

# --- Choose access method ---
echo ""
log_info "How do you want to access the panel?"
echo ""
echo -e "  ${BOLD}1)${NC} Direct IP   ->   http://${VPS_IP}:PORT"
echo -e "  ${BOLD}2)${NC} Subdomain    ->   http://your-domain.com:PORT"
echo ""
read -p "Enter your choice [1 or 2]: " ACCESS_CHOICE

HOST="$VPS_IP"
if [[ "$ACCESS_CHOICE" == "2" ]]; then
    echo ""
    read -p "Enter your subdomain (e.g. panel.example.com): " SUBDOMAIN
    
    if [[ -z "$SUBDOMAIN" ]]; then
        log_err "No subdomain entered. Exiting."
        exit 1
    fi
    
    echo ""
    echo -e "${YELLOW}  ==========================================${NC}"
    echo -e "${YELLOW}   !!  DNS CHECK BEFORE CONTINUING${NC}"
    echo -e "${YELLOW}  ==========================================${NC}"
    echo ""
    echo -e "  Make sure this A record exists in your DNS:"
    echo ""
    echo -e "    ${BOLD}${SUBDOMAIN}${NC}  ->  ${BOLD}${VPS_IP}${NC}"
    echo ""
    echo -e "  ${YELLOW}Cloudflare users:${NC}"
    echo -e "    Use DNS-only mode (gray cloud) for custom ports."
    echo ""
    
    read -p "DNS record already set? [y/N]: " DNS_OK
    if [[ ! "$DNS_OK" =~ ^[Yy]$ ]]; then
        log_warn "Set up the DNS A record first, then re-run this script."
        exit 0
    fi
    
    HOST="$SUBDOMAIN"
fi

# --- Pick random port ---
echo ""
log_info "Assigning a random port..."

PANEL_PORT=$(( 15000 + (RANDOM % 40000) ))
log_ok "Port: ${BOLD}${PANEL_PORT}${NC}"

# --- Summary ---
echo ""
echo -e "${CYAN}  --- Installation Summary ---${NC}"
echo -e "  URL:      ${BOLD}http://${HOST}:${PANEL_PORT}${NC}"
echo -e "  App dir:  /opt/simple-panel"
echo -e "  Service:  simple-panel (systemd)"
echo ""

read -p "Proceed with install? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# ============================================
#  INSTALL
# ============================================

APP_DIR="/opt/simple-panel"
log_info "Creating app directory..."
mkdir -p "$APP_DIR"

# --- Write Python server ---
log_info "Writing server code..."

cat > "$APP_DIR/server.py" << 'PYEOF'
import http.server
import os
import socket
import json
from datetime import datetime

PORT = int(os.environ.get('PANEL_PORT', '8080'))
HOST = os.environ.get('PANEL_HOST', 'N/A')
IP   = os.environ.get('PANEL_IP', 'N/A')
START_TIME = datetime.now()

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Panel | {{HOST}}</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  background:linear-gradient(135deg,#0a0a1a,#121240,#0a0a1a);
  min-height:100vh;display:flex;align-items:center;justify-content:center;
  color:#e0e0e0;
}
.card{
  background:rgba(255,255,255,0.03);
  backdrop-filter:blur(24px);
  -webkit-backdrop-filter:blur(24px);
  border-radius:24px;padding:50px 44px;text-align:center;
  border:1px solid rgba(255,255,255,0.06);
  box-shadow:0 30px 80px rgba(0,0,0,0.6);
  max-width:500px;width:90%;
}
.icon{font-size:64px;margin-bottom:20px}
h1{font-size:28px;font-weight:700;margin-bottom:6px;
  background:linear-gradient(90deg,#7c3aed,#a78bfa);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;
}
.subtitle{font-size:15px;color:#777;margin-bottom:28px;word-break:break-all}
.badge{
  display:inline-flex;align-items:center;gap:10px;
  background:rgba(34,197,94,0.1);
  border:1px solid rgba(34,197,94,0.25);
  border-radius:30px;padding:12px 28px;margin-bottom:32px;
  font-size:15px;color:#4ade80;font-weight:500;
}
.pulse{width:10px;height:10px;background:#22c55e;border-radius:50%;
  animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1;box-shadow:0 0 10px #22c55e}
  50%{opacity:.3;box-shadow:0 0 3px #22c55e}}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:4px;text-align:left}
.cell{
  background:rgba(255,255,255,0.02);
  border-radius:14px;padding:16px 18px;
  border:1px solid rgba(255,255,255,0.04);
}
.cell .lbl{font-size:10px;color:#555;text-transform:uppercase;
  letter-spacing:0.6px;margin-bottom:5px}
.cell .val{font-size:15px;color:#bbb;font-weight:500;word-break:break-all}
.foot{margin-top:28px;font-size:12px;color:#444}
</style>
</head>
<body>
<div class="card">
  <div class="icon">&#x1F680;</div>
  <h1>Panel is Running</h1>
  <div class="subtitle">{{HOST}}</div>
  <div class="badge"><span class="pulse"></span> Online &amp; Healthy</div>
  <div class="grid">
    <div class="cell"><div class="lbl">Hostname</div><div class="val">{{HOSTNAME}}</div></div>
    <div class="cell"><div class="lbl">IP Address</div><div class="val">{{IP}}</div></div>
    <div class="cell"><div class="lbl">Port</div><div class="val">{{PORT}}</div></div>
    <div class="cell"><div class="lbl">Uptime</div><div class="val">{{UPTIME}}</div></div>
  </div>
  <div class="foot">Simple Panel Deploy v2.0 &middot; {{DATE}}</div>
</div>
</body>
</html>"""

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            uptime = str(datetime.now() - START_TIME)
            body = json.dumps({"status":"ok","uptime":uptime}).encode()
            self.send_response(200)
            self.send_header('Content-Type','application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        uptime = datetime.now() - START_TIME
        h, r = divmod(int(uptime.total_seconds()), 3600)
        m, s = divmod(r, 60)

        page = (HTML
            .replace('{{HOST}}', HOST)
            .replace('{{HOSTNAME}}', socket.gethostname())
            .replace('{{IP}}', IP)
            .replace('{{PORT}}', str(PORT))
            .replace('{{UPTIME}}', f"{h}h {m}m {s}s")
            .replace('{{DATE}}', datetime.now().strftime('%Y-%m-%d %H:%M UTC')))

        body = page.encode()
        self.send_response(200)
        self.send_header('Content-Type','text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass  # suppress access logs

if __name__ == '__main__':
    httpd = http.server.HTTPServer(('0.0.0.0', PORT), Handler)
    print(f"Server started on port {PORT}", flush=True)
    httpd.serve_forever()
PYEOF

log_ok "Server code written"

# --- Test Python syntax ---
if python3 -c "import py_compile; py_compile.compile('$APP_DIR/server.py', doraise=True)" 2>/dev/null; then
    log_ok "Python syntax check passed"
else
    log_err "Python syntax error in server.py. This should not happen."
    exit 1
fi

# --- Create systemd service ---
log_info "Creating systemd service..."

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
ExecStart=/usr/bin/python3 /opt/simple-panel/server.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVEOF

systemctl daemon-reload
systemctl enable simple-panel 2>/dev/null
log_ok "Systemd service created and enabled"

# --- Start service ---
log_info "Starting panel..."
systemctl start simple-panel
sleep 3

# --- Verify ---
if systemctl is-active --quiet simple-panel; then
    # Health check
    if curl -s --connect-timeout 5 "http://127.0.0.1:${PANEL_PORT}/health" 2>/dev/null | grep -q '"ok"'; then
        log_ok "Panel is running and responding"
    else
        log_warn "Service active but health check failed (firewall may block localhost)"
    fi
    
    # UFW
    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            ufw allow ${PANEL_PORT}/tcp 2>/dev/null
            log_ok "Port ${PANEL_PORT} opened in UFW"
        fi
    fi
    
    # Success
    echo ""
    echo -e "${GREEN}  ==========================================${NC}"
    echo -e "${GREEN}    PANEL INSTALLED SUCCESSFULLY${NC}"
    echo -e "${GREEN}  ==========================================${NC}"
    echo ""
    echo -e "  ${BOLD}Access URL:${NC}"
    echo -e "    ${CYAN}http://${HOST}:${PANEL_PORT}${NC}"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    systemctl status simple-panel"
    echo -e "    systemctl restart simple-panel"
    echo -e "    journalctl -u simple-panel -f"
    echo ""
    
    if ! command -v ufw &>/dev/null || ! ufw status 2>/dev/null | grep -q "Status: active"; then
        log_warn "Make sure port ${PANEL_PORT}/tcp is open in your cloud firewall"
        echo ""
    fi
else
    # Failure
    echo ""
    echo -e "${RED}  ==========================================${NC}"
    echo -e "${RED}    PANEL FAILED TO START${NC}"
    echo -e "${RED}  ==========================================${NC}"
    echo ""
    echo -e "  Debug info:"
    echo ""
    journalctl -u simple-panel -n 20 --no-pager 2>/dev/null || true
    echo ""
    echo -e "  ${YELLOW}Check: python3 /opt/simple-panel/server.py${NC}"
    exit 1
fi
