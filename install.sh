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
VIDEO_URL="https://app.zaro.ai/api/files/download?fid=db586684-38ad-4835-91bf-64f4c6c8d8ce&exp=1785514314&sig=pU1s6DYxTpkIJM3hBhpAKA"

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
    echo -e "${YELLOW}  DNS CHECK:${NC}"
    echo -e "  ${BOLD}${SUBDOMAIN}${NC} -> ${BOLD}${VPS_IP}${NC}"
    echo -e "  ${YELLOW}Cloudflare: Use DNS-only (gray cloud).${NC}"
    echo ""
    read -p "DNS record set? [y/N]: " DNS_OK
    if [[ ! "$DNS_OK" =~ ^[Yy]$ ]]; then
        log_warn "Set up DNS first, then re-run."
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
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/static/logo.png" "${REPO_RAW}/assets/logo.png" && {
    log_ok "Logo downloaded"
} || {
    log_warn "Logo download failed — skipping"
}

log_info "Downloading background video (~17MB)..."
curl -s --connect-timeout 15 --max-time 120 -o "$APP_DIR/static/bg.mp4" "${VIDEO_URL}" 2>/dev/null && {
    VSIZE=$(stat -c%s "$APP_DIR/static/bg.mp4" 2>/dev/null || echo 0)
    if [[ "$VSIZE" -gt 10000 ]]; then
        log_ok "Video downloaded ($(( VSIZE / 1048576 ))MB)"
    else
        log_warn "Video incomplete — using CSS fallback"
        rm -f "$APP_DIR/static/bg.mp4"
    fi
} || {
    log_warn "Video download failed — using CSS gradient"
}

if python3 -c "import py_compile;py_compile.compile('$APP_DIR/server.py',doraise=True)" 2>/dev/null; then
    log_ok "Python syntax OK"
else
    log_err "Python syntax error"
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
    echo -e "${RED}Not installed. Run the installer first.${NC}"
    exit 1
fi
source <(grep -E '^(HOST|PORT)=' "$CONFIG_FILE")
USERNAME=$(cut -d: -f1 "$CREDS_FILE" 2>/dev/null)
PASSWORD=$(cut -d: -f2- "$CREDS_FILE" 2>/dev/null)

show_status() {
    echo ""
    echo -e "${CYAN}  K M P a n e l  v4${NC}"
    echo ""
    echo -e "  ${BOLD}URL:${NC}       ${GREEN}http://${HOST}:${PORT}${NC}"
    echo -e "  ${BOLD}Username:${NC}   ${USERNAME}"
    echo -e "  ${BOLD}Password:${NC}   ${PASSWORD}"
    echo ""
    if systemctl is-active --quiet simple-panel 2>/dev/null; then
        echo -e "  ${BOLD}Status:${NC}     ${GREEN}Running${NC}"
    else
        echo -e "  ${BOLD}Status:${NC}     ${RED}Stopped${NC}"
    fi
    echo ""
}

reset_password() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Run: sudo kmpanel reset${NC}"
        exit 1
    fi
    NEW_PASS=$(openssl rand -base64 9 2>/dev/null || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits)for _ in range(12)))")
    echo "${USERNAME}:${NEW_PASS}" > "$CREDS_FILE"
    chmod 600 "$CREDS_FILE"
    echo ""
    echo -e "${GREEN}Password reset!${NC}"
    echo -e "  New: ${NEW_PASS}"
    echo ""
    systemctl restart simple-panel 2>/dev/null
}

case "${1:-status}" in
    status|s) show_status ;;
    reset|rp) reset_password ;;
    url|u) echo "http://${HOST}:${PORT}" ;;
    restart|r)
        [[ $EUID -ne 0 ]] && { echo "Run: sudo kmpanel restart"; exit 1; }
        systemctl restart simple-panel 2>/dev/null && echo "Restarted"
        ;;
    help|-h|--help)
        echo "kmpanel | kmpanel reset | kmpanel url | kmpanel restart"
        ;;
    *) echo "Unknown: $1 — try 'kmpanel help'" ;;
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
    curl -s --connect-timeout 5 "http://127.0.0.1:${PANEL_PORT}/health" 2>/dev/null | grep -q '"ok"' && log_ok "Panel is running" || log_warn "Health check skipped"

    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow ${PANEL_PORT}/tcp 2>/dev/null
        log_ok "Port ${PANEL_PORT} opened in UFW"
    fi

    echo ""
    echo -e "${GREEN}  ==========================================${NC}"
    echo -e "${GREEN}     KMPANEL v4 INSTALLED!${NC}"
    echo -e "${GREEN}  ==========================================${NC}"
    echo ""
    echo -e "  ${BOLD}URL:${NC}       ${CYAN}http://${HOST}:${PANEL_PORT}${NC}"
    echo -e "  ${BOLD}Username:${NC}   ${PANEL_USER}"
    echo -e "  ${BOLD}Password:${NC}   ${PANEL_PASS}"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}  kmpanel  |  sudo kmpanel reset  |  kmpanel url"
    echo ""

    if ! command -v ufw &>/dev/null || ! ufw status 2>/dev/null | grep -q "Status: active"; then
        log_warn "Ensure port ${PANEL_PORT}/tcp is open in cloud firewall"
        echo ""
    fi
else
    echo -e "${RED}PANEL FAILED TO START${NC}"
    journalctl -u simple-panel -n 20 --no-pager 2>/dev/null || true
    echo ""
    exit 1
fi
