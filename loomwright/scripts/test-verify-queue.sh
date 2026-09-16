#!/usr/bin/env bash
# test-verify-queue.sh — self-tests for the `/verify --folder <dir>` multi-ticket queue engine
# (item 07): the four new verify-helpers.sh queue-* subcommands, verify-run.sh's
# queue-reconcile-item, and a hand-rolled per-item loop (this suite's own harness, NOT the
# prose-executed /verify command) that drives them exactly the way commands/verify.md's Queue
# mode / skills/verify-walkthrough/SKILL.md §10 document. Schema authority:
# docs/RESULT_SCHEMAS.md §VERIFY_QUEUE. Precedent: test-automate-helpers.sh (pure-logic helper
# self-tests via a hand-rolled harness, not the prose /automate loop) and
# test-verify-walkthrough.sh (staged bin/ + stub verify-env.sh + git fixture repo).
#
# WRITE CONTAINMENT. Every fixture lives under a `mktemp -d`; the scripts under test are COPIES
# staged beside a stub `verify-env.sh` (the walkthrough's own STUB, browser-less — this suite
# only exercises the NOT_VERIFIABLE verdict path, never `walk`/Playwright) in a throwaway git
# repo. Nothing here ever touches the real .supervisor/ of this repo. UNCOUNTED by the
# doc-currency gate (a plain test script, not an agent/command/skill/hook).
#
# Arms:
#   (A) folder resolution + queue creation — automate-helpers.sh resolve-folder (verbatim reuse)
#       over a 3-ticket folder with one `## Status: done` returns exactly 2, LC_ALL=C sort order;
#       the queue file built from them carries 2 `- [ ]` items in that order.
#   (B) --limit 1 — processing one item with a second still queued pauses the queue
#       `## Status: paused` / `pause_reason: limit_reached`; the unpicked item is untouched
#       (no run_id minted); `queue-remaining` reports 1.
#   (C) crash mid-item resume — item 1 finishes and is checked off; item 2 is picked (preflight)
#       and gets ONE verdict (AC1) then the harness stops (simulated kill, no finish/pause);
#       `queue-reconcile-item` on item 2's run dir reports `status:"crashed"` and
#       `resume_ac_id:"AC2"`; resuming at AC2 and finishing checks item 2 off — item 1's queue
#       line (and its run_id) is byte-unchanged throughout (never re-picked).
#   (D) moved branch head → stale — after item 1 is picked (preflight) and gets a partial verdict,
#       a new commit moves `main`; `queue-reconcile-item` reports `status:"stale"` with the old and
#       new SHAs (checked BEFORE any evidence-derived status, so a moved head always wins) and the
#       run dir's `evidence.jsonl` is proven byte-unchanged by the reconcile call itself; the
#       simulated loop reaction marks the item `# stale: head moved <old>-><new>` and re-queues a
#       fresh unchecked item for the same ticket — the stale run dir is never reused or deleted.
#   (E) empty-stdin guard — `queue-write` on an existing non-empty queue file, given empty stdin,
#       REFUSES (non-zero exit) and leaves the file byte-for-byte unchanged; a same-or-more-lines
#       rewrite still succeeds.
#   (F) mutation control — deleting the head-sha comparison from a COPY of verify-run.sh (gated:
#       non-empty, differs from the original, `bash -n` clean) makes the SAME stale fixture from
#       (D) report a non-"stale" status, proving (D) is not passing vacuously.
#   (N) never shares state with /automate — `find .supervisor/automate .supervisor/state.md
#       -newer <marker>` is empty after a full item-processing sequence (arm B's).
#   (G) queue-reconcile-item paused + not_started branches — driven directly against a hand-built
#       run dir (mirrors (C)/(D)/(F)): a run dir whose evidence.jsonl's LAST line is a `pause`
#       (written via the real `pause` subcommand, reason `session_expired`) reconciles to
#       `{status:"paused", pause_reason:"session_expired"}`; a run dir with NO evidence.jsonl at
#       all (never preflighted) reconciles to `{status:"not_started", pause_reason:null}`.
#   (S) static shape — `bash -n` on both changed scripts; `--help` lists the four queue-*
#       subcommands (verify-helpers.sh) and queue-reconcile-item (verify-run.sh).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VH_SRC="$HERE/verify-helpers.sh"
VR_SRC="$HERE/verify-run.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$VH_SRC" "$VR_SRC" "$HERE/automate-helpers.sh" "$HERE/validate-verify-evidence.py" \
         "$HERE/read-verify.sh" "$HERE/propose-verify.sh"; do
  if [ ! -f "$f" ]; then
    echo "  FAIL: required file not found at $f"
    echo "RESULT: 0 passed, 1 failed"
    exit 1
  fi
done
for tool in python3 jq git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "  FAIL: $tool is required by this suite"
    echo "RESULT: 0 passed, 1 failed"
    exit 1
  fi
done

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

LAST_OUT="$ROOT/last-stdout.txt"
LAST_ERR="$ROOT/last-stderr.txt"

FOLDER=".supervisor/requirements/queue-test"

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

# stage <T> — bin/ = copies of the runner/helpers + a browser-less stub verify-env.sh (same shape
# as test-verify-walkthrough.sh's own stub — this suite only drives the NOT_VERIFIABLE verdict
# path, never `walk`). repo/ = a git repo with 3 tickets (01-a.md, 02-b.md queued; 03-c.md done).
stage() {
  local T="$1"
  mkdir -p "$T/bin" "$T/repo/$FOLDER"
  cp "$VR_SRC" "$VH_SRC" "$HERE/automate-helpers.sh" "$HERE/validate-verify-evidence.py" \
     "$HERE/read-verify.sh" "$HERE/propose-verify.sh" "$T/bin/"
  cat > "$T/bin/verify-env.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_CALLS:?STUB_CALLS unset}"
case "${STUB_NONPROD:-pass}" in
  fail) echo "verify-env: every non_prod_assert member failed (1 evaluated) — this target could be production; refusing [non_prod_assert_failed]" >&2; exit 1 ;;
  *)    echo "non-prod asserted"; exit 0 ;;
esac
STUB
  chmod +x "$T/bin/"*.sh
  cat > "$T/repo/$FOLDER/01-a.md" <<'EOF'
# 01 — a

## Acceptance Criteria
- Given ticket a's page, when it loads, then the a-panel is visible.
- Given the a-panel, when the a-button is clicked, then the a-result shows.
EOF
  cat > "$T/repo/$FOLDER/02-b.md" <<'EOF'
# 02 — b

## Acceptance Criteria
- Given ticket b's page, when it loads, then the b-panel is visible.
- Given the b-panel, when the b-button is clicked, then the b-result shows.
EOF
  cat > "$T/repo/$FOLDER/03-c.md" <<'EOF'
# 03 — c

## Status: done

## Acceptance Criteria
- Given ticket c, when it loads, then it renders.
EOF
  printf '# fixture\n' > "$T/repo/README.md"
  ( cd "$T/repo" && git init -q -b main && git add -A >/dev/null 2>&1 \
    && git -c user.email=t@example.invalid -c user.name=t commit -q -m init ) \
    || { echo "  FAIL: fixture git init"; exit 1; }
}

# contract <T> — well-formed .agent/verify.json; auth.method none (no auth-check probe needed by
# this suite's browser-less verdict path); non_prod_assert.cmd drives the stub via STUB_NONPROD.
contract() {
  mkdir -p "$1/repo/.agent"
  jq -n '{start: null, base_url: "http://localhost:3000", health: "/",
    auth: {method: "none", storage_state_path: null, probe_path: null},
    non_prod_assert: {cmd: "true"}, seed: null, reset: null, stop: null}' > "$1/repo/.agent/verify.json"
}

# run_bin <T> <args…> — runs the STAGED verify-run.sh (cwd = the fixture repo).
run_bin() {
  local T="$1"; shift
  : > "$LAST_OUT"; : > "$LAST_ERR"
  ( cd "$T/repo" && STUB_CALLS="$T/calls.log" bash "$T/bin/verify-run.sh" "$@" ) >"$LAST_OUT" 2>"$LAST_ERR"
}
last_run_dir() { grep '^run_dir=' "$LAST_OUT" | tail -1 | sed 's/^run_dir=//'; }

vh() { local T="$1"; shift; ( cd "$T/repo" && bash "$T/bin/verify-helpers.sh" "$@" ); }
qfile_of() { echo "$1/repo/.supervisor/verify/queue-test.md"; }

# build_queue <T> <qfile-relpath> <limit> <ticket…> — writes the queue template with each ticket
# as an unchecked "- [ ] <ticket>" line, via queue-write (guarded atomic write).
build_queue() {
  local T="$1" qrel="$2" limit="$3"; shift 3
  {
    echo "# Verify Queue: queue-test"
    echo "## Status: running"
    echo "## Source"
    echo "- folder $FOLDER"
    echo "## Run Config"
    echo "- limit: $limit | impact_limit: 10"
    echo "## Queue"
    for t in "$@"; do echo "- [ ] $t"; done
    echo "## Current"
    echo "- item: null | run_id: null | status: null"
    echo "- pause_reason: null"
    echo "## Progress"
  } | ( cd "$T/repo" && bash "$T/bin/verify-helpers.sh" queue-write "$qrel" )
}

# record_run_id <T> <qfile> <ticket> <run_id> — rewrites "- [ ] <ticket>" -> "- [ ] <ticket> -> <run_id>"
record_run_id() {
  local T="$1" qabs="$2" ticket="$3" rid="$4"
  awk -v old="- [ ] $ticket" -v new="- [ ] $ticket -> $rid" '$0==old{print new;next}{print}' "$qabs" \
    | ( cd "$T/repo" && bash "$T/bin/verify-helpers.sh" queue-write "$(basename "$qabs" | sed "s|^|.supervisor/verify/|")" )
}

# process_all_acs <T> <run_dir> <ac_ids…> — NOT_VERIFIABLE-verdicts each ac_id (browser-less path).
process_ac() {
  local T="$1" rd="$2" ac="$3"
  run_bin "$T" verdict "$rd" "$ac" NOT_VERIFIABLE --reason "queue test stub"
}
finish_item() { local T="$1" rd="$2"; run_bin "$T" finish "$rd"; }

reconcile() {
  local T="$1" rd="$2" branch="${3:-main}"
  ( cd "$T/repo" && bash "$T/bin/verify-run.sh" queue-reconcile-item "$rd" --branch "$branch" --repo . )
}

ev_hash() { sha256sum "$1/evidence.jsonl" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$1/evidence.jsonl" 2>/dev/null | cut -d' ' -f1; }

# ============================================================================
echo "== (A) folder resolution + queue creation: 2 items, LC_ALL=C sort order, done skipped =="
TA="$(mktmp)"; stage "$TA"; contract "$TA"
items="$(cd "$TA/repo" && bash "$TA/bin/automate-helpers.sh" resolve-folder "$FOLDER")"
n="$(printf '%s\n' "$items" | grep -c .)"
[ "$n" -eq 2 ] && ok "(A) resolve-folder returns 2 items" || no "(A) resolve-folder returned $n items: $items"
first="$(printf '%s\n' "$items" | sed -n 1p)"; second="$(printf '%s\n' "$items" | sed -n 2p)"
[ "$first" = "$FOLDER/01-a.md" ] && ok "(A) item 1 is 01-a.md" || no "(A) item 1 is '$first'"
[ "$second" = "$FOLDER/02-b.md" ] && ok "(A) item 2 is 02-b.md" || no "(A) item 2 is '$second'"
printf '%s\n' "$items" | grep -q '03-c.md' && no "(A) done ticket 03-c.md was NOT skipped" || ok "(A) 03-c.md (## Status: done) skipped"

build_queue "$TA" ".supervisor/verify/queue-test.md" 5 "$first" "$second"
QA="$(qfile_of "$TA")"
rem="$(vh "$TA" queue-remaining .supervisor/verify/queue-test.md)"
[ "$rem" -eq 2 ] && ok "(A) fresh queue file has 2 unchecked items" || no "(A) queue-remaining=$rem"
grep -qF -- "- [ ] $FOLDER/01-a.md" "$QA" && grep -qF -- "- [ ] $FOLDER/02-b.md" "$QA" \
  && ok "(A) queue file carries both items unchecked, in order" || no "(A) queue file content: $(cat "$QA")"

# ============================================================================
echo "== (B) --limit 1: processes one, pauses limit_reached, second item untouched =="
TB="$(mktmp)"; stage "$TB"; contract "$TB"
build_queue "$TB" ".supervisor/verify/queue-test.md" 1 "$FOLDER/01-a.md" "$FOLDER/02-b.md"
QB="$(qfile_of "$TB")"
MARKER="$TB/marker"; touch "$MARKER"; sleep 1

RD1="$(run_bin "$TB" preflight "$FOLDER/01-a.md" --repo . && last_run_dir)"
[ -n "$RD1" ] && [ -d "$RD1" ] || no "(B) preflight item1 failed: $(cat "$LAST_ERR")"
RID1="$(basename "$RD1")"
record_run_id "$TB" "$QB" "$FOLDER/01-a.md" "$RID1"
process_ac "$TB" "$RD1" AC1
process_ac "$TB" "$RD1" AC2
finish_item "$TB" "$RD1"
counts_row="$(grep '^PASS: ' "$LAST_OUT" | tail -1)"
vh "$TB" queue-checkoff .supervisor/verify/queue-test.md "$FOLDER/01-a.md -> $RID1" "verdict: $counts_row"
vh "$TB" queue-progress-append .supervisor/verify/queue-test.md "picked $FOLDER/01-a.md -> run_id $RID1; run_end $counts_row"
# limit(1) reached with item 2 still unchecked -> pause the queue.
awk '
  /^## Status:/ { print "## Status: paused"; next }
  /^- pause_reason:/ { print "- pause_reason: limit_reached"; next }
  { print }
' "$QB" | vh "$TB" queue-write .supervisor/verify/queue-test.md

rem="$(vh "$TB" queue-remaining .supervisor/verify/queue-test.md)"
[ "$rem" -eq 1 ] && ok "(B) 1 item remains unchecked after limit=1" || no "(B) queue-remaining=$rem"
grep -qF '## Status: paused' "$QB" && ok "(B) queue Status: paused" || no "(B) queue Status not paused: $(grep '^## Status' "$QB")"
grep -qF 'pause_reason: limit_reached' "$QB" && ok "(B) pause_reason: limit_reached" || no "(B) pause_reason line: $(grep pause_reason "$QB")"
grep -qF -- "- [x] $FOLDER/01-a.md -> $RID1  verdict:" "$QB" && ok "(B) item 1 checked off with verdict counts" || no "(B) item1 line: $(grep '01-a.md' "$QB")"
grep -qF -- "- [ ] $FOLDER/02-b.md" "$QB" && ok "(B) item 2 left untouched, no run_id minted" || no "(B) item2 line: $(grep '02-b.md' "$QB")"

echo "== (N) never shares state with /automate =="
if [ -d "$TB/repo/.supervisor/automate" ] || [ -f "$TB/repo/.supervisor/state.md" ]; then
  touched="$(find "$TB/repo/.supervisor/automate" "$TB/repo/.supervisor/state.md" -newer "$MARKER" 2>/dev/null)"
  [ -z "$touched" ] && ok "(N) no .supervisor/automate or state.md touched" || no "(N) touched: $touched"
else
  ok "(N) .supervisor/automate and state.md never even created"
fi

# ============================================================================
echo "== (C) crash mid-item resume: item2 verdicted AC1 only, reconcile finds AC2, item1 unchanged =="
TC="$(mktmp)"; stage "$TC"; contract "$TC"
build_queue "$TC" ".supervisor/verify/queue-test.md" 5 "$FOLDER/01-a.md" "$FOLDER/02-b.md"
QC="$(qfile_of "$TC")"

RD1C="$(run_bin "$TC" preflight "$FOLDER/01-a.md" --repo . && last_run_dir)"
RID1C="$(basename "$RD1C")"
record_run_id "$TC" "$QC" "$FOLDER/01-a.md" "$RID1C"
process_ac "$TC" "$RD1C" AC1; process_ac "$TC" "$RD1C" AC2
finish_item "$TC" "$RD1C"
counts1="$(grep '^PASS: ' "$LAST_OUT" | tail -1)"
vh "$TC" queue-checkoff .supervisor/verify/queue-test.md "$FOLDER/01-a.md -> $RID1C" "verdict: $counts1"
item1_line_before="$(grep -F '01-a.md' "$QC")"

RD2C="$(run_bin "$TC" preflight "$FOLDER/02-b.md" --repo . && last_run_dir)"
RID2C="$(basename "$RD2C")"
record_run_id "$TC" "$QC" "$FOLDER/02-b.md" "$RID2C"
process_ac "$TC" "$RD2C" AC1
# simulated kill — no AC2 verdict, no finish, no pause.

rc_json="$(reconcile "$TC" "$RD2C")"
status="$(printf '%s' "$rc_json" | jq -r .status)"
resume_ac="$(printf '%s' "$rc_json" | jq -r .resume_ac_id)"
[ "$status" = "crashed" ] && ok "(C) reconcile reports status=crashed" || no "(C) reconcile status='$status' ($rc_json)"
[ "$resume_ac" = "AC2" ] && ok "(C) reconcile resume_ac_id=AC2" || no "(C) resume_ac_id='$resume_ac'"

process_ac "$TC" "$RD2C" "$resume_ac"
finish_item "$TC" "$RD2C"
counts2="$(grep '^PASS: ' "$LAST_OUT" | tail -1)"
vh "$TC" queue-checkoff .supervisor/verify/queue-test.md "$FOLDER/02-b.md -> $RID2C" "verdict: $counts2"

item1_line_after="$(grep -F '01-a.md' "$QC")"
[ "$item1_line_before" = "$item1_line_after" ] && ok "(C) item 1's queue line byte-unchanged (never re-picked)" || no "(C) item1 before='$item1_line_before' after='$item1_line_after'"
rem="$(vh "$TC" queue-remaining .supervisor/verify/queue-test.md)"
[ "$rem" -eq 0 ] && ok "(C) both items checked off after resume" || no "(C) queue-remaining=$rem"
grep -qF -- "- [x] $FOLDER/02-b.md -> $RID2C  verdict:" "$QC" && ok "(C) item 2 checked off with verdict counts" || no "(C) item2 line: $(grep '02-b.md' "$QC")"

# ============================================================================
echo "== (D) moved branch head -> stale, re-queued, old run dir untouched =="
TD="$(mktmp)"; stage "$TD"; contract "$TD"
build_queue "$TD" ".supervisor/verify/queue-test.md" 5 "$FOLDER/01-a.md"
QD="$(qfile_of "$TD")"

RD1D="$(run_bin "$TD" preflight "$FOLDER/01-a.md" --repo . && last_run_dir)"
RID1D="$(basename "$RD1D")"
record_run_id "$TD" "$QD" "$FOLDER/01-a.md" "$RID1D"
process_ac "$TD" "$RD1D" AC1   # partial progress, in flight — mirrors item 04's "## Current" shape

OLDSHA="$(cd "$TD/repo" && git rev-parse main)"
HASH_BEFORE="$(ev_hash "$RD1D")"

( cd "$TD/repo" && echo more >> README.md && git add README.md \
  && git -c user.email=t@example.invalid -c user.name=t commit -q -m second )
NEWSHA="$(cd "$TD/repo" && git rev-parse main)"
[ "$OLDSHA" != "$NEWSHA" ] || { echo "  FAIL: fixture head did not move"; exit 1; }

rc_json="$(reconcile "$TD" "$RD1D")"
status="$(printf '%s' "$rc_json" | jq -r .status)"
r_old="$(printf '%s' "$rc_json" | jq -r .old_sha)"
r_new="$(printf '%s' "$rc_json" | jq -r .new_sha)"
[ "$status" = "stale" ] && ok "(D) reconcile reports status=stale on a moved head" || no "(D) status='$status' ($rc_json)"
[ "$r_old" = "$OLDSHA" ] && [ "$r_new" = "$NEWSHA" ] && ok "(D) reconcile echoes the correct old/new SHAs" || no "(D) old=$r_old new=$r_new (want $OLDSHA / $NEWSHA)"

HASH_AFTER_RECONCILE="$(ev_hash "$RD1D")"
[ "$HASH_BEFORE" = "$HASH_AFTER_RECONCILE" ] && ok "(D) reconcile itself never mutates the run dir" || no "(D) evidence.jsonl changed by a pure read"

# simulated loop reaction: mark stale, re-queue a fresh item.
vh "$TD" queue-checkoff .supervisor/verify/queue-test.md "$FOLDER/01-a.md -> $RID1D" "# stale: head moved $r_old->$r_new"
awk -v marker="- [x] $FOLDER/01-a.md -> $RID1D  # stale: head moved $r_old->$r_new" -v newline="- [ ] $FOLDER/01-a.md" '
  { print }
  $0==marker { print newline }
' "$QD" | vh "$TD" queue-write .supervisor/verify/queue-test.md

grep -qF "# stale: head moved $r_old->$r_new" "$QD" && ok "(D) item marked stale with old->new SHAs" || no "(D) queue file: $(cat "$QD")"
rem="$(vh "$TD" queue-remaining .supervisor/verify/queue-test.md)"
[ "$rem" -eq 1 ] && ok "(D) a fresh unchecked item was re-queued" || no "(D) queue-remaining=$rem"

HASH_AFTER_REQUEUE="$(ev_hash "$RD1D")"
[ "$HASH_BEFORE" = "$HASH_AFTER_REQUEUE" ] && [ -d "$RD1D" ] && ok "(D) stale run dir untouched and never deleted after re-queue" || no "(D) run dir mutated or removed"

# ============================================================================
echo "== (E) empty-stdin guard: queue-write refuses to shrink; a growth rewrite still succeeds =="
TE="$(mktmp)"; stage "$TE"
build_queue "$TE" ".supervisor/verify/queue-test.md" 5 "$FOLDER/01-a.md" "$FOLDER/02-b.md"
QE="$(qfile_of "$TE")"
before_hash="$(sha256sum "$QE" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$QE" | cut -d' ' -f1)"
printf '' | vh "$TE" queue-write .supervisor/verify/queue-test.md
rc=$?
after_hash="$(sha256sum "$QE" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$QE" | cut -d' ' -f1)"
[ "$rc" -ne 0 ] && ok "(E) empty-stdin rewrite exits non-zero" || no "(E) empty-stdin rewrite exited 0"
[ "$before_hash" = "$after_hash" ] && ok "(E) queue file byte-unchanged after the refused rewrite" || no "(E) queue file bytes changed on a refused write"
# positive control: a same-or-more-lines rewrite still succeeds.
( cat "$QE"; echo "- extra line" ) | vh "$TE" queue-write .supervisor/verify/queue-test.md
rc=$?
[ "$rc" -eq 0 ] && grep -qF 'extra line' "$QE" && ok "(E) a growth rewrite still succeeds" || no "(E) growth rewrite failed rc=$rc"

# ============================================================================
echo "== (F) mutation control: deleting the head-sha comparison defeats stale detection =="
MUTANT="$TD/bin/verify-run.mutant.sh"
sed 's/\[ "\$old_sha" != "\$new_sha" \]/[ "$old_sha" = "__NEVER_MATCH__" ]/' "$TD/bin/verify-run.sh" > "$MUTANT"
[ -s "$MUTANT" ] && ok "(F) mutant is non-empty" || no "(F) mutant file empty"
if diff -q "$TD/bin/verify-run.sh" "$MUTANT" >/dev/null 2>&1; then
  no "(F) mutant is byte-identical to the original — mutation had no effect"
else
  ok "(F) mutant differs from the original"
fi
if bash -n "$MUTANT" 2>/dev/null; then
  ok "(F) mutant passes bash -n"
else
  no "(F) mutant fails bash -n"
fi
chmod +x "$MUTANT"
mutant_json="$( cd "$TD/repo" && bash "$MUTANT" queue-reconcile-item "$RD1D" --branch main --repo . )"
mutant_status="$(printf '%s' "$mutant_json" | jq -r .status)"
[ "$mutant_status" != "stale" ] && ok "(F) mutant fails to detect the moved head (status='$mutant_status') — (D) is not vacuous" || no "(F) mutant still reported stale — the comparison was not actually neutralized"

# ============================================================================
echo "== (G) queue-reconcile-item: paused (evidence-derived) and not_started branches =="
TG="$(mktmp)"; stage "$TG"; contract "$TG"

RD1G="$(run_bin "$TG" preflight "$FOLDER/01-a.md" --repo . && last_run_dir)"
[ -n "$RD1G" ] && [ -d "$RD1G" ] || no "(G) preflight item1 failed: $(cat "$LAST_ERR")"

run_bin "$TG" pause "$RD1G" --reason session_expired
prc=$?
[ "$prc" -eq 0 ] || no "(G) pause subcommand failed rc=$prc: $(cat "$LAST_ERR")"

rc_json="$(reconcile "$TG" "$RD1G")"
status="$(printf '%s' "$rc_json" | jq -r .status)"
reason="$(printf '%s' "$rc_json" | jq -r .pause_reason)"
[ "$status" = "paused" ] && ok "(G) reconcile reports status=paused for an evidence-derived pause" || no "(G) status='$status' ($rc_json)"
[ "$reason" = "session_expired" ] && ok "(G) reconcile echoes pause_reason=session_expired" || no "(G) pause_reason='$reason' ($rc_json)"

NOTSTARTED="$TG/repo/.supervisor/verify/queue-test-not-started"
mkdir -p "$NOTSTARTED"
rc_json="$(reconcile "$TG" "$NOTSTARTED")"
status="$(printf '%s' "$rc_json" | jq -r .status)"
reason="$(printf '%s' "$rc_json" | jq -r .pause_reason)"
[ "$status" = "not_started" ] && ok "(G) reconcile reports status=not_started for a run dir with no evidence.jsonl" || no "(G) status='$status' ($rc_json)"
[ "$reason" = "null" ] && ok "(G) reconcile reports pause_reason=null for not_started" || no "(G) pause_reason='$reason' ($rc_json)"

# ============================================================================
echo "== (S) static shape: bash -n, --help lists the new subcommands =="
bash -n "$VH_SRC" && ok "(S) verify-helpers.sh: bash -n" || no "(S) verify-helpers.sh: bash -n failed"
bash -n "$VR_SRC" && ok "(S) verify-run.sh: bash -n" || no "(S) verify-run.sh: bash -n failed"
help_vh="$(bash "$VH_SRC" --help 2>&1)"
for sub in queue-write queue-progress-append queue-checkoff queue-remaining; do
  printf '%s\n' "$help_vh" | grep -q "$sub" && ok "(S) verify-helpers.sh --help lists $sub" || no "(S) --help missing $sub"
done
help_vr="$(bash "$VR_SRC" --help 2>&1)"
printf '%s\n' "$help_vr" | grep -q 'queue-reconcile-item' && ok "(S) verify-run.sh --help lists queue-reconcile-item" || no "(S) --help missing queue-reconcile-item"

# ============================================================================
echo ""
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && exit 0 || exit 1
