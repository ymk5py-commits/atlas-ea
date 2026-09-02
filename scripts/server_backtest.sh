#!/bin/bash
#===============================================================================
# ATLAS EA v2 — Backtest en el servidor (contenedor descartable, NO toca el bot)
#
# Re-verifica la CARTERA VIGENTE (oro + plata + USDJPY, todos con Smart Money),
# cuyos numeros estan documentados en src/Atlas_EA.mq5 pero nunca se
# re-corrieron juntos despues de sumar la plata.
#
# Uso (desde el servidor, con la imagen atlas-ea:2.0 ya construida):
#   docker run --rm --env-file ~/atlas-ea/.env \
#     -v ~/atlas-ea/scripts/server_backtest.sh:/bt.sh atlas-ea:2.0 bash /bt.sh
#
# Nota: el tester no tiene TimeGMT real; el EA asume broker EET (UTC+2/+3
# europeo) en backtest. Para un broker en otro huso, agregar
# InpServerGmtOffset=N en TesterInputs.
#===============================================================================
set -uo pipefail

MT5="/mt5/wine/drive_c/Program Files/MetaTrader 5"
W="wine"
export WINEPREFIX="/mt5/wine" WINEARCH=win64 WINEDEBUG=-all

FROM="${BT_FROM:-2023.01.01}"
TO="${BT_TO:-2026.07.31}"
RESULTS=/tmp/results.csv
echo "tag,simbolo,crt,smc,balance_final,trades,dd_max_diario" > "$RESULTS"

# OJO: MetaTrader IGNORA los inputs de texto que se pasan VACIOS en
# [TesterInputs] y aplica el valor por defecto del codigo. Para apagar una
# estrategia hay que darle un simbolo inexistente, no una cadena vacia.
NADA="__NINGUNO__"

# La SESION tiene que acompanar al simbolo que se mide. Antes este script
# fijaba InpNewYorkSymbols=EURUSD / InpLondonSymbols=XAUUSD a mano: cualquier
# otro simbolo caia en la ventana de respaldo (hora del servidor, 8-20h) en
# vez de su sesion real, y el resultado no era comparable con el del bot vivo.
# Se deduce igual que en el EA: metales a Londres, pares a Nueva York.
sesion_de() {
  local s="${1^^}"
  case "$s" in
    *XAU*|*GOLD*|*XAG*|*SILVER*|*XPT*|*XPD*) echo "LON" ;;
    *)                                       echo "NY"  ;;
  esac
}

run_test() {
  # 5º arg: simbolos de TENDENCIA (posicional — NO via extra: una clave duplicada
  # en el .ini hace que MetaTrader tome la PRIMERA y el override no aplique)
  local tag="$1" symbol="$2" crt="$3" smc="$4" trend="${5:-}" extra="${6:-}"
  local crt_v="${crt:-$NADA}" smc_v="${smc:-$NADA}" trend_v="${trend:-$NADA}"

  # Cartera: puede ser mas de un simbolo (pasada combinada). El grafico del
  # tester es siempre el primero.
  local cartera="${BT_SYMBOLS:-$symbol}"
  local chart="${cartera%%,*}"

  # Cada simbolo de la cartera a su sesion
  local lon="" ny=""
  local IFS_OLD="$IFS"; IFS=','
  for s in $cartera; do
    if [ "$(sesion_de "$s")" = "LON" ]; then lon="${lon:+$lon,}$s"; else ny="${ny:+$ny,}$s"; fi
  done
  IFS="$IFS_OLD"
  local lon_v="${lon:-$NADA}" ny_v="${ny:-$NADA}"

  printf '[Common]\r\nLogin=%s\r\nPassword=%s\r\nServer=%s\r\n[Tester]\r\nExpert=Atlas\\Atlas_EA\r\nSymbol=%s\r\nPeriod=M15\r\nModel=1\r\nFromDate=%s\r\nToDate=%s\r\nDeposit=500\r\nCurrency=USD\r\nLeverage=100\r\nShutdownTerminal=1\r\nVisual=0\r\n[TesterInputs]\r\nInpSymbols=%s\r\nInpRiskPct=1.5\r\nInpRR=2.0\r\nInpBeTriggerR=1.0\r\nInpTrailAtrMult=2.0\r\nInpMaxDrawdownPct=100\r\nInpCrtSymbols=%s\r\nInpSmcSymbols=%s\r\nInpTrendSymbols=%s\r\nInpBreakoutSymbols=%s\r\nInpScalpSymbols=%s\r\nInpRevSymbols=%s\r\nInpNewYorkSymbols=%s\r\nInpLondonSymbols=%s\r\n%s' \
    "$MT_LOGIN" "$MT_PASSWORD" "$MT_SERVER" "$chart" "$FROM" "$TO" \
    "$cartera" "$crt_v" "$smc_v" "$trend_v" "$NADA" "$NADA" "$NADA" \
    "$ny_v" "$lon_v" "$extra" > "$MT5/bt.ini"

  find "$MT5/Tester" -mindepth 1 -maxdepth 1 -type d -name 'Agent-*' -exec rm -rf {} + 2>/dev/null
  xvfb-run -a $W 'C:\mt5\terminal64.exe' /portable '/config:C:\mt5\bt.ini' >/dev/null 2>&1
  sleep 2

  local LOG=""
  for d in "$MT5/Tester/"Agent-*; do
    local f=$(find "$d/logs" -name '*.log' 2>/dev/null | head -1)
    [ -n "$f" ] && LOG="$f" && break
  done
  if [ -z "$LOG" ]; then
    echo "$tag,$cartera,$crt,$smc,ERROR,0,0" >> "$RESULTS"
    echo "[bt] $tag: SIN LOG (fallo)"
    return
  fi
  iconv -f UTF-16LE -t UTF-8 "$LOG" > "/tmp/bt_$tag.log" 2>/dev/null
  local bal=$(grep "final balance" "/tmp/bt_$tag.log" | tail -1 | sed 's/.*balance //; s/ USD.*//')
  # El contador tenia la lista de simbolos HARDCODEADA (XAUUSD|EURUSD): con la
  # cartera nueva, las operaciones de plata y de USDJPY contaban 0 y toda
  # pasada que las incluyera parecia no haber operado. Ahora sale de la cartera.
  local patron=$(echo "$cartera" | sed 's/,/|/g')
  local trades=$(grep -cE "\[ATLAS\] ($patron) (COMPRA|VENTA) [0-9]" "/tmp/bt_$tag.log")
  local dd=$(grep "Nuevo dia" "/tmp/bt_$tag.log" | sed 's/.*base: //' | awk 'BEGIN{peak=0;maxdd=0} {if($1>peak)peak=$1; d=(peak-$1)/peak*100; if(d>maxdd)maxdd=d} END{printf "%.1f", maxdd}')
  echo "$tag,$cartera,${crt:-no},${smc:-no},$bal,$trades,$dd" >> "$RESULTS"
  echo "[bt] $tag ($cartera | CRT=${crt:-no} SMC=${smc:-no}): balance=$bal | trades=$trades | DD diario max=$dd%"
}

# Nombres del broker. XM usa GOLD/SILVER; se pueden pisar por entorno.
ORO="${BT_ORO:-XAUUSD}"
PLATA="${BT_PLATA:-XAGUSD}"
JPY="${BT_JPY:-USDJPY}"

# CONTROL: todo apagado. Si esto NO da 0 trades, los overrides no se aplican
# y el resto de los numeros no vale nada — se aborta.
run_test   control_nada    "$ORO"   ""       ""
CONTROL_TRADES=$(grep "^control_nada," "$RESULTS" | cut -d, -f6)
if [ "${CONTROL_TRADES:-0}" != "0" ]; then
  echo "[bt] ABORTADO: el control con todo apagado hizo $CONTROL_TRADES trades."
  echo "[bt] Los overrides de [TesterInputs] NO se estan aplicando; los resultados serian invalidos."
  exit 1
fi
echo "[bt] control OK (0 trades con todo apagado) — los overrides se aplican, sigo."

# --- Re-verificacion de la cartera vigente -----------------------------------
# Cada pata en solitario, para poder contrastar contra los numeros que estan
# escritos en src/Atlas_EA.mq5, y despues las tres juntas.
#          tag           simbolo   CRT  SMC
run_test   oro_smc       "$ORO"    ""   "$ORO"
run_test   plata_smc     "$PLATA"  ""   "$PLATA"
run_test   jpy_smc       "$JPY"    ""   "$JPY"

# Cartera completa: el tester engancha el grafico al primero, pero el EA opera
# los tres. Es la unica pasada que mide la diversificacion.
BT_SYMBOLS="$ORO,$JPY,$PLATA" \
run_test   cartera_smc   "$ORO"    ""   "$ORO,$JPY,$PLATA"

# --- Esquema v2.1: ¿el gate de confianza o el check de volatilidad SUMAN
# sobre la config vigente? Nacen apagados; esto decide si se encienden.
#          tag              simbolo  CRT  SMC     TREND  extra
run_test   oro_smc_conf60   "$ORO"   ""   "$ORO"  ""     $'InpMinScore=60\r\n'
run_test   oro_smc_vol      "$ORO"   ""   "$ORO"  ""     $'InpVolCheck=true\r\n'

echo
echo "[bt] Contrastar contra lo documentado en src/Atlas_EA.mq5:"
echo "[bt]   oro_smc      esperado ~561.02 (+12.2%)  84 trades  DD  8.8%"
echo "[bt]   plata_smc    esperado ~605.89 (+21.2%)             DD  4.9%"
echo "[bt]   jpy_smc      esperado ~531.84 (+6.4%)              DD  9.8%"
echo "[bt]   cartera_smc  esperado ~725.00 (+45.0%) 229 trades  DD 12.3%"
echo "[bt] Si difieren mucho, revisar que los nombres de simbolo del broker"
echo "[bt] sean los correctos (BT_ORO / BT_PLATA / BT_JPY) y que haya historia."

# --- YA RESPONDIDAS (2023-2026, 500 USD) — no re-correr ---
# eur solo SMC        461.15 (-7.8%)   67 trades  DD 10.8%  <- sin ventaja
# eur SMC + barrido   508.25 (+1.7%)   19 trades  DD 6.4%   <- muestra insuficiente
# (commit 2e0fc4f y siguientes:)
# oro CRT+SMC      522.63 (+4.5%)  297 trades  DD 14.5%  <- CRT resta
# oro solo CRT     493.74 (-1.3%)  210 trades  DD 13.7%
# EURUSD con CRT   297.26 (-40.5%) 207 trades  DD 43.6%
# GBPUSD solo SMC  432.24 (-13.6%)                       <- descartado
# USDCHF solo SMC  526.08 (+5.2%)             DD 16.5%   <- mala relacion

echo "[bt] COMPLETO"
cat "$RESULTS"
