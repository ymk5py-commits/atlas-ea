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
#include "include/CrtStrategy.mqh"

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
   //--- 8-20 hora del servidor; el viernes se recorta 2h para entrar y 1h para cerrar
   sf.Init(SESION_SERVIDOR, 8, 20, 2, 1, 50, 2, 5);

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

   Assert(PriceInDiscount(140.0, 100.0, 200.0) == true,  "Rango: 140 en descuento (100-200)");
   Assert(PriceInDiscount(160.0, 100.0, 200.0) == false, "Rango: 160 NO esta en descuento");
   Assert(PriceInDiscount(150.0, 100.0, 200.0) == true,  "Rango: equilibrio cuenta como descuento");
   Assert(PriceInPremium(160.0, 100.0, 200.0)  == true,  "Rango: 160 en premium");
   Assert(PriceInPremium(140.0, 100.0, 200.0)  == false, "Rango: 140 NO esta en premium");
   Assert(PriceInDiscount(150.0, 200.0, 100.0) == false, "Rango: invertido -> falso");

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
//| Helpers puros de Candle Range Theory                              |
//+------------------------------------------------------------------+
void TestCrtHelpers()
  {
   //--- Validez del rango de la vela mayor (ATR del TF = 10)
   Assert(CrtRangeValid(10.0, 10.0, 0.8, 2.5) == true,  "CRT: rango normal es valido");
   Assert(CrtRangeValid(5.0,  10.0, 0.8, 2.5) == false, "CRT: doji sin recorrido -> invalido");
   Assert(CrtRangeValid(30.0, 10.0, 0.8, 2.5) == false, "CRT: vela gigante ya extendida -> invalido");
   Assert(CrtRangeValid(8.0,  10.0, 0.8, 2.5) == true,  "CRT: borde inferior del rango es valido");
   Assert(CrtRangeValid(25.0, 10.0, 0.8, 2.5) == true,  "CRT: borde superior del rango es valido");
   Assert(CrtRangeValid(10.0,  0.0, 0.8, 2.5) == false, "CRT: sin ATR no se valida el rango");
   Assert(CrtRangeValid(0.0,  10.0, 0.8, 2.5) == false, "CRT: rango nulo -> invalido");

   //--- Profundidad de la purga (rango = 10, tope 40%)
   Assert(CrtPurgeIsSweep(2.0, 10.0, 40.0) == true,  "CRT: purga somera es barrido");
   Assert(CrtPurgeIsSweep(4.0, 10.0, 40.0) == true,  "CRT: purga en el limite sigue siendo barrido");
   Assert(CrtPurgeIsSweep(5.0, 10.0, 40.0) == false, "CRT: purga profunda es ruptura, no barrido");
   Assert(CrtPurgeIsSweep(0.0, 10.0, 40.0) == false, "CRT: sin purga no hay barrido");
   Assert(CrtPurgeIsSweep(2.0,  0.0, 40.0) == false, "CRT: sin rango no hay barrido");

   //--- Beneficio / riesgo hasta el extremo opuesto
   Assert(MathAbs(CrtRewardRisk(100.0, 104.0, 92.0) - 2.0) < 1e-9,
          "CRT: venta con riesgo 4 y recorrido 8 = 2R");
   Assert(MathAbs(CrtRewardRisk(100.0, 96.0, 110.0) - 2.5) < 1e-9,
          "CRT: compra con riesgo 4 y recorrido 10 = 2.5R");
   Assert(CrtRewardRisk(100.0, 104.0, 108.0) == 0.0,
          "CRT: objetivo del lado equivocado -> 0R (se descarta)");
   Assert(CrtRewardRisk(100.0, 100.0, 90.0) == 0.0,
          "CRT: SL pegado al precio -> 0R (se descarta)");
  }

//+------------------------------------------------------------------+
//| Zona horaria: cambio de horario de EE.UU. y conversion de sesion  |
//+------------------------------------------------------------------+
void TestTimezone()
  {
   //--- Ubicacion de los domingos de transicion
   Assert(NthWeekdayOfMonth(2026, 3, 0, 2)  == StringToTime("2026.03.08 00:00"),
          "DST: 2do domingo de marzo 2026 = 8-mar");
   Assert(NthWeekdayOfMonth(2026, 11, 0, 1) == StringToTime("2026.11.01 00:00"),
          "DST: 1er domingo de noviembre 2026 = 1-nov");
   Assert(NthWeekdayOfMonth(2025, 3, 0, 2)  == StringToTime("2025.03.09 00:00"),
          "DST: 2do domingo de marzo 2025 = 9-mar");
   Assert(NthWeekdayOfMonth(2027, 3, 0, 2)  == StringToTime("2027.03.14 00:00"),
          "DST: 2do domingo de marzo 2027 = 14-mar");

   //--- Vigencia del horario de verano (los instantes van en UTC)
   Assert(IsUsDst(StringToTime("2026.03.08 06:59")) == false, "DST: un minuto antes todavia es invierno");
   Assert(IsUsDst(StringToTime("2026.03.08 07:00")) == true,  "DST: arranca a las 07:00 UTC");
   Assert(IsUsDst(StringToTime("2026.07.15 12:00")) == true,  "DST: julio es verano");
   Assert(IsUsDst(StringToTime("2026.11.01 05:59")) == true,  "DST: un minuto antes todavia es verano");
   Assert(IsUsDst(StringToTime("2026.11.01 06:00")) == false, "DST: termina a las 06:00 UTC");
   Assert(IsUsDst(StringToTime("2026.01.15 12:00")) == false, "DST: enero es invierno");
   Assert(IsUsDst(StringToTime("2026.12.15 12:00")) == false, "DST: diciembre es invierno");

   Assert(NewYorkGmtOffset(StringToTime("2026.07.15 12:00")) == -4 * 3600,
          "NY: en verano esta a UTC-4");
   Assert(NewYorkGmtOffset(StringToTime("2026.01.15 12:00")) == -5 * 3600,
          "NY: en invierno esta a UTC-5");

   //--- Lo que importa: la MISMA hora de Nueva York sale bien con brokers
   //--- en husos distintos y en estaciones distintas.
   CSessionFilter ny3;                    // Nueva York, servidor UTC+3 (EET verano)
   ny3.Init(SESION_NUEVA_YORK, 8, 17, 2, 1, 50, 2, 5, 3);
   CSessionFilter ny2;                    // Nueva York, servidor UTC+2 (EET invierno)
   ny2.Init(SESION_NUEVA_YORK, 8, 17, 2, 1, 50, 2, 5, 2);

   Assert(ny3.ToSessionTime(StringToTime("2026.07.15 15:00")) == StringToTime("2026.07.15 08:00"),
          "zona: servidor UTC+3 15:00 en julio = 08:00 de Nueva York");
   Assert(ny2.ToSessionTime(StringToTime("2026.01.15 15:00")) == StringToTime("2026.01.15 08:00"),
          "zona: servidor UTC+2 15:00 en enero = la MISMA apertura de Nueva York");
   Assert(ny3.ToSessionTime(StringToTime("2026.07.15 20:00")) == StringToTime("2026.07.15 13:00"),
          "zona: servidor UTC+3 20:00 en julio = 13:00 de Nueva York");

   //--- Y la ventana de entradas se evalua sobre la hora ya convertida
   Assert(ny3.EntryAllowedAt(ny3.ToSessionTime(StringToTime("2026.07.15 15:00"))) == true,
          "sesion NY: miercoles en la apertura permite entrar");
   Assert(ny3.EntryAllowedAt(ny3.ToSessionTime(StringToTime("2026.07.15 09:00"))) == false,
          "sesion NY: 02:00 de Nueva York NO permite (aun no abrio)");
   Assert(ny3.EntryAllowedAt(ny3.ToSessionTime(StringToTime("2026.07.17 20:00"))) == true,
          "sesion NY: viernes 13:00 todavia permite entrar");
   Assert(ny3.EntryAllowedAt(ny3.ToSessionTime(StringToTime("2026.07.17 23:00"))) == false,
          "sesion NY: viernes 16:00 ya no permite entrar");
   Assert(ny3.MustCloseAllAt(ny3.ToSessionTime(StringToTime("2026.07.17 23:00"))) == true,
          "sesion NY: viernes 16:00 cierra todo");

   //--- El viernes se recorta desde el FIN de la sesion
   Assert(ny3.FridayLastEntryHour() == 15, "viernes: ultima entrada = fin - 2h");
   Assert(ny3.FridayCloseHour()     == 16, "viernes: cierre total = fin - 1h");

   //--- En modo servidor nada se convierte (comportamiento historico)
   CSessionFilter srv;
   srv.Init(SESION_SERVIDOR, 8, 20, 2, 1, 50, 2, 5);
   Assert(srv.ToSessionTime(StringToTime("2026.07.15 15:00")) == StringToTime("2026.07.15 15:00"),
          "zona: en modo servidor la hora pasa sin tocar");
   Assert(srv.ZoneName() == "SERVIDOR",   "zona: nombre de la plaza servidor");
   Assert(ny3.ZoneName() == "NUEVA YORK", "zona: nombre de la plaza Nueva York");
  }

//+------------------------------------------------------------------+
//| Londres: horario de verano europeo y convivencia con Nueva York   |
//+------------------------------------------------------------------+
void TestLondres()
  {
   //--- El horario europeo se ubica por el ULTIMO domingo, no el n-esimo
   Assert(LastWeekdayOfMonth(2026, 3, 0)  == StringToTime("2026.03.29 00:00"),
          "DST UE: ultimo domingo de marzo 2026 = 29-mar");
   Assert(LastWeekdayOfMonth(2026, 10, 0) == StringToTime("2026.10.25 00:00"),
          "DST UE: ultimo domingo de octubre 2026 = 25-oct");
   Assert(LastWeekdayOfMonth(2025, 3, 0)  == StringToTime("2025.03.30 00:00"),
          "DST UE: ultimo domingo de marzo 2025 = 30-mar");
   Assert(LastWeekdayOfMonth(2027, 10, 0) == StringToTime("2027.10.31 00:00"),
          "DST UE: ultimo domingo de octubre 2027 = 31-oct");

   Assert(IsEuDst(StringToTime("2026.03.29 00:59")) == false, "DST UE: un minuto antes es invierno");
   Assert(IsEuDst(StringToTime("2026.03.29 01:00")) == true,  "DST UE: arranca a las 01:00 UTC");
   Assert(IsEuDst(StringToTime("2026.07.15 12:00")) == true,  "DST UE: julio es verano");
   Assert(IsEuDst(StringToTime("2026.10.25 00:59")) == true,  "DST UE: un minuto antes todavia es verano");
   Assert(IsEuDst(StringToTime("2026.10.25 01:00")) == false, "DST UE: termina a las 01:00 UTC");
   Assert(IsEuDst(StringToTime("2026.01.15 12:00")) == false, "DST UE: enero es invierno");

   Assert(LondonGmtOffset(StringToTime("2026.07.15 12:00")) == 3600, "Londres: en verano esta a UTC+1");
   Assert(LondonGmtOffset(StringToTime("2026.01.15 12:00")) == 0,    "Londres: en invierno esta a UTC+0");

   CSessionFilter lon3;                   // Londres, servidor UTC+3 (EET verano)
   lon3.Init(SESION_LONDRES, 8, 17, 2, 1, 50, 2, 5, 3);
   CSessionFilter lon2;                   // Londres, servidor UTC+2 (EET invierno)
   lon2.Init(SESION_LONDRES, 8, 17, 2, 1, 50, 2, 5, 2);

   Assert(lon3.ToSessionTime(StringToTime("2026.07.15 10:00")) == StringToTime("2026.07.15 08:00"),
          "Londres: servidor UTC+3 10:00 en julio = 08:00 de Londres");
   Assert(lon2.ToSessionTime(StringToTime("2026.01.15 10:00")) == StringToTime("2026.01.15 08:00"),
          "Londres: servidor UTC+2 10:00 en enero = la MISMA apertura de Londres");
   Assert(lon3.ToSessionTime(StringToTime("2026.07.15 19:00")) == StringToTime("2026.07.15 17:00"),
          "Londres: servidor UTC+3 19:00 en julio = 17:00 de Londres (cierre)");
   Assert(lon3.EntryAllowedAt(lon3.ToSessionTime(StringToTime("2026.07.15 10:00"))) == true,
          "sesion Londres: miercoles en la apertura permite entrar");
   Assert(lon3.EntryAllowedAt(lon3.ToSessionTime(StringToTime("2026.07.15 19:00"))) == false,
          "sesion Londres: 17:00 ya es el cierre, no permite");

   //--- Lo importante: EE.UU. y Europa NO cambian la hora el mismo dia.
   //--- Del 8 al 28 de marzo de 2026 Londres y Nueva York estan a 4 horas
   //--- y no a 5. Una ventana fija en hora del servidor se corre esos dias;
   //--- esta no, porque cada plaza lleva su propio horario de verano.
   datetime marzo = StringToTime("2026.03.20 12:00");   // UTC, dentro del desfase
   datetime julio = StringToTime("2026.07.15 12:00");   // UTC, ambas en verano
   Assert(LondonGmtOffset(marzo) - NewYorkGmtOffset(marzo) == 4 * 3600,
          "desfase: en marzo Londres y Nueva York estan a 4 horas");
   Assert(LondonGmtOffset(julio) - NewYorkGmtOffset(julio) == 5 * 3600,
          "desfase: en julio vuelven a estar a 5 horas");

   //--- Y en ese hueco cada sesion sigue abriendo a SU hora 08:00
   CSessionFilter lonMar, nyMar;
   lonMar.Init(SESION_LONDRES,     8, 17, 2, 1, 50, 2, 5, 2);
   nyMar.Init(SESION_NUEVA_YORK,   8, 17, 2, 1, 50, 2, 5, 2);
   Assert(lonMar.ToSessionTime(StringToTime("2026.03.20 10:00")) == StringToTime("2026.03.20 08:00"),
          "desfase: 20-mar servidor 10:00 = apertura de Londres");
   Assert(nyMar.ToSessionTime(StringToTime("2026.03.20 14:00")) == StringToTime("2026.03.20 08:00"),
          "desfase: 20-mar servidor 14:00 = apertura de Nueva York (4h despues, no 5)");
  }

//+------------------------------------------------------------------+
//| Limite de spread: la misma tolerancia real en cualquier broker    |
//+------------------------------------------------------------------+
void TestSpread()
  {
   //--- Clasificacion del instrumento
   Assert(SymbolIsGold("XAUUSD")   == true,  "spread: XAUUSD es oro");
   Assert(SymbolIsGold("GOLD")     == true,  "spread: GOLD es oro");
   Assert(SymbolIsGold("XAUUSD.a") == true,  "spread: el sufijo del broker no rompe la deteccion");
   Assert(SymbolIsGold("EURUSD")   == false, "spread: EURUSD no es oro");
   Assert(SymbolIsIndex("US30")    == true,  "spread: US30 es indice");
   Assert(SymbolIsIndex("NAS100")  == true,  "spread: NAS100 es indice");
   Assert(SymbolIsIndex("EURUSD")  == false, "spread: EURUSD no es indice");
   Assert(SymbolIsIndex("XAUUSD")  == false, "spread: el oro no cuenta como indice");

   //--- Lo importante: el MISMO limite real cae en distinta cantidad de
   //--- points segun con cuantos decimales cotice el broker.
   Assert(SpreadLimitPoints(0.50, 0.01)     == 50,  "spread: 0.50 USD de oro = 50 points con 2 decimales");
   Assert(SpreadLimitPoints(0.50, 0.001)    == 500, "spread: 0.50 USD de oro = 500 points con 3 decimales");
   //--- Forex por DIGITOS (el pip de los pares JPY es 0.01, no 0.0001)
   Assert(ForexSpreadLimitPoints(2.0, 5) == 20, "spread: 2 pips = 20 points (EURUSD 5 digitos)");
   Assert(ForexSpreadLimitPoints(2.0, 4) == 2,  "spread: 2 pips = 2 points (broker de 4 digitos)");
   Assert(ForexSpreadLimitPoints(2.0, 3) == 20, "spread: 2 pips = 20 points (USDJPY 3 digitos) — antes daba 0 y bloqueaba");
   Assert(ForexSpreadLimitPoints(2.0, 2) == 2,  "spread: 2 pips = 2 points (JPY de 2 digitos)");
   Assert(ForexSpreadLimitPoints(2.0, 0) == 0,  "spread: sin digitos -> 0 (no operar)");
   Assert(ForexSpreadLimitPoints(0.0, 5) == 0,  "spread: limite nulo -> 0 (no operar)");
   Assert(SpreadLimitPoints(5.0, 0.1)        == 50, "spread: 5 puntos de indice = 50 points con 1 decimal");
   Assert(SpreadLimitPoints(5.0, 0.01)       == 500,"spread: 5 puntos de indice = 500 points con 2 decimales");

   //--- Sin especificacion del simbolo el limite queda en 0, y con 0 no se opera
   Assert(SpreadLimitPoints(0.50, 0.0) == 0, "spread: sin point conocido -> limite 0 (no operar)");

   //--- El limite configurado llega a cada tipo de instrumento
   CSessionFilter sf;
   sf.Init(SESION_SERVIDOR, 8, 20, 2, 1, 50, 2, 5);
   Assert(MathAbs(sf.MaxSpreadPriceFor("XAUUSD") - 0.50)   < 1e-9, "spread: 50 centavos de oro = 0.50 USD");
   Assert(MathAbs(sf.MaxSpreadPriceFor("US30")   - 5.0)    < 1e-9, "spread: 5 puntos de indice = 5.0");
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

   CCrtStrategy crt;
   if(!crt.Init(symbol, PERIOD_H4, 0, 0.8, 2.5, 40.0, 1.5, 0.25, true, true, true))
     {
      Assert(false, "CrtStrategy: creacion de handles en " + symbol);
      return;
     }
   waited = 0;
   while(!crt.Ready() && waited < 20)
     {
      Sleep(1000);
      waited++;
     }
   if(crt.Ready())
     {
      SSignal cs = crt.Check(REGIME_CHOPPY);
      Assert(cs.dir == SIGNAL_NONE || cs.dir == SIGNAL_BUY || cs.dir == SIGNAL_SELL,
             "CRT " + symbol + ": devuelve una senal valida");
      if(cs.dir != SIGNAL_NONE)
        {
         Assert(cs.sl_price > 0.0 && cs.tp_price > 0.0,
                "CRT " + symbol + ": toda senal trae SL y objetivo");
         //--- El SL y el objetivo tienen que quedar en lados OPUESTOS del precio
         double px = (cs.dir == SIGNAL_BUY ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(symbol, SYMBOL_BID));
         bool ok = (cs.dir == SIGNAL_BUY ? (cs.sl_price < px && cs.tp_price > px)
                                         : (cs.sl_price > px && cs.tp_price < px));
         Assert(ok, "CRT " + symbol + ": SL y objetivo en lados opuestos del precio");
        }
      Print("INFO  ", symbol, " CRT = ", crt.Note());
     }
   else
      Print("SKIP  CrtStrategy ", symbol, ": historia H4/M15 insuficiente aun");
   crt.Release();
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
   TestCrtHelpers();
   TestTimezone();
   TestLondres();
   TestSpread();

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
