//+------------------------------------------------------------------+
//| AtlasTypes.mqh — Tipos, enums y helpers compartidos de ATLAS EA  |
//+------------------------------------------------------------------+
#property copyright "ATLAS EA"
#property strict

#define ATLAS_MAGIC      20260803
#define ATLAS_GV_PREFIX  "ATLAS_"

//--- Régimen de mercado detectado
enum ERegime
  {
   REGIME_TREND_UP,     // tendencia alcista
   REGIME_TREND_DOWN,   // tendencia bajista
   REGIME_SQUEEZE,      // compresión de volatilidad (pre-ruptura)
   REGIME_CHOPPY        // lateral sucio: no operar
  };

//--- Rating técnico (réplica escala TradingView)
enum ERating
  {
   RATING_STRONG_SELL = -2,
   RATING_SELL        = -1,
   RATING_NEUTRAL     =  0,
   RATING_BUY         =  1,
   RATING_STRONG_BUY  =  2
  };

//--- Dirección de señal
enum ESignalDir
  {
   SIGNAL_NONE =  0,
   SIGNAL_BUY  =  1,
   SIGNAL_SELL = -1
  };

//--- Señal emitida por una estrategia
struct SSignal
  {
   ESignalDir        dir;
   double            sl_price;   // stop loss propuesto (precio)
   string            reason;     // descripción para log/notificación
  };

//+------------------------------------------------------------------+
//| Convierte el promedio de votos (-1..+1) a la escala TradingView  |
//+------------------------------------------------------------------+
ERating RatingFromAverage(const double avg)
  {
   if(avg >= 0.5)   return RATING_STRONG_BUY;
   if(avg >= 0.1)   return RATING_BUY;
   if(avg > -0.1)   return RATING_NEUTRAL;
   if(avg > -0.5)   return RATING_SELL;
   return RATING_STRONG_SELL;
  }

//+------------------------------------------------------------------+
//| Texto corto de un rating (para dashboard y logs)                 |
//+------------------------------------------------------------------+
string RatingToString(const ERating r)
  {
   switch(r)
     {
      case RATING_STRONG_BUY:  return "COMPRA FUERTE";
      case RATING_BUY:         return "COMPRA";
      case RATING_NEUTRAL:     return "NEUTRAL";
      case RATING_SELL:        return "VENTA";
      case RATING_STRONG_SELL: return "VENTA FUERTE";
     }
   return "?";
  }

//+------------------------------------------------------------------+
//| Texto corto de un régimen                                        |
//+------------------------------------------------------------------+
string RegimeToString(const ERegime r)
  {
   switch(r)
     {
      case REGIME_TREND_UP:   return "TENDENCIA ALCISTA";
      case REGIME_TREND_DOWN: return "TENDENCIA BAJISTA";
      case REGIME_SQUEEZE:    return "COMPRESION";
      case REGIME_CHOPPY:     return "LATERAL (no operar)";
     }
   return "?";
  }

//+------------------------------------------------------------------+
//| True una sola vez por vela nueva del símbolo en el timeframe dado|
//| 'last' guarda el open time de la última vela vista               |
//+------------------------------------------------------------------+
bool NewBar(const string symbol, const ENUM_TIMEFRAMES tf, datetime &last)
  {
   datetime t = iTime(symbol, tf, 0);
   if(t == 0)
      return false;               // historia aún no cargada
   if(t == last)
      return false;
   last = t;
   return true;
  }

bool NewM15Bar(const string symbol, datetime &last)
  {
   return NewBar(symbol, PERIOD_M15, last);
  }

//+------------------------------------------------------------------+
//| Fecha (día) de un datetime, sin hora — para rollovers diarios    |
//+------------------------------------------------------------------+
datetime DateOf(const datetime t)
  {
   return t - (t % 86400);
  }
