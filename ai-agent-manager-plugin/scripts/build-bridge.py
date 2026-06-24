#!/usr/bin/env python3
"""
build-bridge.py — Local Twin BRIDGE builder (re-runnable, READ-ONLY toward graph+findings).

Graduated from the Step-4 scratch spike (.supervisor/scratch/local-twin-step4/build_bridge.py).
This shipped engine keeps ONLY the per-community bridge INDEX build; the spike's retrospective-FN
gate (gate.json/gate.md + stratification) was the Step-4 PROCEED gate — already passed — and is
intentionally DROPPED here.

WHAT IT DOES
  Joins the plugin's accumulated findings to the code graph's communities so a later READER
  (read-bridge.sh) can answer "what do we already know about the areas this change touches?":

      finding.changed_paths  ->  graph node.source_file  ->  node.community (integer)

  A finding can span MANY communities (many-to-many). Communities are integer-only in graph.json;
  a readable label is derived from each community's top member source_files. Secondary LESSONS are
  attached to communities by explicit file-name mention.

INPUTS (all READ-ONLY; resolved against --root):
  - graphify-out/graph.json                  (the code graph: nodes carry source_file + community)
  - .supervisor/postmortem/results.jsonl     (postmortem findings; some carry changed_paths)
  - .supervisor/heal-signal/joined.jsonl     (labeled PRs — read for self_heal_miss enrichment)
  - .supervisor/memory/LESSONS.md            (lessons; category-scoped, file-mention anchor)
  - git (subprocess)                         (backfill changed_paths from squash-merge commits)

  Repo root + output dir are ARG-DRIVEN (the spike's hard-coded ROOT=../../.. constant is gone, so
  this runs correctly from the shipped scripts/ location).

REPO IDENTITY (machine-agnostic — NO hard-coded slug):
  The current repo slug (owner/repo) is DERIVED from the git remote (mirrors read-postmortem.sh's
  CUR_REPO: parsed from remote.origin.url, case-insensitive, strip .git). That derived slug is used
  for BOTH the finding repo filter AND the pr_url fallback. When NO remote is resolvable the tool
  FAILS OPEN (unscoped — keeps all findings rather than dropping every one).

OUTPUTS (gitignored, fully regenerated each run) under --out (default .supervisor/bridge/):
  - bridge.json  — machine index the reader consumes (schema below)
  - bridge.md    — human "what do we know here?" per community

==============================================================================================
bridge.json SCHEMA (consumed by read-bridge.sh — Subtasks 2/3)
==============================================================================================
{
  "built_at_commit": "<sha>",            # copied verbatim from graph.json (staleness anchor)
  "head_commit": "<sha>",                # git HEAD at build time (for the reader's staleness note)
  "graph_fresh_vs_head": <bool>,         # convenience: built_at_commit == HEAD
  "generated_repo": "owner/repo" | null, # derived slug, or null when no remote (fail-open)

  # LOAD-BEARING reader JOIN SURFACE — keyed by the RAW source_file EXACTLY as the graph stores it:
  # repo-root-relative WITH the "ai-agent-manager-plugin/" prefix (root files like CHANGELOG.md have
  # no prefix). This is byte-identical to `git diff --name-only` output (the reader's input). The
  # spike's strip_prefix() is for LABELS/display ONLY and is NEVER applied to these keys.
  "file_to_communities": { "<source_file>": [<community_id_int>, ...], ... },

  # O(1) reader lookup: communities is a DICT keyed by the STRINGIFIED community id (NOT a list).
  "communities": {
    "<id>": {
      "community": <id_int>,
      "label": "<readable label>",
      "member_file_count": <int>,        # # distinct member source_files (god-node suppression input)
      "ubiquitous": <bool>,              # deterministic god-node flag (see UBIQUITOUS rule below)
      "top_files": ["<stripped display path>", ...],
      "findings": [
        { "pr": <int>, "miss": <int>,    # self_heal_misses count for that PR
          "miss_classes": { "<class>": <count>, ... },   # root-cause class histogram (may be {})
          "self_heal_miss": <bool> },    # did this finding record a self-heal miss?
        ...
      ],
      "lessons": [
        { "id": "<lesson id>", "category": "<category>", "summary": "<lesson TEXT, <=200 chars>" },
        ...
      ]
    },
    ...
  }
}

UBIQUITOUS (god-node) RULE — deterministic, documented so the reader stays cheap:
  A community is stamped `ubiquitous: true` iff its member_file_count >= UBIQUITOUS_MEMBER_THRESHOLD
  (default 12). Broadly-connected "god-node" communities attach to nearly every diff and carry
  findings from almost every PR; surfacing them as "this area churned" is noise. The reader uses
  this flag (Subtask 2 step 2a) to down-weight/drop them so the advisory stays SPECIFIC. This is
  advisory tuning, never a gate. Override the threshold with --ubiquitous-threshold N.

STALENESS: only an ABSENT graph/bridge is a silent no-op (handled by the wrapper + the reader). A
  STALE graph (HEAD past built_at_commit) STILL emits — the reader downgrades it to a "hint" caveat.
  This builder always records built_at_commit + head_commit so the reader can compute that.

EXIT: 0 on a successful build AND on a missing graph/python (robust by itself; the wrapper also
  fail-safe-skips). It WRITES only under --out.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

UBIQUITOUS_MEMBER_THRESHOLD_DEFAULT = 12
PLUGIN_PREFIX = "ai-agent-manager-plugin/"


def log(msg):
    print(msg, file=sys.stderr)


def derive_repo_slug(root):
    """owner/repo from remote.origin.url (case-insensitive host strip, .git stripped).
    Returns None when no remote / parse fails (fail-open / unscoped)."""
    try:
        url = subprocess.run(
            ["git", "config", "--get", "remote.origin.url"],
            cwd=root, capture_output=True, text=True, timeout=15,
        ).stdout.strip()
    except Exception:
        return None
    if not url:
        return None
    # strip scheme/host: git@host:owner/repo.git  OR  https://host/owner/repo.git
    slug = re.sub(r"^(git@|https?://)[^/:]+[:/]+", "", url)
    slug = re.sub(r"\.git$", "", slug)
    return slug.strip() or None


def strip_prefix(p):
    return p[len(PLUGIN_PREFIX):] if p.startswith(PLUGIN_PREFIX) else p


def load_jsonl(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                # fail-safe: skip a malformed line, never crash the build
                continue
    return rows


def main():
    ap = argparse.ArgumentParser(description="Build the findings->community bridge index.")
    ap.add_argument("--root", default=None,
                    help="repo root (default: git rev-parse --show-toplevel, else CWD)")
    ap.add_argument("--out", default=None,
                    help="output dir (default: <root>/.supervisor/bridge)")
    ap.add_argument("--ubiquitous-threshold", type=int,
                    default=UBIQUITOUS_MEMBER_THRESHOLD_DEFAULT,
                    help="member_file_count at/above which a community is flagged ubiquitous "
                         f"(default {UBIQUITOUS_MEMBER_THRESHOLD_DEFAULT})")
    args = ap.parse_args()

    # ---- resolve root ----
    root = args.root
    if not root:
        try:
            root = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True, text=True, timeout=15,
            ).stdout.strip()
        except Exception:
            root = ""
    if not root:
        root = os.getcwd()
    root = os.path.abspath(root)

    graph_path = os.path.join(root, "graphify-out", "graph.json")
    postmortem_path = os.path.join(root, ".supervisor", "postmortem", "results.jsonl")
    joined_path = os.path.join(root, ".supervisor", "heal-signal", "joined.jsonl")
    lessons_path = os.path.join(root, ".supervisor", "memory", "LESSONS.md")
    outdir = args.out or os.path.join(root, ".supervisor", "bridge")
    # A RELATIVE --out resolves against --root (not the process CWD, which need not equal root).
    if args.out and not os.path.isabs(args.out):
        outdir = os.path.join(root, args.out)

    # ---- graph absent => robust no-op (exit 0), matching the wrapper's fail-safe contract ----
    if not os.path.exists(graph_path):
        log(f"build-bridge: no graph at {graph_path} — skipping (nothing written).")
        return 0

    try:
        with open(graph_path) as f:
            graph = json.load(f)
    except Exception as e:
        log(f"build-bridge: graph.json unreadable ({e}) — skipping (nothing written).")
        return 0

    repo_slug = derive_repo_slug(root)  # None => fail-open / unscoped
    built_at = graph.get("built_at_commit", "") or ""

    # ---- 1. graph indexes: file -> communities, community -> file counter ----
    file_to_comms = defaultdict(set)      # RAW source_file -> {community ids}
    comm_files = defaultdict(Counter)     # community -> Counter(source_file -> node_count)
    all_comms = set()
    for n in graph.get("nodes", []):
        c = n.get("community")
        sf = n.get("source_file")
        if c is None:
            continue
        all_comms.add(c)
        if sf:
            file_to_comms[sf].add(c)
            comm_files[c][sf] += 1

    def common_dir(files):
        if not files:
            return ""
        segs = [strip_prefix(f).split("/")[:-1] for f in files]
        if not any(segs):
            return ""
        out = []
        for parts in zip(*segs):
            if len(set(parts)) == 1:
                out.append(parts[0])
            else:
                break
        return "/".join(out)

    def label_for(c):
        fc = comm_files.get(c, Counter())
        if not fc:
            return f"community {c} (no file-backed members)"
        top = [f for f, _ in fc.most_common(8)]
        cd = common_dir(top)
        nfiles = len(fc)
        nnodes = sum(fc.values())
        top1 = strip_prefix(fc.most_common(1)[0][0])
        head = (cd + "/") if (cd and cd not in (".", "")) else top1
        return f"{head}  ({nfiles} files, {nnodes} nodes)"

    comm_label = {c: label_for(c) for c in all_comms}
    comm_topfiles = {c: [strip_prefix(f) for f, _ in comm_files[c].most_common(6)]
                     for c in all_comms}

    def paths_to_comms(paths):
        comms = set()
        for p in paths or []:
            if p in file_to_comms:
                comms |= file_to_comms[p]
        return comms

    # ---- 2. git backfill for changed_paths ----
    git_cache = {}

    def git_files_for_pr(num):
        if num in git_cache:
            return git_cache[num]
        files = []
        try:
            logout = subprocess.run(
                ["git", "log", "--all", "--format=%H\t%s"],
                cwd=root, capture_output=True, text=True, timeout=30,
            ).stdout
            sha = None
            pat = re.compile(r"\(#%d\)\s*$" % num)
            for line in logout.splitlines():
                h, _, subj = line.partition("\t")
                if pat.search(subj):
                    sha = h
                    break
            if sha:
                out = subprocess.run(
                    ["git", "show", "--name-only", "--format=", sha],
                    cwd=root, capture_output=True, text=True, timeout=30,
                ).stdout
                files = [ln.strip() for ln in out.splitlines() if ln.strip()]
        except Exception as e:
            log(f"  git backfill #{num} failed: {e}")
        git_cache[num] = files
        return files

    # ---- 3. findings corpus (postmortem records + heal-signal joins) ----
    pm_raw = load_jsonl(postmortem_path)
    # heal-signal joins (labeled PRs) — read for self_heal_miss enrichment. A missing/unreadable
    # file degrades to [] (load_jsonl is itself fail-safe), exactly like the postmortem corpus.
    joined_raw = load_jsonl(joined_path)

    def repo_matches(rec_repo):
        # Fail-open: no derived slug => keep everything (unscoped).
        if not repo_slug:
            return True
        # Fail-open: a record lacking a repo field is kept (legacy/hand-authored);
        # only records with a PRESENT, non-matching repo are scoped out.
        if rec_repo is None:
            return True
        return str(rec_repo).lower() == repo_slug.lower()

    # dedupe by PR number, keeping the record with the MAX self_heal_misses (floor-raising).
    # Both the postmortem corpus and the heal-signal joins feed the SAME by_num dict, so the
    # floor-raising rule applies uniformly: a PR present in both keeps whichever record carries
    # the higher self_heal_misses; a PR present ONLY in joined.jsonl still becomes a finding
    # (this is the documented "self_heal_miss enrichment").
    by_num = {}

    def _rich(x):
        # A record carries root-cause evidence if it has changed_paths or categories
        # (the postmortem corpus does; a heal-signal join does NOT).
        return bool(x.get("changed_paths") or x.get("categories"))

    def consider(rec):
        """Fold one already-repo-scoped record into by_num.

        Dedupe by PR number. When the same PR appears in BOTH corpora, RAISE the
        self_heal_misses floor and backfill pr_url, but PRESERVE the richer record's
        changed_paths / categories evidence. A leaner heal-signal join must never
        overwrite the postmortem row's root-cause classes / paths — doing so would
        emit empty miss_classes and force a fragile git-log path backfill (which can
        even drop the finding from its community entirely when the backfill finds
        nothing). Symmetric in arrival order, so a postmortem row arriving after a
        leaner joined row still wins the evidence fields while keeping the floor."""
        num = rec.get("number")
        if num is None:
            return
        prev = by_num.get(num)
        if prev is None:
            by_num[num] = dict(rec)
            return
        # Prefer whichever record actually carries evidence as the base to preserve.
        base = rec if (_rich(rec) and not _rich(prev)) else prev
        other = prev if base is rec else rec
        merged = dict(base)
        merged["self_heal_misses"] = max(prev.get("self_heal_misses", 0) or 0,
                                         rec.get("self_heal_misses", 0) or 0)
        if not merged.get("pr_url") and other.get("pr_url"):
            merged["pr_url"] = other.get("pr_url")
        by_num[num] = merged

    for r in pm_raw:
        if not repo_matches(r.get("repo")):
            continue
        consider(r)

    # joined.jsonl uses "owner_repo" (NOT "repo") for the slug and carries no changed_paths /
    # categories — the finding-build loop git-backfills paths, derives pr_url from repo_slug+num,
    # and treats absent categories as []. So a joined row only needs to contribute its
    # self_heal_misses floor (+ pr_url when present).
    for r in joined_raw:
        if not repo_matches(r.get("owner_repo")):
            continue
        consider({
            "number": r.get("number"),
            "self_heal_misses": r.get("self_heal_misses", 0) or 0,
            "pr_url": r.get("pr_url"),
        })

    findings = []
    for num, r in sorted(by_num.items()):
        paths = r.get("changed_paths")
        if not (isinstance(paths, list) and paths):
            paths = git_files_for_pr(num)
        comms = paths_to_comms(paths)
        classes = [cat.get("class") for cat in (r.get("categories") or []) if cat.get("class")]
        misses = r.get("self_heal_misses", 0) or 0
        pr_url = r.get("pr_url")
        if not pr_url and repo_slug:
            pr_url = f"https://github.com/{repo_slug}/pull/{num}"
        findings.append({
            "number": num,
            "self_heal_misses": misses,
            "is_miss": misses > 0,
            "miss_classes": classes,
            "miss_class_counts": dict(Counter(classes)),
            "communities": sorted(comms),
            "pr_url": pr_url,
        })

    # ---- 4. LESSONS (secondary): attach by explicit file-name mention ----
    lesson_rows = []
    graph_basenames = {os.path.basename(f): f for f in file_to_comms}  # basename -> a repo path
    if os.path.exists(lessons_path):
        cur_cat = None
        with open(lessons_path) as f:
            for line in f:
                m = re.match(r"^##\s+(.+)$", line)
                if m:
                    cur_cat = m.group(1).strip()
                    continue
                lm = re.match(r"^- \[([0-9a-f]+)\]\s+(.*)$", line.strip())
                if lm:
                    text = lm.group(2)
                    comms = set()
                    for bn, full in graph_basenames.items():
                        if "." in bn and re.search(r"\b" + re.escape(bn) + r"\b", text):
                            comms |= file_to_comms[full]
                    lesson_rows.append({
                        "id": lm.group(1),
                        "category": cur_cat,
                        "summary": text[:200],   # carry the TEXT (graduation delta vs spike :270)
                        "communities": sorted(comms),
                    })

    # ---- 5. per-community index (DICT keyed by str id) ----
    communities = {}
    for c in sorted(all_comms):
        attached = sorted((fd for fd in findings if c in fd["communities"]),
                          key=lambda x: x["number"])
        member_file_count = len(comm_files[c])
        ubiquitous = member_file_count >= args.ubiquitous_threshold
        lessons_here = [lr for lr in lesson_rows if c in lr["communities"]]
        communities[str(c)] = {
            "community": c,
            "label": comm_label[c],
            "member_file_count": member_file_count,
            "ubiquitous": ubiquitous,
            "top_files": comm_topfiles[c],
            "findings": [
                {"pr": fd["number"], "miss": fd["self_heal_misses"],
                 "miss_classes": fd["miss_class_counts"], "self_heal_miss": fd["is_miss"]}
                for fd in attached
            ],
            "lessons": [
                {"id": lr["id"], "category": lr["category"], "summary": lr["summary"]}
                for lr in lessons_here
            ],
        }

    # ---- 6. freshness ----
    try:
        head_sha = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root,
            capture_output=True, text=True, timeout=15,
        ).stdout.strip()
    except Exception:
        head_sha = ""
    graph_fresh = bool(built_at) and bool(head_sha) and (
        head_sha.startswith(built_at) or built_at.startswith(head_sha[:12]))

    # ---- 7. emit ----
    os.makedirs(outdir, exist_ok=True)
    bridge = {
        "built_at_commit": built_at,
        "head_commit": head_sha,
        "graph_fresh_vs_head": graph_fresh,
        "generated_repo": repo_slug,
        "ubiquitous_member_threshold": args.ubiquitous_threshold,
        "file_to_communities": {sf: sorted(cs) for sf, cs in file_to_comms.items()},
        "communities": communities,
    }
    with open(os.path.join(outdir, "bridge.json"), "w") as f:
        json.dump(bridge, f, indent=2)

    # ---- bridge.md (human "what do we know here?") ----
    n_with_findings = sum(1 for cobj in communities.values() if cobj["findings"])
    n_with_miss = sum(1 for cobj in communities.values()
                      if any(fd["self_heal_miss"] for fd in cobj["findings"]))
    n_findings = len(findings)
    n_miss_findings = sum(1 for fd in findings if fd["is_miss"])
    lines = [
        "# BRIDGE — per-community findings index", "",
        f"> Re-runnable. Graph built_at_commit={built_at[:12]} · HEAD={head_sha[:12]} · fresh={graph_fresh}",
        f"> repo={repo_slug or '(unscoped — no remote)'}",
        f"> {len(all_comms)} communities · {n_with_findings} carry a finding · "
        f"{n_with_miss} carry a prior MISS · {n_findings} findings ({n_miss_findings} misses)", "",
        "Only communities WITH at least one finding are shown (the rest are 'novel — nothing known yet').",
        "",
    ]

    def sort_key(cid):
        cobj = communities[cid]
        nmiss = sum(1 for fd in cobj["findings"] if fd["self_heal_miss"])
        return (-nmiss, -len(cobj["findings"]), cobj["community"])

    for cid in sorted(communities, key=sort_key):
        cobj = communities[cid]
        if not cobj["findings"]:
            continue
        nmiss = sum(1 for fd in cobj["findings"] if fd["self_heal_miss"])
        ubiq = " [ubiquitous god-node — down-weighted by reader]" if cobj["ubiquitous"] else ""
        lines.append(f"## community {cid} — {cobj['label']}{ubiq}")
        lines.append(f"- top files: {', '.join('`'+t+'`' for t in cobj['top_files'])}")
        fr = ", ".join(
            f"#{x['pr']}{'★' if x['self_heal_miss'] else ''}({x['miss']}m)"
            for x in cobj["findings"])
        lines.append(f"- findings ({len(cobj['findings'])}, {nmiss} misses ★): {fr}")
        miss_hist = Counter()
        for fd in cobj["findings"]:
            if fd["self_heal_miss"]:
                miss_hist.update(fd["miss_classes"])
        if miss_hist:
            lines.append(f"- miss-class histogram: {dict(miss_hist.most_common())}")
        if cobj["lessons"]:
            for l in cobj["lessons"]:
                lines.append(f"- lesson [{l['id']}] ({l['category']}): {l['summary']}")
        lines.append("")
    with open(os.path.join(outdir, "bridge.md"), "w") as f:
        f.write("\n".join(lines))

    # ---- console summary ----
    print("=== BRIDGE ===")
    print(f"repo: {repo_slug or '(unscoped — no remote)'}")
    print(f"communities: {len(all_comms)} | with-finding: {n_with_findings} | with-miss: {n_with_miss}")
    print(f"findings: {n_findings} ({n_miss_findings} misses) | lessons: {len(lesson_rows)}")
    print(f"graph fresh vs HEAD: {graph_fresh} (built_at={built_at[:12]} head={head_sha[:12]})")
    print(f"wrote: {os.path.join(outdir, 'bridge.json')} + bridge.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
