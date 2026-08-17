#!/usr/bin/env python3
"""
Validate reposcan's repo-map against an INDEPENDENT ground truth: the real
TypeScript import graph (`import ... from '...'`). Imports are deterministic and
verifiable, and are extracted by a DIFFERENT method than reposcan's type-identifier
matching — so agreement is real validation, not circular.

Scores:
  - edge precision: of reposcan's edges (A uses a type defined in B), what fraction
    are backed by a real import A->B?  (catches coincidental/false edges)
  - ranking validity: do reposcan's top files by PageRank match the most-imported
    files (independent importance signal)?  top-N overlap + Spearman.

Run: uv run --with tree-sitter --with tree-sitter-typescript ... python3 validate.py <root>
"""
import sys, re, os
from pathlib import Path
from collections import defaultdict
import reposcan_multi as R

root = Path(sys.argv[1]).resolve()
files = R.list_files(root)
relset = {str(p.relative_to(root)) for p in files}

# ---------- GROUND TRUTH: real import graph ----------
IMP = re.compile(r"""(?:from|import)\s+['"]([^'"]+)['"]""")
def resolve(spec, importer_rel):
    if spec.startswith("@/"):
        base = spec[2:]
    elif spec.startswith("."):
        base = os.path.normpath(os.path.join(os.path.dirname(importer_rel), spec))
    else:
        return None  # external pkg
    for cand in (base+".ts", base+".tsx", base+"/index.ts", base+"/index.tsx", base):
        if cand in relset:
            return cand
    return None

import_edges = defaultdict(set)     # importer -> {targets}
in_degree = defaultdict(int)        # target -> # distinct importers
raw_specifiers = resolved = external = 0
for p in files:
    rel = str(p.relative_to(root))
    txt = p.read_text("utf-8", "replace")
    for spec in IMP.findall(txt):
        raw_specifiers += 1
        if not (spec.startswith("@/") or spec.startswith(".")):
            external += 1; continue
        tgt = resolve(spec, rel)
        if tgt and tgt != rel:
            resolved += 1
            if tgt not in import_edges[rel]:
                import_edges[rel].add(tgt); in_degree[tgt] += 1
local_specs = raw_specifiers - external

# ---------- reposcan: rebuild edges + ranking on the same set ----------
from tree_sitter import Parser
ftd, fr = {}, {}
for p in files:
    rel = str(p.relative_to(root)); b = p.read_bytes()
    ln = R.EXT2LANG[p.suffix]
    try: _, td, refs, _ = R.extract(p, b, ln)
    except Exception: td, refs = set(), {}
    ftd[rel] = td; fr[rel] = refs
sym = defaultdict(set)
for rel, td in ftd.items():
    for n in td: sym[n].add(rel)
redges = defaultdict(dict)
for rel, refs in fr.items():
    for name, cnt in refs.items():
        ds = sym.get(name, ())
        if not ds or len(ds) > 8: continue
        for d in ds:
            if d != rel: redges[rel][d] = redges[rel].get(d, 0) + cnt/len(ds)
nodes = list(relset)
pr = R.pagerank(nodes, {u: dict(v) for u, v in redges.items()})

# ---------- SCORE ----------
# edge precision
total_re = sum(len(v) for v in redges.values())
matched = sum(1 for a, ds in redges.items() for d in ds if d in import_edges.get(a, ()))
prec = matched/total_re if total_re else 0

def topN(d, n): return [k for k, _ in sorted(d.items(), key=lambda x: -x[1])[:n]]
gt_rank = topN(in_degree, 20)
rs_rank = topN(pr, 20)
overlap20 = len(set(gt_rank) & set(rs_rank))
overlap10 = len(set(gt_rank[:10]) & set(rs_rank[:10]))

# spearman over files appearing in either ranking signal
allf = [f for f in nodes if in_degree.get(f, 0) > 0 or pr.get(f, 0) > 0]
def ranks(score):
    order = sorted(allf, key=lambda f: -score.get(f, 0))
    return {f: i for i, f in enumerate(order)}
ri, rp = ranks(in_degree), ranks(pr)
n = len(allf)
if n > 2:
    d2 = sum((ri[f]-rp[f])**2 for f in allf)
    spearman = 1 - 6*d2/(n*(n*n-1))
else:
    spearman = float("nan")

print(f"=== GROUND TRUTH (real import graph) ===")
print(f"files: {len(files)} | local import specifiers: {local_specs} | resolved to a file: {resolved} ({100*resolved//max(1,local_specs)}%)")
print(f"import edges: {sum(len(v) for v in import_edges.values())} | files with inbound imports: {len(in_degree)}")
print(f"\n=== EDGE PRECISION (reposcan edges backed by a real import) ===")
print(f"reposcan edges: {total_re} | backed by an import: {matched} | precision: {prec:.1%}")
print(f"  (lower bound — type-use without an explicit import still counts as 'unbacked')")
print(f"\n=== RANKING VALIDITY (reposcan PageRank vs import in-degree) ===")
print(f"top-10 overlap: {overlap10}/10 | top-20 overlap: {overlap20}/20 | Spearman: {spearman:.3f}")
print(f"\nreposcan top-10 (PageRank)        | import in-degree of that file")
for f in rs_rank[:10]:
    print(f"  {in_degree.get(f,0):4} imports  {f}")
print(f"\nground-truth top-10 (most imported) | in reposcan top-20? ")
for f in gt_rank[:10]:
    print(f"  {in_degree[f]:4} imports  {'✓' if f in rs_rank else ' '}  {f}")

# ---------- THE FIX: rank by PageRank over the REAL import graph ----------
pr_imp = R.pagerank(nodes, {a: {d: 1.0 for d in ds} for a, ds in import_edges.items()})
fix_rank = topN(pr_imp, 20)
fix_overlap10 = len(set(gt_rank[:10]) & set(fix_rank[:10]))
fix_overlap20 = len(set(gt_rank) & set(fix_rank))
print(f"\n=== PROPOSED FIX: edges from IMPORTS (not type-identifier matching) ===")
print(f"top-10 overlap w/ most-imported: {fix_overlap10}/10 | top-20: {fix_overlap20}/20")
print(f"fix top-10 (import-graph PageRank):")
for f in fix_rank[:10]:
    print(f"  {in_degree.get(f,0):4} imports  {f}")
