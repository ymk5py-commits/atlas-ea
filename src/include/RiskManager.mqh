//+------------------------------------------------------------------+
//| RiskManager.mqh — Sizing por riesgo, límites diarios,            |
//| kill switch persistente y control de exposición total.           |
//+------------------------------------------------------------------+
#property strict
#include "AtlasTypes.mqh"
#include "Notifier.mqh"

class CRiskManager
  {
private:
   double            m_riskPct;            // % de equity arriesgado por operación
   double            m_dailyLossPct;       // % de pérdida diaria que frena entradas
   double            m_maxDDPct;           // % de drawdown desde el pico → kill switch
   double            m_maxTotalRiskPct;    // riesgo abierto máximo simultáneo (%)
   int               m_maxTradesPerDay;    // por símbolo
   int               m_maxPositions;       // total simultáneas
   CNotifier        *m_notifier;

   double            m_dayStartEquity;
   datetime          m_currentDay;

   string            m_symbols[];
   int               m_tradesToday[];

   string            m_gvPeak;             // GlobalVariable: pico de equity
   string            m_gvKill;             // GlobalVariable: latch del kill switch

   int SymbolIndex(const string symbol)
     {
      for(int i = 0; i < ArraySize(m_symbols); i++)
         if(m_symbols[i] == symbol)
            return i;
      return -1;
     }

public:
   void Init(const double riskPct, const double dailyLossPct, const double maxDDPct,
             const double maxTotalRiskPct, const int maxTradesPerDay,
             const int maxPositions, const bool resetKillSwitch,
             CNotifier *notifier, const string &symbols[])
     {
      m_riskPct         = riskPct;
      m_dailyLossPct    = dailyLossPct;
      m_maxDDPct        = maxDDPct;
      m_maxTotalRiskPct = maxTotalRiskPct;
      m_maxTradesPerDay = maxTradesPerDay;
      m_maxPositions    = maxPositions;
      m_notifier        = notifier;

      int n = ArraySize(symbols);
      ArrayResize(m_symbols, n);
      ArrayResize(m_tradesToday, n);
      for(int i = 0; i < n; i++)
        {
         m_symbols[i]     = symbols[i];
         m_tradesToday[i] = 0;
        }

      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      m_gvPeak = ATLAS_GV_PREFIX + "PEAK_" + IntegerToString(login);
      m_gvKill = ATLAS_GV_PREFIX + "KILL_" + IntegerToString(login);

      if(resetKillSwitch && GlobalVariableCheck(m_gvKill))
        {
         GlobalVariableDel(m_gvKill);
         GlobalVariableSet(m_gvPeak, AccountInfoDouble(ACCOUNT_EQUITY));
         m_notifier.Notify("Kill switch RESETEADO manualmente. Pico de equity reiniciado.");
        }

      //--- El pico DEBE existir desde el arranque: si solo baja el equity,
      //--- el kill switch tiene que poder disparar igual.
      if(!GlobalVariableCheck(m_gvPeak))
         GlobalVariableSet(m_gvPeak, AccountInfoDouble(ACCOUNT_EQUITY));

      m_currentDay      = DateOf(TimeTradeServer());
      m_dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
     }

   //--- Pérdida por 1 lote entre entry y sl. Combina el motor del broker
   //--- (OrderCalcProfit) con el cálculo estructural (dist × contrato) y
   //--- usa el MAYOR: datos rotos del broker nunca pueden agrandar el lote.
   //--- (Bug real detectado: MetaQuotes-Demo reporta tick_value=0.1 en
   //--- XAUUSD, 10 veces menos que el valor real del contrato de 100 oz.)
   double LossPerLot(const string symbol, const double entry, const double sl)
     {
      double sl_dist = MathAbs(entry - sl);
      if(sl_dist <= 0.0)
         return 0.0;

      double lossBroker = 0.0;
      ENUM_ORDER_TYPE ot = (sl < entry ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double calc = 0.0;
      if(OrderCalcProfit(ot, symbol, 1.0, entry, sl, calc))
         lossBroker = MathAbs(calc);

      double lossStruct = 0.0;
      string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
      string acct  = AccountInfoString(ACCOUNT_CURRENCY);
      double contract = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(quote == acct && contract > 0.0)
         lossStruct = sl_dist * contract;

      double lossTick = 0.0;
      double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size > 0.0 && tick_value > 0.0)
         lossTick = sl_dist / tick_size * tick_value;

      //--- el mayor de los tres estimadores = el lote más conservador
      return MathMax(lossBroker, MathMax(lossStruct, lossTick));
     }

   //--- Cálculo de lote por riesgo fijo. Devuelve 0 si no se puede operar.
   double CalcLots(const string symbol, const double entry, const double sl)
     {
      double sl_dist = MathAbs(entry - sl);
      if(sl_dist <= 0.0)
         return 0.0;

      double loss_per_lot = LossPerLot(symbol, entry, sl);
      if(loss_per_lot <= 0.0)
        {
         m_notifier.Notify(symbol + ": no se pudo calcular la perdida por lote — operacion salteada por seguridad.");
         return 0.0;
        }

      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double risk_money = equity * m_riskPct / 100.0;
      double lots       = risk_money / loss_per_lot;

      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double vmax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      if(step <= 0.0)
         step = 0.01;

      lots = MathFloor(lots / step) * step;
      if(lots < vmin)
        {
         m_notifier.Notify(StringFormat(
            "%s: operacion salteada — hasta el lote minimo %.2f excede el riesgo %.1f%% (SL %.1f pts)",
            symbol, vmin, m_riskPct, sl_dist / SymbolInfoDouble(symbol, SYMBOL_POINT)));
         return 0.0;
        }
      if(lots > vmax)
         lots = vmax;
      return NormalizeDouble(lots, 8);
     }

   //--- % de equity en riesgo en las posiciones propias abiertas
   double OpenRiskPct()
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         return 100.0;
      double total = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != ATLAS_MAGIC)
            continue;
         string psym  = PositionGetString(POSITION_SYMBOL);
         double pentry = PositionGetDouble(POSITION_PRICE_OPEN);
         double psl    = PositionGetDouble(POSITION_SL);
         double pvol   = PositionGetDouble(POSITION_VOLUME);
         if(psl <= 0.0)
            continue;                       // sin SL no debería pasar; no suma
         double risk = LossPerLot(psym, pentry, psl) * pvol;
         if(risk > 0.0)
            total += risk;                  // SL en ganancia (BE) no resta riesgo
        }
      return total / equity * 100.0;
     }

   int CountOwnPositions(const string symbol = "")
     {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != ATLAS_MAGIC)
            continue;
         if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol)
            continue;
         count++;
        }
      return count;
     }

   //--- ¿Se perdió ya el máximo diario?
   bool DailyLossHit()
     {
      if(m_dayStartEquity <= 0.0)
         return false;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (equity <= m_dayStartEquity * (1.0 - m_dailyLossPct / 100.0));
     }

   //--- Rollover diario (llamar en cada timer)
   void CheckNewDay()
     {
      datetime today = DateOf(TimeTradeServer());
      if(today == m_currentDay)
         return;
      m_currentDay     = today;
      m_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      for(int i = 0; i < ArraySize(m_tradesToday); i++)
         m_tradesToday[i] = 0;
      m_notifier.Log("Nuevo dia de trading. Equity base: " + DoubleToString(m_dayStartEquity, 2));
     }

   //--- Kill switch: actualiza pico y evalúa. True = recién disparado.
   bool KillSwitchTriggered()
     {
      if(GlobalVariableCheck(m_gvKill))
         return false;                      // ya estaba latcheado
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double peak   = GlobalVariableCheck(m_gvPeak) ? GlobalVariableGet(m_gvPeak) : equity;
      if(equity > peak)
        {
         peak = equity;
         GlobalVariableSet(m_gvPeak, peak);
        }
      if(equity <= peak * (1.0 - m_maxDDPct / 100.0))
        {
         GlobalVariableSet(m_gvKill, 1.0);
         m_notifier.Critical(StringFormat(
            "KILL SWITCH: equity %.2f cayo %.0f%% desde el pico %.2f. Bot APAGADO. Reactivar con InpResetKillSwitch=true tras revisar.",
            equity, m_maxDDPct, peak));
         return true;
        }
      return false;
     }

   bool KillSwitchLatched()
     {
      return GlobalVariableCheck(m_gvKill);
     }

   //--- ¿Se puede abrir una operación nueva en este símbolo?
   bool CanOpen(const string symbol, string &blockReason)
     {
      if(KillSwitchLatched())
        { blockReason = "kill switch activo"; return false; }
      if(DailyLossHit())
        { blockReason = StringFormat("limite de perdida diaria %.1f%% alcanzado", m_dailyLossPct); return false; }
      if(CountOwnPositions(symbol) > 0)
        { blockReason = "ya hay posicion abierta en " + symbol; return false; }
      if(CountOwnPositions() >= m_maxPositions)
        { blockReason = "maximo de posiciones simultaneas alcanzado"; return false; }
      int idx = SymbolIndex(symbol);
      if(idx >= 0 && m_tradesToday[idx] >= m_maxTradesPerDay)
        { blockReason = StringFormat("maximo %d operaciones/dia en %s", m_maxTradesPerDay, symbol); return false; }
      if(OpenRiskPct() + m_riskPct > m_maxTotalRiskPct + 0.0001)
        { blockReason = StringFormat("riesgo total abierto superaria %.1f%%", m_maxTotalRiskPct); return false; }
      blockReason = "";
      return true;
     }

   //--- Registrar operación abierta (contador diario)
   void RegisterOpen(const string symbol)
     {
      int idx = SymbolIndex(symbol);
      if(idx >= 0)
         m_tradesToday[idx]++;
     }

   int TradesToday(const string symbol)
     {
      int idx = SymbolIndex(symbol);
      return (idx >= 0 ? m_tradesToday[idx] : 0);
     }

   double DayPnLPct()
     {
      if(m_dayStartEquity <= 0.0)
         return 0.0;
      return (AccountInfoDouble(ACCOUNT_EQUITY) / m_dayStartEquity - 1.0) * 100.0;
     }

   double DrawdownFromPeakPct()
     {
      double peak = GlobalVariableCheck(m_gvPeak) ? GlobalVariableGet(m_gvPeak)
                                                  : AccountInfoDouble(ACCOUNT_EQUITY);
      if(peak <= 0.0)
         return 0.0;
      return (1.0 - AccountInfoDouble(ACCOUNT_EQUITY) / peak) * 100.0;
     }

   double RiskPct() const { return m_riskPct; }
  };
