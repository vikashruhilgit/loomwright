# Supervisor Job: Stop the /pr-postmortem classifier producing flow_stage unknowable for phantom and low-confidence rounds

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-11-182243/L1
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/churn-ledger/02-classifier-unknowable-attribution.md
- **Base commit:** 0aa53c37ac59fe86a99bd590b36b379d24f9956b

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash + jq gather script and markdown skill/command/schema docs — the plugin's own stack |
| 2 | Dependency Availability | GO | jq, gh stub harness already used by `test-pr-postmortem-gather.sh` |
| 3 | Architecture Fit | GO | The gather owns `is_review_fix`; the skill owns per-round class / flow_stage attribution; the schema doc owns the trend-line contract |
| 4 | Scope vs Supervisor Capability | GO | 5 modified files + 1 created fragment, well under the Decomposition Threshold — single subtask |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** GO

## Task
**Goal:** Fix the two classifier causes behind the 18 `convention_mismatch` / `unknowable` ledger entries: the fix-commit regex counting a PR's own first (feature) commit as a review-fix round, and the skill's rule that sends a thin-evidence residual round to `flow_stage: unknowable` instead of attributing or omitting it.

**Problem Statement:**
The churn-ledger proposer (`propose-work.sh`) and the floor need `flow_stage` to name WHERE churn arose.
Currently, `pr-postmortem-gather.sh`'s `review_fix_re` contains a bare `self-heal` alternative, so a PR whose FIRST commit subject mentions self-heal (ledger line 3, PR #43 round 1: "counting artifact: initial feature commit subject contains self-heal, matching the fix-commit regex — not real churn") books a phantom review round; and `skills/pr-postmortem/SKILL.md` Step 3 tells the categorizer that a residual round whose evidence is thin goes to `flow_stage: unknowable` with a best-fit class, so bot verify-clean rounds with "push followed (low confidence)" evidence (ledger line 4, PR #47 rounds 1, 2, 3, 5) land as `convention_mismatch/unknowable`. 18 such entries crossed the proposer's emission threshold and produced a non-actionable candidate.
Success looks like: a PR's first commit can never count as a review-fix round, and the skill's protocol attributes a residual round from a concrete fix headline or omits it — it never assigns `unknowable` to a round whose only evidence is "a push followed".

**Cited ledger entries (read at their source lines, `.supervisor/postmortem/results.jsonl`):**
- line 3 (PR #43) round 1 — `convention_mismatch`/`unknowable`, evidence "counting artifact: initial feature commit subject contains self-heal, matching the fix-commit regex — not real churn (low confidence)" ⇒ cause A (gather counts the first commit).
- line 4 (PR #47) rounds 1, 2, 3, 5 — `convention_mismatch`/`unknowable`, evidence "bot round N verified …; push followed (low confidence)" ⇒ cause B (skill sends no-finding residual rounds to unknowable).
- Named pattern: two causes, both mis-classifications by the classifier, not churn in the code the entries point at.

## Acceptance Criteria
- [ ] Given a PR whose first commit subject matches `review_fix_re` (e.g. "feat: self-heal sweep"), when `pr-postmortem-gather.sh` runs, then `commits[0].is_review_fix` is `false` and that commit adds nothing to `review_rounds`.
- [ ] Given a PR whose second or later commit subject matches `review_fix_re`, when the gather runs, then that commit is still `is_review_fix: true` (existing fixtures' expectations unchanged).
- [ ] Given the gather's header doc, when a reader looks up `commits[].is_review_fix`, then it states that the PR's first commit is never a review-fix (no review can precede it) and why.
- [ ] Given `skills/pr-postmortem/SKILL.md` Step 3, when a residual round has no concrete finding (a bot verify/all-clear comment and only "a push followed"), then the protocol says to attribute it from a concrete `is_review_fix` headline when one exists, otherwise to OMIT it from `categories[]` — never to classify it `flow_stage: unknowable`.
- [ ] Given SKILL.md Step 3's sentence "Categorize exactly `review_rounds` rounds", when the omit rule lands, then that sentence reads "at most `review_rounds` rounds; a round with no concrete evidence is omitted" — the protocol never says both "exactly N" and "omit".
- [ ] Given an omitted round, when the trend line is built, then it is counted in neither `categories[]` nor `flow_stages` — the sum of `flow_stages` values equals the length of `categories[]` (so `build-floor.sh`'s `flow_stage_counter_disagreements` compare stays clean); SKILL.md Step 5's `FLOW_STAGES_JSON` bullet and postmortem-result.md's `flow_stages` bullet say so.
- [ ] Given SKILL.md Step 2's `review_rounds` paragraph (which restates the review-fix headline signal), when a reader looks up the review-fix rule there, then it states the PR's first commit never counts as a review-fix (same change as the gather header — house rule on restated lists).
- [ ] Given the skill's flow-stage table and Failure Modes table, when a reader looks up `unknowable`, then it is reserved for a round that HAS a concrete finding whose stage cannot be told, and the thin-evidence row says omit, not unknowable.
- [ ] Given `docs/result-schemas/postmortem-result.md` and `commands/pr-postmortem.md`, when a reader looks up `categories`, then they state that `categories[]` may hold fewer entries than `review_rounds` (omitted no-evidence rounds) and the `flow_stages` keys are unchanged.
- [ ] Given `test-pr-postmortem-gather.sh`, when it runs, then a new case pins the first-commit exclusion and it passes alongside every existing case.
- [ ] Given `changelog.d/`, when the PR is opened, then it carries one fragment `changelog.d/churn-ledger-02-classifier-unknowable-attribution.md` and NO version bump (lane PR — the wave branch bumps).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory

## Touched-file invariants

> Grounded at base `0aa53c37ac59fe86a99bd590b36b379d24f9956b`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/pr-postmortem-gather.sh`** — keep: always exit 0 and the single jq build (`ALWAYS exits 0. No \`set -e\` mid-emit crash`; `--arg/--argjson`); keep the success key set unchanged (no new output key — the schema doc says the gather's object shape is consumed by the skill); keep `agent_commit_re` (`def agent_commit_re: "self-heal|^subtask: |^[a-z]{2,}-[0-9]+[a-z]?:";`) untouched — a first commit mentioning self-heal is still an agent-generated signal; reuse: the existing `$headlines` array and `$commits` construction (`([ $headlines[] | { headline: ., is_review_fix: (test(review_fix_re; "i")) } ]) as $commits`) — derive the first-commit exclusion from the array index inside that same jq program, no second jq call; mirror: the header doc block `commits[].is_review_fix —` describes the regex — the new rule is documented there too; pinned by: `loomwright/scripts/test-pr-postmortem-gather.sh` (`is_review_fix`).
- **`loomwright/scripts/test-pr-postmortem-gather.sh`** — keep: the gh-stub-on-PATH harness and the numbered `echo "== N. …"` case style; reuse: the existing fixture writer used by case 3 (`fix: address review feedback`) — add a case, do not rewrite existing ones.
- **`loomwright/skills/pr-postmortem/SKILL.md`, `loomwright/commands/pr-postmortem.md`, `loomwright/docs/result-schemas/postmortem-result.md`** — keep: the 6 classes and the 4 `flow_stages` keys (`{launch_pad, worker, self_heal, unknowable}` — `build-floor.sh` and `scripts/automate-helpers.d/learning.sh` read that object); keep `schema_version` at `1`; mirror: the skill is the authority for the classification protocol, the command and schema doc point at or restate it — update every restating sentence in the same change (house rule above).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | First-commit exclusion in the gather + attribute-or-omit rule in the postmortem protocol | all | 5 modify, 1 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/pr-postmortem-gather.sh"}
  - {kind: "symbol", path: "loomwright/scripts/pr-postmortem-gather.sh", name: "first commit is never a review-fix"}
  - {kind: "symbol", path: "loomwright/scripts/test-pr-postmortem-gather.sh", name: "first commit is never a review-fix"}
  - {kind: "symbol", path: "loomwright/skills/pr-postmortem/SKILL.md", name: "OMIT it from `categories[]`"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/postmortem-result.md", name: "omitted rounds"}
  - {kind: "file", path: "changelog.d/churn-ledger-02-classifier-unknowable-attribution.md"}
requires: []
lanes:
  - "loomwright/scripts/pr-postmortem-gather.sh"
  - "loomwright/scripts/test-pr-postmortem-gather.sh"
  - "loomwright/skills/pr-postmortem/SKILL.md"
  - "loomwright/commands/pr-postmortem.md"
  - "loomwright/docs/result-schemas/postmortem-result.md"
  - "changelog.d/churn-ledger-02-classifier-unknowable-attribution.md"
external_requires: []
```

## Parallelism Analysis
single-agent (no fan-out)

- Recommended workers: 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Prior churn on `pr-postmortem-gather.sh` and `skills/pr-postmortem/SKILL.md` (postmortem ledger: drain_churn, self_heal stage) — source "Prior churn (postmortem ledger)" | MEDIUM | Keep the change minimal and test-pinned; update every surface that restates the classification rule in the same change |
| Omitting rounds makes `categories[]` shorter than `review_rounds`; a consumer that assumes equal length could misread | LOW | `build-floor.sh` / `propose-work.sh` / `harvest-conventions.sh` iterate `categories[]` and tally `flow_stages`; none indexes by `review_rounds`. State the inequality in the schema doc |
| Existing ledger lines keep their `unknowable` entries — the proposer re-emits the candidate until it is dismissed | LOW | The source requirement carries the `evidence-set:` line; its done stamp at close-out is the durable dismissal |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-11-churn-ledger-02-classifier-unknowable.md
```

## Plan Review: PASS (attempt 2/3; 1 LOW advisory — provides-name wording, owner chose Save and exit)

## Outcome
- **Status:** completed
- **Completed:** 2026-10-11T13:36:40Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/477
- **Branch:** feature/churn-ledger-02-classifier-unknowable
- **Files changed:** 6
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Gather pins commits[0].is_review_fix=false (case 13); pr-postmortem skill/command/schema attribute-or-omit no-evidence rounds, never unknowable. Phase 4.5 consistency_audit PASS iter 1 (2 LOW dismissed); ground truth 2/2.

## Not verified
- **live gh pr view commit ordering** — assumed oldest-first (index 0 = PR-opening commit); exercised only via the stubbed gh (subtask 1)
