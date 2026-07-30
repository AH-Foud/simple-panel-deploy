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
echo -e "${CYAN}     KMBot Panel — Bale Bot Dashboard v1.0${NC}"
echo -e "${CYAN}  ==========================================${NC}"
echo ""

[[ $EUID -ne 0 ]] && { log_err "Run: sudo bash install_botpanel.sh"; exit 1; }

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
echo -e "  ${BOLD}1)${NC} Direct IP   →   http://${VPS_IP}:PORT"
echo -e "  ${BOLD}2)${NC} Subdomain   →   http://sub.domain.com:PORT"
read -p "Choice [1/2]: " ACCESS_CHOICE

HOST="$VPS_IP"
if [[ "$ACCESS_CHOICE" == "2" ]]; then
    read -p "Subdomain: " SUBDOMAIN
    [[ -z "$SUBDOMAIN" ]] && { log_err "No subdomain"; exit 1; }
    echo -e "${YELLOW}DNS: ${SUBDOMAIN} → ${VPS_IP} (gray cloud on Cloudflare!)${NC}"
    read -p "DNS set? [y/N]: " DNS_OK
    [[ ! "$DNS_OK" =~ ^[Yy]$ ]] && { log_warn "Set DNS first"; exit 0; }
    HOST="$SUBDOMAIN"
fi

PANEL_PORT=$(( 15000 + (RANDOM % 40000) ))
log_ok "Port: ${BOLD}${PANEL_PORT}${NC}"

PANEL_USER="admin"
PANEL_PASS=$(openssl rand -base64 9 2>/dev/null || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits)for _ in range(12)))")

echo ""
echo -e "${CYAN}--- Summary ---${NC}"
echo -e "  URL:  ${BOLD}http://${HOST}:${PANEL_PORT}${NC}"
echo -e "  User: ${PANEL_USER}"
echo -e "  Pass: ${PANEL_PASS}"
echo ""
echo -e "${YELLOW}⚠️  Bot Token + Admin ID: Set from within the panel (Settings page)${NC}"
echo ""
read -p "Install? [Y/n]: " CONFIRM
[[ "$CONFIRM" =~ ^[Nn]$ ]] && { echo "Cancelled"; exit 0; }

APP_DIR="/opt/bot-panel"
mkdir -p "$APP_DIR/static" "$APP_DIR/data"

cat > "$APP_DIR/.settings" << EOF
{"bot_token": "", "admin_id": "", "port": ${PANEL_PORT}, "host": "${HOST}"}
EOF

echo "${PANEL_USER}:${PANEL_PASS}" > "$APP_DIR/.credentials"
chmod 600 "$APP_DIR/.credentials" "$APP_DIR/.settings"
log_ok "Credentials saved"

log_info "Downloading server..."
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/server.py" "${REPO_RAW}/bot-panel/server.py" || { log_err "Failed"; exit 1; }
log_ok "Server downloaded"

log_info "Downloading logo..."
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/static/logo.png" "${LOGO_URL}" 2>/dev/null && log_ok "Logo OK" || log_warn "Logo skip"

python3 -c "import py_compile;py_compile.compile('$APP_DIR/server.py',doraise=True)" 2>/dev/null && log_ok "Python OK" || { log_err "Syntax error"; exit 1; }

log_info "Creating systemd service..."
cat > /etc/systemd/system/kmbot-panel.service << SERVEOF
[Unit]
Description=KMBot Panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bot-panel
Environment="PANEL_IP=${VPS_IP}"
Environment="PANEL_PORT=${PANEL_PORT}"
Environment="PANEL_HOST=${HOST}"
ExecStart=/usr/bin/python3 /opt/bot-panel/server.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVEOF

systemctl daemon-reload
systemctl enable kmbot-panel 2>/dev/null

log_info "Starting..."
systemctl start kmbot-panel
sleep 3

if systemctl is-active --quiet kmbot-panel; then
    curl -s --connect-timeout 5 "http://127.0.0.1:${PANEL_PORT}/health" 2>/dev/null | grep -q '"ok"' && log_ok "Running!" || log_warn "Health check skip"
    command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active" && { ufw allow ${PANEL_PORT}/tcp 2>/dev/null; log_ok "UFW opened"; }

    echo ""
    echo -e "${GREEN}  ==========================================${NC}"
    echo -e "${GREEN}     KMBOT PANEL INSTALLED!${NC}"
    echo -e "${GREEN}  ==========================================${NC}"
    echo ""
    echo -e "  ${BOLD}URL:${NC}     ${CYAN}http://${HOST}:${PANEL_PORT}${NC}"
    echo -e "  ${BOLD}User:${NC}    ${PANEL_USER}"
    echo -e "  ${BOLD}Pass:${NC}    ${PANEL_PASS}"
    echo ""
    echo -e "  ${YELLOW}⚙️  After login:${NC}"
    echo -e "  ${YELLOW}   1. Go to ⚙️ Settings${NC}"
    echo -e "  ${YELLOW}   2. Enter Bot Token + Admin ID${NC}"
    echo -e "  ${YELLOW}   3. systemctl restart kmbot-panel${NC}"
    echo ""
else
    echo -e "${RED}FAILED${NC}"
    journalctl -u kmbot-panel -n 20 --no-pager 2>/dev/null
    exit 1
fi
