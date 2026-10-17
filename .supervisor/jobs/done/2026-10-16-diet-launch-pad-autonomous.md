# Supervisor Job: Prompt diet — Launch Pad and /autonomous carry rules, not stories (automate-speed/13)

## Environment
- **Project:** L6 (lane clone of loomwright, `~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L6`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/13-diet-launch-pad-autonomous.md
- **Base commit:** 142540b8210a4b206e87e2b4349999c9978f8e29

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt files + one bash 3.2/BSD awk test script; no new dependency |
| 2 | Dependency Availability | GO | Item 04 (loop inventory + `test-loop-inventory.sh`) is merged on main (`loomwright/docs/loop-inventory/launch-pad-autonomous.md`, 520 rows) |
| 3 | Architecture Fit | GO | Follows D1/D2 of the automate-speed plan doc; same move-only pattern as the automate-loop split (parallel-automate/22) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~270KB of prose and a 520-row inventory: well over 800 changed lines, so a `context-bound` split into three serial subtasks |
| 5 | Hard Blockers | GO | None |

**Overall Verdict:** CAUTION

## Task
**Goal:** Cut the Launch Pad + `/autonomous` runtime prompts to instructions and short rules: every `story` inventory row moves to a rationale doc, every `rule` row gets a non-prose home (existing script/hook, `step-scoped`, or `global`), and the multi-iteration-only `/autonomous` protocol loads only when the run is not `--single-iteration`.

**Problem Statement:**
The `/automate` main thread needs `agents/launch-pad.md`, `commands/launch-pad.md`, `skills/autonomous-loop/SKILL.md` and `commands/autonomous.md` read inline on every item, because they are short instructions it must follow.
Currently those four files are 270,110 bytes (94,385 + 30,217 + 102,429 + 43,079 at the base commit) and carry history, stories and multi-iteration-only protocol that a `--single-iteration` run (every `/automate` item) never uses. This costs context on every item turn.
Success looks like a single-iteration read set at least 30% smaller with no rule dropped, proved by the inventory and its test.

## Acceptance Criteria
- [ ] AC1 — Given `loomwright/docs/loop-inventory/launch-pad-autonomous.md` after this change, when its rows are read, then no row of kind `story` has home `prose`, and every row of kind `rule` has a home other than `prose` (`script:…`, `hook:…`, `step-scoped`, `global`, or `rationale:<doc>#<anchor>` only for a rule row that was split per Part B and whose rule part has its own row); a committed evidence file `docs/evidence/as13-diet-launch-pad-autonomous.md` contains the awk command that counts `story`/`rule` rows by home and its before/after output, and the PR body links to it.
- [ ] AC2 — Given the four runtime files (`agents/launch-pad.md`, `commands/launch-pad.md`, `skills/autonomous-loop/SKILL.md`, `commands/autonomous.md`), when `wc -c` is taken before (270,110 bytes at the base commit) and after, then the after total is at most 189,077 bytes (≥30% smaller); the evidence file contains both `wc -c` outputs, plus the all-modes total that adds the new `skills/autonomous-loop/multi-iteration.md`, and the PR body links to it.
- [ ] AC3 — Given the history-reference regex `grep -oE '#[0-9]{2,4}\b|queue/[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2}|item [0-9]+'` over the four runtime files, when counted before (34 at the base commit) and after, then the after count is lower; the evidence file contains the command and both counts.
- [ ] AC4 — Given a `rule` row whose home is `script:<file>[ <sub>]` or `hook:<leaf>`, then its prose is deleted from the runtime file (one line may stay only where the model would otherwise attempt the blocked action), and the named script/subcommand or `hooks.json` leaf exists; a rule that would need a NEW hook keeps its prose and is filed as a propose-only draft under `.supervisor/requirements/proposed/` (no hook is added).
- [ ] AC5 — Given every `story` row, then its text lives in `loomwright/docs/rationale/launch-pad-autonomous.md` under a heading whose slug is the row's `rationale:docs/rationale/launch-pad-autonomous.md#<slug>` anchor; a one-line "because" stays in the runtime file only where it blocks a tempting wrong shortcut; a story paragraph containing a rule is split first (the rule gets its own row and home).
- [ ] AC6 — Given `/autonomous --single-iteration` (what `/automate` always passes), when its Step 0 runs, then it reads `commands/launch-pad.md`, `commands/supervisor.md` and `skills/autonomous-loop/SKILL.md` only; the multi-iteration-only protocol (EVALUATE, PR-base verification, the chained review-heal step, Signal 1 / Signal 2, the no-rubric gate, the max-iterations cap, stacked-branch and `--base-branch` mechanics, rubric auto-authoring and freeze) lives in `loomwright/skills/autonomous-loop/multi-iteration.md`, which Step 0 of both `commands/autonomous.md` and `skills/autonomous-loop/SKILL.md` reads only when the run is NOT `--single-iteration`; every moved `###`/`##` section leaves its heading in `SKILL.md` with a one-line pointer to the new file, so existing `§"…"` citations keep resolving.
- [ ] AC7 — Given `loomwright/scripts/test-loop-inventory.sh`, when it checks a row, then a row whose home is `global` is anchor-checked exactly like a `prose` row (deleting its anchored line from a scratch copy prints `FAIL <id>: anchor not found in <file>` and exits 1), and a row whose home is `rationale:<doc>#<anchor>` fails with `FAIL <id>: rationale doc not found: <doc>` when `<doc>` (relative to the plugin root) is not readable (the check line contains `readable(root "/" rdoc)`) and with `FAIL <id>: rationale anchor not found: <anchor>` when no `#`/`##`/`###` heading in it slugs to `<anchor>` (slug = lowercase; spaces → `-`; characters other than `[a-z0-9-]` dropped; the comparison line contains `slug(hl) == ranc`); each new branch has a red fixture leg; `step-scoped`/`hook:` homes stay unchecked as today; and the fixture base copies `$PLUGIN/docs/rationale` into the scratch tree when that directory exists (beside the existing `cp -R "$PLUGIN/docs/loop-inventory"`), so a green leg stays green once `rationale:` rows exist — subtask 1 adds one green leg with a `rationale:` row pointing at a scratch rationale doc to prove it.
- [ ] AC8 — Given the `launch-pad-autonomous` group, then `test-loop-inventory.sh`'s group map and the inventory's `## Sources` both list `skills/autonomous-loop/multi-iteration.md`, and every `###`/`####` heading in it is the `h:` anchor of a row.
- [ ] AC9 — Given every invariant in CLAUDE.md §"Failure-Mode Invariants" that appears in this group (bimodal fail-closed/fail-safe, every question gate has a named can't-ask branch, the `--non-interactive-fallback` forwards), then it stays in the runtime prompt or in an enforcing script/hook; every named can't-ask status the seam tests grep still resolves (see Touched-file invariants).
- [ ] AC10 — Given the change, then no behaviour changes: a behaviour question found while moving text is recorded in the evidence file's "Behaviour questions" section, not fixed; no count or version claim is added to moved text; any `file:line` citation moved into the rationale doc is pinned or replaced by a descriptive anchor.
- [ ] AC11 — Given the release mechanics, then a fragment `changelog.d/as13-diet-launch-pad-autonomous.md` exists with `<!-- bump: minor -->` semantics per `changelog.d/README.md`, and the version files are not hand-edited (`bash scripts/check-version-bump.sh` passes).
- [ ] AC12 — Given the gates, when run, then `bash loomwright/scripts/test-loop-inventory.sh`, `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh`, `bash loomwright/scripts/test-non-interactive-gates-seam.sh`, `bash loomwright/scripts/test-rule-conformance-seam.sh`, `bash loomwright/scripts/test-pr-body-evidence-seam.sh`, `bash loomwright/scripts/test-closed-enum-pins-seam.sh`, `bash loomwright/scripts/test-run-lock.sh`, `bash loomwright/scripts/test-agent-memory-permission.sh`, `bash loomwright/scripts/test-build-capabilities.sh` and `bash loomwright/scripts/test-verify-provides.sh` all exit 0, and the evidence file records each `<passed>/<total>` (or exit line) — Validation 1; and a mutation control (delete one `global` row's anchored line from a scratch copy ⇒ `test-loop-inventory.sh --root <scratch>` exits 1 naming that row) is recorded in the evidence file — Validation 2.
- [ ] AC13 — Given the source requirement's Validation 3 (a running-system step: one real item that exercises this group after the change, with the phase's result block pasted), when the job finishes, then the evidence file has a "Not run — Validation 3" section stating that it is a pre-merge owner step outside this job: before merge the owner either runs one live item on the changed prompts and pastes its fenced result block into the PR body, or waives V3 through the human-only `AUT-WAIVE` ask that `/automate`'s `validation-gate` raises; so the gap is visible and the gate fails closed; this job never fabricates that result block.

**Evidence rule:** AC1–AC3, AC10 and AC12 put their numbers in the committed evidence file `docs/evidence/as13-diet-launch-pad-autonomous.md` (Markdown, a File Impact Map create); the PR body only links to it.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory

## Touched-file invariants

> Grounded at base `142540b8210a4b206e87e2b4349999c9978f8e29`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/test-loop-inventory.sh`** — keep: static bash 3.2 + BSD awk only, `Static: bash 3.2 + BSD userland, awk/cp/cmp/mktemp only`; the mutant guard `each mutant is checked non-empty` before a red leg is trusted; exit contract `Exit 0 = pass, 1 = fail`; reuse: the existing `bad(` helper and `run_leg` / `expect_red` / `expect_green` fixture helpers, and the `set_cell` helper for row edits; mirror: the home grammar in its header `global or rationale:<doc>#<anchor>` (subtask 2 rewrites the inventory intro's stale sentence `Every \`home\` is \`prose\` today` to state the homes this group now uses, matching that header); keep `step-scoped` exempt (the existing leg `exemption: home step-scoped, anchor gone` stays green — sibling item 06 may move rows into driver output); keep the vendor-coupling note `names no vendor-coupling token`; pinned by: itself (CI runs every `loomwright/scripts/test-*.sh`).
- **`loomwright/agents/launch-pad.md`** — keep: every named can't-ask status in its own section — `clarification_needed_non_interactive` (Phase 2), `no_go_non_interactive` (Phase 2.5), `needs_human_non_interactive` (Phase 5.5/6), `save_requires_flag_non_interactive`, `plan_review_fail_non_interactive`, `rule_conflict_non_interactive`; the `- **Can't-ask rule:**` line (also present, identical in meaning, in `commands/launch-pad.md`); the Plan Reviewer spawn text `Output a PLAN_REVIEW_RESULT block` and the `--- GATE PARSE ---` / `--- APPLICABLE RULES ---` markers; the Phase 7 `LAUNCH_PAD_RESULT` emission block; the `### Agent memory write permission` heading; mirror: `scripts/validate-launch-pad-result.py` key set (`schema_version`, `status`, `saved_brief_path`, `summary`, `cmd_bullets_stripped_non_interactive`); pinned by: `test-non-interactive-gates-seam.sh` (`section_has_status`, `lp_rule`), `test-rule-conformance-seam.sh`, `test-pr-body-evidence-seam.sh`, `test-closed-enum-pins-seam.sh`, `test-agent-memory-permission.sh`, `test-build-capabilities.sh` (`Output a PLAN_REVIEW_RESULT block`), `test-verify-provides.sh` (`LAUNCHPAD=`), and the `.agents["launch-pad"]` ceiling in `loomwright/docs/prompt-token-budgets.json` (only lower is safe).
- **`loomwright/commands/launch-pad.md`** — keep: the `- **Can't-ask rule:**` line and the Phase 2.5 `no_go_non_interactive` text (`section_has_status "(g) commands/launch-pad.md NO-GO"`); the inline-execution banner `Execute this workflow inline as the main thread`; pinned by: `test-non-interactive-gates-seam.sh`, `test-rule-conformance-seam.sh` (`LPC=`), `test-pr-body-evidence-seam.sh` (`LPC=`), `test-closed-enum-pins-seam.sh` (`LPC=`).
- **`loomwright/skills/autonomous-loop/SKILL.md`** — keep (in SKILL.md or, after AC6, in a file the seam test also reads — update the test's `AL_SKILL` read in the same change if a status moves): `non_interactive_without_fallback`, `rubric_gate_closed_non_interactive`, `no_rubric_in_non_interactive`, `review_heal_escalated_non_interactive`, `pr_base_verify_skipped_non_interactive`, `launch_pad_cant_ask_non_interactive`; the `## PLAN` section's `**Launch Pad forward` paragraph (`al_plan=` awk reads `/^## PLAN/`); inside `## PLAN` the rubric paragraphs the (r) leg greps — `**Conditional auto-authoring directive`, `**Never under `--non-interactive-fallback`:**` (carries `no_rubric_in_non_interactive`), `**Non-interactive no-op:**` — and, anywhere in the file, `**Auto-forwarded flags (the complete `/supervisor` forward set):**` (`sv_set=`); if AC6 moves any of these paragraphs out of `## PLAN` / out of `SKILL.md`, repoint that test read in the same change (the (r) leg and `sv_set=` must still find them); the INIT run-lock acquire with `--session-id` (`check_acquire_has_session_id "autonomous-loop SKILL INIT"`); the `{basename(current_brief_path)}` convention cited by `build-context-digest.sh`; frontmatter `version:` (SKILLS_INDEX row); pinned by: `test-non-interactive-gates-seam.sh`, `test-run-lock.sh`, and the `.skills["autonomous-loop"]` ceiling (counts every `*.md` under the dir, so `multi-iteration.md` is measured too).
- **`loomwright/commands/autonomous.md`** — keep: the forward-set note naming the separate Launch Pad forward, the flow-diagram line showing the PLAN-step Launch Pad forward, and the `--non-interactive-fallback` row text `separately to the inlined Launch Pad`; the inline-execution banner; pinned by: `test-non-interactive-gates-seam.sh` (`AUT_CMD=`), `check-doc-currency.sh` (version/count claims), and the `.commands["autonomous"]` ceiling.
- **`loomwright/scripts/test-loop-inventory.sh` fixture base** — keep: the fixture base mirrors every doc a home can reference — after subtask 1 it copies `docs/rationale` beside `cp -R "$PLUGIN/docs/loop-inventory"`, and `new_leg` copies the whole `$BASE/loomwright/docs`; subtask 3 adds `multi-iteration.md` to the `launch-pad-autonomous)` arm of `group_sources` only (no other arm changes).
- **Pinning tests (`test-non-interactive-gates-seam.sh`, `test-rule-conformance-seam.sh`, `test-pr-body-evidence-seam.sh`, `test-closed-enum-pins-seam.sh`, `test-run-lock.sh`)** — edited ONLY to repoint a read at the file/section a pinned line moved to; never loosen a needle, never delete an assertion; keep each test's `pipefail-safe` capture idiom (`Captured, not piped into grep -q`).
- **`loomwright/docs/loop-inventory/launch-pad-autonomous.md`** — keep: the four `## ` sections in order (Sources, Inventory, Gap list (ordered by risk), Counts), the nine-column header, ids never reused (`LP-` prefix), gap list and counts recomputed from the table; pinned by: `test-loop-inventory.sh`.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-loop-inventory.sh` — red leg "global row anchor gone" | flip `hm == "global"` → `hm == "global-mutant"` in `loomwright/scripts/test-loop-inventory.sh` (after the change `hm == "global"` occurs exactly once: in the live-anchor branch, no longer in the exemption line) |
| `loomwright/scripts/test-loop-inventory.sh` — red leg "rationale anchor not found" | flip `slug(hl) == ranc` → `1` in `loomwright/scripts/test-loop-inventory.sh` (every heading matches, so the leg's expected FAIL never prints) |
| `loomwright/scripts/test-loop-inventory.sh` — green leg "rationale row resolves in a scratch rationale doc" | flip `slug(hl) == ranc` → `0` in `loomwright/scripts/test-loop-inventory.sh` (no heading matches, so the green leg goes red) |
| `loomwright/scripts/test-loop-inventory.sh` — red leg "rationale doc not found" | flip `readable(root "/" rdoc)` → `1` in `loomwright/scripts/test-loop-inventory.sh` (a missing doc is treated as present, so the leg's expected FAIL never prints) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Inventory checker: anchor-check `global` and `rationale:` homes | AC7, AC12 (mutation control) | 1 modify, 0 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Launch Pad pair diet + rationale doc | AC1, AC4, AC5, AC9, AC10 for `agents/launch-pad.md` + `commands/launch-pad.md` rows | 3 modify, 1 create | `skills/pattern-detector/SKILL.md` | BLOCKED (by #1) |
| 3 | /autonomous pair diet + load-by-mode + evidence + fragment | AC1–AC6, AC8–AC13 for `skills/autonomous-loop/SKILL.md` + `commands/autonomous.md` rows | 5 modify, 3 create | `skills/pattern-detector/SKILL.md` | BLOCKED (by #2) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/test-loop-inventory.sh", name: "rationale anchor not found"}
requires: []
lanes:
  - "loomwright/scripts/test-loop-inventory.sh"
external_requires: []

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/docs/rationale/launch-pad-autonomous.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/test-loop-inventory.sh", name: "rationale anchor not found"}
lanes:
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/docs/rationale/launch-pad-autonomous.md"
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
  - "loomwright/scripts/test-non-interactive-gates-seam.sh"
  - "loomwright/scripts/test-rule-conformance-seam.sh"
  - "loomwright/scripts/test-pr-body-evidence-seam.sh"
  - "loomwright/scripts/test-closed-enum-pins-seam.sh"
  - ".supervisor/requirements/proposed/"
external_requires: []

# Subtask 3
provides:
  - {kind: "file", path: "loomwright/skills/autonomous-loop/multi-iteration.md"}
  - {kind: "file", path: "docs/evidence/as13-diet-launch-pad-autonomous.md"}
  - {kind: "file", path: "changelog.d/as13-diet-launch-pad-autonomous.md"}
requires:
  - {from: "2", kind: "file", path: "loomwright/docs/rationale/launch-pad-autonomous.md"}
lanes:
  - "loomwright/skills/autonomous-loop/SKILL.md"
  - "loomwright/skills/autonomous-loop/multi-iteration.md"
  - "loomwright/commands/autonomous.md"
  - "loomwright/docs/rationale/launch-pad-autonomous.md"
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
  - "loomwright/scripts/test-loop-inventory.sh"
  - "loomwright/scripts/test-non-interactive-gates-seam.sh"
  - "loomwright/scripts/test-run-lock.sh"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "docs/evidence/as13-diet-launch-pad-autonomous.md"
  - "changelog.d/as13-diet-launch-pad-autonomous.md"
  - ".supervisor/requirements/proposed/"
external_requires: []
```

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| checker | `loomwright/scripts/test-loop-inventory.sh` | — | HIGH |
| launch-pad | `loomwright/agents/launch-pad.md`, `loomwright/commands/launch-pad.md`, `loomwright/docs/loop-inventory/launch-pad-autonomous.md` | `loomwright/docs/rationale/launch-pad-autonomous.md` (NEW directory `loomwright/docs/rationale/`, named by the source requirement's Touches; parent `loomwright/docs/` exists) | HIGH |
| autonomous | `loomwright/skills/autonomous-loop/SKILL.md`, `loomwright/commands/autonomous.md`, `loomwright/docs/loop-inventory/launch-pad-autonomous.md`, `loomwright/docs/rationale/launch-pad-autonomous.md`, `loomwright/scripts/test-loop-inventory.sh` (group map) | `loomwright/skills/autonomous-loop/multi-iteration.md`, `docs/evidence/as13-diet-launch-pad-autonomous.md`, `changelog.d/as13-diet-launch-pad-autonomous.md` | HIGH |
| pinning tests (only if a pinned line moves) | `loomwright/scripts/test-non-interactive-gates-seam.sh`, `test-rule-conformance-seam.sh`, `test-pr-body-evidence-seam.sh`, `test-closed-enum-pins-seam.sh`, `test-run-lock.sh`; `loomwright/skills/SKILLS_INDEX.md` (autonomous-loop version cell, only if its `version:` changes) | — | MEDIUM |

> Validator-owned surfaces: `scripts/check-doc-currency.sh` scans `agents/`, `commands/`, `skills/` and `docs/`; `scripts/check-token-budget.sh` measures `agents/launch-pad.md`, both command docs and every `*.md` under `skills/autonomous-loop/` against `loomwright/docs/prompt-token-budgets.json` (shrinking stays under the ceilings; ceilings are NOT lowered here — item 18 does that).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 3 | `loomwright/scripts/test-loop-inventory.sh` | YES |
| Subtask 2 | Subtask 3 | `loomwright/docs/loop-inventory/launch-pad-autonomous.md`, `loomwright/docs/rationale/launch-pad-autonomous.md`, `loomwright/scripts/test-non-interactive-gates-seam.sh`, `.supervisor/requirements/proposed/` | YES |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after 1)
- **Batch 3:** Subtask 3 (after 2)
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |
| 2 | `skills/pattern-detector/SKILL.md` |
| 3 | `skills/pattern-detector/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope is large: 270KB of prose and 520 inventory rows (Feasibility (Phase 2.5)) | HIGH | `context-bound` split into three serial subtasks; each worker edits only its own file pair's rows |
| Deleting prose drops a rule silently | HIGH | D1: a rule row gets its non-prose home BEFORE its prose is deleted; `global` rows are now anchor-checked (subtask 1); `step-scoped` rows stay unchecked by the test, so subtask 2/3 workers verify each step-scoped row's anchor by hand and list them in the evidence file |
| A moved line breaks a pinning test (named can't-ask statuses, Can't-ask rule line, forward-set note) | HIGH | Touched-file invariants list every pin; run the seam tests after each file; if a pinned line moves file, move the test's read in the same change |
| Moving multi-iteration sections out of `SKILL.md` breaks `§"…"` citations elsewhere (supervisor, review-heal, docs) | MEDIUM | AC6: each moved heading stays in `SKILL.md` with a one-line pointer; `test-citation-drift.sh` must stay green |
| Sibling lanes 14/15/16 (later waves) and 06 (this wave) also edit `test-loop-inventory.sh` / inventory docs | MEDIUM | Change only the anchor-check branch and the `launch-pad-autonomous` group-map arm; leave `step-scoped` exempt (item 06 may rely on it) |
| Behaviour accidentally changes while rewriting (non-goal) | MEDIUM | Move text, never reword a rule's condition/action; behaviour questions go to the evidence file, not into the diff |
| History regex misses version tags (`vNN.N.N`) | LOW | AC3 pins the requirement's own regex; report version-tag counts too as information only |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-16-diet-launch-pad-autonomous.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-16T05:19:05Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/573
- **Branch:** feature/as13-diet-launch-pad-autonomous
- **Files changed:** 16
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Launch Pad + /autonomous prompt diet: four-file single-iteration read set 270,110 -> 158,557 bytes (-41.3%), history refs 34 -> 5, no story/rule inventory row left in prose, multi-iteration protocol in skills/autonomous-loop/multi-iteration.md loaded by mode; Phase 4.5 PASS after 2 fix iterations (stale pointers, evidence wording); ground truth 2/2.

## Not verified
- **/launch-pad live run on the changed prompts** — no live Launch Pad run; Validation 3 is a pre-merge owner step (subtask 2)
- **/autonomous --single-iteration live run on the changed prompts (Validation 3)** — pre-merge owner step (subtask 3)
- **/autonomous multi-iteration live run (conditional read of multi-iteration.md)** — no live runtime; prose-only (subtask 3)
