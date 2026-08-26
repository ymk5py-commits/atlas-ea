//+------------------------------------------------------------------+
//| BreakoutStrategy.mqh — Ruptura del rango asiático.               |
//| En COMPRESION: marca el high/low de la sesión asiática y opera   |
//| la primera vela M15 que CIERRA fuera del rango en la ventana de  |
//| Londres/NY. Máximo una ruptura operada por día y por símbolo.    |
//| Horas en HORA DEL SERVIDOR del broker.                           |
//+------------------------------------------------------------------+
#property strict
#include "AtlasTypes.mqh"

class CBreakoutStrategy
  {
private:
   string            m_symbol;
   int               m_asiaStartHour;     // inicio rango asiático
   int               m_asiaEndHour;       // fin rango / inicio ventana ruptura
   int               m_breakEndHour;      // fin ventana de ruptura
   double            m_maxRangeAtrMult;   // rango válido si ≤ mult × ATR(H1)
   double            m_atrSlMult;
   int               m_hAtrH1;
   int               m_hAtrM15;
   datetime          m_lastTradeDay;      // día de la última ruptura operada

   bool CopyOne(const int handle, double &value)
     {
      double arr[];
      ArraySetAsSeries(arr, true);
      if(CopyBuffer(handle, 0, 1, 1, arr) != 1)
         return false;
      value = arr[0];
      return true;
     }

   //--- High/low del rango asiático de HOY. False si faltan barras.
   bool AsianRange(double &rangeHigh, double &rangeLow)
     {
      datetime now = TimeTradeServer();
      datetime day = DateOf(now);
      datetime tStart = day + m_asiaStartHour * 3600;
      datetime tEnd   = day + m_asiaEndHour * 3600;
      if(now < tEnd)
         return false;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M15, tStart, tEnd - 1, rates);
      if(copied < 8)
         return false;                    // rango incompleto (feriado, gap)

      rangeHigh = rates[0].high;
      rangeLow  = rates[0].low;
      for(int i = 1; i < copied; i++)
        {
         rangeHigh = MathMax(rangeHigh, rates[i].high);
         rangeLow  = MathMin(rangeLow, rates[i].low);
        }
      return (rangeHigh > rangeLow);
     }

public:
   //--- Los miembros de un objeto recien creado valen 0, y 0 NO es
   //--- INVALID_HANDLE. Sin invalidar, Release() liberaria el handle 0.
   CBreakoutStrategy() { Invalidate(); }

   void Invalidate() { m_hAtrH1 = INVALID_HANDLE; m_hAtrM15 = INVALID_HANDLE; }

   bool Init(const string symbol, const int asiaStartHour, const int asiaEndHour,
             const int breakEndHour, const double maxRangeAtrMult, const double atrSlMult)
     {
      Release();                 // idempotente: reinicializar no fuga handles
      m_symbol          = symbol;
      m_asiaStartHour   = asiaStartHour;
      m_asiaEndHour     = asiaEndHour;
      m_breakEndHour    = breakEndHour;
      m_maxRangeAtrMult = maxRangeAtrMult;
      m_atrSlMult       = atrSlMult;
      m_lastTradeDay    = 0;
      m_hAtrH1  = iATR(symbol, PERIOD_H1, 14);
      m_hAtrM15 = iATR(symbol, PERIOD_M15, 14);
      return (m_hAtrH1 != INVALID_HANDLE && m_hAtrM15 != INVALID_HANDLE);
     }

   void Release()
     {
      if(m_hAtrH1  != INVALID_HANDLE) IndicatorRelease(m_hAtrH1);
      if(m_hAtrM15 != INVALID_HANDLE) IndicatorRelease(m_hAtrM15);
      Invalidate();
     }

   bool Ready()
     {
      return (BarsCalculated(m_hAtrH1) > 20 && BarsCalculated(m_hAtrM15) > 20);
     }

   //--- El EA la llama tras ejecutar la orden de ruptura
   void MarkTraded()
     {
      m_lastTradeDay = DateOf(TimeTradeServer());
     }

   SSignal Check(const ERegime regime)
     {
      SSignal sig;
      sig.dir      = SIGNAL_NONE;
      sig.sl_price = 0.0;
      sig.tp_price = 0.0;
      sig.reason   = "";

      if(regime != REGIME_SQUEEZE)
         return sig;

      datetime now = TimeTradeServer();
      if(DateOf(now) == m_lastTradeDay)
         return sig;                      // ya se operó la ruptura de hoy

      MqlDateTime dt;
      TimeToStruct(now, dt);
      if(dt.hour < m_asiaEndHour || dt.hour >= m_breakEndHour)
         return sig;

      double rangeHigh, rangeLow, atrH1, atrM15;
      if(!AsianRange(rangeHigh, rangeLow))
         return sig;
      if(!CopyOne(m_hAtrH1, atrH1) || !CopyOne(m_hAtrM15, atrM15))
         return sig;
      if(atrH1 <= 0.0 || atrM15 <= 0.0)
         return sig;
      if(rangeHigh - rangeLow > m_maxRangeAtrMult * atrH1)
         return sig;                      // el día ya se movió: no es compresión real

      double closeM15 = iClose(m_symbol, PERIOD_M15, 1);
      if(closeM15 <= 0.0)
         return sig;

      //=== Ruptura alcista ===
      if(closeM15 > rangeHigh)
        {
         double entry = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double slRange = rangeLow;
         double slAtr   = entry - m_atrSlMult * atrM15;
         sig.dir      = SIGNAL_BUY;
         sig.sl_price = MathMax(slRange, slAtr);   // el más CERCANO (spec 4.3)
         sig.reason   = "Ruptura alcista del rango asiatico";
         return sig;
        }

      //=== Ruptura bajista ===
      if(closeM15 < rangeLow)
        {
         double entry = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double slRange = rangeHigh;
         double slAtr   = entry + m_atrSlMult * atrM15;
         sig.dir      = SIGNAL_SELL;
         sig.sl_price = MathMin(slRange, slAtr);   // el más CERCANO
         sig.reason   = "Ruptura bajista del rango asiatico";
         return sig;
        }

      return sig;
     }
  };
