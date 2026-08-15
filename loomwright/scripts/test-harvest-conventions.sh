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
#   (J) column 6's US list separator is load-bearing (a multi-path fixture whose ONLY live path is the
#       second array element), and the scope-fidelity denominator filter is DISCLOSED — both the
#       checkable figure and the honest all-findings figure are printed, with the exclusions counted.
#   (K) a derived glob MATCHES its own motivating path, asserted through the real bash `case` matcher
#       rather than by glob shape — with the previously-unfixtured TWO-segment path.
#   (L) a repo-wide (null-scope) rule's findings stay in the honest all-findings denominator.
#   (N) a changed_path containing a space is matched WHOLE, never IFS-word-split.
#   (O) the unmapped remainder itemises every unmapped theme — including one deferred by the cap —
#       with its real reason, and the itemisation sums to its own stated headline.
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
#   (M5) join column 6 with the empty string instead of $US ⇒ (J)'s counts collapse AND (B)'s
#        applies_to derivation breaks. (M5b) is the proof that (B) is no longer self-masking.
#   (M6) restore the old `s[1]"/"s[2]"/*"` reduction for two-segment paths ⇒ the derived glob stops
#        matching its own source path and (K)'s fidelity falls to 0%.
#   (M7) accumulate FIDELITY_ALL_TOTAL only in the scoped branch ⇒ (L)'s 9-finding batch reports as
#        if it had 5, at a flattering 100%.
#   (M8) re-introduce the unquoted word-split over a row's paths ⇒ (N)'s spaced path stops matching.
#   (M9) key the unmapped-remainder breakdown on $RULE_THEMES again ⇒ (O)'s itemisation under-sums
#        its own stated total.

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
  # (A) is the ONE run pointed at the REAL repo root, so it is the only run that could falsify this
  # file's header claim that the fixture runs never touch the real repo's stores. Signature it.
  REAL_SUM_BEFORE="$(store_sum "$REPO_ROOT")"
  OUT="$( bash "$HARVEST" --root "$REPO_ROOT" --session-id "test-a" --no-writer 2>&1 )"; RC=$?
  REAL_SUM_AFTER="$(store_sum "$REPO_ROOT")"
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
  # pw_of <candidate-name> — the project-wide term-overlap score the triage printed for it.
  pw_of() { sed -n "s/^    - $1 (corpus: pw=\([0-9]*\)%.*/\1/p" "$ROOT/a.txt" | head -1; }

  # §2's worked example, asserted as the SEPARATION it actually rests on rather than as absolute
  # bucket membership. WHY, measured: pw is a % of term overlap with the live CLAUDE.md +
  # AGENT_GUIDELINES.md, so prose that touches none of this code moves it — editing CLAUDE.md's
  # banner alone moved one corpus entry 50%→62%, and the cross-role example sits ~7 points over the
  # 85% floor while another entry sits one point under it. An absolute-membership assertion against
  # a live-prose input is a tripwire on the next unrelated doc edit, not a test of this engine. The
  # ordering IS the requirement's claim (§2's table separates these three) and it is what justifies
  # PROJECT_WIDE_PCT sitting between them.
  pw_grad="$(pw_of attack_failclosed_vs_failsafe_split)"
  pw_jq="$(pw_of attack_jq_only_json_injection)"
  pw_gf="$(pw_of golden_fixture_regen)"
  if [ -n "$pw_grad" ] && [ -n "$pw_jq" ] && [ -n "$pw_gf" ]; then
    [ "$pw_grad" -gt "$pw_jq" ] && [ "$pw_grad" -gt "$pw_gf" ] \
      && ok "(a2) the cross-role (corroborating) example outscores both stay-put entries (${pw_grad}% > ${pw_jq}% / ${pw_gf}%) — the separation PROJECT_WIDE_PCT is set between" \
      || no "(a2) separation lost: failclosed=${pw_grad}% jq_only=${pw_jq}% golden_fixture=${pw_gf}%"
    # ...and the gap is WIDE, not a rounding artifact: a threshold can only sit between them if it is.
    gap_jq=$((pw_grad - pw_jq)); gap_gf=$((pw_grad - pw_gf))
    [ "$gap_jq" -ge 20 ] && [ "$gap_gf" -ge 20 ] \
      && ok "(a3) that separation is wide (+${gap_jq} / +${gap_gf} points), so a threshold can sit between them" \
      || no "(a3) separation too narrow to place a threshold: +${gap_jq} / +${gap_gf} points"
    # Where they actually landed today, reported and NOT counted as a pass — the buckets are a
    # function of live prose, so a green counter here would be measuring CLAUDE.md, not this engine.
    echo "  note: today's buckets — failclosed=$(bucket_of attack_failclosed_vs_failsafe_split) jq_only=$(bucket_of attack_jq_only_json_injection) golden_fixture=$(bucket_of golden_fixture_regen)"
  else
    no "(a2/a3) the worked-example entries were not scored: failclosed='$pw_grad' jq_only='$pw_jq' golden_fixture='$pw_gf'"
  fi
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
# NOTE ON THE THIRD RECORD. It used to be single-path (`["src/a/y.md"]`), and that MASKED this
# fixture: its 3 findings alone cleared the 95% APPLIES_TO_COVER threshold, so (b1) still found a
# `src/a/*` glob even if column 6's list separator was destroyed and every multi-path record was
# dropped. It is multi-path now, with the live path SECOND, so no record in this fixture can
# contribute its scope without the separator being intact. Section (J) below makes that a first-class
# assertion with a mutation control; this change stops (B) from quietly passing over the same break.
{ rec 1 "count drift in the banner" '["src/a/x.md","src/a/y.md"]' 3
  rec 2 "version count drift again"  '["src/a/x.md","src/b/z.sh"]' 3
  rec 3 "count bump drift once more" '["gone/old/q.md","src/a/y.md"]' 3
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
echo "(J) column 6's list separator is load-bearing, and the fidelity denominator is disclosed"
# ============================================================================
# WHY THIS SECTION EXISTS. Column 6 of the findings TSV is a US-joined ($'\037') list of the record's
# changed_paths, and BOTH consumers (derive_applies_to, scope_fidelity) split it on that byte. Two
# review channels independently read the emitter's separator as empty (it was a raw 0x1F typed inline
# into the jq program — correct, but invisible in every reader) and reported a critical bug. The
# separator is a named `--arg us` now, and this fixture makes the CONSEQUENCE of losing it a red test
# rather than something only careful reading catches: 74 of the 84 committed ledger records carry more
# than one changed_path, so a destroyed separator silently drops ~26% of the scope evidence while
# every printed number stays plausible.
#
# The fixture is built so that BOTH facts are asserted as COUNTS, not as glob presence:
#   J1 (4 findings): the ONLY live path is the SECOND element of a two-element array — unreachable
#                    unless the separator survives. No other record can supply the scope.
#   J2 (2 findings): two paths, BOTH untracked — the "dead paths" exclusion.
#   J3 (2 findings): no changed_paths at all         — the "no recorded path" exclusion.
# Expected, by construction: applies_to src/a/*; checkable fidelity 4 of 4; over ALL 8 motivating
# findings 50% (4 of 8), excluding 2 no-path and 2 dead-path findings.
RJ="$(new_repo)"
{ rec 1 "count drift in the banner"    '["gone/dead/a.md","src/a/x.md"]'   4
  rec 2 "version count drift again"    '["gone/dead/b.md","gone/dead/c.md"]' 2
  rec 3 "count bump drift once more"   '[]'                                 2
} > "$RJ/.supervisor/postmortem/results.jsonl"
run_harvest "$RJ" --session-id "fx-j" --min-support 4 --cap 3 --no-writer
printf '%s\n' "$OUT" > "$ROOT/j.txt"

# j1 — the CHECKABLE denominator is exactly the 4 findings with a live path, and all 4 are matched.
if grep -qF 'scope fidelity: 100% (4 of the 4 CHECKABLE motivating findings' "$ROOT/j.txt"; then
  ok "(j1) the checkable fidelity denominator is 4 — reachable only through the second element of a multi-path changed_paths array"
else
  no "(j1) expected '4 of the 4 CHECKABLE'; got: $(grep -F 'scope fidelity' "$ROOT/j.txt" | head -1)"
fi
# j2 — the honest figure over ALL motivating findings, and the two exclusions NAMED with their counts.
if grep -qF 'over ALL 8 motivating findings: 50% (4 of 8)' "$ROOT/j.txt" \
   && grep -qF '2 finding(s) come from a ledger record with no changed_paths at all, and 2 have changed_paths of which none is still tracked' "$ROOT/j.txt"; then
  ok "(j2) the all-findings figure (4 of 8, 50%) is printed alongside it, with both exclusions named by count — the denominator filter is disclosed, not silent"
else
  no "(j2) the all-findings figure or the named exclusions are missing: $(grep -F 'over ALL' "$ROOT/j.txt" | head -1)"
fi
# j3 — the aggregate carries both figures too, so a reader of the summary alone is not flattered.
grep -qF 'over ALL motivating findings: 50% (4 of 8)' "$ROOT/j.txt" \
  && ok "(j3) the run summary prints the all-findings aggregate as well as the checkable one" \
  || no "(j3) the summary printed only the checkable aggregate: $(grep -F 'scope fidelity:  aggregate' "$ROOT/j.txt" | head -1)"

# ---- MUTATION CONTROL M5: destroy column 6's list separator ----
# Restore the pre-fix hazard by joining with the empty string. If (j1)/(j2) were vacuous — as the
# pre-existing (B) and (E) fixtures were, by coincidence of their single-path records — the mutant
# would still print the same counts.
MUT5="$ROOT/mut-join.sh"
sed 's@| join($us)) as $cp@| join("")) as $cp@' "$HARVEST" > "$MUT5"
if ! cmp -s "$HARVEST" "$MUT5" && grep -qF 'join("")) as $cp' "$MUT5" && bash -n "$MUT5" 2>/dev/null; then
  M5OUT="$( bash "$MUT5" --root "$RJ" --session-id fx-m5 --min-support 4 --cap 3 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M5OUT" | grep -qF '4 of the 4 CHECKABLE motivating findings'; then
    no "(M5) REFUTED: the mutant still reported 4 checkable findings — (j1)/(j2) are vacuous"
  else
    ok "(M5) CONFIRMED: with the separator destroyed the scope collapses to '$(printf '%s\n' "$M5OUT" | grep -F 'scope fidelity:' | head -1 | sed 's/^ *//')' — (j1)/(j2) are load-bearing"
  fi
else
  no "(M5) the join mutation did not land"
fi
# ...and the same mutant must also break (B), which no longer has a single-path record to mask it.
M5B="$( bash "$MUT5" --root "$R" --session-id fx-m5b --min-support 4 --cap 3 --no-writer 2>&1 )" || true
if printf '%s\n' "$M5B" | grep -qE '^     applies_to: \[.*src/a/\*'; then
  no "(M5b) REFUTED: (B) still derives src/a/* with the separator destroyed — it is masked again"
else
  ok "(M5b) CONFIRMED: the same mutant also breaks (B)'s applies_to derivation — its de-masked third record is load-bearing"
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
# The read-only promise, asserted rather than noted: (A) is the one run pointed at the REAL repo
# root, so it is the only run that could falsify this file's header claim. Compare the store's byte
# signature either side of it. (An earlier form here incremented the pass counter merely because
# `.agent/rules/` EXISTED — it would have stayed green with the store rewritten.)
# SCOPE, stated so this is not read as broader than it is: (A) runs with `--no-writer`, so
# `add-rule.sh` is never invoked and (h8) can only catch the HARVESTER ITSELF writing to the store.
# The writer-side hazard — a composed call that prompts and writes — is covered by (M1a)/(M1b) on
# fixtures, not here.
if [ -n "${REAL_SUM_BEFORE+x}" ]; then
  [ "$REAL_SUM_BEFORE" = "$REAL_SUM_AFTER" ] \
    && ok "(h8) the REAL repo's .agent/rules/ is byte-unchanged across the (A) run against \$REPO_ROOT" \
    || no "(h8) the (A) run MUTATED the real repo's store — the read-only promise is broken"
else
  echo "  skip: (h8) — the (A) real-corpus run did not run, so there is no before/after to compare"
fi

# ---------------------------------------------------------------------------
# (I) AC14's two DENOMINATORS, by value. The miss-share is the single number this batch is
# justified by (it is quoted into /dreaming's report and into HARVEST_DRYRUN_SAMPLE.md), and it was
# previously computed by piping jq's per-record counts through `paste -sd+ - | bc` — making `bc` an
# UNDECLARED dependency that failed OPEN: with `bc` absent the `|| true` + `is_num` fallback printed
# `107/0 (0%)` and exited 0. Nothing asserted a bc-derived VALUE, so nothing caught it: (e1) reads
# coverage (a grep-derived number) and (e7) only asserts the miss-share line is PRESENT.
# The fixture below gives all four counts DISTINCT values, so no swap between them can pass.
# This property is load-bearing and was got WRONG once: the first version of this fixture scored
# 5 / 3 / 3 / 2, in which all-misses and convention_mismatch-total are BOTH 3 — a mutant swapping
# those two produced byte-identical output and passed (i2)-(i4), i.e. the section reproduced the
# very vacuity it was added to close. Keep all four distinct, and keep the two SHARES distinct too.
# ---------------------------------------------------------------------------
echo "(I) AC14 denominators compute by value, over a fixture with four distinct counts"
R10="$(new_repo)"
# rec 1: 3 convention_mismatch (miss) + 1 other-class (miss)
# rec 2: 2 convention_mismatch (no miss) + 2 other-class (no miss)
# ⇒ all findings 8, all misses 4, convention_mismatch 5, cm misses 3 — four distinct values
#   ⇒ 5/8 (62%) and 3/4 (75%) — two distinct shares, neither reducible to the other.
mk_mixed() {
  jq -c -n --argjson num "$1" --argjson cats "$2" \
    '{schema_version:1, ts:"2026-01-01T00:00:00Z", repo:"o/r", number:$num,
      agent_generated_guess:true, review_rounds:1, additions:1, deletions:1, changed_files:1,
      changed_paths:["src/a/x.md"], self_heal_misses:1, categories:$cats,
      flow_stages:{launch_pad:0,worker:1,self_heal:0,unknowable:0}, summary:"s"}'
}
cat_cm_miss='{"round":1,"class":"convention_mismatch","self_heal_miss":true,"flow_stage":"worker","evidence":"count drift"}'
cat_cm_ok='{"round":1,"class":"convention_mismatch","self_heal_miss":false,"flow_stage":"worker","evidence":"count drift"}'
cat_other_miss='{"round":1,"class":"missed_edge_case","self_heal_miss":true,"flow_stage":"worker","evidence":"count drift"}'
cat_other_ok='{"round":1,"class":"missed_edge_case","self_heal_miss":false,"flow_stage":"worker","evidence":"count drift"}'
{
  mk_mixed 1 "[$cat_cm_miss,$cat_cm_miss,$cat_cm_miss,$cat_other_miss]"
  mk_mixed 2 "[$cat_cm_ok,$cat_cm_ok,$cat_other_ok,$cat_other_ok]"
} > "$R10/.supervisor/postmortem/results.jsonl"
run_harvest "$R10" --session-id "fx-i" --min-support 2 --cap 5 --no-writer
printf '%s\n' "$OUT" > "$ROOT/i.txt"
[ "$RC" -eq 0 ] && ok "(i1) the mixed-class fixture run exits 0" || no "(i1) exited $RC"
grep -q '8 findings, 4 self-heal misses' "$ROOT/i.txt" \
  && ok "(i2) the ledger denominators read 8 findings / 4 misses by VALUE (not 0, not the record count)" \
  || no "(i2) wrong denominators: $(grep 'records read WHOLE' "$ROOT/i.txt" | head -1)"
grep -q 'share of all findings:      5/8 (62%)' "$ROOT/i.txt" \
  && ok "(i3) AC14 findings share computes to the constructed 5/8 (62%)" \
  || no "(i3) wrong findings share: $(grep 'share of all findings' "$ROOT/i.txt" | head -1)"
grep -q 'share of self-heal MISSES:  3/4 (75%)' "$ROOT/i.txt" \
  && ok "(i4) AC14 miss share computes to the constructed 3/4 (75%)" \
  || no "(i4) wrong miss share: $(grep 'share of self-heal MISSES' "$ROOT/i.txt" | head -1)"
# `bc` must not be reachable as a dependency at all: run with it stubbed to 127 and require the
# SAME values. Before the fix this printed `5/0 (0%)` and `3/0 (0%)` and still exited 0.
BCSTUB="$ROOT/bcstub"; mkdir -p "$BCSTUB"; printf '#!/bin/sh\nexit 127\n' > "$BCSTUB/bc"; chmod +x "$BCSTUB/bc"
I5OUT="$( PATH="$BCSTUB:$PATH" bash "$HARVEST" --root "$R10" --session-id fx-i5 --min-support 2 --cap 5 --no-writer 2>&1 )"; i5rc=$?
if [ "$i5rc" -eq 0 ] && printf '%s\n' "$I5OUT" | grep -q 'share of self-heal MISSES:  3/4 (75%)'; then
  ok "(i5) with \`bc\` stubbed to exit 127 the denominators are UNCHANGED — bc is no longer a dependency"
else
  no "(i5) a broken \`bc\` still changes the AC14 numbers (rc=$i5rc): $(printf '%s\n' "$I5OUT" | grep 'share of self-heal MISSES' | head -1)"
fi

# ---- MUTATION CONTROL M4: break the denominator counting ----
# Count RECORDS instead of findings. If (i2)-(i4) were vacuous the mutant would still pass them.
MUT4="$ROOT/mut-count.sh"
sed 's@(\[$r\.categories\[\]?\] | length)@1@' "$HARVEST" > "$MUT4"
if ! cmp -s "$HARVEST" "$MUT4" && grep -q 'reduce inputs as $r (0; . + 1)' "$MUT4" && bash -n "$MUT4" 2>/dev/null; then
  M4OUT="$( bash "$MUT4" --root "$R10" --session-id fx-m4 --min-support 2 --cap 5 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M4OUT" | grep -q 'share of all findings:      5/8 (62%)'; then
    no "(M4) REFUTED: the mutant still printed 3/5 — (i2)/(i3) are vacuous"
  else
    ok "(M4) CONFIRMED: counting records instead of findings turns 5/8 into $(printf '%s\n' "$M4OUT" | sed -n 's/.*share of all findings: *//p' | head -1) — (i2)/(i3) are load-bearing"
  fi
else
  no "(M4) the denominator mutation did not land"
fi

# ---------------------------------------------------------------------------
# (K) A DERIVED GLOB MUST MATCH THE PATH IT WAS DERIVED FROM. Asserted as a MATCH under the same
# bash `case` matcher read-rules.sh uses, never as the glob's textual shape — the bug this section
# closes produced a perfectly plausible-LOOKING glob.
# WHAT WAS WRONG: the reducer took `s[1]"/"s[2]"/*"` for every path with >= 2 segments. For a
# TWO-segment path the second segment is the FILE, so `loomwright/plugin.json` became
# `loomwright/plugin.json/*` — a pattern that matches only things nested under a directory named
# `plugin.json`, i.e. never its own source path. Two-segment paths are common here
# (`loomwright/plugin.json`, `.claude-plugin/marketplace.json`), and no fixture used one, which is
# exactly why every existing assertion stayed green.
# ---------------------------------------------------------------------------
echo "(K) a derived glob matches its own motivating path — including the two-segment case"
RK="$(new_repo)"
mkdir -p "$RK/pkg"
printf '{"v":"1"}\n' > "$RK/pkg/manifest.json"
( cd "$RK" && git add -A && git commit -qm two-segment ) >/dev/null 2>&1
{ rec 1 "count drift in the manifest" '["pkg/manifest.json"]' 5; } > "$RK/.supervisor/postmortem/results.jsonl"
run_harvest "$RK" --session-id "fx-k" --min-support 4 --cap 3 --no-writer
printf '%s\n' "$OUT" > "$ROOT/k.txt"
k_globs="$(sed -n 's/^     applies_to: \[\(.*\)\]$/\1/p' "$ROOT/k.txt" | head -1)"
# THE assertion: run the derived glob through the real matcher against the real source path.
k_match=0
oldIFS="$IFS"; IFS=','
for g in $k_globs; do
  g="${g# }"
  case "pkg/manifest.json" in $g) k_match=1 ;; esac
done
IFS="$oldIFS"
if [ "$k_match" -eq 1 ]; then
  ok "(k1) the glob derived from a 2-segment path ([$k_globs]) actually MATCHES pkg/manifest.json under bash \`case\`"
else
  no "(k1) the derived scope [$k_globs] does not match its own motivating path pkg/manifest.json"
fi
grep -qF 'scope fidelity: 100% (5 of the 5 CHECKABLE' "$ROOT/k.txt" \
  && ok "(k2) the harvester's own fidelity check agrees: 5 of 5 checkable findings routed" \
  || no "(k2) fidelity is not 100% on a fixture where every path is live and in scope: $(grep -F 'scope fidelity:' "$ROOT/k.txt" | head -1)"
# A >= 3-segment path is a SEPARATE case and must not regress: there s[2] IS a directory.
grep -qE '^     applies_to: \[.*src/a/\*' "$ROOT/b.txt" \
  && ok "(k3) the >=3-segment case still derives the directory prefix src/a/* (checked against (B), whose paths are 3-segment)" \
  || no "(k3) the >=3-segment derivation regressed"

# ---- MUTATION CONTROL M6: restore the old two-segment reduction ----
MUT6="$ROOT/mut-2seg.sh"
sed 's@s\[1\] "/\*"@s[1] "/" s[2] "/*"@' "$HARVEST" > "$MUT6"
if ! cmp -s "$HARVEST" "$MUT6" && bash -n "$MUT6" 2>/dev/null; then
  M6OUT="$( bash "$MUT6" --root "$RK" --session-id fx-m6 --min-support 4 --cap 3 --no-writer 2>&1 )" || true
  m6_globs="$(printf '%s\n' "$M6OUT" | sed -n 's/^     applies_to: \[\(.*\)\]$/\1/p' | head -1)"
  m6_match=0
  oldIFS="$IFS"; IFS=','
  for g in $m6_globs; do g="${g# }"; case "pkg/manifest.json" in $g) m6_match=1 ;; esac; done
  IFS="$oldIFS"
  if [ "$m6_match" -eq 1 ]; then
    no "(M6) REFUTED: the old reduction still matches its own path — (k1) is vacuous"
  else
    ok "(M6) CONFIRMED: the old reduction yields [$m6_globs], which does NOT match pkg/manifest.json ($(printf '%s\n' "$M6OUT" | grep -F 'scope fidelity:' | head -1 | sed 's/^ *//')) — (k1)/(k2) are load-bearing"
  fi
else
  no "(M6) the two-segment mutation did not land"
fi

# ---------------------------------------------------------------------------
# (L) A NULL-SCOPE RULE'S FINDINGS STAY IN THE HONEST DENOMINATOR. The all-findings figure exists to
# stop the checkable one flattering itself; accumulating it only in the scoped branch dropped the
# repo-wide rules — the population that is unmatchable BY CONSTRUCTION — from both sides at once.
# Fixture, by construction: 5 findings on a live path (scoped, all matched) + 4 findings whose only
# path is dead (repo-wide fallback). Checkable 5 of 5 = 100%; honest 5 of 9 = 55%.
# ---------------------------------------------------------------------------
echo "(L) the all-findings fidelity denominator spans repo-wide rules too"
RL="$(new_repo)"
{ rec 1 "count drift in the banner"  '["src/a/x.md"]'      5
  rec 2 "stale prose in a dead tree" '["gone/dead/a.md"]'  4
} > "$RL/.supervisor/postmortem/results.jsonl"
run_harvest "$RL" --session-id "fx-l" --min-support 4 --cap 3 --no-writer
printf '%s\n' "$OUT" > "$ROOT/l.txt"
grep -qF '1 proposal(s) fell back to a repo-wide (null) scope' "$ROOT/l.txt" \
  && ok "(l1) the fixture does produce exactly one repo-wide proposal alongside one scoped proposal" \
  || no "(l1) the fixture did not produce a null-scope proposal: $(grep -F 'repo-wide (null) scope' "$ROOT/l.txt" | head -1)"
grep -qF 'aggregate 100% (5 of 5 CHECKABLE' "$ROOT/l.txt" \
  && ok "(l2) the CHECKABLE aggregate is 5 of 5 — the repo-wide rule contributes nothing to it, correctly" \
  || no "(l2) wrong checkable aggregate: $(grep -F 'scope fidelity:  aggregate' "$ROOT/l.txt" | head -1)"
if grep -qF 'over ALL motivating findings: 55% (5 of 9)' "$ROOT/l.txt"; then
  ok "(l3) the HONEST aggregate is 5 of 9 — the repo-wide rule's 4 findings are in the denominator, not dropped from it"
else
  no "(l3) the null-scope rule's findings are missing from the honest denominator: $(grep -F 'over ALL motivating findings' "$ROOT/l.txt" | head -1)"
fi

# ---- MUTATION CONTROL M7: accumulate the honest denominator only for SCOPED rules ----
MUT7="$ROOT/mut-fidden.sh"
sed 's@^  FIDELITY_ALL_TOTAL=$((FIDELITY_ALL_TOTAL + fid_n))$@  [ -n "$globs" ] \&\& FIDELITY_ALL_TOTAL=$((FIDELITY_ALL_TOTAL + fid_n))@' "$HARVEST" > "$MUT7"
if ! cmp -s "$HARVEST" "$MUT7" && bash -n "$MUT7" 2>/dev/null; then
  M7OUT="$( bash "$MUT7" --root "$RL" --session-id fx-m7 --min-support 4 --cap 3 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M7OUT" | grep -qF 'over ALL motivating findings: 55% (5 of 9)'; then
    no "(M7) REFUTED: the mutant still reports 5 of 9 — (l3) is vacuous"
  else
    ok "(M7) CONFIRMED: excluding repo-wide rules turns the honest figure into '$(printf '%s\n' "$M7OUT" | sed -n 's/.*over ALL motivating findings: \([0-9]*% ([0-9]* of [0-9]*)\).*/\1/p' | head -1)' — a batch of 9 findings reported as if it had 5"
  fi
else
  no "(M7) the fidelity-denominator mutation did not land"
fi

# ---------------------------------------------------------------------------
# (N) A PATH CONTAINING A SPACE IS ONE PATH. scope_fidelity read its row's paths with an unquoted
# `for p in $paths`, so a spaced path was IFS-shredded into tokens matched independently — which can
# report a match the real matcher would not, and a miss where the whole path does match. This fixture
# takes the second form: a tracked ROOT file `my notes.md` yields the literal glob `my notes.md`,
# which the whole path matches and neither of its two tokens does.
# ---------------------------------------------------------------------------
echo "(N) a changed_path containing a space is matched whole, not word-split"
RN="$(new_repo)"
printf 'notes\n' > "$RN/my notes.md"
( cd "$RN" && git add -A && git commit -qm spaced ) >/dev/null 2>&1
{ rec 1 "count drift in the notes" '["my notes.md"]' 5; } > "$RN/.supervisor/postmortem/results.jsonl"
run_harvest "$RN" --session-id "fx-n" --min-support 4 --cap 3 --no-writer
printf '%s\n' "$OUT" > "$ROOT/n.txt"
grep -qF 'applies_to: [my notes.md]' "$ROOT/n.txt" \
  && ok "(n1) the spaced root path derives the literal glob 'my notes.md'" \
  || no "(n1) unexpected scope: $(grep -F 'applies_to:' "$ROOT/n.txt" | head -1)"
grep -qF 'scope fidelity: 100% (5 of the 5 CHECKABLE' "$ROOT/n.txt" \
  && ok "(n2) all 5 findings on the spaced path are matched — the path is matched whole" \
  || no "(n2) the spaced path was not matched against its own glob: $(grep -F 'scope fidelity:' "$ROOT/n.txt" | head -1)"

# ---- MUTATION CONTROL M8: restore the unquoted word-split ----
# The mutant reads the SAME here-doc, but unquoted-word-splits it exactly as the old
# `for p in $paths` did — the redirection still applies to the whole compound command.
MUT8="$ROOT/mut-split.sh"
sed 's@^    while IFS= read -r p; do$@    for p in $(cat); do@' "$HARVEST" > "$MUT8"
if ! cmp -s "$HARVEST" "$MUT8" && grep -qF 'for p in $(cat); do' "$MUT8" && bash -n "$MUT8" 2>/dev/null; then
  M8OUT="$( bash "$MUT8" --root "$RN" --session-id fx-m8 --min-support 4 --cap 3 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M8OUT" | grep -qF '5 of the 5 CHECKABLE'; then
    no "(M8) REFUTED: the word-splitting version still matches the spaced path — (n2) is vacuous"
  else
    ok "(M8) CONFIRMED: with the unquoted split restored the same fixture reports '$(printf '%s\n' "$M8OUT" | grep -F 'scope fidelity:' | head -1 | sed 's/^ *//')' — (n2) is load-bearing"
  fi
else
  no "(M8) the word-split mutation did not land"
fi

# ---------------------------------------------------------------------------
# (O) THE UNMAPPED REMAINDER ITEMISES EVERY UNMAPPED THEME, WITH ITS REAL REASON. The breakdown was
# keyed on $RULE_THEMES (themes bucketed `rules`), so a theme that reached the support floor and was
# then DEFERRED BY THE CAP was skipped from the list while still counting toward the stated total —
# the itemisation under-summed its own headline. The blanket label "below the support floor" was
# also wrong for a theme excluded as flow_stage=unknowable-only, which can sit far above the floor.
# Fixture: cap=1, so of two rule-eligible themes only one is emitted; plus a third theme above the
# floor whose findings are ALL unknowable. Unmapped = 4 (cap-deferred) + 5 (unknowable) = 9.
# ---------------------------------------------------------------------------
echo "(O) the unmapped remainder itemises cap-deferred and unknowable-only themes, with the right reason"
rec_stage() {   # rec_stage <num> <evidence> <paths-json> <n-findings> <flow_stage>
  jq -c -n --argjson num "$1" --arg ev "$2" --argjson paths "$3" --argjson n "$4" --arg st "$5" \
    '{schema_version:1, ts:"2026-01-01T00:00:00Z", repo:"o/r", number:$num,
      agent_generated_guess:true, review_rounds:1, additions:1, deletions:1, changed_files:1,
      changed_paths:$paths, self_heal_misses:1,
      categories: [range(0;$n) | {round:1, class:"convention_mismatch", self_heal_miss:true,
                                 flow_stage:$st, evidence:$ev}],
      flow_stages:{launch_pad:0,worker:1,self_heal:0,unknowable:0}, summary:"s"}'
}
RO="$(new_repo)"
{ rec       1 "count drift in the banner" '["src/a/x.md"]' 6
  rec       2 "stale prose in the guide"  '["src/b/z.sh"]' 4
  rec_stage 3 "wording nit again"         '["src/a/y.md"]' 5 unknowable
} > "$RO/.supervisor/postmortem/results.jsonl"
run_harvest "$RO" --session-id "fx-o" --min-support 4 --cap 1 --no-writer
printf '%s\n' "$OUT" > "$ROOT/o.txt"
grep -qF 'UNMAPPED REMAINDER: 9 findings, of which 0 matched no theme' "$ROOT/o.txt" \
  && ok "(o1) the stated unmapped remainder is 9 findings, none of them unthemed" \
  || no "(o1) unexpected remainder: $(grep -F 'UNMAPPED REMAINDER' "$ROOT/o.txt" | head -1)"
if grep -qE '^ +doc-currency-drift +4 +\(reached the support floor but was DEFERRED BY THE cap=1' "$ROOT/o.txt"; then
  ok "(o2) the cap-deferred theme appears in the itemisation with its 4 findings and the CAP named as the reason"
else
  no "(o2) the cap-deferred theme is missing or mislabelled: $(grep -F 'doc-currency-drift' "$ROOT/o.txt" | tail -1)"
fi
if grep -qE '^ +naming-framing +5 +\(every finding is flow_stage=unknowable \(support 5 is NOT the reason\)\)' "$ROOT/o.txt"; then
  ok "(o3) the unknowable-only theme is labelled by its real cause, not as 'below the support floor' (its support 5 is ABOVE the floor of 4)"
else
  no "(o3) the unknowable-only theme is mislabelled: $(grep -F 'naming-framing' "$ROOT/o.txt" | tail -1)"
fi
# The itemisation must SUM to the headline it is printed under: 4 + 5 = 9, with 0 unthemed.
o_sum="$(awk '/UNMAPPED REMAINDER/,/dedupe rate|distillation:/' "$ROOT/o.txt" \
          | awk '/^ +[a-z-]+ +[0-9]+ +\(/ { s += $2 } END { print s+0 }')"
[ "$o_sum" = "9" ] \
  && ok "(o4) the itemised lines sum to 9 — the breakdown accounts for its own stated total" \
  || no "(o4) the itemisation sums to $o_sum but the stated remainder is 9 — it under-states its own total"

# ---- MUTATION CONTROL M9: key the breakdown on RULE_THEMES again ----
MUT9="$ROOT/mut-remainder.sh"
sed 's@" $EMITTED_THEMES "@" $RULE_THEMES "@' "$HARVEST" > "$MUT9"
if ! cmp -s "$HARVEST" "$MUT9" && bash -n "$MUT9" 2>/dev/null; then
  M9OUT="$( bash "$MUT9" --root "$RO" --session-id fx-m9 --min-support 4 --cap 1 --no-writer 2>&1 )" || true
  m9_sum="$(printf '%s\n' "$M9OUT" | awk '/UNMAPPED REMAINDER/,/dedupe rate|distillation:/' \
             | awk '/^ +[a-z-]+ +[0-9]+ +\(/ { s += $2 } END { print s+0 }')"
  if [ "$m9_sum" = "9" ]; then
    no "(M9) REFUTED: keying on RULE_THEMES still itemises 9 findings — (o2)/(o4) are vacuous"
  else
    ok "(M9) CONFIRMED: keying on RULE_THEMES itemises only $m9_sum of the 9 unmapped findings — (o2)/(o4) are load-bearing"
  fi
else
  no "(M9) the remainder-key mutation did not land"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
