# 10 — Harness portability: vendor-neutral core + thin adapters (Claude Code, Cursor, Codex, …)

> **RE-BASELINED 2026-08-22.** The measurements below (dated 2026-07-23, v15.13.0) are **stale and
> preserved for the record only** — see §"Re-baseline (2026-08-22)" at the foot of this file for
> today's counts and the verified harness capability matrix. Two things changed materially: the
> coupling seam **kept widening** (script portability 82%→70%, prompt-layer refs +31%), and
> Cursor/Codex reached capability parity, which invalidates
> this file's predicted degradation list. Two stories were split out to act on that:
> `2026-08-22-092036-vendor-coupling-ratchet.md` (stops the growth — this file had no ratchet) and
> `2026-08-22-092037-skills-layer-portability-probe.md` (de-risks §5 by testing §6's premise first).

## Problem
Loomwright is structurally a Claude Code plugin, but its actual value — the accumulated-judgment Twin — is not Claude-specific. Measured 2026-07-23:
- **`loomwright/scripts/`: 87 scripts, ~25,973 lines, 71 of 87 (82%) contain NO Claude-specific reference** — pure bash + `jq`/`git`/`gh` (+ occasional python3/node/curl). This is already a portable engine.
- **State substrate is plain files:** `.supervisor/` (jobs, state.md, logs, worker-summaries, postmortem, automate run files), `.agent/rules/`, `.agent/orientation/`. Portable by construction; `.agent/` was deliberately placed OUTSIDE `.claude/` for exactly this reason (NORTH_STAR §Bet 6 mechanics).
- **Coupling is thin and countable:** 150 `CLAUDE_PLUGIN_ROOT` refs + 58 Task-spawn refs across the prompt layer (agents 6,793 + commands 6,075 + skills 14,782 lines), plus 199 lines of `hooks/hooks.json`.
- **No `AGENTS.md` at repo root** — the emerging cross-vendor instruction convention other harnesses read.

So the barrier is not the engine; it's that orchestration, instruction delivery, and event hooks are expressed only in Claude Code's dialect.

## Goal
Establish **ports-and-adapters**: a vendor-neutral core (file protocol + CLI entry points + prose protocols) that any agent harness can drive, with thin per-harness adapters. Prove it with ONE working second-harness adapter before porting anything wholesale.

## Strategic constraint (resolves the tension with item 09)
Item 09 adopts Claude-native primitives; this item reduces vendor dependence. They are compatible under exactly one rule, which both items must honor: **native adoptions land in the Claude ADAPTER, never in the core.** The core may not require any harness-specific primitive; an adapter may exploit every primitive its harness offers. A capability the core needs but a harness lacks degrades (documented) rather than blocking.

## Scope
1. **Portability inventory (evidence, not estimate):** classify every asset as CORE (vendor-neutral), ADAPTER (harness-specific), or COUPLED (core logic with harness deps to extract). Publish the table with line counts. Expected shape from the measurement above: scripts + state + docs/protocols = core; hooks.json + agent frontmatter + slash-command wiring = adapter; the 150+58 refs = coupled.
2. **Define the core contract** — the thing an adapter implements, written down once:
   - **File protocol:** the `.supervisor/` + `.agent/` layouts and their lifecycle (already de-facto; make it explicit and versioned).
   - **CLI surface:** the scripts that constitute the engine, with documented argv/stdin/stdout/exit-code contracts (they already fail-safe exit 0 by convention — codify it).
   - **Capability ports the harness must supply:** run-a-subagent, run-in-background, isolate-a-workspace, react-to-an-event, deliver-instructions. Each with a documented degraded fallback when absent (e.g. no event hooks ⇒ explicit invocation at the same seam; no worktree isolation ⇒ sequential execution).
   - Replace `${CLAUDE_PLUGIN_ROOT}` with a resolved-once env var (e.g. `LOOMWRIGHT_ROOT`, defaulting from `CLAUDE_PLUGIN_ROOT` when present) so the core stops naming a vendor.
3. **Harness capability research (verify, never assert from recollection):** for Cursor and Codex (and any other target), determine from CURRENT official docs what each provides for: instruction files (`AGENTS.md` / `.cursor/rules` / equivalents), subagent or background-task execution, hook/event surfaces, workspace isolation, and command/skill invocation. Cite sources with dates. Where a capability is absent or unverified, record it as such — an adapter designed against a guessed feature is worse than no adapter.
4. **`AGENTS.md` as the portable instruction home (cheap first win):** author a root `AGENTS.md` carrying the vendor-neutral subset of project instruction, with CLAUDE.md becoming the Claude-specific delta that points at it. **Coordinate with item 04** — that item's DELETE-over-gate rule applies here: this must not create a second copy of the same claims. One authoritative home; the other file references it.
5. **Ship ONE adapter as a falsifiable spike:** pick the single highest-signal target (recommend the one whose research shows the most capability parity) and make **one complete requirement flow end-to-end** under it — brief → implement → verify against ground truth → PR. Report honestly what degraded (likely: parallel worktree workers, event-driven hooks, subagent-isolated review). The spike's verdict decides whether full portability is worth it — do not port 27k lines of prompts on faith.
6. **Prompt-layer portability follow-up (proposal only here):** how the ~27k lines of agent/command/skill prose become harness-agnostic (shared protocol bodies already live in `skills/` — that's the seam) with per-harness thin wrappers. Stub a follow-up requirement; do not execute in this item.

## Non-goals
No wholesale rewrite. No dropping Claude Code support or degrading it to a lowest-common-denominator (it is the primary and most capable target). No new advisory stores (freeze-compatible). No adapter built against unverified vendor capabilities.

## Acceptance criteria
- Inventory table published with real line counts and CORE/ADAPTER/COUPLED classification for every asset.
- Core contract documented (file protocol + CLI contracts + the five capability ports with degraded fallbacks); `LOOMWRIGHT_ROOT` indirection in place with Claude-path compatibility verified.
- Harness research cites live official docs with fetch dates; unverified capabilities explicitly labeled UNVERIFIED (read-before-write rule).
- ONE second-harness adapter runs one real requirement end-to-end; the run's degradations are enumerated honestly (a spike that only reports success is incomplete evidence).
- No regression on Claude Code: existing gates green, `${CLAUDE_PLUGIN_ROOT}` resolution still works for marketplace installs.

## Outcomes Rubric
- Evidence-based CORE/ADAPTER/COUPLED inventory
- Written core contract incl. five capability ports + degraded fallbacks
- Vendor-neutral root path variable replacing CLAUDE_PLUGIN_ROOT in core scripts
- AGENTS.md authored without duplicating CLAUDE.md claims
- One second-harness end-to-end run with an honest degradation report


---

## Re-baseline (2026-08-22)

### Measured counts — supersedes the Problem section's 2026-07-23 figures

| Metric (basis stated — the July figures were prompt-layer and `.sh` only) | 2026-07-23 (v15.13.0) | 2026-08-22 | Δ |
|---|---|---|---|
| `CLAUDE_PLUGIN_ROOT` refs, **prompt layer** (agents+commands+skills) | 150 | **197** | **+31%** |
| `CLAUDE_PLUGIN_ROOT` refs, **repo-wide** (＋scripts/hooks/docs) | *not measured* | **309** | new baseline |
| `scripts/*.sh` total | 87 | 113 | +30% |
| `scripts/*.sh` with zero Claude refs | 71 (**82%**) | 79 (**70%**) | **−12pp** |
| Task-spawn refs (prompt layer) | 58 | 51 | −12% |
| `hooks.json` lines | 199 | 202 | +3 |
| agents / commands / skills lines | 6,793 / 6,075 / 14,782 | 7,039 / 6,547 / 14,804 | +740 |
| Root `AGENTS.md` | absent | **still absent** | — |
| `LOOMWRIGHT_ROOT` occurrences | 0 | **0** | never built |

Refs by area (2026-08-22, repo-wide 309): commands 86 · skills 65 · scripts 64 · agents 46 ·
docs 25 · hooks 23.

**Basis note:** the July figures counted the prompt layer and `.sh` scripts only. The repo-wide 309
is a NEW baseline with no July counterpart — do not read it as a delta. The regression measured on
identical basis both dates is **script portability 82% → 70%**.

**Interpretation.** The seam is not merely un-shrunk, it is **growing faster than the repo**. The
"thin and countable" framing still holds in kind, but the direction of travel does not. Nothing in
CI gates new coupling, so this file's §1 inventory would be stale the week it was published — an
inventory is a snapshot where a **ratchet** is required. That gap is now owned by
`2026-08-22-092036-vendor-coupling-ratchet.md`, which also supplies the enforcement this file's
"Strategic constraint" (natives in the adapter, never the core) currently asserts as unbacked prose.

### Harness capability matrix — §3 research, partially discharged

Verified against official vendor documentation fetched **2026-08-22**. This **supersedes this
file's predicted degradation list** ("likely: parallel worktree workers, event-driven hooks,
subagent-isolated review") — those capabilities now exist in both targets.

| Capability port | Claude Code | Cursor | Codex CLI |
|---|---|---|---|
| run-subagent | Task | Subagents; nested trees since 2.5 (child subagents cannot nest further) | Subagents, enabled by default |
| run-background | background tasks | via subagents | via subagents |
| isolate-workspace | git worktrees | git worktrees (harness-neutral) | git worktrees (harness-neutral) |
| react-to-event | `hooks/hooks.json` | `.cursor/hooks.json` (project) / `~/.cursor/hooks.json` (user); ~18 events incl. `sessionStart`, `preToolUse`, `postToolUse`, `subagentStart`, `subagentStop`, `stop`, `preCompact` | 10 PascalCase events (`PreToolUse`, `PostToolUse`, `SessionStart`, `SubagentStart`, `SubagentStop`, `UserPromptSubmit`, `Stop`, `PermissionRequest`, `PreCompact`, `PostCompact`); requires `codex_hooks = true` |
| deliver-instructions | CLAUDE.md | `.cursor/rules/*.mdc` + AGENTS.md | AGENTS.md |
| skills | `skills/*/SKILL.md` | `SKILL.md`; discovers `.agents/skills/`, `.cursor/skills/`, **and `.claude/skills/`, `.codex/skills/`** (+ `~/` variants) | `SKILL.md` |

**Two findings that change this file's plan:**

1. **Cursor's hook contract is near-isomorphic to ours.** Hooks are spawned processes speaking JSON
   over stdio in both directions; **exit 0 = proceed, exit 2 = block**, other codes = failure. Our
   bimodal convention (fail-CLOSED correctness gates, fail-SAFE `exit 0` emitters) maps across
   directly. §2's "react-to-an-event port with a documented degraded fallback" needs a
   **translation layer**, not a degradation story.
2. **Cursor natively reads `.claude/skills/`.** That is 14,804 lines — the largest prose block and
   the exact thing §6 deferred as too expensive to port. It may be portable at near-zero cost.
   Testing this is now owned by `2026-08-22-092037-skills-layer-portability-probe.md` and should
   run **before** §5 commits to an adapter scope.

### Standing limits on the above

- Capability **existence** is verified from vendor docs dated 2026-08-22. **Behavioral fidelity is
  UNVERIFIED** — specifically whether Cursor's `subagentStop` payload carries the fields our
  `SubagentStop` validators read, and whether its skill loader honors our frontmatter. Settling
  this is §5's and the skills probe's job. Do not build against the matrix as if it were observed.
- Vendor capabilities move fast: this matrix gained three ports in one month. **Re-verify at
  adapter-build time**; do not treat this table as durable.

### Consequent change to §5's recommendation

§5 says pick "the one whose research shows the most capability parity". On the 2026-08-22 evidence
that is **Cursor** — full port coverage plus native `.claude/skills/` discovery plus
near-isomorphic hook semantics. Codex is the second adapter, not the first. This is now an
evidence-backed pick rather than an open question.

## Status: pending — PARTIALLY LANDED outside this queue (note added 2026-09-21)
- Scope item 1 (CORE/ADAPTER inventory as evidence) shipped as `scripts/check-vendor-coupling.sh` + `loomwright/docs/vendor-coupling-manifest.json` (commit 7fa14d8; today 629 refs / 0 breaches, ratchet one-directional). The "ONE adapter spike" shipped as `loomwright/scripts/adapters/providers/{lens-run,provider-claude,provider-codex,provider-cursor,provider-gemini}.sh` (PR #239) and `adapters/orca/` (PR #237).
- **Remaining:** scope item 2 (written core contract: file protocol, CLI surface, capability ports + degraded fallbacks; `LOOMWRIGHT_ROOT` resolved-once env var) and item 3 (Cursor/Codex capability research from current docs). Re-scope the AC to those before dispatching.
