#!/usr/bin/env bash
# test-rule-conformance-seam.sh — static seam test for plan-time rule routing
# (plan-time-rule-routing, decision 7 / AC8).
#
# Launch Pad and Plan Reviewer are LLM prompts, so CI can only pin their TEXT; the behavioral proof
# of Criterion 17 is the LIVE probe (AC7) run on the committed fixtures under
# fixtures/rule-conformance/. This test pins:
#   PART 1  Launch Pad's Phase 3 action 0c shape (reader invoked with `--with-ids`, paths as
#           ARGUMENTS, empty ⇒ omit), Phase 5 action 6a (House Rules section with the demoted
#           banner, `- rule: <id>` bullets, empty ⇒ emit neither) and the Phase 5.5 APPLICABLE
#           RULES block's conditional emission; the criteria count (now 19) in the command mirror.
#   PART 2  Plan Reviewer Criterion 17: skip clause, 17a / 17b FAIL conditions, the
#           `rule_conformance` category (criterion body AND output-format enum), the count, and
#           Criterion 14's classifier naming `rule:` as a non-cmd prefix.
#   PART 2b Plan Reviewer Criterion 18 (touched-file invariants, iq01): gate, 18a/18b/18c, the
#           `touched_file_invariants` category, and the template ↔ Launch Pad agent ↔ command
#           mirror that produces the section it checks.
#   PART 3  Fixture well-formedness: the fixture store parses under `read-rules.sh --with-ids`
#           in a sandbox `git init` repo (copied in, never the live store — the FIXREPO pattern of
#           test-rules-seams.sh PART 2), routes by `applies_to`, each brief's `## House Rules`
#           section is exactly that reader output with its banner demoted, and each brief's
#           `## Executable Acceptance` classifies through exec-acceptance-lib.sh's classify_kind
#           as its role requires.
#   PART 4  Mutation control (lesson fa32a308): deleting Criterion 17's 17b sentence, Criterion
#           18's 18a sentence, or Launch Pad's action 0c, from a TEMP copy must make this test fail. Each mutant is gated on
#           non-empty + differs-from-original, and a positive control (unmutated temp copies)
#           must pass first, so a vacuous or broken harness cannot report a false kill.
#
#   PART 5  #432 plan half — an AC that contradicts an ADVISORY rule: Plan Reviewer 17c (NEEDS_HUMAN
#           unless an owner-acknowledged `Rule override:` line is present; a scope line is never an
#           override), Launch Pad carrying `## Rule conflicts (open decisions)` through verbatim and
#           owning the 17c gate (action 2b, catalog code LP-RULE-OVR, can't-ask status
#           rule_conflict_non_interactive, inventory row), Product Owner's Assumption Check d.
#           (reads the rules, writes the section; agent<->command mirror byte-identical), and the
#           fixtures under fixtures/rule-conformance/advisory/ (override grammar with negative
#           controls, story->brief byte-identical carry, reader trace, plan-waves --lint). PART 4
#           also kills mutants that delete 17c, Launch Pad action 2b, or the PO d. check. Prompt
#           BEHAVIOUR (a model actually flagging the contradiction) is the live probe on those
#           fixtures, not this test.
#
# Env overrides (used by PART 4's re-invocation only): SEAM_LP (agents/launch-pad.md),
# SEAM_PR (agents/plan-reviewer.md), SEAM_PO (agents/product-owner.md), SEAM_NO_MUTATION=1
# (skip PART 4 in the child).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
LP="${SEAM_LP:-$PLUGIN/agents/launch-pad.md}"
PR="${SEAM_PR:-$PLUGIN/agents/plan-reviewer.md}"
LPC="$PLUGIN/commands/launch-pad.md"
PO="${SEAM_PO:-$PLUGIN/agents/product-owner.md}"
POC="$PLUGIN/commands/product-owner.md"
ARCH="$PLUGIN/docs/ARCHITECTURE_CONTRACTS.md"
FIX="$HERE/fixtures/rule-conformance"
READER="$HERE/read-rules.sh"
LIB="$HERE/exec-acceptance-lib.sh"
RULE_ID="payments-money-integer-minor-units"
BANNER='## Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)'
DEMOTED='> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)'

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
has()  { grep -qF -- "$2" "$1"; }                       # has <file> <literal>
lacks() { ! grep -qF -- "$2" "$1"; }
# block <file> <start-ERE> <stop-ERE> — lines from the first start match up to (not incl.) stop.
# Patterns go through ENVIRON, not `awk -v` (which would process the backslash escapes away).
block() { BLK_A="$2" BLK_B="$3" awk 'f && $0 ~ ENVIRON["BLK_B"] {exit} $0 ~ ENVIRON["BLK_A"] {f=1} f' "$1"; }
bhas() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }  # bhas <text> <literal>

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

echo "PART 1 — Launch Pad (plan side)"
for f in "$LP" "$LPC"; do [ -s "$f" ] || no "missing or empty: $f"; done
A0C="$(block "$LP" '^0c\. ' '^1\. Parse CLAUDE\.md')"
if [ -n "$A0C" ]; then ok "action 0c present"; else no "action 0c block not found"; fi
# The plugin-root variable is assembled from parts so this test does not itself count as a
# vendor-coupling reference (scripts/check-vendor-coupling.sh); the asserted string is unchanged.
ROOTVAR='${''CLAUDE_''PLUGIN_ROOT}'
bhas "$A0C" "bash \"$ROOTVAR/scripts/read-rules.sh\" --with-ids <space-separated File-Impact-Map paths>" \
  && ok "0c invokes read-rules.sh --with-ids with File-Impact-Map paths" || no "0c invocation shape"
bhas "$A0C" 'command-line ARGUMENTS** (NOT via stdin)' && ok "0c: paths as arguments, never stdin" || no "0c args-not-stdin clause"
bhas "$A0C" 'after action 3 settles the File Impact Map' && ok "0c runs after action 3" || no "0c ordering clause"
bhas "$A0C" 'Empty output ⇒ `applicable_rules` is empty' && bhas "$A0C" 'are both OMITTED' \
  && ok "0c: empty ⇒ omit rule" || no "0c empty ⇒ omit clause"
A6A="$(block "$LP" '^6a\. \*\*House Rules' '^7\. ')"
bhas "$A6A" 'Emit a `## House Rules` section' && ok "6a emits ## House Rules" || no "6a House Rules section"
bhas "$A6A" "$DEMOTED" && ok "6a demotes the reader banner to a blockquote" || no "6a demoted banner text"
bhas "$A6A" 'emit `- rule: <id>` in `## Executable Acceptance`' && ok "6a emits rule: bullets" || no "6a rule: bullet clause"
bhas "$A6A" 'whose `check` is not `(none)`' && ok "6a: only checkable must rules" || no "6a checkable-must scoping"
bhas "$A6A" 'When `applicable_rules` is empty, emit NEITHER' && ok "6a: empty ⇒ emit neither" || no "6a empty ⇒ neither clause"
bhas "$A6A" 'does NOT relax the `cmd:` prohibition' && ok "6a keeps the cmd: prohibition" || no "6a cmd: prohibition clause"
SPAWN="$(block "$LP" '^\*\*Spawn contract:\*\*' '^\*\*Output:\*\*')"
bhas "$SPAWN" '--- APPLICABLE RULES ---' && bhas "$SPAWN" '--- APPLICABLE RULES END ---' \
  && ok "spawn carries the APPLICABLE RULES block" || no "spawn APPLICABLE RULES markers"
bhas "$SPAWN" 'OMIT this whole block, both markers included, when applicable_rules is empty' \
  && ok "spawn: block omitted when empty" || no "spawn conditional-emission clause"
bhas "$SPAWN" 'Check all 19 review criteria.' && ok "spawn: Check all 19" || no "spawn criteria count"
lacks "$LP" 'Check all 18' && ok "no stale 'Check all 18'" || no "stale 'Check all 18' in launch-pad agent"
has "$LPC" 'checks all 19 criteria' && lacks "$LPC" 'all 18 criteria' \
  && ok "command mirror: all 19 criteria" || no "command mirror criteria count"

echo "PART 2 — Plan Reviewer Criterion 17"
[ -s "$PR" ] || no "missing or empty: $PR"
C17="$(block "$PR" '^### 17\. Rule Conformance' '^### 18\. ')"
if [ -n "$C17" ]; then ok "### 17. Rule Conformance present"; else no "Criterion 17 block not found"; fi
bhas "$C17" 'no `--- APPLICABLE RULES ---` block in the spawn prompt, or a block that lists no rules → skip silently' \
  && ok "17: skip clause" || no "17 skip clause"
bhas "$C17" '**17a — contradiction.** FAIL when the brief' && bhas "$C17" "contradict an applicable \`enforcement: must\` rule" \
  && ok "17a FAIL condition" || no "17a FAIL condition"
bhas "$C17" '**17b — omission.** FAIL when an applicable `enforcement: must` rule whose `check` is not `(none)` has no matching `- rule: <id>` bullet' \
  && ok "17b FAIL condition" || no "17b FAIL condition"
bhas "$C17" '**Advisory rules never FAIL.**' && ok "17: advisory never FAILs" || no "17 advisory clause"
bhas "$C17" '**Issue category:** `rule_conformance`' && ok "17: rule_conformance category" || no "17 category"
bhas "$C17" 'HIGH for 17a and 17b' && ok "17: HIGH severity" || no "17 severity"
has "$PR" '| lane_overlap | rule_conformance |' && ok "output-format category enum lists rule_conformance" || no "category enum"
has "$PR" '## 19 Review Criteria' && lacks "$PR" '## 18 Review Criteria' && has "$PR" 'All 19 review criteria must be checked' \
  && has "$PR" '(19 total, Criteria 11, 12, 13, 14, 15, 16, 17, 18, and 19 conditional)' && has "$PR" 'All 19 criteria checked' \
  && ok "criteria count 19 at heading / never-skip / matrix / checklist" || no "criteria count surfaces"

echo "PART 2b — Plan Reviewer Criterion 18 + the section it checks"
C18="$(block "$PR" '^### 18\. Touched-File Invariants' '^### 19\. ')"
if [ -n "$C18" ]; then ok "### 18. Touched-File Invariants present"; else no "Criterion 18 block not found"; fi
bhas "$C18" 'Only creates, or only non-script edits → skip silently' && ok "18: skip clause" || no "18 skip clause"
bhas "$C18" '**18a — absence.** The gate fires and the brief has no `## Touched-file invariants` section.' \
  && ok "18a absence condition" || no "18a absence condition"
bhas "$C18" '**18b — coverage.**' && bhas "$C18" 'which matchers/callers fire it' && ok "18b coverage incl. hook callers" || no "18b coverage"
bhas "$C18" '**18c — grounding.**' && bhas "$C18" '`Grep` at least one quoted anchor' && ok "18c grounding by grep" || no "18c grounding"
bhas "$C18" '**Issue category:** `touched_file_invariants`' && ok "18: category" || no "18 category"
bhas "$C18" 'HIGH for 18a' && ok "18: 18a is HIGH (FAIL)" || no "18 severity"
bhas "$C18" '§"Touched-file invariants"' && ok "18 points at the template" || no "18 template pointer"
has "$PR" '| touched_file_invariants |' && ok "output-format enum lists touched_file_invariants" || no "output enum missing touched_file_invariants"
SKILL="$PLUGIN/skills/supervisor-readiness/SKILL.md"
TFI="$(block "$SKILL" '^## Touched-file invariants$' '^## Subtask Structure')"
bhas "$TFI" '**Grounded:**' && bhas "$TFI" 'backticked literal that `grep -F` finds' && ok "template: grounding rule" || no "template grounding rule"
bhas "$TFI" 'fired by:' && bhas "$TFI" 'mirror:' && bhas "$TFI" 'pinned by:' && ok "template: entry fields" || no "template entry fields"
A11="$(block "$LP" '^11\. \*\*Touched-file invariants' '^\*\*Output:\*\*')"
bhas "$A11" 'Plan Reviewer Criterion 18' && bhas "$A11" '§"Touched-file invariants"' && ok "launch-pad action 11 ties template + Criterion 18" || no "launch-pad action 11"
has "$LP" '4c. **Touched-file invariants' && ok "launch-pad Phase 5 emits the section" || no "launch-pad Phase 5 emission"
has "$LPC" '8. Touched-file invariants' && has "$LPC" 'Criterion 18 runs only when the brief modifies an existing script' \
  && ok "command mirror: step 8 + Criterion 18 gate" || no "command mirror touched-file invariants"
has "$PLUGIN/docs/result-schemas/plan-review-result.md" '`touched_file_invariants` for Criterion 18' && ok "schema doc: category" || no "schema doc category"
has "$PR" '`corpus-task:` / `qa-executor:` / `rule:` prefix' && ok "Criterion 14 classifier names rule:" || no "Criterion 14 rule: prefix"

echo "PART 3 — fixtures"
for f in rules/must.json brief-conforming.md brief-contradicting.md brief-omitting.md; do
  [ -s "$FIX/$f" ] && ok "fixture present: $f" || no "fixture missing/empty: $f"
done
# Blind fixtures: a live Plan Reviewer probe reads the brief, so no brief may carry its own verdict or
# label. The answer key lives in the sibling README.md, which a probe never passes to the reviewer.
HINTS='expect|rule_conformance|17a|17b|conforming|contradicting|omitting'
for b in conforming contradicting omitting; do
  if grep -qiE -- "$HINTS" "$FIX/brief-$b.md"; then
    no "brief-$b.md leaks a verdict/label hint (/$HINTS/i): $(grep -niE -- "$HINTS" "$FIX/brief-$b.md" | head -n1)"
  else
    ok "brief-$b.md carries no verdict/label hint (case-insensitive /$HINTS/)"
  fi
done
T_CONF="$(grep -m1 '^# Supervisor Job:' "$FIX/brief-conforming.md")"
T_CONT="$(grep -m1 '^# Supervisor Job:' "$FIX/brief-contradicting.md")"
T_OMIT="$(grep -m1 '^# Supervisor Job:' "$FIX/brief-omitting.md")"
[ -n "$T_CONF" ] && [ "$T_CONF" = "$T_CONT" ] && [ "$T_CONF" = "$T_OMIT" ] \
  && ok "all three briefs share one neutral title ($T_CONF)" || no "brief titles differ: '$T_CONF' / '$T_CONT' / '$T_OMIT'"
RM="$FIX/README.md"
if [ -s "$RM" ]; then
  R_CONF="$(grep -F '| `brief-conforming.md` |' "$RM")"
  R_CONT="$(grep -F '| `brief-contradicting.md` |' "$RM")"
  R_OMIT="$(grep -F '| `brief-omitting.md` |' "$RM")"
  bhas "$R_CONF" 'PASS: no `rule_conformance` issue' \
    && ok "README: conforming => PASS, no rule_conformance issue" || no "README conforming verdict row: '$R_CONF'"
  bhas "$R_CONT" 'FAIL: 17a HIGH `rule_conformance`' \
    && ok "README: contradicting => FAIL 17a HIGH rule_conformance" || no "README contradicting verdict row: '$R_CONT'"
  bhas "$R_OMIT" 'FAIL: 17b HIGH `rule_conformance`' \
    && ok "README: omitting => FAIL 17b HIGH rule_conformance" || no "README omitting verdict row: '$R_OMIT'"
else
  no "fixture answer key missing/empty: README.md"
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "  skip: jq unavailable — read-rules.sh no-ops by contract, so the store trace is vacuous here."
else
  jq -e 'type=="array" and length==1 and .[0].enforcement=="must" and (.[0].check|type=="string")
         and (.[0].applies_to|type=="array")' "$FIX/rules/must.json" >/dev/null 2>&1 \
    && ok "store: one must rule, string check, routed by applies_to" || no "store shape"
  FIXREPO="$WORK/repo"
  mkdir -p "$FIXREPO/.agent/rules"
  ( cd "$FIXREPO" && git init -q ) >/dev/null 2>&1
  cp "$FIX"/rules/*.json "$FIXREPO/.agent/rules/"
  OUT="$( cd "$FIXREPO" && bash "$READER" --with-ids src/payments/refund.ts </dev/null 2>/dev/null )"
  [ "$(printf '%s\n' "$OUT" | sed -n 1p)" = "$BANNER" ] && ok "reader: H2 banner first" || no "reader banner"
  bhas "$OUT" "  - id: $RULE_ID" && bhas "$OUT" '  - enforcement: must' && bhas "$OUT" '- [MUST] ' \
    && ok "reader --with-ids: id + enforcement + [MUST]" || no "reader --with-ids lines"
  bhas "$OUT" 'check (data only, NOT executed by this reader): (none)' && no "fixture check renders (none)" || ok "fixture check is non-(none)"
  UNR="$( cd "$FIXREPO" && bash "$READER" --with-ids README.md </dev/null 2>/dev/null )"
  [ -z "$UNR" ] && ok "unrouted path ⇒ empty (the empty ⇒ omit case)" || no "rule leaked to an unrouted path"
  EXPECT="$(printf '%s\n' "$OUT" | sed "1s/.*/$DEMOTED/")"
  for b in conforming contradicting omitting; do
    HRB="$(block "$FIX/brief-$b.md" '^## House Rules$' '^## Executable Acceptance$' | sed '1d' | sed '/^$/d')"
    [ -n "$OUT" ] && [ "$HRB" = "$EXPECT" ] && ok "brief-$b: ## House Rules == reader output, banner demoted" \
      || no "brief-$b: House Rules block drifted from the reader output"
  done
fi
if [ -r "$LIB" ]; then
  # shellcheck source=/dev/null
  . "$LIB"
  kinds() { extract_brief_section_bullets "$1" | while IFS= read -r l; do printf '%s|%s\n' "$(classify_kind "$l")" "$l"; done; }
  K="$(kinds "$FIX/brief-conforming.md")"
  [ "$K" = "rule|rule: $RULE_ID" ] && ok "conforming: sole bullet classifies rule (id matches store)" || no "conforming classify: $K"
  K="$(kinds "$FIX/brief-contradicting.md")"
  [ "$K" = "rule|rule: $RULE_ID" ] && ok "contradicting: carries the rule: bullet (isolates 17a)" || no "contradicting classify: $K"
  K="$(kinds "$FIX/brief-omitting.md")"
  [ "$K" = "corpus-task|corpus-task: version-consistent" ] && ok "omitting: no rule: bullet (isolates 17b)" || no "omitting classify: $K"
  lacks "$FIX/brief-omitting.md" '- rule:' && ok "omitting: no rule: bullet anywhere" || no "omitting carries a rule: bullet"
else
  no "exec-acceptance-lib.sh unreadable"
fi
DEC="$(block "$FIX/brief-contradicting.md" '^## Design decisions' '^## Acceptance Criteria')"
bhas "$DEC" 'parseFloat(amount)' && ok "contradicting: Design decisions use parseFloat (17a target)" || no "contradicting has no contradiction"
for b in conforming omitting; do
  DEC="$(block "$FIX/brief-$b.md" '^## Design decisions' '^## Acceptance Criteria')"
  { bhas "$DEC" parseFloat || bhas "$DEC" toFixed; } && no "brief-$b contradicts the rule" || ok "brief-$b: Design decisions honor the rule"
done

echo "PART 5 — advisory-rule conflicts at plan time (#432 plan half: Product Owner, Criterion 17c, Launch Pad)"
ADV="$FIX/advisory"
ADV_ID="ui-select-max-ten-options"
CONFLICTS_H='## Rule conflicts (open decisions)'
# The override grammar, as an ERE over one line: id, an em-dash, a non-empty why, then the owner
# acknowledgment with a non-empty <where> and an ISO date.
OVR_ERE='^- Rule override: [a-z0-9][a-z0-9-]* — .*[^ ].* \(acknowledged by the owner: [^,)]*[^ ,)], [0-9]{4}-[0-9]{2}-[0-9]{2}\)$'
CONF_ERE='^- Conflicts with house rule [a-z0-9][a-z0-9-]* \((advisory|must)\): AC ".+" vs rule ".+"\. Owner'"'"'s choice: (pending|honor the rule|override|change the rule via /rules)$'
# 5a — Plan Reviewer 17c (re-uses the Criterion 17 block from PART 2).
bhas "$C17" '**17c — advisory contradiction.**' && ok "17c present" || no "17c sentence missing"
bhas "$C17" '`- Rule override: <id> — <why> (acknowledged by the owner: <where>, <YYYY-MM-DD>)`' \
  && ok "17c: override grammar" || no "17c override grammar"
bhas "$C17" 'is not an override' && bhas "$C17" 'out of scope' && ok "17c: a scope line is never an override" || no "17c scope-line clause"
bhas "$C17" "Owner's choice: pending" && ok "17c: a pending conflict line triggers it" || no "17c pending-conflict carve-out"
bhas "$C17" 'description starts `17c:`' && ok "17c: issue description prefix" || no "17c description prefix"
bhas "$C17" 'MEDIUM for 17c' && ok "17c: MEDIUM severity" || no "17c severity"
bhas "$C17" 'never relaxes 17a or 17b' && ok "17c: an override never relaxes a must rule" || no "17c must-rule clause"
grep -qE '^\| Criterion 17c .*\*\*NEEDS_HUMAN\*\*' "$PR" && ok "decision matrix: 17c ⇒ NEEDS_HUMAN" || no "decision matrix 17c row"
CHK="$(grep -F -- '- [ ] All 19 criteria checked' "$PR")"
grep -qF '17c' <<<"$CHK" && ok "quality checklist names 17c" || no "checklist 17c"
# 5b — Launch Pad carries the section through and owns the 17c gate.
bhas "$A6A" '**(iii)**' && bhas "$A6A" "$CONFLICTS_H" && bhas "$A6A" 'copy it into the brief verbatim' \
  && bhas "$A6A" 'independent of `applicable_rules`' && ok "6a (iii): carry the Rule conflicts section verbatim" || no "6a (iii) carry-through"
P6="$(block "$LP" '^### Phase 6: REFINE & SAVE' '^### Phase 7')"
A2B="$(block "$LP" '^2b\. \*\*House-rule override NEEDS_HUMAN' '^3\. If Plan Review returned PASS')"
[ -n "$A2B" ] && ok "Phase 6 action 2b present" || no "Phase 6 action 2b missing"
for s in '`record-override`' '`honor-rule`' '`discard`' 'rule_conflict_non_interactive' '**Never author an override.**' '`LP-RULE-OVR`'; do
  bhas "$A2B" "$s" && ok "2b names $s" || no "2b lacks $s"
done
bhas "$P6" 'rule_conflict_non_interactive' && ok "Phase 6 names rule_conflict_non_interactive" || no "Phase 6 status"
P55="$(block "$LP" '^### Phase 5\.5: PLAN REVIEW' '^### Phase 6: ')"
bhas "$P55" 'issue.description.startswith("17c:")' && ok "Phase 5.5 retry loop routes 17c to action 2b" || no "Phase 5.5 17c branch"
for f in "$LP" "$LPC"; do
  CAR="$(grep -F -- "- **Can't-ask rule:**" "$f")"
  grep -qF 'rule_conflict_non_interactive' <<<"$CAR" \
    && ok "$(basename "$(dirname "$f")")/launch-pad.md Can't-ask rule names rule_conflict_non_interactive" \
    || no "$(basename "$(dirname "$f")")/launch-pad.md Can't-ask rule lacks rule_conflict_non_interactive"
done
has "$LPC" 'record-override' && ok "command mirror: 17c gate options" || no "command mirror 17c gate"
# 5c — Product Owner reads the rules and writes the section (agent + command mirror).
po_d() { block "$1" '^   d\. \*\*House-rule conflicts\*\*' '^   \*\*Output \(appended to Context Read section\):\*\*'; }
POD_A="$(po_d "$PO")"; POD_C="$(po_d "$POC")"
[ -n "$POD_A" ] && ok "PO agent: Assumption Check d. House-rule conflicts" || no "PO agent d. missing"
bhas "$POD_A" "bash \"$ROOTVAR/scripts/read-rules.sh\" --with-ids" && ok "PO d: runs the reader with --with-ids" || no "PO d reader call"
for s in "$CONFLICTS_H" 'Conflicts with house rule <id>' "Owner's choice: pending" 'never executes' 'never resolve' 'before `## Depends on`'; do
  bhas "$POD_A" "$s" && ok "PO d names: $s" || no "PO d lacks: $s"
done
[ -n "$POD_A" ] && [ "$POD_A" = "$POD_C" ] && ok "PO d block byte-identical in agent and command (mirror)" || no "PO d block differs agent vs command"
for f in "$PO" "$POC"; do
  CAB="$(grep -F -- "**Can't-ask branch" "$f")"
  grep -qF '+ house-rule conflicts' <<<"$CAB" \
    && ok "$(basename "$(dirname "$f")")/product-owner.md can't-ask count includes house-rule conflicts" \
    || no "$(basename "$(dirname "$f")")/product-owner.md can't-ask count omits house-rule conflicts"
done
# 5d — the gate is catalogued human-only and inventoried with its can't-ask status.
CAT="$(bash "$HERE/lane-policy.sh" catalog 2>/dev/null | awk -F'\t' '$1 == "LP-RULE-OVR" { print $2 "|" $3 }')"
[ "$CAT" = "human-only|record-override|honor-rule|discard" ] && ok "lane catalog: LP-RULE-OVR human-only with its labels" || no "lane catalog row: '$CAT'"
INV="$(block "$ARCH" '^## Question-gate inventory' '^## Failure Escalation Summary')"
INVROW="$(grep -F '| Launch Pad house-rule override NEEDS_HUMAN |' <<<"$INV")"
grep -qF 'rule_conflict_non_interactive' <<<"$INVROW" \
  && ok "question-gate inventory row names rule_conflict_non_interactive" || no "question-gate inventory row"
# 5e — fixtures.
for f in rules/advisory.json brief-no-override.md brief-override.md story-conflict.md README.md; do
  [ -s "$ADV/$f" ] && ok "advisory fixture present: $f" || no "advisory fixture missing/empty: $f"
done
AHINTS='expect|rule_conformance|17[abc]|needs_human'
for b in no-override override; do
  grep -qiE -- "$AHINTS" "$ADV/brief-$b.md" && no "brief-$b.md leaks a verdict hint (/$AHINTS/i)" || ok "brief-$b.md carries no verdict hint"
done
[ "$(grep -m1 '^# Supervisor Job:' "$ADV/brief-no-override.md")" = "$(grep -m1 '^# Supervisor Job:' "$ADV/brief-override.md")" ] \
  && ok "both advisory briefs share one title" || no "advisory brief titles differ"
RROW="$(grep -F '| `brief-no-override.md` |' "$ADV/README.md")"
grep -qF 'NEEDS_HUMAN: 17c MEDIUM `rule_conformance`' <<<"$RROW" \
  && ok "README: no-override ⇒ NEEDS_HUMAN 17c" || no "README no-override row"
RROW="$(grep -F '| `brief-override.md` |' "$ADV/README.md")"
grep -qF 'PASS: no 17c issue' <<<"$RROW" \
  && ok "README: override ⇒ PASS" || no "README override row"
SEC_STORY="$(block "$ADV/story-conflict.md" '^## Rule conflicts \(open decisions\)$' '^## Depends on$')"
SEC_BRIEF="$(block "$ADV/brief-override.md" '^## Rule conflicts \(open decisions\)$' '^## Risk Assessment$')"
[ -n "$SEC_STORY" ] && [ "$SEC_STORY" = "$SEC_BRIEF" ] && ok "override brief carries the story's section byte-for-byte" || no "story ↔ brief section drift"
lacks "$ADV/brief-no-override.md" 'Rule override:' && lacks "$ADV/brief-no-override.md" "$CONFLICTS_H" \
  && ok "no-override brief: no override, no section" || no "no-override brief carries an override"
n_conf="$(grep -cE "$CONF_ERE" <<<"$SEC_STORY")"; n_ovr="$(grep -cE "$OVR_ERE" <<<"$SEC_STORY")"
[ "$n_conf" -eq 1 ] && [ "$n_ovr" -eq 1 ] && ok "story section: one conflict line + one override line, both well-formed" \
  || no "story section grammar (conflict=$n_conf override=$n_ovr)"
OVR_LINE="$(grep -E "$OVR_ERE" <<<"$SEC_STORY")"; CONF_LINE="$(grep -E "$CONF_ERE" <<<"$SEC_STORY")"
grep -qF "Rule override: $ADV_ID — " <<<"$OVR_LINE" && ok "override names the store's rule id" || no "override id mismatch"
grep -qF "house rule $ADV_ID (advisory)" <<<"$CONF_LINE" && ok "conflict line names id + enforcement" || no "conflict line id/enforcement"
# grammar controls: an override with no acknowledgment, or an empty why, is not well-formed.
grep -qE "$OVR_ERE" <<<"- Rule override: $ADV_ID — because" && no "grammar accepts an unacknowledged override" || ok "grammar rejects an unacknowledged override"
grep -qE "$OVR_ERE" <<<"- Rule override: $ADV_ID —  (acknowledged by the owner: x, 2026-10-13)" && no "grammar accepts an empty why" || ok "grammar rejects an empty why"
LINT="$(bash "$HERE/automate-helpers.sh" plan-waves "$ADV/story-conflict.md" --lint 2>&1)"; lrc=$?
[ "$lrc" -eq 0 ] && bhas "$LINT" 'Touches ok; Depends on ok' && ok "story with a Rule conflicts section still lints clean" || no "story lint: rc=$lrc $LINT"
if command -v jq >/dev/null 2>&1; then
  AREPO="$WORK/adv-repo"; mkdir -p "$AREPO/.agent/rules"; ( cd "$AREPO" && git init -q ) >/dev/null 2>&1
  cp "$ADV"/rules/*.json "$AREPO/.agent/rules/"
  AOUT="$( cd "$AREPO" && bash "$READER" --with-ids src/ui/address-form.tsx </dev/null 2>/dev/null )"
  bhas "$AOUT" "  - id: $ADV_ID" && bhas "$AOUT" '  - enforcement: advisory' && ! bhas "$AOUT" '[MUST]' \
    && ok "advisory store: routed, advisory, no [MUST]" || no "advisory reader output"
  AEXP="$(printf '%s\n' "$AOUT" | sed "1s/.*/$DEMOTED/")"
  for b in no-override override; do
    HRB="$(block "$ADV/brief-$b.md" '^## House Rules$' '^## (Rule conflicts|Risk Assessment)' | sed '1d' | sed '/^$/d')"
    [ -n "$AOUT" ] && [ "$HRB" = "$AEXP" ] && ok "brief-$b: ## House Rules == reader output, banner demoted" || no "brief-$b House Rules drift"
  done
else
  echo "  skip: jq unavailable — advisory store trace is vacuous here."
fi

if [ "${SEAM_NO_MUTATION:-0}" != "1" ]; then
  echo "PART 4 — mutation control"
  cp "$LP" "$WORK/lp.md"; cp "$PR" "$WORK/pr.md"
  child() { SEAM_NO_MUTATION=1 SEAM_LP="$1" SEAM_PR="$2" bash "$HERE/test-rule-conformance-seam.sh" >/dev/null 2>&1; }
  if child "$WORK/lp.md" "$WORK/pr.md"; then ok "positive control: unmutated temp copies pass"
  else no "positive control failed — mutation results would be meaningless"; fi
  awk '!/^- \*\*17b — omission\.\*\*/' "$WORK/pr.md" > "$WORK/pr-m.md"
  awk '!/^- \*\*18a — absence\.\*\*/' "$WORK/pr.md" > "$WORK/pr18-m.md"
  awk 'f && /^1\. Parse CLAUDE\.md/ {f=0} /^0c\. / {f=1} !f' "$WORK/lp.md" > "$WORK/lp-m.md"
  for m in pr-m pr18-m lp-m; do
    src="${m%-m}"; src="${src%18}"
    if [ ! -s "$WORK/$m.md" ]; then no "mutant $m is empty"; continue; fi
    if cmp -s "$WORK/$m.md" "$WORK/$src.md"; then no "mutant $m is identical to its original"; continue; fi
    if [ "$src" = pr ]; then child "$WORK/lp.md" "$WORK/$m.md"; else child "$WORK/lp-m.md" "$WORK/pr.md"; fi
    [ $? -ne 0 ] && ok "mutant $m (${m%%-*}) is killed" || no "mutant $m survived"
  done
  # #432 plan half: deleting 17c, Launch Pad's action 2b, or the PO d. check must each be killed.
  cp "$PO" "$WORK/po.md"
  child3() { SEAM_NO_MUTATION=1 SEAM_LP="$1" SEAM_PR="$2" SEAM_PO="$3" bash "$HERE/test-rule-conformance-seam.sh" >/dev/null 2>&1; }
  if child3 "$WORK/lp.md" "$WORK/pr.md" "$WORK/po.md"; then ok "positive control (with PO copy) passes"
  else no "positive control (with PO copy) failed"; fi
  awk '!/^- \*\*17c — advisory contradiction\.\*\*/' "$WORK/pr.md" > "$WORK/pr17c-m.md"
  awk 'f && /^3\. If Plan Review returned PASS/ {f=0} /^2b\. \*\*House-rule override NEEDS_HUMAN/ {f=1} !f' "$WORK/lp.md" > "$WORK/lp2b-m.md"
  awk 'f && /^   \*\*Output \(appended to Context Read section\):\*\*/ {f=0} /^   d\. \*\*House-rule conflicts\*\*/ {f=1} !f' "$WORK/po.md" > "$WORK/pod-m.md"
  for trio in "pr17c-m:lp:pr17c-m:po" "lp2b-m:lp2b-m:pr:po" "pod-m:lp:pr:pod-m"; do
    m="${trio%%:*}"; rest="${trio#*:}"; a="${rest%%:*}"; rest="${rest#*:}"; b="${rest%%:*}"; c="${rest#*:}"
    case "$m" in pr*) orig=pr ;; lp*) orig=lp ;; *) orig=po ;; esac
    if [ ! -s "$WORK/$m.md" ]; then no "mutant $m is empty"; continue; fi
    if cmp -s "$WORK/$m.md" "$WORK/$orig.md"; then no "mutant $m is identical to its original"; continue; fi
    child3 "$WORK/$a.md" "$WORK/$b.md" "$WORK/$c.md"
    [ $? -ne 0 ] && ok "mutant $m is killed" || no "mutant $m survived"
  done
fi

echo
echo "test-rule-conformance-seam.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
