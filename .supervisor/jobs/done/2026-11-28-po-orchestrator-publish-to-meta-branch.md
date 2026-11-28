# Supervisor Job: Product Owner and Orchestrator publish the requirement files they write to the metadata branch, and stop calling them local-only

## Environment
- **Project:** yellowtail (an Orca worktree of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: vikashruhilgit/loomwright-two-requirement-items
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (one prunable linked worktree in the shared repo — unrelated to this run)
- **Prior attempt:** Launch Pad session `5b0f129e` stopped at Plan Review FAIL 3/3 (HIGH: the `changelog.d/` fragment listed in provides was deleted by the bump) and 3 paths outside Touches; both are resolved by the 2026-11-28 owner decisions in the source requirement (Touches extended; fragment only, no bump)
- **Source requirement:** .supervisor/requirements/2026-11-26-221024-product-owner-and-orchestrator-publish-what-they-write-to-the-metadata-branch.md
- **Base commit:** c5cf65984f9999b80f3e77051082f1b0b93ae1c8

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-compatible script + markdown prompts; the existing branch-mode family `loomwright/scripts/automate-helpers.d/meta.sh` already wraps `setup-memory.sh mode` and `meta-sync.sh` |
| 2 | Dependency Availability | GO | `meta-sync.sh scrub --paths-from`, `meta-sync.sh push --paths-from`, `meta-sync.sh list-managed`, `setup-memory.sh mode` and `automate-lanes.sh lane-info` all exist at base; no new dependency |
| 3 | Architecture Fit | GO | a new subcommand in the `meta` family of `automate-helpers.sh` follows the `<script>.d/` family layout and the fail-safe emitter convention (`meta-entry` / `meta-push-failed` always exit 0) |
| 4 | Scope vs Supervisor Capability | GO | 15 files declared (13 modify + 2 create; ~12 actually changed, 3 expected unchanged); at the context-bound bound, which permits but never requires a split — most files take one-line or append-only edits, so one coherent change → single subtask |
| 5 | Hard Blockers | GO | none — the three paths the earlier attempt needed outside `## Touches` (the meta help golden, the `12-meta` test part, the Validation 3 evidence file) were added to Touches by the owner on 2026-11-28; every File Impact Map path is now inside Touches |

**Overall Verdict:** GO

## Task
**Goal:** In branch mode, every requirement file `/product-owner` or `/orchestrator` writes is pushed to the metadata branch right after it is written, through one shared exact-list helper, and the four "Collaboration note" paragraphs state what is true in each mode.

**Problem Statement:**
The owner running Loomwright in a branch-mode repo needs planning files to be on the metadata branch as soon as they are written, because today only `/automate`'s `trail-pr` pushes, and only for the item it ran.
Currently, files written by `/product-owner` / `/orchestrator` stay on one machine until someone runs `meta-sync.sh push`, and four prompt paragraphs tell the agent such files are "local-only" — false wherever branch mode is on. This caused a 12-file gap and a wrong "local-only" claim to the owner on 2026-11-27.
Success looks like: a branch-mode PO run's story is readable with `git show origin/loomwright-meta:<path>` right after the run, nothing else is pushed, and every non-push case is one named report line.

## Acceptance Criteria

**Happy path**
- [ ] AC1: Given branch mode `on loomwright-meta`, when `/product-owner` persists two stories and a plan doc, then those three paths, and no others, are pushed; `git show origin/loomwright-meta:<path>` matches each local file, and the report names the push (the commit sha and path count `meta-sync.sh` printed).
- [ ] AC2: Given branch mode on, when `/orchestrator` writes `{slug}-plan.md` or appends `## Task Plan` to a requirement file, then that one path is pushed the same way.
- [ ] AC3: Given the helper, when it runs, then it pushes only the paths it was given (`meta-sync.sh push --paths-from`), never a whole root, so another unpushed (local-ahead) or locally deleted managed file is left alone; a test leg pins this with a local-ahead file and a locally deleted file that are not in the list.

**Edge cases**
- [ ] AC4: Given branch mode `off`, when either agent writes, then nothing is pushed and the report says so in one line (`branch mode off: requirement files stay in this checkout`).
- [ ] AC5: Given branch mode `unknown <reason>`, when either agent writes, then nothing is pushed and the report names the reason.
- [ ] AC6: Given this checkout is an `/automate` lane (`automate-helpers.sh lane-info` exits 0), when either agent writes, then the helper does not push (a lane publishes at wave end through `lane-convert-ready`, or `lane-remove --abandon`), and the report says so.
- [ ] AC7: Given Product Owner's can't-ask branch (`po_gate: needs_owner`), when the run ends, then nothing was persisted and nothing is pushed (the helper call sits inside the Persist step, after the gate).
- [ ] AC8: Given a path outside the managed set (checked against `meta-sync.sh list-managed`), when passed to the helper, then it is refused by name and nothing is pushed.

**Error scenarios**
- [ ] AC9: Given a scrub hit in one of the files, when the helper runs, then nothing is pushed, each hit is named (`scrub-hit` lines), the files stay written locally, and the agent's report says the push did not happen and why.
- [ ] AC10: Given `meta-sync.sh push` fails (no network, a merge conflict on the branch, the lock held), when the helper runs, then the failure is named in the report with the exact command to retry, the files stay written locally, and the agent's run still completes (the helper always exits 0 — publishing never undoes a write).
- [ ] AC11: Given the same unchanged path pushed twice (PO's push, then `/automate`'s trail push), when the second push runs, then it is a no-op (`meta_sync: no_changes`), pinned by a test leg.

**Wording**
- [ ] AC12: Given the four "Collaboration note" paragraphs (`loomwright/agents/product-owner.md`, `loomwright/commands/product-owner.md`, `loomwright/agents/orchestrator.md`, `loomwright/commands/orchestrator.md`), when this lands, then each says: branch mode off ⇒ local to this checkout; branch mode on ⇒ published to the metadata branch, which is public when the repo is; the agent and command copies of each note carry the same text (house rule: a restated text changes in the same change as its source).

**Validation (from the requirement's `## Validation (must pass before merge)`)**
- [ ] AC13: Given the change, when `bash scripts/ci-local.sh --affected` runs, then it passes, including the new helper legs (mode on/off/unknown, lane checkout, scrub hit, path outside the managed set, failed push, local-ahead + locally deleted file left alone, repeated push no-op) against a local bare repo as `origin`; and `check-token-budget.sh` and `check-doc-currency.sh` pass with updated budget rows for the agent and command files that grew. The worker writes and commits the `changelog.d/po-orchestrator-publish-to-meta.md` fragment and does NOT run `scripts/bump-version.sh` or edit any version file (owner decision 2026-11-28: fragment only, the next bump folds it — `changelog.d/README.md` "An unfolded fragment merged without a bump is legal"); `bash scripts/check-version-bump.sh` passes in its "Not bumped" state.
- [ ] AC14: Given a branch-mode scratch clone whose `origin` is a local bare repo, when `/loomwright:product-owner` writes one story, then a committed evidence file `docs/evidence/po-publish-to-meta-branch.md` (repo-root `docs/evidence/`, the only place the validation evidence step `automate-lanes.d/evidence.sh` reads: `^docs/evidence/[^/]+\.md$`) contains the run's helper line and the fenced `git show origin/loomwright-meta:<path>` output printed right after the run (home paths written as `/Users/<name>/`), with the line `Verdict: PASS for Validation 3` at column 0 outside any fence, and the PR body links to it.

## Touched-file invariants

> Grounded at base `c5cf65984f9999b80f3e77051082f1b0b93ae1c8`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-helpers.d/meta.sh`** — keep: fail-safe, always exit 0 (`writes nothing itself; … always exits 0`); the mode is read only through `setup-memory.sh mode` (`reads \`setup-memory.sh mode\` itself (no caller input can assert the mode)`), never by parsing `.gitignore`; an option-shaped `--root` value is a misinvocation (`""|-*) echo "meta-entry: failed — --root requires a checkout path`). reuse: `_meta_root` for root resolution and the `LOOMWRIGHT_META_SYNC_BIN` test seam (`ms="${LOOMWRIGHT_META_SYNC_BIN:-$here/meta-sync.sh}"`); reuse meta-entry's reason-join idiom (`sed -n 's/^meta_sync: //p'`). mirror: `meta-sync.sh`'s `--paths-from` contract (`push only the managed paths listed in <file>`) and its silent skip of non-managed paths (`unlisted or non-managed paths are never pushed`) — the named refusal (AC8) must happen in the helper BEFORE calling push, reading `meta-sync.sh list-managed`; scrub exit codes (`exit 2 on any hit, 0 when clean`). pinned by: `loomwright/scripts/fixtures/automate-helpers-help/meta.golden` (the family's `#:  ` usage lines, byte-for-byte) and `loomwright/scripts/test-automate-helpers.d/12-meta.sh` (`== branch mode: meta-entry / meta-push-failed ==`).
- **`loomwright/scripts/automate-helpers.sh`** — keep: the dispatcher's function-arm shape that `test-automate-helpers-dispatch.sh`'s `fn_arms` parses (`    meta-push-failed) meta_push_failed "$@" ;;`); the fail-SAFE exceptions list must name the new subcommand (`meta-entry and meta-push-failed are the fail-SAFE`); the `LOOMWRIGHT_META_SYNC_BIN` TEST SEAM note (`TEST SEAM (tests only — never set it in a real run)`) must name the new subcommand if it uses the seam. Family files are listed by name, never globbed (`_ah_source meta`) — no new family, so `_AH_HELP_SEGMENTS` is unchanged. pinned by: `loomwright/scripts/test-automate-helpers-dispatch.sh` (`SEGMENTS="config runfile intake resume hdr-gate`).
- **`loomwright/scripts/test-automate-helpers.sh`** — keep: it only sources named parts (`TAH_PARTS="01-config 02-runfile`); the new legs go into the existing `12-meta` part, so this runner is unchanged unless a header "Covers" line is added.
- **`loomwright/scripts/test-automate-helpers.d/12-meta.sh`** — keep: hermetic, no network — a LOCAL bare origin (`Hermetic: a mktemp world with a LOCAL bare origin, never GitHub`); reuse `bm_world` and `bm_env` for every new leg (never a second world builder); the failed-push leg stubs meta-sync through the `LOOMWRIGHT_META_SYNC_BIN` seam (or a lock held / origin removed), never a real remote; keep the section header `== branch mode: meta-entry / meta-push-failed ==` (extend its text to name `meta-publish`). New legs: mode on/off/unknown, a lane checkout, a scrub hit, a non-managed path, a failed push, a local-ahead + a locally deleted managed file not in the list left alone, a repeated push no-op, and a call from a linked worktree with `--root` set.
- **`loomwright/scripts/test-automate-helpers-dispatch.sh`** — expected unchanged: no new family, so `SEGMENTS` and `_AH_HELP_SEGMENTS` stay as they are; its check 1 picks up the new arm automatically. Modify only if a check fails; keep `SEGMENTS="config runfile intake resume hdr-gate`.
- **`loomwright/agents/product-owner.md` / `loomwright/commands/product-owner.md`** — keep: the Persist step runs only after the Pre-persist house-rule check gate (`only after the Pre-persist house-rule check (Responsibilities 3a) has run and its gate is clear`), so the `po_gate: needs_owner` branch persists and pushes nothing. **Call site (pinned):** in Persistence Mode, AFTER item 3 (`**Plan doc (2 or more stories persisted for this prompt):**`) — or after item 2 when no plan doc is written — and BEFORE item 4 (`**Hand off by file path**`); the list is the FINAL set of files this run wrote after any `right-size` fold/split: every persisted story plus the `_BACKLOG-*` file, each path copied from your own write. The call passes `--root "$(git rev-parse --show-toplevel)"` (see Risk: linked worktree). **Placement (one form only):** the call is a NEW list line between item 3 and item 4, written byte-identically in both copies; the item-2 `**Persist**` line itself is NOT edited (renumber item 4 only after `grep -rnF 'Hand off by file path' loomwright/scripts/` shows no pin on its number). mirror: the agent and command copies of the Collaboration note say the same thing (`> **Collaboration note:**`), and so do the two copies of the new publish line. pinned by: `loomwright/scripts/test-requirement-shape.sh` (the identical-Persist-step check: `grep -F '**Persist**'` in both files, then `[ "$pa" = "$pc" ]` — so if the item-2 line is ever touched, both copies change together), and the `loomwright/docs/prompt-token-budgets.json` rows (`"product-owner": {"budget": 19533` agent, `"product-owner": {"budget": 12779` command). Run `bash loomwright/scripts/test-requirement-shape.sh` before hand-back.
- **`loomwright/agents/orchestrator.md` / `loomwright/commands/orchestrator.md`** — keep: the helper is called after the plan write in File-fallback Persistence Mode (`Write the task tree** as a markdown checklist to \`.supervisor/requirements/{slug}-plan.md\``), with that one path (the `{slug}-plan.md`, or the handed-off requirement file the `## Task Plan` was appended to), passing `--root "$(git rev-parse --show-toplevel)"`; Beads mode is unchanged. pinned by: budget rows (`"orchestrator": {"budget": 10357` agent, `"orchestrator": {"budget": 3859` command).
- **`loomwright/skills/automate-loop/branch-mode.md`** — keep: `setup-memory.sh mode` stays the ONE reader (`every caller below uses it; nothing else parses the managed \`.gitignore\` block`); a lane's metadata never takes the whole-set route (`A lane's metadata never takes the whole-set route`). pinned by: `loomwright/docs/loop-inventory/automate-loop.md` (13 rows quote this file, e.g. `q: **Push failures are loud.**`) via `scripts/test-loop-inventory.sh` — extend an existing bullet's text rather than adding a new bold-headed bullet, and run `bash loomwright/scripts/test-loop-inventory.sh`.

## Closed enumerations touched

> Sibling grep at base `c5cf659`, repo-wide: `grep -rnF 'meta-push-failed' --exclude=CHANGELOG.md .` (excluding `.git/`) → 223 hits. The closed lists among them are below; the rest are consumers that call or quote the subcommand and need no change (`automate-next-step.sh`, `janitor-report.sh`, `automate-lanes.d/{remove,wave}.sh`, the `automate-trail.*` family, the tests, and `skills/automate-loop/helpers.md`'s trail-pr row).

- **`meta-publish`** (new subcommand; sibling: `meta-push-failed`) — must be named in:
  - `loomwright/scripts/automate-helpers.sh` — the dispatcher `case` arm set (`    meta-push-failed) meta_push_failed "$@" ;;`) — extend.
  - `loomwright/scripts/automate-helpers.sh` — the fail-SAFE exceptions comment (`meta-entry and meta-push-failed are the fail-SAFE`) — extend.
  - `loomwright/scripts/fixtures/automate-helpers-help/meta.golden` — the help segment (`  meta-push-failed <runfile>`) — extend (same line as meta.sh's `#:  ` line, `#:  ` replaced by two spaces, same position).
  - `loomwright/skills/automate-loop/branch-mode.md` — §13 bullet text — extend (documents who pushes on write).
  - `loomwright/skills/automate-loop/helpers.md` — no change: its table does not list `meta-entry`/`meta-push-failed` either (branch-mode helpers are documented in branch-mode.md).
  - `loomwright/skills/automate-loop/lanes.md`, `loomwright/docs/PITFALLS.md`, `loomwright/docs/loop-inventory/automate-loop.md`, `loomwright/docs/result-schemas/automate-run.md` — no change: they describe the trail push / PICK report, not the subcommand list.
- **verdict lines of `meta-publish`** — a new closed set owned by meta.sh's own comment above `meta_publish` (one place); the agents quote the line the helper printed, never re-list the set.
  - `loomwright/scripts/fixtures/automate-helpers-help/incidental.golden` (sibling grep `meta-entry` → its `  meta-entry: off   mode off — proceed exactly as today, no network` block) — **no change**, by layout: `--help` prints every `#   <lowercase>` line (`grep -E '^#   [a-z]'` in `automate-helpers.sh`), so the new verdict comment lines MUST NOT start with `#   ` + a lowercase letter (write them as `#   - meta-publish: …` or `# meta-publish: …`). Verify: `bash loomwright/scripts/test-automate-helpers-dispatch.sh` stays green with incidental.golden byte-unchanged.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — local-ahead + locally deleted file not in the list stay unpushed | replace the `--paths-from "$list"` argument of the helper's `meta-sync.sh push` call with no `--paths-from` (whole-set push) in `loomwright/scripts/automate-helpers.d/meta.sh` |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — scrub hit ⇒ nothing pushed + `scrub-hit` named | delete the line that returns after a non-zero scrub exit in `loomwright/scripts/automate-helpers.d/meta.sh` |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — non-managed path refused by name | delete the line that refuses a path absent from `list-managed` in `loomwright/scripts/automate-helpers.d/meta.sh` |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — lane checkout ⇒ skipped, nothing pushed | delete the `lane-info` check line in `loomwright/scripts/automate-helpers.d/meta.sh` |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — mode off ⇒ one skipped line, nothing pushed | flip `branch mode off: requirement files stay in this checkout` → `pushed` in `loomwright/scripts/automate-helpers.d/meta.sh` (the literal is unique to meta_publish; `off)` alone is not — meta_entry has one) |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — mode on happy push ⇒ `meta-publish: pushed <branch> <sha> (<n> path(s))` and `git show origin/<branch>:<path>` equals the local file | delete the line that prints the `meta-publish: pushed` verdict in `loomwright/scripts/automate-helpers.d/meta.sh` |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — mode `unknown <reason>` ⇒ the verdict carries the reason text (the leg asserts the reason, not only `skipped`) | delete the `(<reason>)` suffix from the helper's `branch mode unknown` verdict line in `loomwright/scripts/automate-helpers.d/meta.sh` |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — repeated push of an unchanged path ⇒ `meta-publish: no_changes <branch>` | delete the line that maps `meta_sync: no_changes` to the `no_changes` verdict in `loomwright/scripts/automate-helpers.d/meta.sh` |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — call from a linked worktree with `--root` ⇒ the worktree's file is the one pushed | drop `--root "$root"` from the helper's `meta-sync.sh push` call in `loomwright/scripts/automate-helpers.d/meta.sh` |
| `loomwright/scripts/test-automate-helpers.d/12-meta.sh` — failed push ⇒ named failure + retry command, exit 0 | replace the helper's final `return 0` on the push-failure arm with `return 1` in `loomwright/scripts/automate-helpers.d/meta.sh` |

> Rows describe lines that do not exist until the helper is written; the worker restates each row as a machine-applicable `delete \`<literal>\` in \`<path>\`` / `flip \`<A>\` → \`<B>\` in \`<path>\`` (literal unique in `loomwright/scripts/automate-helpers.d/meta.sh`) in its hand-back so Phase 4.5 can apply them by script.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `meta-publish` helper + PO/Orchestrator call sites + Collaboration notes + tests + budgets | all | 13 modify (3 of them expected unchanged or append-only), 2 create (evidence file + `changelog.d/` fragment) | `skills/automate-loop/branch-mode.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| helper | `loomwright/scripts/automate-helpers.d/meta.sh` (86 — the branch-mode family; the new subcommand's home), `loomwright/scripts/automate-helpers.sh` (1280 — append only: one case arm + one comment word, no logic; the single dispatcher), `loomwright/scripts/fixtures/automate-helpers-help/meta.golden` (2) | — | HIGH |
| tests | `loomwright/scripts/test-automate-helpers.d/12-meta.sh` (151 — the existing branch-mode leg part, reuses `bm_world`), `loomwright/scripts/test-automate-helpers-dispatch.sh` (292 — only if its covers header needs the new arm; else unchanged), `loomwright/scripts/test-automate-helpers.sh` (451 — the parts runner; expected unchanged, in lanes only for a "Covers" header line) | — | HIGH / LOW / LOW |
| prompts | `loomwright/agents/product-owner.md` (634 — the Persistence Mode list is the single authority for the write; one new line between item 3 and item 4, the item-2 Persist line unedited), `loomwright/commands/product-owner.md` (718 — mirror copy of the note), `loomwright/agents/orchestrator.md` (360), `loomwright/commands/orchestrator.md` (287) | — | HIGH |
| docs | `loomwright/skills/automate-loop/branch-mode.md` (11), `loomwright/docs/prompt-token-budgets.json` (JSON rows), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1042 — budget mirror rows only, in the existing Prompt Token Budgets table, the single mirror home) | `docs/evidence/po-publish-to-meta-branch.md`, `changelog.d/po-orchestrator-publish-to-meta.md` | HIGH |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/meta.sh", name: "meta_publish"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "meta-publish"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/automate-helpers-help/meta.golden", name: "meta-publish"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.d/12-meta.sh", name: "meta-publish"}
  - {kind: "symbol", path: "loomwright/agents/product-owner.md", name: "meta-publish"}
  - {kind: "symbol", path: "loomwright/agents/orchestrator.md", name: "meta-publish"}
  - {kind: "file", path: "docs/evidence/po-publish-to-meta-branch.md"}
  # the fragment survives the subtask: this PR ships it unfolded and never bumps (owner decision 2026-11-28)
  - {kind: "file", path: "changelog.d/po-orchestrator-publish-to-meta.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.d/meta.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/meta.golden"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers.d/12-meta.sh"
  - "loomwright/scripts/test-automate-helpers-dispatch.sh"
  - "loomwright/agents/product-owner.md"
  - "loomwright/commands/product-owner.md"
  - "loomwright/agents/orchestrator.md"
  - "loomwright/commands/orchestrator.md"
  - "loomwright/skills/automate-loop/branch-mode.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "docs/evidence/po-publish-to-meta-branch.md"
  - "changelog.d/po-orchestrator-publish-to-meta.md"
external_requires:
  - "a local bare git repo as origin for the hermetic test legs and the Validation 3 scratch clone (no network)"
```

**Helper contract (for the worker):** `automate-helpers.sh meta-publish --paths-from <file> [--root <checkout>]` — ALWAYS exit 0; prints one verdict line first, then any `scrub-hit` lines meta-sync printed. Order: (1) mode via `setup-memory.sh mode` (`off` ⇒ `meta-publish: skipped — branch mode off: requirement files stay in this checkout`; `unknown <r>` ⇒ `meta-publish: skipped — branch mode unknown (<r>)`); (2) lane check via `automate-lanes.sh lane-info --root <root>` exit 0 ⇒ `meta-publish: skipped — /automate lane: published at wave end (lane-convert-ready / lane-remove --abandon)`; (3) every listed path must be in `meta-sync.sh list-managed` ⇒ else `meta-publish: refused — not managed: <path>` (all named, nothing pushed); (4) `meta-sync.sh scrub --paths-from` exit 2 ⇒ `meta-publish: blocked — scrub hit (nothing pushed; files kept locally)` + the hits; (5) `meta-sync.sh push --branch <b> --paths-from <file> --root <root>` ⇒ `meta-publish: pushed <branch> <sha> (<n> path(s))` | `meta-publish: no_changes <branch>` | `meta-publish: FAILED — <reason>; retry: bash <meta-sync.sh path> push --branch <b> --paths-from <file>`. The sha is read from what meta-sync printed (or `git rev-parse origin/<branch>` after a successful push) — the worker reads `meta-sync.sh push`'s success output at base before choosing. A retry line must not leak a home path into a pushed file (it is printed, not written).

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/automate-loop/branch-mode.md`, `skills/unit-testing/SKILL.md` |

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

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The worker (or a Phase 4.5 fix task) runs the version bump by habit — the default single-PR rule says the author bumps | MEDIUM | AC13 and `## Configuration` state "fragment only, no bump" (owner decision 2026-11-28); `check-version-bump.sh` passes in both states, so the reviewer checks that no version file and no folded changelog entry appear in the diff |
| Public by default: a draft story goes public on write (the meta branch is on a public repo) | MEDIUM | scrub runs first and blocks on any hit; the Collaboration note states it; no change to scrub rules (non-goal) |
| Two writers contend for meta-sync's lock (PO push vs a concurrent trail push) | MEDIUM | the loser prints a named FAILED line + retry command and exits 0; test leg for the failed push |
| Editing `branch-mode.md` breaks a `docs/loop-inventory/automate-loop.md` quoted row | MEDIUM | extend existing bullet text only; run `bash loomwright/scripts/test-loop-inventory.sh` |
| Prompt growth breaches token budgets of the PO/orchestrator agent+command | LOW | re-baseline rows (measured + ~10%) in `prompt-token-budgets.json` and the ARCHITECTURE_CONTRACTS.md mirror in the same change |
| Linked worktree: `_meta_root` and meta-sync's resolve-root default to the FIRST `git worktree list` entry (the main checkout), but PO/Orchestrator write relative to their own checkout | MEDIUM | call sites always pass `--root "$(git rev-parse --show-toplevel)"`; test leg runs the helper from a linked worktree with `--root` and asserts the worktree's file is the one pushed |
| Validation 3 needs a real headless PO run; without a human, any PO flag (Assumption Check, house-rule conflict, missing proof, unproven defect) ends `po_gate: needs_owner` with nothing saved | LOW | drive it with the recipe in `docs/evidence/po-story-validation.md` (`claude -p "/loomwright:product-owner …" --plugin-dir <checkout>/loomwright` in the scratch clone) with a goal that raises no PO flag; on `po_gate: needs_owner`, re-run rather than write evidence |
| A worker writes a home path into the evidence file → its own trail push trips the `home_path` scrub | LOW | write `/Users/<name>/` placeholders (AC14) |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main
- **Release:** `changelog.d/` fragment only — no `scripts/bump-version.sh` run and no version-file edit in this PR (owner decision 2026-11-28, source requirement §"Owner decisions"); no subtask owns a bump

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-28-po-orchestrator-publish-to-meta-branch.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-28T07:37:47Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/999
- **Branch:** feature/2026-11-28-po-orchestrator-publish-to-meta-branch
- **Files changed:** 16
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** New fail-safe `automate-helpers.sh meta-publish` pushes exactly the requirement files Product Owner / Orchestrator write to the metadata branch in branch mode (mode, lane, requirement-only scope, scrub checks; one named verdict, always exit 0); four Collaboration notes reworded; hermetic 12-meta legs BP1–BP13; fragment only, no bump. Phase 4.5: 3 review rounds, 2 fix rounds (quoted retry, requirement-only scope, meta-sync Callers list, unreadable list), final PASS; 2 LOW findings dismissed below the MEDIUM fix floor. Driver path not used (main checked out in another worktree) — legacy prose for Phases 1–4.

## Not verified
- **/orchestrator Publish step in a live session** — no headless /orchestrator run; same helper call, covered by the hermetic 12-meta legs only (subtask 1)
- **PR body link to docs/evidence/po-publish-to-meta-branch.md (AC14)** — written by the Supervisor at FINALIZE, not by a worker (subtask 1)
- **two-story + _BACKLOG plan-doc headless PO run (three paths)** — one live run wrote one story; the three-path publish is pinned by hermetic leg BP1 only (subtask 1)
