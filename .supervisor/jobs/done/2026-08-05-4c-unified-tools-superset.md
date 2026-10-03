# Supervisor-Ready Brief: 4c — Unified `tools:` superset across the 14 agents

- **Source requirement:** `.supervisor/requirements/final-state/12-4c-unified-tools-lists.md`
- **Provenance:** item 07's scope item 3, split out because 07 itself mandated it
  (`07-route-freshness-tools.md` — "4c gets its own PR (plugin-wide frontmatter change)").
- **Execution order:** step 7 (D7/D8) in `docs/SPIKES/FINAL_STATE_GOAL.md`. No deviation.
- **All paths in this brief are REPO-ROOT-RELATIVE.** The plugin lives under `loomwright/`.

---

## Environment

- **Mode:** Single-Agent Path (no worktree)
- **Recommended workers:** 1
- **Base branch:** `main`
- **Branch:** `feature/unified-tools-superset`
- `legacy_brief: false` — this brief carries a `provides:`/`requires:`/`lanes:` contract block
  (see §Subtask Structure).

---

## PINNED SEMANTICS — read this before touching a frontmatter line

This brief ships a **consistency change, not a cache change.** The source requirement's problem
statement claims a unified `tools:` block plus the shared prefix "clears the 512-token floor" for
cross-agent prompt-cache sharing. **That premise is FALSE and was falsified before this brief was
written.** It is pinned here so the worker does not re-derive the optimistic reading from the
requirement body.

**Doc evidence (two already-committed surfaces in this repo):**

- `loomwright/docs/shared-agent-prefix.md` §"HONEST CACHE EXPECTATION" — "each agent type carries a
  different `tools:`/`disallowedTools:` frontmatter set, so two different agent types diverge at
  position 0".
- `loomwright/docs/POINTER_AUDIT.md` §"HONEST CACHE EXPECTATION" — "Cross-agent prompt-cache reuse
  is structurally **ZERO** … the harness renders each agent's `tools:` / `disallowedTools:`
  frontmatter BEFORE the system prompt … **Do NOT claim cross-agent cache reuse without ledger
  evidence (expected ≈ zero).**"

**Empirical evidence (observed, with the discriminating control pair).** Declared frontmatter is NOT
the effective toolset. Observed effective toolsets for this session's registered agents:

| Agent | `memory: project` | Declared has Write/Edit | **Effective** has Write/Edit |
|---|---|---|---|
| product-owner | yes | no | **yes** |
| red-team-reviewer | yes | no | **yes** |
| qa-strategist | yes | no | **yes** |
| launch-pad | yes | Write only | **Write + Edit** |
| code-reviewer | yes | no | **no** — carries `disallowedTools: Write, Edit, NotebookEdit` |
| **orchestrator** | **no** | no | **no** |
| **execute-manager** | **no** | no | **no** |
| **review-pr** | **no** | no | **no** |
| **plan-reviewer** | **no** | no | **no** |

Two conclusions, each with its own control:

1. **The grant is tied to `memory: project`, not to plugin agents generally.** The discriminating
   pair is `product-owner` (memory → gains Write/Edit) vs `orchestrator` (no memory, otherwise a
   comparable read-only role → does NOT gain them). Four non-memory agents were observed and none
   gained anything beyond its declared list. This **rules out** the rival reading "the harness grants
   Write/Edit to every plugin agent", under which rows 3, 5 and 11 would have been losing a real
   capability.
2. **`disallowedTools` is SUBTRACTIVE on the effective rendered toolset.** `code-reviewer` has
   `memory: project` like the four above, yet does not receive Write/Edit — the only difference is
   its denylist. Therefore per-agent denylists produce per-agent effective toolsets, reproducing the
   byte-0 divergence the unification was supposed to remove.

(The installed `15.22.0` plugin cache matches repo disk, so the augmentation is the harness's
behaviour, not a stale install.)

> **OPEN QUESTION — do not paper over it, and do not let it expand scope.** `code-reviewer` has
> `memory: project` AND blocks `Write`/`Edit`. So either agent-memory writes do not route through
> the `Write`/`Edit` tools, or `code-reviewer`'s memory has been non-functional and unnoticed. This
> brief does **not** resolve that and does **not** change `code-reviewer`. It matters only because it
> falsifies a *tempting rationale*: the reason rows 4/7/9/10 keep Write/Edit is **"preserve the
> OBSERVED effective set"** — NOT "otherwise memory writes break", which the `code-reviewer` case
> disproves. Record the open question in the PR body; do not act on it here.

**Consequence — the two rules that govern this whole change:**

1. **RULE A (authorized).** Unify `tools:` to ONE canonical-order superset across all 14 agents and
   preserve every agent's **observed effective** capability set via per-agent `disallowedTools`.
2. **RULE B (FORBIDDEN by name).** Do NOT unify `disallowedTools` to make the rendered prefix
   byte-identical. It is the only shape that would actually clear the floor, and it would hand
   `plan-reviewer` / `code-reviewer` / `rubric-grader` / `context-keeper` `Write`/`Edit`/`Task`.
   That is a real capability expansion, forbidden by the source requirement's own Non-goals, and it
   would delete the only read-only enforcement that survives plugin distribution
   (`permissionMode` is silently ignored for plugin agents — `AGENT_GUIDELINES.md`
   §"Agent Frontmatter Conventions").

**Owner decision (2026-08-05, at the Launch Pad Phase 2.5 feasibility gate):** ship consistency-only
with honest framing. AC3 is satisfied through its own "say which it turned out to be" branch —
report the floor **NOT cleared**, structurally, with evidence. Do not report a cache win.

**PRESERVE THE EFFECTIVE SET, NOT THE DECLARED SET.** This is the single most likely thing to get
wrong. Four agents (`launch-pad`, `product-owner`, `qa-strategist`, `red-team-reviewer`) must
deliberately **omit** `Write`/`Edit` from their new denylists even though their *declared* `tools:`
never listed them — blocking them would REMOVE an observed capability. A naive
`superset − declared_tools` derivation gets all four wrong.

---

## Objective

Replace 13 distinct `tools:` lists across the 14 agent files with ONE byte-identical superset line
in ONE canonical order, adding per-agent `disallowedTools` so that **every agent's observed
effective capability set is bit-for-bit what it is today.** Then measure and report honestly.

## Non-goals

- No change to any agent's effective capabilities or contract (see RULE B).
- No new CI gate.
- No change to `check-shared-prefix.sh` (verified frontmatter-agnostic — its `extract_block()` and
  `count_exact()` are awk passes anchored on the `SHARED-AGENT-PREFIX v1` marker lines and never read
  the frontmatter fence).
- Not resolving the `code-reviewer` memory/denylist open question above.
- Not chasing the decorative `measured`/`note` fields in `prompt-token-budgets.json` (the gate reads
  ONLY `.agents[<stem>].budget`; those fields are frozen authoring metadata by that file's own
  `_comment`).

---

## The canonical superset and order

Union of all 14 declared lists **plus** the harness-granted `Write`/`Edit`, in one canonical order
(most-common first, then spawn/inspection, then network — chosen once and documented so future
agents append rather than re-order):

```
tools: Read, Write, Edit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch
```

`NotebookEdit` is deliberately **absent** from the superset — no agent declares it today, so it stays
excluded by the allowlist. Existing `NotebookEdit` denylist entries are kept as harmless
defense-in-depth rather than removed.

## Per-agent `disallowedTools` derivation (superset − OBSERVED EFFECTIVE toolset)

Each row is `superset − effective`, NOT `superset − declared`. Existing denylist entries are
preserved and unioned in.

**Derive every row from disk yourself and cross-check it against this table.** Disk is authoritative;
this table is a cross-check, not a substitute for reading the files. (It was independently
re-derived from disk by Plan Review and all 14 rows confirmed, so a mismatch is genuinely
surprising.) **On any mismatch, STOP and escalate with BOTH derivations** — do not silently edit
either one.

| # | Agent file | New `disallowedTools` | Note |
|---|---|---|---|
| 1 | `code-reviewer.md` | Write, Edit, NotebookEdit, Task, TaskOutput, WebSearch, WebFetch | keeps existing 3; read-only preserved |
| 2 | `context-keeper.md` | Task, TaskOutput, Bash, Glob, Grep, LSP, WebSearch, WebFetch | keeps existing 4 |
| 3 | `execute-manager.md` | Write, Edit, LSP, WebSearch, WebFetch | first denylist; non-memory agent, no Write/Edit observed |
| 4 | `launch-pad.md` | TaskOutput, WebSearch, WebFetch | **Write/Edit deliberately NOT blocked** (observed) |
| 5 | `orchestrator.md` | Write, Edit, Task, TaskOutput, LSP, WebSearch, WebFetch | read-only planner preserved; control case for the confound |
| 6 | `plan-reviewer.md` | Write, Edit, NotebookEdit, Task, Bash, TaskOutput, LSP, WebSearch, WebFetch | keeps existing 5 |
| 7 | `product-owner.md` | Task, TaskOutput, LSP | **Write/Edit deliberately NOT blocked** (observed) |
| 8 | `qa-executor.md` | TaskOutput, WebSearch, WebFetch | already declares Write/Edit |
| 9 | `qa-strategist.md` | Task, TaskOutput, LSP, WebSearch, WebFetch | keeps existing `Task`; **Write/Edit NOT blocked** |
| 10 | `red-team-reviewer.md` | Task, TaskOutput, LSP | **Write/Edit deliberately NOT blocked** (observed) |
| 11 | `review-pr.md` | Write, Edit, TaskOutput, LSP, WebSearch, WebFetch | non-memory; delegates edits to `Task(general-purpose)` fix workers |
| 12 | `rubric-grader.md` | Write, Edit, NotebookEdit, Task, TaskOutput, LSP, WebSearch, WebFetch | keeps existing 4 |
| 13 | `supervisor.md` | LSP, WebSearch, WebFetch | already declares Write/Edit |
| 14 | `worker.md` | Task, TaskOutput, WebSearch, WebFetch | keeps existing `Task` |

---

## Acceptance criteria

- **AC1** — All 14 files in `loomwright/agents/` carry the identical superset `tools:` line above,
  byte-identically and in the one canonical order. Prove with a grep that returns 14 identical lines.
- **AC2** — **Per-agent** effective-capability verification, named per agent, NOT asserted in
  aggregate. For each of the 14 rows: state the effective toolset before, the new
  `tools:` + `disallowedTools` pair, and that the resulting effective set is identical. The four
  `Write`/`Edit`-preserving rows (4, 7, 9, 10) must each be called out explicitly by name.
- **AC3** — Cache-prefix claim **re-measured and reported honestly**: state that the 512-token floor
  is **NOT cleared** and that cross-agent reuse remains structurally zero, citing
  `shared-agent-prefix.md` §"HONEST CACHE EXPECTATION" and `POINTER_AUDIT.md` §"HONEST CACHE
  EXPECTATION" **by section anchor, never by line number** (see AC9). Do not claim a cache win. If
  token-ledger evidence is obtainable, cite it; if not, say so plainly rather than implying
  measurement.
- **AC4** — `scripts/check-shared-prefix.sh` still passes.
- **AC5** — Token budgets: **re-derive live headroom by running `bash scripts/check-token-budget.sh`
  and reading its printed per-agent figures — do NOT compute headroom from the JSON's `measured`
  field, which several rows' own notes declare stale.** Raise a budget only on an actual breach, and
  if raised, update the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row in the same
  edit (the gate machine-asserts table cell == JSON). **Expected outcome: NO breach** — the added
  bytes are ~130 max per agent (~33 proxy tokens) against a tightest live headroom of ~212
  (`rubric-grader`; `worker` ~537 is next). State the tightest row and its margin; do not raise
  budgets unnecessarily.
- **AC6** — Full gate set enumerated **from disk** (`ls scripts/check-*.sh scripts/validate-*.sh`)
  and all green. As of this brief that is **7**: `check-command-sync`, `check-contract-parity`,
  `check-doc-currency`, `check-shared-prefix`, `check-skills-index-sync`, `check-token-budget`,
  `validate-version`. Plus the whole-suite glob in `.github/workflows/ci.yml` over
  `loomwright/scripts/test-*.sh` (must be Ubuntu-clean) and the separate sdk-spike suites.
- **AC7** — `loomwright/docs/ARCHITECTURE_CONTRACTS.md` updated in **two** places, not one:
  - §"disallowedTools (Defense-in-Depth)" — currently lists only 5 agents; after this change **all
    14** carry a denylist.
  - §"Agent Capability Matrix" — its `Write` column reads `no` for Product Owner, Orchestrator, Red
    Team Reviewer and QA Strategist. Three of those have observed effective Write and this change
    deliberately keeps it, so the matrix would visibly contradict the frontmatter a few lines away.
    Reconcile the `Write`/spawn columns against the observed effective sets.
- **AC8** — The falsification is recorded durably, not just in the PR body:
  - Update `12-4c-unified-tools-lists.md` so it no longer asserts the floor-clearing premise.
  - Add the `disallowedTools`-is-subtractive finding to `POINTER_AUDIT.md` §"HONEST CACHE
    EXPECTATION" as empirical corroboration of what it already predicted.
  - **Update `loomwright/docs/shared-agent-prefix.md` §"HONEST CACHE EXPECTATION".** Its sentence
    "each agent type carries a different `tools:`/`disallowedTools:` frontmatter set" becomes HALF
    FALSE at merge — `tools:` is now identical across all 14; the divergence comes from
    `disallowedTools` **alone**. AC3 cites this paragraph as evidence, so leaving it stale would have
    the change quietly invalidate its own cited source.
- **AC9** — No absolute line-number references introduced in any prose written by this change; use
  descriptive section anchors (standing lesson — this exact defect recurred in items 13 and 11).
- **AC10** — **`AGENT_GUIDELINES.md` §"Agent Frontmatter Conventions" updated.** It documents
  `tools:` as the *"(allowlist)"* and states *"Tool restrictions enforce safety: Workers can't spawn
  subagents (no Task tool), Context-Keeper can't run Bash."* Both named examples become false —
  `worker` and `context-keeper` will carry `Task`/`Bash` in the superset and rely solely on the
  denylist. Update the framing and both examples.
- **AC11 — Record and accept the enforcement-model downgrade explicitly, and state its scope
  HONESTLY.** `AGENT_GUIDELINES.md` and `ARCHITECTURE_CONTRACTS.md` both state `disallowedTools` is
  *"defense-in-depth… NOT a security boundary"*, with the `tools:` allowlist as the real restriction.
  This change moves **all 14** agents' restrictions from the allowlist to the denylist at once. Add a
  short, honest paragraph to `ARCHITECTURE_CONTRACTS.md` §"disallowedTools (Defense-in-Depth)"
  recording that the allowlist half of enforcement is now uniform-by-construction and the denylist
  carries the whole restriction.

  **The rationale MUST be split — do not write the simpler version.** An earlier draft of this AC
  justified the downgrade with "`permissionMode` is already ignored for plugin agents, so the
  denylist was already the surviving mechanism for the read-only roles." **That is false for exactly
  the agents where the downgrade is real, and writing it would durably record a false claim in a
  contracts doc.** Verified on disk — only six agents carry a denylist today (`context-keeper`,
  `rubric-grader`, `qa-strategist`, `worker`, `plan-reviewer`, `code-reviewer`). The honest split:
  - **No change in enforcement strength:** `code-reviewer`, `plan-reviewer`, `rubric-grader` — the
    denylist was already their surviving mechanism.
  - **A genuine reduction:** `orchestrator` and `execute-manager` have **no denylist today** and are
    100% allowlist-enforced (both are `Write: no` in the Capability Matrix); this is their FIRST
    reliance on the denylist. Name `orchestrator` explicitly as the case where the `permissionMode`
    argument does not even apply — **it declares no `permissionMode` at all**, so "that mechanism was
    already dead" is a non-sequitur for it. `review-pr` is the same shape but a weaker case
    (`Write: yes` via its fix worker).
  - **Wider than the read-only roles — but NOT uniformly 14-wide.** The downgrade also covers tools
    that were allowlist-excluded on *most* agents, not all. `TaskOutput` moves from
    allowlist-exclusion to denylist on **12** agents (`supervisor` and `execute-manager` declare it
    today); `LSP` on **10** (`launch-pad`, `code-reviewer`, `qa-executor`, `worker` declare it);
    `WebSearch`/`WebFetch` on **12** (`product-owner` and `red-team-reviewer` declare them).
    **The derivation table above is the check:** a row omits one of these four exactly when that
    agent already declares it. Far wider than the three read-only roles — but writing "all 14" would
    be a fresh false claim in the same doc, and is contradicted by eight rows of that table.
    (Verified on disk: `grep -l '^tools:.*\bLSP\b' loomwright/agents/*.md` → 4 files, etc.)

  Accepted for consistency and canonical ordering, with that cost stated. **Do not** silently ship
  this as if it were a no-op, and do not understate its scope.

## Outcomes Rubric

- Superset `tools:` line landed byte-identically across all 14 agents in one canonical order
- Per-agent effective-capability verification recorded by name, with the four Write/Edit-preserving
  agents explicitly called out — not asserted in aggregate
- Cache-prefix claim reported as NOT cleared with the structural reason, and no cache win claimed
  anywhere in the diff, PR body, or CHANGELOG
- Both ARCHITECTURE_CONTRACTS.md tables (disallowedTools + Agent Capability Matrix) reconciled, and
  the enforcement-model downgrade recorded rather than shipped silently
- All three falsified doc surfaces corrected at source (requirement, POINTER_AUDIT,
  shared-agent-prefix) plus AGENT_GUIDELINES' allowlist framing
- All 7 CI gates plus the whole test suite green, with budget headroom re-derived live and any raise
  justified per the raise rule

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Worker derives denylists as `superset − declared_tools` and blocks Write/Edit on the 4 memory agents | **HIGH** | PINNED SEMANTICS + the per-agent table (Plan-Review-verified); AC2 forces per-agent naming |
| Worker "optimizes" by unifying `disallowedTools` to chase the cache win | **HIGH** | RULE B forbids it by name and states the capability-expansion consequence |
| Enforcement silently downgraded from allowlist to denylist across all 14 agents | **HIGH** | AC11 forces it to be recorded and accepted explicitly |
| Worker restates the requirement's floor-clearing claim in CHANGELOG/CLAUDE.md | **MEDIUM** | AC3 + rubric bullet 3 both gate on no-cache-win-claimed |
| A cited doc surface is falsified by the change that cites it | **MEDIUM** | AC8 puts `shared-agent-prefix.md` in the lane; AC3 and AC8 must land together |
| Stale table passes all gates (no gate covers prose tables) | **MEDIUM** | AC7 covers BOTH tables — the "gates check currency, not completeness" blind spot, missed one table over in the first draft |
| Budget headroom computed from the stale frozen `measured` field | **LOW** | AC5 mandates live re-derivation via the gate, not the JSON field |
| Effective-toolset claim is environment-observed and not CI-verifiable | **LOW** | Report as an observed measurement with its control pair, not as a gate |

---

## Subtask Structure

**ONE subtask, Single-Agent Path (no worktree).** All 14 agent files plus the doc surfaces are one
tightly-coupled frontmatter change driven by a shared derivation table; any split would place that
table in every lane — the same-wave overlap trap (Plan Reviewer Criterion 16) that items 09 and 13
both hit.

| id | Title | Depends on |
|---|---|---|
| 1 | Unify `tools:` superset + per-agent `disallowedTools` across the 14 agents, reconcile the falsified doc surfaces, and record the enforcement downgrade | — |

```yaml
subtasks:
  - id: 1
    title: "Unified tools superset across the 14 agents"
    requires: []
    # Release-bump surfaces (CHANGELOG.md, CLAUDE.md, plugin.json, marketplace.json) and the
    # CONDITIONAL prompt-token-budgets.json edit are deliberately OUTSIDE provides — they are not
    # this subtask's contract artifacts, and their consistency is already machine-gated by
    # validate-version.sh (marketplace<->plugin version parity), check-doc-currency.sh (version and
    # count claims), and check-token-budget.sh (budget JSON <-> ARCHITECTURE_CONTRACTS mirror),
    # all three of which are in AC6's enumerated seven. Recorded so the exclusion reads as
    # conscious rather than as an omission.
    provides:
      - kind: file
        path: loomwright/agents/code-reviewer.md
        name: agent-frontmatter-code-reviewer
      - kind: file
        path: loomwright/agents/context-keeper.md
        name: agent-frontmatter-context-keeper
      - kind: file
        path: loomwright/agents/execute-manager.md
        name: agent-frontmatter-execute-manager
      - kind: file
        path: loomwright/agents/launch-pad.md
        name: agent-frontmatter-launch-pad
      - kind: file
        path: loomwright/agents/orchestrator.md
        name: agent-frontmatter-orchestrator
      - kind: file
        path: loomwright/agents/plan-reviewer.md
        name: agent-frontmatter-plan-reviewer
      - kind: file
        path: loomwright/agents/product-owner.md
        name: agent-frontmatter-product-owner
      - kind: file
        path: loomwright/agents/qa-executor.md
        name: agent-frontmatter-qa-executor
      - kind: file
        path: loomwright/agents/qa-strategist.md
        name: agent-frontmatter-qa-strategist
      - kind: file
        path: loomwright/agents/red-team-reviewer.md
        name: agent-frontmatter-red-team-reviewer
      - kind: file
        path: loomwright/agents/review-pr.md
        name: agent-frontmatter-review-pr
      - kind: file
        path: loomwright/agents/rubric-grader.md
        name: agent-frontmatter-rubric-grader
      - kind: file
        path: loomwright/agents/supervisor.md
        name: agent-frontmatter-supervisor
      - kind: file
        path: loomwright/agents/worker.md
        name: agent-frontmatter-worker
      - kind: file
        path: loomwright/docs/ARCHITECTURE_CONTRACTS.md
        name: architecture-contracts-tables
      - kind: file
        path: loomwright/docs/shared-agent-prefix.md
        name: shared-agent-prefix-honest-cache
      - kind: file
        path: loomwright/docs/POINTER_AUDIT.md
        name: pointer-audit-honest-cache
      - kind: file
        path: AGENT_GUIDELINES.md
        name: agent-guidelines-frontmatter-conventions
      - kind: file
        path: .supervisor/requirements/final-state/12-4c-unified-tools-lists.md
        name: requirement-premise-corrected
    # lanes are repo-relative path GLOBS (supervisor-readiness/SKILL.md §"Lane Declaration Schema").
    # Both consumers glob-match — worker.md ("matches at least one glob") and execute-manager.md
    # ("whose lanes: glob-match path") — so a trailing-slash DIRECTORY PREFIX matches nothing and
    # would put every touched file in out_of_lane. Use globs, not prefixes.
    # `loomwright/docs/*` (not `*.md`) so prompt-token-budgets.json stays in lane under AC5's
    # conditional raise.
    lanes:
      - "loomwright/agents/*.md"
      - "loomwright/docs/*"
      - "AGENT_GUIDELINES.md"
      - "CHANGELOG.md"
      - "CLAUDE.md"
      - ".supervisor/requirements/final-state/12-4c-unified-tools-lists.md"
      - "loomwright/.claude-plugin/plugin.json"
      - ".claude-plugin/marketplace.json"
```

## Parallelism Analysis

Single-agent (no fan-out). **Recommended workers: 1.** No split reason applies — the 14 agent files
share one derivation table and four doc surfaces must move in lockstep with them, so every candidate
split produces a same-wave lane overlap.

## File Impact

| Path | Action | Why |
|---|---|---|
| `loomwright/agents/*.md` (14 files) | modify | superset `tools:` + per-agent `disallowedTools` |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | modify | AC7 (both tables) + AC11 downgrade paragraph + budget mirror row if AC5 raises |
| `loomwright/docs/shared-agent-prefix.md` | modify | AC8 — its cache paragraph is half-falsified by this change |
| `loomwright/docs/POINTER_AUDIT.md` | modify | AC8 — add the subtractive-denylist corroboration |
| `AGENT_GUIDELINES.md` | modify | AC10 — allowlist framing + the two falsified examples |
| `.supervisor/requirements/final-state/12-4c-unified-tools-lists.md` | modify | AC8 — correct the floor-clearing premise at source |
| `loomwright/docs/prompt-token-budgets.json` | modify (conditional) | only on an actual live breach (AC5); expected NOT to trigger |
| `CHANGELOG.md` | modify | release notes (no cache-win claim) |
| `CLAUDE.md` | modify | one-paragraph current-version summary |
| `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | modify | version bump + in-place description version string (counts UNCHANGED 14/21/41/24) |

## Skill References

- `loomwright/skills/quality-checklist/SKILL.md` — pre/post-task gates
- `loomwright/skills/commit/SKILL.md` — conventional commit format
- `AGENT_GUIDELINES.md` §"Agent Frontmatter Conventions" — the surface this change edits

## Configuration

- **Mode:** Single-Agent Path (no worktree)
- **Recommended workers:** 1
- **Base Branch:** main

(Restated here as well as in §Environment: the house format carries Mode / workers / Base Branch
under `## Configuration`, and a consumer parsing that section by convention would otherwise find
nothing.)

No runtime config changes. No new env vars, no new gates, no hook changes.

## Handoff

Worker returns a `WORKER_RESULT` block naming every `provides` entry above. **Write the 14 agent
files FIRST** (most load-bearing artifact first) so a turn-limit exhaustion cannot cost the critical
work — this worker-dies-before-reporting failure mode hit items 11 and 13 in this same run, and
`outputs_verified` is worker-self-reported, so it is silently a no-op if the worker never reports.
Supervisor should re-verify the ACs on disk directly rather than trusting the self-report.

## Executable Acceptance

- `bash scripts/check-shared-prefix.sh && bash scripts/check-token-budget.sh && bash scripts/check-doc-currency.sh`
- `grep -c '^tools: Read, Write, Edit, Glob, Grep, Bash, Task, TaskOutput, LSP, WebSearch, WebFetch$' loomwright/agents/*.md | grep -c ':1$'` → must be `14`
- `for f in loomwright/agents/*.md; do grep -q '^disallowedTools:' "$f" || echo "MISSING: $f"; done` → no output

> All three bullets are bare-shell (`cmd`) form and are read-only/benign; they execute only on the
> interactive Phase 4.5 path and resolve to `cmd_disabled` under `--non-interactive`.

---

## Outcome

- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/125 (v15.24.0)
- **Branch:** feature/unified-tools-superset @ 49cb792 (base: main, self-verified)
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1 (holistic review PASS with 1 MEDIUM `new` finding → fixed → gates re-run green)
- **Heal remaining issues:** 0 new BLOCKING/HIGH; 1 LOW pre-existing left out of scope (`commands/dreaming.md` write-tools claim)
- **Rubric score:** 6/6
- **Until-mergeable dispatched:** false (deliberately suppressed by the /automate engine's `.auto_review:false` window; the engine owns exactly ONE inline drain — automate-loop §7)
- **Verification:** superset 14/14 byte-identical (13 distinct lists → 1); all 14 denylist rows re-derived from `main` and matched; 7/7 CI gates green; 52/52 test suite; budgets re-derived live, 0 breaches, tightest `rubric-grader` 189 headroom, no raise taken
- **Heal finding fixed:** the AC11 enforcement-downgrade enumeration omitted `Task` (allowlist→denylist on 9 agents, 4 with no prior `Task` denylist) and mis-classified `code-reviewer` as "no change in enforcement strength" — true for Write/Edit, false for Task. Doc + CHANGELOG mirror corrected together.
- **Open question recorded, not resolved:** `code-reviewer` carries `memory: project` yet does not gain Write/Edit, unlike the four memory agents that do.
