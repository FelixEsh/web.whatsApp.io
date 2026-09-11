# Breakout Intelligence MT5 v1.11

Indicador de MetaTrader 5 para detectar rupturas de rangos y niveles relevantes,
filtrar las rupturas débiles y avisar cuando aparece una configuración que cumple
un conjunto de reglas definidas y verificables.

```
Rango → Ruptura → Validación → Retesteo → Confirmación → Alerta
```

**No abre operaciones.** Es una herramienta de análisis y alertas para operativa
manual.

---

## Los tres niveles de señal

| Nivel | Estado | Significado |
|---|---|---|
| 1 · VIGILANCIA | — | El precio se aproxima a una zona relevante |
| 2 · RUPTURA | `BREAKOUT` | Cierre validado fuera de la zona. Aún **no** es una entrada |
| 3 · SETUP | `CONFIRMED` | Ruptura + retesteo + confirmación + filtros. Revisa riesgo antes de operar |

Un setup puede además quedar **INVALIDADO** (el precio vuelve a cerrar dentro) o
**CADUCADO** (el retesteo o la confirmación no llegan a tiempo).

---

## Instalación

Los 8 ficheros van **en la misma carpeta**. No hay que tocar `MQL5\Include`:
los `#include` son relativos al fichero, así que todo se resuelve dentro de la
propia carpeta del indicador.

1. En MetaTrader 5: **Archivo → Abrir carpeta de datos**.
   Esto es importante: MT5 **no** usa la carpeta de `Archivos de programa`, sino
   una carpeta de datos en `AppData`. Copiar ahí es el error de instalación más
   frecuente.
2. Entra en `MQL5\Indicators\` y crea la carpeta `BreakoutIntelligence`.
3. Copia dentro los 8 ficheros:

```
MQL5/Indicators/BreakoutIntelligence/
├── BreakoutIntelligence.mq5   <- este es el que se compila
├── BI_Types.mqh
├── BI_Utils.mqh
├── BI_Profile.mqh
├── BI_Levels.mqh
├── BI_Engine.mqh
├── BI_Alerts.mqh
└── BI_Render.mqh
```

4. Abre `BreakoutIntelligence.mq5` en MetaEditor y pulsa **F7**.
5. En el Navegador de MT5, botón derecho → **Actualizar**, y arrastra el
   indicador al gráfico.

Si aparece `file '...' not found`, es que los `.mqh` no están junto al `.mq5`.

## Uso recomendado

| Timeframe | Papel | Input |
|---|---|---|
| H4 | Contexto de tendencia (EMA 200) | `InpContextTF` |
| H1 | Zonas y estructura | `InpStructureTF` |
| M15 | Gráfico de trabajo: ruptura, retesteo y confirmación | (gráfico) |
| M5 | Opcional, para afinar | (gráfico) |

Configuración de partida: abrir en **M15** con `InpContextTF = PERIOD_H4` y
`InpStructureTF = PERIOD_H1` (valores por defecto). Las zonas se calculan sobre H1
y se proyectan en M15 sin look-ahead. Deja en `0` los parámetros «(0=perfil)» para
que el indicador use los valores del activo detectado.

---

## Parámetros que más importan

| Input | Efecto |
|---|---|
| `InpProfile` | `AUTO` detecta metales / cripto / índices / forex por el nombre del símbolo |
| `InpBreakMarginATR` | Cuánto debe cerrar el precio más allá de la zona. Subirlo = menos señales, más exigentes |
| `InpMinBodyRatio` | Cuerpo mínimo de la vela de ruptura. Es el filtro anti-mecha |
| `InpRequireRetest` | `true` exige retesteo antes de confirmar (recomendado) |
| `InpMinScoreAlert` | Score mínimo para lanzar la alerta de entrada |
| `InpStructureTF` | Timeframe de zonas/estructura (H1). Debe ser superior al gráfico |
| `InpRequireRetest` | `true` exige penetración real de la zona antes de confirmar |
| `InpEmaHardFilter` | Si es `true`, veta las rupturas contra la EMA de contexto |
| `InpLondonStart/End`, `InpNewYorkStart/End` | Horas de sesión en **horario del servidor** |

Cualquier parámetro numérico a `0` toma el valor por defecto del perfil del
activo. Cualquier otro valor sobrescribe el perfil.

---

## Puntuación

El *score* 0–100 es una **clasificación interna según los filtros**, no una
probabilidad de acierto. Un 90 no significa 90 % de aciertos.

El score está **normalizado sobre los filtros realmente activos**: un filtro
desactivado no suma ni resta (la sesión OFF ya no infla el resultado).
A ≥ 80 · B 65–79 · C 50–64 · D < 50. Desglose completo en
[`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md).

---

## Documentación

- [`CHANGELOG.md`](CHANGELOG.md) — qué cambió en v1.10 respecto a v1.00, prioridad
  a prioridad.
- [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md) — definición numérica de cada
  concepto, política anti-repintado, anti-duplicados, perfiles y limitaciones.
- [`docs/PRUEBAS.md`](docs/PRUEBAS.md) — qué está verificado, qué no, cómo
  compilar y cómo probarlo.

## Herramientas de desarrollo

```bash
python3 tools/mql5_lint.py          # verificación estática del código MQL5
python3 tools/logic_model_test.py   # pruebas de la lógica sobre series sintéticas
```

---

## Advertencias

- El indicador **no elimina** los falsos breakouts. Filtra los que incumplen sus
  reglas; siguen existiendo rupturas que cumplen todo y fallan igualmente.
- El SL y el TP mostrados son **orientativos**, derivados de la estructura y del
  ATR. No calculan lotaje ni tienen en cuenta el contrato del símbolo.
- **El código no ha sido compilado por su autor.** Lee `docs/PRUEBAS.md` antes de
  darlo por bueno.
