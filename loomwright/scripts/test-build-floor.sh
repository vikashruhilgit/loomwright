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
#   (n) agents roster - the three committed fixture agent files parsed from YAML frontmatter,
#       with every absent frontmatter field OMITTED from its row rather than defaulted, and the
#       whole-token `read_only` derivation (a row whose list holds `NotebookEdit` but not `Edit`
#       must NOT read as read-only). Plus the third not-counted arm - the UNRESOLVED one that
#       fires when neither `$0` nor FLOOR_AGENTS_DIR names a directory, reached with a spoofed
#       argv[0] because every real directory resolves, with a control proving the arm needs
#       BOTH conditions
#   (o) newest-session agent rows - the session owning the newest `ts` picks `current`; per
#       agent_id events / first_ts / last_ts / agent_type / branch, with a second session's rows
#       never contributing, plus the no-`ts`-anywhere case (current OMITTED, never guessed from
#       file order)
#   (p) state subtask rows - {id, title, status} in table order, `status` omitted on a table
#       with no Status column, with the existing row count unchanged
#   (q) add_surface's invalid-detail guard - an unparseable `detail` still emits the surface
#       (without `detail`) and names the key and the reason in notes[]; two controls, one
#       reverting the guard (the surface vanishes) and one passing VALID detail through
#   (r) rules detail - deterministic rows; `applies_to` AND `check` each a genuine TRI-STATE
#       (key absent / present-and-null / value), with a mutation control showing the truthy-only
#       reading collapses two of the three; `count` still means category FILES
#   (s) supersedes - a TRANSITIVE, in-order chain, a dangling pointer REPORTED as dangling, and an
#       A->B->C->A cycle reported whole; the deliberate divergence from read-rules.sh's
#       hide/single-hop/ignore-dangling routing semantics, with its BOUNDED walk inherited
#   (t) unparseable rules file - named with its reason, valid rules still reported, and the
#       all / partial / none read distinction, with two mutation controls
#   (u) churn detail - the flow-stage basis PINNED to `.categories[].flow_stage` against a fixture
#       whose `.flow_stages` counter disagrees, malformed lines counted and named, nothing scored
#   (v) correlation - evidence travels with it, it is labelled an observation, and an uncomputable
#       one is OMITTED rather than emitted as zero
#   (w) the empty fixture still yields `absent` for both new-detail surfaces, and no env seam was
#       added for either (both stay cwd-relative)
#   (z) the output path is CWD-RELATIVE, proven by running a COPY of the projector from a
#       foreign install directory with the cwd elsewhere and hashing that install tree exactly -
#       the always-on, CI-running form of (m)'s claim, with a mutation control that resolves the
#       output from `$0` and must turn the same assertion red
#   (m) real `.supervisor/` corroboration (local only) or an explicit SKIPPED line. Placed out of
#       alphabetical order - after (w), before (x)/(y) - because it is the only case that may
#       SKIP and because its `(m)` label is what the brief commissioning (n)-(q) refers to;
#       renaming it would break that reference to buy nothing. Its containment assertion
#       ATTRIBUTES rather than suppresses: a live Floor that regenerates THIS project rewrites
#       `.supervisor/floor/floor.json` inside it every couple of seconds, so a change to that one
#       artefact is excused only on evidence of such a server, every other path in that directory
#       is DIRTY unconditionally, and with no such server these same paths still redden
#   (m1)-(m8) the controls for that attribution, run UNCONDITIONALLY (the assertion they control
#       is the one that skips): a foreign path stays DIRTY under a live Floor, the serve's own
#       artefact stays DIRTY without one, a mixed delta names only the foreign path, and the
#       detector is proven to reject a no-index / other-project / `--no-regen` server while
#       still firing for one that lists this repo
#
# Exit 0 = all pass, 1 = any failure. Registered automatically by ci.yml's test-*.sh glob.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build-floor.sh"
SCHEMA_MD="$(cd "$HERE/../docs" && pwd)/RESULT_SCHEMAS.md"
SESS_FIXTURE="$HERE/fixtures/floor-sessions.jsonl"
SESS_CUR_FIXTURE="$HERE/fixtures/floor-sessions-current.jsonl"
AGENTS_FIXTURE_DIR="$HERE/fixtures/floor-agents"
RULES_FIXTURE_DIR="$HERE/fixtures/floor-rules"
RULES_BROKEN_FIXTURE="$HERE/fixtures/floor-rules-broken/broken.json"
PM_FIXTURE="$HERE/fixtures/floor-postmortem.jsonl"
PM_BAD_FIXTURE="$HERE/fixtures/floor-postmortem-malformed.jsonl"

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

# FLOOR_AGENTS_DIR on EVERY run, seeded fixture or not: an unset override sends the script to
# its own install directory, so the empty fixture would report the real agent count instead of
# `absent`. The eleven direct `bash "$BUILD"` call sites below (the c2/f2/f3/g/i/k/l/l2 groups)
# deliberately do NOT export it - they resolve the real directory and assert nothing about the
# `agents` surface.
run_build() { ( cd "$1" && FLOOR_AGENTS_DIR="$1/agents" bash "$BUILD" >/dev/null 2>&1 ); }

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
EXP_RULES=2                # category FILES, never rules - the count key keeps that meaning
EXP_RULES_DETAIL=16        # rule OBJECTS across those two files; a separate, differently-named field
EXP_PM_CATEGORIES=4        # category objects across the 4 ledger lines (2 + 1 + 0 + 1)
EXP_PM_DISAGREE=1          # ledger lines whose .flow_stages counter disagrees with .categories[].flow_stage
EXP_AGENTS=3              # the three committed fixture agent files, copied into <fixture>/agents/

# The roster expectations are LITERALS, and the premise block in (n) re-greps each one out of
# the committed fixture file it came from. Deriving them here with a second frontmatter parser
# would only prove that two parsers written on the same afternoon agree; a literal plus a drift
# check on its source is what (c) already does for fixtures/floor-sessions.jsonl.
EXP_AG_NAMES="alpha beta gamma"
EXP_AG_ALPHA_COLOR='#1E90FF'   # quoted in the fixture; the surrounding quotes must be stripped
EXP_AG_ALPHA_MODEL="sonnet"
EXP_AG_ALPHA_TURNS=12
EXP_AG_BETA_MODEL="opus"
EXP_AG_BETA_TURNS=40
EXP_AG_GAMMA_COLOR="forestgreen"   # unquoted in the fixture - the other half of the quote path
EXP_AG_GAMMA_MODEL="haiku"

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

  # The ledger is a COMMITTED fixture rather than a generated one, because the churn detail
  # asserts on the SHAPE of a record (categories[].class / .flow_stage / .evidence, and the
  # .flow_stages counter that disagrees with them) and a loop printing `{"number":N}` carries
  # none of it. Its line count is still EXP_POSTMORTEM, and the drift check below re-derives
  # that from the file so the literal cannot silently outlive the fixture.
  cp "$PM_FIXTURE" "$r/.supervisor/postmortem/results.jsonl"

  for i in $(seq 1 $EXP_DRAIN); do printf '{"rounds":%s,"max_rounds":5}\n' "$i" \
      > "$r/.supervisor/drain-rounds/round-$i.json"; done
  for i in $(seq 1 $EXP_WORKER_SUMMARIES); do echo "## WORKER_SUMMARY $i" \
      > "$r/.supervisor/worker-summaries/w$i.md"; done
  # Same reasoning for the rules store: `[{"id":"rN"}]` proves a file count and nothing about
  # the tri-state fields, the supersedes graph or the row shape. The fixture is TWO category
  # files (so `rules` still counts 2) holding TEN rules (a separate, differently-named field).
  cp "$RULES_FIXTURE_DIR"/*.json "$r/.agent/rules/"

  # The agent roster's real-run source is the PLUGIN directory, not a .supervisor/ one, so the
  # fixture needs its own copy and run_build must point FLOOR_AGENTS_DIR at it. Without that
  # export the script resolves its own install directory and would count the REAL agents on
  # every fixture - including the EMPTY one, which would turn the anti-vacuity control green
  # for a reason that has nothing to do with the tree under test.
  mkdir -p "$r/agents"
  cp "$AGENTS_FIXTURE_DIR"/*.md "$r/agents/" 2>/dev/null
}

jget() { jq -r "$2" "$1" 2>/dev/null; }
scount()  { jq -r --arg k "$2" '.surfaces[$k].count  // "ABSENT"' "$1" 2>/dev/null; }
sstatus() { jq -r --arg k "$2" '.surfaces[$k].status // "ABSENT"' "$1" 2>/dev/null; }
sreason() { jq -r --arg k "$2" '.surfaces[$k].reason // ""'       "$1" 2>/dev/null; }

# The single count comparator. Used for the real assertions AND, unchanged, for the
# negative control - if it cannot fail it is not an assertion.
count_is() { [ "$(scount "$1" "$2")" = "$3" ]; }

ALL_KEYS="state jobs_pending jobs_in_progress jobs_done jobs_failed automate_runs logs \
sessions insights_runs postmortem drain_rounds worker_summaries rules agents"

command -v jq >/dev/null 2>&1 || { echo "test-build-floor: jq required to run these tests" >&2; exit 1; }
[ -f "$BUILD" ]        || { echo "test-build-floor: $BUILD missing" >&2; exit 1; }
[ -f "$SCHEMA_MD" ]    || { echo "test-build-floor: $SCHEMA_MD missing" >&2; exit 1; }
[ -f "$SESS_FIXTURE" ] || { echo "test-build-floor: committed fixture $SESS_FIXTURE missing" >&2; exit 1; }
[ -f "$SESS_CUR_FIXTURE" ] || { echo "test-build-floor: committed fixture $SESS_CUR_FIXTURE missing" >&2; exit 1; }
[ -d "$AGENTS_FIXTURE_DIR" ] || { echo "test-build-floor: committed fixture dir $AGENTS_FIXTURE_DIR missing" >&2; exit 1; }
[ -d "$RULES_FIXTURE_DIR" ] || { echo "test-build-floor: committed fixture dir $RULES_FIXTURE_DIR missing" >&2; exit 1; }
[ -f "$RULES_BROKEN_FIXTURE" ] || { echo "test-build-floor: committed fixture $RULES_BROKEN_FIXTURE missing" >&2; exit 1; }
[ -f "$PM_FIXTURE" ]     || { echo "test-build-floor: committed fixture $PM_FIXTURE missing" >&2; exit 1; }
[ -f "$PM_BAD_FIXTURE" ] || { echo "test-build-floor: committed fixture $PM_BAD_FIXTURE missing" >&2; exit 1; }

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
check_pair agents             "$EXP_AGENTS"

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
  && ok "all 14 sections counted and non-zero" \
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
[ -n "$zoe" ] && [ "$n_zoe" -eq 14 ] \
  && ok "ANTI-VACUITY: an EMPTY fixture fails the zero/absent guard on all 14 sections" \
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
[ -z "$missing_basis" ] && ok "all 14 surfaces carry a non-empty basis" \
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
# EXACTLY ONE site may be mutated: the identical normalisation appears in the postmortem
# classifier and in the churn-detail / correlation readers, and mutating more than the SESSIONS
# one (the first) would change several things at once. The survivor count is DERIVED from the
# unmutated script rather than written as a literal - a hard-coded `1` silently becomes a
# vacuous premise the moment another reader legitimately uses the same normalisation, which is
# exactly what happened when the churn detail was added.
GS_BEFORE="$(grep -cF 'gsub("\\s"; "")' "$BUILD")"
GS_AFTER="$(grep -cF 'gsub("\\s"; "")' "$GSMUT")"
if [ -s "$GSMUT" ] && ! cmp -s "$GSMUT" "$BUILD" && bash -n "$GSMUT" 2>/dev/null \
   && [ "$GS_BEFORE" -ge 2 ] && [ "$GS_AFTER" -eq "$((GS_BEFORE - 1))" ]; then
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

# The surfaces KEY LIST in the schema block is prose - the validator above parses key NAMES
# out of the block but never checks that the list of surface keys matches what the producer
# emits, so a new surface can ship undocumented behind a fully green (h). Read it here.
# Captured ONCE into a here-string source. `schema_block | grep -q ...` would be a pipeline
# whose producer is killed by SIGPIPE the moment grep matches and exits, and under `pipefail`
# that makes the pipeline status 141 - a MATCH read as a miss. Here-strings are one command.
SCHEMA_BLOCK_TXT="$(schema_block)"
skeys_line="$(grep -F 'surfaces: object' <<< "$SCHEMA_BLOCK_TXT" | head -1)"
undocumented=""
for k in $ALL_KEYS; do
  grep -qF "$k" <<< "$skeys_line" || undocumented="$undocumented $k"
done
[ -n "$skeys_line" ] && [ -z "$undocumented" ] \
  && ok "every emitted surface key is named in the schema block's surfaces list" \
  || no "surface keys missing from the schema block's list:$undocumented"
# ...and the reverse direction, so a key removed from the producer cannot linger in the doc.
grep -qF "no_such_surface" <<< "$skeys_line" \
  && no "the surfaces-list check matched a key that does not exist - it is not discriminating" \
  || ok "CONTROL: a key that is not in the list is NOT matched (the check can fail)"

# The three documented `detail` sub-keys, each marked optional. They are six-space lines, so
# they are deliberately invisible to the two- and four-space parsers above - a consumer reads
# them, and nothing else would notice if they were deleted.
# This list is HARD-CODED, and that is exactly why it has to grow with the producer: a sub-key
# absent from it falls outside the loop and can ship undocumented behind a fully green (h). The
# mutation control below is what keeps the list itself honest.
DETAIL_SUBKEYS="roster current subtasks \
rules rules_parsed files_parsed files_unparseable files_not_an_array read_completeness supersedes correlations \
class_distribution class_basis flow_stage_distribution flow_stage_basis categories_total \
lines_without_categories flow_stage_counter_disagreements entries lines_malformed malformed_lines"
undocumented_detail() {  # <block-text> -> the sub-keys it fails to document, space-separated
  local blk="$1" k out=""
  for k in $DETAIL_SUBKEYS; do
    grep -qE "^      $k:.*optional" <<< "$blk" || out="$out $k"
  done
  printf '%s' "$out"
}
missing_detail="$(undocumented_detail "$SCHEMA_BLOCK_TXT")"
n_subkeys="$(printf '%s\n' $DETAIL_SUBKEYS | awk 'NF{n++} END{print n+0}')"
[ -z "$missing_detail" ] \
  && ok "the schema block documents all $n_subkeys detail sub-keys as optional" \
  || no "detail sub-keys missing or not marked optional:$missing_detail"
# MUTATION CONTROL: remove ONE sub-key line from the block and the same check must go red, naming
# it. Without this the loop could be pointed at a list of names nothing emits and stay green.
MUT_BLOCK="$(grep -v '^      flow_stage_basis:' <<< "$SCHEMA_BLOCK_TXT")"
mut_missing="$(undocumented_detail "$MUT_BLOCK")"
[ "$mut_missing" = " flow_stage_basis" ] \
  && ok "MUTATION CONTROL: deleting the flow_stage_basis line from the block turns this check RED, naming it" \
  || no "the sub-key check did not react to a deleted line (got '$mut_missing') - it is vacuous"

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
echo "== (n) agents roster: frontmatter parsed, absent fields OMITTED, whole-token read_only =="
# PREMISES, measured against the COMMITTED fixture files rather than assumed. Every literal in
# the EXP_AG_* block near the top is re-derived here from the file it came from, so a fixture
# edit turns THIS block red - naming the drift - instead of silently re-keying the assertions
# below. Same convention as (c)'s 3-ids / 1-noid / 8-lines check on floor-sessions.jsonl.
AF="$AGENTS_FIXTURE_DIR"
n_af="$(ls -1 "$AF"/*.md 2>/dev/null | awk 'NF{n++} END{print n+0}')"
[ "$n_af" -eq "$EXP_AGENTS" ] \
  && ok "PREMISE: the committed fixture holds $EXP_AGENTS agent files" \
  || no "the committed fixture holds $n_af agent files, expected $EXP_AGENTS"

fm_count() { grep -c "^$2:" "$1" 2>/dev/null; }
ag_premise=""
grep -qxF "color: \"$EXP_AG_ALPHA_COLOR\"" "$AF/alpha.md"       || ag_premise="$ag_premise alpha.color"
grep -qxF "model: $EXP_AG_ALPHA_MODEL" "$AF/alpha.md"           || ag_premise="$ag_premise alpha.model"
grep -qxF "maxTurns: $EXP_AG_ALPHA_TURNS" "$AF/alpha.md"        || ag_premise="$ag_premise alpha.maxTurns"
grep -qxF "model: $EXP_AG_BETA_MODEL" "$AF/beta.md"             || ag_premise="$ag_premise beta.model"
grep -qxF "maxTurns: $EXP_AG_BETA_TURNS" "$AF/beta.md"          || ag_premise="$ag_premise beta.maxTurns"
grep -qxF "color: $EXP_AG_GAMMA_COLOR" "$AF/gamma.md"           || ag_premise="$ag_premise gamma.color"
grep -qxF "model: $EXP_AG_GAMMA_MODEL" "$AF/gamma.md"           || ag_premise="$ag_premise gamma.model"
[ "$(fm_count "$AF/beta.md" color)"            = "0" ]          || ag_premise="$ag_premise beta.has-color"
[ "$(fm_count "$AF/gamma.md" maxTurns)"        = "0" ]          || ag_premise="$ag_premise gamma.has-maxTurns"
[ "$(fm_count "$AF/gamma.md" disallowedTools)" = "0" ]          || ag_premise="$ag_premise gamma.has-disallowedTools"
[ -z "$ag_premise" ] \
  && ok "PREMISE: every EXP_AG_* literal is still what the committed fixture files say" \
  || no "the committed agent fixtures drifted from the expectations:$ag_premise"

# The whole-token premise, stated as a measurement rather than as a claim about the fixture:
# alpha's list must contain `Edit` as a standalone token and beta's must NOT, even though
# beta's list DOES contain the string `Edit` inside `NotebookEdit`.
a_dis="$(sed -n 's/^disallowedTools:[[:space:]]*//p' "$AF/alpha.md" | head -1)"
b_dis="$(sed -n 's/^disallowedTools:[[:space:]]*//p' "$AF/beta.md"  | head -1)"
# Here-strings, not `producer | grep -q`: under `pipefail` a producer killed by SIGPIPE when
# grep exits early makes the PIPELINE status 141 even on a match. A here-string is one command.
tok_has() { grep -qE "(^|[^A-Za-z0-9_])$2([^A-Za-z0-9_]|\$)" <<< "$1"; }
if tok_has "$a_dis" Edit && tok_has "$a_dis" Write \
   && ! tok_has "$b_dis" Edit && grep -qF 'Edit' <<< "$b_dis"; then
  ok "PREMISE: alpha lists Edit+Write as whole tokens; beta contains the SUBSTRING Edit (NotebookEdit) but not the token"
else
  no "the whole-token premise does not hold (alpha: '$a_dis' / beta: '$b_dis') - the read_only assertions below would prove nothing"
fi

[ "$(sstatus "$JA" agents)" = "counted" ] && count_is "$JA" agents "$EXP_AGENTS" \
  && ok "agents == counted/$EXP_AGENTS from the seeded fixture directory" \
  || no "agents == $(sstatus "$JA" agents)/$(scount "$JA" agents), expected counted/$EXP_AGENTS"

# Row readers. `araw` prints the RAW json value, because `read_only: false` and an ABSENT
# read_only are different findings and `// "ABSENT"` collapses them into one.
araw()  { jq -c  --arg n "$1" --arg k "$2" '[.surfaces.agents.detail.roster[] | select(.name == $n) | .[$k]] | .[0]' "$JA" 2>/dev/null; }
astr()  { jq -r  --arg n "$1" --arg k "$2" '[.surfaces.agents.detail.roster[] | select(.name == $n) | .[$k]] | .[0] // "ABSENT"' "$JA" 2>/dev/null; }
ahas()  { jq -e  --arg n "$1" --arg k "$2" '[.surfaces.agents.detail.roster[] | select(.name == $n) | has($k)] | .[0] // false' "$JA" >/dev/null 2>&1; }

ros_names="$(jq -r '.surfaces.agents.detail.roster[].name' "$JA" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
[ "$ros_names" = "$EXP_AG_NAMES" ] \
  && ok "roster is sorted by name and carries exactly: $EXP_AG_NAMES (the loomwright: prefix stripped)" \
  || no "roster names are '$ros_names', expected '$EXP_AG_NAMES'"

[ "$(astr alpha color)" = "$EXP_AG_ALPHA_COLOR" ] \
  && ok "alpha.color == $EXP_AG_ALPHA_COLOR (the frontmatter's surrounding quotes are stripped)" \
  || no "alpha.color == $(astr alpha color), expected $EXP_AG_ALPHA_COLOR"
[ "$(astr gamma color)" = "$EXP_AG_GAMMA_COLOR" ] \
  && ok "gamma.color == $EXP_AG_GAMMA_COLOR (an unquoted value survives the same path)" \
  || no "gamma.color == $(astr gamma color), expected $EXP_AG_GAMMA_COLOR"
[ "$(astr alpha model)" = "$EXP_AG_ALPHA_MODEL" ] && [ "$(astr beta model)" = "$EXP_AG_BETA_MODEL" ] \
  && [ "$(astr gamma model)" = "$EXP_AG_GAMMA_MODEL" ] \
  && ok "every model is the frontmatter's own value ($EXP_AG_ALPHA_MODEL / $EXP_AG_BETA_MODEL / $EXP_AG_GAMMA_MODEL)" \
  || no "models read $(astr alpha model)/$(astr beta model)/$(astr gamma model)"
[ "$(araw alpha max_turns)" = "$EXP_AG_ALPHA_TURNS" ] && [ "$(araw beta max_turns)" = "$EXP_AG_BETA_TURNS" ] \
  && ok "max_turns is emitted as a NUMBER from maxTurns ($EXP_AG_ALPHA_TURNS / $EXP_AG_BETA_TURNS)" \
  || no "max_turns reads $(araw alpha max_turns)/$(araw beta max_turns), expected $EXP_AG_ALPHA_TURNS/$EXP_AG_BETA_TURNS"

# THE OMISSION RULE, one assertion per absent frontmatter field.
ahas beta color \
  && no "beta carries a color key although its frontmatter has no color: line - a default leaked in" \
  || ok "beta has NO color key at all (absent frontmatter field => omitted, never defaulted)"
ahas gamma max_turns \
  && no "gamma carries a max_turns key although its frontmatter has no maxTurns: line" \
  || ok "gamma has NO max_turns key (absent maxTurns => omitted)"
ahas gamma read_only \
  && no "gamma carries read_only == $(araw gamma read_only) although it lists no disallowedTools - that is a guess, not a reading" \
  || ok "gamma has NO read_only key (no disallowedTools evidence => omitted, not false)"

# THE WHOLE-TOKEN DERIVATION. beta is the discriminating row: a substring test for `Edit`
# matches its `NotebookEdit` and would report it read-only.
[ "$(araw alpha read_only)" = "true" ] \
  && ok "alpha.read_only == true (its list covers BOTH Write and Edit)" \
  || no "alpha.read_only == $(araw alpha read_only), expected true"
[ "$(araw beta read_only)" = "false" ] \
  && ok "beta.read_only == false although its list contains the SUBSTRING Edit inside NotebookEdit" \
  || no "beta.read_only == $(araw beta read_only), expected false - the whole-token check is not whole-token"

jq -e '[.surfaces.agents.detail.roster[] | to_entries[] | select(.value == "")] | length == 0' "$JA" >/dev/null 2>&1 \
  && ok "no roster row carries an empty-string value (an omitted field is a missing KEY)" \
  || no "a roster row carries an empty string: $(jq -c '[.surfaces.agents.detail.roster[] | to_entries[] | select(.value == "")]' "$JA" 2>/dev/null)"

# The absent-directory arm, on the EMPTY fixture that (a) already built.
[ "$(sstatus "$JEMPTY" agents)" = "absent" ] && [ "$(scount "$JEMPTY" agents)" = "ABSENT" ] \
  && ok "agents on a tree with no agents dir: absent with NO count" \
  || no "agents on the empty fixture: $(sstatus "$JEMPTY" agents)/$(scount "$JEMPTY" agents)"
grep -qF "agents" <<< "$(sreason "$JEMPTY" agents)" \
  && ok "and the reason names the directory it looked for" \
  || no "the reason does not name the directory: '$(sreason "$JEMPTY" agents)'"
jq -e '.surfaces.agents | has("detail") | not' "$JEMPTY" >/dev/null 2>&1 \
  && ok "an absent agents dir yields no roster at all (never an empty roster asserting 'no agents')" \
  || no "the absent agents surface still carried a detail payload"

# The two `! -r` branches this surface adds, covered ON THE WAY IN. The suite that shipped
# before this one had never made any input unreadable anywhere, so all three pre-existing
# readability guards were dead code that had never once executed - which is precisely how two
# proven-looking zeros shipped. A new guard gets its coverage now, not after the next incident.
if ! unreadable_premise; then
  skipn "chmod 000 does not deny a read here - the unreadable-agents cases cannot be exercised and are NOT counted as passes"
else
  RN1="$(new_repo)"; seed_tree "$RN1"
  chmod 000 "$RN1/agents" 2>/dev/null
  if [ -r "$RN1/agents" ]; then
    no "unreadable agents dir: it is still readable - this case is vacuous"
  else
    run_build "$RN1"
    JN1="$RN1/.supervisor/floor/floor.json"
    stN1="$(sstatus "$JN1" agents)"; cnN1="$(scount "$JN1" agents)"; rsN1="$(sreason "$JN1" agents)"
    chmod -R u+rwX "$RN1/agents" >/dev/null 2>&1
    [ "$stN1" = "unverified" ] && [ "$cnN1" = "ABSENT" ] \
      && ok "unreadable agents dir: unverified with NO count - under nullglob it expands exactly like an EMPTY one, so a counted 0 here would be a zero nobody measured" \
      || no "unreadable agents dir: status=$stN1 count=$cnN1, expected unverified/ABSENT"
    grep -qF "agents" <<< "$rsN1" \
      && ok "...and the reason names the directory it could not read" \
      || no "the reason does not name the directory: '$rsN1'"
  fi

  RN2="$(new_repo)"; seed_tree "$RN2"
  chmod 000 "$RN2/agents/beta.md" 2>/dev/null
  if [ -r "$RN2/agents/beta.md" ]; then
    no "unreadable agent file: it is still readable - this case is vacuous"
  else
    run_build "$RN2"
    JN2="$RN2/.supervisor/floor/floor.json"
    stN2="$(sstatus "$JN2" agents)"; cnN2="$(scount "$JN2" agents)"; rsN2="$(sreason "$JN2" agents)"
    hasrN2="$(jq -r '.surfaces.agents | if has("detail") then "y" else "n" end' "$JN2" 2>/dev/null)"
    chmod -R u+rwX "$RN2/agents" >/dev/null 2>&1
    [ "$stN2" = "unverified" ] && [ "$cnN2" = "ABSENT" ] \
      && ok "an unreadable MEMBER makes the surface unverified with no count - awk on it prints nothing, so the roster would silently lose a row while the glob-derived count still claimed it" \
      || no "unreadable agent file: status=$stN2 count=$cnN2, expected unverified/ABSENT"
    grep -qF "beta.md" <<< "$rsN2" \
      && ok "...and the reason names the offending file" \
      || no "the reason does not name the file: '$rsN2'"
    [ "$hasrN2" = "n" ] \
      && ok "...and NO roster is published over files it could not fully read" \
      || no "a roster was published although one member was unreadable"
  fi
fi


# --- THE UNRESOLVED ARM: neither $0 nor FLOOR_AGENTS_DIR names a directory ----------------
# The `agents` surface has THREE not-counted arms and only two of them had a case. The third
# fires when the plugin directory cannot be resolved from `$0` AND the override is unset -
# and every other call site in this file exports FLOOR_AGENTS_DIR, so it had never once
# executed. It is not reachable by staging the script somewhere odd: ANY real directory
# resolves, and `cd "$SELF_DIR/.."` of one succeeds, which is exactly why the branch survived
# uncovered. What it takes is a `$0` whose dirname does not exist, and `bash -c '. "$1"' <$0>`
# supplies precisely that and nothing else - the script is the real one, byte for byte, and
# the ONLY thing changed is the argv[0] it resolves its install directory from.
RUN0="$(new_repo)"; seed_tree "$RUN0"
( cd "$RUN0" && env -u FLOOR_AGENTS_DIR bash -c '. "$1"' \
    "/no-such-directory-$$/build-floor.sh" "$BUILD" ) >/dev/null 2>&1
rc0=$?
JU="$RUN0/.supervisor/floor/floor.json"
if [ ! -f "$JU" ]; then
  no "unresolved agents dir: the projector still produced its artefact" "no floor.json at $JU (rc=$rc0)"
else
  stU="$(sstatus "$JU" agents)"; cnU="$(scount "$JU" agents)"; rsU="$(sreason "$JU" agents)"
  srcU="$(jq -r '.surfaces.agents.source // "ABSENT"' "$JU" 2>/dev/null)"
  hasdU="$(jq -r '.surfaces.agents | if has("detail") then "y" else "n" end' "$JU" 2>/dev/null)"
  [ "$rc0" -eq 0 ] \
    && ok "unresolved agents dir: exit 0 - a projector that cannot find its own install dir still must not break its caller" \
    || no "unresolved agents dir: exit $rc0, expected 0"
  [ "$stU" = "absent" ] && [ "$cnU" = "ABSENT" ] \
    && ok "unresolved agents dir: absent with NO count - a roster nobody could look for is not a roster of size 0" \
    || no "unresolved agents dir: status=$stU count=$cnU, expected absent/ABSENT"
  [ "$srcU" = "unresolved" ] \
    && ok "...and the source reads 'unresolved' rather than naming a path that was never resolved" \
    || no "unresolved agents dir: source=$srcU, expected 'unresolved'"
  case "$rsU" in
    *"could not be resolved"*"FLOOR_AGENTS_DIR"*)
      ok "...and the reason names BOTH halves of the condition (\$0 and the unset override)" ;;
    *) no "the reason does not name both halves of the condition: '$rsU'" ;;
  esac
  [ "$hasdU" = "n" ] \
    && ok "...and no roster is published for a directory that was never located" \
    || no "the unresolved agents surface still carried a detail payload"
  n_noteU="$(jq -r '[.notes[] | select(startswith("agents "))] | length' "$JU" 2>/dev/null)"
  [ "$n_noteU" -ge 1 ] 2>/dev/null \
    && ok "...and notes[] states the omission a second time, as the schema requires of a not-counted surface" \
    || no "no agents note was emitted for the unresolved arm (found $n_noteU)"
fi
# CONTROL: the branch is the AND of two conditions. The SAME spoofed argv[0], with the
# override SET, must NOT take it - otherwise the case above would pass for an engine that
# ignores FLOOR_AGENTS_DIR entirely.
RUN0C="$(new_repo)"; seed_tree "$RUN0C"
( cd "$RUN0C" && FLOOR_AGENTS_DIR="$RUN0C/agents" bash -c '. "$1"' \
    "/no-such-directory-$$/build-floor.sh" "$BUILD" ) >/dev/null 2>&1
JUC="$RUN0C/.supervisor/floor/floor.json"
stUC="$(sstatus "$JUC" agents)"; cnUC="$(scount "$JUC" agents)"
[ "$stUC" = "counted" ] && [ "$cnUC" = "$EXP_AGENTS" ] \
  && ok "CONTROL: the same unresolvable \$0 with FLOOR_AGENTS_DIR SET counts $cnUC agents - the unresolved arm needs BOTH conditions" \
  || no "CONTROL: unresolvable \$0 + FLOOR_AGENTS_DIR set: status=$stUC count=$cnUC, expected counted/$EXP_AGENTS"
# ============================================================================
echo "== (o) newest-session agent rows: current is picked by the newest ts, never by file order =="
# Every expectation below is recomputed FROM THE FIXTURE with jq, independently of the
# projector's own aggregation - never read back out of floor.json.
cf_lines="$(awk 'NF{n++} END{print n+0}' "$SESS_CUR_FIXTURE")"
cf_ids="$(jq -r 'select(has("cc_session_id")) | .cc_session_id' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort -u | awk 'NF{n++} END{print n+0}')"
cf_nots="$(jq -r 'select(has("ts") | not) | "x"' "$SESS_CUR_FIXTURE" 2>/dev/null | awk 'NF{n++} END{print n+0}')"
cf_new_ts="$(jq -r 'select(has("ts")) | .ts' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort | tail -1)"
cf_new_sid="$(jq -r 'select(has("ts")) | [.ts, .cc_session_id] | @tsv' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort | tail -1 | awk -F'\t' '{print $2}')"
cf_agents="$(jq -r --arg s "$cf_new_sid" 'select(.cc_session_id == $s and has("agent_id")) | .agent_id' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
cf_n_agents="$(printf '%s' "$cf_agents" | tr ' ' '\n' | awk 'NF{n++} END{print n+0}')"
cf_typed="$(jq -r --arg s "$cf_new_sid" 'select(.cc_session_id == $s and has("agent_type")) | .agent_id' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
cf_type_val="$(jq -r --arg s "$cf_new_sid" 'select(.cc_session_id == $s and has("agent_type")) | .agent_type' "$SESS_CUR_FIXTURE" 2>/dev/null | head -1)"
cf_branch_val="$(jq -r --arg s "$cf_new_sid" 'select(.cc_session_id == $s and has("branch")) | .branch' "$SESS_CUR_FIXTURE" 2>/dev/null | head -1)"
cf_scoped="$(jq -r --arg s "$cf_new_sid" 'select(.cc_session_id == $s and has("agent_scope")) | .agent_id' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
cf_main_agent="$(jq -r --arg s "$cf_new_sid" 'select(.cc_session_id == $s and .agent_scope == "main") | .agent_id' "$SESS_CUR_FIXTURE" 2>/dev/null | head -1)"
cf_unscoped="$(jq -r --arg s "$cf_new_sid" 'select(.cc_session_id == $s and has("agent_id")) | .agent_id' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort -u | grep -v -x -F -f <(printf '%s\n' $cf_scoped) | tr '\n' ' ' | sed 's/ $//')"
# The main-scoped agent's OWN newest line must NOT carry the scope either - same
# take-from-ANY-line rule as agent_type, and it is only tested if the newest lacks it.
cf_main_newest="$(jq -r --arg s "$cf_new_sid" --arg a "$cf_main_agent" \
  'select(.cc_session_id == $s and .agent_id == $a and has("ts")) | [.ts, (.agent_scope // "-")] | @tsv' \
  "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort | tail -1 | awk -F'\t' '{print $2}')"
cf_other_agents="$(jq -r --arg s "$cf_new_sid" 'select(.cc_session_id != $s and has("agent_id")) | .agent_id' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
# The typed agent's OWN newest line must NOT be the one carrying agent_type: "take the type
# from ANY of the agent's lines" is only tested if the newest line lacks it.
cf_typed_newest="$(jq -r --arg s "$cf_new_sid" --arg a "$cf_typed" \
  'select(.cc_session_id == $s and .agent_id == $a and has("ts")) | [.ts, (.agent_type // "-")] | @tsv' \
  "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort | tail -1 | awk -F'\t' '{print $2}')"

[ "$cf_lines" -eq 9 ] && [ "$cf_ids" -eq 2 ] && [ "$cf_nots" -eq 1 ] && [ "$cf_n_agents" -eq 3 ] \
  && ok "PREMISE: the committed fixture is $cf_lines lines / $cf_ids sessions / $cf_nots ts-less line / $cf_n_agents agents in the newest session" \
  || no "committed fixture drifted: lines=$cf_lines ids=$cf_ids nots=$cf_nots agents=$cf_n_agents (expected 9/2/1/3)"
[ "$(printf '%s' "$cf_typed" | tr ' ' '\n' | awk 'NF{n++} END{print n+0}')" -eq 1 ] && [ "$cf_typed_newest" = "-" ] \
  && ok "PREMISE: exactly one agent in that session is typed, and its type is on an OLDER line than its own newest" \
  || no "the typed-agent premise does not hold (typed='$cf_typed', newest line's type='$cf_typed_newest')"
[ -n "$cf_other_agents" ] \
  && ok "PREMISE: the older session contributes agent ids of its own ($cf_other_agents) that must NOT appear" \
  || no "the older session carries no agent id - the cross-session isolation assertion would be vacuous"
# agent_scope carries THREE states in this one fixture, and all three must be present or
# the assertions below prove less than they read: a typed+subagent row, an UNtyped row
# scoped `main` (the whole point of the field - a lane with no role that is nevertheless
# identified), and a row with no scope at all (the genuinely-unknown case).
[ "$(printf '%s' "$cf_scoped" | tr ' ' '\n' | awk 'NF{n++} END{print n+0}')" -eq 2 ] \
  && [ -n "$cf_main_agent" ] && [ -n "$cf_unscoped" ] && [ "$cf_main_newest" = "-" ] \
  && ok "PREMISE: the fixture carries all three agent_scope states (scoped: $cf_scoped / unscoped: $cf_unscoped), and main is on an OLDER line than that agent's newest" \
  || no "the agent_scope premise does not hold (scoped='$cf_scoped', main='$cf_main_agent', unscoped='$cf_unscoped', newest line's scope='$cf_main_newest')"

# ITS OWN new_repo, deliberately not seed_tree: this fixture would re-key EXP_LOGS,
# EXP_LOG_DIR_ENTRIES, EXP_SESSIONS, EXP_SESS_LINES and the "3 jsonl + 5 plain .log" basis
# assertion at once, and would edit the very file whose drift guard exists to notice it
# changing. The (c2) precedent, for the same reason.
RO="$(new_repo)"; mkdir -p "$RO/.supervisor/logs"
cp "$SESS_CUR_FIXTURE" "$RO/.supervisor/logs/current-session.jsonl"
run_build "$RO"; rcO=$?
JO="$RO/.supervisor/floor/floor.json"
[ "$rcO" -eq 0 ] && [ -f "$JO" ] \
  && ok "current-session fixture: exits 0 and writes an artefact" \
  || no "current-session fixture: rc=$rcO, artefact $( [ -f "$JO" ] && echo present || echo absent )"

cur() { jq -r "$1" "$JO" 2>/dev/null; }
[ "$(cur '.surfaces.sessions.detail.current.cc_session_id')" = "$cf_new_sid" ] \
  && ok "current.cc_session_id == $cf_new_sid (the session owning the newest ts)" \
  || no "current.cc_session_id == $(cur '.surfaces.sessions.detail.current.cc_session_id'), expected $cf_new_sid"
[ "$(cur '.surfaces.sessions.detail.current.last_event_ts')" = "$cf_new_ts" ] \
  && ok "current.last_event_ts == $cf_new_ts (the max ts, recomputed from the fixture)" \
  || no "current.last_event_ts == $(cur '.surfaces.sessions.detail.current.last_event_ts'), expected $cf_new_ts"
got_agents="$(cur '.surfaces.sessions.detail.current.agents[].agent_id' | tr '\n' ' ' | sed 's/ $//')"
[ "$got_agents" = "$cf_agents" ] \
  && ok "current.agents is sorted by agent_id and holds exactly: $cf_agents" \
  || no "current.agents holds '$got_agents', expected '$cf_agents'"

# Per-agent tallies, each recomputed from the fixture.
agg_bad=""
for a in $cf_agents; do
  want_ev="$(jq -r --arg s "$cf_new_sid" --arg a "$a" 'select(.cc_session_id == $s and .agent_id == $a) | "x"' "$SESS_CUR_FIXTURE" 2>/dev/null | awk 'NF{n++} END{print n+0}')"
  want_first="$(jq -r --arg s "$cf_new_sid" --arg a "$a" 'select(.cc_session_id == $s and .agent_id == $a and has("ts")) | .ts' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort | head -1)"
  want_last="$(jq -r --arg s "$cf_new_sid" --arg a "$a" 'select(.cc_session_id == $s and .agent_id == $a and has("ts")) | .ts' "$SESS_CUR_FIXTURE" 2>/dev/null | LC_ALL=C sort | tail -1)"
  got_ev="$(jq -r --arg a "$a" '[.surfaces.sessions.detail.current.agents[] | select(.agent_id == $a) | .events] | .[0]' "$JO" 2>/dev/null)"
  got_first="$(jq -r --arg a "$a" '[.surfaces.sessions.detail.current.agents[] | select(.agent_id == $a) | .first_ts] | .[0]' "$JO" 2>/dev/null)"
  got_last="$(jq -r --arg a "$a" '[.surfaces.sessions.detail.current.agents[] | select(.agent_id == $a) | .last_ts] | .[0]' "$JO" 2>/dev/null)"
  [ "$got_ev" = "$want_ev" ]       || agg_bad="$agg_bad $a(events $got_ev!=$want_ev)"
  [ "$got_first" = "$want_first" ] || agg_bad="$agg_bad $a(first_ts $got_first!=$want_first)"
  [ "$got_last" = "$want_last" ]   || agg_bad="$agg_bad $a(last_ts $got_last!=$want_last)"
done
[ -z "$agg_bad" ] \
  && ok "every agent's events / first_ts / last_ts matches the fixture recomputed independently" \
  || no "per-agent aggregation mismatch:$agg_bad"
# The ts-less line still counts as an event but contributes no timestamp: events > the number
# of ts-carrying lines for exactly the agent that owns it.
ts_less_agent="$(jq -r 'select(has("ts") | not) | .agent_id' "$SESS_CUR_FIXTURE" 2>/dev/null | head -1)"
tla_ev="$(jq -r --arg a "$ts_less_agent" '[.surfaces.sessions.detail.current.agents[] | select(.agent_id == $a) | .events] | .[0]' "$JO" 2>/dev/null)"
tla_ts="$(jq -r --arg s "$cf_new_sid" --arg a "$ts_less_agent" 'select(.cc_session_id == $s and .agent_id == $a and has("ts")) | "x"' "$SESS_CUR_FIXTURE" 2>/dev/null | awk 'NF{n++} END{print n+0}')"
[ "$tla_ev" -gt "$tla_ts" ] \
  && ok "$ts_less_agent counts $tla_ev events over $tla_ts ts-carrying lines - a ts-less line is an event with no timestamp" \
  || no "$ts_less_agent counts $tla_ev events for $tla_ts ts-carrying lines - the ts-less line was dropped or double-counted"

typed_rows="$(jq -r '[.surfaces.sessions.detail.current.agents[] | select(has("agent_type")) | .agent_id] | join(" ")' "$JO" 2>/dev/null)"
[ "$typed_rows" = "$cf_typed" ] \
  && ok "agent_type is present for exactly $cf_typed - taken from an OLDER line than that agent's newest" \
  || no "typed rows are '$typed_rows', expected '$cf_typed'"
[ "$(jq -r --arg a "$cf_typed" '[.surfaces.sessions.detail.current.agents[] | select(.agent_id == $a) | .agent_type] | .[0]' "$JO" 2>/dev/null)" = "$cf_type_val" ] \
  && ok "and it is the fixture's own value ($cf_type_val), verbatim" \
  || no "agent_type value mismatch, expected $cf_type_val"
branch_rows="$(jq -r '[.surfaces.sessions.detail.current.agents[] | select(has("branch")) | .agent_id] | join(" ")' "$JO" 2>/dev/null)"
[ "$branch_rows" = "$cf_typed" ] \
  && ok "branch is present ONLY on the row whose lines carried one ($cf_branch_val), omitted on the rest" \
  || no "branch rows are '$branch_rows', expected '$cf_typed'"
scope_rows="$(jq -r '[.surfaces.sessions.detail.current.agents[] | select(has("agent_scope")) | .agent_id] | join(" ")' "$JO" 2>/dev/null)"
[ "$scope_rows" = "$cf_scoped" ] \
  && ok "agent_scope is present for exactly $cf_scoped - taken from an OLDER line than that agent's newest" \
  || no "scoped rows are '$scope_rows', expected '$cf_scoped'"
[ "$(jq -r --arg a "$cf_main_agent" '[.surfaces.sessions.detail.current.agents[] | select(.agent_id == $a) | .agent_scope] | .[0]' "$JO" 2>/dev/null)" = "main" ] \
  && ok "and $cf_main_agent - untyped, so a lane the page used to call 'identity unknown' - projects agent_scope main" \
  || no "agent_scope for $cf_main_agent is $(jq -r --arg a "$cf_main_agent" '[.surfaces.sessions.detail.current.agents[] | select(.agent_id == $a) | .agent_scope] | .[0]' "$JO" 2>/dev/null), expected main"
scope_unk_bad=""
for a in $cf_unscoped; do
  jq -e --arg a "$a" '[.surfaces.sessions.detail.current.agents[] | select(.agent_id == $a) | has("agent_scope")] | .[0] | not' "$JO" >/dev/null 2>&1 \
    || scope_unk_bad="$scope_unk_bad $a"
done
[ -z "$scope_unk_bad" ] \
  && ok "an agent no line scoped keeps the key ABSENT ($cf_unscoped) - unknown stays unknown, never defaulted to main" \
  || no "agent_scope was invented for:$scope_unk_bad"

iso_bad=""
for a in $cf_other_agents; do
  jq -e --arg a "$a" '[.surfaces.sessions.detail.current.agents[] | select(.agent_id == $a)] | length == 0' "$JO" >/dev/null 2>&1 \
    || iso_bad="$iso_bad $a"
done
[ -z "$iso_bad" ] \
  && ok "no agent from the OLDER session leaked into current.agents (checked: $cf_other_agents)" \
  || no "agents from another session appear in current:$iso_bad"
# The older session is nevertheless still counted as a session - `current` is a view, not a filter.
[ "$(scount "$JO" sessions)" = "$cf_ids" ] \
  && ok "the sessions count still spans BOTH sessions ($cf_ids) - current narrows the view, not the count" \
  || no "sessions count == $(scount "$JO" sessions), expected $cf_ids"

# No ts anywhere -> current OMITTED with a note, never guessed from file order.
RO2="$(new_repo)"; mkdir -p "$RO2/.supervisor/logs"
{ printf '{"event":"a","cc_session_id":"sess-nots-0001","agent_id":"agt-x"}\n'
  printf '{"event":"b","cc_session_id":"sess-nots-0002","agent_id":"agt-y"}\n'; } \
  > "$RO2/.supervisor/logs/no-ts.jsonl"
run_build "$RO2"; rcO2=$?
JO2="$RO2/.supervisor/floor/floor.json"
[ "$rcO2" -eq 0 ] && [ -f "$JO2" ] && ok "no-ts fixture: exits 0 and writes an artefact" \
  || no "no-ts fixture: rc=$rcO2, artefact $( [ -f "$JO2" ] && echo present || echo absent )"
jq -e '.surfaces.sessions.detail | has("current") | not' "$JO2" >/dev/null 2>&1 \
  && ok "with no ts on any line, current is OMITTED (file order is not evidence of recency)" \
  || no "current was emitted without a single ts: $(jq -c '.surfaces.sessions.detail.current' "$JO2" 2>/dev/null)"
jq -e '[.notes[] | select(test("current"))] | length > 0' "$JO2" >/dev/null 2>&1 \
  && ok "and the omission is named in notes[]" \
  || no "notes[] does not record the omitted current: $(jq -c '.notes' "$JO2" 2>/dev/null)"
[ "$(sstatus "$JO2" sessions)" = "counted" ] && [ "$(scount "$JO2" sessions)" = "2" ] \
  && ok "the sessions count itself is unaffected by the missing ts (counted/2)" \
  || no "sessions == $(sstatus "$JO2" sessions)/$(scount "$JO2" sessions), expected counted/2"

# ============================================================================
echo "== (p) state subtask rows: {id, title, status} in table order, status omitted when absent =="
# seed_tree writes rows `| N | sub N | COMPLETED | PASS |` for N in 1..EXP_STATE, so the
# expectations here are the seeder's own literals - not a re-read of the projector's output.
st_n="$(jq -r '.surfaces.state.detail.subtasks | length' "$JA" 2>/dev/null)"
[ "$st_n" = "$EXP_STATE" ] \
  && ok "state.detail.subtasks holds $EXP_STATE rows, one per seeded table row" \
  || no "state.detail.subtasks holds $st_n rows, expected $EXP_STATE"
count_is "$JA" state "$EXP_STATE" \
  && ok "and the existing state count is unchanged at $EXP_STATE" \
  || no "the state count changed to $(scount "$JA" state) when subtasks were added"
row_bad=""
i=1
while [ "$i" -le "$EXP_STATE" ]; do
  gid="$(jq -r --argjson i "$((i-1))" '.surfaces.state.detail.subtasks[$i].id' "$JA" 2>/dev/null)"
  gti="$(jq -r --argjson i "$((i-1))" '.surfaces.state.detail.subtasks[$i].title' "$JA" 2>/dev/null)"
  gst="$(jq -r --argjson i "$((i-1))" '.surfaces.state.detail.subtasks[$i].status' "$JA" 2>/dev/null)"
  [ "$gid" = "$i" ]           || row_bad="$row_bad row$i(id=$gid)"
  [ "$gti" = "sub $i" ]       || row_bad="$row_bad row$i(title=$gti)"
  [ "$gst" = "COMPLETED" ]    || row_bad="$row_bad row$i(status=$gst)"
  i=$((i+1))
done
[ -z "$row_bad" ] \
  && ok "every row is {id, title, status} in TABLE ORDER, cells trimmed" \
  || no "subtask rows mismatch:$row_bad"

RP="$(new_repo)"; mkdir -p "$RP/.supervisor"
{ printf '# Supervisor State\n\n## Session\n- phase: PLAN\n\n## Subtasks\n'
  printf '| # | Title |\n|---|-------|\n'
  printf '| 1 | alpha task |\n'
  printf '| 2 | beta task |\n'
  printf '\n## Parallelism\n- launchable: 0\n'; } > "$RP/.supervisor/state.md"
run_build "$RP"; rcP=$?
JP="$RP/.supervisor/floor/floor.json"
[ "$rcP" -eq 0 ] && [ -f "$JP" ] && ok "status-less table: exits 0 and writes an artefact" \
  || no "status-less table: rc=$rcP, artefact $( [ -f "$JP" ] && echo present || echo absent )"
[ "$(sstatus "$JP" state)" = "counted" ] && [ "$(scount "$JP" state)" = "2" ] \
  && ok "a table with no Status column is still counted (2 rows)" \
  || no "state == $(sstatus "$JP" state)/$(scount "$JP" state), expected counted/2"
[ "$(jq -r '.surfaces.state.detail.subtasks | length' "$JP" 2>/dev/null)" = "2" ] \
  && ok "both rows are emitted" \
  || no "subtasks holds $(jq -r '.surfaces.state.detail.subtasks | length' "$JP" 2>/dev/null) rows, expected 2"
jq -e '[.surfaces.state.detail.subtasks[] | has("status")] | any | not' "$JP" >/dev/null 2>&1 \
  && ok "no row carries a status key (a missing column is OMITTED, never guessed as PENDING)" \
  || no "a status was invented for a table with no Status column: $(jq -c '.surfaces.state.detail.subtasks' "$JP" 2>/dev/null)"
[ "$(jq -r '.surfaces.state.detail.subtasks[0].title' "$JP" 2>/dev/null)" = "alpha task" ] \
  && ok "titles with an internal space survive the cell trim intact" \
  || no "title reads '$(jq -r '.surfaces.state.detail.subtasks[0].title' "$JP" 2>/dev/null)', expected 'alpha task'"

# ============================================================================
echo "== (q) add_surface: an unparseable detail emits the surface WITHOUT detail, never drops it =="
# The guard is DEFENSIVE: every `detail` payload in build-floor.sh is itself built by jq, so no
# tree can reach it. Exercising it therefore needs an injected call site, and all three variants
# below are the REAL script plus ONE inserted line - the probe runs the real add_surface with a
# bad payload, the CONTROL is that same probe with the guard line reverted, and the third feeds
# VALID detail so the injection mechanism itself is not what the assertions rest on.
# ENVIRON, not `awk -v`, per this file's convention: -v processes escape sequences.
PROBE_ANCHOR='STATE=".supervisor/state.md"'
PROBE_BAD='add_surface "probe_bad_detail" "probe-source" "probe basis" "counted" "1" "" "" "{not valid json"'
PROBE_GOOD='add_surface "probe_good_detail" "probe-source" "probe basis" "counted" "1" "" "" '"'"'{"ok":true}'"'"''
GUARD_OLD='  if [ -z "$obj" ] && [ -n "$detail" ]; then'
GUARD_NEW='  if false; then'

inject_probe() {   # <outfile> <line to insert>
  PI_ANCHOR="$PROBE_ANCHOR" PI_INS="$2" awk '
    BEGIN{a=ENVIRON["PI_ANCHOR"]; ins=ENVIRON["PI_INS"]}
    {print}
    $0==a && !d {print ins; d=1}' "$BUILD" > "$1"
}
grep -qxF "$PROBE_ANCHOR" "$BUILD" \
  && ok "the probe anchor line is present in build-floor.sh (the injection point is real)" \
  || no "the probe anchor '$PROBE_ANCHOR' is not in build-floor.sh - every (q) case below is inconclusive"
grep -qxF "$GUARD_OLD" "$BUILD" \
  && ok "the add_surface guard line is present verbatim (the control below can revert it)" \
  || no "the guard line '$GUARD_OLD' is not in build-floor.sh - the mutation control is inconclusive"

PBAD="$ROOT/probe-bad-detail.sh"; inject_probe "$PBAD" "$PROBE_BAD"
RQ="$(new_repo)"; seed_tree "$RQ"
JQ1="$RQ/.supervisor/floor/floor.json"
if [ -s "$PBAD" ] && ! cmp -s "$PBAD" "$BUILD" && bash -n "$PBAD" 2>/dev/null && grep -qxF "$PROBE_BAD" "$PBAD"; then
  ok "the bad-detail probe is buildable and bash -n clean"
  ( cd "$RQ" && FLOOR_AGENTS_DIR="$RQ/agents" bash "$PBAD" ) >/dev/null 2>&1; rcQ=$?
  if [ "$rcQ" -eq 0 ] && [ -f "$JQ1" ]; then
    ok "the probe still reaches its own success line (exit 0 + artefact written)"
    jq -e '.surfaces | has("probe_bad_detail")' "$JQ1" >/dev/null 2>&1 \
      && ok "the surface is STILL EMITTED although its detail would not parse" \
      || no "the surface vanished on an unparseable detail - add_surface returned silently"
    [ "$(sstatus "$JQ1" probe_bad_detail)" = "counted" ] && [ "$(scount "$JQ1" probe_bad_detail)" = "1" ] \
      && ok "its status and count survive intact (counted/1)" \
      || no "probe surface reads $(sstatus "$JQ1" probe_bad_detail)/$(scount "$JQ1" probe_bad_detail)"
    jq -e '.surfaces.probe_bad_detail | has("detail") | not' "$JQ1" >/dev/null 2>&1 \
      && ok "and it carries NO detail key (the unparseable payload is dropped, not half-written)" \
      || no "an unparseable detail was emitted anyway: $(jq -c '.surfaces.probe_bad_detail.detail' "$JQ1" 2>/dev/null)"
    jq -e '[.notes[] | select(test("probe_bad_detail"))] | length > 0' "$JQ1" >/dev/null 2>&1 \
      && ok "notes[] names the offending surface key" \
      || no "notes[] does not name probe_bad_detail: $(jq -c '.notes' "$JQ1" 2>/dev/null)"
    jq -e '[.notes[] | select(test("probe_bad_detail") and (test("JSON") or test("json")))] | length > 0' "$JQ1" >/dev/null 2>&1 \
      && ok "...and states the reason (the payload is not valid JSON) in the same line" \
      || no "the note names the key but not the reason: $(jq -c '[.notes[] | select(test("probe_bad_detail"))]' "$JQ1" 2>/dev/null)"
    count_is "$JQ1" logs "$EXP_LOGS" \
      && ok "the rest of the projection is unaffected (logs still $EXP_LOGS)" \
      || no "a bad detail on one surface disturbed another (logs == $(scount "$JQ1" logs))"
  else
    no "the bad-detail probe did not reach its success line (rc=$rcQ) - every (q) assertion is inconclusive"
  fi
else
  no "could not build a valid bad-detail probe - every (q) assertion is inconclusive"
fi

echo "-- mutation control: reverting the guard must make the surface VANISH --"
PREV="$ROOT/probe-guard-reverted.sh"
GUARD_OLD="$GUARD_OLD" GUARD_NEW="$GUARD_NEW" awk '
  BEGIN{o=ENVIRON["GUARD_OLD"]; n=ENVIRON["GUARD_NEW"]}
  $0==o && !d {print n; d=1; next} {print}' "$PBAD" > "$PREV"
if [ -s "$PREV" ] && ! cmp -s "$PREV" "$PBAD" && bash -n "$PREV" 2>/dev/null \
   && grep -qxF "$GUARD_NEW" "$PREV" && grep -qxF "$PROBE_BAD" "$PREV"; then
  ok "the guard-reverted mutant is buildable, bash -n clean, differs from the probe, and keeps the injected call"
  RQ2="$(new_repo)"; seed_tree "$RQ2"
  ( cd "$RQ2" && FLOOR_AGENTS_DIR="$RQ2/agents" bash "$PREV" ) >/dev/null 2>&1; rcQ2=$?
  JQ2="$RQ2/.supervisor/floor/floor.json"
  if [ "$rcQ2" -eq 0 ] && [ -f "$JQ2" ]; then
    ok "the mutant still reaches its own success line (exit 0 + artefact written)"
    jq -e '.surfaces | has("probe_bad_detail")' "$JQ2" >/dev/null 2>&1 \
      && no "the guard-reverted mutant still emitted the surface - the control is inconclusive" \
      || ok "MUTATION CONTROL: without the guard the surface VANISHES silently, turning the assertions above RED"
    count_is "$JQ2" logs "$EXP_LOGS" \
      && ok "...and it vanishes without any other symptom - which is exactly why nothing would notice" \
      || no "the mutant diverged elsewhere too (logs == $(scount "$JQ2" logs)) - the silence claim needs re-checking"
  else
    no "the guard-reverted mutant did not reach its success line (rc=$rcQ2) - control inconclusive"
  fi
else
  no "could not build a valid guard-reverted mutant - this control is inconclusive"
fi

echo "-- positive control: VALID injected detail must still reach the artefact --"
PGOOD="$ROOT/probe-good-detail.sh"; inject_probe "$PGOOD" "$PROBE_GOOD"
if [ -s "$PGOOD" ] && ! cmp -s "$PGOOD" "$BUILD" && bash -n "$PGOOD" 2>/dev/null && grep -qxF "$PROBE_GOOD" "$PGOOD"; then
  ok "the valid-detail probe is buildable and bash -n clean"
  RQ3="$(new_repo)"; seed_tree "$RQ3"
  ( cd "$RQ3" && FLOOR_AGENTS_DIR="$RQ3/agents" bash "$PGOOD" ) >/dev/null 2>&1
  JQ3="$RQ3/.supervisor/floor/floor.json"
  if [ -f "$JQ3" ]; then
    jq -e '.surfaces.probe_good_detail.detail.ok == true' "$JQ3" >/dev/null 2>&1 \
      && ok "CONTROL: a VALID injected detail is emitted unchanged - the guard drops only what will not parse, and the injection mechanism works" \
      || no "CONTROL: a valid injected detail did not reach the artefact ($(jq -c '.surfaces.probe_good_detail' "$JQ3" 2>/dev/null)) - the (q) probe proves nothing"
    jq -e '[.notes[] | select(test("probe_good_detail"))] | length == 0' "$JQ3" >/dev/null 2>&1 \
      && ok "CONTROL: and no note is emitted for a payload that parsed" \
      || no "CONTROL: a note was emitted for a VALID detail: $(jq -c '[.notes[] | select(test("probe_good_detail"))]' "$JQ3" 2>/dev/null)"
  else
    no "the valid-detail probe wrote no artefact - this control is inconclusive"
  fi
else
  no "could not build a valid valid-detail probe - this control is inconclusive"
fi

# ============================================================================
echo "== (r) rules detail: deterministic rows, tri-state applies_to AND check, count unchanged =="
# PREMISE, re-derived from the committed fixture so the literals above cannot outlive it.
fx_files="$(ls "$RULES_FIXTURE_DIR"/*.json 2>/dev/null | awk 'NF{n++} END{print n+0}')"
fx_rules="$(jq -s 'add | length' "$RULES_FIXTURE_DIR"/*.json 2>/dev/null)"
[ "$fx_files" = "$EXP_RULES" ] && [ "$fx_rules" = "$EXP_RULES_DETAIL" ] \
  && ok "PREMISE: the committed rules fixture is $EXP_RULES category files holding $EXP_RULES_DETAIL rules" \
  || no "rules fixture drift: files=$fx_files (want $EXP_RULES) rules=$fx_rules (want $EXP_RULES_DETAIL)"
fx_pm_lines="$(awk 'NF{n++} END{print n+0}' "$PM_FIXTURE" 2>/dev/null)"
fx_pm_cats="$(jq -s '[.[].categories[]?] | length' "$PM_FIXTURE" 2>/dev/null)"
[ "$fx_pm_lines" = "$EXP_POSTMORTEM" ] && [ "$fx_pm_cats" = "$EXP_PM_CATEGORIES" ] \
  && ok "PREMISE: the committed ledger fixture is $EXP_POSTMORTEM lines carrying $EXP_PM_CATEGORIES category objects" \
  || no "ledger fixture drift: lines=$fx_pm_lines (want $EXP_POSTMORTEM) categories=$fx_pm_cats (want $EXP_PM_CATEGORIES)"

rdet() { jq -c "$2" "$1/.supervisor/floor/floor.json" 2>/dev/null; }

[ "$(rdet "$RA" '.surfaces.rules.detail.rules_parsed')" = "$EXP_RULES_DETAIL" ] \
  && ok "detail.rules_parsed == $EXP_RULES_DETAIL (rule OBJECTS)" \
  || no "detail.rules_parsed: got $(rdet "$RA" '.surfaces.rules.detail.rules_parsed'), want $EXP_RULES_DETAIL"
[ "$(scount "$JA" rules)" = "$EXP_RULES" ] \
  && ok "...while surfaces.rules.count is STILL $EXP_RULES - the count key keeps meaning category files, not rules" \
  || no "count was silently redefined: $(scount "$JA" rules)"
[ "$(rdet "$RA" '.surfaces.rules.detail.rules_parsed')" != "$(scount "$JA" rules)" ] \
  && ok "the two numbers are different fields carrying different meanings, and differ on this fixture" \
  || no "rules_parsed and count are the same number - the fixture cannot tell them apart"
[ "$(rdet "$RA" '.surfaces.rules.detail.rules | length')" = "$EXP_RULES_DETAIL" ] \
  && ok "detail.rules[] holds $EXP_RULES_DETAIL rows" \
  || no "detail.rules[] length: $(rdet "$RA" '.surfaces.rules.detail.rules | length')"

# Deterministic order, stated as a literal rather than read back out of the artefact.
EXP_ROW_IDS='["fixture-applies-absent-check-absent","fixture-applies-array-check-string","fixture-applies-null-check-null","fixture-chain-head","fixture-chain-mid","fixture-chain-tail","fixture-cycle-a","fixture-cycle-b","fixture-cycle-c","fixture-dangling-source","fixture-malformed-applies-to","fixture-provenance-empty-object","fixture-provenance-malformed","fixture-supersedes-empty","fixture-supersedes-malformed","fixture-supersedes-null"]'
[ "$(rdet "$RA" '[.surfaces.rules.detail.rules[].id]')" = "$EXP_ROW_IDS" ] \
  && ok "detail.rules[] is in a deterministic (category, id, source_file) order" \
  || no "row order/ids: $(rdet "$RA" '[.surfaces.rules.detail.rules[].id]')"
# ...and a second run over the unchanged tree reproduces it byte for byte.
RA2="$(new_repo)"; seed_tree "$RA2"; run_build "$RA2"
[ "$(rdet "$RA2" '.surfaces.rules.detail')" = "$(rdet "$RA" '.surfaces.rules.detail')" ] \
  && ok "a second run over an identical tree emits a byte-identical rules detail" \
  || no "rules detail is not deterministic across two identical trees"

miss_field=""
for f in id category statement enforcement provenance; do
  [ "$(rdet "$RA" "[.surfaces.rules.detail.rules[] | select(has(\"$f\") | not)] | length")" = "0" ] \
    || miss_field="$miss_field $f"
done
[ -z "$miss_field" ] && ok "every row carries id / category / statement / enforcement / provenance" \
  || no "rows missing always-present fields:$miss_field"

echo "-- applies_to and check are BOTH genuine tri-states, all three states distinguishable --"
row() { rdet "$RA" ".surfaces.rules.detail.rules[] | select(.id == \"$1\")"; }
tri() { # <row-id> <field> -> absent | null | value
  local r; r="$(row "$1")"
  printf '%s' "$r" | jq -r --arg f "$2" 'if (has($f) | not) then "absent" elif (.[$f] == null) then "null" else "value" end' 2>/dev/null
}
tri_bad=""
[ "$(tri fixture-applies-absent-check-absent applies_to)" = "absent" ] || tri_bad="$tri_bad applies_to/absent"
[ "$(tri fixture-applies-null-check-null     applies_to)" = "null"   ] || tri_bad="$tri_bad applies_to/null"
[ "$(tri fixture-applies-array-check-string  applies_to)" = "value"  ] || tri_bad="$tri_bad applies_to/value"
[ "$(tri fixture-applies-absent-check-absent check)"      = "absent" ] || tri_bad="$tri_bad check/absent"
[ "$(tri fixture-applies-null-check-null     check)"      = "null"   ] || tri_bad="$tri_bad check/null"
[ "$(tri fixture-applies-array-check-string  check)"      = "value"  ] || tri_bad="$tri_bad check/value"
[ -z "$tri_bad" ] \
  && ok "applies_to and check each render absent / null / value as THREE distinct states" \
  || no "tri-state collapsed for:$tri_bad"
[ "$(row fixture-applies-array-check-string | jq -c '.applies_to')" = '["loomwright/scripts/*","CLAUDE.md"]' ] \
  && ok "the non-empty applies_to array is carried verbatim" \
  || no "applies_to array: $(row fixture-applies-array-check-string | jq -c '.applies_to')"
[ "$(row fixture-applies-array-check-string | jq -r '.check')" = "grep -q 'a literal this fixture never runs' CLAUDE.md" ] \
  && ok "the check string is carried verbatim as DATA" \
  || no "check string: $(row fixture-applies-array-check-string | jq -r '.check')"
# MUTATION CONTROL for the tri-state: the truthy-only reading a `if .check then` producer would
# emit collapses absent and null into one bucket. Run that reading over the SAME rows and show it.
truthy_absent="$(row fixture-applies-absent-check-absent | jq -r 'if (.check // null) == null then "no-check" else "check" end')"
truthy_null="$(row fixture-applies-null-check-null       | jq -r 'if (.check // null) == null then "no-check" else "check" end')"
[ "$truthy_absent" = "$truthy_null" ] \
  && ok "MUTATION CONTROL: a truthy-only reading of the SAME rows collapses absent and null into one bucket ($truthy_absent) - which is what has() avoids" \
  || no "the truthy-only control did not collapse - it proves nothing about has()"
# ...and the check string is never executed anywhere in the producer.
[ "$(grep -cE '(^|[^[:alnum:]_-])(eval|exec)[[:space:]]' "$BUILD" 2>/dev/null)" = "0" ] \
  && ok "build-floor.sh contains no eval / exec construct - a check string cannot be executed" \
  || no "build-floor.sh carries an eval/exec construct: $(grep -nE '(^|[^[:alnum:]_-])(eval|exec)[[:space:]]' "$BUILD" | head -3)"

# ============================================================================
echo "== (s) supersedes: transitive chain in order, dangling reported, cycle bounded and whole =="
sup() { rdet "$RA" ".surfaces.rules.detail.supersedes$1"; }
[ "$(sup '.chains')" = '[["fixture-chain-head","fixture-chain-mid","fixture-chain-tail"]]' ] \
  && ok "the two-hop chain resolves TRANSITIVELY and IN ORDER (read-rules.sh would stop at one hop)" \
  || no "chains: $(sup '.chains')"
[ "$(sup '.dangling')" = '[{"from":"fixture-dangling-source","to":"fixture-no-such-rule-id"}]' ] \
  && ok "the dangling pointer is REPORTED as dangling (read-rules.sh ignores it)" \
  || no "dangling: $(sup '.dangling')"
[ "$(rdet "$RA" '[.surfaces.rules.detail.rules[] | select(.id == "fixture-dangling-source")] | length')" = "1" ] \
  && ok "...and the carrying row is still emitted, with its pointer preserved" \
  || no "the dangling row was dropped"
[ "$(sup '.cycles')" = '[["fixture-cycle-a","fixture-cycle-b","fixture-cycle-c"]]' ] \
  && ok "the A->B->C->A cycle is reported AS a cycle, canonicalised from its smallest member" \
  || no "cycles: $(sup '.cycles')"
cyc_rows="$(rdet "$RA" '[.surfaces.rules.detail.rules[] | select(.id | startswith("fixture-cycle-"))] | length')"
[ "$cyc_rows" = "3" ] \
  && ok "EVERY cycle member is emitted - none is dropped (read-rules.sh hides nothing here either, but for a different reason)" \
  || no "cycle members emitted: $cyc_rows of 3"
# TERMINATION, on a fixture that is nothing BUT a cycle: the run must return, exit 0 and write.
RCYC="$(new_repo)"; mkdir -p "$RCYC/.agent/rules"
jq -c '[.[] | select(.id | startswith("fixture-cycle-"))]' "$RULES_FIXTURE_DIR/process.json" \
  > "$RCYC/.agent/rules/only-a-cycle.json" 2>/dev/null
run_build "$RCYC"; rcCyc=$?
JCYC="$RCYC/.supervisor/floor/floor.json"
[ "$rcCyc" -eq 0 ] && [ -f "$JCYC" ] \
  && ok "a rules store that is ONLY a cycle still terminates, exits 0 and writes an artefact" \
  || no "the cycle-only fixture did not terminate cleanly (rc=$rcCyc)"
[ "$(jq -c '.surfaces.rules.detail.supersedes.cycles' "$JCYC" 2>/dev/null)" = '[["fixture-cycle-a","fixture-cycle-b","fixture-cycle-c"]]' ] \
  && ok "...and reports the cycle with all three members" \
  || no "cycle-only fixture cycles: $(jq -c '.surfaces.rules.detail.supersedes.cycles' "$JCYC" 2>/dev/null)"
[ "$(jq -c '[.surfaces.rules.detail.rules[].id] | sort' "$JCYC" 2>/dev/null)" = '["fixture-cycle-a","fixture-cycle-b","fixture-cycle-c"]' ] \
  && ok "...and emits every member as a row rather than dropping any" \
  || no "cycle-only fixture rows: $(jq -c '[.surfaces.rules.detail.rules[].id]' "$JCYC" 2>/dev/null)"
# The termination PROPERTY is inherited structurally, not by luck: a bounded, non-recursive walk.
grep -qF 'reduce range(0; $edge_n)' "$BUILD" \
  && ok "the walk is the same BOUNDED reduce range(0; \$edge_n) construction read-rules.sh uses" \
  || no "no bounded range(0; \$edge_n) walk found in build-floor.sh"
[ "$(grep -cE 'recurse|getpath\(\[|while\(' "$BUILD" 2>/dev/null)" = "0" ] \
  && ok "and carries no open-ended jq traversal (recurse / while) that could run unbounded" \
  || no "an open-ended jq traversal is present: $(grep -nE 'recurse|while\(' "$BUILD" | head -3)"
# The DIVERGENCE from read-rules.sh is stated where a reader will meet it, not left to be found.
grep -q 'read-rules.sh' "$BUILD" && grep -qi 'transitiv' "$BUILD" && grep -qi 'dangling' "$BUILD" \
  && ok "build-floor.sh states the read-rules.sh divergence (transitive / dangling) in a comment" \
  || no "build-floor.sh does not state the read-rules.sh divergence"
grep -q 'read-rules.sh' "$SCHEMA_MD" && grep -qi 'single-hop' "$SCHEMA_MD" \
  && ok "RESULT_SCHEMAS.md states the same divergence" \
  || no "RESULT_SCHEMAS.md does not state the read-rules.sh divergence"
# read-rules.sh itself is UNTOUCHED by this change - it is a different reader with pinned semantics.
grep -q 'single-hop only, NEVER transitive' "$HERE/read-rules.sh" \
  && ok "read-rules.sh keeps its own pinned single-hop contract (not modified by this surface)" \
  || no "read-rules.sh's pinned single-hop contract is missing - it must not be edited"

# ============================================================================
echo "== (t) unparseable rules file: named, never counted clean, valid rules still reported =="
mk_rules_repo() { # <"broken"|"good"|"both"> -> repo path
  local r; r="$(new_repo)"; mkdir -p "$r/.agent/rules" "$r/agents"
  cp "$AGENTS_FIXTURE_DIR"/*.md "$r/agents/" 2>/dev/null
  case "$1" in
    good|both) cp "$RULES_FIXTURE_DIR"/*.json "$r/.agent/rules/" ;;
  esac
  case "$1" in
    broken|both) cp "$RULES_BROKEN_FIXTURE" "$r/.agent/rules/broken.json" ;;
  esac
  printf '%s' "$r"
}
RPART="$(mk_rules_repo both)";   run_build "$RPART"; JPART="$RPART/.supervisor/floor/floor.json"
RNONE="$(mk_rules_repo broken)"; run_build "$RNONE"; JNONE="$RNONE/.supervisor/floor/floor.json"

[ "$(sstatus "$JPART" rules)" = "unverified" ] && [ "$(scount "$JPART" rules)" = "ABSENT" ] \
  && ok "a store with one unparseable file is unverified with NO count - never counted clean" \
  || no "partial store: status=$(sstatus "$JPART" rules) count=$(scount "$JPART" rules)"
printf '%s' "$(sreason "$JPART" rules)" | grep -qF 'broken.json' \
  && ok "...and the reason NAMES the offending file" \
  || no "the reason does not name the offender: $(sreason "$JPART" rules)"
[ "$(jq -r '.surfaces.rules.detail.read_completeness' "$JPART" 2>/dev/null)" = "partial" ] \
  && ok "read_completeness is 'partial' - read some, could not read others" \
  || no "partial read_completeness: $(jq -r '.surfaces.rules.detail.read_completeness' "$JPART" 2>/dev/null)"
[ "$(jq -r '.surfaces.rules.detail.rules_parsed' "$JPART" 2>/dev/null)" = "$EXP_RULES_DETAIL" ] \
  && ok "...and the VALID files' $EXP_RULES_DETAIL rules are still reported" \
  || no "valid rules lost on a partial read: $(jq -r '.surfaces.rules.detail.rules_parsed' "$JPART" 2>/dev/null)"
[ "$(jq -r '.surfaces.rules.detail.files_unparseable[0].file' "$JPART" 2>/dev/null)" = ".agent/rules/broken.json" ] \
  && ok "files_unparseable names the file" \
  || no "files_unparseable: $(jq -c '.surfaces.rules.detail.files_unparseable' "$JPART" 2>/dev/null)"
[ -n "$(jq -r '.surfaces.rules.detail.files_unparseable[0].reason // ""' "$JPART" 2>/dev/null)" ] \
  && ok "...and carries the parser's own reason" \
  || no "files_unparseable carries no reason"
[ "$(jq -r '.surfaces.rules.detail.read_completeness' "$JNONE" 2>/dev/null)" = "none" ] \
  && ok "a store whose ONLY file is unparseable reads 'none' - distinct from partial and from all" \
  || no "none read_completeness: $(jq -r '.surfaces.rules.detail.read_completeness' "$JNONE" 2>/dev/null)"
[ "$(jq -r '.surfaces.rules.detail | has("rules")' "$JNONE" 2>/dev/null)" = "false" ] \
  && ok "...and emits no rules[] at all rather than an empty array that would read as 'examined and clean'" \
  || no "the read-nothing case emitted a rules[] array"
[ "$(jq -r '.surfaces.rules.detail.read_completeness' "$JA" 2>/dev/null)" = "all" ] \
  && [ "$(jq -r '.surfaces.rules.detail | has("files_unparseable")' "$JA" 2>/dev/null)" = "false" ] \
  && ok "a fully-parsed store reads 'all' with no files_unparseable key - the third distinct render" \
  || no "the all-parsed case: completeness=$(jq -r '.surfaces.rules.detail.read_completeness' "$JA" 2>/dev/null)"

echo "-- MUTATION CONTROLS: a producer that does not report the unreadable file must turn these red --"
mutate_build() { # <sed-expr> -> mutant path
  local m="$ROOT/mut-build-$2.sh"
  sed "$1" "$BUILD" > "$m" 2>/dev/null
  printf '%s' "$m"
}
run_mutant() { ( cd "$1" && FLOOR_AGENTS_DIR="$1/agents" bash "$2" >/dev/null 2>&1 ); }
MUT1="$(mutate_build 's/"partial"/"all"/' completeness)"
RM1="$(mk_rules_repo both)"; run_mutant "$RM1" "$MUT1"; JM1="$RM1/.supervisor/floor/floor.json"
if [ -f "$JM1" ] && ! cmp -s "$MUT1" "$BUILD"; then
  [ "$(jq -r '.surfaces.rules.detail.read_completeness' "$JM1" 2>/dev/null)" = "partial" ] \
    && no "the mutant that reports a partial read as 'all' still satisfied the assertion" \
    || ok "MUTATION CONTROL: a producer calling a partial read 'all' turns the read_completeness assertion RED"
else
  no "the read_completeness mutant could not be built - this control is inconclusive"
fi
MUT2="$(mutate_build '/files_unparseable: \$badfiles/d' unparseable)"
RM2="$(mk_rules_repo both)"; run_mutant "$RM2" "$MUT2"; JM2="$RM2/.supervisor/floor/floor.json"
if [ -f "$JM2" ] && ! cmp -s "$MUT2" "$BUILD"; then
  [ "$(jq -r '.surfaces.rules.detail.files_unparseable[0].file' "$JM2" 2>/dev/null)" = ".agent/rules/broken.json" ] \
    && no "the mutant that drops the files_unparseable report still satisfied the assertion" \
    || ok "MUTATION CONTROL: dropping the files_unparseable report turns the naming assertion RED"
else
  no "the files_unparseable mutant could not be built - this control is inconclusive"
fi

# ============================================================================
echo "== (u) churn detail: basis PINNED to .categories[].flow_stage, malformed never a class =="
pmd() { jq -c "$2" "$1" 2>/dev/null; }
[ "$(jq -r '.surfaces.postmortem.detail.flow_stage_basis' "$JA" 2>/dev/null)" = ".categories[].flow_stage" ] \
  && ok "flow_stage_basis is the EXACT literal .categories[].flow_stage" \
  || no "flow_stage_basis: '$(jq -r '.surfaces.postmortem.detail.flow_stage_basis' "$JA" 2>/dev/null)'"
[ "$(jq -r '.surfaces.postmortem.detail.class_basis' "$JA" 2>/dev/null)" = ".categories[].class" ] \
  && ok "class_basis is .categories[].class - the SAME denominator as the flow-stage half" \
  || no "class_basis: '$(jq -r '.surfaces.postmortem.detail.class_basis' "$JA" 2>/dev/null)'"
[ "$(pmd "$JA" '.surfaces.postmortem.detail.categories_total')" = "$EXP_PM_CATEGORIES" ] \
  && ok "categories_total == $EXP_PM_CATEGORIES - the one denominator both distributions are over" \
  || no "categories_total: $(pmd "$JA" '.surfaces.postmortem.detail.categories_total')"
[ "$(pmd "$JA" '.surfaces.postmortem.detail.class_distribution')" = '{"convention_mismatch":1,"drain_churn":1,"execution_bug":1,"quality_gap":1}' ] \
  && ok "class_distribution matches the fixture's four classes" \
  || no "class_distribution: $(pmd "$JA" '.surfaces.postmortem.detail.class_distribution')"
[ "$(pmd "$JA" '.surfaces.postmortem.detail.flow_stage_distribution')" = '{"self_heal":2,"unknowable":1,"worker":1}' ] \
  && ok "flow_stage_distribution is computed over the category objects (self_heal == 2)" \
  || no "flow_stage_distribution: $(pmd "$JA" '.surfaces.postmortem.detail.flow_stage_distribution')"
# THE DISCRIMINATOR: recompute the OTHER representation from the fixture and show they differ,
# so this assertion could not pass had the producer picked `.flow_stages`.
counter_dist="$(jq -s -c '[.[].flow_stages? // {} | to_entries[]] | group_by(.key)
  | map({(.[0].key): (map(.value) | add)}) | add | with_entries(select(.value > 0))' "$PM_FIXTURE" 2>/dev/null)"
[ "$counter_dist" = '{"self_heal":4,"unknowable":1,"worker":1}' ] \
  && ok "PREMISE: the fixture's .flow_stages counter reads $counter_dist - a DIFFERENT number" \
  || no "the fixture no longer carries a disagreeing counter: $counter_dist"
[ "$(pmd "$JA" '.surfaces.postmortem.detail.flow_stage_distribution')" != "$counter_dist" ] \
  && ok "MUTATION-EQUIVALENT CONTROL: the emitted distribution is NOT the counter reading - picking .flow_stages would turn this red" \
  || no "the emitted distribution equals the counter reading - the basis assertion is vacuous"
[ "$(pmd "$JA" '.surfaces.postmortem.detail.flow_stage_counter_disagreements')" = "$EXP_PM_DISAGREE" ] \
  && ok "the projector counts the $EXP_PM_DISAGREE line where the two representations disagree" \
  || no "flow_stage_counter_disagreements: $(pmd "$JA" '.surfaces.postmortem.detail.flow_stage_counter_disagreements')"
[ "$(pmd "$JA" '.surfaces.postmortem.detail.lines_without_categories')" = "1" ] \
  && ok "the one line with an empty categories[] is counted as such, not folded into a class" \
  || no "lines_without_categories: $(pmd "$JA" '.surfaces.postmortem.detail.lines_without_categories')"
[ "$(pmd "$JA" '.surfaces.postmortem.detail.entries | length')" = "$EXP_PM_CATEGORIES" ] \
  && ok "entries[] carries one row per category object" \
  || no "entries[] length: $(pmd "$JA" '.surfaces.postmortem.detail.entries | length')"
[ "$(pmd "$JA" '[.surfaces.postmortem.detail.entries[] | select(has("evidence") | not)] | length')" = "0" ] \
  && ok "...each carrying the per-category evidence string it was derived from" \
  || no "an entry lost its evidence: $(pmd "$JA" '[.surfaces.postmortem.detail.entries[] | select(has("evidence") | not)]')"
[ "$(pmd "$JA" '.surfaces.postmortem.detail.entries[0].evidence')" = '"the reviewer asked for the pinned literal and got a variant"' ] \
  && ok "and the evidence is the fixture's own string, verbatim" \
  || no "entries[0].evidence: $(pmd "$JA" '.surfaces.postmortem.detail.entries[0].evidence')"
# No rate / score / ranking anywhere in the churn detail.
bad_keys="$(jq -r '[.surfaces.postmortem.detail | paths(scalars) | join(".")]
  | map(select(test("rate|score|rank|top_|percent|pct"; "i"))) | join(" ")' "$JA" 2>/dev/null)"
[ -z "$bad_keys" ] \
  && ok "no rate / score / rank / top-N key appears in the churn detail" \
  || no "a scoring-shaped key is present: $bad_keys"
[ "$(pmd "$JA" '.surfaces.postmortem.detail.class_distribution | type')" = '"object"' ] \
  && ok "the distributions are key-addressed objects, never arrays ordered by desirability" \
  || no "class_distribution is not an object"

echo "-- malformed ledger lines are counted and NAMED, never folded into a class --"
RPMB="$(new_repo)"; mkdir -p "$RPMB/.supervisor/postmortem" "$RPMB/agents"
cp "$AGENTS_FIXTURE_DIR"/*.md "$RPMB/agents/" 2>/dev/null
cp "$PM_BAD_FIXTURE" "$RPMB/.supervisor/postmortem/results.jsonl"
run_build "$RPMB"; JPMB="$RPMB/.supervisor/floor/floor.json"
[ "$(sstatus "$JPMB" postmortem)" = "unverified" ] && [ "$(scount "$JPMB" postmortem)" = "ABSENT" ] \
  && ok "a ledger with a malformed line is unverified with NO count" \
  || no "malformed ledger: status=$(sstatus "$JPMB" postmortem) count=$(scount "$JPMB" postmortem)"
[ "$(pmd "$JPMB" '.surfaces.postmortem.detail.lines_malformed')" = "1" ] \
  && ok "...the malformed line is COUNTED" \
  || no "lines_malformed: $(pmd "$JPMB" '.surfaces.postmortem.detail.lines_malformed')"
[ "$(pmd "$JPMB" '.surfaces.postmortem.detail.malformed_lines')" = "[5]" ] \
  && ok "...and NAMED by its line number" \
  || no "malformed_lines: $(pmd "$JPMB" '.surfaces.postmortem.detail.malformed_lines')"
[ "$(pmd "$JPMB" '.surfaces.postmortem.detail.class_distribution')" = "$(pmd "$JA" '.surfaces.postmortem.detail.class_distribution')" ] \
  && ok "...and contributes to NO class - the distribution is unchanged by it" \
  || no "the malformed line leaked into a class: $(pmd "$JPMB" '.surfaces.postmortem.detail.class_distribution')"

# ============================================================================
echo "== (v) correlation carries its evidence, is labelled an observation, and is omitted when uncomputable =="
cor() { jq -c "$2" "$1" 2>/dev/null; }
[ "$(cor "$JA" '.surfaces.rules.detail.correlations | length')" = "1" ] \
  && ok "exactly one rule has a computable correlation on this fixture" \
  || no "correlations length: $(cor "$JA" '.surfaces.rules.detail.correlations | length')"
[ "$(cor "$JA" '.surfaces.rules.detail.correlations[0].rule_id')" = '"fixture-applies-array-check-string"' ] \
  && ok "...the only rule carrying a non-empty applies_to array" \
  || no "correlation rule_id: $(cor "$JA" '.surfaces.rules.detail.correlations[0].rule_id')"
[ "$(cor "$JA" '.surfaces.rules.detail.correlations[0].label')" = '"observation"' ] \
  && ok "it is LABELLED an observation, not a measurement" \
  || no "correlation label: $(cor "$JA" '.surfaces.rules.detail.correlations[0].label')"
cbasis="$(jq -r '.surfaces.rules.detail.correlations[0].basis // ""' "$JA" 2>/dev/null)"
printf '%s' "$cbasis" | grep -qF 'changed_paths' && printf '%s' "$cbasis" | grep -qi 'not evidence' \
  && ok "...and states its basis, including that a path overlap is not evidence of a violation" \
  || no "correlation basis is missing or does not disclaim: '$cbasis'"
[ "$(cor "$JA" '.surfaces.rules.detail.correlations[0].matched | length')" = "3" ] \
  && ok "three ledger paths overlap this rule's globs" \
  || no "matched length: $(cor "$JA" '.surfaces.rules.detail.correlations[0].matched | length')"
# Evidence is carried ONCE PER CORRELATION keyed by line, not once per (rule, path) match: a
# rule's globs typically match many paths on the same ledger line, and attaching the array to
# every match re-serialised it (measured: 612 occurrences for 154 distinct strings). What
# AC-correlation-evidence requires is that the evidence travel WITH the correlation it was
# derived from - so the assertion is that EVERY matched line RESOLVES to evidence, which is the
# property that matters and is stronger than checking a key exists on each match.
[ "$(cor "$JA" '[.surfaces.rules.detail.correlations[0].matched[] | select((has("line") and has("path") and has("pattern")) | not)] | length')" = "0" ] \
  && ok "every match carries the line, the path and the pattern it matched" \
  || no "a match is missing line/path/pattern: $(cor "$JA" '.surfaces.rules.detail.correlations[0].matched')"
# NB the `as $l` capture is load-bearing: inside `has(.)` the `.` would rebind to
# evidence_by_line itself, not the line - the same jq scoping trap that silently emptied the
# supersedes chain walk during subtask 1 (there via `index(.)`). Capture, then test.
[ "$(cor "$JA" '.surfaces.rules.detail.correlations[0] as $c | [$c.matched[].line | tostring as $l | select((($c.evidence_by_line // {}) | has($l)) | not)] | length')" = "0" ] \
  && ok "...and every matched line resolves to the ledger's own evidence in evidence_by_line" \
  || no "a matched line has no evidence: $(cor "$JA" '.surfaces.rules.detail.correlations[0].evidence_by_line')"
[ "$(cor "$JA" '[.surfaces.rules.detail.correlations[].rule_id] | sort == .')" = "true" ] \
  && ok "correlations are ordered by rule_id - never ranked by match count" \
  || no "correlations are not in rule_id order"
# OMITTED, never zero: the nine rules with no computable correlation appear nowhere.
[ "$(cor "$JA" '[.surfaces.rules.detail.correlations[].rule_id] | map(select(. == "fixture-applies-null-check-null" or . == "fixture-applies-absent-check-absent")) | length')" = "0" ] \
  && ok "a rule with applies_to null or absent is OMITTED from correlations, not emitted as zero" \
  || no "an uncomputable correlation was emitted anyway"
[ "$(cor "$JA" '[.surfaces.rules.detail.correlations[].matched | length] | map(select(. == 0)) | length')" = "0" ] \
  && ok "no correlation carries an empty match set - a zero there would read as 'measured no violations'" \
  || no "a zero-match correlation was emitted"
# CONTROL: the same rules store against a ledger whose paths overlap NOTHING - the key vanishes.
RNC="$(new_repo)"; mkdir -p "$RNC/.agent/rules" "$RNC/.supervisor/postmortem" "$RNC/agents"
cp "$AGENTS_FIXTURE_DIR"/*.md "$RNC/agents/" 2>/dev/null
cp "$RULES_FIXTURE_DIR"/*.json "$RNC/.agent/rules/"
jq -c '.changed_paths = ["nothing/that/matches.txt"]' "$PM_FIXTURE" > "$RNC/.supervisor/postmortem/results.jsonl" 2>/dev/null
run_build "$RNC"; JNC="$RNC/.supervisor/floor/floor.json"
[ "$(jq -r '.surfaces.rules.detail | has("correlations")' "$JNC" 2>/dev/null)" = "false" ] \
  && ok "CONTROL: with no overlapping path the correlations key is ABSENT entirely, not an empty array" \
  || no "a non-overlapping ledger still produced: $(cor "$JNC" '.surfaces.rules.detail.correlations')"
[ "$(jq -r '.surfaces.rules.detail.rules_parsed' "$JNC" 2>/dev/null)" = "$EXP_RULES_DETAIL" ] \
  && ok "...and the rest of the rules detail is unaffected by the absent correlation" \
  || no "the no-correlation tree lost its rules detail"

# ============================================================================
echo "== (w) both new surfaces stay ABSENT on the empty fixture (the anti-vacuity premise) =="
[ "$(sstatus "$JEMPTY" rules)" = "absent" ] && [ "$(scount "$JEMPTY" rules)" = "ABSENT" ] \
  && ok "rules is absent with no count on the EMPTY fixture" \
  || no "empty fixture rules: status=$(sstatus "$JEMPTY" rules) count=$(scount "$JEMPTY" rules)"
[ "$(sstatus "$JEMPTY" postmortem)" = "absent" ] && [ "$(scount "$JEMPTY" postmortem)" = "ABSENT" ] \
  && ok "postmortem is absent with no count on the EMPTY fixture" \
  || no "empty fixture postmortem: status=$(sstatus "$JEMPTY" postmortem) count=$(scount "$JEMPTY" postmortem)"
[ "$(jq -r '.surfaces.rules | has("detail")' "$JEMPTY" 2>/dev/null)" = "false" ] \
  && [ "$(jq -r '.surfaces.postmortem | has("detail")' "$JEMPTY" 2>/dev/null)" = "false" ] \
  && ok "neither surface emits a detail on a tree it never read" \
  || no "a detail was emitted for a surface that was never read"
# No env seam was introduced: both surfaces stay cwd-relative, which is what already makes them
# hermetic through run_build's `cd`. A FLOOR_RULES_DIR / FLOOR_POSTMORTEM override would be a
# redundant second seam, and its absence is asserted rather than assumed.
[ "$(grep -cE 'FLOOR_RULES_DIR|FLOOR_POSTMORTEM' "$BUILD" 2>/dev/null)" = "0" ] \
  && ok "no FLOOR_RULES_DIR / FLOOR_POSTMORTEM override exists - the surfaces stay cwd-relative" \
  || no "a redundant env seam was added: $(grep -nE 'FLOOR_RULES_DIR|FLOOR_POSTMORTEM' "$BUILD" | head -2)"
[ "$(grep -cF 'FLOOR_AGENTS_DIR' "$BUILD" 2>/dev/null)" -gt 0 ] \
  && ok "CONTROL: the one legitimate override, FLOOR_AGENTS_DIR, IS present - the grep can find a seam" \
  || no "the seam grep found nothing at all - it proves nothing"

# ============================================================================
echo "== (z) the output path is CWD-relative - a \$0-derived write cannot reach the checkout =="
# THE ENFORCEMENT GATE THAT (m) BELOW IS THE RESIDUE-CATCHER FOR, and the reason (m) is allowed
# to attribute serve churn at all.
#
# (m) mirrors the real `.supervisor/` by symlink and runs the projector against it, then checks
# that nothing landed in the developer's own checkout. The escape it guards is not imaginary:
# this script ALREADY resolves one input directory from `$0` rather than from the cwd (the
# agents roster - see (n)), so "a path derived from the plugin's install location instead of the
# project root" is a shape that exists here and could spread to the OUTPUT path. But (m) can
# only ever be a corroboration: it is local-only, it skips on a fresh clone and in CI, and -
# since the previous release - it must attribute the churn of a live Floor server rather than
# report it, which is a narrowing however carefully evidenced.
#
# So the absolute, always-on, CI-running form of that same claim is HERE, and it is hermetic:
# the projector is COPIED into a temp directory that is not a repository, and run with the cwd
# in a fixture repo somewhere else entirely. Every write must land under the cwd. A `$0`-derived
# output would land beside the copy, where nothing else writes and where a hash is therefore
# exact rather than attributed - no live server, no concurrent session, no skip.
RZ="$(new_repo)"; seed_tree "$RZ"
ZPLUG="$(mktmp)"; mkdir -p "$ZPLUG/scripts"
cp "$BUILD" "$ZPLUG/scripts/build-floor.sh" 2>/dev/null
# The hash covers the copy's whole parent, not just its own directory, so a write ONE LEVEL UP
# from the script (the `<plugin>/agents` shape (n) describes, resolved from `$0`) is in scope.
z_sig() {
  ( cd "$1" 2>/dev/null || return 1
    find . \( -type f -o -type l -o -type d \) -print | LC_ALL=C sort \
      | while IFS= read -r p; do
          if [ -f "$p" ] && [ ! -L "$p" ]; then printf '%s  %s\n' "$(csum "$p")" "$p"
          else printf 'NONFILE  %s\n' "$p"; fi
        done )
}
z_before="$(z_sig "$ZPLUG")"
[ -n "$z_before" ] \
  && ok "(z) pre-run signature of the copied projector's install tree is non-empty" \
  || no "(z) the install-tree signature is empty - the containment assertion below would be vacuous"
( cd "$RZ" && bash "$ZPLUG/scripts/build-floor.sh" ) >/dev/null 2>&1
z_after="$(z_sig "$ZPLUG")"
[ -f "$RZ/.supervisor/floor/floor.json" ] \
  && ok "(z) the artefact landed under the CWD, not beside the script" \
  || no "(z) the projector wrote no artefact under the cwd - the containment claim has no subject"
[ "$z_before" = "$z_after" ] \
  && ok "(z) ...and the projector's own install tree is byte-unchanged and gained no path - no write is derived from \$0" \
  || no "(z) the projector wrote into its own install directory:
$(diff <(printf '%s\n' "$z_before") <(printf '%s\n' "$z_after") 2>/dev/null | head -10)"

# (z2) MUTATION CONTROL. Without it (z) is a restatement of current behaviour: a signature that
# never changes is satisfied just as well by a projector that writes NOTHING anywhere. The
# mutant is the exact defect (z) exists to catch - the output path resolved from `$0` instead of
# the cwd - and it must turn the SAME assertion red.
MUTZ="$ZPLUG/scripts/build-floor-escaped.sh"
sed 's@^OUT_DIR="\.supervisor/floor"$@OUT_DIR="$(cd "$(dirname "$0")" \&\& pwd)/.supervisor/floor"@' \
  "$BUILD" > "$MUTZ" 2>/dev/null
if [ -s "$MUTZ" ] && ! cmp -s "$MUTZ" "$BUILD" && bash -n "$MUTZ" 2>/dev/null; then
  RZ2="$(new_repo)"; seed_tree "$RZ2"
  z2_before="$(z_sig "$ZPLUG")"
  ( cd "$RZ2" && bash "$MUTZ" ) >/dev/null 2>&1
  z2_after="$(z_sig "$ZPLUG")"
  [ "$z2_before" != "$z2_after" ] \
    && ok "(z2) MUTATION CONTROL: an output path resolved from \$0 DOES change the install-tree signature - (z) discriminates rather than passing on any projector" \
    || no "(z2) MUTATION CONTROL: the escaped mutant left the install tree unchanged - (z) proves nothing"
else
  no "(z2) MUTATION CONTROL: could not build the \$0-derived output mutant - the sed no longer matches build-floor.sh's OUT_DIR assignment, so (z) is uncontrolled"
fi

# --- ATTRIBUTING A CHANGE IN THE DEVELOPER'S OWN CHECKOUT --------------------------------
# WHY THIS EXISTS. The corroboration below hashes `.supervisor/floor/` in the developer's
# checkout around its own run, to prove it wrote nothing there. But `setup-ui.sh serve` - the
# Floor - regenerates `.supervisor/floor/floor.json` UNDER EVERY PROJECT IT SERVES, by running
# this very projector inside it, on a 2-second default interval. Measured on the maintainer
# machine: the artefact's checksum moves every ~3 seconds with the Floor up. So for a developer
# who actually RUNS the tool on the repo they develop it in, the hash changed for a reason with
# nothing to do with this suite, and the assertion was unpassable. That is the same defect, in
# the same population, that (k28) had in test-setup-ui.sh, and it is fixed the same way: the
# subject is writes ATTRIBUTABLE TO THIS SUITE, so this ATTRIBUTES rather than suppresses.
#
# WHAT IS AND IS NOT EXEMPTED. `serve` reaches this directory by exactly one route -
# `regen_project` runs `build-floor.sh` in the project root - and `build-floor.sh` writes its
# output in place, with no staging file (see (z) above, whose subject is that write). So the
# closed set a serve owns inside a repo is the directory itself (`mkdir -p`) and `floor.json`,
# and nothing else. Measured: the real directory holds that one file and no other. Any other
# path appearing or changing there is DIRTY unconditionally, and so is `floor.json` itself
# whenever no live Floor that regenerates THIS repo can be found - which is the state on CI, on
# a fresh clone, and on any machine with the Floor stopped.
#
# THE HONEST LIMIT, stated because a narrowing that hides its own cost is worse than none: while
# a Floor that regenerates this checkout IS live, a write to `floor.json` by this suite would be
# attributed to that server rather than reported. That case is not left uncovered - it is moved
# to where it can be proven absolutely: (z) above runs the projector from a foreign install
# directory with the cwd elsewhere and hashes the install tree exactly, on every machine and in
# CI, with a mutation control. The enforcement is there; this remains the residue-catcher.

# floor_dir_sig <dir> -> a per-path signature of the directory, or the VALUE `ABSENT`.
# ABSENT is a value rather than a skip on purpose: a run that turns an absent directory into a
# present one must be a CHANGE, not an untested state.
floor_dir_sig() {
  [ -d "$1" ] || { printf 'ABSENT\n'; return 0; }
  ( cd "$1" 2>/dev/null || return 1
    find . \( -type f -o -type l -o -type d \) -print | LC_ALL=C sort \
      | while IFS= read -r p; do
          if [ -f "$p" ] && [ ! -L "$p" ]; then printf '%s  %s\n' "$(csum "$p")" "$p"
          else printf 'NONFILE  %s\n' "$p"; fi
        done )
}

# serve_owned_floor_rel <rel> - is this path one a Floor's own regen writes? See the closed set
# above. Deliberately exact: `./floor.json` and the directory, never a prefix match.
#
# `ABSENT` - the value floor_dir_sig reports for a directory that does not exist at all - is
# NOT in the set, and that asymmetry is deliberate rather than an oversight. A serve does create
# the directory (`mkdir -p`), so the argument for exempting the transition exists; it is refused
# because the exemption is for CHURN, and a directory coming into existence is not churn. The
# case it costs is narrow and self-limiting - a Floor's first ever tick for a project that has
# never been regenerated, landing inside this one run's window - and it costs a red, which is
# the safe direction. Creating that directory in the developer's checkout is, meanwhile, exactly
# what a containment breach looks like, and (z) above catches it absolutely either way.
serve_owned_floor_rel() {
  case "$1" in
    .|./floor.json) return 0 ;;
  esac
  return 1
}

# floor_changed_paths <before file> <after file> - the paths that differ. The path is cut by
# stripping the leading checksum field rather than by taking $2, so a path containing a space is
# reported whole instead of truncated into something that then fails serve_owned_floor_rel and
# is misreported as a foreign write.
floor_changed_paths() {
  diff "$1" "$2" 2>/dev/null | awk '
    /^[<>] / { line = substr($0, 3)
               if (line == "ABSENT") { print "ABSENT"; next }
               sub(/^[^ ]+  /, "", line)
               if (line != "") print line }' \
    | LC_ALL=C sort -u
}

# classify_real_floor_delta <before file> <after file> <live serve: yes|no>
#   -> "CLEAN" | "SERVE <paths...>" | "DIRTY <paths...>"
# The whole decision in one place, so the controls below drive the SAME code the live assertion
# runs rather than a re-implementation that could drift from it.
classify_real_floor_delta() {
  local bf="$1" af="$2" live="$3" paths p all="" foreign=""
  paths="$(floor_changed_paths "$bf" "$af")"
  [ -n "$paths" ] || { printf 'CLEAN'; return 0; }
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    all="$all $p"
    serve_owned_floor_rel "$p" || foreign="$foreign $p"
  done <<FLOOR_DELTA_EOF
$paths
FLOOR_DELTA_EOF
  if [ -n "$foreign" ]; then printf 'DIRTY%s' "$foreign"; return 0; fi
  if [ "$live" = "yes" ]; then printf 'SERVE%s' "$all"; return 0; fi
  printf 'DIRTY%s' "$all"
  return 0
}

# live_floor_regen_pids <repo path> -> the pids of a LIVE Floor server that REGENERATES that
# repo. Three clauses, each load-bearing, and none of them satisfiable by a file alone:
#   * the process must be ALIVE and answer to this module's own command-line description - the
#     same ownership test `setup-ui.sh stop` applies. A pidfile outlives its process, so a
#     pidfile is not evidence.
#   * it must be regenerating AT ALL: `serve --no-regen` writes nothing into any project.
#   * it must regenerate THIS repo. A Floor serving somebody else's project cannot excuse a
#     change here, and the selected project is not the only one a serve writes to - it also
#     regenerates registered projects on the slow cadence - so "is it this repo's" is asked of
#     the server's OWN published project list, not of its cwd.
# Read-only throughout, and it never signals anything. The server's ui directory is taken from
# its argv rather than spelled here, which is also what keeps this file's literal count of
# host-tool paths at the zero the vendor-coupling manifest records for it. Every failure to read
# - no `ps`, no `jq`, an unreadable or unparseable index - yields NO pid, so the exemption is
# simply not granted and the assertion stays as absolute as it was before this change.
live_floor_regen_pids() {
  local repo="$1" snapshot
  [ -n "$repo" ] || return 0
  # The snapshot is taken into a variable BEFORE the awk that filters it, so that awk's own
  # argv - which carries the string being searched for - cannot appear in its own input.
  snapshot="$(ps -eo pid=,command= 2>/dev/null || true)"
  [ -n "$snapshot" ] || return 0
  printf '%s\n' "$snapshot" \
    | awk '
        index($0, "setup-ui.sh") == 0 { next }
        # The served config is handed to the HTTP engine on its command line, and the ui
        # directory is the argument immediately after the bare `-` that feeds the engine on
        # stdin. Positional-from-the-front only as far as that marker: later arguments can be
        # EMPTY (an unset --registry is passed as ""), and `ps` collapses an empty argument, so
        # counting fields past this point would silently read the wrong one.
        { for (i = 2; i < NF; i++) if ($i == "-") { print $1 "\t" $(i + 1); break } }' \
    | while IFS="$(printf '\t')" read -r pid uidir; do
        case "$pid" in ''|*[!0-9]*) continue ;; esac
        [ -n "$uidir" ] || continue
        [ -f "$uidir/index.json" ] || continue
        jq -e --arg p "$repo" '
          (.serve.regen == true)
          and ((.serve.selected_path == $p) or ([.projects[]?.path] | index($p) != null))
        ' "$uidir/index.json" >/dev/null 2>&1 || continue
        printf '%s\n' "$pid"
      done
  return 0
}
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
  # The agents surface's source is the PLUGIN directory, not a .supervisor/ one, so the mirror
  # needs its own link or run_build's FLOOR_AGENTS_DIR export resolves to nothing here. What
  # this buys is a corroboration against the REAL agent files' CONTENT (via cmp_real below) -
  # NOT a test of the `$0`-derived default path, which the export short-circuits either way.
  [ -d "$HERE/../agents" ] && ln -s "$HERE/../agents" "$MIR/agents"
  REALFLOOR="$REAL/.supervisor/floor"
  # The SUBJECT IS THE DIRECTORY, not the single artefact it holds. A serve owns `floor.json`
  # inside it and nothing else, so hashing the directory is what leaves the attribution below
  # something to still be absolute ABOUT: any other file, directory or symlink appearing here
  # is a containment breach whatever any server is doing.
  real_before="$(floor_dir_sig "$REALFLOOR")"
  run_build "$MIR"; rcM=$?
  JM="$MIR/.supervisor/floor/floor.json"
  real_after="$(floor_dir_sig "$REALFLOOR")"
  [ "$rcM" -eq 0 ] && [ -f "$JM" ] && ok "real-tree mirror: exits 0 and writes the artefact" \
    || no "real-tree mirror: rc=$rcM, artefact $( [ -f "$JM" ] && echo present || echo absent )"
  # Reported either way - never a silently-vanishing assertion.
  if [ "$real_before" = "$real_after" ]; then
    ok "the developer checkout is byte-unchanged by this corroboration"
  else
    printf '%s\n' "$real_before" > "$ROOT/real-floor-before" 2>/dev/null
    printf '%s\n' "$real_after"  > "$ROOT/real-floor-after"  2>/dev/null
    m_live_pids="$(live_floor_regen_pids "$REAL" | tr '\n' ' ' | sed 's/ *$//')"
    m_live=no; [ -n "$m_live_pids" ] && m_live=yes
    m_verdict="$(classify_real_floor_delta "$ROOT/real-floor-before" "$ROOT/real-floor-after" "$m_live")"
    case "$m_verdict" in
      SERVE*)
        ok "the developer checkout changed ONLY in what a LIVE Floor regenerating this project owns (pid(s): $m_live_pids), so no write here is attributable to this corroboration -$(printf '%s' "${m_verdict#SERVE}"). With no such server running these same paths would have reddened, and every other path in that directory is still absolute" ;;
      *)
        no "the corroboration wrote into the developer checkout: these paths changed and no live Floor regenerating this project owns them -$(printf '%s' "${m_verdict#DIRTY}")
     (live Floor regenerating $REAL: $m_live${m_live_pids:+ - pid(s) $m_live_pids})
$(diff "$ROOT/real-floor-before" "$ROOT/real-floor-after" 2>/dev/null | head -20)" ;;
    esac
  fi

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
  cmp_real agents           "$(real_n "$HERE"/../agents/*.md)"
  cmp_real postmortem       "$(awk 'NF{n++} END{print n+0}' "$REAL/.supervisor/postmortem/results.jsonl" 2>/dev/null)"

  real_sessions="$(cat "$REAL"/.supervisor/logs/*.jsonl 2>/dev/null \
    | jq -r 'select(has("cc_session_id")) | .cc_session_id' 2>/dev/null | LC_ALL=C sort -u | awk 'NF{n++} END{print n+0}')"
  cmp_real sessions "$real_sessions"
  validate_floor "$JM" >/dev/null 2>&1 \
    && ok "the real-tree artefact conforms to the schema parsed from RESULT_SCHEMAS.md" \
    || no "the real-tree artefact failed schema validation: $(validate_floor "$JM" 2>&1 | head -3)"
fi

# ============================================================================
echo "== (m1)-(m8) the controls for that attribution =="
# An exemption that is never tested is a hole with a comment over it. These run UNCONDITIONALLY
# - outside the skip above - because the assertion they control is the one that skips, and CI is
# exactly where a classifier bug would otherwise go unexamined. Nothing here reads or writes the
# developer's tree: (m1)-(m5) drive the classifier on SYNTHETIC signatures, which is the only
# way to test a "somebody wrote into the checkout" case without doing it.
M_A="$ROOT/m-sig-a"; M_B="$ROOT/m-sig-b"
{ printf 'NONFILE  .\n'; printf 'AAA  ./floor.json\n'; } > "$M_A"

# (m1) THE ONE THAT MATTERS MOST: proof the narrowing did not blind the backstop. A path a serve
# does not own must redden even while a serve is live.
{ cat "$M_A"; printf 'BBB  ./stray.json\n'; } > "$M_B"
m_c="$(classify_real_floor_delta "$M_A" "$M_B" yes)"
case "$m_c" in
  DIRTY*./stray.json*)
    ok "(m1) CONTROL: with a live Floor running, a path the serve does not own is still DIRTY - the exemption covers the serve's own artefact and nothing else" ;;
  *)
    no "(m1) CONTROL: a foreign path is still DIRTY while a Floor is live" \
       "classifier returned '$m_c' - the narrowing is swallowing writes it must never swallow" ;;
esac

# (m2) the serve's OWN artefact, with NO live serve. Must stay DIRTY: the exemption is earned by
# evidence that a server is running, never granted to a path list.
sed 's|^AAA  \./floor\.json$|ZZZ  ./floor.json|' "$M_A" > "$M_B"
m_c="$(classify_real_floor_delta "$M_A" "$M_B" no)"
case "$m_c" in
  DIRTY*./floor.json*)
    ok "(m2) CONTROL: with NO live Floor, a change to floor.json is DIRTY - so CI, a fresh clone and a stopped Floor all keep the absolute backstop" ;;
  *)
    no "(m2) CONTROL: floor.json is still DIRTY when no Floor is live" \
       "classifier returned '$m_c' - the path alone is granting the exemption" ;;
esac

# (m3) the defect itself: the SAME change with a live serve is attributed, not reported.
m_c="$(classify_real_floor_delta "$M_A" "$M_B" yes)"
case "$m_c" in
  SERVE*./floor.json*)
    ok "(m3) CONTROL: the same change WITH a live Floor is attributed to it - this is the false positive that made this assertion unpassable for anyone actually running the Floor on this repo" ;;
  *)
    no "(m3) CONTROL: serve-owned churn under a live Floor is attributed to the serve" "classifier returned '$m_c'" ;;
esac

# (m4) MIXED - the case a per-path exemption is most likely to get wrong. A write hiding among
# genuine server churn must still redden, and must name ONLY the write.
{ sed 's|^AAA  \./floor\.json$|ZZZ  ./floor.json|' "$M_A"; printf 'BBB  ./stray.json\n'; } > "$M_B"
m_c="$(classify_real_floor_delta "$M_A" "$M_B" yes)"
case "$m_c" in
  DIRTY*./stray.json*)
    case "$m_c" in
      *floor.json*) no "(m4) CONTROL: a mixed delta reddens and names only the unattributable path" \
                       "it named the serve's own floor.json too: '$m_c'" ;;
      *) ok "(m4) CONTROL: a write hidden among live-Floor churn still reddens, and the report names ONLY the unattributable path - the server's noise cannot cover a write" ;;
    esac ;;
  *)
    no "(m4) CONTROL: a write mixed with live-Floor churn still reddens" "classifier returned '$m_c'" ;;
esac

# (m5) the ABSENT -> present transition, with no live serve. `floor_dir_sig` reports an absent
# directory as a VALUE, and this is what that buys: a corroboration that CREATES the directory
# in a checkout that had none is a change, not an untested state.
printf 'ABSENT\n' > "$M_B"
m_c="$(classify_real_floor_delta "$M_B" "$M_A" no)"
case "$m_c" in
  DIRTY*ABSENT*|DIRTY*floor.json*)
    ok "(m5) CONTROL: a directory that did not exist before and does after is DIRTY with no live Floor - ABSENT is a value, so the absent case is compared rather than skipped" ;;
  *)
    no "(m5) CONTROL: an ABSENT -> present transition is a change" "classifier returned '$m_c'" ;;
esac

# --- (m6)-(m8) THE OTHER HALF: the EVIDENCE that grants the exemption -------------------
# (m1)-(m5) are handed the live/not-live answer. Nothing above tests what PRODUCES it, and that
# is the only input that can grant the exemption wrongly: if live_floor_regen_pids called a
# server that does not regenerate this repo "a live Floor", the narrowing would apply on a
# machine where nothing writes here at all - silently reopening the hole (m2) keeps shut.
# ONE live process, three states of its published index, so each arm differs in exactly the
# clause it is about. `sleep` is BACKGROUNDED behind a trap rather than run in the foreground:
# non-interactive bash defers a signal until the foreground child it is waiting on finishes, so
# a plain `sleep` here would make the kill below block this suite for the whole duration.
MDET="$(mktmp)"; mkdir -p "$MDET/plugin" "$MDET/ui"
printf '#!/usr/bin/env bash\nsleep 30 & c=$!\ntrap "kill $c 2>/dev/null; exit 0" TERM INT\nwait\n' \
  > "$MDET/plugin/setup-ui.sh"
M_REPO="$MDET/some-project"
# argv shaped the way `serve` hands its config to the HTTP engine: the bare `-` then the ui dir.
bash "$MDET/plugin/setup-ui.sh" - "$MDET/ui" 7734 "$MDET/plugin/setup-ui.sh" "" "$MDET" "$M_REPO" X-Floor-Token &
m_pid=$!

# (m6) no published index at all - a ui directory a server has not written yet.
m_out="$(live_floor_regen_pids "$M_REPO")"
[ -z "$m_out" ] \
  && ok "(m6) CONTROL: a live server with no published index yields no live Floor - the evidence is what the server SAYS it regenerates, never merely that a process exists" \
  || no "(m6) CONTROL: a server with no index is not read as regenerating this repo" "live_floor_regen_pids returned '$m_out'"

# (m7) an index that does not list this repo - THE REGISTRATION CLAUSE. A Floor serving somebody
# else's project is live, and must excuse nothing here.
printf '{"serve":{"regen":true,"selected_path":"/somewhere/else"},"projects":[{"path":"/somewhere/else"}]}\n' \
  > "$MDET/ui/index.json"
m_out="$(live_floor_regen_pids "$M_REPO")"
[ -z "$m_out" ] \
  && ok "(m7) CONTROL: a live Floor that regenerates a DIFFERENT project yields nothing for this one - the exemption is repo-scoped, not machine-scoped" \
  || no "(m7) CONTROL: a Floor serving another project does not excuse a change here" "live_floor_regen_pids returned '$m_out'"

# (m7b) the same server, listing this repo, but started --no-regen: it serves the copy already
# in its ui dir and writes into no project at all.
printf '{"serve":{"regen":false,"selected_path":"%s"},"projects":[{"path":"%s"}]}\n' "$M_REPO" "$M_REPO" \
  > "$MDET/ui/index.json"
m_out="$(live_floor_regen_pids "$M_REPO")"
[ -z "$m_out" ] \
  && ok "(m7b) CONTROL: a --no-regen Floor yields nothing even for a project it lists - a server that regenerates nothing cannot have written this artefact" \
  || no "(m7b) CONTROL: a --no-regen Floor grants no exemption" "live_floor_regen_pids returned '$m_out'"

# (m8) ANTI-VACUITY, and it is not optional: (m6), (m7) and (m7b) are all satisfied perfectly by
# a detector that returns NOTHING, ever - which would leave this assertion permanently red for
# the very people the change is for. This is the arm that proves it discriminates.
printf '{"serve":{"regen":true,"selected_path":"/elsewhere"},"projects":[{"path":"/elsewhere"},{"path":"%s"}]}\n' "$M_REPO" \
  > "$MDET/ui/index.json"
m_wait=0; m_out=""
while [ "$m_wait" -lt 20 ]; do
  m_out="$(live_floor_regen_pids "$M_REPO")"
  [ -n "$m_out" ] && break
  sleep 0.25; m_wait=$((m_wait + 1))
done
[ "$m_out" = "$m_pid" ] \
  && ok "(m8) ANTI-VACUITY: a live server whose published index lists this repo as one it regenerates IS reported (pid $m_pid) - and it is listed as a REGISTERED project, not the selected one, which is the arm a cwd-only test would have missed" \
  || no "(m8) ANTI-VACUITY: a live Floor regenerating this repo is reported" \
       "live_floor_regen_pids returned '$m_out', wanted '$m_pid' - the detector never fires, so the exemption could never be granted and this assertion is unpassable under a live Floor again"
kill "$m_pid" 2>/dev/null; wait "$m_pid" 2>/dev/null

# ============================================================================
echo "== (x) runtime bound - the multi-scan regression cannot return silently =="
# WHY THIS CASE EXISTS, and why it is shaped the way it is.
#
# The detail readers this suite commissions ((r)-(v)) shipped 4.1x SLOWER than the surface
# they extended: 0.85s -> 3.5s on the maintainer tree, because each new reader re-walked
# ledgers an existing pass had already walked. That is load-bearing, not cosmetic:
# `setup-ui.sh serve` regenerates on a 2-SECOND default interval, so the loop had begun
# taking longer than its own tick, and requirement 06 pins its whole scheduling design on
# the measured sub-second figure. It passed 338 assertions and seven repo gates in silence.
# THAT silence is the defect this case closes - not the timing number itself.
#
# Two shapes were rejected before this one:
#
#   1. Timing the SMALL fixtures. Redundant scans of a 4-line ledger cost nothing measurable
#      -- `jq` process startup dominates entirely -- so a small-fixture bound would have gone
#      green straight through the very 4x regression it was written to catch. Vacuous.
#   2. An ABSOLUTE wall-clock ceiling. CI hardware is slower and noisier than a laptop, so
#      any ceiling tight enough to catch a 4x regression here would flake there, and any
#      ceiling loose enough to survive CI would not catch it. Unusable either way.
#
# So the bound is a RATIO against a real artefact: commit 2b41286, the last commit that
# still had the multi-scan readers. Both versions run on the SAME synthesized input on the
# SAME machine in the same test run, so a slow or loaded runner slows BOTH and the ratio
# holds -- the guard is hardware-independent by construction. And the control is not a
# hand-built mutant that might not represent anything: it IS the slow code, so this
# assertion has demonstrably been red, in production, on the commit it names.
#
# The input is synthesized (~800 ledger lines), never the real tree, so the measurement does
# not drift as `.supervisor/` grows.
PERF_PRE_SHA="2b41286"
PERF_MIN_RATIO_X10=20        # historical arm: require >= 2.0x; integer tenths (bash 3.2 has no floats)
PERF_MAX_UNITS=180           # primary arm: see the calibration note below

# ---------------------------------------------------------------------------
# PRIMARY ARM - a CALIBRATED bound that needs NO git history, so it runs on CI.
#
# The first version of this case had only the historical arm below, and it was wrong in the
# way that matters: `2b41286` is a BRANCH commit, so `actions/checkout` (depth 1) cannot
# reach it and the entire case degraded to SKIPPED on CI - permanently so once this branch
# squash-merges. A regression bound that runs only on the author's laptop is the
# "a claim no check backs" class this repo keeps recording. So the arm that must always run
# is measured against a UNIT calibrated in the same run:
#
#   unit  = wall time for ONE full `jq` scan of the synthesized ledger
#   bound = projector wall time / unit
#
# Both numbers move with the machine, so a slow or loaded runner cancels out - exactly what
# an absolute millisecond ceiling cannot do. Measured on the maintainer tree: the
# bound sits at 180. These are wall-clock figures and therefore NOISY: across repeated runs on
# this machine the consolidated readers measured 93-109 units and the pre-consolidation code
# 266-313. The bound sits above the top of the first range and well below the bottom of the
# second, which is the property that matters; quoting one exact pair here would claim a
# precision this measurement does not have.
#
# Counting `jq` INVOCATIONS was tried first and REJECTED after measuring - 37 now versus 35
# then. The regression was work done per invocation, not process count, so that gate would
# have gone green straight through it. A second vacuous bound, avoided only by measuring
# instead of assuming.
# ---------------------------------------------------------------------------
RPERF="$(new_repo)"
mkdir -p "$RPERF/.supervisor/postmortem" "$RPERF/.agent/rules" "$RPERF/agents"
cp "$RULES_FIXTURE_DIR"/*.json "$RPERF/.agent/rules/" 2>/dev/null
: > "$RPERF/.supervisor/postmortem/results.jsonl"
iperf=0
while [ "$iperf" -lt 200 ]; do cat "$PM_FIXTURE" >> "$RPERF/.supervisor/postmortem/results.jsonl"; iperf=$((iperf+1)); done
perf_lines="$(awk 'NF{n++} END{print n+0}' "$RPERF/.supervisor/postmortem/results.jsonl")"

perf_units="$(python3 - "$RPERF" "$BUILD" 2>/dev/null <<'__PY1__'
import subprocess, sys, time, os
repo, script = sys.argv[1], sys.argv[2]
led = repo + "/.supervisor/postmortem/results.jsonl"
env = dict(os.environ); env["FLOOR_AGENTS_DIR"] = repo + "/agents"

def best(fn, n=3):
    return min(fn() for _ in range(n))

def unit():
    t = time.time()
    subprocess.run(["jq", "-s", "[.[]|.categories]|length", led],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return time.time() - t

def run():
    t = time.time()
    subprocess.run(["bash", script], cwd=repo, env=env,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return time.time() - t

u = best(unit)
if u <= 0:
    print("ERR")
else:
    print(int(best(run) / u))
__PY1__
)"
case "$perf_units" in
  ''|*[!0-9]*) no "(x) could not calibrate the runtime bound (got '$perf_units') - PRIMARY arm inconclusive" ;;
  *)
    if [ "$perf_units" -le "$PERF_MAX_UNITS" ]; then
      ok "(x) PRIMARY: the projector costs $perf_units calibrated units on $perf_lines ledger lines, within the $PERF_MAX_UNITS bound (1 unit = one full jq scan measured in this same run, so the machine cancels out)"
    else
      no "(x) RUNTIME REGRESSION: $perf_units calibrated units on $perf_lines ledger lines, over the $PERF_MAX_UNITS bound - a reader is re-walking an input an earlier pass already read"
    fi ;;
esac

# ---------------------------------------------------------------------------
# HISTORICAL ARM - a direct A/B against the real pre-consolidation code, when git history
# reaches it. Strictly a BONUS: it is the strongest control available (the control IS the
# slow code, not a hand-built mutant that might represent nothing), but it cannot run on a
# shallow clone, which is why it is no longer the only arm.
# ---------------------------------------------------------------------------
perf_pre="$ROOT/build-floor-preperf.sh"
if git -C "$HERE/../.." cat-file -e "$PERF_PRE_SHA:loomwright/scripts/build-floor.sh" 2>/dev/null \
   && git -C "$HERE/../.." show "$PERF_PRE_SHA:loomwright/scripts/build-floor.sh" > "$perf_pre" 2>/dev/null \
   && [ -s "$perf_pre" ] && bash -n "$perf_pre" 2>/dev/null; then

  perf_ms() {
    python3 - "$1" "$2" <<'__PY2__'
import subprocess, sys, time, os
script, cwd = sys.argv[1], sys.argv[2]
env = dict(os.environ); env["FLOOR_AGENTS_DIR"] = cwd + "/agents"
best = None
for _ in range(3):
    t = time.time()
    subprocess.run(["bash", script], cwd=cwd, env=env,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    d = int((time.time() - t) * 1000)
    best = d if best is None else min(best, d)
print(best)
__PY2__
  }

  ms_now="$(perf_ms "$BUILD" "$RPERF")"
  ms_pre="$(perf_ms "$perf_pre" "$RPERF")"

  case "$ms_now$ms_pre" in
    ''|*[!0-9]*) no "(x) HISTORICAL: could not measure (now='$ms_now' pre='$ms_pre') - inconclusive" ;;
    *)
      if [ "$ms_now" -le 0 ]; then
        no "(x) HISTORICAL: the current script measured ${ms_now}ms - too fast to ratio, inconclusive"
      else
        ratio_x10=$(( ms_pre * 10 / ms_now ))
        if [ "$ratio_x10" -ge "$PERF_MIN_RATIO_X10" ]; then
          ok "(x) HISTORICAL: ${ratio_x10}/10x faster than $PERF_PRE_SHA's multi-scan readers (${ms_now}ms vs ${ms_pre}ms), at or above the required ${PERF_MIN_RATIO_X10}/10x"
        else
          no "(x) HISTORICAL REGRESSION: only ${ratio_x10}/10x faster than $PERF_PRE_SHA (${ms_now}ms vs ${ms_pre}ms), below the required ${PERF_MIN_RATIO_X10}/10x"
        fi
        if [ "$ms_pre" -gt "$ms_now" ]; then
          ok "(x) ANTI-VACUITY: the $PERF_PRE_SHA control is measurably slower here (${ms_pre}ms > ${ms_now}ms), so the ratio compares two different implementations"
        else
          no "(x) ANTI-VACUITY FAILED: control ${ms_pre}ms vs HEAD ${ms_now}ms - the control is not slow, so the ratio proves nothing"
        fi
      fi ;;
  esac
else
  skipn "(x) HISTORICAL arm: commit $PERF_PRE_SHA is unreachable (shallow clone / post-squash-merge). The PRIMARY calibrated arm above still ran - which is precisely why it exists"
fi

# ============================================================================
echo "== (y) curation faults: rendered by the page, driven by nothing until now =="
# `self_referential`, `duplicate_ids` and `files_not_an_array` are jq-computed AND rendered in
# floor.js, and until this fixture existed NO committed input produced any of them: 0 rules with
# supersedes == .id, 0 repeated ids, 0 non-array files. The single prior `files_not_an_array`
# occurrence in this suite is the DETAIL_SUBKEYS doc-key list, which asserts the schema documents
# the key - not that anything ever emits it. Three rendered branches with no driving input, in a
# PR whose own narrative is "a stale fixture kept the suite green".
CURATION_FIXTURE_DIR="$HERE/fixtures/floor-rules-curation"
[ -d "$CURATION_FIXTURE_DIR" ] || { echo "test-build-floor: committed fixture $CURATION_FIXTURE_DIR missing" >&2; exit 1; }
RCUR="$(new_repo)"; mkdir -p "$RCUR/.agent/rules" "$RCUR/agents"
cp "$AGENTS_FIXTURE_DIR"/*.md "$RCUR/agents/" 2>/dev/null
cp "$CURATION_FIXTURE_DIR"/*.json "$RCUR/.agent/rules/"
run_build "$RCUR"; JCUR="$RCUR/.supervisor/floor/floor.json"

[ "$(jq -r '[.surfaces.rules.detail.supersedes.self_referential[]?] | length' "$JCUR" 2>/dev/null)" = "1" ] \
  && ok "(y) a rule whose supersedes names its own id is reported as self_referential" \
  || no "(y) self_referential: $(jq -c '.surfaces.rules.detail.supersedes.self_referential' "$JCUR" 2>/dev/null)"
[ "$(jq -r '[.surfaces.rules.detail.supersedes.duplicate_ids[]?] | length' "$JCUR" 2>/dev/null)" = "1" ] \
  && ok "(y) an id appearing twice in the merged store is reported as a duplicate" \
  || no "(y) duplicate_ids: $(jq -c '.surfaces.rules.detail.supersedes.duplicate_ids' "$JCUR" 2>/dev/null)"
[ "$(jq -r '[.surfaces.rules.detail.files_not_an_array[]?] | length' "$JCUR" 2>/dev/null)" = "1" ] \
  && ok "(y) a file that parses but is not an array is NAMED, not folded into unparseable" \
  || no "(y) files_not_an_array: $(jq -c '.surfaces.rules.detail.files_not_an_array' "$JCUR" 2>/dev/null)"

# read_completeness must count "parsed but not understood" against completeness. Keying only on
# UNPARSEABLE files reported "all" beside a file the projector had just refused to read - the
# examined-and-clean claim this projection exists to never make.
[ "$(jq -r '.surfaces.rules.detail.read_completeness' "$JCUR" 2>/dev/null)" = "partial" ] \
  && ok "(y) a store holding one usable and one not-an-array file reads PARTIAL, never all" \
  || no "(y) read_completeness with a not-an-array file: $(jq -r '.surfaces.rules.detail.read_completeness' "$JCUR" 2>/dev/null)"
RONLY="$(new_repo)"; mkdir -p "$RONLY/.agent/rules" "$RONLY/agents"
cp "$AGENTS_FIXTURE_DIR"/*.md "$RONLY/agents/" 2>/dev/null
cp "$CURATION_FIXTURE_DIR/notarray.json" "$RONLY/.agent/rules/"
run_build "$RONLY"
[ "$(jq -r '.surfaces.rules.detail.read_completeness' "$RONLY/.supervisor/floor/floor.json" 2>/dev/null)" = "none" ] \
  && ok "(y) a store whose only file is not an array reads NONE - nothing usable was read" \
  || no "(y) read_completeness with only a not-an-array file: $(jq -r '.surfaces.rules.detail.read_completeness' "$RONLY/.supervisor/floor/floor.json" 2>/dev/null)"

# MUTATION CONTROL: revert read_completeness to keying on $badfiles alone and require the
# PARTIAL assertion above to go red - otherwise it is a restatement of current behaviour.
MUTY="$ROOT/build-floor-completeness.sh"
# NB the delimiter: the pattern is full of jq pipes, so `s|...|...|` would terminate early.
sed 's@(($badfiles . length) + ($notarray . length)) == 0@($badfiles | length) == 0@' "$BUILD" > "$MUTY" 2>/dev/null
if [ -s "$MUTY" ] && ! cmp -s "$MUTY" "$BUILD" && bash -n "$MUTY" 2>/dev/null; then
  RMUT="$(new_repo)"; mkdir -p "$RMUT/.agent/rules" "$RMUT/agents"
  cp "$CURATION_FIXTURE_DIR"/*.json "$RMUT/.agent/rules/"
  ( cd "$RMUT" && FLOOR_AGENTS_DIR="$RMUT/agents" bash "$MUTY" >/dev/null 2>&1 )
  [ "$(jq -r '.surfaces.rules.detail.read_completeness' "$RMUT/.supervisor/floor/floor.json" 2>/dev/null)" = "all" ] \
    && ok "(y2) MUTATION CONTROL: keying completeness on unparseable-only DOES report the banned 'all' - the assertion discriminates" \
    || no "(y2) MUTATION CONTROL: the reverted computation did not report 'all' - (y) proves nothing"
else
  no "(y2) MUTATION CONTROL: could not build the completeness mutant - control inconclusive"
fi

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
exit 0
