#!/usr/bin/env python3
"""
Tier-1 repo-map spike — MULTI-LANGUAGE (C#, TypeScript, TSX, Python).

Generalizes reposcan.py behind a per-language config. Same approach:
tree-sitter extract -> type-only def/ref edges + IDF -> personalized PageRank ->
token-budgeted skeleton, with a content-SHA incremental cache.

Run:
  uv run --with tree-sitter --with tree-sitter-c-sharp --with tree-sitter-typescript \
         --with tree-sitter-python python3 reposcan_multi.py <root> [--top N] [--budget TOK] [--tag NAME]
"""
import sys, os, re, json, time, hashlib, argparse
from pathlib import Path
from collections import defaultdict, Counter
from tree_sitter import Language, Parser

HERE = Path(__file__).resolve().parent
TOK = lambda s: max(1, len(s) // 4)

# ---- per-language config ------------------------------------------------
def _langs():
    cfg = {}
    try:
        import tree_sitter_c_sharp as m
        cfg["c_sharp"] = dict(
            lang=Language(m.language()),
            ext={".cs"},
            defs={"class_declaration","struct_declaration","interface_declaration","enum_declaration",
                  "record_declaration","method_declaration","constructor_declaration","property_declaration"},
            tdefs={"class_declaration","struct_declaration","interface_declaration","enum_declaration","record_declaration"},
            refnodes={"identifier"},
        )
    except Exception: pass
    try:
        import tree_sitter_typescript as m
        common = dict(
            defs={"class_declaration","interface_declaration","enum_declaration","type_alias_declaration",
                  "function_declaration","method_definition","abstract_class_declaration"},
            tdefs={"class_declaration","interface_declaration","enum_declaration","type_alias_declaration","abstract_class_declaration"},
            refnodes={"identifier","type_identifier"},
        )
        cfg["typescript"] = dict(lang=Language(m.language_typescript()), ext={".ts"}, **common)
        cfg["tsx"]        = dict(lang=Language(m.language_tsx()),        ext={".tsx"}, **common)
    except Exception: pass
    try:
        import tree_sitter_dart as m
        cfg["dart"] = dict(
            lang=Language(m.language()),
            ext={".dart"},
            defs={"class_definition","enum_declaration","mixin_declaration","extension_declaration","function_signature"},
            tdefs={"class_definition","enum_declaration","mixin_declaration","extension_declaration"},
            refnodes={"identifier","type_identifier"},
        )
    except Exception: pass
    try:
        import tree_sitter_python as m
        cfg["python"] = dict(
            lang=Language(m.language()),
            ext={".py"},
            defs={"class_definition","function_definition"},
            tdefs={"class_definition"},   # only classes carry edges in py (functions collide)
            refnodes={"identifier"},
        )
    except Exception: pass
    return cfg

CFG = _langs()
EXT2LANG = {e: name for name, c in CFG.items() for e in c["ext"]}
PARSERS = {name: Parser(c["lang"]) for name, c in CFG.items()}

SKIP = ("/node_modules/","/.git/","/dist/","/build/","/.next/","/.venv/","/venv/",
        "/__pycache__/","/vendor/","/coverage/","/.turbo/","/out/","/bin/","/obj/","/Library/",
        "/.dart_tool/","/ios/Pods/","/.symlinks/","/.claude/","/ephemeral/","/windows/flutter/",
        "/temp/","/tmp/","/extracted/","/_extracted/")
GENERATED = (".d.ts",".freezed.dart",".g.dart",".gr.dart",".config.dart",".mocks.dart",".pb.dart")

def sha(b): return hashlib.sha256(b).hexdigest()

def list_files(root: Path):
    out=[]
    for p in root.rglob("*"):
        if not p.is_file(): continue
        s=str(p)
        if any(k in s for k in SKIP): continue
        if s.endswith(GENERATED): continue       # generated/ambient decls = noise
        if p.suffix in EXT2LANG: out.append(p)
    return sorted(out)

def header(src,n):
    body=n.child_by_field_name("body") or n.child_by_field_name("value")
    end=body.start_byte if body else n.end_byte
    h=src[n.start_byte:end].decode("utf-8","replace")
    return re.sub(r"\s+"," ",h).strip().rstrip("{").strip()[:200]

def extract(path, src, langname):
    c=CFG[langname]; parser=PARSERS[langname]
    tree=parser.parse(src); root=tree.root_node
    defs,tdefs,refs,skel=set(),set(),Counter(),[]
    DEF,TDEF,REF=c["defs"],c["tdefs"],c["refnodes"]
    def visit(n):
        if n.type in DEF:
            nm=n.child_by_field_name("name")
            if nm:
                name=nm.text.decode()
                defs.add(name)
                if n.type in TDEF: tdefs.add(name); skel.append(f"  {header(src,n)}")
                else: skel.append(f"    {header(src,n)}")
        if n.type in REF: refs[n.text.decode()]+=1
        for ch in n.children: visit(ch)
    visit(root)
    return defs,tdefs,refs,skel

def pagerank(nodes,edges,d=0.85,iters=50):
    N=len(nodes)
    if not N: return {}
    out_w={u:sum(edges.get(u,{}).values()) for u in nodes}
    pr={u:1.0/N for u in nodes}; base=1.0/N
    inc=defaultdict(list)
    for u,dst in edges.items():
        for v,w in dst.items(): inc[v].append((u,w))
    for _ in range(iters):
        dangle=sum(pr[u] for u in nodes if out_w[u]==0)
        new={}
        for v in nodes:
            r=(1-d)*base+d*dangle*base
            for u,w in inc.get(v,()): r+=d*pr[u]*(w/out_w[u])
            new[v]=r
        pr=new
    return pr

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("root"); ap.add_argument("--top",type=int,default=25)
    ap.add_argument("--budget",type=int,default=2500); ap.add_argument("--tag",default="run")
    ap.add_argument("--max-definers",type=int,default=8)
    a=ap.parse_args()
    root=Path(a.root).resolve()
    files=list_files(root)
    man_path=HERE/f"manifest-{a.tag}.json"
    prev=json.loads(man_path.read_text()) if man_path.exists() else {}

    t0=time.time(); manifest={}; reused=0; lang_hist=Counter()
    fdefs,ftdefs,frefs,fskel={},{},{},{}; full_tok=0
    for p in files:
        rel=str(p.relative_to(root)); b=p.read_bytes(); h=sha(b); manifest[rel]=h
        full_tok+=TOK(b.decode("utf-8","replace"))
        if prev.get(rel)==h: reused+=1
        ln=EXT2LANG[p.suffix]; lang_hist[ln]+=1
        try: d,td,r,sk=extract(p,b,ln)
        except Exception: d,td,r,sk=set(),set(),Counter(),[]
        fdefs[rel]=d; ftdefs[rel]=td; frefs[rel]=r; fskel[rel]=sk
    parse_t=time.time()-t0

    sym=defaultdict(set)
    for rel,td in ftdefs.items():
        for n in td: sym[n].add(rel)
    edges=defaultdict(lambda:defaultdict(float))
    for rel,refs in frefs.items():
        for name,cnt in refs.items():
            ds=sym.get(name,())
            if not ds or len(ds)>a.max_definers: continue
            w=cnt/len(ds)
            for dd in ds:
                if dd!=rel: edges[rel][dd]+=w
    edges={u:dict(v) for u,v in edges.items()}

    nodes=[str(p.relative_to(root)) for p in files]
    pr=pagerank(nodes,edges)
    ranked=sorted(nodes,key=lambda r:pr.get(r,0),reverse=True)

    out=[];used=0
    for rel in ranked[:a.top]:
        blk=[f"\n### {rel}  (rank={pr[rel]:.4f})"]+fskel[rel][:30]
        bt=TOK("\n".join(blk))
        if used+bt>a.budget: break
        out+=blk; used+=bt
    (HERE/f"repo-map-{a.tag}.txt").write_text("\n".join(out).strip()+"\n")
    man_path.write_text(json.dumps(manifest))
    stats=dict(tag=a.tag, root=str(root), files=len(files),
        languages=dict(lang_hist), symbols_type_defs=len(sym),
        edges=sum(len(v) for v in edges.values()), parse_time_sec=round(parse_t,2),
        cache_unchanged=reused, full_source_tokens_est=full_tok, repo_map_tokens_est=used,
        compression_ratio=round(full_tok/max(1,used),1),
        top12=[(r,round(pr[r],4)) for r in ranked[:12]])
    (HERE/f"ranked-{a.tag}.json").write_text(json.dumps(stats,indent=2))
    print(json.dumps({k:v for k,v in stats.items() if k!="top12"},indent=2))
    print("TOP12:");[print(f"   {w:.4f}  {r}") for r,w in stats["top12"]]

if __name__=="__main__": main()
