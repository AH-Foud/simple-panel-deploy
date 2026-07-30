#!/bin/bash

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

REPO_RAW="https://raw.githubusercontent.com/AH-Foud/simple-panel-deploy/main"
VIDEO_URL="https://app.zaro.ai/api/files/download?fid=a14f63fb-b9df-4a2a-b492-e8704b5eeaa4&exp=1785512902&sig=98_nsE9cHRZaOZQkISf3Hg"

banner() {
    echo ""
    echo -e "${CYAN}  ==========================================${NC}"
    echo -e "${CYAN}       KMPanel Deploy v4.0${NC}"
    echo -e "${CYAN}  ==========================================${NC}"
    echo ""
}

banner

if [[ $EUID -ne 0 ]]; then
    log_err "This script must be run as root!"
    echo -e "${YELLOW}       Run: sudo bash install.sh${NC}"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    log_info "Python3 not found, installing..."
    apt-get update -qq
    apt-get install -y -qq python3 || { log_err "Failed to install python3"; exit 1; }
fi
log_ok "Python3: $(python3 --version)"

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
    echo -e "    ${BOLD}${SUBDOMAIN}${NC}  ->  ${BOLD}${VPS_IP}${NC}"
    echo ""
    echo -e "  ${YELLOW}Cloudflare users: Use DNS-only mode (gray cloud).${NC}"
    echo ""
    read -p "DNS record already set? [y/N]: " DNS_OK
    if [[ ! "$DNS_OK" =~ ^[Yy]$ ]]; then
        log_warn "Set up the DNS A record first, then re-run this script."
        exit 0
    fi
    HOST="$SUBDOMAIN"
fi

echo ""
log_info "Assigning a random port..."
PANEL_PORT=$(( 15000 + (RANDOM % 40000) ))
log_ok "Port: ${BOLD}${PANEL_PORT}${NC}"

PANEL_USER="admin"
PANEL_PASS=$(openssl rand -base64 9 2>/dev/null || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits)for _ in range(12)))")

echo ""
echo -e "${CYAN}  --- Installation Summary ---${NC}"
echo -e "  URL:       ${BOLD}http://${HOST}:${PANEL_PORT}${NC}"
echo -e "  Username:  ${BOLD}${PANEL_USER}${NC}"
echo -e "  Password:  ${BOLD}${PANEL_PASS}${NC}"
echo -e "  CLI tool:  ${BOLD}kmpanel${NC}"
echo ""

read -p "Proceed with install? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
fi

APP_DIR="/opt/simple-panel"
log_info "Creating directories..."
mkdir -p "$APP_DIR/static"

cat > "$APP_DIR/.config" << EOF
HOST=${HOST}
PORT=${PANEL_PORT}
EOF
chmod 600 "$APP_DIR/.config"

echo "${PANEL_USER}:${PANEL_PASS}" > "$APP_DIR/.credentials"
chmod 600 "$APP_DIR/.credentials"
log_ok "Credentials saved"

log_info "Downloading server code..."
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/server.py" "${REPO_RAW}/server.py" || {
    log_err "Failed to download server.py"
    exit 1
}
log_ok "Server code downloaded"

log_info "Downloading logo..."
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/static/logo.png" "${REPO_RAW}/assets/logo.png" 2>/dev/null && {
    log_ok "Logo downloaded"
} || {
    log_warn "Logo download failed — skipping"
}

log_info "Downloading background video (may take a moment)..."
curl -s --connect-timeout 15 --max-time 120 -o "$APP_DIR/static/bg.mp4" "${VIDEO_URL}" 2>/dev/null && {
    VSIZE=$(stat -c%s "$APP_DIR/static/bg.mp4" 2>/dev/null || echo 0)
    if [[ "$VSIZE" -gt 10000 ]]; then
        log_ok "Video downloaded ($(( VSIZE / 1048576 ))MB)"
    else
        log_warn "Video download incomplete — using CSS background"
        rm -f "$APP_DIR/static/bg.mp4"
    fi
} || {
    log_warn "Video download failed — using CSS gradient background"
}

if python3 -c "import py_compile;py_compile.compile('$APP_DIR/server.py',doraise=True)" 2>/dev/null; then
    log_ok "Python syntax OK"
else
    log_err "Python syntax error in server.py"
    exit 1
fi

log_info "Installing kmpanel CLI..."
cat > /usr/local/bin/kmpanel << 'CLIEOF'
#!/bin/bash
APP_DIR="/opt/simple-panel"
CREDS_FILE="$APP_DIR/.credentials"
CONFIG_FILE="$APP_DIR/.config"
RED='\033[0;31m';GREEN='\033[0;32m';CYAN='\033[0;36m';BOLD='\033[1m';NC='\033[0m'
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}KMPanel is not installed. Run the installer first.${NC}"
    exit 1
fi
source <(grep -E '^(HOST|PORT)=' "$CONFIG_FILE")
USERNAME=$(cut -d: -f1 "$CREDS_FILE" 2>/dev/null)
PASSWORD=$(cut -d: -f2- "$CREDS_FILE" 2>/dev/null)

show_status() {
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║         ${BOLD}K M P a n e l${NC}${CYAN}          ║${NC}"
    echo -e "${CYAN}  ╚══════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Panel URL:${NC}"
    echo -e "    ${GREEN}http://${HOST}:${PORT}${NC}"
    echo ""
    echo -e "  ${BOLD}Username:${NC}  ${USERNAME}"
    echo -e "  ${BOLD}Password:${NC}  ${PASSWORD}"
    echo ""
    if systemctl is-active --quiet simple-panel 2>/dev/null; then
        echo -e "  ${BOLD}Status:${NC}    ${GREEN}Running${NC}"
    else
        echo -e "  ${BOLD}Status:${NC}    ${RED}Stopped${NC}"
    fi
    echo ""
}

reset_password() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Run with sudo: sudo kmpanel reset${NC}"
        exit 1
    fi
    NEW_PASS=$(openssl rand -base64 9 2>/dev/null || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits)for _ in range(12)))")
    echo "${USERNAME}:${NEW_PASS}" > "$CREDS_FILE"
    chmod 600 "$CREDS_FILE"
    echo ""
    echo -e "${GREEN}  Password reset!${NC}"
    echo -e "  ${BOLD}New Password:${NC}  ${NEW_PASS}"
    echo ""
    systemctl restart simple-panel 2>/dev/null
    echo -e "${GREEN}  Panel restarted.${NC}"
    echo ""
}

restart_panel() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Run with sudo: sudo kmpanel restart${NC}"
        exit 1
    fi
    systemctl restart simple-panel 2>/dev/null
    sleep 1
    if systemctl is-active --quiet simple-panel 2>/dev/null; then
        echo -e "${GREEN}Panel restarted successfully.${NC}"
    else
        echo -e "${RED}Panel failed to start!${NC}"
    fi
}

case "${1:-status}" in
    status|s) show_status ;;
    reset|reset-password|rp) reset_password ;;
    url|u) echo "http://${HOST}:${PORT}" ;;
    restart|r) restart_panel ;;
    help|--help|-h)
        echo ""
        echo "  KMPanel CLI v4"
        echo "  kmpanel           Show status, URL, credentials"
        echo "  kmpanel reset     Reset password (needs sudo)"
        echo "  kmpanel url       Print panel URL"
        echo "  kmpanel restart   Restart panel (needs sudo)"
        echo ""
        ;;
    *) echo -e "${RED}Unknown: $1${NC}"; echo "Run 'kmpanel help'" ;;
esac
CLIEOF
chmod +x /usr/local/bin/kmpanel
log_ok "kmpanel CLI installed"

log_info "Creating systemd service..."
cat > /etc/systemd/system/simple-panel.service << SERVEOF
[Unit]
Description=KMPanel
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
log_ok "Systemd service created"

log_info "Starting panel..."
systemctl start simple-panel
sleep 3

if systemctl is-active --quiet simple-panel; then
    curl -s --connect-timeout 5 "http://127.0.0.1:${PANEL_PORT}/health" 2>/dev/null | grep -q '"ok"' && log_ok "Panel is running and responding" || log_warn "Service active but health check failed"

    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow ${PANEL_PORT}/tcp 2>/dev/null
        log_ok "Port ${PANEL_PORT} opened in UFW"
    fi

    echo ""
    echo -e "${GREEN}  ==========================================${NC}"
    echo -e "${GREEN}     KMPANEL v4 INSTALLED SUCCESSFULLY${NC}"
    echo -e "${GREEN}  ==========================================${NC}"
    echo ""
    echo -e "  ${BOLD}Login URL:${NC}  ${CYAN}http://${HOST}:${PANEL_PORT}${NC}"
    echo -e "  ${BOLD}Username:${NC}   ${PANEL_USER}"
    echo -e "  ${BOLD}Password:${NC}   ${PANEL_PASS}"
    echo ""
    echo -e "  ${BOLD}CLI:${NC}  kmpanel  |  sudo kmpanel reset  |  kmpanel url"
    echo ""

    if ! command -v ufw &>/dev/null || ! ufw status 2>/dev/null | grep -q "Status: active"; then
        log_warn "Make sure port ${PANEL_PORT}/tcp is open in your cloud firewall"
        echo ""
    fi
else
    echo ""
    echo -e "${RED}  PANEL FAILED TO START${NC}"
    journalctl -u simple-panel -n 20 --no-pager 2>/dev/null || true
    echo ""
    exit 1
fi
