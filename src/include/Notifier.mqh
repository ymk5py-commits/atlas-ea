//+------------------------------------------------------------------+
//| Notifier.mqh — Log centralizado + push a la app móvil de MT5     |
//+------------------------------------------------------------------+
#property strict

class CNotifier
  {
private:
   bool              m_push;     // enviar push notifications
public:
   void              Init(const bool enablePush) { m_push = enablePush; }

   //--- Mensaje normal: siempre al log, push si está habilitado
   void Notify(const string msg)
     {
      Print("[ATLAS] ", msg);
      if(m_push && !MQLInfoInteger(MQL_TESTER))
         SendNotification("ATLAS: " + msg);
     }

   //--- Mensaje crítico (kill switch, errores graves)
   void Critical(const string msg)
     {
      Print("[ATLAS][CRITICO] ", msg);
      if(m_push && !MQLInfoInteger(MQL_TESTER))
         SendNotification("ATLAS CRITICO: " + msg);
     }

   //--- Solo log (decisiones de no-operar, debug)
   void Log(const string msg)
     {
      Print("[ATLAS] ", msg);
     }
  };
