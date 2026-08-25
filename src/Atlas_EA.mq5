//+------------------------------------------------------------------+
//| Atlas_EA.mq5 — Bot híbrido adaptativo para XAUUSD + EURUSD.      |
//| Spec: docs/superpowers/specs/2026-08-03-atlas-ea-design.md       |
//|                                                                  |
//| ADVERTENCIA: el trading apalancado puede generar pérdidas.       |
//| Validar SIEMPRE en backtest y cuenta demo antes de dinero real.  |
//+------------------------------------------------------------------+
#property copyright "ATLAS EA — uso personal"
#property version   "2.00"
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
#include "include/RevStrategy.mqh"
#include "include/SmcStrategy.mqh"
#include "include/CrtStrategy.mqh"
#include "include/NewsFilter.mqh"
#include "include/Dashboard.mqh"

//=== Inputs ========================================================
input group "General"
input string InpSymbols          = "XAUUSD,USDJPY,XAGUSD"; // Simbolos (separados por coma)
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

input group "Estrategias — que simbolo opera cual (vacio = ninguno)"
// Cada lista es un subconjunto de InpSymbols. Un simbolo puede llevar varias.
// CARTERA VIGENTE (backtest 2023-2026, 500 USD): oro+USDJPY+PLATA con Smart
// Money = 725.00 (+45.0%, DD 12.3%, 229 trades). En solitario cada uno:
// plata 605.89 (+21.2%, DD 4.9%) - el mejor · oro 561.02 (+12.2%, DD 8.8%)
// · USDJPY 531.84 (+6.4%, DD 9.8%). Descartados: GBPUSD (-13.6%), USDCHF
// (+5.2% con DD 16.5%), EURUSD (nada le sirvio).
// Backtest previo: oro+USDJPY con SMC = 605.88 (+21.2%, DD 13.2%,
// 169 trades) — mejor que el oro solo (561.02, +12.2%, DD 8.8%, 84 trades).
// Otros pares con SMC: USDCHF 526.08 (+5.2%, DD 16.5%) · GBPUSD 432.24 (-13.6%).
// EURUSD sin estrategia: CRT -40.5%, SMC -7.8%, tendencia -0.4%. Fuera.
// Backtest previo: SMC solo en oro = 561.02 (+12.2%, DD 8.8%) ·
// CRT+SMC en oro = 522.63 · CRT solo en oro = 493.74 · CRT en EURUSD = 297.26
// (-40.5%). CRT resta en ambos instrumentos, asi que queda apagado. El euro
// no opera hasta encontrarle una estrategia con ventaja demostrada.
input string InpCrtSymbols       = "";              // Simbolos con Candle Range Theory (apagado: resta en backtest)
input string InpSmcSymbols       = "XAUUSD,USDJPY,XAGUSD"; // Simbolos con Smart Money
input string InpTrendSymbols     = "";              // Simbolos con tendencia (pullback)
input string InpBreakoutSymbols  = "";              // Simbolos con ruptura asiatica
input string InpRevSymbols       = "";              // Simbolos con reversion M1 (metodo manual del dueno)
input double InpAdxTrend         = 22.0;            // ADX H1 minimo para tendencia
input double InpSqueezeRatio     = 0.75;            // Compresion: ancho BB < ratio x prom
input double InpAtrSlMult        = 1.5;             // Stop loss: multiplicador ATR M15
input double InpMaxRangeAtrMult  = 1.2;             // Rango asiatico max (x ATR H1)

input group "Smart Money (estructura + Order Block / FVG)"
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

input group "Sesiones — que simbolo opera en que ventana"
// Las horas van en la HORA DE CADA PLAZA; el bot convierte solo, con el
// horario de verano que corresponda a cada una. Un simbolo que no figure
// en ninguna lista opera en hora del SERVIDOR con la ventana de respaldo.
input string InpNewYorkSymbols   = "USDJPY";        // Simbolos que operan en la sesion de NUEVA YORK
input int    InpNyStart          = 8;               // Nueva York: hora de inicio
input int    InpNyEnd            = 13;              // Nueva York: hora de fin (13h = fin del solape con Londres)
input string InpLondonSymbols    = "XAUUSD,XAGUSD"; // Simbolos que operan en la sesion de LONDRES
input int    InpLonStart         = 8;               // Londres: hora de inicio
input int    InpLonEnd           = 17;              // Londres: hora de fin
input int    InpSrvStart         = 8;               // Respaldo (hora del servidor): inicio
input int    InpSrvEnd           = 20;              // Respaldo (hora del servidor): fin
input int    InpFridayEntryCutH  = 2;               // Viernes: sin entradas las ultimas N horas de la sesion
input int    InpFridayCloseCutH  = 1;               // Viernes: cerrar todo N horas antes del fin de sesion
input int    InpServerGmtOffset  = 99;              // Desfase del servidor vs UTC en horas; 99 = detectar solo
input int    InpLocalGmtOffset   = -3;              // Tu huso horario (solo para mostrar horas en el panel). Paraguay = -3
// El limite va en la unidad natural de cada instrumento, NO en "points":
// los points dependen de con cuantos decimales cotice cada broker (el oro
// con 2 o 3, los pares con 4 o 5), asi que el mismo numero puede quedar
// diez veces mas flojo sin avisar. El bot lo convierte a points solo.
input double InpMaxSpreadGold    = 50.0;            // Spread max en ORO (centavos de dolar; 50 = 0.50 USD)
input double InpMaxSpreadForex   = 2.0;             // Spread max en PARES (pips)
input double InpMaxSpreadMetal   = 5.0;             // Spread max en PLATA/PLATINO (centavos)
input double InpMaxSpreadIndex   = 5.0;             // Spread max en INDICES (puntos del indice)
input int    InpNewsBlockMin     = 30;              // Bloqueo +/- minutos por noticia
input string InpNewsCurrencies   = "USD,EUR,GBP";  // Monedas cuyo calendario se vigila
// Vacio = pausar ante CUALQUIER evento de alto impacto. Es el default y el
// mas seguro: filtrar por nombre depende de como los escriba el calendario
// de MT5 (y del idioma del terminal), asi que una lista puede no matchear
// nada y dejar pasar justo el dato que mueve el mercado.
input string InpNewsKeywords     = "";
input int    InpAsiaStart        = 1;               // Rango asiatico: hora inicio
input int    InpAsiaEnd          = 8;               // Rango asiatico: hora fin
input int    InpBreakEnd         = 15;              // Fin ventana de ruptura

input group "Reversion M1 (bajada fuerte -> compra / subida fuerte -> venta)"
input int    InpRevLookback      = 3;      // Velas M1 que forman el tramo
input double InpRevImpulseAtr    = 2.0;    // Impulso minimo del tramo (x ATR M1)
input double InpRevRsiLow        = 25.0;   // RSI7 maximo para COMPRAR (sobreventa)
input double InpRevRsiHigh       = 75.0;   // RSI7 minimo para VENDER (sobrecompra)
input double InpRevTargetPct     = 50.0;   // % del tramo que se busca recuperar
input double InpRevSlAtr         = 1.0;    // Colchon del stop tras el extremo (x ATR M1)
input double InpRevMaxSlAtr      = 4.0;    // Descartar si el stop supera (x ATR M1)
input double InpRevRiskPct       = 1.0;    // Riesgo por operacion de reversion (%)
input int    InpRevMaxPerDay     = 15;     // Max operaciones/dia por simbolo
input int    InpRevHoldMin       = 8;      // Cierre por tiempo (minutos) — el metodo usa 5-10
input int    InpRevCooldownMin   = 3;      // Espera minima entre operaciones (min)
input double InpRevBeR           = 0.5;    // Break-even al llegar a +R

input group "Scalping (estilo manual, hora del SERVIDOR)"
input string InpScalpSymbols     = "";              // Simbolos con scalping M1 (vacio = ninguno)
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
CSessionFilter    *g_session[];    // una ventana por simbolo
CRiskManager       g_risk;
CTradeManager      g_trade;
CNewsFilter        g_news;
CDashboard         g_dash;

CTVRating         *g_tvM15[];
CTVRating         *g_tvH1[];
CRegimeDetector   *g_regime[];
CTrendStrategy    *g_trend[];
CBreakoutStrategy *g_breakout[];
CScalpStrategy    *g_scalp[];
CRevStrategy      *g_rev[];        // NULL si el simbolo no opera reversion
CSmcStrategy      *g_smc[];
CCrtStrategy      *g_crt[];

//--- Que estrategias corre cada simbolo (resuelto en OnInit)
bool               g_useTrend[];
bool               g_useBreakout[];
bool               g_useSmc[];
bool               g_useCrt[];
int                g_hAtrM15[];

datetime           g_lastM15[];
datetime           g_lastM1[];      // tracker de vela M1 (scalping)
datetime           g_lastScalpOpen[];
datetime           g_lastRevOpen[];
datetime           g_lastRevBlockLog[];
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
//--- ¿El símbolo figura en una lista separada por comas? Lista vacía = no.
//--- Es el mismo criterio con el que ya se elegían los símbolos de
//--- scalping, ahora usado para asignar estrategias y sesiones.
bool SymbolInList(const string symbol, const string list)
  {
   if(StringLen(list) == 0)
      return false;
   string parts[];
   int n = StringSplit(list, ',', parts);
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

//--- Plaza en cuya hora se define la ventana de este símbolo.
//--- Precedencia: Nueva York, Londres, y si no figura, hora del servidor.
ESesion SessionZoneFor(const string symbol)
  {
   if(SymbolInList(symbol, InpNewYorkSymbols))
      return SESION_NUEVA_YORK;
   if(SymbolInList(symbol, InpLondonSymbols))
      return SESION_LONDRES;
   return SESION_SERVIDOR;
  }

int SessionStartFor(const ESesion zone)
  {
   if(zone == SESION_NUEVA_YORK) return InpNyStart;
   if(zone == SESION_LONDRES)    return InpLonStart;
   return InpSrvStart;
  }

int SessionEndFor(const ESesion zone)
  {
   if(zone == SESION_NUEVA_YORK) return InpNyEnd;
   if(zone == SESION_LONDRES)    return InpLonEnd;
   return InpSrvEnd;
  }

//--- Ventana horaria del scalping. InpScalpStart/End siguen siendo HORA
//--- DEL SERVIDOR (se eligieron para esquivar el rollover del broker),
//--- asi que el corte del viernes hay que traducirlo: viene expresado en
//--- la zona en que se define la sesion, que puede ser Nueva York.
bool ScalpSessionOK(const int idx, const datetime now)
  {
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
      return false;
   if(dt.hour < InpScalpStart || dt.hour >= InpScalpEnd)
      return false;
   int friCut = g_session[idx].SessionHourToServerHour(g_session[idx].FridayLastEntryHour());
   if(dt.day_of_week == 5 && dt.hour >= friCut)
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

   if(g_useSmc[i] &&
      !g_smc[i].Init(s, InpSmcFractal, InpSmcLookback, InpSmcMaxAgeBars,
                     InpSmcDisplacement, InpSmcSlBufferAtr, InpSmcMaxSlAtr,
                     InpSmcRequireHtf, InpSmcRequireSweep, InpSmcRequireDisc,
                     InpSmcNeedRejection, InpSmcUseFvg, InpSmcAllowChoppy))
      return false;

   if(g_useCrt[i] &&
      !g_crt[i].Init(s, InpCrtTimeframe, InpCrtMode, InpCrtMinRangeAtr,
                     InpCrtMaxRangeAtr, InpCrtMaxPurgePct, InpCrtMinRR,
                     InpCrtSlBufferAtr, InpCrtRequireEq, InpCrtNeedRejection,
                     InpCrtFollowRegime))
      return false;

   //--- Estrategia de scalping (solo símbolos habilitados)
   if(SymbolInList(s, InpScalpSymbols) && CheckPointer(g_scalp[i]) != POINTER_DYNAMIC)
     {
      g_scalp[i] = new CScalpStrategy();
      if(!g_scalp[i].Init(s, InpScalpAtrMult, InpScalpRsiBuy, InpScalpRsiSell))
        {
         delete g_scalp[i];
         g_scalp[i] = NULL;
         return false;
        }
     }

   //--- Estrategia de reversion M1 (solo símbolos habilitados)
   if(SymbolInList(s, InpRevSymbols) && CheckPointer(g_rev[i]) != POINTER_DYNAMIC)
     {
      g_rev[i] = new CRevStrategy();
      if(!g_rev[i].Init(s, InpRevLookback, InpRevImpulseAtr, InpRevRsiLow,
                        InpRevRsiHigh, InpRevTargetPct, InpRevSlAtr, InpRevMaxSlAtr))
        {
         delete g_rev[i];
         g_rev[i] = NULL;
         return false;
        }
     }

   g_symReady[i] = true;

   //--- Spread real contra el limite configurado. Los brokers cotizan el oro
   //--- con 2 o 3 decimales segun el caso, asi que el mismo limite en points
   //--- puede quedar diez veces mas flojo de lo previsto: hay que verlo.
   long spNow = SymbolInfoInteger(s, SYMBOL_SPREAD);
   long spMax = g_session[i].MaxSpreadFor(s);
   g_notifier.Log(StringFormat("%s: spread actual %d points (limite %d, %d digitos)%s",
                  s, spNow, spMax, (int)SymbolInfoInteger(s, SYMBOL_DIGITS),
                  (spNow > 0 && spNow > spMax / 4
                     ? " — ATENCION: cerca del limite, revisar si el limite es el correcto" : "")));

   g_cacheRegime[i] = "cargando historia...";
   g_cacheRating[i] = "cargando historia...";
   g_cacheSmc[i]    = (g_useSmc[i] ? "cargando historia..." : "desactivado");
   g_cacheCrt[i]    = (g_useCrt[i] ? "cargando historia..." : "desactivado");
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
   g_risk.Init(InpRiskPct, InpDailyLossPct, InpMaxDrawdownPct, InpMaxTotalRiskPct,
               InpMaxTradesPerDay, InpMaxPositions, InpResetKillSwitch,
               GetPointer(g_notifier), g_symbols);
   g_trade.Init(InpDeviationPoints, InpRR, InpBeTriggerR, InpPartialR, InpTrailAtrMult,
                GetPointer(g_notifier));
   g_news.Init(InpNewsBlockMin, InpNewsKeywords, InpNewsCurrencies,
               GetPointer(g_notifier));
   g_dash.Init();

   //--- Módulos por símbolo
   ArrayResize(g_tvM15, n);
   ArrayResize(g_tvH1, n);
   ArrayResize(g_regime, n);
   ArrayResize(g_trend, n);
   ArrayResize(g_breakout, n);
   ArrayResize(g_scalp, n);
   ArrayResize(g_rev, n);
   ArrayResize(g_lastRevOpen, n);
   ArrayResize(g_lastRevBlockLog, n);
   ArrayResize(g_smc, n);
   ArrayResize(g_crt, n);
   ArrayResize(g_session, n);
   ArrayResize(g_useTrend, n);
   ArrayResize(g_useBreakout, n);
   ArrayResize(g_useSmc, n);
   ArrayResize(g_useCrt, n);
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

      //--- Estrategias y ventana horaria de ESTE símbolo
      g_useTrend[i]    = SymbolInList(g_symbols[i], InpTrendSymbols);
      g_useBreakout[i] = SymbolInList(g_symbols[i], InpBreakoutSymbols);
      g_useSmc[i]      = SymbolInList(g_symbols[i], InpSmcSymbols);
      g_useCrt[i]      = SymbolInList(g_symbols[i], InpCrtSymbols);

      ESesion zone = SessionZoneFor(g_symbols[i]);
      g_session[i] = new CSessionFilter();
      g_session[i].Init(zone, SessionStartFor(zone), SessionEndFor(zone),
                        InpFridayEntryCutH, InpFridayCloseCutH,
                        InpMaxSpreadGold, InpMaxSpreadForex, InpMaxSpreadIndex,
                        InpServerGmtOffset, InpMaxSpreadMetal);
      g_hAtrM15[i]  = INVALID_HANDLE;
      g_lastM15[i]  = 0;
      g_lastM1[i]   = 0;
      g_lastScalpOpen[i] = 0;
      g_lastRevOpen[i]   = 0;
      g_lastRevBlockLog[i] = 0;
      g_lastRetryLog[i]  = 0;
      g_lastScalpBlockLog[i] = 0;
      g_symReady[i] = false;
      g_cacheRegime[i] = "esperando conexion...";
      g_cacheRating[i] = "esperando conexion...";
      g_cacheSmc[i]    = (g_useSmc[i] ? "esperando conexion..." : "desactivado");
      g_cacheCrt[i]    = (g_useCrt[i] ? "esperando conexion..." : "desactivado");
      TryInitSymbol(i);          // si el terminal aún no conectó, se reintenta
     }

   //--- Re-adoptar posiciones tras reinicio
   g_trade.Reconcile();

   EventSetTimer(1);
   g_notifier.Log(StringFormat(
      "ATLAS EA v2.00 iniciado. Simbolos: %s | Riesgo %.1f%%/op | Limite diario %.1f%% | Kill switch %.0f%%",
      InpSymbols, InpRiskPct, InpDailyLossPct, InpMaxDrawdownPct));
   //--- Una linea por simbolo: que corre, en que ventana, y esa ventana
   //--- traducida a hora del servidor y a la hora del usuario. Es el
   //--- chequeo de un vistazo de que la conversion de husos dio bien.
   for(int i = 0; i < n; i++)
     {
      string estr = "";
      if(g_useCrt[i])      estr += "CRT ";
      if(g_useSmc[i])      estr += "SmartMoney ";
      if(g_useTrend[i])    estr += "Tendencia ";
      if(g_useBreakout[i]) estr += "Ruptura ";
      if(SymbolInList(g_symbols[i], InpScalpSymbols)) estr += "Scalp ";
      if(estr == "")       estr = "NINGUNA (no va a operar)";

      int hIni = g_session[i].StartHour();
      int hFin = g_session[i].EndHour();
      g_notifier.Log(StringFormat(
         "%s | %s | sesion %s %02d-%02dh = servidor %02d-%02dh = tu hora (UTC%+d) %02d-%02dh | viernes: ultima entrada %02dh, cierre %02dh",
         g_symbols[i], estr, g_session[i].ZoneName(), hIni, hFin,
         g_session[i].SessionHourToServerHour(hIni),
         g_session[i].SessionHourToServerHour(hFin),
         InpLocalGmtOffset,
         g_session[i].SessionHourToLocalHour(hIni, InpLocalGmtOffset),
         g_session[i].SessionHourToLocalHour(hFin, InpLocalGmtOffset),
         g_session[i].FridayLastEntryHour(), g_session[i].FridayCloseHour()));
     }
   if(n > 0)
     {
      datetime utcNow = (datetime)((long)TimeTradeServer() - (long)g_session[0].ServerOffsetSec());
      g_notifier.Log(StringFormat(
         "Servidor detectado UTC%+d | horario de verano — EE.UU.: %s · Europa: %s",
         g_session[0].ServerOffsetSec() / 3600,
         (IsUsDst(utcNow) ? "si" : "no"), (IsEuDst(utcNow) ? "si" : "no")));
     }
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
      if(CheckPointer(g_rev[i])      == POINTER_DYNAMIC) { g_rev[i].Release();      delete g_rev[i]; }
      if(CheckPointer(g_smc[i])      == POINTER_DYNAMIC) { g_smc[i].Release();      delete g_smc[i]; }
      if(CheckPointer(g_crt[i])      == POINTER_DYNAMIC) { g_crt[i].Release();      delete g_crt[i]; }
      if(CheckPointer(g_session[i])  == POINTER_DYNAMIC) delete g_session[i];
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

   //--- 2) Viernes: cierre pre-weekend. Cada símbolo cierra en el horario
   //---    de SU plaza, así el corte de uno no arrastra al otro.
   if(!killed)
      for(int i = 0; i < n; i++)
         if(g_symReady[i] && g_session[i].MustCloseAll())
            g_trade.CloseSymbolOwn(g_symbols[i], "cierre previo al fin de semana");

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
         else if(CheckPointer(g_rev[i]) == POINTER_DYNAMIC)
            g_trade.ManageScalp(g_symbols[i], InpRevBeR, InpRevHoldMin * 60);
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
   if(!killed && StringLen(InpScalpSymbols) > 0)
      for(int i = 0; i < n; i++)
        {
         if(!g_symReady[i] || CheckPointer(g_scalp[i]) != POINTER_DYNAMIC)
            continue;
         if(!NewBar(g_symbols[i], PERIOD_M1, g_lastM1[i]))
            continue;
         EvaluateScalp(i);
        }

   //--- 5c) Reversion M1: el metodo manual del dueno (fade del impulso)
   if(!killed && StringLen(InpRevSymbols) > 0)
      for(int i = 0; i < n; i++)
        {
         if(!g_symReady[i] || CheckPointer(g_rev[i]) != POINTER_DYNAMIC)
            continue;
         if(!NewBar(g_symbols[i], PERIOD_M1, g_lastM1[i]))
            continue;
         EvaluateRev(i);
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
      (g_useTrend[idx]    && !g_trend[idx].Ready())    ||
      (g_useBreakout[idx] && !g_breakout[idx].Ready()) ||
      (g_useSmc[idx]      && !g_smc[idx].Ready())      ||
      (g_useCrt[idx]      && !g_crt[idx].Ready()))
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
   if(g_session[idx].MustCloseAll())
      return true;
   if(!g_session[idx].EntryAllowedNow())
     {
      g_notifier.Log(symbol + ": fuera de sesion, sin entradas.");
      return true;
     }
   if(!g_session[idx].SpreadOK(symbol))
     {
      long sp = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      if(sp <= 0)
        {
         LogTransient(idx, symbol + ": sin datos de precio aun (reconectando), reintento en esta vela.");
         return false;                 // no perder la vela: reintentar
        }
      g_notifier.Log(StringFormat("%s: spread %d pts excede el limite %d, sin entradas.",
                                  symbol, sp, g_session[idx].MaxSpreadFor(symbol)));
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

   if(g_useSmc[idx])
     {
      sig = g_smc[idx].Check(regime);
      g_cacheSmc[idx] = g_smc[idx].Note();
      fromSmc = (sig.dir != SIGNAL_NONE);
     }

   if(g_useCrt[idx])
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
      if((regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN) && g_useTrend[idx])
         sig = g_trend[idx].Check(regime);
      else if(regime == REGIME_SQUEEZE && g_useBreakout[idx])
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
   if(g_session[idx].MustCloseAll())
      return;
   if(!ScalpSessionOK(idx, TimeTradeServer()))
      return;
   if(!g_session[idx].SpreadOK(symbol))
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
//| Evalúa una operación de REVERSIÓN en la vela M1 (método manual   |
//| del dueño: fade del impulso, salida en 5-10 min). Usa la misma   |
//| gestión que el scalp: break-even rápido + cierre por tiempo.     |
//+------------------------------------------------------------------+
void EvaluateRev(const int idx)
  {
   string symbol = g_symbols[idx];

   if(!g_rev[idx].Ready())
      return;
   if(g_session[idx].MustCloseAll())
      return;
   if(!ScalpSessionOK(idx, TimeTradeServer()))
      return;
   if(!g_session[idx].SpreadOK(symbol))
      return;
   if(g_news.IsBlocked())
      return;

   if(TimeCurrent() - g_lastRevOpen[idx] < InpRevCooldownMin * 60)
      return;

   string blockReason = "";
   if(!g_risk.CanOpenScalp(symbol, InpRevMaxPerDay, InpRevRiskPct, blockReason))
     {
      datetime now = TimeCurrent();
      if(now - g_lastRevBlockLog[idx] >= 60)
        {
         g_lastRevBlockLog[idx] = now;
         g_notifier.Log(symbol + ": reversion bloqueada por riesgo — " + blockReason);
        }
      return;
     }

   SSignal sig = g_rev[idx].Check();
   if(sig.dir == SIGNAL_NONE)
      return;

   double entry = (sig.dir == SIGNAL_BUY ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(symbol, SYMBOL_BID));
   double lots = g_risk.CalcLots(symbol, entry, sig.sl_price, InpRevRiskPct);
   if(lots <= 0.0)
      return;

   //--- OpenScalp respeta sig.tp_price (el objetivo de la regresión) y marca
   //--- la posición para que ManageScalp le aplique el cierre por tiempo.
   if(g_trade.OpenScalp(symbol, sig, lots, 1.0))
     {
      g_risk.RegisterScalpOpen(symbol);
      g_lastRevOpen[idx] = TimeCurrent();
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
   string regimes[], ratings[], smc[], crt[], sessions[], positions[];
   int trades[];
   ArrayResize(regimes, n);
   ArrayResize(ratings, n);
   ArrayResize(smc, n);
   ArrayResize(crt, n);
   ArrayResize(sessions, n);
   ArrayResize(positions, n);
   ArrayResize(trades, n);

   bool anyOpen = false, anyClosing = false;
   for(int i = 0; i < n; i++)
     {
      regimes[i]   = g_cacheRegime[i];
      ratings[i]   = g_cacheRating[i];
      smc[i]       = g_cacheSmc[i];
      crt[i]       = g_cacheCrt[i];
      positions[i] = g_trade.PositionInfo(g_symbols[i]);
      trades[i]    = g_risk.TradesToday(g_symbols[i]);

      int hIni = g_session[i].StartHour();
      int hFin = g_session[i].EndHour();
      bool abierta = g_session[i].EntryAllowedNow();
      anyOpen    = (anyOpen || abierta);
      anyClosing = (anyClosing || g_session[i].MustCloseAll());
      sessions[i] = StringFormat("%s %02d-%02dh (vos %02d-%02dh) — %s",
                     g_session[i].ZoneName(), hIni, hFin,
                     g_session[i].SessionHourToLocalHour(hIni, InpLocalGmtOffset),
                     g_session[i].SessionHourToLocalHour(hFin, InpLocalGmtOffset),
                     (abierta ? "ABIERTA" : "cerrada"));
     }

   string state = "OPERANDO";
   color  stateColor = clrLime;
   if(g_risk.KillSwitchLatched())
     { state = "KILL SWITCH — bot apagado"; stateColor = clrRed; }
   else if(anyClosing)
     { state = "CIERRE PRE-WEEKEND"; stateColor = clrOrange; }
   else if(g_risk.DailyLossHit())
     { state = "LIMITE DIARIO ALCANZADO — sin entradas hasta manana"; stateColor = clrOrange; }
   else if(g_news.IsBlocked())
     { state = "PAUSA POR NOTICIA: " + g_news.BlockingEventName(); stateColor = clrOrange; }
   else if(!anyOpen)
     { state = "FUERA DE SESION (ninguna plaza abierta)"; stateColor = clrSilver; }

   string newsDesc = "";
   datetime newsWhen = 0;
   string newsLine = "";
   if(g_news.NextHighImpact(newsDesc, newsWhen))
      newsLine = newsDesc + " @ " + TimeToString(newsWhen, TIME_DATE | TIME_MINUTES);

   g_dash.Update(state, stateColor,
                 AccountInfoDouble(ACCOUNT_EQUITY), g_risk.DayPnLPct(),
                 g_risk.DrawdownFromPeakPct(), g_risk.OpenRiskPct(),
                 newsLine, g_symbols, regimes, ratings, smc, crt, sessions,
                 positions, trades);
  }
