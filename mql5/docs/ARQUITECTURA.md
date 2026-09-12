# Breakout Intelligence MT5 — Arquitectura y definiciones

Documento técnico del indicador. Define **con precisión numérica** cada concepto
del sistema, para que no quede ninguna regla ambigua del tipo «ruptura fuerte» o
«rechazo claro».

---

## 1. Qué es y qué no es

- Es un **indicador** (`.mq5`) de análisis y alertas.
- **No** abre, modifica ni cierra operaciones. No calcula lotaje.
- El *score* es una **clasificación interna de la calidad del setup según los
  filtros definidos abajo**. No es una probabilidad de acierto ni una estimación
  estadística.
- No elimina los falsos breakouts. Filtra los que incumplen las reglas.

---

## 2. Mapa de módulos

```
BreakoutIntelligence.mq5        Inputs, buffers, ciclo OnCalculate, despacho
  │
  ├── BI_Types.mqh              Enumeraciones y estructuras (nivel, setup, evento, parámetros)
  ├── BI_Utils.mqh              Utilidades: clamp, horas, sesiones, textos
  ├── BI_Profile.mqh            Clasificación del símbolo y valores por defecto por familia
  ├── BI_Levels.mqh             Pivotes, agrupación en zonas, detección de rangos
  ├── BI_Engine.mqh             Carga de datos, alineación multi-timeframe, máquina de estados, score
  ├── BI_Alerts.mqh             Texto de las 6 alertas y anti-duplicados
  └── BI_Render.mqh             Líneas de nivel, caja de rango, zonas de setup, panel
```

Responsabilidad de cada módulo:

| Módulo | Responsabilidad | No hace |
|---|---|---|
| `BI_Types` | Contratos de datos | Ninguna lógica |
| `BI_Utils` | Funciones puras sin estado | Acceso a mercado |
| `BI_Profile` | Adaptar constantes al activo | Decidir señales |
| `BI_Levels` | Dónde están las zonas | Decidir rupturas |
| `BI_Engine` | Cuándo cambia el estado de un setup | Dibujar ni alertar |
| `BI_Alerts` | Formato y envío, sin repetir | Decidir si hay señal |
| `BI_Render` | Representación gráfica | Modificar el estado |

---

## 3. Definiciones numéricas

Todas las magnitudes de distancia se expresan en múltiplos de **ATR(14) del
timeframe de señal**, de modo que el motor no depende de dígitos, tick size ni
tamaño de contrato. `ATR_k` es el ATR de la vela `k`.

### 3.1 Pivote

Pivote máximo en la vela `p` con profundidad `D`:

```
high[p] >= high[p-i]   para i = 1..D
high[p] >  high[p+i]   para i = 1..D
```

La desigualdad estricta por la derecha evita que una meseta de máximos iguales
produzca varios pivotes. El pivote mínimo es simétrico.

**Un pivote en `p` sólo se considera conocido a partir de la vela `p+D`.** Antes
de esa vela no existe para el motor. Esta es la primera garantía anti-repintado.

### 3.2 Nivel y zona

Un nivel es un **cluster** de precios. Al incorporar un precio `x` en la vela `k`:

- Tolerancia `tol_k = clusterATR · ATR_k`.
- Si existe un nivel no roto con `lo - tol_k <= x <= hi + tol_k`, se fusiona:
  `hi = max(hi, x)`, `lo = min(lo, x)`, `price = (hi+lo)/2`, `touches += 1`.
- La fusión se rechaza si la zona resultante superaría `2 · clusterATR · ATR_k`
  de anchura; en ese caso se crea un nivel nuevo.

Orígenes de nivel: pivotes (`SWING`), bordes de rango (`RANGE`), máximo/mínimo del
día anterior (`PDAY`), de la semana anterior (`PWEEK`) y de la sesión asiática
(`ASIA`).

Un nivel es **candidato a ser roto** en la vela `k` si:

```
activo  Y  no roto  Y  k > knownIdx  Y  (k - lastIdx) <= lookbackBars
y, si es SWING o RANGE:  (k - firstIdx) >= minLevelAgeBars
y, si es SWING:          touches >= minTouches
```

### 3.3 Rango / consolidación

Terminado en la vela `k`:

1. Se amplía la ventana desde `rangeMinBars` y se toma la **más larga** cuya
   anchura `hi - lo` no supere `rangeMaxWidthATR · ATR_k`. La anchura es monótona
   no decreciente al ampliar, así que basta ampliar hasta incumplir.
2. Toques: `high >= hi - rangeTouchATR·ATR_k` cuenta como toque del borde
   superior (simétrico abajo). Se exigen `rangeMinTouches` en **cada** borde.
3. Deriva: se comparan las **medias** de los cierres del primer y del último
   quinto de la ventana. Si
   `|media_última - media_primera| / anchura > rangeMaxDrift`, el tramo se
   considera tendencia y se descarta.

Los bordes del rango aceptado se dan de alta como niveles `RANGE`.

### 3.4 Ruptura

Sobre la vela **cerrada** `k`, dirección `d` (+1 alcista, −1 bajista), borde
`edge` (= `hi` si alcista, `lo` si bajista):

```
margin_k = max( breakMarginATR · ATR_k , breakMarginSpreads · spread_k , tickSize )

C1  d·(close[k] − edge) > margin_k
C2  d·(close[k] − open[k]) / (high[k] − low[k])  >= minBodyRatio
C3  posición del cierre en la vela >= minCloseLoc
      alcista: (close−low)/(high−low)
      bajista: (high−close)/(high−low)
C4  (high[k] − low[k]) >= minBarRangeATR · ATR_k
      O BIEN  d·(close[k] − edge) >= 1.5 · margin_k
C5  las preBreakBars velas anteriores cerraron del lado contrario:
      d·(close[k−q] − edge) <= 0   para q = 1..preBreakBars
C6  d·(edge − close[k−1]) <= approachMaxATR · ATR_k
C7  filtros duros activos (EMA, ATR, RSI, sesión) si están marcados como duros
```

**C2 y C3 son el filtro anti-mecha**: una vela que sólo perfora con la sombra no
cumple ni el cuerpo mínimo ni la posición del cierre. **C5** impide señalar dos
veces la misma ruptura. **C6** evita que un hueco enorme «rompa» un nivel muy
lejano.

Si varias zonas cumplen las condiciones en la misma vela y dirección, se elige la
de mayor relevancia (§3.8). Se crea **un** setup y el nivel queda marcado como
roto en esa dirección, lo que impide volver a señalarlo.

### 3.5 Retesteo

Con el setup en estado RUPTURA, en la vela cerrada `k`:

```
ext    = low[k]  si alcista,  high[k] si bajista
tol_k  = retestTolATR · ATR_k
RETESTEO  si   d·(ext − edge) <= tol_k
```

Se marca `touchedZone = true` cuando `d·(ext − edge) <= 0`, es decir cuando el
precio ha penetrado realmente la zona y no sólo se ha acercado.

**Retesteo estricto (obligatorio con `InpRequireRetest = true`).** Para pasar a
CONFIRMADO se exige `touchedZone == true`: una simple aproximación a la zona
**no** confirma. Si el precio se aproxima (entra en estado RETESTEO) pero nunca
penetra, el setup **caduca** en lugar de confirmar. El componente de puntuación
de retesteo sólo cuenta si hubo un retesteo genuino.

### 3.6 Confirmación

Con el setup en estado RETESTEO y `k > retestIdx`. Condición previa obligatoria:
`d·(close[k] − edge) > 0`. Basta con **uno** de estos cuatro patrones:

| Patrón | Regla |
|---|---|
| Continuación | `d·(close[k] − ref) > 0` y `d·(close[k] − edge) >= margin_k`, donde `ref` es el extremo del tramo `[retestIdx, k−1]` |
| Envolvente | Vela direccional que envuelve a la anterior, de signo contrario, con cuerpo mayor |
| Rechazo | Mecha del lado del nivel `>= pinWickRatio · (high−low)` y cierre en el 40 % favorable. **No** se exige color de cuerpo: un martillo con cuerpo ligeramente contrario pero mecha dominante es válido |
| Estructura | Extremo del retesteo mejor que el de la vela de ruptura **y** cierre superando el extremo de esa vela |

No se exigen todos a la vez: eso haría que casi nunca hubiera señal.

### 3.7 Invalidación y caducidad

```
INVALIDADO  si   d·(close[k] − edge) < −reentryATR · ATR_k
                 (se comprueba antes que cualquier otra transición)
CADUCADO    si   estado RUPTURA  y  k − breakIdx  >= retestMaxBars
            o si estado RETESTEO y  k − retestIdx >= confirmMaxBars
```

Al invalidarse, el nivel **vuelve a estar operativo** y suma un toque: ha
aguantado, luego es más relevante. Al caducar, el nivel permanece marcado como
roto para no repetir la misma señal.

### 3.8 Puntuación (0–100)

| Componente | Máx | Regla |
|---|---|---|
| Relevancia del nivel | 20 | `RANGE` 20, `PWEEK` 19, `PDAY` 18, `ASIA` 14; `SWING`: 4+ toques 20, 3 → 17, 2 → 14, 1 → 8 |
| Calidad del cierre | 15 | +6 si exceso ≥ margin, +3 si ≥ 2·margin, +3 si cuerpo ≥ 60 %, +3 si cierre ≥ 75 % |
| Contexto EMA | 15 | 15 alineado y EMA en pendiente favorable; 10 sólo alineado; 0 en contra; 8 si el filtro está desactivado |
| Volatilidad | 10 | 10 si `ATR/ATR_medio` dentro de [min,max]; 5 en el margen ±20 %; 0 fuera |
| Retesteo | 20 | 20 si penetró la zona; 14 si sólo se aproximó; 0 sin retesteo |
| Confirmación | 10 | Continuación/envolvente 10, rechazo 8, estructura 7 |
| Sesión | 5 | 5 dentro de la ventana configurada |
| Volumen | 5 | 5 si `vol >= volumeMult · media`; 3 si ≥ media; 3 si el símbolo no da volumen útil |

**Normalización (importante).** Cada componente aporta al numerador (puntos
ganados) **y al denominador** (puntos máximos) **sólo si está activo**:

- nivel y cierre cuentan siempre (núcleo estructural, 35 puntos);
- EMA, ATR, sesión y volumen cuentan sólo si su filtro está activado y el dato es
  utilizable (así **la sesión desactivada ya no otorga 5/5** ni infla el score);
- retesteo cuenta sólo si hubo un retesteo genuino;
- confirmación cuenta sólo una vez confirmado el setup.

`score = redondeo(100 · ganados / máximo_activo)`. Con todos los filtros activos y
el setup confirmado, el máximo es 100 (compatibilidad con la tabla anterior). En
la ruptura, el máximo excluye retesteo y confirmación (aún no evaluados).

Clasificación: **A** ≥ 80, **B** 65–79, **C** 50–64, **D** < 50. Sólo se alerta la
entrada si el score alcanza `InpMinScoreAlert` (65 por defecto).

---

## 4. Política anti-repintado

1. El recorrido llega hasta el índice `n−2`. **La vela en formación nunca se
   evalúa.**
2. Entre ticks de una misma vela el indicador **no recalcula nada**: sólo refresca
   el panel. Ningún marcador ni ninguna alerta puede cambiar dentro de la vela.
3. Cada vela `k` decide con datos de velas `<= k` exclusivamente. Los detectores
   de pivote y de rango reciben `n = k+1` como límite superior, lo que hace
   imposible leer velas posteriores.
4. Las series de timeframe superior (EMA de contexto, día previo, semana previa,
   **y las zonas del TF de estructura**) se alinean exigiendo que la vela superior
   esté **cerrada** antes del cierre de la vela `k`. Durante el día en curso, el
   valor del «día anterior» es el del día cerrado, no el del día que se está
   formando. Las zonas de H1 (`BuildStructureLevels`) sólo se inyectan en la vela
   M15 cuya hora de cierre alcanza el cierre de la barra H1 que confirmó el pivote
   o el rango. La detección de rangos de H1 usa un **ATR(14) real del propio H1**
   (`BI_AtrArray`, suavizado de Wilder y causal: el ATR en la barra `conf` sólo
   depende de barras ≤ `conf`), no la anchura de una única vela.
5. La reconstrucción es **determinista**: se recorre toda la ventana con las
   mismas reglas en cada vela nueva. Para que el borde vivo sea estable, el
   indicador amplía automáticamente la ventana procesada a
   `lookbackBars + rangeMaxBars + 200` como mínimo, de modo que ningún nivel
   vigente pueda proceder del extremo antiguo de la ventana.

**Lo que sí cambia intra-vela:** nada del gráfico. El panel muestra ATR y RSI de
la última vela cerrada, que tampoco cambian.

---

## 5. Anti-duplicados

- Un setup emite cada evento **una sola vez**: cada transición cambia el estado y
  los estados terminales (CONFIRMADO, INVALIDADO, CADUCADO) ya no se procesan.
- No puede haber dos setups vivos sobre el mismo nivel y dirección.
- Un nivel roto no vuelve a generar ruptura en la misma dirección mientras siga
  marcado como roto.
- Sólo se despachan alertas de eventos cuyo índice coincide con la **última vela
  cerrada**.
- Sobre eso, `BI_Alerts` mantiene un anillo de 64 claves
  `(tipo | id de setup | hora de vela | dirección | nivel)`; una clave repetida no
  se envía.
- Los avisos de aproximación (alerta 1) tienen además un enfriamiento de
  `InpWatchCooldown` velas por nivel.

---

## 6. Multi-timeframe

| Timeframe | Papel |
|---|---|
| Contexto (`InpContextTF`, por defecto H4) | Dirección mediante EMA 200 y su pendiente |
| Gráfico actual | Zonas, rangos, ruptura, retesteo y confirmación |
| D1 / W1 | Máximo y mínimo del periodo anterior como niveles de referencia |

El planteamiento **H4 contexto / H1 zonas / M15 ejecución** se implementa de
forma explícita: se abre el indicador en **M15** con `InpContextTF = H4` y
`InpStructureTF = H1` (valores por defecto). Cuando `InpStructureTF` es superior
al timeframe del gráfico, las zonas (pivotes y rangos) se calculan sobre ese TF y
se inyectan alineadas anti-look-ahead: una zona de H1 sólo influye en una vela
M15 cuando su barra H1 ya está cerrada respecto al cierre de esa vela M15 (ver
`BuildStructureLevels` en §4). Si `InpStructureTF` = timeframe del gráfico, las
zonas se calculan sobre el propio gráfico (comportamiento de la v1.00).

Una zona de estructura se registra con su índice **real** de conocimiento
(`knownIdx`), sin fabricar antigüedad. Por tanto sólo pasa a ser operable cuando
han transcurrido `minLevelAgeBars` velas del gráfico desde `knownIdx` (es decir,
en `knownIdx + minLevelAgeBars`). El almacenamiento de niveles de estructura se
dimensiona según el histórico procesado, de modo que los niveles más recientes
—los relevantes para la señal actual— nunca se descartan por un tope fijo.

---

## 7. Perfiles por activo

Detección automática por nombre de símbolo, en este orden: metales → cripto →
índices → forex. Se comprueban subcadenas (`XAU`, `GOLD`, `XAG`, `BTC`, `XBT`,
`NAS`, `US100`, `USTEC`, `NDX`, …) sobre el nombre normalizado a mayúsculas y sin
separadores, de modo que `XAUUSD.pro`, `BTCUSD_m` o `US100.cash` se clasifican
bien.

Cada perfil ajusta márgenes, tolerancias y plazos. Extracto:

| Parámetro | Forex | Metales | Cripto | Índices |
|---|---|---|---|---|
| Margen de ruptura (×ATR) | 0.25 | 0.35 | 0.45 | 0.30 |
| Tolerancia de retesteo (×ATR) | 0.35 | 0.45 | 0.55 | 0.40 |
| Reentrada que invalida (×ATR) | 0.10 | 0.15 | 0.20 | 0.12 |
| Anchura máxima de rango (×ATR) | 2.5 | 3.0 | 3.5 | 3.0 |
| Velas hasta caducar sin retesteo | 12 | 14 | 16 | 14 |

Cualquier parámetro numérico puesto a `0` en los inputs toma el valor del perfil.
Cualquier valor distinto de `0` **sobrescribe** el perfil.

**Sesiones.** Las horas de Londres, Nueva York y personalizada se indican en
**horario del servidor del broker** (`InpLondonStart/End`, `InpNewYorkStart/End`,
`InpSessCustomStart/End`). No hay conversión a UTC ni ajuste automático de horario
de verano: si el broker cambia de offset, el usuario ajusta las horas. El filtro
`LDN_NY` evalúa dos ventanas simultáneas.

---

## 8. Limitaciones conocidas

1. **No compilado por el autor del código.** Ver `PRUEBAS.md`.
2. El volumen de Forex es **volumen de ticks** del broker, no volumen real de
   mercado; el panel lo etiqueta como `TICK`. Cuando el símbolo no entrega
   volumen útil, el componente de volumen **no se cuenta** en el score (ni suma
   ni resta), en lugar de otorgar un valor neutro.
3. Las horas de sesión son **horas del servidor del broker**, definidas
   explícitamente por el usuario. El indicador **no** convierte a UTC ni gestiona
   el horario de verano: si el broker cambia de offset (típico en primavera/otoño),
   el usuario debe ajustar las horas. Se eligió esta vía frente a un ajuste
   automático de DST porque el offset real depende del broker y no es fiable
   deducirlo.
4. No hay integración con calendario de noticias. MQL5 ofrece la API de
   calendario, pero requiere permisos y datos que no todos los brokers sirven;
   se ha dejado fuera de la versión 1.0 en lugar de entregar algo poco fiable.
5. Los niveles del día y la semana anteriores usan las barras D1/W1 del broker,
   cuyo corte horario depende del servidor.
6. El indicador reconstruye toda la ventana en cada vela nueva. Con
   `InpMaxHistoryBars` muy alto (> 10 000) y `InpRangeMaxBars` grande el coste por
   vela crece de forma apreciable.
7. La sesión asiática se calcula sobre las velas del timeframe del gráfico. En
   timeframes altos (H4 o superior) la ventana horaria pierde resolución y la
   opción deja de tener sentido.
