//+------------------------------------------------------------------+
//| SessionFilter.mqh — Ventanas horarias, viernes y gate de spread  |
//| Todas las horas son HORA DEL SERVIDOR del broker.                |
//+------------------------------------------------------------------+
#property strict

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

public:
   void Init(const int startHour, const int endHour,
             const int friLastEntryHour, const int friCloseHour,
             const long maxSpreadGold, const long maxSpreadEur,
             const long maxSpreadIndex)
     {
      m_startHour        = startHour;
      m_endHour          = endHour;
      m_friLastEntryHour = friLastEntryHour;
      m_friCloseHour     = friCloseHour;
      m_maxSpreadGold    = maxSpreadGold;
      m_maxSpreadEur     = maxSpreadEur;
      m_maxSpreadIndex   = maxSpreadIndex;
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

   //--- API de producción (usa hora del servidor + spread)
   bool EntryAllowed(const string symbol) const
     {
      if(!EntryAllowedAt(TimeTradeServer()))
         return false;
      return SpreadOK(symbol);
     }

   bool MustCloseAll() const
     {
      return MustCloseAllAt(TimeTradeServer());
     }
  };
