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
echo
echo "  ¿Cómo llama tu broker a los símbolos? (miralo en Observación del mercado)"
echo "    1 = estándar: XAUUSD / XAGUSD / USDJPY   (MetaQuotes, la mayoría)"
echo "    2 = XM:       GOLD / SILVER / USDJPY"
read -rp "  Opción [1]: " BROKER_NAMES
BROKER_NAMES="${BROKER_NAMES:-1}"
if [ "$BROKER_NAMES" = "2" ]; then
   SY_ORO="GOLD"; SY_PLATA="SILVER"
else
   SY_ORO="XAUUSD"; SY_PLATA="XAGUSD"
fi

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
  printf '# Cartera validada por backtest 2023-2026 (+45%%): oro+plata en Londres,\n'
  printf '# USDJPY en NY, los tres SOLO con Smart Money. CRT restaba: apagado.\n'
  printf 'ATLAS_SYMBOLS=%s,USDJPY,%s\n' "$SY_ORO" "$SY_PLATA"
  printf 'ATLAS_RISK=1.5\n'
  printf 'ATLAS_DAILY_LOSS=5.0\n'
  printf 'ATLAS_MAX_DD=50.0\n'
  printf 'ATLAS_CRT_SYMBOLS=\n'
  printf 'ATLAS_SMC_SYMBOLS=%s,USDJPY,%s\n' "$SY_ORO" "$SY_PLATA"
  printf 'ATLAS_NY_SYMBOLS=USDJPY\n'
  printf 'ATLAS_LONDON_SYMBOLS=%s,%s\n' "$SY_ORO" "$SY_PLATA"
  printf 'ATLAS_LOCAL_GMT_OFFSET=-3\n' 
} > "$ENVFILE"
chmod 600 "$ENVFILE"
unset MT_PASSWORD

echo
echo "  ✓ Credenciales guardadas en $ENVFILE (solo tu usuario puede leerlas)"
echo "  ✓ Cuenta $MT_LOGIN en $MT_SERVER"
echo "  ✓ Símbolos: ${SY_ORO},USDJPY,${SY_PLATA} (oro+plata Londres, USDJPY NY, todo SMC)"
echo
echo "  Si tu broker usa sufijos (GOLD., XAUUSD.a...), editá $ENVFILE con los"
echo "  nombres EXACTOS de Observación del mercado: se comparan por texto."
echo
echo "  Listo. Avisale a Claude que ya está — él enciende el bot."
echo "════════════════════════════════════════════════════════════════"
