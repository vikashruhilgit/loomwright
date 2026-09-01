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
#   (H) exit contract: unknown arg / bad --session-id ⇒ 2; absent ledger ⇒ 3. The `no jq ⇒ 3` half
#       of that claim was documented here but never tested; it is now asserted by (q1), in (Q).
#   (Q) the fail-closed jq gate (asserted, not just documented), and a `categories[]` array carrying
#       non-object elements — handled, never a hard exit-3 failure on an otherwise readable ledger.
#   (J) column 6's US list separator is load-bearing (a multi-path fixture whose ONLY live path is the
#       second array element), and the scope-fidelity denominator filter is DISCLOSED — both the
#       checkable figure and the honest all-findings figure are printed, with the exclusions counted.
#   (K) a derived glob MATCHES its own motivating path, asserted through the real bash `case` matcher
#       rather than by glob shape — with the previously-unfixtured TWO-segment path.
#   (L) a repo-wide (null-scope) rule's findings stay in the honest all-findings denominator.
#   (N) a changed_path containing a space is matched WHOLE, never IFS-word-split.
#   (O) the unmapped remainder itemises every unmapped theme — including one deferred by the cap —
#       with its real reason, and the itemisation sums to its own stated headline.
#   (R) the repo-wide justification renders as ONE line with the right count (the `grep -c … ||
#       echo 0` two-line trap), states the ZERO-path case in kind, and a non-object TOP-LEVEL
#       record is skipped-and-counted rather than killing the whole harvest.
#   (S) an agent-memory reason names the test that ACTUALLY excluded the candidate: a normative=0
#       entry is excluded by the normative test at any pw, so its reason may not assert a
#       "(< PROJECT_WIDE_PCT%)" comparison its own printed pw refutes. Asserted by shape over both
#       the fixture transcript and the real-corpus one.
#   (T) the store dedupe pass — a proposal whose claim a LIVE `.agent/rules/` rule already makes is
#       reported as an already-covered DEFERRAL naming that rule's id, spends no cap slot, and keeps
#       its findings in every denominator (coverage falls; it is not quietly shrunk). Over a fixture
#       whose live rule is a PARAPHRASE of the harvester's own committed statement, proved to share
#       no literal with it, so an exact-string dedupe could not pass the section. Also: the
#       all-covered empty batch still PRINTS its deferrals and names the right cause, `--dup-pct 101`
#       is the non-deferring measurement run the header documents, and an unparseable/absent store is
#       fail-safe but DISCLOSED rather than silently treated as clean. (t22)-(t26) cover the
#       COMBINED empty batch — one theme turned away by the cap AND one already covered — the case
#       in which the diagnostic must name both causes.
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
#  (M11) strip the `select(type=="object")` type guard from ALL_MISSES ⇒ (Q)'s mixed-array fixture
#        dies exit 3 "could not count findings/misses" again.
#  (M12) restore the `|| echo 0` capture behind the repo-wide justification ⇒ (R)'s zero-path
#        fixture stops rendering a whole justification line.
#  (M13) strip the record-level `select((.value|type)=="object")` from the extractor ⇒ (R)'s
#        non-object records die exit 3 "could not extract findings from the ledger" again.
#  (M14) strip the record-level guard from ALL_FINDINGS/ALL_MISSES ⇒ the same fixture still dies,
#        one level down. The point of (d) in AGENT_GUIDELINES' verification gate, asserted: fixing
#        only the first consumer of a malformed input moves the crash rather than removing it.
#  (M15) collapse the corpus agent-memory reason back into ONE shared template (`elif false`) ⇒ the
#        non-normative fixture asserts "only 100% … (< 85%)" again and (s1)/(s3) go RED.
#  (M10) make the cap-deferred arm of the empty-batch diagnostic unreachable (i.e. restore the
#        unconditional support-floor sentence) ⇒ (P)'s `--cap 0` run blames the support floor again,
#        one line under a header stating the themes were deferred by the cap.
#  (M16) remove the store dedupe decision (`if false` at the comparison) ⇒ (T)'s already-covered
#        theme is proposed as a rule again, exactly as it was before the pass existed.
#  (M17) credit a deferred theme's findings to the PROPOSED batch instead of to the already-covered
#        figure ⇒ (T)'s coverage flatters itself to 10/10 (100%) for a batch that proposed one rule
#        over four findings.
#  (M18) make the already-covered CONTINUATION line under the cap sentence unreachable (its guard
#        always-true) ⇒ (T)'s combined --cap 0 run reports only the cap and loses the second cause.
#        That line was reachable, correct, and NEVER EXECUTED until (t24): every rule-seeding
#        fixture ran at --cap 5 and the only --cap 0 fixture seeded no rule.

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
#   ⇒ 5/8 (63%) and 3/4 (75%) — two distinct shares, neither reducible to the other.
# 5/8 is 62.5 EXACTLY, i.e. the one boundary where pct()'s half-up rule and Python's half-to-even
# `round()` disagree (63 here, 62 there). That is stated as an honest limit at pct() itself; this
# fixture is the case that exercises it, so the expectation is 63 on purpose, not a stale number.
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
grep -q 'share of all findings:      5/8 (63%)' "$ROOT/i.txt" \
  && ok "(i3) AC14 findings share computes to the constructed 5/8 (63%)" \
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
# NOTE: this pattern must track ALL_FINDINGS' jq program verbatim — it grew a record-level
# `select((.|type)=="object")` when a top-level bare scalar/array was found to kill the run, and a
# stale pattern here does not fail loudly, it just stops landing (the `did not land` arm below is
# what caught that). The `grep -q` guard on the mutant is the second half of the same check.
sed 's@(\[$r | select((\.|type)=="object") | \.categories\[\]?\] | length)@1@' "$HARVEST" > "$MUT4"
if ! cmp -s "$HARVEST" "$MUT4" && grep -q 'reduce inputs as $r (0; . + 1)' "$MUT4" && bash -n "$MUT4" 2>/dev/null; then
  M4OUT="$( bash "$MUT4" --root "$R10" --session-id fx-m4 --min-support 2 --cap 5 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M4OUT" | grep -q 'share of all findings:      5/8 (63%)'; then
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
# path is dead (repo-wide fallback). Checkable 5 of 5 = 100%; honest 5 of 9 = 56%.
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
if grep -qF 'over ALL motivating findings: 56% (5 of 9)' "$ROOT/l.txt"; then
  ok "(l3) the HONEST aggregate is 5 of 9 — the repo-wide rule's 4 findings are in the denominator, not dropped from it"
else
  no "(l3) the null-scope rule's findings are missing from the honest denominator: $(grep -F 'over ALL motivating findings' "$ROOT/l.txt" | head -1)"
fi

# ---- MUTATION CONTROL M7: accumulate the honest denominator only for SCOPED rules ----
MUT7="$ROOT/mut-fidden.sh"
sed 's@^  FIDELITY_ALL_TOTAL=$((FIDELITY_ALL_TOTAL + fid_n))$@  [ -n "$globs" ] \&\& FIDELITY_ALL_TOTAL=$((FIDELITY_ALL_TOTAL + fid_n))@' "$HARVEST" > "$MUT7"
if ! cmp -s "$HARVEST" "$MUT7" && bash -n "$MUT7" 2>/dev/null; then
  M7OUT="$( bash "$MUT7" --root "$RL" --session-id fx-m7 --min-support 4 --cap 3 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M7OUT" | grep -qF 'over ALL motivating findings: 56% (5 of 9)'; then
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

# ---------------------------------------------------------------------------
# (P) AN EMPTY BATCH NAMES THE CAUSE IT MEASURED, NOT ONE IT ASSUMED. The empty-batch line asserted
# "no theme reached the support floor" UNCONDITIONALLY. With `--cap 0` (which passes `is_num`, so it
# is reachable input) themes DO reach the floor and are turned away by the bound — the header line
# printed one line above says so — and the diagnostic contradicted it. Both arms are asserted here:
# the cap arm must name the cap, and the genuine thin-evidence arm must keep the floor sentence.
# Reuses (O)'s fixture, whose themes sit above a support floor of 4.
# ---------------------------------------------------------------------------
echo "(P) the empty-batch diagnostic branches on the measured cause"
run_harvest "$RO" --session-id "fx-p" --min-support 4 --cap 0 --no-writer
printf '%s\n' "$OUT" > "$ROOT/p.txt"
[ "$RC" -eq 0 ] && ok "(p1) --cap 0 is accepted input and exits 0" || no "(p1) --cap 0 exited $RC, expected 0"
if grep -qE '\(empty batch — but NOT for want of evidence: [1-9][0-9]* theme\(s\) reached the 4-finding support floor and were deferred by the cap=0 batch bound' "$ROOT/p.txt"; then
  ok "(p2) the --cap 0 empty batch names the CAP as the cause and counts the themes it deferred"
else
  no "(p2) the --cap 0 empty batch does not name the cap: $(grep -F '(empty batch' "$ROOT/p.txt" | head -1)"
fi
grep -qF 'no theme reached the support floor' "$ROOT/p.txt" \
  && no "(p3) the --cap 0 run still asserts the support floor as the cause — it contradicts its own header line" \
  || ok "(p3) the --cap 0 run does NOT blame the support floor (4 findings/theme cleared it)"
# The other arm must survive the branch: a floor nothing can reach is still reported as the floor.
run_harvest "$RO" --session-id "fx-p2" --min-support 9999 --cap 5 --no-writer
if printf '%s\n' "$OUT" | grep -qF '(empty batch — no theme reached the support floor'; then
  ok "(p4) a genuinely thin corpus still reports the support floor — the branch did not overwrite the true case"
else
  no "(p4) the support-floor arm was lost: $(printf '%s\n' "$OUT" | grep -F '(empty batch' | head -1)"
fi

# ---- MUTATION CONTROL M10: make the cap arm unreachable (the unconditional message restored) ----
MUT10="$ROOT/mut-emptycause.sh"
sed 's@\[ "$CAP_DEFERRED" -gt 0 \]@[ "$CAP_DEFERRED" -gt 999999 ]@' "$HARVEST" > "$MUT10"
if ! cmp -s "$HARVEST" "$MUT10" && bash -n "$MUT10" 2>/dev/null; then
  M10OUT="$( bash "$MUT10" --root "$RO" --session-id fx-m10 --min-support 4 --cap 0 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M10OUT" | grep -qF 'no theme reached the support floor'; then
    ok "(M10) CONFIRMED: with the cap arm unreachable the --cap 0 run blames the support floor again — (p2)/(p3) are load-bearing"
  else
    no "(M10) REFUTED: the unconditional message did not reappear — (p2)/(p3) may be vacuous"
  fi
else
  no "(M10) the empty-batch-cause mutation did not land"
fi

# ============================================================================
echo "(Q) the jq fail-closed gate, and a categories[] array carrying non-object elements"
# ============================================================================
# (q1) THE `no jq ⇒ 3` HALF OF (H), WHICH WAS DOCUMENTED BUT NEVER TESTED. The section docstring
# above has always claimed it; nothing asserted it. Only `bc` was ever stubbed, by (i5), for the
# unrelated reason that bc had once been an undeclared dependency. So the fail-closed jq gate — the
# one that stops this tool printing coverage over a ledger it could not read — was unguarded, and a
# regression that made it fail OPEN (exit 0 with a confident 0%) would have gone undetected.
#
# THE TRAP, recorded because it produced a convincing false green while this was being written:
# emptying or over-narrowing PATH makes `bash` ITSELF unfindable, and the run then dies 127 from the
# SHELL, not from the gate — a non-zero status that looks like a pass if you only compare against 0.
# So the interpreter is invoked by ABSOLUTE path, and the assertion is on the exact code 3.
JQSTUB="$ROOT/jqstub"; mkdir -p "$JQSTUB"
BASH_ABS="$(command -v bash)"
# A PATH holding only a directory with no `jq` in it: `command -v jq` fails, while the absolute
# interpreter still starts. Coreutils the script uses are resolved from this PATH too, so the gate
# must fire before any of them matter — which it does, it is the first thing after arg parsing.
Q1OUT="$( PATH="$JQSTUB" "$BASH_ABS" "$HARVEST" --root "$R8" --session-id fx-q1 --no-writer 2>&1 )"; q1rc=$?
if [ "$q1rc" -eq 3 ]; then
  ok "(q1) with jq unfindable on PATH the run exits 3 (could-not-examine), never a confident 0 — the documented fail-closed gate is now asserted"
else
  no "(q1) jq-absent run exited $q1rc, expected 3: $(printf '%s\n' "$Q1OUT" | head -2)"
fi
[ "$q1rc" -ne 127 ] || echo "  note: 127 means the interpreter itself was unfindable, not the gate firing"

# (q2) A NON-OBJECT ELEMENT INSIDE categories[] MUST NOT KILL THE RUN. `ALL_MISSES` indexes every
# element with `.self_heal_miss`, and jq THROWS `Cannot index string with string` on a bare string,
# number or null. The throw was swallowed by `2>/dev/null || true`, ALL_MISSES came back empty, the
# is_num gate failed, and the script died exit 3 — "could not count findings/misses" — on a ledger
# that was perfectly readable. A handleable element turned into a hard failure, and every OTHER
# reader of this ledger already guards the shape (harvest_convention_findings' `select((.value|type)
# == "object" …)`), so this was the one aggregate that skipped it.
RQ="$(new_repo)"
{
  printf '{"repo":"o/r","number":1,"changed_paths":["src/a/x.md"],"categories":[{"class":"convention_mismatch","evidence":"count drift in the banner","flow_stage":"do","self_heal_miss":true},"not-an-object",42,null,{"class":"quality_gap","self_heal_miss":true}]}\n'
  printf '{"repo":"o/r","number":2,"changed_paths":["src/a/y.md"],"categories":[{"class":"convention_mismatch","evidence":"version count drift","flow_stage":"do","self_heal_miss":false},["nested","array"]]}\n'
} > "$RQ/.supervisor/postmortem/results.jsonl"
# Known by construction: 7 elements total across both records; misses = the 2 objects with
# self_heal_miss:true. The non-objects must be counted by NEITHER denominator's numerator and must
# not abort the run.
run_harvest "$RQ" --session-id fx-q2 --min-support 1 --cap 5 --no-writer
if [ "$RC" -eq 0 ]; then
  ok "(q2) a categories[] array mixing objects with a string, a number, a null and a nested array exits 0 — a malformed element is handled, not fatal"
else
  no "(q2) mixed categories[] exited $RC (expected 0): $(printf '%s\n' "$OUT" | grep -i 'could not count' | head -1)"
fi
if printf '%s\n' "$OUT" | grep -qF 'share of self-heal MISSES:  1/2'; then
  ok "(q3) only the OBJECT elements are counted: misses 1/2 (the string/number/null/array contribute to neither side)"
else
  no "(q3) miss denominators wrong: $(printf '%s\n' "$OUT" | grep -F 'share of self-heal MISSES' | head -1)"
fi

# ---- MUTATION CONTROL M11: remove the type guard from ALL_MISSES ⇒ (q2)/(q3) must go RED ----
# Without this control (q2)/(q3) would pass against a script that never had the guard at all, since
# a well-formed fixture exercises neither.
MUT11="$ROOT/mut-allmisses.sh"
sed 's@ | select(type=="object")@@' "$HARVEST" > "$MUT11"
if ! cmp -s "$HARVEST" "$MUT11" && bash -n "$MUT11" 2>/dev/null; then
  M11OUT="$( bash "$MUT11" --root "$RQ" --session-id fx-m11 --min-support 1 --cap 5 --no-writer 2>&1 )"; m11rc=$?
  if [ "$m11rc" -eq 3 ] && printf '%s\n' "$M11OUT" | grep -qF 'could not count findings/misses'; then
    ok "(M11) CONFIRMED: with the type guard removed the SAME fixture dies exit 3 'could not count findings/misses' — (q2)/(q3) are load-bearing, not vacuous"
  else
    no "(M11) REFUTED: the unguarded ALL_MISSES survived the mixed array (rc=$m11rc) — (q2)/(q3) may be vacuous"
  fi
else
  no "(M11) the ALL_MISSES type-guard mutation did not land"
fi

# ============================================================================
echo "(R) the repo-wide justification renders as ONE line, and a non-object RECORD is skipped, not fatal"
# ============================================================================
# (r1) THE `grep -c … || echo 0` TWO-LINE TRAP, on the one sentence a reviewer is explicitly "being
# asked to accept". `grep -c . file` prints 0 AND EXITS 1 on an empty file, so `|| echo 0` prints a
# SECOND 0 and the justification breaks mid-sentence into two lines. Reachable on the real corpus:
# findings whose ledger record carries no changed_paths at all are ordinary (the fidelity block above
# counts them as `ex_nopath` precisely because they exist). This fixture makes the paths file empty
# by construction — every finding has `changed_paths: []` — so the null-scope branch runs with a zero
# count, which is the exact input that garbles.
RR="$(new_repo)"
{ rec 1 "count drift in the banner" '[]' 5
} > "$RR/.supervisor/postmortem/results.jsonl"
run_harvest "$RR" --session-id "fx-r1" --min-support 4 --cap 3 --no-writer
printf '%s\n' "$OUT" > "$ROOT/r1.txt"
r1n="$(grep -c 'REPO-WIDE JUSTIFICATION' "$ROOT/r1.txt" || true)"
if [ "$r1n" -eq 1 ] && grep -q 'REPO-WIDE JUSTIFICATION.*asked to accept\.$' "$ROOT/r1.txt" \
   && ! grep -qE '^0 changed_paths' "$ROOT/r1.txt"; then
  ok "(r1) with zero recorded changed_paths the justification renders as ONE whole line — no stray second '0' line splitting the sentence"
else
  no "(r1) the justification is garbled or missing (matches=$r1n): $(grep -n -A1 'REPO-WIDE JUSTIFICATION' "$ROOT/r1.txt" | head -3)"
fi
# (r2) …and it is right IN KIND, not merely in count: with no path ever recorded, nothing "no longer
# exists in the repository index" — the scope is unrecorded, not stale.
if grep -q 'REPO-WIDE JUSTIFICATION.*NONE of this theme'"'"'s findings recorded a changed_path at all (0 paths)' "$ROOT/r1.txt" \
   && ! grep -q 'REPO-WIDE JUSTIFICATION.*none of the 0 changed_paths' "$ROOT/r1.txt"; then
  ok "(r2) the zero case states the real reason (UNRECORDED scope), not the false 'no longer exists in the index' claim"
else
  no "(r2) wrong justification wording for the zero-path case: $(grep -F 'REPO-WIDE JUSTIFICATION' "$ROOT/r1.txt" | head -1)"
fi

# ---- MUTATION CONTROL M12: restore the `|| echo 0` capture ⇒ (r1) must go RED ----
# Without this control (r1) would pass against a script that still carried the trap, since the
# single-branch string would still contain the phrase it greps for.
MUT12="$ROOT/mut-twoline.sh"
sed 's@^    pn="$(grep -c . "$WORK/paths.$k" 2>/dev/null || true)"; is_num "$pn" || pn=0$@    pn="$(grep -c . "$WORK/paths.$k" 2>/dev/null || echo 0)"@' "$HARVEST" > "$MUT12"
if ! cmp -s "$HARVEST" "$MUT12" && bash -n "$MUT12" 2>/dev/null; then
  M12OUT="$( bash "$MUT12" --root "$RR" --session-id fx-m12 --min-support 4 --cap 3 --no-writer 2>&1 )" || true
  # With the trap restored `pn` is the two-line string "0\n0"; `[ "$pn" -eq 0 ]` then fails loudly on
  # a non-numeric operand, so the tell is that the clean single-line zero-path justification is GONE.
  if ! printf '%s\n' "$M12OUT" | grep -q 'REPO-WIDE JUSTIFICATION.*asked to accept\.$'; then
    ok "(M12) CONFIRMED: with the two-line capture restored the SAME fixture no longer renders a whole justification line — (r1)/(r2) are load-bearing"
  else
    no "(M12) REFUTED: the two-line capture still produced an intact justification — (r1)/(r2) may be vacuous"
  fi
else
  no "(M12) the two-line-capture mutation did not land"
fi

# (r3) A NON-OBJECT TOP-LEVEL RECORD MUST NOT KILL THE HARVEST. `jq empty` returns 0 on every shape
# below, so the ledger is perfectly readable — but the extractor INDEXES the record (`.value as $r |
# ($r.repo // …)`) and jq throws `Cannot index string with "repo"` on a bare scalar or array, which
# the caller reported as "could not extract findings from the ledger": a could-not-examine verdict
# for a file that parsed fine. The two record-level aggregates (ALL_FINDINGS/ALL_MISSES) throw on the
# same input one line later — `.categories[]?` guards the ITERATION, not the INDEX — so all three
# levels are asserted here, not just the one that failed first.
for shape in '"a bare scalar"' '[1,2]' 'null' '{"categories":"not-an-array"}'; do
  RS="$(new_repo)"
  { rec 1 "count drift in the banner" '["src/a/x.md"]' 5; printf '%s\n' "$shape"
  } > "$RS/.supervisor/postmortem/results.jsonl"
  run_harvest "$RS" --session-id "fx-r3" --min-support 4 --cap 3 --no-writer
  if [ "$RC" -eq 0 ]; then
    ok "(r3) a top-level $shape record exits 0 — a malformed record is skipped, not a whole-harvest failure"
  else
    no "(r3) a top-level $shape record exited $RC: $(printf '%s\n' "$OUT" | grep -iE 'could not (extract|count)' | head -1)"
  fi
done

# (r4) THE SKIP IS STATED, NOT HIDDEN — and only when there is something to state, so a clean corpus
# renders byte-identically to what it rendered before the guard existed (the committed
# HARVEST_DRYRUN_SAMPLE.md transcript is that check).
RS2="$(new_repo)"
{ rec 1 "count drift in the banner" '["src/a/x.md"]' 5; printf '"a bare scalar"\n[1,2]\n'
} > "$RS2/.supervisor/postmortem/results.jsonl"
run_harvest "$RS2" --session-id "fx-r4" --min-support 4 --cap 3 --no-writer
printf '%s\n' "$OUT" > "$ROOT/r4.txt"
grep -qF '2 record(s) SKIPPED as non-objects' "$ROOT/r4.txt" \
  && ok "(r4) the two skipped records are COUNTED and reported in 'inputs read', not silently dropped" \
  || no "(r4) the skipped-record count is missing: $(grep -F 'records read WHOLE' "$ROOT/r4.txt" | head -1)"
grep -qF 'SKIPPED as non-objects' "$ROOT/r1.txt" \
  && no "(r5) a clean corpus printed a skipped-records line — the committed sample transcript would move" \
  || ok "(r5) a clean corpus prints NO skipped-records line, so the committed dry-run transcript is unchanged"

# ---- MUTATION CONTROL M13: remove the record-level type guard from the extractor ⇒ (r3) must go RED ----
MUT13="$ROOT/mut-recguard.sh"
sed 's@^    | select((.value | type) == "object")$@@' "$HARVEST" > "$MUT13"
if ! cmp -s "$HARVEST" "$MUT13" && bash -n "$MUT13" 2>/dev/null; then
  M13OUT="$( bash "$MUT13" --root "$RS2" --session-id fx-m13 --min-support 4 --cap 3 --no-writer 2>&1 )"; m13rc=$?
  if [ "$m13rc" -eq 3 ] && printf '%s\n' "$M13OUT" | grep -qF 'could not extract findings from the ledger'; then
    ok "(M13) CONFIRMED: without the record-level guard the SAME fixture dies exit 3 'could not extract findings' — (r3)/(r4) are load-bearing"
  else
    no "(M13) REFUTED: the unguarded extractor survived the non-object records (rc=$m13rc) — (r3)/(r4) may be vacuous"
  fi
else
  no "(M13) the record-level-guard mutation did not land"
fi

# ---- MUTATION CONTROL M14: remove the record-level guard from the two aggregates ⇒ (r3) must go RED ----
# The sibling-coverage point in AGENT_GUIDELINES §"Read-Before-Write Verification Gate" (d), asserted:
# fixing only the extractor would have moved the same crash one line down, into ALL_FINDINGS.
MUT14="$ROOT/mut-aggguard.sh"
sed 's@ | select((\.|type)=="object")@@g' "$HARVEST" > "$MUT14"
if ! cmp -s "$HARVEST" "$MUT14" && bash -n "$MUT14" 2>/dev/null; then
  M14OUT="$( bash "$MUT14" --root "$RS2" --session-id fx-m14 --min-support 4 --cap 3 --no-writer 2>&1 )"; m14rc=$?
  if [ "$m14rc" -eq 3 ] && printf '%s\n' "$M14OUT" | grep -qF 'could not count findings/misses'; then
    ok "(M14) CONFIRMED: with the extractor guarded but the aggregates not, the SAME fixture still dies exit 3 — the sibling-level guards are load-bearing too"
  else
    no "(M14) REFUTED: the unguarded aggregates survived the non-object records (rc=$m14rc)"
  fi
else
  no "(M14) the aggregate-guard mutation did not land"
fi

# ============================================================================
echo "(S) the agent-memory reason names the test that actually excluded the candidate"
# ============================================================================
# The corpus `rules` branch needs normative=1 AND pw >= PROJECT_WIDE_PCT. A normative=0 entry is
# excluded by the FIRST conjunct at ANY pw — including pw >= the floor — but the single shared
# else-branch template asserted "(< 85%)" unconditionally, so the real corpus printed reasons like
# "normative=0 and only 91% … (< 85%)": a provably false comparison in the one sentence whose whole
# job is to justify the triage. Bucketing was never wrong; the stated reason was.
#
# false_pct_claims <file> — every line that states "only N% … (< F%)" where N >= F, i.e. every
# comparison the transcript asserts and its own numbers refute. Deliberately shape-based, not
# wording-based, so it also guards any future reason string that renders a comparison.
false_pct_claims() {
  sed -n 's/.*only \([0-9][0-9]*\)% of its distinctive terms[^(]*(< \([0-9][0-9]*\)%).*/\1 \2/p' "$1" \
    | awk '$1 >= $2 { print "claims " $1 "% is < " $2 "%" }'
}
reason_of() {   # reason_of <transcript> <candidate-name>
  awk -v want="$2" '$0 ~ ("^    - " want " \\(corpus:") { getline; sub(/^      reason: /,""); print; exit }' "$1"
}

SS="$(new_repo)"
{ rec 1 "count drift in the banner" '["src/a/x.md"]' 5
} > "$SS/.supervisor/postmortem/results.jsonl"
mkdir -p "$SS/.claude/agent-memory/loomwright:code-reviewer"
# (i) NON-NORMATIVE, HIGH pw — the case that produced the false sentence. Every distinctive term is
# lifted from new_repo's own CLAUDE.md/AGENT_GUIDELINES.md, so pw is 100%; the body carries none of
# the MUST/NEVER/ALWAYS-class wording, so normative=0. This combination is NOT hypothetical: the
# real corpus has entries at pw=91% and pw=100% with normative=0.
cat > "$SS/.claude/agent-memory/loomwright:code-reviewer/nonnormative_high_overlap.md" <<'EOF'
---
description: guidance counts advisory guidelines closed emitters
---
An observation about how the gates read.
EOF
# (ii) NORMATIVE, LOW pw — the case whose "below the floor" wording was correct and must survive.
cat > "$SS/.claude/agent-memory/loomwright:code-reviewer/normative_low_overlap.md" <<'EOF'
---
description: zygomorphic quixotry frobnicate widgetized snorklewhacker
---
Agents MUST frobnicate before widgetizing.
EOF
run_harvest "$SS" --session-id "fx-s" --min-support 4 --cap 3 --no-writer
printf '%s\n' "$OUT" > "$ROOT/s.txt"

s_pw="$(sed -n 's/^    - nonnormative_high_overlap (corpus: pw=\([0-9]*\)%,normative=\([01]\)).*/\1 \2/p' "$ROOT/s.txt" | head -1)"
if [ "$s_pw" = "100 0" ]; then
  ok "(s0) the fixture really is the hazardous combination (pw=100%, normative=0), not a restatement of the low-pw case"
else
  no "(s0) fixture did not score as intended (got '$s_pw', wanted '100 0'): $(grep -F 'nonnormative_high_overlap' "$ROOT/s.txt" | head -1)"
fi
s_reason="$(reason_of "$ROOT/s.txt" nonnormative_high_overlap)"
if [ -n "$s_reason" ] && case "$s_reason" in *"(< 85%)"*) false ;; *) true ;; esac \
   && case "$s_reason" in *"normative=0"*) true ;; *) false ;; esac; then
  ok "(s1) the non-normative entry's reason names the normative test as the disqualifier and asserts NO threshold comparison"
else
  no "(s1) wrong reason for the non-normative high-overlap entry: $s_reason"
fi
n_reason="$(reason_of "$ROOT/s.txt" normative_low_overlap)"
if case "$n_reason" in *"(< 85%)"*) true ;; *) false ;; esac; then
  ok "(s2) the normative BELOW-the-floor entry keeps its (correct) below-the-floor wording — the fix branched, it did not delete"
else
  no "(s2) the normative low-pw entry lost its below-the-floor reason: $n_reason"
fi
s_false="$(false_pct_claims "$ROOT/s.txt")"
[ -z "$s_false" ] && ok "(s3) the whole transcript states no comparison its own numbers refute" \
  || no "(s3) false comparisons in the transcript: $s_false"
# ...and the same shape invariant over the REAL corpus run, which is where the defect was found.
if [ -f "$ROOT/a.txt" ]; then
  a_false="$(false_pct_claims "$ROOT/a.txt")"
  [ -z "$a_false" ] && ok "(s4) the REAL-corpus transcript states no comparison its own numbers refute" \
    || no "(s4) false comparisons in the real-corpus transcript: $a_false"
fi

# ---- MUTATION CONTROL M15: collapse the two branches back into one ⇒ (s1)/(s3) must go RED ----
# `elif false` makes the normative=0 arm unreachable, so every non-normative entry falls through to
# the below-the-floor template again — exactly the shipped defect, reproduced on demand.
MUT15="$ROOT/mut-onetemplate.sh"
sed 's@^      elif \[ "$normative" -ne 1 \]; then$@      elif false; then@' "$HARVEST" > "$MUT15"
if ! cmp -s "$HARVEST" "$MUT15" && bash -n "$MUT15" 2>/dev/null; then
  M15OUT="$( bash "$MUT15" --root "$SS" --session-id fx-m15 --min-support 4 --cap 3 --no-writer 2>&1 )" || true
  printf '%s\n' "$M15OUT" > "$ROOT/m15.txt"
  if [ -n "$(false_pct_claims "$ROOT/m15.txt")" ]; then
    ok "(M15) CONFIRMED: with the branches collapsed the SAME fixture asserts $(false_pct_claims "$ROOT/m15.txt") — (s1)/(s3) are load-bearing"
  else
    no "(M15) REFUTED: the single-template script printed no false comparison — (s1)/(s3) may be vacuous"
  fi
else
  no "(M15) the single-template mutation did not land"
fi

# ============================================================================
echo "(T) proposals are deduped against the LIVE .agent/rules/ store"
# ============================================================================
# THE DEFECT THIS SECTION PINS. The harvester read `.agent/rules/` for context and never compared
# its own PROPOSALS against it, so a theme whose convention the store already carried was offered to
# a human for Accept again in different words. Accepting it puts two differently-worded copies of
# ONE convention in ONE file — the exact duplication the store's own cross-surface rule prohibits.
#
# THE FIXTURE IS BUILT SO AN EXACT-STRING DEDUPE CANNOT PASS IT. The seeded live rule is a
# PARAPHRASE of the harvester's own committed `restated-count-version` statement: same claim, no
# shared sentence. (t0b) proves that property of the fixture rather than assuming it — a fixture
# that accidentally contained the canonical statement verbatim would let a `grep -F` dedupe pass and
# every assertion below would be measuring nothing.
# THE CANONICAL STATEMENT IS EXTRACTED FROM THE SCRIPT, NEVER HAND-TYPED. A hand-typed copy of the
# committed lexicon is a second copy of the thing under test: it drifts on the first reword and the
# test then quietly compares the paraphrase against a statement the harvester no longer proposes.
# (t0a) is the control that the extractor found anything at all.
canon_statement() {   # canon_statement <theme-key> — read the committed lexicon's statement
  sed -n "/^    $1)\$/,/^      esac ;;\$/p" "$HARVEST" \
    | sed -n "s/^ *statement) printf '\(.*\)' ;;\$/\1/p" | head -1
}
CANON_RCV="$(canon_statement restated-count-version)"
case "$CANON_RCV" in
  *authoritative*machine-readable*) ok "(t0a) the canonical restated-count-version statement was extracted from the script's lexicon (${#CANON_RCV} chars) — the fixture is not comparing against a hand-typed copy" ;;
  *) no "(t0a) could not extract the canonical statement from $HARVEST (got: '$CANON_RCV') — every assertion below would be vacuous" ;;
esac

# The paraphrase that plays the part of the already-committed rule. Hand-authored on purpose: it is
# the INPUT under test (what the store happens to hold), not a copy of the thing under test.
LIVE_STMT='Every count and every version number has exactly one authoritative machine-readable home. Any other surface either derives that literal when it is read, or it names the authority in prose; restating it creates a second claim, and nothing keeps a restated number current.'
LIVE_ID='process-every-count-and-every-version-number-has-exactly-one-authoritative-machine-readable-home'

seed_rule() {   # seed_rule <repo> <id> <statement> [<file-stem>]
  local r="$1" id="$2" st="$3" stem="${4:-process}"
  mkdir -p "$r/.agent/rules"
  jq -n --arg id "$id" --arg st "$st" --arg cat "$stem" \
    '[{id:$id, category:$cat, statement:$st, enforcement:"advisory", check:null,
       provenance:{source:"test-fixture", added:"2026-01-01T00:00:00Z"}, applies_to:null}]' \
    > "$r/.agent/rules/$stem.json"
}

TD="$(new_repo)"
{ rec 1 "count drift in the banner" '["src/a/x.md"]' 6
  rec 2 "stale prose in the guide"  '["src/b/z.sh"]' 4
} > "$TD/.supervisor/postmortem/results.jsonl"
seed_rule "$TD" "$LIVE_ID" "$LIVE_STMT"

# (t0b) THE FIXTURE HAZARD CONTROL. Neither statement contains the other, and the canonical
# statement does not appear in the store file at all — so no exact or substring match could find
# this duplicate. If this ever fails, the section below stops testing the distinctive-term signal.
t0_ok=1
[ "$CANON_RCV" != "$LIVE_STMT" ] || t0_ok=0
case "$LIVE_STMT" in *"$CANON_RCV"*) t0_ok=0 ;; esac
case "$CANON_RCV" in *"$LIVE_STMT"*) t0_ok=0 ;; esac
grep -qF "$CANON_RCV" "$TD/.agent/rules/process.json" 2>/dev/null && t0_ok=0
[ "$t0_ok" -eq 1 ] \
  && ok "(t0b) the seeded live rule makes the same claim in different words: neither statement contains the other and the canonical statement appears nowhere in the store file — an exact-string dedupe finds nothing here" \
  || no "(t0b) the fixture's live rule shares a literal with the canonical statement — an exact-string dedupe would pass this section, making every assertion below vacuous"

run_harvest "$TD" --session-id "fx-t" --min-support 4 --cap 5 --no-writer
printf '%s\n' "$OUT" > "$ROOT/t.txt"
[ "$RC" -eq 0 ] && ok "(t1) the run exits 0 — the dedupe pass is advisory, never a gate" || no "(t1) exited $RC, expected 0"

if grep -qF 'DEFERRED — ALREADY COVERED by a live rule' "$ROOT/t.txt" \
   && grep -qE 'theme=restated-count-version' "$ROOT/t.txt"; then
  ok "(t2) the theme whose claim the store already makes is reported as an ALREADY-COVERED DEFERRAL"
else
  no "(t2) the duplicate theme was not deferred: $(grep -E 'theme=restated-count-version' "$ROOT/t.txt" | head -1)"
fi
grep -qF "covered by rule id: $LIVE_ID" "$ROOT/t.txt" \
  && ok "(t3) the deferral NAMES the covering rule's id, so a reader can go read the rule that already says it" \
  || no "(t3) the deferral does not name the covering rule id: $(grep -F 'covered by rule id' "$ROOT/t.txt" | head -1)"
if grep -qE '^     overlap: [6-9][0-9]%|^     overlap: 100%' "$ROOT/t.txt"; then
  ok "(t4) the deferral prints its measured overlap ($(grep -E '^     overlap:' "$ROOT/t.txt" | head -1 | awk '{print $2}')) and the floor it cleared — the threshold is checkable from the report"
else
  no "(t4) the deferral prints no overlap >= the floor: $(grep -E '^     overlap:' "$ROOT/t.txt" | head -1)"
fi
# The pass must not defer everything: the unrelated theme is still proposed, and it says so.
if grep -qE '^  1\) \[documentation\] theme=doc-currency-drift' "$ROOT/t.txt" \
   && grep -qE '^     store dedupe: NEW — nearest of the 1 live rule\(s\)' "$ROOT/t.txt"; then
  ok "(t5) the unrelated theme is still EMITTED, and names the nearest live rule it did not match — the pass reports in both directions"
else
  no "(t5) the unrelated theme was lost or reports no nearest-rule line: $(grep -E 'theme=doc-currency-drift' "$ROOT/t.txt" | head -1)"
fi
# The deferral must not spend a cap slot — the emitted rule is numbered 1), not 2).
grep -qE '^  2\) ' "$ROOT/t.txt" \
  && no "(t6) a second proposal was numbered — the deferral appears to have consumed a batch slot" \
  || ok "(t6) the deferral consumed no cap slot: the one emitted proposal is numbered 1)"

# ---- the metrics half: the deferred theme's findings stay in every denominator ----
# 10 convention_mismatch findings in the fixture: 6 restated-count-version (deferred), 4 doc-drift
# (emitted). Coverage is measured against all 10, so the deferral LOWERS it to 4/10 rather than
# shrinking the denominator to 4/4.
grep -qF 'coverage:        4/10 convention_mismatch findings (40%) map to >= 1 proposed rule' "$ROOT/t.txt" \
  && ok "(t7) coverage is 4/10 (40%) — the 6 deferred findings stay in the denominator, so the deferral lowers coverage instead of hiding" \
  || no "(t7) coverage did not keep the deferred findings in its denominator: $(grep -F 'coverage:' "$ROOT/t.txt" | head -1)"
grep -qF 'already covered by the live store: 6/10 findings (60%)' "$ROOT/t.txt" \
  && ok "(t8) the 6 deferred findings are counted and reported as already covered by the live store — not silently dropped" \
  || no "(t8) the already-covered figure is wrong or missing: $(grep -F 'already covered by the live store' "$ROOT/t.txt" | head -1)"
grep -qF 'COMBINED convention coverage: 10/10 (100%)' "$ROOT/t.txt" \
  && ok "(t9) the COMBINED figure is 10/10 — every finding maps to a rule that is proposed here or already live" \
  || no "(t9) the combined coverage is wrong or missing: $(grep -F 'COMBINED convention coverage' "$ROOT/t.txt" | head -1)"
grep -qF '1 already covered by a live rule' "$ROOT/t.txt" \
  && ok "(t10) the batch header's deferral breakdown counts the already-covered arm separately from the cap" \
  || no "(t10) the batch header does not break out the already-covered deferral: $(grep -F 'proposed rule batch' "$ROOT/t.txt" | head -1)"
# The unmapped-remainder itemisation must give the REAL reason (not the cap, not the support floor)
# and must still sum to its own stated headline.
if grep -qE '^ +restated-count-version +6 +\(reached the support floor but is ALREADY COVERED by the live rule' "$ROOT/t.txt"; then
  ok "(t11) the unmapped remainder itemises the deferred theme with 'already covered' as the reason — not the cap, not the floor"
else
  no "(t11) the remainder gives the wrong reason: $(grep -E '^ +restated-count-version' "$ROOT/t.txt" | head -1)"
fi
t_sum="$(awk '/UNMAPPED REMAINDER/,/store dedupe:/' "$ROOT/t.txt" \
          | awk '/^ +[a-z-]+ +[0-9]+ +\(/ { s += $2 } END { print s+0 }')"
[ "$t_sum" = "6" ] \
  && ok "(t12) the itemisation sums to 6 — the stated remainder still accounts for itself with a deferred theme in it" \
  || no "(t12) the itemisation sums to $t_sum, not the 6 unmapped findings"

# ---- the whole batch already covered: the report must say so, and still show the deferrals ----
TD2="$(new_repo)"
rec 1 "count drift in the banner" '["src/a/x.md"]' 6 > "$TD2/.supervisor/postmortem/results.jsonl"
seed_rule "$TD2" "$LIVE_ID" "$LIVE_STMT"
run_harvest "$TD2" --session-id "fx-t2" --min-support 4 --cap 5 --no-writer
printf '%s\n' "$OUT" > "$ROOT/t2.txt"
grep -qF 'DEFERRED — ALREADY COVERED by a live rule' "$ROOT/t2.txt" \
  && ok "(t13) with EVERY theme already covered the deferral blocks are still PRINTED — an empty batch is not an empty report" \
  || no "(t13) the deferral blocks vanished when 0 rules were emitted, yet the diagnostic says 'named above'"
grep -qF 'are ALREADY COVERED by a live rule' "$ROOT/t2.txt" \
  && ok "(t14) the empty-batch diagnostic names already-covered as the measured cause" \
  || no "(t14) the empty batch does not name the already-covered cause: $(grep -F '(empty batch' "$ROOT/t2.txt" | head -1)"
grep -qF 'no theme reached the support floor' "$ROOT/t2.txt" \
  && no "(t15) the all-covered run blames the support floor — a cause its own numbers refute (support 6 >= floor 4)" \
  || ok "(t15) the all-covered run does NOT blame the support floor"

# ---- --dup-pct 101 is the documented measurement run: defers nothing, prints every percentage ----
run_harvest "$TD" --session-id "fx-t3" --min-support 4 --cap 5 --no-writer --dup-pct 101
printf '%s\n' "$OUT" > "$ROOT/t3.txt"
if ! grep -qF 'DEFERRED — ALREADY COVERED' "$ROOT/t3.txt" \
   && grep -qE '^     store dedupe: NEW — nearest of the 1 live rule\(s\) is .* at [0-9]+%' "$ROOT/t3.txt"; then
  ok "(t16) --dup-pct 101 defers nothing and still prints each proposal's nearest live rule and exact percentage — the header's re-derivation recipe works"
else
  no "(t16) --dup-pct 101 did not behave as the header documents: $(grep -cF 'DEFERRED — ALREADY COVERED' "$ROOT/t3.txt") deferral(s)"
fi

# ---- an unparseable store file is NAMED, and the dedupe pass says it is UNVERIFIED ----
TD4="$(new_repo)"
rec 1 "count drift in the banner" '["src/a/x.md"]' 6 > "$TD4/.supervisor/postmortem/results.jsonl"
seed_rule "$TD4" "$LIVE_ID" "$LIVE_STMT" other
printf '{ not json at all\n' > "$TD4/.agent/rules/broken.json"
run_harvest "$TD4" --session-id "fx-t4" --min-support 4 --cap 5 --no-writer
printf '%s\n' "$OUT" > "$ROOT/t4.txt"
[ "$RC" -eq 0 ] \
  && ok "(t17) an unparseable rule file is not fatal — the harvest still runs and exits 0" \
  || no "(t17) an unparseable rule file killed the run (exit $RC)"
if grep -qF 'NOT PARSEABLE as a rule array — broken.json' "$ROOT/t4.txt" \
   && grep -qF 'UNVERIFIED against broken.json' "$ROOT/t4.txt"; then
  ok "(t18) the unreadable file is NAMED in both 'inputs read' and the dedupe metric, which states the pass is UNVERIFIED against it — silence there would read as 'checked, and clean'"
else
  no "(t18) the unparseable file is not named/disclosed: $(grep -F 'PARSEABLE' "$ROOT/t4.txt" | head -1)"
fi
grep -qF 'DEFERRED — ALREADY COVERED by a live rule' "$ROOT/t4.txt" \
  && ok "(t19) the readable sibling file is still deduped against — one broken file does not disarm the whole pass" \
  || no "(t19) the readable rule file was skipped along with the broken one"

# ---- an ABSENT store is a normal empty case ----
TD5="$(new_repo)"
rec 1 "count drift in the banner" '["src/a/x.md"]' 6 > "$TD5/.supervisor/postmortem/results.jsonl"
rm -rf "$TD5/.agent"
run_harvest "$TD5" --session-id "fx-t5" --min-support 4 --cap 5 --no-writer
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qF 'store dedupe: no live rule to compare against'; then
  ok "(t20) an absent rules store exits 0 and says outright that nothing could have been deduped"
else
  no "(t20) an absent store misbehaved (exit $RC): $(printf '%s\n' "$OUT" | grep -F 'store dedupe' | head -1)"
fi

# ---- a non-numeric --dup-pct is a usage error, like every other numeric flag ----
run_harvest "$TD" --session-id "fx-t6" --no-writer --dup-pct abc
[ "$RC" -eq 2 ] \
  && ok "(t21) a non-numeric --dup-pct exits 2 (usage error) rather than silently comparing against a garbage floor" \
  || no "(t21) --dup-pct abc exited $RC, expected 2"

# ---- BOTH deferral causes in ONE empty batch: the cap arm AND the already-covered arm ----
# The `and a further N theme(s)` continuation line under the cap sentence was REACHABLE and CORRECT
# and NEVER EXECUTED: every fixture that seeds a live rule ran with --cap 5 (never exhausted), and
# the only --cap 0 fixture (section P) seeds no rule, so the two counters were never both non-zero
# in the same run. Reasoned about, not run — which is this file's most-repeated defect class, and
# the reason (T) reuses $TD here rather than trusting the trace. $TD has exactly the needed shape:
# restated-count-version (6 findings) is already covered, doc-currency-drift (4) is not, so at
# --cap 0 the first defers as already-covered (before the cap check, spending no slot) and the
# second is turned away by the bound.
run_harvest "$TD" --session-id "fx-t7" --min-support 4 --cap 0 --no-writer
printf '%s\n' "$OUT" > "$ROOT/t7.txt"
if grep -qF '0 emitted, 2 deferred: 1 by the cap, 1 already covered by a live rule' "$ROOT/t7.txt"; then
  ok "(t22) with one theme cap-deferred and one already-covered, the header attributes each to its own cause"
else
  no "(t22) the two deferral causes are not both counted: $(grep -F 'proposed rule batch' "$ROOT/t7.txt" | head -1)"
fi
grep -qE '\(empty batch — but NOT for want of evidence: 1 theme\(s\) reached the 4-finding support floor and were deferred by the cap=0 batch bound' "$ROOT/t7.txt" \
  && ok "(t23) the cap sentence counts ONLY the cap-deferred theme — the already-covered one is not folded into it" \
  || no "(t23) the cap sentence is wrong or missing: $(grep -F '(empty batch' "$ROOT/t7.txt" | head -1)"
grep -qF '(and a further 1 theme(s) were deferred as ALREADY COVERED by a live rule' "$ROOT/t7.txt" \
  && ok "(t24) the continuation line fires, so the empty-batch diagnostic names BOTH measured causes rather than only the first" \
  || no "(t24) the already-covered continuation line did not fire alongside the cap sentence"
grep -qF 'DEFERRED — ALREADY COVERED by a live rule' "$ROOT/t7.txt" \
  && ok "(t25) the deferral block is still printed in the combined case — 'named above' remains true" \
  || no "(t25) the diagnostic says 'named above' but no deferral block was printed"
grep -qF 'no theme reached the support floor' "$ROOT/t7.txt" \
  && no "(t26) the combined run still blames the support floor — a cause its own numbers refute" \
  || ok "(t26) the combined run does not blame the support floor"

# ---- MUTATION CONTROL M18: make the continuation line unreachable ----
# `-ge 0` is true for every count, so the `||` short-circuits and the line never runs — the state
# the branch was in before (t24) existed, when it had only ever been reasoned about.
MUT18="$ROOT/mut-nocontinuation.sh"
sed 's@^  \[ "$DUP_DEFERRED" -eq 0 \] || \\$@  [ "$DUP_DEFERRED" -ge 0 ] || \\@' "$HARVEST" > "$MUT18"
if ! cmp -s "$HARVEST" "$MUT18" && bash -n "$MUT18" 2>/dev/null; then
  M18OUT="$( bash "$MUT18" --root "$TD" --session-id fx-m18 --min-support 4 --cap 0 --no-writer 2>&1 )" || true
  if printf '%s\n' "$M18OUT" | grep -qF '(and a further 1 theme(s) were deferred as ALREADY COVERED'; then
    no "(M18) REFUTED: the continuation line still printed with its guard always-true — (t24) is vacuous"
  elif printf '%s\n' "$M18OUT" | grep -qF 'were deferred by the cap=0 batch bound'; then
    ok "(M18) CONFIRMED: with the guard always-true the cap sentence still prints but the already-covered continuation is silently lost — (t24) is load-bearing"
  else
    no "(M18) the mutant printed neither sentence — the control proved nothing"
  fi
else
  no "(M18) the continuation-line mutation did not land"
fi

# ---- MUTATION CONTROL M16: remove the dedupe pass ⇒ the duplicate is proposed again ----
# `if false` at the decision point leaves every line of reporting in place and removes only the
# comparison — the state the script was in before this pass existed.
MUT16="$ROOT/mut-nodedupe.sh"
sed 's@^  if nearest_live_rule "$(theme_field "$k" statement)"; then$@  if false; then@' "$HARVEST" > "$MUT16"
if ! cmp -s "$HARVEST" "$MUT16" && bash -n "$MUT16" 2>/dev/null; then
  M16OUT="$( bash "$MUT16" --root "$TD" --session-id fx-m16 --min-support 4 --cap 5 --no-writer 2>&1 )" || true
  printf '%s\n' "$M16OUT" > "$ROOT/m16.txt"
  if grep -qF 'DEFERRED — ALREADY COVERED' "$ROOT/m16.txt"; then
    no "(M16) REFUTED: the duplicate is still deferred with the dedupe pass removed — (t2)/(t3) are vacuous"
  elif grep -qE '^  [12]\) \[process\] theme=restated-count-version' "$ROOT/m16.txt"; then
    ok "(M16) CONFIRMED: with the dedupe pass removed the already-covered theme is proposed as a rule again, exactly as it was before — (t2)/(t3)/(t7)/(t8) are load-bearing"
  else
    no "(M16) the mutant neither deferred nor emitted the duplicate theme — the control proved nothing"
  fi
else
  no "(M16) the dedupe-removal mutation did not land"
fi

# ---- MUTATION CONTROL M17: credit the deferred findings to the PROPOSED batch ----
# The denominator half of this section stands or falls on one line. Silently counting an
# already-covered theme's findings as mapped would print a flattering `coverage: 10/10 (100%)` for a
# batch that proposed one rule over four findings — the self-crediting arithmetic (t7)/(t8) exist to
# prevent. Mutating it must break BOTH, or they are decoration.
MUT17="$ROOT/mut-selfcredit.sh"
sed 's@^    COVERED_EXISTING=$((COVERED_EXISTING + fid_n))$@    MAPPED=$((MAPPED + fid_n))@' "$HARVEST" > "$MUT17"
if ! cmp -s "$HARVEST" "$MUT17" && bash -n "$MUT17" 2>/dev/null; then
  M17OUT="$( bash "$MUT17" --root "$TD" --session-id fx-m17 --min-support 4 --cap 5 --no-writer 2>&1 )" || true
  printf '%s\n' "$M17OUT" > "$ROOT/m17.txt"
  if grep -qF 'coverage:        4/10 convention_mismatch findings (40%)' "$ROOT/m17.txt" \
     || grep -qF 'already covered by the live store: 6/10 findings (60%)' "$ROOT/m17.txt"; then
    no "(M17) REFUTED: crediting the deferred findings to the proposed batch changed neither figure — (t7)/(t8) are vacuous"
  else
    ok "(M17) CONFIRMED: crediting them to the batch reports '$(grep -F 'coverage:        ' "$ROOT/m17.txt" | head -1 | sed 's/^ *//')' — (t7)/(t8) are load-bearing"
  fi
else
  no "(M17) the self-crediting mutation did not land"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
