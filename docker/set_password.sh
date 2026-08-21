#!/bin/bash
#===============================================================================
# ATLAS EA — Guardar las credenciales de la cuenta en el servidor.
#
# Este es el ÚNICO paso que hace el dueño de la cuenta. No usa Docker (así no
# depende de permisos de la sesión gráfica): solo escribe un archivo protegido
# con la cuenta. La contraseña se tipea acá, en el servidor.
#
# Uso:  bash ~/atlas-ea/docker/set_password.sh
#===============================================================================
set -uo pipefail

ENVFILE="$HOME/atlas-ea/.env"

echo "════════════════════════════════════════════════════════════════"
echo "  ATLAS EA — credenciales de la cuenta MetaTrader"
echo "════════════════════════════════════════════════════════════════"
read -rp "  Número de cuenta (login)    : " MT_LOGIN
read -rp "  Servidor [MetaQuotes-Demo]  : " MT_SERVER
MT_SERVER="${MT_SERVER:-MetaQuotes-Demo}"
read -rsp "  Contraseña (no se muestra)  : " MT_PASSWORD
echo

if [ -z "$MT_LOGIN" ] || [ -z "$MT_PASSWORD" ]; then
   echo "  ✗ Login y contraseña son obligatorios."
   exit 1
fi

mkdir -p "$(dirname "$ENVFILE")"
umask 077
{
  printf 'MT_LOGIN=%s\n'      "$MT_LOGIN"
  printf 'MT_PASSWORD=%s\n'   "$MT_PASSWORD"
  printf 'MT_SERVER=%s\n'     "$MT_SERVER"
  printf 'ATLAS_SYMBOLS=XAUUSD,EURUSD\n'
  printf 'ATLAS_RISK=1.5\n'
  printf 'ATLAS_DAILY_LOSS=5.0\n'
  printf 'ATLAS_MAX_DD=50.0\n'
} > "$ENVFILE"
chmod 600 "$ENVFILE"
unset MT_PASSWORD

echo
echo "  ✓ Credenciales guardadas en $ENVFILE (solo tu usuario puede leerlas)"
echo "  ✓ Cuenta $MT_LOGIN en $MT_SERVER"
echo
echo "  Listo. Avisale a Claude que ya está — él enciende el bot."
echo "════════════════════════════════════════════════════════════════"
