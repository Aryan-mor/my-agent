# graph-outline.py - compact per-file outline from graphify-out/graph.json for delegate.ps1.
# Usage: python graph-outline.py <project_root> <relpath> [<relpath> ...]
# Prints, per file: line count, symbols with line numbers, local imports, importers, outside users.
import json, os, sys, posixpath, collections

root = sys.argv[1]; refs = [r.replace("\\", "/") for r in sys.argv[2:]]
g = json.load(open(os.path.join(root, "graphify-out", "graph.json"), encoding="utf-8"))
N = {n["id"]: n for n in g["nodes"]}
E = g.get("links") or g.get("edges") or []
files = {n["source_file"] for n in g["nodes"] if n.get("source_file")}
EXT = ["", ".ts", ".tsx", ".js", ".jsx", ".dart", "/index.ts", "/index.tsx", "/index.js"]

def resolve(src, spec):
    if not spec or ":" in spec or not (spec.startswith(".") or spec.endswith(".dart")):
        return None
    base = posixpath.normpath(posixpath.join(posixpath.dirname(src), spec))
    for e in EXT:
        if base + e in files:
            return base + e
    for e in (".ts", ".tsx"):  # TS ESM imports written as .js
        if base.endswith(".js") and base[:-3] + e in files:
            return base[:-3] + e
    return None

imports = collections.defaultdict(set); importers = collections.defaultdict(set)
users = collections.defaultdict(list)
for e in E:
    s, t = N.get(e["source"]), N.get(e["target"])
    if not s or not t:
        continue
    sf = e.get("source_file") or s.get("source_file")
    if e["relation"] in ("imports", "imports_from") and sf:
        r = t.get("source_file") if t.get("source_file") in files and t.get("source_location") in (None, "L1") else resolve(sf, t.get("label", ""))
        if r and r != sf:
            imports[sf].add(r); importers[r].add(sf)
    elif e["relation"] in ("calls", "references", "inherits", "implements", "mixes_in") and sf:
        tf = t.get("source_file")
        if tf and tf != sf and t.get("label") and not t["label"].endswith((".dart", ".ts", ".tsx")):
            users[tf].append((t["label"], sf, e.get("source_location") or ""))

def lines(p):
    try:
        with open(os.path.join(root, p), "rb") as f:
            return sum(1 for _ in f)
    except OSError:
        return None

def short(lst, n):
    lst = sorted(lst)
    return ", ".join(lst[:n]) + (f" (+{len(lst) - n} more)" if len(lst) > n else "")

for r in refs:
    n = lines(r)
    print(f"## {r}" + (f" ({n} lines)" if n is not None else " (missing on disk)"))
    if r not in files:
        print("not in graph (new or non-code file)\n"); continue
    syms = []
    for x in g["nodes"]:
        loc = x.get("source_location") or ""
        if x.get("source_file") == r and loc.startswith("L") and x.get("file_type") == "code":
            syms.append((int(loc[1:]) if loc[1:].isdigit() else 0, x["label"]))
    syms.sort()
    if syms:
        out = [f"{l} L{n}" for n, l in syms[:120]]
        print("symbols: " + ", ".join(out) + (f" (+{len(syms) - 120} more)" if len(syms) > 120 else ""))
    if imports[r]:
        print("imports: " + short(imports[r], 20))
    if importers[r]:
        print("imported by: " + short(importers[r], 15))
    if users[r]:
        seen = collections.OrderedDict()
        for lab, f, loc in users[r]:
            seen.setdefault(lab, set()).add(f"{f}:{loc}" if loc else f)
        print("used elsewhere: " + "; ".join(f"{lab} <- {short(v, 3)}" for lab, v in list(seen.items())[:12]))
    print()