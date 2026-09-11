//+------------------------------------------------------------------+
//|                                                     BI_Types.mqh |
//|  Breakout Intelligence MT5 - tipos, enumeraciones y estructuras  |
//+------------------------------------------------------------------+
#ifndef __BI_TYPES_MQH__
#define __BI_TYPES_MQH__

#define BI_VERSION        "1.10"
#define BI_OBJ_PREFIX     "BI_"
#define BI_MAX_LEVELS     120
#define BI_MAX_SETUPS     32
#define BI_MAX_EVENTS     256
#define BI_ALERT_RING     64
#define BI_MAX_STRUCT     600

//--- Direccion de la operativa detectada
enum ENUM_BI_DIR
  {
   BI_DIR_NONE  =  0,  // Sin direccion
   BI_DIR_UP    =  1,  // Alcista
   BI_DIR_DOWN  = -1   // Bajista
  };

//--- Origen del nivel detectado
enum ENUM_BI_LEVEL_KIND
  {
   BI_LK_SWING = 0,  // Cluster de pivotes (estructura)
   BI_LK_RANGE = 1,  // Borde de rango / consolidacion
   BI_LK_PDAY  = 2,  // Maximo / minimo del dia anterior
   BI_LK_PWEEK = 3,  // Maximo / minimo de la semana anterior
   BI_LK_ASIA  = 4   // Maximo / minimo de la sesion asiatica
  };

//--- Estados del ciclo de vida de un setup
enum ENUM_BI_STATE
  {
   BI_ST_NONE        = 0,  // Sin setup
   BI_ST_BREAKOUT    = 1,  // Ruptura confirmada, esperando retesteo
   BI_ST_RETEST      = 2,  // Retesteo en curso, esperando confirmacion
   BI_ST_CONFIRMED   = 3,  // Setup confirmado
   BI_ST_INVALIDATED = 4,  // Invalidado (cierre de vuelta dentro del rango)
   BI_ST_EXPIRED     = 5   // Caducado por tiempo
  };

//--- Tipos de evento emitidos por el motor
enum ENUM_BI_EVENT
  {
   BI_EV_NONE        = 0,
   BI_EV_LEVEL       = 1,  // Nivel relevante nuevo
   BI_EV_WATCH       = 2,  // Precio aproximandose a un nivel
   BI_EV_BREAKOUT    = 3,  // Ruptura confirmada por cierre
   BI_EV_RETEST      = 4,  // Retesteo detectado
   BI_EV_ENTRY       = 5,  // Setup confirmado
   BI_EV_INVALIDATED = 6,  // Setup invalidado
   BI_EV_EXPIRED     = 7   // Setup caducado
  };

//--- Perfiles por familia de activo
enum ENUM_BI_PROFILE
  {
   BI_PROFILE_AUTO   = 0,  // Auto (detectar por nombre de simbolo)
   BI_PROFILE_FOREX  = 1,  // Forex
   BI_PROFILE_METAL  = 2,  // Metales (XAUUSD, XAGUSD...)
   BI_PROFILE_CRYPTO = 3,  // Cripto (BTCUSD, BTCUSDT...)
   BI_PROFILE_INDEX  = 4   // Indices (NAS100, US100, USTEC...)
  };

//--- Filtro de sesion
enum ENUM_BI_SESSION_FILTER
  {
   BI_SESS_OFF     = 0,  // Desactivado
   BI_SESS_LONDON  = 1,  // Londres
   BI_SESS_NEWYORK = 2,  // Nueva York
   BI_SESS_LDN_NY  = 3,  // Londres + Nueva York
   BI_SESS_CUSTOM  = 4   // Horario personalizado
  };

//--- Tipo de vela de confirmacion reconocida
enum ENUM_BI_CONFIRM_KIND
  {
   BI_CONF_NONE         = 0,
   BI_CONF_CONTINUATION = 1,  // Cierre de continuacion
   BI_CONF_ENGULFING    = 2,  // Vela envolvente
   BI_CONF_REJECTION    = 3,  // Rechazo / pin bar
   BI_CONF_STRUCTURE    = 4   // Estructura (minimo/maximo superior)
  };

//--- Modo de operacion multi-timeframe del contexto
enum ENUM_BI_TREND_STATE
  {
   BI_TREND_UNKNOWN =  0,
   BI_TREND_UP      =  1,
   BI_TREND_DOWN    = -1
  };

//+------------------------------------------------------------------+
//| Nivel / zona relevante                                           |
//+------------------------------------------------------------------+
struct SBILevel
  {
   int      id;          // identificador estable
   int      kind;        // ENUM_BI_LEVEL_KIND
   double   price;       // precio representativo (centro de la zona)
   double   hi;          // borde superior de la zona
   double   lo;          // borde inferior de la zona
   int      touches;     // numero de toques acumulados
   int      firstIdx;    // barra en la que se formo el primer toque
   int      knownIdx;    // barra a partir de la cual el nivel es CONOCIDO
   int      lastIdx;     // ultimo toque
   int      brokenDir;   // 0 intacto, +1 roto al alza, -1 roto a la baja
   int      brokenIdx;   // barra de la rotura
   int      lastWatchIdx;// ultima alerta de aproximacion
   bool     active;      // sigue vigente
  };

//+------------------------------------------------------------------+
//| Setup (maquina de estados)                                       |
//+------------------------------------------------------------------+
struct SBISetup
  {
   int      id;
   int      levelId;
   int      levelKind;
   double   levelEdge;     // borde roto (hi si alcista, lo si bajista)
   double   levelHi;
   double   levelLo;
   int      dir;           // ENUM_BI_DIR
   int      state;         // ENUM_BI_STATE
   int      breakIdx;
   int      retestIdx;     // primer retesteo
   int      retestDeepIdx; // retesteo mas profundo
   double   retestExtreme; // low (alcista) / high (bajista) mas profundo
   int      confirmIdx;
   int      endIdx;        // barra de cierre del ciclo
   int      confirmKind;   // ENUM_BI_CONFIRM_KIND
   bool     touchedZone;   // el retesteo penetro realmente la zona
   bool     retestReal;    // hubo un retesteo genuino (no confirmacion directa)
   double   breakClose;
   double   breakMargin;
   double   atrAtBreak;
   double   slPrice;
   double   tpPrice;
   bool     slValid;       // el SL/TP calculado es coherente y presentable
   int      scLevel;
   int      scClose;
   int      scTrend;
   int      scVola;
   int      scRetest;
   int      scConfirm;
   int      scSession;
   int      scVolume;
   int      scoreMax;      // maximo alcanzable segun filtros/estado activos
   int      score;         // 0-100 normalizado sobre scoreMax
  };

//+------------------------------------------------------------------+
//| Evento emitido por el motor                                      |
//+------------------------------------------------------------------+
struct SBIEvent
  {
   int      type;        // ENUM_BI_EVENT
   int      dir;
   int      barIdx;      // indice interno del motor
   datetime barTime;
   double   price;       // precio de referencia del evento
   double   level;       // nivel implicado
   double   sl;
   double   tp;
   int      score;
   int      setupId;
   int      levelKind;
   int      confirmKind;
   int      state;
  };

//+------------------------------------------------------------------+
//| Parametros de trabajo resueltos (inputs + perfil)                |
//+------------------------------------------------------------------+
struct SBIParams
  {
   //--- contexto
   string          symbol;
   ENUM_TIMEFRAMES tfSignal;
   ENUM_TIMEFRAMES tfContext;        // contexto de tendencia (EMA), p.ej. H4
   ENUM_TIMEFRAMES tfStructure;      // estructura/zonas, p.ej. H1 (0 = grafico)
   bool            useStructTF;      // tfStructure != grafico
   int             profile;          // ENUM_BI_PROFILE resuelto

   //--- estructura
   int             pivotDepth;
   int             lookbackBars;
   int             minTouches;
   int             minLevelAgeBars;
   double          clusterATR;

   //--- rango
   bool            useRange;
   int             rangeMinBars;
   int             rangeMaxBars;
   double          rangeMaxWidthATR;
   double          rangeTouchATR;
   double          rangeMaxDrift;
   int             rangeMinTouchesSide;

   //--- ruptura
   double          breakMarginATR;
   double          breakMarginSpreads;
   double          minBodyRatio;
   double          minCloseLoc;
   double          minBarRangeATR;
   double          approachMaxATR;
   int             preBreakBars;

   //--- retesteo y confirmacion
   bool            requireRetest;
   double          retestTolATR;
   double          reentryATR;
   int             retestMaxBars;
   int             confirmMaxBars;
   double          pinWickRatio;

   //--- vigilancia
   double          watchDistATR;
   int             watchCooldown;

   //--- filtros
   bool            useEmaFilter;
   bool            emaHardFilter;
   int             emaPeriod;
   bool            useAtrFilter;
   bool            atrHardFilter;
   int             atrPeriod;
   int             atrRefPeriod;
   double          atrMinRatio;
   double          atrMaxRatio;
   bool            useVolume;
   double          volumeMult;
   int             volumeMAPeriod;
   bool            useRsi;
   bool            rsiHardFilter;
   int             rsiPeriod;
   double          rsiBullMin;
   double          rsiBearMax;

   //--- niveles de referencia
   bool            usePrevDay;
   bool            usePrevWeek;
   bool            useAsia;
   int             asiaStartHour;
   int             asiaEndHour;

   //--- sesion (horas del SERVIDOR del broker; sin conversion ni DST)
   int             sessionFilter;    // ENUM_BI_SESSION_FILTER
   int             sess1Start;       // ventana 1 (Londres): hora inicio
   int             sess1End;         // ventana 1: hora fin
   int             sess2Start;       // ventana 2 (Nueva York): -1 si no se usa
   int             sess2End;
   bool            sessionHardFilter;

   //--- puntuacion y riesgo
   int             minScoreAlert;
   double          slAtrMult;
   double          rrTarget;

   //--- ejecucion
   int             maxHistoryBars;
   int             maxActiveSetups;
  };


//+------------------------------------------------------------------+
//| Senal historica (registro persistente e independiente del cap de |
//| setups vivos). Cada BREAKOUT / RETEST / ENTRY que ocurre en la   |
//| ventana procesada queda aqui para representarse aunque el setup  |
//| que la genero ya haya sido reciclado.                            |
//+------------------------------------------------------------------+
struct SBISignal
  {
   int      type;        // ENUM_BI_EVENT (solo BREAKOUT/RETEST/ENTRY)
   int      dir;
   int      barIdx;      // indice interno del motor
   datetime barTime;
   double   level;
   double   sl;
   double   tp;
   bool     slValid;
   int      score;
   int      confirmKind;
   int      setupId;
  };

#endif // __BI_TYPES_MQH__
