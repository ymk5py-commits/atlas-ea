//+------------------------------------------------------------------+
//| Atlas_EA.mq5 — Bot híbrido adaptativo para XAUUSD + EURUSD.      |
//| Spec: docs/superpowers/specs/2026-08-03-atlas-ea-design.md       |
//|                                                                  |
//| ADVERTENCIA: el trading apalancado puede generar pérdidas.       |
//| Validar SIEMPRE en backtest y cuenta demo antes de dinero real.  |
//+------------------------------------------------------------------+
#property copyright "ATLAS EA — uso personal"
#property version   "1.00"
#property strict

#include "include/AtlasTypes.mqh"
#include "include/Notifier.mqh"
#include "include/SessionFilter.mqh"
#include "include/RiskManager.mqh"
#include "include/TradeManager.mqh"
#include "include/TVRating.mqh"
#include "include/RegimeDetector.mqh"
#include "include/TrendStrategy.mqh"
#include "include/BreakoutStrategy.mqh"
#include "include/ScalpStrategy.mqh"
#include "include/SmcStrategy.mqh"
#include "include/CrtStrategy.mqh"
#include "include/NewsFilter.mqh"
#include "include/Dashboard.mqh"

//=== Inputs ========================================================
input group "General"
input string InpSymbols          = "EURUSD";        // Simbolos (separados por coma)
input bool   InpEnablePush       = true;            // Notificaciones push al celular
input int    InpDeviationPoints  = 20;              // Slippage maximo (points)

input group "Riesgo"
input double InpRiskPct          = 1.5;             // Riesgo por operacion (% equity)
input double InpDailyLossPct     = 5.0;             // Limite de perdida diaria (%)
input double InpMaxDrawdownPct   = 30.0;            // Kill switch: DD desde pico (%)
input double InpMaxTotalRiskPct  = 3.0;             // Riesgo abierto total maximo (%)
input int    InpMaxTradesPerDay  = 4;               // Max operaciones/dia por simbolo
input int    InpMaxPositions     = 2;               // Max posiciones simultaneas
input bool   InpResetKillSwitch  = false;           // Resetear kill switch (tras revisar)

input group "Gestion de posicion"
input double InpRR               = 2.0;             // Objetivo en R (TP sin parcial)
input double InpBeTriggerR       = 1.0;             // Break-even al llegar a +R
input double InpPartialR         = 1.0;             // Cierre parcial al llegar a +R
input double InpTrailAtrMult     = 2.0;             // Trailing: multiplicador ATR

input group "Estrategias"
input bool   InpEnableTrend      = false;           // Estrategia de tendencia (pullback)
input bool   InpEnableBreakout   = false;           // Estrategia de ruptura asiatica
input double InpAdxTrend         = 22.0;            // ADX H1 minimo para tendencia
input double InpSqueezeRatio     = 0.75;            // Compresion: ancho BB < ratio x prom
input double InpAtrSlMult        = 1.5;             // Stop loss: multiplicador ATR M15
input double InpMaxRangeAtrMult  = 1.2;             // Rango asiatico max (x ATR H1)

input group "Smart Money (estructura + Order Block / FVG)"
input bool   InpEnableSmc        = false;  // Activar Smart Money (tiene prioridad sobre CRT)
input int    InpSmcFractal       = 2;      // Amplitud del swing fractal (velas a cada lado)
input int    InpSmcLookback      = 160;    // Velas M15 analizadas (estructura)
input int    InpSmcMaxAgeBars    = 20;     // Antiguedad max del BOS/CHoCH (velas M15)
input double InpSmcDisplacement  = 1.0;    // Desplazamiento min de la vela del quiebre (x rango medio; 0 = sin filtro)
input bool   InpSmcRequireHtf    = true;   // Exigir que la estructura H1 acompane
input bool   InpSmcRequireSweep  = false;  // Exigir barrido de liquidez previo (mas selectivo)
input bool   InpSmcRequireDisc   = true;   // Comprar solo en descuento / vender solo en premium
input bool   InpSmcNeedRejection = true;   // Exigir vela de rechazo al tocar la zona
input bool   InpSmcUseFvg        = true;   // Refinar la zona con el FVG (imbalance)
input bool   InpSmcAllowChoppy   = false;  // Permitir SMC en regimen lateral (mas trades, mas ruido)
input double InpSmcSlBufferAtr   = 0.25;   // Colchon del SL bajo/sobre la zona (x ATR M15)
input double InpSmcMaxSlAtr      = 3.0;    // Descartar el setup si el SL supera (x ATR M15)
input int    InpSmcTvFilter      = 0;      // Confluencia rating TV: 0=ninguna, 1=solo H1, 2=M15+H1

input group "Candle Range Theory (rango de vela mayor + purga)"
input bool            InpEnableCrt      = true;       // Activar CRT
input ENUM_TIMEFRAMES InpCrtTimeframe   = PERIOD_H4;  // Vela que define el rango
input int    InpCrtMode          = 0;      // 0 = en vivo (purga en la vela en curso) · 1 = confirmado (la purga ya cerro)
input double InpCrtMinRangeAtr   = 0.8;    // Rango minimo de la vela (x ATR del TF) — evita dojis
input double InpCrtMaxRangeAtr   = 2.5;    // Rango maximo (x ATR del TF) — evita velas ya extendidas
input double InpCrtMaxPurgePct   = 40.0;   // Purga max en % del rango; mas profundo = ruptura, no barrido
input double InpCrtMinRR         = 1.5;    // Recorrido minimo al extremo opuesto (en R)
input double InpCrtSlBufferAtr   = 0.25;   // Colchon del SL sobre la purga (x ATR M15)
input bool   InpCrtRequireEq     = true;   // Vender solo desde premium / comprar solo desde descuento
input bool   InpCrtNeedRejection = true;   // Exigir vela de rechazo en M15
input bool   InpCrtFollowRegime  = true;   // No operar la purga a contramano de la tendencia H1
input int    InpCrtTvFilter      = 0;      // Confluencia rating TV: 0=ninguna, 1=solo H1, 2=M15+H1

input group "Sesion y noticias"
input bool   InpSessionInNY      = true;            // Ventana de entradas en hora de NUEVA YORK (false = hora del servidor)
input int    InpServerGmtOffset  = 99;              // Desfase del servidor vs UTC en horas; 99 = detectar solo
input int    InpLocalGmtOffset   = -3;              // Tu huso horario (solo para mostrar horas en el panel). Paraguay = -3
input int    InpSessionStart     = 8;               // Inicio ventana de entradas (apertura de Nueva York)
input int    InpSessionEnd       = 17;              // Fin ventana de entradas (cierre de Nueva York)
input int    InpFridayLastEntry  = 15;              // Viernes: ultima hora de entrada
input int    InpFridayClose      = 16;              // Viernes: cerrar todo desde
input long   InpMaxSpreadGold    = 400;             // Spread max XAUUSD (points)
input long   InpMaxSpreadEur     = 20;              // Spread max EURUSD (points)
input long   InpMaxSpreadIndex   = 600;             // Spread max indices US (points)
input int    InpNewsBlockMin     = 30;              // Bloqueo +/- minutos por noticia
// Solo pausan eventos HIGH cuyo nombre matchee (CSV, vacio = todos)
input string InpNewsKeywords     = "CPI,NFP,NONFARM,PAYROLL,FOMC,INTEREST RATE,RATE DECISION,UNEMPLOYMENT,GDP,PCE,RETAIL SALES";
input int    InpAsiaStart        = 1;               // Rango asiatico: hora inicio
input int    InpAsiaEnd          = 8;               // Rango asiatico: hora fin
input int    InpBreakEnd         = 15;              // Fin ventana de ruptura

input group "Scalping (estilo manual, hora del SERVIDOR)"
input bool   InpEnableScalp      = false;           // Activar modo scalping M1
input string InpScalpSymbols     = "XAUUSD";        // Simbolos a scalpear (subset de InpSymbols)
input double InpScalpRiskPct     = 1.0;             // Riesgo por scalp (% equity)
input double InpScalpRR          = 1.0;             // TP del scalp (en R)
input double InpScalpBeR         = 0.5;             // Break-even del scalp (en R)
input double InpScalpAtrMult     = 1.2;             // SL scalp: multiplicador ATR M1
input int    InpScalpMaxPerDay   = 15;              // Max scalps/dia por simbolo
input int    InpScalpHoldMin     = 20;              // Cierre por tiempo (minutos)
input int    InpScalpCooldownMin = 3;               // Espera minima entre scalps (min)
input int    InpScalpStart       = 1;               // Scalp: hora inicio (evita rollover)
input int    InpScalpEnd         = 23;              // Scalp: hora fin
input double InpScalpRsiBuy      = 60.0;            // RSI7 minimo para comprar
input double InpScalpRsiSell     = 40.0;            // RSI7 maximo para vender

//=== Estado global =================================================
string             g_symbols[];
CNotifier          g_notifier;
CSessionFilter     g_session;
CRiskManager       g_risk;
CTradeManager      g_trade;
CNewsFilter        g_news;
CDashboard         g_dash;

CTVRating         *g_tvM15[];
CTVRating         *g_tvH1[];
CRegimeDetector   *g_regime[];
CTrendStrategy    *g_trend[];
CBreakoutStrategy *g_breakout[];
CScalpStrategy    *g_scalp[];       // NULL si el símbolo no scalpea
CSmcStrategy      *g_smc[];
CCrtStrategy      *g_crt[];
int                g_hAtrM15[];

datetime           g_lastM15[];
datetime           g_lastM1[];      // tracker de vela M1 (scalping)
datetime           g_lastScalpOpen[];
datetime           g_lastRetryLog[];  // throttle de logs transitorios
datetime           g_lastScalpBlockLog[];
string             g_cacheRegime[];
string             g_cacheRating[];
string             g_cacheSmc[];
string             g_cacheCrt[];
datetime           g_lastDashUpdate = 0;

//--- Inicialización diferida por símbolo: al arrancar en un servidor, el
//--- terminal puede no estar conectado todavía y los símbolos no existen aún.
bool               g_symReady[];
datetime           g_lastInitTry = 0;

//+------------------------------------------------------------------+
//| Intenta dejar operativo un símbolo (selección + indicadores).     |
//| Devuelve true si quedó listo. Se reintenta desde el timer hasta   |
//| que el terminal esté conectado y el símbolo exista.               |
//+------------------------------------------------------------------+
//--- ¿El símbolo está en la lista de scalping?
bool IsScalpSymbol(const string symbol)
  {
   if(!InpEnableScalp)
      return false;
   string parts[];
   int n = StringSplit(InpScalpSymbols, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == symbol)
         return true;
     }
   return false;
  }

//--- Ventana horaria del scalping. InpScalpStart/End siguen siendo HORA
//--- DEL SERVIDOR (se eligieron para esquivar el rollover del broker),
//--- asi que el corte del viernes hay que traducirlo: viene expresado en
//--- la zona en que se define la sesion, que puede ser Nueva York.
bool ScalpSessionOK(const datetime now)
  {
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
      return false;
   if(dt.hour < InpScalpStart || dt.hour >= InpScalpEnd)
      return false;
   if(dt.day_of_week == 5 && dt.hour >= g_session.SessionHourToServerHour(InpFridayLastEntry))
      return false;                       // viernes: sin scalps tarde
   return true;
  }

bool TryInitSymbol(const int i)
  {
   if(g_symReady[i])
      return true;

   string s = g_symbols[i];
   if(!SymbolSelect(s, true))
      return false;
   if(SymbolInfoDouble(s, SYMBOL_POINT) <= 0.0)
      return false;                       // aún sin especificación del símbolo

   if(g_hAtrM15[i] == INVALID_HANDLE)
      g_hAtrM15[i] = iATR(s, PERIOD_M15, 14);

   if(!g_tvM15[i].Init(s, PERIOD_M15) || !g_tvH1[i].Init(s, PERIOD_H1) ||
      !g_regime[i].Init(s, InpAdxTrend, InpSqueezeRatio) ||
      !g_trend[i].Init(s, InpAtrSlMult) ||
      !g_breakout[i].Init(s, InpAsiaStart, InpAsiaEnd, InpBreakEnd,
                          InpMaxRangeAtrMult, InpAtrSlMult) ||
      g_hAtrM15[i] == INVALID_HANDLE)
      return false;

   if(InpEnableSmc &&
      !g_smc[i].Init(s, InpSmcFractal, InpSmcLookback, InpSmcMaxAgeBars,
                     InpSmcDisplacement, InpSmcSlBufferAtr, InpSmcMaxSlAtr,
                     InpSmcRequireHtf, InpSmcRequireSweep, InpSmcRequireDisc,
                     InpSmcNeedRejection, InpSmcUseFvg, InpSmcAllowChoppy))
      return false;

   if(InpEnableCrt &&
      !g_crt[i].Init(s, InpCrtTimeframe, InpCrtMode, InpCrtMinRangeAtr,
                     InpCrtMaxRangeAtr, InpCrtMaxPurgePct, InpCrtMinRR,
                     InpCrtSlBufferAtr, InpCrtRequireEq, InpCrtNeedRejection,
                     InpCrtFollowRegime))
      return false;

   //--- Estrategia de scalping (solo símbolos habilitados)
   if(IsScalpSymbol(s) && CheckPointer(g_scalp[i]) != POINTER_DYNAMIC)
     {
      g_scalp[i] = new CScalpStrategy();
      if(!g_scalp[i].Init(s, InpScalpAtrMult, InpScalpRsiBuy, InpScalpRsiSell))
        {
         delete g_scalp[i];
         g_scalp[i] = NULL;
         return false;
        }
     }

   g_symReady[i] = true;
   g_cacheRegime[i] = "cargando historia...";
   g_cacheRating[i] = "cargando historia...";
   g_cacheSmc[i]    = (InpEnableSmc ? "cargando historia..." : "desactivado");
   g_cacheCrt[i]    = (InpEnableCrt ? "cargando historia..." : "desactivado");
   g_notifier.Log(s + ": indicadores listos, operativo.");
   return true;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Parsear símbolos
   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   if(n < 1)
     {
      Print("[ATLAS] ERROR: InpSymbols vacio.");
      return INIT_PARAMETERS_INCORRECT;
     }
   ArrayResize(g_symbols, n);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      g_symbols[i] = s;
     }

   //--- Módulos globales
   g_notifier.Init(InpEnablePush);
   g_session.Init(InpSessionStart, InpSessionEnd, InpFridayLastEntry, InpFridayClose,
                  InpMaxSpreadGold, InpMaxSpreadEur, InpMaxSpreadIndex,
                  InpSessionInNY, InpServerGmtOffset);
   g_risk.Init(InpRiskPct, InpDailyLossPct, InpMaxDrawdownPct, InpMaxTotalRiskPct,
               InpMaxTradesPerDay, InpMaxPositions, InpResetKillSwitch,
               GetPointer(g_notifier), g_symbols);
   g_trade.Init(InpDeviationPoints, InpRR, InpBeTriggerR, InpPartialR, InpTrailAtrMult,
                GetPointer(g_notifier));
   g_news.Init(InpNewsBlockMin, InpNewsKeywords, GetPointer(g_notifier));
   g_dash.Init();

   //--- Módulos por símbolo
   ArrayResize(g_tvM15, n);
   ArrayResize(g_tvH1, n);
   ArrayResize(g_regime, n);
   ArrayResize(g_trend, n);
   ArrayResize(g_breakout, n);
   ArrayResize(g_scalp, n);
   ArrayResize(g_smc, n);
   ArrayResize(g_crt, n);
   ArrayResize(g_hAtrM15, n);
   ArrayResize(g_lastM15, n);
   ArrayResize(g_lastM1, n);
   ArrayResize(g_lastScalpOpen, n);
   ArrayResize(g_lastRetryLog, n);
   ArrayResize(g_lastScalpBlockLog, n);
   ArrayResize(g_cacheRegime, n);
   ArrayResize(g_cacheRating, n);
   ArrayResize(g_cacheSmc, n);
   ArrayResize(g_cacheCrt, n);
   ArrayResize(g_symReady, n);

   for(int i = 0; i < n; i++)
     {
      g_tvM15[i]    = new CTVRating();
      g_tvH1[i]     = new CTVRating();
      g_regime[i]   = new CRegimeDetector();
      g_trend[i]    = new CTrendStrategy();
      g_breakout[i] = new CBreakoutStrategy();
      g_scalp[i]    = NULL;
      g_smc[i]      = new CSmcStrategy();
      g_crt[i]      = new CCrtStrategy();
      g_hAtrM15[i]  = INVALID_HANDLE;
      g_lastM15[i]  = 0;
      g_lastM1[i]   = 0;
      g_lastScalpOpen[i] = 0;
      g_lastRetryLog[i]  = 0;
      g_lastScalpBlockLog[i] = 0;
      g_symReady[i] = false;
      g_cacheRegime[i] = "esperando conexion...";
      g_cacheRating[i] = "esperando conexion...";
      g_cacheSmc[i]    = (InpEnableSmc ? "esperando conexion..." : "desactivado");
      g_cacheCrt[i]    = (InpEnableCrt ? "esperando conexion..." : "desactivado");
      TryInitSymbol(i);          // si el terminal aún no conectó, se reintenta
     }

   //--- Re-adoptar posiciones tras reinicio
   g_trade.Reconcile();

   EventSetTimer(1);
   g_notifier.Log(StringFormat(
      "ATLAS EA iniciado. Simbolos: %s | Riesgo %.1f%%/op | Limite diario %.1f%% | Kill switch %.0f%%",
      InpSymbols, InpRiskPct, InpDailyLossPct, InpMaxDrawdownPct));
   if(InpEnableSmc)
      g_notifier.Log(StringFormat(
         "Smart Money ACTIVO | fractal %d | H1 a favor: %s | barrido exigido: %s | descuento/premium: %s | lateral: %s | confluencia TV: %s",
         InpSmcFractal, (InpSmcRequireHtf ? "si" : "no"), (InpSmcRequireSweep ? "si" : "no"),
         (InpSmcRequireDisc ? "si" : "no"), (InpSmcAllowChoppy ? "si" : "no"),
         (InpSmcTvFilter == 0 ? "ninguna" : (InpSmcTvFilter == 1 ? "solo H1" : "M15+H1"))));
   if(InpSessionInNY)
      g_notifier.Log(StringFormat(
         "Sesion NUEVA YORK %02d-%02dh = servidor %02d-%02dh = tu hora (UTC%+d) %02d-%02dh | servidor detectado UTC%+d | horario de verano EE.UU.: %s",
         InpSessionStart, InpSessionEnd,
         g_session.SessionHourToServerHour(InpSessionStart),
         g_session.SessionHourToServerHour(InpSessionEnd),
         InpLocalGmtOffset,
         g_session.SessionHourToLocalHour(InpSessionStart, InpLocalGmtOffset),
         g_session.SessionHourToLocalHour(InpSessionEnd, InpLocalGmtOffset),
         g_session.ServerOffsetSec() / 3600,
         (IsUsDst((datetime)((long)TimeTradeServer() - (long)g_session.ServerOffsetSec())) ? "si" : "no")));
   else
      g_notifier.Log(StringFormat("Sesion en hora del SERVIDOR %02d-%02dh",
                                  InpSessionStart, InpSessionEnd));
   if(InpEnableCrt)
      g_notifier.Log(StringFormat(
         "CRT ACTIVO | vela-rango %s | modo %s | purga max %.0f%% del rango | recorrido min %.1fR | premium/descuento: %s | sigue al regimen: %s",
         EnumToString(InpCrtTimeframe), (InpCrtMode == 1 ? "confirmado" : "en vivo"),
         InpCrtMaxPurgePct, InpCrtMinRR, (InpCrtRequireEq ? "si" : "no"),
         (InpCrtFollowRegime ? "si" : "no")));
   if(InpEnableScalp)
      g_notifier.Log(StringFormat(
         "Scalping ACTIVO en %s | Riesgo %.1f%%/scalp | RR %.1f | BE %.1fR | max %d/dia | hold %d min | sesion %02d-%02dh server",
         InpScalpSymbols, InpScalpRiskPct, InpScalpRR, InpScalpBeR,
         InpScalpMaxPerDay, InpScalpHoldMin, InpScalpStart, InpScalpEnd));
   if(TerminalInfoInteger(TERMINAL_VPS))
      g_notifier.Notify("Corriendo en VPS 24/5 (sin panel visual). El pico de equity del kill switch arranca desde el equity actual.");
   if(g_risk.KillSwitchLatched())
      g_notifier.Critical("ATENCION: kill switch ACTIVO. El bot no opera hasta resetear (InpResetKillSwitch=true).");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < ArraySize(g_symbols); i++)
     {
      if(CheckPointer(g_tvM15[i])    == POINTER_DYNAMIC) { g_tvM15[i].Release();    delete g_tvM15[i]; }
      if(CheckPointer(g_tvH1[i])     == POINTER_DYNAMIC) { g_tvH1[i].Release();     delete g_tvH1[i]; }
      if(CheckPointer(g_regime[i])   == POINTER_DYNAMIC) { g_regime[i].Release();   delete g_regime[i]; }
      if(CheckPointer(g_trend[i])    == POINTER_DYNAMIC) { g_trend[i].Release();    delete g_trend[i]; }
      if(CheckPointer(g_breakout[i]) == POINTER_DYNAMIC) { g_breakout[i].Release(); delete g_breakout[i]; }
      if(CheckPointer(g_scalp[i])    == POINTER_DYNAMIC) { g_scalp[i].Release();    delete g_scalp[i]; }
      if(CheckPointer(g_smc[i])      == POINTER_DYNAMIC) { g_smc[i].Release();      delete g_smc[i]; }
      if(CheckPointer(g_crt[i])      == POINTER_DYNAMIC) { g_crt[i].Release();      delete g_crt[i]; }
      if(g_hAtrM15[i] != INVALID_HANDLE)
         IndicatorRelease(g_hAtrM15[i]);
     }
   g_dash.Destroy();
   Print("[ATLAS] EA detenido (reason ", reason, ").");
  }

//+------------------------------------------------------------------+
double AtrM15(const int idx)
  {
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(g_hAtrM15[idx], 0, 1, 1, arr) != 1)
      return 0.0;
   return arr[0];
  }

//+------------------------------------------------------------------+
//| El tester no siempre dispara OnTimer en cada tick simulado:      |
//| corremos la misma lógica desde OnTick como respaldo.             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(MQLInfoInteger(MQL_TESTER))
      RunCycle();
  }

void OnTimer()
  {
   RunCycle();
  }

//+------------------------------------------------------------------+
void RunCycle()
  {
   int n = ArraySize(g_symbols);

   //--- 0) Kill switch: primero, siempre
   if(g_risk.KillSwitchTriggered())
      g_trade.CloseAllOwn("kill switch por drawdown maximo");
   bool killed = g_risk.KillSwitchLatched();

   //--- 1) Rollover diario (y fijar la referencia si la cuenta recién sincronizó)
   g_risk.EnsureBaseline();
   g_risk.CheckNewDay();

   //--- 2) Viernes: cierre total pre-weekend
   if(!killed && g_session.MustCloseAll())
      g_trade.CloseAllOwn("cierre previo al fin de semana");

   //--- 3) Símbolos que aún no quedaron operativos (terminal recién conectado):
   //---    reintentar cada 20 s hasta lograrlo.
   datetime nowTs = TimeCurrent();
   if(nowTs - g_lastInitTry >= 20)
     {
      g_lastInitTry = nowTs;
      for(int i = 0; i < n; i++)
         if(!g_symReady[i])
            TryInitSymbol(i);
     }

   //--- 4) Gestión de posiciones abiertas (BE, parcial, trailing)
   for(int i = 0; i < n; i++)
      if(g_symReady[i])
        {
         g_trade.Manage(g_symbols[i], AtrM15(i));
         if(CheckPointer(g_scalp[i]) == POINTER_DYNAMIC)
            g_trade.ManageScalp(g_symbols[i], InpScalpBeR, InpScalpHoldMin * 60);
        }

   //--- 5) Señales en vela M15 nueva. Si el símbolo todavía no tiene
   //---    datos (reconexión), NO se consume la vela: se reintenta.
   for(int i = 0; i < n; i++)
     {
      if(!g_symReady[i])
         continue;
      datetime prevBar = g_lastM15[i];
      if(!NewM15Bar(g_symbols[i], g_lastM15[i]))
         continue;
      if(!EvaluateSymbol(i))
         g_lastM15[i] = prevBar;    // condición transitoria: reintentar
     }

   //--- 5b) Scalping: señales en vela M1 nueva
   if(!killed && InpEnableScalp)
      for(int i = 0; i < n; i++)
        {
         if(!g_symReady[i] || CheckPointer(g_scalp[i]) != POINTER_DYNAMIC)
            continue;
         if(!NewBar(g_symbols[i], PERIOD_M1, g_lastM1[i]))
            continue;
         EvaluateScalp(i);
        }

   //--- 6) Dashboard cada 5 s
   datetime now = TimeCurrent();
   if(now - g_lastDashUpdate >= 5)
     {
      g_lastDashUpdate = now;
      UpdateDashboard();
     }
  }

//--- Log de condiciones transitorias, acotado a 1 por minuto por símbolo
void LogTransient(const int idx, const string msg)
  {
   datetime now = TimeCurrent();
   if(now - g_lastRetryLog[idx] < 60)
      return;
   g_lastRetryLog[idx] = now;
   g_notifier.Log(msg);
  }

//+------------------------------------------------------------------+
//| Confluencia con el rating TradingView según el nivel exigido:    |
//| 0 = ninguna · 1 = solo H1 (sesgo mayor) · 2 = M15 y H1           |
//+------------------------------------------------------------------+
bool TvConfirms(const ESignalDir dir, const ERating rM15, const ERating rH1, const int level)
  {
   if(level <= 0)
      return true;
   if(dir == SIGNAL_BUY)
     {
      if(rH1 < RATING_BUY)
         return false;
      return (level < 2 || rM15 >= RATING_BUY);
     }
   if(dir == SIGNAL_SELL)
     {
      if(rH1 > RATING_SELL)
         return false;
      return (level < 2 || rM15 <= RATING_SELL);
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Evalúa señales swing en la vela M15. Devuelve false SOLO ante    |
//| condiciones transitorias (sin datos/cargando) para reintentar la |
//| misma vela; true cuando la decisión fue definitiva.              |
//+------------------------------------------------------------------+
bool EvaluateSymbol(const int idx)
  {
   string symbol = g_symbols[idx];

   //--- Datos listos?
   //--- Solo se exige historia a los modulos ENCENDIDOS: una estrategia
   //--- apagada (p.ej. tendencia, que necesita 200 velas de H1) no debe
   //--- frenar el arranque de las demas.
   if(!g_tvM15[idx].Ready() || !g_tvH1[idx].Ready() || !g_regime[idx].Ready() ||
      (InpEnableTrend    && !g_trend[idx].Ready())    ||
      (InpEnableBreakout && !g_breakout[idx].Ready()) ||
      (InpEnableSmc      && !g_smc[idx].Ready())      ||
      (InpEnableCrt      && !g_crt[idx].Ready()))
     {
      LogTransient(idx, symbol + ": historia/indicadores aun cargando, reintento en esta vela.");
      return false;
     }

   //--- Régimen y ratings (siempre, para dashboard)
   ERegime regime  = g_regime[idx].Detect();
   ERating rM15    = g_tvM15[idx].Get();
   ERating rH1     = g_tvH1[idx].Get();
   g_cacheRegime[idx] = RegimeToString(regime);
   g_cacheRating[idx] = "M15 " + RatingToString(rM15) + " | H1 " + RatingToString(rH1);

   //--- Gates de contexto
   if(g_session.MustCloseAll())
      return true;
   if(!g_session.EntryAllowedNow())
     {
      g_notifier.Log(symbol + ": fuera de sesion, sin entradas.");
      return true;
     }
   if(!g_session.SpreadOK(symbol))
     {
      long sp = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(sp <= 0)
        {
         LogTransient(idx, symbol + ": sin datos de precio aun (reconectando), reintento en esta vela.");
         return false;                 // no perder la vela: reintentar
        }
      g_notifier.Log(StringFormat("%s: spread %d pts excede el limite %d, sin entradas.",
                                  symbol, sp, g_session.MaxSpreadFor(symbol)));
      return true;
     }
   if(g_news.IsBlocked())
     {
      g_notifier.Log(symbol + ": pausa por noticia (" + g_news.BlockingEventName() + ")");
      return true;
     }
   string blockReason = "";
   if(!g_risk.CanOpen(symbol, blockReason))
     {
      g_notifier.Log(symbol + ": bloqueado por riesgo — " + blockReason);
      return true;
     }

   //--- Orden de prioridad: primero los dos modelos estructurales
   //--- (los más selectivos, con su propio contexto multi-temporal) y
   //--- recién después la estrategia que corresponda al régimen.
   //--- Los estados se refrescan siempre, dispare o no, para el panel.
   SSignal sig;
   sig.dir = SIGNAL_NONE;
   bool fromBreakout = false;
   bool fromSmc      = false;
   bool fromCrt      = false;

   if(InpEnableSmc)
     {
      sig = g_smc[idx].Check(regime);
      g_cacheSmc[idx] = g_smc[idx].Note();
      fromSmc = (sig.dir != SIGNAL_NONE);
     }

   if(InpEnableCrt)
     {
      SSignal crtSig = g_crt[idx].Check(regime);
      g_cacheCrt[idx] = g_crt[idx].Note();
      if(sig.dir == SIGNAL_NONE && crtSig.dir != SIGNAL_NONE)
        {
         sig     = crtSig;
         fromCrt = true;
        }
     }

   if(sig.dir == SIGNAL_NONE)
     {
      if((regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN) && InpEnableTrend)
         sig = g_trend[idx].Check(regime);
      else if(regime == REGIME_SQUEEZE && InpEnableBreakout)
        {
         sig = g_breakout[idx].Check(regime);
         fromBreakout = (sig.dir != SIGNAL_NONE);
        }
     }

   if(sig.dir == SIGNAL_NONE)
      return true;

   //--- Confluencia con el rating TradingView.
   //--- SMC y CRT usan su propia escala (InpSmcTvFilter / InpCrtTvFilter):
   //--- un CHoCH y una purga de liquidez son reversiones tempranas, y los
   //--- indicadores del rating van con retraso, así que exigirles
   //--- confirmación anularía casi todos esos setups.
   int tvLevel = 2;
   if(fromSmc)
      tvLevel = InpSmcTvFilter;
   else if(fromCrt)
      tvLevel = InpCrtTvFilter;
   if(!TvConfirms(sig.dir, rM15, rH1, tvLevel))
     {
      g_notifier.Log(symbol + ": senal " + (sig.dir == SIGNAL_BUY ? "COMPRA" : "VENTA") +
                     " descartada, rating TV no confirma (" + g_cacheRating[idx] + ")");
      return true;
     }

   //--- Sizing por riesgo
   double entry = (sig.dir == SIGNAL_BUY ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(symbol, SYMBOL_BID));
   double lots = g_risk.CalcLots(symbol, entry, sig.sl_price);
   if(lots <= 0.0)
      return true;

   //--- Ejecutar
   if(g_trade.Open(symbol, sig, lots))
     {
      g_risk.RegisterOpen(symbol);
      if(fromBreakout)
         g_breakout[idx].MarkTraded();
      if(fromSmc)
         g_smc[idx].MarkTraded();          // la zona queda consumida
      if(fromCrt)
         g_crt[idx].MarkTraded();          // el rango queda consumido
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Evalúa un scalp en la vela M1. Gates silenciosos (M1 es muy      |
//| frecuente para loguear cada rechazo); los bloqueos de riesgo se  |
//| loguean acotados a 1 por minuto.                                 |
//+------------------------------------------------------------------+
void EvaluateScalp(const int idx)
  {
   string symbol = g_symbols[idx];

   if(!g_scalp[idx].Ready())
      return;
   if(g_session.MustCloseAll())
      return;
   if(!ScalpSessionOK(TimeTradeServer()))
      return;
   if(!g_session.SpreadOK(symbol))
      return;
   if(g_news.IsBlocked())
      return;

   //--- Cooldown entre scalps
   if(TimeCurrent() - g_lastScalpOpen[idx] < InpScalpCooldownMin * 60)
      return;

   string blockReason = "";
   if(!g_risk.CanOpenScalp(symbol, InpScalpMaxPerDay, InpScalpRiskPct, blockReason))
     {
      datetime now = TimeCurrent();
      if(now - g_lastScalpBlockLog[idx] >= 60)
        {
         g_lastScalpBlockLog[idx] = now;
         g_notifier.Log(symbol + ": scalp bloqueado por riesgo — " + blockReason);
        }
      return;
     }

   SSignal sig = g_scalp[idx].Check();
   if(sig.dir == SIGNAL_NONE)
      return;

   double entry = (sig.dir == SIGNAL_BUY ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(symbol, SYMBOL_BID));
   double lots = g_risk.CalcLots(symbol, entry, sig.sl_price, InpScalpRiskPct);
   if(lots <= 0.0)
      return;

   if(g_trade.OpenScalp(symbol, sig, lots, InpScalpRR))
     {
      g_risk.RegisterScalpOpen(symbol);
      g_lastScalpOpen[idx] = TimeCurrent();
     }
  }

//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   if(TerminalInfoInteger(TERMINAL_VPS))
      return;                          // en VPS no hay pantalla que dibujar

   int n = ArraySize(g_symbols);
   string regimes[], ratings[], smc[], crt[], positions[];
   int trades[];
   ArrayResize(regimes, n);
   ArrayResize(ratings, n);
   ArrayResize(smc, n);
   ArrayResize(crt, n);
   ArrayResize(positions, n);
   ArrayResize(trades, n);
   for(int i = 0; i < n; i++)
     {
      regimes[i]   = g_cacheRegime[i];
      ratings[i]   = g_cacheRating[i];
      smc[i]       = g_cacheSmc[i];
      crt[i]       = g_cacheCrt[i];
      positions[i] = g_trade.PositionInfo(g_symbols[i]);
      trades[i]    = g_risk.TradesToday(g_symbols[i]);
     }

   string state = "OPERANDO";
   color  stateColor = clrLime;
   if(g_risk.KillSwitchLatched())
     { state = "KILL SWITCH — bot apagado"; stateColor = clrRed; }
   else if(g_session.MustCloseAll())
     { state = "CIERRE PRE-WEEKEND"; stateColor = clrOrange; }
   else if(g_risk.DailyLossHit())
     { state = "LIMITE DIARIO ALCANZADO — sin entradas hasta manana"; stateColor = clrOrange; }
   else if(g_news.IsBlocked())
     { state = "PAUSA POR NOTICIA: " + g_news.BlockingEventName(); stateColor = clrOrange; }
   else if(!g_session.EntryAllowedNow())
     { state = "FUERA DE SESION"; stateColor = clrSilver; }

   string sessionLine = StringFormat("%s %02d-%02dh  (servidor %02d-%02dh · vos %02d-%02dh)",
                        (g_session.UsesNewYork() ? "NUEVA YORK" : "SERVIDOR"),
                        InpSessionStart, InpSessionEnd,
                        g_session.SessionHourToServerHour(InpSessionStart),
                        g_session.SessionHourToServerHour(InpSessionEnd),
                        g_session.SessionHourToLocalHour(InpSessionStart, InpLocalGmtOffset),
                        g_session.SessionHourToLocalHour(InpSessionEnd, InpLocalGmtOffset));

   string newsDesc = "";
   datetime newsWhen = 0;
   string newsLine = "";
   if(g_news.NextHighImpact(newsDesc, newsWhen))
      newsLine = newsDesc + " @ " + TimeToString(newsWhen, TIME_DATE | TIME_MINUTES);

   g_dash.Update(state, stateColor,
                 AccountInfoDouble(ACCOUNT_EQUITY), g_risk.DayPnLPct(),
                 g_risk.DrawdownFromPeakPct(), g_risk.OpenRiskPct(),
                 newsLine, sessionLine, g_symbols, regimes, ratings, smc, crt,
                 positions, trades);
  }
