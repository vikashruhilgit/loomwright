# CLAUDE.md

Guidance for Claude Code when working in this repository.

- User-facing docs (install, quick start, commands, troubleshooting): `README.md`
- Development standards & shared agent contract: `AGENT_GUIDELINES.md`
- This file captures what's *not* obvious from those — invariants, schemas, hooks, and incident-derived gotchas

---

## Project Overview

**Loomwright** is a Claude Code plugin with 14 agent roles (9 user-facing + 5 internal) for plan-first readiness, parallel execution, requirements, planning, code review, commits, adversarial audits, standalone PR review-and-heal, and dual-agent QA. Supervisor and Launch Pad use `.supervisor/` exclusively for state; Orchestrator and Product Owner can optionally use Beads.

**Version + counts:** authoritative in `plugin.json` (see `Plugin Layout` below for the per-directory breakdown) — **never restated here, and that includes this banner.** Deliberately version-free: a number written here is a second copy that has to be bumped by hand every release, which is exactly the drift this file warns about elsewhere. Say "the previous release", not a version string; the changelog's top entry is always the current one.

**Latest change:** **the floor acts — guarded writes from the page.** Item 06 made the page *show* the project registry; it still could not touch it, and the blocker was structural: the module served the bundle with a static file server that answers `501` to every write, so there was no endpoint to call. The earlier view had also justified having **no authentication** with "there is nothing to authenticate against on loopback" — sound for a read-only page, and **unsound the moment a write exists**, which is the real content of this change. A loopback port is not a security boundary in a browser: any site open in another tab can POST at `127.0.0.1:<port>` (the attacker never reads the reply, but the write has landed), and DNS rebinding extends that to a remote origin. A stdlib threading request handler replaces the static server — **no new dependency, no Node, no npm, no CDN** — preserving every `GET` byte-for-byte and still answering `501` to unrouted writes. **Exactly four mutating routes exist and the set is read out of the engine rather than restated in the test**; the two install-level verbs are excluded *by decision, not omission*, because a page able to uninstall itself buys nothing and risks something. **The guard is four parts, all required together**, because any one alone is defeatable: a per-run token, **carried in a custom header** so a preflight a hostile cross-origin page cannot satisfy is forced (closing the simple-request hole where a write lands unread), plus `Origin` and `Host` validation — the latter being what actually defeats rebinding, which an `Origin` check provably cannot. **Each part is proven load-bearing by a control that disables that part alone and watches the previously-refused request succeed**, with a further control that fails red if any of those four is ever silently skipped. The token travels in the URL fragment, which is never transmitted to a server, and the page strips it. Paths from the browser are untrusted input — resolved, confined, refused by name for traversal, non-directories and escaping symlinks — while **the command line stays deliberately unconfined**, because the terminal is the trusted channel and the browser is not. **Eight existing gate groups had their subject replaced and every one was repaired rather than deleted or relaxed**; the enumeration was the hard part and took three review rounds, because a list assembled from memory found two and a sweep for *the tokens a scanner matches* found four — only a sweep for **scanner names and assertion subjects** found all eight. Two of them fail *silently* (their mutants anchor on an exact string in the file being changed, so once it is gone the control is skipped rather than red), so the repairs assert the control still executes; one held a private copy of a shared regex and would have gone quietly vacuous. The kill-guard case that no test covered — replacing the server changes the command line `stop` matches on — went from **zero coverage to seven**. `serve` writes one further file, a log of mutating requests only, added because "the token never appears in the server's own output" was unfalsifiable while that output went to `/dev/null`. Counts are unchanged: the command gained no verb — the page gained the ability to invoke ones that already existed. Full narrative in `CHANGELOG.md`.

> 📜 **Full release history** (every version, including the current one) lives in [`CHANGELOG.md`](CHANGELOG.md). CLAUDE.md keeps only the one-paragraph latest-change summary above — full release notes belong in the changelog, not here. **Write that summary without version numbers or counts:** both already live in `plugin.json` and `CHANGELOG.md`, and a hand-maintained copy here goes stale silently (`check-doc-currency.sh` verifies numbers that ARE claimed; it cannot tell you a claim should not have been made). Historical anchors elsewhere in this file that name the release an incident or a refactor happened in are fine — those are fixed points that never need bumping.

---

## Plugin Layout

The repo is a **marketplace wrapper** containing three sibling plugins (loomwright, stackpack, mysql-mcp):

- Marketplace manifest: `.claude-plugin/marketplace.json` (root)
- Plugin manifest: `loomwright/.claude-plugin/plugin.json`
- Agents: `loomwright/agents/` (14 markdown prompts)
- Commands: `loomwright/commands/` (22 entry points)
- Skills: `loomwright/skills/` (41 skills, see `SKILLS_INDEX.md`)
- Hooks: `loomwright/hooks/hooks.json`
- Docs: `loomwright/docs/`
- Sibling plugins: `stackpack/` (18 tech-stack reference skills, v1.0.0) and `mysql-mcp/` (read-only MySQL MCP server `vikashruhil-mysql-mcp`, v1.0.0)

> **Repo path vs. runtime path:** `loomwright/...` is the developer-side path (this repo on disk). Anything invoked by hooks, skills, or agents at *runtime* must reference `${CLAUDE_PLUGIN_ROOT}/...` — that's the canonical Claude Code variable that resolves to the plugin install dir on both dev checkouts and marketplace installs. Never use `loomwright/...` paths from the user-project root; they only resolve for the plugin maintainer.

---

## The 14 Agent Roles

Full per-agent invariants, the `/autonomous` orchestration shell, the Shared Agent Contract, and the Parallel Execution Model relocated to `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Agent Invariants" in the v15.21.0 diet (content moved, never deleted). Detailed per-agent purpose and workflow diagrams also live in `README.md` §"The 14 Agents" and the agent prompts (`loomwright/agents/*.md`). Quick name/type/purpose map:

| Agent | Type | One-line purpose |
|---|---|---|
| Launch Pad | user-facing | Raw goal → reviewed Supervisor-ready brief |
| Supervisor | user-facing | Parallel orchestration, 7-phase workflow |
| Product Owner | user-facing | Requirements → Beads/requirement-file stories |
| Orchestrator | user-facing | Goal → EPIC/TASK decomposition |
| Code Reviewer | user-facing | Read-only diff/consistency review |
| Red Team Reviewer | user-facing | Adversarial audit, 6 attack vectors |
| QA Strategist | user-facing | Risk-based test strategy + audit |
| QA Executor | user-facing | Discovery, test generation, execution |
| Review-PR (`review-pr-runner`) | user-facing | Standalone PR review→fix→re-review loop |
| Execute Manager | internal | Phase 3 poll loop + worker lifecycle |
| Context-Keeper | internal | Sole state-file writer (parallel path) |
| Worker | internal | Implements one subtask (worktree or Single-Agent Path) |
| Plan Reviewer | internal | Gates brief save (PASS / NEEDS_HUMAN / FAIL) |
| Rubric Grader | internal | Advisory Phase 4.5 outcomes scorer |

---

## Adding or Modifying Agents

1. **New agent:** `.md` in `loomwright/agents/` with YAML frontmatter; output follows Context Read → Plan → Work → Results → Risks. **Also declare a token budget:** add an `.agents[<stem>]` entry to `loomwright/docs/prompt-token-budgets.json` (measured proxy weight + ~10% headroom) plus the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" — `check-token-budget.sh` fails CI CLOSED on an agent with no declared budget
2. **New slash command:** `.md` in `loomwright/commands/` referencing the agent prompt
3. **New skill:** `SKILL.md` in `loomwright/skills/[name]/` with version frontmatter; update `SKILLS_INDEX.md`
4. **Test locally:**
   ```
   /plugin uninstall loomwright
   /plugin install loomwright@atelier
   ```
   Verify with `/agent-help`
5. **When referencing code from committed prose or comments, prefer a descriptive anchor** ("the `category` guard in §1 above") over a bare `file.ext:<N>` — an absolute line number is falsified by the next insertion above it, silently. If a number genuinely aids navigation in a long file, **pin it** so it can be re-derived: `` emit-token-ledger.sh:128 [pins: `running|checkpoint)`] ``. `scripts/test-citation-drift.sh` verifies every pin against the cited file and **fails any new bare, unpinned citation**. (This applies to text that gets committed. Ephemeral review output — a `file:line` in a code-review finding — is consumed immediately and should stay exact.)

**Doc currency is CI-enforced:** `scripts/check-doc-currency.sh` mechanically verifies that version/count claims across the doc surfaces match the authoritative source (`plugin.json`, `hooks.json`, the `agents/`/`commands/`/`skills/` dirs) — update the doc claims in the same change or CI fails. Full scope (what's scanned vs. deliberately unscanned, the frozen-example-value convention for illustrative `session_end`/`POSTMORTEM_RESULT` records and `e.g. "X.Y.Z"` placeholders) lives in the script's own header comment — on any phase/version/budget/section change, grep the OLD value repo-wide; a green doc-currency run is necessary but not sufficient.

**Plugin `description` is a summary, not a changelog (anti-rebloat):** the `description` field in `plugin.json` and `.claude-plugin/marketplace.json` is the crisp card shown in the plugin-manager UI. On a version bump, update the `vX.Y.Z` string and the four counts **in place** and keep it short; put the per-release narrative in `CHANGELOG.md` (and, if notable, a single CLAUDE.md banner) — **never append another version clause to the description.**

**Hook gotcha:** Claude Code silently ignores `hooks`, `mcpServers`, and `permissionMode` in plugin agent frontmatter — only `hooks.json` hooks fire for plugin-distributed agents. Per-agent frontmatter hooks are kept for `~/.claude/agents/` compatibility.

---

## Structured Contracts (v9.0.0)

- **Result Schemas** — `loomwright/docs/RESULT_SCHEMAS.md` (all current `schema_version`s + per-schema field contracts; single source of truth — this file no longer restates them)
- **Failure Escalation** — `…/FAILURE_ESCALATION.md` (retry limits, escalation paths)
- **Architecture Contracts** — `…/ARCHITECTURE_CONTRACTS.md` (capability matrix, context budgets, timeouts, worktree naming, per-agent invariants)
- **Job Lifecycle** — briefs flow `pending/` → `in-progress/` → `done/` / `failed/` in `.supervisor/jobs/`
- **Session Logging** — JSONL in `.supervisor/logs/{session_id}.jsonl`
- **Merge Safety Gate** — pre-merge checklist in FINALIZE prevents corrupted partial merges

---

## Plugin Hooks (Quality Gates)

Full hook table (trigger, location, validation, one row per hook) relocated to `loomwright/docs/HOOKS.md` §"Hook Table" in the v15.21.0 diet — now the authoritative, always-current source. Only three hooks still use prompt-based validation (`SubagentStop[loomwright:code-reviewer]`, `Stop`, `TaskCompleted`); every other hook is `type: command` for zero-latency. **`|| true` convention:** every `type: command` hook string carries `|| true` as belt-and-suspenders — valid ONLY because all of them are always-exit-0 fail-safe emitters/validators. A future blocking gate (non-zero-exit) added as a `type: command` hook must NOT carry `|| true` — that would silently neuter it (see §"Failure-Mode Invariants" below).

---

## Telemetry System (opt-in)

**Disabled by default.** Opt in via `/telemetry enable` (interactive) or `LOOMWRIGHT_TELEMETRY_REPO=owner/repo`; `/telemetry status|disable|test` manage it. Hooks **never** prompt — consent flows only through `/telemetry`.

Two invariants worth knowing here: it **fails CLOSED on privacy** (any whitelist match aborts the post, core exits `2`), and there is **no origin-remote fallback** — the plugin runs in arbitrary user projects whose origin is the wrong place for telemetry.

Full design (wrapper-vs-core architecture, scoring rubric, privacy whitelist, exit-code table 0..5): `loomwright/docs/TELEMETRY.md`.

---

## Persistent Memory & Skills Preloading

Agents opt in via frontmatter: `memory: project` gives an agent a persistent store at `.claude/agent-memory/loomwright:<agent>/`; `skills:` pre-injects those skill bodies at spawn time (no runtime file-read). Both lists are authoritative in `loomwright/agents/*.md` frontmatter — read there, not from a table here.

> Decision aid for *what* to write to those memory directories: `loomwright/skills/memory-tool/SKILL.md` (reference skill — not pre-loaded; consult on demand when tagging conventions or Memory-Tool-vs-file-based questions arise).

## Agent Teams (Recommended for 3 Use Cases, Experimental for the Rest)

Native Claude Code multi-agent coordination — requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Best for research, competing hypotheses, cross-layer changes; not for sequential tasks or same-file edits (use Supervisor with worktrees). Patterns + decision matrix: `loomwright/skills/agent-teams/SKILL.md`. Complementary to Supervisor v4, not a replacement.

---

## Cost Profile

`/supervisor --cheap` — opt-in flag that overrides execution-shaped roles (orchestrator, execute-manager, worker, code-reviewer, Phase 4.5 fix tasks, and — when `--multi-voter-heal` is ON — the multi-voter verification voters/refute spawn) to Sonnet at spawn time. Default behavior (`inherit` for all) unchanged. Profile table, semantics, and Haiku-session caveat: `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles".

---

## Failure-Mode Invariants

**Bimodal failure philosophy (invariant — do not break):** correctness gates fail **CLOSED** under `--non-interactive` / CI / stdin-not-tty (`preflight_overlap_detected`, `non_interactive_without_fallback`, `rubric_gate_closed_non_interactive`); runtime side-effect emitters (telemetry wrapper, `send-webhook.sh`, the session-resume observability probe) fail **SAFE** and ALWAYS `exit 0`. Inverting either — a gate that silently proceeds without an explicit `--skip-*`, or an emitter that exits non-zero on a normal failure path — is a security regression, not a bug fix. Corollary for advisory signals: `contract_conformance_status: skipped` means UNVERIFIED, not clean (it only runs when a brief authored an `## Executable Acceptance` ground-truth surface), and a green `heal_decision: PASS` does NOT mean the PR is reviewer-clean.

**`gh pr merge --squash` has exactly ONE sanctioned executor (invariant — do not break):** the **only** place in the plugin that EXECUTES `gh pr merge --squash` is the `automate-loop` `--auto-merge` gate (`skills/automate-loop/SKILL.md` §10, implemented by `scripts/automate-helpers.sh`'s `gate-eval`). It is **opt-in, default-OFF**, and fires only when ALL FIVE trusted-merge conditions hold; any failed / null / unreadable condition fails **CLOSED** (park + notify). `review-heal` (`/review-pr`) and Supervisor Phase 4.5 **NEVER merge** — they review-and-heal only and leave the PR open for a human (`READY`/`PASS`/`ESCALATED` are all terminal-stop, merge-identical). The positive-form invariant check is `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` — it resolves to exactly five surfaces: `skills/automate-loop/SKILL.md`, `scripts/automate-helpers.sh` (the executor), `scripts/test-automate-helpers.sh`, `commands/agent-help.md` (which describes the sanctioned gate), and `scripts/result_block_parser.py` (a comment at `result_block_parser.py:1356` [pins: `convention CLAUDE.md already uses`] citing this grep's negation-filter convention as precedent for the worker destructive-command tripwire — a prose mention in a parser, it executes nothing). (`commands/automate.md`'s own two mentions are correctly EXCLUDED by the `no|never|not` filter; review-heal / review-pr / RESULT_SCHEMAS likewise keep only their negative-assertion "never merges" mentions.) See `skills/automate-loop/SKILL.md` §11 for the authoritative enumeration. Adding a second executor anywhere else is a regression.

**Two review lenses, not four passes (the review-lane contract — invariant):** the `--until-mergeable` drain is **heal-only by default**, with one **Earned Fallback Review** that runs only when no review-producing lens verifiably posted (`no_review_lens_posted`) and fails closed *toward* running it; and **no per-subtask LLM reviewer is spawned at any threshold** — the deterministic `outputs_verified` gate plus tests/lint is the per-subtask gate, and Phase 4.5's integrated review is the sole LLM gate. Authority: `skills/review-heal/SKILL.md` §"Earned Fallback Review" and `agents/orchestrator.md` §"Review Gate Policy".

**`/automate` single-drain ownership (invariant — do not break):** when the `automate-loop` engine runs an item it sets `.supervisor/config.json {"auto_review": false}` **around** the inner `/autonomous` RUN phase (both of Supervisor's default detached until-mergeable dispatch paths — step 5.5 and the `PostToolUse[Bash]` `gh pr create` hook — fire *during* `/autonomous`, so the toggle must wrap RUN, not DRAIN), then owns **exactly ONE** inline `/review-pr --until-mergeable` drain. The toggle is a byte-for-byte backup to a transient `<run_id>.config-backup.json` restored in a finally-style cleanup (overwrite, or **delete if originally absent**; **malformed pre-existing config ⇒ abort**; RECONCILE restores a crash-stranded backup). This prevents a double until-mergeable drain racing the PR branch. Verifiable via `## Current`'s `suppressed_default_dispatch: true` + `owned_drain_started`/`owned_drain_result` and the absence of any detached `dispatch-pr-review.sh` artifact for the PR.

## Common Pitfalls

Full pitfall list relocated to `loomwright/docs/PITFALLS.md` §"Common Pitfalls" in the v15.21.0 diet — only the ones that bite every session stay here.

### Claimed work is "already merged" / "on main" but isn't (stale-branch trap)?
- Never assert git merge/PR state from memory or in-context summary — verify with `git log origin/$BASE_BRANCH` and `git branch --contains <sha>` before claiming work landed.
- This is the **v13.1.0→v14.0.0 stale-branch incident** (work branched from a stale base and re-implemented something already merged) that motivated the Supervisor's Phase 1.5 PRE-FLIGHT SYNC gate (see `loomwright/agents/supervisor.md` §"Phase 1.5: PRE-FLIGHT SYNC"). The Supervisor row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Agent Invariants" keeps the quick reference — the Agent Roles table above is now purpose-only and no longer carries it.

### Agents don't understand project structure?
Update the project's CLAUDE.md with concrete patterns and references — descriptive anchors, or pinned line numbers per the citation convention above. Agents re-read at session start.

### Beads tasks not appearing?
`bd list` to check; ensure `bd init` ran. Beads is only used by Orchestrator/Product Owner — Supervisor/Launch Pad don't need it.

---

## References

- User-facing: `README.md`, `.claude-plugin/README.md`
- Standards: `AGENT_GUIDELINES.md`
- Manifests: `.claude-plugin/marketplace.json`, `loomwright/.claude-plugin/plugin.json`
- Schemas / contracts / failure modes: `loomwright/docs/{RESULT_SCHEMAS,ARCHITECTURE_CONTRACTS,FAILURE_ESCALATION,ARCHITECTURE,QA_SYSTEM_BLUEPRINT,TELEMETRY,OBSERVABILITY,POINTER_AUDIT,PITFALLS,HOOKS}.md`
- Skills index: `loomwright/skills/SKILLS_INDEX.md`
