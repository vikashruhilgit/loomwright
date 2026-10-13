#!/usr/bin/env bash
# test-pr-body-evidence-seam.sh — static seam test for #511: acceptance criteria may not put their only
# evidence in the PR body.
#
# FINALIZE writes the PR body from a fixed template before Phase 4.5, nothing in the plugin edits it
# afterwards, and Phase 4.5 brief conformance judges each criterion from the diff. A criterion only the
# body can satisfy (PR #459: "the PR body pastes the exact command for every number") therefore FAILs
# every heal round until a human edits the body (#411, #462, #463, #471). The fix moves the evidence into
# a committed file the diff carries and a fix task can write:
#   - Plan Reviewer Criterion 20 FAILs (HIGH `pr_body_evidence`) a criterion whose only evidence is the
#     PR body, with the evidence-file rewrite as its suggestion; Launch Pad's FAIL refine loop applies it.
#   - Launch Pad Phase 2 action 3, the supervisor-readiness template and user-story-writing author the
#     evidence-file form up front; the template's rubric example no longer grades the PR description.
#   - code-reviewer step 5a / the Phase 4.5 BRIEF-CONFORMANCE line judge a committed-file criterion on
#     that file in the diff, and never judge a PR-body clause (PR-body-only => cannot_determine).
#   - FINALIZE's PR body lists the branch's `docs/evidence/` files in an optional `## Evidence` section.
#
# Plan Reviewer and the code reviewer are LLM prompts, so CI pins their TEXT, ORDER and OUTCOME words;
# the behavioural proof is a live Plan Reviewer probe on fixtures/pr-body-evidence/ (answer key: its
# README.md). This test pins:
#   PART 1  Plan Reviewer Criterion 20: it is the LAST criterion (after 19, before the Decision Matrix),
#           its gate, 20a, the not-a-finding clause, category, HIGH, the rewrite in its suggestion; the
#           Decision Matrix row (inside the matrix, decision FAIL); the count at every count surface;
#           the output-format enum; the schema doc; the Criterion 1 / 16 docs/evidence exemptions.
#   PART 2  Launch Pad: Phase 2 action 3 (inside Phase 2's actions), the FAIL (attempt < 3) bullet's
#           rewrite-never-delete clause, the spawn's count; the command mirror of all three.
#   PART 3  authoring surfaces: the template's Evidence rule sits under `## Acceptance Criteria`, the
#           rubric example grades the diff, the quality checklist line, user-story-writing's item rule
#           (with the `## Validation` distinction), and no authoring surface asks for PR-body evidence.
#   PART 4  review side: code-reviewer 5a's evidence bullet (inside 5a, outcomes for both locations),
#           the Phase 4.5 prompt line and the preloaded checklist say the same, and FINALIZE's template
#           carries `## Evidence` between Test Plan and Not verified with its omit rule.
#   PART 5  .gitignore: a `docs/evidence/*.md` file is NOT ignored, a `docs/evidence/*.log` one IS
#           (why the rule says Markdown, never *.log) — `git check-ignore` with global excludes off.
#   PART 6  fixtures: present, blind, one shared title, and the expected Criterion 20 result of each
#           decided MECHANICALLY here (a detector with its own positive/negative self-check) and
#           matched against the README rows.
#   PART 7  mutation control: delete Criterion 20, move it after the Decision Matrix, reword its HIGH to
#           MEDIUM, delete the matrix row, delete Launch Pad's action-3 clause, delete code-reviewer's
#           evidence bullet — each in a TEMP copy, each must make this test fail. Each mutant is gated on
#           non-empty + differs-from-original, after a positive control (unmutated copies pass).
#
# EXPLICIT LIMIT: this pins wiring and fixture shape. It cannot prove that a reviewer flags a brief or
# that a fix task writes the evidence file — model behaviour, proven only by a live probe.
#
# Env overrides (PART 7's re-invocation only): SEAM_LP (agents/launch-pad.md), SEAM_PR
# (agents/plan-reviewer.md), SEAM_CR (agents/code-reviewer.md), SEAM_NO_MUTATION=1 (skip PART 7).
# bash 3.2 / BSD userland safe; paths from $BASH_SOURCE so it runs from any CWD.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/.." && pwd)"
LP="${SEAM_LP:-$PLUGIN/agents/launch-pad.md}"
PR="${SEAM_PR:-$PLUGIN/agents/plan-reviewer.md}"
CR="${SEAM_CR:-$PLUGIN/agents/code-reviewer.md}"
LPC="$PLUGIN/commands/launch-pad.md"
SKILL="$PLUGIN/skills/supervisor-readiness/SKILL.md"
USW="$PLUGIN/skills/user-story-writing/SKILL.md"
QC="$PLUGIN/skills/quality-checklist/SKILL.md"
SHA="$PLUGIN/skills/self-heal-advisory/SKILL.md"
AO="$PLUGIN/skills/async-orchestration/SKILL.md"
SCHEMA="$PLUGIN/docs/result-schemas/plan-review-result.md"
FIX="$HERE/fixtures/pr-body-evidence"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }
has()   { grep -qF -- "$2" "$1"; }                     # has <file> <literal>
lacks() { ! grep -qF -- "$2" "$1"; }
# block <file> <start-ERE> <stop-ERE> — lines from the first start match up to (not incl.) stop.
block() { BLK_A="$2" BLK_B="$3" awk 'f && $0 ~ ENVIRON["BLK_B"] {exit} $0 ~ ENVIRON["BLK_A"] {f=1} f' "$1"; }
bhas() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }   # bhas <text> <literal>
# lineno <file> <ERE> — first matching line number, empty when none.
lineno() { LN_RE="$2" awk '$0 ~ ENVIRON["LN_RE"] {print NR; exit}' "$1"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

for f in "$LP" "$PR" "$CR" "$LPC" "$SKILL" "$USW" "$QC" "$SHA" "$AO" "$SCHEMA"; do
  [ -s "$f" ] || no "missing or empty: $f"
done

echo "PART 1 — Plan Reviewer Criterion 20"
C20="$(block "$PR" '^### 20\. Acceptance Evidence Location' '^## Decision Matrix')"
[ -n "$C20" ] && ok "### 20. Acceptance Evidence Location present" || no "Criterion 20 block not found"
L19="$(lineno "$PR" '^### 19\. ')"; L20="$(lineno "$PR" '^### 20\. ')"; LDM="$(lineno "$PR" '^## Decision Matrix')"
[ -n "$L19" ] && [ -n "$L20" ] && [ -n "$LDM" ] && [ "$L19" -lt "$L20" ] && [ "$L20" -lt "$LDM" ] \
  && ok "Criterion 20 sits after Criterion 19 and before the Decision Matrix" \
  || no "Criterion 20 position (19=$L19 20=$L20 matrix=$LDM)"
[ -z "$(lineno "$PR" '^### 21\. ')" ] && ok "Criterion 20 is the last criterion" || no "a Criterion 21 exists"
bhas "$C20" 'None names the PR body, PR description or pull-request description as the place its result is recorded, pasted, listed or shown → skip silently.' \
  && ok "20: conditional gate + skip clause" || no "20 gate/skip clause"
bhas "$C20" '**20a — PR-body-only evidence.** A criterion whose only stated evidence location is the PR body' \
  && ok "20a: PR-body-only evidence" || no "20a condition"
bhas "$C20" 'One issue per criterion, quoting it verbatim.' && ok "20a: one issue per criterion, verbatim" || no "20a multiplicity"
bhas "$C20" '**Not a finding:** a criterion whose evidence is a committed file and which also asks the PR body to link to it' \
  && ok "20: committed-file + link is not a finding" || no "20 not-a-finding clause"
bhas "$C20" '**Issue category:** `pr_body_evidence`.' && ok "20: category" || no "20 category"
bhas "$C20" '**Severity if failed:** HIGH (the decision is FAIL).' && ok "20: HIGH => FAIL" || no "20 severity"
bhas "$C20" 'a committed evidence file `docs/evidence/<slug>.md` (Markdown, never `*.log`' \
  && bhas "$C20" 'and the PR body links to it' && bhas "$C20" "to that subtask's \`lanes:\`" \
  && ok "20: suggestion = evidence-file rewrite (+ File Impact Map + lanes)" || no "20 suggestion rewrite"
bhas "$C20" 'HIGH, not NEEDS_HUMAN:' && bhas "$C20" 'NEEDS_HUMAN aborts a non-interactive run' && bhas "$C20" 'Not MEDIUM:' \
  && ok "20: severity choice justified" || no "20 severity justification"
DM="$(block "$PR" '^## Decision Matrix' '^## Output Format')"
ROW="$(printf '%s\n' "$DM" | grep -F -- '| Criterion 20 finds' | head -n1)"
[ -n "$ROW" ] && ok "Decision Matrix carries a Criterion 20 row" || no "Decision Matrix row missing"
DEC="$(printf '%s\n' "$ROW" | awk -F'|' '{print $3}')"
bhas "$DEC" '**FAIL**' && bhas "$DEC" '`pr_body_evidence`' && ! bhas "$DEC" 'NEEDS_HUMAN' \
  && ok "matrix row decides FAIL (pr_body_evidence)" || no "matrix row decision: '$DEC'"
has "$PR" '## 20 Review Criteria' && lacks "$PR" '## 19 Review Criteria' && has "$PR" 'All 20 review criteria must be checked' \
  && has "$PR" '(20 total, Criteria 11, 12, 13, 14, 15, 16, 17, 18, 19, and 20 conditional)' && has "$PR" '- [ ] All 20 criteria checked' \
  && ok "criteria count 20 at heading / never-skip / matrix / checklist" || no "criteria count surfaces"
has "$PR" 'Criteria 11, 13, 14, 15, 16, 17, 18, 19, and 20 are conditional' && ok "never-skip rule lists 20 as conditional" \
  || no "never-skip conditional list"
has "$PR" 'Criterion 20 is conditional: skip silently when no acceptance criterion names the PR body as its evidence.' \
  && ok "intro paragraph names Criterion 20's gate" || no "intro paragraph gate"
CHK="$(grep -F -- '- [ ] All 20 criteria checked' "$PR")"
bhas "$CHK" 'Criterion 20 skipped silently when no acceptance criterion names the PR body as its evidence' \
  && bhas "$CHK" 'HIGH `pr_body_evidence` finding (20a)' && ok "quality checklist names Criterion 20" || no "checklist Criterion 20"
has "$PR" '| pin_mutations | pr_body_evidence | ...}"  # optional — emit when a criterion mandates it (12–20)' \
  && ok "output-format enum lists pr_body_evidence" || no "output-format category enum"
has "$SCHEMA" '"pr_body_evidence" for Criterion 20 findings' && has "$SCHEMA" '`pr_body_evidence` for Criterion 20 (' \
  && ok "schema doc: category in both lists" || no "schema doc category"
C1="$(block "$PR" '^### 1\. File Path Verification' '^### 2\. ')"
bhas "$C1" "a new \`docs/evidence/\` parent is expected — Criterion 20's evidence file creates it; not a finding" \
  && ok "Criterion 1: docs/evidence parent exempt" || no "Criterion 1 exemption"
C16="$(block "$PR" '^### 16\. Lane Declaration' '^### 17\. ')"
bhas "$C16" "except a \`docs/evidence/\` path (Criterion 20's evidence file creates the directory)" \
  && ok "Criterion 16: docs/evidence lane exempt" || no "Criterion 16 exemption"

echo "PART 2 — Launch Pad + command mirror"
P2="$(block "$LP" '^### Phase 2: DISCOVER' '^\*\*Output:\*\*')"
A3="$(printf '%s\n' "$P2" | grep -E '^3\. Write/refine criteria' | head -n1)"
[ -n "$A3" ] && ok "launch-pad: Phase 2 action 3 found inside Phase 2's actions" || no "launch-pad: Phase 2 action 3 missing"
bhas "$A3" 'A criterion whose evidence would live in the PR body — one carried forward at step 0 included — is written in the evidence-file form instead' \
  && bhas "$A3" 'joins the Phase 3 File Impact Map as a create' && bhas "$A3" 'Plan Reviewer Criterion 20 FAILs it otherwise' \
  && ok "action 3: evidence-file form, carried-forward criteria, File Impact Map, Criterion 20" || no "action 3 clause"
P55="$(block "$LP" '^### Phase 5\.5: PLAN REVIEW' '^\*\*Retry loop:\*\*')"
FB="$(printf '%s\n' "$P55" | grep -F -- '- **FAIL (attempt < 3):**' | head -n1)"
bhas "$FB" 'A Criterion 20 `pr_body_evidence` issue is fixed by rewriting that criterion in the evidence-file form its suggestion gives' \
  && bhas "$FB" 'never by deleting the criterion' && ok "FAIL (attempt < 3): rewrite, never delete" || no "FAIL bullet Criterion 20 clause"
SPAWN="$(block "$LP" '^\*\*Spawn contract:\*\*' '^\*\*Output:\*\*')"
bhas "$SPAWN" 'Check all 20 review criteria.' && ok "spawn: Check all 20" || no "spawn criteria count"
lacks "$LP" 'Check all 19 review criteria' && ok "launch-pad: no stale 'Check all 19'" || no "stale 'Check all 19' in launch-pad"
LPC2="$(block "$LPC" '^### Phase 2: DISCOVER' '^### Phase 2\.5')"
bhas "$LPC2" 'a criterion whose evidence would live in the PR body (a carried-forward one included) is written in the evidence-file form instead' \
  && ok "command mirror: Phase 2 step 3" || no "command mirror Phase 2 step 3"
has "$LPC" 'checks all 20 criteria' && lacks "$LPC" 'checks all 19 criteria' && ok "command mirror: all 20 criteria" || no "command mirror count"
has "$LPC" 'Criterion 20 runs only when an acceptance criterion names the PR body as its evidence, and FAILs it' \
  && ok "command mirror: Criterion 20 gate" || no "command mirror Criterion 20 gate"
has "$LPC" 'FAIL (attempt < 3) → fix issues (a Criterion 20 PR-body criterion is rewritten to the evidence-file form, never deleted)' \
  && ok "command mirror: FAIL rewrite-never-delete" || no "command mirror FAIL clause"

echo "PART 3 — authoring surfaces"
ACT="$(block "$SKILL" '^## Acceptance Criteria$' '^## Outcomes Rubric \(optional')"
bhas "$ACT" '**Evidence rule (Launch Pad Phase 2 action 3; Plan Reviewer Criterion 20):**' \
  && bhas "$ACT" 'then a committed evidence file `docs/evidence/<slug>.md` contains' && bhas "$ACT" 'never `*.log`' \
  && ok "template: Evidence rule under ## Acceptance Criteria" || no "template Evidence rule"
bhas "$ACT" "\`## Evidence\` section" && ok "template: points at FINALIZE's ## Evidence section" || no "template ## Evidence pointer"
lacks "$SKILL" 'The PR description does not mention' && has "$SKILL" '- No line the diff adds contains `TODO`, `FIXME`, or `deferred`.' \
  && ok "template: rubric example grades the diff, not the PR description" || no "rubric example still grades the PR description"
has "$SKILL" "- [ ] No acceptance criterion's only evidence is the PR body" && ok "template quality checklist line" || no "template checklist"
IR="$(block "$USW" '^### Item rules' '^### Plan-doc template')"
bhas "$IR" '**Evidence lives in a committed file, never the PR body.**' && bhas "$IR" '`docs/evidence/<slug>.md` contains' \
  && ok "user-story-writing: item rule" || no "user-story-writing item rule"
bhas "$IR" '`## Validation (must pass before merge)` running-system steps are different' \
  && ok "user-story-writing: keeps the validation-gate distinction" || no "user-story-writing Validation distinction"
# No authoring surface may ask for PR-body evidence: every line naming the PR body / description must be
# one of the rule's own lines (it names docs/evidence/, the evidence-file form, or Criterion 20).
for f in agents/launch-pad.md agents/product-owner.md agents/orchestrator.md commands/launch-pad.md \
         commands/product-owner.md commands/orchestrator.md skills/supervisor-readiness/SKILL.md \
         skills/user-story-writing/SKILL.md skills/product-discovery/SKILL.md skills/mvp-scoping/SKILL.md; do
  [ -f "$PLUGIN/$f" ] || { no "authoring surface missing: $f"; continue; }
  bad="$(grep -niE 'PR body|PR description|pull[- ]request (body|description)' "$PLUGIN/$f" \
    | grep -viE 'docs/evidence|evidence-file form|Criterion 20|Evidence rule|all 20 criteria' || true)"
  [ -z "$bad" ] && ok "authoring surface asks for no PR-body evidence: $f" || no "$f names the PR body outside the rule: $bad"
done

echo "PART 4 — review side (the AC is checked against the committed file)"
S5A="$(block "$CR" '^5a\. \*\*Brief conformance' '^5b\. ')"
EB="$(printf '%s\n' "$S5A" | grep -F -- '- **Where the evidence lives:**' | head -n1)"
[ -n "$EB" ] && ok "code-reviewer: evidence bullet inside step 5a" || no "code-reviewer 5a evidence bullet missing"
bhas "$EB" 'is judged on that file in the diff — absent, or lacking what the criterion says it contains ⇒ `not_addressed`, `file:` that path' \
  && ok "5a: committed-file criterion => not_addressed on that file when missing" || no "5a committed-file outcome"
bhas "$EB" 'a criterion whose ONLY evidence is the PR body is `cannot_determine`, never a finding' \
  && bhas "$EB" 'never judge a clause about it' && ok "5a: PR-body clause never judged; PR-body-only => cannot_determine" \
  || no "5a PR-body outcome"
LINE="$(grep -F -- '**BRIEF-CONFORMANCE ADVISORY (include this line ONLY' "$SHA" | head -n1)"
bhas "$LINE" 'is judged on that file in the diff (absent or incomplete ⇒ `not_addressed`, `file:` that path)' \
  && bhas "$LINE" 'a criterion whose ONLY evidence is the PR body is `cannot_determine`' \
  && ok "Phase 4.5 prompt line: same two outcomes" || no "Phase 4.5 prompt line evidence clause"
has "$QC" 'or evidence only in the PR body, which no fix task can edit) ⇒ named in a one-line summary, not a finding; a criterion naming a committed evidence file is judged on that file.' \
  && ok "preloaded quality-checklist agrees" || no "quality-checklist brief-conformance item"
TPL="$(awk '/^\*\*PR Body Template:\*\*/{f=1} f{print; if (/^```$/ && c++) exit}' "$AO")"
ORDER="$(printf '%s\n' "$TPL" | grep -E '^## (Test Plan|Evidence|Not verified|Task)$' | tr '\n' '|')"
[ "$ORDER" = "## Test Plan|## Evidence|## Not verified|## Task|" ] && ok "FINALIZE template: ## Evidence between Test Plan and Not verified" \
  || no "FINALIZE template order: $ORDER"
EVR="$(grep -F -- '**`## Evidence` section (optional, #511):**' "$AO" | head -n1)"
bhas "$EVR" 'git diff --name-only --diff-filter=AM "origin/$BASE_BRANCH...HEAD" -- docs/evidence/' \
  && bhas "$EVR" '**OMITTED ENTIRELY**' && ok "FINALIZE ## Evidence: mechanical source + omit rule" || no "FINALIZE ## Evidence rule"

echo "PART 5 — .gitignore: evidence Markdown is committable, *.log is not"
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  GH="$WORK/home"; mkdir -p "$GH"
  ci() { HOME="$GH" XDG_CONFIG_HOME="$GH/.config" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
         git -C "$REPO" check-ignore -q --no-index -- "$1"; }
  ci "docs/evidence/zz-seam-probe.md"; rc=$?
  [ "$rc" -eq 1 ] && ok "docs/evidence/*.md is not ignored (check-ignore exit 1)" || no "docs/evidence/*.md: check-ignore exit $rc (0 = ignored)"
  ci "docs/evidence/zz-seam-probe.log"; rc=$?
  [ "$rc" -eq 0 ] && ok "docs/evidence/*.log IS ignored (why the rule says Markdown)" || no "docs/evidence/*.log: check-ignore exit $rc"
else
  no "repo root is not a git checkout — cannot run check-ignore"
fi

echo "PART 6 — fixtures"
for f in README.md brief-pr-body.md brief-pr-description.md brief-evidence-file.md; do
  [ -s "$FIX/$f" ] && ok "fixture present: $f" || no "fixture missing/empty: $f"
done
HINTS='expect|pr_body_evidence|criterion 20|20a|answer key|finding|verdict'
for b in pr-body pr-description evidence-file; do
  if grep -qiE -- "$HINTS" "$FIX/brief-$b.md"; then
    no "brief-$b.md leaks a hint (/$HINTS/i): $(grep -niE -- "$HINTS" "$FIX/brief-$b.md" | head -n1)"
  else
    ok "brief-$b.md carries no verdict/label hint"
  fi
done
T="$(grep -m1 '^# Supervisor Job:' "$FIX/brief-pr-body.md")"
[ -n "$T" ] && [ "$T" = "$(grep -m1 '^# Supervisor Job:' "$FIX/brief-pr-description.md")" ] \
  && [ "$T" = "$(grep -m1 '^# Supervisor Job:' "$FIX/brief-evidence-file.md")" ] \
  && ok "the three briefs share one title" || no "brief titles differ"
# detect <brief> — the AC ids whose only evidence is the PR body: a `## Acceptance Criteria` bullet naming
# the PR body/description that names no committed docs/evidence/ file. Mirrors Criterion 20's 20a.
detect() {
  block "$1" '^## Acceptance Criteria$' '^## [^A]' | grep -E '^- ' \
    | grep -iE 'PR body|PR description|pull[- ]request (body|description)' | grep -vF 'docs/evidence/' \
    | sed -n 's/.*\*\*\(AC[0-9][0-9]*\):\*\*.*/\1/p' | tr '\n' ' ' | sed 's/ $//'
}
printf '## Acceptance Criteria\n- [ ] **AC1:** then the PR body pastes X.\n- [ ] **AC2:** then `docs/evidence/a.md` contains X, and the PR body links to it.\n- [ ] **AC3:** then a PR against `main` is open.\n## Next\n' > "$WORK/det.md"
[ "$(detect "$WORK/det.md")" = "AC1" ] && ok "detector self-check: flags PR-body-only, passes evidence-file + PR-existence" \
  || no "detector self-check returned '$(detect "$WORK/det.md")'"
RM="$FIX/README.md"
row() { grep -F -- "| \`$1\` |" "$RM" 2>/dev/null; }
[ "$(detect "$FIX/brief-pr-body.md")" = "AC2" ] && bhas "$(row brief-pr-body.md)" '20a HIGH `pr_body_evidence` on AC2' \
  && ok "pr-body: AC2 fires, README agrees" || no "pr-body: detector '$(detect "$FIX/brief-pr-body.md")' / README row"
[ "$(detect "$FIX/brief-pr-description.md")" = "AC2" ] && bhas "$(row brief-pr-description.md)" '20a HIGH `pr_body_evidence` on AC2' \
  && ok "pr-description: AC2 fires, README agrees" || no "pr-description: detector '$(detect "$FIX/brief-pr-description.md")' / README row"
[ -z "$(detect "$FIX/brief-evidence-file.md")" ] && bhas "$(row brief-evidence-file.md)" 'none: AC2' \
  && ok "evidence-file: nothing fires, README agrees" || no "evidence-file: detector '$(detect "$FIX/brief-evidence-file.md")' / README row"
EFIM="$(block "$FIX/brief-evidence-file.md" '^### File Impact Map$' '^## Subtask Contracts$')"
ELN="$(block "$FIX/brief-evidence-file.md" '^lanes:$' '^external_requires:')"
bhas "$EFIM" '`docs/evidence/qa-prompt-sizes.md`' && bhas "$ELN" '"docs/evidence/qa-prompt-sizes.md"' \
  && ok "evidence-file: the file is a File Impact Map create and a lanes: entry" || no "evidence-file touch set"
for b in pr-body pr-description; do
  lacks "$FIX/brief-$b.md" 'docs/evidence/' && ok "brief-$b names no evidence file" || no "brief-$b names an evidence file"
done

if [ "${SEAM_NO_MUTATION:-0}" != "1" ]; then
  echo "PART 7 — mutation control"
  cp "$LP" "$WORK/lp.md"; cp "$PR" "$WORK/pr.md"; cp "$CR" "$WORK/cr.md"
  child() { SEAM_NO_MUTATION=1 SEAM_LP="$1" SEAM_PR="$2" SEAM_CR="$3" bash "$HERE/test-pr-body-evidence-seam.sh" >/dev/null 2>&1; }
  if child "$WORK/lp.md" "$WORK/pr.md" "$WORK/cr.md"; then ok "positive control: unmutated temp copies pass"
  else no "positive control failed — mutation results would be meaningless"; fi
  # pr20-m: Criterion 20 deleted.  prmove-m: Criterion 20 moved after the Decision Matrix (position).
  # prmed-m: its HIGH reworded to MEDIUM (outcome).  prrow-m: the matrix row deleted.
  awk 'f && /^---$/ {f=0} /^### 20\. / {f=1} !f' "$WORK/pr.md" > "$WORK/pr20-m.md"
  awk '/^### 20\. /{f=1} f && /^---$/ {f=0; next} f {held = held $0 "\n"; next} {print} /^## Decision Matrix/ {printf "%s", held}' \
    "$WORK/pr.md" > "$WORK/prmove-m.md"
  sed 's/^\*\*Severity if failed:\*\* HIGH (the decision is FAIL)\./**Severity if failed:** MEDIUM (the decision stays PASS)./' "$WORK/pr.md" > "$WORK/prmed-m.md"
  awk '!/^\| Criterion 20 finds/' "$WORK/pr.md" > "$WORK/prrow-m.md"
  sed 's/ A criterion whose evidence would live in the PR body — one carried forward at step 0 included — is written in the evidence-file form instead.*$//' \
    "$WORK/lp.md" > "$WORK/lp3-m.md"
  awk '!/^   - \*\*Where the evidence lives:\*\*/' "$WORK/cr.md" > "$WORK/cr5a-m.md"
  for m in pr20-m prmove-m prmed-m prrow-m lp3-m cr5a-m; do
    case "$m" in pr*) src=pr ;; lp*) src=lp ;; *) src=cr ;; esac
    if [ ! -s "$WORK/$m.md" ]; then no "mutant $m is empty"; continue; fi
    if cmp -s "$WORK/$m.md" "$WORK/$src.md"; then no "mutant $m is identical to its original"; continue; fi
    case "$src" in
      pr) child "$WORK/lp.md" "$WORK/$m.md" "$WORK/cr.md" ;;
      lp) child "$WORK/$m.md" "$WORK/pr.md" "$WORK/cr.md" ;;
      cr) child "$WORK/lp.md" "$WORK/pr.md" "$WORK/$m.md" ;;
    esac
    [ $? -ne 0 ] && ok "mutant $m is killed" || no "mutant $m survived"
  done
fi

echo
echo "test-pr-body-evidence-seam.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
