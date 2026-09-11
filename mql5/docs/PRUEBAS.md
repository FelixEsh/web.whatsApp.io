# Estado de verificación y plan de pruebas

## 1. Qué se ha verificado y qué no

**No he compilado este código.** El entorno donde se ha desarrollado es Linux sin
MetaEditor ni Wine, así que no existe compilador MQL5 disponible. Lo digo de
forma explícita porque el estado de verificación cambia lo que puedes dar por
bueno.

Lo que **sí** se ha comprobado de forma automática:

| Comprobación | Herramienta | Resultado |
|---|---|---|
| Equilibrio de llaves, paréntesis y corchetes | `tools/mql5_lint.py` | 0 errores |
| Toda función invocada existe en MQL5 o en el proyecto (detecta APIs inventadas) | `tools/mql5_lint.py` | 0 errores |
| Toda constante usada existe | `tools/mql5_lint.py` | 0 errores |
| Métodos declarados ↔ métodos definidos en las 4 clases | `tools/mql5_lint.py` | 0 errores |
| Campos de estructura inexistentes | `tools/mql5_lint.py` | 0 errores |
| `indicator_buffers` ↔ número de `SetIndexBuffer` ↔ `indicator_plots` | `tools/mql5_lint.py` | 0 errores |
| Detector de rango acepta consolidaciones y rechaza tendencias | `tools/logic_model_test.py` | OK |
| Secuencia ruptura → retesteo → confirmación | `tools/logic_model_test.py` | OK |
| Falso breakout se invalida y devuelve el nivel al estado operativo | `tools/logic_model_test.py` | OK |
| Ruptura sin retesteo caduca | `tools/logic_model_test.py` | OK |
| Ningún setup emite dos veces el mismo evento (200 series aleatorias) | `tools/logic_model_test.py` | OK |
| Todo setup empieza por RUPTURA y los eventos van en orden temporal | `tools/logic_model_test.py` | OK |
| El histórico truncado reproduce el completo (ausencia de look-ahead) | `tools/logic_model_test.py` | OK |

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

1. Copia el contenido de `mql5/Indicators/` en `<Terminal>/MQL5/Indicators/` y el
   de `mql5/Include/` en `<Terminal>/MQL5/Include/`. La estructura debe quedar:

```
MQL5/Indicators/BreakoutIntelligence/BreakoutIntelligence.mq5
MQL5/Include/BreakoutIntelligence/BI_Types.mqh
MQL5/Include/BreakoutIntelligence/BI_Utils.mqh
MQL5/Include/BreakoutIntelligence/BI_Profile.mqh
MQL5/Include/BreakoutIntelligence/BI_Levels.mqh
MQL5/Include/BreakoutIntelligence/BI_Engine.mqh
MQL5/Include/BreakoutIntelligence/BI_Alerts.mqh
MQL5/Include/BreakoutIntelligence/BI_Render.mqh
```

   La ruta de `Include` importa: los `#include` usan
   `<BreakoutIntelligence/BI_*.mqh>`.

2. Abre `BreakoutIntelligence.mq5` en MetaEditor y pulsa **F7**.
3. Si aparece algún error, pásamelo literalmente con el número de línea. Los
   puntos más probables de fallo, por orden, son:
   - `input group` (requiere build razonablemente moderno del terminal),
   - métodos `const` de las clases,
   - los códigos Wingdings de las flechas (son estéticos, no funcionales).

---

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
