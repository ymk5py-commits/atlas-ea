# ATLAS EA — Bot de trading para MetaTrader 5 (oro + EURUSD)

Bot híbrido adaptativo que opera **XAUUSD** y **EURUSD** en intradía (M15 con tendencia
H1/H4), con gestión de riesgo estricta: límite de pérdida diaria, kill switch por
drawdown, filtro de noticias y cierre pre-fin de semana.

**Estrategias que corren en paralelo:**

| Estrategia | Cuándo entra | Módulo |
|---|---|---|
| **Smart Money (SMC)** | Quiebre de estructura (BOS/CHoCH) con desplazamiento, y retroceso a un Order Block / FVG sin mitigar, en descuento (compras) o premium (ventas) | `SmcStrategy.mqh` |
| **Tendencia** | Pullback a la EMA20 de M15 a favor de H1/H4, con RSI(9) recuperando 50 | `TrendStrategy.mqh` |
| **Ruptura asiática** | Cierre M15 fuera del rango 1–8h en la ventana de Londres/NY | `BreakoutStrategy.mqh` |
| **Scalping M1** | Momentum EMA9/EMA21 + RSI(7) en oro, salida en minutos | `ScalpStrategy.mqh` |

Un detector de régimen (ADX H1 / compresión de Bollinger M15) decide cuál aplica.
Smart Money tiene prioridad: si encuentra setup, se opera ese; si no, entra la
estrategia del régimen. El scalping corre aparte, en su propia ventana horaria.

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

1. Abrí un gráfico **XAUUSD** en temporalidad **M15** (una sola instancia del bot maneja
   los dos símbolos — no lo pongas en dos gráficos).
2. Botón **Algo Trading** de la barra superior: debe quedar **verde/activado**.
3. Arrastrá `Atlas_EA` desde el Navegador al gráfico. En la ventana que aparece:
   - Pestaña "Común": tildá **"Permitir Algo Trading"**.
   - Pestaña "Parámetros de entrada": revisá los valores (vienen con los defaults
     correctos del diseño). Si tu broker llama `GOLD` al oro, cambiá `InpSymbols` a
     `GOLD,EURUSD`.
4. OK. En la esquina superior derecha del gráfico debe aparecer una carita 🙂 (algo
   trading activo) y en el gráfico el **panel ATLAS** con el estado en vivo.

**Qué esperar:** el bot analiza al cierre de cada vela de 15 minutos, opera solo en
sesión de Londres/NY, y muchas velas la decisión correcta es NO operar. Un día típico
tiene 0 a 4 operaciones por símbolo. Todo queda registrado en la pestaña Expertos.

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
   - Símbolo: **XAUUSD** · Período: **M15**
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
   (`InpEnableSmc`, `InpEnableTrend`, `InpEnableBreakout`, `InpEnableScalp`) para ver
   qué aporta cada una. Empezá por medir Smart Money sola contra la combinación
   completa: como tiene prioridad, es la que más cambia el resultado.

> **Nota:** el filtro de noticias no funciona en el backtest (limitación de MT5 — el
> calendario económico no está disponible en el probador). En demo/real sí funciona.
> Por eso los resultados de demo pueden ser levemente mejores que el backtest.

## Fases de validación (no saltear)

| Fase | Qué | Criterio para avanzar |
|---|---|---|
| 1. Backtest | 2023–2026, ticks reales | PF ≥ 1.3 · DD ≤ 25% · ≥ 100 ops |
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
| `InpSessionStart/End` | 8 / 20 | Ventana de entradas (hora del SERVIDOR del broker) |
| `InpMaxSpreadGold/Eur` | 400 / 20 | Spread máximo tolerado (points) |

## Problemas frecuentes

- **"simbolo no disponible"** al iniciar → el broker usa otro nombre (GOLD, XAUUSD.a…):
  corregir `InpSymbols`.
- **No opera nunca** → revisar: Algo Trading activado (botón verde), hora del servidor
  dentro de la sesión (8–20), pestaña Expertos para ver los motivos ("fuera de sesion",
  "rating TV no confirma", etc. — el bot explica cada decisión).
- **Smart Money no dispara nunca** → mirá la línea `SmartM.` del panel: dice en qué paso
  se frena ("esperando retroceso a la zona", "zona ya mitigada", "H1 no acompana",
  "zona fuera de descuento"). Es un modelo selectivo: pasar semanas sin setup en un
  símbolo es normal. Para aflojarlo, empezá por `InpSmcRequireDisc = false`; para
  apretarlo, `InpSmcRequireSweep = true`.
- **La carita del gráfico está gris/tachada** → falta tildar "Permitir Algo Trading" en
  las propiedades del EA (F7 sobre el gráfico).
- **El backtest no descarga ticks** → probar primero con modelado "1 minuto OHLC" para
  una pasada rápida, y dejar la de ticks reales corriendo con tiempo.
- **Mac se duerme** → Ajustes del Sistema → Pantalla y Energía: evitar reposo con MT5
  abierto durante la sesión de trading (o el bot se pausa con la Mac).
