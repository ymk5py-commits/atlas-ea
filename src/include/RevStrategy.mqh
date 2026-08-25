//+------------------------------------------------------------------+
//| RevStrategy.mqh — Reversión a la media en M1.                    |
//|                                                                  |
//| Réplica del método MANUAL del dueño (24-ago-2026, sus palabras): |
//|   "cuando hay una bajada fuerte hago compra y cuando hay una     |
//|    subida fuerte hago venta, y lo dejo por 5 a 10 min            |
//|    dependiendo de la regresión".                                 |
//|                                                                  |
//| Es lo OPUESTO al scalping de momentum (ScalpStrategy), que       |
//| compraba fuerza y vendía debilidad. Acá se opera CONTRA el       |
//| impulso, apostando a que el precio regrese.                      |
//|                                                                  |
//| Pasos:                                                           |
//|   1. IMPULSO: en las últimas N velas M1 el precio recorrió       |
//|      >= mult x ATR(M1) en una dirección.                         |
//|   2. EXTREMO: el RSI(7) confirma sobreventa (para comprar) o     |
//|      sobrecompra (para vender). Sin esto, cualquier tramo        |
//|      normal dispararía la señal.                                 |
//|   3. ENTRADA: a favor de la regresión, contra el impulso.        |
//|   4. OBJETIVO: recuperar un % del tramo recorrido (la            |
//|      "regresión"). No se busca el giro completo.                 |
//|   5. STOP: más allá del extremo del impulso + colchón ATR.       |
//|   La salida por tiempo (5-10 min) la aplica el EA con            |
//|   ManageScalp(), igual que en el scalping.                       |
//|                                                                  |
//| Índices: 0 = vela M1 en formación; se lee desde shift 1 (última  |
//| CERRADA) hacia atrás. Nunca se opera con la vela en curso.       |
//+------------------------------------------------------------------+
#property strict
#include "AtlasTypes.mqh"

class CRevStrategy
  {
private:
   string            m_symbol;
   int               m_lookback;       // velas M1 del tramo
   double            m_impulseAtr;     // tamaño mínimo del impulso (x ATR)
   double            m_rsiLow;         // RSI7 <= esto para COMPRAR
   double            m_rsiHigh;        // RSI7 >= esto para VENDER
   double            m_targetPct;      // % del tramo que se busca recuperar
   double            m_slAtr;          // colchón del stop (x ATR)
   double            m_maxSlAtr;       // descartar si el stop queda más ancho
   int               m_hRsi7;
   int               m_hAtr;
   string            m_note;           // para el panel

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
   bool Init(const string symbol, const int lookback, const double impulseAtr,
             const double rsiLow, const double rsiHigh, const double targetPct,
             const double slAtr, const double maxSlAtr)
     {
      m_symbol     = symbol;
      m_lookback   = MathMax(2, lookback);
      m_impulseAtr = impulseAtr;
      m_rsiLow     = rsiLow;
      m_rsiHigh    = rsiHigh;
      m_targetPct  = MathMax(0.05, targetPct / 100.0);
      m_slAtr      = slAtr;
      m_maxSlAtr   = maxSlAtr;
      m_note       = "sin datos";
      m_hRsi7 = iRSI(symbol, PERIOD_M1, 7, PRICE_CLOSE);
      m_hAtr  = iATR(symbol, PERIOD_M1, 14);
      return (m_hRsi7 != INVALID_HANDLE && m_hAtr != INVALID_HANDLE);
     }

   void Release()
     {
      if(m_hRsi7 != INVALID_HANDLE) IndicatorRelease(m_hRsi7);
      if(m_hAtr  != INVALID_HANDLE) IndicatorRelease(m_hAtr);
     }

   bool Ready()
     {
      return (BarsCalculated(m_hRsi7) > 15 && BarsCalculated(m_hAtr) > 20);
     }

   string Note() const { return m_note; }

   //--- Evalúa en cada vela M1 cerrada.
   SSignal Check()
     {
      SSignal sig;
      sig.dir      = SIGNAL_NONE;
      sig.sl_price = 0.0;
      sig.tp_price = 0.0;
      sig.reason   = "";

      double rsi = 0.0, atr = 0.0;
      if(!CopyOne(m_hRsi7, rsi) || !CopyOne(m_hAtr, atr) || atr <= 0.0)
        {
         m_note = "sin datos";
         return sig;
        }

      double c1 = iClose(m_symbol, PERIOD_M1, 1);
      if(c1 <= 0.0)
        {
         m_note = "sin datos";
         return sig;
        }

      //--- Extremos del tramo: shifts 1..lookback (la vela 1 incluida)
      double hh = 0.0, ll = DBL_MAX;
      for(int i = 1; i <= m_lookback; i++)
        {
         double h = iHigh(m_symbol, PERIOD_M1, i);
         double l = iLow(m_symbol, PERIOD_M1, i);
         if(h > 0.0) hh = MathMax(hh, h);
         if(l > 0.0) ll = MathMin(ll, l);
        }
      if(hh <= 0.0 || ll == DBL_MAX || hh <= ll)
        {
         m_note = "sin datos";
         return sig;
        }

      double caida = hh - c1;     // cuánto bajó desde el máximo del tramo
      double subida = c1 - ll;    // cuánto subió desde el mínimo del tramo
      double minimo = m_impulseAtr * atr;

      //=== COMPRA: bajada fuerte + sobreventa → apostar a la regresión ===
      if(caida >= minimo && rsi <= m_rsiLow)
        {
         double entry = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double sl    = ll - m_slAtr * atr;
         if(entry - sl > m_maxSlAtr * atr)
           {
            m_note = "bajada fuerte pero el stop queda muy ancho";
            return sig;
           }
         sig.dir      = SIGNAL_BUY;
         sig.sl_price = sl;
         sig.tp_price = c1 + m_targetPct * caida;
         sig.reason   = StringFormat("Reversion COMPRA tras bajada de %.1f ATR (RSI7 %.0f)",
                                     caida / atr, rsi);
         m_note = "COMPRA por reversion";
         return sig;
        }

      //=== VENTA: subida fuerte + sobrecompra → apostar a la regresión ===
      if(subida >= minimo && rsi >= m_rsiHigh)
        {
         double entry = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double sl    = hh + m_slAtr * atr;
         if(sl - entry > m_maxSlAtr * atr)
           {
            m_note = "subida fuerte pero el stop queda muy ancho";
            return sig;
           }
         sig.dir      = SIGNAL_SELL;
         sig.sl_price = sl;
         sig.tp_price = c1 - m_targetPct * subida;
         sig.reason   = StringFormat("Reversion VENTA tras subida de %.1f ATR (RSI7 %.0f)",
                                     subida / atr, rsi);
         m_note = "VENTA por reversion";
         return sig;
        }

      m_note = StringFormat("sin extremo (caida %.1f / subida %.1f ATR, RSI7 %.0f)",
                            caida / atr, subida / atr, rsi);
      return sig;
     }
  };
