//+------------------------------------------------------------------+
//|                                                   BI_Profile.mqh |
//|  Breakout Intelligence MT5 - perfiles por familia de activo      |
//+------------------------------------------------------------------+
#ifndef __BI_PROFILE_MQH__
#define __BI_PROFILE_MQH__

#include "BI_Types.mqh"
#include "BI_Utils.mqh"

//+------------------------------------------------------------------+
//| Valores por defecto dependientes del activo.                     |
//| Todos los margenes se expresan en multiplos de ATR(14) del       |
//| timeframe de senal, de modo que el motor es independiente de     |
//| los digitos, el tick size y el tamano de contrato del simbolo.   |
//+------------------------------------------------------------------+
struct SBIProfileDefaults
  {
   double breakMarginATR;      // margen minimo de cierre fuera de la zona
   double breakMarginSpreads;  // margen minimo en multiplos del spread
   double retestTolATR;        // profundidad admitida del retesteo
   double reentryATR;          // cierre de vuelta que invalida la ruptura
   double clusterATR;          // tolerancia de agrupacion de pivotes
   double rangeMaxWidthATR;    // anchura maxima de un rango valido
   double rangeTouchATR;       // tolerancia para contar un toque del rango
   double minBodyRatio;        // cuerpo minimo de la vela de ruptura
   double minCloseLoc;         // posicion minima del cierre dentro de la vela
   double minBarRangeATR;      // recorrido minimo de la vela de ruptura
   double pinWickRatio;        // mecha minima para considerar rechazo
   double watchDistATR;        // distancia de aviso de aproximacion
   double volumeMult;          // volumen relativo considerado favorable
   double slAtrMult;           // colchon de ATR para el SL sugerido
   int    retestMaxBars;       // caducidad de la ruptura sin retesteo
   int    confirmMaxBars;      // caducidad del retesteo sin confirmacion
  };

//+------------------------------------------------------------------+
//| Normaliza el nombre del simbolo a mayusculas sin separadores     |
//+------------------------------------------------------------------+
string BI_NormalizeSymbol(const string symbol)
  {
   string s=symbol;
   StringToUpper(s);
   StringReplace(s,".","");
   StringReplace(s,"_","");
   StringReplace(s,"-","");
   StringReplace(s,"/","");
   StringReplace(s," ","");
   return(s);
  }

//+------------------------------------------------------------------+
//| Clasifica el simbolo en una familia de activo.                   |
//| El orden de comprobacion importa: metales y cripto antes que     |
//| los indices, y los indices antes que el patron de divisas.       |
//+------------------------------------------------------------------+
int BI_DetectProfile(const string symbol)
  {
   const string s=BI_NormalizeSymbol(symbol);

   if(StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0 ||
      StringFind(s,"XAG")>=0 || StringFind(s,"SILVER")>=0 ||
      StringFind(s,"XPT")>=0 || StringFind(s,"XPD")>=0)
      return(BI_PROFILE_METAL);

   if(StringFind(s,"BTC")>=0 || StringFind(s,"XBT")>=0 ||
      StringFind(s,"ETH")>=0 || StringFind(s,"LTC")>=0 ||
      StringFind(s,"XRP")>=0 || StringFind(s,"SOL")>=0 ||
      StringFind(s,"DOGE")>=0)
      return(BI_PROFILE_CRYPTO);

   if(StringFind(s,"NAS")>=0   || StringFind(s,"US100")>=0 ||
      StringFind(s,"USTEC")>=0 || StringFind(s,"NDX")>=0   ||
      StringFind(s,"US30")>=0  || StringFind(s,"US500")>=0 ||
      StringFind(s,"SPX")>=0   || StringFind(s,"DJ")>=0    ||
      StringFind(s,"GER")>=0   || StringFind(s,"DAX")>=0   ||
      StringFind(s,"UK100")>=0 || StringFind(s,"JP225")>=0 ||
      StringFind(s,"HK50")>=0  || StringFind(s,"AUS200")>=0)
      return(BI_PROFILE_INDEX);

   return(BI_PROFILE_FOREX);
  }

//+------------------------------------------------------------------+
//| Devuelve los valores por defecto del perfil indicado             |
//+------------------------------------------------------------------+
SBIProfileDefaults BI_ProfileDefaults(const int profile)
  {
   SBIProfileDefaults d;

   //--- base: Forex
   d.breakMarginATR     = 0.25;
   d.breakMarginSpreads = 2.0;
   d.retestTolATR       = 0.35;
   d.reentryATR         = 0.10;
   d.clusterATR         = 0.35;
   d.rangeMaxWidthATR   = 2.5;
   d.rangeTouchATR      = 0.20;
   d.minBodyRatio       = 0.50;
   d.minCloseLoc        = 0.60;
   d.minBarRangeATR     = 0.50;
   d.pinWickRatio       = 0.50;
   d.watchDistATR       = 0.75;
   d.volumeMult         = 1.20;
   d.slAtrMult          = 0.35;
   d.retestMaxBars      = 12;
   d.confirmMaxBars     = 8;

   if(profile==BI_PROFILE_METAL)
     {
      d.breakMarginATR     = 0.35;
      d.breakMarginSpreads = 2.5;
      d.retestTolATR       = 0.45;
      d.reentryATR         = 0.15;
      d.clusterATR         = 0.40;
      d.rangeMaxWidthATR   = 3.0;
      d.rangeTouchATR      = 0.25;
      d.minBodyRatio       = 0.50;
      d.minCloseLoc        = 0.60;
      d.minBarRangeATR     = 0.55;
      d.watchDistATR       = 0.90;
      d.slAtrMult          = 0.45;
      d.retestMaxBars      = 14;
      d.confirmMaxBars     = 8;
     }
   else if(profile==BI_PROFILE_CRYPTO)
     {
      d.breakMarginATR     = 0.45;
      d.breakMarginSpreads = 3.0;
      d.retestTolATR       = 0.55;
      d.reentryATR         = 0.20;
      d.clusterATR         = 0.45;
      d.rangeMaxWidthATR   = 3.5;
      d.rangeTouchATR      = 0.30;
      d.minBodyRatio       = 0.55;
      d.minCloseLoc        = 0.62;
      d.minBarRangeATR     = 0.60;
      d.watchDistATR       = 1.00;
      d.volumeMult         = 1.30;
      d.slAtrMult          = 0.60;
      d.retestMaxBars      = 16;
      d.confirmMaxBars     = 10;
     }
   else if(profile==BI_PROFILE_INDEX)
     {
      d.breakMarginATR     = 0.30;
      d.breakMarginSpreads = 2.5;
      d.retestTolATR       = 0.40;
      d.reentryATR         = 0.12;
      d.clusterATR         = 0.38;
      d.rangeMaxWidthATR   = 3.0;
      d.rangeTouchATR      = 0.25;
      d.minBodyRatio       = 0.50;
      d.minCloseLoc        = 0.60;
      d.minBarRangeATR     = 0.55;
      d.watchDistATR       = 0.85;
      d.volumeMult         = 1.25;
      d.slAtrMult          = 0.40;
      d.retestMaxBars      = 14;
      d.confirmMaxBars     = 8;
     }

   return(d);
  }

//+------------------------------------------------------------------+
//| Resuelve hasta DOS ventanas de sesion en HORARIO DE SERVIDOR.    |
//|                                                                  |
//| El usuario indica las horas de Londres y Nueva York tal como las |
//| ve en su servidor (no en UTC). No se aplica ningun ajuste de     |
//| horario de verano: si el broker cambia de offset, el usuario     |
//| ajusta las horas. Esto elimina el "shift" ambiguo anterior.      |
//|                                                                  |
//|   LONDON  -> ventana 1 = Londres                                 |
//|   NEWYORK -> ventana 1 = Nueva York                              |
//|   LDN_NY  -> ventana 1 = Londres, ventana 2 = Nueva York         |
//|   CUSTOM  -> ventana 1 = horario personalizado                   |
//| Ventana no utilizada -> start=end=-1.                            |
//+------------------------------------------------------------------+
void BI_ResolveSessions(const int filter,
                        const int lonStart,const int lonEnd,
                        const int nyStart,const int nyEnd,
                        const int cusStart,const int cusEnd,
                        int &s1,int &e1,int &s2,int &e2)
  {
   s1=-1; e1=-1; s2=-1; e2=-1;
   switch(filter)
     {
      case BI_SESS_LONDON:  s1=lonStart; e1=lonEnd; break;
      case BI_SESS_NEWYORK: s1=nyStart;  e1=nyEnd;  break;
      case BI_SESS_LDN_NY:  s1=lonStart; e1=lonEnd; s2=nyStart; e2=nyEnd; break;
      case BI_SESS_CUSTOM:  s1=cusStart; e1=cusEnd; break;
      default:              break;   // OFF: ninguna ventana
     }
  }

#endif // __BI_PROFILE_MQH__
