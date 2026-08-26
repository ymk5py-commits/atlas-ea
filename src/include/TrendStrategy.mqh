//+------------------------------------------------------------------+
//| TrendStrategy.mqh — Pullback a favor de la tendencia, multi-TF.  |
//| Largo: H1 EMA50>EMA200 · H4 sobre EMA50 · M15 retrocede a la     |
//| zona EMA20±0.3ATR y RSI(9) recupera 50. Corto simétrico.         |
//| Anti-repetición: el setup debe "rearmarse" (RSI vuelve a <45/>55)|
//+------------------------------------------------------------------+
#property strict
#include "AtlasTypes.mqh"

class CTrendStrategy
  {
private:
   string            m_symbol;
   double            m_atrSlMult;         // multiplicador ATR del stop
   int               m_hEma50H1;
   int               m_hEma200H1;
   int               m_hEma50H4;
   int               m_hEma20M15;
   int               m_hRsi9M15;
   int               m_hAtrM15;
   bool              m_armedLong;
   bool              m_armedShort;

   bool CopyN(const int handle, const int buffer, const int count, double &arr[])
     {
      ArraySetAsSeries(arr, true);
      return (CopyBuffer(handle, buffer, 1, count, arr) == count);
     }

public:
   //--- Los miembros de un objeto recien creado valen 0, y 0 NO es
   //--- INVALID_HANDLE. Sin invalidar, Release() liberaria el handle 0.
   CTrendStrategy() { Invalidate(); }

   void Invalidate()
     {
      m_hEma50H1  = INVALID_HANDLE; m_hEma200H1 = INVALID_HANDLE;
      m_hEma50H4  = INVALID_HANDLE; m_hEma20M15 = INVALID_HANDLE;
      m_hRsi9M15  = INVALID_HANDLE; m_hAtrM15   = INVALID_HANDLE;
     }

   bool Init(const string symbol, const double atrSlMult)
     {
      Release();                 // idempotente: reinicializar no fuga handles
      m_symbol    = symbol;
      m_atrSlMult = atrSlMult;
      m_armedLong  = false;
      m_armedShort = false;
      m_hEma50H1  = iMA(symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_hEma200H1 = iMA(symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
      m_hEma50H4  = iMA(symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_hEma20M15 = iMA(symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
      m_hRsi9M15  = iRSI(symbol, PERIOD_M15, 9, PRICE_CLOSE);
      m_hAtrM15   = iATR(symbol, PERIOD_M15, 14);
      return (m_hEma50H1 != INVALID_HANDLE && m_hEma200H1 != INVALID_HANDLE &&
              m_hEma50H4 != INVALID_HANDLE && m_hEma20M15 != INVALID_HANDLE &&
              m_hRsi9M15 != INVALID_HANDLE && m_hAtrM15 != INVALID_HANDLE);
     }

   void Release()
     {
      if(m_hEma50H1  != INVALID_HANDLE) IndicatorRelease(m_hEma50H1);
      if(m_hEma200H1 != INVALID_HANDLE) IndicatorRelease(m_hEma200H1);
      if(m_hEma50H4  != INVALID_HANDLE) IndicatorRelease(m_hEma50H4);
      if(m_hEma20M15 != INVALID_HANDLE) IndicatorRelease(m_hEma20M15);
      if(m_hRsi9M15  != INVALID_HANDLE) IndicatorRelease(m_hRsi9M15);
      if(m_hAtrM15   != INVALID_HANDLE) IndicatorRelease(m_hAtrM15);
      Invalidate();
     }

   bool Ready()
     {
      return (BarsCalculated(m_hEma200H1) > 210 && BarsCalculated(m_hEma50H4) > 60 &&
              BarsCalculated(m_hEma20M15) > 30 && BarsCalculated(m_hRsi9M15) > 15 &&
              BarsCalculated(m_hAtrM15) > 20);
     }

   //--- Evalúa en cada vela M15 cerrada. regime debe ser TREND_UP/DOWN.
   SSignal Check(const ERegime regime)
     {
      SSignal sig;
      sig.dir      = SIGNAL_NONE;
      sig.sl_price = 0.0;
      sig.tp_price = 0.0;
      sig.reason   = "";

      if(regime != REGIME_TREND_UP && regime != REGIME_TREND_DOWN)
         return sig;

      double ema50h1[], ema200h1[], ema50h4[], ema20[], rsi[], atr[];
      if(!CopyN(m_hEma50H1, 0, 1, ema50h1) || !CopyN(m_hEma200H1, 0, 1, ema200h1) ||
         !CopyN(m_hEma50H4, 0, 1, ema50h4) || !CopyN(m_hEma20M15, 0, 1, ema20) ||
         !CopyN(m_hRsi9M15, 0, 3, rsi) || !CopyN(m_hAtrM15, 0, 1, atr))
         return sig;

      double closeH4 = iClose(m_symbol, PERIOD_H4, 1);
      double closeM15 = iClose(m_symbol, PERIOD_M15, 1);
      double lowM15   = iLow(m_symbol, PERIOD_M15, 1);
      double highM15  = iHigh(m_symbol, PERIOD_M15, 1);
      if(closeH4 <= 0.0 || closeM15 <= 0.0 || atr[0] <= 0.0)
         return sig;

      double zone = 0.3 * atr[0];
      double spreadPrice = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) *
                           SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      //--- Rearme del setup
      if(rsi[0] < 45.0)
         m_armedLong = true;
      if(rsi[0] > 55.0)
         m_armedShort = true;

      //=== LARGO ===
      if(regime == REGIME_TREND_UP && m_armedLong &&
         ema50h1[0] > ema200h1[0] && closeH4 > ema50h4[0] &&
         lowM15 <= ema20[0] + zone && closeM15 >= ema20[0] - zone &&
         rsi[1] < 50.0 && rsi[0] >= 50.0)
        {
         double entry = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double swingLow = lowM15;
         for(int i = 2; i <= 5; i++)
            swingLow = MathMin(swingLow, iLow(m_symbol, PERIOD_M15, i));
         double slSwing = swingLow - spreadPrice;
         double slAtr   = entry - m_atrSlMult * atr[0];
         sig.dir      = SIGNAL_BUY;
         sig.sl_price = MathMin(slSwing, slAtr);     // el más lejano protege mejor
         sig.reason   = "Pullback tendencia alcista (RSI9 recupera 50)";
         m_armedLong  = false;
         return sig;
        }

      //=== CORTO ===
      if(regime == REGIME_TREND_DOWN && m_armedShort &&
         ema50h1[0] < ema200h1[0] && closeH4 < ema50h4[0] &&
         highM15 >= ema20[0] - zone && closeM15 <= ema20[0] + zone &&
         rsi[1] > 50.0 && rsi[0] <= 50.0)
        {
         double entry = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double swingHigh = highM15;
         for(int i = 2; i <= 5; i++)
            swingHigh = MathMax(swingHigh, iHigh(m_symbol, PERIOD_M15, i));
         double slSwing = swingHigh + spreadPrice;
         double slAtr   = entry + m_atrSlMult * atr[0];
         sig.dir      = SIGNAL_SELL;
         sig.sl_price = MathMax(slSwing, slAtr);     // el más lejano
         sig.reason   = "Pullback tendencia bajista (RSI9 pierde 50)";
         m_armedShort = false;
         return sig;
        }

      return sig;
     }
  };
