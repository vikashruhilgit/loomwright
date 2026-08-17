#!/usr/bin/env python3
"""Generalize the validation: does the type-edge ranking FAIL and the import-edge
ranking PASS on OTHER repos/langs (HUB=TS monorepo, flutter=Dart)?
Ground truth = real import in-degree. Run: python3 validate_gen.py <root> <ts|dart>"""
import sys, re, os
from pathlib import Path
from collections import defaultdict, Counter
import reposcan_multi as R

root = Path(sys.argv[1]).resolve(); lang = sys.argv[2]
files = R.list_files(root)
relset = {str(p.relative_to(root)) for p in files}

def resolve_ts(spec, imp):
    if spec.startswith("@/"): base = spec[2:]
    elif spec.startswith("."): base = os.path.normpath(os.path.join(os.path.dirname(imp), spec))
    else: return None
    for c in (base+".ts", base+".tsx", base+"/index.ts", base+"/index.tsx", base):
        if c in relset: return c
    return None
def resolve_dart(spec, imp):
    if spec.startswith("package:"):
        base = "lib/" + spec.split("/", 1)[1] if "/" in spec else None   # package:app/x -> lib/x
    elif spec.startswith("dart:"): return None
    else: base = os.path.normpath(os.path.join(os.path.dirname(imp), spec))
    if not base: return None
    for c in (base, base if base.endswith(".dart") else base+".dart"):
        if c in relset: return c
    return None
resolve = resolve_ts if lang == "ts" else resolve_dart
IMP = re.compile(r"""(?:from|import)\s+['"]([^'"]+)['"]""") if lang=="ts" else re.compile(r"""import\s+['"]([^'"]+)['"]""")

indeg = Counter(); local = res = 0
for rel in relset:
    for spec in IMP.findall((root/rel).read_text("utf-8","replace")):
        if lang=="ts" and not (spec.startswith("@/") or spec.startswith(".")): continue
        if lang=="dart" and spec.startswith("dart:"): continue
        local += 1
        t = resolve(spec, rel)
        if t and t != rel: res += 1; indeg[t] += 1

# type-edge reposcan ranking (the OLD approach)
from tree_sitter import Parser
ftd, fr = {}, {}
for p in files:
    rel=str(p.relative_to(root))
    try: _,td,refs,_ = R.extract(p, p.read_bytes(), R.EXT2LANG[p.suffix])
    except Exception: td,refs=set(),{}
    ftd[rel]=td; fr[rel]=refs
sym=defaultdict(set)
for rel,td in ftd.items():
    for n in td: sym[n].add(rel)
te=defaultdict(dict)
for rel,refs in fr.items():
    for name,cnt in refs.items():
        ds=sym.get(name,())
        if ds and len(ds)<=8:
            for d in ds:
                if d!=rel: te[rel][d]=te[rel].get(d,0)+cnt/len(ds)
nodes=list(relset)
pr_type=R.pagerank(nodes,{u:dict(v) for u,v in te.items()})

def top(d,n): return [k for k,_ in sorted(d.items(),key=lambda x:-x[1])[:n]]
gt=top(indeg,10)
ov_type=len(set(gt)&set(top(pr_type,10)))
print(f"{root.name} [{lang}]: files={len(files)} resolved={res}/{local} ({100*res//max(1,local)}%) inbound-files={len(indeg)}")
print(f"  TYPE-edge ranking vs ground-truth top-10: {ov_type}/10   (expect LOW = defect generalizes)")
print(f"  ground-truth top-5 most-imported:")
for f in gt[:5]: print(f"     {indeg[f]:4}  {f}")
