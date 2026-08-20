//+------------------------------------------------------------------+
//| ScalpStrategy.mqh — Scalping de momentum en M1 (estilo manual).  |
//| Réplica del estilo de operación manual del dueño (19-ago-2026):  |
//| entradas rápidas a favor del impulso en oro, salida en minutos.  |
//|                                                                  |
//| Señal COMPRA: EMA9>EMA21 en M1, cierre sobre EMA9, RSI7 con      |
//| fuerza (>=umbral) y cierre que rompe el máximo de las 3 velas    |
//| previas (ráfaga de momentum). VENTA simétrica.                   |
//| SL = mult × ATR(M1,14). El TP (en R) lo fija el TradeManager.    |
//+------------------------------------------------------------------+
#property strict
#include "AtlasTypes.mqh"

class CScalpStrategy
  {
private:
   string            m_symbol;
   double            m_atrMult;           // multiplicador ATR M1 del stop
   double            m_rsiBuy;            // RSI7 mínimo para comprar
   double            m_rsiSell;           // RSI7 máximo para vender
   int               m_hEma9;
   int               m_hEma21;
   int               m_hRsi7;
   int               m_hAtr;

   bool CopyOne(const int handle, double &value)
     {
      double arr[];
      ArraySetAsSeries(arr, true);
      if(CopyBuffer(handle, 0, 1, 1, arr) != 1)
         return false;
      value = arr[0];
      return true;
     }

public:
   bool Init(const string symbol, const double atrMult,
             const double rsiBuy, const double rsiSell)
     {
      m_symbol  = symbol;
      m_atrMult = atrMult;
      m_rsiBuy  = rsiBuy;
      m_rsiSell = rsiSell;
      m_hEma9   = iMA(symbol, PERIOD_M1, 9, 0, MODE_EMA, PRICE_CLOSE);
      m_hEma21  = iMA(symbol, PERIOD_M1, 21, 0, MODE_EMA, PRICE_CLOSE);
      m_hRsi7   = iRSI(symbol, PERIOD_M1, 7, PRICE_CLOSE);
      m_hAtr    = iATR(symbol, PERIOD_M1, 14);
      return (m_hEma9 != INVALID_HANDLE && m_hEma21 != INVALID_HANDLE &&
              m_hRsi7 != INVALID_HANDLE && m_hAtr != INVALID_HANDLE);
     }

   void Release()
     {
      if(m_hEma9  != INVALID_HANDLE) IndicatorRelease(m_hEma9);
      if(m_hEma21 != INVALID_HANDLE) IndicatorRelease(m_hEma21);
      if(m_hRsi7  != INVALID_HANDLE) IndicatorRelease(m_hRsi7);
      if(m_hAtr   != INVALID_HANDLE) IndicatorRelease(m_hAtr);
     }

   bool Ready()
     {
      return (BarsCalculated(m_hEma21) > 30 && BarsCalculated(m_hRsi7) > 15 &&
              BarsCalculated(m_hAtr) > 20);
     }

   //--- Evalúa en cada vela M1 cerrada.
   SSignal Check()
     {
      SSignal sig;
      sig.dir      = SIGNAL_NONE;
      sig.sl_price = 0.0;
      sig.reason   = "";

      double ema9 = 0, ema21 = 0, rsi = 0, atr = 0;
      if(!CopyOne(m_hEma9, ema9) || !CopyOne(m_hEma21, ema21) ||
         !CopyOne(m_hRsi7, rsi) || !CopyOne(m_hAtr, atr))
         return sig;

      double c1 = iClose(m_symbol, PERIOD_M1, 1);
      if(c1 <= 0.0 || atr <= 0.0)
         return sig;

      //--- Extremos de las 3 velas previas a la señal (shifts 2..4)
      double hh = 0.0, ll = DBL_MAX;
      for(int i = 2; i <= 4; i++)
        {
         hh = MathMax(hh, iHigh(m_symbol, PERIOD_M1, i));
         double lo = iLow(m_symbol, PERIOD_M1, i);
         if(lo > 0.0)
            ll = MathMin(ll, lo);
        }
      if(hh <= 0.0 || ll == DBL_MAX)
         return sig;

      //=== COMPRA: impulso alcista ===
      if(ema9 > ema21 && c1 > ema9 && rsi >= m_rsiBuy && c1 > hh)
        {
         double entry = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         sig.dir      = SIGNAL_BUY;
         sig.sl_price = entry - m_atrMult * atr;
         sig.reason   = StringFormat("Scalp COMPRA momentum M1 (RSI7 %.0f)", rsi);
         return sig;
        }

      //=== VENTA: impulso bajista ===
      if(ema9 < ema21 && c1 < ema9 && rsi <= m_rsiSell && c1 < ll)
        {
         double entry = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         sig.dir      = SIGNAL_SELL;
         sig.sl_price = entry + m_atrMult * atr;
         sig.reason   = StringFormat("Scalp VENTA momentum M1 (RSI7 %.0f)", rsi);
         return sig;
        }

      return sig;
     }
  };
