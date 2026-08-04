//+------------------------------------------------------------------+
//| Dashboard.mqh — Panel de estado en el gráfico (labels de texto). |
//+------------------------------------------------------------------+
#property strict

#define ATLAS_DB_PREFIX "ATLAS_DB_"

class CDashboard
  {
private:
   int               m_lines;
   int               m_x;
   int               m_y0;
   int               m_lineHeight;
   int               m_fontSize;

   void SetLine(const int idx, const string text, const color clr)
     {
      string name = ATLAS_DB_PREFIX + IntegerToString(idx);
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_y0 + idx * m_lineHeight);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, m_fontSize);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
        }
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      if(idx >= m_lines)
         m_lines = idx + 1;
     }

public:
   void Init()
     {
      m_lines      = 0;
      m_x          = 10;
      m_y0         = 20;
      m_lineHeight = 16;
      m_fontSize   = 9;
     }

   void Destroy()
     {
      ObjectsDeleteAll(0, ATLAS_DB_PREFIX);
      ChartRedraw(0);
     }

   //--- Redibuja el panel completo. Los arrays van en paralelo por símbolo.
   void Update(const string globalState, const color stateColor,
               const double equity, const double dayPnlPct, const double ddPct,
               const double openRiskPct, const string nextNews,
               const string &symbols[], const string &regimes[],
               const string &ratings[], const string &positions[],
               const int &tradesToday[])
     {
      color cWhite = clrSilver;
      color cVal   = clrWhite;
      color cWarn  = clrOrange;
      color cGood  = clrLime;
      color cBad   = clrTomato;

      int i = 0;
      SetLine(i++, "==================== ATLAS EA ====================", cWhite);
      SetLine(i++, "Estado : " + globalState, stateColor);
      SetLine(i++, StringFormat("Equity : %.2f USD   P&L dia: %+.2f%%", equity, dayPnlPct),
              (dayPnlPct >= 0.0 ? cGood : cBad));
      SetLine(i++, StringFormat("DD pico: %.1f%%     Riesgo abierto: %.1f%%", ddPct, openRiskPct),
              (ddPct < 10.0 ? cVal : cWarn));
      SetLine(i++, "Noticia: " + (nextNews == "" ? "sin eventos proximos" : nextNews), cWhite);
      SetLine(i++, "--------------------------------------------------", cWhite);
      for(int s = 0; s < ArraySize(symbols); s++)
        {
         SetLine(i++, StringFormat("%s  [%d ops hoy]", symbols[s], tradesToday[s]), cVal);
         SetLine(i++, "  Regimen: " + regimes[s], cWhite);
         SetLine(i++, "  Rating : " + ratings[s], cWhite);
         SetLine(i++, "  Posic. : " + (positions[s] == "" ? "---" : positions[s]),
                 (positions[s] == "" ? cWhite : cGood));
        }
      SetLine(i++, "==================================================", cWhite);
      ChartRedraw(0);
     }
  };
