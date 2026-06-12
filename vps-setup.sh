#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# KICK VIEWER BOT — VPS Auto Setup (Oracle Cloud / DigitalOcean / Hetzner)
# ═══════════════════════════════════════════════════════════════════════════
# USO:
#   chmod +x vps-setup.sh
#   sudo ./vps-setup.sh
# ═══════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $1"; }
fail() { echo -e "${RED}  ✗${NC} $1"; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Root check ──────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || fail "Ejecutar como root: sudo ./vps-setup.sh"

# ── 1. Sistema ──────────────────────────────────────────────────────────
log "Actualizando sistema..."
apt update -qq && apt upgrade -y -qq
ok "Sistema actualizado"

# ── 2. Dependencias ────────────────────────────────────────────────────
log "Instalando dependencias..."
apt install -y -qq curl wget git python3 python3-pip python3-venv nodejs npm tor netcat-openbsd
ok "Dependencias instaladas"

# ── 3. Tor con rotación de IP ──────────────────────────────────────────
log "Configurando Tor..."
TORRC="/etc/tor/torrc"

# Configurar Tor como proxy SOCKS5 con rotación
cat > "$TORRC" << 'TOREOF'
# Tor config para Kick Bot
SOCKSPort 0.0.0.0:9050
SOCKSPolicy accept *
ControlPort 9051
HashedControlPassword 16:872860B76453A77D60CA2BB8C1A7042072093276A3D701AD684053EC4C

# Rotación cada 10 segundos
MaxCircuitDirtiness 10 seconds
CircuitBuildTimeout 5
NewCircuitPeriod 10 seconds
NumEntryGuards 1
LearnCircuitBuildTimeout 0

# Log
Log notice file /var/log/tor/notices.log
TOREOF

systemctl enable tor
systemctl restart tor
ok "Tor configurado (nueva IP cada ~10s)"

# ── 4. Script de rotación forzada ──────────────────────────────────────
cat > /usr/local/bin/rotate-tor << 'ROTATEEOF'
#!/usr/bin/env bash
# Fuerza nueva IP en Tor
echo -e "AUTHENTICATE \"kickbot2024\"\r\nSIGNAL NEWNYM\r\n" | nc -w 1 127.0.0.1 9051 > /dev/null 2>&1
[ $? -eq 0 ] && echo "[$(date +%H:%M:%S)] Tor IP rotada" || echo "[$(date +%H:%M:%S)] Fallo rotacion Tor"
ROTATEEOF
chmod +x /usr/local/bin/rotate-tor

# Rotar cada 5 minutos via cron
(crontab -l 2>/dev/null | grep -v rotate-tor; echo "*/5 * * * * /usr/local/bin/rotate-tor >> /var/log/tor-rotate.log 2>&1") | crontab -
ok "Rotacion Tor cada 5 minutos via cron"

# ── 5. Probar Tor ──────────────────────────────────────────────────────
log "Probando Tor (espera 5s)..."
sleep 5
TOR_IP=$(curl -s --socks5 127.0.0.1:9050 --max-time 15 https://ifconfig.me 2>/dev/null || echo "timeout")
if [[ -n "$TOR_IP" && "$TOR_IP" != "timeout" ]]; then
    ok "Tor funcionando — IP actual: $TOR_IP"
else
    warn "Tor no responde, revisar: journalctl -u tor -n20"
fi

# ── 6. Python deps ─────────────────────────────────────────────────────
log "Instalando dependencias Python..."
cd "$DIR"
python3 -m venv .venv 2>/dev/null || true
PIP="${DIR}/.venv/bin/pip"
if [[ -f "$PIP" ]]; then
    $PIP install -q fastapi uvicorn curl-cffi
    PYTHON="${DIR}/.venv/bin/python"
else
    pip3 install -q fastapi uvicorn curl-cffi
    PYTHON="python3"
fi
ok "Python deps instaladas"

# ── 7. Node deps ──────────────────────────────────────────────────────
log "Instalando dependencias Node..."
cd "$DIR"
npm install ws --silent 2>/dev/null
ok "Node deps instaladas"

# ── 8. Systemd: Token Server ──────────────────────────────────────────
log "Creando servicio Token Server..."
cat > /etc/systemd/system/kick-token-server.service << 'SERVICEEOF'
[Unit]
Description=Kick Token Server (FastAPI + Tor)
After=network.target tor.service
Requires=tor.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kick-bot
ExecStart=/opt/kick-bot/.venv/bin/python token_server_vps.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/kick-token.log
StandardError=append:/var/log/kick-token.log

[Install]
WantedBy=multi-user.target
SERVICEEOF

# ── 9. Systemd: Kick Bot ──────────────────────────────────────────────
cat > /etc/systemd/system/kick-bot.service << 'BOTEOF'
[Unit]
Description=Kick Viewer Bot
After=network.target kick-token-server.service
Requires=kick-token-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kick-bot
ExecStart=/usr/bin/node kick-websocket-v14-tor.js
Restart=always
RestartSec=15
StandardOutput=append:/var/log/kick-bot.log
StandardError=append:/var/log/kick-bot.log

[Install]
WantedBy=multi-user.target
BOTEOF

# ── 10. Desplegar archivos ────────────────────────────────────────────
log "Desplegando archivos..."
mkdir -p /opt/kick-bot/logs
cp "$DIR"/token_server_vps.py /opt/kick-bot/
cp "$DIR"/kick-websocket.js /opt/kick-bot/kick-websocket-v14-tor.js
cp "$DIR"/package.json /opt/kick-bot/ 2>/dev/null || true
cp -r "$DIR"/node_modules /opt/kick-bot/ 2>/dev/null || true
cp -r "$DIR"/.venv /opt/kick-bot/ 2>/dev/null || true

systemctl daemon-reload
systemctl enable kick-token-server
systemctl enable kick-bot

ok "Servicios instalados"

# ── 11. Extra: múltiples instancias ───────────────────────────────────
log "Creando script para multiples instancias..."
cat > /opt/kick-bot/start-instance.sh << 'INSTEOF'
#!/usr/bin/env bash
# Ejemplo: ./start-instance.sh "https://kick.com/canal" 100
# Para multiples instancias en distintas pantallas:
# screen -dmS kick1 ./start-instance.sh "https://kick.com/canal1" 100
# screen -dmS kick2 ./start-instance.sh "https://kick.com/canal2" 100

STREAM_URL="${1:-https://kick.com/ejemplo}"
VIEWERS="${2:-50}"
SCREEN_NAME="kick_$(echo "$STREAM_URL" | grep -oP '[^/]+$')"

cd /opt/kick-bot
/usr/bin/node kick-websocket-v14-tor.js "$STREAM_URL" "$VIEWERS"
INSTEOF
chmod +x /opt/kick-bot/start-instance.sh

# ── 12. Resumen ──────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           INSTALACION COMPLETA ✓                           ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} Token Server : kick-token-server.service ${GREEN}║${NC}"
echo -e "${GREEN}║${NC} Bot          : kick-bot.service          ${GREEN}║${NC}"
echo -e "${GREEN}║${NC} Tor IP rotada cada 5 min por cron        ${GREEN}║${NC}"
echo -e "${GREEN}║${NC} Directorio   : /opt/kick-bot              ${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} Para iniciar manualmente:                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}   systemctl start kick-token-server                     ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}   systemctl start kick-bot                              ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}   journalctl -u kick-bot -f                             ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}                                                        ${GREEN}║${NC}"
echo -e "${GREEN}║${NC} O en pantalla manual:                                   ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}   screen -S kick                                        ${GREEN}║${NC}"
echo -e "${GREEN}║${NC}   screen -dmS kick1 ./start-instance.sh \"URL\" 100             ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "IP Tor actual:     ${YELLOW}$TOR_IP${NC}"
echo -e "Log Token Server:  ${YELLOW}tail -f /var/log/kick-token.log${NC}"
echo -e "Log Bot:           ${YELLOW}tail -f /var/log/kick-bot.log${NC}"
