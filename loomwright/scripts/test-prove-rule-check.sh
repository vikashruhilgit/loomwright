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
#       bad args / scratch baseline fails / --out inside the repo / jq absent with --out / a TMPDIR
#       that cannot hold the scratch dir / the proof write failing after the legs pass ⇒
#       `UNPROVABLE (<reason>)`, exit 2 (AC 4, AC 12).
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
#   (d8d) an in-repo --out on an EARLY refusal (bad_args, counterexample_unreadable/empty) writes no
#       proof into the repo; (d8e) an out-of-repo --out on the same refusal still gets its proof.
#   (k) mutation control, in-suite: a VALID mutant that restores the containment check to AFTER the
#       early exits must turn (d8d) RED while (d8) stays green — so (d8d) is load-bearing.
#   (l) containment is by FILE IDENTITY: on a case-insensitive filesystem an upper-cased in-repo
#       --out (absolute, or relative from an upper-cased cwd) is still out_inside_repo, nothing lands
#       in the repo. Skipped, with a printed reason, on a case-sensitive filesystem (Linux CI).
#   (m) the baseline and leg 2 are independent: a check that writes a marker into its own scratch
#       copy reads VACUOUS (not PROVEN) on a patch that leaves the rule intact, and an identity patch
#       still reads patch_no_effect although the baseline dirtied the copy.
#   (p) HEAD is pinned before leg 1: a check that commits in the user's tree (and in its own copy)
#       still proves against the commit that was HEAD when the run started.
#   (n) the reset cannot be done (the restoring `git checkout` stubbed to fail) ⇒
#       `UNPROVABLE (scratch_reset_failed)`.
#   (q) the reset never moves a shared ref: a check that leaves its scratch copy ON a pre-existing
#       branch (`git checkout feat`) still reads PROVEN, and every ref of the user's repo (`feat`
#       included) is byte-identical after the run; a copy left on a branch AT the pinned sha (the
#       restoring checkout stubbed to a no-op) is refused by the detached-HEAD verify.
#   (o) mutation controls, in-suite, for (l) (m) (n) (p) (q): each VALID mutant reverts one fix, still
#       PROVES a valid run (faithful), and turns its test RED.

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
prove_in() { prove_with "$PROVER" "$@"; }
# prove_with <script> <repo> <args...> — prove_in for a given prover script (the mutation controls).
prove_with() {
  local script="$1" repo="$2"; shift 2
  RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"
  BEFORE="$(state "$repo" 2>&1)"
  OUT="$( ( cd "$repo" && TMPDIR="$RUN_TMP" bash "$script" "$@" ) </dev/null 2>&1 )"; RC=$?
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
home_print() { ( cd "$HOME" && find . -type f -exec cksum {} \; | env LC_ALL=C sort ); }
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
grep -qF 'now leg (current tree' < <(printf '%s' "$OUT") && grep -qF 'counterexample leg (scratch copy of HEAD + patch): exit 1' < <(printf '%s' "$OUT") \
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
  && grep -qF 'counterexample leg: not run' < <(printf '%s' "$OUT") \
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
  if [ -n "${STUB_FAIL_SUBCMD:-}" ] && [ "$a" = "$STUB_FAIL_SUBCMD" ]; then echo "shim: git $a refused" >&2; exit 128; fi
  if [ -n "${STUB_NOOP_SUBCMD:-}" ] && [ "$a" = "$STUB_NOOP_SUBCMD" ]; then exit 0; fi
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
# (d8d) the containment check runs BEFORE every refusal that writes a proof: an in-repo --out on an
# EARLIER exit (bad args, unreadable/empty patch, bad --timeout) still names its own reason, but no
# proof lands in the repo and `git status` is unchanged.
d8d_case() {   # <label> <reason> <out-rel> <prover args...>
  local label="$1" reason="$2" rel="$3"; shift 3
  prove_in "$RD" "$@" --out "$RD/$rel" --confirm
  expect_unprovable "$label" "$reason"
  if [ ! -e "$RD/$rel" ] && [ -z "$(find "$RD" -name '.prove-rule-check.*' -not -path "$RD/.git/*" 2>/dev/null)" ]; then
    ok "$label: no proof (and no temp proof) was written inside the repo"
  else
    no "$label: a proof landed in the repo at $rel"
  fi
  no_leak "$label"
  rm -f "$RD/$rel"
}
mkdir -p "$RD/sub"   # an existing (empty, so status-invisible) in-repo dir
d8d_case "(d8d1) in-repo --out + no --check"            bad_args                  proof.json     --counterexample "$DEL_PATCH"
d8d_case "(d8d2) in-repo --out + unreadable patch"      counterexample_unreadable proof.json     --check 'true' --counterexample "$ROOT/nope.patch"
d8d_case "(d8d3) in-repo --out + --timeout 0"           bad_args                  sub/p.json     --check 'true' --counterexample "$DEL_PATCH" --timeout 0
d8d_case "(d8d4) in-repo --out + empty patch"           counterexample_empty      proof.json     --check 'true' --counterexample "$ROOT/empty.patch"
# (d8e) persistence is NOT over-corrected: an early refusal with an OUT-of-repo --out still writes
# its proof, recording the refusal's own reason.
rm -f "$ROOT/d8e.proof.json"
prove_in "$RD" --counterexample "$DEL_PATCH" --out "$ROOT/d8e.proof.json" --confirm
expect_unprovable "(d8e) out-of-repo --out + no --check" bad_args
jq -e '.verdict=="UNPROVABLE" and .reason=="bad_args"' "$ROOT/d8e.proof.json" >/dev/null 2>&1 \
  && ok "(d8e2) a bad-args run still leaves a proof outside the repo saying so" \
  || no "(d8e2) proof: $(cat "$ROOT/d8e.proof.json" 2>/dev/null)"

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

# (d13) jq absent from PATH with --out ⇒ nothing runs. Every PATH dir holding a jq is replaced by a
# symlink farm of that dir minus jq (one `ln -s dir/*` each), so every other tool resolves unchanged.
nojq_path() {
  local IFS=: d out="" n=0 farm
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/jq" ]; then
      n=$((n + 1)); farm="$ROOT/nojq.$n"; mkdir -p "$farm"
      ln -s "$d"/* "$farm"/ 2>/dev/null
      rm -f "$farm/jq"; d="$farm"
    fi
    out="${out:+$out:}$d"
  done
  printf '%s' "$out"
}
NOJQ_PATH="$(nojq_path)"
if ! PATH="$NOJQ_PATH" command -v jq >/dev/null 2>&1 && PATH="$NOJQ_PATH" command -v git >/dev/null 2>&1; then
  ok "(d13-premise) jq is off the stubbed PATH, git still on it"
else
  no "(d13-premise) the jq-less PATH still resolves jq (or lost git): $NOJQ_PATH"
fi
RD13="$(new_repo)"; CNT13="$ROOT/d13.count"; : > "$CNT13"; rm -f "$ROOT/d13.proof.json"
RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"; BEFORE="$(state "$RD13" 2>&1)"
OUT="$( ( cd "$RD13" && TMPDIR="$RUN_TMP" PATH="$NOJQ_PATH" bash "$PROVER" --check "printf x >> '$CNT13'" \
          --counterexample "$DEL_PATCH" --out "$ROOT/d13.proof.json" --confirm ) </dev/null 2>&1 )"; RC=$?
AFTER="$(state "$RD13" 2>&1)"
expect_unprovable "(d13) jq absent with --out" jq_missing
[ ! -s "$CNT13" ] && [ ! -e "$ROOT/d13.proof.json" ] \
  && ok "(d13b) the check never ran and no proof file was written" \
  || no "(d13b) the check ran or a proof appeared without jq (runs=$(wc -c < "$CNT13" | tr -d '[:space:]'))"
no_leak "(d13c) UNPROVABLE (jq_missing)"

# (d14) a TMPDIR that cannot hold the scratch dir (it does not exist) ⇒ scratch_create_failed, before
# leg 1 runs; the out-of-repo proof still records the reason.
RD14="$(new_repo)"; CNT14="$ROOT/d14.count"; : > "$CNT14"; rm -f "$ROOT/d14.proof.json"
RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"; BEFORE="$(state "$RD14" 2>&1)"
OUT="$( ( cd "$RD14" && TMPDIR="$RUN_TMP/no-such-dir" bash "$PROVER" --check "printf x >> '$CNT14'" \
          --counterexample "$DEL_PATCH" --out "$ROOT/d14.proof.json" --confirm ) </dev/null 2>&1 )"; RC=$?
AFTER="$(state "$RD14" 2>&1)"
expect_unprovable "(d14) TMPDIR does not exist" scratch_create_failed
[ ! -s "$CNT14" ] && ok "(d14b) the check never ran (the scratch dir comes before leg 1)" \
  || no "(d14b) the check ran although no scratch dir could be created"
jq -e '.verdict=="UNPROVABLE" and .reason=="scratch_create_failed"' "$ROOT/d14.proof.json" >/dev/null 2>&1 \
  && ok "(d14c) the proof records UNPROVABLE (scratch_create_failed)" \
  || no "(d14c) proof: $(cat "$ROOT/d14.proof.json" 2>/dev/null)"
no_leak "(d14d) UNPROVABLE (scratch_create_failed)"

# (d15) the proof write fails AFTER every leg passed (would be PROVEN): a jq shim refuses only the
# proof-building call (the one naming counterexample_exit) ⇒ proof_write_failed; a stale file at --out
# is removed, not left to read as a proof, and no temp proof is left beside it.
JQ_SHIM="$ROOT/jq-shim"; mkdir -p "$JQ_SHIM"
cat > "$JQ_SHIM/jq" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = counterexample_exit ]; then echo "shim: jq proof write refused" >&2; exit 5; fi
done
exec "$STUB_REAL_JQ" "$@"
SH
chmod +x "$JQ_SHIM/jq"
RD15="$(new_repo)"; D15_OUT="$(mktemp -d "$ROOT/d15out.XXXXXX")"
printf '{"verdict":"PROVEN","stale":true}\n' > "$D15_OUT/p.json"
RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"; BEFORE="$(state "$RD15" 2>&1)"
OUT="$( ( cd "$RD15" && TMPDIR="$RUN_TMP" PATH="$JQ_SHIM:$PATH" STUB_REAL_JQ="$(command -v jq)" \
          bash "$PROVER" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --out "$D15_OUT/p.json" --confirm ) </dev/null 2>&1 )"; RC=$?
AFTER="$(state "$RD15" 2>&1)"
grep -qF 'counterexample leg (scratch copy of HEAD + patch): exit 1' < <(printf '%s' "$OUT") \
  && ok "(d15-premise) both legs ran and the patch was caught — the run would have been PROVEN" \
  || no "(d15-premise) the legs did not reach PROVEN, so (d15) could pass for the wrong reason: $OUT"
expect_unprovable "(d15) the proof write fails after the checks pass" proof_write_failed
[ -z "$(ls -A "$D15_OUT")" ] \
  && ok "(d15b) the stale --out file is removed and no temp proof is left in the --out directory" \
  || no "(d15b) left in the --out directory: $(ls -A "$D15_OUT")"
no_leak "(d15c) UNPROVABLE (proof_write_failed)"

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
grep -qF "touch '$CANARY'" < <(printf '%s' "$OUT") && grep -qF -- '-TOKEN here' < <(printf '%s' "$OUT") \
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
grep -qF 'git worktree prune' < <(printf '%s' "$OUT") && ok "(g3) the leak report names the remedy" || no "(g3) no remedy named: $OUT"
git -C "$RG" worktree prune >/dev/null 2>&1   # clean the fixture's stale entry

# ============================================================================
echo "== (l) containment by identity: a case-variant in-repo --out is still inside the repo =="
mkdir -p "$ROOT/CiProbe"
if [ -d "$ROOT/ciprobe" ]; then CI_FS=1; else CI_FS=0; fi
RL="$(new_repo)"; RL_UP="$(printf '%s' "$RL" | tr '[:lower:]' '[:upper:]')"
if [ "$CI_FS" -eq 1 ] && [ "$RL_UP" != "$RL" ] && [ "$RL_UP" -ef "$RL" ]; then
  ok "(l0) premise: the filesystem is case-insensitive and the upper-cased path names the fixture repo"
  prove_in "$RL" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --out "$RL_UP/caseproof.json" --confirm
  expect_unprovable "(l1) valid args + an upper-cased absolute in-repo --out" out_inside_repo
  [ ! -e "$RL/caseproof.json" ] && ok "(l1b) no proof landed in the repo" || no "(l1b) the proof landed in the repo via a case-variant path"
  no_leak "(l1c) UNPROVABLE (out_inside_repo, case variant)"
  RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"; BEFORE="$(state "$RL" 2>&1)"
  OUT="$( ( cd "$RL_UP" && TMPDIR="$RUN_TMP" bash "$PROVER" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --out caseproof2.json --confirm ) </dev/null 2>&1 )"; RC=$?
  AFTER="$(state "$RL" 2>&1)"
  expect_unprovable "(l2) valid args + a relative --out from an upper-cased cwd" out_inside_repo
  [ ! -e "$RL/caseproof2.json" ] && ok "(l2b) no proof landed in the repo" || no "(l2b) the proof landed in the repo via an upper-cased cwd"
  no_leak "(l2c) UNPROVABLE (out_inside_repo, case-variant cwd)"
else
  echo "  skip: (l) needs a case-insensitive filesystem; this one is case-sensitive (e.g. Linux CI), where no case variant of the repo path exists"
fi

# ============================================================================
echo "== (m) the baseline and leg 2 are independent: a check's own leftovers earn nothing =="
# The check writes a marker (scratch.log — gitignored, so the user's status is unchanged) and then
# fails whenever the marker already exists. The patch adds an unrelated file; TOKEN stays.
ADD_PATCH="$ROOT/add-unrelated.patch"
cat > "$ADD_PATCH" <<'PATCH'
--- /dev/null
+++ b/src/b.txt
@@ -0,0 +1 @@
+unrelated
PATCH
CHECK_STATEFUL='grep -q TOKEN src/a.txt && test ! -e scratch.log && touch scratch.log'
RM="$(new_repo)"
prove_in "$RM" --check "$CHECK_STATEFUL" --counterexample "$ADD_PATCH" --out "$ROOT/m.proof.json" --confirm
[ "$RC" -eq 1 ] && [ "$(last_line)" = "verdict: VACUOUS" ] \
  && ok "(m1) a marker the baseline left behind is not credited to the patch: VACUOUS, exit 1" \
  || no "(m1) expected VACUOUS/1 (the patch leaves the rule intact), got rc=$RC: $OUT"
jq -e '.baseline_exit==0 and .counterexample_exit==0' "$ROOT/m.proof.json" >/dev/null 2>&1 \
  && ok "(m2) proof: baseline 0, counterexample 0 — leg 2 started from a clean copy" \
  || no "(m2) proof: $(cat "$ROOT/m.proof.json" 2>/dev/null)"
no_leak "(m3) VACUOUS (stateful check)"
# An identity patch (applies, changes nothing): the baseline's marker must not hide that.
ID_PATCH="$ROOT/identity.patch"
cat > "$ID_PATCH" <<'PATCH'
--- a/src/a.txt
+++ b/src/a.txt
@@ -1 +1 @@
-TOKEN here
+TOKEN here
PATCH
RM2="$(new_repo)"
prove_in "$RM2" --check "$CHECK_STATEFUL" --counterexample "$ID_PATCH" --confirm
expect_unprovable "(m4) a no-effect patch after a baseline that dirtied its copy" patch_no_effect
no_leak "(m5) UNPROVABLE (patch_no_effect, stateful check)"

# ============================================================================
echo "== (p) HEAD is pinned before leg 1: a check that commits cannot move what the scratch copies =="
# On its first run in a tree (no scratch.log) the check removes TOKEN and COMMITS — in the user's tree
# during leg 1, and in its detached copy during the baseline. Its exit is the TOKEN grep from BEFORE.
CHECK_DRIFT='grep -q TOKEN src/a.txt; r=$?; if [ ! -e scratch.log ]; then touch scratch.log; sed -i.bak s/TOKEN/gone/ src/a.txt && rm -f src/a.txt.bak && git -c user.email=t@t -c user.name=t commit -qam drift; fi; exit $r'
RP="$(new_repo)"
prove_in "$RP" --check "$CHECK_DRIFT" --counterexample "$DEL_PATCH" --out "$ROOT/p.proof.json" --confirm
[ "$RC" -eq 0 ] && [ "$(last_line)" = "verdict: PROVEN" ] \
  && jq -e '.now_exit==0 and .baseline_exit==0 and .counterexample_exit==1' "$ROOT/p.proof.json" >/dev/null 2>&1 \
  && ok "(p1) the scratch legs copied the commit pinned before leg 1, and leg 2 started from it again: PROVEN" \
  || no "(p1) expected PROVEN with exits 0/0/1, got rc=$RC: $OUT / $(cat "$ROOT/p.proof.json" 2>/dev/null)"
[ "$(git -C "$RP" worktree list --porcelain | grep -c '^worktree ')" = "1" ] && [ -z "$(ls -A "$RUN_TMP" 2>/dev/null)" ] \
  && ok "(p2) no scratch worktree entry or directory left behind" || no "(p2) scratch leak: $(git -C "$RP" worktree list --porcelain)"

# ============================================================================
echo "== (n) the scratch copy cannot be reset ⇒ UNPROVABLE (scratch_reset_failed) =="
RN="$(new_repo)"
RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"; BEFORE="$(state "$RN" 2>&1)"
OUT="$( ( cd "$RN" && TMPDIR="$RUN_TMP" PATH="$SHIM:$PATH" STUB_REAL_GIT="$REAL_GIT" STUB_FAIL_SUBCMD=checkout \
          bash "$PROVER" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --out "$ROOT/n.proof.json" --confirm ) </dev/null 2>&1 )"; RC=$?
AFTER="$(state "$RN" 2>&1)"
expect_unprovable "(n1) the restoring git checkout fails after the baseline (would otherwise be PROVEN)" scratch_reset_failed
jq -e '.reason=="scratch_reset_failed" and .baseline_exit==0 and .counterexample_exit==null' "$ROOT/n.proof.json" >/dev/null 2>&1 \
  && ok "(n2) proof: the baseline ran, leg 2 never did" || no "(n2) proof: $(cat "$ROOT/n.proof.json" 2>/dev/null)"
no_leak "(n3) UNPROVABLE (scratch_reset_failed)"

# ============================================================================
echo "== (q) the reset never moves a shared ref: a branch the check checks out in its copy is untouched =="
# `feat` is one commit ahead of HEAD and shares src/a.txt with it. In its scratch copy (cwd */wt) the
# check checks `feat` out, so the baseline leaves the copy ON that branch; the reset that follows must
# move only the copy's own HEAD — a `reset --hard` would rewrite `feat` (refs are shared with the
# user's repo) and leave the user's commit reachable from the reflog alone.
RQ="$(new_repo)"
( cd "$RQ" && git checkout -qb feat && printf 'feat\n' > src/c.txt && git add src/c.txt \
    && git commit -qm feat && git checkout -q - ) >/dev/null 2>&1
FEAT_SHA="$(git -C "$RQ" rev-parse --verify -q refs/heads/feat 2>/dev/null)"
REFS_BEFORE="$(git -C "$RQ" for-each-ref 2>&1)"
CHECK_BRANCH='case "$PWD" in */wt) git checkout -q feat ;; esac; grep -q TOKEN src/a.txt'
if [ -n "$FEAT_SHA" ] && [ "$FEAT_SHA" != "$(git -C "$RQ" rev-parse HEAD)" ]; then
  ok "(q0) premise: feat ($FEAT_SHA) is a distinct commit ahead of HEAD"
else
  no "(q0) premise: could not build the feat branch fixture"
fi
prove_in "$RQ" --check "$CHECK_BRANCH" --counterexample "$DEL_PATCH" --out "$ROOT/q.proof.json" --confirm
[ "$RC" -eq 0 ] && [ "$(last_line)" = "verdict: PROVEN" ] \
  && ok "(q1) a check that checks a branch out in its copy still reads PROVEN" \
  || no "(q1) expected PROVEN/0, got rc=$RC: $OUT"
[ "$(git -C "$RQ" rev-parse --verify -q refs/heads/feat 2>/dev/null)" = "$FEAT_SHA" ] \
  && [ "$(git -C "$RQ" for-each-ref 2>&1)" = "$REFS_BEFORE" ] \
  && ok "(q2) feat and every other ref of the user's repo are byte-identical after the run" \
  || no "(q2) a shared ref MOVED: feat=$(git -C "$RQ" rev-parse refs/heads/feat 2>&1) (was $FEAT_SHA); refs now [$(git -C "$RQ" for-each-ref 2>&1)]"
no_leak "(q3) PROVEN (check leaves its copy on a branch)"
# (q4) the detached-HEAD verify: the check creates a branch AT the pinned sha in its copy (`switch -c`,
# so the shim's no-op on `checkout` does not swallow it) and the restoring checkout is a no-op ⇒ the
# tree is clean and HEAD resolves to the pinned sha, yet HEAD is a branch — refused, not PROVEN.
CHECK_ONBRANCH='case "$PWD" in */wt) git switch -qc q4-branch ;; esac; grep -q TOKEN src/a.txt'
RQ4="$(new_repo)"
RUN_TMP="$(mktemp -d "$ROOT/tmp.XXXXXX")"; BEFORE="$(state "$RQ4" 2>&1)"
OUT="$( ( cd "$RQ4" && TMPDIR="$RUN_TMP" PATH="$SHIM:$PATH" STUB_REAL_GIT="$REAL_GIT" STUB_NOOP_SUBCMD=checkout \
          bash "$PROVER" --check "$CHECK_ONBRANCH" --counterexample "$DEL_PATCH" --confirm ) </dev/null 2>&1 )"; RC=$?
AFTER="$(state "$RQ4" 2>&1)"
expect_unprovable "(q4) a copy left on a branch at the pinned sha after the restore" scratch_reset_failed
no_leak "(q5) UNPROVABLE (scratch_reset_failed, HEAD on a branch)"

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

# ============================================================================
echo "== (k) mutation control: containment moved back AFTER the early exits must break (d8d) =="
# The mutant is the pre-fix shape: OUT_ABS is set as soon as --out resolves, and the later
# out_inside_repo refusal clears it — so every early exit in between writes the proof into the repo.
MUTK="$ROOT/mutant-k-prove-rule-check.sh"
sed -e 's|^  \[ "\$OUT_INSIDE" -eq 1 \] \|\| OUT_ABS="\$out_cand"$|  OUT_ABS="$out_cand"   # MUTANT: set before containment|' \
    -e 's|^\[ "\$OUT_INSIDE" -eq 0 \] \\$|[ "$OUT_INSIDE" -eq 0 ] \|\| OUT_ABS=""; [ "$OUT_INSIDE" -eq 0 ] \\|' \
    "$PROVER" > "$MUTK"
if [ -s "$MUTK" ] && ! cmp -s "$PROVER" "$MUTK" && bash -n "$MUTK" 2>/dev/null \
   && grep -qF '# MUTANT: set before containment' "$MUTK" && grep -qF '|| OUT_ABS=""; [ "$OUT_INSIDE" -eq 0 ]' "$MUTK"; then
  ok "(k1) the mutant is VALID: non-empty, differs from the prover, parses, both edits landed"
  RK="$(new_repo)"
  OUT="$( ( cd "$RK" && bash "$MUTK" --check 'true' --counterexample "$DEL_PATCH" --out "$RK/proof.json" --confirm ) </dev/null 2>&1 )"; RC=$?
  [ "$(last_line)" = "verdict: UNPROVABLE (out_inside_repo)" ] && [ ! -e "$RK/proof.json" ] \
    && ok "(k2) the mutant still passes (d8) — valid args are refused with no proof written" \
    || no "(k2) the mutant is not the pre-fix shape: (d8) changed ($(last_line))"
  rm -f "$RK/proof.json"
  OUT="$( ( cd "$RK" && bash "$MUTK" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --out "$ROOT/k.proof.json" --confirm ) </dev/null 2>&1 )"; RC=$?
  [ "$(last_line)" = "verdict: PROVEN" ] && [ "$(jq -r .verdict "$ROOT/k.proof.json" 2>/dev/null)" = "PROVEN" ] \
    && ok "(k2b) the mutant still proves an out-of-repo valid-args run (only the guard ordering differs)" \
    || no "(k2b) the mutant broke the valid path, so it is not the pre-fix shape ($(last_line))"
  OUT="$( ( cd "$RK" && bash "$MUTK" --counterexample "$DEL_PATCH" --out "$RK/proof.json" --confirm ) </dev/null 2>&1 )"; RC=$?
  [ -e "$RK/proof.json" ] \
    && ok "(k3) CONFIRMED: the mutant writes a bad_args proof INTO the repo — (d8d1) would go RED, so it is load-bearing" \
    || no "(k3) REFUTED: the mutant writes no in-repo proof — (d8d) cannot detect a write ahead of its guard"
else
  no "(k1) the mutation did not land (empty, identical, unparseable, or an edit missed) — the control proves nothing"
fi
rm -f "$MUTK"

# ============================================================================
echo "== (o) mutation controls for (l) (m) (n) (p) (q): revert one fix, the test must go RED =="
# mutant_ok <file> <marker> — VALID: non-empty, differs from the prover, parses, the edit landed.
mutant_ok() { [ -s "$1" ] && ! cmp -s "$PROVER" "$1" && bash -n "$1" 2>/dev/null && grep -qF -- "$2" "$1"; }
# faithful <file> <label> — the mutant still PROVES a plain valid run, so only the reverted fix differs.
faithful() {
  local r; r="$(new_repo)"
  prove_with "$1" "$r" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --out "$ROOT/faithful.proof.json" --confirm
  [ "$(last_line)" = "verdict: PROVEN" ] && ok "$2: the mutant still PROVES a valid run (faithful)" \
    || no "$2: the mutant broke a valid run ($(last_line)) — it is not a one-fix revert"
}

# (o1) no reset between the baseline and leg 2 (the pre-fix shape) ⇒ (m1), (m4), (n1) go RED.
MUT_R="$ROOT/mutant-reset-prove-rule-check.sh"
sed 's|^reset_scratch_copy$|:   # MUTANT: no reset between the baseline and leg 2|' "$PROVER" > "$MUT_R"
if mutant_ok "$MUT_R" '# MUTANT: no reset between the baseline and leg 2'; then
  ok "(o1a) the no-reset mutant is VALID: non-empty, differs from the prover, parses, the edit landed"
  faithful "$MUT_R" "(o1b)"
  prove_with "$MUT_R" "$(new_repo)" --check "$CHECK_STATEFUL" --counterexample "$ADD_PATCH" --confirm
  [ "$(last_line)" = "verdict: PROVEN" ] \
    && ok "(o1c) CONFIRMED: without the reset the stateful check reads PROVEN — (m1) would go RED" \
    || no "(o1c) REFUTED: the no-reset mutant reads '$(last_line)' — (m1) cannot detect a missing reset"
  prove_with "$MUT_R" "$(new_repo)" --check "$CHECK_STATEFUL" --counterexample "$ID_PATCH" --confirm
  [ "$(last_line)" != "verdict: UNPROVABLE (patch_no_effect)" ] \
    && ok "(o1d) CONFIRMED: without the reset the identity patch reads '$(last_line)' — (m4) would go RED" \
    || no "(o1d) REFUTED: the no-reset mutant still reads patch_no_effect — (m4) is not load-bearing"
  OUT="$( ( cd "$(new_repo)" && PATH="$SHIM:$PATH" STUB_REAL_GIT="$REAL_GIT" STUB_FAIL_SUBCMD=checkout \
            bash "$MUT_R" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --confirm ) </dev/null 2>&1 )"
  [ "$(last_line)" != "verdict: UNPROVABLE (scratch_reset_failed)" ] \
    && ok "(o1e) CONFIRMED: without the reset a failing restoring checkout reads '$(last_line)' — (n1) would go RED" \
    || no "(o1e) REFUTED: the no-reset mutant still reads scratch_reset_failed"
else
  no "(o1a) the no-reset mutation did not land — the control proves nothing"
fi
rm -f "$MUT_R"

# (o2) the scratch worktree copies whatever HEAD is AFTER leg 1 (the pre-fix shape) ⇒ (p1) goes RED.
MUT_P="$ROOT/mutant-pin-prove-rule-check.sh"
sed 's|worktree add --detach "\$WT" "\$HEAD_SHA" >|worktree add --detach "$WT" HEAD >|' "$PROVER" > "$MUT_P"
if mutant_ok "$MUT_P" 'worktree add --detach "$WT" HEAD >'; then
  ok "(o2a) the unpinned-HEAD mutant is VALID: non-empty, differs from the prover, parses, the edit landed"
  faithful "$MUT_P" "(o2b)"
  prove_with "$MUT_P" "$(new_repo)" --check "$CHECK_DRIFT" --counterexample "$DEL_PATCH" --confirm
  [ "$(last_line)" != "verdict: PROVEN" ] \
    && ok "(o2c) CONFIRMED: with HEAD read after leg 1 the drift check reads '$(last_line)' — (p1) would go RED" \
    || no "(o2c) REFUTED: the unpinned mutant still PROVES — (p1) cannot detect an unpinned HEAD"
else
  no "(o2a) the unpinned-HEAD mutation did not land — the control proves nothing"
fi
rm -f "$MUT_P"

# (o3) the reset targets the copy's own (moved) HEAD instead of the pinned sha ⇒ (p1) goes RED.
MUT_S="$ROOT/mutant-resetsha-prove-rule-check.sh"
sed 's|checkout -q --force --detach "\$HEAD_SHA" >|checkout -q --force --detach >|' "$PROVER" > "$MUT_S"
if mutant_ok "$MUT_S" 'checkout -q --force --detach >'; then
  ok "(o3a) the reset-to-own-HEAD mutant is VALID: non-empty, differs from the prover, parses, the edit landed"
  faithful "$MUT_S" "(o3b)"
  prove_with "$MUT_S" "$(new_repo)" --check "$CHECK_DRIFT" --counterexample "$DEL_PATCH" --confirm
  [ "$(last_line)" != "verdict: PROVEN" ] \
    && ok "(o3c) CONFIRMED: resetting to the copy's moved HEAD reads '$(last_line)' — (p1) would go RED" \
    || no "(o3c) REFUTED: the mutant still PROVES — (p1) cannot detect a reset to the wrong commit"
else
  no "(o3a) the reset-to-own-HEAD mutation did not land — the control proves nothing"
fi
rm -f "$MUT_S"

# (o5) the reset is `reset --hard` again with no detached-HEAD verify (the iteration-2 shape) ⇒ (q2)
# goes RED (feat moved) and (q4) goes RED (the branch at the pinned sha is not refused).
MUT_Q="$ROOT/mutant-resethard-prove-rule-check.sh"
sed -e 's|checkout -q --force --detach "\$HEAD_SHA" >|reset -q --hard "$HEAD_SHA" >|' \
    -e 's|^  if git -C "\$WT" symbolic-ref -q HEAD .*$|  :   # MUTANT: reset --hard, no detached-HEAD verify|' \
    "$PROVER" > "$MUT_Q"
if mutant_ok "$MUT_Q" '# MUTANT: reset --hard, no detached-HEAD verify' && grep -qF 'reset -q --hard "$HEAD_SHA" >' "$MUT_Q"; then
  ok "(o5a) the reset --hard mutant is VALID: non-empty, differs from the prover, parses, both edits landed"
  faithful "$MUT_Q" "(o5b)"
  RQM="$(new_repo)"
  ( cd "$RQM" && git checkout -qb feat && printf 'feat\n' > src/c.txt && git add src/c.txt \
      && git commit -qm feat && git checkout -q - ) >/dev/null 2>&1
  FEAT_M="$(git -C "$RQM" rev-parse --verify -q refs/heads/feat 2>/dev/null)"
  prove_with "$MUT_Q" "$RQM" --check "$CHECK_BRANCH" --counterexample "$DEL_PATCH" --confirm
  FEAT_M_AFTER="$(git -C "$RQM" rev-parse --verify -q refs/heads/feat 2>/dev/null)"
  [ -n "$FEAT_M" ] && [ "$FEAT_M_AFTER" != "$FEAT_M" ] \
    && ok "(o5c) CONFIRMED: reset --hard moved feat $FEAT_M -> $FEAT_M_AFTER ('$(last_line)') — (q2) would go RED" \
    || no "(o5c) REFUTED: the reset --hard mutant left feat at '$FEAT_M_AFTER' — (q2) is not load-bearing"
  OUT="$( ( cd "$(new_repo)" && PATH="$SHIM:$PATH" STUB_REAL_GIT="$REAL_GIT" STUB_NOOP_SUBCMD=reset \
            bash "$MUT_Q" --check "$CHECK_ONBRANCH" --counterexample "$DEL_PATCH" --confirm ) </dev/null 2>&1 )"
  [ "$(last_line)" != "verdict: UNPROVABLE (scratch_reset_failed)" ] \
    && ok "(o5d) CONFIRMED: without the detached-HEAD verify a copy on a branch reads '$(last_line)' — (q4) would go RED" \
    || no "(o5d) REFUTED: the mutant still refuses a copy left on a branch — (q4) is not load-bearing"
else
  no "(o5a) the reset --hard mutation did not land — the control proves nothing"
fi
rm -f "$MUT_Q"

# (o4) string-prefix containment (the pre-fix shape) ⇒ (l1) goes RED. Case-insensitive hosts only.
if [ "$CI_FS" -eq 1 ] && [ "$RL_UP" != "$RL" ] && [ "$RL_UP" -ef "$RL" ]; then
  MUT_C="$ROOT/mutant-case-prove-rule-check.sh"
  sed 's|^    same_file_or_ancestor "\$out_dir" "\$TOP" && OUT_INSIDE=1$|    case "$out_cand/" in "$TOP/"*) OUT_INSIDE=1 ;; esac   # MUTANT: string-prefix containment|' "$PROVER" > "$MUT_C"
  if mutant_ok "$MUT_C" '# MUTANT: string-prefix containment'; then
    ok "(o4a) the string-containment mutant is VALID: non-empty, differs from the prover, parses, the edit landed"
    faithful "$MUT_C" "(o4b)"
    RO="$(new_repo)"
    prove_with "$MUT_C" "$RO" --check 'true' --counterexample "$DEL_PATCH" --out "$RO/proof.json" --confirm
    [ "$(last_line)" = "verdict: UNPROVABLE (out_inside_repo)" ] && [ ! -e "$RO/proof.json" ] \
      && ok "(o4c) the mutant still refuses a same-case in-repo --out ((d8) stays green)" \
      || no "(o4c) the mutant changed (d8): $(last_line)"
    RO_UP="$(printf '%s' "$RO" | tr '[:lower:]' '[:upper:]')"
    prove_with "$MUT_C" "$RO" --check "$CHECK_TOKEN" --counterexample "$DEL_PATCH" --out "$RO_UP/caseproof.json" --confirm
    [ -e "$RO/caseproof.json" ] \
      && ok "(o4d) CONFIRMED: the string-prefix mutant writes the proof INTO the repo ('$(last_line)') — (l1) would go RED" \
      || no "(o4d) REFUTED: the mutant wrote no in-repo proof — (l1) is not load-bearing"
  else
    no "(o4a) the string-containment mutation did not land — the control proves nothing"
  fi
  rm -f "$MUT_C"
else
  echo "  skip: (o4) needs a case-insensitive filesystem, like (l)"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
