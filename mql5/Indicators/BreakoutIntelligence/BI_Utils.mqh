//+------------------------------------------------------------------+
//|                                                     BI_Utils.mqh |
//|  Breakout Intelligence MT5 - utilidades comunes                  |
//+------------------------------------------------------------------+
#ifndef __BI_UTILS_MQH__
#define __BI_UTILS_MQH__

#include "BI_Types.mqh"

//+------------------------------------------------------------------+
//| Limita un entero al intervalo [lo, hi]                           |
//+------------------------------------------------------------------+
int BI_ClampInt(const int v,const int lo,const int hi)
  {
   if(v<lo) return(lo);
   if(v>hi) return(hi);
   return(v);
  }

//+------------------------------------------------------------------+
//| Limita un double al intervalo [lo, hi]                           |
//+------------------------------------------------------------------+
double BI_ClampDbl(const double v,const double lo,const double hi)
  {
   if(v<lo) return(lo);
   if(v>hi) return(hi);
   return(v);
  }

//+------------------------------------------------------------------+
//| Devuelve val si es > 0, en caso contrario def                    |
//+------------------------------------------------------------------+
double BI_OrDefault(const double val,const double def)
  {
   return(val>0.0 ? val : def);
  }

//+------------------------------------------------------------------+
//| Idem para enteros                                                |
//+------------------------------------------------------------------+
int BI_OrDefaultInt(const int val,const int def)
  {
   return(val>0 ? val : def);
  }

//+------------------------------------------------------------------+
//| Hora (0-23) del servidor para un instante dado                   |
//+------------------------------------------------------------------+
int BI_HourOf(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t,dt);
   return(dt.hour);
  }

//+------------------------------------------------------------------+
//| Dia de la semana (0=domingo) para un instante dado               |
//+------------------------------------------------------------------+
int BI_DayOfWeekOf(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t,dt);
   return(dt.day_of_week);
  }

//+------------------------------------------------------------------+
//| Comprueba si "hour" esta dentro de [start,end) admitiendo que    |
//| la ventana cruce la medianoche (start > end)                     |
//+------------------------------------------------------------------+
bool BI_HourInWindow(const int hour,const int startHour,const int endHour)
  {
   if(startHour==endHour)
      return(true);                       // ventana de 24 h
   if(startHour<endHour)
      return(hour>=startHour && hour<endHour);
   return(hour>=startHour || hour<endHour);
  }

//+------------------------------------------------------------------+
//| Sesion favorable segun hasta DOS ventanas horarias.              |
//|                                                                  |
//| IMPORTANTE: las horas son horas del SERVIDOR del broker. No hay  |
//| conversion a UTC ni ajuste de horario de verano; el usuario      |
//| define las horas que correspondan a su servidor. Una ventana con |
//| start==end==-1 se considera no utilizada.                        |
//+------------------------------------------------------------------+
bool BI_InWindows(const datetime t,const int s1,const int e1,const int s2,const int e2)
  {
   const int h=BI_HourOf(t);
   if(s1>=0 && e1>=0 && BI_HourInWindow(h,s1,e1)) return(true);
   if(s2>=0 && e2>=0 && BI_HourInWindow(h,s2,e2)) return(true);
   return(false);
  }

//+------------------------------------------------------------------+
//| Texto de la direccion                                            |
//+------------------------------------------------------------------+
string BI_DirText(const int dir)
  {
   if(dir>0) return("ALCISTA");
   if(dir<0) return("BAJISTA");
   return("NEUTRO");
  }

//+------------------------------------------------------------------+
//| Texto corto BUY / SELL                                           |
//+------------------------------------------------------------------+
string BI_SideText(const int dir)
  {
   if(dir>0) return("BUY");
   if(dir<0) return("SELL");
   return("---");
  }

//+------------------------------------------------------------------+
//| Texto del estado                                                 |
//+------------------------------------------------------------------+
string BI_StateText(const int state)
  {
   switch(state)
     {
      case BI_ST_BREAKOUT:    return("RUPTURA - esperando retesteo");
      case BI_ST_RETEST:      return("RETESTEO - esperando confirmacion");
      case BI_ST_CONFIRMED:   return("SETUP CONFIRMADO");
      case BI_ST_INVALIDATED: return("INVALIDADO");
      case BI_ST_EXPIRED:     return("CADUCADO");
     }
   return("SIN SETUP");
  }

//+------------------------------------------------------------------+
//| Texto del tipo de nivel                                          |
//+------------------------------------------------------------------+
string BI_LevelKindText(const int kind)
  {
   switch(kind)
     {
      case BI_LK_SWING: return("Estructura");
      case BI_LK_RANGE: return("Rango");
      case BI_LK_PDAY:  return("Dia previo");
      case BI_LK_PWEEK: return("Semana previa");
      case BI_LK_ASIA:  return("Sesion asiatica");
     }
   return("Nivel");
  }

//+------------------------------------------------------------------+
//| Texto del tipo de confirmacion                                   |
//+------------------------------------------------------------------+
string BI_ConfirmText(const int kind)
  {
   switch(kind)
     {
      case BI_CONF_CONTINUATION: return("cierre de continuacion");
      case BI_CONF_ENGULFING:    return("vela envolvente");
      case BI_CONF_REJECTION:    return("rechazo / pin bar");
      case BI_CONF_STRUCTURE:    return("estructura favorable");
     }
   return("sin confirmacion");
  }

//+------------------------------------------------------------------+
//| Clasificacion textual del score                                  |
//+------------------------------------------------------------------+
string BI_GradeText(const int score)
  {
   if(score>=80) return("A");
   if(score>=65) return("B");
   if(score>=50) return("C");
   return("D");
  }

//+------------------------------------------------------------------+
//| Color asociado a la clasificacion                                |
//+------------------------------------------------------------------+
color BI_GradeColor(const int score)
  {
   if(score>=80) return(clrLimeGreen);
   if(score>=65) return(clrGold);
   if(score>=50) return(clrSilver);
   return(clrTomato);
  }

//+------------------------------------------------------------------+
//| Texto del perfil                                                 |
//+------------------------------------------------------------------+
string BI_ProfileText(const int profile)
  {
   switch(profile)
     {
      case BI_PROFILE_FOREX:  return("FOREX");
      case BI_PROFILE_METAL:  return("METALES");
      case BI_PROFILE_CRYPTO: return("CRIPTO");
      case BI_PROFILE_INDEX:  return("INDICES");
     }
   return("AUTO");
  }

//+------------------------------------------------------------------+
//| Formatea un precio con los digitos del simbolo                   |
//+------------------------------------------------------------------+
string BI_Px(const double price,const int digits)
  {
   return(DoubleToString(price,digits));
  }

//+------------------------------------------------------------------+
//| Nombre corto y legible de un timeframe                           |
//+------------------------------------------------------------------+
string BI_TfText(const ENUM_TIMEFRAMES tf)
  {
   string s=EnumToString(tf);
   StringReplace(s,"PERIOD_","");
   return(s);
  }


//+------------------------------------------------------------------+
//| Maximo / minimo de dos enteros (evita la conversion a double)    |
//+------------------------------------------------------------------+
int BI_MaxInt(const int a,const int b) { return(a>b ? a : b); }
int BI_MinInt(const int a,const int b) { return(a<b ? a : b); }


//+------------------------------------------------------------------+
//| ATR(period) de Wilder sobre un array de MqlRates alineado por la  |
//| derecha. Es CAUSAL: dest[i] solo depende de barras <= i, por lo   |
//| que puede usarse para el TF de estructura sin look-ahead.         |
//| Sembrado con la media simple de los primeros `period` TR, como    |
//| iATR de MT5. dest[i]=0 mientras no haya datos suficientes.        |
//+------------------------------------------------------------------+
void BI_AtrArray(const MqlRates &r[],const int n,const int period,double &dest[])
  {
   ArrayResize(dest,n);
   ArrayInitialize(dest,0.0);
   if(n<=0 || period<=0 || n<period) return;

   double tr[];
   ArrayResize(tr,n);
   for(int i=0;i<n;i++)
     {
      const double hl=r[i].high-r[i].low;
      if(i==0) { tr[i]=hl; continue; }
      const double hc=MathAbs(r[i].high-r[i-1].close);
      const double lc=MathAbs(r[i].low -r[i-1].close);
      tr[i]=MathMax(hl,MathMax(hc,lc));
     }

   double sum=0.0;
   for(int i=0;i<period;i++) sum+=tr[i];
   dest[period-1]=sum/period;                          // siembra (SMA de TR)
   for(int i=period;i<n;i++)
      dest[i]=(dest[i-1]*(period-1)+tr[i])/period;      // suavizado de Wilder
  }

#endif // __BI_UTILS_MQH__
