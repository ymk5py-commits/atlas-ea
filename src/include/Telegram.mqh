//+------------------------------------------------------------------+
//| Telegram.mqh — Canal BIDIRECCIONAL: memos, alertas 24/7 y         |
//| aprobacion humana. El push de MT5 es de una sola via; Telegram    |
//| permite que el dueno responda APROBAR / RECHAZAR / WATCH / ESTADO.|
//|                                                                  |
//| Requiere permitir https://api.telegram.org para WebRequest en el  |
//| terminal (Opciones > Asesores Expertos > Permitir WebRequest). Si |
//| no esta permitida, WebRequest devuelve -1 con error 4014 y el EA  |
//| lo dice UNA vez en el log; el bot sigue operando en AUTOMATICO.   |
//| En el Strategy Tester queda desactivado (WebRequest no existe).   |
//+------------------------------------------------------------------+
#property strict

//--- Codifica para application/x-www-form-urlencoded, byte a byte en UTF-8
string UrlEncode(const string text)
  {
   uchar bytes[];
   int n = StringToCharArray(text, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   string out = "";
   for(int i = 0; i < n; i++)
     {
      uchar c = bytes[i];
      if(c == 0)
         break;                            // terminador
      if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
         c == '-' || c == '_' || c == '.' || c == '~')
         out += CharToString(c);
      else
         out += StringFormat("%%%02X", c);
     }
   return out;
  }

//+------------------------------------------------------------------+
//| Lectura minima del JSON de getUpdates. Telegram devuelve JSON     |
//| compacto y por update solo hacen falta tres datos: "update_id",   |
//| el id del chat y el texto. No hace falta un parser completo, pero |
//| SI respetar los niveles: al RESPONDER a un memo, Telegram manda   |
//| el memo citado (reply_to_message, con su propio "chat" y su       |
//| propio "text") ANTES que el texto del dueno. Quedarse con el      |
//| primer "text" que apareciera devolvia el memo y el APROBAR se     |
//| perdia.                                                           |
//+------------------------------------------------------------------+

//--- Substring sin pasarle a StringSubstr un largo <= 0
string TgJsonSub(const string &s, const int start, const int len)
  {
   return (len > 0 ? StringSubstr(s, start, len) : "");
  }

//--- Indice de la comilla que cierra el string que abre en 'open' (el
//--- largo del texto si no cierra). Un caracter escapado (\" o \\) no cierra.
int TgJsonStringEnd(const string &s, const int open)
  {
   int n = StringLen(s);
   for(int i = open + 1; i < n; i++)
     {
      ushort c = StringGetCharacter(s, i);
      if(c == '\\')
         i++;
      else if(c == '"')
         return i;
     }
   return n;
  }

//--- Primer caracter no blanco a partir de 'from'
int TgJsonSkipBlank(const string &s, const int from)
  {
   int n = StringLen(s);
   int i = from;
   while(i < n)
     {
      ushort c = StringGetCharacter(s, i);
      if(c != ' ' && c != '\t' && c != '\r' && c != '\n')
         break;
      i++;
     }
   return i;
  }

//+------------------------------------------------------------------+
//| Id del chat y texto del MENSAJE de un update, leidos solo en el   |
//| primer nivel del mensaje. 'chunk' arranca dentro del objeto del   |
//| update (nivel 0): el mensaje es el objeto de nivel 1 y su "chat", |
//| el de nivel 2. Lo citado (reply_to_message, quote) queda mas      |
//| adentro y se saltea. False si al mensaje le falta alguno de los   |
//| dos (fotos, botones, altas y bajas del chat).                     |
//+------------------------------------------------------------------+
bool TgMessageFields(const string &chunk, string &chatId, string &text)
  {
   chatId = "";
   text   = "";
   bool hasText = false;
   bool inChat  = false;                 // dentro del "chat" del mensaje
   int  depth   = 0;
   int  n       = StringLen(chunk);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(chunk, i);
      if(c == '{' || c == '[')
        {
         depth++;
         continue;
        }
      if(c == '}' || c == ']')
        {
         depth--;
         if(depth < 2)
            inChat = false;
         continue;
        }
      if(c != '"')
         continue;

      //--- Un string: es clave solo si lo sigue ':'
      int    e   = TgJsonStringEnd(chunk, i);
      string key = TgJsonSub(chunk, i + 1, e - i - 1);
      i = e;
      int v = TgJsonSkipBlank(chunk, e + 1);
      if(v >= n || StringGetCharacter(chunk, v) != ':')
         continue;
      v = TgJsonSkipBlank(chunk, v + 1);
      if(v >= n)
         break;
      ushort first = StringGetCharacter(chunk, v);

      if(depth == 1 && key == "text" && first == '"')
        {
         int te  = TgJsonStringEnd(chunk, v);
         text    = TgJsonSub(chunk, v + 1, te - v - 1);
         hasText = true;
         i = te;
        }
      else if(depth == 1 && key == "chat" && first == '{')
         inChat = true;                  // el '{' lo cuenta la vuelta siguiente
      else if(depth == 2 && inChat && key == "id")
        {
         int ve = v;
         while(ve < n)
           {
            ushort d = StringGetCharacter(chunk, ve);
            if(!((d >= '0' && d <= '9') || (d == '-' && ve == v)))
               break;
            ve++;
           }
         chatId = TgJsonSub(chunk, v, ve - v);
         i = ve - 1;
        }
     }
   return (hasText && chatId != "");
  }

//+------------------------------------------------------------------+
//| Extrae de la respuesta de getUpdates los textos que llegaron del  |
//| chat AUTORIZADO y el mayor update_id visto. Mensajes de otros     |
//| chats se ignoran: nadie mas puede aprobar una operacion. El id se |
//| compara ENTERO: buscarlo como texto dejaba pasar a un chat cuyo   |
//| id solo EMPIEZA igual (el 5551234 pasaba por el 555).             |
//+------------------------------------------------------------------+
int TgExtractCommands(const string json, const long chatId, string &texts[], long &maxUpdateId)
  {
   ArrayResize(texts, 0);
   maxUpdateId = -1;
   string want = IntegerToString(chatId);
   int len = StringLen(json);
   int pos = 0;
   int count = 0;
   while(true)
     {
      int u = StringFind(json, "\"update_id\":", pos);
      if(u < 0)
         break;
      int vstart = u + 12;
      int vend = vstart;
      while(vend < len)
        {
         ushort d = StringGetCharacter(json, vend);
         if(d < '0' || d > '9')
            break;
         vend++;
        }
      long uid = StringToInteger(TgJsonSub(json, vstart, vend - vstart));
      if(uid > maxUpdateId)
         maxUpdateId = uid;

      int next  = StringFind(json, "\"update_id\":", vend);
      int limit = (next < 0 ? len : next);
      string chunk = TgJsonSub(json, vend, limit - vend);

      string cid, text;
      if(TgMessageFields(chunk, cid, text) && cid == want)
        {
         int sz = ArraySize(texts);
         ArrayResize(texts, sz + 1);
         texts[sz] = text;
         count++;
        }
      pos = limit;
     }
   return count;
  }

//+------------------------------------------------------------------+
class CTelegram
  {
private:
   string            m_token;
   long              m_chatId;
   bool              m_enabled;
   long              m_nextOffset;      // update_id + 1 del ultimo procesado
   bool              m_drained;         // ya se descartaron los mensajes viejos
   bool              m_warned;          // ya se aviso que WebRequest fallo

   string BaseUrl() const { return "https://api.telegram.org/bot" + m_token + "/"; }

   //--- Ejecuta la peticion; devuelve el cuerpo o "" si fallo (y dice por que, una vez)
   string Request(const string method, const string url, const string body, const int timeoutMs)
     {
      char   data[];
      char   result[];
      string resultHeaders;
      string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
      if(StringLen(body) > 0)
         StringToCharArray(body, data, 0, StringLen(body), CP_UTF8);   // sin terminador
      ResetLastError();
      int code = WebRequest(method, url, headers, timeoutMs, data, result, resultHeaders);
      if(code == -1)
        {
         int err = GetLastError();
         if(!m_warned)
           {
            m_warned = true;
            if(err == 4014)
               Print("[ATLAS][TELEGRAM] WebRequest NO permitida (error 4014). Agregar https://api.telegram.org en ",
                     "Opciones > Asesores Expertos > Permitir WebRequest, o via config/common.ini en el servidor. ",
                     "Mientras tanto el bot opera en AUTOMATICO y sin alertas de Telegram.");
            else
               Print("[ATLAS][TELEGRAM] WebRequest fallo (error ", err, "). Revisar conectividad del terminal.");
           }
         return "";
        }
      string text = CharArrayToString(result, 0, -1, CP_UTF8);
      if(code != 200)
        {
         Print("[ATLAS][TELEGRAM] HTTP ", code, ": ", StringSubstr(text, 0, 200));
         return "";
        }
      return text;
     }

public:
   void Init(const string token, const long chatId)
     {
      m_token      = token;
      m_chatId     = chatId;
      m_nextOffset = 0;
      m_drained    = false;
      m_warned     = false;
      m_enabled    = (StringLen(token) > 10 && chatId != 0 && !(bool)MQLInfoInteger(MQL_TESTER));
     }

   bool Enabled() const { return m_enabled; }

   bool Send(const string text)
     {
      if(!m_enabled)
         return false;
      string body = "chat_id=" + IntegerToString(m_chatId) + "&text=" + UrlEncode(text);
      return (Request("POST", BaseUrl() + "sendMessage", body, 4000) != "");
     }

   //--- Lee los mensajes nuevos del chat autorizado. La PRIMERA lectura solo
   //--- descarta lo acumulado antes de arrancar: un "APROBAR" viejo no puede
   //--- ejecutar una operacion de hoy.
   int Poll(string &texts[])
     {
      ArrayResize(texts, 0);
      if(!m_enabled)
         return 0;
      string url  = BaseUrl() + "getUpdates?timeout=0&offset=" + IntegerToString(m_nextOffset);
      string json = Request("GET", url, "", 4000);
      if(json == "")
         return 0;
      long maxId = -1;
      int  n = TgExtractCommands(json, m_chatId, texts, maxId);
      if(maxId >= 0)
         m_nextOffset = maxId + 1;
      if(!m_drained)
        {
         m_drained = true;
         ArrayResize(texts, 0);
         return 0;
        }
      return n;
     }
  };
