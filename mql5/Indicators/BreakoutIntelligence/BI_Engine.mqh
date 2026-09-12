//+------------------------------------------------------------------+
//|                                                    BI_Engine.mqh |
//|  Breakout Intelligence MT5 - motor de estados y puntuacion       |
//|                                                                  |
//|  POLITICA ANTI-REPINTADO                                         |
//|  ------------------------                                        |
//|  1. El motor solo evalua barras CERRADAS: el recorrido llega     |
//|     hasta el indice m_n-2 (la barra m_n-1 esta en formacion).    |
//|  2. Cada barra k se evalua usando exclusivamente informacion de  |
//|     barras <= k. Un pivote situado en la barra p solo se         |
//|     incorpora en la barra p+pivotDepth, que es cuando queda      |
//|     confirmado.                                                  |
//|  3. Las series de timeframe superior se alinean exigiendo que la |
//|     barra superior este CERRADA antes del cierre de la barra k.  |
//|  4. La reconstruccion completa es determinista: procesar todo el |
//|     historico produce exactamente la misma secuencia de estados  |
//|     que se obtuvo barra a barra en tiempo real.                  |
//+------------------------------------------------------------------+
#ifndef __BI_ENGINE_MQH__
#define __BI_ENGINE_MQH__

#include "BI_Types.mqh"
#include "BI_Utils.mqh"
#include "BI_Profile.mqh"
#include "BI_Levels.mqh"

//+------------------------------------------------------------------+
//| Copia un buffer de indicador a un array alineado por la derecha  |
//| (el ultimo elemento corresponde a la barra actual)               |
//+------------------------------------------------------------------+
bool BI_CopyAligned(const int handle,const int buffer,const int count,double &dest[])
  {
   if(handle==INVALID_HANDLE || count<=0) return(false);
   if(ArrayResize(dest,count)!=count) return(false);
   ArrayInitialize(dest,0.0);

   double tmp[];
   ArraySetAsSeries(tmp,false);
   const int copied=CopyBuffer(handle,buffer,0,count,tmp);
   if(copied<=0) return(false);

   const int off=count-copied;
   for(int i=0;i<copied;i++)
      dest[off+i]=tmp[i];
   return(true);
  }

//+------------------------------------------------------------------+
//| Media movil simple sobre un array alineado (0 si no hay datos)   |
//+------------------------------------------------------------------+
void BI_SmaArray(const double &src[],const int n,const int period,double &dest[])
  {
   ArrayResize(dest,n);
   ArrayInitialize(dest,0.0);
   if(period<=0 || n<=0) return;

   double sum=0.0;
   int    cnt=0;
   for(int i=0;i<n;i++)
     {
      sum+=src[i];
      cnt++;
      if(cnt>period) { sum-=src[i-period]; cnt=period; }
      if(cnt==period) dest[i]=sum/period;
     }
  }

//+------------------------------------------------------------------+
//| Motor principal                                                  |
//+------------------------------------------------------------------+
class CBIEngine
  {
private:
   SBIParams         m_par;
   CBILevels         m_levels;

   MqlRates          m_rates[];
   int               m_n;
   int               m_warmup;

   int               m_digits;
   double            m_point;
   double            m_tickSize;

   int               m_hAtr,m_hEma,m_hRsi,m_hCtxEma;

   double            m_atr[],m_atrAvg[],m_ema[],m_rsi[];
   double            m_ctxEma[],m_ctxEmaPrev[],m_ctxClose[];
   double            m_pdh[],m_pdl[],m_pwh[],m_pwl[];
   double            m_vol[],m_volMA[];
   bool              m_volUsable;
   bool              m_volIsTick;      // true si se uso tick volume (no real)

   SBISetup          m_setups[];
   int               m_setupCount;
   int               m_nextSetupId;

   SBIEvent          m_events[];
   int               m_eventCount;

   //--- historico de senales, independiente del cap de setups vivos (P3)
   SBISignal         m_signals[];
   int               m_signalCount;

   //--- niveles precomputados del timeframe de estructura (P1)
   double            m_slPrice[];
   int               m_slKind[];
   int               m_slKnownIdx[];
   int               m_slCount;
   int               m_slCursor;
   //--- rangos del TF de estructura (solo para dibujar la caja)
   double            m_srHi[];
   double            m_srLo[];
   int               m_srKnown[];
   int               m_srBars[];
   int               m_srCount;
   int               m_srCursor;

   //--- estado incremental del recorrido
   double            m_lastPdh,m_lastPdl,m_lastPwh,m_lastPwl;
   double            m_lastRangeHi,m_lastRangeLo;
   double            m_rangeHi,m_rangeLo;
   int               m_rangeBars,m_rangeIdx;
   bool              m_asiaOpen;
   int               m_asiaKey;
   double            m_asiaHi,m_asiaLo;
   int               m_s1Start,m_s1End,m_s2Start,m_s2End;
   string            m_lastError;

public:
                     CBIEngine(void);
                    ~CBIEngine(void);

   bool              Init(const SBIParams &p);
   void              Deinit(void);
   bool              Rebuild(void);

   //--- acceso de solo lectura
   int               BarCount(void)      const { return(m_n); }
   int               LastClosedIdx(void) const { return(m_n-2); }
   int               Warmup(void)        const { return(m_warmup); }
   string            LastError(void)     const { return(m_lastError); }
   datetime          BarTime(const int k) const
     { return(k>=0 && k<m_n ? m_rates[k].time : 0); }
   double            Atr(const int k) const
     { return(k>=0 && k<m_n ? m_atr[k] : 0.0); }
   double            AtrRatio(const int k) const
     { return(k>=0 && k<m_n && m_atrAvg[k]>0.0 ? m_atr[k]/m_atrAvg[k] : 0.0); }
   double            Rsi(const int k) const
     { return(k>=0 && k<m_n ? m_rsi[k] : 0.0); }
   double            Ema(const int k) const
     { return(k>=0 && k<m_n ? m_ema[k] : 0.0); }
   bool              VolumeUsable(void) const { return(m_volUsable); }
   bool              VolumeIsTick(void) const { return(m_volIsTick); }
   int               TrendState(const int k) const;
   bool              InSession(const int k) const;

   int               SetupCount(void) const { return(m_setupCount); }
   SBISetup          SetupAt(const int i) const { return(m_setups[i]); }
   int               LevelCount(void) { return(m_levels.Count); }
   SBILevel          LevelAt(const int i) { return(m_levels.Items[i]); }
   int               EventCount(void) const { return(m_eventCount); }
   SBIEvent          EventAt(const int i) const { return(m_events[i]); }
   int               SignalCount(void) const { return(m_signalCount); }
   SBISignal         SignalAt(const int i) const { return(m_signals[i]); }
   bool              CurrentRange(double &hi,double &lo,int &bars,int &idx) const;
   int               LastActiveSetup(void) const;

private:
   bool              LoadData(void);
   bool              AlignContext(void);
   bool              AlignReference(const ENUM_TIMEFRAMES tf,double &outHi[],double &outLo[]);
   bool              BuildStructureLevels(void);
   void              BuildVolume(void);
   void              ResetRun(void);
   void              InjectStructureLevels(const int k);
   void              AppendSignal(const int type,const SBISetup &s,const int k);

   void              ProcessBar(const int k);
   void              UpdatePivots(const int k);
   void              UpdateReferenceLevels(const int k);
   void              UpdateRangeLevels(const int k);
   void              UpdateSetups(const int k);
   void              DetectBreakouts(const int k);
   void              DetectWatch(const int k);

   double            BreakMargin(const int k) const;
   double            ClusterTol(const int k) const;
   bool              HardFiltersPass(const int k,const int dir) const;
   bool              IsConfirmation(const int k,const SBISetup &s,int &confirmKind) const;
   bool              LevelEligible(const int li,const int k);

   int               ScoreLevelComp(const SBILevel &lv) const;
   int               ScoreCloseComp(const int k,const double edge,const double margin,const int dir) const;
   int               ScoreTrendComp(const int k,const int dir) const;
   int               ScoreVolaComp(const int k) const;
   int               ScoreSessionComp(const int k) const;
   int               ScoreVolumeComp(const int k) const;
   int               ScoreRetestComp(const SBISetup &s) const;
   int               ScoreConfirmComp(const int confirmKind) const;
   void              RecalcScore(SBISetup &s) const;

   void              AppendEvent(const SBIEvent &e);
   void              PushEvent(const int type,const SBISetup &s,const int k);
   bool              HasLiveSetup(const int levelId,const int dir) const;
   int               LiveSetupCount(void) const;
   void              PushLevelEvent(const int type,const int k,const int dir,
                                    const double level,const int levelKind);
   int               NewSetup(const int li,const int k,const int dir);
   void              CloseSetup(const int si,const int k,const int state);
   void              ComputeStops(SBISetup &s,const int k);
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CBIEngine::CBIEngine(void)
  {
   m_n=0; m_warmup=0;
   m_digits=5; m_point=0.00001; m_tickSize=0.00001;
   m_hAtr=INVALID_HANDLE; m_hEma=INVALID_HANDLE;
   m_hRsi=INVALID_HANDLE; m_hCtxEma=INVALID_HANDLE;
   m_volUsable=false; m_volIsTick=true;
   m_setupCount=0; m_nextSetupId=1; m_eventCount=0;
   m_signalCount=0; m_slCount=0; m_slCursor=0; m_srCount=0; m_srCursor=0;
   m_lastPdh=0.0; m_lastPdl=0.0; m_lastPwh=0.0; m_lastPwl=0.0;
   m_lastRangeHi=0.0; m_lastRangeLo=0.0;
   m_rangeHi=0.0; m_rangeLo=0.0; m_rangeBars=0; m_rangeIdx=-1;
   m_asiaOpen=false; m_asiaKey=-1; m_asiaHi=0.0; m_asiaLo=0.0;
   m_s1Start=-1; m_s1End=-1; m_s2Start=-1; m_s2End=-1;
   m_lastError="";
   ArraySetAsSeries(m_rates,false);
  }

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CBIEngine::~CBIEngine(void)
  {
   Deinit();
  }

//+------------------------------------------------------------------+
//| Creacion de handles y calculo del periodo de calentamiento       |
//+------------------------------------------------------------------+
bool CBIEngine::Init(const SBIParams &p)
  {
   Deinit();
   m_par=p;

   m_digits  =(int)SymbolInfoInteger(m_par.symbol,SYMBOL_DIGITS);
   m_point   =SymbolInfoDouble(m_par.symbol,SYMBOL_POINT);
   m_tickSize=SymbolInfoDouble(m_par.symbol,SYMBOL_TRADE_TICK_SIZE);
   if(m_point<=0.0)    m_point=MathPow(10.0,-m_digits);
   if(m_tickSize<=0.0) m_tickSize=m_point;

   //--- las horas de sesion ya vienen resueltas (horario de servidor)
   m_s1Start=m_par.sess1Start; m_s1End=m_par.sess1End;
   m_s2Start=m_par.sess2Start; m_s2End=m_par.sess2End;

   m_hAtr=iATR(m_par.symbol,m_par.tfSignal,m_par.atrPeriod);
   m_hEma=iMA(m_par.symbol,m_par.tfSignal,m_par.emaPeriod,0,MODE_EMA,PRICE_CLOSE);
   m_hRsi=iRSI(m_par.symbol,m_par.tfSignal,m_par.rsiPeriod,PRICE_CLOSE);
   m_hCtxEma=iMA(m_par.symbol,m_par.tfContext,m_par.emaPeriod,0,MODE_EMA,PRICE_CLOSE);

   if(m_hAtr==INVALID_HANDLE || m_hEma==INVALID_HANDLE ||
      m_hRsi==INVALID_HANDLE || m_hCtxEma==INVALID_HANDLE)
     {
      m_lastError="No se pudieron crear los handles de ATR/EMA/RSI";
      return(false);
     }

   int w=BI_MaxInt(m_par.emaPeriod+10,m_par.atrPeriod+m_par.atrRefPeriod+10);
   w=BI_MaxInt(w,m_par.lookbackBars);
   w=BI_MaxInt(w,m_par.rangeMaxBars+5);
   w=BI_MaxInt(w,m_par.rsiPeriod+10);
   w=BI_MaxInt(w,m_par.volumeMAPeriod+10);
   w=BI_MaxInt(w,m_par.pivotDepth*2+2);
   m_warmup=w+20;

   return(true);
  }

//+------------------------------------------------------------------+
//| Sesion favorable en la barra k (horario de servidor, 2 ventanas) |
//+------------------------------------------------------------------+
bool CBIEngine::InSession(const int k) const
  {
   if(m_par.sessionFilter==BI_SESS_OFF) return(true);
   if(k<0 || k>=m_n) return(false);
   return(BI_InWindows(m_rates[k].time,m_s1Start,m_s1End,m_s2Start,m_s2End));
  }

//+------------------------------------------------------------------+
//| Liberacion de recursos                                           |
//+------------------------------------------------------------------+
void CBIEngine::Deinit(void)
  {
   if(m_hAtr!=INVALID_HANDLE)    { IndicatorRelease(m_hAtr);    m_hAtr=INVALID_HANDLE; }
   if(m_hEma!=INVALID_HANDLE)    { IndicatorRelease(m_hEma);    m_hEma=INVALID_HANDLE; }
   if(m_hRsi!=INVALID_HANDLE)    { IndicatorRelease(m_hRsi);    m_hRsi=INVALID_HANDLE; }
   if(m_hCtxEma!=INVALID_HANDLE) { IndicatorRelease(m_hCtxEma); m_hCtxEma=INVALID_HANDLE; }
  }

//+------------------------------------------------------------------+
//| Carga de precios y series auxiliares                             |
//+------------------------------------------------------------------+
bool CBIEngine::LoadData(void)
  {
   const int want=m_par.maxHistoryBars+m_warmup;

   ArraySetAsSeries(m_rates,false);
   m_n=CopyRates(m_par.symbol,m_par.tfSignal,0,want,m_rates);
   if(m_n<=0)
     {
      m_lastError="CopyRates sin datos (historico no sincronizado)";
      m_n=0;
      return(false);
     }
   if(m_n<m_warmup+10)
     {
      m_lastError=StringFormat("Historico insuficiente: %d barras, se necesitan %d",
                               m_n,m_warmup+10);
      return(false);
     }

   if(!BI_CopyAligned(m_hAtr,0,m_n,m_atr)) { m_lastError="CopyBuffer(ATR) fallo";  return(false); }
   if(!BI_CopyAligned(m_hEma,0,m_n,m_ema)) { m_lastError="CopyBuffer(EMA) fallo";  return(false); }
   if(!BI_CopyAligned(m_hRsi,0,m_n,m_rsi)) { m_lastError="CopyBuffer(RSI) fallo";  return(false); }

   BI_SmaArray(m_atr,m_n,m_par.atrRefPeriod,m_atrAvg);

   if(!AlignContext()) return(false);

   ArrayResize(m_pdh,m_n); ArrayResize(m_pdl,m_n);
   ArrayResize(m_pwh,m_n); ArrayResize(m_pwl,m_n);
   ArrayInitialize(m_pdh,0.0); ArrayInitialize(m_pdl,0.0);
   ArrayInitialize(m_pwh,0.0); ArrayInitialize(m_pwl,0.0);
   if(m_par.usePrevDay)  AlignReference(PERIOD_D1,m_pdh,m_pdl);
   if(m_par.usePrevWeek) AlignReference(PERIOD_W1,m_pwh,m_pwl);

   BuildVolume();

   //--- zonas del timeframe de estructura (P1). Si falla, se degrada a las
   //    zonas del propio grafico en lugar de abortar el indicador.
   m_slCount=0; m_slCursor=0; m_srCount=0; m_srCursor=0;
   if(m_par.useStructTF && !BuildStructureLevels())
     {
      m_par.useStructTF=false;   // degradacion segura documentada en LastError
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Alineacion de la EMA de contexto (timeframe superior).           |
//| Para la barra k se usa la ULTIMA barra de contexto CERRADA antes |
//| o en el instante de cierre de k: no hay look-ahead.              |
//+------------------------------------------------------------------+
bool CBIEngine::AlignContext(void)
  {
   ArrayResize(m_ctxEma,m_n);     ArrayInitialize(m_ctxEma,0.0);
   ArrayResize(m_ctxEmaPrev,m_n); ArrayInitialize(m_ctxEmaPrev,0.0);
   ArrayResize(m_ctxClose,m_n);   ArrayInitialize(m_ctxClose,0.0);

   const int sigSec=PeriodSeconds(m_par.tfSignal);
   const int ctxSec=PeriodSeconds(m_par.tfContext);
   if(sigSec<=0 || ctxSec<=0) { m_lastError="Timeframe invalido"; return(false); }

   int need=(int)MathCeil((double)m_n*sigSec/ctxSec)+m_par.emaPeriod+50;
   need=BI_ClampInt(need,64,20000);

   datetime ct[]; double cc[];
   ArraySetAsSeries(ct,false); ArraySetAsSeries(cc,false);

   const int nT=CopyTime(m_par.symbol,m_par.tfContext,0,need,ct);
   const int nC=CopyClose(m_par.symbol,m_par.tfContext,0,need,cc);
   double tmpEma[];
   ArraySetAsSeries(tmpEma,false);
   const int nE=CopyBuffer(m_hCtxEma,0,0,need,tmpEma);
   if(nT<2 || nC<2 || nE<2)
     {
      m_lastError="Datos del timeframe de contexto no disponibles todavia";
      return(false);
     }

   const int nc=BI_MinInt(nT,BI_MinInt(nC,nE));
   if(nc<3) { m_lastError="Contexto con muy pocas barras"; return(false); }

   //--- realineamos los tres arrays por su extremo derecho (barra actual)
   datetime CT[]; double CE[],CC[];
   ArrayResize(CT,nc); ArrayResize(CE,nc); ArrayResize(CC,nc);
   for(int i=0;i<nc;i++)
     {
      CT[i]=ct[nT-nc+i];
      CE[i]=tmpEma[nE-nc+i];
      CC[i]=cc[nC-nc+i];
     }

   int j=0;
   for(int k=0;k<m_n;k++)
     {
      const datetime closeT=(datetime)(m_rates[k].time+sigSec);
      while(j+1<nc && (datetime)(CT[j+1]+ctxSec)<=closeT) j++;
      if((datetime)(CT[j]+ctxSec)<=closeT && CE[j]>0.0)
        {
         m_ctxEma[k]     = CE[j];
         m_ctxClose[k]   = CC[j];
         m_ctxEmaPrev[k] = (j>0 ? CE[j-1] : CE[j]);
        }
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Alineacion de maximos/minimos del periodo superior cerrado       |
//| (dia anterior con PERIOD_D1, semana anterior con PERIOD_W1)      |
//+------------------------------------------------------------------+
bool CBIEngine::AlignReference(const ENUM_TIMEFRAMES tf,double &outHi[],double &outLo[])
  {
   const int sigSec=PeriodSeconds(m_par.tfSignal);
   const int refSec=PeriodSeconds(tf);
   if(sigSec<=0 || refSec<=0) return(false);

   int need=(int)MathCeil((double)m_n*sigSec/refSec)+10;
   need=BI_ClampInt(need,8,5000);

   MqlRates hr[];
   ArraySetAsSeries(hr,false);
   const int nh=CopyRates(m_par.symbol,tf,0,need,hr);
   if(nh<2) return(false);

   int j=0;
   for(int k=0;k<m_n;k++)
     {
      const datetime closeT=(datetime)(m_rates[k].time+sigSec);
      while(j+1<nh && (datetime)(hr[j+1].time+refSec)<=closeT) j++;
      if((datetime)(hr[j].time+refSec)<=closeT)
        {
         outHi[k]=hr[j].high;
         outLo[k]=hr[j].low;
        }
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| BuildStructureLevels (P1)                                        |
//|                                                                  |
//| Detecta pivotes y rangos en el TIMEFRAME DE ESTRUCTURA (p.ej.    |
//| H1) y los traduce a "indice de barra del grafico en el que el    |
//| nivel es CONOCIBLE", sin look-ahead:                             |
//|                                                                  |
//|  - Un pivote en la barra sp del TF de estructura se confirma al  |
//|    cierre de la barra sp+depth de ese TF. Su instante conocible  |
//|    es (time[sp+depth] + structSec).                              |
//|  - Un rango que termina en la barra sk se conoce al cierre de sk |
//|    es decir (time[sk] + structSec).                              |
//|                                                                  |
//| El indice del grafico asociado es la primera barra k cuyo cierre |
//| (time[k]+sigSec) es >= ese instante conocible. Asi una zona de   |
//| H1 solo influye en M15 cuando su barra H1 ya esta cerrada.       |
//+------------------------------------------------------------------+
bool CBIEngine::BuildStructureLevels(void)
  {
   const int sigSec   =PeriodSeconds(m_par.tfSignal);
   const int structSec=PeriodSeconds(m_par.tfStructure);
   if(sigSec<=0 || structSec<=0 || structSec<=sigSec)
     {
      m_lastError="TF de estructura debe ser superior al del grafico";
      return(false);
     }

   int need=(int)MathCeil((double)m_n*sigSec/structSec)+m_par.rangeMaxBars+m_par.pivotDepth+50;
   need=BI_ClampInt(need,64,20000);

   MqlRates sr[];
   ArraySetAsSeries(sr,false);
   const int nS=CopyRates(m_par.symbol,m_par.tfStructure,0,need,sr);
   if(nS<m_par.rangeMinBars+m_par.pivotDepth*2+5)
     {
      m_lastError="Datos del TF de estructura no disponibles todavia";
      return(false);
     }

   //--- Bug 1: ATR(14) REAL del TF de estructura (Wilder), no la anchura de una
   //    sola vela. Es causal: atrS[conf] solo depende de barras <= conf.
   double atrS[];
   BI_AtrArray(sr,nS,m_par.atrPeriod,atrS);

   //--- Bug 3: la capacidad se dimensiona segun el HISTORICO procesado, no con
   //    un tope fijo que descartaria los niveles mas recientes. Cada barra de
   //    estructura aporta como mucho 2 pivotes + 2 bordes de rango.
   const int cap=4*nS+64;
   ArrayResize(m_slPrice,cap);
   ArrayResize(m_slKind ,cap);
   ArrayResize(m_slKnownIdx,cap);
   ArrayResize(m_srHi,cap); ArrayResize(m_srLo,cap);
   ArrayResize(m_srKnown,cap); ArrayResize(m_srBars,cap);
   m_slCount=0; m_srCount=0;
   const double sigRatio=(double)structSec/(double)sigSec;

   //--- cursor de mapeo estructura -> grafico (ambos ascendentes en tiempo)
   int kc=0;
   double lastRHi=0.0,lastRLo=0.0;

   for(int sp=m_par.pivotDepth; sp<nS-m_par.pivotDepth; sp++)
     {
      const int conf=sp+m_par.pivotDepth;          // barra que confirma el pivote
      const datetime knownT=(datetime)(sr[conf].time+structSec);
      while(kc<m_n && (datetime)(m_rates[kc].time+sigSec)<knownT) kc++;
      if(kc>=m_n) break;                            // ya no hay barra de grafico
      const int kIdx=kc;

      //--- pivotes (n=conf+1 impide leer barras posteriores a conf)
      if(BI_IsPivotHigh(sr,conf+1,sp,m_par.pivotDepth) && m_slCount<cap)
        {
         m_slPrice[m_slCount]=sr[sp].high; m_slKind[m_slCount]=BI_LK_SWING;
         m_slKnownIdx[m_slCount]=kIdx; m_slCount++;
        }
      if(BI_IsPivotLow(sr,conf+1,sp,m_par.pivotDepth) && m_slCount<cap)
        {
         m_slPrice[m_slCount]=sr[sp].low; m_slKind[m_slCount]=BI_LK_SWING;
         m_slKnownIdx[m_slCount]=kIdx; m_slCount++;
        }

      //--- rango del TF de estructura terminado en la barra "conf"
      if(m_par.useRange && atrS[conf]>0.0)
        {
         double rhi=0.0,rlo=0.0; int rbars=0;
         if(BI_DetectRange(sr,conf+1,conf,m_par.rangeMinBars,m_par.rangeMaxBars,
                           atrS[conf],m_par.rangeMaxWidthATR,m_par.rangeTouchATR,
                           m_par.rangeMaxDrift,m_par.rangeMinTouchesSide,rhi,rlo,rbars))
           {
            const double tol=(rhi-rlo)*0.15+m_point;

            //--- Bug 2: se decide si el rango es NUEVO antes de tocar lastRHi/lastRLo
            const bool changedHi=(MathAbs(rhi-lastRHi)>tol);
            const bool changedLo=(MathAbs(rlo-lastRLo)>tol);
            const bool newRange =(changedHi || changedLo);

            if(changedHi && m_slCount<cap)
              { m_slPrice[m_slCount]=rhi; m_slKind[m_slCount]=BI_LK_RANGE;
                m_slKnownIdx[m_slCount]=kIdx; m_slCount++; }
            if(changedLo && m_slCount<cap)
              { m_slPrice[m_slCount]=rlo; m_slKind[m_slCount]=BI_LK_RANGE;
                m_slKnownIdx[m_slCount]=kIdx; m_slCount++; }

            //--- registro del rango para dibujar la caja (aprox. en barras M15)
            if(newRange && m_srCount<cap)
              {
               m_srHi[m_srCount]=rhi; m_srLo[m_srCount]=rlo;
               m_srKnown[m_srCount]=kIdx;
               m_srBars[m_srCount]=(int)MathRound(rbars*sigRatio);
               m_srCount++;
              }

            if(changedHi) lastRHi=rhi;   // se actualiza DESPUES de decidir
            if(changedLo) lastRLo=rlo;
           }
        }
     }

   ArrayResize(m_slPrice,m_slCount);
   ArrayResize(m_slKind ,m_slCount);
   ArrayResize(m_slKnownIdx,m_slCount);
   ArrayResize(m_srHi,m_srCount); ArrayResize(m_srLo,m_srCount);
   ArrayResize(m_srKnown,m_srCount); ArrayResize(m_srBars,m_srCount);
   //--- ya vienen ordenados por knownIdx (sp y conf crecen monotonamente)
   return(m_slCount>0);
  }

//+------------------------------------------------------------------+
//| Inyecta en la barra k los niveles de estructura conocibles en k  |
//+------------------------------------------------------------------+
void CBIEngine::InjectStructureLevels(const int k)
  {
   const double tol=ClusterTol(k);
   while(m_slCursor<m_slCount && m_slKnownIdx[m_slCursor]<=k)
     {
      const int idx=m_slCursor;
      //--- Bug 4: NO se fabrica antiguedad. Se usa el indice REAL en que la zona
      //    se hizo conocible (m_slKnownIdx[idx]) como firstIdx y knownIdx. El
      //    filtro de LevelEligible (k - firstIdx >= minLevelAgeBars) equivale
      //    asi a exigir knownIdx + minLevelAgeBars antes de operar el nivel,
      //    sin adelantar el firstIdx a un pasado inventado.
      const int knownIdx=m_slKnownIdx[idx];
      m_levels.AddOrMerge(m_slPrice[idx],m_slKind[idx],knownIdx,knownIdx,tol);
      m_slCursor++;
     }

   //--- rango vigente para la caja de dibujo (ultimo rango de estructura visto)
   while(m_srCursor<m_srCount && m_srKnown[m_srCursor]<=k)
     {
      m_rangeHi=m_srHi[m_srCursor];
      m_rangeLo=m_srLo[m_srCursor];
      m_rangeBars=m_srBars[m_srCursor];
      m_rangeIdx=k;
      m_srCursor++;
     }
  }


//+------------------------------------------------------------------+
//| Serie de volumen y su media movil                                |
//+------------------------------------------------------------------+
void CBIEngine::BuildVolume(void)
  {
   ArrayResize(m_vol,m_n);
   ArrayInitialize(m_vol,0.0);

   //--- decidimos si el simbolo entrega volumen real utilizable
   m_volUsable=false;
   const int from=BI_MaxInt(0,m_n-500);
   long realSum=0;
   for(int k=from;k<m_n;k++) realSum+=m_rates[k].real_volume;

   const bool useReal=(realSum>0);
   m_volIsTick=!useReal;
   long tickSum=0;
   for(int k=0;k<m_n;k++)
     {
      m_vol[k]=(double)(useReal ? m_rates[k].real_volume : m_rates[k].tick_volume);
      if(k>=from) tickSum+=(long)m_vol[k];
     }
   m_volUsable=(tickSum>0);

   BI_SmaArray(m_vol,m_n,m_par.volumeMAPeriod,m_volMA);
  }

//+------------------------------------------------------------------+
//| Reinicia el estado del recorrido                                 |
//+------------------------------------------------------------------+
void CBIEngine::ResetRun(void)
  {
   m_levels.Reset();
   m_setupCount=0; m_nextSetupId=1;
   ArrayResize(m_setups,0);
   m_eventCount=0;
   ArrayResize(m_events,0);
   m_signalCount=0;
   ArrayResize(m_signals,0);
   m_slCursor=0; m_srCursor=0;
   m_lastPdh=0.0; m_lastPdl=0.0; m_lastPwh=0.0; m_lastPwl=0.0;
   m_lastRangeHi=0.0; m_lastRangeLo=0.0;
   m_rangeHi=0.0; m_rangeLo=0.0; m_rangeBars=0; m_rangeIdx=-1;
   m_asiaOpen=false; m_asiaKey=-1; m_asiaHi=0.0; m_asiaLo=0.0;
  }

//+------------------------------------------------------------------+
//| Reconstruccion completa y determinista                           |
//+------------------------------------------------------------------+
bool CBIEngine::Rebuild(void)
  {
   if(!LoadData()) return(false);
   ResetRun();

   const int kEnd=m_n-2;                       // ultima barra CERRADA
   for(int k=m_warmup;k<=kEnd;k++)
      ProcessBar(k);

   m_lastError="";
   return(true);
  }

//+------------------------------------------------------------------+
//| Secuencia de trabajo de una barra cerrada                        |
//+------------------------------------------------------------------+
void CBIEngine::ProcessBar(const int k)
  {
   if(m_atr[k]<=0.0) return;

   m_levels.SetMaxZoneWidth(m_par.clusterATR*2.0*m_atr[k]);

   if(m_par.useStructTF)
      InjectStructureLevels(k);        // zonas del TF de estructura (P1)
   else
     {
      UpdatePivots(k);                 // zonas del propio grafico
      UpdateRangeLevels(k);
     }
   UpdateReferenceLevels(k);
   UpdateSetups(k);
   DetectBreakouts(k);
   DetectWatch(k);

   if((k%10)==0)
      m_levels.Prune(k,m_par.lookbackBars);
  }

//+------------------------------------------------------------------+
//| Incorporacion de pivotes confirmados                             |
//+------------------------------------------------------------------+
void CBIEngine::UpdatePivots(const int k)
  {
   const int p=k-m_par.pivotDepth;
   if(p<m_par.pivotDepth) return;

   const double tol=ClusterTol(k);
   //--- n=k+1 impide que la deteccion lea barras posteriores a k
   if(BI_IsPivotHigh(m_rates,k+1,p,m_par.pivotDepth))
      m_levels.AddOrMerge(m_rates[p].high,BI_LK_SWING,p,k,tol);
   if(BI_IsPivotLow(m_rates,k+1,p,m_par.pivotDepth))
      m_levels.AddOrMerge(m_rates[p].low,BI_LK_SWING,p,k,tol);
  }

//+------------------------------------------------------------------+
//| Niveles de referencia: dia previo, semana previa, sesion asiatica|
//+------------------------------------------------------------------+
void CBIEngine::UpdateReferenceLevels(const int k)
  {
   const double tol=ClusterTol(k);
   const int    known=BI_MaxInt(0,k-1);   // derivados de periodos ya cerrados

   if(m_par.usePrevDay)
     {
      if(m_pdh[k]>0.0 && MathAbs(m_pdh[k]-m_lastPdh)>tol*0.25)
        { m_levels.AddOrMerge(m_pdh[k],BI_LK_PDAY,k,known,tol); m_lastPdh=m_pdh[k]; }
      if(m_pdl[k]>0.0 && MathAbs(m_pdl[k]-m_lastPdl)>tol*0.25)
        { m_levels.AddOrMerge(m_pdl[k],BI_LK_PDAY,k,known,tol); m_lastPdl=m_pdl[k]; }
     }

   if(m_par.usePrevWeek)
     {
      if(m_pwh[k]>0.0 && MathAbs(m_pwh[k]-m_lastPwh)>tol*0.25)
        { m_levels.AddOrMerge(m_pwh[k],BI_LK_PWEEK,k,known,tol); m_lastPwh=m_pwh[k]; }
      if(m_pwl[k]>0.0 && MathAbs(m_pwl[k]-m_lastPwl)>tol*0.25)
        { m_levels.AddOrMerge(m_pwl[k],BI_LK_PWEEK,k,known,tol); m_lastPwl=m_pwl[k]; }
     }

   if(!m_par.useAsia) return;

   const int  h=BI_HourOf(m_rates[k].time);
   const bool inWin=BI_HourInWindow(h,m_par.asiaStartHour,m_par.asiaEndHour);
   const int  key=(int)(((long)m_rates[k].time-(long)m_par.asiaStartHour*3600)/86400);

   if(inWin)
     {
      if(!m_asiaOpen || key!=m_asiaKey)
        {
         m_asiaOpen=true; m_asiaKey=key;
         m_asiaHi=m_rates[k].high; m_asiaLo=m_rates[k].low;
        }
      else
        {
         if(m_rates[k].high>m_asiaHi) m_asiaHi=m_rates[k].high;
         if(m_rates[k].low <m_asiaLo) m_asiaLo=m_rates[k].low;
        }
     }
   else if(m_asiaOpen)
     {
      m_asiaOpen=false;
      if(m_asiaHi>m_asiaLo)
        {
         m_levels.AddOrMerge(m_asiaHi,BI_LK_ASIA,k,known,tol);
         m_levels.AddOrMerge(m_asiaLo,BI_LK_ASIA,k,known,tol);
        }
     }
  }

//+------------------------------------------------------------------+
//| Deteccion de rango y alta de sus bordes como niveles             |
//+------------------------------------------------------------------+
void CBIEngine::UpdateRangeLevels(const int k)
  {
   if(!m_par.useRange) return;

   double rhi=0.0,rlo=0.0;
   int    rbars=0;
   if(!BI_DetectRange(m_rates,k+1,k,m_par.rangeMinBars,m_par.rangeMaxBars,
                      m_atr[k],m_par.rangeMaxWidthATR,m_par.rangeTouchATR,
                      m_par.rangeMaxDrift,m_par.rangeMinTouchesSide,rhi,rlo,rbars))
      return;

   m_rangeHi=rhi; m_rangeLo=rlo; m_rangeBars=rbars; m_rangeIdx=k;

   const double tol=ClusterTol(k);
   if(MathAbs(rhi-m_lastRangeHi)>tol*0.5)
     { m_levels.AddOrMerge(rhi,BI_LK_RANGE,k,k,tol); m_lastRangeHi=rhi; }
   if(MathAbs(rlo-m_lastRangeLo)>tol*0.5)
     { m_levels.AddOrMerge(rlo,BI_LK_RANGE,k,k,tol); m_lastRangeLo=rlo; }
  }

//+------------------------------------------------------------------+
//| Margen minimo de ruptura en unidades de precio                   |
//+------------------------------------------------------------------+
double CBIEngine::BreakMargin(const int k) const
  {
   double m=m_par.breakMarginATR*m_atr[k];
   const double spr=(double)m_rates[k].spread*m_point;
   const double ms =m_par.breakMarginSpreads*spr;
   if(ms>m) m=ms;
   if(m<m_tickSize) m=m_tickSize;
   return(m);
  }

//+------------------------------------------------------------------+
//| Tolerancia de agrupacion de niveles                              |
//+------------------------------------------------------------------+
double CBIEngine::ClusterTol(const int k) const
  {
   double t=m_par.clusterATR*m_atr[k];
   if(t<m_tickSize) t=m_tickSize;
   return(t);
  }

//+------------------------------------------------------------------+
//| Estado de tendencia del timeframe de contexto en la barra k      |
//+------------------------------------------------------------------+
int CBIEngine::TrendState(const int k) const
  {
   if(k<0 || k>=m_n)        return(BI_TREND_UNKNOWN);
   if(m_ctxEma[k]<=0.0)     return(BI_TREND_UNKNOWN);
   if(m_ctxClose[k]>m_ctxEma[k]) return(BI_TREND_UP);
   if(m_ctxClose[k]<m_ctxEma[k]) return(BI_TREND_DOWN);
   return(BI_TREND_UNKNOWN);
  }


//+------------------------------------------------------------------+
//| Filtros duros: si estan activados como "hard", vetan la senal    |
//+------------------------------------------------------------------+
bool CBIEngine::HardFiltersPass(const int k,const int dir) const
  {
   if(m_par.useEmaFilter && m_par.emaHardFilter)
     {
      const int t=TrendState(k);
      if(t==BI_TREND_UNKNOWN || t!=dir) return(false);
     }
   if(m_par.useAtrFilter && m_par.atrHardFilter)
     {
      const double r=AtrRatio(k);
      if(r<=0.0 || r<m_par.atrMinRatio || r>m_par.atrMaxRatio) return(false);
     }
   if(m_par.useRsi && m_par.rsiHardFilter)
     {
      const double v=m_rsi[k];
      if(v<=0.0) return(false);
      if(dir>0 && v<m_par.rsiBullMin) return(false);
      if(dir<0 && v>m_par.rsiBearMax) return(false);
     }
   if(m_par.sessionFilter!=BI_SESS_OFF && m_par.sessionHardFilter)
     {
      if(!InSession(k)) return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Un nivel es candidato a ser roto en la barra k                   |
//+------------------------------------------------------------------+
bool CBIEngine::LevelEligible(const int li,const int k)
  {
   if(li<0 || li>=m_levels.Count)              return(false);
   if(!m_levels.Items[li].active)              return(false);
   if(m_levels.Items[li].brokenDir!=0)         return(false);
   if(k<=m_levels.Items[li].knownIdx)          return(false);
   if(k-m_levels.Items[li].lastIdx>m_par.lookbackBars) return(false);

   const int kind=m_levels.Items[li].kind;
   if(kind==BI_LK_SWING || kind==BI_LK_RANGE)
     {
      if(k-m_levels.Items[li].firstIdx<m_par.minLevelAgeBars) return(false);
      if(kind==BI_LK_SWING && m_levels.Items[li].touches<m_par.minTouches) return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Numero de setups todavia vivos                                   |
//+------------------------------------------------------------------+
int CBIEngine::LiveSetupCount(void) const
  {
   int c=0;
   for(int i=0;i<m_setupCount;i++)
      if(m_setups[i].state==BI_ST_BREAKOUT || m_setups[i].state==BI_ST_RETEST) c++;
   return(c);
  }

//+------------------------------------------------------------------+
//| Existe ya un setup vivo sobre ese nivel y direccion              |
//+------------------------------------------------------------------+
bool CBIEngine::HasLiveSetup(const int levelId,const int dir) const
  {
   for(int i=0;i<m_setupCount;i++)
     {
      if(m_setups[i].levelId!=levelId) continue;
      if(m_setups[i].dir!=dir)         continue;
      if(m_setups[i].state==BI_ST_BREAKOUT || m_setups[i].state==BI_ST_RETEST)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| DETECCION DE RUPTURA                                             |
//|                                                                  |
//| Condiciones, todas sobre la barra CERRADA k:                     |
//|   C1  cierre mas alla del borde de la zona por al menos          |
//|       margin = max(breakMarginATR*ATR, breakMarginSpreads*spread,|
//|                    tickSize)                                     |
//|   C2  cuerpo direccional >= minBodyRatio del recorrido total     |
//|   C3  cierre situado en el minCloseLoc final de la vela          |
//|       (evita que una mecha se cuente como ruptura)               |
//|   C4  desplazamiento: recorrido >= minBarRangeATR*ATR            |
//|       o exceso sobre el nivel >= 1.5*margin                      |
//|   C5  las preBreakBars anteriores cerraron del lado contrario    |
//|   C6  el precio venia de las inmediaciones del nivel             |
//|       (distancia <= approachMaxATR*ATR)                          |
//|   C7  filtros duros activos                                      |
//+------------------------------------------------------------------+
void CBIEngine::DetectBreakouts(const int k)
  {
   if(LiveSetupCount()>=m_par.maxActiveSetups) return;

   const double atr=m_atr[k];
   const double margin=BreakMargin(k);
   const double rng=m_rates[k].high-m_rates[k].low;
   if(rng<=0.0) return;

   const double body=m_rates[k].close-m_rates[k].open;

   for(int di=0;di<2;di++)
     {
      //--- Bug 5: el limite se reevalua ANTES de cada direccion. Sin esto,
      //    tras crear un setup BUY en esta vela la rama SELL podria crear otro
      //    y superar maxActiveSetups en una sola barra.
      if(LiveSetupCount()>=m_par.maxActiveSetups) break;

      const int dir=(di==0 ? BI_DIR_UP : BI_DIR_DOWN);

      //--- C2 y C3: calidad de la vela de ruptura
      const double dirBody=(double)dir*body;
      if(dirBody<=0.0)                      continue;
      if(dirBody/rng<m_par.minBodyRatio)    continue;
      const double loc=(dir>0 ? (m_rates[k].close-m_rates[k].low)/rng
                              : (m_rates[k].high-m_rates[k].close)/rng);
      if(loc<m_par.minCloseLoc)             continue;

      //--- C7
      if(!HardFiltersPass(k,dir))           continue;

      int bestLi=-1, bestScore=-1;
      for(int i=0;i<m_levels.Count;i++)
        {
         if(!LevelEligible(i,k)) continue;

         const double edge=(dir>0 ? m_levels.Items[i].hi : m_levels.Items[i].lo);
         const double excess=(double)dir*(m_rates[k].close-edge);
         if(excess<=margin) continue;                                   // C1

         if(rng<m_par.minBarRangeATR*atr && excess<1.5*margin) continue; // C4

         bool cameFromInside=true;                                      // C5
         for(int q=1;q<=m_par.preBreakBars;q++)
           {
            const int idx=k-q;
            if(idx<0) { cameFromInside=false; break; }
            if((double)dir*(m_rates[idx].close-edge)>0.0) { cameFromInside=false; break; }
           }
         if(!cameFromInside) continue;

         if((double)dir*(edge-m_rates[k-1].close)>m_par.approachMaxATR*atr) continue; // C6

         if(HasLiveSetup(m_levels.Items[i].id,dir)) continue;

         const int sc=BI_LevelScore(m_levels.Items[i].kind,m_levels.Items[i].touches);
         if(sc>bestScore) { bestScore=sc; bestLi=i; }
        }

      if(bestLi>=0) NewSetup(bestLi,k,dir);
     }
  }

//+------------------------------------------------------------------+
//| Alta de un setup en estado RUPTURA                               |
//+------------------------------------------------------------------+
int CBIEngine::NewSetup(const int li,const int k,const int dir)
  {
   if(m_setupCount>=BI_MAX_SETUPS)
     {
      int drop=-1;
      for(int i=0;i<m_setupCount;i++)
         if(m_setups[i].state==BI_ST_CONFIRMED ||
            m_setups[i].state==BI_ST_INVALIDATED ||
            m_setups[i].state==BI_ST_EXPIRED) { drop=i; break; }
      if(drop<0) return(-1);
      for(int i=drop;i<m_setupCount-1;i++) m_setups[i]=m_setups[i+1];
      m_setupCount--;
      ArrayResize(m_setups,m_setupCount);
     }

   if(ArrayResize(m_setups,m_setupCount+1)!=m_setupCount+1) return(-1);

   const double edge=(dir>0 ? m_levels.Items[li].hi : m_levels.Items[li].lo);
   const double margin=BreakMargin(k);

   SBISetup s;
   s.id            = m_nextSetupId++;
   s.levelId       = m_levels.Items[li].id;
   s.levelKind     = m_levels.Items[li].kind;
   s.levelEdge     = edge;
   s.levelHi       = m_levels.Items[li].hi;
   s.levelLo       = m_levels.Items[li].lo;
   s.dir           = dir;
   s.state         = BI_ST_BREAKOUT;
   s.breakIdx      = k;
   s.retestIdx     = -1;
   s.retestDeepIdx = -1;
   s.retestExtreme = 0.0;
   s.confirmIdx    = -1;
   s.endIdx        = -1;
   s.confirmKind   = BI_CONF_NONE;
   s.touchedZone   = false;
   s.retestReal    = false;
   s.breakClose    = m_rates[k].close;
   s.breakMargin   = margin;
   s.atrAtBreak    = m_atr[k];
   s.slPrice       = 0.0;
   s.tpPrice       = 0.0;
   s.slValid       = false;
   s.scLevel       = ScoreLevelComp(m_levels.Items[li]);
   s.scClose       = ScoreCloseComp(k,edge,margin,dir);
   s.scTrend       = ScoreTrendComp(k,dir);
   s.scVola        = ScoreVolaComp(k);
   s.scSession     = ScoreSessionComp(k);
   s.scVolume      = ScoreVolumeComp(k);
   s.scRetest      = 0;
   s.scConfirm     = 0;
   s.scoreMax      = 0;
   s.score         = 0;
   RecalcScore(s);

   m_setups[m_setupCount]=s;
   m_setupCount++;

   m_levels.Items[li].brokenDir=dir;
   m_levels.Items[li].brokenIdx=k;

   PushEvent(BI_EV_BREAKOUT,s,k);
   return(m_setupCount-1);
  }

//+------------------------------------------------------------------+
//| Cierre de un setup (invalidacion o caducidad)                    |
//+------------------------------------------------------------------+
void CBIEngine::CloseSetup(const int si,const int k,const int state)
  {
   m_setups[si].state=state;
   m_setups[si].endIdx=k;

   if(state==BI_ST_INVALIDATED)
     {
      const int li=m_levels.IndexOfId(m_setups[si].levelId);
      if(li>=0)
        {
         //--- el nivel ha aguantado: vuelve a estar operativo y gana relevancia
         m_levels.Items[li].brokenDir=0;
         m_levels.Items[li].brokenIdx=-1;
         m_levels.Items[li].touches++;
         m_levels.Items[li].lastIdx=k;
        }
     }

   PushEvent(state==BI_ST_INVALIDATED ? BI_EV_INVALIDATED : BI_EV_EXPIRED,
             m_setups[si],k);
  }

//+------------------------------------------------------------------+
//| ACTUALIZACION DE SETUPS VIVOS                                    |
//|                                                                  |
//|  RUPTURA  -> INVALIDADO  si close vuelve a cruzar el borde por   |
//|                          mas de reentryATR*ATR                   |
//|           -> RETESTEO    si el extremo de la vela regresa a la   |
//|                          zona (dentro de retestTolATR*ATR)       |
//|           -> CADUCADO    si pasan retestMaxBars sin retesteo     |
//|  RETESTEO -> INVALIDADO  igual criterio de cierre                |
//|           -> CONFIRMADO  si aparece patron de confirmacion       |
//|           -> CADUCADO    si pasan confirmMaxBars sin confirmar   |
//+------------------------------------------------------------------+
void CBIEngine::UpdateSetups(const int k)
  {
   const double atr=m_atr[k];
   const double reentry=m_par.reentryATR*atr;
   const double tol=m_par.retestTolATR*atr;

   for(int i=0;i<m_setupCount;i++)
     {
      if(m_setups[i].state!=BI_ST_BREAKOUT && m_setups[i].state!=BI_ST_RETEST) continue;
      if(m_setups[i].breakIdx>=k) continue;

      const int    dir =m_setups[i].dir;
      const double edge=m_setups[i].levelEdge;
      const double ext =(dir>0 ? m_rates[k].low : m_rates[k].high);

      //--- invalidacion por cierre de vuelta dentro del rango
      if((double)dir*(m_rates[k].close-edge)<-reentry)
        {
         CloseSetup(i,k,BI_ST_INVALIDATED);
         continue;
        }

      if(m_setups[i].state==BI_ST_BREAKOUT)
        {
         if((double)dir*(ext-edge)<=tol)
           {
            m_setups[i].state        =BI_ST_RETEST;
            m_setups[i].retestIdx    =k;
            m_setups[i].retestDeepIdx=k;
            m_setups[i].retestExtreme=ext;
            m_setups[i].retestReal   =true;
            m_setups[i].touchedZone  =((double)dir*(ext-edge)<=0.0);
            PushEvent(BI_EV_RETEST,m_setups[i],k);
            continue;
           }

         //--- confirmacion directa por continuacion cuando no se exige retesteo
         if(!m_par.requireRetest)
           {
            SBISetup tmp=m_setups[i];
            tmp.retestIdx    =tmp.breakIdx;
            tmp.retestDeepIdx=tmp.breakIdx;
            tmp.retestExtreme=(dir>0 ? m_rates[tmp.breakIdx].low : m_rates[tmp.breakIdx].high);
            int ckDirect=BI_CONF_NONE;
            if(IsConfirmation(k,tmp,ckDirect))
              {
               m_setups[i].state      =BI_ST_CONFIRMED;
               m_setups[i].confirmIdx =k;
               m_setups[i].confirmKind=ckDirect;
               m_setups[i].endIdx     =k;
               ComputeStops(m_setups[i],k);
               RecalcScore(m_setups[i]);
               PushEvent(BI_EV_ENTRY,m_setups[i],k);
               continue;
              }
           }

         if(k-m_setups[i].breakIdx>=m_par.retestMaxBars)
            CloseSetup(i,k,BI_ST_EXPIRED);
         continue;
        }

      //--- estado RETESTEO
      if((double)dir*(ext-m_setups[i].retestExtreme)<0.0)
        {
         m_setups[i].retestExtreme=ext;
         m_setups[i].retestDeepIdx=k;
        }
      if(!m_setups[i].touchedZone && (double)dir*(ext-edge)<=0.0)
         m_setups[i].touchedZone=true;

      //--- P2: con requireRetest, el precio DEBE haber penetrado la zona
      //    (touchedZone). Una simple aproximacion no puede confirmar.
      const bool touchOk=(!m_par.requireRetest || m_setups[i].touchedZone);

      int ck=BI_CONF_NONE;
      if(touchOk && k>m_setups[i].retestIdx && IsConfirmation(k,m_setups[i],ck))
        {
         m_setups[i].state      =BI_ST_CONFIRMED;
         m_setups[i].confirmIdx =k;
         m_setups[i].confirmKind=ck;
         m_setups[i].endIdx     =k;
         ComputeStops(m_setups[i],k);
         RecalcScore(m_setups[i]);
         PushEvent(BI_EV_ENTRY,m_setups[i],k);
         continue;
        }

      if(k-m_setups[i].retestIdx>=m_par.confirmMaxBars)
         CloseSetup(i,k,BI_ST_EXPIRED);
     }
  }

//+------------------------------------------------------------------+
//| PATRONES DE CONFIRMACION (basta uno)                             |
//|  1 Continuacion : cierre mas alla del extremo del tramo de       |
//|                   retesteo y a >= margin del nivel               |
//|  2 Envolvente   : cuerpo direccional que envuelve el de la vela  |
//|                   anterior, de signo contrario                   |
//|  3 Rechazo      : mecha del lado del nivel >= pinWickRatio del   |
//|                   recorrido y cierre en el 40% favorable. NO se  |
//|                   exige color de cuerpo: un martillo con cuerpo  |
//|                   ligeramente contrario pero mecha inferior      |
//|                   dominante es un rechazo alcista valido.        |
//|  4 Estructura   : extremo del retesteo mejor que el de la vela   |
//|                   de ruptura y cierre superando su extremo       |
//| En todos los casos el cierre debe seguir del lado roto.          |
//+------------------------------------------------------------------+
bool CBIEngine::IsConfirmation(const int k,const SBISetup &s,int &confirmKind) const
  {
   confirmKind=BI_CONF_NONE;
   if(k<1 || k>=m_n) return(false);

   const int    dir =s.dir;
   const double edge=s.levelEdge;
   const double rng =m_rates[k].high-m_rates[k].low;
   if(rng<=0.0) return(false);
   if((double)dir*(m_rates[k].close-edge)<=0.0) return(false);

   const double margin  =BreakMargin(k);
   const double dirBody =(double)dir*(m_rates[k].close-m_rates[k].open);
   const double body    =MathAbs(m_rates[k].close-m_rates[k].open);
   const double prevBody=MathAbs(m_rates[k-1].close-m_rates[k-1].open);

   //--- 1) cierre de continuacion
   const int from=(s.retestIdx>=0 ? s.retestIdx : s.breakIdx);
   double ref=(dir>0 ? m_rates[from].high : m_rates[from].low);
   for(int q=from;q<k;q++)
     {
      if(dir>0) { if(m_rates[q].high>ref) ref=m_rates[q].high; }
      else      { if(m_rates[q].low <ref) ref=m_rates[q].low;  }
     }
   if(dirBody>0.0 && (double)dir*(m_rates[k].close-ref)>0.0 &&
      (double)dir*(m_rates[k].close-edge)>=margin)
     { confirmKind=BI_CONF_CONTINUATION; return(true); }

   //--- 2) vela envolvente
   if(dirBody>0.0 &&
      (double)dir*(m_rates[k-1].close-m_rates[k-1].open)<0.0 &&
      (double)dir*(m_rates[k].close-m_rates[k-1].open)>=0.0 &&
      (double)dir*(m_rates[k].open -m_rates[k-1].close)<=0.0 &&
      body>prevBody)
     { confirmKind=BI_CONF_ENGULFING; return(true); }

   //--- 3) rechazo / pin bar (P7): mecha del lado del nivel + cierre
   //    en el 40% favorable. El cierre ya esta del lado roto (garantizado
   //    arriba). loc>=0.60 acota el cuerpo: aunque sea ligeramente
   //    contrario, el cierre queda en la parte favorable de la vela.
   const double wick=(dir>0 ? MathMin(m_rates[k].open,m_rates[k].close)-m_rates[k].low
                            : m_rates[k].high-MathMax(m_rates[k].open,m_rates[k].close));
   const double loc =(dir>0 ? (m_rates[k].close-m_rates[k].low)/rng
                            : (m_rates[k].high-m_rates[k].close)/rng);
   if(wick>=m_par.pinWickRatio*rng && loc>=0.60)
     { confirmKind=BI_CONF_REJECTION; return(true); }

   //--- 4) estructura
   if(s.retestIdx>=0)
     {
      const double brkExt =(dir>0 ? m_rates[s.breakIdx].low  : m_rates[s.breakIdx].high);
      const double brkEdge=(dir>0 ? m_rates[s.breakIdx].high : m_rates[s.breakIdx].low);
      if((double)dir*(s.retestExtreme-brkExt)>0.0 &&
         (double)dir*(m_rates[k].close-brkEdge)>0.0)
        { confirmKind=BI_CONF_STRUCTURE; return(true); }
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| SL / TP orientativos (estructura + colchon de ATR)               |
//+------------------------------------------------------------------+
void CBIEngine::ComputeStops(SBISetup &s,const int k)
  {
   const int    dir=s.dir;
   const double atr=m_atr[k];

   s.slPrice=0.0; s.tpPrice=0.0; s.slValid=false;

   //--- SL detras del extremo estructural del tramo, con colchon de ATR
   const int from=(s.retestIdx>=0 ? BI_MinInt(s.retestIdx,s.breakIdx) : s.breakIdx);
   double ext=(dir>0 ? m_rates[from].low : m_rates[from].high);
   for(int q=from;q<=k;q++)
     {
      if(dir>0) { if(m_rates[q].low <ext) ext=m_rates[q].low;  }
      else      { if(m_rates[q].high>ext) ext=m_rates[q].high; }
     }
   if(dir>0) { if(s.levelLo<ext) ext=s.levelLo; }
   else      { if(s.levelHi>ext) ext=s.levelHi; }

   double sl=ext-(double)dir*m_par.slAtrMult*atr;
   const double entry=m_rates[k].close;

   //--- redondeo al tick real del simbolo (no solo a los digitos)
   sl=MathRound(sl/m_tickSize)*m_tickSize;
   double risk=(double)dir*(entry-sl);

   //--- distancia minima exigible: tick, colchon de ATR y stops level del broker
   const double stopsLvl=(double)SymbolInfoInteger(m_par.symbol,SYMBOL_TRADE_STOPS_LEVEL)*m_point;
   double minDist=MathMax(m_tickSize,atr*0.10);
   if(stopsLvl>minDist) minDist=stopsLvl;

   //--- P8: validaciones. Si algo no cuadra, no se presenta SL/TP.
   if(risk<=0.0)          return;   // SL en el lado equivocado o sobre la entrada
   if(risk<minDist)       return;   // absurdamente cercano
   if((double)dir*(entry-sl)<=0.0) return;

   double tp=entry+(double)dir*m_par.rrTarget*risk;
   tp=MathRound(tp/m_tickSize)*m_tickSize;
   if((double)dir*(tp-entry)<=0.0) return;   // TP en direccion incorrecta

   s.slPrice=NormalizeDouble(sl,m_digits);
   s.tpPrice=NormalizeDouble(tp,m_digits);
   s.slValid=true;
  }

//+------------------------------------------------------------------+
//| COMPONENTES DE PUNTUACION                                        |
//+------------------------------------------------------------------+
int CBIEngine::ScoreLevelComp(const SBILevel &lv) const
  {
   return(BI_LevelScore(lv.kind,lv.touches));
  }

int CBIEngine::ScoreCloseComp(const int k,const double edge,const double margin,const int dir) const
  {
   const double rng=m_rates[k].high-m_rates[k].low;
   const double excess=(double)dir*(m_rates[k].close-edge);
   int pts=0;
   if(excess>=margin)     pts+=6;
   if(excess>=2.0*margin) pts+=3;
   if(rng>0.0)
     {
      const double br =MathAbs(m_rates[k].close-m_rates[k].open)/rng;
      const double loc=(dir>0 ? (m_rates[k].close-m_rates[k].low)/rng
                              : (m_rates[k].high-m_rates[k].close)/rng);
      if(br>=0.60)  pts+=3;
      if(loc>=0.75) pts+=3;
     }
   return(BI_ClampInt(pts,0,15));
  }

int CBIEngine::ScoreTrendComp(const int k,const int dir) const
  {
   const int t=TrendState(k);
   if(t==BI_TREND_UNKNOWN) return(5);
   if(t!=dir)              return(0);
   const bool slope=(dir>0 ? m_ctxEma[k]>m_ctxEmaPrev[k] : m_ctxEma[k]<m_ctxEmaPrev[k]);
   return(slope ? 15 : 10);
  }

int CBIEngine::ScoreVolaComp(const int k) const
  {
   const double r=AtrRatio(k);
   if(r<=0.0) return(3);
   if(r>=m_par.atrMinRatio && r<=m_par.atrMaxRatio) return(10);
   if(r>=m_par.atrMinRatio*0.8 && r<=m_par.atrMaxRatio*1.2) return(5);
   return(0);
  }

int CBIEngine::ScoreSessionComp(const int k) const
  {
   return(InSession(k) ? 5 : 0);
  }

int CBIEngine::ScoreVolumeComp(const int k) const
  {
   if(m_volMA[k]<=0.0) return(0);
   const double r=m_vol[k]/m_volMA[k];
   if(r>=m_par.volumeMult) return(5);
   if(r>=1.0)              return(3);
   return(0);
  }

int CBIEngine::ScoreRetestComp(const SBISetup &s) const
  {
   return(s.touchedZone ? 20 : 14);
  }

int CBIEngine::ScoreConfirmComp(const int confirmKind) const
  {
   switch(confirmKind)
     {
      case BI_CONF_CONTINUATION: return(10);
      case BI_CONF_ENGULFING:    return(10);
      case BI_CONF_REJECTION:    return(8);
      case BI_CONF_STRUCTURE:    return(7);
     }
   return(0);
  }

//+------------------------------------------------------------------+
//| Puntuacion NORMALIZADA sobre las condiciones realmente evaluadas |
//| (P4). NO es una probabilidad.                                    |
//|                                                                  |
//| Cada componente aporta al numerador (puntos ganados) y al        |
//| denominador (puntos maximos) SOLO si esta activo:                |
//|   - nivel y cierre: siempre (nucleo estructural);                |
//|   - EMA, ATR, sesion, volumen: solo si su filtro esta activo y   |
//|     el dato es utilizable (asi la sesion OFF ya no da 5/5);      |
//|   - retesteo: solo si hubo un retesteo genuino;                  |
//|   - confirmacion: solo una vez confirmado el setup.              |
//| score = redondeo(100 * ganados / maximos). Con todos los filtros |
//| activos y setup confirmado, el maximo es 100 (compatibilidad).   |
//+------------------------------------------------------------------+
void CBIEngine::RecalcScore(SBISetup &s) const
  {
   int earned=0, mx=0;

   earned+=s.scLevel; mx+=20;                     // nivel   (nucleo)
   earned+=s.scClose; mx+=15;                     // cierre  (nucleo)

   if(m_par.useEmaFilter)                    { earned+=s.scTrend;   mx+=15; }
   if(m_par.useAtrFilter)                    { earned+=s.scVola;    mx+=10; }
   if(m_par.sessionFilter!=BI_SESS_OFF)      { earned+=s.scSession; mx+=5;  }
   if(m_par.useVolume && m_volUsable)        { earned+=s.scVolume;  mx+=5;  }

   if(s.retestReal)
     { s.scRetest=ScoreRetestComp(s); earned+=s.scRetest; mx+=20; }
   else
      s.scRetest=0;

   if(s.state==BI_ST_CONFIRMED)
     { s.scConfirm=ScoreConfirmComp(s.confirmKind); earned+=s.scConfirm; mx+=10; }
   else
      s.scConfirm=0;

   s.scoreMax=mx;
   s.score=(mx>0 ? BI_ClampInt((int)MathRound(100.0*earned/mx),0,100) : 0);
  }

//+------------------------------------------------------------------+
//| Cola circular de eventos                                         |
//+------------------------------------------------------------------+
void CBIEngine::AppendEvent(const SBIEvent &e)
  {
   if(m_eventCount>=BI_MAX_EVENTS)
     {
      const int drop=BI_MAX_EVENTS/4;
      for(int i=0;i<m_eventCount-drop;i++) m_events[i]=m_events[i+drop];
      m_eventCount-=drop;
      ArrayResize(m_events,m_eventCount);
     }
   if(ArrayResize(m_events,m_eventCount+1)!=m_eventCount+1) return;
   m_events[m_eventCount]=e;
   m_eventCount++;
  }

void CBIEngine::PushEvent(const int type,const SBISetup &s,const int k)
  {
   SBIEvent e;
   e.type       =type;
   e.dir        =s.dir;
   e.barIdx     =k;
   e.barTime    =m_rates[k].time;
   e.price      =m_rates[k].close;
   e.level      =s.levelEdge;
   e.sl         =s.slPrice;
   e.tp         =s.tpPrice;
   e.score      =s.score;
   e.setupId    =s.id;
   e.levelKind  =s.levelKind;
   e.confirmKind=s.confirmKind;
   e.state      =s.state;
   AppendEvent(e);

   //--- P3: registro historico persistente (independiente del cap de setups)
   if(type==BI_EV_BREAKOUT || type==BI_EV_RETEST || type==BI_EV_ENTRY)
      AppendSignal(type,s,k);
  }

//+------------------------------------------------------------------+
//| Historico de senales (P3). No se recicla con los setups vivos:   |
//| conserva toda la secuencia BREAKOUT/RETEST/ENTRY de la ventana   |
//| procesada para poder dibujarla y estudiarla.                     |
//+------------------------------------------------------------------+
void CBIEngine::AppendSignal(const int type,const SBISetup &s,const int k)
  {
   //--- cota de seguridad: no puede haber mas senales que barras
   if(m_signalCount>=m_n) return;
   if(ArrayResize(m_signals,m_signalCount+1)!=m_signalCount+1) return;

   SBISignal g;
   g.type       =type;
   g.dir        =s.dir;
   g.barIdx     =k;
   g.barTime    =m_rates[k].time;
   g.level      =s.levelEdge;
   g.sl         =s.slPrice;
   g.tp         =s.tpPrice;
   g.slValid    =s.slValid;
   g.score      =s.score;
   g.confirmKind=s.confirmKind;
   g.setupId    =s.id;
   m_signals[m_signalCount]=g;
   m_signalCount++;
  }

void CBIEngine::PushLevelEvent(const int type,const int k,const int dir,
                               const double level,const int levelKind)
  {
   SBIEvent e;
   e.type       =type;
   e.dir        =dir;
   e.barIdx     =k;
   e.barTime    =m_rates[k].time;
   e.price      =m_rates[k].close;
   e.level      =level;
   e.sl         =0.0;
   e.tp         =0.0;
   e.score      =0;
   e.setupId    =-1;
   e.levelKind  =levelKind;
   e.confirmKind=BI_CONF_NONE;
   e.state      =BI_ST_NONE;
   AppendEvent(e);
  }

//+------------------------------------------------------------------+
//| Aviso de aproximacion a un nivel vigente (NIVEL 1 - WATCH)       |
//+------------------------------------------------------------------+
void CBIEngine::DetectWatch(const int k)
  {
   const double dist=m_par.watchDistATR*m_atr[k];
   const double c=m_rates[k].close;
   int fired=0;

   for(int i=0;i<m_levels.Count && fired<2;i++)
     {
      if(!LevelEligible(i,k)) continue;
      if(k-m_levels.Items[i].lastWatchIdx<m_par.watchCooldown) continue;

      int dir=BI_DIR_NONE;
      if(c<m_levels.Items[i].hi && (m_levels.Items[i].hi-c)<=dist)      dir=BI_DIR_UP;
      else if(c>m_levels.Items[i].lo && (c-m_levels.Items[i].lo)<=dist) dir=BI_DIR_DOWN;
      if(dir==BI_DIR_NONE) continue;

      m_levels.Items[i].lastWatchIdx=k;
      PushLevelEvent(BI_EV_WATCH,k,dir,
                     (dir>0 ? m_levels.Items[i].hi : m_levels.Items[i].lo),
                     m_levels.Items[i].kind);
      fired++;
     }
  }

//+------------------------------------------------------------------+
//| Rango vigente y ultimo setup vivo                                |
//+------------------------------------------------------------------+
bool CBIEngine::CurrentRange(double &hi,double &lo,int &bars,int &idx) const
  {
   hi=m_rangeHi; lo=m_rangeLo; bars=m_rangeBars; idx=m_rangeIdx;
   if(m_rangeIdx<0 || m_rangeHi<=m_rangeLo) return(false);
   //--- en modo estructura un rango H1 permanece vigente mas de una vela M15;
   //    en modo grafico solo si se detecto en la ultima vela cerrada.
   const int maxAge=(m_par.useStructTF ? m_par.lookbackBars : 1);
   return((m_n-2-m_rangeIdx)<=maxAge);
  }

int CBIEngine::LastActiveSetup(void) const
  {
   for(int i=m_setupCount-1;i>=0;i--)
      if(m_setups[i].state==BI_ST_BREAKOUT || m_setups[i].state==BI_ST_RETEST)
         return(i);
   return(-1);
  }

#endif // __BI_ENGINE_MQH__
