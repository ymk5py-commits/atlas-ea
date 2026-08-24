#!/bin/bash
#===============================================================================
# ATLAS EA — Dos investigaciones (contenedor descartable, NO toca el bot vivo)
#
# PARTE A — Smart Money en otros pares
#   El oro con SMC da +12.2%. ¿El mismo motor sirve en GBPUSD/USDJPY/USDCHF?
#   Model=1 (OHLC M1) para ser comparable con los SMC ya corridos.
#
# PARTE B — El scalping, testeado como corresponde
#   Los backtests previos usaron Model=1 (OHLC de 1 minuto): 4 puntos de precio
#   por vela. Para una estrategia de M15 alcanza; para una de M1 con SL/TP
#   ajustados NO: cuál se toca primero dentro de la vela lo ADIVINA el
#   simulador. El -96% puede ser artefacto del modelo. Se corre la MISMA
#   ventana con Model=1 y con Model=4 (ticks reales) para comparar.
#===============================================================================
set -uo pipefail

MT5="/mt5/wine/drive_c/Program Files/MetaTrader 5"
export WINEPREFIX="/mt5/wine" WINEARCH=win64 WINEDEBUG=-all
NADA="__NINGUNO__"
RESULTS=/tmp/results.csv
echo "parte,tag,simbolo,modelo,periodo,balance_final,trades,dd_max_diario" > "$RESULTS"

# $1 tag · $2 simbolo · $3 modelo · $4 desde · $5 hasta · $6 parte · $7.. overrides
corre() {
  local tag="$1" symbol="$2" model="$3" from="$4" to="$5" parte="$6"; shift 6
  local extra=""
  for kv in "$@"; do extra+="${kv}"$'\r\n'; done

  printf '[Common]\r\nLogin=%s\r\nPassword=%s\r\nServer=%s\r\n[Tester]\r\nExpert=Atlas\\Atlas_EA\r\nSymbol=%s\r\nPeriod=M15\r\nModel=%s\r\nFromDate=%s\r\nToDate=%s\r\nDeposit=500\r\nCurrency=USD\r\nLeverage=100\r\nShutdownTerminal=1\r\nVisual=0\r\n[TesterInputs]\r\nInpSymbols=%s\r\nInpRiskPct=1.5\r\nInpRR=2.0\r\nInpBeTriggerR=1.0\r\nInpTrailAtrMult=2.0\r\nInpMaxDrawdownPct=100\r\n%s' \
    "$MT_LOGIN" "$MT_PASSWORD" "$MT_SERVER" "$symbol" "$model" "$from" "$to" \
    "$symbol" "$extra" > "$MT5/bt.ini"

  find "$MT5/Tester" -mindepth 1 -maxdepth 1 -type d -name 'Agent-*' -exec rm -rf {} + 2>/dev/null
  xvfb-run -a wine 'C:\mt5\terminal64.exe' /portable '/config:C:\mt5\bt.ini' >/dev/null 2>&1
  sleep 2

  local LOG=""
  for d in "$MT5/Tester/"Agent-*; do
    local f=$(find "$d/logs" -name '*.log' 2>/dev/null | head -1)
    [ -n "$f" ] && LOG="$f" && break
  done
  if [ -z "$LOG" ]; then
    echo "$parte,$tag,$symbol,$model,$from..$to,ERROR,0,0" >> "$RESULTS"
    echo "[bt] $tag: SIN LOG (fallo)"; return
  fi
  iconv -f UTF-16LE -t UTF-8 "$LOG" > "/tmp/bt_$tag.log" 2>/dev/null
  local bal=$(grep "final balance" "/tmp/bt_$tag.log" | tail -1 | sed 's/.*balance //; s/ USD.*//')
  local tr=$(grep -acE '\[ATLAS\] (SCALP )?[A-Z]{6} (COMPRA|VENTA) [0-9]' "/tmp/bt_$tag.log")
  local dd=$(grep "Nuevo dia" "/tmp/bt_$tag.log" | sed 's/.*base: //' | awk 'BEGIN{p=0;m=0}{if($1>p)p=$1;d=(p-$1)/p*100;if(d>m)m=d}END{printf "%.1f",m}')
  echo "$parte,$tag,$symbol,$model,$from..$to,$bal,$tr,$dd" >> "$RESULTS"
  echo "[bt][$parte] $tag ($symbol, modelo=$model): balance=$bal | trades=$tr | DD=$dd%"
}

SOLO_SMC=(InpCrtSymbols=$NADA InpTrendSymbols=$NADA InpBreakoutSymbols=$NADA InpScalpSymbols=$NADA)
SOLO_SCALP=(InpCrtSymbols=$NADA InpSmcSymbols=$NADA InpTrendSymbols=$NADA InpBreakoutSymbols=$NADA)

#--- CONTROL: sin estrategias no puede haber trades; si los hay, los overrides fallan
corre control XAUUSD 1 2023.01.01 2026.07.31 control \
  InpCrtSymbols=$NADA InpSmcSymbols=$NADA InpTrendSymbols=$NADA \
  InpBreakoutSymbols=$NADA InpScalpSymbols=$NADA
CT=$(grep '^control,' "$RESULTS" | cut -d, -f7)
if [ "${CT:-0}" != "0" ]; then
  echo "[bt] ABORTADO: el control hizo $CT trades — los overrides no se aplican."
  exit 1
fi
echo "[bt] control OK — los overrides se aplican."
echo

echo "════ PARTE A — Smart Money en otros pares (2023-2026) ════"
for par in GBPUSD USDJPY USDCHF; do
  corre "smc_${par}" "$par" 1 2023.01.01 2026.07.31 A \
    InpSmcSymbols="$par" "${SOLO_SMC[@]}" \
    InpNewYorkSymbols="$par" InpLondonSymbols=""
done

echo
echo "════ PARTE B — Scalping: OHLC-M1 vs ticks REALES (misma ventana) ════"
for m in 1 4; do
  etiqueta=$([ "$m" = "1" ] && echo "ohlc" || echo "ticks_reales")
  corre "scalp_${etiqueta}" XAUUSD "$m" 2026.01.01 2026.07.31 B \
    InpScalpSymbols=XAUUSD "${SOLO_SCALP[@]}"
done

echo
echo "[bt] COMPLETO"
cat "$RESULTS"
