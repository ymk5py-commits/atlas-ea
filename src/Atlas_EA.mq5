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
#include "include/NewsFilter.mqh"
#include "include/Dashboard.mqh"

//=== Inputs ========================================================
input group "General"
input string InpSymbols          = "XAUUSD,EURUSD"; // Simbolos (separados por coma)
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
input bool   InpEnableTrend      = true;            // Estrategia de tendencia (pullback)
input bool   InpEnableBreakout   = true;            // Estrategia de ruptura asiatica
input double InpAdxTrend         = 22.0;            // ADX H1 minimo para tendencia
input double InpSqueezeRatio     = 0.75;            // Compresion: ancho BB < ratio x prom
input double InpAtrSlMult        = 1.5;             // Stop loss: multiplicador ATR M15
input double InpMaxRangeAtrMult  = 1.2;             // Rango asiatico max (x ATR H1)

input group "Sesion y noticias (hora del SERVIDOR)"
input int    InpSessionStart     = 8;               // Inicio ventana de entradas
input int    InpSessionEnd       = 20;              // Fin ventana de entradas
input int    InpFridayLastEntry  = 18;              // Viernes: ultima hora de entrada
input int    InpFridayClose      = 21;              // Viernes: cerrar todo desde
input long   InpMaxSpreadGold    = 400;             // Spread max XAUUSD (points)
input long   InpMaxSpreadEur     = 20;              // Spread max EURUSD (points)
input int    InpNewsBlockMin     = 30;              // Bloqueo +/- minutos por noticia
input int    InpAsiaStart        = 1;               // Rango asiatico: hora inicio
input int    InpAsiaEnd          = 8;               // Rango asiatico: hora fin
input int    InpBreakEnd         = 15;              // Fin ventana de ruptura

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
int                g_hAtrM15[];

datetime           g_lastM15[];
string             g_cacheRegime[];
string             g_cacheRating[];
datetime           g_lastDashUpdate = 0;

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
      if(!SymbolSelect(s, true))
        {
         Print("[ATLAS] ERROR: simbolo no disponible en este broker: ", s,
               " — revisar el nombre exacto (ej. XAUUSD vs GOLD).");
         return INIT_PARAMETERS_INCORRECT;
        }
     }

   //--- Módulos globales
   g_notifier.Init(InpEnablePush);
   g_session.Init(InpSessionStart, InpSessionEnd, InpFridayLastEntry, InpFridayClose,
                  InpMaxSpreadGold, InpMaxSpreadEur);
   g_risk.Init(InpRiskPct, InpDailyLossPct, InpMaxDrawdownPct, InpMaxTotalRiskPct,
               InpMaxTradesPerDay, InpMaxPositions, InpResetKillSwitch,
               GetPointer(g_notifier), g_symbols);
   g_trade.Init(InpDeviationPoints, InpRR, InpBeTriggerR, InpPartialR, InpTrailAtrMult,
                GetPointer(g_notifier));
   g_news.Init(InpNewsBlockMin, GetPointer(g_notifier));
   g_dash.Init();

   //--- Módulos por símbolo
   ArrayResize(g_tvM15, n);
   ArrayResize(g_tvH1, n);
   ArrayResize(g_regime, n);
   ArrayResize(g_trend, n);
   ArrayResize(g_breakout, n);
   ArrayResize(g_hAtrM15, n);
   ArrayResize(g_lastM15, n);
   ArrayResize(g_cacheRegime, n);
   ArrayResize(g_cacheRating, n);

   for(int i = 0; i < n; i++)
     {
      string s = g_symbols[i];
      g_tvM15[i]    = new CTVRating();
      g_tvH1[i]     = new CTVRating();
      g_regime[i]   = new CRegimeDetector();
      g_trend[i]    = new CTrendStrategy();
      g_breakout[i] = new CBreakoutStrategy();
      g_hAtrM15[i]  = iATR(s, PERIOD_M15, 14);
      g_lastM15[i]  = 0;
      g_cacheRegime[i] = "cargando datos...";
      g_cacheRating[i] = "cargando datos...";

      if(!g_tvM15[i].Init(s, PERIOD_M15) || !g_tvH1[i].Init(s, PERIOD_H1) ||
         !g_regime[i].Init(s, InpAdxTrend, InpSqueezeRatio) ||
         !g_trend[i].Init(s, InpAtrSlMult) ||
         !g_breakout[i].Init(s, InpAsiaStart, InpAsiaEnd, InpBreakEnd,
                             InpMaxRangeAtrMult, InpAtrSlMult) ||
         g_hAtrM15[i] == INVALID_HANDLE)
        {
         Print("[ATLAS] ERROR: no se pudieron crear indicadores para ", s);
         return INIT_FAILED;
        }
     }

   //--- Re-adoptar posiciones tras reinicio
   g_trade.Reconcile();

   EventSetTimer(1);
   g_notifier.Log(StringFormat(
      "ATLAS EA iniciado. Simbolos: %s | Riesgo %.1f%%/op | Limite diario %.1f%% | Kill switch %.0f%%",
      InpSymbols, InpRiskPct, InpDailyLossPct, InpMaxDrawdownPct));
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

   //--- 1) Rollover diario
   g_risk.CheckNewDay();

   //--- 2) Viernes: cierre total pre-weekend
   if(!killed && g_session.MustCloseAll())
      g_trade.CloseAllOwn("cierre previo al fin de semana");

   //--- 3) Gestión de posiciones abiertas (BE, parcial, trailing)
   for(int i = 0; i < n; i++)
      g_trade.Manage(g_symbols[i], AtrM15(i));

   //--- 4) Señales en vela M15 nueva
   for(int i = 0; i < n; i++)
     {
      if(!NewM15Bar(g_symbols[i], g_lastM15[i]))
         continue;
      EvaluateSymbol(i);
     }

   //--- 5) Dashboard cada 5 s
   datetime now = TimeCurrent();
   if(now - g_lastDashUpdate >= 5)
     {
      g_lastDashUpdate = now;
      UpdateDashboard();
     }
  }

//+------------------------------------------------------------------+
void EvaluateSymbol(const int idx)
  {
   string symbol = g_symbols[idx];

   //--- Datos listos?
   if(!g_tvM15[idx].Ready() || !g_tvH1[idx].Ready() ||
      !g_regime[idx].Ready() || !g_trend[idx].Ready() || !g_breakout[idx].Ready())
     {
      g_notifier.Log(symbol + ": historia/indicadores aun cargando, salteo esta vela.");
      return;
     }

   //--- Régimen y ratings (siempre, para dashboard)
   ERegime regime  = g_regime[idx].Detect();
   ERating rM15    = g_tvM15[idx].Get();
   ERating rH1     = g_tvH1[idx].Get();
   g_cacheRegime[idx] = RegimeToString(regime);
   g_cacheRating[idx] = "M15 " + RatingToString(rM15) + " | H1 " + RatingToString(rH1);

   //--- Gates de contexto
   if(g_session.MustCloseAll())
      return;
   if(!g_session.EntryAllowed(symbol))
     {
      g_notifier.Log(symbol + ": fuera de sesion o spread alto, sin entradas.");
      return;
     }
   if(g_news.IsBlocked())
     {
      g_notifier.Log(symbol + ": pausa por noticia (" + g_news.BlockingEventName() + ")");
      return;
     }
   string blockReason = "";
   if(!g_risk.CanOpen(symbol, blockReason))
     {
      g_notifier.Log(symbol + ": bloqueado por riesgo — " + blockReason);
      return;
     }

   //--- Señal según régimen
   SSignal sig;
   sig.dir = SIGNAL_NONE;
   bool fromBreakout = false;

   if((regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN) && InpEnableTrend)
      sig = g_trend[idx].Check(regime);
   else if(regime == REGIME_SQUEEZE && InpEnableBreakout)
     {
      sig = g_breakout[idx].Check(regime);
      fromBreakout = (sig.dir != SIGNAL_NONE);
     }

   if(sig.dir == SIGNAL_NONE)
      return;

   //--- Confluencia con el rating TradingView (M15 y H1 a favor)
   if(sig.dir == SIGNAL_BUY && !(rM15 >= RATING_BUY && rH1 >= RATING_BUY))
     {
      g_notifier.Log(symbol + ": senal COMPRA descartada, rating TV no confirma (" +
                     g_cacheRating[idx] + ")");
      return;
     }
   if(sig.dir == SIGNAL_SELL && !(rM15 <= RATING_SELL && rH1 <= RATING_SELL))
     {
      g_notifier.Log(symbol + ": senal VENTA descartada, rating TV no confirma (" +
                     g_cacheRating[idx] + ")");
      return;
     }

   //--- Sizing por riesgo
   double entry = (sig.dir == SIGNAL_BUY ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(symbol, SYMBOL_BID));
   double lots = g_risk.CalcLots(symbol, entry, sig.sl_price);
   if(lots <= 0.0)
      return;

   //--- Ejecutar
   if(g_trade.Open(symbol, sig, lots))
     {
      g_risk.RegisterOpen(symbol);
      if(fromBreakout)
         g_breakout[idx].MarkTraded();
     }
  }

//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;

   int n = ArraySize(g_symbols);
   string regimes[], ratings[], positions[];
   int trades[];
   ArrayResize(regimes, n);
   ArrayResize(ratings, n);
   ArrayResize(positions, n);
   ArrayResize(trades, n);
   for(int i = 0; i < n; i++)
     {
      regimes[i]   = g_cacheRegime[i];
      ratings[i]   = g_cacheRating[i];
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
   else if(!g_session.EntryAllowedAt(TimeTradeServer()))
     { state = "FUERA DE SESION"; stateColor = clrSilver; }

   string newsDesc = "";
   datetime newsWhen = 0;
   string newsLine = "";
   if(g_news.NextHighImpact(newsDesc, newsWhen))
      newsLine = newsDesc + " @ " + TimeToString(newsWhen, TIME_DATE | TIME_MINUTES);

   g_dash.Update(state, stateColor,
                 AccountInfoDouble(ACCOUNT_EQUITY), g_risk.DayPnLPct(),
                 g_risk.DrawdownFromPeakPct(), g_risk.OpenRiskPct(),
                 newsLine, g_symbols, regimes, ratings, positions, trades);
  }
