#!/usr/bin/env python3
"""
Banco de pruebas de la LOGICA de Breakout Intelligence MT5.

IMPORTANTE: esto NO prueba el binario MQL5. Es una transcripcion fiel, en
Python, de dos piezas del motor -- el detector de rango (BI_DetectRange) y la
maquina de estados de los setups (UpdateSetups / DetectBreakouts) -- ejecutada
sobre series sinteticas para verificar:

  * que el detector de rango acepta consolidaciones y rechaza tendencias,
  * que la secuencia ruptura -> retesteo -> confirmacion se produce,
  * que un falso breakout se invalida,
  * que una ruptura sin retesteo caduca,
  * que ningun setup emite dos veces el mismo evento,
  * que ninguna decision de la vela k usa datos de velas posteriores a k.

Si se cambian las reglas del .mqh hay que cambiarlas tambien aqui.
"""
import random
from collections import namedtuple

Bar = namedtuple('Bar', 'o h l c')

# ---------------------------------------------------------------- utilidades
def atr_series(bars, period=14):
    trs, out = [], []
    for i, b in enumerate(bars):
        if i == 0:
            tr = b.h - b.l
        else:
            pc = bars[i-1].c
            tr = max(b.h - b.l, abs(b.h - pc), abs(b.l - pc))
        trs.append(tr)
        out.append(sum(trs[-period:]) / period if len(trs) >= period else 0.0)
    return out

# ------------------------------------------------- BI_DetectRange (transcrito)
def detect_range(bars, k, min_bars, max_bars, atr, max_width_atr,
                 touch_atr, max_drift, min_touches_side):
    if atr <= 0 or k < min_bars - 1:
        return None
    max_width = max_width_atr * atr
    hi, lo = bars[k].h, bars[k].l
    best = None
    for m in range(1, max_bars + 1):
        idx = k - m + 1
        if idx < 0:
            break
        hi = max(hi, bars[idx].h)
        lo = min(lo, bars[idx].l)
        if m < min_bars:
            continue
        if (hi - lo) > max_width:
            break
        best = (hi, lo, m)
    if best is None:
        return None
    bhi, blo, bbars = best
    width = bhi - blo
    if width <= 0:
        return None
    tol = touch_atr * atr
    th = sum(1 for m in range(bbars) if bars[k-m].h >= bhi - tol)
    tl = sum(1 for m in range(bbars) if bars[k-m].l <= blo + tol)
    if th < min_touches_side or tl < min_touches_side:
        return None
    first = k - bbars + 1
    q = max(3, bbars // 5)
    avg_first = sum(bars[first + m].c for m in range(q)) / q
    avg_last = sum(bars[k - m].c for m in range(q)) / q
    if abs(avg_last - avg_first) / width > max_drift:
        return None
    return (bhi, blo, bbars)

# ------------------------------------- maquina de estados (UpdateSetups, etc.)
P = dict(break_margin_atr=0.25, min_body=0.50, min_close_loc=0.60,
         min_bar_range_atr=0.50, pre_break=3, approach_max_atr=3.0,
         retest_tol_atr=0.35, reentry_atr=0.10, retest_max=12,
         confirm_max=8, pin_wick=0.50)

class Setup:
    _n = 0
    def __init__(self, level, edge, d, k):
        Setup._n += 1
        self.id = Setup._n
        self.level, self.edge, self.dir, self.break_idx = level, edge, d, k
        self.state = 'BREAKOUT'
        self.retest_idx = -1
        self.retest_ext = None
        self.touched = False
        self.confirm_idx = -1
        self.events = []

def is_confirmation(bars, k, s):
    d, edge = s.dir, s.edge
    rng = bars[k].h - bars[k].l
    if rng <= 0 or d * (bars[k].c - edge) <= 0:
        return None
    margin = P['break_margin_atr'] * atr[k]
    dir_body = d * (bars[k].c - bars[k].o)
    body = abs(bars[k].c - bars[k].o)
    prev_body = abs(bars[k-1].c - bars[k-1].o)
    frm = s.retest_idx if s.retest_idx >= 0 else s.break_idx
    ref = bars[frm].h if d > 0 else bars[frm].l
    for q in range(frm, k):
        ref = max(ref, bars[q].h) if d > 0 else min(ref, bars[q].l)
    if dir_body > 0 and d * (bars[k].c - ref) > 0 and d * (bars[k].c - edge) >= margin:
        return 'CONTINUATION'
    if (dir_body > 0 and d * (bars[k-1].c - bars[k-1].o) < 0
            and d * (bars[k].c - bars[k-1].o) >= 0
            and d * (bars[k].o - bars[k-1].c) <= 0 and body > prev_body):
        return 'ENGULFING'
    wick = (min(bars[k].o, bars[k].c) - bars[k].l) if d > 0 else \
           (bars[k].h - max(bars[k].o, bars[k].c))
    loc = ((bars[k].c - bars[k].l) / rng) if d > 0 else ((bars[k].h - bars[k].c) / rng)
    if dir_body > 0 and wick >= P['pin_wick'] * rng and loc >= 0.60:
        return 'REJECTION'
    if s.retest_idx >= 0:
        brk_ext = bars[s.break_idx].l if d > 0 else bars[s.break_idx].h
        brk_edge = bars[s.break_idx].h if d > 0 else bars[s.break_idx].l
        if d * (s.retest_ext - brk_ext) > 0 and d * (bars[k].c - brk_edge) > 0:
            return 'STRUCTURE'
    return None

def run(bars, levels, start=20):
    """levels: lista de dicts {price, broken_dir}. Devuelve (setups, eventos)."""
    global atr
    atr = atr_series(bars)
    setups, events = [], []
    for k in range(start, len(bars) - 1):          # solo velas CERRADAS
        a = atr[k]
        if a <= 0:
            continue
        margin = P['break_margin_atr'] * a
        reentry, tol = P['reentry_atr'] * a, P['retest_tol_atr'] * a

        # ---- actualizacion de setups vivos
        for s in setups:
            if s.state not in ('BREAKOUT', 'RETEST') or s.break_idx >= k:
                continue
            d, edge = s.dir, s.edge
            ext = bars[k].l if d > 0 else bars[k].h
            if d * (bars[k].c - edge) < -reentry:
                s.state = 'INVALIDATED'
                s.level['broken_dir'] = 0
                s.events.append(('INVALIDATED', k)); events.append((s.id, 'INVALIDATED', k))
                continue
            if s.state == 'BREAKOUT':
                if d * (ext - edge) <= tol:
                    s.state, s.retest_idx, s.retest_ext = 'RETEST', k, ext
                    s.touched = (d * (ext - edge) <= 0)
                    s.events.append(('RETEST', k)); events.append((s.id, 'RETEST', k))
                elif k - s.break_idx >= P['retest_max']:
                    s.state = 'EXPIRED'
                    s.events.append(('EXPIRED', k)); events.append((s.id, 'EXPIRED', k))
                continue
            if d * (ext - s.retest_ext) < 0:
                s.retest_ext = ext
            if not s.touched and d * (ext - edge) <= 0:
                s.touched = True
            ck = is_confirmation(bars, k, s) if k > s.retest_idx else None
            if ck:
                s.state, s.confirm_idx = 'CONFIRMED', k
                s.events.append(('ENTRY', k)); events.append((s.id, 'ENTRY', k))
            elif k - s.retest_idx >= P['confirm_max']:
                s.state = 'EXPIRED'
                s.events.append(('EXPIRED', k)); events.append((s.id, 'EXPIRED', k))

        # ---- deteccion de rupturas
        rng = bars[k].h - bars[k].l
        if rng <= 0:
            continue
        body = bars[k].c - bars[k].o
        for d in (1, -1):
            db = d * body
            if db <= 0 or db / rng < P['min_body']:
                continue
            loc = ((bars[k].c - bars[k].l) / rng) if d > 0 else ((bars[k].h - bars[k].c) / rng)
            if loc < P['min_close_loc']:
                continue
            for lv in levels:
                if lv['broken_dir'] != 0:
                    continue
                edge = lv['price']
                excess = d * (bars[k].c - edge)
                if excess <= margin:
                    continue
                if rng < P['min_bar_range_atr'] * a and excess < 1.5 * margin:
                    continue
                if any(d * (bars[k-q].c - edge) > 0 for q in range(1, P['pre_break'] + 1)):
                    continue
                if d * (edge - bars[k-1].c) > P['approach_max_atr'] * a:
                    continue
                if any(s.level is lv and s.dir == d and s.state in ('BREAKOUT', 'RETEST')
                       for s in setups):
                    continue
                s = Setup(lv, edge, d, k)
                lv['broken_dir'] = d
                setups.append(s)
                s.events.append(('BREAKOUT', k)); events.append((s.id, 'BREAKOUT', k))
                break
    return setups, events

# --------------------------------------------------------------- escenarios
def make_range(n=60, lo=100.0, hi=101.0, seed=1):
    rnd = random.Random(seed)
    bars = []
    for i in range(n):
        c = rnd.uniform(lo + 0.05, hi - 0.05)
        o = rnd.uniform(lo + 0.05, hi - 0.05)
        # toques periodicos de ambos bordes
        h = hi if i % 7 == 0 else max(o, c) + rnd.uniform(0.02, 0.15)
        l = lo if i % 5 == 0 else min(o, c) - rnd.uniform(0.02, 0.15)
        bars.append(Bar(o, min(h, hi), max(l, lo), c))
    return bars

def bar(o, h, l, c):
    return Bar(o, h, l, c)

FAIL = []
def check(name, cond, detail=""):
    print(("  OK   " if cond else "  FALLO") + "  " + name + ("  " + detail if detail else ""))
    if not cond:
        FAIL.append(name)

print("1) Detector de rango")
bars = make_range()
a = atr_series(bars)
r = detect_range(bars, len(bars) - 2, 12, 120, a[len(bars)-2], 3.0, 0.20, 0.55, 2)
check("acepta una consolidacion", r is not None and abs(r[0]-101.0) < 1e-9 and abs(r[1]-100.0) < 1e-9,
      str(r))
trend = [Bar(100+i*0.2, 100+i*0.2+0.15, 100+i*0.2-0.05, 100+i*0.2+0.1) for i in range(60)]
at = atr_series(trend)
rt = detect_range(trend, len(trend)-2, 12, 120, at[len(trend)-2], 3.0, 0.20, 0.55, 2)
check("rechaza una tendencia limpia", rt is None, str(rt))

print("2) Ruptura + retesteo + confirmacion")
bars = make_range()
bars += [bar(100.9, 101.75, 100.85, 101.70),   # ruptura con cuerpo grande
         bar(101.70, 101.75, 101.10, 101.20),  # retroceso a la zona
         bar(101.20, 101.28, 101.02, 101.25),  # retesteo profundo
         bar(101.25, 101.95, 101.20, 101.90),  # continuacion
         bar(101.90, 102.10, 101.85, 102.00)]
lv = [dict(price=101.0, broken_dir=0)]
setups, events = run(bars, lv)
seq = [e[1] for e in events]
check("secuencia BREAKOUT->RETEST->ENTRY", seq[:3] == ['BREAKOUT', 'RETEST', 'ENTRY'], str(seq))
check("un unico setup generado", len(setups) == 1, str(len(setups)))

print("3) Falso breakout")
bars = make_range()
bars += [bar(100.9, 101.75, 100.85, 101.70),   # ruptura
         bar(101.70, 101.72, 100.70, 100.75),  # vuelve a cerrar dentro
         bar(100.75, 100.95, 100.60, 100.80)]
lv = [dict(price=101.0, broken_dir=0)]
setups, events = run(bars, lv)
seq = [e[1] for e in events]
check("ruptura seguida de invalidacion", seq[:2] == ['BREAKOUT', 'INVALIDATED'], str(seq))
check("el nivel vuelve a quedar operativo", lv[0]['broken_dir'] == 0)

print("4) Ruptura sin retesteo -> caducidad")
bars = make_range()
bars += [bar(100.9, 101.75, 100.85, 101.70)]
p = 101.70
for i in range(16):                            # se aleja sin volver nunca
    p += 0.25
    bars.append(bar(p-0.2, p+0.05, p-0.25, p))
lv = [dict(price=101.0, broken_dir=0)]
setups, events = run(bars, lv)
seq = [e[1] for e in events]
check("ruptura seguida de caducidad", seq[:2] == ['BREAKOUT', 'EXPIRED'], str(seq))

print("5) Invariantes sobre 200 series aleatorias")
dup = no_break = late = 0
total_ev = 0
for seed in range(200):
    rnd = random.Random(seed)
    bars, p = [], 100.0
    for i in range(300):
        p += rnd.gauss(0, 0.12)
        o = p + rnd.gauss(0, 0.05)
        c = p + rnd.gauss(0, 0.05)
        bars.append(bar(o, max(o, c) + abs(rnd.gauss(0, 0.06)),
                        min(o, c) - abs(rnd.gauss(0, 0.06)), c))
    lv = [dict(price=100.0 + j * 0.5, broken_dir=0) for j in range(-6, 7)]
    setups, events = run(bars, lv)
    total_ev += len(events)
    for s in setups:
        kinds = [e[0] for e in s.events]
        if len(kinds) != len(set(kinds)):
            dup += 1
        if kinds and kinds[0] != 'BREAKOUT':
            no_break += 1
        idxs = [e[1] for e in s.events]
        if idxs != sorted(idxs):
            late += 1
check("ningun setup repite un evento", dup == 0, "setups con repeticion: %d" % dup)
check("todo setup empieza por BREAKOUT", no_break == 0, "anomalos: %d" % no_break)
check("los eventos van en orden temporal", late == 0, "anomalos: %d" % late)
check("el motor genera senales (no esta muerto)", total_ev > 100, "eventos: %d" % total_ev)

print("6) Ausencia de look-ahead")
# Recorrer el historico completo debe dar el mismo resultado que recorrerlo
# truncado en cada punto: la decision de la vela k no puede depender de k+1.
bars = make_range(120, seed=7)
bars += [bar(100.9, 101.75, 100.85, 101.70), bar(101.70, 101.75, 101.10, 101.20),
         bar(101.20, 101.28, 101.02, 101.25), bar(101.25, 101.95, 101.20, 101.90),
         bar(101.90, 102.10, 101.85, 102.00), bar(102.00, 102.30, 101.95, 102.25)]
Setup._n = 0
full = run(bars, [dict(price=101.0, broken_dir=0)])[1]
stable = True
for cut in range(len(bars) - 8, len(bars) + 1):
    Setup._n = 0
    partial = run(bars[:cut], [dict(price=101.0, broken_dir=0)])[1]
    # todo evento del recorrido truncado debe aparecer igual en el completo
    if partial != [e for e in full if e[2] <= cut - 2]:
        stable = False
check("el historico truncado reproduce el completo", stable)

print()
print("=" * 60)
print("FALLOS: %d" % len(FAIL) + ("" if not FAIL else "  -> " + ", ".join(FAIL)))
raise SystemExit(1 if FAIL else 0)
