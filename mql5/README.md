# Breakout Intelligence MT5 v1.00

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

```
<Terminal MT5>/MQL5/Indicators/BreakoutIntelligence/BreakoutIntelligence.mq5
<Terminal MT5>/MQL5/Include/BreakoutIntelligence/BI_*.mqh
```

Abre el `.mq5` en MetaEditor y pulsa **F7**. La ruta de `Include` es obligatoria:
los `#include` usan `<BreakoutIntelligence/BI_*.mqh>`.

---

## Uso recomendado

| Timeframe | Papel |
|---|---|
| H4 | Contexto (`InpContextTF`) |
| H1 | Zonas y estructura principal |
| M15 | Gráfico de trabajo: ruptura, retesteo y confirmación |
| M5 | Opcional, para afinar |

Configuración de partida: abrir en **M15** con `InpContextTF = PERIOD_H4` y dejar
en `0` todos los parámetros marcados «(0=perfil)» para que el indicador use los
valores del activo detectado.

---

## Parámetros que más importan

| Input | Efecto |
|---|---|
| `InpProfile` | `AUTO` detecta metales / cripto / índices / forex por el nombre del símbolo |
| `InpBreakMarginATR` | Cuánto debe cerrar el precio más allá de la zona. Subirlo = menos señales, más exigentes |
| `InpMinBodyRatio` | Cuerpo mínimo de la vela de ruptura. Es el filtro anti-mecha |
| `InpRequireRetest` | `true` exige retesteo antes de confirmar (recomendado) |
| `InpMinScoreAlert` | Score mínimo para lanzar la alerta de entrada |
| `InpEmaHardFilter` | Si es `true`, veta las rupturas contra la EMA de contexto |
| `InpSessionShiftHours` | Ajuste del horario del servidor del broker respecto a GMT |

Cualquier parámetro numérico a `0` toma el valor por defecto del perfil del
activo. Cualquier otro valor sobrescribe el perfil.

---

## Puntuación

El *score* 0–100 es una **clasificación interna según los filtros**, no una
probabilidad de acierto. Un 90 no significa 90 % de aciertos.

A ≥ 80 · B 65–79 · C 50–64 · D < 50. Desglose completo en
[`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md).

---

## Documentación

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
