//+------------------------------------------------------------------+
//|                                                    BI_Render.mqh |
//|  Breakout Intelligence MT5 - dibujo de niveles, zonas y panel    |
//+------------------------------------------------------------------+
#ifndef __BI_RENDER_MQH__
#define __BI_RENDER_MQH__

#include "BI_Types.mqh"
#include "BI_Utils.mqh"
#include "BI_Engine.mqh"

//+------------------------------------------------------------------+
//| Creacion / actualizacion de una linea de tendencia               |
//+------------------------------------------------------------------+
void BI_Line(const string name,const datetime t1,const double p1,
             const datetime t2,const double p2,const color clr,
             const ENUM_LINE_STYLE style,const int width,const bool rayRight)
  {
   if(ObjectFind(0,name)<0)
      if(!ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2))
         return;
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble (0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,rayRight);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

//+------------------------------------------------------------------+
//| Creacion / actualizacion de un rectangulo                        |
//+------------------------------------------------------------------+
void BI_Rect(const string name,const datetime t1,const double p1,
             const datetime t2,const double p2,const color clr,const bool fill)
  {
   if(ObjectFind(0,name)<0)
      if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2))
         return;
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble (0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,fill);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

//+------------------------------------------------------------------+
//| Texto anclado a un precio y a una hora                           |
//+------------------------------------------------------------------+
void BI_Text(const string name,const datetime t,const double p,
             const string txt,const color clr,const int fontSize)
  {
   if(ObjectFind(0,name)<0)
      if(!ObjectCreate(0,name,OBJ_TEXT,0,t,p))
         return;
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t);
   ObjectSetDouble (0,name,OBJPROP_PRICE,0,p);
   ObjectSetString (0,name,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

//+------------------------------------------------------------------+
//| Etiqueta fija en la esquina del grafico                          |
//+------------------------------------------------------------------+
void BI_Label(const string name,const int x,const int y,const string txt,
              const color clr,const int fontSize,const ENUM_BASE_CORNER corner)
  {
   if(ObjectFind(0,name)<0)
      if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))
         return;
   ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,name,OBJPROP_TEXT,txt);
   ObjectSetString (0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

//+------------------------------------------------------------------+
//| Color por tipo de nivel                                          |
//+------------------------------------------------------------------+
color BI_LevelColor(const int kind)
  {
   switch(kind)
     {
      case BI_LK_RANGE: return(clrDodgerBlue);
      case BI_LK_PWEEK: return(clrMediumOrchid);
      case BI_LK_PDAY:  return(clrDarkOrange);
      case BI_LK_ASIA:  return(clrTeal);
     }
   return(clrSlateGray);
  }

//+------------------------------------------------------------------+
//| Renderizador                                                     |
//+------------------------------------------------------------------+
class CBIRender
  {
private:
   bool   m_showLevels;
   bool   m_showRange;
   bool   m_showZones;
   bool   m_showPanel;
   int    m_maxLevels;
   int    m_panelX;
   int    m_panelY;
   int    m_fontSize;
   int    m_digits;
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;
   ENUM_TIMEFRAMES m_tfCtx;
   ENUM_TIMEFRAMES m_tfStruct;
   int    m_profile;

public:
                     CBIRender(void);
                    ~CBIRender(void) {}

   void              Configure(const string symbol,const ENUM_TIMEFRAMES tf,
                               const ENUM_TIMEFRAMES tfCtx,const ENUM_TIMEFRAMES tfStruct,
                               const int digits,const int profile,
                               const bool showLevels,const bool showRange,const bool showZones,
                               const bool showPanel,const int maxLevels,
                               const int panelX,const int panelY,const int fontSize);
   void              Clear(void);
   void              Draw(CBIEngine &eng);
   void              DrawStatus(CBIEngine &eng,const string extraLine);
  };

//+------------------------------------------------------------------+
CBIRender::CBIRender(void)
  {
   m_showLevels=true; m_showRange=true; m_showZones=true; m_showPanel=true;
   m_maxLevels=8; m_panelX=12; m_panelY=18; m_fontSize=9;
   m_digits=_Digits; m_symbol=_Symbol; m_tf=PERIOD_CURRENT; m_tfCtx=PERIOD_H4; m_tfStruct=PERIOD_H1;
   m_profile=BI_PROFILE_AUTO;
  }

//+------------------------------------------------------------------+
void CBIRender::Configure(const string symbol,const ENUM_TIMEFRAMES tf,
                          const ENUM_TIMEFRAMES tfCtx,const ENUM_TIMEFRAMES tfStruct,
                          const int digits,const int profile,
                          const bool showLevels,const bool showRange,const bool showZones,
                          const bool showPanel,const int maxLevels,
                          const int panelX,const int panelY,const int fontSize)
  {
   m_symbol=symbol; m_tf=tf; m_tfCtx=tfCtx; m_tfStruct=tfStruct; m_digits=digits; m_profile=profile;
   m_showLevels=showLevels; m_showRange=showRange; m_showZones=showZones;
   m_showPanel=showPanel; m_maxLevels=maxLevels;
   m_panelX=panelX; m_panelY=panelY; m_fontSize=fontSize;
  }

//+------------------------------------------------------------------+
void CBIRender::Clear(void)
  {
   ObjectsDeleteAll(0,BI_OBJ_PREFIX,0,-1);
  }

//+------------------------------------------------------------------+
//| Dibujo completo (se invoca tras cada reconstruccion)             |
//+------------------------------------------------------------------+
void CBIRender::Draw(CBIEngine &eng)
  {
   ObjectsDeleteAll(0,BI_OBJ_PREFIX+"L_",0,-1);
   ObjectsDeleteAll(0,BI_OBJ_PREFIX+"R_",0,-1);
   ObjectsDeleteAll(0,BI_OBJ_PREFIX+"Z_",0,-1);
   ObjectsDeleteAll(0,BI_OBJ_PREFIX+"T_",0,-1);

   const int n=eng.BarCount();
   if(n<3) return;
   const int last=eng.LastClosedIdx();
   const datetime tLast=eng.BarTime(n-1);

   //--- 1) niveles vigentes mas cercanos al precio
   if(m_showLevels)
     {
      //--- referencia de precio para ordenar los niveles por cercania
      double price=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      if(price<=0.0) price=eng.Ema(last);
      if(price<=0.0) return;

      int    idxs[];
      double dist[];
      const int lc=eng.LevelCount();
      ArrayResize(idxs,lc); ArrayResize(dist,lc);
      int cnt=0;
      for(int i=0;i<lc;i++)
        {
         SBILevel lv=eng.LevelAt(i);
         if(!lv.active) continue;
         if(last-lv.lastIdx>600) continue;
         idxs[cnt]=i;
         dist[cnt]=MathAbs(lv.price-price);
         cnt++;
        }
      //--- seleccion de los m_maxLevels mas cercanos
      const int take=BI_MinInt(m_maxLevels,cnt);
      for(int a=0;a<take;a++)
        {
         int best=a;
         for(int b=a+1;b<cnt;b++)
            if(dist[b]<dist[best]) best=b;
         const int ti=idxs[a]; idxs[a]=idxs[best]; idxs[best]=ti;
         const double td=dist[a]; dist[a]=dist[best]; dist[best]=td;

         SBILevel lv=eng.LevelAt(idxs[a]);
         const string nm=BI_OBJ_PREFIX+"L_"+IntegerToString(lv.id);
         const datetime t1=eng.BarTime(BI_MaxInt(0,lv.firstIdx));
         const color c=BI_LevelColor(lv.kind);
         const ENUM_LINE_STYLE st=(lv.brokenDir!=0 ? STYLE_DOT :
                                   (lv.kind==BI_LK_SWING ? STYLE_DASH : STYLE_SOLID));
         BI_Line(nm,t1,lv.price,tLast,lv.price,c,st,1,true);
         BI_Text(nm+"_t",tLast,lv.price,
                 "  "+BI_LevelKindText(lv.kind)+" x"+IntegerToString(lv.touches),
                 c,m_fontSize-1);
        }
     }

   //--- 2) rango vigente
   if(m_showRange)
     {
      double rhi,rlo; int rbars,ridx;
      if(eng.CurrentRange(rhi,rlo,rbars,ridx) && ridx>=0)
        {
         const int first=BI_MaxInt(0,ridx-rbars+1);
         BI_Rect(BI_OBJ_PREFIX+"R_box",eng.BarTime(first),rhi,eng.BarTime(ridx),rlo,
                 clrSteelBlue,false);
        }
     }

   //--- 3) zonas de los setups y etiquetas de puntuacion
   const int sc=eng.SetupCount();
   for(int i=0;i<sc;i++)
     {
      SBISetup s=eng.SetupAt(i);
      const int endIdx=(s.endIdx>=0 ? s.endIdx : n-1);
      if(last-endIdx>600) continue;

      if(m_showZones && (s.state==BI_ST_BREAKOUT || s.state==BI_ST_RETEST ||
                         s.state==BI_ST_CONFIRMED))
        {
         color zc=(s.state==BI_ST_CONFIRMED ? (s.dir>0?clrSeaGreen:clrFireBrick) : clrGoldenrod);
         BI_Rect(BI_OBJ_PREFIX+"Z_"+IntegerToString(s.id),
                 eng.BarTime(s.breakIdx),s.levelHi,eng.BarTime(endIdx),s.levelLo,zc,true);
        }

      if(s.state==BI_ST_CONFIRMED && s.confirmIdx>=0)
        {
         const double off=eng.Atr(s.confirmIdx)*1.2;
         const double anchor=(s.dir>0 ? s.levelEdge+off : s.levelEdge-off);
         BI_Text(BI_OBJ_PREFIX+"T_"+IntegerToString(s.id),
                 eng.BarTime(s.confirmIdx),anchor,
                 BI_SideText(s.dir)+" "+IntegerToString(s.score)+" ("+BI_GradeText(s.score)+")",
                 BI_GradeColor(s.score),m_fontSize);
        }
     }
  }

//+------------------------------------------------------------------+
//| Panel de estado (se refresca tambien entre barras)               |
//+------------------------------------------------------------------+
void CBIRender::DrawStatus(CBIEngine &eng,const string extraLine)
  {
   if(!m_showPanel)
     {
      ObjectsDeleteAll(0,BI_OBJ_PREFIX+"P_",0,-1);
      return;
     }

   const int n=eng.BarCount();
   if(n<3) return;
   const int last=eng.LastClosedIdx();

   string lines[9];
   lines[0]="Breakout Intelligence MT5 v"+BI_VERSION;
   lines[1]=m_symbol+" "+BI_TfText(m_tf)+"  |  contexto "+BI_TfText(m_tfCtx)+
            "  |  estructura "+BI_TfText(m_tfStruct)+"  |  perfil "+BI_ProfileText(m_profile);

   const int trend=eng.TrendState(last);
   lines[2]=StringFormat("ATR %s  ratio %.2f  |  contexto EMA: %s",
                         BI_Px(eng.Atr(last),m_digits),eng.AtrRatio(last),
                         (trend>0?"ALCISTA":(trend<0?"BAJISTA":"INDEFINIDO")));

   double rhi,rlo; int rbars,ridx;
   if(eng.CurrentRange(rhi,rlo,rbars,ridx))
      lines[3]=StringFormat("Rango vigente: %s - %s (%d velas)  |  niveles: %d",
                            BI_Px(rlo,m_digits),BI_Px(rhi,m_digits),rbars,eng.LevelCount());
   else
      lines[3]=StringFormat("Rango vigente: no detectado  |  niveles: %d",eng.LevelCount());

   const int si=eng.LastActiveSetup();
   if(si>=0)
     {
      SBISetup s=eng.SetupAt(si);
      lines[4]="Estado: "+BI_StateText(s.state)+"  ("+BI_SideText(s.dir)+
               ", nivel "+BI_Px(s.levelEdge,m_digits)+", score parcial "+
               IntegerToString(s.score)+")";
     }
   else
      lines[4]="Estado: sin setup vivo";

   //--- ultima senal confirmada (desde el historico, P3)
   lines[5]="Ultima senal confirmada: ninguna";
   for(int i=eng.SignalCount()-1;i>=0;i--)
     {
      SBISignal g=eng.SignalAt(i);
      if(g.type!=BI_EV_ENTRY) continue;
      lines[5]=StringFormat("Ultima senal: %s  score %d/100 (%s)  %s",
                            BI_SideText(g.dir),g.score,BI_GradeText(g.score),
                            TimeToString(g.barTime,TIME_DATE|TIME_MINUTES));
      break;
     }

   lines[6]="Volumen: "+(eng.VolumeUsable()
                          ? (eng.VolumeIsTick()?"TICK (del broker, no de mercado)":"REAL")
                          : "no utilizable")+
            "  |  RSI "+DoubleToString(eng.Rsi(last),1);
   lines[7]=(extraLine=="" ? "El score es una clasificacion interna, no una probabilidad." : extraLine);
   lines[8]="Indicador de analisis y alertas: no abre operaciones.";

   for(int i=0;i<9;i++)
      BI_Label(BI_OBJ_PREFIX+"P_"+IntegerToString(i),
               m_panelX,m_panelY+i*(m_fontSize+6),lines[i],
               (i==0?clrWhite:clrSilver),m_fontSize,CORNER_LEFT_UPPER);
  }

#endif // __BI_RENDER_MQH__
