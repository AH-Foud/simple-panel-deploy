#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m';BOLD='\033[1m';NC='\033[0m'
log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${RED}[X]${NC} $1"; }

REPO_RAW="https://raw.githubusercontent.com/AH-Foud/simple-panel-deploy/main"
LOGO_URL="https://app.zaro.ai/api/files/download?fid=ffe4ec6a-bcf0-4900-a2f2-85d08872234e&exp=1785514576&sig=ABksCW6qJ8ZQUaSkSziMqw"

echo ""
echo -e "${CYAN}  ==========================================${NC}"
echo -e "${CYAN}       KMPanel Deploy v6${NC}"
echo -e "${CYAN}  ==========================================${NC}"
echo ""

[[ $EUID -ne 0 ]] && { log_err "Run: sudo bash install.sh"; exit 1; }

command -v python3 &>/dev/null || { apt-get update -qq; apt-get install -y -qq python3; }
log_ok "Python3: $(python3 --version)"

log_info "Detecting VPS IP..."
VPS_IP=""
for svc in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com" "https://checkip.amazonaws.com"; do
    IP_CANDIDATE=$(curl -s --connect-timeout 5 --max-time 10 "$svc" 2>/dev/null)
    [[ -n "$IP_CANDIDATE" && "$IP_CANDIDATE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { VPS_IP="$IP_CANDIDATE"; break; }
done
[[ -z "$VPS_IP" ]] && { read -p "Enter VPS IP: " VPS_IP; }
log_ok "VPS IP: ${BOLD}${VPS_IP}${NC}"

echo ""
log_info "Access method:"
echo -e "  ${BOLD}1)${NC} Direct IP   →   http://${VPS_IP}"
echo -e "  ${BOLD}2)${NC} Subdomain   →   http://your-domain.com"
read -p "Choice [1/2]: " ACCESS_CHOICE

HOST="$VPS_IP"
if [[ "$ACCESS_CHOICE" == "2" ]]; then
    read -p "Subdomain: " SUBDOMAIN
    [[ -z "$SUBDOMAIN" ]] && { log_err "No subdomain"; exit 1; }
    echo ""
    echo -e "${YELLOW}  ⚠️  IMPORTANT:${NC}"
    echo -e "${YELLOW}  DNS: ${BOLD}${SUBDOMAIN}${NC}${YELLOW} → ${BOLD}${VPS_IP}${NC}"
    echo -e "${YELLOW}  Cloudflare: ${BOLD}USE GRAY CLOUD (DNS only)${NC}${YELLOW} — orange cloud blocks ports${NC}"
    echo ""
    read -p "DNS set? [y/N]: " DNS_OK
    [[ ! "$DNS_OK" =~ ^[Yy]$ ]] && { log_warn "Set up DNS first, then re-run."; exit 0; }
    HOST="$SUBDOMAIN"
fi

# Cloudflare-compatible port: 80 works everywhere
PANEL_PORT=80
log_ok "Port: ${BOLD}${PANEL_PORT}${NC} (Cloudflare compatible)"

PANEL_USER="admin"
PANEL_PASS=$(openssl rand -base64 9 2>/dev/null || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits)for _ in range(12)))")

echo ""
echo -e "${CYAN}--- Summary ---${NC}"
echo -e "  URL:  ${BOLD}http://${HOST}${NC}"
echo -e "  User: ${PANEL_USER}"
echo -e "  Pass: ${PANEL_PASS}"
echo ""
read -p "Install? [Y/n]: " CONFIRM
[[ "$CONFIRM" =~ ^[Nn]$ ]] && { echo "Cancelled"; exit 0; }

APP_DIR="/opt/simple-panel"

# Stop old panel if exists
systemctl stop simple-panel 2>/dev/null
systemctl stop kmbot-panel 2>/dev/null

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/static" "$APP_DIR/data"

echo "${PANEL_USER}:${PANEL_PASS}" > "$APP_DIR/.credentials"
chmod 600 "$APP_DIR/.credentials"
log_ok "Credentials saved"

log_info "Downloading server..."
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/server.py" "${REPO_RAW}/server.py" || { log_err "Failed!"; exit 1; }
log_ok "Server downloaded"

log_info "Downloading logo..."
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/static/logo.png" "${LOGO_URL}" 2>/dev/null && log_ok "Logo OK" || log_warn "Logo skipped"

python3 -c "import py_compile;py_compile.compile('$APP_DIR/server.py',doraise=True)" 2>/dev/null && log_ok "Python OK" || { log_err "Syntax error in server.py"; exit 1; }

# Kill anything on port 80
fuser -k 80/tcp 2>/dev/null; sleep 1

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
    curl -s --connect-timeout 5 "http://127.0.0.1:${PANEL_PORT}/health" 2>/dev/null | grep -q '"ok"' && log_ok "Panel is running!" || log_warn "Health check skipped"

    command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active" && { ufw allow ${PANEL_PORT}/tcp 2>/dev/null; log_ok "UFW port ${PANEL_PORT} opened"; }

    echo ""
    echo -e "${GREEN}  ==========================================${NC}"
    echo -e "${GREEN}     KMPANEL v6 INSTALLED!${NC}"
    echo -e "${GREEN}  ==========================================${NC}"
    echo ""
    echo -e "  ${BOLD}URL:${NC}  ${CYAN}http://${HOST}${NC}"
    echo -e "  ${BOLD}User:${NC} ${PANEL_USER}"
    echo -e "  ${BOLD}Pass:${NC} ${PANEL_PASS}"
    echo ""

    if ! command -v ufw &>/dev/null || ! ufw status 2>/dev/null | grep -q "Status: active"; then
        log_warn "Open port ${PANEL_PORT}/tcp in your cloud firewall (Hetzner/OVH panel)"
    fi
    echo ""
else
    echo -e "${RED}PANEL FAILED TO START${NC}"
    journalctl -u simple-panel -n 20 --no-pager 2>/dev/null || true
    exit 1
fi
