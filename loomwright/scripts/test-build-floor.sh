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
#   (c2) blank / whitespace-only log lines - a SEPARATE seeded fixture carrying both shapes, so
#       `lines_scanned` (total - blank) and a bare total stop being the same number; two
#       mutation controls (the subtraction deleted, the classifier's `gsub` deleted)
#   (d) missing directory -> absent + named reason + NO count + exit 0
#   (e) empty log -> sessions absent + named reason + NO count + exit 0
#   (f) malformed JSON -> `unverified`, never `counted`, count omitted, offender named
#   (f2) UNREADABLE inputs -> `unverified`, count key ABSENT, offending path named, exit 0 -
#       one case per surface family (count_glob dir, count_json_docs dir, state.md,
#       postmortem/results.jsonl, logs/*.jsonl), each gated on a measured premise that
#       chmod 000 actually denies a read on this machine
#   (f3) an UNWRITABLE output path leaks no raw bash redirect diagnostic to the caller, with a
#       mutation control proving the un-brace-grouped variant does leak
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
#   (l2) clock-read failure - a `date` stub printing a non-numeric string must make
#       generated_at_epoch exactly `null` with the KEY STILL PRESENT, with a no-shim numeric
#       control and two mutation controls (a defaulted 0, and the key dropped)
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
# chmod before rm: the (f2) cases deliberately create unreadable paths and restore them
# in-block, but a mid-case abort must not strand a 000 directory that `rm -rf` cannot enter.
trap 'chmod -R u+rwX "$ROOT" >/dev/null 2>&1; rm -rf "$ROOT" 2>/dev/null' EXIT
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
# Echoes the offending sections; empty output means every section is counted and non-zero.
zero_offenders() {
  local j="$1" k st c out=""
  for k in $ALL_KEYS; do
    st="$(sstatus "$j" "$k")"; c="$(scount "$j" "$k")"
    case "$c" in ''|*[!0-9]*) out="$out $k(count=$c)"; continue ;; esac
    [ "$st" = "counted" ] || out="$out $k(status=$st)"
    [ "$c" -gt 0 ]        || out="$out $k(zero)"
  done
  printf '%s' "$out"
}
zo="$(zero_offenders "$JA")"
[ -z "$zo" ] \
  && ok "all 13 sections counted and non-zero" \
  || no "sections absent or zero:$zo"

# ANTI-VACUITY CONTROL: the same guard, pointed at an EMPTY fixture (a bare git repo with no
# .supervisor/ at all), must FAIL - and must fail on the zero/absent check itself, before any
# count comparison is reached. This is the assertion that makes "an empty tree can never
# satisfy this suite" a measurement rather than a claim: it is exactly the tree a fresh clone,
# a worktree and CI present.
REMPTY="$(new_repo)"
run_build "$REMPTY"; rcEmpty=$?
JEMPTY="$REMPTY/.supervisor/floor/floor.json"
[ "$rcEmpty" -eq 0 ] && [ -f "$JEMPTY" ] \
  && ok "empty fixture: still exits 0 and writes an artefact" \
  || no "empty fixture: rc=$rcEmpty, artefact $( [ -f "$JEMPTY" ] && echo present || echo absent )"
zoe="$(zero_offenders "$JEMPTY")"
n_zoe="$(printf '%s' "$zoe" | tr ' ' '\n' | awk 'NF{n++} END{print n+0}')"
[ -n "$zoe" ] && [ "$n_zoe" -eq 13 ] \
  && ok "ANTI-VACUITY: an EMPTY fixture fails the zero/absent guard on all 13 sections" \
  || no "an empty fixture was NOT caught by the zero/absent guard (offenders: '$zoe', n=$n_zoe)"
# ...and it fails on the guard, not merely on a count mismatch: no section is even `counted`.
[ "$(jq -r '[.surfaces[] | select(.status == "counted")] | length' "$JEMPTY" 2>/dev/null)" = "0" ] \
  && ok "ANTI-VACUITY: no section on the empty fixture reaches status counted at all" \
  || no "a section on the empty fixture reported status counted"

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

# The boundary between "no directory" (absent) and "directory exists but holds nothing"
# (a legitimately counted 0). This is the shape a fresh worktree actually has, and the
# empty-array expansion on this path aborts macOS bash 3.2 under `set -u` if written naively.
RZL="$(new_repo)"; mkdir -p "$RZL/.supervisor/logs"
echo "dispatch" > "$RZL/.supervisor/logs/review-pr-dispatch-1.log"
run_build "$RZL"; rcZL=$?
JZL="$RZL/.supervisor/floor/floor.json"
[ "$rcZL" -eq 0 ] && [ -f "$JZL" ] \
  && ok "logs dir present with zero *.jsonl: exits 0 and writes an artefact" \
  || no "logs dir present with zero *.jsonl: rc=$rcZL, artefact $( [ -f "$JZL" ] && echo present || echo absent )"
[ "$(sstatus "$JZL" logs)" = "counted" ] && [ "$(scount "$JZL" logs)" = "0" ] \
  && ok "an existing but jsonl-less logs dir is a legitimately COUNTED 0, not absent" \
  || no "logs on a jsonl-less dir: status=$(sstatus "$JZL" logs) count=$(scount "$JZL" logs)"
[ "$(sstatus "$JZL" sessions)" = "absent" ] && [ "$(scount "$JZL" sessions)" = "ABSENT" ] \
  && ok "sessions is absent with no count (a 0 there would be unprovable, not measured)" \
  || no "sessions on a jsonl-less dir: status=$(sstatus "$JZL" sessions) count=$(scount "$JZL" sessions)"

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
echo "== (c2) blank and whitespace-only log lines: skipped, tallied, never scanned =="
# THE GAP THIS CLOSES: not one fixture in this file - nor the committed
# fixtures/floor-sessions.jsonl - carried a blank line. So `lines_scanned` (= total - blank)
# and a bare total were THE SAME NUMBER on every tree the suite built, and
# `lines_blank_skipped` was asserted nowhere at all: a regression deleting the subtraction was
# invisible behind a fully green run. That is measured at the end of this block rather than
# claimed - the subtraction mutant's output is byte-identical to the real script's on a
# blank-free tree.
#
# A SEPARATE seeded fixture, deliberately NOT an edit to the committed
# fixtures/floor-sessions.jsonl. That file is pinned by EXP_SESS_LINES, EXP_SESSIONS and
# EXP_SESS_NO_ID and by (c)'s 3-ids / 1-noid / 8-lines drift check; adding two lines to it
# re-keys four expectations at once AND forces an edit to the very guard whose job is to
# notice that file changing. A new fixture buys the coverage without spending that guard.
#
# BOTH blank shapes are present and both are load-bearing. A truly EMPTY line and a
# WHITESPACE-ONLY line take the same branch, but only the second proves the classifier's
# `gsub("\\s"; "")` is doing work - an empty line alone is caught by a bare `. == ""`.
EXP_BLANK_TOTAL=4      # raw lines written to the seeded log
EXP_BLANK_SKIPPED=2    # one empty + one whitespace-only
EXP_BLANK_SCANNED=2    # TOTAL - SKIPPED: the formula under test
EXP_BLANK_SESSIONS=2

seed_blank_log() {
  { printf '{"cc_session_id":"s1"}\n'
    printf '\n'
    printf '   \n'
    printf '{"cc_session_id":"s2"}\n'; } > "$1"
}

RC2="$(new_repo)"; mkdir -p "$RC2/.supervisor/logs"
BLANKLOG="$RC2/.supervisor/logs/blank-lines.jsonl"
seed_blank_log "$BLANKLOG"
# PREMISE, measured: the seeded log really holds one EMPTY and one WHITESPACE-ONLY line. A
# trailing-whitespace-stripping editor collapses the second into the first shape, and every
# assertion below would then stay green while covering only half the branch.
b_total="$(awk 'END{print NR+0}' "$BLANKLOG")"
b_empty="$(awk 'length($0)==0{n++} END{print n+0}' "$BLANKLOG")"
b_ws="$(awk 'length($0)>0 && !/[^[:space:]]/{n++} END{print n+0}' "$BLANKLOG")"
[ "$b_total" -eq "$EXP_BLANK_TOTAL" ] && [ "$b_empty" -eq 1 ] && [ "$b_ws" -eq 1 ] \
  && ok "PREMISE: the seeded log is $EXP_BLANK_TOTAL lines with exactly one EMPTY and one WHITESPACE-ONLY line" \
  || no "seeded log drifted: total=$b_total empty=$b_empty whitespace-only=$b_ws (expected $EXP_BLANK_TOTAL/1/1)"

run_build "$RC2"; rcC2=$?
JC2="$RC2/.supervisor/floor/floor.json"
[ "$rcC2" -eq 0 ] && [ -f "$JC2" ] \
  && ok "blank-line fixture: exits 0 and writes an artefact" \
  || no "blank-line fixture: rc=$rcC2, artefact $( [ -f "$JC2" ] && echo present || echo absent )"

bdet() { jget "$JC2" ".surfaces.sessions.detail.$1"; }
[ "$(bdet lines_blank_skipped)" = "$EXP_BLANK_SKIPPED" ] \
  && ok "lines_blank_skipped == $EXP_BLANK_SKIPPED (both blank shapes take the blank branch)" \
  || no "lines_blank_skipped == $(bdet lines_blank_skipped), expected $EXP_BLANK_SKIPPED"
[ "$(bdet lines_scanned)" = "$EXP_BLANK_SCANNED" ] \
  && ok "lines_scanned == $EXP_BLANK_SCANNED (total $EXP_BLANK_TOTAL minus $EXP_BLANK_SKIPPED blanks)" \
  || no "lines_scanned == $(bdet lines_scanned), expected $EXP_BLANK_SCANNED"
# The entire point of this fixture: the two formulas no longer agree on it.
[ "$EXP_BLANK_SCANNED" != "$EXP_BLANK_TOTAL" ] && [ "$(bdet lines_scanned)" != "$b_total" ] \
  && ok "lines_scanned ($EXP_BLANK_SCANNED) differs from the raw line total ($b_total) - the two formulas are now distinguishable" \
  || no "lines_scanned still equals the raw line total - this fixture does not separate the formulas"
[ "$(bdet lines_malformed)" = "0" ] \
  && ok "a blank line is SKIPPED, never counted as malformed (lines_malformed == 0)" \
  || no "lines_malformed == $(bdet lines_malformed), expected 0"
[ "$(bdet lines_with_session_id)" = "2" ] && [ "$(bdet lines_without_session_id)" = "0" ] \
  && ok "the two real records are still accounted (with_session_id 2 / without 0)" \
  || no "with_session_id=$(bdet lines_with_session_id) without=$(bdet lines_without_session_id), expected 2/0"
[ "$(sstatus "$JC2" sessions)" = "counted" ] && count_is "$JC2" sessions "$EXP_BLANK_SESSIONS" \
  && ok "sessions == counted/$EXP_BLANK_SESSIONS across a log containing blank lines" \
  || no "sessions == $(sstatus "$JC2" sessions)/$(scount "$JC2" sessions), expected counted/$EXP_BLANK_SESSIONS"

echo "-- mutation controls: both blank-line assertions must be able to turn RED --"
# MUTANT 1 - the subtraction deleted, so `lines_scanned` becomes the raw total.
# ENVIRON, not `awk -v`, throughout: -v processes escape sequences, so `\\s` and `\n` inside
# these literals would be rewritten and the line comparison could never match.
SL_OLD='  sess_lines=$((sess_total - sess_blank))'
SL_NEW='  sess_lines=$sess_total'
SLMUT="$ROOT/sess-lines-mutant.sh"
SL_OLD="$SL_OLD" SL_NEW="$SL_NEW" awk '
  BEGIN{o=ENVIRON["SL_OLD"]; n=ENVIRON["SL_NEW"]}
  $0==o && !d {print n; d=1; next} {print}' "$BUILD" > "$SLMUT"
if [ -s "$SLMUT" ] && ! cmp -s "$SLMUT" "$BUILD" && bash -n "$SLMUT" 2>/dev/null \
   && grep -qF "$SL_NEW" "$SLMUT"; then
  ok "the blank-subtraction mutant is buildable and bash -n clean"
  RSL="$(new_repo)"; mkdir -p "$RSL/.supervisor/logs"
  seed_blank_log "$RSL/.supervisor/logs/blank-lines.jsonl"
  ( cd "$RSL" && bash "$SLMUT" ) >/dev/null 2>&1; rcSL=$?
  JSL="$RSL/.supervisor/floor/floor.json"
  if [ "$rcSL" -eq 0 ] && [ -f "$JSL" ]; then
    ok "the mutant still reaches its own success line (exit 0 + artefact written)"
    [ "$(jget "$JSL" '.surfaces.sessions.detail.lines_scanned')" = "$EXP_BLANK_TOTAL" ] \
      && ok "MUTATION CONTROL: the mutant reports lines_scanned == $EXP_BLANK_TOTAL on this fixture, turning the assertion RED" \
      || no "the mutant reported lines_scanned == $(jget "$JSL" '.surfaces.sessions.detail.lines_scanned') - control inconclusive"
  else
    no "the blank-subtraction mutant did not reach its success line (rc=$rcSL) - control inconclusive"
  fi
  # ...and THIS is why the gap was invisible: on a blank-FREE tree the same mutant and the real
  # script are indistinguishable, so every pre-existing assertion stays green against it.
  RSL2="$(new_repo)"; seed_tree "$RSL2"
  ( cd "$RSL2" && bash "$SLMUT" ) >/dev/null 2>&1
  JSL2="$RSL2/.supervisor/floor/floor.json"
  [ "$(jget "$JSL2" '.surfaces.sessions.detail.lines_scanned')" = "$EXP_SESS_LINES" ] \
    && ok "GAP MEASURED: on the blank-FREE fixture the same mutant still reports lines_scanned == $EXP_SESS_LINES, identical to the real script - which is why nothing caught it" \
    || no "the mutant diverged on the blank-free fixture ($(jget "$JSL2" '.surfaces.sessions.detail.lines_scanned')) - the gap rationale needs re-checking"
else
  no "could not build a valid blank-subtraction mutant - this control is inconclusive"
fi

# MUTANT 2 - the classifier's whitespace normalisation deleted, so only a TRULY empty line is
# blank. This is what makes the whitespace-only line load-bearing rather than decorative: that
# record then falls through to `fromjson`, fails, and is reported MALFORMED - which drags the
# whole surface to `unverified` with no count at all.
GS_OLD='    if ((. | gsub("\\s"; "")) == "") then "blank"'
GS_NEW='    if (. == "") then "blank"'
GSMUT="$ROOT/blank-gsub-mutant.sh"
GS_OLD="$GS_OLD" GS_NEW="$GS_NEW" awk '
  BEGIN{o=ENVIRON["GS_OLD"]; n=ENVIRON["GS_NEW"]}
  $0==o && !d {print n; d=1; next} {print}' "$BUILD" > "$GSMUT"
# Exactly one gsub must survive. The identical line appears in the postmortem classifier and
# only the SESSIONS one (the first) may be mutated, or this control changes two things at once.
if [ -s "$GSMUT" ] && ! cmp -s "$GSMUT" "$BUILD" && bash -n "$GSMUT" 2>/dev/null \
   && [ "$(grep -cF 'gsub("\\s"; "")' "$GSMUT")" = "1" ]; then
  ok "the whitespace-normalisation mutant is buildable, bash -n clean, and touches only the sessions classifier"
  RGS="$(new_repo)"; mkdir -p "$RGS/.supervisor/logs"
  seed_blank_log "$RGS/.supervisor/logs/blank-lines.jsonl"
  ( cd "$RGS" && bash "$GSMUT" ) >/dev/null 2>&1; rcGS=$?
  JGS="$RGS/.supervisor/floor/floor.json"
  if [ "$rcGS" -eq 0 ] && [ -f "$JGS" ]; then
    ok "the mutant still reaches its own success line (exit 0 + artefact written)"
    [ "$(jget "$JGS" '.surfaces.sessions.detail.lines_blank_skipped')" = "1" ] \
      && [ "$(jget "$JGS" '.surfaces.sessions.detail.lines_malformed')" = "1" ] \
      && [ "$(sstatus "$JGS" sessions)" = "unverified" ] && [ "$(scount "$JGS" sessions)" = "ABSENT" ] \
      && ok "MUTATION CONTROL: without the gsub the WHITESPACE-ONLY line is misread as malformed (blank 1 / malformed 1 / unverified / no count) - the assertions above turn RED" \
      || no "the gsub mutant did not change the classification (blank=$(jget "$JGS" '.surfaces.sessions.detail.lines_blank_skipped') malformed=$(jget "$JGS" '.surfaces.sessions.detail.lines_malformed') status=$(sstatus "$JGS" sessions)) - the whitespace-only line would prove nothing"
  else
    no "the whitespace-normalisation mutant did not reach its success line (rc=$rcGS) - control inconclusive"
  fi
else
  no "could not build a valid whitespace-normalisation mutant - this control is inconclusive"
fi

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
echo "== (f2) unreadable input -> unverified, count OMITTED, path named, exit 0 =="
# THE GAP THIS CLOSES: before this block, `grep -n chmod` over this file returned exactly ONE
# hit - the `chmod +x` on the (l) stat stub. No test made any input unreadable, so all three of
# build-floor.sh's `! -r` branches were UNCOVERED and the two that were MISSING were invisible
# behind a fully green suite. The failure is not loud: under `nullglob` an unreadable directory
# expands to ZERO arguments, which is byte-indistinguishable from an empty one, so the surface
# fell into the "counted 0" arm and shipped a FABRICATED zero carrying an `mtime_epoch` that
# implies a real reading. Nothing but asserting the readability of the input itself can tell
# those two trees apart.
unreadable_premise() {
  # chmod 000 does not stop root, and some filesystems ignore mode bits entirely. Measure the
  # premise on THIS machine instead of assuming it - otherwise every assertion below is vacuous.
  local p="$ROOT/unreadable-premise" denied=1
  rm -rf "$p" 2>/dev/null; mkdir -p "$p/d" 2>/dev/null; : > "$p/f"
  chmod 000 "$p/d" "$p/f" 2>/dev/null
  { [ ! -r "$p/d" ] && [ ! -r "$p/f" ]; } || denied=0
  # Restore and clean up BEFORE returning, so the probe never outlives the check.
  chmod -R u+rwX "$p" >/dev/null 2>&1; rm -rf "$p" 2>/dev/null
  [ "$denied" -eq 1 ]
}
if ! unreadable_premise; then
  skipn "chmod 000 does not deny a read here (running as root, or a mode-less filesystem) - the unreadable-input cases cannot be exercised and are NOT counted as passes"
else
  ok "PREMISE: chmod 000 genuinely denies a read on this machine (the cases below are not vacuous)"
  # <label> <surface key> <path relative to the fixture root> <substring the reason must name>
  unreadable_case() {
    local label="$1" key="$2" rel="$3" want="$4"
    local r j rc st cnt rsn
    r="$(new_repo)"; seed_tree "$r"
    chmod 000 "$r/$rel" 2>/dev/null
    if [ -r "$r/$rel" ]; then no "$label: $rel is still readable - case is vacuous"; return 0; fi
    ( cd "$r" && bash "$BUILD" ) >/dev/null 2>&1; rc=$?
    j="$r/.supervisor/floor/floor.json"
    st="$(sstatus "$j" "$key")"; cnt="$(scount "$j" "$key")"; rsn="$(sreason "$j" "$key")"
    # Restore in the SAME block, so teardown stays clean whatever the assertions say.
    chmod -R u+rwX "$r/$rel" >/dev/null 2>&1
    [ "$rc" -eq 0 ] && ok "$label: exits 0" || no "$label: expected exit 0, got $rc"
    [ -f "$j" ] && ok "$label: the artefact is still written" || no "$label: no artefact written"
    [ "$st" = "unverified" ] \
      && ok "$label: status == unverified" \
      || no "$label: status == $st, expected unverified"
    [ "$cnt" = "ABSENT" ] \
      && ok "$label: count key is OMITTED (never a zero it did not measure)" \
      || no "$label: emitted count $cnt for an input it could not read - a fabricated zero"
    printf '%s' "$rsn" | grep -qF "$want" \
      && ok "$label: reason names $want" \
      || no "$label: reason does not name $want (reason: '$rsn')"
  }
  unreadable_case "unreadable dir via count_glob" \
    jobs_done    ".supervisor/jobs/done"                  ".supervisor/jobs/done"
  unreadable_case "unreadable dir via count_json_docs" \
    drain_rounds ".supervisor/drain-rounds"               ".supervisor/drain-rounds"
  unreadable_case "unreadable dir via count_json_docs (rules)" \
    rules        ".agent/rules"                           ".agent/rules"
  unreadable_case "unreadable state.md" \
    state        ".supervisor/state.md"                   ".supervisor/state.md"
  unreadable_case "unreadable postmortem ledger" \
    postmortem   ".supervisor/postmortem/results.jsonl"   ".supervisor/postmortem/results.jsonl"
  unreadable_case "unreadable logs/*.jsonl member" \
    sessions     ".supervisor/logs/second.jsonl"          ".supervisor/logs/second.jsonl"

  # The unreadable-member case again, this time asserting the two properties a bulk
  # `cat ... 2>/dev/null` gets WRONG in the same breath: it drops the file's lines silently, so
  # `sessions` reports a `counted` UNDERCOUNT *and* `lines_malformed: 0` - actively asserting
  # cleanliness about bytes it never read. `logs` must stay counted at 3, because glob
  # membership IS provable from a readable directory; only the CONTENT reading is unverified.
  RU="$(new_repo)"; seed_tree "$RU"
  chmod 000 "$RU/.supervisor/logs/second.jsonl" 2>/dev/null
  if [ -r "$RU/.supervisor/logs/second.jsonl" ]; then
    no "unreadable log member: the file is still readable - this pair is vacuous"
  else
    run_build "$RU"
    JU="$RU/.supervisor/floor/floor.json"
    chmod -R u+rwX "$RU/.supervisor/logs" >/dev/null 2>&1
    [ "$(sstatus "$JU" logs)" = "counted" ] && [ "$(scount "$JU" logs)" = "$EXP_LOGS" ] \
      && ok "logs stays counted at $EXP_LOGS - glob membership is provable from a readable dir" \
      || no "logs == $(sstatus "$JU" logs)/$(scount "$JU" logs), expected counted/$EXP_LOGS"
    [ "$(jget "$JU" '.surfaces.sessions.detail.lines_malformed')" = "null" ] \
      && ok "sessions publishes NO lines_malformed tally over bytes it could not read" \
      || no "sessions asserted lines_malformed == $(jget "$JU" '.surfaces.sessions.detail.lines_malformed') over an unreadable file"
    [ "$(scount "$JU" sessions)" != "$EXP_SESSIONS" ] && [ "$(scount "$JU" sessions)" = "ABSENT" ] \
      && ok "sessions publishes no count at all, rather than a silent undercount" \
      || no "sessions count == $(scount "$JU" sessions) with one log unreadable"
  fi

  # A directory named `*.jsonl` is a glob member that is readable but is NOT a record stream;
  # `cat` on it fails the same silent way. The guard must be `-f` as well as `-r`.
  RDJ="$(new_repo)"; seed_tree "$RDJ"
  mkdir -p "$RDJ/.supervisor/logs/a-directory.jsonl"
  run_build "$RDJ"; rcDJ=$?
  JDJ="$RDJ/.supervisor/floor/floor.json"
  [ "$rcDJ" -eq 0 ] && ok "directory named *.jsonl: exits 0" || no "expected exit 0, got $rcDJ"
  [ "$(sstatus "$JDJ" sessions)" = "unverified" ] && [ "$(scount "$JDJ" sessions)" = "ABSENT" ] \
    && ok "a directory named *.jsonl makes sessions unverified with no count" \
    || no "sessions == $(sstatus "$JDJ" sessions)/$(scount "$JDJ" sessions) with a directory named *.jsonl"
  sreason "$JDJ" sessions | grep -qF "a-directory.jsonl" \
    && ok "reason names the offending glob member" \
    || no "reason does not name the offending glob member: $(sreason "$JDJ" sessions)"

  # A file whose last record carries no trailing newline. A bulk `cat` splices it onto the
  # first record of the NEXT file, destroying TWO valid records and reporting the splice as a
  # malformed line - blaming the reader for the reader's own defect.
  RNL="$(new_repo)"; seed_tree "$RNL"
  rm -f "$RNL/.supervisor/logs"/*.jsonl
  printf '{"event":"a","cc_session_id":"sess-nl-0001"}\n{"event":"b","cc_session_id":"sess-nl-0002"}' \
    > "$RNL/.supervisor/logs/aaa-no-trailing-newline.jsonl"
  printf '{"event":"c","cc_session_id":"sess-nl-0003"}\n' \
    > "$RNL/.supervisor/logs/bbb-normal.jsonl"
  run_build "$RNL"
  JNL="$RNL/.supervisor/floor/floor.json"
  [ "$(sstatus "$JNL" sessions)" = "counted" ] && [ "$(scount "$JNL" sessions)" = "3" ] \
    && ok "a newline-less final record does not swallow the next file's first record (3 ids)" \
    || no "newline-less final record: sessions == $(sstatus "$JNL" sessions)/$(scount "$JNL" sessions), expected counted/3"
  [ "$(jget "$JNL" '.surfaces.sessions.detail.lines_malformed')" = "0" ] \
    && ok "and no splice is misreported as a malformed line" \
    || no "lines_malformed == $(jget "$JNL" '.surfaces.sessions.detail.lines_malformed') on a well-formed newline-less file"
fi

# ============================================================================
echo "== (f3) unwritable OUTPUT -> our own message only, no bash diagnostic, exit 0 =="
if ! unreadable_premise; then
  skipn "mode bits are not enforced here - the unwritable-output case cannot be exercised"
else
  # bash opens the redirect and reports ITS OWN `line NNN: <path>: Permission denied` BEFORE
  # `printf` is ever executed, so a command-level `2>/dev/null` on the printf arrives too late
  # and the caller sees a raw diagnostic naming a source line. Only a redirection on the brace
  # GROUP covers the failing redirect itself.
  RW="$(new_repo)"; seed_tree "$RW"
  mkdir -p "$RW/.supervisor/floor"; : > "$RW/.supervisor/floor/floor.json"
  chmod 400 "$RW/.supervisor/floor/floor.json" 2>/dev/null
  if [ -w "$RW/.supervisor/floor/floor.json" ]; then
    no "unwritable output: floor.json is still writable - this case is vacuous"
  else
    errW="$( cd "$RW" && bash "$BUILD" 2>&1 >/dev/null )"; rcW=$?
    [ "$rcW" -eq 0 ] && ok "unwritable output: still exits 0" \
      || no "unwritable output: expected exit 0, got $rcW"
    printf '%s' "$errW" | grep -qF "build-floor: cannot write" \
      && ok "unwritable output: the script's own one-line message is emitted" \
      || no "unwritable output: our own message is missing (stderr: '$errW')"
    printf '%s' "$errW" | grep -qiE 'line [0-9]+:|permission denied' \
      && no "unwritable output: a raw bash redirect diagnostic leaked: '$errW'" \
      || ok "unwritable output: no raw bash redirect diagnostic leaks to the caller"

    # MUTATION CONTROL. Without it, "no diagnostic leaked" could be green because the write
    # never failed at all. The un-brace-grouped variant must LEAK against this same fixture.
    WMUT="$ROOT/write-redirect-mutant.sh"
    WM_OLD='{ printf '"'"'%s\n'"'"' "$out_json" > "$OUT"; } 2>/dev/null || {'
    WM_NEW='printf '"'"'%s\n'"'"' "$out_json" > "$OUT" 2>/dev/null || {'
    # ENVIRON, not `awk -v`: -v processes escape sequences, so the `\n` inside the literal
    # would become a real newline and the line comparison could never match.
    WM_OLD="$WM_OLD" WM_NEW="$WM_NEW" awk '
      BEGIN{o=ENVIRON["WM_OLD"]; n=ENVIRON["WM_NEW"]}
      $0==o && !d {print n; d=1; next} {print}' "$BUILD" > "$WMUT"
    if [ -s "$WMUT" ] && ! cmp -s "$WMUT" "$BUILD" && bash -n "$WMUT" 2>/dev/null \
       && grep -qF "$WM_NEW" "$WMUT"; then
      ok "the un-brace-grouped write mutant is buildable and bash -n clean"
      errWM="$( cd "$RW" && bash "$WMUT" 2>&1 >/dev/null )"; rcWM=$?
      if [ "$rcWM" -eq 0 ] && printf '%s' "$errWM" | grep -qF "build-floor: cannot write"; then
        ok "the mutant still reaches its own success path (exit 0 + its own message)"
        printf '%s' "$errWM" | grep -qiE 'line [0-9]+:|permission denied' \
          && ok "MUTATION CONTROL: the un-brace-grouped variant DOES leak a bash diagnostic" \
          || no "the un-brace-grouped variant leaked nothing - the leak assertion is vacuous"
      else
        no "the write mutant did not reach its success path (rc=$rcWM) - control inconclusive"
      fi
    else
      no "could not build a valid un-brace-grouped write mutant - control inconclusive"
    fi
  fi
  chmod -R u+rwX "$RW/.supervisor/floor" >/dev/null 2>&1
fi

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

# The two checks above are SECTION-SCOPED (one addresses the single `Current versions:` line,
# the other a bounded awk range) rather than whole-file greps. That is itself a claim, and a
# claim no check backs is the failure mode this repo keeps rediscovering - so falsify it.
# Both mutants below RELOCATE the text rather than deleting it: a whole-file `grep -F
# FLOOR_PROJECTION` still succeeds on each, so only a section-scoped parse can reject them.
companion_ok() {
  local md="$1" il vhl
  il="$(grep -m1 'Current versions:' "$md" 2>/dev/null)"
  [ -n "$il" ] || return 1
  printf '%s' "$il" | grep -qF 'FLOOR_PROJECTION at `schema_version: 1`' || return 1
  printf '%s' "$il" | grep -qi 'FLOOR_PROJECTION.*no hook validator'     || return 1
  vhl="$(awk '/^### Version History$/{f=1;next} f&&/^## /{exit} f' "$md" 2>/dev/null | grep -F 'FLOOR_PROJECTION' | head -1)"
  [ -n "$vhl" ] || return 1
  printf '%s' "$vhl" | grep -qE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' || return 1
  return 0
}
companion_ok "$SCHEMA_MD" \
  && ok "CONTROL: the real RESULT_SCHEMAS.md passes the section-scoped companion check" \
  || no "the real RESULT_SCHEMAS.md failed the section-scoped companion check"

# Mutant 1 - the Version-History entry moved OUT of its section, re-appended at end of file.
MVH="$ROOT/schema-vh-relocated.md"
awk '
  /^### Version History$/ {inv=1; print; next}
  inv && /^## / {inv=0}
  inv && /FLOOR_PROJECTION/ {saved=$0; next}
  {print}
  END {if (saved != "") print saved}
' "$SCHEMA_MD" > "$MVH"
if [ -s "$MVH" ] && ! cmp -s "$MVH" "$SCHEMA_MD" && grep -qF 'FLOOR_PROJECTION' "$MVH"; then
  ok "mutant 1 is a RELOCATION: FLOOR_PROJECTION still present in the file (a whole-file grep would pass it)"
  companion_ok "$MVH" \
    && no "a Version-History entry moved out of its section was ACCEPTED - the check is a whole-file grep" \
    || ok "MUTATION CONTROL: the entry relocated out of ### Version History is REJECTED"
else
  no "could not build the Version-History relocation mutant - this control is inconclusive"
fi

# Mutant 2 - the FLOOR_PROJECTION clause lifted OUT of the `Current versions:` paragraph
# and left as its own line immediately below it.
MIN="$ROOT/schema-intro-relocated.md"
awk -v n="FLOOR_PROJECTION at " '
  !d && /Current versions:/ {
    i = index($0, n)
    if (i > 0) {
      print substr($0, 1, i-1) substr($0, i + length(n))
      print ""
      print "FLOOR_PROJECTION at `schema_version: 1` (no hook validator)"
      d = 1
      next
    }
  }
  {print}
' "$SCHEMA_MD" > "$MIN"
if [ -s "$MIN" ] && ! cmp -s "$MIN" "$SCHEMA_MD" && grep -qF 'FLOOR_PROJECTION at `schema_version: 1`' "$MIN"; then
  ok "mutant 2 is a RELOCATION: the clause still present in the file (a whole-file grep would pass it)"
  companion_ok "$MIN" \
    && no "an intro clause moved out of the Current versions: paragraph was ACCEPTED" \
    || ok "MUTATION CONTROL: the clause relocated out of the Current versions: paragraph is REJECTED"
else
  no "could not build the intro relocation mutant - this control is inconclusive"
fi

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
# Strip full-line comments and trailing comments, then count every WALL-CLOCK IDIOM, not just
# `date`. A whole-word `date` alone is not the property being claimed: the clock is readable
# four other ways that never spell the word - `printf '%(%s)T'`, `$EPOCHSECONDS`, `$SECONDS`,
# and `git log -1 --format=%ct` (in three spellings) - and each would sail past a `date`-only
# grep while breaking determinism. The (i) determinism case cannot compensate: two runs a fraction of a second
# apart read the same second and diff clean, so it goes green on exactly the smuggled reads
# this check exists to catch.
CLOCK_RE='date|%\(%s\)T|EPOCHSECONDS|SECONDS|--format=%ct|--pretty=%ct|--pretty=format:%ct'
clock_reads() {
  sed '/^[[:space:]]*#/d' "$1" | sed 's/[[:space:]]#.*$//' \
    | grep -owE "$CLOCK_RE" | awk 'NF{n++} END{print n+0}'
}
n_clock="$(clock_reads "$BUILD")"
[ "$n_clock" -eq 1 ] && ok "build-floor.sh contains exactly one wall-clock read" \
  || no "build-floor.sh contains $n_clock wall-clock reads, expected 1"

# One mutant PER IDIOM. A single `date` mutant only proves the grep can see the idiom it
# already names; the alternation is only worth something if every branch of it is exercised.
# EVERY branch of the alternation gets its own mutant, including the two `git log` spellings:
# an alternation branch no mutant exercises is a branch nobody has shown can fire.
CLOCK_IDIOMS=7
clock_bad=""; clock_ok=0; clock_i=0
for idiom in \
  'second_clock="$(date -u +%s)"' \
  'printf -v second_clock "%(%s)T" -1' \
  'second_clock="$EPOCHSECONDS"' \
  'second_clock="$SECONDS"' \
  'second_clock="$(git log -1 --format=%ct)"' \
  'second_clock="$(git log -1 --pretty=%ct)"' \
  'second_clock="$(git log -1 --pretty=format:%ct)"'
do
  # clock_i indexes the file, clock_ok counts successes - one variable cannot do both, or a
  # mutant that fails to build silently reuses the previous mutant's path.
  clock_i=$((clock_i + 1))
  CLKMUT="$ROOT/clock-mutant-$clock_i.sh"
  awk -v ins="$idiom" '{print} /^set -uo pipefail$/ && !d {print ins; d=1}' "$BUILD" > "$CLKMUT"
  if [ -s "$CLKMUT" ] && ! cmp -s "$CLKMUT" "$BUILD" && bash -n "$CLKMUT" 2>/dev/null; then
    if [ "$(clock_reads "$CLKMUT")" -eq 2 ]; then clock_ok=$((clock_ok + 1))
    else clock_bad="$clock_bad [$idiom -> $(clock_reads "$CLKMUT")]"; fi
  else
    clock_bad="$clock_bad [$idiom -> mutant-not-buildable]"
  fi
done
[ "$clock_ok" -eq "$CLOCK_IDIOMS" ] && [ -z "$clock_bad" ] \
  && ok "NEGATIVE CONTROL: each of the $clock_ok smuggled clock idioms is detected (count 2, would fail)" \
  || no "the clock-read check missed a smuggled idiom ($clock_ok/$CLOCK_IDIOMS detected):$clock_bad"

# The notes[] fallback must not assert "nothing was omitted". This is a SOURCE-level check by
# necessity: the fallback fires only if jq fails while assembling notes, and jq's presence is
# already a hard precondition of reaching that line, so no input reaches it. Forcing it would
# mean stubbing jq to fail on one invocation and succeed on the others - a fixture that tests
# the stub. What IS checkable is that the fallback value is not a false all-clear.
# Comment lines are stripped FIRST: a comment that quotes the literal it warns about would
# otherwise trip this check, which is the second-order trap this repo has recorded before.
build_code() { sed '/^[[:space:]]*#/d' "$BUILD"; }
build_code | grep -qF "notes_json='[]'" \
  && no "the notes fallback is a bare [] - it claims nothing was omitted at exactly the moment that is unknown" \
  || ok "the notes fallback is not a bare [] (an empty array there would be a false all-clear)"
nf_line="$(build_code | grep -F '|| notes_json=' | head -1)"
nf_val="$(printf '%s' "$nf_line" | sed "s/^.*|| notes_json=//; s/^'//; s/'\$//")"
printf '%s' "$nf_val" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
  && ok "the notes fallback is a valid, NON-empty JSON array" \
  || no "the notes fallback is not a valid non-empty JSON array: '$nf_val'"
printf '%s' "$nf_val" | jq -e 'all(.[]; test("could not be assembled"))' >/dev/null 2>&1 \
  && ok "and it records that the list could not be assembled, rather than implying an all-clear" \
  || no "the notes fallback does not say why it is not evidence: '$nf_val'"

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
# `-type f` ALONE would make a stray directory or a symlink dropped outside .supervisor/floor/
# invisible to the containment assertion - and a symlink is the cheapest way to escape a
# directory allow-list. Directories and symlinks are in scope; the ./.git/* exclusion stays
# (plus ./.git itself, which -type d would otherwise add as constant noise).
path_set() {
  ( cd "$1" 2>/dev/null || return 1
    find . \( -type f -o -type l -o -type d \) \
      -not -path "./.git/*" -not -path "./.git" -print | LC_ALL=C sort )
}

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
# Two, not one: path_set now sees directories, and the script legitimately CREATES its own
# output directory. Anything else - a file, a directory or a symlink - is a containment breach.
want_newp="$(printf './.supervisor/floor\n./.supervisor/floor/floor.json')"
[ "$newp" = "$want_newp" ] \
  && ok "the output dir and floor.json are the ONLY paths that appeared" \
  || no "new paths: $newp"

# The path_set widening is itself a claim; falsify it. A symlink and a directory planted
# outside .supervisor/floor/ must both turn the assertion RED - under `-type f` they did not.
for kind in symlink directory; do
  RK3="$(new_repo)"; seed_tree "$RK3"
  b3="$(path_set "$RK3")"
  case "$kind" in
    symlink)   ln -s /etc/hosts "$RK3/.supervisor/stray-link" 2>/dev/null ;;
    directory) mkdir -p "$RK3/.supervisor/stray-dir" ;;
  esac
  a3="$(path_set "$RK3")"
  [ "$b3" != "$a3" ] \
    && ok "MUTATION CONTROL: a stray $kind outside .supervisor/floor/ is VISIBLE to path_set" \
    || no "a stray $kind outside .supervisor/floor/ is invisible to path_set"
done

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
echo "== (l2) a failed clock read is generated_at_epoch: null - present, never 0 =="
# THE GAP THIS CLOSES: the `## FLOOR_PROJECTION` block in RESULT_SCHEMAS.md documents
# `generated_at_epoch` as `integer|null, required`, `null` ONLY when the clock read itself
# failed, "the key is always present" - and nothing anywhere tested it. (i) and (j) both name
# the field but neither ever FAILS the clock: (i) asserts only that it is the one line that
# changes between two injected timestamps, and (j) counts clock reads in the source. Same
# shape as (l) directly above - an unverifiable value is reported as unknown, never defaulted -
# and the same mechanism: a PATH stub for one coreutils binary.
DSTUB="$ROOT/datestub"; mkdir -p "$DSTUB"
printf '#!/bin/sh\necho "not-a-number"\n' > "$DSTUB/date"; chmod +x "$DSTUB/date"
[ "$( PATH="$DSTUB:$PATH" date -u +%s 2>/dev/null )" = "not-a-number" ] \
  && ok "the date stub is in effect (a non-numeric clock read, mimicking a broken date)" \
  || no "the date stub is not in effect - this case would be vacuous"

# The clock comparators - used UNCHANGED for the real assertions and for both mutants.
# Presence and value are asserted SEPARATELY because neither alone is discriminating: a
# key-less document also reads `.generated_at_epoch == null`, and a defaulted `0` also
# satisfies `has()`. Each mutant below is caught by exactly one of the two.
epoch_present() { jq -e 'has("generated_at_epoch")' "$1" >/dev/null 2>&1; }
epoch_is_null() { jq -e 'has("generated_at_epoch") and .generated_at_epoch == null' "$1" >/dev/null 2>&1; }
epoch_raw()     { jq -c '.generated_at_epoch' "$1" 2>/dev/null; }
# For DIAGNOSTICS only. A bare `epoch_raw` on a key-less document prints `null`, so a failure
# message built from it reads "generated_at_epoch == null, expected null" - measured against
# the key-dropped variant. The two states must be distinguishable in the output, not only in
# the assertion.
epoch_desc()    { if epoch_present "$1"; then printf 'PRESENT with value %s' "$(epoch_raw "$1")"
                  else printf 'ABSENT (which a bare value read still reports as null)'; fi; }

RL2="$(new_repo)"; seed_tree "$RL2"
JL2="$RL2/.supervisor/floor/floor.json"

# NO-SHIM CONTROL first, on the SAME tree. Without it the null assertion is not
# discriminating - a producer that emitted null unconditionally would satisfy it.
( cd "$RL2" && unset FLOOR_SOURCE_DATE_EPOCH; bash "$BUILD" ) >/dev/null 2>&1; rcL2c=$?
[ "$rcL2c" -eq 0 ] && [ -f "$JL2" ] \
  && ok "CONTROL: with a working clock the script exits 0 and writes the artefact" \
  || no "CONTROL: rc=$rcL2c, artefact $( [ -f "$JL2" ] && echo present || echo absent )"
epoch_present "$JL2" && jq -e '.generated_at_epoch | type == "number"' "$JL2" >/dev/null 2>&1 \
  && ok "CONTROL: with a working clock generated_at_epoch is PRESENT and NUMERIC ($(epoch_raw "$JL2"))" \
  || no "CONTROL: generated_at_epoch is $(epoch_desc "$JL2") with a working clock"
epoch_is_null "$JL2" \
  && no "CONTROL: the null comparator accepted a working-clock artefact - it is not discriminating" \
  || ok "CONTROL: the null comparator REJECTS a working-clock artefact"

# The FLOOR_SOURCE_DATE_EPOCH seam must be OUT of the way or the stub proves nothing: it
# short-circuits the `date` call entirely. Measured here, not assumed, which is also why every
# run below unsets it inside its own subshell rather than trusting the ambient environment.
( cd "$RL2" && FLOOR_SOURCE_DATE_EPOCH=1500000000 PATH="$DSTUB:$PATH" bash "$BUILD" ) >/dev/null 2>&1
[ "$(epoch_raw "$JL2")" = "1500000000" ] \
  && ok "PREMISE: FLOOR_SOURCE_DATE_EPOCH short-circuits the clock even under the stub - so the case below must run with it UNSET" \
  || no "the FLOOR_SOURCE_DATE_EPOCH seam did not short-circuit the stub ($(epoch_raw "$JL2"))"

rm -f "$JL2"
( cd "$RL2" && unset FLOOR_SOURCE_DATE_EPOCH; PATH="$DSTUB:$PATH" bash "$BUILD" ) >/dev/null 2>&1; rcL2=$?
[ "$rcL2" -eq 0 ] && [ -f "$JL2" ] \
  && ok "broken clock: exits 0 and still writes the artefact" \
  || no "broken clock: rc=$rcL2, artefact $( [ -f "$JL2" ] && echo present || echo absent )"
epoch_present "$JL2" \
  && ok "broken clock: the generated_at_epoch key is still PRESENT (a missing key is a producer bug)" \
  || no "broken clock: the generated_at_epoch key is absent"
epoch_is_null "$JL2" \
  && ok "broken clock: generated_at_epoch is exactly null" \
  || no "broken clock: generated_at_epoch is $(epoch_desc "$JL2"), expected a PRESENT null"
jq -e '.generated_at_epoch == 0 or .generated_at_epoch == "" or (.generated_at_epoch | type) == "string"' "$JL2" >/dev/null 2>&1 \
  && no "broken clock: a defaulted 0 / empty / raw-string stamp leaked through ($(epoch_raw "$JL2"))" \
  || ok "broken clock: not 0, not empty, not the raw stub string"
# A failed clock degrades ONE field; it does not degrade the projection.
validate_floor "$JL2" >/dev/null 2>&1 \
  && ok "broken clock: the artefact still conforms to the schema parsed from RESULT_SCHEMAS.md" \
  || no "broken clock: the artefact failed schema validation: $(validate_floor "$JL2" 2>&1 | head -3)"

echo "-- mutation controls: presence and null-ness must each be able to turn RED --"
CE_OLD='   generated_at_epoch: (if $ge == "" then null else ($ge | tonumber) end),'
run_clock_mutant() { rm -f "$JL2"
  ( cd "$RL2" && unset FLOOR_SOURCE_DATE_EPOCH; PATH="$DSTUB:$PATH" bash "$1" ) >/dev/null 2>&1; }

# MUTANT 1 - the plausible default. `0` is a real integer, the key is still present and the
# document still validates, so ONLY the value assertion can see it. That is the fabricated zero
# this projector exists to refuse, one character away from correct.
CE_ZERO='   generated_at_epoch: (if $ge == "" then 0 else ($ge | tonumber) end),'
CZMUT="$ROOT/clock-zero-mutant.sh"
CE_OLD="$CE_OLD" CE_ZERO="$CE_ZERO" awk '
  BEGIN{o=ENVIRON["CE_OLD"]; n=ENVIRON["CE_ZERO"]}
  $0==o && !d {print n; d=1; next} {print}' "$BUILD" > "$CZMUT"
if [ -s "$CZMUT" ] && ! cmp -s "$CZMUT" "$BUILD" && bash -n "$CZMUT" 2>/dev/null \
   && grep -qF "$CE_ZERO" "$CZMUT"; then
  ok "the defaulted-zero clock mutant is buildable and bash -n clean"
  run_clock_mutant "$CZMUT"
  if [ -f "$JL2" ]; then
    ok "the defaulted-zero mutant still reaches its own success line (artefact written)"
    epoch_present "$JL2" && [ "$(epoch_raw "$JL2")" = "0" ] \
      && ok "MUTATION CONTROL: it emits a present-but-ZERO stamp, turning the null assertion RED - the presence assertion alone would NOT have caught it" \
      || no "the defaulted-zero mutant emitted $(epoch_desc "$JL2") - control inconclusive"
  else
    no "the defaulted-zero mutant wrote no artefact - control inconclusive"
  fi
else
  no "could not build a valid defaulted-zero clock mutant - this control is inconclusive"
fi

# MUTANT 2 - the key dropped entirely. The null assertion alone CANNOT see this, because
# `.generated_at_epoch` on a key-less document also reads null; only the has() half rejects it.
COMUT="$ROOT/clock-omitted-mutant.sh"
CE_OLD="$CE_OLD" awk 'BEGIN{o=ENVIRON["CE_OLD"]} $0==o && !d {d=1; next} {print}' "$BUILD" > "$COMUT"
if [ -s "$COMUT" ] && ! cmp -s "$COMUT" "$BUILD" && bash -n "$COMUT" 2>/dev/null \
   && ! grep -qF "$CE_OLD" "$COMUT"; then
  ok "the omitted-key clock mutant is buildable and bash -n clean"
  run_clock_mutant "$COMUT"
  if [ -f "$JL2" ]; then
    ok "the omitted-key mutant still reaches its own success line (artefact written)"
    epoch_present "$JL2" \
      && no "the omitted-key mutant still carries the key - control inconclusive" \
      || ok "MUTATION CONTROL: it drops the key entirely, turning the PRESENCE assertion RED"
    [ "$(epoch_raw "$JL2")" = "null" ] \
      && ok "...and a key-less document reads null to a bare value check - precisely why presence is asserted separately" \
      || no "a key-less document did not read null to a bare value check ($(epoch_raw "$JL2")) - re-check the pairing rationale"
  else
    no "the omitted-key mutant wrote no artefact - control inconclusive"
  fi
else
  no "could not build a valid omitted-key clock mutant - this control is inconclusive"
fi

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
