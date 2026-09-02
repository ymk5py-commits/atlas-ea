//+------------------------------------------------------------------+
//| Notifier.mqh — Log centralizado + push a la app de MT5 + Telegram|
//| El push de MT5 admite ~255 caracteres y es de una sola via; los   |
//| memos largos y las respuestas del dueno van por Telegram.         |
//+------------------------------------------------------------------+
#property strict
#include "Telegram.mqh"

class CNotifier
  {
private:
   bool              m_push;     // enviar push notifications de MT5
   CTelegram        *m_tg;       // NULL si no hay Telegram

   bool TgOn() const { return (m_tg != NULL && m_tg.Enabled()); }

public:
   void Init(const bool enablePush, CTelegram *tg = NULL)
     {
      m_push = enablePush;
      m_tg   = tg;
     }

   //--- Mensaje normal: siempre al log; push y Telegram si estan habilitados
   void Notify(const string msg)
     {
      Print("[ATLAS] ", msg);
      if(m_push && !MQLInfoInteger(MQL_TESTER))
         SendNotification("ATLAS: " + msg);
      if(TgOn())
         m_tg.Send(msg);
     }

   //--- Mensaje crítico (kill switch, errores graves)
   void Critical(const string msg)
     {
      Print("[ATLAS][CRITICO] ", msg);
      if(m_push && !MQLInfoInteger(MQL_TESTER))
         SendNotification("ATLAS CRITICO: " + msg);
      if(TgOn())
         m_tg.Send("CRITICO: " + msg);
     }

   //--- Memo largo: Telegram y log reciben el texto completo; el push de
   //--- MT5 recibe la version corta (limite de 255 caracteres).
   void Memo(const string full, const string shortMsg)
     {
      Print("[ATLAS] ", full);
      if(m_push && !MQLInfoInteger(MQL_TESTER))
         SendNotification("ATLAS: " + shortMsg);
      if(TgOn())
         m_tg.Send(full);
     }

   //--- Solo log (decisiones de no-operar, debug)
   void Log(const string msg)
     {
      Print("[ATLAS] ", msg);
     }
  };
