#!/usr/bin/env bash
# test-build-floor.sh - self-tests for build-floor.sh, the read-only floor projector.
#
# HERMETIC BY CONSTRUCTION, and that is the load-bearing property of this file.
# `.gitignore` ignores `.supervisor/*`, so EIGHT of the nine input surfaces are absent from
# every fresh clone and from every `git worktree` - measured: a fresh worktree has
# `.supervisor/logs/` with zero entries. CI (`.github/workflows/ci.yml`) runs every
# `loomwright/scripts/test-*.sh` as a hard gate in exactly that environment. A test that
# asserted against the real `.supervisor/` would therefore compare 0 to 0 and go SILENTLY
# GREEN while proving nothing. Every assertion below runs against a `mktemp -d` + `git init`
# fixture tree with KNOWN counts (the same harness convention as test-build-handoff.sh /
# test-insights.sh / test-reconcile-resume-state.sh). The real-`.supervisor/` run at the end
# is a LOCAL-ONLY corroboration that prints an explicit `SKIPPED - <reason>` line when the
# tree is absent, and skips are reported separately - never counted as passes.
#
# Cases:
#   (a) hermetic counts - every count equals an independently known fixture value; no counted
#       section may be absent or zero; a deliberately wrong expectation must turn red
#   (b) counting basis - every surface carries the glob/predicate that produced its number,
#       and `logs` counts 3 `*.jsonl` out of 8 directory entries
#   (c) session segmentation by cc_session_id, never by filename (committed fixture:
#       3 ids / 7 lines + 1 field-less line), with the field-less line accounted explicitly
#   (d) missing directory -> absent + named reason + NO count + exit 0
#   (e) empty log -> sessions absent + named reason + NO count + exit 0
#   (f) malformed JSON -> `unverified`, never `counted`, count omitted, offender named
#   (g) jq absent -> named reason, exit 0, no artefact
#   (h) schema conformance - the required-key set is PARSED OUT of the `## FLOOR_PROJECTION`
#       block in docs/RESULT_SCHEMAS.md (never restated here); every required key removed in
#       turn must be rejected BY NAME, and a control proves the validator passes the intact
#       payload, so the rejection is discriminating rather than blanket
#   (i) determinism - two RAW UNFILTERED runs under two DIFFERENT injected timestamps differ
#       by exactly one line pair; the same injected timestamp is byte-identical
#   (j) exactly one wall-clock read in the source, with a negative control embedding a second
#   (k) containment - tree hashed via `find` with ignored files IN SCOPE and git NEVER
#       consulted (git reports neither an illegal write into `.supervisor/` nor the legitimate
#       output, because `.supervisor/` is IGNORED, not untracked), plus a mutation control
#   (l) stat-flavour portability - a `stat` stub printing a non-numeric string must make
#       mtime_epoch OMITTED, not empty, not 0, not the raw string
#   (m) real `.supervisor/` corroboration (local only) or an explicit SKIPPED line
#
# Exit 0 = all pass, 1 = any failure. Registered automatically by ci.yml's test-*.sh glob.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build-floor.sh"
SCHEMA_MD="$(cd "$HERE/../docs" && pwd)/RESULT_SCHEMAS.md"
SESS_FIXTURE="$HERE/fixtures/floor-sessions.jsonl"

pass=0; fail=0; skip=0
ok()   { echo "  ok: $1";        pass=$((pass+1)); }
no()   { echo "  FAIL: $1";      fail=$((fail+1)); }
skipn(){ echo "  SKIPPED - $1";  skip=$((skip+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

csum() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}

new_repo() {
  local r; r="$(mktmp)"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

run_build() { ( cd "$1" && bash "$BUILD" >/dev/null 2>&1 ); }

# ---------------------------------------------------------------------------
# The hermetic fixture. Every number here is KNOWN and is what the assertions
# recompute against - nothing is read back out of the script's own output.
# ---------------------------------------------------------------------------
EXP_STATE=3
EXP_JOBS_PENDING=2; EXP_JOBS_IN_PROGRESS=1; EXP_JOBS_DONE=5; EXP_JOBS_FAILED=3
EXP_AUTOMATE=4
EXP_LOGS=3                # *.jsonl only, out of 8 directory entries
EXP_LOG_DIR_ENTRIES=8     # 3 jsonl + 5 plain .log - the counting-basis case in point
EXP_SESSIONS=4            # 3 from the committed fixture + 1 new; one id spans two files
EXP_SESS_NO_ID=1
EXP_SESS_LINES=11
EXP_INSIGHTS=2
EXP_POSTMORTEM=4
EXP_DRAIN=7
EXP_WORKER_SUMMARIES=6
EXP_RULES=2

seed_tree() {
  local r="$1" i
  mkdir -p "$r/.supervisor"/{jobs/pending,jobs/in-progress,jobs/done,jobs/failed} \
           "$r/.supervisor"/{automate,logs,insights/runs,postmortem,drain-rounds,worker-summaries} \
           "$r/.agent/rules"

  {
    printf '# Supervisor State\n\n## Session\n'
    printf -- '- session_id: fixture-session\n- branch: feature/fixture\n'
    printf -- '- status: running\n- phase: EXECUTE\n\n'
    printf '## Subtasks\n| # | Title | Status | Review |\n|---|-------|--------|--------|\n'
    for i in 1 2 3; do printf '| %s | sub %s | COMPLETED | PASS |\n' "$i" "$i"; done
    printf '\n## Parallelism\n- launchable: 0\n'
  } > "$r/.supervisor/state.md"

  for i in $(seq 1 $EXP_JOBS_PENDING);     do echo "# p$i"  > "$r/.supervisor/jobs/pending/p$i.md";     done
  for i in $(seq 1 $EXP_JOBS_IN_PROGRESS); do echo "# i$i"  > "$r/.supervisor/jobs/in-progress/i$i.md"; done
  for i in $(seq 1 $EXP_JOBS_DONE);        do echo "# d$i"  > "$r/.supervisor/jobs/done/d$i.md";        done
  for i in $(seq 1 $EXP_JOBS_FAILED);      do echo "# f$i"  > "$r/.supervisor/jobs/failed/f$i.md";      done

  for i in $(seq 1 $EXP_AUTOMATE); do echo "# run $i" > "$r/.supervisor/automate/run-$i.md"; done
  # Two sibling transients a `*.md` glob must NOT count.
  echo '{}' > "$r/.supervisor/automate/run-1.config-backup.json"
  echo '{}' > "$r/.supervisor/automate/run-2.config-backup.json"

  # logs/: 3 *.jsonl among 8 directory entries. `second.jsonl` REUSES sess-aaaa-0001 from the
  # committed fixture, so grouping by filename would give 3 and grouping by field gives 4.
  cp "$SESS_FIXTURE" "$r/.supervisor/logs/8d43da72-first.jsonl"
  {
    printf '{"ts":"2026-08-02T10:00:00Z","event":"subtask_complete","cc_session_id":"sess-aaaa-0001"}\n'
    printf '{"ts":"2026-08-29T10:00:00Z","event":"session_start","cc_session_id":"sess-dddd-0004"}\n'
    printf '{"ts":"2026-08-29T10:30:00Z","event":"session_end","cc_session_id":"sess-dddd-0004"}\n'
  } > "$r/.supervisor/logs/second.jsonl"
  : > "$r/.supervisor/logs/empty.jsonl"
  for i in 1 2 3 4 5; do echo "dispatch transcript $i" > "$r/.supervisor/logs/review-pr-dispatch-$i.log"; done

  for i in $(seq 1 $EXP_INSIGHTS); do echo "# run note $i" > "$r/.supervisor/insights/runs/run-$i.md"; done

  : > "$r/.supervisor/postmortem/results.jsonl"
  for i in $(seq 1 $EXP_POSTMORTEM); do
    printf '{"schema_version":1,"number":%s,"review_rounds":%s}\n' "$i" "$i" \
      >> "$r/.supervisor/postmortem/results.jsonl"
  done

  for i in $(seq 1 $EXP_DRAIN); do printf '{"rounds":%s,"max_rounds":5}\n' "$i" \
      > "$r/.supervisor/drain-rounds/round-$i.json"; done
  for i in $(seq 1 $EXP_WORKER_SUMMARIES); do echo "## WORKER_SUMMARY $i" \
      > "$r/.supervisor/worker-summaries/w$i.md"; done
  for i in $(seq 1 $EXP_RULES); do printf '[{"id":"r%s"}]\n' "$i" > "$r/.agent/rules/rule-$i.json"; done
}

jget() { jq -r "$2" "$1" 2>/dev/null; }
scount()  { jq -r --arg k "$2" '.surfaces[$k].count  // "ABSENT"' "$1" 2>/dev/null; }
sstatus() { jq -r --arg k "$2" '.surfaces[$k].status // "ABSENT"' "$1" 2>/dev/null; }
sreason() { jq -r --arg k "$2" '.surfaces[$k].reason // ""'       "$1" 2>/dev/null; }

# The single count comparator. Used for the real assertions AND, unchanged, for the
# negative control - if it cannot fail it is not an assertion.
count_is() { [ "$(scount "$1" "$2")" = "$3" ]; }

ALL_KEYS="state jobs_pending jobs_in_progress jobs_done jobs_failed automate_runs logs \
sessions insights_runs postmortem drain_rounds worker_summaries rules"

command -v jq >/dev/null 2>&1 || { echo "test-build-floor: jq required to run these tests" >&2; exit 1; }
[ -f "$BUILD" ]        || { echo "test-build-floor: $BUILD missing" >&2; exit 1; }
[ -f "$SCHEMA_MD" ]    || { echo "test-build-floor: $SCHEMA_MD missing" >&2; exit 1; }
[ -f "$SESS_FIXTURE" ] || { echo "test-build-floor: committed fixture $SESS_FIXTURE missing" >&2; exit 1; }

# ============================================================================
echo "== (a) hermetic fixture: every count equals its independently known value =="
RA="$(new_repo)"; seed_tree "$RA"
run_build "$RA"; rcA=$?
JA="$RA/.supervisor/floor/floor.json"
[ "$rcA" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcA"
[ -f "$JA" ] && ok "floor.json written" || no "floor.json not written"
jq -e . "$JA" >/dev/null 2>&1 && ok "floor.json is valid JSON" || no "floor.json is not valid JSON"

check_pair() {
  local key="$1" want="$2"
  if count_is "$JA" "$key" "$want"; then ok "$key count == $want"
  else no "$key count: expected $want, got $(scount "$JA" "$key")"; fi
}
check_pair state              "$EXP_STATE"
check_pair jobs_pending       "$EXP_JOBS_PENDING"
check_pair jobs_in_progress   "$EXP_JOBS_IN_PROGRESS"
check_pair jobs_done          "$EXP_JOBS_DONE"
check_pair jobs_failed        "$EXP_JOBS_FAILED"
check_pair automate_runs      "$EXP_AUTOMATE"
check_pair logs               "$EXP_LOGS"
check_pair sessions           "$EXP_SESSIONS"
check_pair insights_runs      "$EXP_INSIGHTS"
check_pair postmortem         "$EXP_POSTMORTEM"
check_pair drain_rounds       "$EXP_DRAIN"
check_pair worker_summaries   "$EXP_WORKER_SUMMARIES"
check_pair rules              "$EXP_RULES"

# An empty tree must never satisfy this suite: every section must be counted AND non-zero.
zero_or_absent=""
for k in $ALL_KEYS; do
  st="$(sstatus "$JA" "$k")"; c="$(scount "$JA" "$k")"
  case "$c" in ''|*[!0-9]*) zero_or_absent="$zero_or_absent $k(count=$c)"; continue ;; esac
  [ "$st" = "counted" ] || zero_or_absent="$zero_or_absent $k(status=$st)"
  [ "$c" -gt 0 ]        || zero_or_absent="$zero_or_absent $k(zero)"
done
[ -z "$zero_or_absent" ] \
  && ok "all 13 sections counted and non-zero (an empty tree cannot satisfy this suite)" \
  || no "sections absent or zero:$zero_or_absent"

echo "-- negative control: the comparator must be able to fail --"
count_is "$JA" logs 999 \
  && no "comparator accepted a deliberately wrong count (assertions are vacuous)" \
  || ok "deliberately wrong count (logs=999) is rejected"
count_is "$JA" no_such_surface 1 \
  && no "comparator accepted a non-existent surface" \
  || ok "non-existent surface is rejected (count reads ABSENT)"
# A negative-control FIXTURE: an identical tree with one extra job brief. The very same
# expectation that passes against the good tree must FAIL against this one, which is what
# proves the fixture (not just the literal) is what the assertion is reading.
RNEG="$(new_repo)"; seed_tree "$RNEG"; echo "# extra" > "$RNEG/.supervisor/jobs/done/d99.md"
run_build "$RNEG"
JNEG="$RNEG/.supervisor/floor/floor.json"
count_is "$JNEG" jobs_done "$EXP_JOBS_DONE" \
  && no "the deliberately-wrong negative-control fixture still satisfied the assertion" \
  || ok "negative-control fixture (one extra brief) turns the jobs_done assertion RED ($(scount "$JNEG" jobs_done) != $EXP_JOBS_DONE)"
count_is "$JNEG" jobs_done "$((EXP_JOBS_DONE + 1))" \
  && ok "and the same comparator accepts the negative fixture's true count - it tracks the tree, not a constant" \
  || no "the comparator did not track the negative fixture's true count"

# ============================================================================
echo "== (b) every count states its counting basis =="
missing_basis=""
for k in $ALL_KEYS; do
  b="$(jq -r --arg k "$k" '.surfaces[$k].basis // ""' "$JA" 2>/dev/null)"
  [ -n "$b" ] || missing_basis="$missing_basis $k"
done
[ -z "$missing_basis" ] && ok "all 13 surfaces carry a non-empty basis" \
  || no "surfaces with no basis:$missing_basis"

dir_entries="$(ls -1 "$RA/.supervisor/logs" | awk 'NF{n++} END{print n+0}')"
[ "$dir_entries" -eq "$EXP_LOG_DIR_ENTRIES" ] \
  && ok "fixture logs dir holds $EXP_LOG_DIR_ENTRIES entries (3 jsonl + 5 plain .log)" \
  || no "fixture logs dir holds $dir_entries entries, expected $EXP_LOG_DIR_ENTRIES"
[ "$(scount "$JA" logs)" = "$EXP_LOGS" ] && [ "$EXP_LOGS" != "$EXP_LOG_DIR_ENTRIES" ] \
  && ok "logs counts the *.jsonl glob ($EXP_LOGS), not directory entries ($EXP_LOG_DIR_ENTRIES)" \
  || no "logs count did not discriminate glob from directory entries"
jq -r '.surfaces.logs.basis' "$JA" 2>/dev/null | grep -qF '*.jsonl' \
  && ok "logs basis names the *.jsonl glob that produced the number" \
  || no "logs basis does not name its glob"

# ============================================================================
echo "== (c) sessions are segmented by cc_session_id, never by filename =="
fix_ids="$(jq -r 'select(has("cc_session_id")) | .cc_session_id' "$SESS_FIXTURE" 2>/dev/null | sort -u | awk 'NF{n++} END{print n+0}')"
fix_noid="$(jq -r 'select(has("cc_session_id") | not) | "x"' "$SESS_FIXTURE" 2>/dev/null | awk 'NF{n++} END{print n+0}')"
fix_lines="$(awk 'NF{n++} END{print n+0}' "$SESS_FIXTURE")"
[ "$fix_ids" -eq 3 ] && [ "$fix_noid" -eq 1 ] && [ "$fix_lines" -eq 8 ] \
  && ok "committed fixture is 3 distinct ids across 7 lines plus 1 field-less line" \
  || no "committed fixture drifted: ids=$fix_ids noid=$fix_noid lines=$fix_lines (expected 3/1/8)"

[ "$(scount "$JA" sessions)" = "$EXP_SESSIONS" ] \
  && ok "sessions == $EXP_SESSIONS distinct cc_session_id values" \
  || no "sessions == $(scount "$JA" sessions), expected $EXP_SESSIONS"
[ "$EXP_SESSIONS" != "$EXP_LOGS" ] && [ "$(scount "$JA" sessions)" != "$(scount "$JA" logs)" ] \
  && ok "session count ($EXP_SESSIONS) differs from file count ($EXP_LOGS) - filename grouping would be wrong" \
  || no "session count equals file count; filename grouping is not ruled out"
[ "$(jget "$JA" '.surfaces.sessions.detail.lines_without_session_id')" = "$EXP_SESS_NO_ID" ] \
  && ok "the field-less line is accounted explicitly (lines_without_session_id == $EXP_SESS_NO_ID)" \
  || no "lines_without_session_id == $(jget "$JA" '.surfaces.sessions.detail.lines_without_session_id'), expected $EXP_SESS_NO_ID"
[ "$(jget "$JA" '.surfaces.sessions.detail.lines_scanned')" = "$EXP_SESS_LINES" ] \
  && ok "lines_scanned == $EXP_SESS_LINES across the three jsonl files" \
  || no "lines_scanned == $(jget "$JA" '.surfaces.sessions.detail.lines_scanned'), expected $EXP_SESS_LINES"

# ============================================================================
echo "== (d) missing input directory -> absent, reason named, NO count, exit 0 =="
RD="$(new_repo)"; seed_tree "$RD"; rm -rf "$RD/.supervisor/drain-rounds"
run_build "$RD"; rcD=$?
JD="$RD/.supervisor/floor/floor.json"
[ "$rcD" -eq 0 ] && ok "exits 0 with an input directory missing" || no "expected exit 0, got $rcD"
[ "$(sstatus "$JD" drain_rounds)" = "absent" ] \
  && ok "drain_rounds status == absent" || no "drain_rounds status == $(sstatus "$JD" drain_rounds)"
[ "$(scount "$JD" drain_rounds)" = "ABSENT" ] \
  && ok "drain_rounds count key is OMITTED (never 0)" \
  || no "drain_rounds emitted a count of $(scount "$JD" drain_rounds) - a fabricated default"
sreason "$JD" drain_rounds | grep -qF ".supervisor/drain-rounds" \
  && ok "reason names the missing directory" || no "reason does not name the missing directory"
jq -e '.notes | length > 0' "$JD" >/dev/null 2>&1 \
  && ok "the omission is surfaced in notes[]" || no "notes[] is empty despite an omitted surface"

# ============================================================================
echo "== (e) empty log -> sessions absent, reason named, NO count, exit 0 =="
RE="$(new_repo)"; seed_tree "$RE"
rm -f "$RE/.supervisor/logs"/*.jsonl; : > "$RE/.supervisor/logs/empty.jsonl"
run_build "$RE"; rcE=$?
JE="$RE/.supervisor/floor/floor.json"
[ "$rcE" -eq 0 ] && ok "exits 0 with an empty log" || no "expected exit 0, got $rcE"
[ "$(scount "$JE" logs)" = "1" ] && ok "logs still counts the empty file (1)" \
  || no "logs count == $(scount "$JE" logs), expected 1"
[ "$(sstatus "$JE" sessions)" = "absent" ] && ok "sessions status == absent" \
  || no "sessions status == $(sstatus "$JE" sessions)"
[ "$(scount "$JE" sessions)" = "ABSENT" ] && ok "sessions count key is OMITTED (never 0)" \
  || no "sessions emitted a count of $(scount "$JE" sessions)"
[ -n "$(sreason "$JE" sessions)" ] && ok "sessions reason is named" || no "sessions reason is empty"

# ============================================================================
echo "== (f) malformed JSON -> unverified, never counted, offender named =="
RF="$(new_repo)"; seed_tree "$RF"
printf '{"rounds": 3,\n' > "$RF/.supervisor/drain-rounds/round-3.json"     # truncated document
printf 'this is not json at all\n' >> "$RF/.supervisor/logs/second.jsonl"  # malformed JSONL line
run_build "$RF"; rcF=$?
JF="$RF/.supervisor/floor/floor.json"
[ "$rcF" -eq 0 ] && ok "exits 0 with malformed input" || no "expected exit 0, got $rcF"
[ "$(sstatus "$JF" drain_rounds)" = "unverified" ] \
  && ok "drain_rounds reports unverified, never clean" \
  || no "drain_rounds status == $(sstatus "$JF" drain_rounds), expected unverified"
[ "$(scount "$JF" drain_rounds)" = "ABSENT" ] \
  && ok "drain_rounds count key is OMITTED under unverified" \
  || no "drain_rounds emitted a count of $(scount "$JF" drain_rounds) it cannot prove"
sreason "$JF" drain_rounds | grep -qF "round-3.json" \
  && ok "reason names the offending document by path" \
  || no "reason does not name the offender: $(sreason "$JF" drain_rounds)"
[ "$(sstatus "$JF" sessions)" = "unverified" ] \
  && ok "sessions reports unverified when a line will not parse" \
  || no "sessions status == $(sstatus "$JF" sessions), expected unverified"
[ "$(scount "$JF" sessions)" = "ABSENT" ] \
  && ok "sessions count key is OMITTED under unverified" \
  || no "sessions emitted a count of $(scount "$JF" sessions)"
[ "$(jget "$JF" '.surfaces.sessions.detail.lines_malformed')" = "1" ] \
  && ok "the unparseable line is tallied as evidence (lines_malformed == 1)" \
  || no "lines_malformed == $(jget "$JF" '.surfaces.sessions.detail.lines_malformed'), expected 1"
# A valid document whose value is false/0/null must NOT be misread as malformed
# (`jq -e .` would exit 1 on it; `jq empty` is the correct probe).
RF2="$(new_repo)"; seed_tree "$RF2"; printf 'false\n' > "$RF2/.supervisor/drain-rounds/round-3.json"
run_build "$RF2"
JF2="$RF2/.supervisor/floor/floor.json"
[ "$(sstatus "$JF2" drain_rounds)" = "counted" ] \
  && ok "a valid document whose value is 'false' is NOT misreported as malformed" \
  || no "valid 'false' document misreported as $(sstatus "$JF2" drain_rounds)"

# ============================================================================
echo "== (g) jq absent -> named reason, exit 0, no artefact =="
SHIM="$ROOT/nojq-bin"; mkdir -p "$SHIM"
for t in git bash sh env date stat awk sort cat head cut mkdir tr ls rm grep sed find printf; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$SHIM/$t"
done
RG="$(new_repo)"; seed_tree "$RG"
( PATH="$SHIM"; hash -r 2>/dev/null; command -v jq >/dev/null 2>&1 ) \
  && no "shim PATH still exposes jq - the jq-absent case would be vacuous" \
  || ok "shim PATH genuinely hides jq"
( PATH="$SHIM"; hash -r 2>/dev/null; command -v git >/dev/null 2>&1 ) \
  && ok "shim PATH still provides the other tools (the skip is about jq, not a broken PATH)" \
  || no "shim PATH hides git too - the jq-absent case would prove nothing"
errG="$( cd "$RG" && PATH="$SHIM" bash "$BUILD" 2>&1 >/dev/null )"; rcG=$?
[ "$rcG" -eq 0 ] && ok "exits 0 with jq absent" || no "expected exit 0, got $rcG"
printf '%s' "$errG" | grep -qi "jq" && ok "names jq as the reason for skipping" \
  || no "did not name the reason: $errG"
[ ! -f "$RG/.supervisor/floor/floor.json" ] \
  && ok "no artefact written when jq is absent" || no "wrote an artefact without jq"

# ============================================================================
echo "== (h) schema conformance: required keys PARSED OUT of RESULT_SCHEMAS.md =="
schema_block() {
  awk '/^## FLOOR_PROJECTION$/{f=1} f&&/^```yaml$/{y=1;next} y&&/^```$/{exit} y' "$SCHEMA_MD"
}
# Top-level keys are indented two spaces inside the block; each surfaces-entry key four.
# The `# <type>, required` / `# <type>, optional` marker is the parsed signal.
parse_required() { schema_block | sed -nE "s/^$1([a-z_]+):.*#[^#]*,[[:space:]]*required.*/\\1/p"; }
parse_optional() { schema_block | sed -nE "s/^$1([a-z_]+):.*#[^#]*,[[:space:]]*optional.*/\\1/p"; }

TOP_REQ="$(parse_required '  ')"; ENTRY_REQ="$(parse_required '    ')"
TOP_OPT="$(parse_optional '  ')"; ENTRY_OPT="$(parse_optional '    ')"
n_top="$(printf '%s\n' "$TOP_REQ" | awk 'NF{n++} END{print n+0}')"
n_ent="$(printf '%s\n' "$ENTRY_REQ" | awk 'NF{n++} END{print n+0}')"
n_opt="$(printf '%s\n' "$TOP_OPT$ENTRY_OPT" | awk 'NF{n++} END{print n+0}')"
[ "$n_top" -gt 0 ] && [ "$n_ent" -gt 0 ] \
  && ok "parsed $n_top top-level + $n_ent per-entry required keys out of the schema block" \
  || no "parsed no required keys from the schema block (validator would be vacuous)"
[ "$n_opt" -gt 0 ] \
  && ok "the block is annotated YAML: $n_opt keys are marked optional (a bare JSON example would mark none)" \
  || no "no optional markers found - the block cannot distinguish required from optional"

# The validator. Its ONLY source of required keys is the parse above.
validate_floor() {
  local j="$1" rc=0 k sk st has_c
  [ "$n_top" -gt 0 ] && [ "$n_ent" -gt 0 ] || { echo "schema parse produced nothing"; return 2; }
  for k in $TOP_REQ; do
    jq -e --arg k "$k" 'has($k)' "$j" >/dev/null 2>&1 || { echo "missing required key: $k"; rc=1; }
  done
  if jq -e 'has("surfaces")' "$j" >/dev/null 2>&1; then
    for sk in $(jq -r '.surfaces | keys[]' "$j" 2>/dev/null); do
      for k in $ENTRY_REQ; do
        jq -e --arg s "$sk" --arg k "$k" '.surfaces[$s] | has($k)' "$j" >/dev/null 2>&1 \
          || { echo "missing required key: surfaces.$sk.$k"; rc=1; }
      done
      st="$(jq -r --arg s "$sk" '.surfaces[$s].status // ""' "$j" 2>/dev/null)"
      has_c="$(jq -r --arg s "$sk" 'if (.surfaces[$s] | has("count")) then "y" else "n" end' "$j" 2>/dev/null)"
      case "$st" in
        counted)              [ "$has_c" = y ] || { echo "surfaces.$sk: status counted without count"; rc=1; } ;;
        absent|unverified)    [ "$has_c" = n ] || { echo "surfaces.$sk: count present with status $st"; rc=1; } ;;
        *)                    echo "surfaces.$sk: status not in the documented enum: $st"; rc=1 ;;
      esac
    done
  fi
  return $rc
}

vout="$(validate_floor "$JA" 2>&1)"; vrc=$?
[ "$vrc" -eq 0 ] && ok "CONTROL: the intact payload PASSES the schema-derived validator" \
  || no "the intact payload was rejected: $vout"

# Every required top-level key, removed in turn, must be rejected BY NAME.
bad_top=""
for k in $TOP_REQ; do
  MUT="$ROOT/mut-top-$k.json"
  jq --arg k "$k" 'del(.[$k])' "$JA" > "$MUT" 2>/dev/null
  out="$(validate_floor "$MUT" 2>&1)"; rc=$?
  if [ "$rc" -ne 1 ]; then bad_top="$bad_top $k(not-rejected)"
  elif ! printf '%s' "$out" | grep -qF "missing required key: $k"; then bad_top="$bad_top $k(no-diagnostic)"; fi
done
[ -z "$bad_top" ] \
  && ok "removing any of the $n_top required top-level keys is rejected, each named in the diagnostic" \
  || no "top-level rejection failed for:$bad_top"

# Same for a per-entry required key, on one surface, so the diagnostic must name the path.
bad_ent=""
for k in $ENTRY_REQ; do
  MUT="$ROOT/mut-ent-$k.json"
  jq --arg k "$k" 'del(.surfaces.logs[$k])' "$JA" > "$MUT" 2>/dev/null
  out="$(validate_floor "$MUT" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then bad_ent="$bad_ent $k(not-rejected)"
  elif ! printf '%s' "$out" | grep -qF "surfaces.logs.$k"; then bad_ent="$bad_ent $k(no-diagnostic)"; fi
done
[ -z "$bad_ent" ] \
  && ok "removing any of the $n_ent required surfaces-entry keys is rejected, each named by path" \
  || no "per-entry rejection failed for:$bad_ent"

# Discriminating, not blanket: removing an OPTIONAL key must still PASS.
MUT="$ROOT/mut-optional.json"; jq 'del(.repo_head) | del(.surfaces.logs.mtime_epoch)' "$JA" > "$MUT" 2>/dev/null
validate_floor "$MUT" >/dev/null 2>&1 \
  && ok "removing OPTIONAL keys still passes - the validator is discriminating, not blanket" \
  || no "the validator rejected a payload missing only OPTIONAL keys"
# And the omit-absent-evidence rule is enforced, not merely documented.
MUT="$ROOT/mut-fabricated-zero.json"
jq '.surfaces.drain_rounds.status = "absent" | .surfaces.drain_rounds.count = 0' "$JA" > "$MUT" 2>/dev/null
validate_floor "$MUT" >/dev/null 2>&1 \
  && no "a fabricated count:0 on an absent surface was accepted" \
  || ok "a fabricated count:0 on an absent surface is rejected"

# ============================================================================
echo "== (h2) RESULT_SCHEMAS.md companion edits (enforced by no other gate) =="
# check-doc-currency.sh does not scan this file and the contract-parity MANIFEST is fixed
# and hook-scoped, so if these two edits are not asserted here they are asserted nowhere.
intro="$(grep -n 'Current versions:' "$SCHEMA_MD" | head -1 | cut -d: -f1)"
[ -n "$intro" ] && ok "the intro 'Current versions:' paragraph is present" \
  || no "could not locate the intro 'Current versions:' paragraph"
introline="$(sed -n "${intro:-1}p" "$SCHEMA_MD")"
printf '%s' "$introline" | grep -qF 'FLOOR_PROJECTION at `schema_version: 1`' \
  && ok "the intro names FLOOR_PROJECTION with its schema_version" \
  || no "the intro does not name FLOOR_PROJECTION with its schema_version"
printf '%s' "$introline" | grep -qi 'FLOOR_PROJECTION.*no hook validator' \
  && ok "the intro records FLOOR_PROJECTION's no-hook-validator status" \
  || no "the intro does not record FLOOR_PROJECTION's no-hook-validator status"

vh="$(awk '/^### Version History$/{f=1;next} f&&/^## /{exit} f' "$SCHEMA_MD" | grep -F 'FLOOR_PROJECTION' | head -1)"
[ -n "$vh" ] && ok "### Version History gains a FLOOR_PROJECTION entry" \
  || no "### Version History has no FLOOR_PROJECTION entry"
printf '%s' "$vh" | grep -qE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' \
  && ok "the Version History entry is dated" || no "the Version History entry carries no date"

# ============================================================================
echo "== (i) determinism: RAW UNFILTERED diff under two injected timestamps =="
RI="$(new_repo)"; seed_tree "$RI"
( cd "$RI" && FLOOR_SOURCE_DATE_EPOCH=1000000000 bash "$BUILD" ) >/dev/null 2>&1   # prime
JI="$RI/.supervisor/floor/floor.json"
( cd "$RI" && FLOOR_SOURCE_DATE_EPOCH=1000000000 bash "$BUILD" ) >/dev/null 2>&1; cp "$JI" "$ROOT/t1.json"
( cd "$RI" && FLOOR_SOURCE_DATE_EPOCH=2000000000 bash "$BUILD" ) >/dev/null 2>&1; cp "$JI" "$ROOT/t2.json"
( cd "$RI" && FLOOR_SOURCE_DATE_EPOCH=2000000000 bash "$BUILD" ) >/dev/null 2>&1; cp "$JI" "$ROOT/t3.json"

# Proof the seam is real: without it the assertion below could not distinguish runs.
grep -qF '1000000000' "$ROOT/t1.json" && grep -qF '2000000000' "$ROOT/t2.json" \
  && ok "the FLOOR_SOURCE_DATE_EPOCH seam actually reaches the artefact" \
  || no "the injected timestamp does not appear in the artefact - the seam is inert"

dtxt="$(diff "$ROOT/t1.json" "$ROOT/t2.json")"
nch="$(printf '%s\n' "$dtxt" | awk '/^[<>]/{n++} END{print n+0}')"
[ "$nch" -eq 2 ] \
  && ok "two DIFFERENT injected timestamps: exactly one changed line pair in the raw diff" \
  || no "raw diff has $nch changed lines, expected 2:
$dtxt"
printf '%s\n' "$dtxt" | grep '^[<>]' | grep -vqF 'generated_at_epoch' \
  && no "a changed line other than generated_at_epoch:
$dtxt" \
  || ok "the only changed line is generated_at_epoch"

dsame="$(diff "$ROOT/t2.json" "$ROOT/t3.json")"
nsame="$(printf '%s\n' "$dsame" | awk '/^[<>]/{n++} END{print n+0}')"
[ "$nsame" -eq 0 ] && cmp -s "$ROOT/t2.json" "$ROOT/t3.json" \
  && ok "the SAME injected timestamp is byte-identical with zero diff lines" \
  || no "same-timestamp runs differ ($nsame changed lines)"

# ============================================================================
echo "== (j) source-level: exactly one wall-clock read =="
# Strip full-line comments and trailing comments, then count `date` as a whole word.
clock_reads() {
  sed '/^[[:space:]]*#/d' "$1" | sed 's/[[:space:]]#.*$//' | grep -owE 'date' | awk 'NF{n++} END{print n+0}'
}
n_clock="$(clock_reads "$BUILD")"
[ "$n_clock" -eq 1 ] && ok "build-floor.sh contains exactly one wall-clock read" \
  || no "build-floor.sh contains $n_clock wall-clock reads, expected 1"

CLKMUT="$ROOT/clock-mutant.sh"
awk '{print} /^set -uo pipefail$/ && !d {print "second_clock=\"$(date -u +%s)\""; d=1}' "$BUILD" > "$CLKMUT"
if [ -s "$CLKMUT" ] && ! cmp -s "$CLKMUT" "$BUILD" && bash -n "$CLKMUT" 2>/dev/null; then
  [ "$(clock_reads "$CLKMUT")" -eq 2 ] \
    && ok "NEGATIVE CONTROL: a variant with a second clock read is detected (count 2, would fail)" \
    || no "the clock-read check did not notice a second clock read (count $(clock_reads "$CLKMUT"))"
else
  no "could not build a valid clock-read mutant - the negative control is inconclusive"
fi

# ============================================================================
echo "== (k) containment: git NEVER consulted; ignored files IN SCOPE =="
# `.supervisor/` is IGNORED, not untracked. Measured: a probe file written into
# .supervisor/logs/ is reported by NEITHER `git status --porcelain` NOR `--ignored`, so a
# git-based tree check sees neither an illegal write nor the legitimate output and could
# never fail. Everything below uses `find` + content hashes only.
hash_set() {
  ( cd "$1" 2>/dev/null || return 1
    find . -type f -not -path "./.git/*" -not -path "./.supervisor/floor/*" -print \
      | LC_ALL=C sort \
      | while IFS= read -r p; do printf '%s  %s\n' "$(csum "$p")" "$p"; done )
}
path_set() { ( cd "$1" 2>/dev/null || return 1; find . -type f -not -path "./.git/*" -print | LC_ALL=C sort ); }

RK="$(new_repo)"; seed_tree "$RK"
# Demonstrate WHY git is unusable here, rather than merely asserting it.
printf 'probe\n' > "$RK/.supervisor/logs/git-blindness-probe.log"
gsp="$( cd "$RK" && git status --porcelain 2>/dev/null | grep -c 'git-blindness-probe' )"
gsi="$( cd "$RK" && git status --porcelain --ignored 2>/dev/null | grep -c 'git-blindness-probe' )"
printf '%s\n' "# ignore" > "$RK/.gitignore"; printf '.supervisor/*\n' >> "$RK/.gitignore"
gsp2="$( cd "$RK" && git status --porcelain 2>/dev/null | grep -c 'git-blindness-probe' )"
[ "$gsp2" -eq 0 ] \
  && ok "measured: a probe under an ignored .supervisor/ is invisible to git status --porcelain" \
  || no "git status reported the ignored probe ($gsp2 hits; pre-ignore $gsp/$gsi) - re-check the premise"
rm -f "$RK/.supervisor/logs/git-blindness-probe.log" "$RK/.gitignore"

before_h="$(hash_set "$RK")"; before_p="$(path_set "$RK")"
[ -n "$before_h" ] && ok "pre-run hash set is non-empty ($(printf '%s\n' "$before_h" | awk 'NF{n++} END{print n+0}') files)" \
  || no "pre-run hash set is empty - the containment assertion would be vacuous"
run_build "$RK"
after_h="$(hash_set "$RK")"; after_p="$(path_set "$RK")"
[ "$before_h" = "$after_h" ] && ok "no file outside .supervisor/floor/ changed content or appeared" \
  || no "the tree changed:
$(diff <(printf '%s\n' "$before_h") <(printf '%s\n' "$after_h"))"
newp="$(diff <(printf '%s\n' "$before_p") <(printf '%s\n' "$after_p") | sed -n 's/^> //p')"
[ "$newp" = "./.supervisor/floor/floor.json" ] \
  && ok "floor.json is the ONLY path that appeared" || no "new paths: $newp"

echo "-- mutation control: the containment assertion must be able to turn RED --"
MUTB="$ROOT/write-mutant.sh"
{ head -1 "$BUILD"; printf 'printf x >> .supervisor/state.md\n'; tail -n +2 "$BUILD"; } > "$MUTB"
RK2="$(new_repo)"; seed_tree "$RK2"
if [ -s "$MUTB" ] && ! cmp -s "$MUTB" "$BUILD" && bash -n "$MUTB" 2>/dev/null; then
  b2="$(hash_set "$RK2")"
  ( cd "$RK2" && bash "$MUTB" >/dev/null 2>&1 ); mrc=$?
  a2="$(hash_set "$RK2")"
  if [ "$mrc" -eq 0 ] && [ -f "$RK2/.supervisor/floor/floor.json" ]; then
    ok "mutant is executable and still reaches its own success line (exit 0, artefact written)"
    [ "$b2" != "$a2" ] \
      && ok "MUTATION CONTROL: a one-byte write to .supervisor/state.md turns the assertion RED" \
      || no "the containment assertion stayed green against a mutant that wrote outside its output dir"
  else
    no "mutant did not reach its success line (rc=$mrc) - the mutation control is inconclusive"
  fi
else
  no "could not build a valid write-mutant - the mutation control is inconclusive"
fi

# ============================================================================
echo "== (l) stat flavour: an unverifiable mtime is OMITTED, never 0 =="
STUB="$ROOT/statstub"; mkdir -p "$STUB"
printf '#!/bin/sh\nprintf "/"\nexit 0\n' > "$STUB/stat"; chmod +x "$STUB/stat"
[ "$( PATH="$STUB:$PATH" stat -c %Y . 2>/dev/null )" = "/" ] \
  && ok "the stat stub is in effect (prints a mount point, mimicking GNU 'stat -f %m')" \
  || no "the stat stub is not in effect - this case would be vacuous"

RL="$(new_repo)"; seed_tree "$RL"
( cd "$RL" && PATH="$STUB:$PATH" bash "$BUILD" ) >/dev/null 2>&1; rcL=$?
JL="$RL/.supervisor/floor/floor.json"
[ "$rcL" -eq 0 ] && [ -f "$JL" ] && ok "exits 0 and still writes the artefact under a broken stat" \
  || no "expected exit 0 + artefact under a broken stat (rc=$rcL)"
n_mt="$(jq -r '[.surfaces[] | select(has("mtime_epoch"))] | length' "$JL" 2>/dev/null)"
[ "$n_mt" = "0" ] \
  && ok "every mtime_epoch is OMITTED - not empty, not 0, not the raw string" \
  || no "$n_mt surfaces kept an mtime_epoch under a broken stat: $(jq -c '[.surfaces|to_entries[]|select(.value|has("mtime_epoch"))|{(.key):.value.mtime_epoch}]' "$JL" 2>/dev/null)"
jq -e '[.surfaces[] | .mtime_epoch?] | map(select(. == 0 or . == "" or . == "/")) | length == 0' "$JL" >/dev/null 2>&1 \
  && ok "no surface carries a defaulted 0 / empty / raw-string mtime" || no "a defaulted mtime leaked through"

n_mt_ctl="$(jq -r '[.surfaces[] | select(has("mtime_epoch"))] | length' "$JA" 2>/dev/null)"
[ "$n_mt_ctl" -gt 0 ] \
  && ok "CONTROL: without the stub, $n_mt_ctl surfaces carry an mtime_epoch" \
  || no "CONTROL failed: no surface carries an mtime_epoch even with a working stat"
jq -e '[.surfaces[] | select(has("mtime_epoch")) | .mtime_epoch | type] | all(. == "number")' "$JA" >/dev/null 2>&1 \
  && ok "CONTROL: every emitted mtime_epoch is numeric" || no "CONTROL: a non-numeric mtime_epoch was emitted"

# ============================================================================
echo "== (m) real .supervisor/ corroboration (local only) =="
REAL="$(cd "$HERE/../.." 2>/dev/null && pwd)"
real_logs=("$REAL"/.supervisor/logs/*.jsonl)
if [ ! -d "$REAL/.supervisor" ]; then
  skipn "no .supervisor/ at $REAL (gitignored by '.supervisor/*'; expected absent in a fresh clone, a worktree and CI)"
elif [ "${#real_logs[@]}" -eq 0 ] || [ ! -e "${real_logs[0]}" ]; then
  skipn "$REAL/.supervisor/logs holds no *.jsonl (gitignored; expected absent in a fresh clone, a worktree and CI)"
else
  # MIRROR the real surfaces by symlink into a temp root, so the corroboration reads real
  # data while writing nothing whatsoever into the developer's checkout.
  MIR="$(mktmp)"; mkdir -p "$MIR/.supervisor" "$MIR/.agent"
  ( cd "$MIR" && git init -q ) >/dev/null 2>&1
  for s in logs jobs automate insights postmortem drain-rounds worker-summaries; do
    [ -e "$REAL/.supervisor/$s" ] && ln -s "$REAL/.supervisor/$s" "$MIR/.supervisor/$s"
  done
  [ -f "$REAL/.supervisor/state.md" ] && ln -s "$REAL/.supervisor/state.md" "$MIR/.supervisor/state.md"
  [ -d "$REAL/.agent/rules" ] && ln -s "$REAL/.agent/rules" "$MIR/.agent/rules"
  REALART="$REAL/.supervisor/floor/floor.json"
  real_before="$( [ -f "$REALART" ] && csum "$REALART" || echo ABSENT )"
  run_build "$MIR"; rcM=$?
  JM="$MIR/.supervisor/floor/floor.json"
  real_after="$( [ -f "$REALART" ] && csum "$REALART" || echo ABSENT )"
  [ "$rcM" -eq 0 ] && [ -f "$JM" ] && ok "real-tree mirror: exits 0 and writes the artefact" \
    || no "real-tree mirror: rc=$rcM, artefact $( [ -f "$JM" ] && echo present || echo absent )"
  # Reported either way - never a silently-vanishing assertion.
  [ "$real_before" = "$real_after" ] \
    && ok "the developer checkout is byte-unchanged by this corroboration (was: $real_before)" \
    || no "the corroboration wrote into the developer checkout ($real_before -> $real_after)"

  real_n() { ls -1 "$@" 2>/dev/null | awk 'NF{n++} END{print n+0}'; }
  cmp_real() {
    local key="$1" want="$2" got; got="$(scount "$JM" "$key")"
    if [ "$got" = "$want" ]; then ok "real $key == $want (independently recomputed)"
    elif [ "$(sstatus "$JM" "$key")" != "counted" ]; then
      skipn "real $key is $(sstatus "$JM" "$key"), not counted - nothing to corroborate"
    else no "real $key == $got, independent recount says $want"; fi
  }
  cmp_real logs             "$(real_n "$REAL"/.supervisor/logs/*.jsonl)"
  cmp_real jobs_done        "$(real_n "$REAL"/.supervisor/jobs/done/*.md)"
  cmp_real jobs_failed      "$(real_n "$REAL"/.supervisor/jobs/failed/*.md)"
  cmp_real drain_rounds     "$(real_n "$REAL"/.supervisor/drain-rounds/*.json)"
  cmp_real worker_summaries "$(real_n "$REAL"/.supervisor/worker-summaries/*.md)"
  cmp_real rules            "$(real_n "$REAL"/.agent/rules/*.json)"
  cmp_real postmortem       "$(awk 'NF{n++} END{print n+0}' "$REAL/.supervisor/postmortem/results.jsonl" 2>/dev/null)"

  real_sessions="$(cat "$REAL"/.supervisor/logs/*.jsonl 2>/dev/null \
    | jq -r 'select(has("cc_session_id")) | .cc_session_id' 2>/dev/null | LC_ALL=C sort -u | awk 'NF{n++} END{print n+0}')"
  cmp_real sessions "$real_sessions"
  validate_floor "$JM" >/dev/null 2>&1 \
    && ok "the real-tree artefact conforms to the schema parsed from RESULT_SCHEMAS.md" \
    || no "the real-tree artefact failed schema validation: $(validate_floor "$JM" 2>&1 | head -3)"
fi

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
exit 0
