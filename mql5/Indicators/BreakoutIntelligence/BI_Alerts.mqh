//+------------------------------------------------------------------+
//|                                                    BI_Alerts.mqh |
//|  Breakout Intelligence MT5 - formateo y despacho de alertas      |
//|                                                                  |
//|  Anti-duplicados: cada alerta se identifica por                  |
//|  (tipo | id de setup | hora de la barra | direccion). La clave   |
//|  se guarda en un anillo; si ya esta, la alerta no se repite.     |
//+------------------------------------------------------------------+
#ifndef __BI_ALERTS_MQH__
#define __BI_ALERTS_MQH__

#include "BI_Types.mqh"
#include "BI_Utils.mqh"

class CBIAlerts
  {
private:
   string            m_keys[];
   int               m_head;
   int               m_size;

   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_digits;

   bool              m_popup;
   bool              m_push;
   bool              m_mail;
   bool              m_sound;
   string            m_soundFile;

   bool              m_onWatch;
   bool              m_onBreakout;
   bool              m_onRetest;
   bool              m_onEntry;
   bool              m_onInvalid;
   bool              m_onExpired;
   int               m_minScore;

public:
                     CBIAlerts(void);
                    ~CBIAlerts(void) {}

   void              Configure(const string symbol,const ENUM_TIMEFRAMES tf,const int digits,
                               const bool popup,const bool push,const bool mail,
                               const bool sound,const string soundFile,
                               const bool onWatch,const bool onBreakout,const bool onRetest,
                               const bool onEntry,const bool onInvalid,const bool onExpired,
                               const int minScore);
   void              ResetHistory(void);
   bool              Enabled(const int eventType) const;
   string            BuildText(const SBIEvent &e) const;
   bool              Fire(const SBIEvent &e);

private:
   string            Key(const SBIEvent &e) const;
   bool              Seen(const string key) const;
   void              Remember(const string key);
  };

//+------------------------------------------------------------------+
CBIAlerts::CBIAlerts(void)
  {
   m_head=0;
   m_size=BI_ALERT_RING;
   ArrayResize(m_keys,m_size);
   for(int i=0;i<m_size;i++) m_keys[i]="";
   m_symbol=_Symbol; m_tf=PERIOD_CURRENT; m_digits=_Digits;
   m_popup=true; m_push=false; m_mail=false; m_sound=false; m_soundFile="alert.wav";
   m_onWatch=false; m_onBreakout=true; m_onRetest=true;
   m_onEntry=true;  m_onInvalid=true;  m_onExpired=false;
   m_minScore=65;
  }

//+------------------------------------------------------------------+
void CBIAlerts::Configure(const string symbol,const ENUM_TIMEFRAMES tf,const int digits,
                          const bool popup,const bool push,const bool mail,
                          const bool sound,const string soundFile,
                          const bool onWatch,const bool onBreakout,const bool onRetest,
                          const bool onEntry,const bool onInvalid,const bool onExpired,
                          const int minScore)
  {
   m_symbol=symbol; m_tf=tf; m_digits=digits;
   m_popup=popup; m_push=push; m_mail=mail; m_sound=sound; m_soundFile=soundFile;
   m_onWatch=onWatch; m_onBreakout=onBreakout; m_onRetest=onRetest;
   m_onEntry=onEntry; m_onInvalid=onInvalid; m_onExpired=onExpired;
   m_minScore=minScore;
  }

//+------------------------------------------------------------------+
void CBIAlerts::ResetHistory(void)
  {
   for(int i=0;i<m_size;i++) m_keys[i]="";
   m_head=0;
  }

//+------------------------------------------------------------------+
bool CBIAlerts::Enabled(const int eventType) const
  {
   switch(eventType)
     {
      case BI_EV_WATCH:       return(m_onWatch);
      case BI_EV_BREAKOUT:    return(m_onBreakout);
      case BI_EV_RETEST:      return(m_onRetest);
      case BI_EV_ENTRY:       return(m_onEntry);
      case BI_EV_INVALIDATED: return(m_onInvalid);
      case BI_EV_EXPIRED:     return(m_onExpired);
     }
   return(false);
  }

//+------------------------------------------------------------------+
string CBIAlerts::Key(const SBIEvent &e) const
  {
   return(IntegerToString(e.type)+"|"+IntegerToString(e.setupId)+"|"+
          IntegerToString((long)e.barTime)+"|"+IntegerToString(e.dir)+"|"+
          DoubleToString(e.level,m_digits));
  }

//+------------------------------------------------------------------+
bool CBIAlerts::Seen(const string key) const
  {
   for(int i=0;i<m_size;i++)
      if(m_keys[i]==key) return(true);
   return(false);
  }

//+------------------------------------------------------------------+
void CBIAlerts::Remember(const string key)
  {
   m_keys[m_head]=key;
   m_head=(m_head+1)%m_size;
  }

//+------------------------------------------------------------------+
//| Texto de la alerta                                               |
//+------------------------------------------------------------------+
string CBIAlerts::BuildText(const SBIEvent &e) const
  {
   const string head=m_symbol+" "+BI_TfText(m_tf);
   const string lvl =BI_Px(e.level,m_digits);
   const string px  =BI_Px(e.price,m_digits);

   switch(e.type)
     {
      case BI_EV_WATCH:
         return(StringFormat("[1] VIGILANCIA %s | %s %s en %s | precio %s | posible ruptura proxima",
                             head,(e.dir>0?"resistencia":"soporte"),
                             lvl,BI_LevelKindText(e.levelKind),px));

      case BI_EV_BREAKOUT:
         return(StringFormat("[2] RUPTURA %s %s | nivel %s (%s) roto con cierre en %s | score parcial %d/100 | estado: esperando retesteo",
                             BI_DirText(e.dir),head,lvl,
                             BI_LevelKindText(e.levelKind),px,e.score));

      case BI_EV_RETEST:
         return(StringFormat("[3] RETESTEO %s | el precio ha vuelto al nivel %s | estado: esperando confirmacion",
                             head,lvl));

      case BI_EV_ENTRY:
        {
         string txt=StringFormat("[4] SETUP %s %s | score %d/100 (%s) | nivel %s | confirmacion: %s",
                                 BI_SideText(e.dir),head,e.score,BI_GradeText(e.score),
                                 lvl,BI_ConfirmText(e.confirmKind));
         if(e.sl>0.0) txt+=" | SL sugerido "+BI_Px(e.sl,m_digits);
         if(e.tp>0.0) txt+=" | TP sugerido "+BI_Px(e.tp,m_digits);
         txt+=" | revisar riesgo antes de operar";
         return(txt);
        }

      case BI_EV_INVALIDATED:
         return(StringFormat("[5] INVALIDADO %s | cierre de vuelta dentro del rango, nivel %s | setup descartado",
                             head,lvl));

      case BI_EV_EXPIRED:
         return(StringFormat("[6] CADUCADO %s | sin retesteo o confirmacion en el plazo configurado, nivel %s",
                             head,lvl));
     }
   return("");
  }

//+------------------------------------------------------------------+
//| Dispara la alerta si procede. Devuelve true si se ha enviado.    |
//+------------------------------------------------------------------+
bool CBIAlerts::Fire(const SBIEvent &e)
  {
   if(!Enabled(e.type)) return(false);
   if(e.type==BI_EV_ENTRY && e.score<m_minScore) return(false);

   const string key=Key(e);
   if(Seen(key)) return(false);

   const string txt=BuildText(e);
   if(txt=="") return(false);

   Remember(key);

   if(m_popup) Alert(txt);
   if(m_push)  SendNotification(txt);
   if(m_mail)  SendMail("Breakout Intelligence - "+m_symbol,txt);
   if(m_sound) PlaySound(m_soundFile);
   Print(txt);
   return(true);
  }

#endif // __BI_ALERTS_MQH__
