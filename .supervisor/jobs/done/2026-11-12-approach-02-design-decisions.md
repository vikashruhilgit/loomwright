# Supervisor Job: Briefs record the chosen approach and the alternatives it beat (approach-decisions/02)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (2 stale worktrees listed by `git worktree list`; the source requirement is gitignored under `.supervisor/`, so git cannot vouch for its provenance; it is synced through the metadata branch)
- **Source requirement:** .supervisor/requirements/approach-decisions/02-briefs-record-the-chosen-approach-and-the-alternatives-it-beat.md
- **Base commit:** 0c83614897cb732923510e1ac0be47be04f39432

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Prompt markdown, bash 3.2 tests and JSON budget rows, the same as every other Loomwright change. |
| 2 | Dependency Availability | GO | No new dependency. The read-on-demand split-file pattern already exists (`skills/async-orchestration/finalize.md`). |
| 3 | Architecture Fit | GO | Optional brief section + conditional Launch Pad sub-phase + conditional Plan Reviewer criterion: the same shape as Criteria 18–21 and Phase 2.5. |
| 4 | Scope vs Supervisor Capability | CAUTION | About 22 files including fixtures, so it is past the `context-bound` bound (> 12 files). It is split by Part into 3 subtasks (Split reason below). `right-size` reported "large (31 files)", but 9 of those are companion surfaces of a NEW skill dir, and none of them applies to a new file under an existing skill dir. |
| 5 | Hard Blockers | CAUTION | The `launch-pad` agent budget row has 617 proxy tokens of headroom at base (live 46940 / 47557). The requirement assumed 1051. That row also folds the preloaded `supervisor-readiness/SKILL.md`, so the template edits count against it too. The AC forbids raising it. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Give a Launch Pad brief an optional, trigger-gated `## Design decisions` section (chosen way, rejected way(s) + why, evidence, revisit-when, status), produced by a new conditional Launch Pad Phase 2.7 APPROACH whose protocol lives in a read-on-demand split file, verified by a new conditional Plan Reviewer Criterion 23 (23a–23d), and backed by one Red Team vector-1 bullet. The worker and the rules store stay unchanged, and the house rule is only proposed.

**Problem Statement:**
The owner needs "why not X / the platform already does this" answered when the plan is made, because today it costs a review round.
Currently, Plan Reviewer Criterion 2 only checks that the approach matches CLAUDE.md. Launch Pad Phase 2.5 rates a new dependency CAUTION, and nothing asks whether it is the right one. The brief template has no approach section, yet Criterion 17a/17c already read "Design decisions", a dangling reference.
This causes "why not use X" and "missing_context" review rounds, which story `01`'s `approach_challenged` flag now counts.
Success looks like: a brief that hits a closed trigger (T1–T5) carries a verified Design decisions entry; a reinvention of an existing helper FAILs at plan time (23c); and the `approach_challenged` rate falls (revisit after 20 merged agent PRs).

## Design decisions
- decision: where the Phase 2.7 protocol text lives
  chosen: a read-on-demand split file `loomwright/skills/supervisor-readiness/design-decisions.md`, read with `Read(` only on a trigger
  rejected: inline in `agents/launch-pad.md`: the `launch-pad` row has 617 proxy tokens of headroom, and the AC freezes its budget at 47557
  rejected: inside `supervisor-readiness/SKILL.md`: that file is preloaded into the `launch-pad` row (`check-token-budget.sh` folds `skill_file="$SKILLS_DIR/$skill/SKILL.md"`), so it eats the same headroom
  evidence: `bash scripts/check-token-budget.sh` → `launch-pad 46940 47557 OK 617 headroom (7 preloaded skills)`; precedent `skills/async-orchestration/finalize.md` (read at Supervisor Phase 4 entry, not preloaded)
  revisit when: `check-token-budget.sh` starts folding every `*.md` of a preloaded skill dir, which would move the split file out of a preloaded dir
  status: confirmed
- decision: how a new gate code reaches the gate catalog
  chosen: add an `_lp_row LP-APPROACH human-only …` row to `loomwright/scripts/lane-policy.sh` and regenerate `docs/LANE_GATES.md` with `lane-policy.sh catalog --markdown`
  rejected: hand-editing `docs/LANE_GATES.md` alone, as the requirement worded it: `test-lane-policy.sh` (cat7) fails on drift from the catalog, and `check-gate-headers.sh` G2 rejects a `header:` that names no catalog code
  evidence: `lane-policy.sh`: `# Adding, removing or relabelling a row: regenerate loomwright/docs/LANE_GATES.md's table in the SAME`
  revisit when: the gate catalog moves out of `lane-policy.sh`
  status: confirmed

## Acceptance Criteria

Prompt-surface arms and fixture briefs run in `mktemp -d`. The reviewer is an LLM, so the EXPECTED issue shapes are pinned as fixtures and the prompt text that produces them is pinned by grep (the `test-rule-conformance-seam.sh` style). No network.

- [ ] **AC1 Template section:** Given `loomwright/skills/supervisor-readiness/SKILL.md`, when `bash loomwright/scripts/test-design-decisions.sh` runs, then the template carries `## Design decisions` between `## Task` and `## Acceptance Criteria`, §"Section Requirements" names `Design decisions` as optional, the Quality Checklist names it, and the six entry keys `decision`, `chosen`, `rejected`, `evidence`, `revisit when`, `status` appear verbatim.
- [ ] **AC2 Split file:** Given `loomwright/skills/supervisor-readiness/design-decisions.md`, when the test runs, then it names triggers `T1`–`T5` with one detection rule each (T1 from Phase 2.5 check 1/2 CAUTION rows; T2 from File Impact Map CREATE rows that are a script or module; T3–T5 from the goal and `## Task`). It also names: the three-candidate order with "already in the repo" first; the five fixed axes, each `yes | partial | no` with no weights (fits the CLAUDE.md stack; already in the lockfile or manifest; blast radius; test cost; reversibility / lock-in); the three evidence sources, with `WebSearch` only under `--discovery` and Context7 within `skills/context7-lookup/SKILL.md`'s budget; `status: confirmed | unconfirmed`; the `LP-APPROACH` header with its three options `Keep <chosen>` · `Switch to <runner-up>` · `Decide later`, asked only on an axes tie or a T1 dependency; the Can't-ask branch (record the default pick `status: unconfirmed`, never ask, never abort); and the sentence that a worker's `plan:` deviation is the worker's channel for "I found a better way", read by the Phase 4.5 review lens.
- [ ] **AC3 Launch Pad phase within budget:** Given `loomwright/agents/launch-pad.md`, when the test and `bash scripts/check-token-budget.sh` run, then the file carries `### Phase 2.7: APPROACH` between `### Phase 2.5: FEASIBILITY` and `### Phase 3: ANALYZE`, a `Read(` of `design-decisions.md` gated on a trigger, the literal `## Phase 2.7: APPROACH — no trigger`, `header: "LP-APPROACH"`, and `status: unconfirmed` in its Critical Rules Can't-ask rule via one Phase 2.7 clause that is written byte-identically into `commands/launch-pad.md`'s Can't-ask rule (the two `- **Can't-ask rule:**` bullets stay equal, as `test-non-interactive-gates-seam.sh` (g) requires); the phase block is ≤ 25 lines (counted from its heading to the next `### Phase` heading, the `**Output:**` block excluded); the Phase-numbering convention line names 2.7 beside 2.5 and 5.5; and the `launch-pad` agent row passes with its budget unchanged at 47557.
- [ ] **AC4 Command mirror:** Given `loomwright/commands/launch-pad.md`, when the test runs, then its "7-phase readiness workflow" sentence names the 2.7 sub-phase beside 2.5 and 5.5 ("do not change the count"), it carries a `### Phase 2.7: APPROACH` block after its Phase 2.5 block, its `- **Can't-ask rule:**` bullet stays byte-identical to the agent's, so it carries the same Phase 2.7 `status: unconfirmed` clause, its Phase 5 step 2 names Design decisions beside the optional Feasibility section, and its Phase 5.5 step 2 conditional-criteria list reads `Criteria 11, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, and 23 are conditional` with Criterion 23's gate clause.
- [ ] **AC5 Gate inventory:** Given the gate catalog, when `bash loomwright/scripts/test-lane-policy.sh`, `bash loomwright/scripts/check-gate-headers.sh` and the test run, then `loomwright/scripts/lane-policy.sh` has an `LP-APPROACH` `human-only` row with labels `Keep <chosen>|Switch to <runner-up>|Decide later`, `loomwright/docs/LANE_GATES.md` is regenerated from it (cat7 green), and `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" has an `LP-APPROACH` row whose new can't-ask column says `status: unconfirmed`, never asked, never aborted.
- [ ] **AC6 Criterion 23:** Given `loomwright/agents/plan-reviewer.md`, when the test and the three seam tests run, then it carries `### 23. Approach justification (conditional)` after Criterion 22 with `23a`, `23b`, `23c`, `23d`, the categories `approach_unjustified` and `approach_reinvents`, the "verifies claims; never re-decides" sentence, the two Decision Matrix rows (23c ⇒ FAIL HIGH `approach_reinvents`; 23d T1 `status: unconfirmed` with no BLOCKING/HIGH ⇒ NEEDS_HUMAN), `## 23 Review Criteria`, `All 23 review criteria must be checked`, `(23 total, Criteria 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, and 23 conditional)` and `All 23 criteria checked`, lacks `## 22 Review Criteria`, and its output-format `category` enum names both new categories with the range `(12–23)`. `test-closed-enum-pins-seam.sh`, `test-pr-body-evidence-seam.sh` and `test-rule-conformance-seam.sh` move their "22" pins to "23" (with `lacks … '## 22 Review Criteria'`) in the same change and pass.
- [ ] **AC7 Fixture briefs:** Given `loomwright/scripts/fixtures/design-decisions/`, when the test runs, then four fixture briefs exist, each with an expected-shape JSON: (a) T1 CAUTION row, no section ⇒ `{severity: MEDIUM, category: approach_unjustified, decision: PASS}`; (b) T1 entry whose `chosen:` is absent from the fixture `repo/package.json`, no `rejected:` ⇒ MEDIUM `approach_unjustified`, decision PASS; (c) a CREATE `scripts/slugify.sh` while the fixture `repo/scripts/propose-common.sh` defines `pc_slugify`, the entry silent on it ⇒ `{severity: HIGH, category: approach_reinvents, decision: FAIL}`; (d) T1 entry `status: unconfirmed` ⇒ `{severity: MEDIUM, category: approach_unjustified, decision: NEEDS_HUMAN}`. Each fixture's trigger text matches Criterion 23's gating rule by grep, and the test header states that the LLM verdict itself is not unit-tested (Validation V4–V6 cover it).
- [ ] **AC8 Red Team bullet:** Given `loomwright/agents/red-team-reviewer.md`, when the test runs, then vector 1 "Core Flaws & Blind Spots" carries the bullet "Does this reinvent a mechanism the platform, SDK, harness or an existing module already provides?" and `You MUST examine all 6 attack vectors.` is unchanged.
- [ ] **AC9 Worker unchanged:** Given the branch, when the test runs, then `git diff --exit-code origin/main -- loomwright/agents/worker.md` is clean (the guard is inside the test and degrades to a skip note when `origin/main` is absent).
- [ ] **AC10 No rule written:** Given the branch, when the test runs, then `.agent/rules/*.json` are byte-identical to `origin/main`, and a committed evidence file `docs/evidence/design-decisions.md` contains the proposed `/rules add` invocation verbatim (statement "A brief that adds a new dependency carries a `## Design decisions` entry naming the chosen library, at least one rejected alternative and the evidence", category `process`, `--enforcement advisory`, the seven `--applies-to` manifests `package.json`, `package-lock.json`, `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pubspec.yaml`, and no `--check`) with the reason it is advisory (unprovable by `prove-rule-check.sh` leg 2). The PR body links that file.
- [ ] **AC11 Schema doc:** Given `loomwright/docs/result-schemas/plan-review-result.md`, when `bash loomwright/scripts/test-result-schemas-split.sh` and the test run, then both `category` lines name `"approach_unjustified"` / `"approach_reinvents"` for Criterion 23, and `loomwright/scripts/validate-plan-review-result.py` is byte-identical to `origin/main`.
- [ ] **AC12 Gates:** Given the finished branch, then `bash scripts/check-token-budget.sh` passes, with the `supervisor-readiness` and `plan-reviewer` rows re-baselined to measured + ~10% with their `ARCHITECTURE_CONTRACTS.md` mirror rows, the `launch-pad` agent row NOT raised, and the `launch-pad` command row re-measured (raised to measured + ~10% only if it breaches). `bash scripts/check-prompt-history-refs.sh` passes with the live baselines unraised: `loomwright/agents/launch-pad.md` ≤ 5, `loomwright/agents/plan-reviewer.md` ≤ 8, `loomwright/agents/red-team-reviewer.md` = 0, `loomwright/skills/supervisor-readiness/SKILL.md` ≤ 21, `loomwright/commands/launch-pad.md` = 0, and a new entry `loomwright/skills/supervisor-readiness/design-decisions.md` = 0 (the new text names no PR, issue or version). `bash scripts/check-doc-currency.sh` passes, and `bash scripts/check-version-bump.sh` passes with `changelog.d/design-decisions.md`.
- [ ] **V1–V3 Static validation:** `bash loomwright/scripts/test-design-decisions.sh`, the three seam tests, `bash loomwright/scripts/test-result-schemas-split.sh`, `bash loomwright/scripts/test-lane-policy.sh` and `bash scripts/ci-local.sh --affected` pass. The `--affected` run includes `check-token-budget.sh`, `check-prompt-history-refs.sh`, `check-doc-currency.sh` and `check-test-hermetic.sh`.
- [ ] **V4 Running system, a triggering goal:** Given a scratch Node project (a `package.json`, a CLAUDE.md naming the stack, no rate-limit dependency), when `/launch-pad goal: "add rate limiting to the /api/upload route with a library"` runs interactively with this checkout's plugin, then Phase 2.7 prints a T1 entry (a chosen library, ≥ 1 `rejected:`, an `evidence:` naming the manifest grep), `LP-APPROACH` is asked once, the saved brief carries `## Design decisions` with `status: confirmed`, and the Plan Review result shows Criterion 23 evaluated with no `approach_reinvents`. A committed evidence file `docs/evidence/design-decisions.md` holds the phase output, the question, the section and the Criterion 23 lines, with the column-0 line `Verdict: PASS for Validation 4`, written only when this run was actually observed.
- [ ] **V5 Running system, a non-triggering goal:** Given the same project, when `/launch-pad goal: "fix the typo in README.md §Install"` runs, then it prints `## Phase 2.7: APPROACH — no trigger`, the saved brief has no `## Design decisions`, and the Plan Review result carries no `approach_` category. Recorded in `docs/evidence/design-decisions.md` with `Verdict: PASS for Validation 5`.
- [ ] **V6 Running system, the can't-ask branch:** Given the V4 goal under `--non-interactive`, when it runs, then no question is asked, the entry carries `status: unconfirmed`, and the Plan Review result is NEEDS_HUMAN with a MEDIUM `approach_unjustified` naming 23d. Recorded in `docs/evidence/design-decisions.md` with `Verdict: PASS for Validation 6`.

**Evidence rule:** every criterion's evidence lives in the diff: the test, the fixtures, and `docs/evidence/design-decisions.md` (a File Impact Map create). A Validation whose run was not observed gets no `Verdict:` line. The `/automate` validation gate then parks it for the owner (`AUT-WAIVE`), and no verdict is fabricated.

## Scope widening
- loomwright/docs/prompt-history-refs-baseline.json
- loomwright/scripts/fixtures/design-decisions/**
- loomwright/scripts/fixtures/design-decisions/brief-a-t1-no-section.md
- loomwright/scripts/fixtures/design-decisions/brief-b-t1-no-rejected.md
- loomwright/scripts/fixtures/design-decisions/brief-c-reinvention.md
- loomwright/scripts/fixtures/design-decisions/brief-d-t1-unconfirmed.md
- loomwright/scripts/fixtures/design-decisions/expected-a.json
- loomwright/scripts/fixtures/design-decisions/expected-b.json
- loomwright/scripts/fixtures/design-decisions/expected-c.json
- loomwright/scripts/fixtures/design-decisions/expected-d.json
- loomwright/scripts/fixtures/design-decisions/repo/package.json
- loomwright/scripts/fixtures/design-decisions/repo/scripts/propose-common.sh
- loomwright/scripts/lane-policy.sh
- accepted: LP-SCOPE 2026-11-12

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

> How this brief honors them: the criteria count "23" is written only in `agents/plan-reviewer.md` (its own authority). The three seam tests' existing pins move with it in the same change (rule 2). Nothing new restates the count. The command's conditional-criteria list (`commands/launch-pad.md` Phase 5.5 step 2) and the `LANE_GATES.md` mirror are restated copies, and each is updated in the same change as its authority (`plan-reviewer.md`, `lane-policy.sh`).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `0c83614897cb732923510e1ac0be47be04f39432`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/test-closed-enum-pins-seam.sh`, `loomwright/scripts/test-pr-body-evidence-seam.sh`, `loomwright/scripts/test-rule-conformance-seam.sh`**: keep: `set -uo pipefail`, the `mktemp -d` work dir and the hermetic source line ending `hermetic-test-env.sh"`; reuse: the helpers `has()   { grep -qF -- "$2" "$1"; }` / `lacks() { ! grep -qF -- "$2" "$1"; }` (spacing differs per file, but the bodies are the same) and the arm form `has "$PR" '## 22 Review Criteria' && lacks "$PR" '## 21 Review Criteria'`, moved to `'## 23 Review Criteria'` / `'## 22 Review Criteria'`; mirror: the literals `All 22 review criteria must be checked`, `(22 total, Criteria 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, and 22 conditional)`, `- [ ] All 22 criteria checked` (the `CHK="$(grep -F -- '- [ ] All 22 criteria checked' "$PR")"` extractors in `test-pr-body-evidence-seam.sh` and `test-rule-conformance-seam.sh`), `Criteria 11, 13, 14, 15, 16, 17, 18, 19, 20, 21, and 22 are conditional` and `| pin_mutations | pr_body_evidence | module_layout | requirement_fit | ...}"  # optional — emit when a criterion mandates it (12–22)` must move to exactly the new text in `agents/plan-reviewer.md`; pinned by: themselves (globbed `loomwright/scripts/test-*.sh`), with `scripts/check-test-hermetic.sh` requiring the hermetic source line.
- **`loomwright/agents/launch-pad.md` + `loomwright/commands/launch-pad.md` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory"**: keep: the two `- **Can't-ask rule:**` bullets byte-identical (pinned by `loomwright/scripts/test-non-interactive-gates-seam.sh` (g): `lp_rule() { grep -F -- "- **Can't-ask rule:**" "$1" | head -1; }` … `[ "$lp_a" = "$lp_c" ]`), so add the Phase 2.7 clause verbatim to both; `### Phase 2.5: FEASIBILITY` heading prefix unchanged; the `## Question-gate inventory` section stays immediately before `## Failure Escalation Summary`, and the new `LP-APPROACH` row's LAST cell must not contain `undefined` (same test, `inv_undefined_rows`); keep the seam tests' existing substrings of `commands/launch-pad.md` (e.g. `checks every review criterion`) intact when extending its Phase 5.5 step 2 list; pinned by: `test-non-interactive-gates-seam.sh`, `test-closed-enum-pins-seam.sh`, `test-pr-body-evidence-seam.sh`, `test-rule-conformance-seam.sh`.
- **`loomwright/scripts/lane-policy.sh`**: keep: the row format `_lp_row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }`, so labels are `|`-joined with no tab or newline, and `(free text)` is never on a non-free gate; reuse: an existing human-only Launch Pad row as the model (`_lp_row LP-NO-GO     human-only 'Override and continue|Revise goal|Abort'`); mirror: `# Adding, removing or relabelling a row: regenerate loomwright/docs/LANE_GATES.md's table in the SAME` (run `bash loomwright/scripts/lane-policy.sh catalog --markdown` and paste between its markers); fired by: `check-gate-headers.sh` (G2 every `header:` names a catalog code; G3 the ask site quotes every catalog label; G5 every code has an ask site) and `lane-policy.sh decide`; pinned by: `loomwright/scripts/test-lane-policy.sh` `(cat7) LANE_GATES.md's table, parsed back to TSV, equals lane-policy.sh catalog` and `(cat5) the allowed gates and the auto gates are EXACTLY their two closed sets`. LP-APPROACH is human-only, so cat5's closed sets do not change.
- **`loomwright/docs/prompt-token-budgets.json`** (read by `scripts/check-token-budget.sh`): keep: `"launch-pad": {"budget": 47557` unchanged in `.agents`; the proxy is bytes / 4 (`DIVISOR="$(jq -r '.proxy_bytes_per_token // 4' "$BUDGET_JSON")"`); mirror: each re-baselined row's `ARCHITECTURE_CONTRACTS.md` mirror cell (`` | `supervisor-readiness` | 12700 | 11545 | ``, `` | `plan-reviewer`     | 11535 | 10528¹ | 0 | ``, `` | `launch-pad` | 6203 | 5678 | `` for the command), plus one log line in that section in the existing `> **Raise log (…)` / `> **Re-measure log (…)` style.
- **`loomwright/docs/prompt-history-refs-baseline.json`** (read by `scripts/check-prompt-history-refs.sh`): keep: no entry rises, and the baseline total does not rise (`baseline total rose: <base> -> <now>`); add exactly `"loomwright/skills/supervisor-readiness/design-decisions.md": 0`, never by `--write-baseline` ("lowering PRs only").

## Closed enumerations touched

> Sibling grep at base `0c83614`: `grep -rnF 'module_layout' --exclude=CHANGELOG.md loomwright scripts docs` → 8 hits in 5 files (fixtures excluded).

- **`approach_unjustified` / `approach_reinvents`** (sibling: `module_layout`), which must be named in:
  - `loomwright/agents/plan-reviewer.md`: the output-format enum `category: "{dep_graph | missing_field | …` (emit range `(12–22)` → `(12–23)`), extend; the Quality Checklist `- [ ] All 22 criteria checked (…)`, extend with Criterion 23's clause; the per-criterion `**Issue category:**` line, which gets Criterion 23's own new line.
  - `loomwright/docs/result-schemas/plan-review-result.md`: line-13 `category: string # optional — …` comment and the line-27 `` `category` is optional but recommended `` list. Extend both.
  - `loomwright/scripts/test-pr-body-evidence-seam.sh`: pins the enum line verbatim (`| pin_mutations | pr_body_evidence | module_layout | requirement_fit | ...}"`). Extend it to the new line.
  - `loomwright/scripts/test-closed-enum-pins-seam.sh` (`'**Issue category:** `module_layout`.'`): no change. It pins Criterion 21's own category line, not a list of all categories.
  - `loomwright/scripts/validate-plan-review-result.py`: no change. It has no category enum, and AC11 requires it byte-identical.

> Sibling grep at base `0c83614`: `grep -rlF 'LP-SCOPE' --exclude=CHANGELOG.md loomwright scripts docs` → 14 files.

- **`LP-APPROACH`** (sibling: `LP-SCOPE`), which must be named in:
  - `loomwright/scripts/lane-policy.sh`: the gate catalog `_lp_catalog_rows()`, the ONE authority. Extend.
  - `loomwright/docs/LANE_GATES.md`: the generated catalog mirror. Extend by regenerating.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory": extend with one row.
  - `loomwright/agents/launch-pad.md` / `loomwright/commands/launch-pad.md`: the ask site and the Can't-ask rule. Extend.
  - `loomwright/scripts/automate-lanes.d/scope.sh` (`case "$gate" in ''|AUT-OVERLAP|LP-SCOPE)`), `loomwright/scripts/automate-lanes.sh`, `loomwright/scripts/guard-lane-wait-armed.sh`, `loomwright/skills/automate-loop/lanes.md`: no change. These are the scope re-gate's own two gates, not a list of every gate.
  - `loomwright/scripts/test-lane-policy.sh`, `loomwright/scripts/test-automate-lanes.d/08-scope-regate.sh`, `docs/evidence/lane-scope-regate-*.md`, `loomwright/docs/prompt-token-budgets.json`: no change. They are LP-SCOPE-specific tests, evidence and note text; cat7 reads the whole catalog dynamically.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-design-decisions.sh`: AC1 template heading | delete `## Design decisions` in `loomwright/skills/supervisor-readiness/SKILL.md` |
| `loomwright/scripts/test-design-decisions.sh`: AC2 discovery-only WebSearch | flip `--discovery` → `--always` in `loomwright/skills/supervisor-readiness/design-decisions.md` |
| `loomwright/scripts/test-design-decisions.sh`: AC3 phase heading | delete `### Phase 2.7: APPROACH` in `loomwright/agents/launch-pad.md` |
| `loomwright/scripts/test-design-decisions.sh`: AC3 no-trigger literal | flip `## Phase 2.7: APPROACH — no trigger` → `## Phase 2.7: APPROACH — none` in `loomwright/agents/launch-pad.md` |
| `loomwright/scripts/test-design-decisions.sh`: AC4 command block | delete `### Phase 2.7: APPROACH` in `loomwright/commands/launch-pad.md` |
| `loomwright/scripts/test-design-decisions.sh`: AC5 gate row | flip `LP-APPROACH  human-only` → `LP-APPROACH  allowed` in `loomwright/scripts/lane-policy.sh` (also turns test-lane-policy cat7 red until LANE_GATES.md is regenerated) |
| `loomwright/scripts/test-design-decisions.sh`: AC6 23c FAIL row | delete `(23c)` in `loomwright/agents/plan-reviewer.md` (the Decision Matrix 23c row; the row must be the only line containing `(23c)`) |
| `loomwright/scripts/test-closed-enum-pins-seam.sh`: criteria count 23 | flip `## 23 Review Criteria` → `## 22 Review Criteria` in `loomwright/agents/plan-reviewer.md` (same mutation reddens `test-pr-body-evidence-seam.sh` and `test-rule-conformance-seam.sh`) |
| `loomwright/scripts/test-pr-body-evidence-seam.sh`: category enum line | flip `approach_reinvents | ...}` → `...}` in `loomwright/agents/plan-reviewer.md` |
| `loomwright/scripts/test-design-decisions.sh`: AC7 fixture (c) expected shape | flip `"decision": "FAIL"` → `"decision": "PASS"` in `loomwright/scripts/fixtures/design-decisions/expected-c.json` |
| `loomwright/scripts/test-design-decisions.sh`: AC8 Red Team bullet | delete `Does this reinvent a mechanism the platform, SDK, harness or an existing module already provides?` in `loomwright/agents/red-team-reviewer.md` |
| `loomwright/scripts/test-design-decisions.sh`: AC9 worker guard | flip `### Step 5.7: Optional — record deviations from plan` → `### Step 5.7: Optional — record deviations` in `loomwright/agents/worker.md` |
| `loomwright/scripts/test-design-decisions.sh`: AC10 `/rules add` line | flip `--enforcement advisory` → `--enforcement must` in `docs/evidence/design-decisions.md` |
| `loomwright/scripts/test-design-decisions.sh`: AC11 schema categories | flip `"approach_reinvents"` → `"approach_reinvent"` in `loomwright/docs/result-schemas/plan-review-result.md` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Launch Pad side: template section, split file, Phase 2.7, command mirror, LP-APPROACH gate | AC1, AC2, AC3, AC4, AC5, AC12 (launch-pad rows + history baseline) | 7 modify, 1 create | `skills/supervisor-readiness/SKILL.md`, `skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 2 | Plan Reviewer Criterion 23 + schema categories + Red Team bullet + seam-test pins | AC6, AC8, AC11 | 6 modify, 0 create | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |
| 3 | Test, fixtures, evidence, budget re-baselines, changelog fragment | AC7, AC9, AC10, AC12, V1–V6 | 2 modify, 12 create | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1, #2) |

### Subtask 1: implementation notes
- **SKILL.md (preloaded into the `launch-pad` agent row: every byte counts against its 617 headroom):** add only (a) a `## Design decisions` block in the template between `## Task` and `## Acceptance Criteria`, with a one-line header note naming the split file and the six key lines `- decision:` · `  chosen:` · `  rejected: <way> — <why>` · `  evidence:` · `  revisit when:` · `  status: confirmed | unconfirmed`; (b) `Design decisions` in §"Section Requirements"' optional list (Launch Pad Phase 2.7, only on a trigger; Plan Reviewer Criterion 23), and the paragraph's restated count "the latter eight" becomes count-free (e.g. "the sections after Feasibility") in the same edit, per the advisory count rule; (c) one short Quality Checklist line. The triggers, axes, sources and ask rule go in `design-decisions.md` only. Target ≤ 600 bytes added to SKILL.md.
- **`design-decisions.md` (new, read on demand, counted only under `skills.supervisor-readiness`):** the AC2 content, plus the entry format and the closed trigger list. Bug fixes, docs, prompt-only edits and small changes never trigger it; no trigger ⇒ no section. Also the T2 re-check after Phase 3 action 13, with one section assembled at Phase 5. Start it with `# ` title + a one-line purpose; no frontmatter (it is not a skill).
- **`agents/launch-pad.md`:** `### Phase 2.7: APPROACH (conditional)` between Phase 2.5's closing `---` and `### Phase 3: ANALYZE`, ≤ 25 lines. Its entry is `Read("${CLAUDE_PLUGIN_ROOT}/skills/supervisor-readiness/design-decisions.md")` only when a trigger is detected from the Phase 2.5 table and the goal; T2 is re-checked after Phase 3 action 13. With no trigger it prints `## Phase 2.7: APPROACH — no trigger`, reads nothing and emits no section. The ask is `AskUserQuestion` with `header: "LP-APPROACH"` and options `Keep <chosen>` · `Switch to <runner-up>` · `Decide later`, only on a tie or a T1 dependency (G3 requires all three labels quoted in that block). Also add: one Phase 5 action line (emit `## Design decisions` after `## Task` when ≥ 1 entry exists); `Phase 2.7 → status: unconfirmed recorded, never asked, never aborted` in the Critical Rules Can't-ask rule; 2.7 in the Phase-numbering convention line and the workflow arrow line. Target ≤ 1,800 bytes added, so the agent + SKILL.md total stays ≤ 2,400 bytes (617 proxy tokens × 4). Run `bash scripts/check-token-budget.sh` and confirm the `launch-pad` agent row is OK **without** touching its budget. If it breaches, tighten the new text; never raise the row and never trim unrelated text. If it still cannot fit, report `blocked: launch_pad_budget` in the hand-back.
- **`commands/launch-pad.md`:** the AC4 edits. The Phase 5.5 step 2 list gains `22, and 23 are conditional` and a Criterion 23 clause ("Criterion 23 runs only when the brief carries a trigger (T1 CAUTION dependency row, T2 CREATE script/module, T3–T5 in `## Task`); a 23c reinvention FAILs the brief, a T1 `status: unconfirmed` is NEEDS_HUMAN, any other gap is MEDIUM").
- **Gate catalog:** add the `_lp_row LP-APPROACH human-only 'Keep <chosen>|Switch to <runner-up>|Decide later' '<purpose: Launch Pad Phase 2.7 approach pick, asked only on an axes tie or a T1 new dependency; cannot ask ⇒ status: unconfirmed, never asked, never aborted>'` row after `LP-NO-GO`. Regenerate the `LANE_GATES.md` table, then run `bash loomwright/scripts/test-lane-policy.sh` and `bash loomwright/scripts/check-gate-headers.sh`.
- **`ARCHITECTURE_CONTRACTS.md`:** ONE Question-gate inventory row after the `LP-NO-GO` row, in the five-column shape (`Gate | File / section | Contexts | Current can't-ask behaviour | New can't-ask behaviour`): `new gate` in column 4 and `status: unconfirmed` recorded, never asked, never aborted in column 5. Subtask 1 does not touch the budget mirror rows; subtask 3 owns them.
- **Phase 6 "Edit sections":** verified at base: it reads the assembled brief ("User specifies what to change, update in-place") and enumerates no optional section by name, so no edit is needed there; record that in the hand-back.
- Before hand-back run `bash loomwright/scripts/test-non-interactive-gates-seam.sh` in addition to the gates above.
- **`prompt-history-refs-baseline.json`:** add the `design-decisions.md: 0` entry, then run `bash scripts/check-prompt-history-refs.sh`.
- Expected transient red until subtask 3: `check-token-budget.sh`'s `supervisor-readiness` skill row (the split file grows it; the re-baseline is subtask 3's) and, if it breaches, the `launch-pad` command row. Report the measured numbers in the hand-back.

### Subtask 2: implementation notes
- `### 23. Approach justification (conditional)` after Criterion 22's block and before `## Decision Matrix`, in Criterion 21/22's shape (**Check:** / gate / sub-checks / **Severity if failed:** / **Issue category:**):
  - **Gate:** a trigger is present: T1 = a `## Feasibility` CAUTION row naming a new dependency; T2 = a File Impact Map CREATE row that is a script or module; T3–T5 = `## Task` names a new external integration, a cross-cutting mechanism, or hand-rolls something the manifest, the harness or a stackpack skill provides. No trigger ⇒ skip silently.
  - **23a:** a trigger with no matching `- decision:` entry, or no section ⇒ MEDIUM `approach_unjustified` (stays PASS; Launch Pad refines at its fix floor by running Phase 2.7 for it).
  - **23b:** a T1 entry whose `chosen:` is absent from the manifest or lockfile (the reviewer searches it with its Grep tool) and has no `rejected:` line ⇒ MEDIUM `approach_unjustified`.
  - **23c:** the reviewer's own repo search (helpers, `scripts/`, `stackpack/skills/SKILLS_INDEX.md`) finds an existing helper or module doing what a CREATE path does, and the entry names it under neither `rejected:` nor `evidence:` ⇒ HIGH `approach_reinvents` ⇒ FAIL. The issue quotes the search pattern and the hit.
  - **23d:** `status: unconfirmed` on a T1 entry ⇒ MEDIUM `approach_unjustified` + NEEDS_HUMAN, never FAIL; on T2–T5 it is a LOW note.
  - "The reviewer verifies claims; it never re-decides." A `rejected:` line the reviewer disagrees with is not an issue.
  - Plan Reviewer has Read/Glob/Grep only (no Bash), so the prose says "search with the Grep tool", never a shell `grep -rn`.
- Two Decision Matrix rows. 23c ⇒ **FAIL** (HIGH `approach_reinvents`). 23d T1 `status: unconfirmed` and no BLOCKING/HIGH issue ⇒ **NEEDS_HUMAN** (the owner decides: confirm, switch, or drop the dependency; independent of ambiguity, like the 14 and 17c rows). Also amend the `Only MEDIUM/LOW issues … AND no Criterion 14 or 17c NEEDS_HUMAN escalation` row to name 23d.
- Every count literal moves from 22 to 23: the never-skip line, the `## 22 Review Criteria` heading, the matrix PASS row, the checklist line with a Criterion 23 clause, the output-format enum + `(12–23)`. Run `grep -nE "\b22\b" loomwright/agents/plan-reviewer.md` after editing, and keep only hits that refer to Criterion 22 itself.
- `docs/result-schemas/plan-review-result.md`: both category lines gain `"approach_unjustified" / "approach_reinvents" for Criterion 23 findings`. Run `bash loomwright/scripts/test-result-schemas-split.sh`.
- `agents/red-team-reviewer.md` vector 1: append the one bullet.
- The three seam tests: move every pin listed in §"Touched-file invariants" to the new text (`lacks … '## 22 Review Criteria'`), then run each.
- Expected transient red until subtask 3: `check-token-budget.sh`'s `plan-reviewer` row, if Criterion 23 breaches 11535. Report the measured number.

### Subtask 3: implementation notes
- `loomwright/scripts/test-design-decisions.sh` (new; model: `test-rule-conformance-seam.sh`): `set -uo pipefail`, source `hermetic-test-env.sh`, a `mktemp -d` work dir, `has`/`lacks`, and a header stating that the LLM verdict is not unit-tested (V4–V6 are). Arms for AC1–AC11. The AC3 ≤ 25-line count is an awk from `### Phase 2.7: APPROACH` to the next `### Phase`, skipping the `**Output:**` fence. The AC9/AC10/AC11 byte-identical guards use `git diff --exit-code origin/main -- <path>` and print a skip note when `origin/main` does not resolve. AC7 checks the fixture files exist, that each `expected-*.json` parses with `jq` and carries the stated severity/category/decision, and that each brief's trigger text matches Criterion 23's gate by grep (a: a `## Feasibility` CAUTION row naming a dependency; c: a CREATE `scripts/slugify.sh` row, plus `pc_slugify` defined in `repo/scripts/propose-common.sh`).
- `docs/evidence/design-decisions.md`: the proposed `/rules add` invocation (AC10) and the V4/V5/V6 sections. Run V5 and V6 in a `mktemp -d` scratch Node project with `claude -p --plugin-dir <this checkout>/loomwright` (headless; V6 adds `--non-interactive`). V4 needs an interactive ask: run it if the session can show `LP-APPROACH`. Otherwise record the transcript you have and leave V4 with no `Verdict:` line, so the owner is asked through `AUT-WAIVE`. Never write a verdict for a run you did not observe. Use `/Users/<name>/` placeholders for any home path.
- `loomwright/docs/prompt-token-budgets.json` + `ARCHITECTURE_CONTRACTS.md` budget mirror rows: re-baseline `skills.supervisor-readiness` and `agents.plan-reviewer` to measured + ~10%; re-measure the `commands.launch-pad` row and raise it to measured + ~10% only on a breach; leave `agents.launch-pad`'s budget at 47557 (update its `measured` only). Add one log line in §"Prompt Token Budgets".
- `changelog.d/design-decisions.md`: `<!-- bump: minor -->`, a one-line headline, and a paragraph in the style of `changelog.d/approach-baseline.md`. No version bump in this PR; `bash scripts/check-version-bump.sh` must pass.
- Finish with `bash scripts/ci-local.sh --affected`, and run any suite it lists as not covered.

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/skills/supervisor-readiness/design-decisions.md"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/design-decisions.md", name: "LP-APPROACH"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-readiness/SKILL.md", name: "## Design decisions"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "### Phase 2.7: APPROACH"}
  - {kind: "symbol", path: "loomwright/commands/launch-pad.md", name: "### Phase 2.7: APPROACH"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "LP-APPROACH"}
  - {kind: "symbol", path: "loomwright/docs/LANE_GATES.md", name: "LP-APPROACH"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "LP-APPROACH"}
  - {kind: "symbol", path: "loomwright/docs/prompt-history-refs-baseline.json", name: "design-decisions.md"}
requires: []
lanes:
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/skills/supervisor-readiness/design-decisions.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/docs/LANE_GATES.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/prompt-history-refs-baseline.json"
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "### 23. Approach justification"}
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "## 23 Review Criteria"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/plan-review-result.md", name: "approach_reinvents"}
  - {kind: "symbol", path: "loomwright/agents/red-team-reviewer.md", name: "Does this reinvent a mechanism the platform, SDK, harness or an existing module already provides?"}
  - {kind: "symbol", path: "loomwright/scripts/test-closed-enum-pins-seam.sh", name: "## 23 Review Criteria"}
  - {kind: "symbol", path: "loomwright/scripts/test-pr-body-evidence-seam.sh", name: "## 23 Review Criteria"}
  - {kind: "symbol", path: "loomwright/scripts/test-rule-conformance-seam.sh", name: "## 23 Review Criteria"}
requires: []
lanes:
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/docs/result-schemas/plan-review-result.md"
  - "loomwright/agents/red-team-reviewer.md"
  - "loomwright/scripts/test-closed-enum-pins-seam.sh"
  - "loomwright/scripts/test-pr-body-evidence-seam.sh"
  - "loomwright/scripts/test-rule-conformance-seam.sh"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "loomwright/scripts/test-design-decisions.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/design-decisions/brief-a-t1-no-section.md"}
  - {kind: "file", path: "loomwright/scripts/fixtures/design-decisions/brief-b-t1-no-rejected.md"}
  - {kind: "file", path: "loomwright/scripts/fixtures/design-decisions/brief-c-reinvention.md"}
  - {kind: "file", path: "loomwright/scripts/fixtures/design-decisions/brief-d-t1-unconfirmed.md"}
  - {kind: "file", path: "loomwright/scripts/fixtures/design-decisions/expected-a.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/design-decisions/expected-b.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/design-decisions/expected-c.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/design-decisions/expected-d.json"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/design-decisions/repo/scripts/propose-common.sh", name: "pc_slugify"}
  - {kind: "file", path: "loomwright/scripts/fixtures/design-decisions/repo/package.json"}
  - {kind: "symbol", path: "docs/evidence/design-decisions.md", name: "--enforcement advisory"}
  - {kind: "file", path: "changelog.d/design-decisions.md"}
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "supervisor-readiness"}
requires:
  - {from: "1", kind: "file", path: "loomwright/skills/supervisor-readiness/design-decisions.md"}
  - {from: "1", kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "### Phase 2.7: APPROACH"}
  - {from: "2", kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "### 23. Approach justification"}
lanes:
  - "loomwright/scripts/test-design-decisions.sh"
  - "loomwright/scripts/fixtures/design-decisions/**"
  - "docs/evidence/design-decisions.md"
  - "changelog.d/design-decisions.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires:
  - "claude CLI with --plugin-dir and -p for the V4–V6 running-system validations"
```

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| launch-pad-side (#1) | `loomwright/skills/supervisor-readiness/SKILL.md` (556), `loomwright/agents/launch-pad.md` (912 — the single authority for Launch Pad phases; the protocol goes to the CREATE split file, only the ≤ 25-line phase stays here), `loomwright/commands/launch-pad.md` (246), `loomwright/scripts/lane-policy.sh` (473), `loomwright/docs/LANE_GATES.md` (102), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1066 — the single home for the gate inventory and budget mirror; one row each appended), `loomwright/docs/prompt-history-refs-baseline.json` (134) | `loomwright/skills/supervisor-readiness/design-decisions.md` (home of the Phase 2.7 protocol) | HIGH |
| reviewer-side (#2) | `loomwright/agents/plan-reviewer.md` (410), `loomwright/docs/result-schemas/plan-review-result.md` (37), `loomwright/agents/red-team-reviewer.md` (451), `loomwright/scripts/test-closed-enum-pins-seam.sh` (262), `loomwright/scripts/test-pr-body-evidence-seam.sh` (325), `loomwright/scripts/test-rule-conformance-seam.sh` (463) | — | HIGH |
| tests-evidence-release (#3) | `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1066, budget mirror rows) | `loomwright/scripts/test-design-decisions.sh` (home of the AC1–AC11 arms; a new test, not appended to a seam test), `loomwright/scripts/fixtures/design-decisions/` (4 briefs, 4 expected JSON, `repo/package.json`, `repo/scripts/propose-common.sh`), `docs/evidence/design-decisions.md`, `changelog.d/design-decisions.md` | HIGH |

Paths outside the item's Touches (asked once at save, `LP-SCOPE`): `loomwright/scripts/lane-policy.sh`, `loomwright/docs/prompt-history-refs-baseline.json`, `loomwright/scripts/fixtures/design-decisions/**`. Why: `lane-policy.sh` is the ONE gate-catalog authority, and `LANE_GATES.md` (in Touches) is generated from it. `prompt-history-refs-baseline.json` needs an entry for every scanned prompt (`check-prompt-history-refs.sh`: "no baseline entry for scanned file … a new runtime prompt needs one"). The fixtures are the AC7 files under "the test's `fixtures/`". No agent-help / README / manifest change: a new file under an existing skill dir is not a new skill.

Module layout: `agents/launch-pad.md` (912) and `ARCHITECTURE_CONTRACTS.md` (1066) are past the 500-line threshold. The launch-pad phase protocol gets its own CREATE module (`design-decisions.md`); only the ≤ 25-line phase entry and pointer lines go into `launch-pad.md`, the single authority for Launch Pad phases. `ARCHITECTURE_CONTRACTS.md` gets one table row each in existing tables, its single home. `lane-policy.sh` (473) and the seam tests stay under the threshold. No helper is copied: the new test reuses the `has`/`lacks` idiom that each seam test defines inline, as every sibling seam test does; no shared module exists for it.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 3
Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (different sections: gate inventory vs budget mirror) | YES (3 requires 1) |
| Subtask 2 | Subtask 3 | none | NO (3 requires 2) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (parallel: disjoint lanes, both `requires: []`)
- **Batch 2:** Subtask 3 (after 1 and 2: it measures their final weights and greps their text)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `launch-pad` agent budget: 617 proxy tokens of headroom at base (not the requirement's 1051), and the preloaded `supervisor-readiness/SKILL.md` edits count against the same row (Feasibility (Phase 2.5)) | HIGH | Byte targets in Subtask 1's notes (≤ 600 bytes into SKILL.md, ≤ 1,800 into the agent); all protocol text goes in the split file; run `check-token-budget.sh` before hand-back; never raise or trim unrelated text; if it still cannot fit, report `blocked: launch_pad_budget` so the owner decides |
| Scope: ~22 files, past `context-bound` (Feasibility (Phase 2.5)) | MEDIUM | 3 subtasks by Part with disjoint batch-1 lanes; subtask 3 sequenced after both |
| A new gate header drifts from the catalog | MEDIUM | The catalog row in `lane-policy.sh` and the regenerated `LANE_GATES.md` land in the same subtask as the ask site; `check-gate-headers.sh` and `test-lane-policy.sh` run before hand-back |
| A missed "22" pin goes red in CI | MEDIUM | The pins are listed literally in §"Touched-file invariants" (including the never-skip list and the `(12–22)` enum line, which the requirement did not name); the subtask 2 notes include the `grep -nE "\b22\b"` sweep |
| The running-system V4 needs an interactive ask that a headless worker cannot show | MEDIUM | V5/V6 run headless; V4 gets no `Verdict:` line unless observed, so `/automate` parks it for the owner (`AUT-WAIVE`); no fabricated verdict |
| False triggers (T4/T5 are judgment calls) | LOW | 23a is MEDIUM (PASS); only 23c, a quoted repo-search hit, FAILs |
| The reviewer re-decides instead of verifying | LOW | Criterion 23 says "verifies claims; never re-decides"; a disputed `rejected:` is not an issue |
| Non-interactive runs accumulate `unconfirmed` T1 entries | LOW | 23d ⇒ NEEDS_HUMAN, the existing `needs_human_non_interactive` park; no new park state |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-12-approach-02-design-decisions.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-12T03:33:53Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/895
- **Branch:** feature/approach-02-design-decisions
- **Files changed:** 33
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unarmed (marker_missing)
- **Summary:** 3/3 subtasks merged (outputs verified 9/9, 7/7, 14/14). Phase 4.5 ran 3 rounds: 2 HIGH fixed (77ed90d), 2 MEDIUM fixed (6f34015), 1 MEDIUM (stale plan-reviewer measured figure) fixed in ff4177a but not re-reviewed (final iteration). 6 findings dismissed (1 drift, 5 below floor). Ground truth 2/2 pass; contract conformance pass; rules gate none; CI pending at every read. V4/V5 have no Verdict line (not observed); V6 PASS observed.

## Not verified
- **Plan Reviewer LLM verdicts on Criterion 23 fixtures a–d** — covered by V4–V6 (subtask 2)
- **live /launch-pad Phase 2.7 run** — covered by V4–V6 (subtask 1)
- **docs/rationale/launch-pad-autonomous.md diagram** — out of lane, not updated (subtask 1)
- **Validation 4 interactive LP-APPROACH ask** — headless worker cannot answer; no Verdict line written (subtask 3)
- **Validation 5 no-trigger line** — headless run printed only final summary; no Verdict line (subtask 3)
- **Plan Reviewer reading design-decisions.md in V-runs** — subagent read the installed marketplace SKILL.md (subtask 3)
