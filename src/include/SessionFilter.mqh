//+------------------------------------------------------------------+
//| SessionFilter.mqh — Ventanas horarias, viernes y gate de spread  |
//|                                                                  |
//| La ventana de entradas puede definirse en HORA DEL SERVIDOR del  |
//| broker (comportamiento historico) o en HORA DE NUEVA YORK. En el |
//| segundo caso el filtro convierte solo: toma el desfase real del  |
//| servidor contra UTC y le aplica el horario de verano de EE.UU.,  |
//| asi la sesion no se corre sola dos veces al ano ni hay que       |
//| adivinar en que huso esta el broker.                             |
//+------------------------------------------------------------------+
#property strict

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

//--- Horario de verano de EE.UU.: arranca el 2do domingo de marzo a las
//--- 07:00 UTC y termina el 1er domingo de noviembre a las 06:00 UTC
//--- (2:00 hora local en ambos extremos).
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

//--- Desfase de Nueva York contra UTC, en segundos (-4h en verano, -5h en invierno)
int NewYorkGmtOffset(const datetime utc)
  {
   return (IsUsDst(utc) ? -4 * 3600 : -5 * 3600);
  }

class CSessionFilter
  {
private:
   int               m_startHour;          // inicio ventana de entradas
   int               m_endHour;            // fin ventana de entradas (exclusivo)
   int               m_friLastEntryHour;   // viernes: última hora para entrar
   int               m_friCloseHour;       // viernes: cerrar todo desde esta hora
   long              m_maxSpreadGold;      // spread máx XAUUSD (points)
   long              m_maxSpreadEur;       // spread máx EURUSD (points)
   long              m_maxSpreadIndex;     // spread máx índices US (points)
   bool              m_useNewYork;         // horas en Nueva York en vez del servidor
   int               m_manualOffsetSec;    // desfase del servidor forzado a mano
   bool              m_offsetIsManual;

public:
   void Init(const int startHour, const int endHour,
             const int friLastEntryHour, const int friCloseHour,
             const long maxSpreadGold, const long maxSpreadEur,
             const long maxSpreadIndex, const bool useNewYork = false,
             const int manualServerOffsetHours = 99)
     {
      m_startHour        = startHour;
      m_endHour          = endHour;
      m_friLastEntryHour = friLastEntryHour;
      m_friCloseHour     = friCloseHour;
      m_maxSpreadGold    = maxSpreadGold;
      m_maxSpreadEur     = maxSpreadEur;
      m_maxSpreadIndex   = maxSpreadIndex;
      m_useNewYork       = useNewYork;
      m_offsetIsManual   = (manualServerOffsetHours >= -12 && manualServerOffsetHours <= 14);
      m_manualOffsetSec  = (m_offsetIsManual ? manualServerOffsetHours * 3600 : 0);
     }

   bool UsesNewYork() const { return m_useNewYork; }

   //--- Desfase del servidor contra UTC. Se deduce de TimeTradeServer()
   //--- vs TimeGMT() y se redondea al cuarto de hora (hay brokers en :30).
   //--- Se recalcula en cada llamada: asi el cambio de horario del broker
   //--- se absorbe solo. El input manual lo pisa si la deteccion falla.
   int ServerOffsetSec() const
     {
      if(m_offsetIsManual)
         return m_manualOffsetSec;
      long diff = (long)TimeTradeServer() - (long)TimeGMT();
      long q    = (diff + (diff >= 0 ? 450 : -450)) / 900;
      return (int)(q * 900);
     }

   //--- Pasa hora del servidor a la zona en que se define la sesión
   datetime ToSessionTime(const datetime serverTime) const
     {
      if(!m_useNewYork)
         return serverTime;
      datetime utc = (datetime)((long)serverTime - (long)ServerOffsetSec());
      return (datetime)((long)utc + (long)NewYorkGmtOffset(utc));
     }

   //--- Hora del servidor equivalente a una hora de la sesión (para logs)
   int SessionHourToServerHour(const int sessionHour) const
     {
      if(!m_useNewYork)
         return sessionHour;
      datetime utc = (datetime)((long)TimeTradeServer() - (long)ServerOffsetSec());
      int h = sessionHour - NewYorkGmtOffset(utc) / 3600 + ServerOffsetSec() / 3600;
      return (((h % 24) + 24) % 24);
     }

   //--- Hora en un huso cualquiera equivalente a una hora de la sesión
   int SessionHourToLocalHour(const int sessionHour, const int localGmtOffsetHours) const
     {
      datetime utc = (datetime)((long)TimeTradeServer() - (long)ServerOffsetSec());
      int nyOff = (m_useNewYork ? NewYorkGmtOffset(utc) / 3600 : ServerOffsetSec() / 3600);
      int h = sessionHour - nyOff + localGmtOffsetHours;
      return (((h % 24) + 24) % 24);
     }

   //--- Spread máximo configurado para un símbolo (por tipo de instrumento)
   long MaxSpreadFor(const string symbol) const
     {
      string u = symbol;
      StringToUpper(u);
      if(StringFind(u, "XAU") >= 0 || StringFind(u, "GOLD") >= 0)
         return m_maxSpreadGold;
      //--- índices US (nombres típicos entre brokers: US30/US100/US500,
      //--- USTEC/USTECH, NAS100/NDX, SPX500, DJ30, WS30)
      if(StringFind(u, "US30") >= 0 || StringFind(u, "US100") >= 0 ||
         StringFind(u, "US500") >= 0 || StringFind(u, "USTEC") >= 0 ||
         StringFind(u, "NAS") >= 0 || StringFind(u, "NDX") >= 0 ||
         StringFind(u, "SPX") >= 0 || StringFind(u, "DJ") >= 0 ||
         StringFind(u, "WS30") >= 0)
         return m_maxSpreadIndex;
      return m_maxSpreadEur;
     }

   //--- ¿El spread actual permite operar?
   bool SpreadOK(const string symbol) const
     {
      long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      return (spread > 0 && spread <= MaxSpreadFor(symbol));
     }

   //--- Núcleo testeable: reglas de calendario/hora sobre un datetime dado
   bool EntryAllowedAt(const datetime now) const
     {
      MqlDateTime dt;
      TimeToStruct(now, dt);
      if(dt.day_of_week == 0 || dt.day_of_week == 6)   // dom/sáb
         return false;
      if(dt.hour < m_startHour || dt.hour >= m_endHour)
         return false;
      if(dt.day_of_week == 5 && dt.hour >= m_friLastEntryHour)
         return false;
      return true;
     }

   bool MustCloseAllAt(const datetime now) const
     {
      MqlDateTime dt;
      TimeToStruct(now, dt);
      return (dt.day_of_week == 5 && dt.hour >= m_friCloseHour);
     }

   //--- API de producción: convierte a la zona de la sesión y evalúa
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
