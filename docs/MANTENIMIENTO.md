# Mantenimiento y verificación de ATLAS EA

Este documento es para quien retome el proyecto sin contexto previo: qué se puede
verificar **sin tener MetaTrader instalado**, qué garantiza cada red de seguridad y por
qué existe, y qué queda pendiente de validar.

El `README.md` explica **cómo usar** el bot. Este archivo explica **cómo no romperlo**.

---

## 1. Modelo de configuración: quién gana

Hay tres lugares donde se puede definir qué opera el bot, y no todos pesan igual:

```
src/Atlas_EA.mq5          ← los defaults compilados. LA FUENTE DE VERDAD.
        ↓ (los pisa, si está definida la variable)
~/atlas-ea/.env           ← lo que escriben set_password.sh / agregar_cuenta.sh
        ↓
MQL5/Presets/atlas_params.set   ← lo genera docker/entrypoint.sh en cada arranque
```

**Regla:** `entrypoint.sh` escribe una línea `Inp*=` **solo si su variable de entorno
está definida**. Si no lo está, la línea no existe y manda el default del EA.

Se distingue *no definida* de *definida vacía*: `ATLAS_CRT_SYMBOLS=` es un override
explícito que significa "ninguno", y es distinto de no poner la variable. En bash eso es
`${!var+x}` (definida) y no `${!var:+x}` (definida y no vacía).

### Por qué es así

Antes los scripts de Docker traían la cartera hardcodeada. Como el `.set` gana sobre el
EA, el servidor terminó operando `EURUSD,XAUUSD` con Smart Money solo en el oro, mientras
el EA ya traía compilada la cartera validada por backtest (`XAUUSD,USDJPY,XAGUSD`, +45%):

- **la plata nunca se cargaba** — y es el mejor instrumento en solitario (+21,2%, DD 4,9%);
- **USDJPY tampoco**;
- **EURUSD entraba sin ninguna estrategia** → el EA lo logueaba como `NINGUNA (no va a operar)`.

Estaba en tres scripts a la vez (`entrypoint.sh`, `start_atlas.sh`, `agregar_cuenta.sh`)
y nadie lo notó porque **el bot arrancaba bien y no daba ningún error**. Sólo se veía
leyendo las líneas de arranque una por una.

> **No vuelvas a hardcodear símbolos en los scripts de Docker.** Si necesitás otra
> cartera, cambiala en `src/Atlas_EA.mq5` (y volvé a correr el backtest), o pasala por
> el `.env`. El verificador falla si un script la fija a mano.

### Variables del `.env` y qué input pisa cada una

| Variable | Input |
|---|---|
| `ATLAS_SYMBOLS` | `InpSymbols` |
| `ATLAS_SMC_SYMBOLS` | `InpSmcSymbols` |
| `ATLAS_CRT_SYMBOLS` | `InpCrtSymbols` |
| `ATLAS_TREND_SYMBOLS` | `InpTrendSymbols` |
| `ATLAS_BREAKOUT_SYMBOLS` | `InpBreakoutSymbols` |
| `ATLAS_REV_SYMBOLS` | `InpRevSymbols` |
| `ATLAS_M1_SCALP_SYMBOLS` | `InpScalpSymbols` |
| `ATLAS_NY_SYMBOLS` | `InpNewYorkSymbols` |
| `ATLAS_LONDON_SYMBOLS` | `InpLondonSymbols` |
| `ATLAS_RISK` · `ATLAS_DAILY_LOSS` · `ATLAS_MAX_DD` | riesgo, límite diario, kill switch |

---

## 2. Verificar sin MetaTrader (solo Docker)

No hace falta ni Mac ni MT5 instalado. La imagen del repo trae MetaEditor bajo Wine.

### 2.1 Verificador estático (2 segundos, sin Docker)

```bash
python3 scripts/check_sources.py
```

Ocho bloques. Los cinco primeros son de código (balance de llaves, aridad de llamadas
contra la firma real de cada clase, `Inp*` y `g_*` sin declarar, y que los scripts no
escriban inputs inexistentes). Los tres últimos son de configuración y están explicados
en la sección 3.

Sale con código 1 si encuentra algo. **No es un compilador**: siempre falta compilar.

### 2.2 Compilación real de todas las fuentes

```bash
docker build -f docker/Dockerfile -t atlas-ea:verify .
```

El build **compila las 7 fuentes `.mq5` con MetaEditor y falla si alguna no compila**.
Es el mismo gate que usa `docker/update_atlas.sh`, así que un error de compilación nunca
llega a reemplazar al bot que está corriendo.

Para recompilar el `src/` de trabajo sin rebuildear la imagen entera:

```bash
docker run --rm --entrypoint bash -v "$PWD/src:/fuente:ro" atlas-ea:verify -c '
rm -rf /mt5/term/MQL5/Experts/Atlas; mkdir -p /mt5/term/MQL5/Experts/Atlas
cp -r /fuente/. /mt5/term/MQL5/Experts/Atlas/
for SRC in /mt5/term/MQL5/Experts/Atlas/*.mq5; do
  N="$(basename "$SRC" .mq5)"; rm -f /mt5/term/c.log
  xvfb-run -a wine "C:\\mt5\\metaeditor64.exe" "/compile:C:\\mt5\\MQL5\\Experts\\Atlas\\${N}.mq5" "/log:C:\\mt5\\c.log" >/dev/null 2>&1 || true
  printf "  %-22s %s\n" "$N" "$(iconv -f UTF-16LE -t UTF-8 /mt5/term/c.log 2>/dev/null | grep -a "Result:" | tail -1)"
done'
```

Tiene que dar `0 errors, 0 warnings` en las siete.

### 2.3 Qué configuración se despliega de verdad

Esto es lo que **no** se ve mirando el código, y es donde estuvo el bug. Corre el
`entrypoint.sh` hasta justo antes de arrancar MetaTrader y muestra el `.set` resultante:

```bash
docker run --rm --entrypoint bash -e MT_LOGIN=000 atlas-ea:verify -c '
sed -n "1,/^chmod 600/p" /entrypoint.sh > /tmp/c.sh; bash /tmp/c.sh
cat "${WINEPREFIX}/drive_c/Program Files/MetaTrader 5/MQL5/Presets/atlas_params.set"'
```

Sin `.env`, ahí **no debe aparecer ninguna línea de símbolos** (mandan los defaults del
EA). Con un `.env` real, agregá `--env-file ~/atlas-ea/.env` y comprobá que lo que sale
es la cartera que esperás.

### 2.4 Sintaxis de los scripts

```bash
for f in docker/*.sh scripts/*.sh; do bash -n "$f" && echo "OK $f"; done
```

---

## 3. Las tres guardas de configuración (no las quites)

`check_sources.py` tiene tres bloques que no verifican código sino coherencia entre el
EA y el despliegue. Cada uno existe por un bug real que llegó a producción.

| Bloque | Qué impide |
|---|---|
| `cartera del EA: estrategia y sesion` | Que un símbolo quede en `InpSymbols` sin estrategia (no operaría) o sin sesión (caería en la ventana de respaldo del servidor). También al revés: que una lista nombre un símbolo que no se carga. |
| `despliegue sin cartera hardcodeada` | Que `entrypoint.sh` vuelva a fijar símbolos a mano en vez de leerlos del entorno. |
| `cartera del .env vs la del EA` | Que `set_password.sh` o `agregar_cuenta.sh` escriban una cartera distinta a la que compila el EA. Compara la rama de nombres estándar (`XAUUSD`/`XAGUSD`). |

Las tres se probaron reintroduciendo la regresión exacta en una copia descartable del
repo. Si tocás alguna, **verificá que siga fallando** cuando corresponde:

```bash
cp -r . /tmp/regr && rm -rf /tmp/regr/.git
# meté a mano la desincronización que quieras probar en /tmp/regr
python3 /tmp/regr/scripts/check_sources.py    # tiene que salir con código 1
```

Una guarda que no sabés que falla cuando debe, no es una guarda.

---

## 4. El bug de los límites de spread (leelo antes de tocar `SessionFilter`)

Un límite de spread que convierte a **0 points** hace que `SpreadOK()` devuelva `false`
para siempre, y el símbolo no opera nunca **sin un solo mensaje**. Pasó dos veces:

- **La plata.** Clasificada como forex, el límite en pips (`2.0 × 0.0001`) le daba 0
  points. XAGUSD tiene ahora su propio `InpMaxSpreadMetal`, en centavos.
- **Los pares JPY.** Su pip es `0.01`, no `0.0001`. Convertir multiplicando por `0.0001`
  dejaba a USDJPY en 0 points. Ahora se convierte por **cantidad de dígitos** de la
  cotización (5 y 3 dígitos cotizan en décimas de pip).

Reglas que salen de eso:

1. **Un límite de 0 points es siempre un error de clasificación, nunca una decisión.**
   `Atlas_SelfTest` lo verifica contra el bróker real (`TestSpreadGateVivo`).
2. Un instrumento nuevo que no sea par, oro, metal o índice **no tiene categoría** y va a
   caer en forex. Agregale la suya antes de sumarlo a la cartera.
3. `InpMaxSpreadMetal = 5.0` (5 centavos) es **ajustado**: muchos brókers retail cotizan
   XAGUSD con 3–6 centavos. El auto-test imprime el margen exacto; subilo si hace falta.

---

## 5. Invariantes del código que es fácil romper

- **Toda señal define el lado del stop, no solo su ancho.** Validar `entry - sl > maxSl`
  no alcanza: si el precio se movió entre el cierre de la vela y la cotización actual,
  esa resta puede dar negativo, pasar el filtro y mandar una orden con el SL del lado
  equivocado. `SmcStrategy`, `CrtStrategy` y `RevStrategy` tienen la guarda; y
  `TradeManager` la repite en `Open()` y en `OpenScalp()` como última línea.
- **Un TP calculado sobre el cierre de una vela puede quedar detrás de la entrada.**
  `OpenScalp()` lo valida y cae al objetivo en R si no sirve.
- **Cada estrategia que corra en M1 necesita su propio tracker de vela.** Scalping y
  reversión comparten timeframe: con un solo `g_lastM1`, la primera consume la vela y la
  segunda no se evalúa nunca, en silencio. Hay `g_lastM1` y `g_lastM1Rev`.
- **`Init()` es idempotente en los módulos con handles de indicador.** `TryInitSymbol`
  reintenta cada 20 s hasta que el terminal conecta, así que `Init()` puede correr muchas
  veces. Cada clase tiene constructor + `Invalidate()`, `Release()` invalida después de
  liberar, e `Init()` arranca llamando a `Release()`. Ojo: un objeto recién creado tiene
  los miembros en **0**, y 0 **no** es `INVALID_HANDLE` (`-1`).
- **El filtro de noticias no existe en el Strategy Tester.** Los resultados de demo
  pueden ser mejores que los del backtest por eso.
- **En el tester, `TimeGMT()` devuelve la hora simulada del servidor.** Por eso
  `ServerOffsetSec()` asume convención EET (UTC+2/+3 europeo) cuando corre en el
  probador. Para otro bróker, fijar `InpServerGmtOffset` a mano en el script.

---

## 6. Antes de dar por buena una versión

| Paso | Comando | Criterio |
|---|---|---|
| 1 | `python3 scripts/check_sources.py` | Sin hallazgos |
| 2 | `docker build -f docker/Dockerfile -t atlas-ea:verify .` | Las 7 fuentes en `0 errors, 0 warnings` |
| 3 | Ver §2.3 | El `.set` desplegado es la cartera que esperás |
| 4 | `Atlas_SelfTest` en MT5, mercado abierto | `ATLAS SELFTEST: ALL PASS` |
| 5 | Backtest 2023–2026, ticks reales | PF ≥ 1.3 · DD ≤ 25% · muestra suficiente |
| 6 | Demo 2–4 semanas | P&L positivo, cero violaciones de riesgo |

Y al arrancar, **siempre**: leer las líneas por símbolo del log. Es el único lugar donde
se ve qué está corriendo de verdad.

---

## 7. Pendiente / conocido

- [ ] **La cartera de tres instrumentos no operó nunca en vivo.** Los +45% son backtest.
      La plata en particular nunca llegó a cargarse en producción por el bug de la §1.
      Falta la fase de demo antes de considerarla validada.
- [ ] **`InpMaxSpreadMetal = 5.0` sin ajustar contra un bróker real.** Ver §4.3.
- [ ] **El `.env` de un servidor ya instalado no se actualiza solo.** Si trae la cartera
      vieja, gana sobre el EA: hay que volver a correr `set_password.sh`.
- [ ] **Reversión M1 y scalping están apagados** (`InpRevSymbols` / `InpScalpSymbols`
      vacíos). El código está y compila, pero sin backtest que respalde encenderlos.
- [ ] **CRT apagado por evidencia**, no por estar roto. Restaba en oro y en EURUSD.
- [ ] `scripts/server_backtest.sh` fija `InpNewYorkSymbols=EURUSD` /
      `InpLondonSymbols=XAUUSD`: sirve para las 4 pasadas viejas, pero no para medir la
      cartera actual. Los scripts `_ampliado` y `_reversion` sí parametrizan la sesión.
