#!/bin/bash
#===============================================================================
# ATLAS EA — Agregar una cuenta nueva (multi-cuenta)
#
# Cada cuenta corre en SU PROPIO contenedor, con su propia configuración y sus
# propios logs. Totalmente aislada de las demás: se puede parar, actualizar o
# borrar una sin tocar las otras.
#
# La contraseña se escribe acá (en el servidor) y queda en un archivo protegido
# que solo tu usuario puede leer. No viaja por ningún chat.
#
# Uso:  bash ~/atlas-ea/docker/agregar_cuenta.sh
#===============================================================================
set -uo pipefail

IMAGE="atlas-ea:2.0"
BASE="$HOME/atlas-ea"
CUENTAS="$BASE/cuentas"

echo "════════════════════════════════════════════════════════════════"
echo "  ATLAS EA — agregar una cuenta nueva"
echo "════════════════════════════════════════════════════════════════"

if ! /usr/bin/docker image inspect "$IMAGE" >/dev/null 2>&1; then
   echo "  ✗ No existe la imagen $IMAGE. Construirla primero:"
   echo "    cd ~/atlas-ea && /usr/bin/docker build -f docker/Dockerfile -t $IMAGE ."
   exit 1
fi

read -rp "  Nombre corto de la cuenta (ej: demo2, xm-real): " NOMBRE
NOMBRE=$(echo "$NOMBRE" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9-')
if [ -z "$NOMBRE" ]; then
   echo "  ✗ Nombre inválido. Usar solo letras, números y guiones."
   exit 1
fi
CONT="atlas-$NOMBRE"
ENVFILE="$CUENTAS/$NOMBRE.env"

if /usr/bin/docker ps -a --format '{{.Names}}' | grep -qx "$CONT"; then
   echo "  ✗ Ya existe un contenedor '$CONT'. Elegí otro nombre, o borralo antes:"
   echo "    bash ~/atlas-ea/docker/cuentas.sh borrar $NOMBRE"
   exit 1
fi

read -rp "  Número de cuenta (login)        : " MT_LOGIN
read -rp "  Servidor del broker             : " MT_SERVER
read -rsp "  Contraseña (no se muestra)      : " MT_PASSWORD
echo
read -rp "  Riesgo por operación %  [1.5]   : " RIESGO
RIESGO="${RIESGO:-1.5}"

if [ -z "$MT_LOGIN" ] || [ -z "$MT_PASSWORD" ] || [ -z "$MT_SERVER" ]; then
   echo "  ✗ Login, servidor y contraseña son obligatorios."
   exit 1
fi

#--- Nunca dos contenedores sobre la misma cuenta: se pisarían entre sí
for f in "$CUENTAS"/*.env "$BASE/.env"; do
   [ -f "$f" ] || continue
   [ "$f" = "$ENVFILE" ] && continue
   if grep -q "^MT_LOGIN=$MT_LOGIN$" "$f" 2>/dev/null; then
      OTRO=$(basename "$f" .env)
      echo "  ✗ La cuenta $MT_LOGIN ya está en uso por '$OTRO'."
      echo "    Dos bots sobre la MISMA cuenta se pisan las operaciones. Abortado."
      exit 1
   fi
done

mkdir -p "$CUENTAS"
umask 077
{
  printf 'MT_LOGIN=%s\n'      "$MT_LOGIN"
  printf 'MT_PASSWORD=%s\n'   "$MT_PASSWORD"
  printf 'MT_SERVER=%s\n'     "$MT_SERVER"
  printf 'ATLAS_SYMBOLS=XAUUSD,EURUSD\n'
  printf 'ATLAS_RISK=%s\n'    "$RIESGO"
  printf 'ATLAS_DAILY_LOSS=5.0\n'
  printf 'ATLAS_MAX_DD=50.0\n'
  printf '# Config validada por backtest 2023-2026: Smart Money solo en oro.\n'
  printf 'ATLAS_CRT_SYMBOLS=\n'
  printf 'ATLAS_SMC_SYMBOLS=XAUUSD\n'
  printf 'ATLAS_NY_SYMBOLS=EURUSD\n'
  printf 'ATLAS_LONDON_SYMBOLS=XAUUSD\n'
  printf 'ATLAS_LOCAL_GMT_OFFSET=-3\n'
} > "$ENVFILE"
chmod 600 "$ENVFILE"
unset MT_PASSWORD

echo "  ✓ Configuración guardada en $ENVFILE"
echo "  Arrancando el bot..."

/usr/bin/docker run -d \
  --name "$CONT" \
  --restart unless-stopped \
  --memory 3g \
  --cpus 2 \
  --env-file "$ENVFILE" \
  -v "atlas-logs-$NOMBRE:/mt5/wine/drive_c/Program Files/MetaTrader 5/MQL5/logs" \
  "$IMAGE" >/dev/null

sleep 25
if [ "$(/usr/bin/docker inspect -f '{{.State.Running}}' "$CONT" 2>/dev/null)" = "true" ]; then
   echo "  ✓ Contenedor '$CONT' activo"
else
   echo "  ✗ No arrancó. Ver: /usr/bin/docker logs $CONT"
   exit 1
fi

echo
echo "  Esperá 2-3 minutos y verificá la conexión con:"
echo "    bash ~/atlas-ea/docker/cuentas.sh log $NOMBRE"
echo
echo "  Debe aparecer 'authorized' (cuenta conectada) y las líneas"
echo "  'XAUUSD | SmartMoney' / 'EURUSD | NINGUNA'."
echo "════════════════════════════════════════════════════════════════"
