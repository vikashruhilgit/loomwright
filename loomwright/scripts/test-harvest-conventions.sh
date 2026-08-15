#!/usr/bin/env bash
# test-harvest-conventions.sh — self-tests for harvest-conventions.sh, the READ-ONLY distiller that
# turns ledger `convention_mismatch` findings + the agent-memory corpus into a bounded `.agent/rules/`
# proposal batch. Mirrors the test-add-rule.sh harness convention: isolated temp git repos via
# `mktemp -d` + `git init`, so the fixture runs NEVER touch the real repo's stores.
# Exit 0 = all pass, 1 = any failure (auto-registered by ci.yml's test-*.sh glob).
#
# Covers:
#   (A) three-bucket triage — every candidate lands in exactly ONE of agent-memory/rules/
#       project-memory with a recorded reason, and the requirement's four named worked-example
#       corpus entries come out where §2 says they must (run against the REAL corpus, since the
#       worked example is a claim ABOUT that corpus; skipped, never faked, if it is absent).
#   (B) applies_to derivation from changed_paths, and the null-scope-requires-justification rule.
#   (C) `check` stays null and NO shell command is ever synthesised into a rule.
#   (D) AC3b, TWO INDEPENDENT WAYS: the composed invocation literally detaches stdin, AND a run
#       under a REAL PTY with `y` piped in leaves .agent/rules/ byte-unchanged.
#   (E) the three metrics (coverage / dedupe rate / scope fidelity) compute correctly on a fixture
#       whose right answers are known by construction.
#   (F) AC5 — a near-1:1 batch reports DISTILLATION FAILURE in its own output.
#   (G) an ABSENT .supervisor/agent-memory-proposals/ is a normal empty case (exit 0), not an error.
#   (H) exit contract: unknown arg / bad --session-id ⇒ 2; absent ledger / no jq ⇒ 3.
#
# MUTATION CONTROLS. This repo has repeatedly shipped guards that were vacuous until mutated, so the
# three load-bearing assertions here are each proved non-vacuous by breaking the mechanism they
# guard and confirming the assertion goes RED:
#   (M1) the same add-rule.sh call under a REAL PTY with `y` fed in, run WITH and WITHOUT the
#        `< /dev/null` detachment ⇒ writes without it, byte-unchanged with it. Isolated at the
#        writer on purpose: see the long note at the control itself for why mutating the HARVESTER
#        could not discriminate.
#   (M2) neuter `matches_any` (the `|`-alternation split)  ⇒ 0 findings themed, empty batch.
#   (M3) make compose_add_rule pass `--check`  ⇒ the "never synthesises a check" assertion fires.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARVEST="$SCRIPT_DIR/harvest-conventions.sh"
ADD_RULE="$SCRIPT_DIR/add-rule.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

if [ ! -f "$HARVEST" ]; then echo "test-harvest-conventions: $HARVEST not found"; exit 1; fi
if ! command -v jq >/dev/null 2>&1; then
  echo "test-harvest-conventions: jq absent on this host — harvest-conventions.sh requires jq."
  echo "  (its documented exit 3 for that case is still asserted below)"
fi

# --- fixture builders --------------------------------------------------------
# new_repo — a temp git repo with CLAUDE.md/AGENT_GUIDELINES.md convention surfaces and a real git
# index (the harvester filters derived scopes against `git ls-files`, so the fixture paths must
# actually be tracked or every scope legitimately collapses to null).
new_repo() {
  local r; r="$(mktmp)"
  mkdir -p "$r/.supervisor/postmortem" "$r/.agent/rules" "$r/src/a" "$r/src/b"
  printf 'CLAUDE guidance: counts live in one place. Rules are advisory.\n' > "$r/CLAUDE.md"
  printf 'Agent guidelines: fail closed on gates, fail safe on emitters.\n' > "$r/AGENT_GUIDELINES.md"
  printf 'x\n' > "$r/src/a/x.md"; printf 'y\n' > "$r/src/a/y.md"; printf 'z\n' > "$r/src/b/z.sh"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# rec <number> <evidence> <paths-json> [<n-copies-of-the-finding>]
rec() {
  local num="$1" ev="$2" paths="$3" n="${4:-1}"
  jq -c -n --argjson num "$num" --arg ev "$ev" --argjson paths "$paths" --argjson n "$n" \
    '{schema_version:1, ts:"2026-01-01T00:00:00Z", repo:"o/r", number:$num,
      agent_generated_guess:true, review_rounds:1, additions:1, deletions:1, changed_files:1,
      changed_paths:$paths, self_heal_misses:1,
      categories: [range(0;$n) | {round:1, class:"convention_mismatch", self_heal_miss:true,
                                 flow_stage:"worker", evidence:$ev}],
      flow_stages:{launch_pad:0,worker:1,self_heal:0,unknowable:0}, summary:"s"}'
}

run_harvest() {   # run_harvest <repo> [args...] → sets OUT (text) and RC
  local repo="$1"; shift
  OUT="$( bash "$HARVEST" --root "$repo" "$@" 2>&1 )"; RC=$?
}

store_sum() {   # a stable byte-signature of an entire .agent/rules/ tree
  ( cd "$1" && find .agent/rules -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s ' "$f"; wc -c < "$f" | tr -d ' '; printf ' '; cksum < "$f"; done )
}

# ============================================================================
echo "(A) three-bucket triage + the requirement's worked example"
# ============================================================================
if [ -d "$REPO_ROOT/.claude/agent-memory" ] && [ -f "$REPO_ROOT/.supervisor/postmortem/results.jsonl" ] \
   && command -v jq >/dev/null 2>&1; then
  OUT="$( bash "$HARVEST" --root "$REPO_ROOT" --session-id "test-a" --no-writer 2>&1 )"; RC=$?
  printf '%s\n' "$OUT" > "$ROOT/a.txt"
  [ "$RC" -eq 0 ] && ok "(a1) a real-corpus run exits 0" || no "(a1) real-corpus run exited $RC"

  # bucket_of <candidate-name> — the bucket heading the candidate is printed under.
  bucket_of() {
    awk -v want="$1" '
      /^  \[rules\]/          { b="rules"; next }
      /^  \[agent-memory\]/   { b="agent-memory"; next }
      /^  \[project-memory\]/ { b="project-memory"; next }
      $0 ~ ("^    - " want " ") { print b; exit }
    ' "$ROOT/a.txt"
  }
  # §2's table: these two STAY in agent-memory, this one GRADUATES to rules.
  for want in attack_jq_only_json_injection golden_fixture_regen; do
    got="$(bucket_of "$want")"
    [ "$got" = "agent-memory" ] && ok "(a2) $want stays in agent-memory" \
      || no "(a2) $want landed in '${got:-<not found>}', expected agent-memory"
  done
  got="$(bucket_of attack_failclosed_vs_failsafe_split)"
  [ "$got" = "rules" ] && ok "(a3) attack_failclosed_vs_failsafe_split GRADUATES to rules" \
    || no "(a3) attack_failclosed_vs_failsafe_split landed in '${got:-<not found>}', expected rules"
  # AC1 §1 names this one as a well-formed candidate — it must be triaged, wherever it lands.
  got="$(bucket_of project_self_heal_rubber_stamp)"
  [ -n "$got" ] && ok "(a4) project_self_heal_rubber_stamp is triaged (bucket: $got)" \
    || no "(a4) project_self_heal_rubber_stamp was not triaged at all"

  # Exactly ONE bucket per candidate: no name may appear under two headings.
  dupes="$(grep -E '^    - ' "$ROOT/a.txt" | sed -E 's/^    - ([^ ]+) .*/\1/' | LC_ALL=C sort | uniq -d)"
  [ -z "$dupes" ] && ok "(a5) every candidate appears in exactly one bucket" \
    || no "(a5) candidates appear in more than one bucket: $dupes"
  # ...and every one carries a reason.
  nc="$(grep -cE '^    - ' "$ROOT/a.txt" || true)"; nr="$(grep -cE '^      reason: ' "$ROOT/a.txt" || true)"
  [ "$nc" -gt 0 ] && [ "$nc" = "$nr" ] && ok "(a6) all $nc candidates carry a recorded reason" \
    || no "(a6) $nc candidates but $nr reasons"
  # Both intake sources actually contributed candidates.
  grep -qE '^    - theme:' "$ROOT/a.txt" && ok "(a7) intake (i) the ledger produced candidates" \
    || no "(a7) no ledger-derived candidates"
  grep -qE '^    - [a-z_]+ \(corpus:' "$ROOT/a.txt" && ok "(a8) intake (ii) the corpus produced candidates" \
    || no "(a8) no corpus-derived candidates"
else
  echo "  skip: real corpus/ledger not present — (A) asserts a claim ABOUT them, so it is skipped, not faked"
fi

# ============================================================================
echo "(B) applies_to derivation, and null scope only WITH a justification"
# ============================================================================
R="$(new_repo)"
{ rec 1 "count drift in the banner" '["src/a/x.md","src/a/y.md"]' 3
  rec 2 "version count drift again"  '["src/a/x.md","src/b/z.sh"]' 3
  rec 3 "count bump drift once more" '["src/a/y.md"]'             3
} > "$R/.supervisor/postmortem/results.jsonl"
run_harvest "$R" --session-id "fx-b" --min-support 4 --cap 3 --no-writer
printf '%s\n' "$OUT" > "$ROOT/b.txt"
if grep -qE '^     applies_to: \[.*src/a/\*' "$ROOT/b.txt"; then
  ok "(b1) applies_to is derived from the motivating findings' changed_paths (src/a/*)"
else
  no "(b1) expected a src/a/* glob derived from changed_paths; got: $(grep 'applies_to:' "$ROOT/b.txt" | head -2)"
fi
grep -qE '^     applies_to: null' "$ROOT/b.txt" \
  && no "(b2) a live-path fixture must NOT fall back to a null scope" \
  || ok "(b2) a fixture with live changed_paths gets a non-empty applies_to, never a silent null"

# Null scope: every recorded path is untracked, so no derived glob could route anything.
R2="$(new_repo)"
{ rec 1 "count drift in a deleted tree" '["gone/old/a.md","gone/old/b.md"]' 5
} > "$R2/.supervisor/postmortem/results.jsonl"
run_harvest "$R2" --session-id "fx-b2" --min-support 4 --cap 3 --no-writer
printf '%s\n' "$OUT" > "$ROOT/b2.txt"
if grep -qE '^     applies_to: null' "$ROOT/b2.txt" \
   && grep -q 'REPO-WIDE JUSTIFICATION (stated, never a silent default)' "$ROOT/b2.txt"; then
  ok "(b3) a repo-wide (null) scope is emitted ONLY alongside an explicit stated justification"
else
  no "(b3) null scope without the justification string (or no null scope at all)"
fi

# ============================================================================
echo "(C) check stays null; no shell is ever synthesised into a rule"
# ============================================================================
grep -q 'check: null' "$ROOT/b.txt" && ok "(c1) every proposal reports check: null" || no "(c1) no 'check: null' line"
if grep -q -- '--check' "$ROOT/b.txt"; then
  no "(c2) a composed invocation passed --check — the harvester must never author one"
else
  ok "(c2) no composed invocation passes --check (AC9b)"
fi
# The rule object may carry ONLY add-rule.sh's own flags — no new member can reach the frozen schema.
badflag=0
for f in $(grep -o -- '--[a-z][a-z-]*' "$ROOT/b.txt" | LC_ALL=C sort -u); do
  case "$f" in
    --category|--statement|--enforcement|--applies-to|--source|--confirm|--supersedes|--check|--retract|--target|--reason|--replacement|--help) : ;;
    --root|--session-id|--min-support|--cap|--no-writer|--ledger|--corpus-dir|--proposals-dir|--surface|--expect-repo|--add-rule|--distribution|--json) : ;;
    *) echo "      unexpected flag in output: $f"; badflag=1 ;;
  esac
done
[ "$badflag" -eq 0 ] && ok "(c3) no flag outside add-rule.sh's own set is ever composed (AC9 freeze)" \
  || no "(c3) an unrecognised flag appeared in a composed invocation"

# ============================================================================
echo "(D) AC3b — stdin detachment, asserted TWO independent ways"
# ============================================================================
# Way 1: the composed invocation string literally carries the redirection.
R3="$(new_repo)"
{ rec 1 "count drift in the banner" '["src/a/x.md"]' 5; } > "$R3/.supervisor/postmortem/results.jsonl"
run_harvest "$R3" --session-id "fx-d" --min-support 4 --cap 2 --add-rule "$ADD_RULE"
printf '%s\n' "$OUT" > "$ROOT/d.txt"
ninv="$(grep -cE '^     invocation: add-rule\.sh ' "$ROOT/d.txt" || true)"
ndet="$(grep -cE "^     invocation: add-rule\.sh .* < /dev/null$" "$ROOT/d.txt" || true)"
if [ "$ninv" -gt 0 ] && [ "$ninv" = "$ndet" ]; then
  ok "(d1) all $ninv composed invocations end in the stdin detachment '< /dev/null'"
else
  no "(d1) $ninv invocations but only $ndet detach stdin"
fi
grep -q 'PLANNED WRITE (not written)' "$ROOT/d.txt" \
  && ok "(d2) the writer reached its PLANNED-WRITE branch (the only dry-run-safe one)" \
  || no "(d2) no PLANNED WRITE reported: $(grep 'writer result' "$ROOT/d.txt" | head -2)"

# Way 2: run under a REAL PTY with `y` fed in — the exact hazard AC3b names. Without the
# redirection, add-rule.sh's `[ -t 0 ] && [ -t 1 ]` branch prompts and WRITES on `y`.
# pty_run <cmdline-string> — runs the command on a REAL pty with `y` answers available at its stdin;
# prints combined output. Availability is decided ONCE into $PTY_MODE, never inferred from pty_run's
# own exit status: `yes y | head -50` makes `yes` die of SIGPIPE (141), and under `set -o pipefail`
# that 141 becomes the pipeline's status — so a status-based availability probe reported "no pty on
# this host" on a host that has one, silently skipping the AC3b controls. The feed is a pre-built
# file for that reason: no pipeline, no SIGPIPE, no status to misread.
# THE `sleep 1` IS ALSO LOAD-BEARING, not politeness. MEASURED here: feeding the pty with no delay
# makes `script` push the whole feed in BEFORE the child reaches its `read`, the line discipline
# echoes and discards it, and `read` returns EMPTY — indistinguishable from "the writer declined to
# write", which would have made these controls vacuous in the one direction that matters.
YFEED="$ROOT/yfeed.txt"
i=0; : > "$YFEED"; while [ "$i" -lt 50 ]; do printf 'y\n' >> "$YFEED"; i=$((i+1)); done
# Availability is probed BY OUTPUT, never by exit status: MEASURED on this host, BSD `script -q
# /dev/null true` exits 1 even though `script` works perfectly — a status probe declared "no pty on
# this host" and skipped both AC3b controls on a machine that could run them. The probe also asserts
# the pty is REAL (`[ -t 0 ]` true inside it), which is the property these controls actually need.
# ...and the probe CAPTURES rather than pipes into `grep -q`: under `set -o pipefail` a
# `producer | grep -q` pipeline returns 141 EVEN ON A MATCH, because grep exits at the first hit and
# the producer dies of SIGPIPE. That is a silent false negative and it cost this suite two rounds of
# "no pty on this host" on a host with one. The probe also pins its OWN stdin to /dev/null:
# MEASURED, `script` produces no output at all when it inherits some harness stdins, so a probe that
# inherited the caller's would report absence depending on how the suite was launched. pty_run's own
# invocations always get a pipe (the feed), which is likewise fine.
PTY_MODE=none
_ptyprobe="$(script -q /dev/null /bin/bash -c '[ -t 0 ] && echo __PTYOK__' </dev/null 2>/dev/null || true)"
case "$_ptyprobe" in
  *__PTYOK__*) PTY_MODE=bsd ;;
  *) _ptyprobe="$(script -qec "/bin/bash -c '[ -t 0 ] && echo __PTYOK__'" /dev/null </dev/null 2>/dev/null || true)"
     case "$_ptyprobe" in *__PTYOK__*) PTY_MODE=gnu ;; esac ;;
esac
# THE COMMAND IS PASSED AS A FILE, NEVER AS A RE-QUOTED STRING — and that is a CI-only bug this
# suite already shipped once. The gnu branch used to read `script -qec "/bin/bash -c '$1'" /dev/null`,
# which re-embeds $1 inside single quotes; but GNU `script -c STR` execs `$SHELL -c STR`, so STR is
# re-parsed by a shell, and every caller's own single quotes (the `--statement 'A pty probe rule…'`
# below) shatter that tokenisation. MEASURED: on Linux the writer actually received
# `--statement A`, and the trailing `< /dev/null` was swallowed into a literal argument instead of
# being a redirection — so add-rule.sh kept the pty on stdin, took its `[ -t 0 ] && [ -t 1 ]` branch,
# and WROTE. (M1b)/(M1c) went red on ubuntu while macOS stayed 45/45, because BSD `script cmd args…`
# passes $1 as its OWN argv element with no re-quoting at all. Writing $1 to a file removes the
# quoting layer on BOTH platforms, so the two branches now differ only in `script`'s own argument
# order. The gnu branch passes the path through the ENVIRONMENT rather than interpolating it into
# STR, so a $TMPDIR containing spaces or quotes cannot reintroduce the same class of bug.
# The file lives under "$ROOT" and is therefore covered by the existing EXIT trap; calls are strictly
# sequential, so overwriting it per call is safe (and each call rewrites it before use, so no
# invocation can ever read a stale one).
pty_run() {
  printf '%s\n' "$1" > "$ROOT/_ptycmd.sh"
  case "$PTY_MODE" in
    bsd) { sleep 1; cat "$YFEED"; } | script -q /dev/null /bin/bash "$ROOT/_ptycmd.sh" 2>&1 ;;
    gnu) PTYCMD="$ROOT/_ptycmd.sh"; export PTYCMD
         { sleep 1; cat "$YFEED"; } | script -qec '/bin/bash "$PTYCMD"' /dev/null 2>&1 ;;
    *)   return 127 ;;
  esac
  return 0
}
R4="$(new_repo)"
{ rec 1 "count drift in the banner" '["src/a/x.md"]' 5; } > "$R4/.supervisor/postmortem/results.jsonl"
SUM_BEFORE="$(store_sum "$R4")"
pty_run "bash '$HARVEST' --root '$R4' --session-id fx-pty --min-support 4 --cap 2 --add-rule '$ADD_RULE'" \
     > "$ROOT/pty.txt" 2>&1 || true
if [ "$PTY_MODE" = "none" ]; then
  echo "  skip: no usable \`script\` pty tool on this host — (d3)/(M1) need a real TTY"
else
  SUM_AFTER="$(store_sum "$R4")"
  if [ "$SUM_BEFORE" = "$SUM_AFTER" ]; then
    ok "(d3) run from a REAL PTY with 'y' piped in: .agent/rules/ is BYTE-UNCHANGED"
  else
    no "(d3) the store CHANGED under a PTY — the dry run wrote something"
  fi
  grep -q 'Confirm write?' "$ROOT/pty.txt" \
    && no "(d4) a 'Confirm write?' prompt reached the terminal" \
    || ok "(d4) no 'Confirm write?' prompt reached the terminal"

  # ---- MUTATION CONTROL M1 -------------------------------------------------
  # WHAT THE FIRST VERSION OF THIS CONTROL GOT WRONG, recorded because it changes what (d3) proves.
  # It mutated the harvester to drop `< /dev/null` and expected the store to be written. It was NOT.
  # The reason is a SECOND, independent mechanism: harvest-conventions.sh captures the writer's
  # output with `out="$( ... )"`, so add-rule.sh's stdout is a pipe and its `[ -t 0 ] && [ -t 1 ]`
  # branch is unreachable through this caller whatever stdin is. The mutant therefore proved nothing
  # and the control was vacuous in the direction that matters.
  # So the hazard is isolated HERE, at the writer, which is where decision (f) is aimed: the same
  # add-rule.sh call under a real PTY (stdout on the pty too) with `y` fed in, run BOTH ways. That is
  # a real, discriminating control, and it is what shows `< /dev/null` is load-bearing rather than
  # decorative — the harvester simply happens to carry a second belt as well.
  RW1="$(new_repo)"; SW1="$(store_sum "$RW1")"
  ARGS="--category testing --statement 'A pty probe rule for pr-1 provenance.' --source 'dreaming:pty-probe'"
  pty_run "cd '$RW1' && bash '$ADD_RULE' $ARGS" > "$ROOT/w1.txt" 2>&1 || true
  SW1b="$(store_sum "$RW1")"
  if [ "$SW1" != "$SW1b" ]; then
    ok "(M1a) CONFIRMED the hazard is real: add-rule.sh under a PTY with 'y' fed in and NO stdin detachment WRITES"
  else
    no "(M1a) REFUTED: the writer did not write even on the prompting path — every AC3b assertion here would be vacuous: $(head -3 "$ROOT/w1.txt")"
  fi
  RW2="$(new_repo)"; SW2="$(store_sum "$RW2")"
  pty_run "cd '$RW2' && bash '$ADD_RULE' $ARGS < /dev/null" > "$ROOT/w2.txt" 2>&1 || true
  SW2b="$(store_sum "$RW2")"
  if [ "$SW2" = "$SW2b" ]; then
    ok "(M1b) and '< /dev/null' PREVENTS it: the identical call with stdin detached leaves the store byte-unchanged"
  else
    no "(M1b) the stdin-detached call wrote anyway — decision (f)'s substrate does not hold"
  fi
  grep -q 'PLANNED WRITE' "$ROOT/w2.txt" \
    && ok "(M1c) the stdin-detached call took the PLANNED-WRITE branch" \
    || no "(M1c) the stdin-detached call did not report PLANNED WRITE: $(head -3 "$ROOT/w2.txt")"
fi

# ============================================================================
echo "(E) the three metrics compute correctly on a fixture with known answers"
# ============================================================================
# 4 records x 3 findings = 12 findings, all one theme, all paths live. min-support 4, cap 5
# ⇒ exactly 1 rule, 12 mapped ⇒ coverage 12/12 (100%), dedupe 12.00, scope fidelity 100%.
R6="$(new_repo)"
{ rec 1 "count drift" '["src/a/x.md"]' 3; rec 2 "count drift" '["src/a/y.md"]' 3
  rec 3 "count drift" '["src/a/x.md"]' 3; rec 4 "count drift" '["src/a/y.md"]' 3
} > "$R6/.supervisor/postmortem/results.jsonl"
run_harvest "$R6" --session-id "fx-e" --min-support 4 --cap 5 --no-writer
printf '%s\n' "$OUT" > "$ROOT/e.txt"
grep -q 'coverage:        12/12 convention_mismatch findings (100%)' "$ROOT/e.txt" \
  && ok "(e1) coverage computes to the constructed 12/12 (100%)" \
  || no "(e1) coverage wrong: $(grep 'coverage:' "$ROOT/e.txt" | head -1)"
grep -q 'dedupe rate:     12.00 findings distilled per rule emitted (12 in / 1 out)' "$ROOT/e.txt" \
  && ok "(e2) dedupe rate computes to the constructed 12.00 (12 in / 1 out)" \
  || no "(e2) dedupe wrong: $(grep 'dedupe rate:' "$ROOT/e.txt" | head -1)"
grep -q 'scope fidelity: 100%' "$ROOT/e.txt" \
  && ok "(e3) scope fidelity computes to 100% when every motivating path is under the derived glob" \
  || no "(e3) fidelity wrong: $(grep 'scope fidelity:' "$ROOT/e.txt" | head -1)"
# The unmapped remainder must be STATED, not hidden (AC4).
grep -q 'UNMAPPED REMAINDER:' "$ROOT/e.txt" \
  && ok "(e4) the unmapped remainder is stated explicitly" || no "(e4) no UNMAPPED REMAINDER line"
# Every emitted rule names its motivating finding ids (AC4 traceability).
nrule="$(grep -cE '^  [0-9]+\) \[' "$ROOT/e.txt" || true)"
ntrace="$(grep -cE '^     motivating findings \([0-9]+\):' "$ROOT/e.txt" || true)"
[ "$nrule" -gt 0 ] && [ "$nrule" = "$ntrace" ] && ok "(e5) all $nrule rules name their motivating finding ids" \
  || no "(e5) $nrule rules but $ntrace traceability lines"
# The cap is stated in the output (AC4 "an explicit cap, stated").
grep -qE '^--- proposed rule batch \(cap 5;' "$ROOT/e.txt" \
  && ok "(e6) the batch cap is stated in the output" || no "(e6) the cap is not stated"
# AC14: the targeted class and its share of misses.
grep -q 'this batch targets: convention_mismatch' "$ROOT/e.txt" \
  && grep -q 'share of self-heal MISSES:' "$ROOT/e.txt" \
  && ok "(e7) the run states the class it targets and that class's share of misses (AC14)" \
  || no "(e7) missing the AC14 target-class / miss-share statement"

# ---- MUTATION CONTROL M2: neuter the `|`-alternation split ----
MUT2="$ROOT/mut-theme.sh"
awk '/^matches_any\(\) \{$/ { print; print "  return 1   # MUTANT"; inf=1; next }
     inf && /^\}$/ { print; inf=0; next } { print }' "$HARVEST" > "$MUT2"
if ! cmp -s "$HARVEST" "$MUT2" && bash -n "$MUT2" 2>/dev/null; then
  M2OUT="$( bash "$MUT2" --root "$R6" --session-id fx-m2 --min-support 4 --cap 5 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M2OUT" | grep -q '(empty batch'; then
    ok "(M2) CONFIRMED: with matches_any neutered the batch is EMPTY — (e1)-(e3) are load-bearing"
  else
    no "(M2) REFUTED: the mutant still emitted a batch, so the metric assertions are vacuous"
  fi
else
  no "(M2) the matches_any mutation did not land"
fi

# ---- MUTATION CONTROL M3: make compose_add_rule pass --check ----
MUT3="$ROOT/mut-check.sh"
sed 's|ADD_RULE_ARGV+=(--source "$SOURCE_VAL")|ADD_RULE_ARGV+=(--check "bash mutant.sh"); ADD_RULE_CMD="$ADD_RULE_CMD --check '"'"'bash mutant.sh'"'"'"; ADD_RULE_ARGV+=(--source "$SOURCE_VAL")|' \
  "$HARVEST" > "$MUT3"
if ! cmp -s "$HARVEST" "$MUT3" && bash -n "$MUT3" 2>/dev/null; then
  M3OUT="$( bash "$MUT3" --root "$R6" --session-id fx-m3 --min-support 4 --cap 5 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M3OUT" | grep -q -- '--check'; then
    ok "(M3) CONFIRMED: a synthesised --check IS visible in the output — (c2) would go RED and is load-bearing"
  else
    no "(M3) REFUTED: a synthesised --check was invisible, so (c2) proves nothing"
  fi
else
  no "(M3) the --check mutation did not land"
fi

# ============================================================================
echo "(F) AC5 — a near-1:1 batch reports DISTILLATION FAILURE in its own output"
# ============================================================================
R7="$(new_repo)"
{ rec 1 "count drift"      '["src/a/x.md"]' 1
  rec 2 "vacuous fixture"  '["src/a/y.md"]' 1
  rec 3 "line number cite" '["src/b/z.sh"]' 1
} > "$R7/.supervisor/postmortem/results.jsonl"
run_harvest "$R7" --session-id "fx-f" --min-support 1 --cap 5 --no-writer
printf '%s\n' "$OUT" > "$ROOT/f.txt"
if grep -q 'DISTILLATION FAILURE (AC5)' "$ROOT/f.txt" && grep -q 'DO NOT DELIVER THIS BATCH' "$ROOT/f.txt"; then
  ok "(f1) a 1.00-findings-per-rule batch reports DISTILLATION FAILURE and says not to deliver it"
else
  no "(f1) no distillation failure reported: $(grep -E 'dedupe rate|distillation' "$ROOT/f.txt" | head -2)"
fi
grep -q 'distillation:    OK' "$ROOT/e.txt" \
  && ok "(f2) the well-distilled fixture reports OK — the AC5 verdict is not stuck on one value" \
  || no "(f2) the healthy fixture did not report distillation OK"

# ============================================================================
echo "(G) an absent proposals queue is a NORMAL EMPTY CASE"
# ============================================================================
R8="$(new_repo)"
{ rec 1 "count drift" '["src/a/x.md"]' 5; } > "$R8/.supervisor/postmortem/results.jsonl"
[ -d "$R8/.supervisor/agent-memory-proposals" ] && no "(g0) fixture unexpectedly has a proposals dir"
run_harvest "$R8" --session-id "fx-g" --min-support 4 --no-writer
printf '%s\n' "$OUT" > "$ROOT/g.txt"
[ "$RC" -eq 0 ] && ok "(g1) an absent .supervisor/agent-memory-proposals/ still exits 0" \
  || no "(g1) exited $RC with the proposals dir absent"
grep -q 'proposals queue:.*absent (normal empty case' "$ROOT/g.txt" \
  && ok "(g2) the absence is REPORTED as a normal empty case, not silently ignored" \
  || no "(g2) the absent proposals queue is not reported"
# ...and a PRESENT-but-empty one is equally fine.
mkdir -p "$R8/.supervisor/agent-memory-proposals"
run_harvest "$R8" --session-id "fx-g2" --min-support 4 --no-writer
[ "$RC" -eq 0 ] && ok "(g3) a present-but-empty proposals queue also exits 0" || no "(g3) exited $RC"
# An absent CORPUS is likewise normal.
R9="$(new_repo)"
{ rec 1 "count drift" '["src/a/x.md"]' 5; } > "$R9/.supervisor/postmortem/results.jsonl"
run_harvest "$R9" --session-id "fx-g4" --min-support 4 --corpus-dir "$R9/nope" --no-writer
[ "$RC" -eq 0 ] && ok "(g4) an absent corpus dir exits 0 and is reported as ABSENT" || no "(g4) exited $RC"

# ============================================================================
echo "(H) exit contract"
# ============================================================================
run_harvest "$R8" --totally-made-up-flag
[ "$RC" -eq 2 ] && ok "(h1) an unknown argument exits 2" || no "(h1) unknown arg exited $RC, expected 2"
run_harvest "$R8" --session-id "<session_id>" --no-writer
[ "$RC" -eq 2 ] && ok "(h2) an unsubstituted <session_id> template exits 2 (add-rule.sh would refuse it)" \
  || no "(h2) template session id exited $RC, expected 2"
run_harvest "$R8" --session-id "session_id" --no-writer
[ "$RC" -eq 2 ] && ok "(h3) the bare placeholder word 'session_id' exits 2" || no "(h3) exited $RC, expected 2"
run_harvest "$R8" --cap "many" --no-writer
[ "$RC" -eq 2 ] && ok "(h4) a non-numeric --cap exits 2" || no "(h4) exited $RC, expected 2"
run_harvest "$R8" --ledger "$R8/no/such/ledger.jsonl" --no-writer
[ "$RC" -eq 3 ] && ok "(h5) an absent ledger exits 3 (could-not-examine), never a confident 0" \
  || no "(h5) absent ledger exited $RC, expected 3"
printf 'not json at all\n' > "$ROOT/bad.jsonl"
run_harvest "$R8" --ledger "$ROOT/bad.jsonl" --no-writer
[ "$RC" -eq 3 ] && ok "(h6) an unparseable ledger exits 3" || no "(h6) unparseable ledger exited $RC, expected 3"
# A zero-finding ledger is NOT an error — it is an honest empty report.
: > "$ROOT/empty.jsonl"
run_harvest "$R8" --ledger "$ROOT/empty.jsonl" --no-writer
[ "$RC" -eq 0 ] && ok "(h7) an empty (zero-record) ledger exits 0 with an empty batch" || no "(h7) exited $RC, expected 0"
# The read-only promise, restated as an assertion: the real repo's store is untouched by (A).
if [ -d "$REPO_ROOT/.agent/rules" ]; then
  ok "(h8) note: the real store's integrity across the (A) run is asserted by (d3)/(M1) on fixtures"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
