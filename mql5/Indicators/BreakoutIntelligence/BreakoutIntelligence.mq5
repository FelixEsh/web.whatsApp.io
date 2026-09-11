//+------------------------------------------------------------------+
//|                                       BreakoutIntelligence.mq5   |
//|  Detector de rupturas, retesteos y continuacion para MetaTrader 5|
//|                                                                  |
//|  Indicador de ANALISIS Y ALERTAS. No abre, modifica ni cierra    |
//|  operaciones. Todas las senales se generan sobre velas CERRADAS. |
//+------------------------------------------------------------------+
#property copyright "Breakout Intelligence MT5"
#property version   "1.10"
#property description "Rango -> Ruptura -> Validacion -> Retesteo -> Confirmacion -> Alerta"
#property description "Senales calculadas solo sobre velas cerradas. No es un sistema automatico."
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

#include "BI_Types.mqh"
#include "BI_Utils.mqh"
#include "BI_Profile.mqh"
#include "BI_Levels.mqh"
#include "BI_Engine.mqh"
#include "BI_Alerts.mqh"
#include "BI_Render.mqh"

//--- Plot 0: ruptura alcista
#property indicator_label1  "Ruptura alcista"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrGoldenrod
#property indicator_width1  1
//--- Plot 1: ruptura bajista
#property indicator_label2  "Ruptura bajista"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrGoldenrod
#property indicator_width2  1
//--- Plot 2: retesteo alcista
#property indicator_label3  "Retesteo alcista"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrDodgerBlue
#property indicator_width3  1
//--- Plot 3: retesteo bajista
#property indicator_label4  "Retesteo bajista"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrDodgerBlue
#property indicator_width4  1
//--- Plot 4: setup confirmado alcista
#property indicator_label5  "Setup BUY"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLimeGreen
#property indicator_width5  2
//--- Plot 5: setup confirmado bajista
#property indicator_label6  "Setup SELL"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrOrangeRed
#property indicator_width6  2
//--- Plot 6: score (solo ventana de datos)
#property indicator_label7  "Score"
#property indicator_type7   DRAW_NONE
//--- Plot 7: estado (solo ventana de datos)
#property indicator_label8  "Estado"
#property indicator_type8   DRAW_NONE

//+------------------------------------------------------------------+
//| PARAMETROS DE ENTRADA                                            |
//| Los valores 0 en los campos numericos marcados como "(0=perfil)" |
//| toman el valor por defecto del perfil del simbolo.               |
//+------------------------------------------------------------------+
input group "=== Contexto y perfil ==="
input ENUM_BI_PROFILE  InpProfile            = BI_PROFILE_AUTO; // Perfil de activo
input ENUM_TIMEFRAMES  InpContextTF          = PERIOD_H4;       // Timeframe de contexto (EMA 200)
input ENUM_TIMEFRAMES  InpStructureTF        = PERIOD_H1;       // Timeframe de estructura/zonas (0=grafico)
input int              InpMaxHistoryBars     = 3000;            // Barras de historico a procesar

input group "=== Estructura y niveles ==="
input int              InpPivotDepth         = 3;      // Profundidad del pivote (velas a cada lado)
input int              InpLookbackBars       = 400;    // Vigencia maxima de un nivel (velas)
input int              InpMinTouches         = 2;      // Toques minimos de un nivel de estructura
input int              InpMinLevelAgeBars    = 5;      // Antiguedad minima del nivel (velas)
input double           InpClusterATR         = 0.0;    // Tolerancia de agrupacion x ATR (0=perfil)
input bool             InpUsePrevDay         = true;   // Usar maximo/minimo del dia anterior
input bool             InpUsePrevWeek        = true;   // Usar maximo/minimo de la semana anterior
input bool             InpUseAsia            = false;  // Usar rango de la sesion asiatica
input int              InpAsiaStartHour      = 0;      // Sesion asiatica: hora inicio (servidor)
input int              InpAsiaEndHour        = 8;      // Sesion asiatica: hora fin (servidor)

input group "=== Rango / consolidacion ==="
input bool             InpUseRange           = true;   // Detectar rangos
input int              InpRangeMinBars       = 12;     // Velas minimas del rango
input int              InpRangeMaxBars       = 120;    // Velas maximas del rango
input double           InpRangeMaxWidthATR   = 0.0;    // Anchura maxima x ATR (0=perfil)
input double           InpRangeTouchATR      = 0.0;    // Tolerancia de toque x ATR (0=perfil)
input double           InpRangeMaxDrift      = 0.55;   // Deriva maxima admitida (0-1)
input int              InpRangeMinTouches    = 2;      // Toques minimos en cada borde

input group "=== Ruptura ==="
input double           InpBreakMarginATR     = 0.0;    // Margen de ruptura x ATR (0=perfil)
input double           InpBreakMarginSpread  = 0.0;    // Margen de ruptura x spread (0=perfil)
input double           InpMinBodyRatio       = 0.0;    // Cuerpo minimo de la vela (0=perfil)
input double           InpMinCloseLoc        = 0.0;    // Posicion minima del cierre (0=perfil)
input double           InpMinBarRangeATR     = 0.0;    // Recorrido minimo de la vela x ATR (0=perfil)
input double           InpApproachMaxATR     = 3.0;    // Distancia maxima de aproximacion x ATR
input int              InpPreBreakBars       = 3;      // Velas previas que deben cerrar dentro

input group "=== Retesteo y confirmacion ==="
input bool             InpRequireRetest      = true;   // Exigir retesteo antes de confirmar
input double           InpRetestTolATR       = 0.0;    // Profundidad del retesteo x ATR (0=perfil)
input double           InpReentryATR         = 0.0;    // Reentrada que invalida x ATR (0=perfil)
input int              InpRetestMaxBars      = 0;      // Caducidad sin retesteo (0=perfil)
input int              InpConfirmMaxBars     = 0;      // Caducidad sin confirmacion (0=perfil)
input double           InpPinWickRatio       = 0.0;    // Mecha minima de rechazo (0=perfil)
input int              InpMaxActiveSetups    = 4;      // Setups vivos simultaneos

input group "=== Filtros ==="
input bool             InpUseEmaFilter       = true;   // Filtro de tendencia EMA de contexto
input bool             InpEmaHardFilter      = false;  // EMA como filtro duro (veta la senal)
input int              InpEmaPeriod          = 200;    // Periodo de la EMA
input bool             InpUseAtrFilter       = true;   // Filtro de volatilidad ATR
input bool             InpAtrHardFilter      = false;  // ATR como filtro duro
input int              InpAtrPeriod          = 14;     // Periodo del ATR
input int              InpAtrRefPeriod       = 100;    // Periodo de referencia del ATR medio
input double           InpAtrMinRatio        = 0.70;   // Ratio ATR minimo aceptable
input double           InpAtrMaxRatio        = 2.00;   // Ratio ATR maximo aceptable
input bool             InpUseVolume          = true;   // Usar volumen en la puntuacion
input double           InpVolumeMult         = 0.0;    // Volumen relativo favorable (0=perfil)
input int              InpVolumeMAPeriod     = 20;     // Periodo de la media de volumen
input bool             InpUseRsi             = false;  // Usar RSI
input bool             InpRsiHardFilter      = false;  // RSI como filtro duro
input int              InpRsiPeriod          = 14;     // Periodo del RSI
input double           InpRsiBullMin         = 50.0;   // RSI minimo para rupturas alcistas
input double           InpRsiBearMax         = 50.0;   // RSI maximo para rupturas bajistas

input group "=== Sesion (HORAS DEL SERVIDOR del broker) ==="
input ENUM_BI_SESSION_FILTER InpSessionFilter = BI_SESS_OFF; // Filtro de sesion
input bool             InpSessionHardFilter  = false;  // Sesion como filtro duro
input int              InpLondonStart        = 8;      // Londres: hora inicio (servidor)
input int              InpLondonEnd          = 17;     // Londres: hora fin (servidor)
input int              InpNewYorkStart       = 13;     // Nueva York: hora inicio (servidor)
input int              InpNewYorkEnd         = 22;     // Nueva York: hora fin (servidor)
input int              InpSessCustomStart    = 8;      // Personalizada: hora inicio (servidor)
input int              InpSessCustomEnd      = 22;     // Personalizada: hora fin (servidor)

input group "=== Vigilancia y puntuacion ==="
input double           InpWatchDistATR       = 0.0;    // Distancia de aviso x ATR (0=perfil)
input int              InpWatchCooldown      = 20;     // Velas entre avisos del mismo nivel
input int              InpMinScoreAlert      = 65;     // Score minimo para alertar la entrada
input double           InpSlAtrMult          = 0.0;    // Colchon de ATR para el SL (0=perfil)
input double           InpRrTarget           = 2.0;    // Objetivo en multiplos de riesgo

input group "=== Alertas ==="
input bool             InpAlertPopup         = true;   // Alerta emergente
input bool             InpAlertPush          = false;  // Notificacion push al movil
input bool             InpAlertMail          = false;  // Correo electronico
input bool             InpAlertSound         = false;  // Sonido
input string           InpAlertSoundFile     = "alert.wav"; // Fichero de sonido
input bool             InpAlertOnWatch       = false;  // Alerta 1: aproximacion a nivel
input bool             InpAlertOnBreakout    = true;   // Alerta 2: ruptura confirmada
input bool             InpAlertOnRetest      = true;   // Alerta 3: retesteo
input bool             InpAlertOnEntry       = true;   // Alerta 4: setup confirmado
input bool             InpAlertOnInvalid     = true;   // Alerta 5: setup invalidado
input bool             InpAlertOnExpired     = false;  // Alerta 6: setup caducado

input group "=== Visualizacion ==="
input bool             InpShowLevels         = true;   // Dibujar niveles
input bool             InpShowRange          = true;   // Dibujar el rango vigente
input bool             InpShowZones          = true;   // Dibujar las zonas de los setups
input bool             InpShowPanel          = true;   // Mostrar panel de estado
input int              InpMaxLevelsDrawn     = 8;      // Niveles dibujados como maximo
input int              InpPanelX             = 12;     // Panel: desplazamiento X
input int              InpPanelY             = 18;     // Panel: desplazamiento Y
input int              InpFontSize           = 9;      // Tamano de fuente

//+------------------------------------------------------------------+
//| BUFFERS                                                          |
//+------------------------------------------------------------------+
double BufBreakUp[];
double BufBreakDn[];
double BufRetestUp[];
double BufRetestDn[];
double BufEntryUp[];
double BufEntryDn[];
double BufScore[];
double BufState[];

//+------------------------------------------------------------------+
//| ESTADO GLOBAL                                                    |
//+------------------------------------------------------------------+
CBIEngine  g_engine;
CBIAlerts  g_alerts;
CBIRender  g_render;
SBIParams  g_par;

int        g_profile      = BI_PROFILE_FOREX;
datetime   g_lastBarTime  = 0;
bool       g_initialized  = false;
bool       g_firstBuild   = true;
string     g_lastStatus   = "";

//+------------------------------------------------------------------+
//| Construccion de los parametros de trabajo                        |
//+------------------------------------------------------------------+
void BuildParams()
  {
   g_profile=(InpProfile==BI_PROFILE_AUTO ? BI_DetectProfile(_Symbol) : (int)InpProfile);
   SBIProfileDefaults d=BI_ProfileDefaults(g_profile);

   g_par.symbol    = _Symbol;
   g_par.tfSignal  = (ENUM_TIMEFRAMES)Period();
   g_par.tfContext = (InpContextTF==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : InpContextTF);
   g_par.tfStructure = (InpStructureTF==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : InpStructureTF);
   g_par.useStructTF = (PeriodSeconds(g_par.tfStructure)>PeriodSeconds((ENUM_TIMEFRAMES)Period()));
   g_par.profile   = g_profile;

   g_par.pivotDepth      = BI_ClampInt(InpPivotDepth,1,20);
   g_par.lookbackBars    = BI_ClampInt(InpLookbackBars,50,5000);
   g_par.minTouches      = BI_ClampInt(InpMinTouches,1,10);
   g_par.minLevelAgeBars = BI_ClampInt(InpMinLevelAgeBars,0,500);
   g_par.clusterATR      = BI_OrDefault(InpClusterATR,d.clusterATR);

   g_par.useRange            = InpUseRange;
   g_par.rangeMinBars        = BI_ClampInt(InpRangeMinBars,4,2000);
   g_par.rangeMaxBars        = BI_ClampInt(InpRangeMaxBars,g_par.rangeMinBars,2000);
   g_par.rangeMaxWidthATR    = BI_OrDefault(InpRangeMaxWidthATR,d.rangeMaxWidthATR);
   g_par.rangeTouchATR       = BI_OrDefault(InpRangeTouchATR,d.rangeTouchATR);
   g_par.rangeMaxDrift       = BI_ClampDbl(InpRangeMaxDrift,0.05,1.0);
   g_par.rangeMinTouchesSide = BI_ClampInt(InpRangeMinTouches,1,10);

   g_par.breakMarginATR     = BI_OrDefault(InpBreakMarginATR,d.breakMarginATR);
   g_par.breakMarginSpreads = BI_OrDefault(InpBreakMarginSpread,d.breakMarginSpreads);
   g_par.minBodyRatio       = BI_ClampDbl(BI_OrDefault(InpMinBodyRatio,d.minBodyRatio),0.0,0.95);
   g_par.minCloseLoc        = BI_ClampDbl(BI_OrDefault(InpMinCloseLoc,d.minCloseLoc),0.0,0.99);
   g_par.minBarRangeATR     = BI_OrDefault(InpMinBarRangeATR,d.minBarRangeATR);
   g_par.approachMaxATR     = BI_OrDefault(InpApproachMaxATR,3.0);
   g_par.preBreakBars       = BI_ClampInt(InpPreBreakBars,1,50);

   g_par.requireRetest  = InpRequireRetest;
   g_par.retestTolATR   = BI_OrDefault(InpRetestTolATR,d.retestTolATR);
   g_par.reentryATR     = BI_OrDefault(InpReentryATR,d.reentryATR);
   g_par.retestMaxBars  = BI_OrDefaultInt(InpRetestMaxBars,d.retestMaxBars);
   g_par.confirmMaxBars = BI_OrDefaultInt(InpConfirmMaxBars,d.confirmMaxBars);
   g_par.pinWickRatio   = BI_OrDefault(InpPinWickRatio,d.pinWickRatio);

   g_par.watchDistATR  = BI_OrDefault(InpWatchDistATR,d.watchDistATR);
   g_par.watchCooldown = BI_ClampInt(InpWatchCooldown,1,1000);

   g_par.useEmaFilter  = InpUseEmaFilter;
   g_par.emaHardFilter = InpEmaHardFilter;
   g_par.emaPeriod     = BI_ClampInt(InpEmaPeriod,2,1000);
   g_par.useAtrFilter  = InpUseAtrFilter;
   g_par.atrHardFilter = InpAtrHardFilter;
   g_par.atrPeriod     = BI_ClampInt(InpAtrPeriod,2,200);
   g_par.atrRefPeriod  = BI_ClampInt(InpAtrRefPeriod,10,1000);
   g_par.atrMinRatio   = BI_ClampDbl(InpAtrMinRatio,0.1,5.0);
   g_par.atrMaxRatio   = BI_ClampDbl(InpAtrMaxRatio,g_par.atrMinRatio,10.0);
   g_par.useVolume     = InpUseVolume;
   g_par.volumeMult    = BI_OrDefault(InpVolumeMult,d.volumeMult);
   g_par.volumeMAPeriod= BI_ClampInt(InpVolumeMAPeriod,2,500);
   g_par.useRsi        = InpUseRsi;
   g_par.rsiHardFilter = InpRsiHardFilter;
   g_par.rsiPeriod     = BI_ClampInt(InpRsiPeriod,2,200);
   g_par.rsiBullMin    = BI_ClampDbl(InpRsiBullMin,0.0,100.0);
   g_par.rsiBearMax    = BI_ClampDbl(InpRsiBearMax,0.0,100.0);

   g_par.usePrevDay    = InpUsePrevDay;
   g_par.usePrevWeek   = InpUsePrevWeek;
   g_par.useAsia       = InpUseAsia;
   g_par.asiaStartHour = BI_ClampInt(InpAsiaStartHour,0,23);
   g_par.asiaEndHour   = BI_ClampInt(InpAsiaEndHour,0,23);

   g_par.sessionFilter     = (int)InpSessionFilter;
   BI_ResolveSessions((int)InpSessionFilter,
                      BI_ClampInt(InpLondonStart,0,23),BI_ClampInt(InpLondonEnd,0,23),
                      BI_ClampInt(InpNewYorkStart,0,23),BI_ClampInt(InpNewYorkEnd,0,23),
                      BI_ClampInt(InpSessCustomStart,0,23),BI_ClampInt(InpSessCustomEnd,0,23),
                      g_par.sess1Start,g_par.sess1End,g_par.sess2Start,g_par.sess2End);
   g_par.sessionHardFilter = InpSessionHardFilter;

   g_par.minScoreAlert = BI_ClampInt(InpMinScoreAlert,0,100);
   g_par.slAtrMult     = BI_OrDefault(InpSlAtrMult,d.slAtrMult);
   g_par.rrTarget      = BI_ClampDbl(InpRrTarget,0.5,20.0);

   g_par.maxHistoryBars  = BI_ClampInt(InpMaxHistoryBars,300,20000);
   g_par.maxActiveSetups = BI_ClampInt(InpMaxActiveSetups,1,BI_MAX_SETUPS);

   //--- DETERMINISMO EN EL BORDE VIVO
   //    La reconstruccion recorre una ventana movil. Para que el resultado
   //    en las ultimas velas sea identico en cada reconstruccion, ningun
   //    nivel vigente puede proceder del borde antiguo de la ventana. Basta
   //    con que la ventana sea mayor que la vida maxima de un nivel mas el
   //    rango mas largo detectable.
   const int minWindow=g_par.lookbackBars+g_par.rangeMaxBars+200;
   if(g_par.maxHistoryBars<minWindow)
     {
      PrintFormat("Breakout Intelligence: se amplia el historico procesado de %d a %d velas "
                  "para garantizar un calculo estable (vigencia de nivel %d + rango %d).",
                  g_par.maxHistoryBars,minWindow,g_par.lookbackBars,g_par.rangeMaxBars);
      g_par.maxHistoryBars=minWindow;
     }
  }

//+------------------------------------------------------------------+
//| Configuracion de un plot de flechas                              |
//+------------------------------------------------------------------+
void SetupArrowPlot(const int idx,const int arrowCode,const int shift,const string label)
  {
   PlotIndexSetInteger(idx,PLOT_ARROW,arrowCode);
   PlotIndexSetInteger(idx,PLOT_ARROW_SHIFT,shift);
   PlotIndexSetDouble (idx,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetString (idx,PLOT_LABEL,label);
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0,BufBreakUp ,INDICATOR_DATA);
   SetIndexBuffer(1,BufBreakDn ,INDICATOR_DATA);
   SetIndexBuffer(2,BufRetestUp,INDICATOR_DATA);
   SetIndexBuffer(3,BufRetestDn,INDICATOR_DATA);
   SetIndexBuffer(4,BufEntryUp ,INDICATOR_DATA);
   SetIndexBuffer(5,BufEntryDn ,INDICATOR_DATA);
   SetIndexBuffer(6,BufScore   ,INDICATOR_DATA);
   SetIndexBuffer(7,BufState   ,INDICATOR_DATA);

   ArraySetAsSeries(BufBreakUp ,false);
   ArraySetAsSeries(BufBreakDn ,false);
   ArraySetAsSeries(BufRetestUp,false);
   ArraySetAsSeries(BufRetestDn,false);
   ArraySetAsSeries(BufEntryUp ,false);
   ArraySetAsSeries(BufEntryDn ,false);
   ArraySetAsSeries(BufScore   ,false);
   ArraySetAsSeries(BufState   ,false);

   SetupArrowPlot(0,217, 8,"Ruptura alcista");
   SetupArrowPlot(1,218,-8,"Ruptura bajista");
   SetupArrowPlot(2,159, 6,"Retesteo alcista");
   SetupArrowPlot(3,159,-6,"Retesteo bajista");
   SetupArrowPlot(4,233,14,"Setup BUY");
   SetupArrowPlot(5,234,-14,"Setup SELL");
   PlotIndexSetDouble(6,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(7,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetString(6,PLOT_LABEL,"Score");
   PlotIndexSetString(7,PLOT_LABEL,"Estado");

   BuildParams();

   if(!g_engine.Init(g_par))
     {
      Print("Breakout Intelligence: fallo de inicializacion -> ",g_engine.LastError());
      return(INIT_FAILED);
     }

   g_alerts.Configure(_Symbol,(ENUM_TIMEFRAMES)Period(),_Digits,
                      InpAlertPopup,InpAlertPush,InpAlertMail,
                      InpAlertSound,InpAlertSoundFile,
                      InpAlertOnWatch,InpAlertOnBreakout,InpAlertOnRetest,
                      InpAlertOnEntry,InpAlertOnInvalid,InpAlertOnExpired,
                      g_par.minScoreAlert);
   g_alerts.ResetHistory();

   g_render.Configure(_Symbol,(ENUM_TIMEFRAMES)Period(),g_par.tfContext,g_par.tfStructure,_Digits,g_profile,
                      InpShowLevels,InpShowRange,InpShowZones,InpShowPanel,
                      BI_ClampInt(InpMaxLevelsDrawn,0,40),
                      InpPanelX,InpPanelY,BI_ClampInt(InpFontSize,6,20));
   g_render.Clear();

   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("BreakoutIntelligence %s [%s/%s]",BI_VERSION,
                                   BI_TfText((ENUM_TIMEFRAMES)Period()),
                                   BI_TfText(g_par.tfContext)));

   g_lastBarTime=0;
   g_initialized=true;
   g_firstBuild =true;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_engine.Deinit();
   g_render.Clear();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Vaciado de los buffers                                           |
//+------------------------------------------------------------------+
void ClearBuffers(void)
  {
   ArrayInitialize(BufBreakUp ,EMPTY_VALUE);
   ArrayInitialize(BufBreakDn ,EMPTY_VALUE);
   ArrayInitialize(BufRetestUp,EMPTY_VALUE);
   ArrayInitialize(BufRetestDn,EMPTY_VALUE);
   ArrayInitialize(BufEntryUp ,EMPTY_VALUE);
   ArrayInitialize(BufEntryDn ,EMPTY_VALUE);
   ArrayInitialize(BufScore   ,EMPTY_VALUE);
   ArrayInitialize(BufState   ,EMPTY_VALUE);
  }

//+------------------------------------------------------------------+
//| Volcado de los setups a los buffers de flechas                   |
//+------------------------------------------------------------------+
void FillBuffers(const int rates_total,const double &high[],const double &low[])
  {
   const int engN=g_engine.BarCount();
   const int offset=rates_total-engN;          // indice de grafico = offset + indice de motor
   if(offset<0) return;

   //--- P3: las flechas se llenan desde el HISTORICO de senales, no desde los
   //    setups vivos (limitados a 32). Asi ninguna senal antigua desaparece.
   const int nsig=g_engine.SignalCount();
   for(int i=0;i<nsig;i++)
     {
      SBISignal g=g_engine.SignalAt(i);
      const int ci=offset+g.barIdx;
      if(ci<0 || ci>=rates_total) continue;

      if(g.type==BI_EV_BREAKOUT)
        {
         const double a=g_engine.Atr(g.barIdx)*0.5;
         if(g.dir>0) BufBreakUp[ci]=low[ci]-a;
         else        BufBreakDn[ci]=high[ci]+a;
        }
      else if(g.type==BI_EV_RETEST)
        {
         const double a=g_engine.Atr(g.barIdx)*0.35;
         if(g.dir>0) BufRetestUp[ci]=low[ci]-a;
         else        BufRetestDn[ci]=high[ci]+a;
        }
      else if(g.type==BI_EV_ENTRY)
        {
         const double a=g_engine.Atr(g.barIdx)*0.8;
         if(g.dir>0) BufEntryUp[ci]=low[ci]-a;
         else        BufEntryDn[ci]=high[ci]+a;
         BufScore[ci]=(double)g.score;
         BufState[ci]=(double)(g.dir>0 ? 1 : -1);
        }
     }
  }

//| Despacho de alertas de la ultima barra cerrada                   |
//+------------------------------------------------------------------+
void DispatchAlerts()
  {
   const int lastClosed=g_engine.LastClosedIdx();
   const int ec=g_engine.EventCount();
   for(int i=0;i<ec;i++)
     {
      SBIEvent e=g_engine.EventAt(i);
      if(e.barIdx!=lastClosed) continue;       // solo la ultima vela cerrada
      g_alerts.Fire(e);
     }
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(!g_initialized) return(0);
   if(rates_total<g_engine.Warmup()+10)
     {
      g_lastStatus="Historico insuficiente en el grafico";
      return(0);
     }

   ArraySetAsSeries(time ,false);
   ArraySetAsSeries(open ,false);
   ArraySetAsSeries(high ,false);
   ArraySetAsSeries(low  ,false);
   ArraySetAsSeries(close,false);

   const datetime curBarTime=time[rates_total-1];
   const bool     newBar    =(curBarTime!=g_lastBarTime);
   const bool     fullReset =(prev_calculated==0);

   //--- Entre velas no se recalcula nada: solo se refresca el panel.
   //    Es lo que garantiza que ninguna senal confirmada cambie con el tick.
   if(!newBar && !fullReset)
     {
      g_render.DrawStatus(g_engine,g_lastStatus);
      return(rates_total);
     }

   if(fullReset)
     {
      g_alerts.ResetHistory();
      g_firstBuild=true;
      g_render.Clear();
     }

   if(!g_engine.Rebuild())
     {
      g_lastStatus="Esperando datos: "+g_engine.LastError();
      g_render.DrawStatus(g_engine,g_lastStatus);
      return(0);                                // reintentara en el proximo tick
     }

   //--- comprobacion de alineacion entre el motor y los arrays del grafico
   const int engN=g_engine.BarCount();
   const int offset=rates_total-engN;
   if(offset<0 || g_engine.BarTime(engN-1)!=time[rates_total-1])
     {
      g_lastStatus="Desalineacion temporal: se reintentara";
      g_render.DrawStatus(g_engine,g_lastStatus);
      return(0);
     }

   ClearBuffers();
   FillBuffers(rates_total,high,low);

   if(!g_firstBuild)
      DispatchAlerts();
   g_firstBuild=false;

   g_lastBarTime=curBarTime;
   g_lastStatus="";
   g_render.Draw(g_engine);
   g_render.DrawStatus(g_engine,g_lastStatus);
   ChartRedraw();

   return(rates_total);
  }
//+------------------------------------------------------------------+
