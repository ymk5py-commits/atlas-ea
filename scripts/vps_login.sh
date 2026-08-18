#!/bin/bash
#===============================================================================
# ATLAS EA — Conectar la cuenta MetaTrader y encender el bot en el VPS
#
# Este script lo ejecuta EL DUEÑO del servidor. Pide la contraseña de la cuenta
# de forma interactiva: la clave se escribe directamente en el servidor, no
# viaja por ningún chat ni queda en el historial de comandos.
#
# Uso:  sudo bash vps_login.sh
#===============================================================================
set -euo pipefail

ATLAS_USER="${ATLAS_USER:-atlas}"
WINEPREFIX_DIR="/home/${ATLAS_USER}/.mt5"
MT5_DIR="${WINEPREFIX_DIR}/drive_c/Program Files/MetaTrader 5"

log()  { echo -e "\n\033[1;36m[ATLAS]\033[0m $*"; }
ok()   { echo -e "\033[1;32m  ✓\033[0m $*"; }
die()  { echo -e "\033[1;31m  ✗ $*\033[0m"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Ejecutar como root (sudo bash vps_login.sh)"
[ -f "${MT5_DIR}/terminal64.exe" ] || die "MetaTrader no está instalado. Correr primero vps_install.sh"

echo "════════════════════════════════════════════════════════════════"
echo "  Conectar la cuenta MetaTrader al bot"
echo "════════════════════════════════════════════════════════════════"
read -rp "  Número de cuenta (login) : " MT_LOGIN
read -rp "  Servidor  [MetaQuotes-Demo] : " MT_SERVER
MT_SERVER="${MT_SERVER:-MetaQuotes-Demo}"
read -rsp "  Contraseña (no se muestra)  : " MT_PASS
echo
read -rp "  Símbolos  [XAUUSD,EURUSD] : " MT_SYMBOLS
MT_SYMBOLS="${MT_SYMBOLS:-XAUUSD,EURUSD}"

[ -n "$MT_LOGIN" ] && [ -n "$MT_PASS" ] || die "Login y contraseña son obligatorios."

log "Escribiendo la configuración..."
CFG="${MT5_DIR}/atlas.ini"
{
  printf '[Common]\r\n'
  printf 'Login=%s\r\n' "$MT_LOGIN"
  printf 'Password=%s\r\n' "$MT_PASS"
  printf 'Server=%s\r\n' "$MT_SERVER"
  printf 'EnableNews=false\r\n'
  printf '[Experts]\r\n'
  printf 'AllowLiveTrading=1\r\n'
  printf 'Enabled=1\r\n'
  printf 'Account=0\r\n'
  printf 'Profile=0\r\n'
  printf '[StartUp]\r\n'
  printf 'Expert=Atlas\\Atlas_EA\r\n'
  printf 'Symbol=%s\r\n' "${MT_SYMBOLS%%,*}"
  printf 'Period=M15\r\n'
  printf 'ExpertParameters=atlas_params.set\r\n'
} > "$CFG"
chown "$ATLAS_USER:$ATLAS_USER" "$CFG"
chmod 600 "$CFG"      # solo el usuario del bot puede leer la contraseña
unset MT_PASS
ok "Configuración guardada (permisos 600, solo lectura para '$ATLAS_USER')"

log "Escribiendo los parámetros validados del bot..."
PARAMS="${MT5_DIR}/MQL5/Profiles/Tester/atlas_params.set"
install -d -o "$ATLAS_USER" -g "$ATLAS_USER" "$(dirname "$PARAMS")"
{
  printf 'InpSymbols=%s\r\n' "$MT_SYMBOLS"
  printf 'InpEnablePush=true\r\n'
  printf 'InpRiskPct=1.5\r\n'
  printf 'InpDailyLossPct=5.0\r\n'
  printf 'InpMaxDrawdownPct=30.0\r\n'
  printf 'InpRR=2.0\r\n'
  printf 'InpBeTriggerR=1.0\r\n'
  printf 'InpTrailAtrMult=2.0\r\n'
} > "$PARAMS"
chown "$ATLAS_USER:$ATLAS_USER" "$PARAMS"
ok "Riesgo 1.5%/operación · límite diario 5% · kill switch 30%"

log "Encendiendo el bot..."
systemctl restart atlas-ea.service
sleep 25

if systemctl is-active --quiet atlas-ea.service; then
   ok "Servicio activo"
else
   die "El servicio no arrancó. Ver: journalctl -u atlas-ea -n 50"
fi

LOGDIR="${MT5_DIR}/MQL5/Logs"
LATEST=$(ls -t "$LOGDIR"/*.log 2>/dev/null | head -1 || true)
if [ -n "$LATEST" ]; then
   log "Últimas líneas del bot:"
   iconv -f UTF-16LE -t UTF-8 "$LATEST" 2>/dev/null | tail -6 | sed 's/^/    /'
fi

cat <<FIN

════════════════════════════════════════════════════════════════
  EL BOT ESTÁ CORRIENDO 24/5
════════════════════════════════════════════════════════════════
  Ver estado    : systemctl status atlas-ea
  Ver el diario : sudo -u ${ATLAS_USER} bash -c 'iconv -f UTF-16LE -t UTF-8 "${MT5_DIR}/MQL5/Logs/\$(date +%Y%m%d).log" | tail -30'
  Reiniciar     : systemctl restart atlas-ea
  Apagar        : systemctl stop atlas-ea

  Ya podés apagar tu Mac: el bot vive acá.
════════════════════════════════════════════════════════════════

FIN
