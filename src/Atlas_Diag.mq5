//+------------------------------------------------------------------+
//| Atlas_Diag.mq5 — Diagnóstico de especificaciones de símbolos     |
//| y verificación del cálculo de pérdida por lote (bug de sizing).  |
//+------------------------------------------------------------------+
#property strict

void Diag(const string symbol, const double entry, const double sl)
  {
   SymbolSelect(symbol, true);
   double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double contract   = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);

   PrintFormat("%s: tick_size=%g tick_value=%g contract_size=%g point=%g",
               symbol, tick_size, tick_value, contract, point);

   double dist = MathAbs(entry - sl);
   double lossFormulaVieja = dist / tick_size * tick_value;         // fórmula con bug
   double lossCalc = 0.0;
   bool ok = OrderCalcProfit(ORDER_TYPE_BUY, symbol, 1.0, entry, sl, lossCalc);
   PrintFormat("%s: SL dist=%g | loss/lote FORMULA=%.2f | loss/lote OrderCalcProfit=%.2f (ok=%d)",
               symbol, dist, lossFormulaVieja, MathAbs(lossCalc), ok);
  }

void OnStart()
  {
   Print("=========== ATLAS DIAG ===========");
   Diag("XAUUSD", 1841.42, 1834.50);   // trade #1 del backtest
   Diag("EURUSD", 1.05317, 1.05187);   // trade #3 del backtest
   Print("==================================");
  }
