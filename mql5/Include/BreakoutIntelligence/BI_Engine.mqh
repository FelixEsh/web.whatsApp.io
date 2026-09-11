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

#include <BreakoutIntelligence/BI_Types.mqh>
#include <BreakoutIntelligence/BI_Utils.mqh>
#include <BreakoutIntelligence/BI_Profile.mqh>
#include <BreakoutIntelligence/BI_Levels.mqh>

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

   SBISetup          m_setups[];
   int               m_setupCount;
   int               m_nextSetupId;

   SBIEvent          m_events[];
   int               m_eventCount;

   //--- estado incremental del recorrido
   double            m_lastPdh,m_lastPdl,m_lastPwh,m_lastPwl;
   double            m_lastRangeHi,m_lastRangeLo;
   double            m_rangeHi,m_rangeLo;
   int               m_rangeBars,m_rangeIdx;
   bool              m_asiaOpen;
   int               m_asiaKey;
   double            m_asiaHi,m_asiaLo;
   int               m_sessStart,m_sessEnd;
   string            m_lastError;

public:
                     CBIEngine(void);
                    ~CBIEngine(void);

   bool              Init(const SBIParams &p,const int sessionShiftHours);
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
   int               TrendState(const int k) const;

   int               SetupCount(void) const { return(m_setupCount); }
   SBISetup          SetupAt(const int i) const { return(m_setups[i]); }
   int               LevelCount(void) { return(m_levels.Count); }
   SBILevel          LevelAt(const int i) { return(m_levels.Items[i]); }
   int               EventCount(void) const { return(m_eventCount); }
   SBIEvent          EventAt(const int i) const { return(m_events[i]); }
   bool              CurrentRange(double &hi,double &lo,int &bars,int &idx) const;
   int               LastActiveSetup(void) const;
   int               SessionStart(void) const { return(m_sessStart); }
   int               SessionEnd(void)   const { return(m_sessEnd); }

private:
   bool              LoadData(void);
   bool              AlignContext(void);
   bool              AlignReference(const ENUM_TIMEFRAMES tf,double &outHi[],double &outLo[]);
   void              BuildVolume(void);
   void              ResetRun(void);

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
   m_volUsable=false;
   m_setupCount=0; m_nextSetupId=1; m_eventCount=0;
   m_lastPdh=0.0; m_lastPdl=0.0; m_lastPwh=0.0; m_lastPwl=0.0;
   m_lastRangeHi=0.0; m_lastRangeLo=0.0;
   m_rangeHi=0.0; m_rangeLo=0.0; m_rangeBars=0; m_rangeIdx=-1;
   m_asiaOpen=false; m_asiaKey=-1; m_asiaHi=0.0; m_asiaLo=0.0;
   m_sessStart=0; m_sessEnd=0;
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
bool CBIEngine::Init(const SBIParams &p,const int sessionShiftHours)
  {
   Deinit();
   m_par=p;

   m_digits  =(int)SymbolInfoInteger(m_par.symbol,SYMBOL_DIGITS);
   m_point   =SymbolInfoDouble(m_par.symbol,SYMBOL_POINT);
   m_tickSize=SymbolInfoDouble(m_par.symbol,SYMBOL_TRADE_TICK_SIZE);
   if(m_point<=0.0)    m_point=MathPow(10.0,-m_digits);
   if(m_tickSize<=0.0) m_tickSize=m_point;

   BI_ResolveSessionHours(m_par.sessionFilter,m_par.sessStartHour,m_par.sessEndHour,
                          sessionShiftHours,m_sessStart,m_sessEnd);

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

   UpdatePivots(k);
   UpdateReferenceLevels(k);
   UpdateRangeLevels(k);
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
      if(!BI_InSession(m_rates[k].time,m_par.sessionFilter,m_sessStart,m_sessEnd))
         return(false);
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
   s.breakClose    = m_rates[k].close;
   s.breakMargin   = margin;
   s.atrAtBreak    = m_atr[k];
   s.slPrice       = 0.0;
   s.tpPrice       = 0.0;
   s.scLevel       = ScoreLevelComp(m_levels.Items[li]);
   s.scClose       = ScoreCloseComp(k,edge,margin,dir);
   s.scTrend       = ScoreTrendComp(k,dir);
   s.scVola        = ScoreVolaComp(k);
   s.scSession     = ScoreSessionComp(k);
   s.scVolume      = ScoreVolumeComp(k);
   s.scRetest      = 0;
   s.scConfirm     = 0;
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

      int ck=BI_CONF_NONE;
      if(k>m_setups[i].retestIdx && IsConfirmation(k,m_setups[i],ck))
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
//|                   recorrido y cierre en el 40% favorable         |
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

   //--- 3) rechazo / pin bar
   const double wick=(dir>0 ? MathMin(m_rates[k].open,m_rates[k].close)-m_rates[k].low
                            : m_rates[k].high-MathMax(m_rates[k].open,m_rates[k].close));
   const double loc =(dir>0 ? (m_rates[k].close-m_rates[k].low)/rng
                            : (m_rates[k].high-m_rates[k].close)/rng);
   if(dirBody>0.0 && wick>=m_par.pinWickRatio*rng && loc>=0.60)
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

   const int from=(s.retestIdx>=0 ? BI_MinInt(s.retestIdx,s.breakIdx) : s.breakIdx);
   double ext=(dir>0 ? m_rates[from].low : m_rates[from].high);
   for(int q=from;q<=k;q++)
     {
      if(dir>0) { if(m_rates[q].low <ext) ext=m_rates[q].low;  }
      else      { if(m_rates[q].high>ext) ext=m_rates[q].high; }
     }
   if(dir>0) { if(s.levelLo<ext) ext=s.levelLo; }
   else      { if(s.levelHi>ext) ext=s.levelHi; }

   const double sl=ext-(double)dir*m_par.slAtrMult*atr;
   const double entry=m_rates[k].close;
   const double risk=(double)dir*(entry-sl);

   s.slPrice=NormalizeDouble(sl,m_digits);
   s.tpPrice=(risk>0.0 ? NormalizeDouble(entry+(double)dir*m_par.rrTarget*risk,m_digits) : 0.0);
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
   if(!m_par.useEmaFilter) return(8);
   const int t=TrendState(k);
   if(t==BI_TREND_UNKNOWN) return(5);
   if(t!=dir)              return(0);
   const bool slope=(dir>0 ? m_ctxEma[k]>m_ctxEmaPrev[k] : m_ctxEma[k]<m_ctxEmaPrev[k]);
   return(slope ? 15 : 10);
  }

int CBIEngine::ScoreVolaComp(const int k) const
  {
   if(!m_par.useAtrFilter) return(6);
   const double r=AtrRatio(k);
   if(r<=0.0) return(3);
   if(r>=m_par.atrMinRatio && r<=m_par.atrMaxRatio) return(10);
   if(r>=m_par.atrMinRatio*0.8 && r<=m_par.atrMaxRatio*1.2) return(5);
   return(0);
  }

int CBIEngine::ScoreSessionComp(const int k) const
  {
   if(m_par.sessionFilter==BI_SESS_OFF) return(5);
   return(BI_InSession(m_rates[k].time,m_par.sessionFilter,m_sessStart,m_sessEnd) ? 5 : 0);
  }

int CBIEngine::ScoreVolumeComp(const int k) const
  {
   if(!m_par.useVolume || !m_volUsable || m_volMA[k]<=0.0) return(3);
   const double r=m_vol[k]/m_volMA[k];
   if(r>=m_par.volumeMult) return(5);
   if(r>=1.0)              return(3);
   return(0);
  }

int CBIEngine::ScoreRetestComp(const SBISetup &s) const
  {
   if(s.retestIdx<0) return(m_par.requireRetest ? 0 : 10);
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
//| Suma de componentes (0-100). NO es una probabilidad.             |
//+------------------------------------------------------------------+
void CBIEngine::RecalcScore(SBISetup &s) const
  {
   s.scRetest =ScoreRetestComp(s);
   s.scConfirm=ScoreConfirmComp(s.confirmKind);
   const int total=s.scLevel+s.scClose+s.scTrend+s.scVola+
                   s.scRetest+s.scConfirm+s.scSession+s.scVolume;
   s.score=BI_ClampInt(total,0,100);
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
   //--- solo se considera vigente si se ha detectado en la ultima vela cerrada
   if(m_rangeIdx<0 || m_rangeHi<=m_rangeLo) return(false);
   return((m_n-2-m_rangeIdx)<=1);
  }

int CBIEngine::LastActiveSetup(void) const
  {
   for(int i=m_setupCount-1;i>=0;i--)
      if(m_setups[i].state==BI_ST_BREAKOUT || m_setups[i].state==BI_ST_RETEST)
         return(i);
   return(-1);
  }

#endif // __BI_ENGINE_MQH__
