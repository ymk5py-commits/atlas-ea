# ATLAS EA — Bot de trading para MetaTrader 5 (EURUSD, sesión de Nueva York)

Bot de trading intradía con gestión de riesgo estricta: límite de pérdida diaria, kill
switch por drawdown, filtro de noticias y cierre pre-fin de semana.

## Configuración actual

| | |
|---|---|
| **Símbolo** | EURUSD, únicamente |
| **Estrategia** | Candle Range Theory (CRT), únicamente |
| **Sesión** | Nueva York, 08:00–17:00 hora de NY |

Las demás estrategias siguen en el código y se encienden con un input, pero vienen
**apagadas**:

| Estrategia | Input | Default | Cuándo entra |
|---|---|---|---|
| **Candle Range Theory** | `InpEnableCrt` | **true** | Una vela de H4 define el rango; la siguiente purga un extremo cazando stops y vuelve adentro; se opera hacia el extremo opuesto, que es el objetivo |
| Smart Money (SMC) | `InpEnableSmc` | false | Quiebre de estructura (BOS/CHoCH) con desplazamiento, y retroceso a un Order Block / FVG sin mitigar |
| Tendencia | `InpEnableTrend` | false | Pullback a la EMA20 de M15 a favor de H1/H4, con RSI(9) recuperando 50 |
| Ruptura asiática | `InpEnableBreakout` | false | Cierre M15 fuera del rango 1–8h |
| Scalping M1 | `InpEnableScalp` | false | Momentum EMA9/EMA21 + RSI(7) en oro, salida en minutos |

Si encendés más de una, el orden de prioridad es **SMC → CRT → estrategia del régimen**
(un detector de ADX H1 / compresión de Bollinger M15 elige entre tendencia y ruptura).

CRT es la única que fija su propio objetivo (el extremo opuesto del rango) en vez de
dejar la salida al parcial + trailing; el break-even, el cierre parcial y el trailing
siguen funcionando igual sobre esa posición.

## La ventana horaria se define en hora de NUEVA YORK

El bot **no** usa la hora de tu computadora ni la del bróker para decidir la sesión:
vos ponés las horas en hora de Nueva York y él convierte solo. Deduce el huso del
servidor comparando su reloj contra UTC, y le aplica el horario de verano de EE.UU.
(segundo domingo de marzo → primer domingo de noviembre). O sea que la ventana **no se
corre sola** cuando cambia la hora ni cuando el bróker cambia su propio horario.

Con la ventana por defecto (08–17 de Nueva York), **en Paraguay (UTC-3)** eso cae en:

| Época | Hora de Nueva York | Hora de Paraguay |
|---|---|---|
| Verano EE.UU. (marzo–noviembre) | 08:00–17:00 | **09:00–18:00** |
| Invierno EE.UU. (noviembre–marzo) | 08:00–17:00 | **10:00–19:00** |

Al arrancar, el bot escribe en la pestaña Expertos la ventana ya resuelta en las tres
zonas (Nueva York, servidor y la tuya) y qué huso detectó. **Verificá esa línea la
primera vez.** Si el huso detectado está mal (pasa si el reloj del sistema donde corre
MT5 está mal configurado), forzalo con `InpServerGmtOffset` — por ejemplo `2` o `3` para
un bróker europeo. El panel del gráfico muestra la misma ventana en todo momento.

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

1. Abrí un gráfico **EURUSD** en temporalidad **M15** (una sola instancia del bot; no lo
   pongas en varios gráficos).
2. Botón **Algo Trading** de la barra superior: debe quedar **verde/activado**.
3. Arrastrá `Atlas_EA` desde el Navegador al gráfico. En la ventana que aparece:
   - Pestaña "Común": tildá **"Permitir Algo Trading"**.
   - Pestaña "Parámetros de entrada": revisá los valores (vienen con los defaults
     correctos). Si tu broker le pone sufijo al par (`EURUSD.a`, `EURUSD_i`…), corregí
     `InpSymbols` con el nombre exacto que muestra Observación del mercado.
4. OK. En la esquina superior derecha del gráfico debe aparecer una carita 🙂 (algo
   trading activo) y en el gráfico el **panel ATLAS** con el estado en vivo.

**Qué esperar:** el bot analiza al cierre de cada vela de 15 minutos y la enorme mayoría
de las veces la decisión correcta es NO operar. Con la configuración actual — un solo
símbolo, una sola estrategia y una ventana de 9 horas — es normal ver **1 a 3
operaciones por semana**, y semanas enteras sin ninguna. No está roto: la línea `CRT`
del panel dice en qué paso se frenó cada análisis. Todo queda registrado en la pestaña
Expertos.

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
   - Símbolo: **EURUSD** · Período: **M15**
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
| `InpSessionInNY` | true | Interpretar la ventana en hora de Nueva York (false = hora del servidor) |
| `InpSessionStart/End` | 8 / 17 | Ventana de entradas, en hora de Nueva York |
| `InpServerGmtOffset` | 99 | Huso del servidor; 99 = detectar solo. Forzalo si la detección falla |
| `InpLocalGmtOffset` | -3 | Tu huso, solo para mostrar las horas en el panel (Paraguay = -3) |
| `InpMaxSpreadEur` | 20 | Spread máximo tolerado en EURUSD (points) |

## Problemas frecuentes

- **"simbolo no disponible"** al iniciar → el broker usa otro nombre (GOLD, XAUUSD.a…):
  corregir `InpSymbols`.
- **No opera nunca** → revisar: Algo Trading activado (botón verde), que sea horario de
  la sesión de Nueva York (mirá la línea `Sesion` del panel, que la muestra en tu hora),
  y la pestaña Expertos para ver los motivos ("fuera de sesion",
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
