#!/bin/bash
# ATLAS EA — arranque del contenedor.
# Lee la cuenta desde variables de entorno (nunca quedan en la imagen).
set -uo pipefail

MT5="${WINEPREFIX}/drive_c/Program Files/MetaTrader 5"
CFG="${MT5}/atlas.ini"
# El terminal busca los .set de un EA de gráfico en MQL5/Presets
PARAMS_DIR="${MT5}/MQL5/Presets"

: "${MT_LOGIN:?Falta MT_LOGIN}"
: "${MT_PASSWORD:=}"
: "${MT_SERVER:=MetaQuotes-Demo}"

# Credenciales ya guardadas por MetaTrader en otra instalación (accounts.dat
# cifrado). Evita tener que pasar la contraseña en texto plano.
if [ -d /seed-config ]; then
   echo "[ATLAS] Importando credenciales guardadas de MetaTrader"
   mkdir -p "${MT5}/config"
   cp -a /seed-config/. "${MT5}/config/" 2>/dev/null || true
fi
: "${ATLAS_SYMBOLS:=EURUSD,XAUUSD}"
: "${ATLAS_RISK:=1.5}"
: "${ATLAS_DAILY_LOSS:=5.0}"
: "${ATLAS_MAX_DD:=30.0}"
# Estrategias POR SIMBOLO (listas separadas por coma; vacio = ninguna)
: "${ATLAS_CRT_SYMBOLS:=EURUSD,XAUUSD}"
: "${ATLAS_SMC_SYMBOLS:=XAUUSD}"
: "${ATLAS_TREND_SYMBOLS:=}"
: "${ATLAS_BREAKOUT_SYMBOLS:=}"
# Nombre NUEVO a proposito: un .env viejo con ATLAS_SCALP / ATLAS_SCALP_SYMBOLS
# no puede reencender el scalping que el dueño apago. Para reactivarlo hay que
# escribir ATLAS_M1_SCALP_SYMBOLS de forma deliberada.
: "${ATLAS_M1_SCALP_SYMBOLS:=}"
# Sesiones por simbolo (hora de cada plaza; el EA convierte solo)
: "${ATLAS_NY_SYMBOLS:=EURUSD}"
: "${ATLAS_LONDON_SYMBOLS:=XAUUSD}"
: "${ATLAS_LOCAL_GMT_OFFSET:=-3}"

if [ -n "${ATLAS_SCALP:-}" ] || [ -n "${ATLAS_SCALP_SYMBOLS:-}" ]; then
   echo "[ATLAS] AVISO: ATLAS_SCALP / ATLAS_SCALP_SYMBOLS ya no aplican (v2)."
   echo "[ATLAS]        El scalping se activa solo con ATLAS_M1_SCALP_SYMBOLS."
fi

mkdir -p "$PARAMS_DIR"

# Parametros del EA v2: estrategias y sesiones por simbolo.
# Gestion de posicion validada por backtest (RR 2.0 / BE 1.0R / Trail 2.0 ATR).
{
  printf 'InpSymbols=%s\r\n'          "$ATLAS_SYMBOLS"
  printf 'InpEnablePush=true\r\n'
  printf 'InpRiskPct=%s\r\n'          "$ATLAS_RISK"
  printf 'InpDailyLossPct=%s\r\n'     "$ATLAS_DAILY_LOSS"
  printf 'InpMaxDrawdownPct=%s\r\n'   "$ATLAS_MAX_DD"
  printf 'InpRR=2.0\r\n'
  printf 'InpBeTriggerR=1.0\r\n'
  printf 'InpTrailAtrMult=2.0\r\n'
  printf 'InpCrtSymbols=%s\r\n'       "$ATLAS_CRT_SYMBOLS"
  printf 'InpSmcSymbols=%s\r\n'       "$ATLAS_SMC_SYMBOLS"
  printf 'InpTrendSymbols=%s\r\n'     "$ATLAS_TREND_SYMBOLS"
  printf 'InpBreakoutSymbols=%s\r\n'  "$ATLAS_BREAKOUT_SYMBOLS"
  printf 'InpScalpSymbols=%s\r\n'     "$ATLAS_M1_SCALP_SYMBOLS"
  printf 'InpNewYorkSymbols=%s\r\n'   "$ATLAS_NY_SYMBOLS"
  printf 'InpLondonSymbols=%s\r\n'    "$ATLAS_LONDON_SYMBOLS"
  printf 'InpLocalGmtOffset=%s\r\n'   "$ATLAS_LOCAL_GMT_OFFSET"
} > "${PARAMS_DIR}/atlas_params.set"

{
  printf '[Common]\r\n'
  printf 'Login=%s\r\n'    "$MT_LOGIN"
  [ -n "$MT_PASSWORD" ] && printf 'Password=%s\r\n' "$MT_PASSWORD"
  printf 'Server=%s\r\n'   "$MT_SERVER"
  printf 'EnableNews=false\r\n'
  printf '[Experts]\r\n'
  printf 'AllowLiveTrading=1\r\n'
  printf 'Enabled=1\r\n'
  printf 'Account=0\r\n'
  printf 'Profile=0\r\n'
  printf '[StartUp]\r\n'
  printf 'Expert=Atlas\\Atlas_EA\r\n'
  printf 'Symbol=%s\r\n' "${ATLAS_SYMBOLS%%,*}"
  printf 'Period=M15\r\n'
  printf 'ExpertParameters=atlas_params.set\r\n'
} > "$CFG"
chmod 600 "$CFG"

echo "[ATLAS] Iniciando MetaTrader 5 headless — cuenta ${MT_LOGIN} en ${MT_SERVER}"
echo "[ATLAS] Riesgo ${ATLAS_RISK}%/op · limite diario ${ATLAS_DAILY_LOSS}% · kill switch ${ATLAS_MAX_DD}%"
echo "[ATLAS] CRT: ${ATLAS_CRT_SYMBOLS:-ninguno} · SmartMoney: ${ATLAS_SMC_SYMBOLS:-ninguno} · NY: ${ATLAS_NY_SYMBOLS:-ninguno} · Londres: ${ATLAS_LONDON_SYMBOLS:-ninguno}"

# Pantalla virtual INDEPENDIENTE del terminal: el auto-update de MT5
# (liveupdate) mata y relanza terminal64.exe; con xvfb-run el X moría
# junto al primer proceso y el updater quedaba sin pantalla → crash loop.
Xvfb :99 -screen 0 1280x1024x24 &
sleep 2

wine 'C:\mt5\terminal64.exe' /portable '/config:C:\mt5\atlas.ini' &
MT_PID=$!

# Volcar el diario del bot a la salida del contenedor (docker logs)
LOGDIR="${MT5}/MQL5/Logs"
mkdir -p "$LOGDIR"
(
  LAST=""
  while true; do
    sleep 20
    F="${LOGDIR}/$(date +%Y%m%d).log"
    [ -f "$F" ] || continue
    CUR=$(iconv -f UTF-16LE -t UTF-8 "$F" 2>/dev/null | grep -a "ATLAS" | tail -40)
    if [ "$CUR" != "$LAST" ]; then
      comm -13 <(echo "$LAST") <(echo "$CUR") 2>/dev/null | sed 's/^/[EA] /' || echo "$CUR" | tail -3 | sed 's/^/[EA] /'
      LAST="$CUR"
    fi
  done
) &

trap 'echo "[ATLAS] Deteniendo..."; pkill -f terminal64.exe; exit 0' SIGTERM SIGINT

# Espera resiliente: si el terminal muere (p.ej. por auto-update), dar una
# ventana para que el updater lo relance antes de dar el contenedor por caído.
while true; do
  sleep 15
  if ! pgrep -f terminal64.exe >/dev/null 2>&1; then
    echo "[ATLAS] terminal64 no está; espero 45 s por si el auto-update lo relanza..."
    sleep 45
    if ! pgrep -f terminal64.exe >/dev/null 2>&1; then
      echo "[ATLAS] terminal64 no volvió; salgo para que Docker reinicie limpio."
      break
    fi
    echo "[ATLAS] terminal64 relanzado (auto-update completado)."
  fi
done
