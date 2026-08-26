//+------------------------------------------------------------------+
//| RegimeDetector.mqh — Clasifica el mercado del símbolo en:        |
//| TENDENCIA (ADX H1) · COMPRESION (Bollinger M15 angosto) · CHOPPY |
//+------------------------------------------------------------------+
#property strict
#include "AtlasTypes.mqh"

class CRegimeDetector
  {
private:
   string            m_symbol;
   double            m_adxThreshold;      // ADX mínimo para tendencia
   double            m_squeezeRatio;      // ancho BB < ratio × promedio → squeeze
   int               m_hADX;              // ADX(14) en H1
   int               m_hBB;               // Bollinger(20,2) en M15

   bool CopyOne(const int handle, const int buffer, const int shift, double &value)
     {
      double arr[];
      ArraySetAsSeries(arr, true);
      if(CopyBuffer(handle, buffer, shift, 1, arr) != 1)
         return false;
      value = arr[0];
      return true;
     }

public:
   //--- Los miembros de un objeto recien creado valen 0, y 0 NO es
   //--- INVALID_HANDLE. Sin invalidar, Release() liberaria el handle 0.
   CRegimeDetector() { Invalidate(); }

   void Invalidate() { m_hADX = INVALID_HANDLE; m_hBB = INVALID_HANDLE; }

   bool Init(const string symbol, const double adxThreshold, const double squeezeRatio)
     {
      Release();                 // idempotente: reinicializar no fuga handles
      m_symbol       = symbol;
      m_adxThreshold = adxThreshold;
      m_squeezeRatio = squeezeRatio;
      m_hADX = iADX(symbol, PERIOD_H1, 14);
      m_hBB  = iBands(symbol, PERIOD_M15, 20, 0, 2.0, PRICE_CLOSE);
      return (m_hADX != INVALID_HANDLE && m_hBB != INVALID_HANDLE);
     }

   void Release()
     {
      if(m_hADX != INVALID_HANDLE) IndicatorRelease(m_hADX);
      if(m_hBB  != INVALID_HANDLE) IndicatorRelease(m_hBB);
      Invalidate();
     }

   bool Ready()
     {
      return (BarsCalculated(m_hADX) > 30 && BarsCalculated(m_hBB) > 120);
     }

   ERegime Detect()
     {
      double adx, diPlus, diMinus;
      if(!CopyOne(m_hADX, 0, 1, adx) || !CopyOne(m_hADX, 1, 1, diPlus) ||
         !CopyOne(m_hADX, 2, 1, diMinus))
         return REGIME_CHOPPY;

      if(adx > m_adxThreshold)
        {
         if(diPlus > diMinus)
            return REGIME_TREND_UP;
         if(diMinus > diPlus)
            return REGIME_TREND_DOWN;
        }

      //--- Compresión: ancho de Bollinger vs promedio de las últimas 96 velas
      double upper[], lower[], middle[];
      ArraySetAsSeries(upper, true);
      ArraySetAsSeries(lower, true);
      ArraySetAsSeries(middle, true);
      if(CopyBuffer(m_hBB, 1, 1, 97, upper) != 97 ||
         CopyBuffer(m_hBB, 2, 1, 97, lower) != 97 ||
         CopyBuffer(m_hBB, 0, 1, 97, middle) != 97)
         return REGIME_CHOPPY;

      double widthNow = (middle[0] > 0.0 ? (upper[0] - lower[0]) / middle[0] : 0.0);
      double avgWidth = 0.0;
      int    n = 0;
      for(int i = 1; i < 97; i++)
        {
         if(middle[i] > 0.0)
           {
            avgWidth += (upper[i] - lower[i]) / middle[i];
            n++;
           }
        }
      if(n < 48 || widthNow <= 0.0)
         return REGIME_CHOPPY;
      avgWidth /= n;

      if(widthNow < m_squeezeRatio * avgWidth)
         return REGIME_SQUEEZE;

      return REGIME_CHOPPY;
     }
  };
