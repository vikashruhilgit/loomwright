#!/usr/bin/env bash
# test-close-stranded-run.sh — offline self-tests for close-stranded-run.sh
# (2026-09-05 brief — "A run that ends must stop owning the log").
#
# DETERMINISTIC, NO LIVE SIDE EFFECTS. Every case runs inside a mktemp sandbox
# that is a REAL git repo (init'd per-case) — the SUT resolves the MAIN
# checkout via `git worktree list --porcelain`, so a real repo is required to
# exercise the actual code path rather than a stand-in. The real repo's own
# `.supervisor/` is snapshotted and asserted untouched (same convention as
# test-token-ledger.sh / test-progress-state.sh).
#
# Cases:
#   1.  owner + NON-TERMINAL state.md -> EXACTLY ONE session_end appended,
#       carrying BOTH the canonical `event` and the legacy `type` key (the
#       contract build-insights.sh filters on), status: failed,
#       reason: session_ended_without_completion — and state.md is TERMINAL
#       afterwards (AC-4)
#   1b. re-running against the now-terminal state.md appends nothing — the
#       "exactly one" guarantee under repeat firing
#   2.  NON-OWNER session -> writes nothing, exits 0 (AC-5)
#   3.  ALREADY-TERMINAL state.md -> writes nothing, exits 0 (AC-5)
#   4.  degenerate inputs all exit 0 (AC-8): absent state.md, unreadable
#       state.md, not-a-git-repo cwd, empty stdin (unknown owner ⇒ ADOPT),
#       functionally-broken jq, unreadable log, malformed first log line
#   5.  the run-creation seed (`<run_id>.owner`) makes ownership knowable before
#       the first log line exists — a SLUG-KEYED run stranded in that window now
#       closes out for its own session (5a) and still for NO ONE else (5b), with
#       the seed isolated as the authorising fact (5c) and taking precedence over
#       a foreign first log line (5d) without becoming a blanket suppression (5e)
#
# EXIT: 0 on full pass, 1 on any failed assertion.
# Style mirrors test-progress-state.sh / test-token-ledger.sh.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$SCRIPT_DIR/close-stranded-run.sh"

if [ ! -f "$SUT" ]; then
  echo "FATAL  close-stranded-run.sh not found: $SUT" >&2
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
  # path. Canonicalized with `pwd -P` because macOS resolves /tmp through a
  # /private symlink, which would otherwise not byte-match what git reports.
  local branch="${1:-feature/close-stranded-test}"
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
  # The status is REQUIRED positionally and has no default: a case must state
  # the status it is asserting against, so no shared-fixture default can
  # silently satisfy the terminal/non-terminal distinction under test.
  local repo="$1" psid="$2" status="$3"
  mkdir -p "$repo/.supervisor"
  cat > "$repo/.supervisor/state.md" <<EOF
## Session
- session_id: $psid
- status: $status
- phase: EXECUTE
- branch: feature/close-stranded-test
EOF
}

seed_run_owner() {
  # Usage: seed_run_owner <repo> <plugin-session-id> <owner-cc-session-id> [started_at]
  # Writes the run-creation seed `seed-run-owner.sh` produces at `initialize`.
  # `started_at` is REQUIRED to be stated by any case that depends on it and
  # defaults only to "now" — the close-out never reads it (that is the
  # projector's staleness anchor), so no assertion in THIS file rests on it.
  local repo="$1" psid="$2" owner="$3"
  local started="${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  mkdir -p "$repo/.supervisor/logs"
  printf 'cc_session_id=%s\nsession_id=%s\nstarted_at=%s\n' \
    "$owner" "$psid" "$started" > "$repo/.supervisor/logs/${psid}.owner"
}

seed_owned_log() {
  # Usage: seed_owned_log <repo> <plugin-session-id> <owner-cc-session-id>
  # One line whose FIRST (and only) line records the owner of the run.
  local repo="$1" psid="$2" owner="$3"
  mkdir -p "$repo/.supervisor/logs"
  printf '{"event":"subtask_complete","type":"subtask_complete","session_id":"%s","cc_session_id":"%s"}\n' \
    "$psid" "$owner" > "$repo/.supervisor/logs/${psid}.jsonl"
}

run_sut() {
  # Usage: run_sut <workdir> <session-id-or---empty> [reason]
  # Echoes the SUT's output, then RC=<n> on the last line.
  #
  # The third positional is OPTIONAL and adds a `reason` field to the
  # SessionEnd payload. It is OMITTED when not passed — every pre-existing
  # caller keeps its exact two-argument behaviour, byte for byte, and that is
  # load-bearing rather than incidental: the SUT's `clear` guard is a
  # DENY-LIST, so a payload carrying NO `reason` must still take the main
  # close-out path. If this helper ever acquired a default reason, the
  # no-reason population — which is what every other case in this file
  # exercises — would stop being tested at all.
  local wd="$1" sid="$2" reason="${3:-}"
  local out rc payload
  if [ "$sid" = "--empty" ]; then
    out="$( cd "$wd" && "$REALBASH" "$SUT" </dev/null 2>&1 )"
  else
    if [ -n "$reason" ]; then
      payload="$(printf '{"session_id":"%s","hook_event_name":"SessionEnd","reason":"%s"}' "$sid" "$reason")"
    else
      payload="$(printf '{"session_id":"%s","hook_event_name":"SessionEnd"}' "$sid")"
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
  local wd="$1" sid="$2"
  local bin; bin="$(mktemp -d)"
  CLEANUP_DIRS+=("$bin")
  printf '#!/bin/sh\nexit 1\n' > "$bin/jq"
  chmod +x "$bin/jq"
  local out rc
  out="$( cd "$wd" && printf '{"session_id":"%s","hook_event_name":"SessionEnd"}' "$sid" \
          | PATH="$bin:$PATH" "$REALBASH" "$SUT" 2>&1 )"
  rc=$?
  printf '%s\n' "$out"
  printf 'RC=%s\n' "$rc"
}

get_rc() { printf '%s\n' "$1" | grep '^RC=' | tail -1 | cut -d= -f2; }
count_lines() { wc -l < "$1" 2>/dev/null | tr -d '[:space:]'; }
sup_snapshot() { find "$1/.supervisor" -type f 2>/dev/null | sort | xargs cksum 2>/dev/null | cksum; }

echo "== 1. owner + non-terminal state.md -> exactly ONE session_end, state.md terminal =="
REPO1="$(init_repo "feature/case1")"
seed_owned_log "$REPO1" "sid-case1" "cc-owner-1"
seed_state "$REPO1" "sid-case1" "running"
LOG1="$REPO1/.supervisor/logs/sid-case1.jsonl"
OUT1="$(run_sut "$REPO1" "cc-owner-1")"
assert_eq "case1 exit 0" "0" "$(get_rc "$OUT1")"
assert_eq "case1 log grew by exactly one line" "2" "$(count_lines "$LOG1")"
assert_eq "case1 exactly ONE session_end record in the log" "1" \
  "$(jq -R -r 'fromjson? | select((.event // "") == "session_end") | .event' "$LOG1" 2>/dev/null | wc -l | tr -d '[:space:]')"
LINE1="$(tail -1 "$LOG1")"
assert_eq "case1 canonical .event key" "session_end" "$(printf '%s' "$LINE1" | jq -r '.event // empty')"
assert_eq "case1 legacy .type key (build-insights.sh filters on it)" "session_end" \
  "$(printf '%s' "$LINE1" | jq -r '.type // empty')"
assert_eq "case1 status" "failed" "$(printf '%s' "$LINE1" | jq -r '.status // empty')"
assert_eq "case1 reason" "session_ended_without_completion" "$(printf '%s' "$LINE1" | jq -r '.reason // empty')"
assert_eq "case1 session_id is the run's plugin sid" "sid-case1" "$(printf '%s' "$LINE1" | jq -r '.session_id // empty')"
assert_eq "case1 cc_session_id is the ending CC session" "cc-owner-1" "$(printf '%s' "$LINE1" | jq -r '.cc_session_id // empty')"
assert_eq "case1 state.md is TERMINAL afterwards" "failed" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO1/.supervisor/state.md" 2>/dev/null)"
assert_eq "case1 state.md phase" "LOOP" \
  "$(sed -nE 's/^- phase:[[:space:]]*//p' "$REPO1/.supervisor/state.md" 2>/dev/null)"

echo "== 1b. re-run against the now-terminal state.md appends nothing =="
OUT1B="$(run_sut "$REPO1" "cc-owner-1")"
assert_eq "case1b exit 0" "0" "$(get_rc "$OUT1B")"
assert_eq "case1b no second session_end appended" "2" "$(count_lines "$LOG1")"

echo "== 2. non-owner session -> writes nothing, exits 0 =="
REPO2="$(init_repo "feature/case2")"
seed_owned_log "$REPO2" "sid-case2" "cc-owner-2"
seed_state "$REPO2" "sid-case2" "running"
BEFORE2="$(sup_snapshot "$REPO2")"
OUT2="$(run_sut "$REPO2" "cc-foreign-2")"
assert_eq "case2 exit 0" "0" "$(get_rc "$OUT2")"
assert_eq "case2 .supervisor/ byte-unchanged (nothing written)" "$BEFORE2" "$(sup_snapshot "$REPO2")"
assert_eq "case2 owned log line count unchanged" "1" "$(count_lines "$REPO2/.supervisor/logs/sid-case2.jsonl")"
assert_eq "case2 state.md left non-terminal (someone else's run is still in flight)" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO2/.supervisor/state.md" 2>/dev/null)"

echo "== 3. already-terminal state.md -> writes nothing, exits 0 =="
REPO3="$(init_repo "feature/case3")"
seed_owned_log "$REPO3" "sid-case3" "cc-owner-3"
seed_state "$REPO3" "sid-case3" "completed"
BEFORE3="$(sup_snapshot "$REPO3")"
OUT3="$(run_sut "$REPO3" "cc-owner-3")"
assert_eq "case3 exit 0" "0" "$(get_rc "$OUT3")"
assert_eq "case3 .supervisor/ byte-unchanged (nothing written)" "$BEFORE3" "$(sup_snapshot "$REPO3")"
assert_eq "case3 log line count unchanged" "1" "$(count_lines "$REPO3/.supervisor/logs/sid-case3.jsonl")"
assert_eq "case3 state.md still completed" "completed" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO3/.supervisor/state.md" 2>/dev/null)"

echo "== 4. degenerate inputs -> exit 0 (AC-8) =="

echo "-- 4a. absent state.md --"
REPO4A="$(init_repo "feature/case4a")"
OUT4A="$(run_sut "$REPO4A" "cc-any-4a")"
assert_eq "case4a exit 0" "0" "$(get_rc "$OUT4A")"
if [ -e "$REPO4A/.supervisor" ]; then
  no "case4a created .supervisor/ from nothing"
else
  ok "case4a no .supervisor/ created (no state.md, nothing to close)"
fi

echo "-- 4b. unreadable state.md --"
REPO4B="$(init_repo "feature/case4b")"
seed_owned_log "$REPO4B" "sid-case4b" "cc-owner-4b"
seed_state "$REPO4B" "sid-case4b" "running"
chmod 000 "$REPO4B/.supervisor/state.md" 2>/dev/null || true
OUT4B="$(run_sut "$REPO4B" "cc-owner-4b")"
assert_eq "case4b exit 0" "0" "$(get_rc "$OUT4B")"
chmod 644 "$REPO4B/.supervisor/state.md" 2>/dev/null || true
assert_eq "case4b log untouched when state.md cannot be read" "1" \
  "$(count_lines "$REPO4B/.supervisor/logs/sid-case4b.jsonl")"

echo "-- 4c. not a git repo --"
NOTAREPO="$(mktemp -d)"
CLEANUP_DIRS+=("$NOTAREPO")
NOTAREPO="$(cd "$NOTAREPO" && pwd -P)"
OUT4C="$(run_sut "$NOTAREPO" "cc-any-4c")"
assert_eq "case4c exit 0" "0" "$(get_rc "$OUT4C")"
if [ -e "$NOTAREPO/.supervisor" ]; then
  no "case4c created .supervisor/ outside a git repo"
else
  ok "case4c no side effects outside a git repo"
fi

echo "-- 4d. empty stdin + unknown owner -> WITHHOLD (cannot identify itself as the run) --"
# CHANGED BEHAVIOUR (see 4n for the defect this closes): an empty payload
# yields no `session_id`, so this session cannot show it is the run `state.md`
# names. With no owner recorded there is nothing else to check against, so it
# writes nothing rather than closing out a run that may be someone else's and
# still live. The rule is now uniform: a session that cannot identify itself
# never closes a run out, whether the owner is known (Honest limit 8) or not.
REPO4D="$(init_repo "feature/case4d")"
seed_state "$REPO4D" "sid-case4d" "running"
mkdir -p "$REPO4D/.supervisor/logs"
BEFORE4D="$(sup_snapshot "$REPO4D")"
OUT4D="$(run_sut "$REPO4D" --empty)"
assert_eq "case4d exit 0" "0" "$(get_rc "$OUT4D")"
LOG4D="$REPO4D/.supervisor/logs/sid-case4d.jsonl"
assert_eq "case4d .supervisor/ byte-unchanged (nothing written)" "$BEFORE4D" "$(sup_snapshot "$REPO4D")"
if [ -e "$LOG4D" ]; then
  no "case4d created a log for a run it cannot identify itself as"
else
  ok "case4d no log created — an unidentifiable session writes NOTHING"
fi
assert_eq "case4d state.md is left non-terminal for the real owner to close" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO4D/.supervisor/state.md" 2>/dev/null)"

echo "-- 4e. functionally-broken jq --"
REPO4E="$(init_repo "feature/case4e")"
seed_owned_log "$REPO4E" "sid-case4e" "cc-owner-4e"
seed_state "$REPO4E" "sid-case4e" "running"
OUT4E="$(run_sut_brokenjq "$REPO4E" "cc-owner-4e")"
assert_eq "case4e exit 0 with a broken jq" "0" "$(get_rc "$OUT4E")"
# CHANGED BEHAVIOUR: a broken jq yields NEITHER the log owner NOR the payload
# `session_id`, so this session has zero identity information and cannot show
# it is the run. It therefore withholds, exactly like 4d/4n. Consistent rather
# than special-cased: the ownership rule, the emitters' gate and the staleness
# backstop are all jq-dependent, so a jq-less host has already lost the ability
# to attribute anything — inventing a `failed` there would be the one
# unrecoverable move available to it. Still exits 0 (AC-8 unchanged).
assert_eq "case4e broken jq WITHHOLDS — log untouched" "1" \
  "$(count_lines "$REPO4E/.supervisor/logs/sid-case4e.jsonl")"
assert_eq "case4e state.md left non-terminal" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO4E/.supervisor/state.md" 2>/dev/null)"

echo "-- 4f. unreadable log --"
REPO4F="$(init_repo "feature/case4f")"
seed_owned_log "$REPO4F" "sid-case4f" "cc-owner-4f"
seed_state "$REPO4F" "sid-case4f" "running"
LOG4F="$REPO4F/.supervisor/logs/sid-case4f.jsonl"
chmod 000 "$LOG4F" 2>/dev/null || true
OUT4F="$(run_sut "$REPO4F" "cc-owner-4f")"
assert_eq "case4f exit 0" "0" "$(get_rc "$OUT4F")"
chmod 644 "$LOG4F" 2>/dev/null || true
assert_eq "case4f unreadable log left untouched" "1" "$(count_lines "$LOG4F")"

echo "-- 4g. malformed first log line --"
REPO4G="$(init_repo "feature/case4g")"
mkdir -p "$REPO4G/.supervisor/logs"
printf 'not { valid json\n' > "$REPO4G/.supervisor/logs/sid-case4g.jsonl"
seed_state "$REPO4G" "sid-case4g" "running"
OUT4G="$(run_sut "$REPO4G" "cc-any-4g")"
assert_eq "case4g exit 0" "0" "$(get_rc "$OUT4G")"
# CHANGED BEHAVIOUR: a malformed first line means the owner is UNKNOWN, and
# the payload here (`cc-any-4g`) is not the run id `state.md` names, so this is
# the 4n hole in another costume — an unrelated session closing out a run whose
# ownership it cannot establish. It withholds. Case 4m is the control proving
# the unknown-owner path still closes for the run's OWN session.
assert_eq "case4g malformed first line + unrelated session WITHHOLDS" "1" \
  "$(count_lines "$REPO4G/.supervisor/logs/sid-case4g.jsonl")"
assert_eq "case4g state.md left non-terminal" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO4G/.supervisor/state.md" 2>/dev/null)"

echo "-- 4h. log already CLOSED: the tail guard skips a second session_end --"
# The guard must be positive-form checked (skip) AND controlled (still appends
# when the tail is NOT a session_end), or a mutation that deletes it passes.
REPO4H="$(init_repo "feature/case4h")"
seed_owned_log "$REPO4H" "sid-case4h" "cc-owner-4h"
LOG4H="$REPO4H/.supervisor/logs/sid-case4h.jsonl"
printf '{"event":"session_end","type":"session_end","session_id":"sid-case4h","status":"failed"}\n' >> "$LOG4H"
seed_state "$REPO4H" "sid-case4h" "running"
OUT4H="$(run_sut "$REPO4H" "cc-owner-4h")"
assert_eq "case4h exit 0" "0" "$(get_rc "$OUT4H")"
assert_eq "case4h already-closed log gets NO second session_end (stays at 2 lines)" "2" \
  "$(count_lines "$LOG4H")"

echo "-- 4i. control for 4h: a trailing NON-terminal line still appends --"
REPO4I="$(init_repo "feature/case4i")"
seed_owned_log "$REPO4I" "sid-case4i" "cc-owner-4i"
LOG4I="$REPO4I/.supervisor/logs/sid-case4i.jsonl"
printf '{"event":"subtask_complete","type":"subtask_complete","session_id":"sid-case4i"}\n' >> "$LOG4I"
seed_state "$REPO4I" "sid-case4i" "running"
OUT4I="$(run_sut "$REPO4I" "cc-owner-4i")"
assert_eq "case4i exit 0" "0" "$(get_rc "$OUT4I")"
assert_eq "case4i non-terminal tail still appends (guard is not blanket suppression)" "3" \
  "$(count_lines "$LOG4I")"
assert_eq "case4i appended record is a session_end" "session_end" \
  "$(tail -1 "$LOG4I" | jq -r '.event // empty')"

echo "-- 4j. empty stdin + KNOWN owner -> writes nothing (documented gap) --"
# Pairs empty/unparseable stdin with a KNOWN owner, which case 4d does NOT:
# 4d has an UNKNOWN owner, so the adopt-on-unknown-owner rule rescues it. Here
# the owner IS recorded, so the non-owner branch is taken with an empty
# CC_SESSION_ID and the run stays stranded. That is deliberate — we cannot
# prove ownership, and wrongly closing a LIVE run owned by another session is
# worse than leaving a stranded one for the staleness backstop. This case
# pins the behaviour so a future change to the ownership branch has to
# confront it rather than alter it silently. See docs/TELEMETRY.md
# §"Honest limits" entry 8.
REPO4J="$(init_repo "feature/case4j")"
seed_owned_log "$REPO4J" "sid-case4j" "cc-owner-4j"
seed_state "$REPO4J" "sid-case4j" "running"
LOG4J="$REPO4J/.supervisor/logs/sid-case4j.jsonl"
OUT4J="$(run_sut "$REPO4J" --empty)"
assert_eq "case4j exit 0" "0" "$(get_rc "$OUT4J")"
assert_eq "case4j empty stdin + KNOWN owner appends nothing (stays stranded)" "1" \
  "$(count_lines "$LOG4J")"
assert_eq "case4j state.md left non-terminal (ownership unproven)" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO4J/.supervisor/state.md" 2>/dev/null)"

echo "-- 4k. reason=clear against a LIVE owned run -> no-op --"
# `/clear` keeps the SAME cc_session_id, so every other condition in the SUT
# is satisfied: non-terminal state.md, matching owner. Only the reason guard
# stops the write. Delete that guard and this case appends a `failed`
# session_end to a run that is still executing.
REPO4K="$(init_repo "feature/case4k")"
seed_owned_log "$REPO4K" "sid-case4k" "cc-owner-4k"
seed_state "$REPO4K" "sid-case4k" "running"
LOG4K="$REPO4K/.supervisor/logs/sid-case4k.jsonl"
OUT4K="$(run_sut "$REPO4K" "cc-owner-4k" "clear")"
assert_eq "case4k exit 0" "0" "$(get_rc "$OUT4K")"
assert_eq "case4k /clear appends nothing to a live owned log" "1" \
  "$(count_lines "$LOG4K")"
assert_eq "case4k /clear leaves state.md non-terminal" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO4K/.supervisor/state.md" 2>/dev/null)"

echo "-- 4l. control for 4k: reason=logout still closes out normally --"
# Without this control, 4k would also pass if the guard suppressed EVERY
# payload that carries a reason at all — a blanket break dressed as a fix.
REPO4L="$(init_repo "feature/case4l")"
seed_owned_log "$REPO4L" "sid-case4l" "cc-owner-4l"
seed_state "$REPO4L" "sid-case4l" "running"
LOG4L="$REPO4L/.supervisor/logs/sid-case4l.jsonl"
OUT4L="$(run_sut "$REPO4L" "cc-owner-4l" "logout")"
assert_eq "case4l exit 0" "0" "$(get_rc "$OUT4L")"
assert_eq "case4l reason=logout still appends exactly one session_end" "2" \
  "$(count_lines "$LOG4L")"
assert_eq "case4l appended record is a session_end" "session_end" \
  "$(tail -1 "$LOG4L" | jq -r '.event // empty')"
assert_eq "case4l state.md reaches a terminal status" "failed" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO4L/.supervisor/state.md" 2>/dev/null)"

echo "-- 4m. unknown owner + the run's OWN session -> still closes out --"
# The preserved half of the unknown-owner path. `state.md` session ids come in
# two shapes on disk — a CC uuid AND a plugin slug (`auto-…`, `…-supervisor`) —
# so this cannot be asserted only for uuids: for a run keyed by the session's
# own id, the owning session CAN identify itself and must still close the run
# out with no log present. Without this case, 4n would also pass if the guard
# had simply disabled the unknown-owner path outright.
REPO4M="$(init_repo "feature/case4m")"
seed_state "$REPO4M" "sid-case4m" "running"
mkdir -p "$REPO4M/.supervisor/logs"
OUT4M="$(run_sut "$REPO4M" "sid-case4m")"
assert_eq "case4m exit 0" "0" "$(get_rc "$OUT4M")"
LOG4M="$REPO4M/.supervisor/logs/sid-case4m.jsonl"
assert_eq "case4m the run's own session DOES close it out" "1" "$(count_lines "$LOG4M")"
assert_eq "case4m appended record is a session_end" "session_end" \
  "$(tail -1 "$LOG4M" | jq -r '.event // empty')"
assert_eq "case4m status" "failed" "$(tail -1 "$LOG4M" | jq -r '.status // empty')"
assert_eq "case4m state.md reaches a terminal status" "failed" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO4M/.supervisor/state.md" 2>/dev/null)"

echo "-- 4n. unknown owner + an UNRELATED session -> WITHHOLD (the false close-out) --"
# THE DEFECT. `.supervisor/state.md` is repo-global, so session A can start a
# run (status running, id sid-case4n) and, before A's first worker completion
# creates the log, an entirely unrelated session B simply ENDING would satisfy
# every remaining condition and stamp `failed` onto A's LIVE run — leaving a
# fabricated hard-signal session_end that nothing retracts. B cannot identify
# itself as sid-case4n, so it must now write nothing.
REPO4N="$(init_repo "feature/case4n")"
seed_state "$REPO4N" "sid-case4n" "running"
mkdir -p "$REPO4N/.supervisor/logs"
BEFORE4N="$(sup_snapshot "$REPO4N")"
OUT4N="$(run_sut "$REPO4N" "cc-unrelated-session-4n")"
assert_eq "case4n exit 0" "0" "$(get_rc "$OUT4N")"
LOG4N="$REPO4N/.supervisor/logs/sid-case4n.jsonl"
assert_eq "case4n .supervisor/ byte-unchanged (nothing written)" "$BEFORE4N" "$(sup_snapshot "$REPO4N")"
if [ -e "$LOG4N" ]; then
  no "case4n an unrelated session fabricated a log for someone else's live run"
else
  ok "case4n an unrelated session writes NOTHING into the run's log"
fi
assert_eq "case4n the live run is NOT marked failed" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO4N/.supervisor/state.md" 2>/dev/null)"

echo "-- 4o. log EXISTS but its first line records no owner + unrelated session --"
# The second shape of "unknown owner": events exist, but the first line carries
# no `cc_session_id`, so `loom_log_owner` yields nothing. 4n alone would pass a
# guard that only handled the absent-log case, so this pins the other variant
# of the same hole.
REPO4O="$(init_repo "feature/case4o")"
seed_state "$REPO4O" "sid-case4o" "running"
mkdir -p "$REPO4O/.supervisor/logs"
LOG4O="$REPO4O/.supervisor/logs/sid-case4o.jsonl"
printf '{"event":"subtask_complete","type":"subtask_complete","session_id":"sid-case4o"}\n' > "$LOG4O"
OUT4O="$(run_sut "$REPO4O" "cc-unrelated-session-4o")"
assert_eq "case4o exit 0" "0" "$(get_rc "$OUT4O")"
assert_eq "case4o ownerless log is not adoptable by an unrelated session" "1" \
  "$(count_lines "$LOG4O")"
assert_eq "case4o the live run is NOT marked failed" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO4O/.supervisor/state.md" 2>/dev/null)"

echo "== 5. the run-creation seed makes ownership knowable BEFORE the first event =="
# `.supervisor/logs/<run_id>.owner` is written by seed-run-owner.sh when
# `state.md` is created. Every case here uses a SLUG-KEYED run id, because that
# is the population the seed exists for: a `SessionEnd` payload always carries
# the real Claude Code uuid, so the unknown-owner self-identification test
# (payload session_id == the run id) is STRUCTURALLY unsatisfiable for a
# synthetic `auto-…` id, and 4m's path can never rescue these runs.

echo "-- 5a. slug-keyed run, no log, seed names THIS session -> closes out --"
# The capability this change exists to add. Before the seed, this exact
# situation (`auto-…` run stranded between `initialize` and its first worker)
# could not reach a terminal status by any path.
REPO5A="$(init_repo "feature/case5a")"
seed_state "$REPO5A" "auto-2026-09-05-050440" "running"
seed_run_owner "$REPO5A" "auto-2026-09-05-050440" "cc-owner-5a"
OUT5A="$(run_sut "$REPO5A" "cc-owner-5a")"
LOG5A="$REPO5A/.supervisor/logs/auto-2026-09-05-050440.jsonl"
assert_eq "case5a exit 0" "0" "$(get_rc "$OUT5A")"
assert_eq "case5a the seeded owner closes out a slug-keyed run with no log" "1" "$(count_lines "$LOG5A")"
assert_eq "case5a appended record is a session_end" "session_end" "$(tail -1 "$LOG5A" | jq -r '.event // empty')"
assert_eq "case5a status" "failed" "$(tail -1 "$LOG5A" | jq -r '.status // empty')"
assert_eq "case5a state.md reaches a terminal status" "failed" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO5A/.supervisor/state.md" 2>/dev/null)"

echo "-- 5b. THE REGRESSION THAT MATTERS: an unrelated session still writes nothing --"
# Identical to 5a except for WHO is ending. The seed must make the owner
# knowable WITHOUT making the run closable by anyone else — that is the defect
# 4n pins for the ownerless case, and the seed must not reopen it.
REPO5B="$(init_repo "feature/case5b")"
seed_state "$REPO5B" "auto-2026-09-05-050441" "running"
seed_run_owner "$REPO5B" "auto-2026-09-05-050441" "cc-owner-5b"
BEFORE5B="$(sup_snapshot "$REPO5B")"
OUT5B="$(run_sut "$REPO5B" "cc-unrelated-session-5b")"
LOG5B="$REPO5B/.supervisor/logs/auto-2026-09-05-050441.jsonl"
assert_eq "case5b exit 0" "0" "$(get_rc "$OUT5B")"
assert_eq "case5b .supervisor/ byte-unchanged (nothing written)" "$BEFORE5B" "$(sup_snapshot "$REPO5B")"
if [ -e "$LOG5B" ]; then
  no "case5b an unrelated session closed out a run the seed says it does not own"
else
  ok "case5b an unrelated session writes NOTHING into a seeded run's log"
fi
assert_eq "case5b the live run is NOT marked failed" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO5B/.supervisor/state.md" 2>/dev/null)"

echo "-- 5c. control for 5a: WITHOUT the seed the same session writes nothing --"
# Without this control, 5a would also pass under a guard that had simply gone
# back to closing out any slug-keyed run for anyone — it isolates the seed as
# the thing that authorised 5a, rather than a loosened ownership rule.
REPO5C="$(init_repo "feature/case5c")"
seed_state "$REPO5C" "auto-2026-09-05-050442" "running"
mkdir -p "$REPO5C/.supervisor/logs"
OUT5C="$(run_sut "$REPO5C" "cc-owner-5c")"
assert_eq "case5c exit 0" "0" "$(get_rc "$OUT5C")"
if [ -e "$REPO5C/.supervisor/logs/auto-2026-09-05-050442.jsonl" ]; then
  no "case5c a slug-keyed run with NO seed was closed out — the seed is not what authorised 5a"
else
  ok "case5c no seed, no close-out (the seed is what authorises 5a)"
fi
assert_eq "case5c state.md left non-terminal" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO5C/.supervisor/state.md" 2>/dev/null)"

echo "-- 5d. seed BEATS a foreign first log line -> the foreign session writes nothing --"
# The divergence the precedence exists for. While the owner is unknown the
# emitters ADOPT (deliberately — the fresh-run bootstrap), so a FOREIGN
# session's first worker completion can land as the log's first line and make
# that session look like the owner. The seed was recorded earlier and by the
# session that created the run, so it wins.
REPO5D="$(init_repo "feature/case5d")"
seed_state "$REPO5D" "auto-2026-09-05-050443" "running"
seed_run_owner "$REPO5D" "auto-2026-09-05-050443" "cc-true-owner-5d"
seed_owned_log "$REPO5D" "auto-2026-09-05-050443" "cc-foreign-first-appender"
LOG5D="$REPO5D/.supervisor/logs/auto-2026-09-05-050443.jsonl"
OUT5D="$(run_sut "$REPO5D" "cc-foreign-first-appender")"
assert_eq "case5d exit 0" "0" "$(get_rc "$OUT5D")"
assert_eq "case5d a foreign first-line appender does NOT own the run" "1" "$(count_lines "$LOG5D")"
assert_eq "case5d the live run is NOT marked failed" "running" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO5D/.supervisor/state.md" 2>/dev/null)"

echo "-- 5e. control for 5d: the SEEDED owner still closes that same run out --"
# Without this control, 5d would also pass if the seed simply disabled close-out
# whenever a log's first line disagreed with it.
OUT5E="$(run_sut "$REPO5D" "cc-true-owner-5d")"
assert_eq "case5e exit 0" "0" "$(get_rc "$OUT5E")"
assert_eq "case5e the seeded owner appends exactly one session_end" "2" "$(count_lines "$LOG5D")"
assert_eq "case5e appended record is a session_end" "session_end" "$(tail -1 "$LOG5D" | jq -r '.event // empty')"
assert_eq "case5e state.md reaches a terminal status" "failed" \
  "$(sed -nE 's/^- status:[[:space:]]*//p' "$REPO5D/.supervisor/state.md" 2>/dev/null)"

echo "== real repo .supervisor untouched =="
assert_eq "real .supervisor snapshot unchanged" "$REAL_BEFORE" "$(snapshot_real)"

echo ""
echo "RESULT  pass=$PASS_COUNT  fail=$FAIL_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
