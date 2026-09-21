# Supervisor Job: Ship an opt-in status line and make the agent colour legend derived

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — modified 2026-09-02)
- **Git:** clean (0 files), branch: main @ 2c1cc75 (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2
- **Source requirement:** .supervisor/requirements/loom-floor-ui/02-status-line.md

Warnings (non-blocking):
1. Five orphaned `.claude/worktrees/*` checkouts exist from prior runs. Harmless here (this brief uses the Single-Agent Path, no new worktree), but they mean a bare `git worktree list` is noisy.
2. `jq` is `jq-1.7.1-apple` at `/usr/bin/jq`. Both new scripts hard-depend on it and must `command -v jq` guard rather than assume.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash + jq, matching the 60+ existing `loomwright/scripts/*.sh`. No new language, no new runtime dep. |
| 2 | Dependency Availability | GO | `jq` present and already a hard dep of `build-insights.sh`, `automate-helpers.sh`, `setup-memory.sh`. `git`/`gh` present. |
| 3 | Architecture Fit | GO | `/setup` already has 8 modules and one of them (`memory`) is script-backed by `setup-memory.sh` + `test-setup-memory.sh` — an exact precedent for a 9th script-backed module. |
| 4 | Scope vs Supervisor Capability | CAUTION | Three deliverables + three self-tests + a doc/CI/release surface (18 files, counted from the lane list). Comfortably inside one worker's context, but it is the largest single-subtask brief in this queue. See `## Configuration` for why it is NOT split. |
| 5 | Hard Blockers | CAUTION | No blocker, but two hard-won constraints must be honoured: the vendor-coupling ratchet (Risk 1) and the user's **pre-existing** `statusLine` (Risk 2). Both are named risks below, not surprises. |

**Overall Verdict:** GO

## Task
**Goal:** Ship `status-line.sh` (an opt-in, fail-safe one-line run report), wire it through a new `/setup statusline` module that never touches the user's `settings.json` without consent, and replace the hand-maintained "Color Legend (Status Line)" table with generated output plus a CI check so it cannot drift again.

**Problem Statement:**
A Loomwright user needs to see what a run is doing without reading `.supervisor/state.md` by hand, because the plugin has **zero** visual surface — verified 2026-09-02: `grep -rn "statusLine"` over the tracked tree returns **0 hits**, so the `statusLine` surface Claude Code offers is entirely unused.

Currently the only way to know a run's phase is to open the state file. This causes a run to feel opaque exactly while it is long-running, which is when the user most wants a signal.

The same neglect already produced measurable drift: `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Color Legend (Status Line)" carries **12** rows while **14** agents declare a `color:` in frontmatter. Missing: `review-pr-runner` (`#00CED1`) and `rubric-grader` (`#9ACD32`) — independently re-measured 2026-09-02, matching the requirement's count exactly. The 12 present rows all agree with frontmatter, so this is omission, not contradiction.

Success looks like: one honest line the user opts into, that degrades instead of breaking; and a legend that is generated output with a CI check, so the 2026-09-01 drift is closed by mechanism rather than by hand.

## Acceptance Criteria
- [ ] Given the rendered status line, when it is inspected, then it contains **no active-agent field**, and no code path infers liveness from `token_ledger` recency or any other proxy — grep-checkable. (Item 01 closed NO-GO and shipped no emitter, so no `agent_spawn` event exists in any log; the field is unsatisfiable, not merely unmet.)
- [ ] Given a missing `state.md`, an unparseable `state.md`, and an empty session log (three separate cases), when `status-line.sh` runs, then it prints a degraded line and exits 0 each time.
- [ ] Given a `~/.claude/settings.json` that fails to parse, when the setup module applies, then it **aborts** and writes nothing.
- [ ] Given a valid `~/.claude/settings.json`, when the setup module applies, then a timestamped backup exists before the write, and every key unrelated to `statusLine` is preserved **byte-for-byte** — asserted by diffing the two documents with `statusLine` removed, not by spot-checking individual keys.
- [ ] Given a `~/.claude/settings.json` that **already carries a `statusLine` this plugin did not write**, when the setup module applies, then it does **not** overwrite it: it reports the existing value and requires an explicit opt-in flag to replace. (The owner's live settings carry exactly this case — `statusLine.command` = `~/.claude/statusline-command.sh`.)
- [ ] Given the generated legend, when it is emitted, then it contains **14** rows and each row's hex byte-matches that agent's frontmatter `color:`; deleting a `color:` line or adding a 15th agent fails the check.
- [ ] Given the `gen-color-legend.sh --check` invocation in `scripts/check-doc-currency.sh` is reverted (the **caller**, not the generator), when the gate runs against a fixture where legend and frontmatter genuinely disagree, then the gate wrongly PASSES — proving the wired check is what actually **executed**, not merely that it is reachable. The control must assert the specific diagnostic, not merely a non-zero exit (a syntax error also exits non-zero).
- [ ] Given the legend is regenerated, when `ARCHITECTURE_CONTRACTS.md` is inspected, then the table sits between a `<!-- loomwright:color-legend BEGIN (generated by gen-color-legend.sh) -->` / `<!-- loomwright:color-legend END -->` sentinel pair — the namespaced form the repo already reasoned for at `RESULT_SCHEMAS.md`'s requirement-closeout block, so an idempotent re-stamp keys off the marker — making the generator's write provable and the `provides` token unsatisfiable by an untouched file.
- [ ] Given a fixture agent whose `color:` is a hex that is **not** a CSS named colour, when the generator runs, then that row's Color cell is `—` rather than a guessed name — exercising the fallback branch, which the 14 live hexes never reach.
- [ ] Given a fixture agent whose `color:` is a valid CSS named colour **outside the 14 in use** (e.g. `#FA8072`), when the generator runs, then that row's Color cell reads `Salmon` — proving the lookup is the **published standard**, not a 14-entry subset keyed to today's agent set. Paired with the previous criterion, the two fixtures pin both branches; without this one a subset implementation passes by returning `—` for everything it does not know.
- [ ] Given a new module is added, when the module surfaces are inspected, then all four enumerations are updated in this same change: the Pattern 2 registry row in `loomwright/skills/setup/SKILL.md` (mandated by the "New modules append a row here AND a flow section" sentence directly below that registry table), the flow section in `loomwright/commands/setup.md`, the "across 8 modules" claim in `agent-help.md`'s `/setup` Purpose paragraph, and the `/setup` row in `README.md`'s command table. No CI gate covers any of these — `check-doc-currency.sh` has no module-count check (verified), so `doc-currency-green` stays green while all four rot. (Anchors are descriptive, not line numbers, because this same subtask edits all four files and would invalidate its own pointers.)
- [ ] Given `loomwright/skills/setup/SKILL.md` is materially changed by adding the registry row, when the skills-index gate runs, then it exits 0 — its frontmatter `version:` is bumped `1.2.0` → `1.3.0` with `lastUpdated:` set to the change date, AND the Version and lastUpdated cells of the `setup/` row in `loomwright/skills/SKILLS_INDEX.md` are updated to match. `scripts/check-skills-index-sync.sh` fails **closed** on that parity, and its own rule is "index follows skill" — so bumping the skill without the index row is red CI, and bumping neither silently misrepresents a changed skill.
- [ ] Given the module writes `~/.claude/settings.json` from a script, when `loomwright/commands/setup.md` §"Constraints (every module)" is read, then it carries a `statusline` bullet declaring that module's sanctioned write domain (`~/.claude/settings.json` ONLY, via `setup-statusline.sh`; backup-first, parse-gated, consent-bearing; nothing else under `~/.claude/`), with the mirror item added to the setup skill's quality checklist. Without it the module violates the command's own declared write constraint — `memory` and `rules` each got their own bullet for exactly this reason.
- [ ] Given the no-arg `/setup` dashboard, when it renders, then its `AskUserQuestion` option set is still **exactly 4** — `statusline` folds into an existing bucket or a nested question, per the explicit instruction at `loomwright/commands/setup.md:103` that the set "must NOT be grown when a module is added" — and a row for it is added to the module-status table.
- [ ] Given the module has been applied, when it is removed/disabled, then the prior `settings.json` state is restored.
- [ ] Given the new scripts are staged, when `scripts/check-vendor-coupling.sh` runs, then it exits 0 — with any new allowance **measured** via `--print-allowances` and declared in `loomwright/docs/vendor-coupling-manifest.json` in this same PR.

## Outcomes Rubric
- One honest line, live, opt-in, that degrades instead of breaking.
- The legend can no longer drift, and the drift found on 2026-09-01 is closed by the
  mechanism rather than by hand.
- ~~01's pairing is confirmed working on a real run before a week is spent on 03 and 04.~~
  **Void as of 2026-09-02** — 01 closed NO-GO and shipped no emitter, so there is no
  pairing to confirm; this bullet was unsatisfiable, not merely unmet. In its place:
  the absent active-agent field is *honestly* absent — omitted rather than guessed,
  and no code path infers liveness from a proxy.
- The user's `settings.json` is never touched without consent and never left corrupt.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Status line, consent-bearing `/setup statusline` module, and a derived colour legend | AC 1-16 (all) | 12 modify, 6 create | `skills/setup/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

```yaml
# Subtask 1 — the whole item (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/status-line.sh"}
  - {kind: "file", path: "loomwright/scripts/setup-statusline.sh"}
  - {kind: "file", path: "loomwright/scripts/gen-color-legend.sh"}
  - {kind: "file", path: "loomwright/scripts/test-status-line.sh"}
  - {kind: "file", path: "loomwright/scripts/test-setup-statusline.sh"}
  - {kind: "file", path: "loomwright/scripts/test-gen-color-legend.sh"}
  - {kind: "symbol", path: "loomwright/commands/setup.md", name: "## Module: statusline"}
  - {kind: "symbol", path: "loomwright/skills/setup/SKILL.md", name: "| `statusline` |"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "<!-- loomwright:color-legend BEGIN (generated by gen-color-legend.sh) -->"}
requires: []
lanes:
  - "loomwright/scripts/status-line.sh"
  - "loomwright/scripts/setup-statusline.sh"
  - "loomwright/scripts/gen-color-legend.sh"
  - "loomwright/scripts/test-status-line.sh"
  - "loomwright/scripts/test-setup-statusline.sh"
  - "loomwright/scripts/test-gen-color-legend.sh"
  - "loomwright/commands/setup.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/commands/agent-help.md"
  - "README.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "scripts/check-doc-currency.sh"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "CLAUDE.md"
external_requires:
  - "Claude Code `statusLine` settings key — schema {type: \"command\", command: \"<path>\"}, verified against the owner's live ~/.claude/settings.json on 2026-09-02"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single, independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | n/a (single subtask) | n/a |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/setup/SKILL.md` (module protocol authority — owns Pattern 2's registry and Pattern 3's `~/.claude/settings.json` jq deep-merge rules that ACs 3-5 restate), `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Vendor-coupling ratchet breach.** `setup-statusline.sh` must name `~/.claude/settings.json`; `.claude/` is one of the four `vendor_tokens`, and a NEW file under `loomwright/scripts/*` is CORE with allowance **0**. This is the exact failure that reddened CI on item 01 (PR #170). | HIGH | Stage the new files (`git add`), run `bash scripts/check-vendor-coupling.sh --print-allowances`, and declare the **measured** allowances in `loomwright/docs/vendor-coupling-manifest.json` in this same PR. Declare measured numbers — do NOT adapter-exempt the new scripts (item 01 explicitly rejected that route). Note the gate only sees TRACKED files, so an unstaged new file is invisible locally and green-looks-fine until CI. |
| **The manifest can breach its own allowance.** `loomwright/docs/vendor-coupling-manifest.json` is scanned against its own allowance (currently **5**), and its `allowances_note` records a prior **4→5 self-raise caused purely by prose naming a vendor token**. Declaring the new allowances invites an explanatory note, and a note writing `~/.claude/settings.json` literally would breach it — a second red-CI cycle *after* Risk 1's mitigation is already applied. | MEDIUM | After editing the manifest, re-run `--print-allowances` and bump the manifest's OWN entry in the same edit if the new note names a vendor token — or write the note without the literal token. |
| **Clobbering the user's existing status line.** The owner's live `~/.claude/settings.json` already has `statusLine.command` = `~/.claude/statusline-command.sh`. The requirement's AC only protected keys *unrelated* to `statusLine`, so a naive deep-merge would silently destroy the user's own status line. | HIGH | AC 5 added. Apply is CONSENT-BEARING (mirroring `/setup memory` §"Offer — CONSENT-BEARING (never a silent default)"): a pre-existing foreign `statusLine` is reported and preserved; replacing it requires an explicit flag. Record the prior value so `remove` can restore it (AC 15). |
| **`stat`/`date` flavour trap.** Computing "age of last event" invites `stat -f %m` (BSD) or `date -d` (GNU) — the former *succeeds with garbage* on Linux CI, and `set -u` arithmetic on a non-numeric silently empties the field. macOS-green ≠ CI-green here. | MEDIUM | Derive age from the log line's own `ts` field (never file mtime, avoiding `stat` entirely). Parse it try-BSD-then-GNU (`date -j -u -f … || date -u -d …`), both guarded; validate the result is numeric **before** any arithmetic; omit the age field if neither parse works. |
| **A CI test that never runs.** `ci.yml`'s anti-drift loop globs `loomwright/scripts/test-*.sh` **only** — a test placed in root `scripts/` is not auto-included, and an un-invoked mutation control is no evidence at all. | MEDIUM | Put all three self-tests in `loomwright/scripts/` so the existing glob picks them up. If any check lands in root `scripts/`, wire it explicitly the way `test-check-vendor-coupling.sh` and `test-check-shared-prefix.sh` already are. AC 7 requires proving the check *executed*, not merely that it exists. |
| **A vacuous mutation control.** Item 01 shipped a "not vacuous" control that was itself vacuous, twice, and only a second review round caught it. | MEDIUM | For AC 7, the fixture must make legend and frontmatter *genuinely* disagree and the test must assert the check both FAILED and emitted its specific diagnostic — not merely returned non-zero (which a syntax error also does). |
| **Legend row-label change is user-visible.** Deriving the Agent column from frontmatter `name:` rewrites all 12 existing labels from display names ("Launch Pad") to slugs ("launch-pad-runner"). | LOW | Deliberate and documented below. Nothing consumes the table (0 `statusLine` refs repo-wide), and the requirement itself names the missing rows by slug. Colour *hexes* are unchanged, honouring the Non-goal. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

**Why one subtask, not two.** The status-line half and the legend half are genuinely independent in their *source* files, which looks like `genuine-parallelism`. It is rejected: both halves must edit the same **release surface** — `plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `CLAUDE.md`, and `loomwright/docs/vendor-coupling-manifest.json`. Splitting would convert a non-existent parallelism win into a guaranteed `file-conflict` on five shared files, plus the known cross-worktree review false-positive on producer/consumer contracts. Per the Decomposition Threshold's default (one subtask; split only for a named reason), no reason fires.

## Design decisions (for Plan Review to challenge)

1. **The legend is derived from frontmatter; the only lookup is a published standard.**
   - *Agent* column = frontmatter `name:` minus the `loomwright:` prefix (`launch-pad-runner`, `context-keeper`, `rubric-grader`, …). Authoritative and exact.
   - *Hex* column = frontmatter `color:` verbatim.
   - *Color* word = looked up from the **CSS named-colour table**, camelCase-split. Verified 2026-09-02: **all 14** hexes are exact CSS named colours, and this rule reproduces all 12 existing rows byte-identically (`#708090`→SlateGray→"Slate Gray", `#1E90FF`→"Dodger Blue", …). A hex with no CSS name emits `—` rather than a guess, per the repo's own absent-evidence rule.
   - **Honest limit (do not overclaim):** that CSS table *is* a lookup embedded in the generator. The claim is NOT "no map anywhere" — it is that the only map is a **published standard keyed by hex**, so it cannot drift *relative to frontmatter*: change an agent's `color:` and the name follows automatically. That is categorically different from the display-name map rejected in the Agent column, which would have to be hand-edited every time an agent is added. Because all 14 live hexes are CSS names, the `—` branch is unreachable in production and would ship untested — AC 9 adds a non-CSS-hex fixture to exercise it, and AC 10 pins the other half by requiring a valid CSS name from outside the 14 to resolve — together they prove the lookup is the standard rather than a subset.
   - *Alternative considered:* drop the Color word column entirely (Agent | Hex only). Rejected — but narrowly: the Non-goal constrains *hexes*, not labels, and this brief already accepts label churn in the Agent column, so this is a preference for a legend that stays readable, not a forced move.
2. **`status-line.sh` ships under `loomwright/scripts/`** (runtime, user-invoked); the **check folds into root `scripts/check-doc-currency.sh`** per the requirement, invoking `gen-color-legend.sh --check` rather than adding a new CI step.
3. **The `/setup` module is script-backed, not prose.** `/setup observability`'s settings.json merge is currently *instructions in the agent body* — no script writes `~/.claude/settings.json` today (verified). AC 4 demands the unrelated-keys check be "diffed, not asserted", which is untestable against prose, so the merge must live in `setup-statusline.sh` following the `setup-memory.sh` + `test-setup-memory.sh` precedent.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-02-status-line.md
```
