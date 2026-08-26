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
# ─────────────────────────────────────────────────────────────────────────
# CARTERA Y ESTRATEGIAS: la fuente de verdad es src/Atlas_EA.mq5
#
# Este script NO repite los valores de la cartera. Antes sí lo hacía, y en
# agosto 2026 el resultado fue que el servidor corría EURUSD+XAUUSD con Smart
# Money solo en el oro mientras el EA ya traía compilada la cartera validada
# (XAUUSD+USDJPY+XAGUSD): el .set pisaba los defaults del EA en silencio, la
# plata —el mejor instrumento del backtest— nunca se cargaba, y EURUSD entraba
# sin ninguna estrategia asignada.
#
# Regla nueva: una linea Inp*= se escribe SOLO si su variable de entorno esta
# DEFINIDA. Si no la definis, la linea no existe y manda el default compilado
# del EA. Definir la variable vacia (VAR=) es un override valido y explicito
# que significa "ninguno".
# ─────────────────────────────────────────────────────────────────────────
: "${ATLAS_RISK:=1.5}"
: "${ATLAS_DAILY_LOSS:=5.0}"
: "${ATLAS_MAX_DD:=30.0}"
: "${ATLAS_LOCAL_GMT_OFFSET:=-3}"

if [ -n "${ATLAS_SCALP:-}" ] || [ -n "${ATLAS_SCALP_SYMBOLS:-}" ]; then
   echo "[ATLAS] AVISO: ATLAS_SCALP / ATLAS_SCALP_SYMBOLS ya no aplican (v2)."
   echo "[ATLAS]        El scalping se activa solo con ATLAS_M1_SCALP_SYMBOLS."
fi

mkdir -p "$PARAMS_DIR"

# Escribe la linea 'Inp<Nombre>=valor' solo si la variable de entorno esta DEFINIDA.
# Usa ${!var+x} (definida, aunque sea vacia) y no ${!var:+x} (definida y no
# vacia): para las listas de estrategia, vacio es un valor con significado.
OVERRIDES=""
emit_if_set() {
  local input="$1" var="$2"
  if [ -n "${!var+x}" ]; then
    printf '%s=%s\r\n' "$input" "${!var}"
    OVERRIDES="${OVERRIDES}${OVERRIDES:+, }${input}=${!var:-(ninguno)}"
  fi
}

# Parametros del EA v2. Gestion de posicion validada por backtest
# (RR 2.0 / BE 1.0R / Trail 2.0 ATR).
{
  printf 'InpEnablePush=true\r\n'
  printf 'InpRiskPct=%s\r\n'          "$ATLAS_RISK"
  printf 'InpDailyLossPct=%s\r\n'     "$ATLAS_DAILY_LOSS"
  printf 'InpMaxDrawdownPct=%s\r\n'   "$ATLAS_MAX_DD"
  printf 'InpRR=2.0\r\n'
  printf 'InpBeTriggerR=1.0\r\n'
  printf 'InpTrailAtrMult=2.0\r\n'
  printf 'InpLocalGmtOffset=%s\r\n'   "$ATLAS_LOCAL_GMT_OFFSET"

  # Cartera, estrategias y sesiones: solo si se piden explicitamente.
  emit_if_set InpSymbols         ATLAS_SYMBOLS
  emit_if_set InpCrtSymbols      ATLAS_CRT_SYMBOLS
  emit_if_set InpSmcSymbols      ATLAS_SMC_SYMBOLS
  emit_if_set InpTrendSymbols    ATLAS_TREND_SYMBOLS
  emit_if_set InpBreakoutSymbols ATLAS_BREAKOUT_SYMBOLS
  emit_if_set InpRevSymbols      ATLAS_REV_SYMBOLS
  emit_if_set InpScalpSymbols    ATLAS_M1_SCALP_SYMBOLS
  emit_if_set InpNewYorkSymbols  ATLAS_NY_SYMBOLS
  emit_if_set InpLondonSymbols   ATLAS_LONDON_SYMBOLS
} > "${PARAMS_DIR}/atlas_params.set"

# Trampa clasica: pedir simbolos nuevos sin darles estrategia ni sesion.
# Quedarian en InpSymbols pero en ninguna lista -> el EA los loguea como
# "NINGUNA (no va a operar)" y ademas caen en la ventana horaria de respaldo.
if [ -n "${ATLAS_SYMBOLS+x}" ] && [ -z "${ATLAS_SMC_SYMBOLS+x}" ] \
   && [ -z "${ATLAS_CRT_SYMBOLS+x}" ] && [ -z "${ATLAS_TREND_SYMBOLS+x}" ] \
   && [ -z "${ATLAS_BREAKOUT_SYMBOLS+x}" ] && [ -z "${ATLAS_REV_SYMBOLS+x}" ]; then
   echo "[ATLAS] ⚠ ATENCION: pediste ATLAS_SYMBOLS='${ATLAS_SYMBOLS}' pero no definiste"
   echo "[ATLAS]   ninguna lista de estrategia. Los simbolos que no figuren en la lista"
   echo "[ATLAS]   compilada del EA no van a operar y no van a tener sesion asignada."
   echo "[ATLAS]   Revisa la linea por simbolo del log de arranque."
fi

# Grafico donde se engancha el EA: es solo el contenedor, una sola instancia
# maneja TODOS los simbolos de InpSymbols. Si el .env no sobreescribe la
# cartera, se usa XAUUSD, que es el primero de la cartera compilada del EA.
CHART_SYMBOL="${ATLAS_CHART_SYMBOL:-}"
if [ -z "$CHART_SYMBOL" ]; then
  CANDIDATA="${ATLAS_SYMBOLS:-XAUUSD}"
  CHART_SYMBOL="${CANDIDATA%%,*}"
fi

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
  printf 'Symbol=%s\r\n' "$CHART_SYMBOL"
  printf 'Period=M15\r\n'
  printf 'ExpertParameters=atlas_params.set\r\n'
} > "$CFG"
chmod 600 "$CFG"

echo "[ATLAS] Iniciando MetaTrader 5 headless — cuenta ${MT_LOGIN} en ${MT_SERVER}"
echo "[ATLAS] Riesgo ${ATLAS_RISK}%/op · limite diario ${ATLAS_DAILY_LOSS}% · kill switch ${ATLAS_MAX_DD}%"
if [ -n "$OVERRIDES" ]; then
  echo "[ATLAS] Cartera/estrategias SOBREESCRITAS por el .env: ${OVERRIDES}"
else
  echo "[ATLAS] Cartera y estrategias: las compiladas en el EA (sin override en el .env)."
fi
echo "[ATLAS] La verdad final la dice el EA: mira las lineas 'SIMBOLO | estrategias | sesion' de abajo."

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
