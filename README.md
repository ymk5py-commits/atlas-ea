# ATLAS EA — Bot de trading para MetaTrader 5 (oro + plata + USDJPY, por sesión)

Bot de trading intradía con gestión de riesgo estricta: límite de pérdida diaria, kill
switch por drawdown, filtro de noticias y cierre pre-fin de semana.

> 📖 Este archivo explica **cómo usar** el bot. Para tocar el código o el despliegue, leé
> antes [`docs/MANTENIMIENTO.md`](docs/MANTENIMIENTO.md): qué se puede verificar sin
> tener MetaTrader instalado, qué garantiza cada red de seguridad y por qué existe, los
> invariantes que es fácil romper, y qué queda pendiente de validar.

## Configuración actual

Cada instrumento tiene **su propia sesión y sus propias estrategias**:

| Símbolo | Sesión | Estrategias | Por qué |
|---|---|---|---|
| **XAUUSD** (oro) | Londres, **08:00–17:00** hora de Londres | **Smart Money** | +12,2% en solitario, caída máxima 8,8% (84 operaciones) |
| **XAGUSD** (plata) | Londres, **08:00–17:00** hora de Londres | **Smart Money** | El mejor de los tres en solitario: **+21,2% con caída 4,9%** |
| **USDJPY** | Nueva York, **08:00–13:00** hora de NY | **Smart Money** | +6,4% en solitario con caída 9,8% |

**Los tres juntos: +45,0% con caída 12,3% y 229 operaciones** (backtest 2023–2026,
500 USD). Es la cartera vigente y la que trae compilada el EA.

Probados y descartados: **EURUSD** (CRT −40,5%, SMC −7,8%, tendencia −0,4%), **GBPUSD**
(SMC −13,6%) y **USDCHF** (SMC +5,2% pero con caída 16,5% — mala relación).

> Resultados completos de la comparación de motores: ver `docs/ATLAS_EA_Estrategias.pdf`
> y el commit `2e0fc4f`. **CRT quedó apagado en todos los instrumentos por evidencia**
> (restaba en oro y en EURUSD).

Se configura con listas de símbolos, no con interruptores globales. Un símbolo puede
figurar en varias listas de estrategia; para sacarlo de todo, bórralo de `InpSymbols`.

| Estrategia | Input | Default | Cuándo entra |
|---|---|---|---|
| **Smart Money (SMC)** | `InpSmcSymbols` | `XAUUSD,USDJPY,XAGUSD` | Quiebre de estructura (BOS/CHoCH) con desplazamiento, y retroceso a un Order Block / FVG sin mitigar |
| Candle Range Theory | `InpCrtSymbols` | *(vacío — restaba en backtest)* | Una vela de H4 define el rango; la siguiente purga un extremo cazando stops y vuelve adentro; se opera hacia el extremo opuesto, que es el objetivo |
| Tendencia | `InpTrendSymbols` | *(vacío)* | Pullback a la EMA20 de M15 a favor de H1/H4, con RSI(9) recuperando 50 |
| Ruptura asiática | `InpBreakoutSymbols` | *(vacío)* | Cierre M15 fuera del rango 1–8h |
| Reversión M1 | `InpRevSymbols` | *(vacío)* | Fade del impulso: bajada fuerte + RSI(7) en sobreventa → compra (y espejo para venta). Salida por tiempo en 5–10 min |
| Scalping M1 | `InpScalpSymbols` | *(vacío)* | Momentum EMA9/EMA21 + RSI(7), salida en minutos |

Cuando un símbolo lleva más de una estrategia, el orden de prioridad es
**SMC → CRT → estrategia del régimen** (un detector de ADX H1 / compresión de Bollinger
M15 elige entre tendencia y ruptura). Reversión y scalping corren aparte, en vela M1.

> ⚠️ Un símbolo que esté en `InpSymbols` pero en **ninguna** lista de estrategia se
> loguea al arrancar como `NINGUNA (no va a operar)` y además cae en la ventana horaria
> de respaldo. `python3 scripts/check_sources.py` lo detecta antes de compilar.

### Por qué cada estrategia va donde va

**Smart Money en los tres.** SMC es un modelo de continuación: necesita un quiebre de
estructura con desplazamiento y después un retroceso a la zona. Eso pide una sesión que
expanda direccionalmente. Los metales en Londres y el USDJPY en la apertura de Nueva York
tienen ese perfil; el EURUSD en la ventana de Nueva York se mueve en rango con más
frecuencia y por eso ninguna variante le dio ventaja.

**CRT apagado, pero el código queda.** El modelo necesita un rango previo que la sesión
salga a purgar, y con velas-rango de H4 la vela que le toca a cada sesión cae sola donde
debe:

| Sesión | Vela que hace de rango | Qué es |
|---|---|---|
| Londres, al abrir | 01:00–05:00 UTC | La **sesión asiática**, que Londres purga al abrir |
| Nueva York, al abrir | 05:00–09:00 UTC | La **mañana de Londres**, que Nueva York purga al abrir |

Por eso `InpCrtTimeframe` se queda en H4: no es un número elegido a dedo, es el que hace
que el rango coincida con la sesión anterior en ambos casos. (Verificado para brókers en
UTC+2 y UTC+3, en verano y en invierno.) Aun así, en backtest **restó** en los dos
instrumentos donde se probó, así que `InpCrtSymbols` queda vacío.

CRT es la única que fija su propio objetivo (el extremo opuesto del rango) en vez de
dejar la salida al parcial + trailing; el break-even, el cierre parcial y el trailing
siguen funcionando igual sobre esa posición.

## El esquema del bot: escáner → señales → plan → riesgo → 24/7

El bot sigue el pipeline clásico de un trader sistemático. Así se mapea cada módulo
del esquema al código:

| Módulo | Qué hace | Dónde vive |
|---|---|---|
| **1. Escáner de mercado** | Recorre la cartera al cierre de cada M15: régimen (ADX H1 / compresión Bollinger), sesión de cada plaza, spread, noticias de alto impacto | `RegimeDetector`, `SessionFilter`, `NewsFilter` |
| **2. Motor de señales** | Detecta y **puntúa** setups: continuación/reversión (SMC), reversión por purga (CRT), ruptura, pullback, momentum, regresión M1 | `*Strategy.mqh` — `SmcScore()` / `CrtScore()` |
| **3. Planificador** | Cada señal es un plan completo: zona de entrada, objetivo, stop, **nivel de invalidación**, tipo de setup, temporalidad, R:B y **confianza 0–100** | `SSignal` en `AtlasTypes.mqh` |
| **4. Módulo de riesgo** | Cinco checks: tamaño de posición, exposición total, drawdown, **volatilidad**, pérdida diaria → PASA / BLOQUEA | `RiskManager` + `VolatilityOK()` |
| **5. Monitor 24/7** | Contenedor Docker con reinicio automático, health check, log de cada decisión | `docker/`, `Atlas_Health` |

**Qué agregó la v2.10 (el esquema completo):**

- **Confianza por señal.** SMC y CRT puntúan cada setup con sus propios componentes
  (barrido de liquidez, zona refinada con FVG, fuerza del desplazamiento, frescura del
  quiebre; recorrido al objetivo y profundidad de la purga). ALTA ≥ 70 · MEDIA ≥ 45 ·
  BAJA < 45. `InpMinScore` descarta las que no llegan (default **0 = sin filtro**).
- **Check de volatilidad.** ATR M15 contra su promedio de un día: bloquea picos anormales
  (dato, flash crash) y mercados muertos. `InpVolCheck` (default **false**).
- **Plan de trading al celular.** Antes de cada entrada llega un push con el plan entero:
  `PLAN COMPRA XAUUSD | continuacion M15 | zona 2401.20-2403.50 | SL 2398.00 | TP gestion |
  invalida 2401.20 | R:B 1:2.0 | confianza 78 ALTA`. Y al log va la línea de los cinco
  checks de riesgo con sus números.

Los dos gates nuevos **nacen apagados a propósito**: la configuración vigente está
validada por backtest (+45%), y un filtro que suena bien puede restar. Por eso entraron
a la matriz de `server_backtest.sh` (`oro_smc_conf60`, `oro_smc_vol`): se encienden con
`ATLAS_MIN_SCORE` / `ATLAS_VOL_CHECK` en el `.env` **solo si el backtest dice que suman**.

**Lo que el esquema muestra y acá no va, a propósito:** ninguna IA generativa decide
operaciones en vivo (no se puede backtestear y no es reproducible — el modelo ayuda a
construir y analizar, el EA ejecuta reglas); nada de datos *on-chain* (esto es forex y
metales); y no hay filtro por "volumen" porque en forex el volumen real no existe, solo
ticks del bróker, que no miden nada comparable.

## Las ventanas se definen en la hora de cada plaza

El bot **no** usa la hora de tu computadora ni la del bróker para decidir las sesiones:
vos ponés las horas en la hora de cada plaza y él convierte solo. Deduce el huso del
servidor comparando su reloj contra UTC, y le aplica a cada plaza **su propio** horario
de verano.

Eso último importa más de lo que parece: **Estados Unidos y Europa no cambian la hora el
mismo día.** EE.UU. arranca el segundo domingo de marzo y Europa el último; EE.UU.
termina el primer domingo de noviembre y Europa el último de octubre. En 2026 eso deja
**28 días al año en que Londres y Nueva York están a 4 horas y no a 5** (del 8 al 28 de
marzo, y del 25 al 31 de octubre). Un horario fijo en hora del servidor se corre una
hora esos días; este no.

Con las ventanas por defecto, **en Paraguay (UTC-3)** las sesiones caen en:

| Sesión | Época | Hora de Paraguay |
|---|---|---|
| Londres (oro + plata) | Verano Europa | **04:00–13:00** |
| Londres (oro + plata) | Invierno Europa | **05:00–14:00** |
| Nueva York (USDJPY) | Verano EE.UU. | **09:00–14:00** |
| Nueva York (USDJPY) | Invierno EE.UU. | **10:00–15:00** |

O sea: el bot arranca con los metales de madrugada, y de 09 a 13 (verano) tiene los tres
instrumentos activos a la vez. Después de las 14 no opera nada.

Ojo con la sesión de Londres: **arranca de madrugada para vos.** Si preferís operar los
metales solo en la parte que se solapa con Nueva York, subí `InpLonStart` a `13` — eso es
13:00 de Londres, que es la apertura de Nueva York. Y si querés más operaciones en
USDJPY a costa de calidad, `InpNyEnd = 17` devuelve la tarde de Nueva York.

Al arrancar, el bot escribe en la pestaña Expertos **una línea por símbolo** con qué
estrategias corre, en qué ventana, y esa ventana traducida a hora del servidor y a la
tuya. **Verificá esas líneas la primera vez.** Si el huso detectado está mal (pasa si el
reloj del sistema donde corre MT5 está mal configurado), forzalo con
`InpServerGmtOffset` — por ejemplo `2` o `3` para un bróker europeo. El panel del
gráfico muestra la ventana de cada símbolo y si está abierta o cerrada.

El cierre del viernes se recorta desde el **fin** de cada sesión (`InpFridayEntryCutH` y
`InpFridayCloseCutH`), así la regla vale igual en cualquier plaza. Y cada símbolo cierra
en su propio horario: que se acabe la sesión de Londres no toca las posiciones abiertas
en USDJPY.

> ⚠️ **Advertencia:** el trading apalancado puede generar pérdidas. Ningún sistema
> garantiza rentabilidad. Este bot se valida en **backtest** y **cuenta demo** antes de
> considerar dinero real. La decisión de operar en real es exclusivamente tuya.

---

## Paso 1 — Instalar MetaTrader 5 en tu Mac

1. Entrá a **https://www.metatrader5.com/es/download** y descargá la versión para macOS.
2. Abrí el `.dmg` y arrastrá MetaTrader 5 a Aplicaciones. La primera vez, botón derecho
   → Abrir (para saltear la advertencia de app descargada).
3. Al abrir por primera vez, MT5 te ofrece **abrir una cuenta demo** con el servidor
   `MetaQuotes-Demo`. Aceptá y completá:
   - Tipo de cuenta: **Forex Hedged USD**
   - Depósito: **500 USD** · Apalancamiento: **1:100**
4. Guardá el número de login y contraseña que te muestra al final.

**Verificar los símbolos:** en la ventana "Observación del mercado" (⌘M), botón derecho
→ "Símbolos" → buscá `XAUUSD`, `XAGUSD` y `USDJPY` y activalos (doble clic). Si tu broker
llama distinto a los metales (ej. `GOLD` y `SILVER` en XM), anotá los nombres exactos —
se configuran en el bot y **se comparan por texto**.

## Paso 2 — Copiar el bot a MetaTrader

1. En MT5: menú **Archivo → Abrir carpeta de datos**. Se abre una carpeta del Finder.
2. Entrá a `MQL5/Experts/` y creá una carpeta `Atlas`.
3. Copiá **todo el contenido de la carpeta `src/` de este proyecto** adentro de
   `MQL5/Experts/Atlas/`. Tiene que quedar así:

```
MQL5/Experts/Atlas/
├── Atlas_EA.mq5
├── Atlas_SelfTest.mq5
├── Atlas_Diag.mq5            ← diagnóstico (opcional)
├── Atlas_Health.mq5          ← chequeo de salud (opcional)
├── Atlas_PushTest.mq5        ← prueba de notificaciones (opcional)
├── Atlas_Symbols.mq5         ← lista los símbolos del broker (opcional)
├── Atlas_BuscarSimbolos.mq5  ← busca cómo llama tu broker al oro/plata (opcional)
└── include/
    ├── AtlasTypes.mqh
    ├── BreakoutStrategy.mqh
    ├── CrtStrategy.mqh
    ├── Dashboard.mqh
    ├── NewsFilter.mqh
    ├── Notifier.mqh
    ├── RegimeDetector.mqh
    ├── RevStrategy.mqh
    ├── RiskManager.mqh
    ├── ScalpStrategy.mqh
    ├── SessionFilter.mqh
    ├── SmcStrategy.mqh
    ├── TradeManager.mqh
    ├── TrendStrategy.mqh
    └── TVRating.mqh
```

> Lo más simple es copiar **toda** la carpeta `src/`: si falta un solo `.mqh` de
> `include/`, el EA no compila.

## Paso 2b — Verificación previa (opcional pero recomendado)

Antes de compilar podés correr un chequeo estático de las fuentes:

```
python3 scripts/check_sources.py
```

No es un compilador: es una red de seguridad que atrapa los errores que se cuelan
al cambiar una firma y dejar un llamador viejo, o al renombrar un input o una variable
global y que sobreviva una referencia. Verifica balance de llaves, cantidad de
argumentos en cada llamada a método contra la firma real de su clase, y que todo `Inp*`
y `g_*` usado esté declarado. Además cruza el despliegue contra el EA: que ningún símbolo
de `InpSymbols` quede sin estrategia o sin sesión, y que los scripts de Docker no
hardcodeen la cartera. Si dice "Sin hallazgos", igual **falta compilar**.

## Paso 3 — Compilar

1. En MT5: menú **Herramientas → Editor de lenguaje MetaQuotes** (o tecla F4).
   Se abre el MetaEditor.
2. En el panel Navegador del MetaEditor: `Experts/Atlas/Atlas_SelfTest.mq5` → doble clic
   → botón **Compilar** (o F7). Abajo debe decir **"0 errors, 0 warnings"**.
3. Repetí con `Atlas_EA.mq5`.
4. Si aparece algún error, copiá el texto completo del error y pasámelo — lo corrijo.

## Paso 4 — Correr el auto-test

1. Volvé a MT5 y abrí un gráfico de XAUUSD (arrastralo desde Observación del mercado).
2. En el Navegador de MT5 (⌘N): `Scripts` no — está en `Asesores Expertos`... el
   self-test aparece en **Navegador → Asesores Expertos → Atlas → Atlas_SelfTest**
   *(los scripts compilados dentro de Experts aparecen ahí)*. Arrastralo al gráfico.
3. En sus parámetros verificá `InpTestSymbolGold`, `InpTestSymbolSilver` y
   `InpTestSymbolJpy`: tienen que ser los nombres **exactos** de tu bróker (en XM son
   `GOLD` y `SILVER`). El auto-test prueba los mismos tres símbolos que va a operar el bot.
4. Abrí la pestaña **Caja de herramientas → Expertos** y verificá que termine con:
   `ATLAS SELFTEST: ALL PASS`.
   - Si dice `SKIP ... sin precio`: es normal en fin de semana — repetilo con
     mercado abierto (lunes a viernes).
   - Prestá atención a las líneas `INFO ... spread N pts | limite M pts`: si el límite
     da **0**, ese símbolo no puede operar nunca (es un error de clasificación, no una
     decisión). Si el spread supera siempre al límite, subí el input de spread de ese
     instrumento.

## Paso 5 — Activar el bot en demo

1. Abrí un gráfico **XAUUSD** en temporalidad **M15**. Una sola instancia maneja los
   tres símbolos — **no** lo pongas también en los gráficos de plata o USDJPY.
2. Botón **Algo Trading** de la barra superior: debe quedar **verde/activado**.
3. Arrastrá `Atlas_EA` desde el Navegador al gráfico. En la ventana que aparece:
   - Pestaña "Común": tildá **"Permitir Algo Trading"**.
   - Pestaña "Parámetros de entrada": revisá los valores (vienen con los defaults
     correctos). Si tu broker usa otros nombres (`GOLD`, `SILVER`, `XAUUSD.i`…),
     corregilos en `InpSymbols` **y en las listas de estrategia y sesión** con el nombre
     exacto que muestra Observación del mercado: se comparan por texto. Un símbolo que
     quede fuera de las listas no opera.
4. OK. En la esquina superior derecha del gráfico debe aparecer una carita 🙂 (algo
   trading activo) y en el gráfico el **panel ATLAS** con el estado en vivo.
5. **Leé las líneas de arranque en la pestaña Expertos.** Hay una por símbolo con sus
   estrategias y su sesión traducida. Si alguna dice `NINGUNA (no va a operar)`, ese
   símbolo está en la cartera pero sin estrategia asignada.

**Qué esperar:** el bot analiza al cierre de cada vela de 15 minutos y la enorme mayoría
de las veces la decisión correcta es NO operar. Con la configuración actual — tres
símbolos, ventanas de 9 horas y modelos muy selectivos — es normal ver **3 a 6
operaciones por semana entre los tres**, y semanas sin ninguna (el backtest dio 229
operaciones en 3,5 años). No está roto: las líneas `CRT` y `SmartM.` del panel dicen en
qué paso se frenó cada análisis. Todo queda registrado en la pestaña Expertos.

Si querés más frecuencia sin cambiar de estrategia, la palanca más directa es
`InpCrtTimeframe = PERIOD_H1`: con velas-rango de una hora hay unos 9 rangos por sesión
en vez de 2.

## Paso 6 — Notificaciones push en tu celular

1. Instalá la app **MetaTrader 5** (iOS/Android) y entrá con la misma cuenta demo.
2. En la app: Ajustes → Mensajes → ahí aparece tu **MetaQuotes ID** (8 caracteres).
3. En MT5 de la Mac: **MetaTrader 5 → Preferencias → Notificaciones** → tildá
   "Habilitar notificaciones push" y pegá tu MetaQuotes ID → botón "Test".
4. Con eso, cada operación del bot te llega al celular al instante.

## Paso 7 — Backtest (validación con historia real)

1. En MT5: **Ver → Probador de estrategias** (⌘R).
2. Configurar:
   - Asesor Experto: `Atlas\Atlas_EA`
   - Símbolo: **XAUUSD** · Período: **M15**. El probador de MT5 corre **un símbolo por
     vez**: repetí con `XAGUSD` y `USDJPY` para medir cada pata de la cartera
   - Fechas: **2023.01.01 → 2026.07.31**
   - Modelado: **"Cada tick basado en ticks reales"** (la primera vez descarga muchos
     datos — puede tardar)
   - Depósito: **500 USD** · Apalancamiento 1:100
3. Botón **Iniciar**. Al terminar, pestañas "Resultados" y "Gráfico".
4. Los números que importan (criterios de aceptación del diseño):
   - **Factor de beneficio (Profit Factor) ≥ 1.3**
   - **Drawdown máximo ≤ 25%**
   - **≥ 100 operaciones** en el período
   - Ningún mes con pérdida > 15%
5. Corridas A/B: **no hay interruptores globales tipo `InpEnableX`** — cada estrategia se
   prende y se apaga por su lista de símbolos. Para medir qué aporta cada una, vaciá o
   llená la lista correspondiente:

   | Probar | Cómo |
   |---|---|
   | Solo Smart Money en el oro | `InpSymbols=XAUUSD` · `InpSmcSymbols=XAUUSD` · el resto de las listas vacías |
   | Sumar CRT al oro | lo anterior + `InpCrtSymbols=XAUUSD` |
   | Solo CRT | `InpSmcSymbols=` (vacío) · `InpCrtSymbols=XAUUSD` |
   | La cartera entera | los defaults del EA |

   Empezá por los dos modelos estructurales (SMC y CRT): como tienen prioridad, son los
   que más cambian el resultado. En CRT probá además `InpCrtMode` en 0 (en vivo) y 1
   (confirmado): el segundo entra más tarde pero solo después de que la vela de purga
   cerró dentro del rango.

   Acordate de mover también `InpNewYorkSymbols` / `InpLondonSymbols` al cambiar de
   símbolo: si el símbolo no figura en ninguna, opera con la ventana de respaldo en hora
   del servidor y los resultados no son comparables.

### Límites de spread

Se configuran en la **unidad natural de cada instrumento**, no en "points":

| Instrumento | Input | Unidad | Default |
|---|---|---|---|
| Pares (incluidos los JPY) | `InpMaxSpreadForex` | pips | 2.0 |
| Oro | `InpMaxSpreadGold` | centavos de dólar | 50 (= 0.50 USD) |
| **Plata / platino / paladio** | `InpMaxSpreadMetal` | centavos de dólar | 5.0 (= 0.05 USD) |
| Índices | `InpMaxSpreadIndex` | puntos del índice | 5.0 |

El motivo: un "point" no es una cantidad fija, depende de con cuántos decimales cotice
cada bróker. El oro se cotiza con 2 o 3 decimales según el bróker, y los pares con 4 o
5. Antes el límite del oro eran 400 points, que son **0.40 USD en un bróker de 3
decimales pero 4.00 USD en uno de 2** — diez veces más flojo, sin ningún aviso, dejando
operar con spreads pésimos. Lo mismo pasaba con los 20 points del EURUSD (2 pips contra
20 pips). Ahora ponés la tolerancia real y el bot la convierte a los points de tu
bróker.

La plata tiene su **propio** input y no hereda el del oro ni el de forex: cotiza en
dólares como el oro pero vale ~30 USD en vez de ~2600, y metida en la categoría forex el
límite en pips le daba **0 points**, con lo cual XAGUSD no podía operar nunca y sin un
solo mensaje. Los pares JPY tenían el mismo problema por otro camino (su pip es 0.01, no
0.0001), resuelto convirtiendo por cantidad de dígitos.

> ⚠️ **El default de la plata (5 centavos) es ajustado.** Muchos brókers retail cotizan
> XAGUSD con 3–6 centavos de spread. Si en el log ves que la plata queda seguido por
> encima del límite, subí `InpMaxSpreadMetal`. El auto-test imprime el margen exacto.

Al quedar operativo cada símbolo, el bot escribe en la pestaña Expertos su spread actual,
el límite ya convertido y con cuántos decimales cotiza. **Un límite de 0 points siempre
es un error de clasificación del símbolo, nunca una decisión.**

### Noticias

El filtro vigila el calendario de **USD, EUR y GBP** (se agregó GBP porque el oro ahora
opera la sesión de Londres, donde los datos del Reino Unido son la principal fuente de
volatilidad programada) y pausa las entradas ±30 minutos alrededor de **cualquier**
evento de alto impacto.

Antes filtraba por una lista de palabras (`CPI`, `NFP`, `GDP`, `PCE`…). El problema es
que el calendario de MT5 escribe los nombres completos —"Consumer Price Index", "Gross
Domestic Product"— así que varias de esas abreviaturas **no matcheaban nada** y el filtro
dejaba pasar justo los datos más grandes. Y si el terminal está en español los nombres
cambian de nuevo. Bloquear todo evento de alto impacto cuesta poco (son pocos por
semana) y no depende de cómo estén escritos.

> **Nota:** el filtro de noticias no funciona en el backtest (limitación de MT5 — el
> calendario económico no está disponible en el probador). En demo/real sí funciona.
> Por eso los resultados de demo pueden ser levemente mejores que el backtest.

## Fases de validación (no saltear)

| Fase | Qué | Criterio para avanzar |
|---|---|---|
| 1. Backtest | 2023–2026, ticks reales | PF ≥ 1.3 · DD ≤ 25% · muestra suficiente de ops |
| 2. Demo | 2–4 semanas en vivo | P&L positivo, cero violaciones de riesgo |
| 3. Real | Decisión tuya | Empezar con riesgo 1% las primeras 2 semanas |

## Parámetros principales (pestaña "Parámetros de entrada")

> **No existen inputs `InpEnableX`.** Cada estrategia se prende y se apaga poniendo (o
> sacando) el símbolo de su lista.

### Cartera y estrategias

| Parámetro | Default | Qué hace |
|---|---|---|
| `InpSymbols` | `XAUUSD,USDJPY,XAGUSD` | Los símbolos que carga el bot |
| `InpSmcSymbols` | `XAUUSD,USDJPY,XAGUSD` | Símbolos con Smart Money (prioridad sobre las demás) |
| `InpCrtSymbols` | *(vacío)* | Símbolos con Candle Range Theory |
| `InpTrendSymbols` | *(vacío)* | Símbolos con tendencia (pullback a EMA20) |
| `InpBreakoutSymbols` | *(vacío)* | Símbolos con ruptura asiática |
| `InpRevSymbols` | *(vacío)* | Símbolos con reversión M1 (fade del impulso) |
| `InpScalpSymbols` | *(vacío)* | Símbolos con scalping M1 (momentum) |

### Riesgo

| Parámetro | Default | Qué hace |
|---|---|---|
| `InpRiskPct` | 1.5 | % del capital arriesgado por operación |
| `InpDailyLossPct` | 5.0 | Pérdida diaria que frena al bot hasta mañana |
| `InpMaxDrawdownPct` | 30.0 | Caída desde el pico que apaga el bot (kill switch) |
| `InpMaxTotalRiskPct` | 3.0 | Riesgo abierto total máximo entre todas las posiciones |
| `InpMaxTradesPerDay` | 4 | Máximo de operaciones por día **por símbolo** |
| `InpMaxPositions` | 2 | Máximo de posiciones simultáneas |
| `InpResetKillSwitch` | false | Poner `true` UNA vez para reactivar tras un kill switch |

### Smart Money

| Parámetro | Default | Qué hace |
|---|---|---|
| `InpSmcRequireHtf` | true | Exigir que la estructura de H1 acompañe la de M15 |
| `InpSmcRequireSweep` | false | Exigir barrido de liquidez previo — mucho más selectivo |
| `InpSmcRequireDisc` | true | Comprar solo en descuento, vender solo en premium |
| `InpSmcTvFilter` | 0 | Confluencia del rating TV para SMC: 0 ninguna · 1 solo H1 · 2 M15+H1 |

### Candle Range Theory (apagada por defecto)

| Parámetro | Default | Qué hace |
|---|---|---|
| `InpCrtTimeframe` | H4 | Vela que define el rango (H1, H4, D1…) |
| `InpCrtMode` | 0 | 0 = en vivo (purga en la vela en curso) · 1 = confirmado (la purga ya cerró) |
| `InpCrtMaxPurgePct` | 40.0 | Purga máxima en % del rango; más profundo se considera ruptura real |
| `InpCrtMinRR` | 1.5 | Recorrido mínimo al extremo opuesto para que el setup valga |
| `InpCrtFollowRegime` | true | No operar la purga a contramano de la tendencia de H1 |

### Reversión M1 (apagada por defecto)

| Parámetro | Default | Qué hace |
|---|---|---|
| `InpRevImpulseAtr` | 2.0 | Impulso mínimo del tramo para considerarlo extremo (× ATR M1) |
| `InpRevRsiLow` / `InpRevRsiHigh` | 25 / 75 | RSI(7) que confirma sobreventa / sobrecompra |
| `InpRevTargetPct` | 50.0 | % del tramo que se busca recuperar (el objetivo) |
| `InpRevHoldMin` | 8 | Cierre por tiempo, en minutos (el método manual usa 5–10) |
| `InpRevRiskPct` | 1.0 | Riesgo por operación de reversión |
| `InpRevMaxPerDay` | 15 | Máximo de reversiones por día por símbolo |

### Sesiones y horarios

| Parámetro | Default | Qué hace |
|---|---|---|
| `InpNewYorkSymbols` | `USDJPY` | Símbolos que operan en la sesión de Nueva York |
| `InpNyStart/End` | 8 / 13 | Ventana de Nueva York, en hora de Nueva York |
| `InpLondonSymbols` | `XAUUSD,XAGUSD` | Símbolos que operan en la sesión de Londres |
| `InpLonStart/End` | 8 / 17 | Ventana de Londres, en hora de Londres |
| `InpSrvStart/End` | 8 / 20 | Ventana de **respaldo** (hora del servidor) para símbolos sin sesión |
| `InpFridayEntryCutH` | 2 | Viernes: sin entradas las últimas N horas de cada sesión |
| `InpFridayCloseCutH` | 1 | Viernes: cerrar todo N horas antes del fin de cada sesión |
| `InpServerGmtOffset` | 99 | Huso del servidor; 99 = detectar solo. Forzalo si la detección falla |
| `InpLocalGmtOffset` | -3 | Tu huso, solo para mostrar las horas en el panel (Paraguay = -3) |

### Spread y noticias

| Parámetro | Default | Qué hace |
|---|---|---|
| `InpMaxSpreadForex` | 2.0 | Spread máximo en pares, **en pips** (cubre también los JPY) |
| `InpMaxSpreadGold` | 50.0 | Spread máximo en oro, **en centavos** (50 = 0.50 USD) |
| `InpMaxSpreadMetal` | 5.0 | Spread máximo en plata/platino/paladio, **en centavos** |
| `InpMaxSpreadIndex` | 5.0 | Spread máximo en índices, **en puntos del índice** |
| `InpNewsCurrencies` | `USD,EUR,GBP` | Monedas cuyo calendario económico se vigila |
| `InpNewsKeywords` | *(vacío)* | Vacío = pausar ante cualquier evento de alto impacto |

## Correr el bot en un servidor (Docker)

Tres comandos, en este orden:

```bash
bash ~/atlas-ea/docker/set_password.sh
```

Escribe `~/atlas-ea/.env` con la cuenta **y la cartera**. Te pregunta cómo llama tu
bróker a los metales (estándar `XAUUSD/XAGUSD` o XM `GOLD/SILVER`). Se corre **una sola
vez**.

```bash
bash ~/atlas-ea/docker/start_atlas.sh
```

Enciende el bot 24/5 leyendo ese `.env`. No vuelve a preguntar símbolos: la única fuente
de verdad es el `.env`.

```bash
bash ~/atlas-ea/docker/update_atlas.sh
```

Actualiza: hace `git pull`, corre el verificador estático, **recompila todas las fuentes
dentro del build de la imagen** (el build falla si MetaEditor reporta un error en
cualquiera de ellas — en ese caso el bot viejo sigue corriendo intacto) y relanza el
contenedor con el mismo `.env`.

Al final tiene que aparecer en el log `ATLAS EA v2.00 iniciado` y **una línea por
símbolo** con sus estrategias y su sesión traducida a hora del servidor y a la tuya.
Leelas: es el único lugar donde se ve qué está corriendo de verdad.

### De dónde salen la cartera y las estrategias

La fuente de verdad son los **defaults compilados en `src/Atlas_EA.mq5`**. El
`entrypoint.sh` escribe una línea `Inp…=` **solo** si su variable de entorno está
definida en el `.env`; si no la definís, manda el default del EA.

| Variable del `.env` | Input que sobreescribe |
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

> Antes el `entrypoint.sh` traía la cartera hardcodeada y pisaba al EA en silencio: el
> servidor corría `EURUSD,XAUUSD` con Smart Money solo en el oro mientras el EA ya traía
> compilada la cartera validada, la plata nunca se cargaba y EURUSD entraba sin ninguna
> estrategia. Ahora `scripts/check_sources.py` falla si un script vuelve a hardcodearla.

Para el backtest A/B en el servidor (contenedor descartable, no toca el bot vivo):

```bash
docker run --rm --env-file ~/atlas-ea/.env -v ~/atlas-ea/scripts/server_backtest.sh:/bt.sh atlas-ea:2.0 bash /bt.sh
```

En el tester el EA asume bróker EET (UTC+2/+3 europeo), la convención de
MetaQuotes-Demo; para otro huso, fijar `InpServerGmtOffset` en el script.

## Problemas frecuentes

- **"simbolo no disponible"** al iniciar → el broker usa otro nombre (GOLD, SILVER,
  XAUUSD.a…): corregir `InpSymbols` y las listas de estrategia/sesión, que comparan por
  texto exacto. El script `Atlas_BuscarSimbolos` te dice cómo los llama tu bróker.
- **Un símbolo dice "NINGUNA (no va a operar)"** en el log de arranque → está en
  `InpSymbols` pero en ninguna lista de estrategia. Agregalo a la que corresponda.
  En el servidor, mirá también que el `.env` no tenga una cartera vieja: si define
  `ATLAS_SYMBOLS` sin definir las listas de estrategia, el entrypoint te avisa al
  arrancar.
- **La plata (o el USDJPY) no opera nunca** → mirá la línea de spread del arranque:
  `XAGUSD: spread N points (limite M, D digitos)`. Si el límite da **0**, el símbolo está
  mal clasificado. Si el límite es chico pero real, subí `InpMaxSpreadMetal`.
- **No opera nunca** → revisar: Algo Trading activado (botón verde), que la sesión de ese
  símbolo esté abierta (cada símbolo tiene su línea `Sesion` en el panel, con la hora
  tuya y si está ABIERTA), y la pestaña Expertos para ver los motivos ("fuera de sesion",
  "rating TV no confirma", etc. — el bot explica cada decisión).
- **Smart Money no dispara nunca** → mirá la línea `SmartM.` del panel: dice en qué paso
  se frena ("esperando retroceso a la zona", "zona ya mitigada", "H1 no acompana",
  "zona fuera de descuento"). Es un modelo selectivo: pasar semanas sin setup en un
  símbolo es normal. Para aflojarlo, empezá por `InpSmcRequireDisc = false`; para
  apretarlo, `InpSmcRequireSweep = true`.
- **CRT no dispara nunca** → misma idea con la línea `CRT` del panel ("esperando la purga
  de un extremo", "purga demasiado profunda", "rango sin recorrido", "recorrido
  insuficiente"). Con vela de H4 hay como mucho un setup cada 4 horas y la mayoría se
  descarta. Para aflojarlo: `InpCrtMinRR = 1.0` o `InpCrtFollowRegime = false`; para
  apretarlo, `InpCrtMode = 1`.
- **La carita del gráfico está gris/tachada** → falta tildar "Permitir Algo Trading" en
  las propiedades del EA (F7 sobre el gráfico).
- **El backtest no descarga ticks** → probar primero con modelado "1 minuto OHLC" para
  una pasada rápida, y dejar la de ticks reales corriendo con tiempo.
- **Mac se duerme** → Ajustes del Sistema → Pantalla y Energía: evitar reposo con MT5
  abierto durante la sesión de trading (o el bot se pausa con la Mac).
