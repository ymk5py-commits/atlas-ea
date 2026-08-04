#!/bin/bash
# ATLAS EA — mantiene la Mac despierta durante el horario de mercado del bot
# (lunes a viernes, 01:55–14:00 hora de Paraguay = sesión Londres+NY del broker).
# Lo lanza un LaunchAgent: al iniciar sesión, al despertar la Mac dentro del
# horario, y a la 01:55. Fuera de horario sale sin hacer nada.
# La pantalla puede apagarse igual — solo se evita el reposo del SISTEMA.

H=$(date +%H); M=$(date +%M); DOW=$(date +%u)   # 1=lunes .. 7=domingo
[ "$DOW" -ge 6 ] && exit 0                       # finde: no hace falta

NOW=$((10#$H*60 + 10#$M))
START=$((1*60 + 55))                             # 01:55
END=$((14*60))                                   # 14:00

if [ "$NOW" -ge "$START" ] && [ "$NOW" -lt "$END" ]; then
   SECS=$(( (END - NOW) * 60 ))
   echo "[atlas_awake] $(date '+%F %T') manteniendo la Mac despierta ${SECS}s (hasta las 14:00)"
   /usr/bin/caffeinate -i -s -t "$SECS"
fi
exit 0
