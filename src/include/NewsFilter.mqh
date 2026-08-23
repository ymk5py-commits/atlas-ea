//+------------------------------------------------------------------+
//| NewsFilter.mqh — Bloqueo por noticias de alto impacto            |
//| usando el calendario económico integrado de MT5.                 |
//| LIMITACION: el calendario no existe en el Strategy Tester → en   |
//| backtest este filtro queda desactivado (se valida en demo).      |
//+------------------------------------------------------------------+
#property strict
#include "Notifier.mqh"

class CNewsFilter
  {
private:
   int               m_blockMinutes;      // ± minutos alrededor del evento
   CNotifier        *m_notifier;
   string            m_keywords[];        // solo bloquean eventos que matcheen
   string            m_currencies[];      // monedas cuyo calendario se vigila
   datetime          m_lastCheck;
   bool              m_lastResult;
   string            m_lastEventName;
   datetime          m_nextEventTime;
   string            m_nextEventName;
   datetime          m_lastNextScan;

   //--- ¿El nombre del evento matchea la lista de palabras clave?
   //--- Lista vacía = comportamiento viejo (cualquier HIGH bloquea).
   bool NameMatters(const string name) const
     {
      int n = ArraySize(m_keywords);
      if(n == 0)
         return true;
      string upper = name;
      StringToUpper(upper);
      for(int i = 0; i < n; i++)
         if(StringFind(upper, m_keywords[i]) >= 0)
            return true;
      return false;
     }

   //--- ¿Hay evento HIGH relevante de la moneda en [from, to]?
   bool CurrencyHasHighEvent(const string currency, const datetime from,
                             const datetime to, string &eventName, datetime &eventTime)
     {
      MqlCalendarValue values[];
      int n = CalendarValueHistory(values, from, to, NULL, currency);
      if(n <= 0)
         return false;
      for(int i = 0; i < n; i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev))
            continue;
         if(ev.importance == CALENDAR_IMPORTANCE_HIGH && NameMatters(ev.name))
           {
            eventName = ev.name;
            eventTime = values[i].time;
            return true;
           }
        }
      return false;
     }

   //--- Parsea un CSV a un array, en mayusculas y sin espacios
   void ParseCsv(const string csv, string &out[])
     {
      ArrayResize(out, 0);
      string parts[];
      int k = StringSplit(csv, ',', parts);
      for(int i = 0; i < k; i++)
        {
         string w = parts[i];
         StringTrimLeft(w);
         StringTrimRight(w);
         if(StringLen(w) == 0)
            continue;
         StringToUpper(w);
         int sz = ArraySize(out);
         ArrayResize(out, sz + 1);
         out[sz] = w;
        }
     }

   //--- Primer evento HIGH relevante en cualquiera de las monedas vigiladas
   bool AnyCurrencyHasHighEvent(const datetime from, const datetime to,
                                string &eventName, datetime &eventTime)
     {
      bool   found = false;
      string bestName = "";
      datetime bestTime = 0;
      for(int c = 0; c < ArraySize(m_currencies); c++)
        {
         string nm = "";
         datetime tm = 0;
         if(!CurrencyHasHighEvent(m_currencies[c], from, to, nm, tm))
            continue;
         if(!found || tm < bestTime)      // el más próximo manda
           {
            found    = true;
            bestName = m_currencies[c] + " " + nm;
            bestTime = tm;
           }
        }
      if(found)
        {
         eventName = bestName;
         eventTime = bestTime;
        }
      return found;
     }

public:
   void Init(const int blockMinutes, const string keywordsCsv,
             const string currenciesCsv, CNotifier *notifier)
     {
      m_blockMinutes  = blockMinutes;
      m_notifier      = notifier;

      ParseCsv(keywordsCsv, m_keywords);
      ParseCsv(currenciesCsv, m_currencies);
      if(ArraySize(m_currencies) == 0)
        {
         ArrayResize(m_currencies, 1);
         m_currencies[0] = "USD";         // nunca quedarse sin vigilancia
        }
      m_lastCheck     = 0;
      m_lastResult    = false;
      m_lastEventName = "";
      m_nextEventTime = 0;
      m_nextEventName = "";
      m_lastNextScan  = 0;
     }

   //--- ¿Bloquear entradas nuevas ahora? (cache de 60 s)
   bool IsBlocked()
     {
      if(MQLInfoInteger(MQL_TESTER))
         return false;                    // sin calendario en el tester
      datetime now = TimeCurrent();
      if(now - m_lastCheck < 60)
         return m_lastResult;
      m_lastCheck = now;

      datetime from = now - m_blockMinutes * 60;
      datetime to   = now + m_blockMinutes * 60;
      string   name = "";
      datetime when = 0;

      bool blocked = AnyCurrencyHasHighEvent(from, to, name, when);

      if(blocked && !m_lastResult)
         m_notifier.Log("Pausa por noticia de alto impacto: " + name);
      m_lastResult    = blocked;
      m_lastEventName = (blocked ? name : "");
      return blocked;
     }

   string BlockingEventName() const { return m_lastEventName; }

   //--- Próximo evento HIGH de las monedas vigiladas, 12 h (dashboard)
   bool NextHighImpact(string &desc, datetime &when)
     {
      if(MQLInfoInteger(MQL_TESTER))
         return false;
      datetime now = TimeCurrent();
      if(now - m_lastNextScan >= 300)     // re-escanear cada 5 min
        {
         m_lastNextScan = now;
         m_nextEventTime = 0;
         m_nextEventName = "";
         string   nm = "";
         datetime tm = 0;
         if(AnyCurrencyHasHighEvent(now, now + 12 * 3600, nm, tm))
           { m_nextEventTime = tm; m_nextEventName = nm; }
        }
      if(m_nextEventTime == 0)
         return false;
      desc = m_nextEventName;
      when = m_nextEventTime;
      return true;
     }
  };
