//+------------------------------------------------------------------+
//| Atlas_Symbols.mq5 — Descubre los nombres exactos de los índices  |
//| US (Nasdaq/Dow/S&P) y sus especificaciones en este broker.       |
//+------------------------------------------------------------------+
#property strict

void OnStart()
  {
   Print("=========== ATLAS SYMBOLS ===========");
   int total = SymbolsTotal(false);
   PrintFormat("Simbolos del broker: %d", total);
   string pats[10] = {"US30","US100","US500","USTEC","SPX","NAS","NDX","DJ30","SP500","WS30"};
   int found = 0;
   for(int i = 0; i < total; i++)
     {
      string s = SymbolName(i, false);
      string u = s;
      StringToUpper(u);
      for(int p = 0; p < 10; p++)
        {
         if(StringFind(u, pats[p]) >= 0)
           {
            SymbolSelect(s, true);
            PrintFormat("MATCH: %-12s | %s | path=%s | digits=%d tick=%.2f contrato=%.0f | trade=%s",
                        s,
                        SymbolInfoString(s, SYMBOL_DESCRIPTION),
                        SymbolInfoString(s, SYMBOL_PATH),
                        (int)SymbolInfoInteger(s, SYMBOL_DIGITS),
                        SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE),
                        SymbolInfoDouble(s, SYMBOL_TRADE_CONTRACT_SIZE),
                        (SymbolInfoInteger(s, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL ? "SI" : "LIMITADO"));
            found++;
            break;
           }
        }
     }
   PrintFormat("Total matches: %d", found);
   Print("=====================================");
  }
