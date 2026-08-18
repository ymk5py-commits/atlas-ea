#!/bin/bash
#===============================================================================
# ATLAS EA — Instalador para VPS Linux (headless, 24/5)
#
# Instala Wine + MetaTrader 5 + el bot ATLAS en un servidor Linux sin pantalla,
# lo compila y deja un servicio systemd que lo mantiene corriendo y lo reinicia
# solo si se cae o si el servidor se reinicia.
#
# NO maneja contraseñas: el login de la cuenta lo hace vps_login.sh, que ejecuta
# el dueño del servidor y pide la clave de forma interactiva.
#
# Uso:  sudo bash vps_install.sh
#===============================================================================
set -euo pipefail

ATLAS_USER="${ATLAS_USER:-atlas}"
ATLAS_HOME="/home/${ATLAS_USER}"
WINEPREFIX_DIR="${ATLAS_HOME}/.mt5"
MT5_DIR="${WINEPREFIX_DIR}/drive_c/Program Files/MetaTrader 5"
MT5_SETUP_URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

log()  { echo -e "\n\033[1;36m[ATLAS]\033[0m $*"; }
ok()   { echo -e "\033[1;32m  ✓\033[0m $*"; }
warn() { echo -e "\033[1;33m  ⚠\033[0m $*"; }
die()  { echo -e "\033[1;31m  ✗ $*\033[0m"; exit 1; }

#-------------------------------------------------------------------------------
# 1. Verificaciones previas — no instalar nada si el servidor no da
#-------------------------------------------------------------------------------
log "Verificando el servidor..."
[ "$(id -u)" -eq 0 ] || die "Ejecutar como root (sudo bash vps_install.sh)"

ARCH="$(uname -m)"
[ "$ARCH" = "x86_64" ] || die "Arquitectura $ARCH no soportada. MetaTrader necesita x86_64."
ok "Arquitectura x86_64"

RAM_FREE=$(free -m | awk '/^Mem:/{print $7}')
RAM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
[ "$RAM_FREE" -ge 1500 ] || die "Solo ${RAM_FREE} MB de RAM disponible (de ${RAM_TOTAL} MB). MT5 necesita ~1.5 GB libres."
ok "RAM: ${RAM_FREE} MB disponible de ${RAM_TOTAL} MB"

DISK_FREE=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
[ "$DISK_FREE" -ge 8 ] || die "Solo ${DISK_FREE} GB libres en disco. Se necesitan 8 GB."
ok "Disco: ${DISK_FREE} GB libres"

log "Qué está corriendo en este servidor (para no pisarle nada):"
systemctl list-units --type=service --state=running --no-pager --plain 2>/dev/null \
  | awk 'NR>1 && $1 ~ /\.service$/ {print "    - "$1}' | head -20 || true

#-------------------------------------------------------------------------------
# 2. Dependencias
#-------------------------------------------------------------------------------
log "Instalando dependencias (wine, xvfb, utilidades)..."
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    wine wine64 wine32 xvfb xauth wget ca-certificates cabextract winbind \
    fonts-liberation psmisc procps >/dev/null 2>&1 \
  || apt-get install -y -qq --no-install-recommends \
       wine xvfb xauth wget ca-certificates cabextract winbind fonts-liberation psmisc procps
ok "Dependencias instaladas ($(wine --version 2>/dev/null || echo wine))"

#-------------------------------------------------------------------------------
# 3. Usuario dedicado (el bot no corre como root)
#-------------------------------------------------------------------------------
if ! id "$ATLAS_USER" >/dev/null 2>&1; then
   useradd -m -s /bin/bash "$ATLAS_USER"
   ok "Usuario '$ATLAS_USER' creado"
else
   ok "Usuario '$ATLAS_USER' ya existe"
fi

#-------------------------------------------------------------------------------
# 4. MetaTrader 5 bajo Wine (headless con Xvfb)
#-------------------------------------------------------------------------------
if [ -f "${MT5_DIR}/terminal64.exe" ]; then
   ok "MetaTrader 5 ya está instalado"
else
   log "Instalando MetaTrader 5 (descarga ~500 MB, puede tardar)..."
   sudo -u "$ATLAS_USER" bash -c "
      export WINEPREFIX='${WINEPREFIX_DIR}' WINEARCH=win64 WINEDEBUG=-all
      wineboot --init >/dev/null 2>&1 || true
      sleep 5
      wget -q -O /tmp/mt5setup.exe '${MT5_SETUP_URL}'
      xvfb-run -a wine /tmp/mt5setup.exe /auto >/dev/null 2>&1 || true
      sleep 30
   "
   [ -f "${MT5_DIR}/terminal64.exe" ] || die "La instalación de MT5 no dejó terminal64.exe. Revisar conectividad del servidor."
   ok "MetaTrader 5 instalado"
fi

#-------------------------------------------------------------------------------
# 5. Código del bot + compilación
#-------------------------------------------------------------------------------
log "Instalando el bot ATLAS..."
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/src"
[ -d "$SRC_DIR" ] || die "No encuentro la carpeta src/ junto al script."

install -d -o "$ATLAS_USER" -g "$ATLAS_USER" "${MT5_DIR}/MQL5/Experts/Atlas"
cp -R "${SRC_DIR}/." "${MT5_DIR}/MQL5/Experts/Atlas/"
chown -R "$ATLAS_USER:$ATLAS_USER" "$WINEPREFIX_DIR"
ok "Archivos copiados"

# Symlink sin espacios: el compilador CLI de MetaEditor falla con rutas con espacios
sudo -u "$ATLAS_USER" ln -sfn "$MT5_DIR" "${WINEPREFIX_DIR}/drive_c/mt5"

log "Compilando el bot..."
sudo -u "$ATLAS_USER" bash -c "
   export WINEPREFIX='${WINEPREFIX_DIR}' WINEARCH=win64 WINEDEBUG=-all
   xvfb-run -a wine 'C:\\mt5\\metaeditor64.exe' '/compile:C:\\mt5\\MQL5\\Experts\\Atlas\\Atlas_EA.mq5' '/log:C:\\mt5\\compile.log' >/dev/null 2>&1 || true
   sleep 3
"
COMPILE_LOG="${MT5_DIR}/compile.log"
if [ -f "$COMPILE_LOG" ]; then
   RESULT=$(iconv -f UTF-16LE -t UTF-8 "$COMPILE_LOG" 2>/dev/null | grep -a "Result:" | tail -1 || true)
   echo "    $RESULT"
fi
[ -f "${MT5_DIR}/MQL5/Experts/Atlas/Atlas_EA.ex5" ] || die "El bot no compiló. Revisar ${COMPILE_LOG}"
ok "Bot compilado (Atlas_EA.ex5)"

#-------------------------------------------------------------------------------
# 6. Servicio systemd — 24/5 con reinicio automático
#-------------------------------------------------------------------------------
log "Configurando el servicio 24/5..."
cat > /etc/systemd/system/atlas-ea.service <<SERVICE
[Unit]
Description=ATLAS EA - bot de trading MetaTrader 5 (headless)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${ATLAS_USER}
Environment=WINEPREFIX=${WINEPREFIX_DIR}
Environment=WINEARCH=win64
Environment=WINEDEBUG=-all
Environment=DISPLAY=:99
ExecStartPre=/bin/bash -c 'pkill -u ${ATLAS_USER} -f terminal64.exe || true'
ExecStart=/usr/bin/xvfb-run -a --server-args="-screen 0 1280x1024x24" \\
          /usr/bin/wine "C:\\\\mt5\\\\terminal64.exe" /portable "/config:C:\\\\mt5\\\\atlas.ini"
Restart=always
RestartSec=30
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable atlas-ea.service >/dev/null 2>&1
ok "Servicio 'atlas-ea' registrado (arranca solo al bootear el servidor)"

#-------------------------------------------------------------------------------
# 7. Listo
#-------------------------------------------------------------------------------
cat <<FIN

════════════════════════════════════════════════════════════════
  INSTALACIÓN COMPLETA
════════════════════════════════════════════════════════════════
  MetaTrader 5 : ${MT5_DIR}
  Bot          : MQL5/Experts/Atlas/Atlas_EA.ex5  (compilado)
  Servicio     : atlas-ea.service  (aún NO iniciado)

  FALTA UN PASO — conectar la cuenta:

      sudo bash vps_login.sh

  Ese script pide el login y la contraseña de tu cuenta MetaTrader
  de forma interactiva (la clave queda solo en este servidor) y
  enciende el bot.
════════════════════════════════════════════════════════════════

FIN
