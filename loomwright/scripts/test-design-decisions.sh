#!/usr/bin/env bash
# test-design-decisions.sh — static seam test for the brief's optional `## Design decisions` section
# (approach-decisions/02): the template section, the read-on-demand Phase 2.7 protocol
# (skills/supervisor-readiness/design-decisions.md), Launch Pad Phase 2.7 APPROACH and its command
# mirror, the LP-APPROACH gate, Plan Reviewer Criterion 23 (23a–23d), the Red Team reinvention
# bullet and the schema categories.
#
# The LLM verdict itself is not unit-tested. Launch Pad and Plan Reviewer are LLM prompts, so CI can
# only pin their TEXT (the test-rule-conformance-seam.sh style). What a model actually does with that
# text is the running-system evidence in docs/evidence/design-decisions.md (Validations V4–V6). The
# EXPECTED issue shapes are pinned as fixtures: fixtures/design-decisions/expected-*.json is the
# answer key for the four brief-*.md fixtures, which run against the fixture repo in repo/.
#
# Arms, one per acceptance criterion:
#   AC1  template section, Section Requirements, Quality Checklist, the six entry keys
#   AC2  the split file: T1–T5 and their detection rules, candidate order, five axes, three evidence
#        sources (WebSearch only under --discovery), status values, the LP-APPROACH ask, the
#        Can't-ask branch, the worker `plan:` deviation sentence
#   AC3  Launch Pad Phase 2.7: position, trigger-gated Read(, no-trigger literal, header, the
#        Can't-ask clause, ≤ 25 lines, Phase-numbering line, the launch-pad agent budget kept at 47557
#   AC4  the command mirror: workflow sentence, Phase 2.7 block, byte-identical Can't-ask bullet,
#        Phase 5 step 2, Phase 5.5 step 2's conditional list and Criterion 23 clause
#   AC5  the gate catalog row (lane-policy.sh catalog), LANE_GATES.md and the Question-gate inventory
#   AC6  Criterion 23, its two Decision Matrix rows, the count literals, the category enum
#   AC7  the fixture briefs, their expected-shape JSON, and each brief's trigger text vs Criterion 23's gate
#   AC8  the Red Team vector-1 bullet
#   AC9  agents/worker.md: the `plan:` deviation channel the split file cites, and unchanged vs origin/main
#   AC10 no house rule written; the proposed `/rules add` line in the evidence file
#   AC11 the schema doc's two category lines; validate-plan-review-result.py unchanged vs origin/main
#
# The byte-identical guards (AC9, AC10, AC11) are this change's scope guards, not a permanent ban on
# editing those files: they run only while changelog.d/design-decisions.md is in the work tree and
# absent from origin/main (so on this change's own branch), and print a skip note otherwise — also
# when origin/main does not resolve (a shallow clone, a scratch copy with no remote).
#
# Usage: bash loomwright/scripts/test-design-decisions.sh   (no network; bash 3.2 safe)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"
SR="$PLUGIN/skills/supervisor-readiness/SKILL.md"
DD="$PLUGIN/skills/supervisor-readiness/design-decisions.md"
# The runtime path the prompts must read the split file through (the install-root variable, literal).
DD_RUNTIME='${CLAUDE_PLUGIN_ROOT}/skills/supervisor-readiness/design-decisions.md'
LP="$PLUGIN/agents/launch-pad.md"
LPC="$PLUGIN/commands/launch-pad.md"
PR="$PLUGIN/agents/plan-reviewer.md"
RT="$PLUGIN/agents/red-team-reviewer.md"
WK="$PLUGIN/agents/worker.md"
POL="$HERE/lane-policy.sh"
GATES="$PLUGIN/docs/LANE_GATES.md"
ARCH="$PLUGIN/docs/ARCHITECTURE_CONTRACTS.md"
SCHEMA="$PLUGIN/docs/result-schemas/plan-review-result.md"
BUDGETS="$PLUGIN/docs/prompt-token-budgets.json"
EVID="$REPO/docs/evidence/design-decisions.md"
FRAGMENT="changelog.d/design-decisions.md"
FIX="$HERE/fixtures/design-decisions"

pass=0; fail=0; skips=0
ok()   { echo "  ok: $1"; pass=$((pass+1)); }
no()   { echo "  FAIL: $1"; fail=$((fail+1)); }
skip() { echo "  skip: $1"; skips=$((skips+1)); }
has()   { grep -qF -- "$2" "$1"; }                       # has <file> <literal>
lacks() { ! grep -qF -- "$2" "$1"; }
# block <file> <start-ERE> <stop-ERE> — lines from the first start match up to (not incl.) stop.
block() { BLK_A="$2" BLK_B="$3" awk 'f && $0 ~ ENVIRON["BLK_B"] {exit} $0 ~ ENVIRON["BLK_A"] {f=1} f' "$1"; }
bhas() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }  # bhas <text> <literal>
# lineof <file> <ERE> — the first matching line number, or 0.
lineof() { LO_P="$2" awk '$0 ~ ENVIRON["LO_P"] {print NR; found=1; exit} END {if (!found) print 0}' "$1"; }
# in_order <a> <b> <c> — three line numbers, all non-zero and strictly increasing.
in_order() { [ "$1" -gt 0 ] && [ "$2" -gt "$1" ] && [ "$3" -gt "$2" ]; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

for f in "$SR" "$DD" "$LP" "$LPC" "$PR" "$RT" "$WK" "$POL" "$GATES" "$ARCH" "$SCHEMA" "$BUDGETS"; do
  [ -s "$f" ] || no "missing or empty: $f"
done

# scope_guard <label> <pathspec...> — the byte-identical guard (see the header for its scope).
scope_guard() {
  local label="$1"; shift
  if [ ! -f "$REPO/$FRAGMENT" ]; then skip "$label: $FRAGMENT is not pending, so this change's scope guard does not apply"; return; fi
  if ! git -C "$REPO" rev-parse --verify -q 'origin/main^{commit}' >/dev/null 2>&1; then
    skip "$label: origin/main does not resolve here, guard not run"; return
  fi
  if git -C "$REPO" cat-file -e "origin/main:$FRAGMENT" 2>/dev/null; then
    skip "$label: $FRAGMENT is already on origin/main, so this is not the change's own branch"; return
  fi
  if git -C "$REPO" diff --quiet --exit-code origin/main -- "$@" 2>/dev/null \
     && [ -z "$(git -C "$REPO" ls-files --others --exclude-standard -- "$@" 2>/dev/null)" ]; then
    ok "$label: byte-identical to origin/main"
  else
    no "$label: differs from origin/main"
  fi
}

echo "AC1 — template section (skills/supervisor-readiness/SKILL.md)"
DDL="$(lineof "$SR" '^## Design decisions$')"
TASKL="$(awk -v n="$DDL" 'NR < n && /^## / {h = $0; l = NR} NR >= n {exit} END {if (h == "## Task") print l; else print 0}' "$SR")"
ACL="$(awk -v n="$DDL" 'NR > n && /^## / {print (($0 == "## Acceptance Criteria") ? NR : 0); exit}' "$SR")"
if in_order "${TASKL:-0}" "$DDL" "${ACL:-0}"; then ok "template: ## Design decisions sits between ## Task and ## Acceptance Criteria"
else no "template: ## Design decisions is not between ## Task and ## Acceptance Criteria (task=$TASKL dd=$DDL ac=${ACL:-0})"; fi
TPL="$(block "$SR" '^## Design decisions$' '^## Acceptance Criteria$')"
for k in '- decision:' '  chosen:' '  rejected:' '  evidence:' '  revisit when:' '  status: confirmed | unconfirmed'; do
  bhas "$TPL" "$k" && ok "template entry key '$k'" || no "template entry key '$k' missing"
done
bhas "$TPL" 'design-decisions.md' && ok "template header note names the split file" || no "template header note does not name design-decisions.md"
SECREQ="$(block "$SR" '^### Section Requirements' '^### |^## ')"
bhas "$SECREQ" 'plus **optional sections**' && bhas "$SECREQ" '`Design decisions` (Launch Pad Phase 2.7, only on a trigger; Plan Reviewer Criterion 23)' \
  && ok "Section Requirements names Design decisions as optional" || no "Section Requirements does not name Design decisions as optional"
QC="$(block "$SR" '^## Quality Checklist' '^## [^Q]')"
bhas "$QC" '`## Design decisions` carries one entry per trigger' && ok "Quality Checklist names Design decisions" \
  || no "Quality Checklist does not name Design decisions"

echo "AC2 — the split file (skills/supervisor-readiness/design-decisions.md)"
head -1 "$DD" | grep -q '^# ' && ok "split file starts with a # title (no frontmatter)" || no "split file does not start with a # title"
TRIG="$(block "$DD" '^## Triggers' '^## [^T]')"
row() { printf '%s\n' "$TRIG" | grep -F -- "| \`$1\` |"; }
bhas "$(row T1)" 'check 1 or check 2 CAUTION row' && ok "T1 detected from a Phase 2.5 check 1/2 CAUTION row" || no "T1 detection rule"
bhas "$(row T2)" 'File Impact Map CREATE row that is a script or a module' && ok "T2 detected from a File Impact Map CREATE script/module row" || no "T2 detection rule"
for t in T3 T4 T5; do
  bhas "$(row $t)" 'the goal or `## Task`' && ok "$t detected from the goal and ## Task" || no "$t detection rule"
done
[ "$(printf '%s\n' "$TRIG" | grep -cE '^\| `T[1-5]` \|')" = 5 ] && ok "exactly five trigger rows T1–T5" || no "trigger rows are not exactly T1–T5"
bhas "$(row T2)" 'not a test, fixture, doc or evidence file' && ok "T2 row carries the not-a-test/fixture/doc/evidence exclusion (the authority the copies restate)" \
  || no "T2 row lacks the not-a-test/fixture/doc/evidence exclusion"
has "$DD" 'Bug fixes, docs, prompt-only edits and small changes never trigger' && has "$DD" '## Phase 2.7: APPROACH — no trigger' && ok "no-trigger rule (full sentence) and literal" || no "no-trigger rule or literal"
C1="$(lineof "$DD" '^1\. \*\*already in the repo\*\*')"; C2="$(lineof "$DD" '^2\. \*\*provided by the platform\*\*')"; C3="$(lineof "$DD" '^3\. \*\*new\*\*')"
in_order "$C1" "$C2" "$C3" && ok "three candidates, \"already in the repo\" first" || no "candidate order ($C1 $C2 $C3)"
has "$DD" 'never skip the first' && ok "the first candidate is never skipped" || no "never-skip-the-first clause"
AX="$(block "$DD" '^## Axes' '^## [^A]')"
bhas "$AX" 'five fixed axes, each `yes | partial | no`, with no weights' && ok "five fixed axes, yes | partial | no, no weights" || no "axes rating clause"
for a in '**fits the CLAUDE.md stack**' '**already in the lockfile or manifest**' '**blast radius**' '**test cost**' '**reversibility / lock-in**'; do
  bhas "$AX" "- $a" && ok "axis $a" || no "axis $a missing"
done
[ "$(printf '%s\n' "$AX" | grep -c '^- \*\*')" = 5 ] && ok "exactly five axes" || no "axes are not exactly five"
EV="$(block "$DD" '^## Evidence sources' '^## [^E]')"
bhas "$EV" 'Use only these three' && ok "three evidence sources" || no "three-sources clause"
bhas "$EV" '1. **the repo**' && ok "source 1: the repo" || no "source 1: the repo"
bhas "$EV" '2. **Context7**' && bhas "$EV" "within \`skills/context7-lookup/SKILL.md\`'s per-lookup token budget" \
  && ok "source 2: Context7 within context7-lookup's budget" || no "source 2: Context7 budget clause"
bhas "$EV" '3. **`WebSearch`** — only under `--discovery`' && ok "source 3: WebSearch only under --discovery" || no "WebSearch is not discovery-only"
has "$DD" 'status: confirmed | unconfirmed' && ok "status: confirmed | unconfirmed" || no "status values"
ASK="$(block "$DD" '^## The `LP-APPROACH` ask' '^## [^T]')"
bhas "$ASK" 'header: "LP-APPROACH"' && ok "the LP-APPROACH header" || no "LP-APPROACH header"
bhas "$ASK" '`Keep <chosen>` · `Switch to <runner-up>` · `Decide later`' && ok "the three LP-APPROACH options" || no "LP-APPROACH options"
bhas "$ASK" 'Asked only on an axes tie or a T1 dependency' && ok "asked only on an axes tie or a T1 dependency" || no "ask condition"
bhas "$ASK" "**Can't-ask branch**" && bhas "$ASK" 'record the default pick with `status: unconfirmed`. Never ask, and never abort' \
  && ok "Can't-ask branch: default pick, status: unconfirmed, never ask, never abort" || no "Can't-ask branch"
has "$DD" "a worker's \`plan:\` deviation is the worker's channel for \"I found a better way\", read by the Phase 4.5 review lens" \
  && ok "the worker plan: deviation sentence" || no "the worker plan: deviation sentence"

echo "AC3 — Launch Pad Phase 2.7 (agents/launch-pad.md)"
P25="$(lineof "$LP" '^### Phase 2\.5: FEASIBILITY')"; P27="$(lineof "$LP" '^### Phase 2\.7: APPROACH')"; P3="$(lineof "$LP" '^### Phase 3: ANALYZE')"
in_order "$P25" "$P27" "$P3" && ok "### Phase 2.7: APPROACH between Phase 2.5 and Phase 3" || no "Phase 2.7 position ($P25 $P27 $P3)"
PH="$(block "$LP" '^### Phase 2\.7: APPROACH' '^### Phase [^2]|^### Phase 2\.[^7]')"
bhas "$PH" "A trigger → \`Read($DD_RUNTIME)\`" \
  && ok "trigger-gated Read( of design-decisions.md through the install root" || no "trigger-gated Read( of design-decisions.md through the install root"
bhas "$PH" 'No trigger → print `## Phase 2.7: APPROACH — no trigger`, read nothing' && ok "the no-trigger literal" || no "the no-trigger literal"
bhas "$PH" 'header: "LP-APPROACH"' && bhas "$PH" '`Keep <chosen>` · `Switch to <runner-up>` · `Decide later`' \
  && ok "LP-APPROACH ask with its three options" || no "LP-APPROACH ask in the phase block"
bhas "$PH" 'not a test, fixture, doc or evidence file' && bhas "$PH" 'ug fixes, docs, prompt-only edits and small changes never trigger' && ok "Phase 2.7 trigger list carries the T2 exclusion and the never-trigger rule" \
  || no "Phase 2.7 trigger list lacks the T2 exclusion or the never-trigger rule"
NLINES="$(awk '
  /^### Phase 2\.7: APPROACH/ {f = 1}
  f && /^### Phase / && !/^### Phase 2\.7: APPROACH/ {exit}
  !f {next}
  fence {if ($0 ~ /^```/) fence = 0; next}
  /^\*\*Output:\*\*/ {out = 1; next}
  out && /^```/ {fence = 1; out = 0; next}
  out && /^[[:space:]]*$/ {next}
  {out = 0; n++}
  END {print n + 0}' "$LP")"
[ "${NLINES:-99}" -gt 0 ] && [ "${NLINES:-99}" -le 25 ] && ok "phase block is $NLINES lines (≤ 25, **Output:** excluded)" \
  || no "phase block is ${NLINES:-?} lines (> 25 or empty)"
CLAUSE='Phase 2.7 `LP-APPROACH` → the default pick recorded `status: unconfirmed`, never asked, never aborted'
lp_rule() { grep -F -- "- **Can't-ask rule:**" "$1" | head -1; }
lp_a="$(lp_rule "$LP")"; lp_c="$(lp_rule "$LPC")"
bhas "$lp_a" "$CLAUSE" && ok "agent Can't-ask rule carries the Phase 2.7 clause" || no "agent Can't-ask rule lacks the Phase 2.7 clause"
NUM="$(grep -F '> **Phase-numbering convention**' "$LP" | head -1)"
bhas "$NUM" '**FEASIBILITY (2.5)**, **APPROACH (2.7)** and **PLAN REVIEW (5.5)**' && ok "Phase-numbering convention names 2.7 beside 2.5 and 5.5" \
  || no "Phase-numbering convention line"
has "$LP" '5a. When Phase 2.7 wrote ≥ 1 entry, emit `## Design decisions` right after `## Task`' && ok "Phase 5 action 5a emits the section" \
  || no "Phase 5 action 5a"
[ "$(jq -r '.agents["launch-pad"].budget' "$BUDGETS" 2>/dev/null)" = 47557 ] && ok "launch-pad agent budget unchanged at 47557" \
  || no "launch-pad agent budget is not 47557"
if [ -f "$REPO/scripts/check-token-budget.sh" ]; then
  bash "$REPO/scripts/check-token-budget.sh" > "$WORK/budget.out" 2>&1
  grep -qE '^launch-pad +[0-9]+ +47557 +OK ' "$WORK/budget.out" && ok "check-token-budget.sh: launch-pad agent row OK at 47557" \
    || no "check-token-budget.sh: launch-pad agent row is not OK at 47557"
else
  skip "scripts/check-token-budget.sh absent (plugin-only copy); the budget row is checked by CI"
fi

echo "AC4 — the command mirror (commands/launch-pad.md)"
has "$LPC" 'the FEASIBILITY 2.5, APPROACH 2.7 and PLAN REVIEW 5.5 sub-phases do not change the count' \
  && ok "workflow sentence names 2.7 beside 2.5 and 5.5" || no "workflow sentence"
C25="$(lineof "$LPC" '^### Phase 2\.5: FEASIBILITY')"; C27="$(lineof "$LPC" '^### Phase 2\.7: APPROACH')"; C3="$(lineof "$LPC" '^### Phase 3: ANALYZE')"
in_order "$C25" "$C27" "$C3" && ok "### Phase 2.7: APPROACH after the Phase 2.5 block" || no "command Phase 2.7 position ($C25 $C27 $C3)"
CPH="$(block "$LPC" '^### Phase 2\.7: APPROACH' '^### Phase 3')"
bhas "$CPH" '## Phase 2.7: APPROACH — no trigger' && bhas "$CPH" 'LP-APPROACH' && bhas "$CPH" 'status: unconfirmed' \
  && bhas "$CPH" '`Keep <chosen>` · `Switch to <runner-up>` · `Decide later`' && ok "command Phase 2.7 block: no-trigger, ask, can't-ask" \
  || no "command Phase 2.7 block content"
bhas "$CPH" "\`$DD_RUNTIME\`" && bhas "$CPH" 'not a test, fixture, doc or evidence file' && bhas "$CPH" 'ug fixes, docs, prompt-only edits and small changes never trigger' \
  && ok "command Phase 2.7 block: install-root path, T2 exclusion, never-trigger rule" || no "command Phase 2.7 block path or exclusions"
[ -n "$lp_a" ] && [ "$lp_a" = "$lp_c" ] && ok "Can't-ask rule bullets byte-identical (agent = command)" || no "Can't-ask rule bullets differ"
bhas "$lp_c" "$CLAUSE" && ok "command Can't-ask rule carries the Phase 2.7 clause" || no "command Can't-ask rule lacks the Phase 2.7 clause"
grep -F '2. Fill all 9 sections' "$LPC" | grep -qF 'optional Design decisions section from Phase 2.7' \
  && ok "Phase 5 step 2 names Design decisions" || no "Phase 5 step 2"
S55="$(block "$LPC" '^### Phase 5\.5' '^### Phase 6')"
bhas "$S55" 'Criteria 11, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, and 23 are conditional' && ok "Phase 5.5 step 2 conditional list ends at 23" \
  || no "Phase 5.5 step 2 conditional list"
bhas "$S55" 'Criterion 23 runs only when the brief carries a trigger' && ok "Phase 5.5 step 2 Criterion 23 gate clause" || no "Criterion 23 gate clause"
C23C="$(printf '%s\n' "$S55" | grep -oE 'Criterion 23 runs only when the brief carries a trigger \([^)]*\)' | head -1)"
bhas "$C23C" 'not a test, fixture, doc or evidence file' && bhas "$C23C" 'ug fixes, docs, prompt-only edits and small changes never trigger' && ok "Phase 5.5 Criterion 23 clause carries the T2 exclusion and the never-trigger rule" \
  || no "Phase 5.5 Criterion 23 clause lacks the T2 exclusion or the never-trigger rule"
bhas "$S55" 'checks every review criterion' && ok "count-free 'checks every review criterion' kept" || no "'checks every review criterion' lost"

echo "AC5 — the gate catalog"
CAT="$(bash "$POL" catalog 2>/dev/null | awk -F'\t' '$1 == "LP-APPROACH"')"
[ "$(printf '%s\n' "$CAT" | awk -F'\t' '{print $2}')" = human-only ] && ok "lane-policy.sh catalog: LP-APPROACH is human-only" \
  || no "lane-policy.sh catalog: LP-APPROACH is not human-only (${CAT:-no row})"
[ "$(printf '%s\n' "$CAT" | awk -F'\t' '{print $3}')" = 'Keep <chosen>|Switch to <runner-up>|Decide later' ] \
  && ok "catalog labels Keep <chosen>|Switch to <runner-up>|Decide later" || no "catalog labels"
has "$GATES" '| `LP-APPROACH` | human-only | `Keep <chosen>` · `Switch to <runner-up>` · `Decide later` |' \
  && ok "LANE_GATES.md carries the regenerated LP-APPROACH row" || no "LANE_GATES.md LP-APPROACH row"
INV="$(block "$ARCH" '^## Question-gate inventory' '^## Failure Escalation Summary' | grep -F '`LP-APPROACH`' | head -1)"
LAST="$(printf '%s\n' "$INV" | awk -F'|' '{print $(NF-1)}')"
bhas "$LAST" 'status: unconfirmed' && bhas "$LAST" 'never asked, never aborted' && ! bhas "$LAST" 'undefined' \
  && ok "Question-gate inventory: LP-APPROACH can't-ask cell" || no "Question-gate inventory LP-APPROACH row"

echo "AC6 — Plan Reviewer Criterion 23 (agents/plan-reviewer.md)"
Q22="$(lineof "$PR" '^### 22\. ')"; Q23="$(lineof "$PR" '^### 23\. Approach justification \(conditional\)$')"; DM="$(lineof "$PR" '^## Decision Matrix')"
in_order "$Q22" "$Q23" "$DM" && ok "### 23. Approach justification (conditional) after Criterion 22" || no "Criterion 23 position ($Q22 $Q23 $DM)"
C23="$(block "$PR" '^### 23\. Approach justification' '^---$|^## ')"
for s in '**23a' '**23b' '**23c' '**23d' '`approach_unjustified`' '`approach_reinvents`' 'The reviewer verifies claims; it never re-decides.'; do
  bhas "$C23" "$s" && ok "Criterion 23 names $s" || no "Criterion 23 lacks $s"
done
bhas "$C23" 'T1, a `## Feasibility` CAUTION row naming a new dependency' && bhas "$C23" 'T2, a File Impact Map CREATE row that is a script or module' \
  && ok "Criterion 23 gate: T1 CAUTION row, T2 CREATE script/module" || no "Criterion 23 gate text"
GATE23="$(printf '%s\n' "$C23" | grep -F -- '- **Conditional gate:**' | head -1)"
bhas "$GATE23" 'not a test, fixture, doc or evidence file' && bhas "$GATE23" 'Bug fixes, docs, prompt-only edits and small changes never trigger' && ok "Criterion 23 gate carries Launch Pad's T2 exclusion and the never-trigger rule" \
  || no "Criterion 23 gate lacks the T2 exclusion or the never-trigger rule"
C23C_LINE="$(printf '%s\n' "$C23" | grep -F -- '- **23c' | head -1)"
bhas "$C23C_LINE" 'an installed stackpack skills index' && bhas "$C23C_LINE" 'skip that source when it is absent' \
  && ! bhas "$C23C_LINE" 'stackpack/skills/' && ok "23c names the installed stackpack index, skipped when absent, no cwd-relative path" \
  || no "23c search sources name a cwd-relative stackpack path or lack the skip-when-absent rule"
bhas "$C23" "\`$DD_RUNTIME\`" && ok "Criterion 23 reads the split file through the install root" \
  || no "Criterion 23 does not read the split file through the install root"
[ "$(grep -cF '(23c)' "$PR")" = 1 ] && grep -F '(23c)' "$PR" | grep -qE '^\| .*\| \*\*FAIL\*\* \(HIGH `approach_reinvents` issue\) \|$' \
  && ok "Decision Matrix: the one (23c) line is the FAIL HIGH approach_reinvents row" || no "Decision Matrix (23c) FAIL row"
grep -F '(23d)' "$PR" | grep -F 'status: unconfirmed' | grep -F 'no BLOCKING/HIGH issue exists' | grep -qF '| **NEEDS_HUMAN**' \
  && ok "Decision Matrix: 23d T1 unconfirmed ⇒ NEEDS_HUMAN row" || no "Decision Matrix (23d) NEEDS_HUMAN row"
has "$PR" '## 23 Review Criteria' && lacks "$PR" '## 22 Review Criteria' && ok "## 23 Review Criteria (no ## 22)" || no "criteria heading count"
has "$PR" 'All 23 review criteria must be checked' && ok "never-skip line says 23" || no "never-skip line"
has "$PR" '(23 total, Criteria 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, and 23 conditional)' && ok "Decision Matrix PASS row says 23" || no "PASS row count"
has "$PR" '- [ ] All 23 criteria checked' && ok "Quality Checklist says 23" || no "Quality Checklist count"
grep -F 'category: "{dep_graph' "$PR" | grep -F '| approach_unjustified | approach_reinvents | ...}' | grep -qF '(12–23)' \
  && ok "output-format category enum names both categories, range (12–23)" || no "output-format category enum"

echo "AC7 — fixture briefs and expected shapes (fixtures/design-decisions/)"
expect() {  # expect <letter> <brief> <severity> <category> <decision>
  local j="$FIX/expected-$1.json" got
  [ -s "$FIX/$2" ] && ok "fixture $2 exists" || no "fixture $2 missing"
  if ! jq -e . "$j" >/dev/null 2>&1; then no "expected-$1.json does not parse"; return; fi
  got="$(jq -r '[.fixture, .severity, .category, .decision] | join(" ")' "$j")"
  [ "$got" = "$2 $3 $4 $5" ] && ok "expected-$1.json: $3 $4, decision $5" || no "expected-$1.json is '$got', want '$2 $3 $4 $5'"
}
expect a brief-a-t1-no-section.md   MEDIUM approach_unjustified PASS
expect b brief-b-t1-no-rejected.md  MEDIUM approach_unjustified PASS
expect c brief-c-reinvention.md     HIGH   approach_reinvents   FAIL
expect d brief-d-t1-unconfirmed.md  MEDIUM approach_unjustified NEEDS_HUMAN
BA="$FIX/brief-a-t1-no-section.md"; BB="$FIX/brief-b-t1-no-rejected.md"; BC="$FIX/brief-c-reinvention.md"; BD="$FIX/brief-d-t1-unconfirmed.md"
REPOPKG="$FIX/repo/package.json"
t1_row() { block "$1" '^## Feasibility$' '^## [^F]' | grep -E '^\| [0-9] \| [^|]+ \| CAUTION \|' | grep -F 'New dependency `express-rate-limit`'; }
dd_sec() { block "$1" '^## Design decisions$' '^## [^D]'; }
for b in "$BA" "$BB" "$BD"; do
  [ -n "$(t1_row "$b")" ] && ok "$(basename "$b"): T1 trigger — a ## Feasibility CAUTION row naming a new dependency" \
    || no "$(basename "$b"): no T1 CAUTION row"
done
jq -e '.dependencies["express-rate-limit"] == null' "$REPOPKG" >/dev/null 2>&1 && ok "repo/package.json lacks express-rate-limit (a new dependency)" \
  || no "repo/package.json already declares express-rate-limit"
lacks "$BA" '## Design decisions' && ok "brief a: no ## Design decisions section (23a)" || no "brief a carries a Design decisions section"
SB="$(dd_sec "$BB")"
bhas "$SB" '- decision:' && bhas "$SB" 'chosen: `express-rate-limit`' && ! bhas "$SB" 'rejected:' \
  && ok "brief b: T1 entry, chosen absent from the manifest, no rejected: (23b)" || no "brief b entry shape"
SD="$(dd_sec "$BD")"
bhas "$SD" 'status: unconfirmed' && bhas "$SD" 'rejected:' && ok "brief d: T1 entry with rejected: and status: unconfirmed (23d)" || no "brief d entry shape"
grep -E '^\| [^|]+ \| [^|]+ \| [^|]*`scripts/slugify\.sh`' "$BC" | grep -q . \
  && ok "brief c: T2 trigger — a File Impact Map CREATE scripts/slugify.sh" || no "brief c: no CREATE scripts/slugify.sh row"
grep -qE '^pc_slugify\(\) *\{' "$FIX/repo/scripts/propose-common.sh" && ok "repo/scripts/propose-common.sh defines pc_slugify" \
  || no "repo/scripts/propose-common.sh does not define pc_slugify"
[ -n "$(dd_sec "$BC")" ] && lacks "$BC" 'pc_slugify' && lacks "$BC" 'propose-common' \
  && ok "brief c: its entry is silent on pc_slugify / propose-common.sh (23c)" || no "brief c names the existing helper"
lacks "$BC" 'CAUTION' && ok "brief c carries no T1 row (the reinvention is its only trigger)" || no "brief c carries a CAUTION row"
for b in "$BA" "$BB" "$BC" "$BD"; do
  hint=0; for h in approach_unjustified approach_reinvents 'Criterion 23' NEEDS_HUMAN 'expected-' '23a' '23b' '23c' '23d'; do
    has "$b" "$h" && hint=1
  done
  [ "$hint" -eq 0 ] && ok "$(basename "$b"): no answer-key hint in the brief" || no "$(basename "$b") leaks an answer-key hint"
done
has "${BASH_SOURCE[0]}" 'The LLM verdict itself is not unit-tested' && ok "test header states the LLM verdict is not unit-tested" \
  || no "test header statement"

echo "AC8 — Red Team vector 1 (agents/red-team-reviewer.md)"
V1="$(block "$RT" '^### 1\. Core Flaws & Blind Spots' '^### 2\. ')"
bhas "$V1" '- Does this reinvent a mechanism the platform, SDK, harness or an existing module already provides?' \
  && ok "vector 1 carries the reinvention bullet" || no "vector 1 reinvention bullet"
has "$RT" 'You MUST examine all 6 attack vectors.' && ok "'You MUST examine all 6 attack vectors.' unchanged" || no "attack-vector count line"

echo "AC9 — the worker is unchanged (agents/worker.md)"
S57="$(block "$WK" '^### Step 5\.7: Optional — record deviations from plan$' '^### Step 5\.75')"
bhas "$S57" '`plan:`' && ok "worker Step 5.7 carries the plan: deviation channel design-decisions.md cites" \
  || no "worker Step 5.7 (record deviations from plan) or its plan: prefix is gone"
scope_guard "loomwright/agents/worker.md" loomwright/agents/worker.md

echo "AC10 — no house rule written; the proposed /rules add line"
scope_guard ".agent/rules/*.json" ':(glob).agent/rules/*.json'
RULE_LINE="$(cat <<'EOF'
/rules add --category process --statement 'A brief that adds a new dependency carries a `## Design decisions` entry naming the chosen library, at least one rejected alternative and the evidence' --enforcement advisory --applies-to package.json --applies-to package-lock.json --applies-to requirements.txt --applies-to pyproject.toml --applies-to go.mod --applies-to Cargo.toml --applies-to pubspec.yaml
EOF
)"
if [ -s "$EVID" ]; then
  grep -qxF -- "$RULE_LINE" "$EVID" && ok "evidence file carries the /rules add line verbatim (advisory, seven manifests)" \
    || no "evidence file lacks the verbatim /rules add line"
  grep -F -- '/rules add ' "$EVID" | grep -qF -- '--check' && no "the /rules add line carries a --check" || ok "the /rules add line has no --check"
  has "$EVID" 'prove-rule-check.sh' && has "$EVID" 'leg 2' && ok "evidence file gives the advisory reason (prove-rule-check.sh leg 2)" \
    || no "evidence file lacks the advisory reason"
else
  no "docs/evidence/design-decisions.md missing"
fi

echo "AC11 — schema categories (docs/result-schemas/plan-review-result.md)"
grep -F 'category: string' "$SCHEMA" | grep -qF '"approach_unjustified" / "approach_reinvents" for Criterion 23' \
  && ok "schema category comment names both categories for Criterion 23" || no "schema category comment"
grep -F -- '- `category` is optional' "$SCHEMA" | grep -qF '`approach_unjustified` / `approach_reinvents` for Criterion 23' \
  && ok "schema category list names both categories for Criterion 23" || no "schema category list"
scope_guard "loomwright/scripts/validate-plan-review-result.py" loomwright/scripts/validate-plan-review-result.py

echo
echo "test-design-decisions.sh: $pass passed, $fail failed, $skips skipped"
[ "$fail" -eq 0 ]
