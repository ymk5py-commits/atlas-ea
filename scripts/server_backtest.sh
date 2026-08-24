#!/bin/bash
#===============================================================================
# ATLAS EA v2 — Backtest en el servidor (contenedor descartable, NO toca el bot)
#
# Corre las preguntas ABIERTAS. Las respondidas quedan documentadas al pie
# y en el commit 2e0fc4f; no se re-corren.
#
#   1. EURUSD  solo Smart Money            (¿el euro tiene ventaja con SMC?)
#   2. EURUSD  SMC estricto (con barrido)  (si el default no paga, ¿la version
#      mas selectiva si? En sintetico el barrido filtra ~80% de las senales)
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

run_test() {
  local tag="$1" symbol="$2" crt="$3" smc="$4" extra="${5:-}"
  local crt_v="${crt:-$NADA}" smc_v="${smc:-$NADA}"
  printf '[Common]\r\nLogin=%s\r\nPassword=%s\r\nServer=%s\r\n[Tester]\r\nExpert=Atlas\\Atlas_EA\r\nSymbol=%s\r\nPeriod=M15\r\nModel=1\r\nFromDate=%s\r\nToDate=%s\r\nDeposit=500\r\nCurrency=USD\r\nLeverage=100\r\nShutdownTerminal=1\r\nVisual=0\r\n[TesterInputs]\r\nInpSymbols=%s\r\nInpRiskPct=1.5\r\nInpRR=2.0\r\nInpBeTriggerR=1.0\r\nInpTrailAtrMult=2.0\r\nInpMaxDrawdownPct=100\r\nInpCrtSymbols=%s\r\nInpSmcSymbols=%s\r\nInpTrendSymbols=%s\r\nInpBreakoutSymbols=%s\r\nInpScalpSymbols=%s\r\nInpNewYorkSymbols=EURUSD\r\nInpLondonSymbols=XAUUSD\r\n%s' \
    "$MT_LOGIN" "$MT_PASSWORD" "$MT_SERVER" "$symbol" "$FROM" "$TO" \
    "$symbol" "$crt_v" "$smc_v" "$NADA" "$NADA" "$NADA" "$extra" > "$MT5/bt.ini"

  find "$MT5/Tester" -mindepth 1 -maxdepth 1 -type d -name 'Agent-*' -exec rm -rf {} + 2>/dev/null
  xvfb-run -a $W 'C:\mt5\terminal64.exe' /portable '/config:C:\mt5\bt.ini' >/dev/null 2>&1
  sleep 2

  local LOG=""
  for d in "$MT5/Tester/"Agent-*; do
    local f=$(find "$d/logs" -name '*.log' 2>/dev/null | head -1)
    [ -n "$f" ] && LOG="$f" && break
  done
  if [ -z "$LOG" ]; then
    echo "$tag,$symbol,$crt,$smc,ERROR,0,0" >> "$RESULTS"
    echo "[bt] $tag: SIN LOG (fallo)"
    return
  fi
  iconv -f UTF-16LE -t UTF-8 "$LOG" > "/tmp/bt_$tag.log" 2>/dev/null
  local bal=$(grep "final balance" "/tmp/bt_$tag.log" | tail -1 | sed 's/.*balance //; s/ USD.*//')
  local trades=$(grep -cE '\[ATLAS\] (XAUUSD|EURUSD) (COMPRA|VENTA) [0-9]' "/tmp/bt_$tag.log")
  local dd=$(grep "Nuevo dia" "/tmp/bt_$tag.log" | sed 's/.*base: //' | awk 'BEGIN{peak=0;maxdd=0} {if($1>peak)peak=$1; d=(peak-$1)/peak*100; if(d>maxdd)maxdd=d} END{printf "%.1f", maxdd}')
  echo "$tag,$symbol,${crt:-no},${smc:-no},$bal,$trades,$dd" >> "$RESULTS"
  echo "[bt] $tag ($symbol | CRT=${crt:-no} SMC=${smc:-no}): balance=$bal | trades=$trades | DD diario max=$dd%"
}

# CONTROL: todo apagado. Si esto NO da 0 trades, los overrides no se aplican
# y el resto de los numeros no vale nada — se aborta.
run_test   control_nada    XAUUSD   ""       ""
CONTROL_TRADES=$(grep "^control_nada," "$RESULTS" | cut -d, -f6)
if [ "${CONTROL_TRADES:-0}" != "0" ]; then
  echo "[bt] ABORTADO: el control con todo apagado hizo $CONTROL_TRADES trades."
  echo "[bt] Los overrides de [TesterInputs] NO se estan aplicando; los resultados serian invalidos."
  exit 1
fi
echo "[bt] control OK (0 trades con todo apagado) — los overrides se aplican, sigo."

#          tag              simbolo  CRT  SMC     [extra TesterInputs]
run_test   eur_smc          EURUSD   ""   EURUSD
run_test   eur_smc_barrido  EURUSD   ""   EURUSD  $'InpSmcRequireSweep=true\r\n'

# Variante disponible para despues (mismo mecanismo, oro mas selectivo):
# run_test oro_smc_barrido  XAUUSD   ""   XAUUSD  $'InpSmcRequireSweep=true\r\n'

# --- YA RESPONDIDAS (2023-2026, 500 USD; commit 2e0fc4f) — no re-correr ---
# oro solo SMC     561.02 (+12.2%)  84 trades  DD 8.8%   <- config vigente
# oro CRT+SMC      522.63 (+4.5%)  297 trades  DD 14.5%
# oro solo CRT     493.74 (-1.3%)  210 trades  DD 13.7%
# EURUSD con CRT   297.26 (-40.5%) 207 trades  DD 43.6%

echo "[bt] COMPLETO"
cat "$RESULTS"
