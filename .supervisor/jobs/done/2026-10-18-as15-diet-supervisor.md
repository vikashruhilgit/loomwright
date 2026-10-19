# Supervisor Job: Prompt diet — Supervisor and self-heal-advisory carry rules, not stories (automate-speed/15)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L16 (lane L16 clone of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/15-diet-supervisor.md
- **Base commit:** 3a03dfa66d7de22ff93b0327affa60aa752948d2

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt files + bash 3.2 tests; no new stack |
| 2 | Dependency Availability | GO | No new dependency; `test-loop-inventory.sh` already resolves `rationale:` / `global` / `step-scoped` homes (added by automate-speed/13) |
| 3 | Architecture Fit | GO | Same shape as the merged automate-speed/13 diet (commits `490927a`, `e01e7e1`): rationale doc + load-by-mode split file + inventory re-homing |
| 4 | Scope vs Supervisor Capability | CAUTION | ~391 KB of prompt text and 745 inventory rows; > 800 changed lines ⇒ `context-bound` split into 4 serialized subtasks |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** CAUTION

## Task
**Goal:** Cut the Supervisor loop group's runtime prompts (`agents/supervisor.md`, `commands/supervisor.md`, `skills/self-heal-advisory/SKILL.md`, `skills/async-orchestration/SKILL.md`) to instructions and short rules: every story moves to `docs/rationale/supervisor.md`, every rule gets a non-prose home in `docs/loop-inventory/supervisor.md`, and files load only in the mode/phase that uses them — with no behaviour change.

**Problem Statement:**
The Supervisor loop (run once per `/automate` item) needs its prompts to cost only what the executing model uses at that moment.
Currently the four group files total 391,294 bytes at the base commit (`agents/supervisor.md` 105,710; `commands/supervisor.md` 60,305; `skills/self-heal-advisory/SKILL.md` 176,146; `skills/async-orchestration/SKILL.md` 49,133), they carry 31 history references, the multi-voter section loads on every Phase 4.5 run although `--multi-voter-heal` is default-off, and async-orchestration's FINALIZE procedure is loaded at PLAN (and preloaded into every Execute Manager spawn). The group inventory has 298 `rule` rows and 21 `story` rows still homed `prose`.
Success looks like: a ≥ 30% smaller read set, a lower history-reference count, zero `story`/`rule` rows homed `prose`, and every gate test still green.

## Acceptance Criteria
- [ ] AC1 — Given `docs/loop-inventory/supervisor.md` after this item, when its rows are counted by kind and home, then no row of kind `story` has home `prose` (each is `rationale:docs/rationale/supervisor.md#<anchor>`, or a split row whose rule part got its own row), and every `rule` row has home `script:…`, `hook:…`, `step-scoped`, `global` or `rationale:…` (a `rationale:` home only for a story-split row) — never `prose`; `test-loop-inventory.sh` passes (heading coverage, live anchors for `prose`/`global`, rationale anchors resolve, counts and gap list recomputed).
- [ ] AC2 — Given the group's runtime files (the four sources plus every new split file this item creates; NOT the rationale or inventory docs), when `wc -c` is summed over all of them, then the all-modes total is ≤ 273,905 bytes (≥ 30% below 391,294); the default-path read set (no `--multi-voter-heal`) is also reported. Before/after numbers are written to the committed evidence file `docs/evidence/as15-diet-supervisor.md`, and the PR body links to it.
- [ ] AC3 — Given the requirement's history-reference regex `'#[0-9]{2,4}\b|queue/[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2}|item [0-9]+'`, when it is run over the group's runtime files at the base commit and on the after tree, then the after count is lower than the before count (31 at base: 3 / 5 / 19 / 4); before, after and the command are in `docs/evidence/as15-diet-supervisor.md`.
- [ ] AC4 — Given a Phase 4.5 run without `--multi-voter-heal`, when Phase 4.5 loads its protocol, then the multi-voter verification text lives in its own file under `skills/self-heal-advisory/` whose Read instruction is conditional on `MULTI_VOTER_HEAL` being on, and no unconditional Read of that file exists in any group runtime file (the grep and its output are in the evidence file; the transcript assertion is Validation 3, an owner pre-merge step).
- [ ] AC5 — Given async-orchestration, when Phase 2 PLAN and the Execute Manager preload read `skills/async-orchestration/SKILL.md`, then the FINALIZE procedure (steps 1–7) and the PR Body Template are not in that file: they live in `skills/async-orchestration/finalize.md`, read only at Phase 4 FINALIZE entry. `SKILL.md` keeps a `# Part 2` heading stub that names `finalize.md` and still holds §"Subagent Spawn Contracts" (needed from Phase 2 on), so every existing `SKILL.md Part 2` citation — including `scripts/supervisor-next-step.sh`'s instruction strings and the golden fixtures pinned on them — still resolves without editing the driver.
- [ ] AC6 — Given Part C for self-heal-advisory, when a Phase 4.5 iteration runs, then it Reads only the sections it executes: sections used only on the first iteration (pre-review enrichments, on-entry actions), only on later iterations, only on escalation / base-mismatch cleanup / fix-task crash, only at the completion tail, and only under `--multi-voter-heal` are separated so that each Read instruction names exactly the file(s) its step needs; every moved `###`/`####` heading keeps a one-line pointer in `SKILL.md`, so every existing `skills/self-heal-advisory/SKILL.md` §"…" citation still resolves.
- [ ] AC7 — Given any test, gate or script that greps text from a group file (found by `grep -rlF` of the file's name under `loomwright/scripts/` and root `scripts/`), when the text it pins moves to a split file, then the test is repointed to the new file with its needle byte-identical; pinned text is never moved to the rationale doc and never reworded. Given any committed pinned `file:N` citation into a group file (found by `grep -rnE '(async-orchestration|self-heal-advisory)/SKILL\.md:[0-9]|agents/supervisor\.md:[0-9]|commands/supervisor\.md:[0-9]' loomwright/scripts scripts docs/rationale` — at base: `loomwright/scripts/reconcile-resume-state.sh` (3 citations of `async-orchestration/SKILL.md:536` / `:543-545`, pins `subtask: {subtask_a} — {title}` / `merge: {subtask_a} {title}`) and `loomwright/scripts/test-reconcile-resume-state.sh` (`:546-548`)), when its cited lines move or shift, then the citation is re-derived to the new file and line with the `[pins: …]` text byte-identical, so `test-citation-drift.sh` stays green; the bare, unpinned `async-orchestration/SKILL.md:546-548` comment citation in `test-reconcile-resume-state.sh` is replaced by a descriptive anchor (e.g. `finalize.md §"Phase 4 FINALIZE procedure", the merge -m line`) — never a new BARE_ALLOWLIST entry. `check-contract-parity.sh` stays green (agents/supervisor.md still names every SUPERVISOR_RESULT hook-required field), and when a moved block carries a bare `status: <token>` or `heal_decision: <token>` literal, the new split file gets its own ENUMS row in `scripts/check-contract-parity.sh` (existing rows byte-identical, rows only added), so that gate's coverage moves with the text (its own comment: `add a row here so the gate's coverage moves with it`).
- [ ] AC8 — Given every invariant of CLAUDE.md §"Failure-Mode Invariants" that appears in the group (single merge executor / never-merge, two review lenses, single-drain ownership, bimodal fail-closed/fail-safe, can't-ask branches, `|| true` convention, the completion-tail guard kept verbatim in `agents/supervisor.md`), then when the after tree is grepped for each one, then each stays in a runtime prompt or in an enforcing script/hook (named in its inventory row).
- [ ] AC9 — Given a rule that would need a NEW hook to leave the prompt, when the worker moves its text, then its prose stays and a draft is filed to `.supervisor/requirements/proposed/` (listed in the evidence file); no hook is added. Given a behaviour question found while moving text, when it is found, then it is listed in the evidence file under "Behaviour questions" and not fixed.
- [ ] AC10 — Given moved text, when the after tree is checked, then no count or version claim is added to it, every `file:line` citation in the rationale doc is pinned or replaced by a descriptive anchor (`test-citation-drift.sh` green), and no install-root token (`${CLAUDE_PLUGIN_ROOT}` and the other classes `check-vendor-coupling.sh` counts) is added to the rationale doc; each new split file gets a `docs/vendor-coupling-manifest.json` allowance with a "moved by automate-speed/15 … no reference added" note, and the source file's allowance is lowered by the count it moved.
- [ ] AC11 — Given the release rule for a lane, when the PR is opened, then the PR carries `changelog.d/as15-diet-supervisor.md` (`<!-- bump: minor -->`, prose headline + body) and does NOT run `bump-version.sh` or edit `plugin.json` / `marketplace.json` / `CHANGELOG.md` (the wave's release step folds it).
- [ ] AC12 — Validation 1–2 evidence: `test-loop-inventory.sh`, `check-doc-currency.sh`, `test-citation-drift.sh`, `check-token-budget.sh`, `check-contract-parity.sh`, `check-vendor-coupling.sh` and every test repointed under AC7 pass, each reported `<passed>/<total>` in the evidence file; and a mutation control — delete one real `global` row's anchored line from a scratch copy of its source file and run `test-loop-inventory.sh --root <scratch>` — goes red naming that row (mutant checked non-empty and different before trusting it); plus one pin-mutation control per repointed test (the `## Pin mutations` table), each recorded in the evidence file. The baseline (391,294 bytes; 31 history references) is re-measured at `3a03dfa` with the commands written into the evidence file before any delta is reported.

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

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| supervisor-pair | `loomwright/agents/supervisor.md`, `loomwright/commands/supervisor.md`, `loomwright/docs/loop-inventory/supervisor.md` | `loomwright/docs/rationale/supervisor.md` | HIGH |
| async-orchestration | `loomwright/skills/async-orchestration/SKILL.md`, the pair's Phase 2 / Phase 4 Read lines, inventory, rationale, `loomwright/scripts/test-loop-inventory.sh`, `loomwright/docs/vendor-coupling-manifest.json`, `loomwright/skills/SKILLS_INDEX.md`, pinning tests (e.g. `loomwright/scripts/test-pr-body-evidence-seam.sh`, `loomwright/scripts/test-not-verified-transport-seam.sh`, `loomwright/scripts/test-rules-seams.sh`), `loomwright/scripts/reconcile-resume-state.sh` + `loomwright/scripts/test-reconcile-resume-state.sh` (citation re-derive only), `scripts/check-contract-parity.sh` (ENUMS row for `finalize.md` only if it carries a status literal) | `loomwright/skills/async-orchestration/finalize.md` | HIGH (pin-test list MEDIUM) |
| self-heal-advisory | `loomwright/skills/self-heal-advisory/SKILL.md`, the pair's Phase 4.5 Read lines, inventory, rationale, `loomwright/scripts/test-loop-inventory.sh`, `loomwright/docs/vendor-coupling-manifest.json`, `loomwright/skills/SKILLS_INDEX.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (question-gate surface cells, only if a cited section moves), pinning tests (e.g. `test-closed-enum-pins-seam.sh`, `test-deviations-advisory-seam.sh`, `test-rules-gate-seams.sh`, `test-brief-conformance-seam.sh`, `test-phase45-rounds-seam.sh`, `test-execution-directive-seam.sh`), `scripts/check-contract-parity.sh` (ENUMS rows for each split file that carries a status / heal_decision literal) | `loomwright/skills/self-heal-advisory/multi-voter.md` plus the other per-iteration split files the worker cuts (names chosen by the worker, all under `loomwright/skills/self-heal-advisory/`) | HIGH (split file set MEDIUM) |
| evidence + release | — | `docs/evidence/as15-diet-supervisor.md`, `changelog.d/as15-diet-supervisor.md` | HIGH |

**Not modified (by design):** `loomwright/scripts/supervisor-next-step.sh` and `loomwright/scripts/fixtures/supervisor-golden/**` — the driver's instruction strings name `skills/async-orchestration/SKILL.md Part 2` / `skills/self-heal-advisory/SKILL.md Part 2`; both files keep a `# Part 2` heading that points onward, so the golden fixtures stay byte-identical.

> **Validator-owned surfaces:** `test-loop-inventory.sh` (scans the four group sources + new split files), `check-doc-currency.sh` (scans `loomwright/docs/`, `skills/`, `agents/`, `commands/`), `test-citation-drift.sh` (every committed `file:N` citation), `check-token-budget.sh` (the `.agents.supervisor`, `.agents["execute-manager"]` (preloads async-orchestration), `.commands.supervisor`, `.skills["self-heal-advisory"]`, `.skills["async-orchestration"]` rows — ceilings only shrink here, no budget edits), `check-vendor-coupling.sh` (per-file allowances in `docs/vendor-coupling-manifest.json`), `check-contract-parity.sh` (SUPERVISOR_RESULT field presence in `agents/supervisor.md`; enum allowlists keyed by file path).

## Touched-file invariants

> Grounded at base `3a03dfa66d7de22ff93b0327affa60aa752948d2`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/test-loop-inventory.sh`** — keep: the group → source map is defined once in `group_sources()` (`# GROUPS (the group -> source-file map lives HERE, once; each inventory's `## Sources` must equal it)`); the inventory's `## Sources` list must equal the arm exactly; `This file names no vendor-coupling token`; bash 3.2 + BSD userland only. reuse: extend the existing `supervisor)` arm (`skills/async-orchestration/SKILL.md ;;`) and its header comment line, exactly as automate-speed/13 did for `skills/autonomous-loop/multi-iteration.md`. pinned by: its own fixture legs (must stay green).
- **Pinning tests repointed under AC7 (`loomwright/scripts/test-*.sh` that read a group file)** — keep: needles byte-identical; each test's own fail messages and leg structure unchanged; only the path a needle is read from changes (and, when a test reads several files, the file list). mirror: `test-non-interactive-gates-seam.sh` as repointed by `e01e7e1` — it reads the moved gates from the split file through its own variable (`AL_MULTI="$PLUGIN_ROOT/skills/autonomous-loop/multi-iteration.md"`), needles unchanged. Find them with `grep -rlF 'self-heal-advisory' loomwright/scripts scripts` / `grep -rlF 'async-orchestration' …` / `grep -rlF 'agents/supervisor.md' …`, then run each one after every move.
- **`loomwright/agents/supervisor.md`** — keep: the completion-tail guard verbatim (its own text starts `Completion-tail guard (runtime invariant`; `skills/self-heal-advisory/SKILL.md` Part 2 cites it as `Completion-tail guard — LIVES VERBATIM IN`); every SUPERVISOR_RESULT hook-required field name listed in `scripts/check-contract-parity.sh`'s MANIFEST row `supervisor-runner|supervisor.md|SUPERVISOR_RESULT|…`; the enum allowlists `agents/supervisor.md|status|completed,completed_with_escalation,failed,checkpoint,…` and `agents/supervisor.md|heal_decision|PASS,ESCALATED,null,enum` (no new `status:` literal outside them); the Can't-ask rule's named statuses (pinned by `test-non-interactive-gates-seam.sh`). pinned by: `test-check-contract-parity.sh`, `test-non-interactive-gates-seam.sh`, `test-citation-drift.sh`, `test-run-lock.sh`, `test-check-children-settled.sh`, `test-phase45-rounds-seam.sh`, `test-not-verified-transport-seam.sh`, `test-rules-seams.sh`, `test-release-refold.sh`, `test-build-handoff.sh`, `test-verify-provides.sh` (each re-run after the edit).
- **`loomwright/commands/supervisor.md`** — keep: the inline-path canonical state writes section (`### Inline-path canonical state writes (Phase 1 ACQUIRE + Phase 4.5 completion tail)` — the inline path never loads `agents/supervisor.md`); the observability awk snippet (`if awk -v url="{PR_URL}"`, kept in sync with `skills/self-heal-advisory/SKILL.md` completion-tail step 5.5); the next-step driver section (`## Next-step driver (Phases 0–4)`). pinned by: `test-check-children-settled.sh`, `test-loop-inventory.sh`.
- **`loomwright/skills/self-heal-advisory/SKILL.md`** — keep: the enum allowlists `skills/self-heal-advisory/SKILL.md|status|…` / `|heal_decision|PASS,ESCALATED,null,enum` in `check-contract-parity.sh` (a moved `status:` literal moves the allowance question to the new file — record it); `# Part 2 — Phase 4.5 SELF_HEAL Loop Protocol` heading (the driver's handover message cites `skills/self-heal-advisory/SKILL.md Part 2`); the at_floor rule (`at_floor(i) — the ONE fix-time severity rule`); `ADVISORY CONTRACT (NON-NEGOTIABLE)`; every advisory signal stays non-gating. mirror: commands/supervisor.md observability snippet (`keep the two in sync`). pinned by: the test list under AC7.
- **`loomwright/skills/async-orchestration/SKILL.md`** — keep: `## Subagent Spawn Contracts` reachable from the Phase 2 Read (the driver's `spawn` instructions point there); the Execute Manager's preloaded content (Part 1: poll loop, worker prompt template, pre-spawn verification gate, scope-expansion adjudication) unchanged in meaning; `# Part 2` heading present (driver strings `skills/async-orchestration/SKILL.md Part 2 steps 2-5.5`, `Part 2 PR Body Template`). pinned by: `test-pr-body-evidence-seam.sh`, `test-not-verified-transport-seam.sh`, `test-rules-seams.sh`, `test-verify-provides.sh`, `test-check-children-settled.sh`, `test-reconcile-resume-state.sh`, `test-context-digest.sh`, `test-worktree-salvage.sh`, `test-worktree-audit.sh`, `test-release-refold.sh`, `test-phase45-rounds-seam.sh`, `test-citation-drift.sh`.
- **`loomwright/scripts/reconcile-resume-state.sh`** — keep: the verdict contract (`VERDICT: CLEAN|STALE|UNKNOWN`, exit 0/3/4, a correctness gate — never `|| true`); every line of code unchanged. Only the comment citations `skills/async-orchestration/SKILL.md:536` and `async-orchestration/SKILL.md:543-545` change, re-derived to the file and line where the cited commit-convention text lives after the move, `[pins: …]` text byte-identical. pinned by: `test-citation-drift.sh` (WINDOW=3 pin check), `test-reconcile-resume-state.sh`.
- **`loomwright/scripts/test-reconcile-resume-state.sh`** — keep: every leg and assertion; only the bare comment citation `async-orchestration/SKILL.md:546-548` (no `[pins:]`, not in the drift allowlist) is replaced by a descriptive anchor naming the new file and section. pinned by: `test-citation-drift.sh`.
- **`scripts/check-contract-parity.sh`** — keep: the MANIFEST rows byte-identical (it has a second, out-of-tree 4-column consumer, `eval-corpus/parity-emit-block/check.sh` — never add a column); existing ENUMS rows byte-identical; reuse: add one `<file>|status|…` / `<file>|heal_decision|…` row per new split file that carries such a literal, copying the source file's allowlist. pinned by: `test-check-contract-parity.sh`.
- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: valid JSON; one allowance + one note per counted file; mirror the `e01e7e1` note shape (`moved by automate-speed/13 load-by-mode split … — no reference added`). pinned by: `scripts/check-vendor-coupling.sh`.

## Pin mutations

Every test repointed under AC7 is a changed pin. The split files do not exist yet, so the rows name the procedure; the worker that repoints a test writes the concrete literal into the evidence file and runs it on a scratch copy (mutant checked non-empty and different from the original first).

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| each repointed `loomwright/scripts/test-*.sh` needle (Subtasks 2–3) | delete the line holding that needle's governed text in the NEW split file (not the pointer stub left in `SKILL.md`) ⇒ the test goes red; a test that stays green because the stub still matches is repointed to the split file alone |
| `loomwright/scripts/test-loop-inventory.sh` — a `global` row's live anchor | delete the anchored line in its source file (scratch copy) ⇒ `FAIL <id>: anchor not found` |
| `loomwright/scripts/test-loop-inventory.sh` — group sources | drop a new split file from the `supervisor)` arm (scratch copy) ⇒ heading-coverage FAIL for that file's rows' file cell |
| `scripts/check-contract-parity.sh` — a new ENUMS row | flip one allowlisted token in the split file to an out-of-enum literal (scratch copy) ⇒ the gate fails |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Supervisor pair diet: stories out of `agents/supervisor.md` + `commands/supervisor.md`, rule homes for their rows; creates the evidence file skeleton | AC1 (pair rows), AC7 (test-repoint + citation clauses only — no split file, so no ENUMS row), AC8, AC9, AC10 | 3 modify (+ pin tests as needed), 2 create | — | LAUNCHABLE |
| 2 | async-orchestration diet + FINALIZE split to `finalize.md` (Part C) | AC1 (async rows), AC5, AC7, AC8, AC9, AC10 | ~8 modify, 1 create | — | BLOCKED (by #1) |
| 3 | self-heal-advisory diet + per-iteration / multi-voter split (Part C) | AC1 (self-heal rows), AC4, AC6, AC7, AC8, AC9, AC10 | ~12 modify, 2+ create | — | BLOCKED (by #2) |
| 4 | Finish the evidence file, changelog fragment, full validation (AC2, AC3, AC11, AC12) | AC2, AC3, AC11, AC12 | 1 modify, 1 create | — | BLOCKED (by #3) |

**Evidence file:** Subtask 1 creates `docs/evidence/as15-diet-supervisor.md` (headings: Baseline, Behaviour questions, Proposed hooks, Pin mutations, Results); Subtasks 1–3 append their behaviour questions, filed proposals and pin-mutation records to it; Subtask 4 finishes it (measurements, gate results).

**Per-subtask work rule (all of 1–3):** for each row of the subtask's file(s) in `docs/loop-inventory/supervisor.md`: `story` ⇒ move the text to a `###` section of `docs/rationale/supervisor.md` and set home `rationale:docs/rationale/supervisor.md#<slug>` (split a story paragraph that contains a rule first: the rule keeps or gets its own row); `rule` enforced by an existing script/hook ⇒ delete the prose (keep one line only if the model would otherwise attempt the blocked action) and home `script:<file>[ <sub>]` / `hook:<leaf>`; applies at one step ⇒ `step-scoped`, moved next to that step; applies everywhere ⇒ `global`, rewritten short (a `global` row's anchor must still be a live substring of its file). Recompute `## Counts` and the gap list from the table; add rows for every new heading (heading coverage). Moving text never changes a condition or action.

### Subtask Contracts

```yaml
# Subtask 1 — Supervisor pair diet (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/docs/rationale/supervisor.md"}
  - {kind: "symbol", path: "loomwright/docs/rationale/supervisor.md", name: "# Rationale — Supervisor"}
requires: []
lanes:
  - "loomwright/agents/supervisor.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/docs/rationale/supervisor.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/scripts/test-*.sh"
  - ".supervisor/requirements/proposed/*.md"
  - "docs/evidence/as15-diet-supervisor.md"
external_requires: []

# Subtask 2 — async-orchestration diet + FINALIZE split (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/skills/async-orchestration/finalize.md"}
  - {kind: "symbol", path: "loomwright/scripts/test-loop-inventory.sh", name: "skills/async-orchestration/finalize.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/docs/rationale/supervisor.md"}
lanes:
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/skills/async-orchestration/finalize.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/docs/rationale/supervisor.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/scripts/test-*.sh"
  - "loomwright/scripts/reconcile-resume-state.sh"
  - "scripts/check-contract-parity.sh"
  - ".supervisor/requirements/proposed/*.md"
  - "docs/evidence/as15-diet-supervisor.md"
external_requires: []

# Subtask 3 — self-heal-advisory diet + per-iteration / multi-voter split (BLOCKED by #2)
provides:
  - {kind: "file", path: "loomwright/skills/self-heal-advisory/multi-voter.md"}
  - {kind: "symbol", path: "loomwright/scripts/test-loop-inventory.sh", name: "skills/self-heal-advisory/multi-voter.md"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/scripts/test-loop-inventory.sh", name: "skills/async-orchestration/finalize.md"}
lanes:
  - "loomwright/skills/self-heal-advisory/*.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/docs/rationale/supervisor.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/scripts/test-*.sh"
  - "loomwright/scripts/reconcile-resume-state.sh"
  - "scripts/check-contract-parity.sh"
  - ".supervisor/requirements/proposed/*.md"
  - "docs/evidence/as15-diet-supervisor.md"
external_requires: []

# Subtask 4 — evidence + changelog fragment + validation (BLOCKED by #3)
provides:
  - {kind: "file", path: "docs/evidence/as15-diet-supervisor.md"}
  - {kind: "file", path: "changelog.d/as15-diet-supervisor.md"}
requires:
  - {from: "3", kind: "file", path: "loomwright/skills/self-heal-advisory/multi-voter.md"}
lanes:
  - "docs/evidence/as15-diet-supervisor.md"
  - "changelog.d/as15-diet-supervisor.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3 ──→ Subtask 4
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | inventory, rationale doc, `agents/supervisor.md`, `commands/supervisor.md`, vendor manifest | YES |
| Subtask 2 | Subtask 3 | inventory, rationale doc, the pair, `test-loop-inventory.sh`, vendor manifest, `SKILLS_INDEX.md` | YES |
| Subtask 3 | Subtask 4 | `docs/evidence/as15-diet-supervisor.md` | YES (measures the finished tree) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after #1)
- **Batch 3:** Subtask 3 (after #2)
- **Batch 4:** Subtask 4 (after #3)
- **Recommended workers:** 1
- **Estimated batches:** 4

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | — (precedent: commit `490927a`, `loomwright/docs/rationale/launch-pad-autonomous.md`, `loomwright/docs/loop-inventory/launch-pad-autonomous.md`) |
| 2 | — (precedent: commit `e01e7e1` — load-by-mode split, group-source extension, vendor manifest note, SKILLS_INDEX row) |
| 3 | — (same precedent as 2) |
| 4 | — (precedent: `docs/evidence/as13-diet-launch-pad-autonomous.md` layout, incl. "Not run — Validation 3") |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope vs Supervisor Capability — ~391 KB / 745 rows exceeds one worker's context (Feasibility (Phase 2.5)) | HIGH | `context-bound` split into 4 serialized subtasks, one source file group each; each worker reads only its file(s) and that file's inventory rows |
| A pinned `file:N` citation (`reconcile-resume-state.sh`, its test) goes stale when FINALIZE text moves or shifts | HIGH | AC7: grep every pinned citation into a group file, re-derive file+line after each move, run `test-citation-drift.sh` per subtask |
| A test greps a needle that moves (to a split file or the rationale doc) and goes red | HIGH | AC7: find pinning tests with `grep -rlF` before moving, repoint path only (needle byte-identical), re-run each after every move; never move pinned text to the rationale doc |
| A rule silently dropped while deleting "script-enforced" prose | HIGH | Delete prose only when the inventory row names the enforcing script/hook that exists today; keep one line when the model would otherwise attempt the blocked action; mutation control (AC12) |
| 30% all-modes target not reached by moving stories alone | MEDIUM | Measure after each subtask (`wc -c`); collapse duplicated restatements between `agents/supervisor.md` and `commands/supervisor.md` (each keeps the text its own path needs), drop repeated "why" comment blocks inside code fences (they are stories), report the default-path set separately |
| Breaking an inbound `§"…"` citation (75 files cite `self-heal-advisory/SKILL.md`) | MEDIUM | Every moved `###`/`####` heading keeps a one-line pointer in its original file (the `e01e7e1` pattern); `# Part 2` headings kept in both skills so `supervisor-next-step.sh` strings and golden fixtures stay valid |
| `check-vendor-coupling.sh` breach from install-root tokens moved into the rationale doc or a split file | MEDIUM | AC10: reword install-root tokens out of rationale text; add per-file allowances with notes for split files, lower the source allowance by the moved count |
| Concurrent lanes (automate-speed/14, /16, /26 in this wave) edit neighbouring files (`test-loop-inventory.sh`, `vendor-coupling-manifest.json`, `SKILLS_INDEX.md`) | MEDIUM | Keep edits to those shared files minimal and line-local (one arm, one manifest key pair, one index row) so the wave merge stays a clean 3-way merge |
| Behaviour change sneaks in while rewriting a rule "short" | MEDIUM | Non-goal: no behaviour change; rewrite keeps the same condition and action; any behaviour question goes to the evidence file, not a fix |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 4
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-18-as15-diet-supervisor.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-18T20:59:09Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/611
- **Branch:** feature/as15-diet-supervisor
- **Files changed:** 37
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 1
- **Heal reason:** needs_human
- **Heal remaining issues:** 6
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Supervisor-group prompt diet across 4 subtasks; all gates green, ground truth 2/2. Phase 4.5 reviewer NEEDS_HUMAN: AC2 not met (all-modes 289,378 B, -26.0% vs >=30%) and conflicts with AC7 (no rewording pinned text). 3 MEDIUM cross-reference/verbatim findings + 3 LOW posted to the PR, unfixed.

## Not verified
- **inline /supervisor and delegated supervisor-runner runs on the dieted prompts** — needs a live multi-phase run; Validation 3 is an owner pre-merge step (subtask 1)
- **Phase 4 FINALIZE on the driver path (model follows the SKILL.md Part 2 stub to finalize.md)** — needs a live /supervisor run (subtask 2)
- **Execute Manager spawn with the slimmer preloaded SKILL.md** — needs a live parallel-path run (subtask 2)
- **Phase 4.5 runtime Read behaviour (default path never Reads multi-voter.md)** — needs a live Supervisor run (subtask 3)
