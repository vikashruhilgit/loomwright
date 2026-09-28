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
#           RULES block's conditional emission; the 16 ⇒ 17 count in the command mirror.
#   PART 2  Plan Reviewer Criterion 17: skip clause, 17a / 17b FAIL conditions, the
#           `rule_conformance` category (criterion body AND output-format enum), the count, and
#           Criterion 14's classifier naming `rule:` as a non-cmd prefix.
#   PART 3  Fixture well-formedness: the fixture store parses under `read-rules.sh --with-ids`
#           in a sandbox `git init` repo (copied in, never the live store — the FIXREPO pattern of
#           test-rules-seams.sh PART 2), routes by `applies_to`, each brief's `## House Rules`
#           section is exactly that reader output with its banner demoted, and each brief's
#           `## Executable Acceptance` classifies through exec-acceptance-lib.sh's classify_kind
#           as its role requires.
#   PART 4  Mutation control (lesson fa32a308): deleting Criterion 17's 17b sentence, or Launch
#           Pad's action 0c, from a TEMP copy must make this test fail. Each mutant is gated on
#           non-empty + differs-from-original, and a positive control (unmutated temp copies)
#           must pass first, so a vacuous or broken harness cannot report a false kill.
#
# Env overrides (used by PART 4's re-invocation only): SEAM_LP (agents/launch-pad.md),
# SEAM_PR (agents/plan-reviewer.md), SEAM_NO_MUTATION=1 (skip PART 4 in the child).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
LP="${SEAM_LP:-$PLUGIN/agents/launch-pad.md}"
PR="${SEAM_PR:-$PLUGIN/agents/plan-reviewer.md}"
LPC="$PLUGIN/commands/launch-pad.md"
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
bhas "$SPAWN" 'Check all 17 review criteria.' && ok "spawn: Check all 17" || no "spawn criteria count"
lacks "$LP" 'Check all 16' && ok "no stale 'Check all 16'" || no "stale 'Check all 16' in launch-pad agent"
has "$LPC" 'checks all 17 criteria' && lacks "$LPC" 'all 16 criteria' \
  && ok "command mirror: all 17 criteria" || no "command mirror criteria count"

echo "PART 2 — Plan Reviewer Criterion 17"
[ -s "$PR" ] || no "missing or empty: $PR"
C17="$(block "$PR" '^### 17\. Rule Conformance' '^## Decision Matrix')"
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
has "$PR" '## 17 Review Criteria' && lacks "$PR" '## 16 Review Criteria' && has "$PR" 'All 17 review criteria must be checked' \
  && has "$PR" '(17 total, Criteria 11, 12, 13, 14, 15, 16, and 17 conditional)' && has "$PR" 'All 17 criteria checked' \
  && ok "criteria count 17 at heading / never-skip / matrix / checklist" || no "criteria count surfaces"
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

if [ "${SEAM_NO_MUTATION:-0}" != "1" ]; then
  echo "PART 4 — mutation control"
  cp "$LP" "$WORK/lp.md"; cp "$PR" "$WORK/pr.md"
  child() { SEAM_NO_MUTATION=1 SEAM_LP="$1" SEAM_PR="$2" bash "$HERE/test-rule-conformance-seam.sh" >/dev/null 2>&1; }
  if child "$WORK/lp.md" "$WORK/pr.md"; then ok "positive control: unmutated temp copies pass"
  else no "positive control failed — mutation results would be meaningless"; fi
  awk '!/^- \*\*17b — omission\.\*\*/' "$WORK/pr.md" > "$WORK/pr-m.md"
  awk 'f && /^1\. Parse CLAUDE\.md/ {f=0} /^0c\. / {f=1} !f' "$WORK/lp.md" > "$WORK/lp-m.md"
  for m in pr-m lp-m; do
    src="${m%-m}"
    if [ ! -s "$WORK/$m.md" ]; then no "mutant $m is empty"; continue; fi
    if cmp -s "$WORK/$m.md" "$WORK/$src.md"; then no "mutant $m is identical to its original"; continue; fi
    if [ "$m" = pr-m ]; then child "$WORK/lp.md" "$WORK/pr-m.md"; else child "$WORK/lp-m.md" "$WORK/pr.md"; fi
    [ $? -ne 0 ] && ok "mutant $m (${m%%-*}) is killed" || no "mutant $m survived"
  done
fi

echo
echo "test-rule-conformance-seam.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
