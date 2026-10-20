#!/usr/bin/env bash
# check-gate-headers.sh — fails when an engine ask drifts from the lane gate catalog
# (`lane-policy.sh catalog`, the ONE authority; docs/LANE_GATES.md mirrors it).
#
# Why: a lane relays each question its engine asks, and `lane-policy.sh decide` answers a routine one only
# when its `header` is the gate's catalog code and its options are the catalog's labels. Wave 7 (run
# automate-2026-10-15-163325) showed both drifting at the ask: Launch Pad brief-save asks arrived with
# header "Save brief", an empty header, or `LP-SAVE` with half its labels, so the owner's wave policy
# `LP-SAVE=Save and exit` never fired; AUT-WAIVE and dismissed-finding asks carried `header: ""`. The
# prose said "a human-only gate is asked with no code", which invited a blank or an improvised header.
#
# Surface: the engine prose (`agents/*.md`, `commands/*.md`, `skills/**/*.md`) and the next-step
# emitters (`scripts/*-next-step.sh`). A BLOCK is a run of non-blank lines (a paragraph, a list, a jq
# program); an ASK SITE is a block plus the block right after it (the "use the ask tool with header X:"
# line and its options list, a blank line apart). A label is QUOTED when it appears as `label` or
# "label" (a ` (Recommended)` marker allowed).
#   G1  no `header: ""` / `"header":""` anywhere in the surface (an ask always names its gate);
#   G2  every `header: "<CODE-shaped>"` names a catalog code (no typo or invented code);
#   G3  a block carrying `header: "<code>"` quotes, in its ask site, every one of that gate's catalog
#       labels (`?` stripped; a free-text gate has none) — the catalog's options, not a paraphrase;
#   G4  a block that quotes every label of a gate names, in it or the block before it, one of the codes
#       that carry that label set (prose spelling out a gate's options says which gate it is) — maximal
#       sets only, so a block
#       quoting AUT-DISMISS's labels is not also asked to name AUT-PENDING (a subset of them);
#   G5  every catalog code has at least one `header: "<code>"` ask site in the surface, or — for a
#       supervisor gate — an `sn_ask <step> <code>` emitter call (sn_ask's header IS its gate code).
#
# Usage: check-gate-headers.sh [--root <plugin dir>]   (default: this script's plugin, ../)
# Exit:  0 clean · 1 drift (one `check-gate-headers: <rule> <where> — <what>` line each) · 2 usage /
#        the catalog or python3 unavailable (fail CLOSED: a check that cannot run never reads clean).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) [ "$#" -ge 2 ] || { echo "check-gate-headers: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "check-gate-headers: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "check-gate-headers: no plugin dir at $ROOT" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "check-gate-headers: python3 unavailable — cannot check" >&2; exit 2; }
CAT="$(bash "$ROOT/scripts/lane-policy.sh" catalog 2>/dev/null)"
[ -n "$CAT" ] || { echo "check-gate-headers: lane-policy.sh catalog printed nothing — cannot check" >&2; exit 2; }
CAT="$CAT" python3 - "$ROOT" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
rows = {}
for line in os.environ["CAT"].splitlines():
    code, policy, labels, _purpose = line.split("\t")
    labs = [] if labels == "(free text)" else [l[:-1] if l.endswith("?") else l for l in labels.split("|")]
    rows[code] = labs
by_set = {}
for code, labs in rows.items():
    if labs:
        by_set.setdefault(frozenset(labs), []).append(code)
prose = sorted(set(glob.glob(os.path.join(root, "agents", "*.md")) + glob.glob(os.path.join(root, "commands", "*.md"))
                   + glob.glob(os.path.join(root, "skills", "**", "*.md"), recursive=True)))
emitters = sorted(glob.glob(os.path.join(root, "scripts", "*-next-step.sh")))
HDR = re.compile(r'header:\s*"([^"]*)"|"header":\s*"([^"]*)"')
SHAPE = re.compile(r'^[A-Z][A-Z0-9]*(-[A-Z0-9]+)+$')
bad = []
def say(rule, where, what):
    bad.append("check-gate-headers: %s %s — %s" % (rule, where, what))
def quoted(label, block):
    return re.search(r'[`"]' + re.escape(label) + r'(\s*\(Recommended\))?[`"]', block) is not None
def blocks(path):
    cur, start = [], 0
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    for i, line in enumerate(lines, 1):
        if line.strip():
            if not cur:
                start = i
            cur.append(line)
        elif cur:
            yield start, "\n".join(cur); cur = []
    if cur:
        yield start, "\n".join(cur)
anchored = set()
for path in prose + emitters:
    rel = os.path.relpath(path, root)
    bl = list(blocks(path))
    for i, (start, block) in enumerate(bl):
        where = "%s:%d" % (rel, start)
        site = block + ("\n" + bl[i + 1][1] if i + 1 < len(bl) else "")
        before = (bl[i - 1][1] + "\n" if i > 0 else "") + block
        if path in emitters:
            for m in re.finditer(r'\bsn_ask\s+\S+\s+"?([A-Z][A-Z0-9-]+)"?', block):
                if m.group(1) in rows:
                    anchored.add(m.group(1))
        heads = [m.group(1) if m.group(1) is not None else m.group(2) for m in HDR.finditer(block)]
        for m in re.finditer(r'header:\s*\((.*)', block):   # a jq `header: (if … then "A" else "B" end)`
            heads += [c for c in re.findall(r'"([^"]*)"', m.group(1)) if SHAPE.match(c) or c == ""]
        for h in heads:
            if h == "":
                say("G1", where, 'an empty header (`header: ""`) — ask with the gate\'s catalog code')
                continue
            if not SHAPE.match(h):
                continue   # a plain-word header outside the catalog (e.g. /telemetry's "Target repo")
            if h not in rows:
                say("G2", where, 'header "%s" is not a catalog code (lane-policy.sh catalog)' % h)
                continue
            anchored.add(h)
            missing = [l for l in rows[h] if not quoted(l, site)]
            if missing:
                say("G3", where, 'the %s ask does not offer its catalog label(s) %s' % (h, ", ".join('"%s"' % l for l in missing)))
        matched = [s for s in by_set if all(quoted(l, block) for l in s)]
        for s in matched:
            if any(s < o for o in matched):
                continue
            codes = by_set[s]
            if not any(re.search(r'(?<![A-Z0-9-])' + re.escape(c) + r'(?![A-Z0-9-])', before) for c in codes):
                say("G4", where, 'spells out the options of %s without naming its code' % " / ".join(codes))
for code in rows:
    if code not in anchored:
        say("G5", "catalog", '%s has no `header: "%s"` ask site in agents/ commands/ skills/ or a next-step emitter' % (code, code))
for line in bad:
    print(line)
sys.exit(1 if bad else 0)
PY
