//+------------------------------------------------------------------+
//| SmcStrategy.mqh — Smart Money Concepts (estructura + POI).       |
//|                                                                  |
//| Modelo de entrada institucional clásico, en 5 pasos:             |
//|   1. ESTRUCTURA: se recorre el gráfico de viejo a nuevo marcando |
//|      swings fractales. Un cierre más allá del último swing       |
//|      confirmado = quiebre. Si va contra el quiebre anterior es   |
//|      CHoCH (cambio de carácter); si lo acompaña, BOS.            |
//|   2. DESPLAZAMIENTO: solo cuenta el quiebre cuya vela tiene      |
//|      rango >= mult × rango medio (movimiento con intención, no   |
//|      goteo lateral).                                             |
//|   3. POI: dentro de la pierna se busca el Order Block (última    |
//|      vela contraria antes del impulso) y el FVG / imbalance      |
//|      (hueco de 3 velas). Si se solapan, la zona se refina a la   |
//|      intersección.                                               |
//|   4. FILTROS: estructura H1 a favor, zona SIN mitigar, precio en |
//|      descuento (compras) o premium (ventas), y opcionalmente     |
//|      barrido de liquidez previo (la pierna nace cazando stops).  |
//|   5. ENTRADA: la vela M15 cerrada toca la zona y cierra a favor. |
//|      SL bajo/sobre la zona (o el barrido) + colchón ATR.         |
//|                                                                  |
//| Índices: los arrays van 0 = última vela CERRADA, mayor = más     |
//| viejo. Nunca se lee la vela en formación.                        |
//+------------------------------------------------------------------+
#property strict
#include "AtlasTypes.mqh"

//=== Helpers puros ================================================
//--- Sin dependencia del broker: Atlas_SelfTest los verifica con
//--- arrays construidos a mano.

//--- ¿La barra i es un máximo fractal de amplitud k?
//--- Empate del lado nuevo NO cuenta: evita marcar dos swings iguales.
bool SmcIsSwingHigh(const double &hi[], const int i, const int k, const int total)
  {
   if(k < 1 || i < k || i + k >= total)
      return false;
   double h = hi[i];
   for(int j = 1; j <= k; j++)
     {
      if(hi[i - j] >= h)
         return false;
      if(hi[i + j] > h)
         return false;
     }
   return true;
  }

//--- ¿La barra i es un mínimo fractal de amplitud k?
bool SmcIsSwingLow(const double &lo[], const int i, const int k, const int total)
  {
   if(k < 1 || i < k || i + k >= total)
      return false;
   double l = lo[i];
   for(int j = 1; j <= k; j++)
     {
      if(lo[i - j] <= l)
         return false;
      if(lo[i + j] < l)
         return false;
     }
   return true;
  }

//--- Mitad inferior del rango (descuento): donde se compra
bool SmcInDiscount(const double price, const double legLow, const double legHigh)
  {
   if(legHigh <= legLow)
      return false;
   return (price <= legLow + 0.5 * (legHigh - legLow));
  }

//--- Mitad superior del rango (premium): donde se vende
bool SmcInPremium(const double price, const double legLow, const double legHigh)
  {
   if(legHigh <= legLow)
      return false;
   return (price >= legLow + 0.5 * (legHigh - legLow));
  }

//--- Intersección de dos zonas. False si no se solapan.
bool SmcOverlap(const double aTop, const double aBottom,
                const double bTop, const double bBottom,
                double &outTop, double &outBottom)
  {
   outTop    = MathMin(aTop, bTop);
   outBottom = MathMax(aBottom, bBottom);
   return (outTop > outBottom);
  }

//--- Rango medio de 'count' velas a partir de 'from' (hacia atrás en el tiempo)
double SmcMeanRange(const double &hi[], const double &lo[],
                    const int from, const int count, const int total)
  {
   double sum = 0.0;
   int    n   = 0;
   for(int i = from; i < from + count && i < total; i++)
     {
      if(i < 0)
         continue;
      sum += (hi[i] - lo[i]);
      n++;
     }
   return (n > 0 ? sum / n : 0.0);
  }

//+------------------------------------------------------------------+
//| Recorre la estructura de la vela más vieja a la más nueva y      |
//| devuelve el ÚLTIMO quiebre válido.                               |
//|   dir      : +1 alcista, -1 bajista, 0 sin quiebre               |
//|   breakBar : índice de la vela que quebró                        |
//|   originIdx: índice del swing que originó la pierna              |
//|   prevDir  : dirección del quiebre anterior (para BOS vs CHoCH)  |
//| Un swing formado en j solo es conocible en j-k: el recorrido lo  |
//| respeta, así que no mira el futuro.                              |
//+------------------------------------------------------------------+
void SmcScanStructure(const double &hi[], const double &lo[], const double &cl[],
                      const int total, const int k, const double dispMult,
                      int &dir, int &breakBar, int &originIdx, int &prevDir)
  {
   dir = 0; breakBar = -1; originIdx = -1; prevDir = 0;

   double activeHigh = 0.0, activeLow = 0.0;
   int    activeHighIdx = -1, activeLowIdx = -1;

   for(int b = total - 1; b >= 0; b--)
     {
      //--- Confirmación de swings: en la barra b ya se conoce el swing de b+k
      int j = b + k;
      if(j < total)
        {
         if(SmcIsSwingHigh(hi, j, k, total))
           {
            activeHigh    = hi[j];
            activeHighIdx = j;
           }
         if(SmcIsSwingLow(lo, j, k, total))
           {
            activeLow    = lo[j];
            activeLowIdx = j;
           }
        }

      //--- Desplazamiento: la vela del quiebre debe tener intención
      bool hasDisp = true;
      if(dispMult > 0.0)
        {
         double mr = SmcMeanRange(hi, lo, b + 1, 20, total);
         if(mr > 0.0 && (hi[b] - lo[b]) < dispMult * mr)
            hasDisp = false;
        }
      if(!hasDisp)
         continue;                          // cierre sin fuerza: no rompe estructura

      if(activeHighIdx >= 0 && cl[b] > activeHigh)
        {
         prevDir       = dir;
         dir           = 1;
         breakBar      = b;
         originIdx     = activeLowIdx;      // la pierna nace en el último mínimo
         activeHighIdx = -1;                // consumido: espera un swing nuevo
        }
      else if(activeLowIdx >= 0 && cl[b] < activeLow)
        {
         prevDir      = dir;
         dir          = -1;
         breakBar     = b;
         originIdx    = activeHighIdx;
         activeLowIdx = -1;
        }
     }
  }

//+------------------------------------------------------------------+
class CSmcStrategy
  {
private:
   string            m_symbol;
   int               m_fractal;           // amplitud del swing
   int               m_lookback;          // velas M15 analizadas
   int               m_htfLookback;       // velas H1 analizadas
   int               m_sweepLookback;     // velas hacia atrás al buscar el barrido
   int               m_maxAgeBars;        // antigüedad máxima del quiebre
   double            m_dispMult;          // desplazamiento mínimo (× rango medio)
   double            m_slBufferAtr;       // colchón del SL (× ATR M15)
   double            m_maxSlAtr;          // descarta setups con SL desproporcionado
   bool              m_requireHtf;
   bool              m_requireSweep;
   bool              m_requireDiscount;
   bool              m_needRejection;
   bool              m_useFvg;
   bool              m_allowChoppy;
   int               m_hAtrM15;
   datetime          m_lastZoneTraded;    // zona ya operada (no repetir)
   datetime          m_pendingOrigin;     // zona de la señal en curso
   string            m_lastNote;          // estado legible para el dashboard

   bool CopyAtr(double &value)
     {
      double arr[];
      ArraySetAsSeries(arr, true);
      if(CopyBuffer(m_hAtrM15, 0, 1, 1, arr) != 1)
         return false;
      value = arr[0];
      return (value > 0.0);
     }

   //--- Vuelca las series OHLC en arrays planos (0 = última vela cerrada)
   bool Extract(const MqlRates &r[], const int total,
                double &hi[], double &lo[], double &op[], double &cl[])
     {
      if(ArrayResize(hi, total) != total || ArrayResize(lo, total) != total ||
         ArrayResize(op, total) != total || ArrayResize(cl, total) != total)
         return false;
      for(int i = 0; i < total; i++)
        {
         hi[i] = r[i].high;
         lo[i] = r[i].low;
         op[i] = r[i].open;
         cl[i] = r[i].close;
        }
      return true;
     }

   //--- Dirección de la estructura en H1 (sesgo mayor)
   int HtfDir()
     {
      MqlRates r[];
      ArraySetAsSeries(r, true);
      int total = CopyRates(m_symbol, PERIOD_H1, 1, m_htfLookback, r);
      if(total < 4 * m_fractal + 25)
         return 0;

      double hi[], lo[], op[], cl[];
      if(!Extract(r, total, hi, lo, op, cl))
         return 0;

      int dir = 0, bbar = -1, origin = -1, prevDir = 0;
      SmcScanStructure(hi, lo, cl, total, m_fractal, m_dispMult, dir, bbar, origin, prevDir);
      return dir;
     }

public:
   bool Init(const string symbol, const int fractal, const int lookback,
             const int maxAgeBars, const double dispMult, const double slBufferAtr,
             const double maxSlAtr, const bool requireHtf, const bool requireSweep,
             const bool requireDiscount, const bool needRejection,
             const bool useFvg, const bool allowChoppy)
     {
      m_symbol          = symbol;
      m_fractal         = (int)MathMax(1, fractal);
      m_lookback        = (int)MathMax(60, lookback);
      m_htfLookback     = (int)MathMax(60, lookback / 2);
      m_sweepLookback   = 50;
      m_maxAgeBars      = (int)MathMax(1, maxAgeBars);
      m_dispMult        = dispMult;
      m_slBufferAtr     = slBufferAtr;
      m_maxSlAtr        = (maxSlAtr > 0.0 ? maxSlAtr : 3.0);
      m_requireHtf      = requireHtf;
      m_requireSweep    = requireSweep;
      m_requireDiscount = requireDiscount;
      m_needRejection   = needRejection;
      m_useFvg          = useFvg;
      m_allowChoppy     = allowChoppy;
      m_lastZoneTraded  = 0;
      m_pendingOrigin   = 0;
      m_lastNote        = "sin estructura";
      m_hAtrM15         = iATR(symbol, PERIOD_M15, 14);
      return (m_hAtrM15 != INVALID_HANDLE);
     }

   void Release()
     {
      if(m_hAtrM15 != INVALID_HANDLE)
         IndicatorRelease(m_hAtrM15);
     }

   bool Ready()
     {
      if(BarsCalculated(m_hAtrM15) < 25)
         return false;
      if(Bars(m_symbol, PERIOD_M15) < m_lookback)
         return false;
      if(m_requireHtf && Bars(m_symbol, PERIOD_H1) < m_htfLookback)
         return false;
      return true;
     }

   //--- Estado legible del último análisis (dashboard/logs)
   string Note() { return m_lastNote; }

   //--- El EA la llama tras ejecutar: la zona no se vuelve a operar.
   //--- Tras un reinicio del EA esta marca se pierde, pero la zona queda
   //--- protegida igual: la vela que la tocó al entrar la deja "mitigada"
   //--- y el chequeo de frescura la rechaza sola.
   void MarkTraded()
     {
      if(m_pendingOrigin > 0)
         m_lastZoneTraded = m_pendingOrigin;
     }

   //--- Evalúa en cada vela M15 cerrada.
   SSignal Check(const ERegime regime)
     {
      SSignal sig;
      sig.dir         = SIGNAL_NONE;
      sig.sl_price    = 0.0;
      sig.reason      = "";
      m_pendingOrigin = 0;

      //--- La compresión es territorio de la ruptura asiática
      if(regime == REGIME_SQUEEZE)
        {
         m_lastNote = "en pausa (compresion)";
         return sig;
        }
      if(regime == REGIME_CHOPPY && !m_allowChoppy)
        {
         m_lastNote = "en pausa (lateral)";
         return sig;
        }

      MqlRates r[];
      ArraySetAsSeries(r, true);
      int total = CopyRates(m_symbol, PERIOD_M15, 1, m_lookback, r);
      if(total < 4 * m_fractal + 25)
        {
         m_lastNote = "historia insuficiente";
         return sig;
        }

      double hi[], lo[], op[], cl[];
      if(!Extract(r, total, hi, lo, op, cl))
         return sig;

      //--- 1) Estructura
      int dir = 0, bbar = -1, origin = -1, prevDir = 0;
      SmcScanStructure(hi, lo, cl, total, m_fractal, m_dispMult, dir, bbar, origin, prevDir);
      if(dir == 0 || bbar < 0 || origin <= bbar)
        {
         m_lastNote = "sin estructura definida";
         return sig;
        }

      string kind = ((prevDir != 0 && prevDir != dir) ? "CHoCH" : "BOS");
      m_lastNote  = kind + (dir == 1 ? " alcista" : " bajista") +
                    StringFormat(" hace %d velas", bbar);

      if(bbar > m_maxAgeBars)
        {
         m_lastNote += " (vencido)";
         return sig;
        }

      //--- Alineación con el régimen del detector
      if((regime == REGIME_TREND_UP   && dir != 1) ||
         (regime == REGIME_TREND_DOWN && dir != -1))
        {
         m_lastNote += " (contra el regimen)";
         return sig;
        }

      //--- 2) Sesgo mayor: la estructura H1 debe acompañar
      if(m_requireHtf)
        {
         int htf = HtfDir();
         if(htf == 0 || htf != dir)
           {
            m_lastNote += " (H1 no acompana)";
            return sig;
           }
        }

      //--- 3) POI: Order Block y FVG dentro de la pierna
      int obIdx = -1;
      for(int i = bbar + 1; i <= origin && i < total; i++)
        {
         bool contrary = (dir == 1 ? (cl[i] < op[i]) : (cl[i] > op[i]));
         if(contrary)
           {
            obIdx = i;
            break;
           }
        }
      if(obIdx < 0)
         obIdx = origin;                    // pierna sin vela contraria: usar el origen

      double zTop = hi[obIdx];
      double zBot = lo[obIdx];

      bool   hasFvg = false;
      double fTop = 0.0, fBot = 0.0;
      for(int i = bbar; i + 2 <= origin && i + 2 < total; i++)
        {
         if(dir == 1 && hi[i + 2] < lo[i])
           {
            fBot = hi[i + 2];
            fTop = lo[i];
            hasFvg = true;
            break;
           }
         if(dir == -1 && lo[i + 2] > hi[i])
           {
            fBot = hi[i];
            fTop = lo[i + 2];
            hasFvg = true;
            break;
           }
        }

      bool usedFvg = false;
      if(m_useFvg && hasFvg)
        {
         double oT = 0.0, oB = 0.0;
         if(SmcOverlap(zTop, zBot, fTop, fBot, oT, oB))
           {
            zTop    = oT;                   // zona refinada a la intersección
            zBot    = oB;
            usedFvg = true;
           }
        }
      if(zTop <= zBot)
         return sig;

      //--- No repetir la misma zona
      if(r[obIdx].time == m_lastZoneTraded)
        {
         m_lastNote += " (zona ya operada)";
         return sig;
        }

      //--- 4a) Premium / descuento sobre el rango de la pierna
      double legLow = DBL_MAX, legHigh = 0.0;
      for(int i = 0; i <= origin && i < total; i++)
        {
         legHigh = MathMax(legHigh, hi[i]);
         legLow  = MathMin(legLow, lo[i]);
        }
      if(legLow == DBL_MAX || legHigh <= legLow)
         return sig;

      if(m_requireDiscount)
        {
         //--- Se evalúa el borde MÁS CARO de la zona: el peor precio de entrada
         bool okZone = (dir == 1 ? SmcInDiscount(zTop, legLow, legHigh)
                                 : SmcInPremium(zBot, legLow, legHigh));
         if(!okZone)
           {
            m_lastNote += (dir == 1 ? " (zona fuera de descuento)" : " (zona fuera de premium)");
            return sig;
           }
        }

      //--- 4b) Barrido de liquidez: la pierna nació cazando stops
      bool swept = false;
      for(int j = origin + 1; j < total && j <= origin + m_sweepLookback; j++)
        {
         if(dir == 1)
           {
            if(!SmcIsSwingLow(lo, j, m_fractal, total))
               continue;
            if(lo[origin] < lo[j] && cl[origin] > lo[j])
              {
               swept = true;
               break;
              }
           }
         else
           {
            if(!SmcIsSwingHigh(hi, j, m_fractal, total))
               continue;
            if(hi[origin] > hi[j] && cl[origin] < hi[j])
              {
               swept = true;
               break;
              }
           }
        }
      if(m_requireSweep && !swept)
        {
         m_lastNote += " (sin barrido previo)";
         return sig;
        }

      //--- 4c) La zona debe estar FRESCA (sin mitigar) y no invalidada
      for(int i = bbar - 1; i >= 1; i--)
        {
         if(dir == 1)
           {
            if(cl[i] < zBot)
              {
               m_lastNote += " (zona invalidada)";
               return sig;
              }
            if(lo[i] <= zTop)
              {
               m_lastNote += " (zona ya mitigada)";
               return sig;
              }
           }
         else
           {
            if(cl[i] > zTop)
              {
               m_lastNote += " (zona invalidada)";
               return sig;
              }
            if(hi[i] >= zBot)
              {
               m_lastNote += " (zona ya mitigada)";
               return sig;
              }
           }
        }

      //--- 5) Disparo: la vela cerrada toca la zona y cierra a favor
      if(dir == 1)
        {
         if(!(lo[0] <= zTop && cl[0] > zBot))
           {
            m_lastNote += " (esperando retroceso a la zona)";
            return sig;
           }
         if(m_needRejection && cl[0] <= op[0])
           {
            m_lastNote += " (sin vela de rechazo)";
            return sig;
           }
        }
      else
        {
         if(!(hi[0] >= zBot && cl[0] < zTop))
           {
            m_lastNote += " (esperando retroceso a la zona)";
            return sig;
           }
         if(m_needRejection && cl[0] >= op[0])
           {
            m_lastNote += " (sin vela de rechazo)";
            return sig;
           }
        }

      //--- Stop loss: al otro lado de la zona (o del barrido) + colchón
      double atr = 0.0;
      if(!CopyAtr(atr))
         return sig;
      double point       = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double spreadPrice = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * point;
      double buffer      = spreadPrice + m_slBufferAtr * atr;

      double entry = (dir == 1 ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(m_symbol, SYMBOL_BID));
      if(entry <= 0.0)
        {
         m_lastNote += " (sin precio, reconectando)";
         return sig;                        // no perder la zona por una desconexion
        }

      double sl;
      if(dir == 1)
        {
         double base = (swept ? MathMin(zBot, lo[origin]) : zBot);
         sl = base - buffer;
         if(entry <= sl)
            return sig;
         if(entry - sl > m_maxSlAtr * atr)
           {
            m_lastNote += " (SL desproporcionado)";
            return sig;
           }
         sig.dir = SIGNAL_BUY;
        }
      else
        {
         double base = (swept ? MathMax(zTop, hi[origin]) : zTop);
         sl = base + buffer;
         if(sl <= entry)
            return sig;
         if(sl - entry > m_maxSlAtr * atr)
           {
            m_lastNote += " (SL desproporcionado)";
            return sig;
           }
         sig.dir = SIGNAL_SELL;
        }

      sig.sl_price    = sl;
      sig.reason      = "SMC " + kind + " " + (usedFvg ? "OB+FVG" : "OB") +
                        (swept ? " +barrido" : "");
      m_pendingOrigin = r[obIdx].time;
      m_lastNote      = "SENAL " + (dir == 1 ? "COMPRA" : "VENTA") + " — " + sig.reason;
      return sig;
     }
  };
