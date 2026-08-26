//+------------------------------------------------------------------+
//| TVRating.mqh — Réplica del "Technical Rating" de TradingView.    |
//| 26 votos: 15 medias móviles + 11 osciladores, cada uno -1/0/+1.  |
//| El promedio se mapea a la escala Venta fuerte .. Compra fuerte.  |
//| Todo se evalúa sobre velas CERRADAS (shift 1) del símbolo/TF.    |
//+------------------------------------------------------------------+
#property strict
#include "AtlasTypes.mqh"

class CTVRating
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;

   int               m_hSMA[6];
   int               m_hEMA[6];
   int               m_hIchimoku;
   int               m_hRSI;
   int               m_hStoch;
   int               m_hCCI;
   int               m_hADX;
   int               m_hAO;
   int               m_hMomentum;
   int               m_hMACD;
   int               m_hWPR;
   int               m_hBulls;
   int               m_hBears;

   double            m_lastAvg;

   //--- Copia 'count' valores desde la vela cerrada (shift 1) como serie
   bool CopySeries(const int handle, const int buffer, const int count, double &arr[])
     {
      ArraySetAsSeries(arr, true);
      return (CopyBuffer(handle, buffer, 1, count, arr) == count);
     }

   double WMA(const double &series[], const int period, const int start)
     {
      double sum = 0.0, wsum = 0.0;
      for(int i = 0; i < period; i++)
        {
         double w = period - i;
         sum  += series[start + i] * w;
         wsum += w;
        }
      return (wsum > 0.0 ? sum / wsum : 0.0);
     }

   int PriceVsLevel(const double close, const double level)
     {
      if(level <= 0.0)
         return 0;
      if(close > level) return  1;
      if(close < level) return -1;
      return 0;
     }

public:
   //--- Un objeto recien creado tiene los miembros en 0, y 0 NO es
   //--- INVALID_HANDLE: sin esto, Release() intentaria liberar el handle 0.
   CTVRating() { Invalidate(); }

   void Invalidate()
     {
      for(int i = 0; i < 6; i++)
        {
         m_hSMA[i] = INVALID_HANDLE;
         m_hEMA[i] = INVALID_HANDLE;
        }
      m_hIchimoku = INVALID_HANDLE; m_hRSI      = INVALID_HANDLE;
      m_hStoch    = INVALID_HANDLE; m_hCCI      = INVALID_HANDLE;
      m_hADX      = INVALID_HANDLE; m_hAO       = INVALID_HANDLE;
      m_hMomentum = INVALID_HANDLE; m_hMACD     = INVALID_HANDLE;
      m_hWPR      = INVALID_HANDLE; m_hBulls    = INVALID_HANDLE;
      m_hBears    = INVALID_HANDLE;
     }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      Release();                 // idempotente: reinicializar no fuga handles
      m_symbol = symbol;
      m_tf     = tf;
      m_lastAvg = 0.0;

      int periods[6] = {10, 20, 30, 50, 100, 200};
      for(int i = 0; i < 6; i++)
        {
         m_hSMA[i] = iMA(symbol, tf, periods[i], 0, MODE_SMA, PRICE_CLOSE);
         m_hEMA[i] = iMA(symbol, tf, periods[i], 0, MODE_EMA, PRICE_CLOSE);
         if(m_hSMA[i] == INVALID_HANDLE || m_hEMA[i] == INVALID_HANDLE)
            return false;
        }
      m_hIchimoku = iIchimoku(symbol, tf, 9, 26, 52);
      m_hRSI      = iRSI(symbol, tf, 14, PRICE_CLOSE);
      m_hStoch    = iStochastic(symbol, tf, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
      m_hCCI      = iCCI(symbol, tf, 20, PRICE_TYPICAL);
      m_hADX      = iADX(symbol, tf, 14);
      m_hAO       = iAO(symbol, tf);
      m_hMomentum = iMomentum(symbol, tf, 10, PRICE_CLOSE);
      m_hMACD     = iMACD(symbol, tf, 12, 26, 9, PRICE_CLOSE);
      m_hWPR      = iWPR(symbol, tf, 14);
      m_hBulls    = iBullsPower(symbol, tf, 13);
      m_hBears    = iBearsPower(symbol, tf, 13);

      return (m_hIchimoku != INVALID_HANDLE && m_hRSI != INVALID_HANDLE &&
              m_hStoch != INVALID_HANDLE && m_hCCI != INVALID_HANDLE &&
              m_hADX != INVALID_HANDLE && m_hAO != INVALID_HANDLE &&
              m_hMomentum != INVALID_HANDLE && m_hMACD != INVALID_HANDLE &&
              m_hWPR != INVALID_HANDLE && m_hBulls != INVALID_HANDLE &&
              m_hBears != INVALID_HANDLE);
     }

   void Release()
     {
      for(int i = 0; i < 6; i++)
        {
         if(m_hSMA[i] != INVALID_HANDLE) IndicatorRelease(m_hSMA[i]);
         if(m_hEMA[i] != INVALID_HANDLE) IndicatorRelease(m_hEMA[i]);
        }
      if(m_hIchimoku != INVALID_HANDLE) IndicatorRelease(m_hIchimoku);
      if(m_hRSI      != INVALID_HANDLE) IndicatorRelease(m_hRSI);
      if(m_hStoch    != INVALID_HANDLE) IndicatorRelease(m_hStoch);
      if(m_hCCI      != INVALID_HANDLE) IndicatorRelease(m_hCCI);
      if(m_hADX      != INVALID_HANDLE) IndicatorRelease(m_hADX);
      if(m_hAO       != INVALID_HANDLE) IndicatorRelease(m_hAO);
      if(m_hMomentum != INVALID_HANDLE) IndicatorRelease(m_hMomentum);
      if(m_hMACD     != INVALID_HANDLE) IndicatorRelease(m_hMACD);
      if(m_hWPR      != INVALID_HANDLE) IndicatorRelease(m_hWPR);
      if(m_hBulls    != INVALID_HANDLE) IndicatorRelease(m_hBulls);
      if(m_hBears    != INVALID_HANDLE) IndicatorRelease(m_hBears);
      Invalidate();              // no volver a liberar handles ya liberados
     }

   bool Ready()
     {
      if(Bars(m_symbol, m_tf) < 260)
         return false;
      for(int i = 0; i < 6; i++)
         if(BarsCalculated(m_hSMA[i]) < 210 || BarsCalculated(m_hEMA[i]) < 210)
            return false;
      return (BarsCalculated(m_hRSI) > 60 && BarsCalculated(m_hADX) > 60);
     }

   //--- VWMA(20) manual: media ponderada por volumen de ticks
   double VWMA20()
     {
      double closes[];
      long   vols[];
      ArraySetAsSeries(closes, true);
      ArraySetAsSeries(vols, true);
      if(CopyClose(m_symbol, m_tf, 1, 20, closes) != 20)   return 0.0;
      if(CopyTickVolume(m_symbol, m_tf, 1, 20, vols) != 20) return 0.0;
      double num = 0.0, den = 0.0;
      for(int i = 0; i < 20; i++)
        {
         num += closes[i] * (double)vols[i];
         den += (double)vols[i];
        }
      return (den > 0.0 ? num / den : 0.0);
     }

   //--- Hull MA(9) manual en la vela cerrada
   double Hull9()
     {
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(m_symbol, m_tf, 1, 15, closes) != 15)
         return 0.0;
      double x[3];
      for(int s = 0; s < 3; s++)
         x[s] = 2.0 * WMA(closes, 4, s) - WMA(closes, 9, s);
      double hull = (3.0 * x[0] + 2.0 * x[1] + 1.0 * x[2]) / 6.0;
      return hull;
     }

   //--- Stochastic RSI Fast (3,3,14,14) manual; devuelve K y D
   bool StochRSI(double &k, double &d)
     {
      double rsi[];
      if(!CopySeries(m_hRSI, 0, 19, rsi))
         return false;
      double kraw[5];
      for(int s = 0; s < 5; s++)
        {
         double mn = rsi[s], mx = rsi[s];
         for(int i = s; i < s + 14; i++)
           {
            if(rsi[i] < mn) mn = rsi[i];
            if(rsi[i] > mx) mx = rsi[i];
           }
         kraw[s] = (mx - mn > 0.0 ? (rsi[s] - mn) / (mx - mn) * 100.0 : 50.0);
        }
      double kk[3];
      for(int s = 0; s < 3; s++)
         kk[s] = (kraw[s] + kraw[s + 1] + kraw[s + 2]) / 3.0;
      k = kk[0];
      d = (kk[0] + kk[1] + kk[2]) / 3.0;
      return true;
     }

   //--- Ultimate Oscillator (7,14,28) manual
   double UltimateOsc()
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, m_tf, 1, 30, rates) != 30)
         return 50.0;
      double bp[29], tr[29];
      for(int i = 0; i < 29; i++)
        {
         double prevClose = rates[i + 1].close;
         double lo = MathMin(rates[i].low, prevClose);
         double hi = MathMax(rates[i].high, prevClose);
         bp[i] = rates[i].close - lo;
         tr[i] = hi - lo;
        }
      double sbp7 = 0, str7 = 0, sbp14 = 0, str14 = 0, sbp28 = 0, str28 = 0;
      for(int i = 0; i < 28; i++)
        {
         if(i < 7)  { sbp7 += bp[i];  str7 += tr[i]; }
         if(i < 14) { sbp14 += bp[i]; str14 += tr[i]; }
         sbp28 += bp[i];
         str28 += tr[i];
        }
      if(str7 <= 0.0 || str14 <= 0.0 || str28 <= 0.0)
         return 50.0;
      double a7 = sbp7 / str7, a14 = sbp14 / str14, a28 = sbp28 / str28;
      return 100.0 * (4.0 * a7 + 2.0 * a14 + a28) / 7.0;
     }

   //--- Calcula los 26 votos. Devuelve false si faltan datos.
   bool Votes(double &avg)
     {
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(m_symbol, m_tf, 1, 3, closes) != 3)
         return false;
      double close = closes[0];

      int sum = 0, count = 0;
      double b1[], b2[], b3[];

      //=== Grupo 1: medias móviles (15 votos) ===
      for(int i = 0; i < 6; i++)
        {
         if(CopySeries(m_hSMA[i], 0, 1, b1)) { sum += PriceVsLevel(close, b1[0]); count++; }
         if(CopySeries(m_hEMA[i], 0, 1, b1)) { sum += PriceVsLevel(close, b1[0]); count++; }
        }
      if(CopySeries(m_hIchimoku, 1, 1, b1))  { sum += PriceVsLevel(close, b1[0]); count++; }
      double vwma = VWMA20();
      if(vwma > 0.0) { sum += PriceVsLevel(close, vwma); count++; }
      double hull = Hull9();
      if(hull > 0.0) { sum += PriceVsLevel(close, hull); count++; }

      //=== Grupo 2: osciladores (11 votos) ===
      //--- RSI(14)
      if(CopySeries(m_hRSI, 0, 3, b1))
        {
         bool rising = b1[0] > b1[1];
         if(b1[0] < 30.0 && rising)       sum += 1;
         else if(b1[0] > 70.0 && !rising) sum -= 1;
         count++;
        }
      //--- Estocástico(14,3,3)
      if(CopySeries(m_hStoch, 0, 1, b1) && CopySeries(m_hStoch, 1, 1, b2))
        {
         if(b1[0] < 20.0 && b1[0] > b2[0])      sum += 1;
         else if(b1[0] > 80.0 && b1[0] < b2[0]) sum -= 1;
         count++;
        }
      //--- CCI(20)
      if(CopySeries(m_hCCI, 0, 3, b1))
        {
         bool rising = b1[0] > b1[1];
         if(b1[0] < -100.0 && rising)       sum += 1;
         else if(b1[0] > 100.0 && !rising)  sum -= 1;
         count++;
        }
      //--- ADX(14): fuerza + dirección
      if(CopySeries(m_hADX, 0, 1, b1) && CopySeries(m_hADX, 1, 1, b2) && CopySeries(m_hADX, 2, 1, b3))
        {
         if(b1[0] > 20.0)
           {
            if(b2[0] > b3[0])      sum += 1;
            else if(b3[0] > b2[0]) sum -= 1;
           }
         count++;
        }
      //--- Awesome Oscillator: cruce de cero o platillo
      if(CopySeries(m_hAO, 0, 3, b1))
        {
         if(b1[1] < 0.0 && b1[0] > 0.0)                                    sum += 1;
         else if(b1[1] > 0.0 && b1[0] < 0.0)                               sum -= 1;
         else if(b1[0] > 0.0 && b1[1] < b1[2] && b1[0] > b1[1])            sum += 1;
         else if(b1[0] < 0.0 && b1[1] > b1[2] && b1[0] < b1[1])            sum -= 1;
         count++;
        }
      //--- Momentum(10)
      if(CopySeries(m_hMomentum, 0, 3, b1))
        {
         if(b1[0] > b1[1])      sum += 1;
         else if(b1[0] < b1[1]) sum -= 1;
         count++;
        }
      //--- MACD(12,26,9): main vs signal
      if(CopySeries(m_hMACD, 0, 1, b1) && CopySeries(m_hMACD, 1, 1, b2))
        {
         if(b1[0] > b2[0])      sum += 1;
         else if(b1[0] < b2[0]) sum -= 1;
         count++;
        }
      //--- Stochastic RSI Fast
      double k, d;
      if(StochRSI(k, d))
        {
         if(k < 20.0 && k > d)      sum += 1;
         else if(k > 80.0 && k < d) sum -= 1;
         count++;
        }
      //--- Williams %R(14)
      if(CopySeries(m_hWPR, 0, 3, b1))
        {
         bool rising = b1[0] > b1[1];
         if(b1[0] < -80.0 && rising)        sum += 1;
         else if(b1[0] > -20.0 && !rising)  sum -= 1;
         count++;
        }
      //--- Bull/Bear Power(13)
      if(CopySeries(m_hBulls, 0, 2, b1) && CopySeries(m_hBears, 0, 2, b2))
        {
         double bbpNow  = b1[0] + b2[0];
         double bbpPrev = b1[1] + b2[1];
         if(bbpNow > 0.0 && bbpNow > bbpPrev)      sum += 1;
         else if(bbpNow < 0.0 && bbpNow < bbpPrev) sum -= 1;
         count++;
        }
      //--- Ultimate Oscillator(7,14,28)
      double uo = UltimateOsc();
      if(uo > 70.0)      sum += 1;
      else if(uo < 30.0) sum -= 1;
      count++;

      if(count < 20)
         return false;          // datos insuficientes para un rating confiable
      avg = (double)sum / (double)count;
      m_lastAvg = avg;
      return true;
     }

   //--- Rating en escala TradingView (NEUTRAL si faltan datos)
   ERating Get()
     {
      double avg = 0.0;
      if(!Votes(avg))
         return RATING_NEUTRAL;
      return RatingFromAverage(avg);
     }

   double LastAverage() const { return m_lastAvg; }
  };
