# Supervisor Job: Touches name shared files at intake

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (orphaned/prunable worktrees under `.claude/worktrees/` and one scratchpad worktree — unrelated to this item)
- **Source requirement:** .supervisor/requirements/2026-11-03-174031-touches-name-shared-files-at-intake.md
- **Base commit:** 4fc0c26297378774dc4e078adf9b8560772bc345

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt/skill edits, one JSON budget file, one bash test — the plugin's own stack |
| 2 | Dependency Availability | GO | No new dependency; `.agent/companions.json` and `plan-waves` already ship |
| 3 | Architecture Fit | GO | Product Owner already fills `## Touches` in its Persist step; the skill already owns the Touches rules and already tells set-writers to propose (never write) companions rules |
| 4 | Scope vs Supervisor Capability | GO | 6 modify + 2 create, single worker |
| 5 | Hard Blockers | CAUTION | The plan needs 2 files outside the item's `## Touches` (the Validation 2 evidence file and the pin test) — asked once at Phase 6 action 1a (`LP-SCOPE`) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make the Product Owner list, in a story's `## Touches`, the existing shared files the story must plug into (found by locating an existing similar feature), surface any contract change that sweep finds, and point requirement writers at `.agent/companions.json` for shared files every story of a kind needs.

**Problem Statement:**
The plugin owner queueing requirement items for `/automate --parallel` needs `## Touches` lists close to the real file sets because `plan-waves` and `right-size` plan from them.
Currently, the Product Owner fills `## Touches` "from your own file-impact reasoning" before reading the code, so lists name the new files a story creates and miss the existing files it must register in (an index, a policy table, kernel wiring, the test that asserts the feature is absent). In loomwright-studio, items 05 and 06 declared 11 and 10 files and needed 26 and 25; one widening also hid a contract change (item 06's `Grant form`). This causes half-size `right-size` verdicts and lanes that discover half their files at Launch Pad.
Success looks like a live `/product-owner` run on a feature that must register in an existing index listing that index file in the persisted story's `## Touches`.

**Owner decisions (2026-11-03, carried from the source requirement):** improve intake with a Product Owner prompt step and a pointer to `.agent/companions.json`; no `plan-waves --lint --deep` mode.

**Non-goals:** no new `plan-waves` mode or flag; no change to `plan-waves` / `right-size` / companions parsing; the Product Owner still never writes `.agent/companions.json` (it proposes a rule; the owner adds it); no new question gate.

**Success metric (post-merge, outside this repo — not a PR acceptance criterion):** on a re-run of the loomwright-studio prompt for item 06, `## Touches` includes `kernel/src/kernel.ts` and `kernel/src/sessions/policy.ts`. loomwright-studio is a different repository, so this is the owner's post-merge measurement; this PR's running-system proof is AC9.

## Acceptance Criteria
- [ ] AC1 (Happy path 1). Given a story that adds a new symbol, route, setting or category, when the Product Owner fills `## Touches`, then its instructions (a `**Shared-file sweep:**` bullet in Responsibilities §"2. Requirement Definition" of `loomwright/agents/product-owner.md`, mirrored byte-identically in `loomwright/commands/product-owner.md`) require finding an existing similar feature in the code and listing the existing files that register, dispatch, configure or test it; and the `**Persist**` step's "FILLED from your own file-impact reasoning" wording names that sweep as an input to `## Touches`.
- [ ] AC2 (Happy path 2). Given that sweep finds a contract change (a response shape, an accepted input form, a refusal a test pins), then the instructions say the story states it in its Acceptance Criteria, or — when the Product Owner cannot tell which form is required — raises it as a **contract-change flag**, an Assumption Check line `- [!] Contract changes: {…, or "None" — filled in at story drafting, raised at the Pre-persist gate}`; never as a file in `## Touches` only. The flag follows the existing missing-proof flag exactly, in both `agents/product-owner.md` and `commands/product-owner.md`: the `[!] Contract changes:` line joins the Assumption Check block and the Output Format block; Responsibilities §"3a. Pre-persist house-rule check" step 3's trigger becomes "Any conflict, missing-proof or contract-change flag" with a `**Contract-change flag**` option bullet that reuses `header: "PO-ASSUME"` and its options "Proceed anyway" / "Refine requirements" / "Abort" ("Proceed anyway" persists the story with the owner's chosen form written as an AC); step 4's `<n>` formula adds `+ contract-change flags`; and the `--non-interactive` parameter descriptions (and the command's "Runs Assumption Check" summary) name the contract-change flag beside the missing-proof flag. The Context Setup step 4 soft gate is unchanged (it runs before drafting).
- [ ] AC3 (Happy path 3). Given the project has `.agent/companions.json`, then `loomwright/skills/user-story-writing/SKILL.md` (a `- **Shared-file sweep.**` bullet in the "Fill them; do not leave the defaults" list under the Story Template's machine-read sections) tells writers that shared files every story of a kind needs belong in a `.agent/companions.json` rule, which the planner adds on its own — proposed to the owner, never written by the writer (consistent with the existing "Never write that file" rule in §"Shaping a set for parallel waves").
- [ ] AC4 (Edge 1). Given no similar feature exists, then the instructions (PO bullet and skill bullet) say the Product Owner states so in the story's Assumptions, and `## Touches` lists what it can name, or the sole line `unknown` when it truly cannot.
- [ ] AC5 (Edge 2). Given a shared file is already added by a companions rule, then the instructions say the story need not list it again.
- [ ] AC6 (Error scenario). Given the Product Owner runs as a subagent or with `--non-interactive`, then the sweep is still followed and adds no question: the sweep itself never asks, the new text adds no new `header:` gate code, and an unresolved contract change rides the existing Pre-persist (3a) gate under `PO-ASSUME` and its existing can't-ask branch (step 4: persist nothing, `po_gate: needs_owner (<n> flags)` with the contract-change flag counted in `<n>`).
- [ ] AC7 (Pin). Given the change, then `loomwright/scripts/test-requirement-shape.sh` gains an (S7) check that `**Shared-file sweep` is present in the PO agent, the PO command and the skill, that the full `**Shared-file sweep:**` line is identical in the PO agent and the PO command (extracted with `grep -F` the way (S5) extracts `**Persist**`), that the skill's sweep bullet names `.agent/companions.json` on the same line, and that the `<n>` formula line in both PO files names `contract-change flags`; plus mutation controls (each mutant gated non-empty and differing from its original) that delete the sweep line from a copy of each file, drift one word of the command's sweep line only, and drop `contract-change flags` from the `<n>` formula of each PO file separately (one agent-only mutant, one command-only mutant), each expecting (S7) to fail; the existing (S5) "identical Persist-step text" mirror check stays green.
- [ ] AC8 (Validation 1 — Static). Given the change, then `bash scripts/check-token-budget.sh` passes with the re-measured `product-owner` agent, `product-owner` command and `user-story-writing` skill entries in `loomwright/docs/prompt-token-budgets.json` (each `measured` = the live proxy weight; `budget` raised to measured + ~10% only where live weight exceeds the current budget), the three mirror rows in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" equal to the JSON, and `bash scripts/ci-local.sh --affected` passes.
- [ ] AC9 (Validation 2 — Running system). Given a live `/loomwright:product-owner` run (headless `claude -p --plugin-dir <checkout>/loomwright "/loomwright:product-owner --non-interactive feature: …"`, namespaced command, run from the fixture root) in a scratch fixture repo whose feature request must register in an existing index (e.g. a `src/commands/index.ts` that registers each command, one existing command, and a test asserting the registered command list; the fixture's CLAUDE.md carries a `## Domain Knowledge` section so no domain flag opens, and the feature request states the expected registered list after the change, so the contract form is knowable and lands as an AC rather than a contract-change flag that would persist nothing under `--non-interactive`), then a committed evidence file `docs/evidence/touches-name-shared-files-at-intake.md` contains the fixture tree, the exact command, and the persisted story's `## Touches` listing that existing index file, plus the column-0 line `Verdict: PASS for Validation 2` outside any fence, and the PR body links to it.
- [ ] AC10 (Release). Given the change, then `changelog.d/touches-name-shared-files-at-intake.md` carries the fragment (headline + prose body, `<!-- bump: minor -->`; the `#808` provenance goes here), the worker writes the fragment and does NOT run `bash scripts/bump-version.sh` (an unfolded fragment merged without a bump is legal — `changelog.d/README.md` — and the next bump folds it, as with the fragments already pending on `main`), and `bash scripts/check-version-bump.sh` passes.

## Scope widening
- docs/evidence/touches-name-shared-files-at-intake.md
- loomwright/scripts/test-requirement-shape.sh
- accepted: LP-SCOPE 2026-11-05

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

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| product-owner prompt | `loomwright/agents/product-owner.md` (625 — one `**Shared-file sweep:**` bullet appended in Responsibilities §2, the PO's single authority for drafting; the procedure detail lives in the skill) · `loomwright/commands/product-owner.md` (709 — the byte-identical mirror of that bullet and of the Persist-line wording) | — | HIGH |
| story-writing skill | `loomwright/skills/user-story-writing/SKILL.md` (334 — the home of the sweep procedure: one bullet in the "Fill them" list) | — | HIGH |
| budgets | `loomwright/docs/prompt-token-budgets.json` (93) · `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1061 — edit the three existing mirror rows in §"Prompt Token Budgets"; the mirror lives there) | — | HIGH |
| pin test | `loomwright/scripts/test-requirement-shape.sh` (278 — append (S7) + its mutation control beside (S5)/(S6), whose helpers it reuses; outside Touches) | — | HIGH |
| release + evidence | — | `changelog.d/touches-name-shared-files-at-intake.md` · `docs/evidence/touches-name-shared-files-at-intake.md` (outside Touches) | HIGH |

> **Validator-owned surfaces:** `scripts/check-token-budget.sh` reads `loomwright/docs/prompt-token-budgets.json` (folded in above); `scripts/check-doc-currency.sh` scans the doc surface including `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (folded in above); `scripts/check-prompt-history-refs.sh` counts history references in the three prompt files against `loomwright/docs/prompt-history-refs-baseline.json` (not modified — the new text must add no history reference).

**Total estimated files:** 6 modify + 2 create

## Touched-file invariants

> Grounded at base `4fc0c26297378774dc4e078adf9b8560772bc345`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/agents/product-owner.md` + `loomwright/commands/product-owner.md`** — keep: the `**Persist**` line byte-identical across both files (pinned by `loomwright/scripts/test-requirement-shape.sh`: `PO agent and command mirror: identical Persist-step text`), with `plan-waves <each persisted file> --lint` still before `the same script's \`right-size <each persisted file>\`` and the aim sentence after both (S5 order check); keep the Touches strict-grammar clause `one entry per line, nothing else (no backticks, no bullets, no globs)`; keep Context Setup step 4's can't-ask branch identical in both files (pinned by `loomwright/scripts/test-non-interactive-gates-seam.sh`: `the branch line differs between agents/product-owner.md and commands/product-owner.md (mirror drift)`); keep the existing soft gate as the only route for Assumption Check flags (`Soft gate with user confirmation (before \`bd create\`)`) — add no `AskUserQuestion` and no new `header:` code; reuse: the skill reference form `skills/user-story-writing/SKILL.md` §"…" instead of restating the procedure; mirror: every new sentence lands in both files with identical text; pinned by: `loomwright/scripts/test-requirement-shape.sh`, `loomwright/scripts/test-non-interactive-gates-seam.sh`, `loomwright/scripts/test-product-seam.sh` (`absent-store message deleted`); history: add no issue number, PR number or dated story to the prompt text (`scripts/check-prompt-history-refs.sh` against `loomwright/docs/prompt-history-refs-baseline.json`, which may only go down — the `#808` provenance belongs in the changelog fragment).
- **`loomwright/skills/user-story-writing/SKILL.md`** — keep: the `## Touches` grammar bullet (`characters \`A-Za-z0-9._/@+-\` only`), the bullet `**\`## Touches\` comes from your own file-impact reasoning.**` (extend, do not delete), the (S5) needles `` `automate-helpers.sh right-size <item>` `` and `small enough to review in one PR, large enough to pay the run's fixed cost; when two stories touch the same files, prefer one story with parts`, the Story Template fence between `## Story Template` and `## Example: Staff Scheduling Story` (S6 reads the first fence there — the new bullet goes outside that fence), and the companions ownership rule `Never write that file: it is a committed standing rule for every later plan, so the owner adds it.`; mirror: the companions shape quoted must match `plan-waves.sh`'s strict schema (`{"when": "<glob>", "add": ["<path>"]}`, as the skill's existing step 3 already quotes it); pinned by: `loomwright/scripts/test-requirement-shape.sh` (S5, S6, M1–M5).
- **`loomwright/docs/prompt-token-budgets.json` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: the `{budget, measured, note}` entry shape under `.agents["product-owner"]`, `.commands["product-owner"]`, `.skills["user-story-writing"]`; mirror: the JSON and the three table rows must agree (`| \`product-owner\`     | 17356 | 16719¹ | 3 |` agents table — keep the `¹` marker; `| \`user-story-writing\` | 5709 | 5190 |`; `| \`product-owner\` | 11537 | 10488 |` commands table); a budget is raised only to measured + ~10% and only when live weight exceeds it, and a raise gets a one-line `> **Raise log …**` entry beside the existing ones; pinned by: `scripts/check-token-budget.sh` (CI step `bash scripts/check-token-budget.sh`).
- **`loomwright/scripts/test-requirement-shape.sh`** — reuse: `ok() { pass=$((pass + 1)); echo "ok   $1"; }` / `no()`, and the mutant idiom of M1–M5 (`if cmp -s "$SKILL" "$T/m1-skill.md"; then no "(M1) mutant not built`) — every mutant gated non-empty and differing from its original before its result counts; keep: the existing `(S5)`/`(S6)`/`(M1)`–`(M5)` checks unchanged.

## Closed enumerations touched

> Sibling grep at base `4fc0c26`: `git grep -n -F -e 'missing-proof' -e 'Missing proof' -- . ':!CHANGELOG.md'` → 21 lines in 7 files (7 in `loomwright/agents/product-owner.md`, 8 in `loomwright/commands/product-owner.md`, 2 in `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, 1 each in, `loomwright/docs/LANE_GATES.md`, `loomwright/docs/prompt-token-budgets.json`, `loomwright/scripts/lane-policy.sh`, `loomwright/skills/user-story-writing/SKILL.md`).

- **contract-change flag** (sibling: missing-proof flag) — must be named in:
  - `loomwright/agents/product-owner.md` + `loomwright/commands/product-owner.md` — the Assumption Check output block (`[!] Missing proof: {story with no nameable Validation proof, or "None" — filled in at story drafting, raised at the Pre-persist gate}`) — extend with `[!] Contract changes:`.
  - same two files — the Output Format block (`[!] Missing proof: [story with no nameable Validation proof, or "None" — raised at the Pre-persist gate, never persisted with an empty Validation]`) — extend.
  - same two files — 3a step 3 trigger (`Any conflict or missing-proof flag (Responsibilities 2)`) and its option bullets (`**Missing-proof flag** — options "Proceed anyway" / "Refine requirements" / "Abort" (\`header: "PO-ASSUME"\`)`) — extend: trigger names the contract-change flag; add a `**Contract-change flag**` bullet reusing `PO-ASSUME`.
  - same two files — 3a step 4 count (`` <n>` = prerequisite flags + architecture conflicts + house-rule conflicts + missing-proof flags ``) and its "(a conflict or missing-proof flag here" open-flag clause — extend.
  - `loomwright/agents/product-owner.md` — the `--non-interactive` parameter line (`a house-rule conflict or a missing-proof flag ⇒ nothing persisted`) — extend.
  - `loomwright/commands/product-owner.md` — the `--non-interactive` parameter (`or a story has no nameable proof (a missing-proof flag)`) and the "Runs Assumption Check" summary (`If prerequisites, architecture conflicts, house-rule conflicts or missing-proof flags are found`) — extend.
  - same two files — the checklist line (`no nameable proof ⇒ missing-proof flag, never an empty section`) — no change: it is the Validation-section checklist item, specific to missing proof; AC1/AC2's sweep is covered by the new bullet.
  - `loomwright/docs/LANE_GATES.md` (`Product Owner assumption-check soft gate, pre-persist house-rule check and missing-proof`) and `loomwright/scripts/lane-policy.sh` (the same description string) — no change: they name `PO-ASSUME`'s gate SITES; the contract-change flag is raised at the pre-persist gate they already name, and `PO-ASSUME`'s options are unchanged.
  - `loomwright/skills/user-story-writing/SKILL.md` (`**Never an empty Validation.**`) — no change: missing-proof-specific; the skill's new sweep bullet states the contract-change rule itself.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (two raise/re-measure log lines) and `loomwright/docs/prompt-token-budgets.json` (a `note`) — no change to those historical lines: logs; this change adds its own note/log line.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-requirement-shape.sh` — (S7) PO agent names the shared-file sweep | delete `**Shared-file sweep` in `loomwright/agents/product-owner.md` |
| `loomwright/scripts/test-requirement-shape.sh` — (S7) PO command names the shared-file sweep | delete `**Shared-file sweep` in `loomwright/commands/product-owner.md` |
| `loomwright/scripts/test-requirement-shape.sh` — (S7) agent/command sweep lines identical | flip `**Shared-file sweep:**` → `**Shared-file sweep:** drifted` in `loomwright/commands/product-owner.md` |
| `loomwright/scripts/test-requirement-shape.sh` — (S7) skill sweep bullet present | delete `**Shared-file sweep` in `loomwright/skills/user-story-writing/SKILL.md` |
| `loomwright/scripts/test-requirement-shape.sh` — (S7) skill sweep bullet names `.agent/companions.json` | on the `**Shared-file sweep.**` line of `loomwright/skills/user-story-writing/SKILL.md` only, remove the `.agent/companions.json` reference (the literal also appears in §"Shaping a set for parallel waves" step 3, so this row is reviewer-applied, not machine-applied) |
| `loomwright/scripts/test-requirement-shape.sh` — (S7) agent `<n>` formula counts contract-change flags | flip `missing-proof flags + contract-change flags` → `missing-proof flags` in `loomwright/agents/product-owner.md` |
| `loomwright/scripts/test-requirement-shape.sh` — (S7) command `<n>` formula counts contract-change flags | flip `missing-proof flags + contract-change flags` → `missing-proof flags` in `loomwright/commands/product-owner.md` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Shared-file sweep at Product Owner intake + companions pointer, pinned, budgets re-measured, live evidence | all | 6 modify, 2 create | `skills/user-story-writing/SKILL.md`, `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/agents/product-owner.md", name: "**Shared-file sweep:**"}
  - {kind: "symbol", path: "loomwright/commands/product-owner.md", name: "**Shared-file sweep:**"}
  - {kind: "symbol", path: "loomwright/skills/user-story-writing/SKILL.md", name: "**Shared-file sweep.**"}
  - {kind: "symbol", path: "loomwright/scripts/test-requirement-shape.sh", name: "(S7)"}
  - {kind: "file", path: "changelog.d/touches-name-shared-files-at-intake.md"}
  - {kind: "symbol", path: "docs/evidence/touches-name-shared-files-at-intake.md", name: "Verdict: PASS for Validation 2"}
requires: []
lanes:
  - "loomwright/agents/product-owner.md"
  - "loomwright/commands/product-owner.md"
  - "loomwright/skills/user-story-writing/SKILL.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/scripts/test-requirement-shape.sh"
  - "changelog.d/touches-name-shared-files-at-intake.md"
  - "docs/evidence/touches-name-shared-files-at-intake.md"
external_requires:
  - "claude CLI (headless `claude -p --plugin-dir`) for the AC9 live /loomwright:product-owner run"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/user-story-writing/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Needs files outside the item's `## Touches` (pin test, Validation 2 evidence file) — Feasibility (Phase 2.5) | MEDIUM | Asked once at Launch Pad Phase 6 (`LP-SCOPE`); both are supporting work (a pin for the new instruction, the evidence the requirement's own Validation 2 demands) |
| A longer Product Owner prompt costs tokens on every run (requirement risk); agent headroom at base is 637 proxy tokens | MEDIUM | Put the procedure in the skill (334 lines, read on demand) and keep the PO bullet to the requirement, the contract-change routing and a pointer; re-measure all three entries in the same change |
| The agent/command mirror drifts elsewhere (the `**Persist**` line or a flag-list edit made in one file only) | MEDIUM | (S5) identical-Persist check; write every new sentence once and paste it into both; the `## Closed enumerations touched` rows name each list in both files |
| A contract-change flag is written but gates nothing (every flag-kind list is closed), or it adds a new question on the subagent / `--non-interactive` path | MEDIUM | Raise it at the Responsibilities 3a Pre-persist gate exactly like the missing-proof flag — trigger, option bullet under the existing `PO-ASSUME`, the step 4 `<n>` count and its can't-ask branch (`po_gate: needs_owner (<n> flags)`) — per `## Closed enumerations touched`; (S7) pins the `<n>` formula; AC6 forbids a new `header:` code |
| A mirrored sweep bullet drifts between agent and command | MEDIUM | (S7) asserts the two `**Shared-file sweep:**` lines are identical, with a one-word-drift mutation |
| A prompt step improves lists but cannot guarantee them (requirement assumption) | LOW | The gate stories (Launch Pad `LP-SCOPE`, lane scope re-gate) remain the safety net; this is prevention only |
| The AC9 live run's fixture opens a Domain Knowledge or prerequisite flag, so the non-interactive PO persists nothing | LOW | Fixture CLAUDE.md carries `## Domain Knowledge`; the feature request names an existing pattern; record the full transcript tail in the evidence file if a retry was needed |
| History reference added to a prompt (`#808`, a date) trips `check-prompt-history-refs.sh` | LOW | Provenance goes in the changelog fragment only |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-05-touches-name-shared-files-at-intake.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-05T14:56:44Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/830
- **Branch:** feature/touches-name-shared-files-at-intake
- **Files changed:** 8
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Product Owner gains a mirrored Shared-file sweep bullet and a contract-change flag raised at the existing 3a PO-ASSUME gate (counted in po_gate's <n>); the story-writing skill points shared files at .agent/companions.json (propose, never write); pinned by (S7) + 7 mutants; budgets re-measured with no raise; live headless /loomwright:product-owner evidence committed. Phase 4.5 code-reviewer PASS on round 1 (1 LOW dismissed below the MEDIUM floor: PO-ASSUME description in lane-policy.sh / LANE_GATES.md omits the contract-change flag).

## Not verified
- **interactive /product-owner Contract-change flag question under PO-ASSUME** — needs a human answering AskUserQuestion (subtask 1)
- **can't-ask branch with an open contract-change flag counted in po_gate's <n>** — not run live (subtask 1)
- **PR body link to docs/evidence/touches-name-shared-files-at-intake.md** — FINALIZE owns the PR body (subtask 1)
