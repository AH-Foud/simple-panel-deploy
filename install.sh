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
VIDEO_URL="https://app.zaro.ai/api/files/download?fid=db586684-38ad-4835-91bf-64f4c6c8d8ce&exp=1785514576&sig=pL0Z1RJtXCT8xaFsJnLw1g"
LOGO_URL="https://app.zaro.ai/api/files/download?fid=ffe4ec6a-bcf0-4900-a2f2-85d08872234e&exp=1785514576&sig=ABksCW6qJ8ZQUaSkSziMqw"

banner() {
    echo ""
    echo -e "${CYAN}  ==========================================${NC}"
    echo -e "${CYAN}       KMPanel Deploy v4.0${NC}"
    echo -e "${CYAN}  ==========================================${NC}"
    echo ""
}
banner

[[ $EUID -ne 0 ]] && { log_err "Run: sudo bash install.sh"; exit 1; }

if ! command -v python3 &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq python3 || { log_err "Failed"; exit 1; }
fi
log_ok "Python3: $(python3 --version)"

log_info "Detecting VPS IP..."
VPS_IP=""
for svc in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://checkip.amazonaws.com"; do
    IP_CANDIDATE=$(curl -s --connect-timeout 5 --max-time 10 "$svc" 2>/dev/null)
    [[ -n "$IP_CANDIDATE" && "$IP_CANDIDATE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { VPS_IP="$IP_CANDIDATE"; break; }
done

if [[ -z "$VPS_IP" ]]; then
    read -p "Enter VPS IP: " VPS_IP
    [[ ! "$VPS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { log_err "Bad IP"; exit 1; }
fi
log_ok "IP: ${BOLD}${VPS_IP}${NC}"

echo ""
log_info "Access method?"
echo -e "  ${BOLD}1)${NC} http://${VPS_IP}:PORT"
echo -e "  ${BOLD}2)${NC} http://subdomain:PORT"
read -p "Choice [1/2]: " ACCESS_CHOICE

HOST="$VPS_IP"
if [[ "$ACCESS_CHOICE" == "2" ]]; then
    read -p "Subdomain: " SUBDOMAIN
    [[ -z "$SUBDOMAIN" ]] && { log_err "No subdomain"; exit 1; }
    echo -e "${YELLOW}DNS: ${SUBDOMAIN} -> ${VPS_IP}${NC}"
    read -p "DNS set? [y/N]: " DNS_OK
    [[ ! "$DNS_OK" =~ ^[Yy]$ ]] && { log_warn "Set DNS first"; exit 0; }
    HOST="$SUBDOMAIN"
fi

PANEL_PORT=$(( 15000 + (RANDOM % 40000) ))
log_ok "Port: ${BOLD}${PANEL_PORT}${NC}"

PANEL_USER="admin"
PANEL_PASS=$(openssl rand -base64 9 2>/dev/null || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits)for _ in range(12)))")

echo -e "\n${CYAN}--- Summary ---${NC}"
echo -e "  URL:  ${BOLD}http://${HOST}:${PANEL_PORT}${NC}"
echo -e "  User: ${PANEL_USER}"
echo -e "  Pass: ${PANEL_PASS}"
read -p "Proceed? [Y/n]: " CONFIRM
[[ "$CONFIRM" =~ ^[Nn]$ ]] && { echo "Canceled"; exit 0; }

APP_DIR="/opt/simple-panel"
mkdir -p "$APP_DIR/static"

cat > "$APP_DIR/.config" << EOF
HOST=${HOST}
PORT=${PANEL_PORT}
EOF
chmod 600 "$APP_DIR/.config"

echo "${PANEL_USER}:${PANEL_PASS}" > "$APP_DIR/.credentials"
chmod 600 "$APP_DIR/.credentials"
log_ok "Credentials saved"

log_info "Downloading server..."
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/server.py" "${REPO_RAW}/server.py" || { log_err "server.py failed"; exit 1; }
log_ok "Server downloaded"

log_info "Downloading logo..."
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/static/logo.png" "${LOGO_URL}" 2>/dev/null && log_ok "Logo OK" || log_warn "Logo skip"

log_info "Downloading background video (~17MB)..."
curl -s --connect-timeout 15 --max-time 90 -o "$APP_DIR/static/bg.mp4" "${VIDEO_URL}" 2>/dev/null && {
    VSIZE=$(stat -c%s "$APP_DIR/static/bg.mp4" 2>/dev/null || echo 0)
    if [[ "$VSIZE" -gt 10000 ]]; then
        log_ok "Video OK ($(( VSIZE / 1048576 ))MB)"
    else
        rm -f "$APP_DIR/static/bg.mp4"
        log_warn "Video incomplete — CSS fallback"
    fi
} || log_warn "Video failed — CSS fallback"

python3 -c "import py_compile;py_compile.compile('$APP_DIR/server.py',doraise=True)" 2>/dev/null && log_ok "Python OK" || { log_err "Syntax error"; exit 1; }

log_info "Installing kmpanel..."
cat > /usr/local/bin/kmpanel << 'CLIEOF'
#!/bin/bash
APP_DIR="/opt/simple-panel"
CREDS_FILE="$APP_DIR/.credentials"
CONFIG_FILE="$APP_DIR/.config"
RED='\033[0;31m';GREEN='\033[0;32m';CYAN='\033[0;36m';BOLD='\033[1m';NC='\033[0m'
[[ ! -f "$CONFIG_FILE" ]] && { echo -e "${RED}Not installed${NC}"; exit 1; }
source <(grep -E '^(HOST|PORT)=' "$CONFIG_FILE")
USERNAME=$(cut -d: -f1 "$CREDS_FILE")
PASSWORD=$(cut -d: -f2- "$CREDS_FILE")

case "${1:-status}" in
    status|s)
        echo -e "\n${CYAN}  K M P a n e l  v4${NC}"
        echo -e "  ${BOLD}URL:${NC}  ${GREEN}http://${HOST}:${PORT}${NC}"
        echo -e "  ${BOLD}User:${NC}  ${USERNAME}"
        echo -e "  ${BOLD}Pass:${NC}  ${PASSWORD}"
        systemctl is-active --quiet simple-panel && echo -e "  ${BOLD}Status:${NC} ${GREEN}Running${NC}\n" || echo -e "  ${BOLD}Status:${NC} ${RED}Stopped${NC}\n"
        ;;
    reset|rp)
        [[ $EUID -ne 0 ]] && { echo "Run: sudo kmpanel reset"; exit 1; }
        NEW_PASS=$(openssl rand -base64 9 2>/dev/null || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits)for _ in range(12)))")
        echo "${USERNAME}:${NEW_PASS}" > "$CREDS_FILE"
        chmod 600 "$CREDS_FILE"
        systemctl restart simple-panel 2>/dev/null
        echo -e "${GREEN}Reset! New: ${NEW_PASS}${NC}"
        ;;
    url|u) echo "http://${HOST}:${PORT}" ;;
    restart|r)
        [[ $EUID -ne 0 ]] && { echo "sudo kmpanel restart"; exit 1; }
        systemctl restart simple-panel && echo "Restarted"
        ;;
    *) echo "kmpanel | reset | url | restart" ;;
esac
CLIEOF
chmod +x /usr/local/bin/kmpanel
log_ok "kmpanel installed"

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

log_info "Starting..."
systemctl start simple-panel
sleep 3

if systemctl is-active --quiet simple-panel; then
    curl -s --connect-timeout 5 "http://127.0.0.1:${PANEL_PORT}/health" 2>/dev/null | grep -q '"ok"' && log_ok "Running" || log_warn "Health skip"
    command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active" && { ufw allow ${PANEL_PORT}/tcp 2>/dev/null; log_ok "UFW port opened"; }

    echo -e "\n${GREEN}  ==========================================${NC}"
    echo -e "${GREEN}     KMPANEL v4 INSTALLED!${NC}"
    echo -e "${GREEN}  ==========================================${NC}"
    echo -e "\n  ${BOLD}URL:${NC}  ${CYAN}http://${HOST}:${PANEL_PORT}${NC}"
    echo -e "  ${BOLD}User:${NC}  ${PANEL_USER}"
    echo -e "  ${BOLD}Pass:${NC}  ${PANEL_PASS}"
    echo -e "\n  ${BOLD}CLI:${NC} kmpanel | sudo kmpanel reset\n"

    command -v ufw &>/dev/null || log_warn "Open port ${PANEL_PORT}/tcp in cloud firewall"
else
    echo -e "${RED}FAILED${NC}"
    journalctl -u simple-panel -n 20 --no-pager 2>/dev/null || true
    exit 1
fi
