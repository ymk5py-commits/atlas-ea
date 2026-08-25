//+------------------------------------------------------------------+
//| Atlas_BuscarSimbolos.mq5 — Busca plata, petróleo y otros          |
//| instrumentos en el broker, con su nombre exacto y si se opera.    |
//+------------------------------------------------------------------+
#property strict

string ModoTexto(const long m)
  {
   switch((ENUM_SYMBOL_TRADE_MODE)m)
     {
      case SYMBOL_TRADE_MODE_DISABLED:  return "NO OPERABLE";
      case SYMBOL_TRADE_MODE_LONGONLY:  return "solo compras";
      case SYMBOL_TRADE_MODE_SHORTONLY: return "solo ventas";
      case SYMBOL_TRADE_MODE_CLOSEONLY: return "solo cerrar";
      case SYMBOL_TRADE_MODE_FULL:      return "OPERABLE";
     }
   return "?";
  }

void OnStart()
  {
   Print("========== BUSQUEDA DE SIMBOLOS ==========");
   string pats[] = {"XAG", "SILVER", "OIL", "WTI", "BRENT", "XTI", "XBR", "NGAS", "XPT", "XPD"};
   int total = SymbolsTotal(false);
   int hallados = 0;

   for(int i = 0; i < total; i++)
     {
      string s = SymbolName(i, false);
      string u = s;
      StringToUpper(u);
      for(int p = 0; p < ArraySize(pats); p++)
        {
         if(StringFind(u, pats[p]) < 0)
            continue;
         SymbolSelect(s, true);
         long modo = SymbolInfoInteger(s, SYMBOL_TRADE_MODE);
         PrintFormat("%-14s | %-12s | %-30s | bid %.3f | spread %d | lote min %.2f | contrato %.0f",
                     s, ModoTexto(modo),
                     SymbolInfoString(s, SYMBOL_DESCRIPTION),
                     SymbolInfoDouble(s, SYMBOL_BID),
                     (int)SymbolInfoInteger(s, SYMBOL_SPREAD),
                     SymbolInfoDouble(s, SYMBOL_VOLUME_MIN),
                     SymbolInfoDouble(s, SYMBOL_TRADE_CONTRACT_SIZE));
         hallados++;
         break;
        }
     }
   PrintFormat("Total hallados: %d (de %d simbolos del broker)", hallados, total);
   Print("==========================================");
  }
