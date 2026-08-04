# ATLAS EA — Especificación de diseño
**Fecha:** 2026-08-03
**Proyecto:** Bot de trading (Expert Advisor MQL5) para MetaTrader 5
**Símbolos:** XAUUSD (oro) y EURUSD
**Estado:** Aprobado por el usuario (diseño). Pendiente: plan de implementación.

---

## 1. Contexto y objetivo

El usuario quiere un bot que opere oro y EURUSD en MetaTrader 5 con gestión de riesgo
estricta y análisis de tendencia multi-fuente. Corre en su Mac (MT5 oficial para macOS),
primero en **cuenta demo** (no tiene broker todavía; se abre demo al instalar MT5).

**Expectativas acordadas (honestas):** perfil **agresivo** — objetivo 8-15% mensual en
meses buenos, con drawdown esperado de hasta 25-30%. NO se promete rentabilidad; se
aclaró explícitamente que "10% semanal" es matemáticamente insostenible. El bot no toca
dinero real hasta pasar backtest + 2-4 semanas de demo con métricas de aceptación
cumplidas.

**Decisiones del usuario:**
- Perfil de riesgo: Agresivo (riesgo 2%/operación, límite diario 5%)
- Infraestructura: Mac del usuario con MT5 para macOS (migrable a VPS después)
- Broker: ninguno aún → demo de MetaQuotes al instalar
- Estilo: Intradía M15 con tendencia H1/H4
- Estrategia: **Híbrido adaptativo** (detector de régimen + 2 estrategias)
- Capital real futuro estimado: < USD 500 (demo se configura en USD 500)

---

## 2. Arquitectura

**Un solo EA multi-símbolo** (`Atlas_EA.mq5`) que corre en un gráfico cualquiera
(recomendado XAUUSD M15) y gestiona ambos símbolos desde una instancia, para poder
coordinar el riesgo global. Módulos como includes (`.mqh`), cada uno con una
responsabilidad única e interfaz clara.

```
BOT TRADING/
├── docs/superpowers/specs/          # este documento
├── src/
│   ├── Atlas_EA.mq5                 # orquestador: eventos, wiring de módulos
│   └── include/
│       ├── RegimeDetector.mqh       # clasifica: TENDENCIA / COMPRESION / RANGO_SUCIO
│       ├── TrendStrategy.mqh        # señales de pullback multi-timeframe
│       ├── BreakoutStrategy.mqh     # señales de ruptura del rango asiático
│       ├── TVRating.mqh             # réplica del rating técnico de TradingView
│       ├── RiskManager.mqh          # sizing, límites diarios, kill switch
│       ├── TradeManager.mqh         # ejecución, SL/TP, BE, trailing, parciales
│       ├── NewsFilter.mqh           # calendario económico MQL5
│       ├── SessionFilter.mqh        # ventanas horarias, cierre pre-weekend
│       ├── Dashboard.mqh            # panel visual en el chart
│       └── Notifier.mqh             # push notifications al celular
└── README.md                        # instalación MT5 Mac, demo, compilación, uso
```

**Modelo de eventos:** `OnTimer()` cada 1 segundo (no `OnTick`, porque los ticks solo
llegan del símbolo del chart). En cada timer:
1. Gestionar posiciones abiertas de ambos símbolos (BE, trailing, cierres).
2. Detectar vela M15 nueva por símbolo → correr el pipeline de señales.

**Identificación:** magic number `20260803`. El EA solo gestiona posiciones propias.

---

## 3. Pipeline de decisión (por símbolo, en cada vela M15 nueva)

```
1. GATE de contexto  → SessionFilter OK? NewsFilter OK? spread OK? RiskManager OK?
                       Si algo falla → no evaluar señales (log del motivo).
2. RegimeDetector    → TENDENCIA | COMPRESION | RANGO_SUCIO
3. Señal             → TENDENCIA  → TrendStrategy.check()
                       COMPRESION → BreakoutStrategy.check()
                       RANGO_SUCIO→ nada
4. Confluencia       → TVRating M15 y H1 deben estar a favor
                       (largo: ambos ≥ COMPRA; corto: ambos ≤ VENTA)
5. RiskManager.size()→ calcula lote por riesgo 2% de equity; si min-lot excede → skip
6. TradeManager.open()→ orden a mercado con SL/TP; notificación push; log
```

---

## 4. Especificación de módulos

### 4.1 RegimeDetector
- **TENDENCIA:** ADX(14) en H1 > `InpAdxTrend` (default 22). Dirección por DI+/DI−.
- **COMPRESION:** ancho de Bandas de Bollinger(20,2) en M15 < `InpSqueezeRatio`
  (default 0.75) × promedio del ancho de las últimas 96 velas M15 (~24 h), y ADX H1 ≤ umbral.
- **RANGO_SUCIO:** todo lo demás → no operar.

### 4.2 TrendStrategy (pullback multi-timeframe)
Condiciones para LARGO (corto simétrico invertido):
- H1: EMA50 > EMA200 y ADX(14) > umbral con DI+ > DI−.
- H4: precio de cierre > EMA50(H4) (alineación del marco mayor).
- M15: el precio retrocedió hasta la zona EMA20(M15) ± 0.3×ATR(14)M15 y
  RSI(9)M15 cruza al alza el nivel 50 (momentum retoma).
- **SL:** el mayor entre 1.5×ATR(14)M15 y el swing low del pullback (con margen de spread).
- **TP:** 1.5R mínimo (ver TradeManager para parciales/trailing).
- Anti-repetición: 1 señal máx. por dirección por cruce (no re-entrar en la misma zona
  hasta que RSI vuelva a armar el setup).

### 4.3 BreakoutStrategy (ruptura del rango asiático)
- **Rango:** high/low entre `InpAsiaStart` y `InpAsiaEnd` (defaults 01:00–08:00 hora
  del servidor; parametrizado porque cada broker tiene su zona horaria).
- **Validez:** el rango debe medir ≤ 1.2×ATR(14)H1 (compresión real, no un día ya movido).
- **Entrada:** primera vela M15 que CIERRA fuera del rango dentro de la ventana
  08:00–15:00 servidor, con TVRating a favor.
- **SL:** de las dos opciones —extremo opuesto del rango o 1.5×ATR(14)M15— se usa la
  que quede MÁS CERCA del precio de entrada (menor distancia de stop).
- **Límite:** 1 ruptura operada por día por símbolo.

### 4.4 TVRating (réplica del "Technical Rating" de TradingView)
Implementa el algoritmo público de TradingView. Cada indicador vota −1/0/+1 y se
promedia:
- **Grupo medias (15 votos):** SMA y EMA de 10/20/30/50/100/200 (precio vs media),
  Ichimoku Base Line, VWMA(20), Hull MA(9).
- **Grupo osciladores (11 votos):** RSI(14), Estocástico(14,3,3), CCI(20), ADX(14),
  Awesome Oscillator, Momentum(10), MACD(12,26,9), Stochastic RSI, Williams %R,
  Bull/Bear Power, Ultimate Oscillator — con las reglas de voto de TradingView
  (p. ej. RSI: +1 si <30 y girando al alza; −1 si >70 y girando a la baja).
- **Escala del promedio:** ≥0.5 COMPRA_FUERTE · 0.1–0.5 COMPRA · −0.1–0.1 NEUTRAL ·
  −0.5–−0.1 VENTA · ≤−0.5 VENTA_FUERTE.
- API del módulo: `ERating GetRating(symbol, timeframe)`. Se calcula al cierre de vela.
- Nota: valores casi idénticos a los de la web de TradingView (misma fórmula; feed de
  precios del broker puede diferir marginalmente).

### 4.5 RiskManager
- **Sizing:** `lots = (equity × InpRiskPct) / (SL_puntos × valor_del_punto)`,
  redondeado HACIA ABAJO al step del símbolo. `InpRiskPct` default 2.0.
  Si `lots < min_lot` → **no se opera** (protección de cuenta chica) + log + push.
- **Límite diario:** si el equity cae `InpDailyLossPct` (default 5%) respecto al equity
  del inicio del día (hora servidor), no se abren nuevas posiciones hasta el día
  siguiente. Las abiertas conservan su gestión (el SL protege).
- **Kill switch:** se persiste el pico histórico de equity (variables globales del
  terminal, sobreviven reinicios). Si equity < 75% del pico (`InpMaxDrawdownPct` 25):
  cierra todas las posiciones del EA, deja de operar y notifica. Reactivación: manual
  (input `InpResetKillSwitch`).
- **Exposición:** máx. 1 posición por símbolo, 2 en total; riesgo total abierto ≤ 3%
  del equity (oro y EURUSD correlacionan vía dólar); máx. 4 operaciones/día/símbolo.

### 4.6 TradeManager
- Órdenes a mercado, `deviation` 20 points. SL/TP siempre en la orden.
- **Break-even:** a +0.8R → SL a entrada + spread + 1 point.
- **Trailing:** tras BE, chandelier de 1×ATR(14)M15 desde el extremo favorable.
- **Parcial:** si el lote ≥ 0.02 → cierra 50% en +1R y el resto corre con trailing.
  Si el lote es 0.01 → TP fijo en 1.5R (no se puede partir).
- **Pre-weekend:** viernes: no abre posiciones nuevas desde `InpFridayLastEntry`
  (default 18:00 servidor) y cierra todas las abiertas a `InpFridayCloseHour`
  (default 21:00 servidor, ~2 h antes del cierre del mercado).
- **Reconciliación:** en `OnInit`, re-adopta posiciones con su magic number y
  reconstruye su estado de gestión (BE hecho o no, etc.) desde los datos de la posición.
- Reintentos ante retcodes recuperables (requote, price off): hasta 3 con pausa.

### 4.7 NewsFilter
- Usa el **calendario económico integrado de MQL5** (`CalendarValueHistory`).
- Bloquea nuevas entradas si hay evento `CALENDAR_IMPORTANCE_HIGH` de **USD o EUR**
  dentro de ±30 min (`InpNewsBlockMin`). XAUUSD y EURUSD usan ambas monedas.
- Si hay posición abierta y se acerca una noticia: intenta mover SL a BE (si ya ≥ +0.5R).
- **Limitación documentada:** el calendario NO está disponible en el Strategy Tester →
  en backtest el filtro se desactiva automáticamente (flag interno). Se valida en demo.

### 4.8 SessionFilter
- Ventana de operación: `InpSessionStart`–`InpSessionEnd` (defaults 08:00–20:00 hora
  del servidor ≈ Londres + NY para brokers GMT+2/3). Solo bloquea ENTRADAS nuevas.
- Gate de spread: no operar si spread actual > `InpMaxSpreadPoints` por símbolo
  (defaults: XAUUSD 400 points = $0.40; EURUSD 20 points = 2 pips).

### 4.9 Dashboard
Panel de objetos de texto en el chart: por símbolo → régimen actual, rating TV M15/H1,
posición abierta (dirección, R actual), y global → P&L del día, drawdown desde el pico,
operaciones del día, estado (OPERANDO / PAUSA NOTICIA / LÍMITE DIARIO / KILL SWITCH /
FUERA DE SESIÓN), próxima noticia de alto impacto (hora y moneda).

### 4.10 Notifier
`SendNotification()` (push a la app móvil MT5 vía MetaQuotes ID) + `Print` al log en:
apertura/cierre de posición (con motivo y R), BE activado, parcial tomado, límite diario
alcanzado, kill switch, lote mínimo excede riesgo, y errores críticos. Input
`InpEnablePush` para apagarlo.

---

## 5. Parámetros de entrada (inputs del EA)

Todos los umbrales citados son `input` configurables, agrupados: General (símbolos,
magic, push), Riesgo (risk %, daily loss %, max DD %, max posiciones), Estrategia
(umbrales ADX, squeeze, ATR mults, RR), Sesión/Noticias (ventanas horarias, spread máx,
minutos de bloqueo), Viernes (hora de cierre). Defaults = los valores de esta spec.

---

## 6. Manejo de errores

- **Desconexión/reinicio:** reconciliación en OnInit (ver TradeManager).
- **Retcodes de broker:** clasificados en recuperables (reintento ×3) e irrecuperables
  (log + push + skip).
- **Datos faltantes** (history no cargada para el 2º símbolo): reintenta la carga con
  `SymbolSelect` y espera; no evalúa señales hasta tener historia suficiente (≥ 300
  velas por timeframe usado).
- **Spread/rollover anormal:** gate de spread (4.8).
- **Logs:** cada decisión (incluida la de NO operar y su motivo) se registra con
  timestamp — auditable en la pestaña "Expertos" de MT5.

---

## 7. Plan de validación (fases y criterios de aceptación)

**Fase 1 — Backtest (Strategy Tester de MT5):**
- Datos: "Every tick based on real ticks", spread real, 2023-01 → 2026-07,
  XAUUSD y EURUSD (separados y juntos).
- Walk-forward: optimizar en 2023–2024, validar out-of-sample en 2025–2026.
  Parámetros a optimizar (pocos, para evitar sobreajuste): umbral ADX (18–30),
  multiplicador ATR del SL (1.0–2.5), RR objetivo (1.2–2.5).
- **Criterios para pasar a demo:** profit factor ≥ 1.3 en out-of-sample, drawdown
  máximo ≤ 25%, ≥ 100 operaciones en el período, ningún mes peor que −15%.

**Fase 2 — Demo en vivo:** 2–4 semanas, cuenta demo de USD 500, perfil agresivo.
- **Criterios para considerar real:** P&L positivo, comportamiento consistente con el
  backtest, cero violaciones de las reglas de riesgo, news filter verificado en vivo.

**Fase 3 — Real (decisión exclusiva del usuario):** si decide fondear, arrancar las
primeras 2 semanas con riesgo reducido (1%) antes de subir al perfil agresivo.

Si la Fase 1 no cumple los criterios → se ajusta la estrategia o se replantea. No se
avanza con un sistema perdedor "porque ya está construido".

---

## 8. Fases de implementación (resumen para el plan)

1. Esqueleto del EA + RiskManager + TradeManager (núcleo de seguridad primero).
2. TVRating (réplica del rating de TradingView) con test de sanidad vs web.
3. TrendStrategy + RegimeDetector (modo solo-tendencia) → primer backtest.
4. BreakoutStrategy → backtest del híbrido completo + walk-forward.
5. NewsFilter + SessionFilter completos + Dashboard + Notifier.
6. README de instalación (MT5 para Mac, demo, MetaEditor, compilación, puesta en marcha)
   + puesta en demo guiada.

---

## 9. Advertencias registradas (para que quede escrito)

- El trading con apalancamiento puede generar pérdidas superiores a lo esperado.
  Ningún sistema garantiza rentabilidad; los resultados de backtest no aseguran
  resultados futuros.
- La diferencia demo→real existe (slippage, ejecución). Por eso la validación por fases.
- El perfil agresivo elegido (2%/operación) implica que una racha de 10 pérdidas
  seguidas ≈ −18% del capital. El kill switch de −25% es el último fusible.
- Este proyecto es una herramienta de software; la decisión de operar dinero real y
  sus consecuencias son exclusivamente del usuario.

---

## 10. Addendum v1.0 (2026-08-04) — configuración validada por backtest

Tras el ciclo de backtests (ver commits): dos bugs corregidos (sizing con tick_value
roto del broker; kill switch sin pico persistido) y optimización de gestión validada
en períodos independientes (2023-2024: +17.5% / 2025-2026: +22.0%, 930 trades).

**Defaults finales (difieren del diseño original §4-5):**
- `InpRiskPct` 1.5 (era 2.0) — elegido por el usuario tras ver DD proyectados.
- `InpMaxDrawdownPct` 30 (era 25) — margen sobre el DD máx observado 23.9%.
- `InpRR` 2.0 (era 1.5) · `InpBeTriggerR` 1.0 (era 0.8) · `InpTrailAtrMult` 2.0 (era 1.0).

**Resultado del backtest final (todas las protecciones activas):** 2023.01→2026.07,
500→613.47 USD (+22.7%), 917 trades, DD máx 23.9%, kill switch 0 disparos.
**Expectativa comunicada al usuario: 6-16% anual con rachas de −15 a −25%.**
