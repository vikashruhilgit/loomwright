# Selvedge extraction — backlog, dependency order, and measured baseline

**Origin:** 2026-08-18 owner session. Goal in the owner's words: *"Extract the QA flow — everything
related to QA — into a separate plugin."* This is an index/policy doc — **not an implementable item.**

**Name:** `selvedge` — the self-finished woven edge that stops fabric unravelling. Directory
`selvedge/`, `plugin.json` name `selvedge`, agent namespace prefix `selvedge:` (so
`selvedge:qa-strategist`, `selvedge:qa-executor`). On-metaphor with `loomwright` / `atelier`.

## Owner decisions — settled, do not re-litigate

1. **Name is `selvedge`.** Not up for discussion in any slice.
2. **Companion model, NOT standalone.** `selvedge` installs alongside `loomwright@atelier` and may
   depend on Loomwright-owned shared assets rather than vendoring copies. Explicitly do **NOT**
   duplicate `quality-checklist`, `write-agent-memory.sh`, the `QA_RESULT` schema section, or the
   telemetry scoring rubric into `selvedge`. Duplication-that-drifts is the thing being avoided.
3. **Boundary: core QA only.** Exactly 5 skills move. `unit-testing` and `quality-checklist` **stay**
   in loomwright.

## The one-paragraph feasibility answer

**The QA subsystem is a leaf for forward execution.** Nothing in Loomwright's orchestration path
spawns the QA agents — the only `subagent_type: "loomwright:qa-strategist"` spawns are inside
`agents/qa-executor.md` itself (its own internal debate loop, two call sites) plus
`commands/qa-executor.md`. Neither Supervisor, Orchestrator, Execute Manager, Worker, Launch Pad, nor
the autonomous/automate loops spawn QA. That is why a companion plugin works at all. **But the leaf
claim is about the forward path only** — see Correction #1 below.

## Corrections to the intake ground truth (measured 2026-08-18 — these change the plan)

These were found while verifying the handoff, not assumed. Each is load-bearing.

### Correction #1 — `/dreaming --agent qa-executor` is a LIVE inbound spawn, not a doc mention

`loomwright/commands/dreaming.md` **spawns QA Executor** in reflection mode. It is not prose:

| Evidence | Line |
|---|---|
| `/dreaming --agent qa-executor  # Reflect with QA Executor only` | `dreaming.md:23` |
| `--agent` accepts `all`, `code-reviewer`, `red-team`, or `qa-executor` | `dreaming.md:35` |
| "Spawn target agent(s) in reflection mode … each reflection Task spawn sets `model: "sonnet"`" | `dreaming.md:161` |
| "The agents `/dreaming` spawns (Code Reviewer, Red Team Reviewer, QA Executor)…" | `dreaming.md:191`, `:494` |
| Per-agent role hint for QA Executor in the reflection template | `dreaming.md:266` |
| `/qa-executor` listed as the forward counterpart | `dreaming.md:593`, `:616` |

So the QA subsystem is a leaf **forward**, and a spawn **target backward**. `/dreaming` stays in
loomwright; the agent leaves. That makes cross-plugin `Task(subagent_type:)` resolution a hard
prerequisite, not a nicety — handled in **01** (unknown C) and decided in **03**.

### Correction #2 — the hook delta is 24 → **22**, not 24 → 23

The `SubagentStop` matcher `loomwright:qa-executor` in `loomwright/hooks/hooks.json` carries **two**
hook entries, not one:

1. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-qa-result.py" || true`
2. the telemetry + token-ledger fan-out (`send-telemetry.sh` + `emit-token-ledger.sh`)

`check-doc-currency.sh:56` counts **leaf hook entries** (`jq '[.hooks[][].hooks[]] | length'`), so
removing the whole matcher takes loomwright **24 → 22**. Verified by simulation against the real
`hooks.json`. `23` would only be correct if a fan-out replacement is engineered inside selvedge —
which Correction #3 shows it cannot be, cheaply.

### Correction #3 — `${CLAUDE_PLUGIN_ROOT}` is per-plugin, so selvedge's hooks cannot call loomwright's scripts

`${CLAUDE_PLUGIN_ROOT}` resolves to *the invoking plugin's* install dir. A hook declared in
`selvedge/hooks/hooks.json` therefore resolves to `selvedge/`, and **cannot** reach
`loomwright/scripts/send-telemetry.sh` or `emit-token-ledger.sh`. This is stated in CLAUDE.md
("`${CLAUDE_PLUGIN_ROOT}` … resolves to the plugin install dir") but has never been exercised
across two plugins here, and `stackpack` ships no hooks so there is no precedent. It is unknown **B**
in slice 01 and it directly sets the QA telemetry decision in **03**.

### Correction #4 — three more coupled surfaces the intake did not list

- `loomwright/skills/qa-orchestration/SKILL.md` — 18 QA refs; it is one of the 5 movers and is
  referenced from `agents/qa-executor.md:170` (`.qa-session/plan.json` schema). Confirmed it moves.
- `.claude/agent-memory/loomwright-loomwright-qa-executor/` — a **live, populated** memory store
  (6 files, 5 indexed entries). Renaming the agent to `selvedge:qa-executor` changes the harness's
  sanitized store path and orphans it. `loomwright/scripts/test-committed-twin-scrub.sh:352`
  hard-codes the old path. Handled in **06**.
- `loomwright/scripts/test-agent-memory-permission.sh` pins a **seven-surface** list that includes
  `$PLUGIN_ROOT/agents/qa-executor.md` and `qa-strategist.md`. It breaks the moment they move —
  which is why it is inside the atomic slice **04**, not a follow-up.
- `unit-testing/SKILL.md:24,198` and `ci-cd/SKILL.md:25,241` both cross-reference `playwright-e2e`
  in "see also" prose. Those two skills stay; their pointers must be rewritten (**04**).

## Measured baseline (verified 2026-08-18 — verify again before amending)

| Fact | Evidence |
|---|---|
| Marketplace lists 3 plugins: `loomwright`, `stackpack`, `mysql-mcp` | `.claude-plugin/marketplace.json` |
| loomwright is at v15.36.0 | `loomwright/.claude-plugin/plugin.json` |
| Counts today: agents **14**, commands **21**, skills **41**, hooks **24** | `find loomwright/{agents,commands}` + `find loomwright/skills -mindepth 1 -maxdepth 1 -type d` + `jq '[.hooks[][].hooks[]]\|length'` |
| Counts after the move: **12 / 19 / 36 / 22** | simulated; see Correction #2 for the hook figure |
| `check-doc-currency.sh` scans exactly **9** surfaces | `FILES=(…)` array, `check-doc-currency.sh` §"Doc/config surfaces" |
| `check-skills-index-sync.sh` is **already multi-plugin** (v15.6.0) and iterates every marketplace plugin with a `skills/` tree; a `skills/` dir **without** `SKILLS_INDEX.md` fails loudly | script header, §MULTI-PLUGIN |
| `validate-version.sh` is **already per-plugin** (loops `.plugins[]`, resolves `.source`) | script body + `--self-test` |
| `check-command-sync.sh` targets **only** `loomwright/commands/code-reviewer.md` — unaffected by this queue | `targets=(…)` |
| `check-token-budget.sh` reads `AGENTS_DIR="${TOKEN_BUDGET_AGENTS_DIR:-loomwright/agents}"`; fails CLOSED on an undeclared budget **and** on a broken frontmatter `skills:` reference | script body |
| `check-shared-prefix.sh` reads `SHARED_PREFIX_CANONICAL` / `SHARED_PREFIX_AGENTS_DIR` (defaults under `loomwright/`); an **empty** agents dir fails CLOSED | script header + body |
| `check-contract-parity.sh` hard-codes `PLUGIN="$ROOT/loomwright"`; its `MANIFEST` pins `qa-executor\|qa-executor.md\|QA_RESULT\|schema_version,tests_generated,tests_passed,summary,coverage_estimate` and its `ENUMS` pins `agents/qa-executor.md\|status\|…` | script body |
| CI's hard-gate self-test loop globs **`loomwright/scripts/test-*.sh`** only, and fails loudly on an empty match | `.github/workflows/ci.yml` |
| Both QA agents declare `memory: project`; `qa-strategist` preloads `qa-strategy, qa-gates, quality-checklist`; `qa-executor` preloads `qa-strategy, qa-test-patterns, qa-gates, playwright-e2e, quality-checklist` | agent frontmatter |
| `quality-checklist` is the **only** cross-plugin preload the companion model requires | same |
| Telemetry Rubric C keys on `schema = "QA_RESULT"`, task-type string `"qa-executor"`, pass rule `tests_passed == tests_generated AND gates >= 5`; golden fixtures `telemetry-fixtures/qa-failed.json` + `golden/qa-failed__allow_with_repo.golden.txt` | `send-telemetry-core.sh:230,481-520,561,915` |
| `qa-executor:` in `run-ground-truth.sh` is a **name reservation** — RECOGNIZED but DEFERRED to M2b slice 1b; it **spawns nothing** and records `unverified` (`qa_executor_dispatch_deferred_m2b_1b`) | `run-ground-truth.sh:54,333-337`; mirrored in `agents/plan-reviewer.md:266-267`, `skills/supervisor-readiness/SKILL.md:193`, `skills/self-heal-advisory/SKILL.md:286-287` |
| `stackpack` is a **partial** precedent only — skills-only, 18 skills, no agents/commands/hooks/scripts | `stackpack/` tree |

## Build order (LOAD-BEARING)

```
01  →  02  →  03  →  04  →  05  →  06  →  07
        (03 may run in parallel with 02 once 01 lands)
```

| # | Slice | Kind | Counts touched |
|---|---|---|---|
| 01 | Cross-plugin resolution spike | **gate** — spike + decision record | none |
| 02 | Scaffold `selvedge` + make the loomwright-pinned gates plugin-aware | infrastructure | none |
| 03 | Decouple the loomwright-side QA couplings (dreaming, telemetry, ground-truth, regex lists) | behavioural decisions | none |
| 04 | **The atomic relocation** — agents + commands + 5 skills + hook + validator + parity + budgets + counts + the tests that would otherwise break | the big one | 14→12, 21→19, 41→36, 24→22 |
| 05 | Doc & contract boundary (blueprint move, `QA_RESULT` ownership, deep prose sweep) | docs | none |
| 06 | Selvedge's own CI + agent-memory store migration | infrastructure | none |
| 07 | Migration announcement, READMEs, marketplace descriptions, version bumps | release | none |

### Why 01 gates everything

Three cross-plugin resolution behaviours are **unverified and load-bearing**, and there is **zero
empirical precedent in this repo** — no loomwright agent preloads a stackpack skill, and stackpack
ships no hooks or agents. CLAUDE.md's §"Hook gotcha" records that Claude Code **silently ignores**
`hooks`, `mcpServers`, and `permissionMode` in plugin agent frontmatter. Silent-ignore is therefore
an *established* failure mode for this exact frontmatter block, which makes silent-ignore of a
cross-plugin `skills:` entry a live possibility rather than paranoia. A silently-dropped preload
does not fail any gate — it degrades the agent invisibly. **Do not assume it works.**

### Why 04 cannot be split further (each split is forbidden by a named gate)

This queue deliberately does not contain a "move everything" slice — 04 is the *irreducible* atom,
and every attempted smaller cut is blocked by a specific CI gate:

- **Move the skills before the agents?** `check-token-budget.sh` fails CLOSED on "a broken
  frontmatter skill reference" — the QA agents would still declare `skills: qa-strategy, …`.
- **Move the agents before the skills?** Same gate, mirrored: the moved agents' preloads would point
  at skills still living in loomwright, and `${CLAUDE_PLUGIN_ROOT}`/namespace resolution differ.
- **Move the agents but leave the hook?** `check-contract-parity.sh`'s `MANIFEST` resolves
  `agent_path="$AGENTS/qa-executor.md"` and errors `field-presence` when it is missing — and the
  orphaned matcher would silently validate nothing.
- **Move the agents but leave the counts?** `check-doc-currency.sh` fails on the 9 surfaces in the
  same commit.
- **Move the validator but leave its test?** `test-result-validators.sh` and
  `test-check-contract-parity.sh` invoke it at `loomwright/scripts/`; the CI hard-gate loop runs the
  whole `loomwright/scripts/test-*.sh` suite and fails on the first non-zero exit.

The work that *is* separable was deliberately pulled **out** of 04 and into 02 (gate engineering),
03 (behavioural decisions), 05 (narrative docs), and 06 (memory store + selvedge CI) precisely so
04 reduces to `git mv` + mechanical count/pin updates.

## Non-negotiable invariants carried by every slice

- **Every slice leaves the repo GREEN.** `validate-version.sh`, `check-command-sync.sh`,
  `check-doc-currency.sh`, `check-skills-index-sync.sh`, `check-contract-parity.sh`,
  `check-token-budget.sh`, `check-shared-prefix.sh`, and the full `loomwright/scripts/test-*.sh`
  hard-gate loop all pass at every commit.
- **No duplication of loomwright-owned shared assets into selvedge** (owner decision 2). Where a
  cross-plugin dependency cannot resolve, the answer is to **drop or re-express** the dependency —
  never to vendor a second copy that drifts.
- **A green gate is necessary, not sufficient.** Per CLAUDE.md, on any count/version change grep the
  OLD value repo-wide with flexible separators; `check-doc-currency.sh` verifies claims that ARE
  made, and cannot tell you a claim should not have been made.
- **Prompts are programs.** The agent/command/skill `.md` files being moved are executable logic —
  they get a state-trace, not a "docs-only" consistency read.
- **Descriptive anchors over bare line numbers** in any committed prose this queue adds
  (`scripts/test-citation-drift.sh` fails a new bare, unpinned `file:N`).
- **Plugin `description` is a summary, not a changelog** — update the version string and counts
  **in place** in both `plugin.json` and `marketplace.json`; never append another version clause.

## /automate handling

Every slice is a normal code-change item sized for one `/autonomous --single-iteration` run landing
as one reviewable PR. **Slice 01 is the exception:** it requires an operator to install both plugins
locally and spawn an agent. It cannot be satisfied by static reading and must not be marked done on
the strength of a code trace.

## Status: pending
