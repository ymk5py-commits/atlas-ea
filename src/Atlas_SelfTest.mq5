//+------------------------------------------------------------------+
//| Atlas_SelfTest.mq5 — Verificación de la matemática crítica.      |
//| Arrastrar al gráfico como Script. Resultado en pestaña Expertos: |
//| debe terminar con "ATLAS SELFTEST: ALL PASS".                    |
//+------------------------------------------------------------------+
#property copyright "ATLAS EA"
#property version   "1.00"
#property script_show_inputs
#property strict

#include "include/AtlasTypes.mqh"
#include "include/Notifier.mqh"
#include "include/SessionFilter.mqh"
#include "include/RiskManager.mqh"
#include "include/TVRating.mqh"
#include "include/RegimeDetector.mqh"
#include "include/SmcStrategy.mqh"

input string InpTestSymbolGold = "XAUUSD";  // Simbolo oro del broker
input string InpTestSymbolEur  = "EURUSD";  // Simbolo EURUSD del broker

int g_pass = 0;
int g_fail = 0;

void Assert(const bool cond, const string name)
  {
   if(cond)
     {
      g_pass++;
      Print("PASS  ", name);
     }
   else
     {
      g_fail++;
      Print("FAIL  ", name);
     }
  }

//+------------------------------------------------------------------+
void TestRatingScale()
  {
   Assert(RatingFromAverage(0.6)  == RATING_STRONG_BUY,  "rating 0.6 -> COMPRA FUERTE");
   Assert(RatingFromAverage(0.5)  == RATING_STRONG_BUY,  "rating 0.5 (borde) -> COMPRA FUERTE");
   Assert(RatingFromAverage(0.3)  == RATING_BUY,         "rating 0.3 -> COMPRA");
   Assert(RatingFromAverage(0.1)  == RATING_BUY,         "rating 0.1 (borde) -> COMPRA");
   Assert(RatingFromAverage(0.0)  == RATING_NEUTRAL,     "rating 0.0 -> NEUTRAL");
   Assert(RatingFromAverage(-0.3) == RATING_SELL,        "rating -0.3 -> VENTA");
   Assert(RatingFromAverage(-0.5) == RATING_STRONG_SELL, "rating -0.5 (borde) -> VENTA FUERTE");
   Assert(RatingFromAverage(-0.6) == RATING_STRONG_SELL, "rating -0.6 -> VENTA FUERTE");
  }

//+------------------------------------------------------------------+
void TestSessionFilter()
  {
   CSessionFilter sf;
   sf.Init(8, 20, 18, 21, 400, 20, 600);

   datetime monday10   = StringToTime("2026.08.03 10:00");  // lunes
   datetime monday06   = StringToTime("2026.08.03 06:00");
   datetime monday21   = StringToTime("2026.08.03 21:00");
   datetime friday10   = StringToTime("2026.08.07 10:00");  // viernes
   datetime friday1830 = StringToTime("2026.08.07 18:30");
   datetime friday2105 = StringToTime("2026.08.07 21:05");
   datetime saturday   = StringToTime("2026.08.08 10:00");  // sabado

   Assert(sf.EntryAllowedAt(monday10)    == true,  "sesion: lunes 10:00 permite entrar");
   Assert(sf.EntryAllowedAt(monday06)    == false, "sesion: lunes 06:00 NO permite (pre-apertura)");
   Assert(sf.EntryAllowedAt(monday21)    == false, "sesion: lunes 21:00 NO permite (post-cierre)");
   Assert(sf.EntryAllowedAt(friday10)    == true,  "sesion: viernes 10:00 permite entrar");
   Assert(sf.EntryAllowedAt(friday1830)  == false, "sesion: viernes 18:30 NO permite (pre-weekend)");
   Assert(sf.EntryAllowedAt(saturday)    == false, "sesion: sabado NO permite");
   Assert(sf.MustCloseAllAt(friday2105)  == true,  "sesion: viernes 21:05 cierra todo");
   Assert(sf.MustCloseAllAt(friday10)    == false, "sesion: viernes 10:00 no cierra");
   Assert(sf.MustCloseAllAt(monday21)    == false, "sesion: lunes 21:00 no cierra");
  }

//+------------------------------------------------------------------+
void TestDateHelpers()
  {
   datetime t = StringToTime("2026.08.03 17:45");
   Assert(DateOf(t) == StringToTime("2026.08.03 00:00"), "DateOf recorta la hora");
   Assert(DateOf(t) == DateOf(StringToTime("2026.08.03 02:10")), "DateOf: mismo dia -> igual");
   Assert(DateOf(t) != DateOf(StringToTime("2026.08.04 02:10")), "DateOf: otro dia -> distinto");
  }


//+------------------------------------------------------------------+
//| Helpers puros de Smart Money. Los arrays van 0 = vela mas         |
//| reciente, indice mayor = mas vieja (igual que el modulo).         |
//+------------------------------------------------------------------+
void TestSmcHelpers()
  {
   double hi[10] = {10, 11, 12, 13, 14, 20, 13, 12, 11, 10};
   Assert(SmcIsSwingHigh(hi, 5, 2, 10) == true,  "SMC: fractal marca el maximo en 5");
   Assert(SmcIsSwingHigh(hi, 4, 2, 10) == false, "SMC: 4 no es maximo (hay uno mayor al lado)");
   Assert(SmcIsSwingHigh(hi, 1, 2, 10) == false, "SMC: borde nuevo sin velas suficientes -> no swing");
   Assert(SmcIsSwingHigh(hi, 8, 2, 10) == false, "SMC: borde viejo sin velas suficientes -> no swing");

   double lo[10] = {20, 19, 18, 17, 16, 5, 16, 17, 18, 19};
   Assert(SmcIsSwingLow(lo, 5, 2, 10) == true,  "SMC: fractal marca el minimo en 5");
   Assert(SmcIsSwingLow(lo, 4, 2, 10) == false, "SMC: 4 no es minimo");

   Assert(SmcInDiscount(140.0, 100.0, 200.0) == true,  "SMC: 140 en descuento (rango 100-200)");
   Assert(SmcInDiscount(160.0, 100.0, 200.0) == false, "SMC: 160 NO esta en descuento");
   Assert(SmcInDiscount(150.0, 100.0, 200.0) == true,  "SMC: equilibrio cuenta como descuento");
   Assert(SmcInPremium(160.0, 100.0, 200.0)  == true,  "SMC: 160 en premium");
   Assert(SmcInPremium(140.0, 100.0, 200.0)  == false, "SMC: 140 NO esta en premium");
   Assert(SmcInDiscount(150.0, 200.0, 100.0) == false, "SMC: rango invertido -> falso");

   double oT = 0.0, oB = 0.0;
   Assert(SmcOverlap(110.0, 100.0, 105.0, 95.0, oT, oB) == true,
          "SMC: Order Block y FVG se solapan");
   Assert(oT == 105.0 && oB == 100.0, "SMC: la zona se refina a la interseccion 100-105");
   Assert(SmcOverlap(110.0, 100.0, 99.0, 90.0, oT, oB) == false,
          "SMC: zonas separadas -> sin interseccion");

   double mrHi[3] = {10, 10, 10};
   double mrLo[3] = {8, 6, 4};
   Assert(MathAbs(SmcMeanRange(mrHi, mrLo, 0, 3, 3) - 4.0) < 1e-9, "SMC: rango medio = 4");
   Assert(MathAbs(SmcMeanRange(mrHi, mrLo, 1, 2, 3) - 5.0) < 1e-9, "SMC: rango medio parcial = 5");
   Assert(SmcMeanRange(mrHi, mrLo, 5, 3, 3) == 0.0, "SMC: tramo fuera del array -> 0");
  }

//+------------------------------------------------------------------+
//| Estructura: BOS alcista, CHoCH bajista y filtro de desplazamiento|
//+------------------------------------------------------------------+
void TestSmcStructure()
  {
   //--- Caso 1: subida que cierra sobre el maximo de la barra 7.
   double hi1[12] = {105, 106, 107, 101,  99,  97, 100, 104,  98,  96,  99, 101};
   double lo1[12] = {103, 104, 105,  99,  97,  95,  98, 102,  96,  94,  97,  99};
   double cl1[12] = {104, 105, 106, 100,  98,  96,  99, 103,  97,  95,  98, 100};

   int dir = 0, bbar = -1, origin = -1, prevDir = 0;
   SmcScanStructure(hi1, lo1, cl1, 12, 1, 1.0, dir, bbar, origin, prevDir);
   Assert(dir == 1,       "SMC estructura: detecta quiebre ALCISTA");
   Assert(bbar == 2,      "SMC estructura: la vela del quiebre es la 2");
   Assert(origin == 5,    "SMC estructura: la pierna nace en el minimo de la vela 5");
   Assert(prevDir == 0,   "SMC estructura: primer quiebre -> BOS (no CHoCH)");

   //--- Mismo caso con desplazamiento exigente: ninguna vela lo cumple
   SmcScanStructure(hi1, lo1, cl1, 12, 1, 5.0, dir, bbar, origin, prevDir);
   Assert(dir == 0, "SMC estructura: sin desplazamiento suficiente no hay quiebre");

   //--- Caso 2: el mismo tramo + 4 velas nuevas que rompen a la baja.
   double hi2[16] = { 99, 103, 104, 103, 105, 106, 107, 101,  99,  97, 100, 104,  98,  96,  99, 101};
   double lo2[16] = { 97,  97, 102, 101, 103, 104, 105,  99,  97,  95,  98, 102,  96,  94,  97,  99};
   double cl2[16] = { 98,  98, 103, 102, 104, 105, 106, 100,  98,  96,  99, 103,  97,  95,  98, 100};

   SmcScanStructure(hi2, lo2, cl2, 16, 1, 1.0, dir, bbar, origin, prevDir);
   Assert(dir == -1,     "SMC estructura: el ultimo quiebre es BAJISTA");
   Assert(bbar == 1,     "SMC estructura: la vela del quiebre bajista es la 1");
   Assert(origin == 2,   "SMC estructura: la pierna bajista nace en el maximo de la vela 2");
   Assert(prevDir == 1,  "SMC estructura: venia de un quiebre alcista -> CHoCH");
  }

//+------------------------------------------------------------------+
void TestSizing(const string symbol, CRiskManager &risk)
  {
   if(!SymbolSelect(symbol, true))
     {
      Assert(false, "sizing: simbolo no disponible: " + symbol);
      return;
     }
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(ask <= 0.0 || point <= 0.0)
     {
      Print("SKIP  sizing ", symbol, ": sin precio aun (correr con mercado abierto)");
      return;
     }

   double slDist = 400.0 * point;                 // SL a 400 points
   double sl = ask - slDist;
   double lots = risk.CalcLots(symbol, ask, sl);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * risk.RiskPct() / 100.0;
   //--- REFERENCIA INDEPENDIENTE del codigo bajo prueba: perdida estructural
   //--- = distancia x tamano de contrato (valida para XAUUSD/EURUSD en cuenta USD).
   //--- Un test circular (misma formula que el codigo) dejo pasar el bug del
   //--- tick_value de MetaQuotes-Demo; esta referencia lo habria atrapado.
   double contract = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double lossRef  = slDist * contract;
   double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   Assert(lots >= 0.0, "sizing " + symbol + ": lote no negativo");
   Assert(contract > 0.0, "sizing " + symbol + ": contract_size disponible");
   if(lots > 0.0)
     {
      Assert(lots * lossRef <= riskMoney * 1.02,
             "sizing " + symbol + ": riesgo REAL (dist x contrato) no excede el % configurado");
      Assert(lots >= vmin && lots <= vmax,
             "sizing " + symbol + ": lote dentro de los limites del broker");
      Print("INFO  ", symbol, ": equity ", DoubleToString(equity, 2),
            " riesgo ", DoubleToString(riskMoney, 2), " USD -> ", DoubleToString(lots, 2),
            " lotes | perdida real al SL: ", DoubleToString(lots * lossRef, 2), " USD");
     }
   else
      Print("INFO  ", symbol, ": lote minimo excede el riesgo -> skip correcto para cuenta chica");
  }

//+------------------------------------------------------------------+
void TestSizingSkip(const string symbol)
  {
   //--- Con riesgo casi nulo, CalcLots debe devolver 0 (skip), nunca operar de más
   CNotifier quiet;
   quiet.Init(false);
   string syms[1];
   syms[0] = symbol;
   CRiskManager tiny;
   tiny.Init(0.001, 5.0, 25.0, 3.0, 4, 2, false, GetPointer(quiet), syms);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(ask <= 0.0)
     {
      Print("SKIP  sizing-skip ", symbol, ": sin precio");
      return;
     }
   double lots = tiny.CalcLots(symbol, ask, ask - 5000.0 * point);
   Assert(lots == 0.0, "sizing " + symbol + ": riesgo insuficiente para lote minimo -> 0 (skip)");
  }

//+------------------------------------------------------------------+
void TestIndicatorWiring(const string symbol)
  {
   if(!SymbolSelect(symbol, true))
      return;

   CTVRating tv;
   if(!tv.Init(symbol, PERIOD_M15))
     {
      Assert(false, "TVRating: creacion de handles en " + symbol);
      return;
     }
   //--- esperar hasta 30 s a que carguen historia e indicadores
   int waited = 0;
   while(!tv.Ready() && waited < 30)
     {
      Sleep(1000);
      waited++;
     }
   if(!tv.Ready())
     {
      Print("SKIP  TVRating ", symbol, ": historia insuficiente aun (abrir el grafico M15/H1 y reintentar)");
      tv.Release();
      return;
     }
   double avg = 0.0;
   bool ok = tv.Votes(avg);
   Assert(ok, "TVRating " + symbol + ": calcula los votos con datos reales");
   if(ok)
     {
      Assert(avg >= -1.0 && avg <= 1.0, "TVRating " + symbol + ": promedio en [-1, +1]");
      Print("INFO  ", symbol, " rating M15 = ", RatingToString(RatingFromAverage(avg)),
            " (avg ", DoubleToString(avg, 3), ")");
     }
   tv.Release();

   CRegimeDetector rd;
   if(!rd.Init(symbol, 22.0, 0.75))
     {
      Assert(false, "RegimeDetector: creacion de handles en " + symbol);
      return;
     }
   waited = 0;
   while(!rd.Ready() && waited < 15)
     {
      Sleep(1000);
      waited++;
     }
   if(rd.Ready())
     {
      ERegime r = rd.Detect();
      Assert(r == REGIME_TREND_UP || r == REGIME_TREND_DOWN ||
             r == REGIME_SQUEEZE || r == REGIME_CHOPPY,
             "RegimeDetector " + symbol + ": devuelve un regimen valido");
      Print("INFO  ", symbol, " regimen actual = ", RegimeToString(r));
     }
   else
      Print("SKIP  RegimeDetector ", symbol, ": historia insuficiente aun");
   rd.Release();

   CSmcStrategy smc;
   if(!smc.Init(symbol, 2, 160, 20, 1.0, 0.25, 3.0, true, false, true, true, true, false))
     {
      Assert(false, "SmcStrategy: creacion de handles en " + symbol);
      return;
     }
   waited = 0;
   while(!smc.Ready() && waited < 20)
     {
      Sleep(1000);
      waited++;
     }
   if(smc.Ready())
     {
      SSignal sg = smc.Check(REGIME_TREND_UP);
      Assert(sg.dir == SIGNAL_NONE || sg.dir == SIGNAL_BUY || sg.dir == SIGNAL_SELL,
             "SMC " + symbol + ": devuelve una senal valida");
      if(sg.dir != SIGNAL_NONE)
         Assert(sg.sl_price > 0.0, "SMC " + symbol + ": toda senal trae SL definido");
      Print("INFO  ", symbol, " SMC = ", smc.Note());
     }
   else
      Print("SKIP  SmcStrategy ", symbol, ": historia M15/H1 insuficiente aun");
   smc.Release();
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   Print("================ ATLAS SELFTEST ================");
   TestRatingScale();
   TestSessionFilter();
   TestDateHelpers();
   TestSmcHelpers();
   TestSmcStructure();

   CNotifier notifier;
   notifier.Init(false);
   string syms[2];
   syms[0] = InpTestSymbolGold;
   syms[1] = InpTestSymbolEur;
   CRiskManager risk;
   risk.Init(2.0, 5.0, 25.0, 3.0, 4, 2, false, GetPointer(notifier), syms);

   TestSizing(InpTestSymbolGold, risk);
   TestSizing(InpTestSymbolEur, risk);
   TestSizingSkip(InpTestSymbolGold);

   TestIndicatorWiring(InpTestSymbolGold);
   TestIndicatorWiring(InpTestSymbolEur);

   Print("================================================");
   if(g_fail == 0)
      Print("ATLAS SELFTEST: ALL PASS (", g_pass, " tests)");
   else
      Print("ATLAS SELFTEST: ", g_fail, " FALLARON de ", g_pass + g_fail,
            " — revisar antes de usar el EA");
  }
