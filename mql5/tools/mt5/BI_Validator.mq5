//+------------------------------------------------------------------+
//|                                                 BI_Validator.mq5 |
//|   Arnes de validacion EXTERNO para Breakout Intelligence MT5     |
//|                                                                  |
//|   PROPOSITO: comprobar objetivamente, desde MT5, el              |
//|   comportamiento del indicador (MTF, anti-repaint, state         |
//|   machine, retest, score, errores) SIN modificarlo.             |
//|                                                                  |
//|   RESTRICCIONES (por diseno, verificables en este archivo):     |
//|     - Solo lectura del indicador via iCustom (instancia propia). |
//|     - Cero trading: no incluye <Trade/*>, no llama a OrderSend   |
//|       ni a ninguna funcion de posiciones/ordenes.               |
//|     - Cero WebRequest / red.                                     |
//|     - Solo escribe CSV/TXT en MQL5/Files/<InpOutDir>.           |
//|     - No usa datos futuros: observa shift >= 1 (velas cerradas). |
//|                                                                  |
//|   MODELADO DEL TESTER (documentado):                            |
//|     El indicador recalcula solo en vela nueva y procesa hasta    |
//|     la ultima vela CERRADA (m_n-2), usando el OHLC completo de   |
//|     cada vela cerrada, sin dependencia intrabar. Por tanto el    |
//|     modo "Solo precios de apertura" (Open prices only) entrega   |
//|     el OHLC completo de cada vela cerrada y es CORRECTO y rapido. |
//|     Recomendado ademas repetir en "Cada tick" como confirmacion: |
//|     si baseline WRITE (Open) == COMPARE (Every tick), es prueba  |
//|     de que no hay dependencia intrabar ni repaint por modelado.  |
//+------------------------------------------------------------------+
#property copyright "BI Validator (solo validacion, no opera)"
#property version   "1.00"
#property description "Validador read-only de BreakoutIntelligence via iCustom. Cero trading."

//--- Indices de buffer del indicador (orden real verificado en el .mq5)
#define BUF_BREAK_UP   0
#define BUF_BREAK_DN   1
#define BUF_RETEST_UP  2
#define BUF_RETEST_DN  3
#define BUF_ENTRY_UP   4
#define BUF_ENTRY_DN   5
#define BUF_SCORE      6
#define BUF_STATE      7

enum ENUM_BL { BL_OFF=0, BL_WRITE=1, BL_COMPARE=2 };

input string          InpIndicatorPath = "BreakoutIntelligence\\BreakoutIntelligence"; // Ruta iCustom (relativa a MQL5/Indicators)
input ENUM_TIMEFRAMES InpContextTF     = PERIOD_H4;      // Contexto (2o input del indicador)
input ENUM_TIMEFRAMES InpStructureTF   = PERIOD_H1;      // Estructura (3er input del indicador)
input int             InpHistoryBars   = 3000;           // Velas M15 cerradas a observar
input int             InpWatchWindow   = 800;            // Velas historicas re-chequeadas por barra (repaint L1)
input ENUM_BL         InpBaselineMode  = BL_OFF;         // Baseline: OFF / WRITE / COMPARE
input int             InpUnresolvedWin = 40;             // Ventana (velas) del PROXY de no-confirmados
input bool            InpReadObjects   = true;           // Leer objetos BI_* (requiere indicador adjunto / visual)
input string          InpOutDir        = "BI_Validator"; // Subcarpeta en MQL5/Files

//--- estado global
int      g_handle = INVALID_HANDLE;
datetime g_lastBar = 0;
string   g_SEP = ";";
string   g_cfg = "";

//--- almacen de observaciones (clave = hora de apertura de la vela, ASCENDENTE)
datetime S_time[];
int      S_brk[], S_rts[], S_ent[], S_score[], S_state[];
datetime S_first[];
int      S_shift[];
int      S_n = 0;

//--- almacen baseline (para COMPARE)
long     B_epoch[];
int      B_brk[], B_rts[], B_ent[], B_score[], B_state[];
int      B_n = 0;

//--- contadores
long g_bars=0, g_break=0, g_retest=0, g_entry=0;
long g_repaint=0, g_diff=0, g_err=0, g_maxObj=0;

//--- ficheros CSV abiertos durante el run
int fSig=INVALID_HANDLE, fRep=INVALID_HANDLE, fMtf=INVALID_HANDLE, fErr=INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Utilidades                                                       |
//+------------------------------------------------------------------+
string TfStr(const ENUM_TIMEFRAMES tf)
  {
   string s=EnumToString(tf);
   StringReplace(s,"PERIOD_","");
   return(s);
  }

bool HasMark(const double v)
  {
   return(v!=EMPTY_VALUE && MathIsValidNumber(v));
  }

string Path(const string leaf)
  {
   return(InpOutDir+"\\"+leaf);
  }

int OpenCsv(const string leaf,const string header)
  {
   int h=FileOpen(Path(leaf),FILE_WRITE|FILE_ANSI|FILE_TXT);
   if(h==INVALID_HANDLE)
     {
      PrintFormat("BI_Validator: no se pudo abrir %s (err %d)",leaf,GetLastError());
      return(INVALID_HANDLE);
     }
   FileWriteString(h,header+"\r\n");
   return(h);
  }

void WriteLine(const int h,const string line)
  {
   if(h!=INVALID_HANDLE) FileWriteString(h,line+"\r\n");
  }

//--- ultima barra CERRADA del TF superior en el instante sigClose (sin look-ahead)
datetime LastClosedOpen(const ENUM_TIMEFRAMES tf,const datetime sigClose,datetime &outClose)
  {
   const int sec=PeriodSeconds(tf);
   outClose=0;
   if(sec<=0) return(0);
   int idx=iBarShift(_Symbol,tf,sigClose,false);
   if(idx<0) return(0);
   //--- avanzar hacia barras mas antiguas hasta que la barra este cerrada en sigClose
   for(int guard=0; guard<10000; guard++)
     {
      datetime op=iTime(_Symbol,tf,idx);
      if(op<=0) return(0);
      if((datetime)(op+sec)<=sigClose) { outClose=(datetime)(op+sec); return(op); }
      idx++;
     }
   return(0);
  }

//--- busqueda binaria por tiempo en el almacen S (ascendente). -1 si no existe.
int FindTime(const datetime t)
  {
   int lo=0, hi=S_n-1;
   while(lo<=hi)
     {
      int mid=(lo+hi)/2;
      if(S_time[mid]==t) return(mid);
      if(S_time[mid]<t) lo=mid+1; else hi=mid-1;
     }
   return(-1);
  }

//--- inserta una observacion nueva manteniendo el orden ascendente por tiempo
void InsertObs(const datetime t,const int brk,const int rts,const int ent,
               const int score,const int state,const int shift)
  {
   //--- posicion de insercion (casi siempre al final)
   int pos=S_n;
   while(pos>0 && S_time[pos-1]>t) pos--;

   ArrayResize(S_time ,S_n+1); ArrayResize(S_brk  ,S_n+1);
   ArrayResize(S_rts  ,S_n+1); ArrayResize(S_ent  ,S_n+1);
   ArrayResize(S_score,S_n+1); ArrayResize(S_state,S_n+1);
   ArrayResize(S_first,S_n+1); ArrayResize(S_shift,S_n+1);

   for(int i=S_n;i>pos;i--)
     {
      S_time[i]=S_time[i-1];   S_brk[i]=S_brk[i-1];
      S_rts[i]=S_rts[i-1];     S_ent[i]=S_ent[i-1];
      S_score[i]=S_score[i-1]; S_state[i]=S_state[i-1];
      S_first[i]=S_first[i-1]; S_shift[i]=S_shift[i-1];
     }
   S_time[pos]=t;     S_brk[pos]=brk;   S_rts[pos]=rts;   S_ent[pos]=ent;
   S_score[pos]=score; S_state[pos]=state;
   S_first[pos]=TimeCurrent(); S_shift[pos]=shift;
   S_n++;
  }

//--- registro de errores MQL5
void CheckErr(const string where)
  {
   int e=GetLastError();
   if(e!=0)
     {
      g_err++;
      long nobj=ObjectsTotal(0,-1,-1);
      WriteLine(fErr,StringFormat("%s%s%s%s%s%s%d%s%d%s%s",
                _Symbol,g_SEP,TfStr((ENUM_TIMEFRAMES)_Period),g_SEP,
                TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),g_SEP,
                e,g_SEP,(int)nobj,g_SEP,where));
      ResetLastError();
     }
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_cfg=StringFormat("PROF=AUTO;CTX=%s;STR=%s;HIST=%d;WATCH=%d;BLMODE=%d",
                      TfStr(InpContextTF),TfStr(InpStructureTF),
                      InpHistoryBars,InpWatchWindow,(int)InpBaselineMode);

   if(_Period>=InpStructureTF)
      PrintFormat("BI_Validator AVISO: el TF del grafico (%s) no es inferior al de estructura (%s); "
                  "el modo estructura del indicador no se activara.",
                  TfStr((ENUM_TIMEFRAMES)_Period),TfStr(InpStructureTF));

   //--- instancia PROPIA del indicador (no toca ninguna del grafico)
   ResetLastError();
   g_handle=iCustom(_Symbol,_Period,InpIndicatorPath,0,InpContextTF,InpStructureTF);
   if(g_handle==INVALID_HANDLE)
     {
      PrintFormat("BI_Validator: iCustom fallo para '%s' (err %d). Revisa la ruta.",
                  InpIndicatorPath,GetLastError());
      return(INIT_FAILED);
     }

   //--- ficheros CSV (cabeceras)
   fSig=OpenCsv("signals.csv",
        "symbol;tf;obs_time;bar_epoch;bar_time;shift;type;dir;score;config");
   fRep=OpenCsv("repaint.csv",
        "symbol;tf;detected_time;bar_epoch;bar_time;field;first_value;new_value;first_seen;config");
   fMtf=OpenCsv("mtf.csv",
        "symbol;tf;bar_epoch;bar_time;sig_close;type;dir;h1_open;h1_close;h1_ok;h4_open;h4_close;h4_ok;config");
   fErr=OpenCsv("errors.csv",
        "symbol;tf;at;last_error;bi_objects;where");

   //--- COMPARE: cargar baseline previa
   if(InpBaselineMode==BL_COMPARE)
      LoadBaseline();

   PrintFormat("BI_Validator iniciado. %s. Baseline=%d. Salida en MQL5/Files/%s/",
               g_cfg,(int)InpBaselineMode,InpOutDir);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnTick: una observacion por vela M15 cerrada                     |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- solo en vela nueva (en "Cada tick" ignora los ticks intrabar)
   datetime cur=iTime(_Symbol,_Period,0);
   if(cur==g_lastBar) return;
   g_lastBar=cur;

   if(BarsCalculated(g_handle)<=0) { CheckErr("BarsCalculated"); return; }

   int avail=Bars(_Symbol,_Period)-1;             // excluye la vela en formacion
   if(avail<10) return;
   int need=(int)MathMin(InpHistoryBars,avail);

   //--- lectura de los 8 buffers (series: indice = shift)
   double A0[],A1[],A2[],A3[],A4[],A5[],A6[],A7[];
   ArraySetAsSeries(A0,true); ArraySetAsSeries(A1,true);
   ArraySetAsSeries(A2,true); ArraySetAsSeries(A3,true);
   ArraySetAsSeries(A4,true); ArraySetAsSeries(A5,true);
   ArraySetAsSeries(A6,true); ArraySetAsSeries(A7,true);

   ResetLastError();
   if(CopyBuffer(g_handle,BUF_BREAK_UP ,0,need+1,A0)<=0){ CheckErr("CopyBuffer break_up");  return; }
   if(CopyBuffer(g_handle,BUF_BREAK_DN ,0,need+1,A1)<=0){ CheckErr("CopyBuffer break_dn");  return; }
   if(CopyBuffer(g_handle,BUF_RETEST_UP,0,need+1,A2)<=0){ CheckErr("CopyBuffer retest_up"); return; }
   if(CopyBuffer(g_handle,BUF_RETEST_DN,0,need+1,A3)<=0){ CheckErr("CopyBuffer retest_dn"); return; }
   if(CopyBuffer(g_handle,BUF_ENTRY_UP ,0,need+1,A4)<=0){ CheckErr("CopyBuffer entry_up");  return; }
   if(CopyBuffer(g_handle,BUF_ENTRY_DN ,0,need+1,A5)<=0){ CheckErr("CopyBuffer entry_dn");  return; }
   if(CopyBuffer(g_handle,BUF_SCORE    ,0,need+1,A6)<=0){ CheckErr("CopyBuffer score");     return; }
   if(CopyBuffer(g_handle,BUF_STATE    ,0,need+1,A7)<=0){ CheckErr("CopyBuffer state");     return; }
   CheckErr("CopyBuffer set");

   //--- recuento de objetos BI_ (deteccion de fugas)
   long nobj=CountBIObjects();
   if(nobj>g_maxObj) g_maxObj=nobj;

   //--- re-chequeo de las velas historicas (shift alto -> bajo para insertar ascendente)
   int lastShift=(int)MathMin(need,InpWatchWindow);
   for(int sh=lastShift; sh>=1; sh--)
     {
      datetime t=iTime(_Symbol,_Period,sh);
      if(t<=0) continue;

      int brk = HasMark(A0[sh]) ? +1 : (HasMark(A1[sh]) ? -1 : 0);
      int rts = HasMark(A2[sh]) ? +1 : (HasMark(A3[sh]) ? -1 : 0);
      int ent = HasMark(A4[sh]) ? +1 : (HasMark(A5[sh]) ? -1 : 0);
      int sco = HasMark(A6[sh]) ? (int)MathRound(A6[sh]) : -1;
      int sta = HasMark(A7[sh]) ? (int)MathRound(A7[sh]) : 0;

      int idx=FindTime(t);
      if(idx<0)
        {
         //--- PRIMERA observacion de esta vela
         InsertObs(t,brk,rts,ent,sco,sta,sh);
         if(brk!=0) g_break++;
         if(rts!=0) g_retest++;
         if(ent!=0) g_entry++;
         if(brk!=0 || rts!=0 || ent!=0)
           {
            LogSignal(t,sh,brk,rts,ent,sco);
            LogMtf(t,brk,rts,ent);
           }
        }
      else
        {
         //--- RE-observacion: cualquier cambio historico = repaint (L1)
         CompareCell(idx,t,"break", S_brk[idx],  brk);
         CompareCell(idx,t,"retest",S_rts[idx],  rts);
         CompareCell(idx,t,"entry", S_ent[idx],  ent);
         CompareCell(idx,t,"score", S_score[idx],sco);
         CompareCell(idx,t,"state", S_state[idx],sta);
         S_brk[idx]=brk; S_rts[idx]=rts; S_ent[idx]=ent; S_score[idx]=sco; S_state[idx]=sta;
        }
     }
   g_bars++;
  }

//+------------------------------------------------------------------+
//| Registro de un cambio historico (repaint L1)                     |
//+------------------------------------------------------------------+
void CompareCell(const int idx,const datetime t,const string field,
                 const int oldv,const int newv)
  {
   if(oldv==newv) return;
   g_repaint++;
   WriteLine(fRep,StringFormat("%s%s%s%s%s%s%d%s%s%s%s%s%d%s%d%s%s%s%s",
             _Symbol,g_SEP,TfStr((ENUM_TIMEFRAMES)_Period),g_SEP,
             TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES),g_SEP,
             (int)t,g_SEP,TimeToString(t,TIME_DATE|TIME_MINUTES),g_SEP,
             field,g_SEP,oldv,g_SEP,newv,g_SEP,
             TimeToString(S_first[idx],TIME_DATE|TIME_MINUTES),g_SEP,g_cfg));
  }

//+------------------------------------------------------------------+
//| Registro de una señal (signals.csv)                              |
//+------------------------------------------------------------------+
void LogSignal(const datetime t,const int shift,const int brk,const int rts,
               const int ent,const int score)
  {
   string base=StringFormat("%s%s%s%s%s%s%d%s%s%s%d%s",
              _Symbol,g_SEP,TfStr((ENUM_TIMEFRAMES)_Period),g_SEP,
              TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES),g_SEP,
              (int)t,g_SEP,TimeToString(t,TIME_DATE|TIME_MINUTES),g_SEP,shift,g_SEP);
   if(brk!=0) WriteLine(fSig,base+"BREAKOUT"+g_SEP+IntegerToString(brk)+g_SEP+"-1"+g_SEP+g_cfg);
   if(rts!=0) WriteLine(fSig,base+"RETEST"  +g_SEP+IntegerToString(rts)+g_SEP+"-1"+g_SEP+g_cfg);
   if(ent!=0) WriteLine(fSig,base+"ENTRY"   +g_SEP+IntegerToString(ent)+g_SEP+IntegerToString(score)+g_SEP+g_cfg);
  }

//+------------------------------------------------------------------+
//| Envolvente MTF (mtf.csv): demuestra que H1/H4 estaban cerradas   |
//+------------------------------------------------------------------+
void LogMtf(const datetime t,const int brk,const int rts,const int ent)
  {
   datetime sigClose=(datetime)(t+PeriodSeconds((ENUM_TIMEFRAMES)_Period));
   datetime h1c=0,h4c=0;
   datetime h1o=LastClosedOpen(InpStructureTF,sigClose,h1c);
   datetime h4o=LastClosedOpen(InpContextTF,  sigClose,h4c);
   int h1ok=(h1o>0 && h1c<=sigClose)?1:0;
   int h4ok=(h4o>0 && h4c<=sigClose)?1:0;
   int dir = ent!=0?ent : (brk!=0?brk:rts);
   string type = ent!=0?"ENTRY" : (brk!=0?"BREAKOUT":"RETEST");
   WriteLine(fMtf,StringFormat("%s%s%s%s%d%s%s%s%s%s%s%s%d%s%s%s%s%s%d%s%s%s%s%s%d%s%s",
             _Symbol,g_SEP,TfStr((ENUM_TIMEFRAMES)_Period),g_SEP,
             (int)t,g_SEP,TimeToString(t,TIME_DATE|TIME_MINUTES),g_SEP,
             TimeToString(sigClose,TIME_DATE|TIME_MINUTES),g_SEP,type,g_SEP,dir,g_SEP,
             TimeToString(h1o,TIME_DATE|TIME_MINUTES),g_SEP,TimeToString(h1c,TIME_DATE|TIME_MINUTES),g_SEP,h1ok,g_SEP,
             TimeToString(h4o,TIME_DATE|TIME_MINUTES),g_SEP,TimeToString(h4c,TIME_DATE|TIME_MINUTES),g_SEP,h4ok,g_SEP,g_cfg));
  }

//+------------------------------------------------------------------+
//| Objetos dibujados por el indicador                               |
//+------------------------------------------------------------------+
long CountBIObjects()
  {
   long c=0;
   int total=ObjectsTotal(0,-1,-1);
   for(int i=0;i<total;i++)
      if(StringFind(ObjectName(0,i,-1,-1),"BI_")==0) c++;
   return(c);
  }

void DumpObjects()
  {
   if(!InpReadObjects) return;
   int h=OpenCsv("objects.csv",
        "symbol;tf;snapshot_time;obj_name;kind;price0;price1;time0;time1;color");
   if(h==INVALID_HANDLE) return;
   int total=ObjectsTotal(0,-1,-1);
   for(int i=0;i<total;i++)
     {
      string nm=ObjectName(0,i,-1,-1);
      if(StringFind(nm,"BI_")!=0) continue;
      string kind="otro";
      if(StringFind(nm,"BI_L_")==0)      kind="nivel";
      else if(StringFind(nm,"BI_Z_")==0) kind="zona";
      else if(StringFind(nm,"BI_R_")==0) kind="rango";
      else if(StringFind(nm,"BI_T_")==0) kind="texto";
      else if(StringFind(nm,"BI_P_")==0) kind="panel";
      double p0=ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
      double p1=ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
      long   t0=ObjectGetInteger(0,nm,OBJPROP_TIME,0);
      long   t1=ObjectGetInteger(0,nm,OBJPROP_TIME,1);
      long   cl=ObjectGetInteger(0,nm,OBJPROP_COLOR);
      WriteLine(h,StringFormat("%s%s%s%s%s%s%s%s%s%s%.5f%s%.5f%s%s%s%s%s%d",
                _Symbol,g_SEP,TfStr((ENUM_TIMEFRAMES)_Period),g_SEP,
                TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES),g_SEP,nm,g_SEP,kind,g_SEP,
                p0,g_SEP,p1,g_SEP,
                TimeToString((datetime)t0,TIME_DATE|TIME_MINUTES),g_SEP,
                TimeToString((datetime)t1,TIME_DATE|TIME_MINUTES),g_SEP,(int)cl));
     }
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| Baseline WRITE / COMPARE                                         |
//+------------------------------------------------------------------+
void DumpBaseline()
  {
   int h=OpenCsv("baseline.csv",
        "symbol;tf;write_time;bar_epoch;bar_time;brk;rts;ent;score;state;config");
   if(h==INVALID_HANDLE) return;
   for(int i=0;i<S_n;i++)
      WriteLine(h,StringFormat("%s%s%s%s%s%s%d%s%s%s%d%s%d%s%d%s%d%s%d%s%s",
                _Symbol,g_SEP,TfStr((ENUM_TIMEFRAMES)_Period),g_SEP,
                TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES),g_SEP,
                (int)S_time[i],g_SEP,TimeToString(S_time[i],TIME_DATE|TIME_MINUTES),g_SEP,
                S_brk[i],g_SEP,S_rts[i],g_SEP,S_ent[i],g_SEP,S_score[i],g_SEP,S_state[i],g_SEP,g_cfg));
   FileClose(h);
   PrintFormat("BI_Validator: baseline.csv escrito (%d filas).",S_n);
  }

void LoadBaseline()
  {
   int h=FileOpen(Path("baseline.csv"),FILE_READ|FILE_ANSI|FILE_TXT);
   if(h==INVALID_HANDLE)
     {
      PrintFormat("BI_Validator: COMPARE sin baseline.csv (err %d). Ejecuta WRITE primero.",GetLastError());
      return;
     }
   bool first=true;
   while(!FileIsEnding(h))
     {
      string line=FileReadString(h);
      if(line=="") continue;
      if(first){ first=false; continue; }              // cabecera
      string p[];
      int np=StringSplit(line,StringGetCharacter(g_SEP,0),p);
      if(np<10) continue;
      // columnas: symbol;tf;write_time;bar_epoch;bar_time;brk;rts;ent;score;state;config
      ArrayResize(B_epoch,B_n+1); ArrayResize(B_brk,B_n+1); ArrayResize(B_rts,B_n+1);
      ArrayResize(B_ent,B_n+1);   ArrayResize(B_score,B_n+1); ArrayResize(B_state,B_n+1);
      B_epoch[B_n]=StringToInteger(p[3]);
      B_brk[B_n]=(int)StringToInteger(p[5]);
      B_rts[B_n]=(int)StringToInteger(p[6]);
      B_ent[B_n]=(int)StringToInteger(p[7]);
      B_score[B_n]=(int)StringToInteger(p[8]);
      B_state[B_n]=(int)StringToInteger(p[9]);
      B_n++;
     }
   FileClose(h);
   PrintFormat("BI_Validator: baseline cargada (%d filas) para COMPARE.",B_n);
  }

int FindBaseline(const long epoch)
  {
   for(int i=0;i<B_n;i++) if(B_epoch[i]==epoch) return(i);
   return(-1);
  }

void RunCompare()
  {
   int h=OpenCsv("baseline_diff.csv",
        "symbol;tf;bar_epoch;bar_time;field;baseline;current;config");
   if(h==INVALID_HANDLE) return;
   //--- por cada barra observada, comparar con la baseline
   for(int i=0;i<S_n;i++)
     {
      long ep=(long)S_time[i];
      int bi=FindBaseline(ep);
      if(bi<0)
        {
         g_diff++;
         WriteLine(h,StringFormat("%s%s%s%s%d%s%s%s%s%s%s%s%s%s%s",
                   _Symbol,g_SEP,TfStr((ENUM_TIMEFRAMES)_Period),g_SEP,(int)ep,g_SEP,
                   TimeToString(S_time[i],TIME_DATE|TIME_MINUTES),g_SEP,
                   "presence",g_SEP,"ausente",g_SEP,"presente",g_SEP,g_cfg));
         continue;
        }
      DiffField(h,ep,S_time[i],"break", B_brk[bi],  S_brk[i]);
      DiffField(h,ep,S_time[i],"retest",B_rts[bi],  S_rts[i]);
      DiffField(h,ep,S_time[i],"entry", B_ent[bi],  S_ent[i]);
      DiffField(h,ep,S_time[i],"score", B_score[bi],S_score[i]);
      DiffField(h,ep,S_time[i],"state", B_state[bi],S_state[i]);
     }
   FileClose(h);
  }

void DiffField(const int h,const long ep,const datetime t,const string field,
               const int basev,const int curv)
  {
   if(basev==curv) return;
   g_diff++;
   WriteLine(h,StringFormat("%s%s%s%s%d%s%s%s%s%s%d%s%d%s%s",
             _Symbol,g_SEP,TfStr((ENUM_TIMEFRAMES)_Period),g_SEP,(int)ep,g_SEP,
             TimeToString(t,TIME_DATE|TIME_MINUTES),g_SEP,field,g_SEP,basev,g_SEP,curv,g_SEP,g_cfg));
  }

//+------------------------------------------------------------------+
//| PROXY de no-confirmados (invalidacion/caducidad NO estan en buf) |
//+------------------------------------------------------------------+
long ProxyUnresolved()
  {
   long unresolved=0;
   for(int i=0;i<S_n;i++)
     {
      if(S_brk[i]==0) continue;
      int dir=S_brk[i];
      bool reached=false;
      for(int j=i+1;j<S_n && (j-i)<=InpUnresolvedWin;j++)
         if(S_ent[j]==dir) { reached=true; break; }
      if(!reached) unresolved++;
     }
   return(unresolved);
  }

//+------------------------------------------------------------------+
//| summary.txt                                                      |
//+------------------------------------------------------------------+
void WriteSummary()
  {
   int h=FileOpen(Path("summary.txt"),FILE_WRITE|FILE_ANSI|FILE_TXT);
   if(h==INVALID_HANDLE) return;
   long proxy=ProxyUnresolved();
   FileWriteString(h,"BI_Validator - resumen de ejecucion\r\n");
   FileWriteString(h,"===================================\r\n");
   FileWriteString(h,StringFormat("Simbolo                 : %s\r\n",_Symbol));
   FileWriteString(h,StringFormat("Timeframe grafico       : %s\r\n",TfStr((ENUM_TIMEFRAMES)_Period)));
   FileWriteString(h,StringFormat("Config                  : %s\r\n",g_cfg));
   FileWriteString(h,StringFormat("Fecha/hora fin          : %s\r\n",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)));
   FileWriteString(h,"-----------------------------------\r\n");
   FileWriteString(h,StringFormat("Barras M15 analizadas   : %d\r\n",(int)g_bars));
   FileWriteString(h,StringFormat("Velas observadas (store): %d\r\n",S_n));
   FileWriteString(h,StringFormat("Breakouts               : %d\r\n",(int)g_break));
   FileWriteString(h,StringFormat("Retests                 : %d\r\n",(int)g_retest));
   FileWriteString(h,StringFormat("Entries (confirmados)   : %d\r\n",(int)g_entry));
   FileWriteString(h,"-----------------------------------\r\n");
   FileWriteString(h,StringFormat("Repaints intra-ejecucion: %d   (cualquier valor > 0 = FALLO potencial de repaint)\r\n",(int)g_repaint));
   FileWriteString(h,StringFormat("Diferencias baseline    : %d   (solo en modo COMPARE; > 0 = divergencia)\r\n",(int)g_diff));
   FileWriteString(h,StringFormat("Errores MQL5            : %d   (ver errors.csv)\r\n",(int)g_err));
   FileWriteString(h,StringFormat("Max objetos BI_ vistos  : %d   (crecimiento sin limite = posible fuga)\r\n",(int)g_maxObj));
   FileWriteString(h,"-----------------------------------\r\n");
   FileWriteString(h,StringFormat("PROXY no-confirmados     : %d   (breakouts sin ENTRY en %d velas)\r\n",(int)proxy,InpUnresolvedWin));
   FileWriteString(h,"NOTA: invalidaciones y caducidades NO se codifican en buffers.\r\n");
   FileWriteString(h,"      El recuento autoritativo de INVALIDATED/EXPIRED debe leerse en la\r\n");
   FileWriteString(h,"      pestaña Expertos (el indicador hace Print() de cada evento si activas\r\n");
   FileWriteString(h,"      InpAlertOnInvalid / InpAlertOnExpired). El PROXY de arriba es solo\r\n");
   FileWriteString(h,"      una aproximacion basada en la ausencia de ENTRY posterior.\r\n");
   FileWriteString(h,"-----------------------------------\r\n");
   FileWriteString(h,"LIMITACIONES:\r\n");
   FileWriteString(h,"  - Los componentes del score no son observables (solo el score final 0-100).\r\n");
   FileWriteString(h,"  - MTF valida la ENVOLVENTE (H1/H4 cerradas al cierre M15), no la barra interna exacta.\r\n");
   FileWriteString(h,"  - El canal de objetos requiere el indicador adjunto al grafico (o modo visual).\r\n");
   FileWriteString(h,"  - break/retest/entry se comparan por direccion (-1/0/+1); score por valor.\r\n");
   FileWriteString(h,"  - bar_epoch se imprime como entero de 32 bits (fechas validas hasta 2038); el\r\n");
   FileWriteString(h,"    emparejamiento WRITE/COMPARE usa el mismo valor, asi que no afecta a la comparacion.\r\n");
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpBaselineMode==BL_WRITE)   DumpBaseline();
   if(InpBaselineMode==BL_COMPARE) RunCompare();
   DumpObjects();
   WriteSummary();

   if(fSig!=INVALID_HANDLE) FileClose(fSig);
   if(fRep!=INVALID_HANDLE) FileClose(fRep);
   if(fMtf!=INVALID_HANDLE) FileClose(fMtf);
   if(fErr!=INVALID_HANDLE) FileClose(fErr);
   if(g_handle!=INVALID_HANDLE) IndicatorRelease(g_handle);

   PrintFormat("BI_Validator fin: barras=%d break=%d retest=%d entry=%d repaint=%d diff=%d err=%d maxObj=%d",
               (int)g_bars,(int)g_break,(int)g_retest,(int)g_entry,
               (int)g_repaint,(int)g_diff,(int)g_err,(int)g_maxObj);
  }
//+------------------------------------------------------------------+
