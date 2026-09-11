#!/usr/bin/env python3
"""
Verificador estatico ligero para el proyecto Breakout Intelligence MT5.

NO es un compilador MQL5. Comprueba unicamente:
  1. Equilibrio de llaves, parentesis y corchetes (fuera de cadenas y comentarios).
  2. Que toda funcion invocada este definida en el proyecto o pertenezca a la
     lista blanca de funciones reales de MQL5 (detecta APIs inventadas).
  3. Que toda constante MQL5 usada pertenezca a la lista blanca o al proyecto.
  4. Correspondencia entre metodos declarados en cada clase y sus definiciones.
  5. Que los campos accedidos con '.' existan en alguna estructura del proyecto.
  6. Coherencia entre indicator_buffers / indicator_plots y SetIndexBuffer.
  7. Que 'const' y los parametros coincidan entre declaracion y definicion
     de cada metodo (un desajuste es error de compilacion en MQL5).
  8. Que ninguna funcion con valor de retorno pueda terminar sin return.
  9. Que MathMax/MathMin (que devuelven double) no alimenten un entero.
 10. Que toda estructura local usada como 'constructor' rellene todos sus
     campos (un campo olvidado no es error de compilacion: es basura en
     tiempo de ejecucion).
"""
import re, sys, os, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MQL5_FUNCS = set("""
ArrayResize ArrayInitialize ArraySetAsSeries ArraySize ArrayCopy ArrayFree ArrayFill
ArrayMaximum ArrayMinimum ArraySort ArrayRange ArrayIsSeries
CopyRates CopyBuffer CopyTime CopyOpen CopyHigh CopyLow CopyClose CopyTickVolume
CopyRealVolume CopySpread
iATR iMA iRSI iMACD iStochastic iBands iCustom iBarShift iBars iTime iOpen iHigh iLow
iClose iVolume iTickVolume iSpread
IndicatorRelease IndicatorSetString IndicatorSetInteger IndicatorSetDouble
SetIndexBuffer PlotIndexSetInteger PlotIndexSetDouble PlotIndexSetString
PlotIndexGetInteger
SymbolInfoInteger SymbolInfoDouble SymbolInfoString SymbolInfoTick SymbolSelect
SeriesInfoInteger Bars Period Symbol Digits Point
ObjectCreate ObjectDelete ObjectFind ObjectsDeleteAll ObjectSetInteger ObjectSetDouble
ObjectSetString ObjectGetInteger ObjectGetDouble ObjectGetString ObjectMove
ChartRedraw ChartGetInteger ChartSetInteger ChartID
TimeCurrent TimeLocal TimeGMT TimeToStruct StructToTime TimeToString StringToTime
MathAbs MathMax MathMin MathRound MathFloor MathCeil MathPow MathSqrt MathLog MathExp
MathMod MathRand
StringFormat StringFind StringSubstr StringLen StringReplace StringToUpper StringToLower
StringConcatenate StringTrimLeft StringTrimRight StringSplit StringCompare
DoubleToString IntegerToString StringToDouble StringToInteger NormalizeDouble
EnumToString CharToString ShortToString
Alert Print PrintFormat Comment SendNotification SendMail PlaySound MessageBox
GetPointer GetLastError ResetLastError IsStopped
ZeroMemory ArrayPrint
OnInit OnDeinit OnCalculate OnTimer OnChartEvent OnTick
EventSetTimer EventKillTimer
TerminalInfoInteger AccountInfoInteger MQLInfoInteger
PeriodSeconds ChartPeriod ChartSymbol StringGetCharacter StringSetCharacter
ColorToARGB ArrayReverse FileOpen FileClose FileWrite
""".split())

MQL5_CONSTS = set("""
INVALID_HANDLE EMPTY_VALUE DBL_MAX DBL_MIN INT_MAX INT_MIN NULL WHOLE_ARRAY
INIT_SUCCEEDED INIT_FAILED INIT_PARAMETERS_INCORRECT
INDICATOR_DATA INDICATOR_CALCULATIONS INDICATOR_COLOR_INDEX
INDICATOR_DIGITS INDICATOR_SHORTNAME INDICATOR_LEVELS
PLOT_ARROW PLOT_ARROW_SHIFT PLOT_EMPTY_VALUE PLOT_LABEL PLOT_LINE_COLOR PLOT_DRAW_TYPE
PLOT_SHIFT PLOT_LINE_WIDTH PLOT_SHOW_DATA
DRAW_NONE DRAW_LINE DRAW_ARROW DRAW_HISTOGRAM DRAW_SECTION DRAW_FILLING
MODE_EMA MODE_SMA MODE_SMMA MODE_LWMA
PRICE_CLOSE PRICE_OPEN PRICE_HIGH PRICE_LOW PRICE_MEDIAN PRICE_TYPICAL PRICE_WEIGHTED
PERIOD_CURRENT PERIOD_M1 PERIOD_M5 PERIOD_M15 PERIOD_M30 PERIOD_H1 PERIOD_H4
PERIOD_D1 PERIOD_W1 PERIOD_MN1
SYMBOL_DIGITS SYMBOL_POINT SYMBOL_SPREAD SYMBOL_BID SYMBOL_ASK
SYMBOL_TRADE_TICK_SIZE SYMBOL_TRADE_TICK_VALUE SYMBOL_TRADE_STOPS_LEVEL
SYMBOL_VOLUME_MIN SYMBOL_VOLUME_STEP SYMBOL_TRADE_CONTRACT_SIZE
OBJ_TREND OBJ_RECTANGLE OBJ_TEXT OBJ_LABEL OBJ_HLINE OBJ_VLINE OBJ_ARROW
OBJPROP_TIME OBJPROP_PRICE OBJPROP_COLOR OBJPROP_STYLE OBJPROP_WIDTH OBJPROP_BACK
OBJPROP_RAY_RIGHT OBJPROP_RAY_LEFT OBJPROP_SELECTABLE OBJPROP_HIDDEN OBJPROP_FILL
OBJPROP_TEXT OBJPROP_FONT OBJPROP_FONTSIZE OBJPROP_CORNER OBJPROP_XDISTANCE
OBJPROP_YDISTANCE OBJPROP_ANCHOR OBJPROP_ZORDER
STYLE_SOLID STYLE_DASH STYLE_DOT STYLE_DASHDOT STYLE_DASHDOTDOT
CORNER_LEFT_UPPER CORNER_RIGHT_UPPER CORNER_LEFT_LOWER CORNER_RIGHT_LOWER
TIME_DATE TIME_MINUTES TIME_SECONDS
SERIES_BARS_COUNT
_Symbol _Period _Digits _Point _LastError
""".split())

CTRL = set("if while for switch return sizeof catch else do case new delete".split())
TYPES = set("""int double bool string long short char uchar ushort uint ulong float void
datetime color const static input sinput extern virtual class struct enum private public
protected template union group""".split())

def strip_code(src):
    """Elimina comentarios y literales de cadena conservando las posiciones de linea."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i+1] == '/':
            while i < n and src[i] != '\n':
                i += 1
        elif c == '/' and i + 1 < n and src[i+1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i+1] == '/'):
                if src[i] == '\n':
                    out.append('\n')
                i += 1
            i += 2
        elif c in '"\'':
            q = c
            i += 1
            while i < n and src[i] != q:
                if src[i] == '\\':
                    i += 1
                i += 1
            i += 1
            out.append('""')
        else:
            out.append(c)
            i += 1
    code = ''.join(out)
    # las directivas del preprocesador no son codigo analizable
    code = '\n'.join('' if ln.lstrip().startswith('#') else ln
                      for ln in code.split('\n'))
    return code

def check_balance(name, code, errs):
    pairs = {')': '(', ']': '[', '}': '{'}
    stack = []
    line = 1
    for ch in code:
        if ch == '\n':
            line += 1
        elif ch in '([{':
            stack.append((ch, line))
        elif ch in ')]}':
            if not stack or stack[-1][0] != pairs[ch]:
                errs.append(f"{name}:{line}: cierre '{ch}' sin apertura correspondiente")
                return
            stack.pop()
    for ch, ln in stack:
        errs.append(f"{name}:{ln}: '{ch}' sin cerrar")

def main():
    files = sorted(glob.glob(os.path.join(ROOT, 'Indicators', '**', '*.mqh'), recursive=True)) + \
            sorted(glob.glob(os.path.join(ROOT, 'Indicators', '**', '*.mq5'), recursive=True))
    errs, warns = [], []

    sources, codes = {}, {}
    for f in files:
        src = open(f, encoding='utf-8').read()
        sources[f] = src
        codes[f] = strip_code(src)

    # --- 1) equilibrio de delimitadores
    for f in files:
        check_balance(os.path.basename(f), codes[f], errs)

    all_code = '\n'.join(codes[f] for f in files)

    # --- definiciones del proyecto
    proj_funcs = set(re.findall(r'\b(?:void|int|double|bool|string|long|color|datetime|'
                                r'SBILevel|SBISetup|SBIEvent|SBISignal|SBIParams|SBIProfileDefaults)\s+'
                                r'(?:\w+::)?(\w+)\s*\(', all_code))
    class_methods = set(re.findall(r'\b\w+::(\w+)\s*\(', all_code))
    proj_funcs |= class_methods

    # metodos declarados dentro de clases (incluye los inline)
    decl_methods = set(re.findall(r'^\s*(?:virtual\s+)?(?:void|int|double|bool|string|long|color|'
                                  r'datetime|SBILevel|SBISetup|SBIEvent)\s+(\w+)\s*\(',
                                  all_code, re.M))
    proj_funcs |= decl_methods
    proj_funcs |= {'CBIEngine', 'CBILevels', 'CBIAlerts', 'CBIRender'}

    # enums y defines del proyecto
    proj_consts = set(re.findall(r'^\s*(BI_[A-Z0-9_]+)\s*[=,]', all_code, re.M))
    raw_all = '\n'.join(sources[f] for f in files)
    proj_consts |= set(re.findall(r'#define\s+(\w+)', raw_all))
    proj_consts |= set(re.findall(r'^\s*(BI_[A-Z0-9_]+)\s*$', all_code, re.M))
    proj_consts |= {'BI_DIR_NONE','BI_DIR_UP','BI_DIR_DOWN'}

    # --- 2) llamadas a funciones desconocidas
    for f in files:
        for m in re.finditer(r'\b([A-Za-z_]\w*)\s*\(', codes[f]):
            nm = m.group(1)
            if nm in CTRL or nm in TYPES or nm in MQL5_FUNCS or nm in proj_funcs:
                continue
            if nm.startswith('clr') or nm.startswith('Inp'):
                continue
            ln = codes[f][:m.start()].count('\n') + 1
            errs.append(f"{os.path.basename(f)}:{ln}: funcion desconocida '{nm}'")

    # --- 3) constantes en MAYUSCULAS desconocidas
    known_enum_members = set(re.findall(r'^\s*([A-Z][A-Z0-9_]{2,})\s*(?:=|,)', all_code, re.M))
    for f in files:
        for m in re.finditer(r'\b([A-Z][A-Z0-9_]{2,})\b', codes[f]):
            nm = m.group(1)
            if nm in MQL5_CONSTS or nm in proj_consts or nm in known_enum_members:
                continue
            if re.match(r'^(ENUM|SBI|CBI)', nm):
                continue
            ln = codes[f][:m.start()].count('\n') + 1
            warns.append(f"{os.path.basename(f)}:{ln}: constante no reconocida '{nm}'")

    # --- 4) declaraciones de clase frente a definiciones
    for cls in ['CBIEngine', 'CBILevels', 'CBIAlerts', 'CBIRender']:
        mm = re.search(r'class\s+' + cls + r'\b(.*?)\n\s*\};', all_code, re.S)
        if not mm:
            errs.append(f"clase {cls} no encontrada")
            continue
        body = mm.group(1)
        flat = re.sub(r'\s+', ' ', body)
        declared = set()
        for stmt in flat.split(';'):
            g = re.search(r'(?:^| )(?:virtual )?(?:void|int|double|bool|string|long|color|datetime|'
                          r'SBILevel|SBISetup|SBIEvent)\s+(\w+)\s*\([^()]*\)\s*(?:const)?\s*$',
                          stmt.strip() + ' ')
            if g:
                declared.add(g.group(1))
        defined = set(re.findall(cls + r'::(\w+)\s*\(', all_code))
        missing = declared - defined
        if missing:
            errs.append(f"{cls}: metodos declarados sin definir -> {sorted(missing)}")
        extra = defined - declared - {cls, '~' + cls}
        inline = set(re.findall(r'(\w+)\s*\([^()]*\)\s*(?:const)?\s*\{', flat))
        extra -= inline
        if extra:
            errs.append(f"{cls}: definiciones sin declaracion -> {sorted(extra)}")

    # --- 5) campos de estructura
    struct_fields = set()
    for mm in re.finditer(r'struct\s+(\w+)\s*\{(.*?)\n\s*\};', all_code, re.S):
        for line in mm.group(2).split('\n'):
            g = re.match(r'\s*(?:\w+)\s+(\w+)\s*(?:\[\])?\s*;', line)
            if g:
                struct_fields.add(g.group(1))
    obj_members = {'Items', 'Count', 'time', 'open', 'high', 'low', 'close',
                   'tick_volume', 'real_volume', 'spread', 'hour', 'day_of_week',
                   'day_of_year', 'min', 'sec', 'mon', 'year', 'day'}
    for f in files:
        for m in re.finditer(r'\.([a-z]\w*)\b(?!\s*\()', codes[f]):
            nm = m.group(1)
            if nm in struct_fields or nm in obj_members:
                continue
            ln = codes[f][:m.start()].count('\n') + 1
            errs.append(f"{os.path.basename(f)}:{ln}: campo desconocido '.{nm}'")

    # --- 6) buffers y plots
    mq5 = [f for f in files if f.endswith('.mq5')]
    for f in mq5:
        src = sources[f]
        nb = re.search(r'indicator_buffers\s+(\d+)', src)
        np_ = re.search(r'indicator_plots\s+(\d+)', src)
        used = len(re.findall(r'SetIndexBuffer\s*\(', codes[f]))
        if nb and int(nb.group(1)) != used:
            errs.append(f"{os.path.basename(f)}: indicator_buffers={nb.group(1)} "
                        f"pero hay {used} llamadas a SetIndexBuffer")
        if nb and np_ and int(np_.group(1)) > int(nb.group(1)):
            errs.append(f"{os.path.basename(f)}: indicator_plots > indicator_buffers")
        for i in range(1, (int(np_.group(1)) + 1) if np_ else 1):
            if not re.search(r'indicator_type%d\b' % i, src):
                errs.append(f"{os.path.basename(f)}: falta indicator_type{i}")

    # --- 7) firmas: const y parametros deben coincidir declaracion/definicion
    RETT = (r'(?:void|int|double|bool|string|long|color|datetime|'
            r'SBILevel|SBISetup|SBIEvent|SBISignal|SBIProfileDefaults)')
    for cls in ['CBIEngine', 'CBILevels', 'CBIAlerts', 'CBIRender']:
        mm = re.search(r'class\s+' + cls + r'\b(.*?)\n\s*\};', all_code, re.S)
        if not mm:
            continue
        flat = re.sub(r'\s+', ' ', mm.group(1))
        decl = {}
        for stmt in flat.split(';'):
            g = re.search(r'(?:^| )' + RETT + r'\s+(\w+)\s*\(([^()]*)\)\s*(const)?\s*$',
                          stmt.strip() + ' ')
            if g:
                decl[g.group(1)] = (bool(g.group(3)), re.sub(r'\s+', '', g.group(2)))
        for g in re.finditer(cls + r'::(\w+)\s*\(([^()]*)\)\s*(const)?\s*\n?\s*\{', all_code):
            name, args, isc = g.group(1), re.sub(r'\s+', '', g.group(2)), bool(g.group(3))
            if name in (cls, '~' + cls) or name not in decl:
                continue
            dc, da = decl[name]
            if dc != isc:
                errs.append(f"{cls}::{name}: 'const' no coincide "
                            f"(declaracion={dc}, definicion={isc})")
            if da != args:
                errs.append(f"{cls}::{name}: parametros distintos\n"
                            f"       decl: {da}\n       def : {args}")

    # --- 8) toda funcion con valor de retorno debe terminar en return
    #        (void queda excluido: no devuelve nada)
    RETV = (r'(?:int|double|bool|string|long|color|datetime|'
            r'SBILevel|SBISetup|SBIEvent|SBISignal|SBIProfileDefaults)')
    for f in files:
        code = codes[f]
        for m in re.finditer(r'^' + RETV + r'\s+(?:\w+::)?(\w+)\s*\([^;{]*\)\s*'
                             r'(?:const\s*)?\n?\s*\{', code, re.M):
            i, depth = m.end() - 1, 0
            while i < len(code):
                if code[i] == '{':
                    depth += 1
                elif code[i] == '}':
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            body = code[m.end():i]
            # la ULTIMA sentencia del cuerpo debe ser un return; que exista un
            # return en algun 'case' interior no garantiza todas las rutas
            frag = [x.strip() for x in
                    body.replace('}', ' ').replace('{', ' ').split(';') if x.strip()]
            if not frag or not frag[-1].startswith('return'):
                ln = code[:m.start()].count('\n') + 1
                errs.append(f"{os.path.basename(f)}:{ln}: {m.group(1)}() "
                            f"puede terminar sin return")

    # --- 9) MathMax/MathMin devuelven double: no deben alimentar un entero
    for f in files:
        for m in re.finditer(r'\bint\s+\w+\s*=[^;]*Math(?:Max|Min)\s*\(', codes[f]):
            ln = codes[f][:m.start()].count('\n') + 1
            errs.append(f"{os.path.basename(f)}:{ln}: MathMax/MathMin (double) "
                        f"asignado a int; usa BI_MaxInt/BI_MinInt")

    # --- 10) estructuras locales usadas como constructor: todos los campos asignados
    struct_def = {}
    for mm in re.finditer(r'struct\s+(\w+)\s*\{(.*?)\n\s*\};', all_code, re.S):
        struct_def[mm.group(1)] = [g.group(1) for g in
                                   re.finditer(r'^\s*\w+\s+(\w+)\s*;', mm.group(2), re.M)]
    for f in files:
        code = codes[f]
        for st, fields in struct_def.items():
            for m in re.finditer(r'\b' + st + r'\s+(\w+)\s*;', code):
                var = m.group(1)
                # la ventana llega hasta el final de la funcion que lo declara
                end = code.find('\n  }', m.end())
                tail = code[m.end():end if end > 0 else len(code)]
                assigned = set(re.findall(r'\b' + var + r'\.(\w+)\s*=', tail))
                # tambien cuenta campos pasados por referencia (out-params):
                # p.ej. BI_ResolveSessions(...,g_par.sess1Start,...)
                assigned |= set(re.findall(r'\b' + var + r'\.(\w+)\s*[,)]', tail))
                if len(assigned) < 3:
                    continue                       # no es un relleno de estructura
                missing = [x for x in fields if x not in assigned]
                if missing:
                    ln = code[:m.start()].count('\n') + 1
                    errs.append(f"{os.path.basename(f)}:{ln}: {st} {var} deja sin "
                                f"inicializar {missing}")

    print("Ficheros analizados: %d" % len(files))
    for w in warns:
        print("AVISO  " + w)
    for e in errs:
        print("ERROR  " + e)
    print("-" * 60)
    print("errores: %d   avisos: %d" % (len(errs), len(warns)))
    return 1 if errs else 0

if __name__ == '__main__':
    sys.exit(main())
