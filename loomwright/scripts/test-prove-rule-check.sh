#!/usr/bin/env bash
# test-prove-rule-check.sh — self-tests for prove-rule-check.sh, the confirm-gated prover that shows a
# CANDIDATE rule check passes on the current tree and fails on a counterexample patch applied in a
# throwaway scratch worktree (verified-rule-checks, owner decisions D1–D4). Every fixture is a temp
# git repo under `mktemp -d`; HOME is a temp dir for the whole run; nothing touches the real repo.
# Exit 0 = all pass, 1 = any failure.
#
# Covers (AC numbers from the job brief):
#   (a) PROVEN — a grep for a token + a patch deleting it ⇒ PROVEN, exit 0, proof records PROVEN and
#       the sha256 of the exact check bytes; add-rule.sh then WRITES the must rule (AC 2).
#   (b) VACUOUS — `true` ⇒ VACUOUS, exit 1; add-rule.sh refuses its proof (AC 1).
#   (c) FAILS_NOW — a failing check ⇒ FAILS_NOW, exit 1, the check ran EXACTLY once (leg 2 never
#       ran), proof counterexample_exit null; add-rule.sh refuses it (AC 3).
#   (d) UNPROVABLE — patch does not apply / not a git repo / `git worktree add` fails / timeout /
#       bad args / scratch baseline fails / --out inside the repo ⇒ `UNPROVABLE (<reason>)`, exit 2
#       (AC 4, AC 12).
#   (e) needs_confirmation — no --confirm, no TTY, ambient env "confirm" variables set ⇒ the canary
#       check never runs, `UNPROVABLE (needs_confirmation)` (AC 5).
#   (f) no leak — for every verdict, `git worktree list --porcelain` + `git status --porcelain` are
#       byte-identical before/after and the scratch dir (under a per-run TMPDIR) is gone (AC 6).
#   (g) scratch_leak — worktree removal stubbed to fail ⇒ `UNPROVABLE (scratch_leak)` (AC 6).
#   (h) the user-scope rules stamp file is neither created nor changed by any prove run (AC 7).
#   (j) an interrupt (SIGTERM) during leg 2 ⇒ `UNPROVABLE (interrupted)`, the running check's tree is
#       killed and the scratch worktree is still removed (no leak).
#   (i) Validation 2 mutation control, in-suite: a VALID mutant whose counterexample leg is a no-op
#       reporting exit 1 must NOT read VACUOUS on `true` — so (b) is load-bearing.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVER="$SCRIPT_DIR/prove-rule-check.sh"
WRITER="$SCRIPT_DIR/add-rule.sh"
CHECKER="$SCRIPT_DIR/rules-check.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
export HOME="$ROOT/home"; mkdir -p "$HOME"
REAL_GIT="$(command -v git)"

if ! command -v jq >/dev/null 2>&1; then
  echo "test-prove-rule-check: jq absent on this host — the proof file needs jq. Skipping."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# new_repo — a committed fixture: src/a.txt carries TOKEN; .gitignore ignores scratch.log.
new_repo() {
  local r; r="$(mktemp -d "$ROOT/r.XXXXXX")"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && mkdir src && printf 'TOKEN here\n' > src/a.txt && printf 'scratch.log\n' > .gitignore \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}
# The counterexample used throughout: deletes TOKEN from src/a.txt.
DEL_PATCH="$ROOT/del.patch"
cat > "$DEL_PATCH" <<'PATCH'
--- a/src/a.txt
+++ b/src/a.txt
@@ -1 +1 @@
-TOKEN here
+gone here
PATCH
CHECK_TOKEN='grep -q TOKEN src/a.txt'

# state <repo> — the two snapshots AC 6 compares.
state() { git -C "$1" worktree list --porcelain; echo "--status--"; git -C "$1" status --porcelain; }

# prove_in <repo> <args...> — runs the prover from <repo> with a FRESH per-run TMPDIR (so the scratch
# dir it creates is observable), stdin from /dev/null and stdout captured (never a TTY).
# Sets OUT, RC, RUN_TMP, BEFORE, AFTER.
prove_in() {
  local repo="$1"; shift
  RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"
  BEFORE="$(state "$repo" 2>&1)"
  OUT="$( ( cd "$repo" && TMPDIR="$RUN_TMP" bash "$PROVER" "$@" ) </dev/null 2>&1 )"; RC=$?
  AFTER="$(state "$repo" 2>&1)"
}
last_line() { printf '%s\n' "$OUT" | tail -1; }
# no_leak <label> — AC 6 assertion for the run prove_in just made.
no_leak() {
  if [ "$BEFORE" = "$AFTER" ] && [ -z "$(ls -A "$RUN_TMP" 2>/dev/null)" ]; then
    ok "$1: worktree list + status byte-identical, scratch dir gone"
  else
    no "$1: LEAK — before/after differ or scratch left in $RUN_TMP: [$BEFORE] vs [$AFTER] / $(ls -A "$RUN_TMP" 2>/dev/null)"
  fi
}
sha_of() {   # independent of the prover's helper: whichever tool this host has
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else printf '%s' "$1" | sha256sum | awk '{print $1}'; fi
}

# (h) setup — derive the stamp path from rules-check.sh's ONE assignment (never restated here), seed
# it with known bytes, and fingerprint the whole test HOME. Every prove run below is checked against it.
STAMP_REL="$(sed -n 's|^RULES_CHECK_STAMP_FILE="\${HOME:-}/\(.*\)"$|\1|p' "$CHECKER" | head -1)"
STAMP="$HOME/$STAMP_REL"
home_print() { ( cd "$HOME" && find . -type f -exec cksum {} \; | LC_ALL=C sort ); }
if [ -n "$STAMP_REL" ]; then
  mkdir -p "$(dirname "$STAMP")"; printf '{"seed":"untouched"}\n' > "$STAMP"
  ok "(h0) premise: stamp path derived from rules-check.sh ($STAMP_REL) and seeded"
else
  no "(h0) premise: could not derive the stamp path from rules-check.sh"
fi
HOME_BEFORE="$(home_print)"

# ============================================================================
echo "== (a) PROVEN: token grep + a patch deleting the token =="
RA="$(new_repo)"
prove_in "$RA" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --out "$ROOT/a.proof.json" --confirm
[ "$RC" -eq 0 ] && [ "$(last_line)" = "verdict: PROVEN" ] \
  && ok "(a1) PROVEN, exit 0" || no "(a1) expected PROVEN/0, got rc=$RC: $OUT"
printf '%s' "$OUT" | grep -qF 'now leg (current tree' && printf '%s' "$OUT" | grep -qF 'counterexample leg (scratch copy of HEAD + patch): exit 1' \
  && ok "(a2) both legs' exit codes are printed" || no "(a2) leg output missing: $OUT"
if jq -e --arg h "$(sha_of "$CHECK_TOKEN")" \
     '.schema=="rule-check-proof/1" and .verdict=="PROVEN" and .reason==null and .check_sha256==$h
      and .now_exit==0 and .baseline_exit==0 and .counterexample_exit==1
      and (.counterexample_sha256|type=="string") and (.ts|type=="string")' "$ROOT/a.proof.json" >/dev/null 2>&1; then
  ok "(a3) proof file: schema, PROVEN, sha256 of the EXACT check bytes, all exits recorded"
else
  no "(a3) proof file wrong: $(cat "$ROOT/a.proof.json" 2>/dev/null)"
fi
no_leak "(a4) PROVEN"
OUT_W="$( ( cd "$RA" && bash "$WRITER" --category gate --statement "the token stays in src a" \
            --enforcement must --check "$CHECK_TOKEN" --proof "$ROOT/a.proof.json" --confirm ) 2>&1 )"; RC_W=$?
[ "$RC_W" -eq 0 ] && [ "$(jq -r '.[0].enforcement + "|" + .[0].check' "$RA/.agent/rules/gate.json" 2>/dev/null)" = "must|$CHECK_TOKEN" ] \
  && ok "(a5) AC 2: add-rule.sh --enforcement must --check <same> --proof <file> --confirm WRITES the rule" \
  || no "(a5) add-rule.sh refused a PROVEN proof (rc=$RC_W): $OUT_W"
rm -rf "$RA/.agent"

# ============================================================================
echo "== (b) VACUOUS: \`true\` passes on both legs =="
RB="$(new_repo)"
prove_in "$RB" --check 'true' --counterexample "$DEL_PATCH" --out "$ROOT/b.proof.json" --confirm
[ "$RC" -eq 1 ] && [ "$(last_line)" = "verdict: VACUOUS" ] \
  && ok "(b1) VACUOUS, exit 1" || no "(b1) expected VACUOUS/1, got rc=$RC: $OUT"
[ "$(jq -r '.verdict' "$ROOT/b.proof.json" 2>/dev/null)" = "VACUOUS" ] \
  && ok "(b2) proof records VACUOUS" || no "(b2) proof: $(cat "$ROOT/b.proof.json" 2>/dev/null)"
no_leak "(b3) VACUOUS"
OUT_W="$( ( cd "$RB" && bash "$WRITER" --category gate --statement "always true" \
            --enforcement must --check 'true' --proof "$ROOT/b.proof.json" --confirm ) 2>&1 )"; RC_W=$?
[ "$RC_W" -ne 0 ] && [ ! -e "$RB/.agent" ] \
  && ok "(b4) AC 1: no must rule can be written from a VACUOUS proof (rc=$RC_W, nothing written)" \
  || no "(b4) a VACUOUS proof was accepted (rc=$RC_W): $OUT_W"

# ============================================================================
echo "== (c) FAILS_NOW: the check fails on the current tree; leg 2 never runs =="
RC_REPO="$(new_repo)"; CNT="$ROOT/c.count"; : > "$CNT"
prove_in "$RC_REPO" --check "printf 'x\\n' >> '$CNT'; exit 3" --counterexample "$DEL_PATCH" --out "$ROOT/c.proof.json" --confirm
[ "$RC" -eq 1 ] && [ "$(last_line)" = "verdict: FAILS_NOW" ] \
  && ok "(c1) FAILS_NOW, exit 1" || no "(c1) expected FAILS_NOW/1, got rc=$RC: $OUT"
c_runs="$(wc -l < "$CNT" | tr -d '[:space:]')"
[ "$c_runs" = "1" ] && jq -e '.now_exit==3 and .baseline_exit==null and .counterexample_exit==null' "$ROOT/c.proof.json" >/dev/null 2>&1 \
  && printf '%s' "$OUT" | grep -qF 'counterexample leg: not run' \
  && ok "(c2) the check ran exactly once: the counterexample leg never ran (proof exits null)" \
  || no "(c2) leg 2 ran or was recorded (runs=$c_runs): $(cat "$ROOT/c.proof.json" 2>/dev/null)"
no_leak "(c3) FAILS_NOW"
OUT_W="$( ( cd "$RC_REPO" && bash "$WRITER" --category gate --statement "fails now" --enforcement must \
            --check "printf 'x\\n' >> '$CNT'; exit 3" --proof "$ROOT/c.proof.json" --confirm ) 2>&1 )"; RC_W=$?
[ "$RC_W" -ne 0 ] && [ ! -e "$RC_REPO/.agent" ] \
  && ok "(c4) AC 3: nothing is written from a FAILS_NOW proof" || no "(c4) FAILS_NOW proof accepted: $OUT_W"

# ============================================================================
echo "== (d) UNPROVABLE: every could-not-examine path is exit 2, never PROVEN =="
expect_unprovable() {   # <label> <reason>
  if [ "$RC" -eq 2 ] && [ "$(last_line)" = "verdict: UNPROVABLE ($2)" ]; then
    ok "$1: UNPROVABLE ($2), exit 2"
  else
    no "$1: expected UNPROVABLE ($2)/2, got rc=$RC: $OUT"
  fi
}
RD="$(new_repo)"
printf 'this is not a patch\n' > "$ROOT/garbage.patch"
prove_in "$RD" --check "$CHECK_TOKEN" --counterexample "$ROOT/garbage.patch" --out "$ROOT/d1.proof.json" --confirm
expect_unprovable "(d1) a patch that does not apply" patch_does_not_apply
jq -e '.verdict=="UNPROVABLE" and .reason=="patch_does_not_apply"' "$ROOT/d1.proof.json" >/dev/null 2>&1 \
  && ok "(d1b) the proof file records UNPROVABLE + reason (written for every verdict)" \
  || no "(d1b) proof: $(cat "$ROOT/d1.proof.json" 2>/dev/null)"
no_leak "(d1c) UNPROVABLE (patch_does_not_apply)"
cat > "$ROOT/ctx.patch" <<'PATCH'
--- a/src/a.txt
+++ b/src/a.txt
@@ -1 +1 @@
-a line that is not there
+gone
PATCH
prove_in "$RD" --check "$CHECK_TOKEN" --counterexample "$ROOT/ctx.patch" --confirm
expect_unprovable "(d2) a well-formed patch whose context does not match" patch_does_not_apply

NOTGIT="$(mktemp -d "$ROOT/notgit.XXXXXX")"
OUT="$( ( cd "$NOTGIT" && bash "$PROVER" --check 'true' --counterexample "$DEL_PATCH" --confirm ) </dev/null 2>&1 )"; RC=$?
expect_unprovable "(d3) not a git repo" not_a_git_repo

# (d4) `git worktree add` fails: a git shim refuses exactly `worktree add`, everything else is real git.
SHIM="$ROOT/shim"; mkdir -p "$SHIM"
cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
prev=""
for a in "$@"; do
  if [ "$prev" = worktree ] && [ "$a" = "${STUB_FAIL_WORKTREE:-}" ]; then echo "shim: git worktree $a refused" >&2; exit 128; fi
  prev="$a"
done
exec "$STUB_REAL_GIT" "$@"
SH
chmod +x "$SHIM/git"
RD4="$(new_repo)"
RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"; BEFORE="$(state "$RD4" 2>&1)"
OUT="$( ( cd "$RD4" && TMPDIR="$RUN_TMP" PATH="$SHIM:$PATH" STUB_REAL_GIT="$REAL_GIT" STUB_FAIL_WORKTREE=add \
          bash "$PROVER" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --confirm ) </dev/null 2>&1 )"; RC=$?
AFTER="$(state "$RD4" 2>&1)"
expect_unprovable "(d4) git worktree add fails" worktree_add_failed
no_leak "(d4b) UNPROVABLE (worktree_add_failed)"

# (d5) timeout — the watchdog must kill the check; bounded well below the check's own sleep.
RD5="$(new_repo)"
t0="$(date +%s)"
prove_in "$RD5" --check 'sleep 40' --counterexample "$DEL_PATCH" --timeout 1 --confirm
t1="$(date +%s)"
expect_unprovable "(d5) a check exceeding --timeout 1" timeout
[ $((t1 - t0)) -lt 15 ] && ok "(d5b) the watchdog killed it: returned in $((t1 - t0))s (< 15s, the check sleeps 40s)" \
  || no "(d5b) the run took $((t1 - t0))s — the watchdog did not kill the check"
no_leak "(d5c) UNPROVABLE (timeout)"

# (d6) bad arguments — all UNPROVABLE (bad_args), nothing run.
prove_in "$RD" --counterexample "$DEL_PATCH" --confirm;                      expect_unprovable "(d6a) no --check" bad_args
prove_in "$RD" --check '' --counterexample "$DEL_PATCH" --confirm;           expect_unprovable "(d6b) empty --check" bad_args
prove_in "$RD" --check 'true' --confirm;                                     expect_unprovable "(d6c) no --counterexample" bad_args
prove_in "$RD" --check 'true' --counterexample "$DEL_PATCH" --bogus --confirm; expect_unprovable "(d6d) unknown argument" bad_args
prove_in "$RD" --check 'true' --counterexample "$DEL_PATCH" --timeout 0 --confirm; expect_unprovable "(d6e) --timeout 0" bad_args
prove_in "$RD" --check 'true' --counterexample "$DEL_PATCH" --timeout x1 --confirm; expect_unprovable "(d6f) non-numeric --timeout" bad_args
prove_in "$RD" --check 'true' --counterexample "$ROOT/nope.patch" --confirm; expect_unprovable "(d6g) missing patch file" counterexample_unreadable
: > "$ROOT/empty.patch"
prove_in "$RD" --check 'true' --counterexample "$ROOT/empty.patch" --confirm; expect_unprovable "(d6h) empty patch file" counterexample_empty

# (d7) the check depends on UNCOMMITTED state: it passes on the working tree but fails on a clean copy
# of HEAD, so a failure after the patch could not be credited to the patch.
RD7="$(new_repo)"; printf 'local only\n' > "$RD7/untracked.txt"
prove_in "$RD7" --check 'test -f untracked.txt' --counterexample "$DEL_PATCH" --confirm
expect_unprovable "(d7) the check reads uncommitted state" scratch_baseline_fails
no_leak "(d7b) UNPROVABLE (scratch_baseline_fails)"

# (d8) --out inside the repo is refused — the prover never writes into the user's tree.
prove_in "$RD" --check 'true' --counterexample "$DEL_PATCH" --out "$RD/proof.json" --confirm
expect_unprovable "(d8) --out inside the repo" out_inside_repo
[ ! -e "$RD/proof.json" ] && ok "(d8b) no proof file was written inside the repo" || no "(d8b) a proof file landed in the repo"
no_leak "(d8c) UNPROVABLE (out_inside_repo)"

# (d9) a repo with no commit has no HEAD to copy.
RD9="$(mktemp -d "$ROOT/nohead.XXXXXX")"; ( cd "$RD9" && git init -q ) >/dev/null 2>&1
OUT="$( ( cd "$RD9" && bash "$PROVER" --check 'true' --counterexample "$DEL_PATCH" --confirm ) </dev/null 2>&1 )"; RC=$?
expect_unprovable "(d9) a repo with no HEAD commit" no_head_commit
# (d10)/(d11) --out targets that cannot hold a proof.
prove_in "$RD" --check 'true' --counterexample "$DEL_PATCH" --out "$ROOT/no-such-dir/p.json" --confirm
expect_unprovable "(d10) --out in a directory that does not exist" out_dir_missing
mkdir -p "$ROOT/out-is-a-dir"
prove_in "$RD" --check 'true' --counterexample "$DEL_PATCH" --out "$ROOT/out-is-a-dir" --confirm
expect_unprovable "(d11) --out that is an existing directory" out_not_a_file
[ -z "$(ls -A "$ROOT/out-is-a-dir")" ] && ok "(d11b) nothing was moved into that directory" || no "(d11b) a temp proof leaked into the --out directory"
# (d12) no working sha256 tool (all three stubbed to fail) with --out ⇒ nothing runs.
SHA_STUB="$ROOT/sha-stub"; mkdir -p "$SHA_STUB"
for t in shasum sha256sum openssl; do printf '#!/bin/sh\nexit 1\n' > "$SHA_STUB/$t"; chmod +x "$SHA_STUB/$t"; done
CNT12="$ROOT/d12.count"; : > "$CNT12"
OUT="$( ( cd "$RD" && PATH="$SHA_STUB:$PATH" bash "$PROVER" --check "printf x >> '$CNT12'" --counterexample "$DEL_PATCH" --out "$ROOT/d12.json" --confirm ) </dev/null 2>&1 )"; RC=$?
expect_unprovable "(d12) no working sha256 tool" sha256_unavailable
[ ! -s "$CNT12" ] && ok "(d12b) the check never ran" || no "(d12b) the check ran although the proof could not be hashed"

# ============================================================================
echo "== (j) SIGTERM during leg 2 ⇒ UNPROVABLE (interrupted), scratch still removed =="
# Leg 1 passes on the working tree (the untracked file exists); the clean scratch copy lacks it, so the
# baseline run sleeps — the prover is TERMed while its scratch worktree exists.
RJ="$(new_repo)"; printf 'local\n' > "$RJ/only-here.txt"
RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"; BEFORE="$(state "$RJ" 2>&1)"
( cd "$RJ" && TMPDIR="$RUN_TMP" exec bash "$PROVER" --check '[ -f only-here.txt ] || sleep 30' \
    --counterexample "$DEL_PATCH" --confirm ) </dev/null > "$ROOT/j.out" 2>&1 &
jpid=$!
i=0; while [ "$i" -lt 100 ] && ! ls -d "$RUN_TMP"/*/wt >/dev/null 2>&1; do sleep 0.1; i=$((i + 1)); done
ls -d "$RUN_TMP"/*/wt >/dev/null 2>&1 && ok "(j0) premise: the scratch worktree existed when the signal was sent" \
  || no "(j0) premise: the scratch worktree never appeared — the interrupt below would not exercise its cleanup"
kill -TERM "$jpid" 2>/dev/null; wait "$jpid"; RC=$?
OUT="$(cat "$ROOT/j.out")"; AFTER="$(state "$RJ" 2>&1)"
expect_unprovable "(j1) interrupted" interrupted
no_leak "(j2) UNPROVABLE (interrupted)"

# ============================================================================
echo "== (e) no --confirm, no TTY ⇒ the canary check never runs =="
RE="$(new_repo)"; CANARY="$ROOT/canary_$$"; rm -f "$CANARY"
RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"; BEFORE="$(state "$RE" 2>&1)"
# Every plausible ambient "confirm" variable is set: none may substitute for an argv --confirm.
OUT="$( ( cd "$RE" && TMPDIR="$RUN_TMP" RULES_CHECK_CONFIRM=1 PROVE_RULE_CHECK_CONFIRM=1 CONFIRM=1 \
          bash "$PROVER" --check "touch '$CANARY'" --counterexample "$DEL_PATCH" --out "$ROOT/e.proof.json" ) </dev/null 2>&1 )"; RC=$?
AFTER="$(state "$RE" 2>&1)"
[ ! -e "$CANARY" ] && ok "(e1) the canary file does not exist — the check never ran" || no "(e1) SECURITY: the check ran without --confirm"
expect_unprovable "(e2) unconfirmed run" needs_confirmation
printf '%s' "$OUT" | grep -qF "touch '$CANARY'" && printf '%s' "$OUT" | grep -qF -- '-TOKEN here' \
  && ok "(e3) the check AND the patch text were displayed before the (refused) confirmation" \
  || no "(e3) check/patch not displayed: $OUT"
no_leak "(e4) UNPROVABLE (needs_confirmation)"

# ============================================================================
echo "== (g) a scratch worktree that cannot be removed ⇒ UNPROVABLE (scratch_leak) =="
RG="$(new_repo)"
OUT="$( ( cd "$RG" && PATH="$SHIM:$PATH" STUB_REAL_GIT="$REAL_GIT" STUB_FAIL_WORKTREE=remove \
          bash "$PROVER" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --out "$ROOT/g.proof.json" --confirm ) </dev/null 2>&1 )"; RC=$?
expect_unprovable "(g1) worktree removal fails (would otherwise be PROVEN)" scratch_leak
jq -e '.verdict=="UNPROVABLE" and .reason=="scratch_leak"' "$ROOT/g.proof.json" >/dev/null 2>&1 \
  && ok "(g2) the proof records the leak, not the PROVEN it overrode" || no "(g2) proof: $(cat "$ROOT/g.proof.json" 2>/dev/null)"
printf '%s' "$OUT" | grep -qF 'git worktree prune' && ok "(g3) the leak report names the remedy" || no "(g3) no remedy named: $OUT"
git -C "$RG" worktree prune >/dev/null 2>&1   # clean the fixture's stale entry

# ============================================================================
echo "== (h) the user-scope rules stamp is never created or changed by a prove run =="
if [ -n "$STAMP_REL" ] && [ "$(cat "$STAMP" 2>/dev/null)" = '{"seed":"untouched"}' ] && [ "$(home_print)" = "$HOME_BEFORE" ]; then
  ok "(h1) after every run above (all four verdicts), the stamp and the whole test HOME are byte-identical"
else
  no "(h1) HOME changed: before [$HOME_BEFORE] after [$(home_print)]"
fi

# ============================================================================
echo "== (i) Validation 2 mutation control: a no-op counterexample leg must break (b) =="
MUT="$ROOT/mutant-prove-rule-check.sh"
sed 's|^run_check "\$WT" counterexample$|RUN_RC=1; RUN_TIMED_OUT=0   # MUTANT: counterexample leg is a no-op reporting exit 1|' "$PROVER" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$PROVER" "$MUT" && bash -n "$MUT" 2>/dev/null; then
  ok "(i1) the mutant is VALID: non-empty, differs from the prover, parses"
  RI="$(new_repo)"
  OUT="$( ( cd "$RI" && bash "$MUT" --check 'true' --counterexample "$DEL_PATCH" --confirm ) </dev/null 2>&1 )"; RC=$?
  [ "$(last_line)" != "verdict: VACUOUS" ] \
    && ok "(i2) CONFIRMED: with the leg a no-op, \`true\` reads '$(last_line)' — (b1) would go RED, so it is load-bearing" \
    || no "(i2) REFUTED: the mutant still reads VACUOUS — (b1) cannot detect a dead counterexample leg"
else
  no "(i1) the mutation did not land (empty, identical, or unparseable) — the control proves nothing"
fi
rm -f "$MUT"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
