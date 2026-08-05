//+------------------------------------------------------------------+
//| Atlas_PushTest.mq5 — Verifica que las notificaciones push al     |
//| celular estén configuradas y funcionando. Envía un mensaje de    |
//| prueba y reporta el resultado exacto en la pestaña Expertos.     |
//+------------------------------------------------------------------+
#property strict

void OnStart()
  {
   Print("=========== ATLAS PUSH TEST ===========");
   ResetLastError();
   bool ok = SendNotification("ATLAS EA: prueba de notificaciones OK. El bot te va a avisar cada operacion por aca.");
   int err = GetLastError();
   if(ok)
      Print("PUSH OK — el mensaje salio hacia el celular. Revisa la app MetaTrader 5.");
   else
     {
      switch(err)
        {
         case 4515: Print("PUSH FALLO (4515): MetaQuotes ID invalido o mal pegado en Preferencias > Notificaciones."); break;
         case 4516: Print("PUSH FALLO (4516): no se pudo enviar — revisar conexion o ID."); break;
         default:   Print("PUSH FALLO (error ", err, "): las notificaciones no estan habilitadas en Preferencias > Notificaciones."); break;
        }
     }
   Print("=======================================");
  }
