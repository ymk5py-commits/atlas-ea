//+------------------------------------------------------------------+
//| TradeManager.mqh — Ejecución y gestión de posiciones:            |
//| apertura con SL/TP, break-even, cierre parcial, trailing por ATR,|
//| cierre masivo y reconciliación tras reinicios.                   |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
#include "AtlasTypes.mqh"
#include "Notifier.mqh"

#define ATLAS_GV_ISL  ATLAS_GV_PREFIX + "ISL_"   // SL inicial por ticket
#define ATLAS_GV_IV   ATLAS_GV_PREFIX + "IV_"    // volumen inicial por ticket

class CTradeManager
  {
private:
   CTrade            m_trade;
   CNotifier        *m_notifier;
   double            m_rr;              // TP objetivo (en R) cuando no hay parcial
   double            m_beTriggerR;      // R para mover a break-even
   double            m_partialR;        // R para el cierre parcial
   double            m_trailAtrMult;    // multiplicador ATR del trailing

   string GvISL(const ulong ticket) const { return ATLAS_GV_ISL + IntegerToString((long)ticket); }
   string GvIV(const ulong ticket)  const { return ATLAS_GV_IV  + IntegerToString((long)ticket); }

   double NormPrice(const string symbol, const double price) const
     {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      return NormalizeDouble(price, digits);
     }

   //--- Registra SL/volumen inicial de posiciones que no lo tengan aún
   void RegisterInitialState()
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != ATLAS_MAGIC)
            continue;
         if(!GlobalVariableCheck(GvISL(ticket)))
           {
            double sl = PositionGetDouble(POSITION_SL);
            GlobalVariableSet(GvISL(ticket), sl);
            m_notifier.Log(StringFormat("Reconcile: ticket %I64u adoptado, SL inicial registrado %.5f", ticket, sl));
           }
         if(!GlobalVariableCheck(GvIV(ticket)))
            GlobalVariableSet(GvIV(ticket), PositionGetDouble(POSITION_VOLUME));
        }
     }

   //--- Borra variables globales de tickets que ya no existen
   void CleanOrphanGVs()
     {
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
        {
         string name = GlobalVariableName(i);
         ulong ticket = 0;
         if(StringFind(name, ATLAS_GV_ISL) == 0)
            ticket = (ulong)StringToInteger(StringSubstr(name, StringLen(ATLAS_GV_ISL)));
         else if(StringFind(name, ATLAS_GV_IV) == 0)
            ticket = (ulong)StringToInteger(StringSubstr(name, StringLen(ATLAS_GV_IV)));
         else
            continue;
         if(ticket > 0 && !PositionSelectByTicket(ticket))
            GlobalVariableDel(name);
        }
     }

public:
   void Init(const int deviationPoints, const double rr, const double beTriggerR,
             const double partialR, const double trailAtrMult, CNotifier *notifier)
     {
      m_trade.SetExpertMagicNumber(ATLAS_MAGIC);
      m_trade.SetDeviationInPoints(deviationPoints);
      m_trade.SetTypeFillingBySymbol(_Symbol);
      m_rr           = rr;
      m_beTriggerR   = beTriggerR;
      m_partialR     = partialR;
      m_trailAtrMult = trailAtrMult;
      m_notifier     = notifier;
     }

   void Reconcile()
     {
      RegisterInitialState();
      CleanOrphanGVs();
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket != 0 && PositionGetInteger(POSITION_MAGIC) == ATLAS_MAGIC)
            n++;
        }
      if(n > 0)
         m_notifier.Notify(StringFormat("Reinicio: %d posicion(es) re-adoptada(s), gestion activa.", n));
     }

   //--- Apertura con reintentos. Devuelve true si se ejecutó.
   bool Open(const string symbol, const SSignal &sig, const double lots)
     {
      if(sig.dir == SIGNAL_NONE || lots <= 0.0)
         return false;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      long   stopsLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

      double entry = (sig.dir == SIGNAL_BUY ? ask : bid);
      double sl    = NormPrice(symbol, sig.sl_price);
      double slDist = MathAbs(entry - sl);

      if(slDist < stopsLevel * point + point)
        {
         m_notifier.Log(symbol + ": SL demasiado cerca (stops level del broker). Señal descartada.");
         return false;
        }

      //--- TP: con lote partible se gestiona por parcial+trailing (sin TP fijo)
      double minPartial = 2.0 * SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double tp = 0.0;
      if(lots < minPartial)
         tp = NormPrice(symbol, sig.dir == SIGNAL_BUY ? entry + m_rr * slDist
                                                      : entry - m_rr * slDist);

      bool ok = false;
      for(int attempt = 1; attempt <= 3 && !ok; attempt++)
        {
         if(sig.dir == SIGNAL_BUY)
            ok = m_trade.Buy(lots, symbol, 0.0, sl, tp, "ATLAS " + sig.reason);
         else
            ok = m_trade.Sell(lots, symbol, 0.0, sl, tp, "ATLAS " + sig.reason);

         uint rc = m_trade.ResultRetcode();
         if(!ok)
           {
            if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
               rc == TRADE_RETCODE_PRICE_OFF)
              {
               m_notifier.Log(StringFormat("%s: retcode %u, reintento %d/3", symbol, rc, attempt));
               Sleep(500);
              }
            else
              {
               m_notifier.Notify(StringFormat("%s: orden RECHAZADA (retcode %u: %s)",
                                              symbol, rc, m_trade.ResultRetcodeDescription()));
               return false;
              }
           }
        }
      if(!ok)
        {
         m_notifier.Notify(symbol + ": orden fallida tras 3 reintentos.");
         return false;
        }

      RegisterInitialState();
      m_notifier.Notify(StringFormat("%s %s %.2f lotes @ %.5f | SL %.5f%s | %s",
                        symbol, (sig.dir == SIGNAL_BUY ? "COMPRA" : "VENTA"), lots,
                        m_trade.ResultPrice(), sl,
                        (tp > 0.0 ? " | TP " + DoubleToString(tp, 5) : " | gestion parcial+trailing"),
                        sig.reason));
      return true;
     }

   //--- Gestión de posiciones abiertas del símbolo (llamar cada timer)
   void Manage(const string symbol, const double atr)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != ATLAS_MAGIC)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol)
            continue;

         long   ptype  = PositionGetInteger(POSITION_TYPE);
         double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
         double slNow  = PositionGetDouble(POSITION_SL);
         double tpNow  = PositionGetDouble(POSITION_TP);
         double volNow = PositionGetDouble(POSITION_VOLUME);
         bool   isBuy  = (ptype == POSITION_TYPE_BUY);

         double isl = GlobalVariableCheck(GvISL(ticket)) ? GlobalVariableGet(GvISL(ticket)) : slNow;
         double iv  = GlobalVariableCheck(GvIV(ticket))  ? GlobalVariableGet(GvIV(ticket))  : volNow;
         double riskDist = MathAbs(entry - isl);
         if(riskDist <= 0.0)
            continue;

         double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double bid    = SymbolInfoDouble(symbol, SYMBOL_BID);
         double ask    = SymbolInfoDouble(symbol, SYMBOL_ASK);
         double price  = (isBuy ? bid : ask);              // precio de cierre
         double r      = (isBuy ? price - entry : entry - price) / riskDist;
         long   spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);

         //--- 1) Break-even
         bool beDone = (isBuy ? slNow >= entry : (slNow > 0.0 && slNow <= entry));
         if(!beDone && r >= m_beTriggerR)
           {
            double bePrice = NormPrice(symbol, isBuy ? entry + (spread + 1) * point
                                                     : entry - (spread + 1) * point);
            if(m_trade.PositionModify(ticket, bePrice, tpNow))
              {
               m_notifier.Notify(StringFormat("%s: break-even activado (+%.1fR). Ya no puede perder.", symbol, r));
               slNow  = bePrice;
               beDone = true;
              }
           }

         //--- 2) Cierre parcial (solo si el volumen inicial lo permite)
         double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
         if(iv >= 2.0 * vmin && volNow >= iv - step / 2.0 && r >= m_partialR)
           {
            double half = MathFloor((iv / 2.0) / step) * step;
            if(half >= vmin && m_trade.PositionClosePartial(ticket, half))
               m_notifier.Notify(StringFormat("%s: parcial 50%% cerrado en +%.1fR, el resto corre con trailing.", symbol, r));
           }

         //--- 3) Trailing chandelier tras break-even
         if(beDone && atr > 0.0)
           {
            datetime opentime = (datetime)PositionGetInteger(POSITION_TIME);
            int openShift = iBarShift(symbol, PERIOD_M15, opentime);
            if(openShift > 0)
              {
               double candidate = 0.0;
               if(isBuy)
                 {
                  int hi = iHighest(symbol, PERIOD_M15, MODE_HIGH, openShift + 1, 0);
                  if(hi >= 0)
                     candidate = iHigh(symbol, PERIOD_M15, hi) - m_trailAtrMult * atr;
                  if(candidate > slNow + point && candidate < bid)
                     m_trade.PositionModify(ticket, NormPrice(symbol, candidate), tpNow);
                 }
               else
                 {
                  int lo = iLowest(symbol, PERIOD_M15, MODE_LOW, openShift + 1, 0);
                  if(lo >= 0)
                     candidate = iLow(symbol, PERIOD_M15, lo) + m_trailAtrMult * atr;
                  if(candidate < slNow - point && candidate > ask)
                     m_trade.PositionModify(ticket, NormPrice(symbol, candidate), tpNow);
                 }
              }
           }
        }
      CleanOrphanGVs();
     }

   //--- Cierre de todas las posiciones propias
   void CloseAllOwn(const string reason)
     {
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != ATLAS_MAGIC)
            continue;
         if(m_trade.PositionClose(ticket))
            closed++;
        }
      if(closed > 0)
         m_notifier.Notify(StringFormat("%d posicion(es) cerrada(s): %s", closed, reason));
      CleanOrphanGVs();
     }

   //--- Info de posición para el dashboard ("" si no hay)
   string PositionInfo(const string symbol)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != ATLAS_MAGIC)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol)
            continue;
         bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double isl   = GlobalVariableCheck(GvISL(ticket)) ? GlobalVariableGet(GvISL(ticket))
                                                           : PositionGetDouble(POSITION_SL);
         double riskDist = MathAbs(entry - isl);
         double price = SymbolInfoDouble(symbol, isBuy ? SYMBOL_BID : SYMBOL_ASK);
         double rNow  = (riskDist > 0.0 ? (isBuy ? price - entry : entry - price) / riskDist : 0.0);
         return StringFormat("%s %.2f lotes | %+.2fR", (isBuy ? "COMPRA" : "VENTA"),
                             PositionGetDouble(POSITION_VOLUME), rNow);
        }
      return "";
     }
  };
