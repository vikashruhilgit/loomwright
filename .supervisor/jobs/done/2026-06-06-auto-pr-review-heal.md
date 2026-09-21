# Supervisor Job: Automated Post-Supervisor PR Review-and-Heal (Standalone, Fresh-Session)

> **REFRESH (2026-06-06):** Regenerated against current `main` (**14.15.0**). **Supersedes** `.supervisor/jobs/pending/2026-06-02-auto-pr-review-heal.md` (prepared when `main` was 14.8.0). Settled design unchanged; everything that drifted was re-resolved: **target version 14.16.0** (next minor from live `main` — *not* 14.9.0), **post-change counts 14 agents / 16 commands / 51 skills / 19 hooks** (the old brief's "14/15/51/19" was wrong — `main` already added a command since 14.8.0, so commands go 15 → 16), and all `file:line` references re-located against the current tree. Pre-flight (Supervisor Phase 1.5) confirmed the feature is **still unbuilt and not superseded** — no `review-pr`/`review-heal`/`dispatch-pr-review.sh` artifacts exist, zero open PRs.
>
> Automates the maintainer's recurring manual habit — "when I'm done with Supervisor I always run code review on the PR" — as an independent fresh review pass that **supplements** (never replaces) Phase 4.5 self-heal. Reuses Phase 4.5's existing review→fix→re-review machinery (`ai-agent-manager-plugin/agents/supervisor.md`, the `while heal_iterations` loop at **:672–743**, `code-reviewer` Task at **:680**, fix worker at **:709–731**).

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — confirms 14.15.0)
- **Git:** working tree clean except untracked `.claude/`, `docs/SPIKES/QA_AND_DURABILITY_BACKLOG.md`, `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md`; **branch is `main`** (clean cut — no stale-branch warning this time). This brief targets base **`main`**; Supervisor Phase 1 branches from up-to-date `main`.
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Authoritative source-of-truth (live, `scripts/check-doc-currency.sh`):** `version=14.15.0  agents=13  commands=15  skills=50  hooks=19` — gate currently GREEN.
- **Version:** base `main` is at **14.15.0**. **Target: 14.16.0** — resolve next-minor from `main` at build time (AC8); do **not** hardcode if `main` has advanced again by build time.
- **Blockers:** 0 | **Warnings:** 0

## Task
**Goal:** Add a **standalone PR review-and-heal** capability — Phase 4.5's review-and-bounded-fix loop, extracted to run independently in a **fresh session** keyed off a PR URL — and wire it to fire automatically after Supervisor finishes. It reuses the existing Code Reviewer agent (read-only) + a `general-purpose` fix worker + the bounded heal loop + the PASS/FAIL/NEEDS_HUMAN model. **Behavior:** PASS → done; BLOCKING/HIGH `new` issues → validate + auto-fix via fix worker, push to the PR branch (never `--force`), re-review (bounded, default 3); **NEEDS_HUMAN → STOP, do not auto-fix, notify the human** (reuse `notify-desktop.sh` / `send-webhook.sh`).

**Two entry points / two senses of "fresh":**
- **Plain `/supervisor`** (inline main-thread): dispatch from the **Phase 4.5 completion tail** — the per-task `SUPERVISOR_RESULT` is emitted at `agents/supervisor.md` **step 5, :998** (carries `pr_url`) → after emission, launch the review-and-heal as a **fresh `claude` OS process** (`claude --agent ai-agent-manager-plugin:review-pr-runner`), decoupled, surviving the Supervisor session. *Gated/opt-in* (see Risks).
- **`/autonomous`** (outer loop already running): chain the review-and-heal as a **Task-spawned step** in EVALUATE (fresh isolated context — NOT a nested `claude` process), inserted **after** EVALUATE's PR-base verification (`skills/autonomous-loop/SKILL.md` **:265–315**) and **before** the Signal-1 rubric gate / iterate-stop decision (**:317**).

**What this is NOT (scope guards):**
- Does **not** replace or rewrite Phase 4.5. Phase 4.5 stays functionally untouched; it gains only a *one-line pointer* to the new shared skill (no rewrite of a load-bearing gate).
- Does **not** auto-launch `/code-review ultra` (user-triggered + billed — cannot be self-launched).
- Does **not** auto-merge. NEEDS_HUMAN always defers to the human (honors the "don't weaken a gate / no self-trust" principle).
- The existing `SubagentStop[ai-agent-manager-plugin:supervisor-runner]` webhook hook is **NOT** the trigger — it only fires for the `claude --agent supervisor-runner` path, not inline `/supervisor`. The trigger is the completion-tail dispatch (**no new hook; hook count stays 19**).

## Acceptance Criteria
- [ ] **AC1 (standalone review-and-heal exists):** Given a PR URL, when the review-and-heal capability runs, then it resolves the PR's branch (`gh pr view <url> --json headRefName`), runs `Task(code-reviewer)` on the diff, and applies the bounded loop: PASS → done; FAIL (`new` BLOCKING/HIGH) → `Task(general-purpose)` fix worker → `git push` (never `--force`) → re-review, up to N iterations (default 3); NEEDS_HUMAN → stop without fixing.
- [ ] **AC2 (NEEDS_HUMAN defers + notifies):** Given the reviewer returns NEEDS_HUMAN (or the bounded loop exhausts with issues remaining), when the loop stops, then it posts findings to the PR (`gh pr comment`), fires `notify-desktop.sh` + `send-webhook.sh` (best-effort, never blocks), and exits without auto-fixing or merging.
- [ ] **AC3 (fresh process for plain `/supervisor`):** Given `/supervisor` completes Phase 4.5 with a PR and auto-review is enabled, when the completion tail runs (after the `SUPERVISOR_RESULT` emission at `agents/supervisor.md:998`), then it invokes `scripts/dispatch-pr-review.sh` which launches a **fresh `claude --agent ai-agent-manager-plugin:review-pr-runner`** process against the PR URL — decoupled from the Supervisor session, fire-and-forget, always exiting 0 from the tail's perspective.
- [ ] **AC4 (opt-in + opt-out, no surprise cost):** Given auto-dispatch is **off by default**, when the user has not enabled it, then the completion tail does nothing extra. When enabled (`auto_review: true` in `.supervisor/notify-config.json` OR a `--auto-review` flag) it dispatches; `--no-auto-review` always suppresses it. The dispatcher enforces a cost/runaway guard (single review per PR per run; a per-PR marker prevents re-dispatch loops).
- [ ] **AC5 (env robustness):** Given the dispatcher needs config, when it runs, then it reads from a **config file** (`.supervisor/notify-config.json` — the same convention `send-webhook.sh` already uses), **not** env-var inheritance, so it works regardless of how `claude` was launched (avoids the known `.zshrc`-env-propagation failure class); if `claude`/config is unavailable it logs one line and exits 0 (never hard-fails the Supervisor tail).
- [ ] **AC6 (autonomous chaining via Task):** Given `/autonomous` multi-iteration mode, when EVALUATE runs after a successful Supervisor iteration with a PR (after PR-base verification, before the iterate/stop decision), then it executes the review-and-heal as a `Task` step (fresh isolated context, no nested `claude`) and records a `REVIEW_HEAL_RESULT` into `iterations[]`; NEEDS_HUMAN surfaces via the loop's existing `AskUserQuestion`.
- [ ] **AC7 (structured result):** Given any review-and-heal run, when it finishes, then it emits a `REVIEW_HEAL_RESULT` block (schema_version 1: `decision` PASS|ESCALATED, `iterations` int, `issues_fixed` int, `remaining_issues` int, `pr_url` string, `notified` bool) documented in `docs/RESULT_SCHEMAS.md`.
- [ ] **AC8 (CI green + accurate counts/version):** Given the change ships, when CI runs, then `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` pass — counts updated to **14 agents / 16 commands / 51 skills / 19 hooks** (new `review-pr` agent + `review-pr` command + `review-heal` skill; **no new hook**) across **every** doc-currency-scanned surface (the 10 in `check-doc-currency.sh` `FILES[]` — see Subtask 6), `SKILLS_INDEX.md` lists the new skill (and its `Total: N skills` line bumps 50 → 51), and the version is bumped to the **next available minor read from `main` at build time** (currently **14.16.0**) — not hardcoded.
- [ ] **AC9 (execution-contract correctness):** Given the runner must spawn child agents (code-reviewer + fix worker), when it runs, then it does so only as the **main agent of its own session** (`claude --agent review-pr-runner`) or inline via `/review-pr` — never Task-spawned (subagents can't spawn subagents). The command + agent carry the same inline-execution-contract preamble as `/supervisor`/`/launch-pad`.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | `review-heal` skill — shared loop contract + pinned names (core) | 1 create | LAUNCHABLE |
| 2 | Entry point: `review-pr` agent (→ review-pr-runner) + `/review-pr` command | 2 create | BLOCKED (by #1) |
| 3 | Auto-dispatch: `dispatch-pr-review.sh` + Supervisor completion-tail hook-in + `--no-auto-review` | 1 create, 2 modify | BLOCKED (by #2) |
| 4 | `/autonomous` EVALUATE chaining (Task step) | 2 modify | BLOCKED (by #1,#2) |
| 5 | Schema + contracts: `REVIEW_HEAL_RESULT` + capability matrix | 2 modify | BLOCKED (by #1) |
| 6 | Docs + version + counts (ALL doc-currency surfaces, version, SKILLS_INDEX, CHANGELOG) | 11 modify | BLOCKED (by #1-#5) |

## Subtask Contracts (v12.0.0)

> **Pinned canonical names — defined by Subtask 1; every other subtask consumes them verbatim (no re-coining):**
> - **Result block:** `REVIEW_HEAL_RESULT` (schema_version 1; fields: `decision` enum `PASS|ESCALATED`, `iterations` int, `issues_fixed` int, `remaining_issues` int, `pr_url` string, `notified` bool).
> - **New agent name:** `ai-agent-manager-plugin:review-pr-runner` (registered via `agents/review-pr.md` frontmatter `name:`, mirroring `supervisor.md`→`supervisor-runner`).
> - **New command:** `/review-pr <pr-url>`; **new skill:** `review-heal`.
> - **Opt-out flag:** `--no-auto-review`; **enable signal:** `auto_review: true` in `.supervisor/notify-config.json` (or `--auto-review`).
> - **Dispatcher:** `ai-agent-manager-plugin/scripts/dispatch-pr-review.sh` (gated, config-file-driven, cost/runaway-guarded, always exits 0).

```yaml
subtask_1:   # review-heal skill (single source of truth for the loop)
  provides:
    - {kind: file,   path: ai-agent-manager-plugin/skills/review-heal/SKILL.md, name: "review-heal skill"}
    - {kind: contract, name: "review->fix->re-review bounded loop + PASS/FAIL/NEEDS_HUMAN + notify-on-NEEDS_HUMAN + PR-URL->branch resolution + the pinned canonical names above"}
  requires: []
subtask_2:   # entry point (agent + command)
  provides:
    - {kind: symbol, path: ai-agent-manager-plugin/agents/review-pr.md,   name: "ai-agent-manager-plugin:review-pr-runner agent"}
    - {kind: symbol, path: ai-agent-manager-plugin/commands/review-pr.md, name: "/review-pr command (inline workflow)"}
  requires:
    - subtask_1
subtask_3:   # auto-dispatch from /supervisor
  provides:
    - {kind: file,   path: ai-agent-manager-plugin/scripts/dispatch-pr-review.sh, name: "gated fresh-process dispatcher"}
    - {kind: symbol, path: ai-agent-manager-plugin/agents/supervisor.md,   name: "Phase 4.5 completion-tail auto-review dispatch + --no-auto-review flag parse + review-heal pointer"}
    - {kind: symbol, path: ai-agent-manager-plugin/commands/supervisor.md, name: "--no-auto-review / --auto-review flag docs"}
  requires:
    - subtask_2   # needs review-pr-runner to dispatch to
subtask_4:   # /autonomous chaining
  provides:
    - {kind: symbol, path: ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md, name: "EVALUATE review-heal Task step"}
    - {kind: symbol, path: ai-agent-manager-plugin/commands/autonomous.md,          name: "review-heal chaining behavior doc"}
  requires:
    - subtask_1
    - subtask_2
subtask_5:   # schema + contracts
  provides:
    - {kind: symbol, path: ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md,          name: "REVIEW_HEAL_RESULT schema"}
    - {kind: symbol, path: ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md,  name: "review-pr-runner capability + standalone-loop budgets/timeouts"}
  requires:
    - subtask_1
subtask_6:   # docs + version + counts
  provides:
    - {kind: artifact, name: "counts 14/16/51/19 + next-minor version bump (14.16.0) + SKILLS_INDEX entry across ALL doc-currency surfaces: CLAUDE.md, README.md, AGENT_GUIDELINES.md, .claude-plugin/README.md, .claude-plugin/marketplace.json, plugin.json, commands/agent-help.md, docs/ARCHITECTURE.md, docs/ARCHITECTURE_CONTRACTS.md, .github/workflows/claude-code-review.yml + non-scanned: SKILLS_INDEX.md, CHANGELOG.md"}
  requires:
    - subtask_1
    - subtask_2
    - subtask_3
    - subtask_4
    - subtask_5
```

## File Impact Map

> **Line numbers are against `main` @ 14.15.0 and WILL drift as workers edit. Treat every `:NNN` as a starting anchor — re-locate by reading/grepping the current file before editing, especially in later batches where earlier subtasks have already shifted lines.**

**Subtask 1 — `review-heal` skill (LAUNCHABLE)**
- `ai-agent-manager-plugin/skills/review-heal/SKILL.md` — CREATE (HIGH): the shared review→fix→re-review loop (mirrors `supervisor.md:672–743`), PASS/FAIL/NEEDS_HUMAN handling, bounded iterations (default 3), notify-on-NEEDS_HUMAN, PR-URL→branch resolution (`gh pr view --json headRefName`), and the pinned canonical names. Phase 4.5 is NOT rewritten — it gains only a one-line "see `review-heal` skill" pointer (added in Subtask 3's `supervisor.md` edit, to avoid a second writer of that file here). Add version/lastUpdated frontmatter per the skill convention; follow `skills/SKILL_TEMPLATE.md`.

**Subtask 2 — Entry point (BLOCKED by #1)**
- `ai-agent-manager-plugin/agents/review-pr.md` — CREATE (HIGH): frontmatter `name: ai-agent-manager-plugin:review-pr-runner`, `tools: Task, Read, Glob, Grep, Bash` (no Write/Edit — fixes go through the `general-purpose` fix worker), `model: inherit`. Body references the `review-heal` skill. Mirrors `agents/supervisor.md` runner structure (frontmatter shape at `supervisor.md:1–18`).
- `ai-agent-manager-plugin/commands/review-pr.md` — CREATE (HIGH): inline main-thread workflow with the same execution-contract preamble as `commands/supervisor.md` (the "Execute this workflow inline… don't auto-delegate to the runner; spawn code-reviewer + fix worker via Task" block).

**Subtask 3 — Auto-dispatch (BLOCKED by #2)**
- `ai-agent-manager-plugin/scripts/dispatch-pr-review.sh` — CREATE (HIGH): reads `.supervisor/notify-config.json` (config-file, not env-var), checks the `auto_review` enable flag + a per-PR dispatch marker (cost/runaway guard), launches `claude --agent ai-agent-manager-plugin:review-pr-runner` against the PR URL fire-and-forget, always exits 0. Mirror the defensive style of `scripts/send-webhook.sh`. Add a self-test (`test-dispatch-pr-review.sh`) per repo convention (self-tests are **uncounted** by doc-currency).
- `ai-agent-manager-plugin/agents/supervisor.md` — MODIFY (HIGH): (a) Phase 4.5 completion tail — after the `SUPERVISOR_RESULT` emission (**step 5, :998**; the tail's later steps — twin builder step 4.5 :901, twin-delta step 6 :1000 — already exist), add a new gated best-effort step that calls `dispatch-pr-review.sh` respecting `--no-auto-review`/`--auto-review`/config; (b) add `--no-auto-review`/`--auto-review` to the Inputs **Flags** list (**:49**) and the Phase 0 flag-parse preamble (the `5a` block, ~**:134–161**); (c) add the one-line `review-heal` skill pointer near the Phase 4.5 loop intro (~**:672**).
- `ai-agent-manager-plugin/commands/supervisor.md` — MODIFY (MEDIUM): document `--no-auto-review` / `--auto-review` in the flags table (after the `--cheap` row, **:46**) and the Usage block.

**Subtask 4 — `/autonomous` chaining (BLOCKED by #1,#2)**
- `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md` — MODIFY (HIGH): add a review-heal `Task` step in **EVALUATE (:251)** — placed **after** PR-base verification (**:265–315**) and **before** Signal 1 (**:317**); record `REVIEW_HEAL_RESULT` into `iterations[]` (extend the `state.json` `iterations[]` shape at **:130**); NEEDS_HUMAN routes through the existing `AskUserQuestion`.
- `ai-agent-manager-plugin/commands/autonomous.md` — MODIFY (MEDIUM): document the chained review-heal behavior near the EVALUATE description (**:26**) / Parameters (**:44**).

**Subtask 5 — Schema + contracts (BLOCKED by #1)**
- `ai-agent-manager-plugin/docs/RESULT_SCHEMAS.md` — MODIFY (HIGH): add the `REVIEW_HEAL_RESULT` block (schema_version 1) with the pinned fields, placed near `LAUNCH_PAD_RESULT` (**:1223**); note it reuses `CODE_REVIEW_RESULT` for the underlying review; add a Version History entry (**:1098+**).
- `ai-agent-manager-plugin/docs/ARCHITECTURE_CONTRACTS.md` — MODIFY (MEDIUM): add `review-pr-runner` to the capability matrix; document the standalone loop's tool-call budget + timeout + the fresh-process dispatch contract. (doc-currency-scanned — keep any count phrasing accurate.)

**Subtask 6 — Docs + version + counts (BLOCKED by #1-#5)** — the 10 doc-currency-scanned surfaces (`check-doc-currency.sh` `FILES[]`) + 2 non-scanned:
- `CLAUDE.md` — MODIFY (HIGH): rotate the banner (two-recent rule: drop the v14.14.0 banner, add a v14.16.0 banner); `:13` "13 agent roles" → 14; `:29`/`:48` "13 markdown prompts" → 14; `:30` "15 entry points" → 16; `:49` "15 slash commands" → 16; `:28` `plugin.json (v14.15.0)` → `(v14.16.0)`; "## The 13 Agent Roles" heading + table → 14 (add `review-pr-runner` row — note: not gate-matched but must be accurate); add `review-pr`/`review-heal` to the relevant tables and the Hooks note (hooks stay 19).
- `README.md` — MODIFY (HIGH): `:3` "13 specialized agents" → 14 (and add review-pr-runner to the named list); `:21` "13 agent roles, 15 slash commands, 50 skills, 19 quality gate hooks" → "14 … 16 … 51 … 19"; `:144` "## The 13 Agents" → 14; add a `/review-pr` entry.
- `AGENT_GUIDELINES.md` — VERIFY (LOW): currently carries no gate-matched count claim (the `:261` "multi-agent system" text has no numeric prefix). Confirm no count claim is introduced; likely no edit needed.
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` — MODIFY (HIGH): `version` → 14.16.0 + `description` counts updated **in place** (anti-rebloat — no new clause).
- `.claude-plugin/marketplace.json` — MODIFY (HIGH): `version` → 14.16.0 + description, same in-place rule.
- `.claude-plugin/README.md` — MODIFY (HIGH): `:3` "13 agent roles (…)" + "50 focused skills" → 14 / 51; `:9` "15 slash commands, 50 skills, 19 hooks" → 16 / 51 / 19; `:390` "Slash commands (15)" → 16; `:397` "50 focused skill modules" → 51; `:396`/`:458` hook counts stay 19; add `/review-pr` + `review-heal` entries.
- `ai-agent-manager-plugin/commands/agent-help.md` — MODIFY (HIGH): `:978` "Slash commands (15)" → 16; add a `/review-pr` entry to the command list. (doc-currency-scanned; **not** cross-checked by `check-command-sync.sh` — that script only inspects `commands/code-reviewer.md` — so no sync break, but keep the list complete.)
- `ai-agent-manager-plugin/docs/ARCHITECTURE.md` — MODIFY (MEDIUM): `:3` "13-agent system" → 14.
- `.github/workflows/claude-code-review.yml` — MODIFY (MEDIUM): `:32` "13 specialized agents and 50 skills" → 14 / 51 (both matched by the `specialized agents` + `and N skills` patterns).
- `ai-agent-manager-plugin/skills/SKILLS_INDEX.md` — MODIFY (HIGH, non-scanned): add the `review-heal` skill row; bump `:99` "**Total: 50 skills**" → 51.
- `CHANGELOG.md` — MODIFY (HIGH, non-scanned): new `v14.16.0` entry summarizing the standalone PR review-and-heal capability.

## Parallelism Analysis
- **Batch 1:** Subtask 1 (skill — defines the contract + pinned names everything references)
- **Batch 2:** Subtask 2 ‖ Subtask 5 (both require only #1; disjoint files — `agents/`+`commands/review-pr` vs `docs/`)
- **Batch 3:** Subtask 3 ‖ Subtask 4 (#3 requires #2; #4 requires #1,#2; disjoint files — `scripts/`+`supervisor.md`+`commands/supervisor.md` vs `autonomous-loop`+`commands/autonomous.md`)
- **Batch 4:** Subtask 6 (docs/version/counts — the doc-currency-checked surfaces, done last so counts/version are consistent)
- **Recommended workers:** 2
- **Overlap note:** No literal file overlap within any batch. The one cross-file consistency point — `REVIEW_HEAL_RESULT` appears in #5 (definition), #2/#4 (emission/consumption) — is resolved by **pinning the block name + fields in Subtask 1's contract**, so no worker coins it independently.

## Configuration
- **Base Branch:** main
- **Max workers:** 2
- **Self-heal:** enabled (Phase 4.5 — this change is mostly new files + prose; the integration review is valuable)
- **Cost profile:** default (inherit)
- **Suggested command:** `/supervisor job: .supervisor/jobs/pending/2026-06-06-auto-pr-review-heal.md`

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Auto-spawning a fresh `claude` process from the completion tail = surprise cost / runaway | **HIGH** (Feasibility CAUTION) | **Off by default** (opt-in via `auto_review: true` config flag); `--no-auto-review` always suppresses; per-PR dispatch marker prevents re-dispatch loops; `review-pr` does not create PRs so there's no review→review recursion; dispatcher fire-and-forget, always exits 0. |
| Surface growth: +1 agent, +1 command, +1 skill (anti-rebloat tension) | MEDIUM (Feasibility CAUTION) | Reuses existing Code Reviewer + fix worker + heal loop (no logic duplication — single source in the `review-heal` skill); descriptions updated in place; justified by a high-frequency manual habit. |
| Env/config not reaching the dispatched process (the `.zshrc` env-var propagation bug class) | MEDIUM | Config-file driven (`.supervisor/notify-config.json`), not env-var inheritance (AC5); graceful exit-0 on missing tooling. |
| Fix worker can't push (PR branch not checked out in the fresh process) | MEDIUM | Runner fetches + checks out the PR's `headRefName` before the loop; never `--force`-pushes. |
| Weakening a gate / auto-merge | HIGH→mitigated | NEEDS_HUMAN always stops + notifies, never fixes/merges (AC2); honors no-self-trust. |
| Destabilizing Phase 4.5 (load-bearing) | MEDIUM | Phase 4.5 is NOT rewritten — pointer reference only; full de-duplication deferred. |
| Stale `file:line` anchors from 7 minor-versions of drift since the original brief | MEDIUM (refresh-specific) | All anchors re-resolved 2026-06-06; File Impact Map header warns workers to re-locate before editing; Batch 4 (docs) runs last after line shifts settle. |
| Doc-currency failure (10 scanned surfaces + SKILLS_INDEX + CHANGELOG) | LOW | Subtask 6 updates all; AC8 asserts 14/16/51/19; run `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` before finishing. |
| Version target re-drift if `main` advances again before build | LOW | AC8: resolve next-minor from `main` at build time, don't hardcode (14.16.0 is the value as of 2026-06-06). |

## Feasibility (Phase 2.5)
- **Verdict:** GO (2 CAUTIONs)
- Tech stack: GO — markdown agent/command/skill + one shell script; native medium.
- Dependencies: GO — `git`, `gh`, `claude` CLI, existing `notify-desktop.sh`/`send-webhook.sh`, existing code-reviewer + `general-purpose` fix worker. All verified present.
- Architecture fit: GO with **CAUTION** — adds new agent/command/skill surface AND a new "auto-spawn fresh `claude` process" pattern; must honor anti-bloat + the no-surprise-autonomy principle (→ opt-in default).
- Scope: GO — 6 subtasks, ~30-60 min each.
- Hard blockers: none. **CAUTION:** the auto-dispatch default (opt-in vs opt-out) is a real policy choice — defaulted to opt-in here; flip only with explicit maintainer intent.

## Open Design Decisions (settled — for Plan Review confirmation)
1. **Default for auto-dispatch:** **opt-in (off by default)**. The maintainer wanted it "automated" — if they prefer **on by default**, flip AC4 (guards remain). *(Carried from the 2026-06-02 brief unchanged.)*
2. **Entry shape:** **dedicated `/review-pr` command + `review-pr-runner` agent** (matches the "/code-review this PR" mental model + the existing runner pattern). Leaner alternative: a `/supervisor --review-pr <url>` mode (no new command/agent, but overloads Supervisor). **Recommended: dedicated command** for clarity. *(Carried unchanged.)*

## Handoff
Start a **fresh** session (clean context) and run:

```
/supervisor job: .supervisor/jobs/pending/2026-06-06-auto-pr-review-heal.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-06
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/32
- **Branch:** feature/auto-pr-review-heal
- **Files changed:** 22 (21 feature files + capability-check.md count fix)
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1 (review FAIL → fixed 1 HIGH + 5 consistency items → re-review PASS)
- **Heal remaining issues:** 0
- **Summary:** Added standalone PR review-and-heal (v14.16.0): review-heal skill, review-pr agent + /review-pr command, dispatch-pr-review.sh (+self-test 9/9), Supervisor completion-tail opt-in dispatch, /autonomous EVALUATE chaining, REVIEW_HEAL_RESULT schema, counts 14/16/51/19. CI gates (doc-currency, validate-version, command-sync) green. Phase 4.5 self-heal fixed a HIGH maxTurns contradiction + count-drift; re-review PASS.
