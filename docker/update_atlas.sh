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

# El .env GANA sobre los defaults compilados del EA. Un .env viejo hace que el
# bot siga operando la cartera anterior aunque el codigo ya traiga otra, y sin
# ningun error: eso fue exactamente lo que paso con EURUSD,XAUUSD. Se compara
# lo que hay en el .env contra lo que compila el EA y se avisa ANTES de tocar
# el bot que esta corriendo.
ea_default() {   # default de un input string de Atlas_EA.mq5
   sed -n "s/^input\s\+string\s\+$1\s*=\s*\"\([^\"]*\)\".*/\1/p" "$REPO/src/Atlas_EA.mq5" | head -1
}
env_valor() { grep -aE "^$1=" "$REPO/.env" | tail -1 | cut -d= -f2-; }
# Normaliza los alias del broker antes de comparar: sin esto, un .env de XM
# (GOLD/SILVER) daria "desincronizado" en cada actualizacion aunque sea la
# MISMA cartera, y un aviso que salta siempre deja de leerse.
ordenar() {
   tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' \
   | sed 's/^GOLD.*$/XAUUSD/; s/^SILVER.*$/XAGUSD/; s/^XAUUSD\..*$/XAUUSD/; s/^XAGUSD\..*$/XAGUSD/' \
   | sort -u | paste -sd, -
}

DESYNC=0
for PAR in "ATLAS_SYMBOLS:InpSymbols" \
           "ATLAS_SMC_SYMBOLS:InpSmcSymbols" \
           "ATLAS_NY_SYMBOLS:InpNewYorkSymbols" \
           "ATLAS_LONDON_SYMBOLS:InpLondonSymbols"; do
   VAR="${PAR%%:*}"; INP="${PAR##*:}"
   grep -qaE "^$VAR=" "$REPO/.env" || continue      # no definida: manda el EA, ok
   V_ENV=$(env_valor  "$VAR" | ordenar)
   V_EA=$(ea_default  "$INP" | ordenar)
   if [ "$V_ENV" != "$V_EA" ]; then
      [ "$DESYNC" = "0" ] && echo && echo "  ⚠ EL .env NO COINCIDE CON EL CODIGO NUEVO:"
      DESYNC=1
      printf '      %-22s .env=%-28s EA=%s\n' "$VAR" "${V_ENV:-(vacio)}" "${V_EA:-(vacio)}"
   fi
done

if [ "$DESYNC" = "1" ]; then
   echo
   echo "    El .env tiene prioridad, asi que el bot va a seguir operando la"
   echo "    cartera de la izquierda aunque actualices el codigo."
   echo
   echo "    Para adoptar la cartera del codigo:  bash $REPO/docker/set_password.sh"
   echo "    Para dejar la del .env a proposito:  seguí (es una configuracion valida)."
   echo
   read -rp "  ¿Actualizar igual con el .env actual? [s/N]: " SEGUIR
   case "${SEGUIR:-N}" in
      s|S|si|SI|Si) echo "  → Sigo con el .env actual." ;;
      *) echo "  ✗ Cancelado. El bot sigue corriendo sin cambios."; exit 1 ;;
   esac
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
echo "  Verificá que aparezca 'ATLAS EA v2.21 iniciado' y una línea por símbolo"
echo "  con su sesión traducida. Seguimiento: docker logs -f $NAME"
