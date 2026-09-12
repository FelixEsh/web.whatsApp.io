//+------------------------------------------------------------------+
//|                                                    BI_Levels.mqh |
//|  Breakout Intelligence MT5 - pivotes, niveles y rangos           |
//+------------------------------------------------------------------+
#ifndef __BI_LEVELS_MQH__
#define __BI_LEVELS_MQH__

#include "BI_Types.mqh"
#include "BI_Utils.mqh"

//+------------------------------------------------------------------+
//| Pivote maximo en la barra p.                                     |
//| Definicion: high[p] >= high[p-k] y high[p] > high[p+k] para todo |
//| k en [1, depth]. La desigualdad estricta por la derecha evita    |
//| que una meseta de maximos iguales genere varios pivotes.         |
//| IMPORTANTE: el pivote solo es CONOCIBLE en la barra p+depth.     |
//+------------------------------------------------------------------+
bool BI_IsPivotHigh(const MqlRates &r[],const int n,const int p,const int depth)
  {
   if(p-depth<0 || p+depth>=n) return(false);
   const double v=r[p].high;
   for(int k=1;k<=depth;k++)
     {
      if(r[p-k].high>v)  return(false);
      if(r[p+k].high>=v) return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Pivote minimo en la barra p (simetrico del anterior)             |
//+------------------------------------------------------------------+
bool BI_IsPivotLow(const MqlRates &r[],const int n,const int p,const int depth)
  {
   if(p-depth<0 || p+depth>=n) return(false);
   const double v=r[p].low;
   for(int k=1;k<=depth;k++)
     {
      if(r[p-k].low<v)  return(false);
      if(r[p+k].low<=v) return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Deteccion de rango / consolidacion terminada en la barra k.      |
//|                                                                  |
//| Reglas (todas comprobables numericamente):                       |
//|  1. Se toma la ventana mas LARGA, entre minBars y maxBars, cuya  |
//|     anchura (max high - min low) no supere maxWidthATR * ATR.    |
//|     La anchura es monotona no decreciente al ampliar la ventana, |
//|     por lo que basta ampliar hasta que se incumpla.              |
//|  2. La ventana debe tener al menos minTouchesSide toques en el   |
//|     borde superior y otros tantos en el inferior, contando como  |
//|     toque high >= hi - touchATR*ATR (resp. low <= lo + tol).     |
//|  3. La deriva |close[k] - close[k-m+1]| / anchura no puede       |
//|     superar maxDrift, para descartar tramos en tendencia.        |
//+------------------------------------------------------------------+
bool BI_DetectRange(const MqlRates &r[],const int n,const int k,
                    const int minBars,const int maxBars,
                    const double atr,const double maxWidthATR,
                    const double touchATR,const double maxDrift,
                    const int minTouchesSide,
                    double &outHi,double &outLo,int &outBars)
  {
   outHi=0.0; outLo=0.0; outBars=0;
   if(atr<=0.0 || k<minBars-1 || k>=n) return(false);

   const double maxWidth=maxWidthATR*atr;

   double hi=r[k].high, lo=r[k].low;
   double bestHi=0.0, bestLo=0.0;
   int    bestBars=0;

   for(int m=1;m<=maxBars;m++)
     {
      const int idx=k-m+1;
      if(idx<0) break;
      if(r[idx].high>hi) hi=r[idx].high;
      if(r[idx].low <lo) lo=r[idx].low;
      if(m<minBars) continue;
      if((hi-lo)>maxWidth) break;   // al ampliar solo puede crecer: paramos
      bestHi=hi; bestLo=lo; bestBars=m;
     }

   if(bestBars<minBars) return(false);

   const double width=bestHi-bestLo;
   if(width<=0.0) return(false);

   const double tol=touchATR*atr;
   int touchHi=0, touchLo=0;
   for(int m=0;m<bestBars;m++)
     {
      const int idx=k-m;
      if(idx<0) break;
      if(r[idx].high>=bestHi-tol) touchHi++;
      if(r[idx].low <=bestLo+tol) touchLo++;
     }
   if(touchHi<minTouchesSide || touchLo<minTouchesSide) return(false);

   //--- deriva: se comparan las MEDIAS de los cierres del primer y del ultimo
   //    quinto de la ventana. Comparar dos cierres sueltos es demasiado
   //    sensible al ruido y descartaria consolidaciones validas.
   const int firstIdx=k-bestBars+1;
   if(firstIdx<0) return(false);
   const int q=BI_MaxInt(3,bestBars/5);
   double sumFirst=0.0,sumLast=0.0;
   for(int m=0;m<q;m++)
     {
      sumFirst+=r[firstIdx+m].close;
      sumLast +=r[k-m].close;
     }
   const double drift=MathAbs(sumLast-sumFirst)/(double)q/width;
   if(drift>maxDrift) return(false);

   outHi=bestHi; outLo=bestLo; outBars=bestBars;
   return(true);
  }

//+------------------------------------------------------------------+
//| Prioridad de un tipo de nivel (menor = mas relevante)            |
//+------------------------------------------------------------------+
int BI_LevelKindRank(const int kind)
  {
   switch(kind)
     {
      case BI_LK_RANGE: return(0);
      case BI_LK_PWEEK: return(1);
      case BI_LK_PDAY:  return(2);
      case BI_LK_ASIA:  return(3);
      case BI_LK_SWING: return(4);
     }
   return(5);
  }

//+------------------------------------------------------------------+
//| Puntos de relevancia del nivel (componente scLevel, max 20)      |
//+------------------------------------------------------------------+
int BI_LevelScore(const int kind,const int touches)
  {
   int base=0;
   switch(kind)
     {
      case BI_LK_RANGE: base=20; break;
      case BI_LK_PWEEK: base=19; break;
      case BI_LK_PDAY:  base=18; break;
      case BI_LK_ASIA:  base=14; break;
      default:
        {
         if(touches>=4)      base=20;
         else if(touches==3) base=17;
         else if(touches==2) base=14;
         else                base=8;
         break;
        }
     }
   if(kind!=BI_LK_SWING && touches>=3) base=20;
   return(BI_ClampInt(base,0,20));
  }

//+------------------------------------------------------------------+
//| Gestor de niveles                                                |
//+------------------------------------------------------------------+
class CBILevels
  {
public:
   SBILevel          Items[];
   int               Count;

private:
   int               m_nextId;
   double            m_maxZoneWidth;   // anchura maxima admitida de una zona

public:
                     CBILevels(void) { Count=0; m_nextId=1; m_maxZoneWidth=0.0; }
                    ~CBILevels(void) {}

   //--- Reinicia el gestor (reconstruccion completa)
   void              Reset(void)
     {
      ArrayResize(Items,0);
      Count=0;
      m_nextId=1;
     }

   //--- Anchura maxima de zona permitida al fusionar
   void              SetMaxZoneWidth(const double w) { m_maxZoneWidth=w; }

   //--- Localiza el indice de un nivel por su id (-1 si no existe)
   int               IndexOfId(const int id) const
     {
      for(int i=0;i<Count;i++)
         if(Items[i].id==id) return(i);
      return(-1);
     }

   //--- Anade un toque o crea un nivel nuevo. Devuelve el id.
   int               AddOrMerge(const double price,const int kind,const int barIdx,
                                const int knownIdx,const double tol)
     {
      if(price<=0.0) return(-1);

      int best=-1;
      double bestDist=DBL_MAX;
      for(int i=0;i<Count;i++)
        {
         if(!Items[i].active)       continue;
         if(Items[i].brokenDir!=0)  continue;         // no reciclamos niveles rotos
         if(price>Items[i].hi+tol)  continue;
         if(price<Items[i].lo-tol)  continue;
         const double nhi=MathMax(Items[i].hi,price);
         const double nlo=MathMin(Items[i].lo,price);
         if(m_maxZoneWidth>0.0 && (nhi-nlo)>m_maxZoneWidth) continue;
         const double dist=MathAbs(price-Items[i].price);
         if(dist<bestDist) { bestDist=dist; best=i; }
        }

      if(best>=0)
        {
         Items[best].hi=MathMax(Items[best].hi,price);
         Items[best].lo=MathMin(Items[best].lo,price);
         Items[best].price=(Items[best].hi+Items[best].lo)*0.5;
         Items[best].touches++;
         Items[best].lastIdx=barIdx;
         //--- knownIdx no se toca: el nivel ya era conocido antes de este toque
         if(BI_LevelKindRank(kind)<BI_LevelKindRank(Items[best].kind))
            Items[best].kind=kind;
         return(Items[best].id);
        }

      if(Count>=BI_MAX_LEVELS && !Compact())
         return(-1);

      if(ArrayResize(Items,Count+1)!=Count+1)
         return(-1);

      SBILevel lv;
      lv.id           = m_nextId++;
      lv.kind         = kind;
      lv.price        = price;
      lv.hi           = price;
      lv.lo           = price;
      lv.touches      = 1;
      lv.firstIdx     = barIdx;
      lv.knownIdx     = knownIdx;
      lv.lastIdx      = barIdx;
      lv.brokenDir    = 0;
      lv.brokenIdx    = -1;
      lv.lastWatchIdx = -1000000;
      lv.active       = true;
      Items[Count]    = lv;
      Count++;
      return(lv.id);
     }

   //--- Desactiva niveles obsoletos
   void              Prune(const int barIdx,const int lookback)
     {
      for(int i=0;i<Count;i++)
        {
         if(!Items[i].active) continue;
         const int ref=(Items[i].brokenDir!=0 ? Items[i].brokenIdx : Items[i].lastIdx);
         if(barIdx-ref>lookback) Items[i].active=false;
        }
     }

   //--- Elimina fisicamente los niveles inactivos. false si no libero nada.
   bool              Compact(void)
     {
      int w=0;
      for(int i=0;i<Count;i++)
        {
         if(!Items[i].active) continue;
         if(w!=i) Items[w]=Items[i];
         w++;
        }
      if(w==Count) return(false);
      Count=w;
      ArrayResize(Items,Count);
      return(true);
     }
  };

#endif // __BI_LEVELS_MQH__
