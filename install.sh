#!/bin/bash
# KMPanel Deploy v5 — No video, just works.

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m';BOLD='\033[1m';NC='\033[0m'
log_info()  { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${RED}[X]${NC} $1"; }

REPO_RAW="https://raw.githubusercontent.com/AH-Foud/simple-panel-deploy/main"
LOGO_URL="https://app.zaro.ai/api/files/download?fid=551bfdfb-63cc-4d2b-adfc-da922a267522&exp=1785513370&sig=ocCeSt9o7nmkzEMvjW1YTQ"

echo ""
echo -e "${CYAN}  KMPanel Deploy v5${NC}"
echo ""

[[ $EUID -ne 0 ]] && { log_err "Run as root: sudo bash install.sh"; exit 1; }

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
echo -e "  ${BOLD}1)${NC} Direct IP   ->   http://${VPS_IP}:PORT"
echo -e "  ${BOLD}2)${NC} Subdomain    ->   http://your-domain.com:PORT"
read -p "Choice [1 or 2]: " ACCESS_CHOICE

HOST="$VPS_IP"
[[ "$ACCESS_CHOICE" == "2" ]] && {
    read -p "Enter subdomain: " SUBDOMAIN
    [[ -z "$SUBDOMAIN" ]] && { log_err "No subdomain."; exit 1; }
    echo -e "${YELLOW}DNS: ${BOLD}${SUBDOMAIN}${NC} -> ${BOLD}${VPS_IP}${NC} (gray cloud on Cloudflare)${NC}"
    read -p "DNS ready? [y/N]: " DNS_OK
    [[ ! "$DNS_OK" =~ ^[Yy]$ ]] && { log_warn "Set up DNS first."; exit 0; }
    HOST="$SUBDOMAIN"
}

PANEL_PORT=$(( 15000 + (RANDOM % 40000) ))
log_ok "Port: ${BOLD}${PANEL_PORT}${NC}"

PANEL_USER="admin"
PANEL_PASS=$(openssl rand -base64 9 2>/dev/null || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits)for _ in range(12)))")

echo ""
echo -e "${CYAN}  Summary:${NC}"
echo -e "  URL:   ${BOLD}http://${HOST}:${PANEL_PORT}${NC}"
echo -e "  User:  ${BOLD}${PANEL_USER}${NC}"
echo -e "  Pass:  ${BOLD}${PANEL_PASS}${NC}"
read -p "Install? [Y/n]: " CONFIRM
[[ "$CONFIRM" =~ ^[Nn]$ ]] && { echo "Cancelled."; exit 0; }

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
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/server.py" "${REPO_RAW}/server.py" || { log_err "Download failed"; exit 1; }
log_ok "Server downloaded"

log_info "Downloading logo..."
curl -s --connect-timeout 10 --max-time 30 -o "$APP_DIR/static/logo.png" "${LOGO_URL}" 2>/dev/null && log_ok "Logo OK" || log_warn "Logo skipped"

python3 -c "import py_compile;py_compile.compile('$APP_DIR/server.py',doraise=True)" 2>/dev/null && log_ok "Syntax OK" || { log_err "Syntax error"; exit 1; }

log_info "Installing kmpanel CLI..."
cat > /usr/local/bin/kmpanel << 'CLIEOF'
#!/bin/bash
A="/opt/simple-panel";C="$A/.credentials";F="$A/.config"
R='\033[0;31m';G='\033[0;32m';C2='\033[0;36m';B='\033[1m';N='\033[0m'
[[ ! -f "$F" ]] && { echo -e "${R}Not installed.${N}"; exit 1; }
source <(grep -E '^(HOST|PORT)=' "$F")
U=$(cut -d: -f1 "$C" 2>/dev/null)
P=$(cut -d: -f2- "$C" 2>/dev/null)

show(){ echo ""; echo -e "${C2}  KMPanel v5${N}"; echo ""; echo -e "  ${B}URL:${N}  ${G}http://${HOST}:${PORT}${N}"; echo -e "  ${B}User:${N} ${U}"; echo -e "  ${B}Pass:${N} ${P}"; echo ""; systemctl is-active --quiet simple-panel 2>/dev/null && echo -e "  ${B}Status:${N} ${G}Running${N}" || echo -e "  ${B}Status:${N} ${R}Stopped${N}"; echo ""; }

reset(){ [[ $EUID -ne 0 ]] && { echo "sudo kmpanel reset"; exit 1; }; NP=$(openssl rand -base64 9 2>/dev/null || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits)for _ in range(12)))"); echo "${U}:${NP}" > "$C"; chmod 600 "$C"; echo -e "${G}Reset!${N} New: ${NP}"; systemctl restart simple-panel 2>/dev/null; }

case "${1:-status}" in
    status|s) show ;;
    reset|rp) reset ;;
    url|u) echo "http://${HOST}:${PORT}" ;;
    restart|r) [[ $EUID -ne 0 ]] && { echo "sudo kmpanel restart"; exit 1; }; systemctl restart simple-panel && echo "Restarted" ;;
    *) echo "kmpanel | reset | url | restart" ;;
esac
CLIEOF
chmod +x /usr/local/bin/kmpanel
log_ok "kmpanel CLI ready"

log_info "Creating service..."
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

[Install]
WantedBy=multi-user.target
SERVEOF

systemctl daemon-reload
systemctl enable simple-panel 2>/dev/null

log_info "Starting..."
systemctl start simple-panel
sleep 2

if systemctl is-active --quiet simple-panel; then
    curl -s --connect-timeout 5 "http://127.0.0.1:${PANEL_PORT}/health" 2>/dev/null | grep -q '"ok"' && log_ok "Running!" || log_warn "Check: journalctl -u simple-panel"
    command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active" && { ufw allow ${PANEL_PORT}/tcp 2>/dev/null; log_ok "UFW opened"; }
    echo ""
    echo -e "${GREEN}  ============== INSTALLED ==============${NC}"
    echo -e "  ${B}URL:${N}  ${CYAN}http://${HOST}:${PANEL_PORT}${NC}"
    echo -e "  ${B}User:${N} ${PANEL_USER}"
    echo -e "  ${B}Pass:${N} ${PANEL_PASS}"
    echo -e "  ${B}CLI:${N}  kmpanel  |  sudo kmpanel reset"
    echo ""
else
    echo -e "${RED}FAILED${N}"
    journalctl -u simple-panel -n 20 --no-pager 2>/dev/null || true
    exit 1
fi
