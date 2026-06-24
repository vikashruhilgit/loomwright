#!/usr/bin/env bash
# test-build-bridge.sh — self-tests for the findings→community BRIDGE tool
# (build-bridge.py + build-bridge.sh builder; read-bridge.sh reader; Local Twin Step 5).
# Mirrors test-measure-heal-signal.sh / test-read-postmortem.sh convention: runs in isolated
# temp git repos with SYNTHETIC fixtures, NEVER touches the real .supervisor/bridge or the real
# graphify-out/graph.json. The harness itself fails LOUD (exit 1 on any genuine assertion failure)
# — that is a CI gate, distinct from the runtime scripts' always-exit-0 fail-safe contract, which
# this very test asserts.
#
# Covers BOTH scripts:
#   Builder (build-bridge.sh):
#     - builds bridge.json + bridge.md from a synthetic graph + findings
#     - READ-ONLY toward inputs (the fixture tree is byte-identical before/after)
#     - exit 0 on missing graph and on missing python (fail-safe skip; jq absence is irrelevant
#       to the builder)
#   Reader (read-bridge.sh):
#     - hit → bounded advisory; no-hit → EMPTY; absent bridge → silent exit 0
#     - stale graph (HEAD != built_at_commit) → STILL emits, WITH the hint caveat (NOT a no-op)
#     - arg-precedence / no-stdin-block; advisory-only (never a gating token), exit 0 on every path
#
# The FOUR validated silent-failure modes (the point of this test):
#   1. PATH-FORM JOIN (claim 3 / Notes 8): graph source_file carries the "ai-agent-manager-plugin/"
#      prefix; the RAW prefixed path HITS, the stripped form does NOT — join keys are raw, never
#      strip_prefix-ed.
#   2. REPO-SLUG DERIVATION (claim 2 / Notes 6): slug derived from the git remote — a finding whose
#      repo matches is KEPT; a cross-repo finding is FILTERED OUT; with NO remote the build FAILS
#      OPEN (unscoped — keeps the findings).
#   3. LESSONS INGESTION (claim 4): a LESSONS.md-anchored lesson lands in the community's lessons[]
#      with a NON-EMPTY summary (the lesson TEXT), and that text surfaces in the reader's line.
#   4. GOD-NODE SUPPRESSION (step 2a): a ubiquitous community is dropped while a specific
#      finding-bearing community survives.
#
# Exit 0 = all pass, 1 = any failure.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SH="$HERE/build-bridge.sh"
READ_SH="$HERE/read-bridge.sh"
PY="$(command -v python3 || command -v python || true)"
JQ="$(command -v jq || true)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if [ -z "$PY" ]; then echo "python3 unavailable — cannot self-test"; exit 1; fi
if [ -z "$JQ" ]; then echo "jq unavailable — cannot self-test"; exit 1; fi

# ---- fixture builders -------------------------------------------------------
# new git repo with an identity + an initial commit (so HEAD resolves).
newrepo() {
  local d; d="$(mktemp -d)"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && echo seed > seed.txt && git add seed.txt && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "$d"
}

# write_graph <repo> <built_at_commit>
# Writes a synthetic graphify-out/graph.json. Nodes (each {source_file, community}):
#   community 1 — SPECIFIC, finding-bearing: ai-agent-manager-plugin/agents/supervisor.md (prefixed!)
#                 (note the RAW prefixed source_file — this is the path-form-join probe). This same
#                 community also owns the lesson-anchor file "lessonfile.md" so the attached lesson
#                 surfaces via a FINDING-BEARING community (the reader drops finding-less communities).
#   community 2 — UBIQUITOUS god-node: 14 distinct member files (>= default threshold 12)
write_graph() {
  local repo="$1" built_at="$2"
  mkdir -p "$repo/graphify-out"
  {
    printf '{\n  "built_at_commit": "%s",\n  "directed": false,\n  "multigraph": false,\n  "graph": {},\n  "nodes": [\n' "$built_at"
    # community 1 — specific finding-bearing community, RAW prefixed path
    printf '    {"id":"n_sup","source_file":"ai-agent-manager-plugin/agents/supervisor.md","community":1},\n'
    printf '    {"id":"n_sup2","source_file":"ai-agent-manager-plugin/agents/supervisor.md","community":1},\n'
    # lesson-anchor file — in community 1 (the SAME finding-bearing community) so the lesson, which the
    # builder attaches by basename mention ("lessonfile.md"), surfaces through a surviving community.
    printf '    {"id":"n_lf","source_file":"ai-agent-manager-plugin/skills/lessonfile.md","community":1},\n'
    # community 2 — ubiquitous god-node: 14 distinct member source_files (>= threshold 12)
    local i
    for i in $(seq 1 14); do
      local comma=","
      printf '    {"id":"n_g%s","source_file":"ai-agent-manager-plugin/god/file%s.md","community":2}%s\n' "$i" "$i" "$comma"
    done
    # also give the god-node a finding-bearing input file so it would emit if NOT suppressed
    printf '    {"id":"n_gx","source_file":"ai-agent-manager-plugin/god/touched.md","community":2}\n'
    printf '  ],\n  "links": []\n}\n'
  } > "$repo/graphify-out/graph.json"
}

# write_findings <repo> <repo_slug_for_matching> [cross_repo_slug]
# Writes .supervisor/postmortem/results.jsonl. The supervisor.md finding records a self_heal_miss
# (so community 1 is finding-bearing with a miss). The god/touched.md finding makes community 2
# finding-bearing (so suppression — not "no findings" — is what drops it). An optional cross-repo
# finding (different repo slug, same path) tests the repo filter.
write_findings() {
  local repo="$1" slug="$2" cross="${3:-}"
  mkdir -p "$repo/.supervisor/postmortem"
  {
    "$JQ" -cn --arg repo "$slug" '{schema_version:1, number:101, repo:$repo, branch:"b1",
       pr_url:"u1", changed_paths:["ai-agent-manager-plugin/agents/supervisor.md"],
       categories:[{round:1,class:"drift",self_heal_miss:true,flow_stage:"self_heal",evidence:"x"}],
       self_heal_misses:2, flow_stages:{self_heal:1}, summary:"specific area miss"}'
    "$JQ" -cn --arg repo "$slug" '{schema_version:1, number:102, repo:$repo, branch:"b2",
       pr_url:"u2", changed_paths:["ai-agent-manager-plugin/god/touched.md"],
       categories:[{round:1,class:"cross-ref",self_heal_miss:false,flow_stage:"worker",evidence:"y"}],
       self_heal_misses:0, flow_stages:{worker:1}, summary:"god-node touched"}'
    if [ -n "$cross" ]; then
      # SAME path as the specific finding but a DIFFERENT repo slug — must be FILTERED OUT when the
      # builder derives a slug, KEPT (fail-open) when no remote is resolvable.
      "$JQ" -cn --arg repo "$cross" '{schema_version:1, number:777, repo:$repo, branch:"bx",
         pr_url:"ux", changed_paths:["ai-agent-manager-plugin/agents/supervisor.md"],
         categories:[{round:1,class:"foreign-class",self_heal_miss:true,flow_stage:"self_heal",evidence:"z"}],
         self_heal_misses:9, flow_stages:{self_heal:9}, summary:"FOREIGN repo finding"}'
    fi
  } > "$repo/.supervisor/postmortem/results.jsonl"
}

# write_lessons <repo>  — one finding-area-anchored lesson mentioning lessonfile.md (community 1,
# the finding-bearing community — so the attached lesson surfaces through a surviving community).
write_lessons() {
  local repo="$1"; mkdir -p "$repo/.supervisor/memory"
  {
    printf '# Project Lessons\n\n'
    printf '## review-process\n'
    printf -- '- [abc12345] When editing lessonfile.md always re-run the doc-currency grep before passing — UNIQUE_LESSON_MARKER applies.\n'
  } > "$repo/.supervisor/memory/LESSONS.md"
}

# write_joined <repo> <owner_repo_slug> [floor_misses] [joined_only_pr]
# Writes .supervisor/heal-signal/joined.jsonl. joined.jsonl uses "owner_repo" (NOT "repo") for the
# slug and carries self_heal_misses but NO changed_paths/categories. Two enrichment rows:
#   - PR #101 (also in the postmortem corpus, community 1) with a HIGHER self_heal_misses floor —
#     the by_num floor-raising MUST adopt the joined miss count over the postmortem's.
#   - PR <joined_only_pr> (ABSENT from the postmortem corpus) — must still become a finding, with
#     changed_paths git-backfilled from a commit whose subject ends in "(#<pr>)".
write_joined() {
  local repo="$1" slug="$2" floor="${3:-5}" jonly="${4:-303}"
  mkdir -p "$repo/.supervisor/heal-signal"
  # Create squash-style commits so git_files_for_pr(...) can backfill changed_paths for BOTH the
  # joined-only PR AND #101 (whose floor-raising adopts the changed_paths-LESS joined record, so its
  # paths must be recovered via git — exercising the documented git-backfill enrichment path).
  ( cd "$repo" \
      && mkdir -p ai-agent-manager-plugin/agents \
      && printf 'pm-101 change\n' >> ai-agent-manager-plugin/agents/supervisor.md \
      && git add ai-agent-manager-plugin/agents/supervisor.md \
      && git commit -qm "fix: pm-101 area (#101)" \
      && printf 'joined-only change\n' >> ai-agent-manager-plugin/agents/supervisor.md \
      && git add ai-agent-manager-plugin/agents/supervisor.md \
      && git commit -qm "feat: joined-only enrichment (#$jonly)" ) >/dev/null 2>&1
  {
    "$JQ" -cn --arg or "$slug" --argjson floor "$floor" \
      '{owner_repo:$or, number:101, pr_url:"u1", heal_decision:"PASS", self_heal_misses:$floor,
        review_rounds:3, cell:"FN", label_summary:"joined floor-raise for 101"}'
    "$JQ" -cn --arg or "$slug" --argjson jonly "$jonly" \
      '{owner_repo:$or, number:$jonly, pr_url:"u303", heal_decision:"PASS", self_heal_misses:4,
        review_rounds:2, cell:"FN", label_summary:"joined-only finding"}'
  } > "$repo/.supervisor/heal-signal/joined.jsonl"
}

# set_remote <repo> <owner/repo>
set_remote() { ( cd "$1" && git remote add origin "https://github.com/$2.git" ) >/dev/null 2>&1; }

# Build the canonical fixture used by most tests: graph FRESH vs HEAD, slug matched, lessons present.
# Echoes the repo dir.
build_canonical() {
  local fresh="${1:-fresh}"   # "fresh" → graph built_at == HEAD; "stale" → != HEAD
  local R; R="$(newrepo)"
  set_remote "$R" "acme/widget"
  local head; head="$( cd "$R" && git rev-parse HEAD )"
  # Fresh fixture stamps an ABBREVIATED 7-char SHA (the production shape: graph.json's
  # built_at_commit is extracted as [0-9a-f]{7,}), so the §6 "fresh emits WITHOUT a caveat"
  # assertion exercises read-bridge.sh's prefix-tolerant staleness compare — an exact
  # full-vs-abbreviated != would (wrongly) mark every fresh graph stale.
  local built_at="${head:0:7}"
  [ "$fresh" = "stale" ] && built_at="0000000000000000000000000000000000000000"
  write_graph "$R" "$built_at"
  write_findings "$R" "acme/widget"
  write_lessons "$R"
  printf '%s' "$R"
}

run_build() {  # run_build <repo>  — invoke the wrapper from inside the repo.
  ( cd "$1" && bash "$BUILD_SH" ) >/dev/null 2>&1
}
B() { "$JQ" -r "$1" "$2"; }  # jq read helper

# ============================================================================
echo "== 1. builder produces bridge.json + bridge.md, READ-ONLY toward inputs =="
R1="$(build_canonical fresh)"
# Snapshot ONLY the input tree (exclude the .supervisor/bridge output dir the builder writes).
before="$( cd "$R1" && find . -type f -not -path './.supervisor/bridge/*' -exec shasum {} \; | sort )"
run_build "$R1"; rc=$?
after="$( cd "$R1" && find . -type f -not -path './.supervisor/bridge/*' -exec shasum {} \; | sort )"
BJSON="$R1/.supervisor/bridge/bridge.json"
BMD="$R1/.supervisor/bridge/bridge.md"
[ "$rc" -eq 0 ] && ok "builder exit 0" || no "builder non-zero exit ($rc)"
[ -s "$BJSON" ] && ok "bridge.json written + non-empty" || no "bridge.json missing/empty"
[ -s "$BMD" ] && ok "bridge.md written + non-empty" || no "bridge.md missing/empty"
[ "$before" = "$after" ] && ok "inputs byte-identical after build (READ-ONLY)" || no "builder MUTATED its inputs"

echo "== 2. PATH-FORM JOIN — raw prefixed key hits, stripped form does NOT (claim 3 / Notes 8) =="
# file_to_communities MUST key by the RAW prefixed source_file.
RAWHIT="$(B '.file_to_communities["ai-agent-manager-plugin/agents/supervisor.md"] // empty | tostring' "$BJSON")"
STRIPHIT="$(B '.file_to_communities["agents/supervisor.md"] // "ABSENT"' "$BJSON")"
if printf '%s' "$RAWHIT" | grep -q '1'; then ok "raw prefixed path keys file_to_communities → community 1"; else no "raw prefixed path absent from file_to_communities (got: $RAWHIT)"; fi
[ "$STRIPHIT" = "ABSENT" ] && ok "stripped 'agents/supervisor.md' is NOT a join key (not strip_prefix-ed)" || no "stripped form spuriously present as a join key ($STRIPHIT)"
# reader side: raw path HITS, stripped path produces EMPTY (no spurious hit).
out_raw="$( bash "$READ_SH" "ai-agent-manager-plugin/agents/supervisor.md" 2>/dev/null < /dev/null; )"
# the reader cd's to its own GITROOT, so run it from inside the fixture repo for a real lookup.
out_raw="$( cd "$R1" && bash "$READ_SH" "ai-agent-manager-plugin/agents/supervisor.md" </dev/null 2>/dev/null )"; rcr=$?
out_strip="$( cd "$R1" && bash "$READ_SH" "agents/supervisor.md" </dev/null 2>/dev/null )"; rcs=$?
[ "$rcr" -eq 0 ] && [ "$rcs" -eq 0 ] && ok "reader exit 0 for both raw + stripped lookups" || no "reader non-zero exit (raw=$rcr strip=$rcs)"
printf '%s' "$out_raw" | grep -q "area-knowledge\|area knowledge\|Advisory area-knowledge" && ok "raw prefixed path → reader emits an area-knowledge advisory (HIT)" || no "raw prefixed path did NOT produce a reader hit"
[ -z "$out_strip" ] && ok "stripped path → reader EMPTY (no spurious hit)" || no "stripped path spuriously hit: [$out_strip]"

echo "== 3. GOD-NODE SUPPRESSION — ubiquitous community dropped, specific survives (step 2a) =="
# Builder must stamp the 14-member god-node community 2 ubiquitous, community 1 NOT.
UBIQ2="$(B '.communities["2"].ubiquitous' "$BJSON")"
MFC2="$(B '.communities["2"].member_file_count' "$BJSON")"
UBIQ1="$(B '.communities["1"].ubiquitous' "$BJSON")"
[ "$UBIQ2" = "true" ] && ok "god-node community 2 stamped ubiquitous (member_file_count=$MFC2 >= 12)" || no "god-node community 2 NOT ubiquitous (ubiq=$UBIQ2 mfc=$MFC2)"
[ "$UBIQ1" = "false" ] && ok "specific community 1 NOT ubiquitous" || no "specific community 1 wrongly ubiquitous ($UBIQ1)"
# reader: touching the god-node file (community 2, finding-bearing) → suppressed → EMPTY.
out_god="$( cd "$R1" && bash "$READ_SH" "ai-agent-manager-plugin/god/touched.md" </dev/null 2>/dev/null )"; rcg=$?
[ "$rcg" -eq 0 ] && ok "reader exit 0 on a god-node-only touch" || no "reader non-zero exit on god-node touch ($rcg)"
[ -z "$out_god" ] && ok "god-node-only touch → reader EMPTY (ubiquitous community suppressed)" || no "god-node leaked into the advisory: [$out_god]"
# and the SPECIFIC community still surfaces (already asserted as out_raw non-empty above).
printf '%s' "$out_raw" | grep -q "self_heal_miss" && ok "specific community survives + surfaces self_heal_miss line" || no "specific community survival/self_heal_miss line missing"

echo "== 4. LESSONS INGESTION — anchored lesson in lessons[] with summary TEXT + surfaces in reader (claim 4) =="
# The lesson is anchored (by basename mention) to lessonfile.md, which lives in community 1 — the
# finding-bearing community — so the builder attaches it there and the reader (which drops
# finding-LESS communities) can surface it.
LES_SUM="$(B '.communities["1"].lessons[0].summary // empty' "$BJSON")"
LES_ID="$(B '.communities["1"].lessons[0].id // empty' "$BJSON")"
[ -n "$LES_SUM" ] && ok "community 1 carries a lesson with a non-empty summary" || no "community 1 lesson summary empty/missing"
printf '%s' "$LES_SUM" | grep -q "UNIQUE_LESSON_MARKER" && ok "lesson summary carries the lesson TEXT (not just id/category)" || no "lesson summary lacks the lesson text (got: $LES_SUM)"
[ "$LES_ID" = "abc12345" ] && ok "lesson id ingested" || no "lesson id wrong ($LES_ID)"
# reader: touching the lesson-anchored file → related-lessons line surfaces the TEXT.
out_les="$( cd "$R1" && bash "$READ_SH" "ai-agent-manager-plugin/skills/lessonfile.md" </dev/null 2>/dev/null )"; rcl=$?
[ "$rcl" -eq 0 ] && ok "reader exit 0 on lesson-anchored touch" || no "reader non-zero exit on lesson touch ($rcl)"
printf '%s' "$out_les" | grep -q "UNIQUE_LESSON_MARKER" && ok "lesson TEXT surfaces in the reader's related-lessons line" || no "lesson text NOT surfaced by reader: [$out_les]"

echo "== 5. REPO-SLUG DERIVATION — keep own-repo, filter cross-repo, fail-open with no remote (claim 2) =="
# (a) derived slug: own-repo finding KEPT, cross-repo finding FILTERED OUT.
Ra="$(newrepo)"; set_remote "$Ra" "acme/widget"
ha="$( cd "$Ra" && git rev-parse HEAD )"
write_graph "$Ra" "$ha"
write_findings "$Ra" "acme/widget" "intruder/elsewhere"   # +777 from a foreign repo, same path
write_lessons "$Ra"
run_build "$Ra"
BJa="$Ra/.supervisor/bridge/bridge.json"
GEN="$(B '.generated_repo // empty' "$BJa")"
PRS="$(B '[.communities["1"].findings[].pr] | sort | tostring' "$BJa")"
[ "$GEN" = "acme/widget" ] && ok "builder derived slug 'acme/widget' from the git remote (not hard-coded)" || no "derived slug wrong ($GEN)"
printf '%s' "$PRS" | grep -q '101' && ok "own-repo finding (#101) KEPT" || no "own-repo finding dropped ($PRS)"
printf '%s' "$PRS" | grep -q '777' && no "cross-repo finding (#777) leaked through the repo filter ($PRS)" || ok "cross-repo finding (#777) FILTERED OUT by the derived-slug filter"
# (b) NO remote → fail OPEN (unscoped): the foreign-repo finding is KEPT.
Rb="$(newrepo)"   # newrepo adds NO remote
hb="$( cd "$Rb" && git rev-parse HEAD )"
write_graph "$Rb" "$hb"
write_findings "$Rb" "acme/widget" "intruder/elsewhere"
write_lessons "$Rb"
run_build "$Rb"
BJb="$Rb/.supervisor/bridge/bridge.json"
GENb="$(B '.generated_repo // "null"' "$BJb")"
PRSb="$(B '[.communities["1"].findings[].pr] | sort | tostring' "$BJb")"
{ [ "$GENb" = "null" ] || [ -z "$GENb" ]; } && ok "no remote → generated_repo null (unscoped)" || no "expected null generated_repo with no remote ($GENb)"
printf '%s' "$PRSb" | grep -q '101' && printf '%s' "$PRSb" | grep -q '777' \
  && ok "no-remote fail-OPEN: BOTH own (#101) and foreign (#777) findings kept (unscoped)" \
  || no "fail-open broken — a finding was dropped with no remote ($PRSb)"

echo "== 6. STALENESS — stale graph STILL emits, WITH the hint caveat (NOT a no-op) =="
Rs="$(build_canonical stale)"   # built_at_commit deliberately != HEAD
run_build "$Rs"
out_stale="$( cd "$Rs" && bash "$READ_SH" "ai-agent-manager-plugin/agents/supervisor.md" </dev/null 2>/dev/null )"; rcst=$?
[ "$rcst" -eq 0 ] && ok "reader exit 0 on a stale graph" || no "reader non-zero exit on stale graph ($rcst)"
[ -n "$out_stale" ] && ok "stale graph STILL emits (not collapsed to a silent no-op)" || no "stale graph wrongly produced no output"
printf '%s' "$out_stale" | grep -qi "stale\|hint" && ok "stale emission carries the 'treat as a HINT / may be stale' caveat" || no "stale caveat line missing"
# A FRESH graph (R1, built_at == HEAD) must NOT carry the staleness caveat.
printf '%s' "$out_raw" | grep -qi "may be stale" && no "fresh graph wrongly emitted a staleness caveat" || ok "fresh graph emits WITHOUT a staleness caveat"

echo "== 7. ABSENT bridge → reader silent exit 0 (fail-safe no-op) =="
Rn="$(newrepo)"   # no graph, no bridge built
out_absent="$( cd "$Rn" && bash "$READ_SH" "ai-agent-manager-plugin/agents/supervisor.md" </dev/null 2>/dev/null )"; rca=$?
[ "$rca" -eq 0 ] && ok "reader exit 0 with absent bridge/graph" || no "reader non-zero exit absent bridge ($rca)"
[ -z "$out_absent" ] && ok "reader quiet (EMPTY) with absent bridge" || no "reader emitted with absent bridge: [$out_absent]"

echo "== 8. NO-HIT — bridge present, path overlaps nothing → EMPTY, exit 0 =="
out_nohit="$( cd "$R1" && bash "$READ_SH" "some/unrelated/path.xyz" </dev/null 2>/dev/null )"; rcn=$?
[ "$rcn" -eq 0 ] && ok "reader exit 0 on a no-overlap path" || no "reader non-zero exit on no-hit ($rcn)"
[ -z "$out_nohit" ] && ok "no-overlap (bridge present) → EMPTY output (no sentinel)" || no "no-hit should emit nothing, got: [$out_nohit]"

echo "== 9. ARG-PRECEDENCE / no-stdin-block — args win, stdin ignored when args present =="
# Args present + a HIT path piped on stdin: stdin must be IGNORED (no-hang contract). A no-hit
# arg with a hit-path on stdin must therefore produce EMPTY (the stdin path must not leak in).
out_argwin="$( cd "$R1" && printf '%s\n' "ai-agent-manager-plugin/agents/supervisor.md" \
                 | bash "$READ_SH" "some/unrelated/path.xyz" 2>/dev/null )"; rcaw=$?
[ "$rcaw" -eq 0 ] && ok "exit 0 with args + piped stdin" || no "non-zero exit args+stdin ($rcaw)"
[ -z "$out_argwin" ] && ok "args-present: stdin HIT path ignored → EMPTY (no-hang / arg-precedence holds)" || no "stdin leaked past args: [$out_argwin]"
# No args → stdin IS read (the hit path on stdin produces the advisory).
out_stdin="$( cd "$R1" && printf '%s\n' "ai-agent-manager-plugin/agents/supervisor.md" \
                | bash "$READ_SH" 2>/dev/null )"; rcsi=$?
[ "$rcsi" -eq 0 ] && ok "exit 0 reading paths from stdin (no args)" || no "non-zero exit stdin ($rcsi)"
printf '%s' "$out_stdin" | grep -q "area-knowledge\|area knowledge\|Advisory area-knowledge" && ok "no-args: stdin path matched → advisory emitted" || no "no-args: stdin path not matched"

echo "== 10. ADVISORY-ONLY — reader never emits a gating token, banner is subordinate-to-CLAUDE.md =="
# A hit must read as advisory: subordinate banner present, and NO gating-verdict token leaks.
printf '%s' "$out_raw" | grep -qi "subordinate to CLAUDE.md" && ok "advisory banner (subordinate to CLAUDE.md) present on a hit" || no "advisory banner missing on a hit"
printf '%s' "$out_raw" | grep -qiE "\b(BLOCKING|FAIL|REJECT|heal_decision|gate|MERGE|do not merge)\b" \
  && no "reader emitted a gating-verdict-shaped token (advisory-only violated)" \
  || ok "reader emits NO gating-verdict token (advisory-only)"
# The reader's directional framing (the "bias WHERE you look" reviewer-prompt phrasing is Subtask 4
# wiring, NOT the reader's stdout — the reader frames the signal as a non-authoritative directional
# AREA hint via the attribution line).
printf '%s' "$out_raw" | grep -qi "directional area knowledge, not file-precise" && ok "carries the directional 'area knowledge, not file-precise' framing" || no "directional advisory framing line missing"

echo "== 11. BUILDER FAIL-SAFE — missing graph and missing python both exit 0 (no bridge written) =="
# (a) missing graph: a git repo with NO graphify-out/graph.json.
Rg="$(newrepo)"
out_ng="$( cd "$Rg" && bash "$BUILD_SH" 2>&1 )"; rcng=$?
[ "$rcng" -eq 0 ] && ok "builder exit 0 with no graph (fail-safe skip)" || no "builder non-zero exit with no graph ($rcng)"
[ ! -f "$Rg/.supervisor/bridge/bridge.json" ] && ok "no bridge.json written when graph absent" || no "builder wrote a bridge with no graph"
printf '%s' "$out_ng" | grep -qi "no graph" && ok "builder logs a no-graph skip line to stderr" || no "no-graph skip line missing"
# (b) missing python: mask python3/python off PATH (the wrapper must skip + exit 0). Build a temp
#     bin with the shell tools the wrapper needs but NO python.
Rp="$(build_canonical fresh)"
maskbin="$(mktemp -d)"
for t in bash sh git mktemp sort grep printf date dirname cat env sed jq awk; do
  p="$(command -v "$t" 2>/dev/null || true)"; [ -n "$p" ] && ln -sf "$p" "$maskbin/$t" 2>/dev/null || true
done
out_np="$( cd "$Rp" && PATH="$maskbin" bash "$BUILD_SH" 2>&1 )"; rcnp=$?
if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  [ "$rcnp" -eq 0 ] && ok "builder exit 0 with python masked off PATH (fail-safe)" || no "builder non-zero exit python-masked ($rcnp)"
  printf '%s' "$out_np" | grep -qi "python" && ok "builder logs a python-required skip line" || no "python-required skip line missing"
else
  ok "python not installed in this env — masking path is the default (skipped active mask)"
fi

echo "== 12. EXECUTABLE-ACCEPTANCE parity — read-bridge on a nonexistent path → exit 0, no output =="
# Mirrors the brief's Executable Acceptance cmd: `read-bridge.sh nonexistent/path.xyz` from the
# real repo must be a silent fail-safe no-op (exit 0, empty). Run from a fresh repo to avoid any
# coupling to the real bridge.
Re="$(newrepo)"
out_ea="$( cd "$Re" && bash "$READ_SH" "nonexistent/path.xyz" </dev/null 2>/dev/null )"; rcea=$?
[ "$rcea" -eq 0 ] && [ -z "$out_ea" ] && ok "read-bridge nonexistent/path.xyz → exit 0, no output (fail-safe)" || no "fail-safe no-op broken (rc=$rcea out=[$out_ea])"

echo "== 13. HEAL-SIGNAL JOIN ENRICHMENT — joined.jsonl raises the miss floor + adds a joined-only finding =="
# (a) FAIL-SAFE BASELINE: the canonical fixture (R1) has NO joined.jsonl, yet builds fine — already
#     exercised by §§1–10 above. Re-confirm community 1's miss came ONLY from the postmortem corpus.
MISS101_BASE="$(B '.communities["1"].findings[] | select(.pr==101) | .miss' "$BJSON")"
[ "$MISS101_BASE" = "2" ] && ok "no-joined.jsonl baseline: #101 miss=2 from postmortem corpus (fail-safe path intact)" || no "baseline #101 miss wrong (got: $MISS101_BASE)"

# (b) ENRICHMENT: a fixture WITH joined.jsonl carrying a HIGHER floor for #101 (5 > postmortem 2)
#     and a joined-ONLY PR #303 (absent from postmortem, paths git-backfilled).
Rj="$(newrepo)"; set_remote "$Rj" "acme/widget"
write_findings "$Rj" "acme/widget"                 # postmortem: #101 miss=2 (community 1), #102 (god-node)
write_lessons "$Rj"
write_joined "$Rj" "acme/widget" 5 303             # joined: #101 floor=5, joined-only #303 (commits to supervisor.md)
hj="$( cd "$Rj" && git rev-parse HEAD )"           # stamp graph AFTER the #303 commit so it maps cleanly
write_graph "$Rj" "${hj:0:7}"
run_build "$Rj"
BJj="$Rj/.supervisor/bridge/bridge.json"
[ -s "$BJj" ] && ok "enriched build wrote bridge.json" || no "enriched build produced no bridge.json"
# floor-raising: #101's miss must be the JOINED 5, not the postmortem 2.
MISS101="$(B '.communities["1"].findings[] | select(.pr==101) | .miss' "$BJj")"
SHM101="$(B '.communities["1"].findings[] | select(.pr==101) | .self_heal_miss' "$BJj")"
[ "$MISS101" = "5" ] && ok "joined.jsonl raised #101 self_heal_misses floor 2 → 5 (max-floor enrichment)" || no "joined floor not adopted for #101 (got: $MISS101)"
[ "$SHM101" = "true" ] && ok "#101 self_heal_miss flag true after enrichment" || no "#101 self_heal_miss flag wrong ($SHM101)"
# joined-ONLY finding: #303 was never in the postmortem corpus but still produces a finding,
# with changed_paths git-backfilled (supervisor.md → community 1).
PR303="$(B '[.communities["1"].findings[].pr] | tostring' "$BJj")"
printf '%s' "$PR303" | grep -q '303' && ok "joined-ONLY PR #303 became a finding (git-backfilled paths → community 1)" || no "joined-only #303 produced no finding ($PR303)"
MISS303="$(B '.communities["1"].findings[] | select(.pr==303) | .miss' "$BJj")"
[ "$MISS303" = "4" ] && ok "joined-only #303 carries its self_heal_misses=4" || no "joined-only #303 miss wrong (got: $MISS303)"

# ---- cleanup ----------------------------------------------------------------
rm -rf "$R1" "$Ra" "$Rb" "$Rs" "$Rn" "$Rg" "$Rp" "$Re" "$Rj" "$maskbin" 2>/dev/null

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
