#!/bin/bash
#===============================================================================
# ATLAS EA — Reversión M1 (método manual del dueño) + plata con Smart Money
#
# PARTE A — REVERSIÓN: el método real del dueño, testeado por primera vez.
#   "bajada fuerte -> compra, subida fuerte -> venta, 5-10 min".
#   Es lo OPUESTO al ScalpStrategy (momentum) que se probó antes y dio -80%.
#   Se corre con Model=4 (TICKS REALES): en M1 con SL/TP ajustados, el modelo
#   OHLC adivina cuál se toca primero y los resultados no sirven.
#   Variantes: umbral de impulso y tiempo de salida.
#
# PARTE B — Plata (XAGUSD) con Smart Money, comparable con oro/USDJPY.
#   (El petróleo NO existe como CFD en MetaQuotes-Demo: solo acciones/ETFs.)
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

  printf '[Common]\r\nLogin=%s\r\nPassword=%s\r\nServer=%s\r\n[Tester]\r\nExpert=Atlas\\Atlas_EA\r\nSymbol=%s\r\nPeriod=M15\r\nModel=%s\r\nFromDate=%s\r\nToDate=%s\r\nDeposit=500\r\nCurrency=USD\r\nLeverage=100\r\nShutdownTerminal=1\r\nVisual=0\r\n[TesterInputs]\r\nInpSymbols=%s\r\nInpMaxDrawdownPct=100\r\nInpCrtSymbols=%s\r\nInpSmcSymbols=%s\r\nInpTrendSymbols=%s\r\nInpBreakoutSymbols=%s\r\nInpScalpSymbols=%s\r\nInpRevSymbols=%s\r\n%s' \
    "$MT_LOGIN" "$MT_PASSWORD" "$MT_SERVER" "$symbol" "$model" "$from" "$to" \
    "$symbol" "$NADA" "$NADA" "$NADA" "$NADA" "$NADA" "$NADA" "$extra" > "$MT5/bt.ini"

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

#--- CONTROL
corre control XAUUSD 1 2026.01.01 2026.07.31 control
CT=$(grep '^control,' "$RESULTS" | cut -d, -f7)
if [ "${CT:-0}" != "0" ]; then
  echo "[bt] ABORTADO: el control hizo $CT trades — los overrides no se aplican."; exit 1
fi
echo "[bt] control OK."
echo

echo "════ PARTE A — REVERSIÓN (método manual), ticks REALES ════"
# Base: impulso 2 ATR, salida 8 min, objetivo 50% del tramo
corre rev_base      XAUUSD 4 2026.01.01 2026.07.31 A \
  InpRevSymbols=XAUUSD InpScalpStart=1 InpScalpEnd=23
# Más exigente con el impulso (solo extremos grandes)
corre rev_exigente  XAUUSD 4 2026.01.01 2026.07.31 A \
  InpRevSymbols=XAUUSD InpScalpStart=1 InpScalpEnd=23 \
  InpRevImpulseAtr=3.0 InpRevRsiLow=20 InpRevRsiHigh=80
# Salida más corta (5 min), como el extremo bajo del rango que usa el dueño
corre rev_5min      XAUUSD 4 2026.01.01 2026.07.31 A \
  InpRevSymbols=XAUUSD InpScalpStart=1 InpScalpEnd=23 InpRevHoldMin=5

echo
echo "════ PARTE B — Plata con Smart Money (2023-2026) ════"
corre smc_XAGUSD XAGUSD 1 2023.01.01 2026.07.31 B \
  InpSmcSymbols=XAGUSD InpLondonSymbols=XAGUSD InpNewYorkSymbols=""

echo
echo "[bt] COMPLETO"
cat "$RESULTS"
