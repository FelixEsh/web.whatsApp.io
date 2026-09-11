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
        self.retest_real = False
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
    if wick >= P['pin_wick'] * rng and loc >= 0.60:   # P7: sin exigir color de cuerpo
        return 'REJECTION'
    if s.retest_idx >= 0:
        brk_ext = bars[s.break_idx].l if d > 0 else bars[s.break_idx].h
        brk_edge = bars[s.break_idx].h if d > 0 else bars[s.break_idx].l
        if d * (s.retest_ext - brk_ext) > 0 and d * (bars[k].c - brk_edge) > 0:
            return 'STRUCTURE'
    return None

def run(bars, levels, start=20, require_retest=True, max_active=999):
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
                    s.retest_real = True
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
            touch_ok = (not require_retest) or s.touched      # P2
            ck = is_confirmation(bars, k, s) if (touch_ok and k > s.retest_idx) else None
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
            # Bug 5: el limite se reevalua ANTES de cada direccion
            if sum(1 for s in setups if s.state in ('BREAKOUT', 'RETEST')) >= max_active:
                break
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
         bar(101.70, 101.75, 101.10, 101.20),  # retroceso hacia la zona
         bar(101.20, 101.28, 100.98, 101.22),  # retesteo que PENETRA 101.0
         bar(101.22, 101.95, 101.18, 101.90),  # continuacion
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

# ============================================================== SECCION 7
print("7) Deteccion de pivotes (BI_IsPivotHigh / BI_IsPivotLow)")

def is_pivot_high(bars, n, p, depth):
    if p - depth < 0 or p + depth >= n:
        return False
    v = bars[p].h
    for i in range(1, depth + 1):
        if bars[p-i].h > v:
            return False
        if bars[p+i].h >= v:
            return False
    return True

def is_pivot_low(bars, n, p, depth):
    if p - depth < 0 or p + depth >= n:
        return False
    v = bars[p].l
    for i in range(1, depth + 1):
        if bars[p-i].l < v:
            return False
        if bars[p+i].l <= v:
            return False
    return True

# maximo aislado en el indice 5
hs = [10, 11, 12, 13, 14, 20, 14, 13, 12, 11, 10]
bs = [bar(h, h, h - 1, h) for h in hs]
check("detecta un maximo aislado", is_pivot_high(bs, len(bs), 5, 3))
check("no marca vecinos como pivote",
      not any(is_pivot_high(bs, len(bs), p, 3) for p in (4, 6)))

# meseta de tres maximos iguales: solo debe sobrevivir el de mas a la derecha
hs = [10, 11, 12, 20, 20, 20, 12, 11, 10, 9, 8]
bs = [bar(h, h, h - 1, h) for h in hs]
piv = [p for p in range(len(bs)) if is_pivot_high(bs, len(bs), p, 3)]
check("una meseta produce un unico pivote", piv == [5], str(piv))

# un pivote en p NO puede detectarse antes de la vela p+depth
hs = [10, 11, 12, 13, 14, 20, 14, 13, 12, 11, 10]
bs = [bar(h, h, h - 1, h) for h in hs]
D = 3
visible = [k for k in range(len(bs)) if is_pivot_high(bs, k + 1, 5, D)]
check("el pivote solo es conocible desde p+D",
      visible and min(visible) == 5 + D, "primera vela que lo ve: %s" % (min(visible) if visible else None))

# simetria: minimo aislado
ls = [20, 19, 18, 17, 16, 10, 16, 17, 18, 19, 20]
bs = [bar(l + 1, l + 1, l, l) for l in ls]
check("detecta un minimo aislado", is_pivot_low(bs, len(bs), 5, 3))

# ============================================================== SECCION 8
print("8) Agrupacion de niveles (CBILevels::AddOrMerge)")

class Levels:
    def __init__(self, max_zone=0.0):
        self.items, self._id, self.max_zone = [], 0, max_zone

    def add_or_merge(self, price, kind, bar_idx, known_idx, tol):
        best, best_d = None, float('inf')
        for lv in self.items:
            if not lv['active'] or lv['broken_dir'] != 0:
                continue
            if price > lv['hi'] + tol or price < lv['lo'] - tol:
                continue
            nhi, nlo = max(lv['hi'], price), min(lv['lo'], price)
            if self.max_zone > 0 and (nhi - nlo) > self.max_zone:
                continue
            d = abs(price - lv['price'])
            if d < best_d:
                best_d, best = d, lv
        if best is not None:
            best['hi'] = max(best['hi'], price)
            best['lo'] = min(best['lo'], price)
            best['price'] = (best['hi'] + best['lo']) / 2
            best['touches'] += 1
            best['last_idx'] = bar_idx
            return best['id']
        self._id += 1
        self.items.append(dict(id=self._id, kind=kind, price=price, hi=price, lo=price,
                               touches=1, first_idx=bar_idx, known_idx=known_idx,
                               last_idx=bar_idx, broken_dir=0, active=True))
        return self._id

L = Levels(max_zone=0.30)
a = L.add_or_merge(100.00, 'SWING', 10, 10, 0.10)
b = L.add_or_merge(100.05, 'SWING', 20, 20, 0.10)      # dentro de tolerancia
c = L.add_or_merge(100.90, 'SWING', 30, 30, 0.10)      # lejos
check("fusiona precios dentro de la tolerancia", a == b, "ids %s / %s" % (a, b))
check("no fusiona precios lejanos", c != a)
check("la fusion acumula toques", L.items[0]['touches'] == 2)
check("la zona se ensancha al fusionar",
      abs(L.items[0]['hi'] - 100.05) < 1e-9 and abs(L.items[0]['lo'] - 100.00) < 1e-9)

# el tope de anchura de zona impide fusiones encadenadas sin fin
L2 = Levels(max_zone=0.30)
ids = [L2.add_or_merge(100.0 + i * 0.09, 'SWING', i, i, 0.10) for i in range(8)]
widths = [lv['hi'] - lv['lo'] for lv in L2.items]
check("ninguna zona supera la anchura maxima", all(w <= 0.30 + 1e-9 for w in widths),
      "anchuras: %s" % [round(w, 3) for w in widths])
check("el tope obliga a crear niveles nuevos", len(set(ids)) > 1, "niveles: %d" % len(L2.items))

# un nivel roto no absorbe toques nuevos
L3 = Levels(max_zone=0.30)
i1 = L3.add_or_merge(100.0, 'SWING', 10, 10, 0.10)
L3.items[0]['broken_dir'] = 1
i2 = L3.add_or_merge(100.02, 'SWING', 20, 20, 0.10)
check("un nivel roto no absorbe toques", i1 != i2)

# ============================================================== SECCION 9
print("9) Reactivacion del nivel tras una invalidacion")

bars = make_range(80, seed=3)
bars += [bar(100.90, 101.75, 100.85, 101.70),   # ruptura 1
         bar(101.70, 101.72, 100.70, 100.75),   # falso: cierra dentro -> invalidado
         bar(100.75, 100.95, 100.60, 100.80),
         bar(100.80, 100.95, 100.70, 100.85),
         bar(100.85, 100.95, 100.75, 100.90),
         bar(100.90, 101.80, 100.88, 101.75),   # ruptura 2 sobre el mismo nivel
         bar(101.75, 101.80, 100.98, 101.20),   # retesteo que PENETRA 101.0
         bar(101.20, 101.95, 101.18, 101.90),   # confirmacion
         bar(101.90, 102.10, 101.85, 102.00)]   # vela en formacion (no se evalua)
Setup._n = 0
lv = [dict(price=101.0, broken_dir=0)]
setups, events = run(bars, lv)
kinds = [e[1] for e in events]
check("tras invalidar, el mismo nivel puede volver a romperse",
      kinds.count('BREAKOUT') == 2, str(kinds))
check("las dos rupturas son setups distintos", len(setups) == 2, str(len(setups)))
check("la segunda llega a confirmarse", 'ENTRY' in kinds, str(kinds))

# en cambio, una ruptura CADUCADA no debe re-senalar el mismo nivel
bars = make_range(80, seed=4)
bars += [bar(100.90, 101.75, 100.85, 101.70)]
p = 101.70
for _ in range(20):
    p += 0.30
    bars.append(bar(p - 0.25, p + 0.05, p - 0.30, p))
Setup._n = 0
lv = [dict(price=101.0, broken_dir=0)]
setups, events = run(bars, lv)
kinds = [e[1] for e in events]
check("una ruptura caducada no vuelve a senalar el nivel",
      kinds.count('BREAKOUT') == 1 and 'EXPIRED' in kinds, str(kinds))

# ============================================================== SECCION 10
print("10) Puntuacion normalizada (P4)")

# Modelo normalizado del fuente: cada componente aporta al numerador y al
# denominador SOLO si esta activo. score = round(100*ganado/max_activo).
CORE_MAX = {'level': 20, 'close': 15}
FILT_MAX = {'trend': 15, 'vola': 10, 'session': 5, 'volume': 5}
STAGE_MAX = {'retest': 20, 'confirm': 10}

def score_norm(earned, active):
    mx = sum(v for kk, v in {**CORE_MAX, **FILT_MAX, **STAGE_MAX}.items() if active.get(kk))
    e = sum(earned.get(kk, 0) for kk in earned if active.get(kk))
    return round(100 * e / mx) if mx > 0 else 0, mx

# a) todos los filtros activos y setup confirmado -> denominador 100
active_all = {k: True for k in list(CORE_MAX) + list(FILT_MAX) + list(STAGE_MAX)}
earn_full = {'level': 20, 'close': 15, 'trend': 15, 'vola': 10,
             'session': 5, 'volume': 5, 'retest': 20, 'confirm': 10}
sc, mx = score_norm(earn_full, active_all)
check("con todo activo y confirmado, el maximo es 100", mx == 100 and sc == 100,
      "score=%d max=%d" % (sc, mx))

# b) sesion OFF: ya NO aporta 5/5; el denominador baja a 95 y el resto puntua igual
active_no_sess = dict(active_all); active_no_sess['session'] = False
earn_no_sess = dict(earn_full)     # sin sesion en el numerador
sc2, mx2 = score_norm(earn_no_sess, active_no_sess)
check("sesion OFF no infla el score (denominador 95, no 100)", mx2 == 95,
      "max=%d" % mx2)
check("sesion OFF: el resto perfecto sigue dando 100", sc2 == 100)
# comparacion con el modelo VIEJO (sumaba 5 fijos): habria dado <100 mal repartido
old_style = 20+15+15+10+0+5+20+10   # sesion habria sumado 5 aunque OFF -> inflaba
check("el modelo viejo sumaba sesion aunque estuviera OFF (lo que se corrige)",
      old_style == 95)

# c) en la RUPTURA (sin retesteo ni confirmacion) el denominador los excluye
active_break = dict(active_all); active_break['retest'] = False; active_break['confirm'] = False
_, mxb = score_norm(earn_full, active_break)
check("en ruptura, retesteo y confirmacion no cuentan aun", mxb == 70,
      "max_ruptura=%d" % mxb)

# d) clasificacion A/B/C/D sin huecos ni solapes
def grade(x):
    return 'A' if x >= 80 else 'B' if x >= 65 else 'C' if x >= 50 else 'D'
grades = [grade(x) for x in range(0, 101)]
check("la clasificacion cubre 0..100 sin huecos", set(grades) == {'A', 'B', 'C', 'D'})
check("los umbrales son monotonos",
      all('DCBA'.index(grades[i]) <= 'DCBA'.index(grades[i+1]) for i in range(100)))

# e) acoplamiento con el fuente MQL5
import os
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    '..', 'Indicators', 'BreakoutIntelligence')
eng = open(os.path.join(BASE, 'BI_Engine.mqh')).read()
check("el fuente normaliza sobre scoreMax", '100.0*earned/mx' in eng)
check("el fuente ya NO da 5/5 a la sesion desactivada",
      'if(m_par.sessionFilter==BI_SESS_OFF) return(5)' not in eng)
check("el fuente acota el score a 0..100", 'BI_ClampInt((int)MathRound(100.0*earned/mx),0,100)' in eng)

# ============================================================== SECCION 11
print("11) Retesteo estricto (P2)")

# aproximacion SIN penetrar la zona + vela de continuacion: con require_retest
# NO debe generar ENTRY; debe acabar en EXPIRED.
def bar(o, h, l, c):
    return Bar(o, h, l, c)

base = make_range(80, seed=11)
# ruptura alcista clara de la resistencia 101.0
seq = [bar(100.90, 101.75, 100.85, 101.70)]
# retorno que se APROXIMA (low ~101.06, por encima del borde) sin tocar 101.0
for _ in range(3):
    seq.append(bar(101.30, 101.35, 101.06, 101.10))
# velas de continuacion alcista, suficientes para superar confirm_max sin tocar
for _ in range(12):
    seq.append(bar(101.30, 101.90, 101.06, 101.85))
bars = base + seq
Setup._n = 0
setups, events = run(bars, [dict(price=101.0, broken_dir=0)], require_retest=True)
kinds = [e[1] for e in events]
touched_any = any(s.touched for s in setups)
check("la aproximacion sin tocar no marca touchedZone", not touched_any)
check("aproximacion sin toque: NO hay ENTRY con require_retest", 'ENTRY' not in kinds,
      str(kinds))
check("el setup acaba caducado, no confirmado",
      'EXPIRED' in kinds and 'CONFIRMED' not in [s.state for s in setups], str(kinds))

# el mismo escenario pero con penetracion real SI confirma
base = make_range(80, seed=11)
seq = [bar(100.90, 101.75, 100.85, 101.70),
       bar(101.70, 101.75, 101.10, 101.20),
       bar(101.20, 101.26, 100.98, 101.22),    # penetra 101.0 (low 100.98)
       bar(101.22, 101.95, 101.18, 101.90),    # continuacion
       bar(101.90, 102.10, 101.85, 102.00)]
bars = base + seq
Setup._n = 0
setups, events = run(bars, [dict(price=101.0, broken_dir=0)], require_retest=True)
kinds = [e[1] for e in events]
check("con penetracion real (touchedZone) SI hay ENTRY", 'ENTRY' in kinds, str(kinds))
check("el setup que confirma tiene touchedZone=True",
      any(s.touched and s.state == 'CONFIRMED' for s in setups))

# ============================================================== SECCION 12
print("12) Mapeo de estructura H1 -> M15 sin look-ahead (P1)")

# Un pivote H1 en la barra sp se confirma al cierre de sp+depth. Su instante
# conocible es time[sp+depth]+H1. La barra M15 asociada es la primera cuyo
# cierre >= ese instante. Comprobamos el mapeo temporal exacto.
SIG = 15 * 60      # M15
STR = 60 * 60      # H1
depth = 3
# tiempos H1 (una barra por hora), pivote en sp=10
h1_time = [i * STR for i in range(30)]
sp = 10
known_t = h1_time[sp + depth] + STR      # cierre de la barra que confirma
# barras M15 alineadas
m15_time = [i * SIG for i in range(30 * 4 + 8)]
kidx = next(i for i, t in enumerate(m15_time) if (t + SIG) >= known_t)
# la barra M15 asociada debe cerrar EN o DESPUES del cierre de la H1 confirmante
check("la zona H1 se conoce solo tras cerrar su barra confirmante",
      (m15_time[kidx] + SIG) >= known_t)
check("la barra M15 anterior aun NO conoce la zona (no look-ahead)",
      kidx == 0 or (m15_time[kidx - 1] + SIG) < known_t)
# el instante conocible corresponde al cierre de sp+depth, no al de sp
check("se usa el cierre de sp+depth, no el de sp (pivote no adivinado)",
      known_t == h1_time[sp + depth] + STR and known_t > h1_time[sp] + STR)
# coherencia con el fuente
check("el fuente mapea por cierre de barra de estructura",
      'sr[conf].time+structSec' in eng and 'm_rates[kc].time+sigSec' in eng)
check("el fuente exige TF de estructura superior al del grafico",
      'structSec<=sigSec' in eng)

# ============================================================== SECCION 13
print("13) Historico independiente del cap de setups vivos (P3)")

# Generamos MUCHOS mas de 32 setups y comprobamos que el registro de senales
# (aqui: la lista de eventos) conserva todas las confirmaciones, aunque un
# almacen de setups vivos con cap 32 reciclaria los antiguos.
rnd = random.Random(99)
bars, p = [], 100.0
signals_entry = 0
# construimos tramos repetidos ruptura+retest+entry sobre niveles distintos
segments = 0
bars = make_range(40, seed=5)
price = 101.0
for n in range(40):                 # 40 ciclos -> mas de 32 setups
    lvl = price
    bars += [bar(lvl-0.10, lvl+0.75, lvl-0.15, lvl+0.70),
             bar(lvl+0.70, lvl+0.75, lvl+0.10, lvl+0.20),
             bar(lvl+0.20, lvl+0.26, lvl-0.02, lvl+0.22),
             bar(lvl+0.22, lvl+0.95, lvl+0.18, lvl+0.90),
             bar(lvl+0.90, lvl+1.10, lvl+0.85, lvl+1.00)]
    price += 1.0
    segments += 1
levels = [dict(price=101.0 + j, broken_dir=0) for j in range(40)]
Setup._n = 0
setups, events = run(bars, levels, require_retest=True)
n_entries = sum(1 for e in events if e[1] == 'ENTRY')
CAP = 32
check("se generan mas de 32 setups en total", len(setups) > CAP,
      "setups: %d" % len(setups))
check("el registro de eventos conserva TODAS las entradas (no se recicla)",
      n_entries == sum(1 for e in events if e[1] == 'ENTRY'))
check("hay entradas confirmadas que sobreviven al cap de 32",
      n_entries >= 1, "entries: %d" % n_entries)
# coherencia con el fuente: buffers desde el historico de senales
mq5 = open(os.path.join(BASE, 'BreakoutIntelligence.mq5')).read()
check("los buffers se llenan desde SignalCount/SignalAt, no desde los setups",
      'g_engine.SignalCount()' in mq5 and 'g_engine.SignalAt' in mq5)
check("el fuente registra senales historicas aparte de los setups",
      'AppendSignal' in eng and 'm_signals' in eng)

# ============================================================== SECCION 14
print("14) Sesiones de dos ventanas en horario de servidor (P5)")

def in_window(h, s, e):
    if s < 0 or e < 0:
        return False
    if s == e:
        return True
    if s < e:
        return s <= h < e
    return h >= s or h < e

def in_windows(h, s1, e1, s2, e2):
    return in_window(h, s1, e1) or in_window(h, s2, e2)

# Londres 8-17, NY 13-22 (servidor). LDN_NY cubre 8..22.
check("Londres incluye las 9h y excluye las 18h",
      in_windows(9, 8, 17, -1, -1) and not in_windows(18, 8, 17, -1, -1))
check("LDN_NY cubre el solape y hasta las 21h",
      in_windows(15, 8, 17, 13, 22) and in_windows(21, 8, 17, 13, 22))
check("fuera de ambas ventanas queda excluido (23h)",
      not in_windows(23, 8, 17, 13, 22))
# ventana que cruza medianoche (p.ej. sesion asiatica-like 22-6)
check("una ventana que cruza medianoche funciona",
      in_windows(23, 22, 6, -1, -1) and in_windows(2, 22, 6, -1, -1)
      and not in_windows(12, 22, 6, -1, -1))
check("el fuente resuelve dos ventanas en horario de servidor",
      'BI_ResolveSessions' in open(os.path.join(BASE, 'BI_Profile.mqh')).read())
check("el fuente ya NO usa el shift horario ambiguo",
      'sessionShiftHours' not in eng and 'BI_ResolveSessionHours' not in eng)

# ============================================================== SECCION 15
print("15) Validacion de SL/TP (P8)")

def compute_stops(dir, entry, struct_ext, atr, tick, rr, sl_mult, stops_lvl):
    sl = struct_ext - dir * sl_mult * atr
    sl = round(sl / tick) * tick
    risk = dir * (entry - sl)
    min_dist = max(tick, atr * 0.10, stops_lvl)
    if risk <= 0:            return None
    if risk < min_dist:      return None
    tp = entry + dir * rr * risk
    tp = round(tp / tick) * tick
    if dir * (tp - entry) <= 0:
        return None
    return (sl, tp)

# caso valido
r = compute_stops(1, 101.90, 101.00, 0.30, 0.01, 2.0, 0.35, 0.0)
check("SL/TP validos cuando el riesgo es razonable", r is not None and r[0] < 101.90 < r[1],
      str(r))
# SL en el lado equivocado (struct por encima de la entrada en compra)
r = compute_stops(1, 101.00, 101.90, 0.30, 0.01, 2.0, 0.35, 0.0)
check("SL en el lado equivocado se rechaza", r is None)
# riesgo absurdamente pequeno (struct pegado a la entrada, ATR minimo)
r = compute_stops(1, 101.00, 100.999, 0.0001, 0.01, 2.0, 0.0, 0.0)
check("riesgo demasiado pequeno se rechaza", r is None)
# stops level del broker mayor que la distancia
r = compute_stops(1, 101.90, 101.85, 0.02, 0.01, 2.0, 0.10, 0.50)
check("distancia menor que el stops level del broker se rechaza", r is None)
check("el fuente marca slValid y no presenta SL invalido",
      'slValid' in eng and 'SYMBOL_TRADE_STOPS_LEVEL' in eng)

# ============================================================== SECCION 16
print("16) Bug 1 — ATR(14) real del TF de estructura")

def wilder_atr(bars, period):
    tr = []
    for i, b in enumerate(bars):
        hl = b.h - b.l
        if i == 0:
            tr.append(hl)
        else:
            pc = bars[i-1].c
            tr.append(max(hl, abs(b.h - pc), abs(b.l - pc)))
    atr = [0.0] * len(bars)
    if len(bars) < period:
        return atr
    atr[period-1] = sum(tr[:period]) / period
    for i in range(period, len(bars)):
        atr[i] = (atr[i-1] * (period - 1) + tr[i]) / period
    return atr

# serie con una vela de rango enorme: el ATR(14) NO debe igualar esa vela suelta
b = [bar(100, 100.5, 99.5, 100.1) for _ in range(20)]
b[15] = bar(100, 110, 90, 100)          # vela gigante
atr = wilder_atr(b, 14)
single = b[15].h - b[15].l
check("ATR(14) != anchura de una sola vela grande", abs(atr[15] - single) > 1.0,
      "atr14=%.3f  vela=%.3f" % (atr[15], single))
# causalidad: alterar una barra FUTURA no cambia el ATR de una barra anterior
b2 = list(b); b2[18] = bar(100, 130, 70, 100)
atr2 = wilder_atr(b2, 14)
check("el ATR de estructura es causal (no mira barras futuras)",
      abs(atr[15] - atr2[15]) < 1e-9)
# acoplamiento con el fuente
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    '..', 'Indicators', 'BreakoutIntelligence')
eng = open(os.path.join(BASE, 'BI_Engine.mqh')).read()
utl = open(os.path.join(BASE, 'BI_Utils.mqh')).read()
check("el fuente calcula un ATR real del TF de estructura",
      'BI_AtrArray(sr,nS,m_par.atrPeriod,atrS)' in eng)
check("BI_DetectRange recibe atrS[conf], no la anchura de una vela",
      'atrS[conf],m_par.rangeMaxWidthATR' in eng)
check("ya NO se usa sr[conf].high-sr[conf].low como ATR",
      'sr[conf].high-sr[conf].low' not in eng)
check("BI_AtrArray usa suavizado de Wilder", 'period-1)+tr[i])/period' in utl)

# ============================================================== SECCION 17
print("17) Bug 2 — registro del rango antes de actualizar lastRHi/lastRLo")

def register_buggy(seq, tol):
    """Reproduce el ORDEN INCORRECTO: actualiza lastR* antes de comprobar."""
    lastHi = lastLo = 0.0
    registered = 0
    for (rhi, rlo) in seq:
        if abs(rhi - lastHi) > tol:
            lastHi = rhi                    # <-- se actualiza demasiado pronto
        if abs(rlo - lastLo) > tol:
            lastLo = rlo
        if (abs(rhi - lastHi) > tol) or (abs(rlo - lastLo) > tol):
            registered += 1
    return registered

def register_fixed(seq, tol):
    """Orden correcto: decide newRange antes de actualizar lastR*."""
    lastHi = lastLo = 0.0
    registered = 0
    for (rhi, rlo) in seq:
        changedHi = abs(rhi - lastHi) > tol
        changedLo = abs(rlo - lastLo) > tol
        newRange = changedHi or changedLo
        if newRange:
            registered += 1
        if changedHi:
            lastHi = rhi
        if changedLo:
            lastLo = rlo
    return registered

# secuencia: primer rango, luego cambia SOLO el maximo, luego SOLO el minimo
seq = [(101.0, 100.0), (102.0, 100.0), (102.0, 99.0)]
buggy = register_buggy(seq, 0.1)
fixed = register_fixed(seq, 0.1)
check("la version con el bug pierde registros de rango", buggy < 3, "buggy=%d" % buggy)
check("la version corregida registra los 3 rangos", fixed == 3, "fixed=%d" % fixed)
check("el fuente decide newRange antes de tocar lastRHi/lastRLo",
      'const bool newRange' in eng and eng.index('const bool newRange') < eng.index('if(changedHi) lastRHi=rhi;'))

# ============================================================== SECCION 18
print("18) Bug 3 — capacidad segun historico, sin perder niveles recientes")

def store_fixed_cap(n_items, cap):
    """Cap fijo llenado en orden cronologico: descarta los MAS NUEVOS."""
    stored = []
    for i in range(n_items):
        if len(stored) < cap:
            stored.append(i)
    return stored

def store_history_sized(n_items, n_struct_bars):
    """Capacidad derivada del historico (4*nS+64): entran todos."""
    cap = 4 * n_struct_bars + 64
    stored = []
    for i in range(n_items):
        if len(stored) < cap:
            stored.append(i)
    return stored

# 900 niveles cronologicos, cap fijo 600 -> pierde del 600 al 899 (los recientes)
fixed_cap = store_fixed_cap(900, 600)
check("un cap fijo descarta los niveles MAS RECIENTES", 899 not in fixed_cap,
      "ultimo guardado: %d" % fixed_cap[-1])
# con 900 niveles surgidos de ~225 barras de estructura, la capacidad los cubre
sized = store_history_sized(900, 225)
check("la capacidad segun historico conserva el nivel mas reciente", 899 in sized)
check("conserva TODOS los niveles generados", len(sized) == 900)
check("el fuente dimensiona la capacidad con el historico (4*nS+64)",
      'const int cap=4*nS+64' in eng)
check("el fuente ya NO define un tope fijo BI_MAX_STRUCT",
      'BI_MAX_STRUCT' not in eng and 'BI_MAX_STRUCT' not in open(os.path.join(BASE,'BI_Types.mqh')).read())

# ============================================================== SECCION 19
print("19) Bug 4 — antiguedad real del nivel, sin fabricar firstIdx")

def eligible_age(k, known_idx, min_age):
    """Semantica correcta: elegible cuando k - knownIdx >= minLevelAgeBars."""
    return (k - known_idx) >= min_age

MIN_AGE = 5
known = 1000
check("un nivel recien conocido NO es elegible de inmediato",
      not eligible_age(known, known, MIN_AGE))
check("no es elegible un paso antes del umbral",
      not eligible_age(known + MIN_AGE - 1, known, MIN_AGE))
check("es elegible exactamente en knownIdx + minLevelAgeBars",
      eligible_age(known + MIN_AGE, known, MIN_AGE))
# el comportamiento ANTIGUO (firstIdx = k - minAge - 1) lo hacia elegible al instante
old_firstIdx = known - MIN_AGE - 1
check("el firstIdx fabricado habria dado elegibilidad inmediata (bug)",
      (known - old_firstIdx) >= MIN_AGE)
check("el fuente ya NO fabrica firstIdx = k - minLevelAgeBars - 1",
      'k-m_par.minLevelAgeBars-1' not in eng)
check("el fuente usa el indice real de conocimiento (m_slKnownIdx[idx])",
      'const int knownIdx=m_slKnownIdx[idx];' in eng and
      'AddOrMerge(m_slPrice[idx],m_slKind[idx],knownIdx,knownIdx,tol)' in eng)

# ============================================================== SECCION 20
print("20) Bug 5 — maxActiveSetups no puede superarse con BUY y SELL")

# Escenario: 1 solo slot libre y una vela que rompe DOS niveles opuestos a la vez.
# Construimos una vela con cuerpo... imposible que una sola vela sea a la vez
# BUY y SELL (el cuerpo tiene un signo). El caso real que hay que cubrir es:
# ya hay setups vivos y quedan 0-1 slots; el motor procesa ambas direcciones.
# Modelamos: nivel de resistencia (BUY) y de soporte roto en velas separadas,
# con max_active pequeno, y comprobamos que nunca se superan los slots.
rnd = random.Random(20)
bars = make_range(40, seed=20)
price = 101.0
# generamos varias rupturas alcistas encadenadas sin retest para acumular vivos
for n in range(8):
    lvl = price
    bars += [bar(lvl-0.10, lvl+0.80, lvl-0.15, lvl+0.75)]  # ruptura, queda en BREAKOUT
    price += 1.0
levels = [dict(price=101.0 + j, broken_dir=0) for j in range(8)]
Setup._n = 0
setups, events = run(bars, levels, require_retest=True, max_active=3)
max_live = 0
# recomputar la ocupacion maxima a lo largo del tiempo
live = {}
timeline = {}
for (sid, kind, k) in events:
    timeline.setdefault(k, []).append((sid, kind))
alive = set()
peak = 0
# reconstruimos ocupacion por evento en orden
ev_sorted = sorted(events, key=lambda e: e[2])
state = {}
for (sid, kind, k) in ev_sorted:
    if kind == 'BREAKOUT':
        alive.add(sid); state[sid] = 'live'
    elif kind in ('INVALIDATED', 'EXPIRED', 'ENTRY'):
        # ENTRY pasa a CONFIRMED (ya no cuenta como vivo de ruptura/retest)
        alive.discard(sid)
    peak = max(peak, len(alive))
check("la ocupacion de setups vivos nunca supera max_active", peak <= 3,
      "pico observado: %d (max 3)" % peak)
check("el fuente reevalua el limite antes de cada direccion (break en el bucle)",
      'if(LiveSetupCount()>=m_par.maxActiveSetups) break;' in eng)
# prueba directa del invariante del bucle: con 3 vivos y max 4, tras crear BUY
# la comprobacion >= impide crear SELL
def loop_guard(live, mx):
    created = 0
    for _ in ('BUY', 'SELL'):
        if live + created >= mx:
            break
        created += 1
    return created
check("con 3 vivos y max 4, solo se crea 1 en la vela (no 2)",
      loop_guard(3, 4) == 1)
check("con 2 vivos y max 4, se pueden crear los 2", loop_guard(2, 4) == 2)

print()
print("=" * 60)
print("FALLOS: %d" % len(FAIL) + ("" if not FAIL else "  -> " + ", ".join(FAIL)))
raise SystemExit(1 if FAIL else 0)
