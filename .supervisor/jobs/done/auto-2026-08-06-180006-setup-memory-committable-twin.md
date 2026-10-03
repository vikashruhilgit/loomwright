# Supervisor Job: Make the Twin committable — gitignore negation, repo allowlist, `/setup memory`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — last committed 2026-08-05)
- **Git:** clean (0 files), branch: main @ 261ff1b
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (two pre-existing `.claude/worktrees/` checkouts from earlier sessions; unrelated to this job, do not clean them up)
- **Source requirement:** .supervisor/requirements/twin-loop/01-commit-the-distilled-twin.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash + jq + git, the established stack for every `loomwright/scripts/*.sh` helper. `setup-twin.sh` is a direct structural precedent. |
| 2 | Dependency Availability | GO | `git`, `jq`, `bash` all present and already required by the plugin. No new dependency. |
| 3 | Architecture Fit | GO | An 8th `/setup` module following the documented check → report → offer → apply → verify contract (`skills/setup/SKILL.md` Pattern 1), engine-in-script + interactive-half-in-command (the `twin` module's exact shape). |
| 4 | Scope vs Supervisor Capability | GO | One coherent capability: one new engine script, one new self-test, and the command/skill/doc wiring that must land in the same commit. Below the Decomposition Threshold — single subtask. |
| 5 | Hard Blockers | CAUTION | Two, both mitigable and recorded in Risk Assessment: (a) the run's own `.supervisor/config.json` is engine-owned for the duration (see Risk 1); (b) the `AskUserQuestion` ≤4-option set is already saturated at `setup.md:97` and MUST be reworked, not appended to. |

**Overall Verdict:** CAUTION (proceed; both findings carried into Risk Assessment)

## Task
**Goal:** Ship a `/setup memory` module plus the gitignore-negation and repo-allowlist machinery that lets any repo put its Twin stores under version control in place — no move, no symlink, no generated copy — proven in a scratch fixture repo.

**Problem Statement:**
Every repo the plugin runs in needs its accumulated Twin judgment recoverable, but that judgment is not in version control. `.gitignore:34` ignores `.claude/` and `.gitignore:35` ignores `.supervisor/`; `git ls-files .supervisor .agent .claude` returns exactly three files — two `README.md`s plus `.agent/rules/process.json`, i.e. one rule and zero memos.
Currently a fresh clone, a second machine, CI, and every `git worktree` checkout start cold, and a bad curation pass is irreversible because there is no `git checkout` to undo it and the source session logs are themselves gitignored.
Success looks like: a repo can run `/setup memory`, understand exactly what becomes version-controlled, apply it, and have `git check-ignore` prove per path that the intended stores commit and the unintended ones stay ignored — with nothing moved and every `memory: project` agent still receiving its store.

**Scope decision carried in from planning (OWNER-CONFIRMED — do not re-litigate):** this item ships the **allowlist mechanism only**. The gitignore negation set is exactly `.claude/agent-memory/` and `.supervisor/memory/`, matching the requirement's own acceptance criteria verbatim. **`.supervisor/postmortem/` is NOT negated and the findings ledger is NOT committed by this item** — the allowlist here is a reusable, fixture-proven config + filter predicate. Whether the ledger becomes a committed path is item 01b's decision, using this item's filter. Rationale: committing the ledger in place would mean a destructive rewrite of a file whose sole sanctioned writer (`scripts/curate-postmortem.sh`) is explicitly append-only (retract-by-appending-a-line), and would publish 77 findings to a PUBLIC repo as a side effect of a capability change.

## Acceptance Criteria
- [ ] Given a scratch fixture repo with the naive `.claude/` + `!.claude/agent-memory/` form, when the test asserts ignore status, then the negation is proven to **FAIL** (`git check-ignore` still matches) — the silent failure is asserted, not commented.
- [ ] Given the same fixture rewritten to the `.claude/*` + `!.claude/agent-memory/` form, when the test asserts ignore status, then `agent-memory/**` and `.supervisor/memory/**` are committable.
- [ ] Given that fixture, when each unintended path is asserted, then `.claude/worktrees/`, `.claude/settings.local.json` and `.supervisor/logs/` all remain ignored — asserted per path via `git check-ignore`, never as a bulk claim.
- [ ] Given dotfile sidecars `.provenance.jsonl` and `.lessons-provenance.jsonl` inside a negated store, when their ignore status is asserted, then both are committable — asserted explicitly and separately from the `**` globs.
- [ ] Given a fixture whose ledger holds records under a pre-rename slug and a current slug, when the allowlist filter runs with both slugs listed, then records under **both** are retained.
- [ ] Given that same fixture, when the filter runs, then a record whose `repo` is outside the allowlist is excluded.
- [ ] Given a fresh install with no configured allowlist, when the allowlist is resolved, then it defaults to the current git remote's `owner/repo` — and the allowlist is stored as a **list**, never a string.
- [ ] Given an already-applied repo, when `/setup memory` runs a second time, then it reports "already configured" and writes nothing (idempotent no-op).
- [ ] Given a hand-edited or unparseable `.gitignore`, when apply runs, then it changes nothing, reports why, and exits without a partial write.
- [ ] Given an applied repo, when `/setup memory remove` runs, then future tracking stops AND the output states plainly that git history retains anything already pushed.
- [ ] Given the shipped `commands/setup.md`, when its `## Constraints` block is read, then the `memory` module's `.gitignore` write class has its own explicit constraint line, and the `AskUserQuestion` option set is reworked to stay within 4 options with every module still reachable.
- [ ] Given the applied repo, when the sentinel probe is re-run, then a `memory: project` agent still receives its store from the unchanged harness path — nothing moved.

## Outcomes Rubric
- Negation-in-place; zero move/symlink/copy machinery
- Naive-form failure and dotfile survival both asserted by test
- Allowlist is a list; rename case covered; portable to other users
- `/setup memory` follows the module contract, with a real `remove` and honest consent copy
- Tracked-write risk stated and explicitly handed to item 04

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `/setup memory` module: negation engine, repo allowlist, fixture self-test, command/skill/doc wiring | all | 10 modify, 2 create | `skills/setup/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/context-setup/SKILL.md` | LAUNCHABLE |

> **`provides` naming discipline (do not weaken).** The deterministic `outputs_verified` gate for `kind: symbol` is a bare `grep -nE '<name>' <path>` (`agents/worker.md` Step 5.5). Every name below is therefore chosen to be **absent from the file today and unique to the NEW content** — a name that matches incidental prose (`check`, `apply`, `remove`) or an already-present heading verifies green without the work being done. If you rename a function during implementation, update the matching `provides` entry in the same edit; do not leave a name that no longer discriminates.

```yaml
# Subtask 1 — /setup memory module (LAUNCHABLE)
provides:
  - {kind: "file",   path: "loomwright/scripts/setup-memory.sh"}
  # Dispatch functions, mirroring the setup-twin.sh precedent (`check) do_check ;;` at :333).
  # NOT bare "check"/"apply"/"remove" — those match incidental prose this file is
  # guaranteed to contain ("git check-ignore", "apply the negations", "removal stops
  # future tracking"), so the gate could not distinguish shipped subcommands from mentions.
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "do_check"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "do_apply"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "do_remove"}
  # The repo-allowlist half — ACs 5/6/7 and Outcomes Rubric bullet 3 are entirely about
  # this, so it MUST be addressable or the gate cannot detect a worker that ships the
  # gitignore negation and skips the allowlist.
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "resolve_allowlist"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "filter_ledger_by_allowlist"}
  - {kind: "file",   path: "loomwright/scripts/test-setup-memory.sh"}
  - {kind: "symbol", path: "loomwright/commands/setup.md", name: "Module: memory"}
  # The NEW registry ROW, not the enclosing heading — "### Pattern 2 — Module registry"
  # already exists at SKILL.md:40 and would verify green untouched. The literal below is
  # discriminating: the string "memory" currently appears exactly once in that file
  # (line 164, inside the unrelated phrase "in-memory $PK/$SK").
  - {kind: "symbol", path: "loomwright/skills/setup/SKILL.md", name: "\\| `memory` \\|"}
requires: []
lanes:
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/test-setup-memory.sh"
  - "loomwright/commands/setup.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/commands/agent-help.md"
  - ".claude-plugin/README.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "CLAUDE.md"
  - "README.md"
external_requires:
  - "git >= 2.x (git check-ignore, git rev-parse --show-toplevel)"
  - "jq (allowlist config read/write, ledger record filtering)"
```

**Skill-version lockstep (required, CI-gated):** editing `loomwright/skills/setup/SKILL.md` bumps its frontmatter `version:` **1.0.0 → 1.1.0**, and the matching row in `loomwright/skills/SKILLS_INDEX.md:30` (`| Setup | setup/ | … | 1.0.0 | 2026-06-13 |`) must be updated in the SAME commit. `scripts/check-skills-index-sync.sh` fails CI with `DRIFT [version]` otherwise — this is the `supervisor-readiness` / `async-orchestration` precedent from v15.20.0.

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
| 1 | `skills/setup/SKILL.md` (module contract + registry — the authority), `skills/quality-checklist/SKILL.md`, `skills/context-setup/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **`.supervisor/config.json` is owned by the running `/automate` engine.** The engine suppressed `auto_review` into that file and will DELETE it on restore (it was originally absent). Any allowlist seeded there during this run is destroyed. | HIGH | **Do NOT write `.supervisor/config.json` in this repo during this job.** The allowlist config surface must be read/written only inside the scratch fixture repo the tests create. This item is plugin capability; seeding this repo's real allowlist is item 01b's job. |
| **The `AskUserQuestion` ≤4-option set at `setup.md:97` is already saturated** — 4 options with 4 modules folded into one. An 8th module cannot be appended. | HIGH | Rework the fixed set rather than growing it: keep `observability`, fold `twin` + `memory` into one "repo knowledge stores" option that branches to a nested ≤4-option question, keep the folded "Other integrations", keep the opt-out. `/setup memory` as a direct jump must work regardless of the dashboard set. |
| **Committing agent memory publishes it.** `vikashruhilgit/loomwright` is a PUBLIC repo, and a user's agent memory can hold proprietary architecture, internal service names, or client detail. | HIGH | The offer step is consent-bearing and must never be a silent default: state plainly what becomes version-controlled BEFORE applying. `remove` must state that git history retains what was already pushed — removal stops future tracking, it does not unpublish. |
| **Naive gitignore negation fails silently.** `.claude/` + `!.claude/agent-memory/` looks correct and does nothing; git cannot re-include a file whose parent directory is excluded. | HIGH | Assert the failure in the test suite, not in a comment. Both the failing and the working form are fixture-asserted. |
| **A live-remote-keyed allowlist silently drops the older half of a ledger.** This repo's ledger holds 42 records under the pre-rename `vikashruhilgit/ai-agent-manager` vs 35 under the current `vikashruhilgit/loomwright`. | MEDIUM | The allowlist is a LIST, never a string and never derived from the live remote at read time. A repo rename is the documented reason for the list shape — record that rationale in the code, not only the brief. |
| **Hardcoding `vikashruhilgit/*` would break every other user.** | MEDIUM | Default the allowlist to the current remote on fresh install; make it extensible via config. Never ship an owner-specific default. |
| **Tracked-directory writes become working-tree modifications** once `.claude/agent-memory/` is tracked — they show in `git status`, can be swept into an unrelated commit by `git add -A`, and `MEMORY.md` becomes a conflict surface under parallel workers. | MEDIUM | **In scope: state it. Out of scope: fix it.** Record the risk explicitly in the module docs and hand the mitigation to item 04 (agent writes go to a gitignored proposal queue; only `/dreaming`-promoted entries touch the tracked store). Do not build the queue here. |
| **Doc-currency is CI-enforced** and this change adds an 8th `/setup` module, touching several count/version claims. | MEDIUM | Bump the version in `plugin.json` + `marketplace.json`, add the CHANGELOG entry, update the CLAUDE.md latest-change banner, and sweep **every** module enumeration — not just the ones easy to grep: `README.md:215`, `agent-help.md:785-794`, **the bare count "across 7 modules" at `agent-help.md:787` (→ 8)**, **`.claude-plugin/README.md:122`** (in `check-doc-currency.sh`'s `FILES` array, enumerates "observability, telemetry, notifications, Twin bootstrap"), the `commands/setup.md` frontmatter `description`, and both manifest `description` fields. Grep the bare number with flexible separators, not only the exact phrase. A green `check-doc-currency.sh` is necessary but not sufficient. |
| **`test-setup-memory.sh` runs inside the plugin's own repo under CI**, where `git init`-ing a fixture and writing `.gitignore` could leak into the real tree. | MEDIUM | Every fixture is created under a `mktemp -d` scratch directory with its own `git init`, cleaned in a trap. The test must never touch the plugin repo's own `.gitignore`. The CI anti-drift loop at `.github/workflows/ci.yml:62` picks up `test-*.sh` automatically — no CI wiring change needed. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/auto-2026-08-06-180006-setup-memory-committable-twin.md
```
