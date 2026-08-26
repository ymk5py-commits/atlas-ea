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
IMAGE="atlas-ea:2.0"

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

# La cuenta Y la cartera viven en ~/atlas-ea/.env, que escribe set_password.sh.
# Este script NO vuelve a preguntar los símbolos ni inventa una cartera: antes
# sí lo hacía, con un default 'EURUSD,XAUUSD' que ya no es la cartera validada,
# y como tampoco pasaba las listas de estrategia, los símbolos nuevos entraban
# sin estrategia y sin sesión. Una sola fuente de verdad: el .env, igual que
# update_atlas.sh.
ENVFILE="$HOME/atlas-ea/.env"
if [ ! -f "$ENVFILE" ]; then
   echo "  ✗ No existe $ENVFILE"
   echo "    Corré primero:  bash ~/atlas-ea/docker/set_password.sh"
   exit 1
fi

echo "  Config: $ENVFILE"
grep -aE '^ATLAS_' "$ENVFILE" | sed 's/^/      /'

echo
echo "  Deteniendo instancia anterior si existe..."
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "  Arrancando el bot..."
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  --memory 3g \
  --cpus 2 \
  --env-file "$ENVFILE" \
  -v atlas-ea-data:/mt5/wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/Logs \
  "$IMAGE" >/dev/null

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
  Riesgo, límite diario y kill switch: los del .env de arriba.
  Se reinicia solo si se cae o si reiniciás el servidor.

  VERIFICÁ AHORA en el log una línea por símbolo con sus estrategias
  y su sesión. Si alguna dice "NINGUNA (no va a operar)", ese símbolo
  está en la cartera pero sin estrategia asignada: corregí el .env.

  Ver el diario  : docker logs -f atlas-ea
  Ver estado     : docker ps --filter name=atlas-ea
  Apagar el bot  : docker stop atlas-ea
  Encender       : docker start atlas-ea

  Las operaciones las ves en la app MetaTrader del celular,
  con la misma cuenta de siempre.
════════════════════════════════════════════════════════════════

FIN
