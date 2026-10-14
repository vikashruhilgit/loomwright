#!/usr/bin/env bash
# test-phase45-rounds-seam.sh — static seam test for automate-speed/02: Phase 4.5 spends its rounds on
# new defects. Pins the WIRING of three mechanisms whose behaviour their own tests prove
# (test-run-pin-mutations.sh, test-phase45-ci-read.sh, scripts/test-ci-local.sh (SD)):
#
#   PART 1  every worker / fix-worker prompt names `ci-local.sh --affected` as its test command, states
#           the owner rule (a background worker never runs the full `ci-local.sh` pool), and lists no
#           hand-typed suite names: the Phase 4.5 fix worker (self-heal-advisory), review-heal Step 2 and
#           Step U4, the Worker Prompt Template (async-orchestration), and agents/worker.md Step 5.
#   PART 2  Phase 3 runs run-pin-mutations.sh beside verify-provides.sh with the shared --cache path —
#           Single-Agent + Sequential (agents/supervisor.md), parallel poll loop (execute-manager.md) —
#           with one re-spawn on not_held, never adjudication; the closed-enumeration rows name it.
#   PART 3  Phase 4.5 runs run-pin-mutations.sh before the reviewer spawn, hands its lines over as the
#           PIN-MUTATION VERDICTS block right AFTER the DEVIATIONS ADVISORY line, runs phase45-ci-read.sh
#           once per iteration and appends its findings to the ONE `fixable_issues` list.
#   PART 4  supervisor-readiness §"Pin mutations" states the two machine-applicable forms, the
#           first-backticked-token rule and the D1 fallback for any other wording.
#   PART 5  mutation control: a TEMP copy of self-heal-advisory without the fix worker's `--affected`
#           sentence, and of supervisor-readiness without the grammar sentence, each make this test fail
#           (positive control first; every mutant non-empty and different from its original).
#
# EXPLICIT LIMIT: this pins prose wiring only. That a model follows it is proven by a live run.
# Env overrides (PART 5's re-invocation only): SEAM_SHA (self-heal-advisory), SEAM_READINESS,
# SEAM_NO_MUTATION=1.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
SHA="${SEAM_SHA:-$PLUGIN/skills/self-heal-advisory/SKILL.md}"
RDY="${SEAM_READINESS:-$PLUGIN/skills/supervisor-readiness/SKILL.md}"
RH="$PLUGIN/skills/review-heal/SKILL.md"
AO="$PLUGIN/skills/async-orchestration/SKILL.md"
WK="$PLUGIN/agents/worker.md"
SUP="$PLUGIN/agents/supervisor.md"
EM="$PLUGIN/agents/execute-manager.md"
CR="$PLUGIN/agents/code-reviewer.md"
FE="$PLUGIN/docs/FAILURE_ESCALATION.md"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass + 1)); }
no() { echo "  FAIL: $1"; fail=$((fail + 1)); }
has() { grep -qF -- "$2" "$1"; }
bhas() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
# after <file> <literal> <n> — the anchor line (first match) plus the next n lines.
after() { PM_A="$2" awk -v n="$3" 'f && c++ >= n { exit } !f && index($0, ENVIRON["PM_A"]) { f = 1 } f' "$1"; }
# section <file> <start ERE> <stop ERE> — from the start line up to (not incl.) the stop line.
section() { SA="$2" SB="$3" awk 'f && $0 ~ ENVIRON["SB"] { exit } $0 ~ ENVIRON["SA"] { f = 1 } f' "$1"; }

for f in "$SHA" "$RDY" "$RH" "$AO" "$WK" "$SUP" "$EM" "$CR" "$FE"; do [ -s "$f" ] || no "missing or empty: $f"; done

RULE='never the full `ci-local.sh` pool from a background worker'
echo "PART 1 — worker / fix-worker test command"
check_prompt() {   # check_prompt <label> <text>
  local label="$1" text="$2" names
  [ -n "$text" ] || { no "$label: prompt block not found"; return; }
  bhas "$text" 'ci-local.sh --affected' && ok "$label: names ci-local.sh --affected" || no "$label: no ci-local.sh --affected"
  bhas "$text" "$RULE" && ok "$label: states the background-worker rule" || no "$label: missing '$RULE'"
  bhas "$text" 'every static CI gate' && ok "$label: says the affected plan includes every static CI gate" \
    || no "$label: does not say the affected plan includes every static CI gate"
  names="$(printf '%s\n' "$text" | grep -oE '(^|[^*a-z])test-[a-z0-9_-]+\.sh' || true)"
  [ -z "$names" ] && ok "$label: lists no hand-typed suite names" || no "$label: hand-typed suite names: $(echo $names)"
}
check_prompt "self-heal-advisory fix worker" "$(after "$SHA" '3. Run type-check and tests locally before finishing' 0)"
check_prompt "review-heal Step 2" "$(after "$RH" 'Address ONLY these new review findings at or above the fix floor' 3)"
check_prompt "review-heal Step U4" "$(after "$RH" 'Address ONLY these required-check failures and VALIDATED bot findings' 13)"
check_prompt "Worker Prompt Template" "$(section "$AO" '^### Worker Prompt Template' '^5\. Output a WORKER_RESULT block')"
check_prompt "worker.md Step 5" "$(section "$WK" '^### Step 5: Verify' '^3\. If no tests')"
has "$WK" 'pre-push command belongs to the foreground session / FINALIZE' && ok "worker.md: the full pre-push run belongs to the foreground session" \
  || no "worker.md: no foreground-session ownership of the pre-push run"
! has "$WK" "pre-push command once, before a push" && ok "worker.md: no line still orders the worker to run the pre-push command" \
  || no "worker.md: an opposite order (run the pre-push command) is still there"
grep -qE 'scripts/ci-local\.sh' "$RH" && no "review-heal names scripts/ci-local.sh (test-dispatch-pr-review.sh's drift guard reads it as a plugin script)" \
  || ok "review-heal names the PROJECT command without a scripts/ path (the drain allowlist guard stays plugin-only)"

echo "PART 2 — Phase 3 pin gate"
CACHE='--cache .supervisor/pin-mutations/{brief basename without .md}.tsv'
S3A="$(grep -F -- '3a. **Pin-mutation gate' "$SUP" | head -1)"
bhas "$S3A" 'scripts/run-pin-mutations.sh" {brief_path} --root . '"$CACHE" && ok "supervisor Single-Agent 3a runs the script with the shared cache" \
  || no "supervisor 3a: script call / cache path"
bhas "$S3A" 'ONE re-spawn of the same worker' && bhas "$S3A" '`Retry context:` = the `not_held` lines verbatim' \
  && ok "supervisor 3a: one re-spawn with the not_held lines as Retry context" || no "supervisor 3a: re-spawn clause"
bhas "$S3A" 'never folded into its adjudication flow, never a pause' && ok "supervisor 3a: never adjudication, never a pause" \
  || no "supervisor 3a: non-pausing clause"
has "$SUP" '- **Pin-mutation gate:** Single-Agent step 3a above, scoped with `--only-paths <this subtask'"'"'s lanes:>`.' \
  && ok "supervisor Sequential Path: the same gate, scoped to the subtask's lanes" || no "supervisor Sequential bullet"
has "$SUP" 'Disk gap → adjudication' && ok "supervisor step 3 keeps 'Disk gap → adjudication'" || no "supervisor step 3 lost its adjudication rule"
EMG="$(section "$EM" '# --- Pin-mutation gate \(automate-speed/02\)' '# --- Lane-collision gate')"
bhas "$EMG" 'scripts/run-pin-mutations.sh" {brief_path} --root {worktree_path} --cache {main_checkout}/.supervisor/pin-mutations/' \
  && bhas "$EMG" '--only-paths' && ok "execute-manager poll loop runs the scoped script with the main-checkout cache" \
  || no "execute-manager pin gate call"
bhas "$EMG" 'retry once in same worktree' && bhas "$EMG" 'no second re-spawn' && ok "execute-manager: one re-spawn, crash-retry shape" \
  || no "execute-manager: re-spawn shape"
[ "$(grep -n -- '--- v12 outputs_verified gate' "$EM" | head -1 | cut -d: -f1)" -lt "$(grep -n -- '# --- Pin-mutation gate' "$EM" | head -1 | cut -d: -f1)" ] 2>/dev/null \
  && ok "execute-manager: the pin gate sits after the outputs_verified gate" || no "execute-manager: pin gate order"
has "$EM" '| Pin mutation not_held (`run-pin-mutations.sh`, poll-loop pin gate) | Re-spawn once in the same worktree' \
  && ok "execute-manager failure table names Pin mutation not_held" || no "execute-manager failure-table row"
has "$EM" 'the ONE `run-pin-mutations.sh` Bash call of the pin gate' && ok "execute-manager tool-call tracking counts the pin call" \
  || no "execute-manager tool-call tracking"
has "$FE" '| Worker | Pin mutation not_held | 1 (automatic re-spawn) | recorded, carried to Phase 4.5 as BLOCKING (never adjudication) |' \
  && ok "FAILURE_ESCALATION Escalation Summary names Pin mutation not_held" || no "FAILURE_ESCALATION row"
has "$AO" 'or pin-mutation gate `not_held` lines' && ok "async-orchestration Retry context carries the not_held lines" \
  || no "async-orchestration Retry context"

echo "PART 3 — Phase 4.5 pin verdicts + CI read"
LOOP="$(section "$SHA" '^while heal_iterations < max_heal_iterations:' '^# Loop exit')"
[ -n "$LOOP" ] && ok "self-heal loop found" || no "self-heal loop not found"
pin_n="$(grep -n 'scripts/run-pin-mutations.sh" {brief_path} --root . --cache .supervisor/pin-mutations/' <<<"$LOOP" | head -1 | cut -d: -f1)"
rev_n="$(grep -n '^  review = Task(' <<<"$LOOP" | head -1 | cut -d: -f1)"
[ -n "$pin_n" ] && [ -n "$rev_n" ] && [ "$pin_n" -lt "$rev_n" ] && ok "Phase 4.5 runs the pin script (same cache) before the reviewer spawn" \
  || no "Phase 4.5 pin call missing or after the reviewer spawn (pin=$pin_n review=$rev_n)"
# PIN-MUTATION VERDICTS must be the next non-blank line after DEVIATIONS ADVISORY.
next_after_dev="$(awk '
  hit && NF { print; exit }
  { t = $0; sub(/^[[:space:]]+/, "", t) }
  index(t, "**DEVIATIONS ADVISORY (") == 1 { hit = 1 }' "$SHA")"
case "$next_after_dev" in *'**PIN-MUTATION VERDICTS (DATA'*) ok "PIN-MUTATION VERDICTS is the next line after DEVIATIONS ADVISORY" ;;
  *) no "PIN-MUTATION VERDICTS does not directly follow DEVIATIONS ADVISORY" ;; esac
bhas "$next_after_dev" '{pin_out}' && bhas "$next_after_dev" 'ONLY for a row reported `unverified`' \
  && ok "the verdict block carries the script output and the D1 fallback" || no "verdict block content"
ci_n="$(grep -n 'scripts/phase45-ci-read.sh" {pr_url} --sha' <<<"$LOOP" | head -1 | cut -d: -f1)"
fx_n="$(grep -nF 'fixable_issues = [i for i in review.issues if at_floor(i)] + rule_findings' <<<"$LOOP" | head -1 | cut -d: -f1)"
[ -n "$ci_n" ] && [ "$ci_n" -gt "$rev_n" ] && [ -n "$fx_n" ] && [ "$ci_n" -lt "$fx_n" ] \
  && ok "Phase 4.5 reads CI once, after the review and before fixable_issues is built" || no "CI read placement (ci=$ci_n review=$rev_n fixable=$fx_n)"
[ "$(grep -c 'phase45-ci-read.sh' <<<"$LOOP")" = 1 ] && ok "exactly one CI read per iteration" || no "CI read count in the loop != 1"
grep -qF 'fixable_issues += ci_findings' <<<"$LOOP" && ok "CI findings are appended to the one fixable_issues list" \
  || no "fixable_issues += ci_findings missing"
grep -qF 'if ci_findings != [] and iter_decision == PASS:' <<<"$LOOP" && ok "a CI finding makes a reviewer PASS a fix iteration" \
  || no "CI finding does not convert PASS"
bhas "$LOOP" 'never a finding, never an escalation' && ok "untrusted_infra notes are recorded, never a finding (D3)" || no "D3 note clause"
has "$CR" 'PIN-MUTATION VERDICTS' && ok "code-reviewer names the PIN-MUTATION VERDICTS block" || no "code-reviewer: PIN-MUTATION VERDICTS"

echo "PART 4 — readiness two-form grammar"
PMT="$(section "$RDY" '^## Pin mutations$' '^## Subtask Structure$')"
bhas "$PMT" 'two machine-applicable mutation forms' && bhas "$PMT" '`` delete `<literal>` in `<path>` ``' \
  && bhas "$PMT" '`` flip `<A>` → `<B>` in `<path>` ``' && ok "readiness: the two machine-applicable forms" || no "readiness: grammar sentence"
bhas "$PMT" "the Pin cell's first backticked token is the pin's test file" && ok "readiness: first backticked token = the pin's test file" \
  || no "readiness: first-token rule"
bhas "$PMT" "Any other wording reads \`unverified\` and is left to the reviewer's D1 fallback" && ok "readiness: other wording ⇒ D1 fallback" \
  || no "readiness: D1 fallback clause"
bhas "$PMT" '| Pin | Mutation (one line, applied to the code the pin protects) |' && bhas "$PMT" 'one row per new or changed pin' \
  && ok "readiness: table header + Criterion 19's authoring rule kept" || no "readiness: header / authoring rule changed"

if [ "${SEAM_NO_MUTATION:-0}" != "1" ]; then
  echo "PART 5 — mutation control"
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
  cp "$SHA" "$W/sha.md"; cp "$RDY" "$W/rdy.md"
  child() { SEAM_NO_MUTATION=1 SEAM_SHA="$1" SEAM_READINESS="$2" bash "$HERE/test-phase45-rounds-seam.sh" >/dev/null 2>&1; }
  if child "$W/sha.md" "$W/rdy.md"; then ok "positive control: unmutated temp copies pass"
  else no "positive control failed — mutation results would be meaningless"; fi
  # the fix worker's --affected sentence, cut out of step 3 (the rest of the line stays)
  awk '{ i = index($0, ": run `bash scripts/ci-local.sh --affected`"); j = index($0, " WAITING:");
         if (i && j > i && index($0, "3. Run type-check and tests locally before finishing")) { $0 = substr($0, 1, i - 1) "." substr($0, j) } print }' \
    "$W/sha.md" > "$W/sha-m.md"
  awk '!/^- \*\*Machine-applicable rows:\*\*/' "$W/rdy.md" > "$W/rdy-m.md"
  for m in sha-m rdy-m; do
    case "$m" in sha-m) src=sha ;; *) src=rdy ;; esac
    if [ ! -s "$W/$m.md" ]; then no "mutant $m is empty"; continue; fi
    if cmp -s "$W/$m.md" "$W/$src.md"; then no "mutant $m is identical to its original"; continue; fi
    if [ "$src" = sha ]; then child "$W/$m.md" "$W/rdy.md"; else child "$W/sha.md" "$W/$m.md"; fi
    [ $? -ne 0 ] && ok "mutant $m is killed" || no "mutant $m survived"
  done
fi

echo
echo "test-phase45-rounds-seam.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
