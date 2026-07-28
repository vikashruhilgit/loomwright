#!/usr/bin/env bash
# test-reconcile-resume-state.sh — self-test for the resume ground-truth reconciler.
#
# The load-bearing test is REGRESSION 1: it reproduces the 2026-07-27 incident shape (state.md
# schema-valid but claiming PENDING for subtasks git proves are committed) and asserts STALE.
# That case MUST fail before the reconciler exists and pass after.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SUT="$SCRIPT_DIR/reconcile-resume-state.sh"
PASS=0; FAIL=0
TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t reconcile)
trap 'rm -rf "$TMPROOT"' EXIT

ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n       expected %s, got %s\n' "$1" "$2" "$3"; }

# assert_verdict <name> <expected_verdict> <expected_exit> <state_file> <repo>
assert_verdict() {
  _name="$1"; _ev="$2"; _ex="$3"; _sf="$4"; _repo="$5"
  _out=$(bash "$SUT" "$_sf" "$_repo" 2>&1); _rc=$?
  _v=$(printf '%s\n' "$_out" | sed -n 's/^VERDICT: //p' | head -1)
  if [ "$_v" = "$_ev" ] && [ "$_rc" = "$_ex" ]; then
    ok "$_name"
  else
    bad "$_name" "$_ev/exit $_ex" "$_v/exit $_rc"
  fi
}

# --- Build a repo whose git history proves subtasks 1-3 are committed ---------------------------
REPO="$TMPROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t
git -C "$REPO" commit -q --allow-empty -m "base"
git -C "$REPO" checkout -q -b feature/thing
for i in 1 2 3; do
  git -C "$REPO" commit -q --allow-empty -m "subtask: $i — thing $i"
  git -C "$REPO" commit -q --allow-empty -m "merge: subtask $i — thing $i"
done

mkstate() { # mkstate <file> <branch> <rows...>
  _f="$1"; _b="$2"; shift 2
  {
    printf '## Session\n- session_id: s\n- status: running\n- phase: ACQUIRE\n'
    [ -n "$_b" ] && printf -- '- branch: %s\n' "$_b"
    printf '\n## Subtasks\n| # | Title | Status |\n|---|---|---|\n'
    for _r in "$@"; do printf '%s\n' "$_r"; done
  } > "$_f"
}

printf '\n=== REGRESSION: the 2026-07-27 incident shape ===\n'
mkstate "$TMPROOT/incident.md" feature/thing \
  '| 1 | thing 1 | PENDING |' '| 2 | thing 2 | PENDING |' '| 3 | thing 3 | PENDING |'
assert_verdict "all subtasks PENDING but committed => STALE" STALE 3 "$TMPROOT/incident.md" "$REPO"

_out=$(bash "$SUT" "$TMPROOT/incident.md" "$REPO" 2>&1)
if printf '%s' "$_out" | grep -q 'under_reported: 3'; then
  ok "reports the exact count of under-reported subtasks"
else
  bad "reports the exact count" "under_reported: 3" "$(printf '%s' "$_out" | tr '\n' ' ')"
fi
if printf '%s' "$_out" | grep -q 'stale_subtask: id=2 state_says=PENDING'; then
  ok "names each divergent subtask with both claims"
else
  bad "names each divergent subtask" "stale_subtask: id=2 …" "$(printf '%s' "$_out" | tr '\n' ' ')"
fi

printf '\n=== CLEAN paths ===\n'
mkstate "$TMPROOT/clean.md" feature/thing \
  '| 1 | thing 1 | DONE |' '| 2 | thing 2 | DONE |' '| 3 | thing 3 | DONE |'
assert_verdict "state agrees with git => CLEAN" CLEAN 0 "$TMPROOT/clean.md" "$REPO"

mkstate "$TMPROOT/partial.md" feature/thing \
  '| 1 | thing 1 | DONE |' '| 2 | thing 2 | DONE |' '| 3 | thing 3 | DONE |' '| 4 | thing 4 | PENDING |'
assert_verdict "genuinely-pending subtask with no commit => CLEAN" CLEAN 0 "$TMPROOT/partial.md" "$REPO"

mkstate "$TMPROOT/terminal.md" feature/thing '| 1 | thing 1 | FAILED |' '| 2 | thing 2 | SKIPPED |'
assert_verdict "FAILED/SKIPPED are terminal, not under-reporting" CLEAN 0 "$TMPROOT/terminal.md" "$REPO"

# REGRESSION (real-world format, 2026-07-27): Supervisor annotates the status rather than writing a
# bare keyword. An exact-match terminal check flagged every completed subtask as under-reported,
# refusing legitimate resumes. Caught only by running against a live state file, not a fixture.
mkstate "$TMPROOT/annotated.md" feature/thing \
  '| 1 | thing 1 | DONE (review PASS) |' '| 2 | thing 2 | DONE (review PASS) |' \
  '| 3 | thing 3 | DONE (review PASS) |'
assert_verdict "annotated 'DONE (review PASS)' is terminal" CLEAN 0 "$TMPROOT/annotated.md" "$REPO"

mkstate "$TMPROOT/escal.md" feature/thing '| 1 | thing 1 | COMPLETED WITH ESCALATION |'
assert_verdict "multi-word terminal status is terminal" CLEAN 0 "$TMPROOT/escal.md" "$REPO"

# The annotation must not swallow a genuine claim of incompleteness.
mkstate "$TMPROOT/annot_pending.md" feature/thing '| 1 | thing 1 | PENDING (blocked on 2) |'
assert_verdict "annotated PENDING still detected as under-reported" STALE 3 "$TMPROOT/annot_pending.md" "$REPO"

assert_verdict "missing state file is the start-fresh path => CLEAN" CLEAN 0 "$TMPROOT/nope.md" "$REPO"

printf '## Session\n- status: running\n- branch: feature/thing\n' > "$TMPROOT/nosubs.md"
assert_verdict "no ## Subtasks section => CLEAN" CLEAN 0 "$TMPROOT/nosubs.md" "$REPO"

mkstate "$TMPROOT/nobranch.md" "" '| 1 | thing 1 | PENDING |'
assert_verdict "no branch asserted => CLEAN (no ground truth)" CLEAN 0 "$TMPROOT/nobranch.md" "$REPO"

printf '\n=== FAIL-CLOSED paths (must be UNKNOWN, never CLEAN) ===\n'
mkstate "$TMPROOT/ghost.md" feature/does-not-exist '| 1 | thing 1 | PENDING |'
assert_verdict "unresolvable branch => UNKNOWN" UNKNOWN 4 "$TMPROOT/ghost.md" "$REPO"

mkstate "$TMPROOT/evil.md" 'feature/../../etc' '| 1 | x | PENDING |'
assert_verdict "ref-format-invalid branch => UNKNOWN" UNKNOWN 4 "$TMPROOT/evil.md" "$REPO"

mkdir -p "$TMPROOT/notgit"
mkstate "$TMPROOT/nogit.md" feature/thing '| 1 | thing 1 | PENDING |'
assert_verdict "non-git repo root => UNKNOWN" UNKNOWN 4 "$TMPROOT/nogit.md" "$TMPROOT/notgit"

_out=$(bash "$SUT" 2>&1); _rc=$?
if [ "$_rc" = "4" ]; then ok "no argument => UNKNOWN (fail closed)"; else bad "no argument" "exit 4" "exit $_rc"; fi

printf '\n=== MERGE-ONLY REACHABILITY (regression: the merge arm was dead code) ===\n'
# A squash merge or a rebased history leaves ONLY the merge subject. The original single-pattern
# extraction required a literal `subtask:` token after `merge: `, which the MANDATED merge format
# (async-orchestration/SKILL.md:120-122 `merge: {subtask_id} {title}`) does not contain — so these
# branches returned CLEAN and the resume re-executed merged work. Fixtures hid it by always
# including a plain `subtask:` commit too; these cases deliberately do not.
MREPO="$TMPROOT/mergeonly"
mkdir -p "$MREPO"
git -C "$MREPO" init -q 2>/dev/null
git -C "$MREPO" config user.email t@t.t
git -C "$MREPO" config user.name t
git -C "$MREPO" commit -q --allow-empty -m "base"
git -C "$MREPO" checkout -q -b feat
git -C "$MREPO" commit -q --allow-empty -m "merge: 7 implement thing seven"
git -C "$MREPO" commit -q --allow-empty -m "merge: subtask 8 — thing eight"

mkstate "$TMPROOT/mandated.md" feat '| 7 | thing seven | PENDING |'
assert_verdict "mandated 'merge: {id} {title}' alone => STALE" STALE 3 "$TMPROOT/mandated.md" "$MREPO"

mkstate "$TMPROOT/observed.md" feat '| 8 | thing eight | PENDING |'
assert_verdict "observed 'merge: subtask {id}' alone => STALE" STALE 3 "$TMPROOT/observed.md" "$MREPO"

mkstate "$TMPROOT/mergenone.md" feat '| 99 | never merged | PENDING |'
assert_verdict "id absent from all merge subjects => CLEAN" CLEAN 0 "$TMPROOT/mergenone.md" "$MREPO"

# git's own default merge subject is capitalised and must never be mistaken for a subtask record.
git -C "$MREPO" commit -q --allow-empty -m "Merge branch 'main' into feat"
mkstate "$TMPROOT/gitmerge.md" feat "| main | not a subtask | PENDING |"
assert_verdict "git's default 'Merge branch' subject is not a completion record" CLEAN 0 "$TMPROOT/gitmerge.md" "$MREPO"

printf '\n=== ID MATCHING: fixed-string, not regex (false-STALE regression) ===\n'
# `.` is BRE-special. Without grep -F, a dotted id `BD-1.2` also matches a committed `BD-1x2`,
# producing a FALSE STALE that refuses a legitimate resume — the harmful direction for a
# fail-closed gate. Pure-numeric fixtures never expose it.
DREPO="$TMPROOT/dotted"
mkdir -p "$DREPO"
git -C "$DREPO" init -q 2>/dev/null
git -C "$DREPO" config user.email t@t.t
git -C "$DREPO" config user.name t
git -C "$DREPO" commit -q --allow-empty -m "base"
git -C "$DREPO" checkout -q -b feat
git -C "$DREPO" commit -q --allow-empty -m "subtask: BD-1x2 — a DIFFERENT subtask"

mkstate "$TMPROOT/dotted.md" feat '| BD-1.2 | genuinely pending | PENDING |'
assert_verdict "dotted id must not regex-match a near-miss commit" CLEAN 0 "$TMPROOT/dotted.md" "$DREPO"

git -C "$DREPO" commit -q --allow-empty -m "subtask: BD-1.2 — the real one"
mkstate "$TMPROOT/dotted2.md" feat '| BD-1.2 | now committed | PENDING |'
assert_verdict "exact dotted id still detected when truly committed" STALE 3 "$TMPROOT/dotted2.md" "$DREPO"

printf '\n=== ANTI-SPOOF: prose must not masquerade as completion ===\n'
git -C "$REPO" checkout -q -b feature/spoof
git -C "$REPO" commit -q --allow-empty -m "docs: mention subtask: 9 in passing prose"
mkstate "$TMPROOT/spoof.md" feature/spoof '| 9 | thing 9 | PENDING |'
_out=$(bash "$SUT" "$TMPROOT/spoof.md" "$REPO" 2>&1); _rc=$?
# A commit SUBJECT that merely mentions "subtask: 9" mid-sentence is not anchored at position 0,
# so it must NOT count as proof of completion.
if [ "$_rc" = "0" ]; then
  ok "unanchored mention does not count as completion"
else
  bad "unanchored mention" "CLEAN/exit 0" "$(printf '%s' "$_out" | sed -n 's/^VERDICT: //p')/exit $_rc"
fi

printf '\n---\nreconcile-resume-state: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
