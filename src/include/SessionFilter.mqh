//+------------------------------------------------------------------+
//| SessionFilter.mqh — Ventanas horarias, viernes y gate de spread  |
//|                                                                  |
//| Cada simbolo tiene su propia ventana, expresada en la HORA DE SU  |
//| PLAZA: Nueva York, Londres, o directamente la hora del servidor.  |
//| El filtro convierte solo: deduce el huso del servidor comparando  |
//| su reloj contra UTC y le aplica el horario de verano que          |
//| corresponda —el de EE.UU. y el europeo NO cambian el mismo dia—,  |
//| asi la ventana no se corre sola dos veces al ano ni hay que       |
//| adivinar en que huso esta el broker.                              |
//+------------------------------------------------------------------+
#property strict

//--- Plaza en cuya hora se define la ventana de un simbolo
enum ESesion
  {
   SESION_NUEVA_YORK,   // Nueva York
   SESION_LONDRES,      // Londres
   SESION_SERVIDOR      // Hora del servidor del broker (sin conversion)
  };

//=== Helpers puros de calendario (testeables sin broker) ===========

//--- Fecha UTC del n-esimo dia de semana de un mes (nth = 1 es el primero).
//--- dayOfWeek: 0 = domingo, 1 = lunes ... 6 = sabado.
datetime NthWeekdayOfMonth(const int year, const int month,
                           const int dayOfWeek, const int nth)
  {
   MqlDateTime d;
   d.year        = year;
   d.mon         = month;
   d.day         = 1;
   d.hour        = 0;
   d.min         = 0;
   d.sec         = 0;
   d.day_of_week = 0;
   d.day_of_year = 0;
   datetime first = StructToTime(d);
   MqlDateTime f;
   TimeToStruct(first, f);
   int delta = (dayOfWeek - f.day_of_week + 7) % 7;
   return (datetime)((long)first + (long)(delta + (nth - 1) * 7) * 86400);
  }

//--- Ultimo dia de semana dado de un mes (para el horario europeo)
datetime LastWeekdayOfMonth(const int year, const int month, const int dayOfWeek)
  {
   datetime fifth = NthWeekdayOfMonth(year, month, dayOfWeek, 5);
   MqlDateTime d;
   TimeToStruct(fifth, d);
   if(d.mon == month)
      return fifth;                      // el mes tenia cinco
   return NthWeekdayOfMonth(year, month, dayOfWeek, 4);
  }

//--- Horario de verano de EE.UU.: 2do domingo de marzo 07:00 UTC ->
//--- 1er domingo de noviembre 06:00 UTC (2:00 hora local en ambos).
bool IsUsDst(const datetime utc)
  {
   MqlDateTime d;
   TimeToStruct(utc, d);
   if(d.mon < 3 || d.mon > 11)
      return false;
   if(d.mon > 3 && d.mon < 11)
      return true;
   if(d.mon == 3)
      return ((long)utc >= (long)NthWeekdayOfMonth(d.year, 3, 0, 2) + 7 * 3600);
   return ((long)utc < (long)NthWeekdayOfMonth(d.year, 11, 0, 1) + 6 * 3600);
  }

//--- Horario de verano europeo: ULTIMO domingo de marzo 01:00 UTC ->
//--- ULTIMO domingo de octubre 01:00 UTC. No coincide con el de EE.UU.:
//--- hay tres semanas al ano en que Londres y Nueva York se separan.
bool IsEuDst(const datetime utc)
  {
   MqlDateTime d;
   TimeToStruct(utc, d);
   if(d.mon < 3 || d.mon > 10)
      return false;
   if(d.mon > 3 && d.mon < 10)
      return true;
   if(d.mon == 3)
      return ((long)utc >= (long)LastWeekdayOfMonth(d.year, 3, 0) + 3600);
   return ((long)utc < (long)LastWeekdayOfMonth(d.year, 10, 0) + 3600);
  }

//--- Desfase de cada plaza contra UTC, en segundos
int NewYorkGmtOffset(const datetime utc)
  {
   return (IsUsDst(utc) ? -4 * 3600 : -5 * 3600);
  }

int LondonGmtOffset(const datetime utc)
  {
   return (IsEuDst(utc) ? 3600 : 0);
  }

//--- ¿El símbolo es oro? (XAUUSD, GOLD, XAUUSD.a...)
bool SymbolIsGold(const string symbol)
  {
   string u = symbol;
   StringToUpper(u);
   return (StringFind(u, "XAU") >= 0 || StringFind(u, "GOLD") >= 0);
  }

//--- ¿El símbolo es un índice US? Nombres típicos entre brokers:
//--- US30/US100/US500, USTEC/USTECH, NAS100/NDX, SPX500, DJ30, WS30.
bool SymbolIsIndex(const string symbol)
  {
   if(SymbolIsGold(symbol))
      return false;
   string u = symbol;
   StringToUpper(u);
   return (StringFind(u, "US30") >= 0 || StringFind(u, "US100") >= 0 ||
           StringFind(u, "US500") >= 0 || StringFind(u, "USTEC") >= 0 ||
           StringFind(u, "NAS") >= 0 || StringFind(u, "NDX") >= 0 ||
           StringFind(u, "SPX") >= 0 || StringFind(u, "DJ") >= 0 ||
           StringFind(u, "WS30") >= 0);
  }

//--- Pasa un limite de spread expresado en PRECIO a los "points" de un
//--- broker con ese tamano de point. Devuelve 0 si el point no se conoce
//--- todavia, y con 0 el gate de spread no deja operar.
long SpreadLimitPoints(const double maxSpreadPrice, const double point)
  {
   if(point <= 0.0 || maxSpreadPrice <= 0.0)
      return 0;
   return (long)MathRound(maxSpreadPrice / point);
  }

//--- Nombre legible de la plaza
string SesionToString(const ESesion zone)
  {
   if(zone == SESION_NUEVA_YORK)
      return "NUEVA YORK";
   if(zone == SESION_LONDRES)
      return "LONDRES";
   return "SERVIDOR";
  }

//+------------------------------------------------------------------+
class CSessionFilter
  {
private:
   ESesion           m_zone;
   int               m_startHour;          // inicio ventana (hora de la plaza)
   int               m_endHour;            // fin ventana, exclusivo
   int               m_friEntryCutH;       // viernes: sin entradas las ultimas N horas
   int               m_friCloseCutH;       // viernes: cerrar todo N horas antes del fin
   double            m_maxSpreadGold;      // spread máx oro, en centavos de dólar
   double            m_maxSpreadForex;     // spread máx forex, en pips
   double            m_maxSpreadIndex;     // spread máx índices, en puntos del índice
   int               m_manualOffsetSec;    // desfase del servidor forzado a mano
   bool              m_offsetIsManual;

public:
   void Init(const ESesion zone, const int startHour, const int endHour,
             const int friEntryCutH, const int friCloseCutH,
             const double maxSpreadGoldCents, const double maxSpreadForexPips,
             const double maxSpreadIndexPts, const int manualServerOffsetHours = 99)
     {
      m_zone             = zone;
      m_startHour        = startHour;
      m_endHour          = endHour;
      m_friEntryCutH     = friEntryCutH;
      m_friCloseCutH     = friCloseCutH;
      m_maxSpreadGold    = maxSpreadGoldCents;
      m_maxSpreadForex   = maxSpreadForexPips;
      m_maxSpreadIndex   = maxSpreadIndexPts;
      m_offsetIsManual   = (manualServerOffsetHours >= -12 && manualServerOffsetHours <= 14);
      m_manualOffsetSec  = (m_offsetIsManual ? manualServerOffsetHours * 3600 : 0);
     }

   ESesion Zone()      const { return m_zone; }
   string  ZoneName()  const { return SesionToString(m_zone); }
   int     StartHour() const { return m_startHour; }
   int     EndHour()   const { return m_endHour; }

   //--- El viernes se recorta desde el FIN de la sesión, así la regla
   //--- vale igual en cualquier plaza sin duplicar inputs por zona.
   int FridayLastEntryHour() const { return m_endHour - m_friEntryCutH; }
   int FridayCloseHour()     const { return m_endHour - m_friCloseCutH; }

   //--- Desfase del servidor contra UTC. Se deduce de TimeTradeServer()
   //--- vs TimeGMT() y se redondea al cuarto de hora (hay brokers en :30).
   //--- Se recalcula en cada llamada: asi el cambio de horario del broker
   //--- se absorbe solo. El input manual lo pisa si la deteccion falla.
   int ServerOffsetSec() const
     {
      if(m_offsetIsManual)
         return m_manualOffsetSec;
      //--- En el Strategy Tester TimeGMT() devuelve la hora simulada del
      //--- servidor, asi que la resta daria 0 y las sesiones quedarian
      //--- corridas 2-3 horas en todo backtest. Se asume la convencion EET
      //--- del broker (UTC+2 invierno / UTC+3 verano EUROPEO), que es la de
      //--- MetaQuotes-Demo y la mayoria. Broker distinto en backtest ->
      //--- fijar InpServerGmtOffset a mano.
      if((bool)MQLInfoInteger(MQL_TESTER))
        {
         datetime approxUtc = (datetime)((long)TimeTradeServer() - 2 * 3600);
         return (IsEuDst(approxUtc) ? 3 : 2) * 3600;
        }
      long diff = (long)TimeTradeServer() - (long)TimeGMT();
      long q    = (diff + (diff >= 0 ? 450 : -450)) / 900;
      return (int)(q * 900);
     }

   //--- Desfase de la plaza de esta sesión contra UTC
   int ZoneGmtOffsetSec(const datetime utc) const
     {
      if(m_zone == SESION_NUEVA_YORK)
         return NewYorkGmtOffset(utc);
      if(m_zone == SESION_LONDRES)
         return LondonGmtOffset(utc);
      return ServerOffsetSec();
     }

   //--- Pasa hora del servidor a la hora de la plaza
   datetime ToSessionTime(const datetime serverTime) const
     {
      if(m_zone == SESION_SERVIDOR)
         return serverTime;
      datetime utc = (datetime)((long)serverTime - (long)ServerOffsetSec());
      return (datetime)((long)utc + (long)ZoneGmtOffsetSec(utc));
     }

   //--- Hora del servidor equivalente a una hora de la plaza (para logs)
   int SessionHourToServerHour(const int sessionHour) const
     {
      if(m_zone == SESION_SERVIDOR)
         return sessionHour;
      datetime utc = (datetime)((long)TimeTradeServer() - (long)ServerOffsetSec());
      int h = sessionHour - ZoneGmtOffsetSec(utc) / 3600 + ServerOffsetSec() / 3600;
      return (((h % 24) + 24) % 24);
     }

   //--- Hora en un huso cualquiera equivalente a una hora de la plaza
   int SessionHourToLocalHour(const int sessionHour, const int localGmtOffsetHours) const
     {
      datetime utc = (datetime)((long)TimeTradeServer() - (long)ServerOffsetSec());
      int h = sessionHour - ZoneGmtOffsetSec(utc) / 3600 + localGmtOffsetHours;
      return (((h % 24) + 24) % 24);
     }

   //--- Límite de spread en unidades de PRECIO del instrumento.
   //--- Se configura en la unidad natural de cada uno (centavos en el oro,
   //--- pips en forex, puntos del índice) y NO en "points" del broker: los
   //--- points dependen de con cuantos decimales cotice cada broker, asi que
   //--- el mismo numero puede quedar diez veces mas flojo sin avisar.
   double MaxSpreadPriceFor(const string symbol) const
     {
      if(SymbolIsGold(symbol))
         return m_maxSpreadGold * 0.01;    // centavos -> dólares
      if(SymbolIsIndex(symbol))
         return m_maxSpreadIndex;          // ya está en puntos del índice
      return m_maxSpreadForex * 0.0001;    // pips -> precio
     }

   //--- El mismo límite convertido a los points de ESTE broker
   long MaxSpreadFor(const string symbol) const
     {
      return SpreadLimitPoints(MaxSpreadPriceFor(symbol),
                               SymbolInfoDouble(symbol, SYMBOL_POINT));
     }

   //--- ¿El spread actual permite operar?
   bool SpreadOK(const string symbol) const
     {
      long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      long limite = MaxSpreadFor(symbol);
      return (spread > 0 && limite > 0 && spread <= limite);
     }

   //--- Núcleo testeable: reglas de calendario sobre una hora YA CONVERTIDA
   bool EntryAllowedAt(const datetime sessionTime) const
     {
      MqlDateTime dt;
      TimeToStruct(sessionTime, dt);
      if(dt.day_of_week == 0 || dt.day_of_week == 6)   // dom/sáb
         return false;
      if(dt.hour < m_startHour || dt.hour >= m_endHour)
         return false;
      if(dt.day_of_week == 5 && dt.hour >= FridayLastEntryHour())
         return false;
      return true;
     }

   bool MustCloseAllAt(const datetime sessionTime) const
     {
      MqlDateTime dt;
      TimeToStruct(sessionTime, dt);
      return (dt.day_of_week == 5 && dt.hour >= FridayCloseHour());
     }

   //--- API de producción: convierte a la hora de la plaza y evalúa
   bool EntryAllowedNow() const
     {
      return EntryAllowedAt(ToSessionTime(TimeTradeServer()));
     }

   bool EntryAllowed(const string symbol) const
     {
      if(!EntryAllowedNow())
         return false;
      return SpreadOK(symbol);
     }

   bool MustCloseAll() const
     {
      return MustCloseAllAt(ToSessionTime(TimeTradeServer()));
     }
  };
