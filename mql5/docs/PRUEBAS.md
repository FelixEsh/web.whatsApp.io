# Estado de verificación y plan de pruebas

## 1. Qué se ha verificado y qué no

**No he compilado este código.** El entorno donde se ha desarrollado es Linux sin
MetaEditor ni Wine, así que no existe compilador MQL5 disponible. Lo digo de
forma explícita porque el estado de verificación cambia lo que puedes dar por
bueno.

Lo que **sí** se ha comprobado de forma automática:

### Verificación estática — `tools/mql5_lint.py` (0 errores)

| # | Comprobación |
|---|---|
| 1 | Equilibrio de llaves, paréntesis y corchetes |
| 2 | Toda función invocada existe en MQL5 o en el proyecto (detecta **APIs inventadas**) |
| 3 | Toda constante usada existe |
| 4 | Métodos declarados ↔ métodos definidos en las 4 clases |
| 5 | Campos de estructura inexistentes |
| 6 | `indicator_buffers` ↔ nº de `SetIndexBuffer` ↔ `indicator_plots` |
| 7 | `const` y parámetros coinciden entre declaración y definición (un desajuste **es** error de compilación en MQL5) |
| 8 | Ninguna función con valor de retorno puede terminar sin `return` |
| 9 | `MathMax`/`MathMin` (devuelven `double`) no alimentan un `int` |
| 10 | Toda estructura local usada como «constructor» rellena **todos** sus campos (un campo olvidado no es error de compilación: es basura en ejecución) |

El verificador se ha sometido a una **prueba negativa**: se inyectaron cinco
fallos en una copia del proyecto (una API inexistente, un desajuste de `const`,
una función sin `return`, un `MathMax` asignado a `int` y un campo de estructura
sin inicializar) y los detectó los cinco. Un verificador que nunca salta no
sirve de nada.

### Pruebas de lógica — `tools/logic_model_test.py` (88 comprobaciones, 0 fallos)

| Bloque | Qué comprueba |
|---|---|
| 1 · Rango | Acepta consolidaciones, rechaza tendencias limpias |
| 2 · Ciclo completo | Secuencia ruptura → retesteo → confirmación, un solo setup |
| 3 · Falso breakout | Se invalida y devuelve el nivel al estado operativo |
| 4 · Caducidad | Ruptura sin retesteo caduca |
| 5 · Invariantes | 200 series aleatorias: 0 eventos duplicados, todo setup empieza por RUPTURA, eventos en orden temporal, el motor genera señales |
| 6 · Look-ahead | El histórico truncado reproduce exactamente el completo |
| 7 · Pivotes | Máximo/mínimo aislado, una meseta da **un** pivote, el pivote solo es conocible desde `p+D` |
| 8 · Niveles | Fusiona dentro de tolerancia, no fusiona lejos, acumula toques, respeta el tope de anchura de zona, un nivel roto no absorbe toques |
| 9 · Reactivación | Tras invalidar, el mismo nivel puede volver a romperse; tras caducar, **no** |
| 10 · Puntuación | Normalizada: máximo 100 con todo activo, sesión OFF → denominador 95 (no infla), ruptura → 70, A/B/C/D sin huecos, acoplada al fuente |
| 11 · Retest estricto | Aproximación sin toque → sin ENTRY → EXPIRED; penetración real → ENTRY |
| 12 · Estructura H1→M15 | Mapeo temporal exacto sin look-ahead (pivote conocible sólo tras cerrar `sp+depth`) |
| 13 · Histórico | >32 setups: todas las entradas se conservan; buffers desde el histórico de señales |
| 14 · Sesiones | Dos ventanas en horario de servidor, solape LDN_NY, cruce de medianoche; sin shift |
| 15 · SL/TP | Rechaza lado equivocado, riesgo mínimo y distancia < stops level del broker |
| 16 · ATR H1 (Bug 1) | ATR(14) real del TF de estructura, causal; ≠ anchura de una vela |
| 17 · Registro de rango (Bug 2) | `newRange` se decide antes de actualizar `lastRHi/lastRLo` |
| 18 · Capacidad (Bug 3) | Dimensionada por histórico; conserva los niveles recientes |
| 19 · Antigüedad (Bug 4) | Elegibilidad en `knownIdx + minLevelAgeBars`, sin `firstIdx` fabricado |
| 20 · Límite de setups (Bug 5) | La ocupación de setups vivos nunca supera `maxActiveSetups` |

Ejecución:

```bash
python3 mql5/tools/mql5_lint.py
python3 mql5/tools/logic_model_test.py
```

Lo que **no** está verificado y sólo puedes confirmar tú en MetaTrader:

- Que compila sin errores ni avisos en MetaEditor.
- El comportamiento real con datos de broker (huecos, sesiones, fines de semana).
- El rendimiento en gráficos grandes.
- El aspecto visual del panel y de las flechas.

`logic_model_test.py` prueba una **transcripción en Python** de la lógica, no el
binario MQL5. Si cambias una regla en el `.mqh` tienes que cambiarla también ahí,
o la prueba dejará de significar nada.

---

## 2. Compilación

Los 8 ficheros van **en la misma carpeta**. Los `#include` son relativos
(`#include "BI_Types.mqh"`), no del sistema (`<...>`), así que **no** hay que
copiar nada en `MQL5\Include`.

1. En MetaTrader 5: **Archivo → Abrir carpeta de datos**. MT5 no usa la carpeta
   de `Archivos de programa` sino una carpeta de datos en `AppData`; copiar en
   la carpeta equivocada es el error de instalación más frecuente.
2. Crea `MQL5\Indicators\BreakoutIntelligence\` y copia dentro:

```
MQL5/Indicators/BreakoutIntelligence/
├── BreakoutIntelligence.mq5
├── BI_Types.mqh
├── BI_Utils.mqh
├── BI_Profile.mqh
├── BI_Levels.mqh
├── BI_Engine.mqh
├── BI_Alerts.mqh
└── BI_Render.mqh
```

3. Abre `BreakoutIntelligence.mq5` en MetaEditor y pulsa **F7**.

### Errores de instalación frecuentes

| Error de MetaEditor | Causa |
|---|---|
| `file 'BI_Types.mqh' not found` | Los `.mqh` no están en la misma carpeta que el `.mq5` |
| `file 'Include\BreakoutIntelligence\BI_Types.mqh' not found` | Versión antigua con includes `<...>`; usa esta, que los lleva relativos |
| `OnCalculate function not found in custom indicator` | **Cascada**: un `#include` falló y el compilador abortó antes de llegar a `OnCalculate`. Arregla el include y desaparece |
| El indicador no sale en el Navegador | Falta **Actualizar** (botón derecho en el Navegador) o se copió en la carpeta de instalación en vez de la de datos |

Si aparece algún error que no sea de instalación, pásamelo literal con su número
de línea. Los puntos más probables, por orden: `input group` (requiere un build
razonablemente moderno del terminal), los métodos `const` de las clases, y los
códigos Wingdings de las flechas (estéticos, no funcionales).

## 3. Pruebas funcionales en MetaTrader

### 3.1 Prueba de no repintado (la más importante)

1. Abre XAUUSD M15, adjunta el indicador.
2. Espera a que aparezca una flecha de setup confirmado.
3. Haz una captura de pantalla.
4. Deja pasar 20–30 velas.
5. Compara: **la flecha debe estar en la misma vela y al mismo precio**.
6. Cambia de timeframe y vuelve: la flecha debe seguir en la misma vela.

Comprobación adicional con el Probador de Estrategias en modo visual: ejecuta el
indicador y observa que ninguna flecha aparece dentro de la vela en curso, sólo
al cierre.

### 3.2 Prueba de duplicados

1. Activa todas las alertas.
2. Deja el indicador varias horas en un gráfico M15.
3. Revisa la pestaña **Expertos** del terminal: cada línea de alerta debe ser
   única. Dos líneas idénticas con la misma hora de vela son un fallo; mándamelas.

### 3.3 Prueba por activo

Repite en XAUUSD, BTCUSD, EURUSD y NAS100 (o el nombre que use tu broker). En el
panel, la línea 2 debe mostrar el perfil correcto: METALES, CRIPTO, FOREX,
ÍNDICES. Si un símbolo se clasifica mal, fuerza el perfil con `InpProfile`.

### 3.4 Prueba de coherencia con el gráfico

Elige una ruptura marcada por el indicador y compruébala a mano:

- ¿La vela de ruptura cierra realmente fuera de la zona?
- ¿El cuerpo es mayor que la mitad del recorrido de la vela?
- ¿Las velas anteriores cerraban dentro?

Si alguna respuesta es «no», hay un fallo de lógica: dime símbolo, timeframe y
hora de la vela.

### 3.5 Calibración

Si salen demasiadas señales: sube `InpBreakMarginATR`, `InpMinBodyRatio` y
`InpMinTouches`, o activa `InpEmaHardFilter`.
Si salen demasiado pocas: baja `InpBreakMarginATR`, reduce `InpMinScoreAlert`, o
prueba `InpRequireRetest = false` (más señales, de menor calidad, porque se pierden
los 20 puntos del retesteo).

Cambia **un parámetro cada vez** y anota el efecto. Cambiar cinco a la vez no
enseña nada.

---

## 4. Qué deberías observar

Con la configuración por defecto en XAUUSD M15:

- Varias líneas de nivel alrededor del precio, con etiqueta de tipo y número de toques.
- Una caja azul cuando hay una consolidación reconocida.
- Flechas pequeñas doradas en las rupturas, puntos azules en los retesteos y
  flechas grandes verdes/rojas sólo en los setups confirmados.
- Muchas más rupturas que setups confirmados. **Eso es correcto**: el filtrado
  consiste precisamente en que la mayoría de las rupturas no llegue a la fase 5.
- Si ves tantas flechas verdes como rupturas, algo va mal en el filtro: avísame.
