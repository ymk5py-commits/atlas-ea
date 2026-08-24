#!/usr/bin/env python3
"""
check_sources.py — Verificacion estatica de las fuentes MQL5 de ATLAS.

NO reemplaza al compilador de MetaEditor. Atrapa la clase de error que se
cuela cuando se cambia una firma y queda un llamador viejo, o cuando se
renombra un input y sobrevive una referencia. Correr antes de F7:

    python3 scripts/check_sources.py

Sale con codigo 1 si encuentra algo.
"""
import re, sys, os
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent / "src"

# ---------- utilidades de limpieza ----------
def sin_comentarios(txt):
    txt = re.sub(r'/\*.*?\*/', '', txt, flags=re.S)
    txt = re.sub(r'//[^\n]*', '', txt)
    return txt

def sin_strings(txt):
    txt = re.sub(r'"(\\.|[^"\\])*"', '""', txt)
    txt = re.sub(r"'(\\.|[^'\\])*'", "''", txt)
    return txt

def limpio(txt):
    return sin_strings(sin_comentarios(txt))

def partir_args(s):
    """Cuenta argumentos de nivel superior en el interior de un parentesis."""
    if s.strip() == "":
        return 0
    prof = 0
    n = 1
    for ch in s:
        if ch in "([":   prof += 1
        elif ch in ")]": prof -= 1
        elif ch == "," and prof == 0: n += 1
    return n

def cuerpo_parentesis(txt, i):
    """Dado el indice del '(' devuelve (contenido, indice_del_cierre)."""
    prof = 0
    for j in range(i, len(txt)):
        if txt[j] == "(":   prof += 1
        elif txt[j] == ")":
            prof -= 1
            if prof == 0:
                return txt[i+1:j], j
    return None, -1

# ---------- 1) firmas de metodos por clase ----------
TIPOS = r'(?:void|bool|int|long|ulong|double|string|datetime|color|char|uchar|short|ushort|float|ENUM_\w+|E\w+|S\w+|C\w+\s*\*?)'

def firmas_de_clases(fuentes):
    """{clase: {metodo: (min_args, max_args)}}"""
    clases = {}
    for ruta, txt in fuentes.items():
        for m in re.finditer(r'\bclass\s+(C\w+)\b', txt):
            nombre = m.group(1)
            # cuerpo de la clase: desde la primera '{' hasta su cierre
            i = txt.find("{", m.end())
            if i < 0: continue
            prof, fin = 0, len(txt)
            for j in range(i, len(txt)):
                if txt[j] == "{": prof += 1
                elif txt[j] == "}":
                    prof -= 1
                    if prof == 0:
                        fin = j; break
            cuerpo = txt[i:fin]
            metodos = {}
            for mm in re.finditer(r'\b' + TIPOS + r'\s+(\w+)\s*\(', cuerpo):
                met = mm.group(1)
                if met in ("if", "for", "while", "switch", "return", "sizeof"):
                    continue
                args, _ = cuerpo_parentesis(cuerpo, mm.end() - 1)
                if args is None: continue
                if args.strip() == "":
                    lo = hi = 0
                else:
                    partes, prof2, cur = [], 0, ""
                    for ch in args:
                        if ch in "([": prof2 += 1
                        elif ch in ")]": prof2 -= 1
                        if ch == "," and prof2 == 0:
                            partes.append(cur); cur = ""
                        else:
                            cur += ch
                    partes.append(cur)
                    hi = len(partes)
                    lo = sum(1 for p in partes if "=" not in p)
                # si el metodo se declara varias veces, quedarse con el rango mas amplio
                if met in metodos:
                    lo = min(lo, metodos[met][0]); hi = max(hi, metodos[met][1])
                metodos[met] = (lo, hi)
            clases.setdefault(nombre, {}).update(metodos)
    return clases

# ---------- 2) variables -> clase ----------
def mapa_variables(fuentes, clases):
    """{nombre_variable: clase}  (objetos, punteros y arrays)"""
    var = {}
    for ruta, txt in fuentes.items():
        for c in clases:
            for m in re.finditer(r'\b' + c + r'\s*\*?\s*(\w+)\s*(?:\[\s*\]|\[\d*\])?\s*[;,=]', txt):
                var[m.group(1)] = c
    return var

# ---------- 3) chequeos ----------
def revisar_aridad(fuentes, clases, var2clase):
    fallos = []
    for ruta, txt in fuentes.items():
        for m in re.finditer(r'\b(\w+)\s*(?:\[[^\]]*\])?\s*\.\s*(\w+)\s*\(', txt):
            v, met = m.group(1), m.group(2)
            clase = var2clase.get(v)
            if not clase or clase not in clases: continue
            if met not in clases[clase]: continue
            lo, hi = clases[clase][met]
            args, _ = cuerpo_parentesis(txt, m.end() - 1)
            if args is None: continue
            n = partir_args(args)
            if not (lo <= n <= hi):
                linea = txt[:m.start()].count("\n") + 1
                fallos.append(f"{ruta}:{linea}: {v}.{met}() recibe {n} argumento(s); "
                              f"{clase}::{met} espera entre {lo} y {hi}")
    return fallos

def revisar_identificadores(fuentes, prefijo, patron_decl, etiqueta):
    declarados = set()
    for txt in fuentes.values():
        declarados |= set(re.findall(patron_decl, txt))
    fallos = []
    for ruta, txt in fuentes.items():
        for m in re.finditer(r'\b(' + prefijo + r'\w+)\b', txt):
            if m.group(1) not in declarados:
                linea = txt[:m.start()].count("\n") + 1
                fallos.append(f"{ruta}:{linea}: {etiqueta} '{m.group(1)}' usado pero nunca declarado")
    # una sola vez por identificador
    vistos, unicos = set(), []
    for f in fallos:
        clave = f.split("'")[1]
        if clave not in vistos:
            vistos.add(clave); unicos.append(f)
    return unicos

def revisar_balance(fuentes):
    fallos = []
    for ruta, txt in fuentes.items():
        for abre, cierra, nombre in (("{", "}", "llaves"), ("(", ")", "parentesis"), ("[", "]", "corchetes")):
            d = txt.count(abre) - txt.count(cierra)
            if d != 0:
                fallos.append(f"{ruta}: {nombre} desbalanceados ({d:+d})")
    return fallos

def revisar_scripts_despliegue(fuentes):
    """Todo Inp*=... escrito por los scripts de despliegue/backtest debe ser
    un input real del EA. Este es exactamente el bug que tenia entrypoint.sh
    en v1: escribia inputs renombrados, MT5 los ignoraba en silencio y el
    bot corria con otra configuracion de la que el dueño creia."""
    declarados = set()
    for txt in fuentes.values():
        declarados |= set(re.findall(r'input\s+[\w.]+\s+(Inp\w+)', txt))

    raiz = RAIZ.parent
    fallos = []
    for rel in ("docker/entrypoint.sh", "scripts/server_backtest.sh"):
        ruta = raiz / rel
        if not ruta.exists():
            continue
        txt = ruta.read_text(encoding="utf-8", errors="replace")
        # En los printf las lineas van pegadas con \r\n LITERALES (los dos
        # caracteres): sin esto, \b no ve frontera entre la 'n' y la 'I' y
        # todos los inputs del bloque quedan invisibles al chequeo.
        txt = txt.replace("\\r", "\n").replace("\\n", "\n")
        for m in re.finditer(r'\b(Inp\w+)=', txt):
            if m.group(1) not in declarados:
                linea = txt[:m.start()].count("\n") + 1
                fallos.append(f"{rel}:{linea}: escribe '{m.group(1)}' pero ese input no existe en el EA (MT5 lo ignoraria en silencio)")
    # una sola vez por input
    vistos, unicos = set(), []
    for f in fallos:
        clave = f.split("'")[1]
        if clave not in vistos:
            vistos.add(clave); unicos.append(f)
    return unicos

def main():
    fuentes = {}
    for ruta in sorted(RAIZ.rglob("*.mq*")):
        rel = str(ruta.relative_to(RAIZ.parent))
        fuentes[rel] = limpio(ruta.read_text(encoding="utf-8", errors="replace"))
    if not fuentes:
        print("No se encontraron fuentes en", RAIZ); return 1

    clases = firmas_de_clases(fuentes)
    var2clase = mapa_variables(fuentes, clases)

    bloques = [
        ("balance de llaves/parentesis/corchetes", revisar_balance(fuentes)),
        ("aridad de llamadas a metodos",           revisar_aridad(fuentes, clases, var2clase)),
        ("inputs sin declarar",                    revisar_identificadores(fuentes, "Inp", r'input\s+\w+\s+(Inp\w+)', "input")),
        ("globales sin declarar",                  revisar_identificadores(fuentes, "g_",  r'\b(g_\w+)\s*(?:\[\s*\]|\[\d*\])?\s*[;,=]', "global")),
        ("scripts de despliegue vs inputs del EA",  revisar_scripts_despliegue(fuentes)),
    ]

    total = 0
    print(f"Fuentes revisadas: {len(fuentes)} | clases: {len(clases)} | "
          f"metodos: {sum(len(v) for v in clases.values())}\n")
    for titulo, fallos in bloques:
        estado = "OK" if not fallos else f"{len(fallos)} PROBLEMA(S)"
        print(f"[{estado:>14}] {titulo}")
        for f in fallos:
            print(f"                 - {f}")
        total += len(fallos)
    print()
    if total == 0:
        print("Sin hallazgos. Igual hay que compilar en MetaEditor (F7): esto no es un compilador.")
        return 0
    print(f"{total} hallazgo(s) que revisar antes de compilar.")
    return 1

if __name__ == "__main__":
    sys.exit(main())
