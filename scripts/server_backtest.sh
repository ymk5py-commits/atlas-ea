#!/bin/bash
#===============================================================================
# ATLAS EA — Backtest en el servidor (contenedor descartable, NO toca el bot vivo)
# Corre dentro de un docker run --rm sobre la misma imagen atlas-ea:1.0.
#===============================================================================
set -uo pipefail

MT5="/mt5/wine/drive_c/Program Files/MetaTrader 5"
W="wine"
export WINEPREFIX="/mt5/wine" WINEARCH=win64 WINEDEBUG=-all

RESULTS=/tmp/results.csv
echo "tag,scalp,ventana,periodo,balance_final,trades_totales,scalp_trades,dd_max" > "$RESULTS"

run_test() {
  local tag="$1" from="$2" to="$3" sessStart="$4" sessEnd="$5" enableScalp="$6" label="$7"
  local sess_lines="" scalp_line="InpEnableScalp=$enableScalp"$'\r\n'
  if [ -n "$sessStart" ]; then
    sess_lines="InpSessionStart=$sessStart"$'\r\n'"InpSessionEnd=$sessEnd"$'\r\n'
  fi
  printf '[Common]\r\nLogin=%s\r\nPassword=%s\r\nServer=%s\r\n[Tester]\r\nExpert=Atlas\\Atlas_EA\r\nSymbol=XAUUSD\r\nPeriod=M15\r\nModel=1\r\nFromDate=%s\r\nToDate=%s\r\nDeposit=500\r\nCurrency=USD\r\nLeverage=100\r\nShutdownTerminal=1\r\nVisual=0\r\n[TesterInputs]\r\nInpRiskPct=1.5\r\nInpRR=2.0\r\nInpBeTriggerR=1.0\r\nInpTrailAtrMult=2.0\r\nInpMaxDrawdownPct=100\r\n%s%s' \
    "$MT_LOGIN" "$MT_PASSWORD" "$MT_SERVER" "$from" "$to" "$scalp_line" "$sess_lines" > "$MT5/bt.ini"
  find "$MT5/Tester" -mindepth 1 -maxdepth 1 -type d -name 'Agent-*' -exec rm -rf {} + 2>/dev/null
  xvfb-run -a $W 'C:\mt5\terminal64.exe' /portable '/config:C:\mt5\bt.ini' >/dev/null 2>&1
  sleep 2
  local LOG=""
  for d in "$MT5/Tester/"Agent-*; do
    local f=$(find "$d/logs" -name '*.log' 2>/dev/null | head -1)
    [ -n "$f" ] && LOG="$f" && break
  done
  if [ -z "$LOG" ]; then
    echo "$tag,$enableScalp,$([ -n "$sessStart" ] && echo VIEJA || echo NUEVA),$label,ERROR,0,0,0" >> "$RESULTS"
    echo "[bt] $tag: SIN LOG (fallo)"
    return
  fi
  iconv -f UTF-16LE -t UTF-8 "$LOG" > "/tmp/bt_$tag.log" 2>/dev/null
  local bal=$(grep "final balance" "/tmp/bt_$tag.log" | tail -1 | sed 's/.*balance //; s/ USD.*//')
  local trades=$(grep -cE '\[ATLAS\] (XAUUSD|EURUSD) (COMPRA|VENTA) [0-9]' "/tmp/bt_$tag.log")
  local scalps=$(grep -cE 'SCALP (XAUUSD|EURUSD)' "/tmp/bt_$tag.log")
  local dd=$(grep "Nuevo dia" "/tmp/bt_$tag.log" | sed 's/.*base: //' | awk 'BEGIN{peak=0;maxdd=0} {if($1>peak)peak=$1; d=(peak-$1)/peak*100; if(d>maxdd)maxdd=d} END{printf "%.1f", maxdd}')
  echo "$tag,$enableScalp,$([ -n "$sessStart" ] && echo VIEJA || echo NUEVA),$label,$bal,$trades,$scalps,$dd" >> "$RESULTS"
  echo "[bt] $tag ($label, scalp=$enableScalp, $([ -n "$sessStart" ] && echo VIEJA-8-20 || echo NUEVA-1-23)): balance=$bal | trades=$trades (scalp=$scalps) | DD=$dd%"
}

# 1) Sistema completo (con scalp), ventana NUEVA (1-23) — falta este dato
run_test full_nueva_conscalp   2023.01.01 2026.07.31 "" "" true "2023-2026"

# 2) Nucleo Tendencia+Ruptura SOLO (sin scalp), ventana VIEJA validada — el chequeo urgente
run_test core_vieja_sinscalp   2023.01.01 2026.07.31 8 20 false "2023-2026"

# 3) Nucleo Tendencia+Ruptura SOLO (sin scalp), ventana NUEVA
run_test core_nueva_sinscalp   2023.01.01 2026.07.31 "" "" false "2023-2026"

echo "[bt] COMPLETO"
cat "$RESULTS"
