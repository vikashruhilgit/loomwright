# Supervisor Job: Dismissed follow-ups 06b — doc, header and evidence-file drift (23 findings)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (two unrelated worktrees — `wt-842` on `fix-842` in another session's scratchpad and `.claude/worktrees/confident-gagarin-ad5777` on `fix/phase-wait-late-init-session-id` — not touched by this job)
- **Source requirement:** .supervisor/requirements/dismissed-followups/06b-docs-and-evidence-drift.md
- **Base commit:** edcdc2f3d20a23517f77bf0f3c5268cb4236fc67

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown docs, bash 3.2 script headers/strings, existing test suites; no new stack |
| 2 | Dependency Availability | GO | Every fix edits an existing file; F311 reads PR #577's body with `gh pr view` (read-only) |
| 3 | Architecture Fit | GO | Doc/header wording, one emitted string (F358) and one doc-mirror test leg (F196); no gate, merge executor or fail-mode changes |
| 4 | Scope vs Supervisor Capability | CAUTION | 23 findings over ~39 modified files + 3 evidence files + 1 fragment: past one worker's context, so split `context-bound` into 3 zero-overlap groups |
| 5 | Hard Blockers | CAUTION | The F151 heading rename's citation sites (goldens, `MAP.tsv`, `automate-dismissed.sh`, `automate-helpers.d/resume.sh`, two tests, `SKILL.md`, `modes-and-merge-gate.md`, `run-file.md`, `self-heal-advisory/SKILL.md`, `loop-inventory`), the `SKILLS_INDEX.md` / three `SKILL.md` frontmatters (F056, F336), `commands/supervisor.md` (F221), `review-heal-next-step.md`, `test-build-floor.sh`, `test-review-heal-next-step.sh`, the as19 evidence file and the new evidence files sit outside the requirement's `## Touches` — asked once at Phase 6 (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Close the 23 owner-deferred review findings of `dismissed-followups/06b`: re-verify each on the base commit, fix it (with a regression leg where it changes behavior), or record a one-line reason it is not reproducible / not worth fixing.

**Problem Statement:**
The owner needs the 23 `follow-up` findings bundled from 45 `/automate` dismissed drafts acted on, because "follow-up" decisions were never turned into work.
Re-verified by Launch Pad at edcdc2f: 22 are still present (every quoted anchor in `## Touched-file invariants` greps in its file). F156 is half-present: the v17.2.0 CHANGELOG entry still says `so no fix is pushed after a merge`, but no skill prose carries that claim (grep `no fix (is )?pushed` over `loomwright/skills` finds nothing). They are stale restated lists (the done-exit line order, the "nothing written" refusal wording), a heading that misdescribes the READY-park order, script headers that under-describe their own output, a backlog basis string that is inexact, stale dates and paths in indexes and audits, and one evidence file missing its merged-tree re-run.
Success looks like: every finding has one disposition (fixed, or recorded with a reason) in a committed evidence file, the one emitted-string fix has a leg that fails on the base, and CI is green.

**Design (chosen at planning; the evidence file records any deviation with its reason):**
- **Dispositions live in committed evidence files, not in the requirement file** (`.supervisor/requirements/` is gitignored). Each subtask writes `docs/evidence/dismissed-followups-06b-<group>.md` (`loop` / `docs` / `scripts`) with one row per finding it owns: `F<id> | fixed | <file> (<what changed>)[ :: <test file> <leg>]` or `F<id> | recorded | <one-line reason>`, plus the re-verify command it ran on the base commit.
- **F151 / F153 / F154 — rename the heading, mechanically, everywhere it is cited.** `### Dismissed-findings decision step (before the park)` becomes `### Dismissed-findings decision step` in `skills/automate-loop/per-item-loop.md` and in `skills/automate-loop/SKILL.md`'s index heading. Every citation is updated in the same commit by replacing the substring `decision step (before the park)` with `decision step` (this also catches the line-wrapped copies whose `Dismissed-findings` sits on the previous line: `automate-dismissed.sh` header, `automate-next-step.sh` header, `automate-helpers.d/resume.sh`) and the one comment split after `(before the` in `fixtures/automate-golden/MAP.tsv`. Three places are deliberately NOT rewritten: `CHANGELOG.md` (release history), `docs/evidence/as22-split-big-commands.md` (a dated evidence record) and `loomwright/scripts/fixtures/automate-golden/gate-validation-waive/tree/dot-supervisor/requirements/automate-speed/01-question-gates-dont-stall.md` (a frozen requirement fixture — data, not a citation). The goldens `fixtures/automate-helpers-help/{hdr-trail,resume}.golden` change byte-for-byte with their `#:` rows. `MAP.tsv`'s slug `dismissed-findings-decision-step` is unchanged.
- **F349 — add the `process registry:` line to the restated done-exit sequence:** `docs/result-schemas/automate-run.md`'s `done` row reads `(trail-pr --reason done, then the process registry: line, then the dry sweep line are written)`; `docs/loop-inventory/automate-loop.md` AL-295's and AL-556's expected-behavior cells name the same three lines in that order. Anchors (`q:`/`h:` cells) are not touched.
- **F064** — `per-item-loop.md` §8's `escalated` bullet gains one clause: the merge watcher armed at the park (§6 "Post-merge close-out") re-checks the PR and runs `closeout` on a merge.
- **F140** — `helpers.md`'s `sweep` row gives fleet-closeout's line form separately: `<ts> sweep (dry run): <summary>` for §6 "Termination" and `finalize-empty`; `fleet closeout sweep (dry run): <summary>` for `fleet-closeout`.
- **F258** — the three restated copies (`skills/automate-loop/SKILL.md` step 4, `docs/result-schemas/supervisor-result.md` "Nested-object key sets", `skills/self-heal-advisory/completion-tail.md`'s ground_truth comment) say `nothing written to the run file` (the authority, `automate-run.md` §"Writers and failures", keeps its ONE-exception sentence).
- **F174** — `commands/automate.md`'s branch-mode row drops `equivalently` and reads `(… or `setup-memory.sh mode` prints `on <branch>` or `unknown`)`; the trigger itself is unchanged.
- **F052** — `skills/autonomous-loop/SKILL.md` PLAN step 1 drops the `or, at Phase 6 PASS, save nothing (save_requires_flag_non_interactive)` clause: inline on the main thread, a headless no-flag run only hangs on the ask (the save-nothing branch is the subagent case).
- **F150** — `docs/command-parts/agent-help/ops.md`'s `/rules` entry adds one clause: a `must` rule added with `--check` needs `--proof <the PROVEN proof from prove-rule-check.sh>` (`add-rule.sh` refuses it otherwise). `commands/agent-help.md` only points to ops.md and is not changed.
- **F221** — `commands/supervisor.md`'s `--sdk-runner` row cites `skills/async-orchestration/finalize.md` steps 1–7 instead of `skills/async-orchestration/SKILL.md Part 2, steps 1–7`; `test-system-contract.sh` section 20's failure message names `self-heal-advisory/completion-tail.md` (the file `$SK` points at).
- **F275** — `docs/rationale/subagents.md` relabels the two rows whose one-liner no longer exists (code-reviewer `Standard Output Format`, worker `Common skills`) from `kept-as-one-line` to their real disposition (`removed`, with the home the content now has — the worker reads it in the agent files at its base).
- **F056 / F336** — `lastUpdated` in `skills/qa-gates/SKILL.md`, `skills/qa-test-patterns/SKILL.md` and `skills/agent-teams/SKILL.md` frontmatter is set to the date of the last real edit of that skill dir (`git log -1 --format=%cs -- loomwright/skills/<dir>` at base: 2026-07-02, 2026-07-02, 2026-10-23), kept in each file's existing format (`"YYYY-MM"` for the two qa skills, `"YYYY-MM-DD"` for agent-teams); the matching `SKILLS_INDEX.md` rows' Last Updated cells match (regenerated with `scripts/check-skills-index-sync.sh --write` if that generator owns the cell, else hand-edited); `version:` is not bumped (no content change).
- **F086** — `docs/TELEMETRY.md`'s token-ledger sentence (`firings of one completion sum its transcript once, in one line, whatever their ts`) is qualified: `… unless the lock wait times out (the append then proceeds unguarded and a duplicate line is possible)`.
- **F301** — `docs/POINTER_AUDIT.md` row 17 points to `skills/autonomous-loop/multi-iteration.md` §"Signal 1 …" and §"Signal 2 …" by section anchor (no line numbers); row 15 points to `skills/autonomous-loop/multi-iteration.md` §"EVALUATE review-heal step (chained PR review-and-heal — fresh isolated Task context)" by section anchor (the real home of the Task step; `SKILL.md`'s heading of that name is only a pointer stub).
- **F311** — `docs/evidence/as19-split-lanes-and-trail-scripts.md` §6 gains the merged-tree AC11 re-run copied verbatim from PR #577's body (`gh pr view 577 --json body`), with its commit; if the body carries no such re-run, F311 is `recorded` (`the merged-tree AC11 re-run is not in the PR body either`) and §6 is unchanged.
- **F156 — recorded + one clause:** CHANGELOG history is not rewritten and no skill prose carries the claim; the PR's changelog fragment carries one clarifying sentence (the v17.2.0 "no fix is pushed after a merge" means after an observed merge — a merge landing after `park-ask-gate`'s read is not prevented).
- **F046** — `ci-slot.sh` header: the Layout line names the 6th line a held ticket carries (its hold reason, read by `rec_field tickets/<n> 6`), and the `status [--json]` usage line names the machine view and the `machine` / `held` `--json` keys (the worker reads the keys from `status`'s `--json` emitter at its base).
- **F047** — `machine-load.sh` header: `--json` is `one object with the same keys plus busy_at and overloaded_at`.
- **F352** — `proc-registry.sh` header: `LOOMWRIGHT_PROC_PS_SNAPSHOT` is a production input (`janitor-report.sh` passes its one shared snapshot) as well as a test seam.
- **F358 — the emitted basis string is corrected:** `build-floor.sh`'s `backlog_basis` ends `… reads unknown or its open-path state, not merged_unstamped` (backlog.sh steps 1–4 can still classify such an item `in_flight` / `brief_shipped` offline; only step 5's `open` collapses to `unknown`). New leg in `test-build-floor.sh` asserts the projection's `backlog` surface basis contains `unknown or its open-path state`.
- **F196 — the doc sentence is corrected and the header list is pinned:** the header's `STEPS` block stays (it is what `script:review-heal-next-step.sh <step>` inventory homes cite); `docs/result-schemas/review-heal-next-step.md`'s sentence reads that `skills/review-heal/SKILL.md` points here and does not restate the step list, while the driver's header keeps a one-line-per-step `STEPS` index held equal to this file's step table by `test-review-heal-next-step.sh`. New D leg there: the step names in the header's `STEPS` block (lines `#   <name>  …` between `# STEPS` and the next blank `#` section) equal the driver's case arms (`$ARMS`), in order.

## Acceptance Criteria

**Every finding (all subtasks)**
- [ ] AC1. Given a finding this brief assigns to a subtask, when the worker starts, then it re-runs the finding's anchor check on its own base (the `grep -nF` of the quoted anchor in `## Touched-file invariants` or in the Design bullet) and a committed evidence file `docs/evidence/dismissed-followups-06b-<group>.md` (`loop` / `docs` / `scripts`) contains, per finding, the check run and exactly one disposition: `fixed` naming the file and the change (and the test leg, where one exists), or `recorded` with a one-line reason; the PR body links to the three files.
- [ ] AC2. Given a finding dispositioned `fixed` that changes behavior (F358 — an emitted string) or adds a pin (F196), when its new leg runs against the base-commit version of the script or doc (`git show edcdc2f:<path>` copied into a scratch dir beside the suite's fixtures, or for F196 a scratch copy of the driver with one extra `STEPS` row), then the leg fails, and it passes on the fixed tree — the leg name and the red result are listed in the evidence file. Doc-, header- and comment-only fixes carry no leg and say so in their row.

**Subtask 1 — automate-loop docs and the heading rename (`loop`)**
- [ ] AC3 (F151, F153, F154). Given the fixed tree, when `grep -rnF 'decision step (before the park)' loomwright/ docs/ CLAUDE.md AGENT_GUIDELINES.md` runs (and `grep -rnE 'decision step \(before( the)?$' loomwright/`), then it prints only lines in `CHANGELOG.md`, `docs/evidence/as22-split-big-commands.md` and the frozen fixture `…/gate-validation-waive/…/01-question-gates-dont-stall.md`; `per-item-loop.md` and `skills/automate-loop/SKILL.md` each carry `### Dismissed-findings decision step`; `test-loop-inventory.sh`, `test-automate-dismissed.sh`, `test-automate-next-step.sh`, `test-automate-helpers-dispatch.sh` (the `hdr-trail` / `resume` goldens) and the automate-golden suite stay green.
- [ ] AC4 (F349). Given `docs/result-schemas/automate-run.md`'s `done` row and `docs/loop-inventory/automate-loop.md` rows AL-295 and AL-556, when read, then each names `trail-pr --reason done`, the `process registry:` line and the dry sweep line, in that order, matching `per-item-loop.md`'s done-exit sentence.
- [ ] AC5 (F064, F140, F258, F174). Given the fixed tree, when read: `per-item-loop.md`'s `escalated` bullet names the merge watcher armed at the park re-checking the PR and running `closeout` on a merge; `helpers.md`'s `sweep` row gives `fleet closeout sweep (dry run): <summary>` as fleet-closeout's form, apart from `<ts> sweep (dry run): <summary>`; `skills/automate-loop/SKILL.md` step 4, `supervisor-result.md` and `completion-tail.md` say `nothing written to the run file`; `commands/automate.md`'s branch-mode row has no `equivalently` and names the `unknown` mode.

**Subtask 2 — other doc surfaces and evidence (`docs`)**
- [ ] AC6 (F052, F150, F221 part 1, F275). Given the fixed tree, when read: `skills/autonomous-loop/SKILL.md` PLAN step 1 no longer says an inline no-flag headless run saves nothing; `ops.md`'s `/rules` entry names the `--proof` requirement for a `must` add with `--check`; `commands/supervisor.md`'s `--sdk-runner` row cites `skills/async-orchestration/finalize.md`; `docs/rationale/subagents.md` labels no row `kept-as-one-line` whose line is absent from its agent file.
- [ ] AC7 (F056, F336). Given `qa-gates`, `qa-test-patterns` and `agent-teams` `SKILL.md`, when read, then `lastUpdated` is the month (resp. date) of the dir's last real edit at base and the `SKILLS_INDEX.md` rows agree; `bash scripts/check-skills-index-sync.sh` passes.
- [ ] AC8 (F086, F301, F311). Given the fixed tree, when read: `TELEMETRY.md`'s token-ledger sentence names the lock-wait-timeout duplicate; `POINTER_AUDIT.md` rows 15 and 17 both name `skills/autonomous-loop/multi-iteration.md` by section anchor, with no line numbers; `as19-split-lanes-and-trail-scripts.md` §6 carries the merged-tree AC11 result copied from PR #577's body, or the evidence file records F311 with the reason.

**Subtask 3 — script headers, the basis string, the doc-mirror pin and the fragment (`scripts`)**
- [ ] AC9 (F046, F047, F352). Given `ci-slot.sh --help` and `machine-load.sh --help` (each prints its header) and `proc-registry.sh`'s header, when read, then ci-slot names the held ticket's 6th line and the `status --json` machine/held keys, machine-load names `busy_at` / `overloaded_at` as `--json`-only, and proc-registry names `LOOMWRIGHT_PROC_PS_SNAPSHOT` as a production input from `janitor-report.sh` as well as a test seam; `test-ci-slot.sh`, `test-machine-load.sh`, `test-proc-registry.sh` stay green.
- [ ] AC10 (F358). Given `build-floor.sh` run over the `test-build-floor.sh` fixtures, when the `backlog` surface is read, then its basis contains `unknown or its open-path state` — new leg in `loomwright/scripts/test-build-floor.sh`, red on the base-commit `build-floor.sh`.
- [ ] AC11 (F196, F221 part 2). Given `docs/result-schemas/review-heal-next-step.md`, when read, then it no longer says the driver's header does not restate the step list, and names the header's `STEPS` index and the leg that holds it equal; given `test-review-heal-next-step.sh`, when it runs, then a D leg asserts the header `STEPS` names equal `$ARMS` in order (red on a scratch driver copy with one extra `STEPS` row); `test-system-contract.sh` section 20's failure message names `completion-tail.md`.
- [ ] AC12 (F156). Given the evidence file, when read, then F156 is `recorded` (history not rewritten; no skill-prose copy at base — the grep shown) and the changelog fragment carries the one clarifying sentence.

**Validation**
- [ ] V1. `bash scripts/ci-local.sh --affected` passes for each subtask's files, including `check-prompt-history-refs.sh` (no finding id, PR number or incident story added to any prompt file — the F-ids and PR numbers live only in the evidence files), `check-token-budget.sh` (the rename shortens `automate-loop`; `autonomous-loop`, `agent-help`, `automate`, `supervisor` and `self-heal-advisory` edits are one clause each, well under their headroom), `test-citation-drift.sh` (no bare `file:N` in new prose — F301 removes line numbers) and `check-doc-currency.sh`.
- [ ] V2. `bash scripts/check-version-bump.sh` passes; the PR carries `changelog.d/dismissed-followups-06b-docs-and-evidence-drift.md` and no hand-edited version file.

## Scope widening
- docs/evidence/as19-split-lanes-and-trail-scripts.md
- docs/evidence/dismissed-followups-06b-docs.md
- docs/evidence/dismissed-followups-06b-loop.md
- docs/evidence/dismissed-followups-06b-scripts.md
- loomwright/commands/supervisor.md
- loomwright/docs/loop-inventory/automate-loop.md
- loomwright/docs/result-schemas/review-heal-next-step.md
- loomwright/scripts/automate-dismissed.sh
- loomwright/scripts/automate-helpers.d/resume.sh
- loomwright/scripts/automate-helpers.sh
- loomwright/scripts/fixtures/automate-golden/MAP.tsv
- loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden
- loomwright/scripts/fixtures/automate-helpers-help/resume.golden
- loomwright/scripts/test-automate-dismissed.sh
- loomwright/scripts/test-automate-next-step.d/12-dismissed-batch.sh
- loomwright/scripts/test-build-floor.sh
- loomwright/scripts/test-review-heal-next-step.sh
- loomwright/skills/SKILLS_INDEX.md
- loomwright/skills/agent-teams/SKILL.md
- loomwright/skills/automate-loop/SKILL.md
- loomwright/skills/automate-loop/modes-and-merge-gate.md
- loomwright/skills/automate-loop/run-file.md
- loomwright/skills/qa-gates/SKILL.md
- loomwright/skills/qa-test-patterns/SKILL.md
- loomwright/skills/self-heal-advisory/SKILL.md
- accepted: LP-SCOPE 2026-11-10

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| loop (Subtask 1) | `loomwright/skills/automate-loop/per-item-loop.md` (123), `loomwright/skills/automate-loop/SKILL.md` (343), `loomwright/skills/automate-loop/helpers.md` (62), `loomwright/skills/automate-loop/modes-and-merge-gate.md` (59), `loomwright/skills/automate-loop/run-file.md` (84), `loomwright/commands/automate.md` (125), `loomwright/skills/self-heal-advisory/SKILL.md` (447), `loomwright/skills/self-heal-advisory/completion-tail.md` (522 — one comment line), `loomwright/docs/result-schemas/automate-run.md` (163), `loomwright/docs/result-schemas/supervisor-result.md` (235), `loomwright/docs/loop-inventory/automate-loop.md` (806 — cells edited in place), `loomwright/scripts/automate-helpers.sh` (1256 — one `#:` row's comment), `loomwright/scripts/automate-helpers.d/resume.sh` (405 — comments), `loomwright/scripts/automate-next-step.sh` (3966 — comments), `loomwright/scripts/automate-dismissed.sh` (1109 — header comment), `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden` (13), `loomwright/scripts/fixtures/automate-helpers-help/resume.golden` (3), `loomwright/scripts/fixtures/automate-golden/MAP.tsv` (87), `loomwright/scripts/test-automate-dismissed.sh` (1440 — strings edited in place), `loomwright/scripts/test-automate-next-step.d/12-dismissed-batch.sh` (370 — comment) | `docs/evidence/dismissed-followups-06b-loop.md` | HIGH |
| docs (Subtask 2) | `loomwright/skills/autonomous-loop/SKILL.md` (435), `loomwright/docs/command-parts/agent-help/ops.md` (109), `loomwright/commands/supervisor.md` (236), `loomwright/docs/rationale/subagents.md` (1265 — two cells), `loomwright/skills/SKILLS_INDEX.md` (82), `loomwright/skills/qa-gates/SKILL.md` (526 — frontmatter), `loomwright/skills/qa-test-patterns/SKILL.md` (884 — frontmatter), `loomwright/skills/agent-teams/SKILL.md` (298), `loomwright/docs/TELEMETRY.md` (2608 — one sentence), `loomwright/docs/POINTER_AUDIT.md` (195), `docs/evidence/as19-split-lanes-and-trail-scripts.md` (317) | `docs/evidence/dismissed-followups-06b-docs.md` | HIGH |
| scripts (Subtask 3) | `loomwright/scripts/ci-slot.sh` (666 — header), `loomwright/scripts/machine-load.sh` (127 — header), `loomwright/scripts/proc-registry.sh` (987 — header), `loomwright/scripts/build-floor.sh` (1391 — one string), `loomwright/scripts/test-build-floor.sh` (3244 — leg appended), `loomwright/scripts/test-system-contract.sh` (1074 — one message), `loomwright/docs/result-schemas/review-heal-next-step.md` (113 — one sentence), `loomwright/scripts/test-review-heal-next-step.sh` (1358 — leg appended in the E/D block) | `docs/evidence/dismissed-followups-06b-scripts.md`, `changelog.d/dismissed-followups-06b-docs-and-evidence-drift.md` | HIGH |

New responsibilities get no new module: every fix is a wording change inside the surface that owns it, a single emitted string, or one assertion appended to the suite that already pins that surface (the `D` block of `test-review-heal-next-step.sh` already compares the doc's step table to `$ARMS`; the F358 leg reuses `test-build-floor.sh`'s existing fixtures and `ok`/`no` helpers), so appending to the large files is the single-authority form. No helper is copied. Not modified although listed in the requirement's Touches: `CHANGELOG.md` (history, F156), `agents/launch-pad.md` (F052's authority is already correct), `scripts/add-rule.sh` / `prove-rule-check.sh` (F150 documents their existing contract), `automate-helpers.d/backlog.sh` / `session-resume.sh` / `floor-projection.md` (F358's correct side), `janitor-report.sh` (F352's correct side), `review-heal-next-step.sh` (F196 keeps its header), `setup-memory.sh` (F174 documents it), `async-orchestration/finalize.md` (F221's target), `automate-loop/branch-mode.md` (F174's row lives in `commands/automate.md`), `autonomous-loop/multi-iteration.md` (F301's target).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

## Touched-file invariants

> Grounded at base `edcdc2f3d20a23517f77bf0f3c5268cb4236fc67`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/skills/automate-loop/per-item-loop.md`** — keep: every line `test-automate-dismissed.sh` reads by `first_line` / `before` / `case`, in its current order — in particular `**PICK-time pending-decisions ask (automate-followups/12` (step 1, which names the decision step) and the done-exit sentence (`On the **\`## Status: done\`** exit ONLY, the loop runs \`trail-pr --reason done\``, quoted by loop-inventory AL-295's `q:` anchor, so it is NOT reworded); only the heading suffix ` (before the park)` is dropped wherever it occurs, and §8's `escalated` bullet (`- **\`escalated\`:** the run stays **paused**`) gains F064's one clause. Pinned by: `loomwright/scripts/test-automate-dismissed.sh`, `loomwright/scripts/test-loop-inventory.sh` (HEADING COVERAGE, LIVE ANCHORS), the automate-golden suite (`MAP.tsv` heading → golden).
- **`loomwright/skills/automate-loop/SKILL.md`** — keep: the index heading stays a pointer (`See [per-item-loop.md](per-item-loop.md).`) under the renamed `### Dismissed-findings decision step`; step 4's sentence keeps its shape and only `exit 2 is a refusal with nothing written` gains ` to the run file` (F258); the anti-pattern bullet (`**Parking with dismissed findings nobody decided on — or holding the park for them.**`) keeps its order. Pinned by: `loomwright/scripts/test-automate-loop-split.sh`, `test-loop-inventory.sh`, `test-automate-dismissed.sh`.
- **`loomwright/skills/automate-loop/modes-and-merge-gate.md`** — keep: the order the §9 legs of `test-automate-dismissed.sh` assert — `- **Safe mode (default):**`, then `otherwise fail **CLOSED**`, then `**\`ESCALATED\` never merges and PARKS the run**`, whose line must still name the decision step before `## Status: paused`; only ` (before the park)` is dropped. Pinned by: `loomwright/scripts/test-automate-dismissed.sh` (`B: §9 escalated park still runs the decision step before the park write`).
- **`loomwright/scripts/automate-helpers.sh`** — keep: everything but the comment text of ONE `#:` row; the row `#:  dismissed-drafts <runfile> <item> <pr_url> [--after-fix-now]  # §6 "Dismissed-findings decision step (before the park)"` loses ` (before the park)` and nothing else; the merge executor and `gate-eval` are not touched. Mirror: `loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden` (`  dismissed-drafts <runfile> <item> <pr_url> [--after-fix-now]  # §6 "Dismissed-findings decision step (before the park)"`) edited identically. Pinned by: `loomwright/scripts/test-automate-helpers-dispatch.sh` (each `#:  ` row byte-for-byte in its segment's golden).
- **`loomwright/scripts/automate-helpers.d/resume.sh`** — keep: code untouched; the `#:` row `#:  park-ask-gate    <runfile> <item> <pr_url> [--wait <s>]  # §6 "Dismissed-findings decision step (before the park)"` and the wrapped comment `# decision step (before the park)", its "Order — sequential interactive READY park (park` lose ` (before the park)`. Mirror: `fixtures/automate-helpers-help/resume.golden`. Pinned by: `test-automate-helpers-dispatch.sh`.
- **`loomwright/scripts/automate-next-step.sh`** — keep: code and the header `STEPS` list untouched; only the comments `# skills/automate-loop/per-item-loop.md §"Dismissed-findings decision step (before the park)"`, `#               decision step (before the park)"` and `#               findings decision step (before the park)" — the rule, written once there)` change. Pinned by: `loomwright/scripts/test-automate-next-step.sh` (its D doc-mirror leg reads the case arms, not these comments).
- **`loomwright/scripts/automate-dismissed.sh`** — keep: code untouched; header line `# decision step (before the park)" — the THRESHOLD rule, the ask order, fix-now` loses ` (before the park)`. Pinned by: `loomwright/scripts/test-automate-dismissed.sh`.
- **`loomwright/scripts/test-automate-dismissed.sh`** — keep: every leg; the section extractor `SUBH="### Dismissed-findings decision step (before the park)"` and the case patterns quoting the heading change to the new text in the same commit as the heading (the test-integrity guard: an assertion's text changes, none is removed).
- **`loomwright/scripts/test-automate-next-step.d/12-dismissed-batch.sh`** — keep: every leg; only the header comment `# §"Dismissed-findings decision step (before the park)"). Sourced by the runner` changes.
- **`loomwright/scripts/fixtures/automate-golden/MAP.tsv`** — keep: the slug column (`dismissed-findings-decision-step`); the key `per-item-loop.md|Dismissed-findings decision step (before the park)` becomes `per-item-loop.md|Dismissed-findings decision step` and the comment `# per-item-loop.md|Rate-limit park (end of RUN, before DRAIN) and Dismissed-findings decision step (before the` is re-wrapped to the new heading. Pinned by: the automate-golden suite (the heading → golden map).
- **`loomwright/docs/loop-inventory/automate-loop.md`** — keep: nine cells per row, ids, kinds, homes and `q:` anchors unchanged; the `h: ### Dismissed-findings decision step (before the park)` anchors of AL-312 and AL-567 follow the heading; AL-295's (`` `trail-pr --reason done`, then one dry-run `sweep` summary line, then release ``) and AL-556's (`(trail-pr --reason done + the dry sweep line)`) expected-behavior cells gain the `process registry:` line. Pinned by: `loomwright/scripts/test-loop-inventory.sh` (HEADING COVERAGE, LIVE ANCHORS).
- **`loomwright/scripts/ci-slot.sh`** — keep: code untouched (`rec_field() { sed -n "${2}p" "$1" 2>/dev/null; }`); `--help` prints the header (`awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }'`), so the header stays one contiguous `#` block; fix sites `#        ci-slot.sh status [--json]   holders (slot, pid, checkout, name, started) + waiters in order` and `#                  pid, checkout path, name, start epoch; a ticket adds a fifth, the waiter's N.` Pinned by: `loomwright/scripts/test-ci-slot.sh`.
- **`loomwright/scripts/machine-load.sh`** — keep: the emitter `printf '{"load1":%s,"cpus":%s,"load_per_cpu":%s,"mem_pressure":"%s","mem_source":"%s","state":"%s","busy_at":%s,"overloaded_at":%s}\n'` and exit codes (`ALWAYS exit 0 on a`); fix site `mem_source, the raw memory reading). --json: one object with the same keys; a value that`. Pinned by: `loomwright/scripts/test-machine-load.sh`.
- **`loomwright/scripts/proc-registry.sh`** — keep: code untouched, the hermetic skip (`HERMETIC SCAN SKIP: under HERMETIC_TEST_ENV=1 with LOOMWRIGHT_PROC_PS_SNAPSHOT unset`); fix site `#       Test seam: LOOMWRIGHT_PROC_PS_SNAPSHOT=<file> is read IN PLACE of running ps (same columns).` Mirror: `janitor-report.sh`'s `A caller's LOOMWRIGHT_PROC_PS_SNAPSHOT is used instead`. Pinned by: `loomwright/scripts/test-proc-registry.sh`.
- **`loomwright/scripts/build-floor.sh`** — keep: `backlog` stays the one surface it does not parse itself; the three `add_surface "backlog" "$REQ_DIR" "$backlog_basis"` calls unchanged; fix site the tail of `backlog_basis=` (`so an item whose only merge evidence is a merged PR reads unknown, not merged_unstamped`). Mirror: `docs/result-schemas/floor-projection.md` (`it reads \`unknown\` (or its open-path state)`) and `session-resume.sh` (`` (`unknown` or its ``). Pinned by: `loomwright/scripts/test-build-floor.sh` (`add_surface "backlog" "$REQ_DIR" "$backlog_basis" "counted" "$bl_count"` mutants BLM1/BLM2).
- **`loomwright/scripts/test-build-floor.sh`** — keep: every leg; the new leg reuses `ok()   { echo "  ok: $1";        pass=$((pass+1)); }` / `no()` and the suite's existing requirement fixtures.
- **`loomwright/scripts/test-system-contract.sh`** — keep: `SK="$(cd "$HERE/../.." && pwd)/loomwright/skills/self-heal-advisory/completion-tail.md"`; fix site `no "(20) self-heal-advisory/SKILL.md not readable at $SK — this section would assert nothing"`.
- **`loomwright/scripts/test-review-heal-next-step.sh`** — keep: the E/D block's `ARMS="$(sed -n '/^rh_dispatch() {/,/^}/p' "$DRIVER" | sed -n 's/^    \([a-z-]*\)) rh_.*/\1/p')"` and the existing `D: the doc's step table equals the driver's case arms, in order` leg; the new leg sits beside it and reads the header between `# STEPS — each is ONE \`case\` arm of rh_dispatch` and the end of that comment block. Mirror: `review-heal-next-step.sh`'s header (not modified).
- **Appended-only / in-place-text test files** — no assertion is removed; `test-automate-dismissed.sh`'s heading strings change with the heading (rename, not removal).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-build-floor.sh` — F358 backlog basis names `unknown or its open-path state` | flip the `backlog_basis` tail back to `reads unknown, not merged_unstamped` in `loomwright/scripts/build-floor.sh` |
| `loomwright/scripts/test-review-heal-next-step.sh` — F196 header `STEPS` names equal the case arms | add a row `#   bogus       x` to the `STEPS` block of a scratch copy of `loomwright/scripts/review-heal-next-step.sh` |
| `loomwright/scripts/test-loop-inventory.sh` — the renamed heading is covered | revert `### Dismissed-findings decision step` to the old heading in `loomwright/skills/automate-loop/per-item-loop.md` only |
| `loomwright/scripts/test-automate-dismissed.sh` — the renamed heading is extracted (`SUBH`) and quoted by the §9 / PICK order legs | revert `### Dismissed-findings decision step` to the old heading in `loomwright/skills/automate-loop/per-item-loop.md` only (the `SUBH` extraction and the `before`/`case` legs naming the heading turn red) |
| `loomwright/scripts/test-automate-helpers-dispatch.sh` — `hdr-trail.golden` matches the renamed `#:` row | revert the `dismissed-drafts` `#:` row's comment in `loomwright/scripts/automate-helpers.sh` only |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Automate-loop docs and the decision-step heading rename (F151 F153 F154 F349 F064 F140 F258 F174) | AC1, AC2, AC3–AC5, V1 | 20 modify, 1 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Other doc surfaces and the as19 evidence (F052 F150 F221-doc F275 F056 F336 F086 F301 F311) | AC1, AC6–AC8, V1 | 11 modify, 1 create | — | LAUNCHABLE |
| 3 | Script headers, backlog basis, review-heal doc mirror, fragment (F046 F047 F352 F358 F196 F221-test F156) | AC1, AC2, AC9–AC12, V1, V2 | 8 modify, 2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-06b-loop.md"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "then the process registry: line"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/helpers.md", name: "fleet closeout sweep (dry run)"}
requires: []
lanes:
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/automate-loop/helpers.md"
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"
  - "loomwright/skills/automate-loop/run-file.md"
  - "loomwright/commands/automate.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/self-heal-advisory/completion-tail.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/resume.sh"
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/automate-dismissed.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/hdr-trail.golden"
  - "loomwright/scripts/fixtures/automate-helpers-help/resume.golden"
  - "loomwright/scripts/fixtures/automate-golden/MAP.tsv"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/test-automate-next-step.d/12-dismissed-batch.sh"
  - "docs/evidence/dismissed-followups-06b-loop.md"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-06b-docs.md"}
  - {kind: "symbol", path: "loomwright/docs/POINTER_AUDIT.md", name: "Signal 2"}
  - {kind: "symbol", path: "loomwright/docs/command-parts/agent-help/ops.md", name: "prove-rule-check.sh"}
requires: []
lanes:
  - "loomwright/skills/autonomous-loop/SKILL.md"
  - "loomwright/docs/command-parts/agent-help/ops.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/docs/rationale/subagents.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/skills/qa-gates/SKILL.md"
  - "loomwright/skills/qa-test-patterns/SKILL.md"
  - "loomwright/skills/agent-teams/SKILL.md"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/docs/POINTER_AUDIT.md"
  - "docs/evidence/as19-split-lanes-and-trail-scripts.md"
  - "docs/evidence/dismissed-followups-06b-docs.md"
external_requires:
  - "gh pr view 577 --json body (read-only, for F311)"

# Subtask 3
provides:
  - {kind: "file", path: "docs/evidence/dismissed-followups-06b-scripts.md"}
  - {kind: "file", path: "changelog.d/dismissed-followups-06b-docs-and-evidence-drift.md"}
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "open-path state"}
requires: []
lanes:
  - "loomwright/scripts/ci-slot.sh"
  - "loomwright/scripts/machine-load.sh"
  - "loomwright/scripts/proc-registry.sh"
  - "loomwright/scripts/build-floor.sh"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/scripts/test-system-contract.sh"
  - "loomwright/docs/result-schemas/review-heal-next-step.md"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "docs/evidence/dismissed-followups-06b-scripts.md"
  - "changelog.d/dismissed-followups-06b-docs-and-evidence-drift.md"
external_requires: []
```

Subtask 3's fragment is the PR's only `changelog.d/` entry and covers all three groups at the group level (one clause per group, plus F156's clarifying sentence; no per-finding fixed/recorded counts, so a sibling's fix→recorded deviation leaves it true). The version bump is folded by `bash scripts/bump-version.sh` at release, never hand-edited.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
Subtask 2 (independent)
Subtask 3 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO |
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 3 | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2, Subtask 3 (parallel)
- **Recommended workers:** 3
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |
| 2 | — (doc edits only) |
| 3 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 23 findings over ~43 files exceed one worker's context | MEDIUM | `context-bound` split into 3 zero-overlap groups; each writes its own evidence file |
| Feasibility (Phase 2.5): the rename's citation sites, the skill frontmatters, `commands/supervisor.md`, `review-heal-next-step.md`, two test files and the evidence files sit outside the requirement's `## Touches` | MEDIUM | Asked once at Launch Pad Phase 6 (`LP-SCOPE`) before save |
| Prior churn (postmortem ledger): `SKILLS_INDEX.md`, `automate-helpers.sh`, `skills/automate-loop/SKILL.md`, `self-heal-advisory/SKILL.md` and others carry prior churn (`drain_churn`, `self_heal_churn`, `convention_mismatch`), with a `self_heal_miss` in prior rounds | HIGH | Each doc edit is one clause in place, or a pointer instead of a restatement (the two advisory house rules); the rename is one mechanical substring replace verified by a repo-wide grep (AC3) and by the suites that pin the heading (inventory, dismissed, dispatch goldens); workers run `ci-local.sh --affected` including the doc gates before hand-back |
| The heading rename misses a line-wrapped citation (the phrase split across two comment lines) | MEDIUM | AC3's second grep (`decision step \(before( the)?$`) catches a copy split after `(before` / `(before the`; the worker also greps `before the park)` at line start |
| The rename rewrites the frozen golden fixture requirement and changes a golden output | LOW | That fixture is excluded by design; AC3 lists it as an expected remaining hit |
| F056/F336 `lastUpdated` is consumed by a generator (`check-skills-index-sync.sh --write`) that rewrites more than the three rows | LOW | Run the gate first; if `--write` changes any other row, hand-edit the three cells instead and record it |
| F311 depends on PR #577's body carrying the merged-tree re-run | LOW | The fallback disposition (`recorded` with the reason) is pre-decided in the Design |
| Pre-fix-red proof (AC2) needs the base-commit script | LOW | Run the F358 leg against `git show edcdc2f:loomwright/scripts/build-floor.sh` in a scratch dir; F196's mutant is a scratch driver copy; record each red line in the evidence file |
| A concurrent session in this checkout can sweep uncommitted edits (project memory) | LOW | Workers run in their own worktrees; commit per group |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 1
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-10-dismissed-followups-06b-docs-drift.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-10T13:54:14Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/875
- **Branch:** feature/dismissed-followups-06b-docs-drift
- **Files changed:** 46
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** 23 findings of dismissed-followups 06b dispositioned across 3 parallel subtasks (loop / docs / scripts) with evidence files; v17.35.4 fold. Phase 3 resumed via the legacy --continue path after the Execute Manager's wait budget checkpointed with workers still running. Pre-push integrated check found and fixed one unresolved evidence citation (test-automate-loop-split.sh G). Phase 4.5 review PASS on first pass; 1 LOW pre_existing finding dismissed (review-heal-next-step.sh header wording). Brief pin-mutation rows are prose, so run-pin-mutations.sh reported all 5 unverified; reviewer re-verified rows 1–2 held, rows 3–5 rely on the worker's own scratch runs.

## Not verified
- **F156 changelog clarifying sentence (merge after park-ask-gate read not prevented)** — brief's pre-decided wording, checked only against resume.sh's header text; the race is not reproducible without a live gh PR (subtask 3)
