#!/bin/bash
#===============================================================================
# ATLAS EA — Manejo diario de las cuentas (multi-cuenta)
#
# Uso:  bash ~/atlas-ea/docker/cuentas.sh <orden> [nombre]
#
#   lista            estado de todas las cuentas
#   log <nombre>     diario del bot de esa cuenta (últimas líneas)
#   conexion <n>     estado de conexión al broker de esa cuenta
#   parar <nombre>   apagar el bot de esa cuenta (las posiciones quedan con SL/TP)
#   arrancar <n>     volver a encenderlo
#   borrar <nombre>  eliminar contenedor + configuración de esa cuenta
#===============================================================================
set -uo pipefail

D=/usr/bin/docker
BASE="$HOME/atlas-ea"
ORDEN="${1:-lista}"
NOMBRE="${2:-}"

cont() { echo "atlas-${1}"; }
envfile() {
  if [ "$1" = "ea" ]; then echo "$BASE/.env"; else echo "$BASE/cuentas/$1.env"; fi
}

case "$ORDEN" in
  lista)
    echo "CUENTA          LOGIN        ESTADO"
    echo "──────────────────────────────────────────────"
    for c in $($D ps -a --format '{{.Names}}' | grep '^atlas-' | sort); do
      n="${c#atlas-}"
      st=$($D inspect -f '{{.State.Status}} ({{.State.StartedAt}})' "$c" 2>/dev/null | cut -c1-40)
      ef=$(envfile "$n")
      lg=$(grep '^MT_LOGIN=' "$ef" 2>/dev/null | cut -d= -f2)
      printf "%-15s %-12s %s\n" "$n" "${lg:-?}" "$st"
    done
    ;;
  log)
    [ -n "$NOMBRE" ] || { echo "Falta el nombre. Uso: cuentas.sh log <nombre>"; exit 1; }
    $D exec "$(cont "$NOMBRE")" bash -c \
      'F="/mt5/wine/drive_c/Program Files/MetaTrader 5/MQL5/logs/$(date +%Y%m%d).log"; [ -f "$F" ] && iconv -f UTF-16LE -t UTF-8 "$F" | tail -20 || echo "(sin log de hoy todavía)"'
    ;;
  conexion)
    [ -n "$NOMBRE" ] || { echo "Falta el nombre. Uso: cuentas.sh conexion <nombre>"; exit 1; }
    $D exec "$(cont "$NOMBRE")" bash -c \
      'F="/mt5/wine/drive_c/Program Files/MetaTrader 5/logs/$(date +%Y%m%d).log"; [ -f "$F" ] && iconv -f UTF-16LE -t UTF-8 "$F" | grep -aiE "authorized|no connection|connection lost" | tail -5 || echo "(sin log de hoy todavía)"'
    ;;
  parar)
    [ -n "$NOMBRE" ] || { echo "Falta el nombre."; exit 1; }
    $D stop "$(cont "$NOMBRE")" && echo "✓ $(cont "$NOMBRE") detenido (las posiciones abiertas conservan su SL/TP en el broker)"
    ;;
  arrancar)
    [ -n "$NOMBRE" ] || { echo "Falta el nombre."; exit 1; }
    $D start "$(cont "$NOMBRE")" && echo "✓ $(cont "$NOMBRE") encendido"
    ;;
  borrar)
    [ -n "$NOMBRE" ] || { echo "Falta el nombre."; exit 1; }
    read -rp "¿Seguro que querés borrar la cuenta '$NOMBRE'? (escribi SI): " OK
    [ "$OK" = "SI" ] || { echo "Cancelado."; exit 0; }
    $D rm -f "$(cont "$NOMBRE")" 2>/dev/null
    ef=$(envfile "$NOMBRE"); [ "$ef" != "$BASE/.env" ] && rm -f "$ef"
    echo "✓ Contenedor y configuración de '$NOMBRE' eliminados"
    echo "  (el volumen de logs atlas-logs-$NOMBRE queda por si querés auditar;"
    echo "   borralo con: $D volume rm atlas-logs-$NOMBRE)"
    ;;
  *)
    echo "Orden desconocida: $ORDEN"
    sed -n '5,12p' "$0"
    exit 1
    ;;
esac
