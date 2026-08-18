#!/bin/bash
#===============================================================================
# ATLAS EA — Encender el bot 24/5 en el servidor (contenedor Docker)
#
# Pide la contraseña de la cuenta MetaTrader de forma interactiva: se escribe
# acá, en el servidor, y no queda en el historial de comandos ni en la imagen.
#
# Uso:  bash ~/atlas-ea/docker/start_atlas.sh
#===============================================================================
set -uo pipefail

NAME="atlas-ea"
IMAGE="atlas-ea:1.0"

# El escritorio gráfico puede tener un docker de snap (daemon distinto, sin
# nuestras imágenes). Forzamos el binario y el socket del sistema.
export DOCKER_HOST="unix:///var/run/docker.sock"
DOCKER=/usr/bin/docker
[ -x "$DOCKER" ] || DOCKER="$(command -v docker)"
docker() { "$DOCKER" "$@"; }

echo "════════════════════════════════════════════════════════════════"
echo "  ATLAS EA — encender el bot en este servidor"
echo "════════════════════════════════════════════════════════════════"
echo "  docker: $DOCKER"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
   echo "  ✗ No existe la imagen $IMAGE en este daemon."
   echo "    Imagenes visibles:"
   docker images --format "      {{.Repository}}:{{.Tag}}" 2>&1 | head -5
   exit 1
fi

read -rp "  Número de cuenta (login)     : " MT_LOGIN
read -rp "  Servidor  [MetaQuotes-Demo]  : " MT_SERVER
MT_SERVER="${MT_SERVER:-MetaQuotes-Demo}"
read -rsp "  Contraseña (no se muestra)   : " MT_PASSWORD
echo
read -rp "  Símbolos  [XAUUSD,EURUSD]    : " ATLAS_SYMBOLS
ATLAS_SYMBOLS="${ATLAS_SYMBOLS:-XAUUSD,EURUSD}"

if [ -z "$MT_LOGIN" ] || [ -z "$MT_PASSWORD" ]; then
   echo "  ✗ Login y contraseña son obligatorios."
   exit 1
fi

echo
echo "  Deteniendo instancia anterior si existe..."
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "  Arrancando el bot..."
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  --memory 3g \
  --cpus 2 \
  -e MT_LOGIN="$MT_LOGIN" \
  -e MT_PASSWORD="$MT_PASSWORD" \
  -e MT_SERVER="$MT_SERVER" \
  -e ATLAS_SYMBOLS="$ATLAS_SYMBOLS" \
  -e ATLAS_RISK=1.5 \
  -e ATLAS_DAILY_LOSS=5.0 \
  -e ATLAS_MAX_DD=30.0 \
  -v atlas-ea-data:/mt5/wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Logs \
  "$IMAGE" >/dev/null

unset MT_PASSWORD

sleep 20
if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ]; then
   echo "  ✓ Contenedor activo"
else
   echo "  ✗ El contenedor no arrancó. Ver: docker logs $NAME"
   exit 1
fi

echo
echo "  Primeras líneas del bot:"
docker logs --tail 15 "$NAME" 2>&1 | sed 's/^/    /'

cat <<FIN

════════════════════════════════════════════════════════════════
  EL BOT ESTÁ CORRIENDO 24/5
════════════════════════════════════════════════════════════════
  Riesgo 1.5%/operación · límite diario 5% · kill switch 30%
  Se reinicia solo si se cae o si reiniciás el servidor.

  Ver el diario  : docker logs -f atlas-ea
  Ver estado     : docker ps --filter name=atlas-ea
  Apagar el bot  : docker stop atlas-ea
  Encender       : docker start atlas-ea

  Las operaciones las ves en la app MetaTrader del celular,
  con la misma cuenta de siempre.
════════════════════════════════════════════════════════════════

FIN
