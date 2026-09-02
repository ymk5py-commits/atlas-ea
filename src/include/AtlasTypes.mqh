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
//--- Tipo de setup (para el plan de trading y las estadisticas)
enum ESetupType
  {
   SETUP_NONE,          // sin clasificar
   SETUP_RUPTURA,       // el precio rompe niveles clave
   SETUP_PULLBACK,      // retroceso dentro de la tendencia
   SETUP_MOMENTUM,      // aceleracion fuerte del precio
   SETUP_CONTINUACION,  // la estructura se mantiene (BOS)
   SETUP_REVERSION      // posible giro (CHoCH, purga, regresion)
  };

//--- Señal emitida por una estrategia = PLAN DE TRADING completo.
//--- Esquema: la estrategia no devuelve solo "compra/vende", devuelve la
//--- idea entera: zona de entrada, objetivo, stop, nivel que la invalida,
//--- tipo de setup, temporalidad y una confianza 0-100 (si la puntua).
struct SSignal
  {
   ESignalDir        dir;
   double            sl_price;     // stop loss propuesto (precio)
   double            tp_price;     // objetivo fijo; 0 = lo gestiona el TradeManager
   string            reason;       // descripción para log/notificación
   //--- plan de trading (v2.1)
   double            zone_lo;      // zona de entrada; 0/0 = entrada a mercado sin zona
   double            zone_hi;
   double            invalidation; // nivel cuyo CIERRE anula la idea; 0 = el propio SL
   int               score;        // confianza 0-100; -1 = la estrategia no puntua
   ESetupType        setup;
   string            timeframe;    // "M1", "M15", "H4"...
  };

//--- Deja una señal en su estado neutro. TODA estrategia arranca Check() acá.
void ResetSignal(SSignal &s)
  {
   s.dir          = SIGNAL_NONE;
   s.sl_price     = 0.0;
   s.tp_price     = 0.0;
   s.reason       = "";
   s.zone_lo      = 0.0;
   s.zone_hi      = 0.0;
   s.invalidation = 0.0;
   s.score        = -1;
   s.setup        = SETUP_NONE;
   s.timeframe    = "";
  }

int ClampScore(const int score)
  {
   if(score < 0)   return 0;
   if(score > 100) return 100;
   return score;
  }

//--- Escala de confianza del esquema: ALTA / MEDIA / BAJA
string ConfidenceLabel(const int score)
  {
   if(score < 0)   return "-";
   if(score >= 70) return "ALTA";
   if(score >= 45) return "MEDIA";
   return "BAJA";
  }

string SetupTypeToString(const ESetupType t)
  {
   switch(t)
     {
      case SETUP_RUPTURA:      return "ruptura";
      case SETUP_PULLBACK:     return "pullback";
      case SETUP_MOMENTUM:     return "momentum";
      case SETUP_CONTINUACION: return "continuacion";
      case SETUP_REVERSION:    return "reversion";
     }
   return "sin clasificar";
  }

//--- Beneficio/riesgo del plan. Con objetivo fijo se mide contra el; sin
//--- objetivo (gestion por parcial + trailing) se informa el R nominal.
double PlanRewardRisk(const double entry, const double sl, const double tp, const double nominalRR)
  {
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return 0.0;
   if(tp <= 0.0)
      return nominalRR;
   double reward = (sl > entry ? entry - tp : tp - entry);
   return (reward > 0.0 ? reward / risk : 0.0);
  }

//+------------------------------------------------------------------+
//| Mitad inferior del rango (descuento): la zona donde se compra.   |
//| Mitad superior (premium): donde se vende. El equilibrio (50%)    |
//| cuenta para ambos lados.                                         |
//+------------------------------------------------------------------+
bool PriceInDiscount(const double price, const double rangeLow, const double rangeHigh)
  {
   if(rangeHigh <= rangeLow)
      return false;
   return (price <= rangeLow + 0.5 * (rangeHigh - rangeLow));
  }

bool PriceInPremium(const double price, const double rangeLow, const double rangeHigh)
  {
   if(rangeHigh <= rangeLow)
      return false;
   return (price >= rangeLow + 0.5 * (rangeHigh - rangeLow));
  }

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
