# Changelog — Breakout Intelligence MT5

## v1.10 — Revisión y correcciones sobre v1.00

Esta versión responde punto por punto a la revisión externa del proyecto. Cada
prioridad indica **qué se cambió**, **dónde** y **cómo se verificó**. Recordatorio
honesto: **el código sigue sin compilarse en MetaEditor** en este entorno (Linux
sin MetaEditor/Wine). Lo verificado es estático y lógico; lo pendiente es MT5 real.

### P1 — Multi-timeframe real H4 / H1 / M15  🔴
**Antes:** las zonas se calculaban sobre el timeframe del gráfico; no existía un
H1 independiente.
**Ahora:** nuevo input `InpStructureTF` (por defecto **H1**). Cuando el TF de
estructura es superior al del gráfico, las **zonas** (pivotes y rangos) se
construyen sobre ese TF en `BuildStructureLevels()` y se **inyectan** en el
gráfico alineadas **anti-look-ahead**: un pivote de la barra `sp` se confirma al
cierre de `sp+depth`, y solo influye en la barra M15 cuya hora de cierre es
`>= (time[sp+depth] + duración_H1)`. H4 permanece como **contexto EMA 200**
(sin cambios). Si el TF de estructura = gráfico, se conserva el comportamiento
anterior (zonas del propio gráfico).
- Ficheros: `BI_Engine.mqh` (`BuildStructureLevels`, `InjectStructureLevels`,
  rama en `ProcessBar`), `BI_Types.mqh` (`tfStructure`, `useStructTF`),
  `BreakoutIntelligence.mq5` (input y resolución).
- Pruebas: sección 12 del modelo lógico (mapeo temporal exacto, sin look-ahead).

### P2 — Retesteo estricto  🔴
**Antes:** con `InpRequireRetest=true` un setup podía CONFIRMAR sin haber
penetrado la zona (bastaba aproximarse).
**Ahora:** para pasar a `CONFIRMED` con `requireRetest=true` es **obligatorio**
`touchedZone==true` (el precio penetró realmente la zona). Una aproximación sin
toque no genera ENTRY: el setup espera y, si no toca, **caduca**. El componente
de retesteo solo puntúa si hubo un retesteo genuino (`retestReal`).
- Ficheros: `BI_Engine.mqh` (`UpdateSetups`, `RecalcScore`), `BI_Types.mqh`
  (`retestReal`).
- Pruebas: sección 11 (aproximación sin toque → sin ENTRY → EXPIRED; penetración
  real → ENTRY).

### P3 — Histórico separado de los setups vivos  🟠
**Antes:** las flechas se dibujaban desde el array de setups vivos, limitado a 32;
con más de 32 setups, las señales antiguas desaparecían.
**Ahora:** registro histórico independiente `m_signals[]` (estructura `SBISignal`)
que conserva **todas** las señales BREAKOUT/RETEST/ENTRY de la ventana procesada.
Los buffers de flechas se llenan desde ese histórico, no desde los setups vivos.
El cap de 32 sigue aplicando **solo** a la memoria de estado viva. **No** es un
`32 → N` arbitrario: son dos estructuras distintas.
- Ficheros: `BI_Engine.mqh` (`SBISignal`, `AppendSignal`, `SignalCount/At`),
  `BreakoutIntelligence.mq5` (`FillBuffers` desde señales), `BI_Render.mqh`
  (última señal desde el histórico).
- Pruebas: sección 13 (>32 setups; todas las entradas se conservan).

### P4 — Puntuación normalizada sobre filtros activos  🟠
**Antes:** un filtro desactivado (p.ej. sesión OFF) recibía puntos neutros (5/5),
inflando el score.
**Ahora:** cada componente aporta al numerador **y al denominador** solo si está
activo y su dato es utilizable. `score = round(100 · ganado / máximo_activo)`.
Con todos los filtros activos y setup confirmado, el máximo es 100
(compatibilidad). Sesión OFF ya no suma: el denominador baja a 95 y el resto
puntúa igual. En la ruptura, retesteo y confirmación aún no cuentan.
- Ficheros: `BI_Engine.mqh` (`RecalcScore`, componentes `Score*`), `BI_Types.mqh`
  (`scoreMax`).
- Pruebas: sección 10 (máximo 100; sesión OFF → denominador 95; ruptura → 70).

### P5 — Sesiones en horario de servidor, sin shift ni DST ambiguo  🟠
**Antes:** horas fijas + un `InpSessionShiftHours` ambiguo que podía desplazarse
con el horario de verano.
**Ahora:** el usuario define horas de **inicio/fin por sesión en horario del
servidor** (`InpLondonStart/End`, `InpNewYorkStart/End`, personalizada). Hasta
**dos ventanas** simultáneas (LDN_NY). Sin conversión a UTC ni suposición de DST:
si el broker cambia de offset, el usuario ajusta las horas. Se eliminó
`InpSessionShiftHours` y `BI_ResolveSessionHours`.
- Ficheros: `BI_Profile.mqh` (`BI_ResolveSessions`), `BI_Utils.mqh`
  (`BI_InWindows`), `BI_Engine.mqh` (`InSession`), `BreakoutIntelligence.mq5`.
- Pruebas: sección 14 (dos ventanas, solape, cruce de medianoche).

### P6 — Volumen etiquetado como TICK  🟠
**Ahora:** el panel muestra `Volumen: TICK (del broker, no de mercado)` o
`REAL` según el origen, en lugar del ambiguo «disponible».
- Ficheros: `BI_Engine.mqh` (`m_volIsTick`, `VolumeIsTick`), `BI_Render.mqh`.

### P7 — Rechazo / pin bar sin exigir color de cuerpo  🟠
**Antes:** el rechazo exigía cuerpo del color de la dirección (`dirBody>0`).
**Ahora:** el rechazo se basa en **mecha del lado del nivel + posición del cierre
(loc≥0.60) + cierre del lado roto**, sin exigir color de cuerpo. Un martillo con
cuerpo ligeramente contrario pero mecha inferior dominante es válido.
- Ficheros: `BI_Engine.mqh` (`IsConfirmation`).

### P8 — Validación de SL/TP  🟠
**Ahora:** antes de presentar SL/TP se valida: riesgo > 0, SL en el lado correcto,
distancia ≥ máx(tick, 0.10·ATR, `SYMBOL_TRADE_STOPS_LEVEL`), redondeo al **tick
size** real, y TP en la dirección correcta. Si algo falla, `slValid=false` y **no**
se muestra SL/TP (la alerta lo omite).
- Ficheros: `BI_Engine.mqh` (`ComputeStops`), `BI_Types.mqh` (`slValid`).
- Pruebas: sección 15 (lado equivocado, riesgo mínimo, stops level).

### P9 — Seguridad del proyecto  🚨
`index.html` y `server.js` del repositorio original `web.whatsApp.io` son una
**página de phishing** (formulario a `phishing-page.com`, servidor que registra
teléfono/código). **No** forman parte de este indicador (que vive bajo `mql5/`),
**no** se ejecutan y **no** se incluyen en el repositorio del indicador (FMT5).

### P10 — Pruebas ampliadas
Verificador estático `tools/mql5_lint.py`: 10 comprobaciones (incluida prueba
negativa: detecta fallos inyectados). Modelo lógico `tools/logic_model_test.py`:
**64 comprobaciones** en 15 bloques, con casos nuevos para H1/M15, retest estricto,
aproximación sin toque, histórico >32, score con sesión OFF, sesiones de dos
ventanas, tick volume y SL inválido.

### Pendiente de verificar en MT5 real (no cubierto por estas pruebas)
Compilación en MetaEditor; `CopyRates`/`CopyBuffer` reales; alineación H4/H1/M15
con datos del broker; volumen; sesiones sobre el reloj real del servidor; objetos
gráficos; notificaciones push; no-repintado en vivo; rendimiento.
