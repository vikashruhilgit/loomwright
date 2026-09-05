#!/usr/bin/env bash
# test-seed-run-owner.sh — offline self-tests for seed-run-owner.sh, the
# PostToolUse[Write|Edit] run-owner seed.
#
# DETERMINISTIC, NO LIVE SIDE EFFECTS. Every case runs inside a mktemp sandbox
# that is a REAL git repo (init'd per-case) — the SUT resolves the MAIN checkout
# via `git worktree list --porcelain`, so a real repo is required to exercise the
# actual code path rather than a stand-in. The real repo's own `.supervisor/` is
# snapshotted and asserted untouched (same convention as
# test-close-stranded-run.sh / test-progress-state.sh).
#
# Cases:
#   1.  a Write to the main worktree's `.supervisor/state.md` on a NON-TERMINAL
#       run seeds `<run_id>.owner` with the payload session id, the run id, and
#       a strict UTC ISO-8601 `started_at`
#   2.  WRITE-ONCE — a second firing under a DIFFERENT session never rewrites an
#       existing seed (a run's owner cannot change under it)
#   3.  a Write to any OTHER path seeds nothing (the trigger is the run's own
#       state file, not "some file was written")
#   4.  a TERMINAL run seeds nothing
#   5.  no `state.md` seeds nothing, and creates no directories
#   6.  a log whose FIRST LINE already records an owner seeds nothing — the
#       established owner is never contradicted
#   7.  control for 6: a log whose first line carries NO `cc_session_id` (the
#       `/autonomous` `autonomous_session_start` shape) IS seeded — without this
#       the case-6 guard could be a blanket "any log at all suppresses"
#   8.  degenerate inputs all exit 0 and write nothing: empty stdin, a
#       functionally-broken jq, no `session_id` in the payload, not a git repo
#   9.  a hostile `session_id` is sanitised to `[A-Za-z0-9_-]` and cannot inject
#       an extra `key=value` line into the seed
#   10. a RELATIVE `file_path` is resolved against the payload's own `cwd`
#   11. PARITY — `loom_run_owner_seed` is byte-identical in the two consumers
#       (close-stranded-run.sh, build-state.sh), which their own headers claim
#
# EXIT: 0 on full pass, 1 on any failed assertion.
# Style mirrors test-close-stranded-run.sh.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$SCRIPT_DIR/seed-run-owner.sh"

if [ ! -f "$SUT" ]; then
  echo "FATAL  seed-run-owner.sh not found: $SUT" >&2
  exit 1
fi
for c in jq git bash; do
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "FATAL  $c required to run this suite" >&2
    exit 1
  fi
done

PASS_COUNT=0
FAIL_COUNT=0
ok() { echo "  ok: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
no() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"; else no "$label  expected='$expected' actual='$actual'"; fi
}

# Snapshot the real repo's .supervisor — must be untouched by this suite.
REAL_SUP="$REPO_ROOT/.supervisor"
snapshot_real() {
  if [ -d "$REAL_SUP" ]; then
    find "$REAL_SUP" -type f 2>/dev/null | sort | cksum
  else
    echo "supervisor:ABSENT"
  fi
}
REAL_BEFORE="$(snapshot_real)"

REALBASH="$(command -v bash)"
CLEANUP_DIRS=()
cleanup() {
  local d
  for d in "${CLEANUP_DIRS[@]:-}"; do
    [ -n "$d" ] || continue
    chmod -R u+rwx "$d" 2>/dev/null || true
    rm -rf "$d" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# ---- helpers ----------------------------------------------------------------

init_repo() {
  # Creates a fresh git repo (one commit, branch $1) and echoes its absolute
  # path, canonicalized with `pwd -P` because macOS resolves /tmp through a
  # /private symlink — which would otherwise not byte-match what git reports.
  local branch="${1:-feature/seed-owner-test}"
  local d; d="$(mktemp -d)"
  d="$(cd "$d" && pwd -P)"
  CLEANUP_DIRS+=("$d")
  ( cd "$d" && git init -q . \
      && git config user.email test@example.com \
      && git config user.name test \
      && echo seed > seed.txt \
      && git add seed.txt \
      && git commit -qm init \
      && git branch -M "$branch" ) >/dev/null 2>&1
  printf '%s' "$d"
}

seed_state() {
  # Usage: seed_state <repo> <plugin-session-id> <status>
  # The status is REQUIRED positionally and has no default — a case must state
  # the status it asserts against, so no shared-fixture default can silently
  # satisfy the terminal/non-terminal distinction under test.
  local repo="$1" psid="$2" status="$3"
  mkdir -p "$repo/.supervisor"
  cat > "$repo/.supervisor/state.md" <<EOF
## Session
- session_id: $psid
- status: $status
- phase: INIT
- branch: feature/seed-owner-test
EOF
}

run_sut() {
  # Usage: run_sut <workdir> <cc-session-id-or---empty> <file_path>
  # Echoes the SUT's output, then RC=<n> on the last line.
  local wd="$1" sid="$2" fp="$3"
  local out rc payload
  if [ "$sid" = "--empty" ]; then
    out="$( cd "$wd" && "$REALBASH" "$SUT" </dev/null 2>&1 )"
  else
    if [ "$sid" = "--nosid" ]; then
      payload="$(jq -nc --arg fp "$fp" --arg cwd "$wd" \
        '{hook_event_name:"PostToolUse", tool_name:"Write", cwd:$cwd, tool_input:{file_path:$fp}}')"
    else
      payload="$(jq -nc --arg sid "$sid" --arg fp "$fp" --arg cwd "$wd" \
        '{session_id:$sid, hook_event_name:"PostToolUse", tool_name:"Write", cwd:$cwd, tool_input:{file_path:$fp}}')"
    fi
    # The `out=` assignment MUST remain the last command before `rc=$?`, or the
    # captured status becomes the payload builder's instead of the SUT's.
    out="$( cd "$wd" && printf '%s' "$payload" | "$REALBASH" "$SUT" 2>&1 )"
  fi
  rc=$?
  printf '%s\n' "$out"
  printf 'RC=%s\n' "$rc"
}

run_sut_brokenjq() {
  # Same contract as run_sut, but with a jq that is PRESENT and EXECUTABLE on
  # PATH and always fails — the case `command -v jq` structurally cannot see.
  local wd="$1" sid="$2" fp="$3"
  local bin; bin="$(mktemp -d)"
  CLEANUP_DIRS+=("$bin")
  printf '#!/bin/sh\nexit 1\n' > "$bin/jq"
  chmod +x "$bin/jq"
  local out rc payload
  payload="$(jq -nc --arg sid "$sid" --arg fp "$fp" --arg cwd "$wd" \
    '{session_id:$sid, hook_event_name:"PostToolUse", tool_name:"Write", cwd:$cwd, tool_input:{file_path:$fp}}')"
  out="$( cd "$wd" && printf '%s' "$payload" | PATH="$bin:$PATH" "$REALBASH" "$SUT" 2>&1 )"
  rc=$?
  printf '%s\n' "$out"
  printf 'RC=%s\n' "$rc"
}

get_rc() { printf '%s\n' "$1" | grep '^RC=' | tail -1 | cut -d= -f2; }
seed_val() { sed -nE "s/^$2=//p" "$1" 2>/dev/null | head -1; }
sup_snapshot() { find "$1/.supervisor" -type f 2>/dev/null | sort | xargs cksum 2>/dev/null | cksum; }

echo "== 1. Write of the run's state.md seeds the owner =="
REPO1="$(init_repo "feature/case1")"
seed_state "$REPO1" "auto-2026-09-05-050440" "running"
OUT1="$(run_sut "$REPO1" "cc-owner-1" "$REPO1/.supervisor/state.md")"
SEED1="$REPO1/.supervisor/logs/auto-2026-09-05-050440.owner"
assert_eq "case1 exit 0" "0" "$(get_rc "$OUT1")"
if [ -f "$SEED1" ]; then ok "case1 seed file created"; else no "case1 seed file NOT created"; fi
assert_eq "case1 cc_session_id is the payload's session id" "cc-owner-1" "$(seed_val "$SEED1" cc_session_id)"
assert_eq "case1 session_id is the run id state.md names" "auto-2026-09-05-050440" "$(seed_val "$SEED1" session_id)"
TS1="$(seed_val "$SEED1" started_at)"
case "$TS1" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ok "case1 started_at is a strict UTC ISO-8601 instant" ;;
  *) no "case1 started_at is not a strict UTC ISO-8601 instant: '$TS1'" ;;
esac
assert_eq "case1 seed is exactly three lines" "3" "$(wc -l < "$SEED1" | tr -d '[:space:]')"
if [ -e "$REPO1/.supervisor/logs/auto-2026-09-05-050440.jsonl" ]; then
  no "case1 fabricated a JSONL log — the seed is a sidecar, it must not touch the event stream"
else
  ok "case1 no JSONL log fabricated (sidecar only)"
fi

echo "== 2. WRITE-ONCE: a second, different session never rewrites the seed =="
OUT2="$(run_sut "$REPO1" "cc-someone-else-2" "$REPO1/.supervisor/state.md")"
assert_eq "case2 exit 0" "0" "$(get_rc "$OUT2")"
assert_eq "case2 owner is unchanged (write-once)" "cc-owner-1" "$(seed_val "$SEED1" cc_session_id)"
assert_eq "case2 started_at is unchanged" "$TS1" "$(seed_val "$SEED1" started_at)"
assert_eq "case2 seed is still exactly three lines (no append)" "3" "$(wc -l < "$SEED1" | tr -d '[:space:]')"

echo "== 3. a Write to some OTHER path seeds nothing =="
REPO3="$(init_repo "feature/case3")"
seed_state "$REPO3" "sid-case3" "running"
BEFORE3="$(sup_snapshot "$REPO3")"
OUT3="$(run_sut "$REPO3" "cc-owner-3" "$REPO3/README.md")"
assert_eq "case3 exit 0" "0" "$(get_rc "$OUT3")"
assert_eq "case3 .supervisor/ byte-unchanged" "$BEFORE3" "$(sup_snapshot "$REPO3")"
if [ -e "$REPO3/.supervisor/logs" ]; then no "case3 created a logs dir for an unrelated write"; else ok "case3 no seed for an unrelated write"; fi

echo "== 4. a TERMINAL run seeds nothing =="
for st in completed completed_with_escalation failed; do
  REPO4="$(init_repo "feature/case4-$st")"
  seed_state "$REPO4" "sid-case4" "$st"
  OUT4="$(run_sut "$REPO4" "cc-owner-4" "$REPO4/.supervisor/state.md")"
  assert_eq "case4($st) exit 0" "0" "$(get_rc "$OUT4")"
  if [ -e "$REPO4/.supervisor/logs/sid-case4.owner" ]; then
    no "case4($st) seeded an owner for a run that is already over"
  else
    ok "case4($st) no seed for a terminal run"
  fi
done

echo "== 5. no state.md -> no seed, no directories created =="
REPO5="$(init_repo "feature/case5")"
OUT5="$(run_sut "$REPO5" "cc-owner-5" "$REPO5/.supervisor/state.md")"
assert_eq "case5 exit 0" "0" "$(get_rc "$OUT5")"
if [ -e "$REPO5/.supervisor" ]; then no "case5 created .supervisor/ from nothing"; else ok "case5 no .supervisor/ created"; fi

echo "== 6. a log whose FIRST LINE already records an owner -> no seed =="
# The established owner (the rule both emitters and the close-out already apply)
# must never gain a second, possibly disagreeing answer — e.g. a
# `/supervisor --continue` resume under a different session, where the original
# owner is recorded and deliberately keeps the log.
REPO6="$(init_repo "feature/case6")"
seed_state "$REPO6" "sid-case6" "running"
mkdir -p "$REPO6/.supervisor/logs"
printf '{"event":"subtask_complete","session_id":"sid-case6","cc_session_id":"cc-original-owner"}\n' \
  > "$REPO6/.supervisor/logs/sid-case6.jsonl"
OUT6="$(run_sut "$REPO6" "cc-resumed-session-6" "$REPO6/.supervisor/state.md")"
assert_eq "case6 exit 0" "0" "$(get_rc "$OUT6")"
if [ -e "$REPO6/.supervisor/logs/sid-case6.owner" ]; then
  no "case6 contradicted an owner the log already records"
else
  ok "case6 an already-recorded owner is never contradicted"
fi

echo "== 7. control for 6: an OWNERLESS first line (the /autonomous shape) IS seeded =="
# Without this control, case 6 would also pass if the guard suppressed the seed
# whenever ANY log existed — which would silently disable the seed for exactly
# the runs it was built for: `/autonomous` appends `autonomous_session_start`
# (no `cc_session_id`) at INIT, BEFORE Supervisor creates state.md.
REPO7="$(init_repo "feature/case7")"
seed_state "$REPO7" "auto-2026-09-05-121712" "running"
mkdir -p "$REPO7/.supervisor/logs"
printf '{"ts":"2026-09-05T06:47:12Z","session_id":"auto-2026-09-05-121712","event":"autonomous_session_start","mode":"single"}\n' \
  > "$REPO7/.supervisor/logs/auto-2026-09-05-121712.jsonl"
OUT7="$(run_sut "$REPO7" "cc-owner-7" "$REPO7/.supervisor/state.md")"
assert_eq "case7 exit 0" "0" "$(get_rc "$OUT7")"
assert_eq "case7 an ownerless log line does NOT block the seed" "cc-owner-7" \
  "$(seed_val "$REPO7/.supervisor/logs/auto-2026-09-05-121712.owner" cc_session_id)"
assert_eq "case7 the existing log is left byte-identical (append-only, untouched)" "1" \
  "$(wc -l < "$REPO7/.supervisor/logs/auto-2026-09-05-121712.jsonl" | tr -d '[:space:]')"

echo "== 8. degenerate inputs -> exit 0, nothing written =="

echo "-- 8a. empty stdin --"
REPO8A="$(init_repo "feature/case8a")"
seed_state "$REPO8A" "sid-case8a" "running"
BEFORE8A="$(sup_snapshot "$REPO8A")"
OUT8A="$(run_sut "$REPO8A" --empty "")"
assert_eq "case8a exit 0" "0" "$(get_rc "$OUT8A")"
assert_eq "case8a .supervisor/ byte-unchanged" "$BEFORE8A" "$(sup_snapshot "$REPO8A")"

echo "-- 8b. functionally-broken jq --"
REPO8B="$(init_repo "feature/case8b")"
seed_state "$REPO8B" "sid-case8b" "running"
BEFORE8B="$(sup_snapshot "$REPO8B")"
OUT8B="$(run_sut_brokenjq "$REPO8B" "cc-owner-8b" "$REPO8B/.supervisor/state.md")"
assert_eq "case8b exit 0 with a broken jq" "0" "$(get_rc "$OUT8B")"
assert_eq "case8b .supervisor/ byte-unchanged (no payload fields readable)" "$BEFORE8B" "$(sup_snapshot "$REPO8B")"

echo "-- 8c. payload carries no session_id --"
# Load-bearing beyond "no id, no seed": the SUT reads its three fields out of one
# `@tsv` row, and an EMPTY MIDDLE FIELD is exactly where a tab-splitting `read`
# silently shifts `cwd` into the owner slot (tab is IFS whitespace, so runs of it
# collapse). This case caught that during development — it failed with a
# FABRICATED owner derived from a directory path.
REPO8C="$(init_repo "feature/case8c")"
seed_state "$REPO8C" "sid-case8c" "running"
OUT8C="$(run_sut "$REPO8C" --nosid "$REPO8C/.supervisor/state.md")"
assert_eq "case8c exit 0" "0" "$(get_rc "$OUT8C")"
if [ -e "$REPO8C/.supervisor/logs/sid-case8c.owner" ]; then
  no "case8c seeded an owner with no owner id to record"
else
  ok "case8c no seed when the payload names no session"
fi

echo "-- 8d. not a git repo --"
NOTAREPO="$(mktemp -d)"
CLEANUP_DIRS+=("$NOTAREPO")
NOTAREPO="$(cd "$NOTAREPO" && pwd -P)"
mkdir -p "$NOTAREPO/.supervisor"
cat > "$NOTAREPO/.supervisor/state.md" <<'EOF'
## Session
- session_id: sid-case8d
- status: running
EOF
OUT8D="$(run_sut "$NOTAREPO" "cc-owner-8d" "$NOTAREPO/.supervisor/state.md")"
assert_eq "case8d exit 0" "0" "$(get_rc "$OUT8D")"
if [ -e "$NOTAREPO/.supervisor/logs" ]; then
  no "case8d wrote outside a git repo"
else
  ok "case8d no side effects outside a git repo"
fi

echo "== 9. a hostile session_id is sanitised and cannot inject a key=value line =="
REPO9="$(init_repo "feature/case9")"
seed_state "$REPO9" "sid-case9" "running"
OUT9="$(run_sut "$REPO9" 'cc-evil
started_at=1999-01-01T00:00:00Z' "$REPO9/.supervisor/state.md")"
SEED9="$REPO9/.supervisor/logs/sid-case9.owner"
assert_eq "case9 exit 0" "0" "$(get_rc "$OUT9")"
assert_eq "case9 seed is still exactly three lines (no injected key)" "3" "$(wc -l < "$SEED9" | tr -d '[:space:]')"
# `@tsv` renders the embedded newline as the two characters `\` `n`, and the
# `tr -cd 'A-Za-z0-9_-'` sanitiser then drops the backslash and the `=`. Either
# way what lands is ONE value on ONE line — the point of the assertion is that
# no second `key=value` line can be manufactured, not the exact residue.
assert_eq "case9 the newline and '=' cannot survive into the recorded owner" "cc-evilnstarted_at1999-01-01T000000Z" \
  "$(seed_val "$SEED9" cc_session_id)"
STARTED9="$(seed_val "$SEED9" started_at)"
if [ "$STARTED9" = "1999-01-01T00:00:00Z" ]; then
  no "case9 an injected started_at won — the seed's staleness anchor is attacker-controlled"
else
  ok "case9 started_at is the real clock, not the injected value"
fi

echo "== 10. a RELATIVE file_path is resolved against the payload's own cwd =="
REPO10="$(init_repo "feature/case10")"
seed_state "$REPO10" "sid-case10" "running"
OUT10="$(run_sut "$REPO10" "cc-owner-10" ".supervisor/state.md")"
assert_eq "case10 exit 0" "0" "$(get_rc "$OUT10")"
assert_eq "case10 relative path still resolves to the run's state file" "cc-owner-10" \
  "$(seed_val "$REPO10/.supervisor/logs/sid-case10.owner" cc_session_id)"

echo "== 11. PARITY: loom_run_owner_seed is byte-identical in both consumers =="
# Both consumers' headers CLAIM the two copies are kept identical. A claim no
# check backs is how they drift: the two are the single ownership rule, and a
# close-out reading a different owner from the projector is precisely the
# false-attribution class this whole mechanism exists to remove.
extract_fn() {
  awk '/^loom_run_owner_seed\(\) \{/ {inside=1} inside {print} inside && /^\}/ {exit}' "$1" 2>/dev/null
}
FN_CLOSE="$(extract_fn "$SCRIPT_DIR/close-stranded-run.sh")"
FN_BUILD="$(extract_fn "$SCRIPT_DIR/build-state.sh")"
if [ -n "$FN_CLOSE" ]; then ok "case11 loom_run_owner_seed found in close-stranded-run.sh"; else no "case11 loom_run_owner_seed NOT found in close-stranded-run.sh"; fi
if [ -n "$FN_BUILD" ]; then ok "case11 loom_run_owner_seed found in build-state.sh"; else no "case11 loom_run_owner_seed NOT found in build-state.sh"; fi
assert_eq "case11 the two function bodies are byte-identical" "$FN_CLOSE" "$FN_BUILD"

echo "== real repo .supervisor untouched =="
assert_eq "real .supervisor snapshot unchanged" "$REAL_BEFORE" "$(snapshot_real)"

echo ""
echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
