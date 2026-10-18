# Supervisor Job: Apply the next-step pattern inside the review-heal drain loop (automate-speed/12)

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-15-163325/L12 (lane clone of loomwright)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (disk 93% used, 30 GiB free — above the 1 GiB floor)
- **Source requirement:** .supervisor/requirements/automate-speed/12-next-step-review-heal.md
- **Base commit:** a8819a38100d77fbeddc2ff1a56963e91f172a5d

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + BSD userland + jq scripts with `test-*.sh` self-tests — the same stack as `loomwright/scripts/automate-next-step.sh` (items 06/07), which this item mirrors. |
| 2 | Dependency Availability | GO | Every helper the drain calls already exists: `drain-rounds.sh`, `wait-for-checks.sh`, `drain-gh-read.sh`, `classify-bot-review.sh`, `drain-subfloor-decision.sh`, `fix-floor.sh`, `ci-run-probe.sh`, `wrap-external-text.sh`, `release-refold.sh`, `dispatch-pr-postmortem.sh`. |
| 3 | Architecture Fit | GO | Same "driver prints one JSON instruction, model reports back with `--result`" pattern as `automate-next-step.sh`; the instruction shape is item 06's (`docs/result-schemas/automate-run.md` §"next-step instruction"). |
| 4 | Scope vs Supervisor Capability | CAUTION | 231 review-heal GAP rows, a new driver of comparable size to `automate-next-step.sh` (1919 lines) plus golden fixtures: well over 800 changed lines ⇒ `context-bound` split into 2 sequential subtasks. |
| 5 | Hard Blockers | GO | None. Item 06 (the instruction schema) is merged on `main` (PR #594 merged; `automate-next-step.sh` present at base). |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add `loomwright/scripts/review-heal-next-step.sh`, a driver that owns the `/review-pr --until-mergeable` drain loop's deterministic steps and hands the model one instruction at a time, pinned by golden fixtures, and drive the review-heal inventory's GAP count to 0.

**Problem Statement:**
The `/automate` engine and its owner need the drain loop's bookkeeping to be executed by tested code rather than re-derived from 133 KB of `skills/review-heal/SKILL.md` prose every round.
Currently, round counting, the CI wait and readback, `classify-bot-review.sh` calls, fix-cycle bookkeeping, convergence/termination reasons, the Earned Fallback Review trigger and the terminal `REVIEW_HEAL_RESULT` are all carried in prose the model re-reads inline. This causes slow drains (PR #533: one drain round took 2h11m while CI took ~7m) and untested branches (231 GAP rows in `loomwright/docs/loop-inventory/review-heal.md`).
Success looks like: a driver whose golden cases reproduce the result block and drain-round state byte for byte, the Earned Fallback Review emitted exactly once when no review lens posted, the migrated prose deleted, and `test-loop-inventory.sh` reporting `GAP review-heal: 0`.

## Acceptance Criteria
- [ ] AC1 — Given each review-heal golden case under `loomwright/scripts/fixtures/review-heal-golden/` (one case per deterministic branch of §"Step U4 — The bounded drain loop": converged READY, bound_hit ESCALATED, sub_floor_converged READY, ci_untrusted ESCALATED, fix round with a pushed fix, `no_review_lens_posted` fallback, unknown-channel fail-closed ESCALATED, fix_floor_invalid ESCALATED), when its recorded inputs (stubbed `gh` / `drain-gh-read.sh` / `wait-for-checks.sh` output and the model's `--result` reports) are driven through `review-heal-next-step.sh`, then the emitted `REVIEW_HEAL_RESULT` block and the `drain-rounds.sh` ledger state are byte-identical to the case's expected files.
- [ ] AC2 — Given a round whose read shows no review lens posted (`no_review_lens_posted`: no bot-authored finding in any channel and every review-producing check green-with-empty-output, absent or skipped), when the driver reaches READY evaluation, then it emits exactly ONE `{"do":"spawn","what":"fallback review",…}` (a `loomwright:code-reviewer` diff review) per drain run; a second request in the same drain run exits 2 with `review-heal-next-step: fallback_already_spawned — …` on stderr, prints nothing and writes nothing; order for unreadable input: a §U1-gated channel that is UNKNOWN (GraphQL thread error/truncation, errored issue-comment read, errored required/review-producing check-output fetch) terminates `ESCALATED` first and the fallback trigger is never evaluated (the AC1 unknown-channel golden); a trigger that cannot be computed while every gated channel read succeeded (a review-producing check's output emptiness is ambiguous) reads `no_review_lens_posted` as true and emits the spawn (fail closed toward running — its own golden case).
- [ ] AC3 — Given the same drain state, when the driver runs twice with no `--result`, then both calls print the byte-identical pending instruction and no ledger, sidecar or result file changes.
- [ ] AC4 — Given any driver path, then no instruction, command line or code path contains `gh pr merge`, and `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to the same surfaces as at base `a8819a3`; every push the driver hands to a fix worker is a regular push (never `--force`).
- [ ] AC5 — Given the deterministic rows the driver now executes, then their prose is deleted from `loomwright/skills/review-heal/SKILL.md` and `loomwright/commands/review-pr.md` (replaced by a pointer to the driver step), each such inventory row's home is `script:review-heal-next-step.sh <step>` naming a real `case` arm, and the `REVIEW_HEAL_RESULT` schema text in `docs/RESULT_SCHEMAS.md` / `docs/result-schemas/review-heal-result.md` is unchanged.
- [ ] AC6 — Given `bash loomwright/scripts/test-loop-inventory.sh`, then it exits 0 and prints `GAP review-heal: 0` (every review-heal row carries a test cell naming an existing `test-*.sh`; `loomwright/agents/review-pr.md` is not edited).
- [ ] AC7 — Given the review-heal read set (`wc -c` of `skills/review-heal/SKILL.md`, `commands/review-pr.md`, `agents/review-pr.md`) before (base `a8819a3`) and after the change, then a committed evidence file `docs/evidence/as12-review-heal-read-set.md` contains both measurements and the commands that produced them, and the PR body links to it.
- [ ] AC8 — Given the mutation control "skip the fallback spawn on `no_review_lens_posted`" applied to the driver, then `test-review-heal-next-step.sh` goes red; reverting it turns it green.
- [ ] AC9 — Given the detached dispatched drain (entry sense (a)), when its pinned allowlist is built, then `review-heal-next-step.sh` is in `DRAIN_SCRIPTS` in `loomwright/scripts/dispatch-pr-review.sh` and `test-dispatch-pr-review.sh` (its script-admission drift guard) passes.
- [ ] AC10 — Given the review-heal inventory at GAP 0, then `test-loop-inventory.sh`'s fixture legs that mutate a gap-list line (`ac7c`, `shape-gap-line`) still prove their failure lines — retargeted to a group that still has gaps, or fed a synthesized gap row in their scratch copy — and the script exits 0.
- [ ] AC11 — Given a hermetic scratch repo (a throwaway git repo with `gh` stubbed on `PATH` via `LOOMWRIGHT_GH_BIN`, following item 07's `docs/evidence/as07-next-step-drain-and-run.md` §"Validation 3 — running system" precedent), when one `/review-pr <pr> --until-mergeable` drain is driven end to end through `loomwright/scripts/review-heal-next-step.sh` (the model's reports supplied by the worker at each `spawn`), then a committed evidence file `docs/evidence/as12-review-heal-drain-run.md` contains the commands, the driver's printed instructions, the round lines, the emitted `REVIEW_HEAL_RESULT` block, and the `<passed>/<total>` counts of `test-review-heal-next-step.sh`, `test-classify-bot-review.sh`, `test-dispatch-pr-review.sh` and `test-loop-inventory.sh`; the PR body links to it AND pastes the round lines and result block as a fenced block under a `Validation 3 — running system` heading (the form `validation-gate` reads). A drain on the live PR through the branch's driver is not claimed: the PR body lists it under a `Not verified` heading.

## Non-goals
- No change to which findings are fixed, to the fix floor or to the severity floor — the golden cases pin today's decisions.
- No prompt diet of the prose that stays (item 14); delete only prose whose rows the driver now executes.
- `loomwright/agents/review-pr.md` is not edited (its rows get pins only).
- `automate-next-step.sh` and its schema section are not modified.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `a8819a38100d77fbeddc2ff1a56963e91f172a5d`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/skills/review-heal/SKILL.md`** — keep: the never-merge rule (`## No auto-merge ever`) and the heal-only default with the one earned-fallback exception (`under this flag the drain runs **no `code-reviewer` of its own by default**`); the `REVIEW_HEAL_RESULT` block section (`### `REVIEW_HEAL_RESULT` block`) stays the schema pointer, unchanged; the fix-worker prompt text pinned by `test-no-self-matching-wait.sh` (`never `pgrep -f`/`pkill -f <pattern>` with <pattern> in your own command`) and by `test-phase45-rounds-seam.sh`; reuse: every deleted step points to `script:review-heal-next-step.sh <step>`; mirror: the drain-round ledger contract with `loomwright/scripts/drain-rounds.sh` (its `bump` arm) and the sub-floor decision with `drain-subfloor-decision.sh`; pinned by: `test-loop-inventory.sh` (every `###`/`####` heading needs an `h:` row; prose/global rows need live anchors), `check-token-budget.sh` (`"review-heal": {"budget": 36700` in `loomwright/docs/prompt-token-budgets.json` — size may only shrink), `test-citation-drift.sh` (no new bare `file:N` citation), `check-doc-currency.sh`, and every test that reads this file — `grep -l "review-heal/SKILL.md" loomwright/scripts/test-*.sh` at base lists `test-automate-dismissed.sh` (the dismissed-marker bullet `- **<finding>** — <reason> (<source>)`), `test-automate-helpers.sh`, `test-closed-enum-pins-seam.sh`, `test-dispatch-pr-review.sh` (test 28 `script-not-admitted:`), `test-drain-rounds.sh`, `test-execution-directive-seam.sh` (fallback trigger wording), `test-loop-inventory.sh`, `test-no-self-matching-wait.sh`, `test-phase45-rounds-seam.sh`, `test-release-refold.sh`, `test-rules-gate-seams.sh`, `test-wait-for-checks.sh`. Before deleting a passage, the worker greps these for its text: a pinned passage either stays (as a pointer line carrying the pinned literal) or its pin moves to `test-review-heal-next-step.sh` in the same change.
- **`loomwright/scripts/dispatch-pr-review.sh`** — keep: the pinned-allowlist construction (`DRAIN_SCRIPTS="drain-gh-read.sh drain-rounds.sh`) — append `review-heal-next-step.sh` only; `gate-eval` stays non-admitted except `escalation-cause`; the dispatcher's always-exit-0 rule; fired by: Supervisor completion-tail step 5.5 and the `PostToolUse[Bash]` `gh pr create` hook backstop; pinned by: `test-dispatch-pr-review.sh` (`script-not-admitted:`).
- **`loomwright/scripts/test-loop-inventory.sh`** — keep: GROUPS map, every checker branch and every fixture leg's expected FAIL line; change only the gap-list legs (`ac7c` — `FAIL $gid: GAP row missing from the review-heal ## Gap list`; `shape-gap-line` — `FAIL review-heal: malformed ## Gap list line`) so they still produce a valid mutant when review-heal has no gap rows (retarget to a group with gaps, or synthesize a gap row in the scratch copy); the `mutant invalid` guard (`no "AC7 gap-list drift: mutant invalid`) stays a failure; static bash 3.2, no network; pinned by: itself (CI runs it).
- **`loomwright/scripts/test-dispatch-pr-review.sh`** — keep: test 28's drift guard (the grep over `skills/review-heal/SKILL.md` + `agents/review-pr.md` that reports `script-not-admitted:`) and its `EXEMPT28` list; edit only if the driver's admission needs a new expectation; never weaken the guard to pass.
- **`loomwright/scripts/test-automate-dismissed.sh`** — keep: the dismissed-marker pin (the bullet shape `- **<finding>** — <reason> (<source>)`); if subtask 2 moves the marker comment into the driver, the pin moves to read the driver/schema text in the same change, never deleted.
- **`loomwright/scripts/test-execution-directive-seam.sh`** — keep: leg (f) (`keeps the fallback trigger unchanged`) and its mutant check; if the fallback trigger text moves, repoint the leg to the text that still states it.
- **`loomwright/docs/RESULT_SCHEMAS.md`** — keep: the index form (`See [result-schemas/automate-run.md](result-schemas/automate-run.md).`); add one heading + `See [...]` pointer for the new schema file only.
- **`loomwright/commands/review-pr.md`** — keep: the inline-only execution contract (`**AC9:** the `review-pr-runner` is **never itself Task-spawned**`) and the never-merge wording that keeps the `gh pr merge --squash` invariant grep's negation filter excluding it; reuse: point at the skill/driver rather than restating steps (house rule: a restated list is replaced by a pointer to its authority); pinned by: `test-loop-inventory.sh`, `check-token-budget.sh` (`"review-pr": {"budget": 5779` under `commands`), `check-doc-currency.sh`.
- **`loomwright/docs/loop-inventory/review-heal.md`** — keep: the four `## ` sections in order (`## Sources`, `## Inventory`, `## Gap list (ordered by risk)`, `## Counts`), the nine-column header, never-reused ids (`RH-NNN`), and computed counts; mirror: `test-loop-inventory.sh` GROUPS map (`review-heal            skills/review-heal/SKILL.md, commands/review-pr.md, agents/review-pr.md`); pinned by: `test-loop-inventory.sh` (SHAPE, LIVE ANCHORS, SCRIPT SUBCOMMANDS, GAP LIST + COUNTS, TEST CELLS).

## Closed enumerations touched

> Sibling grep at base `a8819a3`: `grep -rnF '"owned drain"' loomwright/docs/result-schemas/automate-run.md loomwright/scripts/test-automate-next-step.sh` → hits in both files (the `/automate` driver's closed `what` / `step` lists).

- **`"validate findings"`, `"fix worker"`, `"fallback review"`** (new `spawn.what` values) and the review-heal driver's step set (sibling: `"owned drain"`, step `drain`) — must be named in:
  - `loomwright/docs/result-schemas/review-heal-next-step.md` (NEW — the ONE authority for the review-heal driver's instruction shape: its `what` enum, its step enum, its `--result` shapes, its named refusals incl. `fallback_already_spawned`) — create.
  - `loomwright/scripts/review-heal-next-step.sh` — its emitter and header point at that file — create.
  - `loomwright/scripts/test-review-heal-next-step.sh` — mirrors the closed enum (a test leg fails on an unlisted `what`) — create.
  - `loomwright/skills/review-heal/SKILL.md` — points at the schema file, never restates the enum — extend (pointer).
  - `loomwright/docs/result-schemas/automate-run.md` `what` / `step` lists — no change: they are the `/automate` driver's closed lists; the review-heal driver is a separate emitter with its own schema file.
  - `loomwright/scripts/test-automate-next-step.sh` — no change: mirrors automate-run.md only.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-review-heal-next-step.sh` — fallback spawn on `no_review_lens_posted` (AC2/AC8) | delete the line that emits the `fallback review` spawn in `loomwright/scripts/review-heal-next-step.sh` |
| `test-review-heal-next-step.sh` — `fallback_already_spawned` refusal (AC2) | delete the `fallback_already_spawned` refusal branch in `loomwright/scripts/review-heal-next-step.sh` |
| `test-review-heal-next-step.sh` — no-`--result` re-print writes nothing (AC3) | make the no-result path re-run the pending step instead of re-printing the stored instruction |
| `test-review-heal-next-step.sh` — no merge / no force (AC4) | add `--force` to the push command line the fix-worker instruction carries |
| `test-review-heal-next-step.sh` — golden byte-identity (AC1) | flip the `termination_reason` the driver writes for a bound-hit drain from `bound_hit` to `converged` |
| `test-dispatch-pr-review.sh` — `script-not-admitted:` (AC9) | delete `review-heal-next-step.sh` from `DRAIN_SCRIPTS` in `loomwright/scripts/dispatch-pr-review.sh` |
| `test-loop-inventory.sh` — legs `ac7c` / `shape-gap-line` (AC10) | delete the gap-list membership check (the `GAP row missing from the` FAIL branch) in `loomwright/scripts/test-loop-inventory.sh`'s checker |
| `test-review-heal-next-step.sh` — each prose pin for a kept rule row (AC6) | delete the pinned rule sentence from `loomwright/skills/review-heal/SKILL.md` (one row per pin family: never-merge, heal-only default, never `--force`, fork-aware push) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Driver + schema doc + golden fixtures + driver test | AC1, AC2, AC3, AC4, AC8 | 1 modify (RESULT_SCHEMAS.md), 4 create (driver, test, fixture dir, schema doc) | `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Migrate prose, admit driver, rehome inventory to GAP 0, evidence + changelog | AC5, AC6, AC7, AC9, AC10, AC11 | up to 9 modify, 3 create | `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

Subtask 2 runs AC11's hermetic scratch-repo drain itself and commits the evidence file; FINALIZE pastes its fenced round lines + result block into the PR body.

```yaml
# Subtask 1 — Driver + schema doc + golden fixtures + driver test (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/review-heal-next-step.sh"}
  - {kind: "symbol", path: "loomwright/scripts/review-heal-next-step.sh", name: "fallback_already_spawned"}
  - {kind: "file", path: "loomwright/scripts/test-review-heal-next-step.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/review-heal-golden/MAP.tsv"}
  - {kind: "file", path: "loomwright/docs/result-schemas/review-heal-next-step.md"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "result-schemas/review-heal-next-step.md"}
requires: []
lanes:
  - "loomwright/scripts/review-heal-next-step.sh"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/scripts/fixtures/review-heal-golden/**"
  - "loomwright/docs/result-schemas/review-heal-next-step.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
external_requires:
  - "jq (already a hard dependency of the drain scripts)"

# Subtask 2 — Migrate prose, admit driver, rehome inventory to GAP 0, evidence + changelog (BLOCKED by #1)
provides:
  - {kind: "file", path: "docs/evidence/as12-review-heal-read-set.md"}
  - {kind: "file", path: "docs/evidence/as12-review-heal-drain-run.md"}
  - {kind: "file", path: "changelog.d/as12-next-step-review-heal.md"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/review-heal.md", name: "GAP: 0"}
  - {kind: "symbol", path: "loomwright/scripts/dispatch-pr-review.sh", name: "review-heal-next-step.sh"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/review-heal-next-step.sh"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-review-heal-next-step.sh"}
  - {from: "1", kind: "file", path: "loomwright/docs/result-schemas/review-heal-next-step.md"}
lanes:
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/commands/review-pr.md"
  - "loomwright/docs/loop-inventory/review-heal.md"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/scripts/dispatch-pr-review.sh"
  - "loomwright/scripts/test-dispatch-pr-review.sh"
  - "loomwright/scripts/test-loop-inventory.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/test-execution-directive-seam.sh"
  - "docs/evidence/as12-review-heal-read-set.md"
  - "docs/evidence/as12-review-heal-drain-run.md"
  - "changelog.d/as12-next-step-review-heal.md"
external_requires: []
```

### Implementation notes (both subtasks)
- **Instruction shape:** reuse item 06's closed `do` enum (`spawn` / `ask` / `park` / `done`) and common fields; the review-heal driver's `spawn.what` values are its own and documented ONCE in `loomwright/docs/result-schemas/review-heal-next-step.md` (the driver header and `skills/review-heal/SKILL.md` point at it; `docs/result-schemas/automate-run.md` is not edited): `"validate findings"` (the main thread validates the candidate findings the driver lists, inside the `EXTERNAL_TEXT` envelope, and reports `confirmed` / `dismissed` per finding), `"fix worker"` (one `general-purpose` fix worker, no Task, the validated findings, regular push), `"fallback review"` (one `loomwright:code-reviewer` diff review). `done` carries the verbatim `REVIEW_HEAL_RESULT` text. Judgment (validating a finding, writing a fix, the reviewer's verdict) stays with the model; everything else is the driver's.
- **Steps to migrate (one `case` arm each, cited by inventory homes):** round start + `drain-rounds.sh bump`, the all-channel read via `drain-gh-read.sh` (an errored channel ⇒ UNKNOWN ⇒ fail closed), required-check discovery, `wait-for-checks.sh` (resume on `CONTINUE`), `classify-bot-review.sh` per channel body, the `ci-run-probe.sh` trust probe (bounded by `--max-probes`), fix-floor dismissal (`fix-floor.sh meets`), fix-cycle bookkeeping, `drain-subfloor-decision.sh`, the `no_review_lens_posted` trigger, the READY/ESCALATED/termination-reason decision, `escalation_cause`, the dismissed-findings marker comment, notifications, and the result block. Seams like `automate-next-step.sh`'s (`*_FROM` / `*_UNTIL` step seams and overridable side-effect command lines) so golden cases run hermetically; `gh` via `LOOMWRIGHT_GH_BIN`.
- **GAP 0 (subtask 2):** a migrated deterministic row → `script:review-heal-next-step.sh <step>` + `test-review-heal-next-step.sh`; a row that stays prose (rule / judgment / story, and every `agents/review-pr.md` row) gets a real pin: an assertion in `test-review-heal-next-step.sh` (or an existing test that already pins it) that fails when the rule's text or behaviour is removed. Never write a test cell for a test that does not exercise the row.
- **Item 07's sibling `automate-next-step.sh` is not modified**; the `/automate` owned drain keeps invoking `/review-pr … --until-mergeable --no-auto-postmortem`.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/scripts/test-review-heal-next-step.sh` | YES (2 requires 1 — legal sequential share) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope vs Supervisor capability: 231 GAP rows plus a large driver (Feasibility (Phase 2.5)) | HIGH | `context-bound` split into two sequential subtasks; subtask 1 lands the tested driver before any prose is deleted (D5) |
| A row pinned by a test that does not exercise it (GAP 0 met on paper) | HIGH | Each pin asserts the rule's text or behaviour and turns red when it is removed; Phase 4.5 reviewer spot-checks pins by mutation |
| Deleting prose drops a rule (D1) | HIGH | Delete only rows whose home becomes a driver step; every remaining rule keeps a prose/global home with a live anchor (`test-loop-inventory.sh`) |
| `REVIEW_HEAL_RESULT` schema drift breaks `gate-eval` condition 1 / `sidecar-check` | MEDIUM | AC5 keeps the schema docs unchanged; golden cases compare the block byte for byte |
| A driver path that merges or force-pushes | MEDIUM | AC4 grep invariant + test assertion that no instruction carries `gh pr merge` or `--force` |
| `scripts/check-vendor-coupling.sh` flags a declared token (e.g. `subagent_type`, `CLAUDE_PLUGIN_ROOT`) in the new driver or its test | LOW | Raise the file's allowance in `loomwright/docs/vendor-coupling-manifest.json` with an `allowance_reasons` entry in the same change (add the manifest to subtask 1's lanes when needed) |
| A sibling wave lane (item 11, supervisor driver) also edits `test-loop-inventory.sh` or `dispatch-pr-review.sh` | MEDIUM | Change only the two gap-list legs and the one `DRAIN_SCRIPTS` string; `wave-build` surfaces any merge conflict for the owner |
| `check-token-budget.sh` / `check-doc-currency.sh` / `test-citation-drift.sh` red after prose edits | LOW | Run `bash scripts/ci-local.sh` before push |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-17-next-step-review-heal.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-18T08:33:47Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/600
- **Branch:** feature/as12-next-step-review-heal
- **Files changed:** 133
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** review-heal next-step driver (review-heal-next-step.sh), schema doc, 11 golden cases + driver test (148/148), prose migrated from skills/review-heal/SKILL.md and commands/review-pr.md, inventory GAP 231→0, driver admitted in DRAIN_SCRIPTS. Phase 4.5: iteration 1 FAIL (1 HIGH + 3 MEDIUM fixed, 4a098f4), iteration 2 PASS with 1 at-floor MEDIUM (fixed, 47cba75), iteration 3 FAIL (1 HIGH fixed on the final iteration, 038d5a1 — not re-reviewed). Ground truth 2/2 pass; benchmark pass; twin conformance skipped (empty store); risk_classification high_risk true.

## Not verified
- **a live inline /review-pr --until-mergeable drain through the driver** — no live PR was driven; the hermetic scratch drain is the evidence (subtask 1)
- **the driver's real non-seam side effects (wait-for-checks.sh, ci-run-probe.sh, rules-gate-verdict.sh, escalation-cause, notify-desktop.sh, send-webhook.sh, dispatch-pr-postmortem.sh)** — golden cases use stubs/recorders (subtask 1)
- **the detached dispatch-pr-review.sh drain end to end with the driver admitted** — only the allowlist drift guard ran (subtask 1)
- **live-PR drain through the branch's driver** — only the hermetic scratch-repo drain ran (subtask 2)
