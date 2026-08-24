# ATLAS EA — Bot de trading para MetaTrader 5 (EURUSD + oro, por sesión)

Bot de trading intradía con gestión de riesgo estricta: límite de pérdida diaria, kill
switch por drawdown, filtro de noticias y cierre pre-fin de semana.

## Configuración actual

Cada instrumento tiene **su propia sesión y sus propias estrategias**:

| Símbolo | Sesión | Estrategias | Por qué |
|---|---|---|---|
| **EURUSD** | Nueva York, **08:00–13:00** hora de NY | CRT | La ventana termina cuando cierra Londres: el EURUSD tiene recorrido mientras las dos plazas se solapan, y después se vuelve chato |
| **XAUUSD** (oro) | Londres, **08:00–17:00** hora de Londres | CRT + Smart Money | Cubre la mañana de Londres (la franja más volátil del oro) y se extiende hasta el final del solape con Nueva York |

Se configura con listas de símbolos, no con interruptores globales. Un símbolo puede
figurar en varias listas de estrategia; para sacarlo de todo, bórralo de `InpSymbols`.

| Estrategia | Input | Default | Cuándo entra |
|---|---|---|---|
| **Candle Range Theory** | `InpCrtSymbols` | `EURUSD,XAUUSD` | Una vela de H4 define el rango; la siguiente purga un extremo cazando stops y vuelve adentro; se opera hacia el extremo opuesto, que es el objetivo |
| **Smart Money (SMC)** | `InpSmcSymbols` | `XAUUSD` | Quiebre de estructura (BOS/CHoCH) con desplazamiento, y retroceso a un Order Block / FVG sin mitigar |
| Tendencia | `InpTrendSymbols` | *(vacío)* | Pullback a la EMA20 de M15 a favor de H1/H4, con RSI(9) recuperando 50 |
| Ruptura asiática | `InpBreakoutSymbols` | *(vacío)* | Cierre M15 fuera del rango 1–8h |
| Scalping M1 | `InpScalpSymbols` | *(vacío)* | Momentum EMA9/EMA21 + RSI(7), salida en minutos |

Cuando un símbolo lleva más de una estrategia, el orden de prioridad es
**SMC → CRT → estrategia del régimen** (un detector de ADX H1 / compresión de Bollinger
M15 elige entre tendencia y ruptura).

### Por qué cada estrategia va donde va

**CRT en las dos.** El modelo necesita un rango previo que la sesión salga a purgar, y
eso es exactamente lo que hace la apertura de cada plaza. Con velas-rango de H4, la vela
que le toca a cada sesión cae sola donde debe:

| Sesión | Vela que hace de rango | Qué es |
|---|---|---|
| Londres, al abrir | 01:00–05:00 UTC | La **sesión asiática**, que Londres purga al abrir |
| Nueva York, al abrir | 05:00–09:00 UTC | La **mañana de Londres**, que Nueva York purga al abrir |

Por eso `InpCrtTimeframe` se queda en H4: no es un número elegido a dedo, es el que hace
que el rango coincida con la sesión anterior en ambos casos. (Verificado para brókers en
UTC+2 y UTC+3, en verano y en invierno.)

**Smart Money solo en el oro.** SMC es un modelo de continuación: necesita un quiebre de
estructura con desplazamiento y después un retroceso a la zona. Eso pide una sesión que
expanda direccionalmente, que es el perfil de Londres y del oro. El EURUSD en la ventana
de Nueva York se mueve en rango con más frecuencia, que es terreno de CRT.

CRT es la única que fija su propio objetivo (el extremo opuesto del rango) en vez de
dejar la salida al parcial + trailing; el break-even, el cierre parcial y el trailing
siguen funcionando igual sobre esa posición.

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
| Londres (oro) | Verano Europa | **04:00–13:00** |
| Londres (oro) | Invierno Europa | **05:00–14:00** |
| Nueva York (EURUSD) | Verano EE.UU. | **09:00–14:00** |
| Nueva York (EURUSD) | Invierno EE.UU. | **10:00–15:00** |

O sea: el bot arranca con el oro de madrugada, y de 09 a 13 (verano) tiene los dos
instrumentos activos a la vez. Después de las 14 no opera nada.

Ojo con la sesión de Londres: **arranca de madrugada para vos.** Si preferís operar el
oro solo en la parte que se solapa con Nueva York, subí `InpLonStart` a `13` — eso es
13:00 de Londres, que es la apertura de Nueva York. Y si querés más operaciones en
EURUSD a costa de calidad, `InpNyEnd = 17` devuelve la tarde de Nueva York.

Al arrancar, el bot escribe en la pestaña Expertos **una línea por símbolo** con qué
estrategias corre, en qué ventana, y esa ventana traducida a hora del servidor y a la
tuya. **Verificá esas líneas la primera vez.** Si el huso detectado está mal (pasa si el
reloj del sistema donde corre MT5 está mal configurado), forzalo con
`InpServerGmtOffset` — por ejemplo `2` o `3` para un bróker europeo. El panel del
gráfico muestra la ventana de cada símbolo y si está abierta o cerrada.

El cierre del viernes se recorta desde el **fin** de cada sesión (`InpFridayEntryCutH` y
`InpFridayCloseCutH`), así la regla vale igual en cualquier plaza. Y cada símbolo cierra
en su propio horario: que se acabe la sesión de Londres no toca las posiciones abiertas
en EURUSD.

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
→ "Símbolos" → buscá `XAUUSD` y `EURUSD` y activalos (doble clic). Si tu broker llama
distinto al oro (ej. `GOLD`), anotá el nombre exacto — se configura en el bot.

## Paso 2 — Copiar el bot a MetaTrader

1. En MT5: menú **Archivo → Abrir carpeta de datos**. Se abre una carpeta del Finder.
2. Entrá a `MQL5/Experts/` y creá una carpeta `Atlas`.
3. Copiá **todo el contenido de la carpeta `src/` de este proyecto** adentro de
   `MQL5/Experts/Atlas/`. Tiene que quedar así:

```
MQL5/Experts/Atlas/
├── Atlas_EA.mq5
├── Atlas_SelfTest.mq5
└── include/
    ├── AtlasTypes.mqh
    ├── BreakoutStrategy.mqh
    ├── CrtStrategy.mqh
    ├── Dashboard.mqh
    ├── NewsFilter.mqh
    ├── Notifier.mqh
    ├── RegimeDetector.mqh
    ├── RiskManager.mqh
    ├── ScalpStrategy.mqh
    ├── SessionFilter.mqh
    ├── SmcStrategy.mqh
    ├── TradeManager.mqh
    ├── TrendStrategy.mqh
    └── TVRating.mqh
```

## Paso 2b — Verificación previa (opcional pero recomendado)

Antes de compilar podés correr un chequeo estático de las fuentes:

```
python3 scripts/check_sources.py
```

No es un compilador: es una red de seguridad que atrapa los errores que se cuelan
al cambiar una firma y dejar un llamador viejo, o al renombrar un input o una variable
global y que sobreviva una referencia. Verifica balance de llaves, cantidad de
argumentos en cada llamada a método contra la firma real de su clase, y que todo `Inp*`
y `g_*` usado esté declarado. Si dice "Sin hallazgos", igual **falta compilar**.

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
3. Abrí la pestaña **Caja de herramientas → Expertos** y verificá que termine con:
   `ATLAS SELFTEST: ALL PASS`.
   - Si dice `SKIP ... mercado cerrado`: es normal en fin de semana — repetilo con
     mercado abierto (lunes a viernes).

## Paso 5 — Activar el bot en demo

1. Abrí un gráfico **EURUSD** en temporalidad **M15**. Una sola instancia maneja los dos
   símbolos — **no** lo pongas también en el gráfico del oro.
2. Botón **Algo Trading** de la barra superior: debe quedar **verde/activado**.
3. Arrastrá `Atlas_EA` desde el Navegador al gráfico. En la ventana que aparece:
   - Pestaña "Común": tildá **"Permitir Algo Trading"**.
   - Pestaña "Parámetros de entrada": revisá los valores (vienen con los defaults
     correctos). Si tu broker usa otros nombres (`EURUSD.a`, `GOLD`, `XAUUSD.i`…),
     corregilos en `InpSymbols` **y en las listas de estrategia y sesión** con el nombre
     exacto que muestra Observación del mercado: se comparan por texto.
4. OK. En la esquina superior derecha del gráfico debe aparecer una carita 🙂 (algo
   trading activo) y en el gráfico el **panel ATLAS** con el estado en vivo.

**Qué esperar:** el bot analiza al cierre de cada vela de 15 minutos y la enorme mayoría
de las veces la decisión correcta es NO operar. Con la configuración actual — dos
símbolos, ventanas de 9 horas y modelos muy selectivos — es normal ver **2 a 5
operaciones por semana entre los dos**, y semanas sin ninguna. No está roto: las líneas
`CRT` y `SmartM.` del panel dicen en qué paso se frenó cada análisis. Todo queda
registrado en la pestaña Expertos.

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
   - Símbolo: **EURUSD** · Período: **M15** (para medir el oro, repetí con **XAUUSD**;
     el probador de MT5 corre un símbolo por vez)
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
5. Corridas A/B: repetí el backtest desactivando una estrategia por vez
   (`InpEnableSmc`, `InpEnableCrt`, `InpEnableTrend`, `InpEnableBreakout`,
   `InpEnableScalp`) para ver qué aporta cada una. Empezá por los dos modelos
   estructurales: como tienen prioridad, son los que más cambian el resultado.
   En CRT probá además `InpCrtMode` en 0 (en vivo) y 1 (confirmado): el segundo entra
   más tarde pero solo después de que la vela de purga cerró dentro del rango.

### Límites de spread

Se configuran en la **unidad natural de cada instrumento**, no en "points":

| Instrumento | Input | Unidad | Default |
|---|---|---|---|
| Pares | `InpMaxSpreadForex` | pips | 2.0 |
| Oro | `InpMaxSpreadGold` | centavos de dólar | 50 (= 0.50 USD) |
| Índices | `InpMaxSpreadIndex` | puntos del índice | 5.0 |

El motivo: un "point" no es una cantidad fija, depende de con cuántos decimales cotice
cada bróker. El oro se cotiza con 2 o 3 decimales según el bróker, y los pares con 4 o
5. Antes el límite del oro eran 400 points, que son **0.40 USD en un bróker de 3
decimales pero 4.00 USD en uno de 2** — diez veces más flojo, sin ningún aviso, dejando
operar con spreads pésimos. Lo mismo pasaba con los 20 points del EURUSD (2 pips contra
20 pips). Ahora ponés la tolerancia real y el bot la convierte a los points de tu
bróker.

Al quedar operativo cada símbolo, el bot escribe en la pestaña Expertos su spread actual,
el límite ya convertido y con cuántos decimales cotiza.

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

| Parámetro | Default | Qué hace |
|---|---|---|
| `InpRiskPct` | 1.5 | % del capital arriesgado por operación |
| `InpDailyLossPct` | 5.0 | Pérdida diaria que frena al bot hasta mañana |
| `InpMaxDrawdownPct` | 30.0 | Caída desde el pico que apaga el bot (kill switch) |
| `InpResetKillSwitch` | false | Poner `true` UNA vez para reactivar tras un kill switch |
| `InpEnableTrend` / `InpEnableBreakout` | true | Activar/desactivar cada estrategia |
| `InpEnableSmc` | true | Activar Smart Money (tiene prioridad sobre las demás) |
| `InpSmcRequireHtf` | true | Exigir que la estructura de H1 acompañe la de M15 |
| `InpSmcRequireSweep` | false | Exigir barrido de liquidez previo — mucho más selectivo |
| `InpSmcRequireDisc` | true | Comprar solo en descuento, vender solo en premium |
| `InpSmcTvFilter` | 0 | Confluencia del rating TV para SMC: 0 ninguna · 1 solo H1 · 2 M15+H1 |
| `InpEnableCrt` | true | Activar Candle Range Theory |
| `InpCrtTimeframe` | H4 | Vela que define el rango (H1, H4, D1…) |
| `InpCrtMode` | 0 | 0 = en vivo (purga en la vela en curso) · 1 = confirmado (la purga ya cerró) |
| `InpCrtMaxPurgePct` | 40.0 | Purga máxima en % del rango; más profundo se considera ruptura real |
| `InpCrtMinRR` | 1.5 | Recorrido mínimo al extremo opuesto para que el setup valga |
| `InpCrtFollowRegime` | true | No operar la purga a contramano de la tendencia de H1 |
| `InpNewYorkSymbols` | `EURUSD` | Símbolos que operan en la sesión de Nueva York |
| `InpNyStart/End` | 8 / 13 | Ventana de Nueva York, en hora de Nueva York |
| `InpLondonSymbols` | `XAUUSD` | Símbolos que operan en la sesión de Londres |
| `InpLonStart/End` | 8 / 17 | Ventana de Londres, en hora de Londres |
| `InpFridayEntryCutH` | 2 | Viernes: sin entradas las últimas N horas de cada sesión |
| `InpFridayCloseCutH` | 1 | Viernes: cerrar todo N horas antes del fin de cada sesión |
| `InpServerGmtOffset` | 99 | Huso del servidor; 99 = detectar solo. Forzalo si la detección falla |
| `InpLocalGmtOffset` | -3 | Tu huso, solo para mostrar las horas en el panel (Paraguay = -3) |
| `InpMaxSpreadForex` | 2.0 | Spread máximo en pares, **en pips** |
| `InpMaxSpreadGold` | 50.0 | Spread máximo en oro, **en centavos** (50 = 0.50 USD) |
| `InpMaxSpreadIndex` | 5.0 | Spread máximo en índices, **en puntos del índice** |
| `InpNewsCurrencies` | `USD,EUR,GBP` | Monedas cuyo calendario económico se vigila |
| `InpNewsKeywords` | *(vacío)* | Vacío = pausar ante cualquier evento de alto impacto |

## Actualizar el bot en el servidor (Docker)

Si el bot corre en un servidor Linux con el contenedor Docker del repo, la
actualización completa es **un comando**:

```
bash ~/atlas-ea/docker/update_atlas.sh
```

Ese script hace `git pull`, corre el verificador estático, **recompila el EA dentro
del build de la imagen** (el build falla si MetaEditor reporta un error — en ese caso
el bot viejo sigue corriendo intacto) y relanza el contenedor leyendo las credenciales
de `~/atlas-ea/.env` (las guarda `docker/set_password.sh`, una sola vez).

Al final tiene que aparecer en el log `ATLAS EA v2.00 iniciado` y una línea por
símbolo con sus estrategias y su sesión traducida a hora del servidor y a la tuya.

Para el backtest A/B en el servidor (contenedor descartable, no toca el bot vivo):

```
docker run --rm --env-file ~/atlas-ea/.env \
  -v ~/atlas-ea/scripts/server_backtest.sh:/bt.sh atlas-ea:2.0 bash /bt.sh
```

Corre 4 pasadas: EURUSD solo CRT, y el oro con CRT+SMC, solo CRT y solo SMC — para
medir qué aporta cada estrategia. En el tester el EA asume bróker EET (UTC+2/+3
europeo), la convención de MetaQuotes-Demo; para otro huso, fijar
`InpServerGmtOffset` en el script.

## Problemas frecuentes

- **"simbolo no disponible"** al iniciar → el broker usa otro nombre (GOLD, XAUUSD.a…):
  corregir `InpSymbols` y las listas de estrategia/sesión, que comparan por texto exacto.
- **Un símbolo dice "NINGUNA (no va a operar)"** en el log de arranque → está en
  `InpSymbols` pero en ninguna lista de estrategia. Agregalo a la que corresponda.
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
