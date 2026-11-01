#!/usr/bin/env bash
# test-heal-review-scope-seam.sh — static wiring test for Phase 4.5's converging re-review
# (heal_review_scope): the two guarded reviewer-prompt lines in skills/self-heal-advisory/SKILL.md
# Part 2 (HEAL RE-REVIEW SCOPE, DO-NOT-REPORT), the reviewer's reporting rule in agents/code-reviewer.md
# §"Review Modes & Scope Expansion", the loop wiring of heal-review-scope.sh (steps S / D / R of
# §"Converging re-review"), the INIT resolution in skills/supervisor-config/SKILL.md step 2.11 and
# the user-facing pointer to it in commands/supervisor.md.
#
# Every surface is prompt text an agent executes, so a grep is the only thing that can hold the wiring.
# Shape follows test-execution-directive-seam.sh: ok()/no() helpers, a "RESULT: N passed, M failed" tail,
# exit 1 on any failure, paths from $BASH_SOURCE (runs from any CWD and from run-pin-mutations.sh's
# scratch copy — no git history is read). bash 3.2 / BSD userland safe.
#
# BYTE IDENTITY: the reviewer Task prompt (from its `prompt: "` line up to the Task's `model:` line)
# with the two GUARDED lines removed (each with the blank line after it) must equal the frozen base
# prompt in scripts/fixtures/phase45-reviewer-prompt-base.txt — so round 1 under every mode, and every
# round under `shadow` and `full` (where both lines are omitted), is the prompt the loop sent before
# heal_review_scope existed. A line counts as guarded only when it starts with its marker AND the guard
# `include this line ONLY when HEAL_REVIEW_SCOPE == files AND heal_iterations ≥ 1`, so an unguarded copy
# stays in and breaks identity. Any later edit to the reviewer prompt must regenerate the fixture in
# the same change; on a mismatch this test prints the command:
#   bash loomwright/scripts/test-heal-review-scope-seam.sh --print-base > loomwright/scripts/fixtures/phase45-reviewer-prompt-base.txt
# (`--print-base [<skill file>]` prints the extracted prompt minus the guarded lines; default file is
# the live SKILL.md.)
#
# Every assertion is paired with a MUTATION CONTROL: a copy of the surface with the asserted text
# removed (or unguarded), validated non-empty + readable + different from the original; the SAME check
# must then FAIL on it, or the assertion is vacuous.
#
# EXPLICIT LIMIT: this pins WIRING. It cannot prove a reviewer honours the scope line or that the loop
# actually calls the helper at run time — both are runtime behaviour (the helper's own behaviour is
# test-heal-review-scope.sh's).

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"

SKILL="$PLUGIN_ROOT/skills/self-heal-advisory/SKILL.md"
REVIEWER="$PLUGIN_ROOT/agents/code-reviewer.md"
CONFIG="$PLUGIN_ROOT/skills/supervisor-config/SKILL.md"
COMMAND="$PLUGIN_ROOT/commands/supervisor.md"
FIXTURE="$HERE/fixtures/phase45-reviewer-prompt-base.txt"
REGEN='bash loomwright/scripts/test-heal-review-scope-seam.sh --print-base > loomwright/scripts/fixtures/phase45-reviewer-prompt-base.txt'

# Canonical strings — ONE copy each, used by the real check AND by the mutant builders.
SCOPE_MARK='**HEAL RE-REVIEW SCOPE ('
DNR_MARK='**DO-NOT-REPORT ('
GUARD='include this line ONLY when HEAL_REVIEW_SCOPE == files AND heal_iterations ≥ 1'
PREC='for REPORTING only, it overrides the DIFF-SCOPE OVERRIDE'
LOOK='look for everything'
CONTEXT='the full diff remains read-only context'
WHOLE='Read each listed file WHOLE'
ONLY_LISTED='report findings ONLY in the listed files'
DNR_ONLY='dismissed fingerprints ONLY'
DNR_NO_FIXED='Fixed fingerprints are never listed'
CR_MARK='**HEAL RE-REVIEW SCOPE (Supervisor Phase 4.5'
CR_EXPAND='still recorded in `scope_expanded[]`'
STEP_D='# REPEAT SUPPRESSION — step D of'
KILL='`HEAL_REVIEW_SCOPE == full` ⇒ call nothing'
COUNT_ONLY='adding `--count-only` under `shadow`'
RECORD_FAIL='heal_round_record_failed: <reason>'
HELPER_ERR='`scope_fallback: helper_error`'
CFG_CALL='`heal-review-scope.sh mode --root .`'
CFG_FULL='record `HEAL_REVIEW_SCOPE = full`'

# ---- extraction (shared by the checks and --print-base) ---------------------------------------------
# prompt_of <skill> — inside the `review = Task(` call: from its `prompt: "` line up to (not including)
# the first `model:` line after it. The Task's other arguments stay out of the fixture: only the prompt
# text is frozen.
prompt_of() {
  env LC_ALL=C awk '
    !task && index($0, "review = Task(") { task = 1; next }
    task { t = $0; sub(/^[[:space:]]+/, "", t)
           if (!on && index(t, "prompt: \"") == 1) on = 1
           if (on && index(t, "model:") == 1) exit
           if (on) print }
  ' "$1"
}
# strip_guarded — stdin prompt; drops each guarded marker line and the blank line right after it.
strip_guarded() {
  env LC_ALL=C awk -v s="$SCOPE_MARK" -v d="$DNR_MARK" -v g="$GUARD" '
    { t = $0; sub(/^[[:space:]]+/, "", t) }
    skipblank { skipblank = 0; if (t == "") next }
    (index(t, s) == 1 || index(t, d) == 1) && index(t, g) { skipblank = 1; next }
    { print }
  '
}

if [ "${1:-}" = "--print-base" ]; then
  src="${2:-$SKILL}"
  [ -r "$src" ] || { echo "test-heal-review-scope-seam: cannot read $src" >&2; exit 2; }
  prompt_of "$src" | strip_guarded
  exit 0
fi

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

for f in "$SKILL" "$REVIEWER" "$CONFIG" "$COMMAND" "$FIXTURE"; do
  [ -s "$f" ] || no "MISSING surface: $f"
done
if [ "$fail" -ne 0 ]; then echo; echo "RESULT: $pass passed, $fail failed"; exit 1; fi

line_with() { grep -F -- "$2" "$1" 2>/dev/null | head -1; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
# guarded_line <file> <marker> — the reviewer-prompt line that starts with <marker> and carries GUARD.
guarded_line() {
  prompt_of "$1" | env LC_ALL=C awk -v m="$2" -v g="$GUARD" '
    { t = $0; sub(/^[[:space:]]+/, "", t) } index(t, m) == 1 && index(t, g) { print; exit }'
}

# Mutant builders — each writes $MUT from $1.
del_lines()     { grep -vF -- "$2" "$1" > "$MUT" || true; }
strip_in_line() { env LC_ALL=C awk -v a="$2" -v n="$3" '{ if (index($0, a)) { i = index($0, n); if (i) $0 = substr($0, 1, i - 1) substr($0, i + length(n)) } print }' "$1" > "$MUT"; }
append_text()   { { cat "$1"; printf '%s\n' "$2"; } > "$MUT"; }

MUT="$(mktemp)"
trap 'rm -f "$MUT" 2>/dev/null' EXIT

# check_with_mutant <label> <check-fn> <file> <builder> <builder-args...>
check_with_mutant() {
  label="$1"; fn="$2"; file="$3"; shift 3
  if "$fn" "$file"; then ok "$label"; else no "$label"; fi
  builder="$1"; shift
  "$builder" "$file" "$@"
  if [ -s "$MUT" ] && [ -r "$MUT" ] && ! cmp -s "$file" "$MUT"; then
    if "$fn" "$MUT"; then
      no "$label — mutation control: check still PASSES on the mutant (vacuous)"
    else
      ok "$label — mutation control: check fails on a valid mutant"
    fi
  else
    no "$label — mutation control: mutant invalid (empty/unreadable/identical) — cannot be trusted"
  fi
}

# ---- (a) HEAL RE-REVIEW SCOPE line: in the reviewer prompt, guarded, whole-file, report-only-listed ----
chk_scope_line() {
  l="$(guarded_line "$1" "$SCOPE_MARK")"
  [ -n "$l" ] && has "$l" 'the helper printed scope: files' && has "$l" "$WHOLE" && has "$l" "$ONLY_LISTED"
}
check_with_mutant "(a) HEAL RE-REVIEW SCOPE line present in the reviewer prompt, guarded to files + heal_iterations ≥ 1" \
  chk_scope_line "$SKILL" del_lines "$SCOPE_MARK"
check_with_mutant "(a) an UNGUARDED HEAL RE-REVIEW SCOPE line does not count" \
  chk_scope_line "$SKILL" strip_in_line "$SCOPE_MARK" "$GUARD"

# ---- (b) precedence sentence on the SKILL.md scope line ----------------------------------------------
chk_prec_skill() {
  l="$(line_with "$1" "$SCOPE_MARK")"
  [ -n "$l" ] && has "$l" "$PREC" && has "$l" "$LOOK" && has "$l" "$CONTEXT"
}
check_with_mutant "(b) scope line: for REPORTING only it overrides DIFF-SCOPE OVERRIDE + 'look for everything'; full diff read-only" \
  chk_prec_skill "$SKILL" strip_in_line "$SCOPE_MARK" "$PREC"

# ---- (c) DO-NOT-REPORT line: guarded, dismissed fingerprints only -------------------------------------
chk_dnr_line() {
  l="$(guarded_line "$1" "$DNR_MARK")"
  [ -n "$l" ] && has "$l" 'dismissed fingerprint; omit entirely otherwise' && has "$l" "$DNR_ONLY" \
    && has "$l" "$DNR_NO_FIXED" && has "$l" 'at the same or a lower severity'
}
check_with_mutant "(c) DO-NOT-REPORT line present, guarded, lists dismissed fingerprints only" \
  chk_dnr_line "$SKILL" del_lines "$DNR_MARK"
check_with_mutant "(c) a DO-NOT-REPORT line that does not exclude fixed fingerprints fails" \
  chk_dnr_line "$SKILL" strip_in_line "$DNR_MARK" "$DNR_NO_FIXED"
check_with_mutant "(c) an UNGUARDED DO-NOT-REPORT line does not count" \
  chk_dnr_line "$SKILL" strip_in_line "$DNR_MARK" "$GUARD"

# ---- (d) placement: after MODULE-SHAPE ADVISORY, before BASE_BRANCH= ----------------------------------
chk_order() {
  prompt_of "$1" | env LC_ALL=C awk -v s="$SCOPE_MARK" -v d="$DNR_MARK" '
    { t = $0; sub(/^[[:space:]]+/, "", t) }
    index(t, "**MODULE-SHAPE ADVISORY (") == 1 { ms = NR }
    index(t, s) == 1 { sl = NR }
    index(t, d) == 1 { dl = NR }
    index(t, "BASE_BRANCH={BASE_BRANCH}") == 1 { bb = NR }
    END { exit ((ms && sl && dl && bb && ms < sl && sl < dl && dl < bb) ? 0 : 1) }'
}
check_with_mutant "(d) both lines sit after MODULE-SHAPE ADVISORY and before BASE_BRANCH=" \
  chk_order "$SKILL" del_lines 'BASE_BRANCH={BASE_BRANCH}'

# ---- (e) byte identity with the frozen base prompt ----------------------------------------------------
chk_identity() {
  out="$(prompt_of "$1" | strip_guarded)"
  [ -n "$out" ] && [ "$out" = "$(cat "$FIXTURE")" ]
}
if chk_identity "$SKILL"; then
  ok "(e) reviewer prompt minus the two guarded lines is byte-identical to fixtures/phase45-reviewer-prompt-base.txt"
else
  no "(e) reviewer prompt minus the two guarded lines differs from fixtures/phase45-reviewer-prompt-base.txt"
  echo "      if the prompt edit is intended, regenerate the fixture in the same change:"
  echo "      $REGEN"
fi
# Mutation controls: an unguarded DO-NOT-REPORT re-insert, an unguarded scope line, an edited base line.
for spec in "$DNR_MARK|$GUARD" "$SCOPE_MARK|$GUARD" "Review the integrated feature branch holistically.|holistically"; do
  a="${spec%%|*}"; n="${spec#*|}"
  strip_in_line "$SKILL" "$a" "$n"
  if [ -s "$MUT" ] && ! cmp -s "$SKILL" "$MUT"; then
    if chk_identity "$MUT"; then no "(e) mutation control: identity still holds after stripping '$n' from '$a' (vacuous)"
    else ok "(e) mutation control: identity breaks after stripping '$n' from '$a'"; fi
  else
    no "(e) mutation control: mutant invalid for '$a' — cannot be trusted"
  fi
done

# ---- (f) agents/code-reviewer.md paragraph ------------------------------------------------------------
chk_reviewer() {
  l="$(line_with "$1" "$CR_MARK")"
  [ -n "$l" ] && has "$l" "$PREC" && has "$l" "$LOOK" && has "$l" "$CONTEXT" && has "$l" "$CR_EXPAND" \
    && has "$l" 'DO-NOT-REPORT'
}
check_with_mutant "(f) code-reviewer paragraph carries the precedence sentence" \
  chk_reviewer "$REVIEWER" strip_in_line "$CR_MARK" "$PREC"
check_with_mutant "(f) code-reviewer paragraph keeps expansion reads recorded in scope_expanded[]" \
  chk_reviewer "$REVIEWER" strip_in_line "$CR_MARK" "$CR_EXPAND"
check_with_mutant "(f) code-reviewer paragraph present" chk_reviewer "$REVIEWER" del_lines "$CR_MARK"

# ---- (g) loop wiring in SKILL.md ----------------------------------------------------------------------
chk_step_d_order() {
  env LC_ALL=C awk -v d="$STEP_D" '
    { t = $0; sub(/^[[:space:]]+/, "", t) }
    index(t, d) == 1 && !sd { sd = NR }
    index(t, "heal_dismissed += [") == 1 && !hd { hd = NR }
    index(t, "fixable_issues = [i for i in review.issues") == 1 && !fx { fx = NR }
    END { exit ((sd && hd && fx && sd < hd && sd < fx) ? 0 : 1) }' "$1"
}
check_with_mutant "(g) repeat suppression runs before heal_dismissed and fixable_issues are built" \
  chk_step_d_order "$SKILL" del_lines "$STEP_D"
chk_kill() { grep -qF -- "$KILL" "$1"; }
check_with_mutant "(g) full is the kill switch: no helper call" chk_kill "$SKILL" del_lines "$KILL"
chk_shadow_count() { grep -qF -- "$COUNT_ONLY" "$1"; }
check_with_mutant "(g) shadow suppresses nothing (--count-only)" chk_shadow_count "$SKILL" del_lines "$COUNT_ONLY"
chk_helper_err() { grep -qF -- "$HELPER_ERR" "$1"; }
check_with_mutant "(g) helper missing / non-zero / unparsable ⇒ full scope + helper_error" \
  chk_helper_err "$SKILL" del_lines "$HELPER_ERR"
chk_record_fail() { grep -qF -- "$RECORD_FAIL" "$1"; }
check_with_mutant "(g) a failed record write logs heal_round_record_failed and continues" \
  chk_record_fail "$SKILL" del_lines "$RECORD_FAIL"
chk_fixed_record() { grep -qF -- 'heal round record (step R below): fixable_issues ⇒ outcome `fixed`' "$1"; }
check_with_mutant "(g) the fix push writes the round record with outcome fixed" \
  chk_fixed_record "$SKILL" del_lines 'heal round record (step R below)'

# ---- (h) supervisor-config step 2.11 ------------------------------------------------------------------
chk_config() {
  l="$(line_with "$1" '2.11. Resolve the **heal review scope**')"
  [ -n "$l" ] && has "$l" "$CFG_CALL" && has "$l" "$CFG_FULL" && has "$l" 'NEVER stops the run'
}
check_with_mutant "(h) supervisor-config step 2.11 resolves HEAL_REVIEW_SCOPE and never stops the run" \
  chk_config "$CONFIG" strip_in_line '2.11. Resolve the **heal review scope**' "$CFG_FULL"
chk_driver_range() { grep -qF -- '5a.2.6–5a.2.11' "$1"; }
check_with_mutant "(h) the driver note keeps step 2.11 the Supervisor's own" \
  chk_driver_range "$CONFIG" strip_in_line '**Driver path' '5a.2.6–5a.2.11'

# ---- (i) the user-facing pointer in commands/supervisor.md ---------------------------------------------
chk_command() {
  l="$(line_with "$1" '**Phase 4.5:**')"
  [ -n "$l" ] && has "$l" '`.heal_review_scope` (default `shadow`' && has "$l" '`skills/supervisor-config/SKILL.md` step 2.11'
}
check_with_mutant "(i) commands/supervisor.md Phase 4.5 paragraph points at step 2.11 for heal_review_scope" \
  chk_command "$COMMAND" strip_in_line '**Phase 4.5:**' '`skills/supervisor-config/SKILL.md` step 2.11'

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
