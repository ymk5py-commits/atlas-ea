//+------------------------------------------------------------------+
//| CrtStrategy.mqh — Candle Range Theory (ciclo AMD).               |
//|                                                                  |
//| Una vela de temporalidad mayor no es un punto: es un RANGO con    |
//| un ciclo adentro. Acumulacion (la vela previa define el rango),   |
//| Manipulacion (la siguiente purga un extremo cazando stops y       |
//| vuelve adentro) y Distribucion (el precio recorre hasta el        |
//| extremo OPUESTO). CRT opera la tercera fase.                      |
//|                                                                  |
//| Pasos:                                                            |
//|   1. RANGO: la vela C1 del TF elegido (H4 por defecto) fija       |
//|      maximo y minimo. Se descarta si es un doji sin recorrido o   |
//|      una vela gigante que ya se movio todo.                       |
//|   2. PURGA: la vela siguiente perfora un extremo. Si perfora los  |
//|      DOS, no es manipulacion limpia: se descarta. Si la purga es  |
//|      demasiado profunda tampoco es barrido, es ruptura.           |
//|   3. REGRESO: el precio cierra de vuelta DENTRO del rango, con    |
//|      vela de rechazo en M15.                                      |
//|   4. UBICACION: vender solo desde premium, comprar solo desde     |
//|      descuento (mitad del rango de C1).                           |
//|   5. OBJETIVO: el extremo opuesto de C1, que viaja en la senal    |
//|      como TP fijo. Si el recorrido no paga el riesgo minimo, no   |
//|      se opera.                                                    |
//|                                                                  |
//| Dos modos:                                                        |
//|   EN VIVO      C1 = ultima vela cerrada, la purga ocurre en la    |
//|                vela en formacion. Entrada temprana.               |
//|   CONFIRMADO   la vela que purgo ya CERRO dentro del rango.       |
//|                Mas seguro, entrada mas tarde.                     |
//+------------------------------------------------------------------+
#property strict
#include "AtlasTypes.mqh"

//=== Helpers puros (testeables sin broker) =========================

//--- Un rango sirve si tiene recorrido pero no se movio todo de una
bool CrtRangeValid(const double rangeSize, const double atr,
                   const double minMult, const double maxMult)
  {
   if(rangeSize <= 0.0 || atr <= 0.0)
      return false;
   return (rangeSize >= minMult * atr && rangeSize <= maxMult * atr);
  }

//--- La purga es barrido mientras no se coma demasiado del rango
bool CrtPurgeIsSweep(const double purgeDepth, const double rangeSize, const double maxPct)
  {
   if(rangeSize <= 0.0 || purgeDepth <= 0.0)
      return false;
   return (purgeDepth <= (maxPct / 100.0) * rangeSize);
  }

//--- Beneficio/riesgo del setup. 0 si la geometria es imposible.
double CrtRewardRisk(const double entry, const double sl, const double tp)
  {
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return 0.0;
   double reward = (sl > entry ? entry - tp : tp - entry);   // sl arriba = venta
   if(reward <= 0.0)
      return 0.0;
   return reward / risk;
  }

//+------------------------------------------------------------------+
class CCrtStrategy
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;                // TF de la vela-rango
   int               m_mode;              // 0 = en vivo, 1 = confirmado
   double            m_minRangeAtr;
   double            m_maxRangeAtr;
   double            m_maxPurgePct;       // profundidad max de la purga (% del rango)
   double            m_minRR;
   double            m_slBufferAtr;       // colchon del SL (× ATR M15)
   bool              m_requireEq;         // exigir premium/descuento
   bool              m_needRejection;
   bool              m_followRegime;      // no operar contra la tendencia H1
   int               m_hAtrTf;
   int               m_hAtrM15;
   datetime          m_lastRangeTraded;   // C1 ya operada
   datetime          m_pendingRange;
   string            m_lastNote;

   bool CopyAtr(const int handle, double &value)
     {
      double arr[];
      ArraySetAsSeries(arr, true);
      if(CopyBuffer(handle, 0, 1, 1, arr) != 1)
         return false;
      value = arr[0];
      return (value > 0.0);
     }

public:
   //--- Los miembros de un objeto recien creado valen 0, y 0 NO es
   //--- INVALID_HANDLE. Sin invalidar, Release() liberaria el handle 0.
   CCrtStrategy() { Invalidate(); }

   void Invalidate() { m_hAtrTf = INVALID_HANDLE; m_hAtrM15 = INVALID_HANDLE; }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const int mode,
             const double minRangeAtr, const double maxRangeAtr,
             const double maxPurgePct, const double minRR,
             const double slBufferAtr, const bool requireEq,
             const bool needRejection, const bool followRegime)
     {
      Release();                 // idempotente: reinicializar no fuga handles
      m_symbol          = symbol;
      m_tf              = (tf == PERIOD_CURRENT ? PERIOD_H4 : tf);
      m_mode            = (mode == 1 ? 1 : 0);
      m_minRangeAtr     = minRangeAtr;
      m_maxRangeAtr     = maxRangeAtr;
      m_maxPurgePct     = maxPurgePct;
      m_minRR           = minRR;
      m_slBufferAtr     = slBufferAtr;
      m_requireEq       = requireEq;
      m_needRejection   = needRejection;
      m_followRegime    = followRegime;
      m_lastRangeTraded = 0;
      m_pendingRange    = 0;
      m_lastNote        = "sin rango";
      m_hAtrTf          = iATR(symbol, m_tf, 14);
      m_hAtrM15         = iATR(symbol, PERIOD_M15, 14);
      return (m_hAtrTf != INVALID_HANDLE && m_hAtrM15 != INVALID_HANDLE);
     }

   void Release()
     {
      if(m_hAtrTf  != INVALID_HANDLE) IndicatorRelease(m_hAtrTf);
      if(m_hAtrM15 != INVALID_HANDLE) IndicatorRelease(m_hAtrM15);
      Invalidate();
     }

   bool Ready()
     {
      if(BarsCalculated(m_hAtrTf) < 20 || BarsCalculated(m_hAtrM15) < 20)
         return false;
      return (Bars(m_symbol, m_tf) > (m_mode == 0 ? 3 : 4));
     }

   string Note() { return m_lastNote; }

   //--- El EA la llama tras ejecutar: ese rango no se opera de nuevo
   void MarkTraded()
     {
      if(m_pendingRange > 0)
         m_lastRangeTraded = m_pendingRange;
     }

   //--- Evalua en cada vela M15 cerrada.
   SSignal Check(const ERegime regime)
     {
      SSignal sig;
      sig.dir        = SIGNAL_NONE;
      sig.sl_price   = 0.0;
      sig.tp_price   = 0.0;
      sig.reason     = "";
      m_pendingRange = 0;

      //--- 1) El rango: C1
      int c1 = (m_mode == 0 ? 1 : 2);
      int c2 = (m_mode == 0 ? 0 : 1);

      double rangeHigh = iHigh(m_symbol, m_tf, c1);
      double rangeLow  = iLow(m_symbol, m_tf, c1);
      datetime rangeTime = iTime(m_symbol, m_tf, c1);
      if(rangeHigh <= 0.0 || rangeLow <= 0.0 || rangeHigh <= rangeLow || rangeTime == 0)
        {
         m_lastNote = "sin vela-rango todavia";
         return sig;
        }
      if(rangeTime == m_lastRangeTraded)
        {
         m_lastNote = "rango ya operado";
         return sig;
        }

      double atrTf = 0.0, atrM15 = 0.0;
      if(!CopyAtr(m_hAtrTf, atrTf) || !CopyAtr(m_hAtrM15, atrM15))
         return sig;

      double rangeSize = rangeHigh - rangeLow;
      if(!CrtRangeValid(rangeSize, atrTf, m_minRangeAtr, m_maxRangeAtr))
        {
         m_lastNote = (rangeSize < m_minRangeAtr * atrTf ? "rango sin recorrido"
                                                         : "rango demasiado grande");
         return sig;
        }

      //--- 2) La purga: C2
      double purgeHigh = iHigh(m_symbol, m_tf, c2);
      double purgeLow  = iLow(m_symbol, m_tf, c2);
      if(purgeHigh <= 0.0 || purgeLow <= 0.0)
         return sig;

      bool sweptHigh = (purgeHigh > rangeHigh);
      bool sweptLow  = (purgeLow  < rangeLow);
      if(sweptHigh && sweptLow)
        {
         m_lastNote = "purga de los dos lados (no es manipulacion limpia)";
         return sig;
        }
      if(!sweptHigh && !sweptLow)
        {
         m_lastNote = "esperando la purga de un extremo";
         return sig;
        }

      ESignalDir dir = (sweptHigh ? SIGNAL_SELL : SIGNAL_BUY);

      double purgeDepth = (sweptHigh ? purgeHigh - rangeHigh : rangeLow - purgeLow);
      if(!CrtPurgeIsSweep(purgeDepth, rangeSize, m_maxPurgePct))
        {
         m_lastNote = "purga demasiado profunda (parece ruptura real)";
         return sig;
        }

      //--- Alineacion con el regimen: no pelear la tendencia de H1
      if(m_followRegime)
        {
         if((regime == REGIME_TREND_UP   && dir == SIGNAL_SELL) ||
            (regime == REGIME_TREND_DOWN && dir == SIGNAL_BUY))
           {
            m_lastNote = "purga a contramano del regimen";
            return sig;
           }
        }

      //--- 3) El regreso: en modo confirmado la vela de purga ya cerro dentro
      if(m_mode == 1)
        {
         double closeC2 = iClose(m_symbol, m_tf, c2);
         if(closeC2 <= 0.0)
            return sig;
         if((dir == SIGNAL_SELL && closeC2 >= rangeHigh) ||
            (dir == SIGNAL_BUY  && closeC2 <= rangeLow))
           {
            m_lastNote = "la vela de purga cerro fuera del rango";
            return sig;
           }
        }

      //--- Confirmacion en la vela M15 cerrada
      double o15 = iOpen(m_symbol, PERIOD_M15, 1);
      double c15 = iClose(m_symbol, PERIOD_M15, 1);
      if(o15 <= 0.0 || c15 <= 0.0)
         return sig;

      if(dir == SIGNAL_SELL)
        {
         if(c15 >= rangeHigh)
           {
            m_lastNote = "el precio sigue fuera del rango";
            return sig;
           }
         if(m_needRejection && c15 >= o15)
           {
            m_lastNote = "sin vela de rechazo en M15";
            return sig;
           }
        }
      else
        {
         if(c15 <= rangeLow)
           {
            m_lastNote = "el precio sigue fuera del rango";
            return sig;
           }
         if(m_needRejection && c15 <= o15)
           {
            m_lastNote = "sin vela de rechazo en M15";
            return sig;
           }
        }

      //--- 4) Premium / descuento del rango de C1
      if(m_requireEq)
        {
         bool okZone = (dir == SIGNAL_SELL ? PriceInPremium(c15, rangeLow, rangeHigh)
                                           : PriceInDiscount(c15, rangeLow, rangeHigh));
         if(!okZone)
           {
            m_lastNote = "el precio ya cruzo el equilibrio del rango";
            return sig;
           }
        }

      //--- 5) Objetivo: el extremo opuesto. Debe pagar el riesgo minimo.
      double entry = (dir == SIGNAL_BUY ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                                        : SymbolInfoDouble(m_symbol, SYMBOL_BID));
      if(entry <= 0.0)
        {
         m_lastNote = "sin precio (reconectando)";
         return sig;
        }

      double point       = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double spreadPrice = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * point;
      double buffer      = spreadPrice + m_slBufferAtr * atrM15;

      double sl = (dir == SIGNAL_SELL ? purgeHigh + buffer : purgeLow - buffer);
      double tp = (dir == SIGNAL_SELL ? rangeLow : rangeHigh);

      if((dir == SIGNAL_SELL && (sl <= entry || tp >= entry)) ||
         (dir == SIGNAL_BUY  && (sl >= entry || tp <= entry)))
        {
         m_lastNote = "geometria invalida (el precio ya paso el objetivo)";
         return sig;
        }

      double rr = CrtRewardRisk(entry, sl, tp);
      if(rr < m_minRR)
        {
         m_lastNote = StringFormat("recorrido insuficiente (%.1fR, minimo %.1fR)", rr, m_minRR);
         return sig;
        }

      sig.dir        = dir;
      sig.sl_price   = sl;
      sig.tp_price   = tp;                 // el TradeManager lo respeta como TP fijo
      sig.reason     = (dir == SIGNAL_SELL ? "CRT purga del maximo" : "CRT purga del minimo");
      m_pendingRange = rangeTime;
      m_lastNote     = StringFormat("SENAL %s — %s (%.1fR al extremo opuesto)",
                                    (dir == SIGNAL_SELL ? "VENTA" : "COMPRA"),
                                    sig.reason, rr);
      return sig;
     }
  };
