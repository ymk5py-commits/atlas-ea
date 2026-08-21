//+------------------------------------------------------------------+
//| Atlas_Health.mq5 — Chequeo de salud del despliegue.               |
//| Verifica hora del broker vs ventana de sesión, notificaciones     |
//| push, calendario económico y estado de los símbolos.              |
//+------------------------------------------------------------------+
#property strict
#include "include/AtlasTypes.mqh"

void OnStart()
  {
   Print("============ ATLAS HEALTH CHECK ============");

   //--- 1) Cuenta
   PrintFormat("CUENTA  : %I64d | %s | %s | equity %.2f %s",
               AccountInfoInteger(ACCOUNT_LOGIN),
               AccountInfoString(ACCOUNT_SERVER),
               (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "REAL"),
               AccountInfoDouble(ACCOUNT_EQUITY),
               AccountInfoString(ACCOUNT_CURRENCY));
   PrintFormat("TRADING : permitido=%s | EA permitido=%s | conectado=%s",
               (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ? "SI" : "NO"),
               (AccountInfoInteger(ACCOUNT_TRADE_EXPERT) ? "SI" : "NO"),
               (TerminalInfoInteger(TERMINAL_CONNECTED) ? "SI" : "NO"));

   //--- 2) Horas: la ventana de sesión del bot usa hora del SERVIDOR
   datetime srv = TimeTradeServer();
   datetime gmt = TimeGMT();
   int offset = (int)MathRound((double)(srv - gmt) / 3600.0);
   MqlDateTime d;
   TimeToStruct(srv, d);
   PrintFormat("HORA    : servidor %s (GMT%+d) | GMT %s | local terminal %s",
               TimeToString(srv, TIME_DATE | TIME_MINUTES), offset,
               TimeToString(gmt, TIME_MINUTES), TimeToString(TimeLocal(), TIME_MINUTES));
   PrintFormat("SESION  : el bot opera 08:00-20:00 hora servidor = %02d:00-%02d:00 en Paraguay (GMT-3)",
               (8 - offset - 3 + 24) % 24, (20 - offset - 3 + 24) % 24);

   //--- 3) Notificaciones push
   bool notifOk = TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED);
   PrintFormat("PUSH    : notificaciones habilitadas en el terminal = %s", (notifOk ? "SI" : "NO"));
   if(notifOk)
     {
      ResetLastError();
      bool sent = SendNotification("ATLAS: chequeo de salud desde el servidor OK");
      PrintFormat("PUSH    : envio de prueba = %s (error %d)", (sent ? "OK" : "FALLO"), GetLastError());
     }
   else
      Print("PUSH    : >>> FALTA configurar el MetaQuotes ID: el bot no puede avisarte al celular <<<");

   //--- 4) Calendario económico (filtro de noticias)
   MqlCalendarValue vals[];
   int n = CalendarValueHistory(vals, TimeCurrent() - 86400, TimeCurrent() + 86400);
   PrintFormat("NOTICIAS: eventos del calendario en +/-24h = %d %s", n,
               (n > 0 ? "(filtro operativo)" : ">>> CALENDARIO VACIO: el filtro de noticias NO protege <<<"));

   //--- 5) Símbolos
   string syms[2] = {"XAUUSD", "EURUSD"};
   for(int i = 0; i < 2; i++)
     {
      string s = syms[i];
      SymbolSelect(s, true);
      PrintFormat("SIMBOLO : %-7s bid %.5f | spread %d pts | contrato %.0f | barras M15 %d | barras H1 %d",
                  s, SymbolInfoDouble(s, SYMBOL_BID),
                  (int)SymbolInfoInteger(s, SYMBOL_SPREAD),
                  SymbolInfoDouble(s, SYMBOL_TRADE_CONTRACT_SIZE),
                  Bars(s, PERIOD_M15), Bars(s, PERIOD_H1));
     }

   Print("============================================");
  }
