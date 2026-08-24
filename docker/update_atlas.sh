#!/bin/bash
#===============================================================================
# ATLAS EA — Actualizar el bot a la última versión del repo y relanzarlo.
#
# La imagen nueva SOLO reemplaza a la vieja si el EA COMPILA: la compilación
# corre dentro del build de Docker y el build falla si MetaEditor reporta un
# error. Si el build falla, el bot actual sigue corriendo intacto.
#
# No pide credenciales: usa ~/atlas-ea/.env (escrito por set_password.sh).
#
# Uso:  bash ~/atlas-ea/docker/update_atlas.sh
#===============================================================================
set -uo pipefail

REPO="$HOME/atlas-ea"
NAME="atlas-ea"
IMAGE="atlas-ea:2.0"

export DOCKER_HOST="unix:///var/run/docker.sock"
DOCKER=/usr/bin/docker
[ -x "$DOCKER" ] || DOCKER="$(command -v docker)"

cd "$REPO" || { echo "✗ No existe $REPO"; exit 1; }

echo "════════════════════════════════════════════════════════════════"
echo "  ATLAS EA — actualización"
echo "════════════════════════════════════════════════════════════════"
echo "  Rama: $(git rev-parse --abbrev-ref HEAD)"
git pull --ff-only || { echo "✗ git pull falló (¿cambios locales?). Nada se tocó."; exit 1; }
echo "  Commit: $(git log --oneline -1)"

# Verificación estática previa (informativa: el build tiene la última palabra)
if command -v python3 >/dev/null 2>&1; then
   python3 scripts/check_sources.py || echo "  ⚠ El verificador estático encontró algo — el compilador del build decidirá."
fi

echo
echo "  Compilando dentro de la imagen (esto tarda unos minutos)..."
if ! "$DOCKER" build -f docker/Dockerfile -t "$IMAGE" . ; then
   echo
   echo "  ✗ EL BUILD FALLÓ — el EA no compiló."
   echo "    El bot que estaba corriendo SIGUE CORRIENDO sin cambios."
   exit 1
fi
echo "  ✓ EA compilado dentro de la imagen"

if [ ! -f "$REPO/.env" ]; then
   echo "  ✗ No hay $REPO/.env — correr primero: bash docker/set_password.sh"
   exit 1
fi

echo "  Relanzando el bot con la imagen nueva..."
"$DOCKER" rm -f "$NAME" >/dev/null 2>&1 || true
"$DOCKER" run -d \
  --name "$NAME" \
  --restart unless-stopped \
  --memory 3g \
  --cpus 2 \
  --env-file "$REPO/.env" \
  -v atlas-ea-data:"/mt5/wine/drive_c/Program Files/MetaTrader 5/MQL5/Logs" \
  "$IMAGE" >/dev/null || { echo "✗ docker run falló"; exit 1; }

sleep 25
if [ "$("$DOCKER" inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" != "true" ]; then
   echo "  ✗ El contenedor no arrancó. Ver: docker logs $NAME"
   exit 1
fi

echo "  ✓ Bot relanzado. Primeras líneas:"
"$DOCKER" logs --tail 20 "$NAME" 2>&1 | sed 's/^/    /'
echo
echo "  Verificá que aparezca 'ATLAS EA v2.00 iniciado' y una línea por símbolo"
echo "  con su sesión traducida. Seguimiento: docker logs -f $NAME"
