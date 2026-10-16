# Supervisor Job: Size ceilings for skills and commands, not just agents (automate-speed/17)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L4 (lane clone of loomwright)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/17-prompt-size-ratchet.md
- **Base commit:** f5c2d0e23fb717d385047340d7ddb5862153b6e0

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq gate, same stack as the existing agent ratchet |
| 2 | Dependency Availability | GO | jq already required by `scripts/check-token-budget.sh`; no new dependency |
| 3 | Architecture Fit | GO | extends the existing fail-CLOSED ratchet with two more tables read from the same JSON |
| 4 | Scope vs Supervisor Capability | GO | 7 files, single worker (below the Decomposition Threshold) |
| 5 | Hard Blockers | CAUTION | parallel wave: sibling lanes (items 25, 04, 05) may add or grow a skill/command; caught at wave integration by `ci-local.sh` |

**Overall Verdict:** CAUTION

## Task
**Goal:** Every loomwright skill directory and every loomwright command doc has a declared size ceiling in `loomwright/docs/prompt-token-budgets.json`, checked fail-CLOSED by `scripts/check-token-budget.sh` in CI, and every budget `note` is cut to one line.

**Problem Statement:**
Plugin maintainers need on-demand skills and command docs under the same ratchet as agents because those are the runtime prompts that grew (automate-loop ~320KB across its split files, self-heal-advisory ~176KB, `commands/dreaming.md` ~138KB).
Currently, `scripts/check-token-budget.sh` measures only the agents plus their preloaded skills; its own header says command docs and on-demand skills are out of scope. This lets each fix PR add a paragraph with nothing pushing back, and `prompt-token-budgets.json` itself is ~37KB of multi-KB history `note`s.
Success looks like: a skill dir or command doc that grows past its ceiling, a new one without an entry, or an orphaned entry each turns CI red, and the budget JSON is at least 50% smaller.

## Acceptance Criteria
- [ ] AC1 Given a skill dir under the skills dir whose `*.md` files (every `*.md` under that dir, counted recursively — a future `references/` subfolder is measured, never silently skipped) total more proxy tokens (bytes / `proxy_bytes_per_token`, same `proxy_tokens` helper) than its `.skills[<dir>].budget`, when `scripts/check-token-budget.sh` runs, then it exits 1 with a BREACH row naming that dir.
- [ ] AC2 Given a command doc `<stem>.md` in the commands dir with no `.commands[<stem>]` entry, when the gate runs, then it exits 1 with an ERROR row naming the missing entry (same "no budget declared" wording the agent table uses, with the `.commands[...]` key). Same for a skill dir with no `.skills[<dir>]` entry.
- [ ] AC3 Given a `.skills` entry whose dir does not exist (or a `.commands` entry whose `.md` does not exist), when the gate runs, then it exits 1 with an "orphaned budget" ERROR row naming it.
- [ ] AC4 Given a non-integer `.skills`/`.commands` budget, or a skills dir / commands dir that is missing or holds zero entries, when the gate runs, then it exits 1 (fail CLOSED — never a false green). Loose files at the skills root (`SKILLS_INDEX.md`, `SKILL_TEMPLATE.md`) are not skill dirs: they need no entry and are not measured.
- [ ] AC5 Given the committed `loomwright/docs/prompt-token-budgets.json`, then it carries a `.skills` entry for every directory in `loomwright/skills/` and a `.commands` entry for every `loomwright/commands/*.md`, each `{budget, measured, note}` with `budget` = measured + ~10% (integer) at this PR's tree; every `note` in the file (agents included) is a single line under 200 chars; `_comment` and `raise_rule` are cut to a few lines (raise rule: same PR, ONE-line reason in `note`, history goes to `CHANGELOG.md`); and `wc -c` of the file is ≤ 18449 bytes (50% of the 36898 bytes at the base commit). Agent `budget` and `measured` values are unchanged. Byte arithmetic: 14 agents + one entry per skill dir + one per command doc at roughly 100 bytes of key/field lines each, so a new entry's note follows one short convention (e.g. `initial ceiling: measured + ~10% (as17)`); only agent notes may use up to the 200-char limit.
- [ ] AC6 Given `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", then it carries two mirror tables (skills, commands) beside the agent table, and the gate's mirror check covers them exactly as it covers agents: a drifted budget cell, a drifted measured cell, a missing row, a ghost row each exit 1; the agent-table parse stays bounded so a skill/command row is never read as an agent ghost row. The section's raise-rule paragraph states the ONE-line reason rule. In the same edit, every sentence in that file that defers to a budget `note` for reasoning or for a live figure ("Full reasoning in ... `note`", "recorded in the JSON `note` only") is reworded to point at the raise log or `CHANGELOG.md`, and any figure that today lives only in a note is carried into the raise log before the note is cut (house rule 2: the restating copy changes with its authority). The same edit also updates the section's other scope restatements that become false: the opening paragraph (agent `.md` plus preloaded skills only), the "Self-test:" paragraph's `command docs and on-demand skills are not spawn-time weight and are out of scope` and its case list (add the skill/command cases), and the closing paragraph's `(also in each JSON `note`)` claim about preloaded-skill counts.
- [ ] AC7 Given `scripts/test-check-token-budget.sh`, then it adds hermetic cases for AC1–AC4 and AC6 (skill breach, missing skill entry, missing command entry, skill orphan, command orphan, non-integer skill/command budget, empty commands dir, missing/zero-entry skills dir, a nested `*.md` that pushes a skill over its ceiling, skill/command mirror drift/missing/ghost, and a valid agents+skills+commands mirror that passes together), keeps every existing case's assertion (fixtures gain only the minimum entries the new tables need), and the whole self-test passes; `bash scripts/check-token-budget.sh` passes on the live repo.
- [ ] AC8 Given `CLAUDE.md` §"Adding or Modifying Agents", then the new-command and new-skill steps each say in one sentence to declare a ceiling (`.commands[<stem>]` / `.skills[<dir>]` in `loomwright/docs/prompt-token-budgets.json` + the mirror row), with no count or version restated.
- [ ] AC9 Given the change, then `changelog.d/as17-prompt-size-ratchet.md` exists with first line `<!-- bump: minor -->`, no version file (`plugin.json`, `marketplace.json`, `CHANGELOG.md`) is edited (lane in a parallel wave — the release lane bumps), and `bash scripts/check-version-bump.sh` and `bash scripts/check-doc-currency.sh` pass.
- [ ] AC10 Given the requirement's Validation section, then a committed evidence file `docs/evidence/automate-speed-17-prompt-size-ratchet.md` contains the `<passed>/<total>` of `scripts/test-check-token-budget.sh`, the `check-doc-currency.sh` result, the JSON byte count before/after, and the two mutation controls run in a scratch copy (append 10KB to a scratch skill ⇒ red; delete a `.commands` entry ⇒ red, each with its exit code and the BREACH/ERROR line), and the PR body links to it.

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

Conformance note: the budget numbers are not count/version claims (rule 1); the ARCHITECTURE_CONTRACTS mirror tables are a restated copy kept in sync by the gate in the same change (rule 2), which the source requirement asks for explicitly. CLAUDE.md gains no count.

## Touched-file invariants

> Grounded at base `f5c2d0e23fb717d385047340d7ddb5862153b6e0`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`scripts/check-token-budget.sh`** — keep: fail-CLOSED exit 1 on every breach/error (`exit "$exit_code"`), `set -uo pipefail`, the non-integer guard (`non-integer budget in $BUDGET_JSON (must be a positive integer)`), the zero-agent guard (`refusing to pass a 0-agent ratchet`), the orphan rule (`orphaned budget in $BUDGET_JSON`), the proxy label (`OFFLINE PROXY, not an Anthropic token count`), bash 3.2 safety (no `${var//...}` on large strings, sizes from `wc -c`); reuse: the `proxy_tokens()` helper and the `TOKEN_BUDGET_*` env-override pattern (`AGENTS_DIR="${TOKEN_BUDGET_AGENTS_DIR:-loomwright/agents}"`) — add `TOKEN_BUDGET_COMMANDS_DIR` the same way, reuse `TOKEN_BUDGET_SKILLS_DIR` for skill dirs; mirror: the contracts-table parse (`awk '/^## Prompt Token Budgets/{s=1;next}`) and the `TOKEN_BUDGET_CONTRACTS_MD` set-but-EMPTY skip (`CONTRACTS_MD="${TOKEN_BUDGET_CONTRACTS_MD-loomwright/docs/ARCHITECTURE_CONTRACTS.md}"`); update the header's SCOPE paragraph (`Command docs, on-demand skills, and non-preloaded`) so it no longer says commands/skills are out of scope, and drop the literal counts in the header's WHY line (`14 agent prompts x 41 skills`) — house rule 1; fired by: `.github/workflows/ci.yml` step "Check per-agent prompt token budgets" (`bash scripts/check-token-budget.sh`), and `scripts/ci-local.sh` derives it from ci.yml; pinned by: `scripts/test-check-token-budget.sh` needles `no budget declared`, `orphaned budget`, `mirror drift`, `MEASURED cell`, `no row in`, `ghost mirror row`, `contracts mirror file not found`, `non-integer budget`, `inline/flow-style`, `0 preloaded skills`, `over by`, `BREACH`.
- **`scripts/test-check-token-budget.sh`** — keep: the hermetic source line as the first executable line (`. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"`, enforced by `scripts/check-test-hermetic.sh`), `mktemp -d` fixtures with `trap 'rm -rf "$TMP"' EXIT`, never touching the real repo except Case 6 (`case6 live repo passes`), the `check` / `contains` helpers and the final `self-test: OK` line; reuse: `run_gate`, `mk_agent`, `mk_skill`, `mk_contracts` (extend `run_gate` to pass a commands dir; extend `mk_contracts` for the new tables); pinned by: `.github/workflows/ci.yml` (`bash scripts/test-check-token-budget.sh`).
- **`loomwright/docs/prompt-token-budgets.json`** — keep: `proxy_bytes_per_token` (`"proxy_bytes_per_token": 4`), every `.agents[<stem>].budget` and `.measured` value byte-equal (the mirror check compares both); mirror: the ARCHITECTURE_CONTRACTS agent table cells; companions: `.agent/companions.json` rule `loomwright/agents/*.md` adds this file.
- **`loomwright/docs/ARCHITECTURE_CONTRACTS.md`** — keep: the `## Prompt Token Budgets` heading text (the gate's awk anchor) and the agent table row shape `` | `stem` | budget | measured | preloaded | ``; scanned by `scripts/check-doc-currency.sh` (`loomwright/docs/ARCHITECTURE_CONTRACTS.md` in its `FILES` array) — add no count claim.
- **`CLAUDE.md`** — keep: the "Do not restate version numbers or counts in this file" rule; scanned by `scripts/check-doc-currency.sh` (`CLAUDE.md` in its `FILES` array) and by `loomwright/scripts/test-citation-drift.sh` (no bare `file:N` citations).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `scripts/test-check-token-budget.sh` — skill-breach case | in `scripts/check-token-budget.sh`, make the skill-dir breach comparison never true (e.g. delete the line that sets the exit code in the skill BREACH branch) — the case must turn red |
| `scripts/test-check-token-budget.sh` — missing `.skills` / `.commands` entry cases | in `scripts/check-token-budget.sh`, delete the `exit_code=1` line of the skill (resp. command) no-budget branch — red |
| `scripts/test-check-token-budget.sh` — skill / command orphan cases | delete the skill (resp. command) orphan loop's `exit_code=1` line — red |
| `scripts/test-check-token-budget.sh` — empty commands dir case | delete the zero-command guard's `exit 1` — red |
| `scripts/test-check-token-budget.sh` — skill/command mirror budget-drift cases | delete the `exit_code=1` line in the skill (resp. command) mirror budget-cell drift branch — red |
| `scripts/test-check-token-budget.sh` — skill/command mirror measured-drift cases | delete the `exit_code=1` line in the skill (resp. command) MEASURED-cell drift branch — red |
| `scripts/test-check-token-budget.sh` — skill/command mirror missing-row cases | delete the `exit_code=1` line in the skill (resp. command) mirror no-row branch — red |
| `scripts/test-check-token-budget.sh` — skill/command mirror ghost-row cases | delete the `exit_code=1` line in the skill (resp. command) ghost-row loop — red |
| `scripts/test-check-token-budget.sh` — non-integer skill/command budget cases | delete the `exit_code=1` line of the skill (resp. command) non-integer guard — red |
| `scripts/test-check-token-budget.sh` — missing / zero-entry skills dir case | delete the zero-skill-dir guard's `exit 1` — red |
| `scripts/test-check-token-budget.sh` — nested `*.md` counted case (a skill whose only overflow sits in a subfolder breaches) | make the skill measure top-level only (glob `<dir>/*.md` instead of the recursive walk) — red |
| `scripts/test-check-token-budget.sh` — valid agents+skills+commands mirror passes together | restore the unbounded agent-table awk (`s && /^\| `/` over the whole section) so skill/command rows read as agent ghost rows — red |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Skill + command size ceilings, gate, mirror, slim notes | all | 5 modify, 2 create | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "scripts/check-token-budget.sh"}
  - {kind: "symbol", path: "scripts/check-token-budget.sh", name: "TOKEN_BUDGET_COMMANDS_DIR"}
  - {kind: "file", path: "scripts/test-check-token-budget.sh"}
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "autonomous-loop"}
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "dreaming"}
  - {kind: "file", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md"}
  - {kind: "file", path: "CLAUDE.md"}
  - {kind: "file", path: "changelog.d/as17-prompt-size-ratchet.md"}
  - {kind: "file", path: "docs/evidence/automate-speed-17-prompt-size-ratchet.md"}
requires: []
lanes:
  - "scripts/check-token-budget.sh"
  - "scripts/test-check-token-budget.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "CLAUDE.md"
  - "changelog.d/as17-prompt-size-ratchet.md"
  - "docs/evidence/automate-speed-17-prompt-size-ratchet.md"
external_requires:
  - "jq (already required by the gate)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| gate | `scripts/check-token-budget.sh`, `scripts/test-check-token-budget.sh` | — | HIGH |
| budgets | `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | — | HIGH |
| docs/release | `CLAUDE.md` | `changelog.d/as17-prompt-size-ratchet.md`, `docs/evidence/automate-speed-17-prompt-size-ratchet.md` | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` scans `CLAUDE.md` and `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (both already in the map); `scripts/check-test-hermetic.sh` scans `scripts/test-*.sh`; `loomwright/scripts/test-citation-drift.sh` scans committed prose for bare `file:N` citations.

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): sibling lanes in this wave (items 25, 04, 05) may add a new skill dir or command doc, or grow one past measured + ~10%, so the integrated wave tree fails the new gate | MEDIUM | Ceilings are measured on this PR's tree; `wave-build` runs `ci-local.sh` on the integrated branch and stops on red — fix by adding the entry / raising with a one-line note there |
| Hermetic fixtures: new fail-closed rules (missing entry, empty dir) break existing cases 1–5g whose fixtures have skills/commands but no `.skills`/`.commands` tables; cases 3–5d use empty skills dirs and case 5b asserts `no agent .md files found` | MEDIUM | Give each existing fixture the minimum entries / a one-command fixture dir; run the new empty-skills/commands-dir guards AFTER the zero-agent guard so case 5b's message still prints; never delete or loosen an existing assertion |
| `.agent/companions.json` gives no budget-JSON hint for a new command or skill dir (only `loomwright/agents/*.md` maps to it) | LOW | Deferred follow-up (outside this item's declared Touches; the companions `"new": true` lists are pinned to `check-doc-currency.sh`'s FILES by `test-automate-helpers.sh`) — the gate's own missing-entry ERROR names the fix |
| Agent mirror parse reads skill/command rows as agent ghost rows (the existing awk takes every `` | ` `` row in the section) | HIGH | Bound each table parse by its own sub-heading; add a test that a valid skills+commands mirror passes alongside the agent table |
| Shrinking notes deletes the only copy of some raise history, and ARCHITECTURE_CONTRACTS sentences that point at a note ("Full reasoning in ... `note`", "recorded in the JSON `note` only") go stale | MEDIUM | AC6: reword every such pointer to the raise log / `CHANGELOG.md` in the same edit and carry note-only figures into the raise log before cutting; raise logs are left in place |
| Gitignored or untracked `*.md` in a dev checkout's skill dir inflates the measure (project memory: prefer `git ls-files` for repo-scanning gates) | LOW | Over-count only makes the gate stricter (false red locally, never false green in CI); measure ceilings from a clean tree |
| Mutation controls that no-op (invalid mutant) give false evidence | MEDIUM | Run each control in a scratch copy and confirm the mutant differs from the original before reading its exit code |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-15-as17-prompt-size-ratchet.md
```

## Plan Review
- **Decision:** PASS (attempt 3/3; saved by owner "Save and exit")
- **Deferred (LOW):** `scripts/check-doc-currency.sh` header comment describes only the per-agent mirror table — optional widen, file outside lanes.

## Outcome
- **Status:** completed
- **Completed:** 2026-10-15T16:59:05Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/565
- **Branch:** feature/as17-prompt-size-ratchet
- **Files changed:** 7
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** check-token-budget.sh now ratchets every skill dir (recursive *.md) and command doc via .skills/.commands ceilings, fail-CLOSED (breach, missing, orphan, non-integer incl. leading-zero, empty dir, symlinks); mirror tables checked; budget JSON 36898 → 11009 bytes with one-line notes. Self-test 98/98; Phase 4.5 iteration 1 fixed a HIGH (octal false pass) and a MEDIUM (symlink skip); iteration 2 PASS. ground_truth 2/2 pass; risk_classification high_risk=true (advisory).

## Not verified
- **.github/workflows/ci.yml on the Linux runner** — verified on macOS bash 3.2 and PATH bash only (subtask 1)
