# Supervisor Job: qa-split 07 — a known-answer set split by defect, with held-out answers kept outside the repo (source (b) real bugs, non-defect criteria, split / no-leak / manifest tooling, plugin-eval re-check)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/`), branch: fix/trail-modules-help-check-split-tree (already merged as #962; branch from `main`)
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 3 (dirty tree, 6 extra worktrees incl. 1 prunable, source requirement is gitignored so its provenance is not git-verifiable)
- **Source requirement:** .supervisor/requirements/qa-split/07-known-answer-set-held-out-from-the-builder.md
- **Base commit:** 478c17086e7f9e1f688b38398fe578ecd4d476b4

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Node >= 18 built-ins (`node:crypto`, `node:fs`) and bash tests, the same stack as `selvedge/lib/*.mjs` and `selvedge/tests/test-*.sh`; no new dependency |
| 2 | Dependency Availability | CAUTION | Reviving sports-management commits needs the `supabase` CLI, Docker, `npm` and `gh` read access to `karch4162/sports-management` — all present on this machine (`/opt/homebrew/bin/supabase`, `/usr/local/bin/docker`, 276 merged `fix` PRs listed by `gh`), but none of them exist on a CI runner |
| 3 | Architecture Fit | GO | Selvedge is self-contained (imports nothing from `loomwright/`); the set lives under `selvedge/eval/`, which item 08's harness will also use |
| 4 | Scope vs Supervisor Capability | CAUTION | 15 files and data files well past 800 lines → `context-bound` split into 2 ordered subtasks; the real-bug harvest (reviving 30+ parent/fix commit pairs) is long, slow work |
| 5 | Hard Blockers | CAUTION | Two count floors (≥100 known-FAIL overall, ≥60 held-out known-FAIL) need source (a) planted defects, which the owner decided this run must NOT write (2026-11-21); they are reported as measured, not forced. The Validation evidence file must sit in root `docs/evidence/` (the `/automate` validation gate reads only `^docs/evidence/[^/]+\.md$`), which is outside the item's Touches |

**Overall Verdict:** CAUTION

## Task
**Goal:** Build the known-answer set's storage, split, no-leak and manifest tooling under `selvedge/eval/`, fill it with real sports-management bug criteria (source (b)) and non-defect criteria, keep the held-out answers outside the repo behind a committed sha256 manifest, and re-check `claude plugin eval`'s reported limits — leaving an empty, ready slot for the planted-defect set (source (a)) the owner will have a separate session write.

**Problem Statement:**
The owner needs a fixed set of acceptance criteria with known right answers, split by underlying defect into tuning (40%) and held-out (60%), with the held-out answers kept away from Selvedge's builder, because item 08 must measure Selvedge's false-PASS rate on cases the builder never tuned toward.
Currently, there is no set: rev 1's accuracy claim had no denominator, no N and a self-written fixture (red team F4).
This means item 08 has nothing to score, and Phase 3 waits on 08's gate.
Success looks like: one count command that reports known-FAIL / known-PASS / real-bug-FAIL / held-out-FAIL counts against their floors, at least 30 real-bug FAIL criteria from sports-management, at least 100 known-PASS criteria, a split that never puts one defect on both sides, no held-out answer in the repo, and a manifest check that names any changed outside file.

**Scope for THIS run (owner decision 2026-11-21, carried from the source requirement):** this run does **not** write source (a) planted defects or their author-session brief — the owner starts that session by hand. Everything built here accepts planted-defect entries added later (`source: "planted"`, `target.kind: "variant"`) with no code change.

**Data model (fixed here so both subtasks and item 08 agree):**
- **Group** (`group_id`, e.g. `sm-pr-<N>` for a real bug, `pd-<slug>` for a later planted defect): the unit of the split. Every case from one bug or one planted defect — including the non-defect criteria taken on that bug's commits — carries that bug's `group_id`, so they all land on the same side.
- **Case**: one criterion checked on one target, with one known answer. `{case_id, group_id, source: "real-bug" | "non-defect" | "planted", criterion: {id, text}, target: {kind: "commit", repo, sha} | {kind: "variant", path}, answer?}`. Store `criterion.text = normalizeCriterionText(raw)` and `criterion.id = criterionId(criterion.text)`, both imported from `selvedge/lib/criteria.mjs` (`criterionId` hashes the text exactly as given, and `selvedge criteria` requires `c.id === criterionId(c.text)`), never re-implemented. A real-bug criterion yields two cases: FAIL on the parent SHA, PASS on the fix SHA. Counts are counts of cases.
- **Split rule** (recorded in `selvedge/eval/split.json` with its seed): a group goes to `tuning` when `parseInt(sha256(seed + ":" + group_id).slice(0, 8), 16) % 100 < 40`, else `held-out`. The rule is per group, so adding a group later never moves an existing one.
- **Held-out outside folder:** `$SELVEDGE_EVAL_HELD_OUT`, default `~/.claude/selvedge-eval/held-out/`, holding `answers.json` (`{case_id: "PASS" | "FAIL"}` for every held-out case) and, later, `variants/<group_id>/…` for held-out planted variants. The repo commits `selvedge/eval/held-out/manifest.sha256` (`<sha256>  <relative path>` per outside file, sorted).

## Design decisions
- decision: how to implement the eval-set tooling (count, split, leak check, manifest write/check, start-folder check)
  chosen: one standalone Node module `selvedge/eval/eval-set.mjs` using only Node built-ins and importing `criterionId` from `selvedge/lib/criteria.mjs`
  rejected: bash + jq script — partial stack fit and partial manifest fit: `selvedge/tests/check-release.sh` says "the selvedge CLI itself never needs it" of jq, and bash 3.2 on macOS makes JSON and sha256 handling fragile
  rejected: a new `selvedge eval …` CLI subcommand in `selvedge/bin/selvedge` — blast radius no (touches the CLI dispatcher and its usage text, outside the item's Touches), and it makes an owner-only measurement tool part of the user-facing CLI
  evidence: `selvedge/lib/criteria.mjs` exports `criterionId`; every `selvedge/lib/*.mjs` uses `node:` built-ins only; `selvedge/bin/selvedge` header: commands run lib/<command>.mjs and are the only ones that need Node (>= 18)
  revisit when: item 08's harness needs the same functions from the CLI, at which point the module is imported, not copied
  status: confirmed

## Acceptance Criteria
- [ ] AC1 (counts): Given the finished set, when `node selvedge/eval/eval-set.mjs count` runs, then it prints known-FAIL, known-PASS, real-bug known-FAIL and held-out known-FAIL counts, each beside its floor (100 / 100 / 30 / 60) marked `met` or `open`; at least 30 known-FAIL cases come from real sports-management bugs and at least 100 cases are known-PASS. The ≥100 known-FAIL and ≥60 held-out known-FAIL floors need the planted-defect set and are reported as measured, not forced (owner decision 2026-11-21).
- [ ] AC2 (split): Given `selvedge/eval/split.json`, when the held-out side is counted, then no `group_id` has cases on both sides, every case's side equals the side the recorded rule and seed give its `group_id`, and `selvedge/tests/test-eval-set.sh` fails (reason `defect_on_both_sides`) on a fixture where one `group_id` appears in both `tuning/cases.json` and `held-out/cases.json`.
- [ ] AC3 (no leak): Given a fresh clone of this repo, when it is searched, then no held-out answer and no held-out planted app variant is in it; `node selvedge/eval/eval-set.mjs check-leak` reads the tracked files under `selvedge/eval/` (from `git ls-files`) and fails with `held_out_answer_committed` on any tracked case or answer for a held-out `group_id` that carries an `answer`, or any tracked file under a held-out variant path, or any tracked file under `selvedge/eval/` named `answers.json` or whose sha256 equals an entry in `selvedge/eval/held-out/manifest.sha256` (a committed copy of an outside file); it fails closed (`no_tracked_files`) when `git ls-files` returns nothing, and (`split_unreadable`) when `selvedge/eval/split.json` is missing, unreadable or names no rule and seed; and `selvedge/tests/test-eval-set.sh` proves all three failures on a temp git repo (including one that commits a copy of the outside `answers.json`) and the pass on the real tree.
- [ ] AC4 (manifest): Given the outside held-out folder, when one byte of any file in it changes, then `node selvedge/eval/eval-set.mjs manifest check` exits non-zero and names that file (`manifest_mismatch: <relative path>`), and also names a listed file that is missing (`manifest_missing_file`) and an unlisted file that appeared (`manifest_extra_file`); it fails closed (`manifest_empty`) when the committed `selvedge/eval/held-out/manifest.sha256` is missing or lists no file; and `count` (after the manifest check) fails (`held_out_answers_incomplete`) when the outside `answers.json` is missing (even with no held-out cases yet) or unless its keys equal the `case_id`s of `selvedge/eval/held-out/cases.json` exactly, naming the missing and extra ids; `selvedge/tests/test-eval-set.sh` proves all five on a temp folder given by `SELVEDGE_EVAL_HELD_OUT`, never on the real one.
- [ ] AC5 (planted-defect session, partially open by owner decision): Given `selvedge/eval/README.md`, when it is read, then it holds an empty slot for the planted-defect author session (session id, start date, path of its committed brief — all `TBD`), the instructions for building its start folder (a copy of `selvedge/tests/fixtures/app-server.mjs` and `selvedge/tests/fixtures/servers.mjs` only), and the command `node selvedge/eval/eval-set.mjs check-start-folder <dir>`, which fails (`start_folder_not_clean`) naming each file in `<dir>` that is not one of those two copies or whose bytes match any other tracked file under `selvedge/`; `selvedge/tests/test-eval-set.sh` proves the pass on a clean folder and the failure on one holding a copy of `selvedge/prompts/planner.md`. That the session ran is open until the planted set lands.
- [ ] AC6 (real-bug entries): Given `selvedge/eval/real-bugs.json`, when any entry is read, then it names `repo` (`karch4162/sports-management`), `pr`, `parent_sha`, `fix_sha`, the per-commit `setup` steps used to revive it and `status: used | skipped`, and every `skipped` entry carries a non-empty `skip_reason`; `check-leak` (or a `validate` subcommand it shares code with) fails with `real_bug_entry_incomplete` on a fixture entry missing any of those, proven in `selvedge/tests/test-eval-set.sh`.
- [ ] AC7 (non-defect criteria): Given the set, when its cases are listed, then it has `source: "non-defect"` cases (known answer PASS) taken on the same sports-management commits as the real bugs, each carrying that bug's `group_id`, so a tool that answers FAIL to everything scores badly.
- [ ] AC8 (plugin eval re-check): Given the installed `claude` CLI, when `claude plugin eval`'s two reported limits are tried (no custom-code graders; a sandbox that cannot read the browser cache under `~`), then `selvedge/eval/plugin-eval-limits.md` records each as `confirmed` or `not confirmed`, with the CLI version, the exact command that showed it and its relevant output, and one line saying whether item 08 may use it for an optional with/without-plugin comparison.
- [ ] AC9 (running-system evidence): Given this machine with the real outside folder, when Validation step 2 runs, then a committed evidence file `docs/evidence/qa-split-07-known-answer-set.md` contains the fenced output of `node selvedge/eval/eval-set.mjs count`, of a passing `manifest check`, and of a failing `manifest check` naming the file after one byte of a held-out file was changed (then restored, and the check passing again); it lists which floors remain `open` until the planted set lands, and carries the declared line `Verdict: PASS for Validation 2` only if all four floors are `met` — otherwise it states the open floors and carries no PASS verdict line, and the PR body links to the file.
- [ ] AC10 (release): Given the selvedge plugin, when `bash selvedge/tests/run.sh` runs, then it passes with the new test file, and `selvedge/.claude-plugin/plugin.json`, its `.claude-plugin/marketplace.json` entry and the top `selvedge/CHANGELOG.md` heading all read `0.8.0`, with no `changelog.d/` fragment and no loomwright version change.

## Scope widening
- docs/evidence/qa-split-07-known-answer-set.md
- accepted: LP-SCOPE 2026-11-21

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

How this brief honors them: `selvedge/eval/README.md` and `selvedge/README.md` never write the set's counts as literals — they name the `count` command, which derives them at read time. The evidence file records one dated measurement (a fixed record, not a live claim).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| tooling (subtask 1) | — | `selvedge/eval/eval-set.mjs`, `selvedge/tests/test-eval-set.sh`, `selvedge/eval/README.md`, `selvedge/eval/plugin-eval-limits.md` | HIGH |
| data + release (subtask 2) | `selvedge/README.md` (1018 — appending one short pointer section; it is the plugin's single user doc and a new file for one paragraph would be a second entry point), `selvedge/CHANGELOG.md` (243), `selvedge/.claude-plugin/plugin.json` (15), `.claude-plugin/marketplace.json` (137), `selvedge/eval/README.md` (created by subtask 1: fill the open-floors line) | `selvedge/eval/split.json`, `selvedge/eval/tuning/cases.json`, `selvedge/eval/held-out/cases.json`, `selvedge/eval/held-out/manifest.sha256`, `selvedge/eval/real-bugs.json`, `docs/evidence/qa-split-07-known-answer-set.md` | HIGH (files) / MEDIUM (how many real bugs revive) |

**Module layout:** one home per responsibility — all set logic (count, split assignment, leak check, entry validation, manifest write/check, start-folder check) lives in `selvedge/eval/eval-set.mjs`; criterion ids come from the existing `selvedge/lib/criteria.mjs` (`criterionId`), never a second copy; the test file is new (below the 500-line threshold is expected; if it would pass it, split by concern into a second `test-eval-*.sh`). No helper is copied by 2+ siblings, so no extract row.

**Outside Touches:** `docs/evidence/qa-split-07-known-answer-set.md` — the `/automate` validation gate reads only root `docs/evidence/*.md` (precedent: `docs/evidence/qa-split-11b1-removal.md`). A root `docs/evidence/` file makes the branch "mixed" for `bump-version.sh --check`, which then checks it as a normal branch: with no `changelog.d/` fragment and an unchanged loomwright version it stays consistent, so no fragment is added.

**Outside the repo (written, never committed):** `$SELVEDGE_EVAL_HELD_OUT` (default `~/.claude/selvedge-eval/held-out/`): `answers.json`. A scratch clone of sports-management for reviving commits lives in the session scratch dir — never the owner's checkout at `~/Documents/work/personal/sports-management`, which is only read.

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| subtask 1 | subtask 2 | `selvedge/eval/README.md` | YES (subtask 2 requires subtask 1) |

### Relevant Skills

| Group | Skills |
|-------|--------|
| tooling | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| data + release | `skills/user-story-writing/SKILL.md` (criteria text) |

## Touched-file invariants

> Grounded at base `478c17086e7f9e1f688b38398fe578ecd4d476b4`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`selvedge/CHANGELOG.md`** + **`selvedge/.claude-plugin/plugin.json`** — keep: the release heading form `## <X.Y.Z> — <YYYY-MM-DD>` with the new release as the FIRST such heading, equal to plugin.json's `"version"`; mirror: `selvedge/tests/check-release.sh` reads them (`changelog_version_mismatch: plugin.json version`) and `selvedge/tests/run.sh` runs it first (`selvedge gate: release consistency`); keep: Selvedge releases on its own — never a `changelog.d/` fragment (CHANGELOG header: `never through the repository's`).
- **`.claude-plugin/marketplace.json`** — keep: only the `"name": "selvedge"` entry's `"version"` changes (to `0.8.0`), its `description` is untouched; mirror: `scripts/check-doc-currency.sh` checks the loomwright entry's description (`marketplace_len" -gt 600`), so the loomwright entry must stay byte-identical; `scripts/bump-version.sh` treats this file as bump-owned (`SELF_RELEASING_PLUGINS="selvedge"`); `scripts/validate-version.sh` checks every `.plugins[]` entry's version against its own plugin.json (`version mismatch, and empty plugins[] each exit 1`), so the selvedge entry and `selvedge/.claude-plugin/plugin.json` must both read `0.8.0`.
- **`selvedge/README.md`** — keep: the `## Environment variables` list is headed `Read by the CLI only, never from a file in the repo:` — `SELVEDGE_EVAL_HELD_OUT` is read by the eval tool, not the CLI, so it is documented in `selvedge/eval/README.md` and NOT added to that list; the new pointer section sits before `## Releasing` and writes no count literal.

## Closed enumerations touched

> Sibling grep at base `478c170`: `grep -rnF 'changelog_version_mismatch' --exclude=CHANGELOG.md selvedge` → 2 hits in 2 files (`selvedge/tests/check-release.sh`, `selvedge/tests/test-check-release.sh`).

- **New reason tokens** `defect_on_both_sides`, `held_out_answer_committed`, `no_tracked_files`, `split_unreadable`, `manifest_mismatch`, `manifest_missing_file`, `manifest_extra_file`, `manifest_empty`, `held_out_answers_incomplete`, `start_folder_not_clean`, `real_bug_entry_incomplete` (sibling convention: `changelog_version_mismatch`) — must be named in:
  - `selvedge/eval/eval-set.mjs` — new file; its header comment lists every token, and each token sits on exactly one line, the line that sets that failure (the convention `check-release.sh` states: `Each reason token sits on exactly one line`) — create.
  - `selvedge/tests/test-eval-set.sh` — new file; pins each token — create.
  - `selvedge/tests/check-release.sh` / `test-check-release.sh` — no change: their token set is the release check's own closed list, not shared with the eval tool.
  - `selvedge/README.md` `## BLOCKED and config reasons` — no change: that list is the CLI's verdict/config reasons; the eval tool's reasons are listed in `selvedge/eval/README.md`.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `selvedge/tests/test-eval-set.sh` — group on both sides fails | delete `defect_on_both_sides` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — committed held-out answer fails | delete `held_out_answer_committed` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — empty `git ls-files` fails closed | delete `no_tracked_files` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — one changed byte names the file | delete `manifest_mismatch` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — missing outside file named | delete `manifest_missing_file` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — extra outside file named | delete `manifest_extra_file` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — missing split.json fails closed | delete `split_unreadable` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — empty or missing manifest fails closed | delete `manifest_empty` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — answers.json not matching held-out case ids fails | delete `held_out_answers_incomplete` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — unclean start folder fails | delete `start_folder_not_clean` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — incomplete real-bug entry fails | delete `real_bug_entry_incomplete` in `selvedge/eval/eval-set.mjs` |
| `selvedge/tests/test-eval-set.sh` — case side follows the recorded rule | flip `< 40` → `< 60` in `selvedge/eval/eval-set.mjs` |

Each deleted line must be the statement that records the failure, so deleting it lets the bad input through and the pin turns red (worker: write each check so that is true, and confirm each mutant is non-empty, differs from the original and still parses before trusting it).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Eval-set tooling, tests, set README and the `claude plugin eval` re-check | AC2, AC3, AC4, AC5, AC6 (tooling + tests), AC8 | 0 modify, 4 create | unit-testing, error-handling | LAUNCHABLE |
| 2 | Harvest real bugs + non-defect criteria, split, outside answers + manifest, evidence, release 0.8.0 | AC1, AC2/AC3/AC6 (on the real data), AC7, AC9, AC10 | 5 modify, 6 create | user-story-writing | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "selvedge/eval/eval-set.mjs"}
  - {kind: "symbol", path: "selvedge/eval/eval-set.mjs", name: "defect_on_both_sides"}
  - {kind: "symbol", path: "selvedge/eval/eval-set.mjs", name: "held_out_answer_committed"}
  - {kind: "symbol", path: "selvedge/eval/eval-set.mjs", name: "manifest_mismatch"}
  - {kind: "symbol", path: "selvedge/eval/eval-set.mjs", name: "start_folder_not_clean"}
  - {kind: "symbol", path: "selvedge/eval/eval-set.mjs", name: "real_bug_entry_incomplete"}
  - {kind: "symbol", path: "selvedge/eval/eval-set.mjs", name: "SELVEDGE_EVAL_HELD_OUT"}
  - {kind: "file", path: "selvedge/tests/test-eval-set.sh"}
  - {kind: "file", path: "selvedge/eval/README.md"}
  - {kind: "symbol", path: "selvedge/eval/README.md", name: "check-start-folder"}
  - {kind: "file", path: "selvedge/eval/plugin-eval-limits.md"}
requires: []
lanes:
  - "selvedge/eval/eval-set.mjs"
  - "selvedge/tests/test-eval-set.sh"
  - "selvedge/eval/README.md"
  - "selvedge/eval/plugin-eval-limits.md"
external_requires:
  - "Node >= 18 (node:crypto, node:fs, node:child_process)"
  - "installed `claude` CLI with `claude plugin eval` (2.1.329 on this machine)"

# Subtask 2
provides:
  - {kind: "file", path: "selvedge/eval/split.json"}
  - {kind: "file", path: "selvedge/eval/tuning/cases.json"}
  - {kind: "file", path: "selvedge/eval/held-out/cases.json"}
  - {kind: "file", path: "selvedge/eval/held-out/manifest.sha256"}
  - {kind: "file", path: "selvedge/eval/real-bugs.json"}
  - {kind: "file", path: "docs/evidence/qa-split-07-known-answer-set.md"}
  - {kind: "symbol", path: "selvedge/CHANGELOG.md", name: "## 0.8.0"}
  - {kind: "symbol", path: "selvedge/.claude-plugin/plugin.json", name: '"version": "0.8.0"'}
requires:
  - {from: "1", kind: "file", path: "selvedge/eval/eval-set.mjs"}
  - {from: "1", kind: "file", path: "selvedge/eval/README.md"}
lanes:
  - "selvedge/eval/split.json"
  - "selvedge/eval/tuning/**"
  - "selvedge/eval/held-out/**"
  - "selvedge/eval/real-bugs.json"
  - "selvedge/eval/README.md"
  - "selvedge/README.md"
  - "selvedge/CHANGELOG.md"
  - "selvedge/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "docs/evidence/qa-split-07-known-answer-set.md"
external_requires:
  - "read access to karch4162/sports-management (gh + a scratch git clone; the owner's checkout is read-only)"
  - "supabase CLI + Docker + npm to revive sports-management parent/fix commits on localhost"
  - "the outside folder $SELVEDGE_EVAL_HELD_OUT (default ~/.claude/selvedge-eval/held-out/), written on this machine only"
```

**Subtask 2 procedure notes (binding):**
1. Pick merged `fix` PRs with `gh pr list -R karch4162/sports-management --state merged --search 'fix in:title' --json number,title,mergeCommit,url` (276 listed at planning time). For each candidate: take the criterion from the PR (title/body/linked issue), resolve `parent_sha` (the fix commit's first parent) and `fix_sha`, and keep it only if the criterion is checkable on localhost web (D12).
2. Revive each kept commit in a scratch clone (`git clone` of the owner's checkout or of the GitHub remote into the session scratch dir; never `git worktree add` in, or any write to, the owner's checkout): `supabase start` / `supabase db reset` for that commit's migrations, `npm ci`, start the dev server, and confirm the criterion's page answers on localhost at both SHAs. Record the steps as the entry's `setup` (item 08 reuses them). A commit that won't revive or isn't web-checkable is `status: skipped` with its reason; never force one.
3. Stop at ≥30 `used` real bugs (more is fine, within the time-box). Add non-defect criteria (behaviour that works) on the same commits, enough that known-PASS cases reach ≥100.
4. Assign sides with the split rule, write tuning cases (with answers) and held-out cases (no `answer` key) in the repo, held-out answers to `$SELVEDGE_EVAL_HELD_OUT/answers.json`, then `manifest write`, `check-leak`, `count`.
5. Stop any `supabase`/dev server it started before hand-back (the owner's own sports-management Supabase may share ports: check `supabase status` first and use a separate project id / ports if one is running).

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `selvedge/eval/README.md` | YES (ordered by `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/user-story-writing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): reviving 30+ old sports-management commits (migrations, Supabase versions, env, `npm ci` per commit) eats the time-box | HIGH | Stop at the 30 floor; a commit that won't revive is `skipped` with its reason, never forced; reuse one scratch clone and cache `node_modules` per lockfile hash |
| Feasibility (Phase 2.5): two floors (≥100 FAIL, ≥60 held-out FAIL) cannot be met without planted defects, which this run must not write | MEDIUM | Owner decision 2026-11-21: `count` reports them `open`; the evidence file and PR say which floors wait on the planted set; no PASS verdict line for Validation 2 unless all four are met (the owner decides at the READY park) |
| Feasibility (Phase 2.5): supabase / Docker / sports-management access exist only on this machine | MEDIUM | `selvedge/tests/test-eval-set.sh` uses temp fixtures, a temp `HOME` and `SELVEDGE_EVAL_HELD_OUT` pointing at a temp dir, so CI's `static` job needs none of them |
| Held-out real-bug answers are derivable from the committed `parent_sha` / `fix_sha` labels and from sports-management's public history | MEDIUM | Accepted by the requirement (Assumptions, Risks); `selvedge/eval/README.md` says so in plain words; the outside `answers.json` still keeps non-derivable answers (non-defect cases, later planted variants) out of the repo |
| A fail-safe reader read as clean: `git ls-files` or a missing outside folder returning nothing would make `check-leak` / `manifest check` pass vacuously (verified lesson dba90cf3) | HIGH | `no_tracked_files` fails closed; `manifest check` on a missing or empty outside folder fails naming every listed file `manifest_missing_file`; both pinned |
| Tests or the worker write into the real `~/.claude/selvedge-eval/held-out/` or the owner's sports-management checkout | HIGH | Tests always set `SELVEDGE_EVAL_HELD_OUT` and `HOME` to temp dirs; only subtask 2 step 4 writes the real outside folder; sports-management work happens in a scratch clone |
| The owner's own local Supabase for sports-management shares ports with a revived commit | MEDIUM | Check `supabase status` first; run revivals with their own project id/ports and stop everything started before hand-back |
| The outside folder is single-machine; losing it loses the held-out answers | MEDIUM | `selvedge/eval/README.md` states how to back it up (copy the folder; `manifest check` verifies a restored copy) and that a loss means rebuilding the held-out set |
| Feasibility (Phase 2.5): the evidence file `docs/evidence/qa-split-07-known-answer-set.md` is outside the item's Touches and makes the branch "mixed" for `bump-version.sh --check` | MEDIUM | No `changelog.d/` fragment and an unchanged loomwright version keep the branch consistent; `bash scripts/check-version-bump.sh` passes; the owner is asked once at Launch Pad Phase 6 (`LP-SCOPE`) |
| `selvedge/README.md` is large (1018 lines) | LOW | Append one short pointer section only; all set documentation lives in `selvedge/eval/README.md` |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Validation (from the source requirement — must pass before merge)
1. **Static — selvedge gate:** `bash selvedge/tests/run.sh` passes, including the new split, no-leak and manifest tests; `bash scripts/ci-local.sh --affected` green.
2. **Running system — the counts and the leak check:** on this machine, the set's count command prints ≥100 FAIL / ≥100 PASS / ≥30 real-bug FAIL / ≥60 held-out FAIL, and the manifest check passes against the outside folder, then fails naming the file after one byte of a held-out file is changed. Its fenced output goes in `docs/evidence/qa-split-07-known-answer-set.md` (AC9); the ≥100 FAIL and ≥60 held-out FAIL figures are reported as measured (owner decision 2026-11-21).

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-21-qa-split-07-known-answer-set.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-21T15:45:00Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/968
- **Branch:** feature/qa-split-07-known-answer-set
- **Files changed:** 14
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 1
- **Heal reason:** needs_human
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Built selvedge/eval known-answer set tooling (eval-set.mjs, 80 tests) and data: 33 real sports-management bugs observed failing at parent and passing at fix on localhost, 132 non-defect cases, split by group, held-out answers outside behind a sha256 manifest; selvedge 0.8.0. count: known-PASS 165 and real-bug FAIL 33 met; known-FAIL 33/100 and held-out FAIL 21/60 open pending the planted set (owner decision). Phase 4.5 fixed 3 findings in ee69aea (false hidden-answer docs claim, check-leak scanned by filename, false positive on planted variants). Escalated: every held-out answer is derivable from committed data (incl. case_id names) — owner must choose accept vs withhold; one MEDIUM open (validate accepts a real-bug case labelled with another group).

## Not verified
- **check-leak / count on the real committed set** — the set's data files did not exist until subtask 2 (subtask 1)
- **PR body link to docs/evidence/qa-split-07-known-answer-set.md** — no PR opened by the worker; FINALIZE owns it (subtask 2)
- **selvedge/eval/plugin-eval-limits.md claims** — written by subtask 1, not re-run (subtask 2)
