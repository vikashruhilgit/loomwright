# Supervisor Job: Prompt diet — review-heal carries rules, not stories (automate-speed/14)

## Environment
- **Project:** L15 (lane clone of loomwright, `~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L15`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/14-diet-review-heal.md
- **Base commit:** 3a03dfa66d7de22ff93b0327affa60aa752948d2

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt files + bash 3.2/BSD awk test scripts; no new dependency |
| 2 | Dependency Availability | GO | Item 12 (review-heal next-step driver, inventory GAP 0) is merged on main (PR #600); item 13 already taught `test-loop-inventory.sh` the `global` and `rationale:<doc>#<anchor>` homes and created `loomwright/docs/rationale/` |
| 3 | Architecture Fit | GO | Same D1/D2 pattern as the merged item 13 (Launch Pad / `/autonomous` diet, PR #573) and the automate-loop move-only split (parallel-automate/22) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~129KB of prose and a 377-row inventory plus a 200+ line prose-pin table in `test-review-heal-next-step.sh`: well over 800 changed lines, so a `context-bound` split into three serial subtasks |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** CAUTION

## Task
**Goal:** Cut the review-heal runtime prompts to instructions and short rules: every `story` inventory row moves to `loomwright/docs/rationale/review-heal.md`, every `rule` row gets a non-prose home (existing script/hook, `step-scoped`, or `global`), and the sections only the Earned Fallback Review, only escalation, or only the dispatching side use load only when that path runs.

**Problem Statement:**
`skills/review-heal/SKILL.md` (110,754 bytes at the base commit) and `commands/review-pr.md` (18,297 bytes) are read by the `/review-pr --until-mergeable` drain that `/automate` owns on every item, and `SKILL.md` is consulted on every drain round.
Item 12 moved the drain's control flow into `scripts/review-heal-next-step.sh`; what remains still mixes instructions with incident history (41 history references at the base commit) and carries sections a normal drain round never uses (the Earned Fallback Review, the escalation-cause table, the Supervisor-side dispatch signal). This costs context on every drain round.
Success looks like a drain-round read set at least 30% smaller, with no rule dropped, proved by the inventory and its tests.

## Acceptance Criteria
- [ ] AC1 — Given `loomwright/docs/loop-inventory/review-heal.md` after this change, when its rows are read, then no row of kind `story` has home `prose`, and every row of kind `rule` has a home other than `prose` (`script:…`, `hook:…`, `step-scoped`, `global`, or `rationale:<doc>#<anchor>` only for a rule row that was split per Part B and whose rule part has its own row); the committed evidence file `docs/evidence/as14-diet-review-heal.md` contains the awk/python command that counts `story`/`rule` rows by home and its before/after output (before at base: rule→prose 160, story→prose 11), and the PR body links to it.
- [ ] AC2 — Given the drain-round read set — `skills/review-heal/SKILL.md` + `commands/review-pr.md` + every new file under `skills/review-heal/` that a `--until-mergeable` drain round reads when it runs neither the Earned Fallback Review nor an escalation (129,051 bytes at the base commit: 110,754 + 18,297) — when `wc -c` is taken before and after, then the after total is at most 90,335 bytes (≥30% smaller); the evidence file contains both `wc -c` outputs, the requirement's literal measure (the Touches files except the rationale/inventory docs), and the all-modes total (every `*.md` under `skills/review-heal/` + `commands/review-pr.md`), which must also be lower than 129,051; the PR body links to it.
- [ ] AC3 — Given the history-reference regex `grep -oE '#[0-9]{2,4}\b|queue/[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2}|item [0-9]+'` over the drain-round read set of AC2, when counted before (41 at the base commit) and after, then the after count is lower; the evidence file contains the command and both counts (version tags `vNN.N.N` reported as information only).
- [ ] AC4 — Given a `rule` row whose home is `script:<file>[ <sub>]` or `hook:<leaf>`, then its prose is deleted from the runtime file (one line may stay only where the model would otherwise attempt the blocked action), and the named script/subcommand or `hooks.json` leaf exists; a rule that would need a NEW hook keeps its prose and is filed as a propose-only draft under `.supervisor/requirements/proposed/` (no hook is added).
- [ ] AC5 — Given every `story` row, then its text lives in `loomwright/docs/rationale/review-heal.md` under a heading whose slug is the row's `rationale:docs/rationale/review-heal.md#<slug>` anchor; a one-line "because" stays in the runtime file only where it blocks a tempting wrong shortcut; a story paragraph containing a rule is split first (the rule gets its own row and home).
- [ ] AC6 — Given the split (Part C), then the Earned Fallback Review lives in `loomwright/skills/review-heal/fallback-review.md`, the escalation-only text (§"Escalation cause") in `loomwright/skills/review-heal/escalation.md`, and the dispatching-side text that a drain round never executes (§"Until-Mergeable Dispatch Signal" and its sub-sections: cardinal guarantee, churn gate, opt-out, launch form) in `loomwright/skills/review-heal/dispatch.md`; every moved `##`/`###` heading stays in `SKILL.md` with a one-line pointer that names its new file by path, so every existing `§"…"` citation — including the `contract` strings `scripts/review-heal-next-step.sh` prints (§"Step U3.5 — Validate-Then-Fix", §"Earned Fallback Review — `no_review_lens_posted`", §"Step U4 — The bounded drain loop", §"Fork-aware push") — still resolves to a heading in `SKILL.md`; and `commands/review-pr.md` states the read rule: a drain reads `SKILL.md` (+ any drain-mode file), reads `fallback-review.md` only when the driver prints a `spawn` with `what: "fallback review"`, and reads `escalation.md` only when the run ends `ESCALATED`.
- [ ] AC7 — Given the `review-heal` group, then `test-loop-inventory.sh`'s group map arm `review-heal)` and the inventory's `## Sources` both list every new file under `skills/review-heal/`, and every `###`/`####` heading in each new file is the `h:` anchor of a row.
- [ ] AC8 — Given `loomwright/scripts/test-review-heal-next-step.sh`'s P leg (the `PROSE_PINS` table), then every pin whose row still has home `prose`/`global` resolves (its literal is present in the file its second column names — repointed to the new file when the text moved), a pin is deleted only when its row's home leaves `prose`/`global`, and the inverse check (every prose/global row naming this test has a pin) stays green; no needle is loosened.
- [ ] AC9 — Given every invariant in CLAUDE.md §"Failure-Mode Invariants" that appears in this group (never merges / no `gh pr merge` executor, never `--force`, an unknown gated channel or unreadable required-check metadata fails CLOSED to `ESCALATED`, the dispatchers always `exit 0`, the earned fallback fails closed toward running, the CI lens is `static-only` with `execution: none`, the two review lenses not four passes), then it stays in the runtime prompt (a file a drain round reads) or in an enforcing script/hook.
- [ ] AC10 — Given the change, then no behaviour changes: `scripts/review-heal-next-step.sh` and every other script are not edited (except the tests named in the Touched-file invariants, only to repoint a read); a behaviour question found while moving text is recorded in the evidence file's "Behaviour questions" section, not fixed; no count or version claim is added to moved text; any `file:line` citation moved into the rationale doc is pinned or replaced by a descriptive anchor.
- [ ] AC11 — Given the release mechanics, then a fragment `changelog.d/as14-diet-review-heal.md` exists with `<!-- bump: minor -->` semantics per `changelog.d/README.md`, and the version files are not hand-edited (`bash scripts/check-version-bump.sh` passes).
- [ ] AC12 — Given the gates, when run, then `bash loomwright/scripts/test-loop-inventory.sh`, `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh`, `bash loomwright/scripts/test-review-heal-next-step.sh`, `bash loomwright/scripts/test-execution-directive-seam.sh`, `bash loomwright/scripts/test-no-self-matching-wait.sh`, `bash loomwright/scripts/test-phase45-rounds-seam.sh`, `bash loomwright/scripts/test-release-refold.sh`, `bash loomwright/scripts/test-rules-gate-seams.sh`, `bash loomwright/scripts/test-automate-dismissed.sh`, `bash loomwright/scripts/test-dispatch-pr-review.sh`, `bash loomwright/scripts/test-closed-enum-pins-seam.sh` and `bash loomwright/scripts/test-drain-rounds.sh` all exit 0, and the evidence file records each `<passed>/<total>` (or exit line) — Validation 1; and a mutation control (delete one `global` row's anchored line from a scratch copy ⇒ `test-loop-inventory.sh --root <scratch>` exits 1 naming that row) is recorded in the evidence file — Validation 2.
- [ ] AC13 — Given the source requirement's Validation 3 (a running-system step: one real item that exercises this group after the change, with the phase's result block pasted, and the transcript showing the fallback file is not read on a drain round that does not run the Earned Fallback Review), when the job finishes, then the evidence file has a "Not run — Validation 3" section stating that it is a pre-merge owner step outside this job: before merge the owner either runs one live drain on the changed prompts and pastes its fenced `REVIEW_HEAL_RESULT` block into the PR body, or waives V3 through the human-only `AUT-WAIVE` ask that `/automate`'s `validation-gate` raises; this job never fabricates that result block.

**Evidence rule:** AC1–AC3, AC10 and AC12 put their numbers in the committed evidence file `docs/evidence/as14-diet-review-heal.md` (Markdown, a File Impact Map create); the PR body only links to it.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory

## Touched-file invariants

> Grounded at base `3a03dfa66d7de22ff93b0327affa60aa752948d2`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/skills/review-heal/SKILL.md`** — keep (in `SKILL.md`, or in a file the pinning test is repointed to in the same change): every heading cited by `scripts/review-heal-next-step.sh`'s `contract` strings (`### Step U3.5 — Validate-Then-Fix …`, `### Earned Fallback Review — \`no_review_lens_posted\` …`, `### Step U4 — The bounded drain loop`, `### Fork-aware push …`) as a heading in `SKILL.md` (a moved section leaves its heading + one-line pointer); the fix-worker prompt sentences `Address ONLY these new review findings at or above the fix floor` and `Address ONLY these required-check failures and VALIDATED bot findings` with the lines after them that `test-phase45-rounds-seam.sh` `check_prompt` reads (`after "$RH" … 3` / `… 13`); no `scripts/ci-local.sh` mention (`test-phase45-rounds-seam.sh` drift guard); the WAITING sentence `test-no-self-matching-wait.sh` mutates (`$PHRASE`); the release re-fold text `FIRST run the release re-fold` and the `push_fix_to_pr()  … release-refold.sh, then git push` call sites (`test-release-refold.sh` `seam_review`); the rules-gate needles `test-rules-gate-seams.sh` greps (its `$INVOKE` string and `no countable human-stamped must-rule check is failing`); the marker-comment bullet `- **<finding>** — <reason> (<source>)` (`test-automate-dismissed.sh` leg B); the CI lens `static-only` wording and the fallback trigger (`test-execution-directive-seam.sh` (f)); every `scripts/<name>.sh|.py` the prose names exists and no prose line starts with `gh api` (`test-dispatch-pr-review.sh` drift guard around its `for s28 in` loop); frontmatter `version:` (mirror: the `review-heal` row of `loomwright/skills/SKILLS_INDEX.md`); pinned by: those tests, `test-review-heal-next-step.sh` P leg, and the `.skills["review-heal"]` ceiling in `loomwright/docs/prompt-token-budgets.json` (counts every `*.md` under the dir, so the new split files are measured too; only lower is safe, ceilings are not lowered here).
- **`loomwright/commands/review-pr.md`** — keep: the inline-execution banner `Execute this workflow inline as the main thread` and the execution-contract paragraph (AC9 `review-pr-runner` is never Task-spawned); the `**The driver runs the drain.**` paragraph (pin RH-377); the `--until-mergeable` parameter row's `**Never merges, never waits on a human.**` text; the `REVIEW_HEAL_RESULT` output block; pinned by: `test-review-heal-next-step.sh` (P leg), `test-execution-directive-seam.sh`, `test-loop-inventory.sh`, `check-doc-currency.sh`, and the `.commands["review-pr"]` ceiling.
- **`loomwright/agents/review-pr.md`** — NOT edited (requirement non-goal). Its inventory rows (RH-3xx) may only change home (`prose` → `global` for a rule that stays) without touching the file; its P-leg pins stay as they are.
- **`loomwright/scripts/test-review-heal-next-step.sh`** — edit ONLY the P leg's `PROSE_PINS` table (repoint a pin's file column when its text moved; delete a pin only when its row's home leaves `prose`/`global`); keep the inverse check (`prose`/`global` row naming this test ⇒ a pin exists) and every other leg byte-identical; keep the `pins_missing` helper; pinned by: itself.
- **`loomwright/scripts/test-loop-inventory.sh`** — change ONLY the `review-heal)` arm of `group_sources` (add the new `skills/review-heal/*.md` files) and the header comment line listing the review-heal sources; keep static bash 3.2 + BSD awk, the `step-scoped` exemption, the `global`/`rationale:` checks item 13 added, and every other arm (sibling lanes for items 15/16 may edit other arms in this wave); the fixture base already copies `skills/review-heal` via `cp -R "$PLUGIN/skills/$d"`, so new files in that dir are carried; pinned by: itself.
- **Other pinning tests (`test-execution-directive-seam.sh`, `test-no-self-matching-wait.sh`, `test-phase45-rounds-seam.sh`, `test-release-refold.sh`, `test-rules-gate-seams.sh`, `test-automate-dismissed.sh`, `test-dispatch-pr-review.sh`)** — edited ONLY to repoint a read at the file a pinned line moved to (e.g. add the new file to a `for f in` list or switch `$RH` for that one needle); never loosen a needle, never delete an assertion.
- **`loomwright/docs/loop-inventory/review-heal.md`** — keep: the four `## ` sections in order (Sources, Inventory, Gap list (ordered by risk), Counts), the nine-column header, ids never reused (`RH-` prefix, new rows take the next free id), gap list and counts recomputed from the table, GAP 0 stays 0; rewrite the intro's statement of homes to match what this group now uses; pinned by: `test-loop-inventory.sh`.
- **`loomwright/scripts/review-heal-next-step.sh`** (and every other non-test script) — NOT edited (no behaviour change); its `contract` strings keep resolving through the heading stubs in `SKILL.md`.

## Pin mutations

Subtask 1 creates the evidence file `docs/evidence/as14-diet-review-heal.md` (with "Pin mutations" and "Step-scoped anchors" sections); each worker (1, 2, 3) appends one row per pin it repoints or adds to its "Pin mutations" table and lists its step-scoped rows under "Step-scoped anchors", in the shape below. The mutation always edits the PROTECTED text in the file the pin now points at, never the needle. The worker runs each row's mutation on a scratch copy and records the red result.

| Pin | Mutation (one line, applied to the protected text the pin guards) |
|-----|-------------------------------------------------------------|
| `test-review-heal-next-step.sh` P leg — any `PROSE_PINS` row repointed to, or added for, a new `skills/review-heal/*.md` file (subtask 2) | delete that row's pinned literal line from the new file in a scratch copy ⇒ P leg prints `P: pinned rule text missing — <id> <file>: …` and exits non-zero |
| `test-review-heal-next-step.sh` P leg — the new pin for the read-rule row in `commands/review-pr.md` (subtask 3) | delete the read-rule sentence (`reads \`fallback-review.md\` only when the driver prints a \`spawn\` with \`what: "fallback review"\``) from `commands/review-pr.md` in a scratch copy ⇒ P leg red naming that id |
| `test-execution-directive-seam.sh` (f) — if its read is repointed to `skills/review-heal/fallback-review.md` (subtask 2) | delete the `static-only` CI-lens sentence / the `no_review_lens_posted` trigger line from `fallback-review.md` in a scratch copy ⇒ leg (f) red |
| `test-rules-gate-seams.sh` — any needle repointed to a new split file (subtask 2) | delete the needle's protected sentence from that file in a scratch copy ⇒ the seam test red |
| `test-automate-dismissed.sh` leg B — if the marker-comment bullet moves file (subtask 2) | change `- **<finding>** — <reason> (<source>)` to `- <finding> — <reason>` in the file the leg now reads ⇒ leg B red |
| `test-loop-inventory.sh` — the `review-heal)` arm listing the new files (subtask 2) | remove one new file from the arm in a scratch copy ⇒ `test-loop-inventory.sh --root <scratch>` exits 1 (the worker records the exact FAIL line it prints) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Core diet: SKILL.md sections before `## Until-Mergeable Mode` and after `## Anti-Patterns`, `commands/review-pr.md`, agent rows; create rationale doc and evidence file | AC1, AC4, AC5, AC8, AC9, AC10 for those rows | 4 modify, 2 create | `skills/pattern-detector/SKILL.md` | LAUNCHABLE |
| 2 | Until-mergeable diet + split (fallback-review.md, escalation.md, dispatch.md) + group map | AC1, AC4–AC10 for the until-mergeable rows | 5–7 modify, 3 create | `skills/pattern-detector/SKILL.md` | BLOCKED (by #1) |
| 3 | Read rule in `commands/review-pr.md`, evidence doc numbers, fragment, full gate run | AC2, AC3, AC6 (read rule), AC11–AC13 | 3–5 modify, 1 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #2) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/docs/rationale/review-heal.md"}
  - {kind: "file", path: "docs/evidence/as14-diet-review-heal.md"}
requires: []
lanes:
  - "docs/evidence/as14-diet-review-heal.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/commands/review-pr.md"
  - "loomwright/docs/rationale/review-heal.md"
  - "loomwright/docs/loop-inventory/review-heal.md"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/scripts/test-phase45-rounds-seam.sh"
  - "loomwright/scripts/test-no-self-matching-wait.sh"
  - "loomwright/scripts/test-release-refold.sh"
  - ".supervisor/requirements/proposed/"
external_requires: []
# Subtask 1 note: the Step 2 fix-worker prompt text (`Address ONLY these new review findings …` and the WAITING sentence) is pinned prompt text — it stays in SKILL.md, never moves to the rationale doc.

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/skills/review-heal/fallback-review.md"}
  - {kind: "file", path: "loomwright/skills/review-heal/escalation.md"}
  - {kind: "file", path: "loomwright/skills/review-heal/dispatch.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/docs/rationale/review-heal.md"}
lanes:
  - "docs/evidence/as14-diet-review-heal.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/skills/review-heal/fallback-review.md"
  - "loomwright/skills/review-heal/escalation.md"
  - "loomwright/skills/review-heal/dispatch.md"
  - "loomwright/docs/rationale/review-heal.md"
  - "loomwright/docs/loop-inventory/review-heal.md"
  - "loomwright/scripts/test-loop-inventory.sh"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/scripts/test-execution-directive-seam.sh"
  - "loomwright/scripts/test-no-self-matching-wait.sh"
  - "loomwright/scripts/test-phase45-rounds-seam.sh"
  - "loomwright/scripts/test-release-refold.sh"
  - "loomwright/scripts/test-rules-gate-seams.sh"
  - "loomwright/scripts/test-automate-dismissed.sh"
  - "loomwright/scripts/test-dispatch-pr-review.sh"
  - ".supervisor/requirements/proposed/"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "changelog.d/as14-diet-review-heal.md"}
requires:
  - {from: "1", kind: "file", path: "docs/evidence/as14-diet-review-heal.md"}
  - {from: "2", kind: "file", path: "loomwright/skills/review-heal/fallback-review.md"}
lanes:
  - "loomwright/commands/review-pr.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/docs/loop-inventory/review-heal.md"
  - "loomwright/scripts/test-review-heal-next-step.sh"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "docs/evidence/as14-diet-review-heal.md"
  - "changelog.d/as14-diet-review-heal.md"
external_requires: []
```

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| core | `loomwright/skills/review-heal/SKILL.md`, `loomwright/commands/review-pr.md`, `loomwright/docs/loop-inventory/review-heal.md`, `loomwright/scripts/test-review-heal-next-step.sh` | `loomwright/docs/rationale/review-heal.md` (dir `loomwright/docs/rationale/` exists), `docs/evidence/as14-diet-review-heal.md` (dir `docs/evidence/` exists) | HIGH |
| until-mergeable | `loomwright/skills/review-heal/SKILL.md`, `loomwright/docs/rationale/review-heal.md`, `loomwright/docs/loop-inventory/review-heal.md`, `loomwright/scripts/test-loop-inventory.sh` (`review-heal)` arm), `loomwright/scripts/test-review-heal-next-step.sh` | `loomwright/skills/review-heal/fallback-review.md`, `loomwright/skills/review-heal/escalation.md`, `loomwright/skills/review-heal/dispatch.md` | HIGH |
| wiring + evidence | `loomwright/commands/review-pr.md`, `loomwright/skills/SKILLS_INDEX.md` (review-heal version cell, only if `version:` changes), `docs/evidence/as14-diet-review-heal.md` | `changelog.d/as14-diet-review-heal.md` | HIGH |
| pinning tests (only if a pinned line moves file) | `loomwright/scripts/test-execution-directive-seam.sh`, `test-no-self-matching-wait.sh`, `test-phase45-rounds-seam.sh`, `test-release-refold.sh`, `test-rules-gate-seams.sh`, `test-automate-dismissed.sh`, `test-dispatch-pr-review.sh` | — | MEDIUM |

> Validator-owned surfaces: `scripts/check-doc-currency.sh` scans `agents/`, `commands/`, `skills/` and `docs/`; `scripts/check-token-budget.sh` measures `commands/review-pr.md` and every `*.md` under `skills/review-heal/` against `loomwright/docs/prompt-token-budgets.json` (shrinking stays under the ceilings; ceilings are NOT lowered here — item 18 does that).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/skills/review-heal/SKILL.md`, `loomwright/docs/rationale/review-heal.md`, `loomwright/docs/loop-inventory/review-heal.md`, `loomwright/scripts/test-review-heal-next-step.sh`, pinning tests | YES |
| Subtask 2 | Subtask 3 | `loomwright/skills/review-heal/SKILL.md`, `loomwright/docs/loop-inventory/review-heal.md`, `loomwright/scripts/test-review-heal-next-step.sh` | YES |
| Subtask 1 | Subtask 3 | `loomwright/commands/review-pr.md`, `loomwright/skills/review-heal/SKILL.md` | YES |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after 1)
- **Batch 3:** Subtask 3 (after 2)
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/pattern-detector/SKILL.md` |
| 2 | `skills/pattern-detector/SKILL.md` |
| 3 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope is large: ~129KB of prose, 377 inventory rows, a 200+ line prose-pin table (Feasibility (Phase 2.5)) | HIGH | `context-bound` split into three serial subtasks; each worker edits only its own section range's rows |
| Deleting prose drops a rule silently | HIGH | D1: a rule row gets its non-prose home BEFORE its prose is deleted; `global` rows are anchor-checked by `test-loop-inventory.sh`; `step-scoped` rows are unchecked by the test, so each worker verifies every step-scoped row's anchor by hand and lists them in the evidence file |
| A moved line breaks a pinning test (prose pins, seam needles, driver `contract` citations) | HIGH | Touched-file invariants list every pin; run the named tests after each file; repoint a test's read in the same change; heading stubs keep `§"…"` citations resolving |
| AC2 gamed by moving text out of the measured set instead of cutting it | MEDIUM | AC2 measures the drain-round read set (core + every drain-mode file), and the all-modes total must be lower too; only fallback/escalation/dispatching-side text may leave the drain-round set |
| Sibling lanes (items 15/16) edit `test-loop-inventory.sh` and other inventory docs in this wave | MEDIUM | Change only the `review-heal)` arm and the review-heal header line; leave other arms and the checker logic untouched |
| Behaviour accidentally changes while rewriting (non-goal) | MEDIUM | Move text, never reword a rule's condition/action; no script edited except the tests' reads; behaviour questions go to the evidence file |
| History regex misses version tags (`vNN.N.N`) | LOW | AC3 pins the requirement's own regex; report version-tag counts as information only |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-18-diet-review-heal.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-19T03:37:19Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/613
- **Branch:** feature/diet-review-heal
- **Files changed:** 13
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 3
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** review-heal prompt diet: drain-round read set 129,051 -> 80,508 bytes (-37.6%), history refs 41 -> 4, no rule/story inventory row left in prose; Earned Fallback Review, Escalation cause and Dispatch Signal split into fallback-review.md / escalation.md / dispatch.md with heading stubs; read rule in commands/review-pr.md. Phase 4.5 PASS after 2 fix iterations (cross-reference drift after the split; stale evidence numbers); 5 LOW findings dismissed. Run note: the Supervisor next-step driver parsed the brief's nested File Impact Map rows as subtasks after subtask 3; FINALIZE ran from the legacy prose on the owner's decision (root-cause fix filed under .supervisor/requirements/proposed/).

## Not verified
- **live /review-pr --until-mergeable drain on the changed prompts** — Validation 3 is a pre-merge owner step (subtask 1)
- **live --until-mergeable drain (fallback-review.md unread on a non-fallback round)** — needs a live PR run; the job's Validation 3 owner step (subtask 2)
- **live /review-pr --until-mergeable drain (Validation 3: fallback-review.md unread on a non-fallback round)** — pre-merge owner step outside this job (subtask 3)
