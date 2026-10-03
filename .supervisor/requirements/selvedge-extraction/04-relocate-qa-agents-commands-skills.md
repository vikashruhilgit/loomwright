# 04 — The atomic relocation: QA agents, commands, skills, hook, validator, pins, and counts

**Depends on:** 01 (fallback for `quality-checklist`), 02 (plugin-aware gates), 03 (telemetry
decision fixes the hook count; `/dreaming` decision removes the last inbound spawn).

## Why this slice is large — and why every smaller cut is forbidden

This is the one big slice, and it is big because **CI makes it atomic**, not because it was written
lazily. Each of the obvious smaller cuts is blocked by a specific named gate:

| Attempted cut | Blocked by |
|---|---|
| Move the 5 skills first, agents later | `check-token-budget.sh` fails CLOSED on "a broken frontmatter skill reference" — the still-in-loomwright QA agents would declare `skills: qa-strategy, …` pointing at another plugin |
| Move the agents first, skills later | Same gate, mirrored — the moved agents' preloads point back at loomwright |
| Move the agents, leave the `SubagentStop` hook | `check-contract-parity.sh`'s `MANIFEST` resolves `agent_path="$AGENTS/qa-executor.md"` and errors `field-presence`; worse, the orphaned matcher would silently validate nothing |
| Move the validator, leave `test-result-validators.sh` | The test invokes it at `loomwright/scripts/`, and CI's hard-gate loop runs the whole suite, failing on the first non-zero exit |
| Move the files, defer the counts | `check-doc-currency.sh` fails on 9 surfaces in the same commit |
| Move the agents, leave `test-agent-memory-permission.sh` | It pins a **seven-surface** list including both QA agent paths |

Everything genuinely separable was already pulled out: gate engineering → 02, behavioural decisions →
03, narrative docs → 05, memory store + selvedge CI → 06. What remains is `git mv` plus mechanical pin
and count updates.

## Goal

Relocate the QA subsystem to `selvedge/` in one green commit, with every mechanically-forced pin and
count updated alongside it.

## Scope

### 1. Files that move (`git mv` — preserve history)

| From | To |
|---|---|
| `loomwright/agents/qa-strategist.md` | `selvedge/agents/qa-strategist.md` |
| `loomwright/agents/qa-executor.md` | `selvedge/agents/qa-executor.md` |
| `loomwright/commands/qa-strategist.md` | `selvedge/commands/qa-strategist.md` |
| `loomwright/commands/qa-executor.md` | `selvedge/commands/qa-executor.md` |
| `loomwright/skills/qa-strategy/` | `selvedge/skills/qa-strategy/` |
| `loomwright/skills/qa-gates/` | `selvedge/skills/qa-gates/` |
| `loomwright/skills/qa-test-patterns/` | `selvedge/skills/qa-test-patterns/` |
| `loomwright/skills/qa-orchestration/` | `selvedge/skills/qa-orchestration/` |
| `loomwright/skills/playwright-e2e/` | `selvedge/skills/playwright-e2e/` |
| `loomwright/scripts/validate-qa-result.py` | `selvedge/scripts/validate-qa-result.py` |
| `loomwright/scripts/result-validator-fixtures/qa-result-valid.md` | `selvedge/scripts/result-validator-fixtures/qa-result-valid.md` |

`unit-testing` and `quality-checklist` **stay** (owner decision 3).

### 2. Namespace rename

`loomwright:qa-strategist` → `selvedge:qa-strategist`, `loomwright:qa-executor` →
`selvedge:qa-executor`, in: both agents' `name:` frontmatter, the **two internal debate-loop spawns**
inside `agents/qa-executor.md` (its own `subagent_type: "loomwright:qa-strategist"` call sites), the
`subagent_type` in `commands/qa-executor.md`, the new selvedge `hooks.json` matcher, and
`validate-qa-result.py`'s own docstring/comments (which name the matcher).

**Use the exact spawn-string form 01 recorded** for a second-plugin agent — including whether the
prefix is doubled. Do not infer it from the loomwright pattern.

### 3. `selvedge/hooks/hooks.json`

One matcher, `selvedge:qa-executor`, carrying the validator hook:
`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-qa-result.py" || true`. Whether the telemetry
fan-out hook is present at all is **03's decision** — implement whatever 03 recorded, and re-derive
the resulting loomwright count from the file.

The `|| true` convention holds: it is valid **only** because this validator is an always-exit-0
fail-safe emitter. Do not add a blocking gate here carrying `|| true`.

### 4. The `quality-checklist` preload

Apply 01's chosen fallback. If the fallback is "drop the preload and reference read-on-demand", both
agents' `skills:` lists shrink and their `check-token-budget.sh` proxy weight **drops** — so
selvedge's `prompt-token-budgets.json` entries must be re-measured from the post-move files, not
copied from loomwright's current numbers.

### 5. Pins and gate data that must move in the same commit

- **`prompt-token-budgets.json`** — remove `qa-executor` and `qa-strategist` from loomwright's; create
  `selvedge/docs/prompt-token-budgets.json` with **re-measured** proxy weights + ~10% headroom, and
  the mirror rows in whichever ARCHITECTURE_CONTRACTS-equivalent selvedge carries (or record
  explicitly that selvedge has no mirror table yet and why). `check-token-budget.sh` fails CLOSED on
  an agent with no declared budget.
- **`check-contract-parity.sh`** — flip the `qa-executor` `MANIFEST` row and the
  `agents/qa-executor.md` `ENUMS` row to the selvedge plugin dimension added in 02. The `MANIFEST`'s
  pin-drift guard requires the field names to still appear in the **validator script's non-prose
  source**, so confirm the move did not disturb them.
- **`check-shared-prefix.sh`** — the two moved agents keep the byte-identical
  `SHARED-AGENT-PREFIX v1` block, still checked against loomwright's canonical
  `docs/shared-agent-prefix.md`. Loomwright drops to 12 copies, selvedge holds 2.

### 6. Tests that break the moment the files move (must be in this commit)

- `loomwright/scripts/test-result-validators.sh` — invokes `validate-qa-result.py` + its fixture.
  Decide: move the QA portion into a new `selvedge/scripts/test-result-validators.sh`, or point the
  loomwright test cross-plugin. **Moving is preferred** (a plugin's tests belong with the plugin), and
  02 already extended CI's loop to run `selvedge/scripts/test-*.sh`.
- `scripts/test-check-contract-parity.sh` (repo root) — 25 QA refs, fixture-tree based.
- `loomwright/scripts/test-agent-memory-permission.sh` — its **seven-surface** list pins both QA agent
  paths. Either it becomes cross-plugin, or selvedge gets its own copy of the check for its two
  agents. **The contract itself (`AGENT_GUIDELINES.md`'s agent-memory write rule) stays in loomwright
  and must not be duplicated** — so a cross-plugin surface list is the likely answer. Preserve the
  test's teeth: it currently proves a deleted rule fails, and that mutation control must survive.
- `loomwright/scripts/test-insights.sh` and `test-token-ledger.sh` — assert on
  `agent_type: "loomwright:qa-executor"` ledger lines. Update the literal, or replace with a
  non-QA agent type if 03 dropped the QA fan-out. Do **not** leave an assertion whose subject no
  longer exists — that is a vacuous test.
- `loomwright/scripts/test-run-ground-truth.sh` — per 03's decision on the reserved kind.

### 7. Counts (all in this commit)

| Count | Before | After | Authority |
|---|---|---|---|
| agents | 14 | **12** | `find loomwright/agents -maxdepth 1 -name '*.md'` |
| commands | 21 | **19** | `find loomwright/commands -maxdepth 1 -name '*.md'` |
| skills | 41 | **36** | `find loomwright/skills -mindepth 1 -maxdepth 1 -type d` |
| hooks | 24 | **22** (see note) | `jq '[.hooks[][].hooks[]] \| length' loomwright/hooks/hooks.json` |

> **The hook figure is 22, not 23.** The `loomwright:qa-executor` matcher carries **two** hook
> entries — the validator *and* the shared telemetry/token-ledger fan-out — and the gate counts leaf
> entries. If 03 chose to preserve a fan-out in selvedge, **re-derive from `hooks.json`; never restate
> a number from this brief.**

The 9 doc-currency surfaces: `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`,
`.claude-plugin/README.md`, `.claude-plugin/marketplace.json`, `loomwright/.claude-plugin/plugin.json`,
`loomwright/commands/agent-help.md`, `loomwright/docs/ARCHITECTURE.md`,
`loomwright/docs/ARCHITECTURE_CONTRACTS.md`.

### 8. Surfaces that must be truthful at this commit (the rest defer to 05)

- **`loomwright/commands/agent-help.md`** — the user-facing command index. It carries 27 QA refs and
  is a doc-currency surface. It must not advertise two commands the plugin no longer ships; sweep its
  QA sections here, not in 05.
- **`loomwright/skills/SKILLS_INDEX.md`** — the 5 rows must be removed or the gate fails; a new
  `selvedge/skills/SKILLS_INDEX.md` must exist and be well-formed (`check-skills-index-sync.sh` fails
  loudly on a `skills/` dir with no index, and requires a well-formed `X.Y.Z` Version cell per row
  matching each `SKILL.md`'s frontmatter).
- **`unit-testing/SKILL.md`** and **`ci-cd/SKILL.md`** — both cross-reference `playwright-e2e` in
  "see also" prose. Rewrite to "install `selvedge@atelier` for `playwright-e2e`". **Never** a
  `${CLAUDE_PLUGIN_ROOT}` path into another plugin (the stackpack spin-off set that precedent).
- **`selvedge/.claude-plugin/plugin.json`** — description and counts updated **in place** to reflect
  2 agents / 2 commands / 5 skills / 1 hook; mirror in `marketplace.json`. Summary, not changelog.

Deferred to 05 (state this in the PR body so a reviewer sees it is intentional):
`docs/QA_SYSTEM_BLUEPRINT.md` relocation, `RESULT_SCHEMAS.md` `QA_RESULT` ownership,
`ARCHITECTURE.md` / `ARCHITECTURE_CONTRACTS.md` narrative (their *counts* are updated here),
`HOOKS.md`, `TELEMETRY.md`, `POINTER_AUDIT.md`, `FAILURE_ESCALATION.md`, `AGENT_GUIDELINES.md`
narrative rows, `IMPROVEMENTS_ROADMAP.md`, and the `docs/SPIKES/*` mentions.

## Constraints / invariants

- **Every gate green at this commit** — that is the whole difficulty, and it is the acceptance bar.
- `git mv`, not delete-and-create: history on 780- and 522-line agent prompts is worth keeping.
- **No duplication of loomwright-owned shared assets** — `quality-checklist`, `write-agent-memory.sh`,
  the `QA_RESULT` schema section, the telemetry rubric, and `docs/shared-agent-prefix.md` all stay
  single-copy.
- **Grep the OLD values repo-wide after the sweep**, with flexible separators. A green
  `check-doc-currency.sh` is necessary, not sufficient — it verifies claims that ARE made and cannot
  tell you a claim should not have been made. Agent/command *enumeration prose* is outside its scope
  entirely.
- **Prompts are programs.** State-trace `agents/qa-executor.md`'s internal debate loop across the
  rename: it spawns QA Strategist twice, and both call sites must resolve under the new namespace.
  A wrong `subagent_type` fails at runtime, not in CI.
- **Do not let a moved test go vacuous.** Every assertion whose literal subject changed
  (`loomwright:qa-executor` ledger lines, validator paths, surface lists) must still fail when its
  mechanism is removed. Mutation-control each one — this repo has recorded a shared-fixture default
  silently disarming the one assertion it was meant to protect.
- bash-3.2-safe / Ubuntu-clean for anything touched under `scripts/`.

## Acceptance criteria

- [ ] All 11 paths relocated via `git mv`; loomwright retains `unit-testing` and `quality-checklist`.
- [ ] Namespace renamed everywhere, using **01's recorded spawn-string form**; both internal
      debate-loop call sites in `qa-executor.md` traced and verified, not just search-replaced.
- [ ] `selvedge/hooks/hooks.json` ships the validator matcher; the `|| true` fail-safe convention
      preserved; the telemetry-fan-out disposition matches 03's recorded decision.
- [ ] 01's `quality-checklist` fallback implemented; if the preload was dropped, both agents'
      budgets are **re-measured from the post-move files**, not carried over.
- [ ] `selvedge/docs/prompt-token-budgets.json` exists with entries for both agents;
      `check-token-budget.sh` passes for **both** plugins and still fails closed on an undeclared
      budget in either.
- [ ] `check-contract-parity.sh` `MANIFEST` + `ENUMS` rows flipped to selvedge; the pin-drift guard
      still resolves the validator's non-prose source; gate green.
- [ ] `check-shared-prefix.sh` green with 12 loomwright + 2 selvedge byte-identical copies against the
      single loomwright canonical.
- [ ] `check-skills-index-sync.sh` green for both plugins; `selvedge/skills/SKILLS_INDEX.md` has 5
      well-formed rows whose Version cells match each `SKILL.md` frontmatter.
- [ ] Counts updated on all 9 doc-currency surfaces; the hook count **re-derived from `hooks.json`**
      and stated in the PR with the `jq` output attached.
- [ ] Every relocated/updated test still has teeth: for each assertion whose literal subject changed,
      a mutation control shows it fails when the mechanism is removed.
- [ ] `agent-help.md` no longer advertises `/qa-strategist` or `/qa-executor` as loomwright commands
      and points users at selvedge.
- [ ] `unit-testing` and `ci-cd` `playwright-e2e` pointers rewritten as install-guidance, with **no**
      `${CLAUDE_PLUGIN_ROOT}` path into another plugin.
- [ ] Repo-wide grep of the OLD counts (14 / 21 / 41 / 24) with flexible separators returns only
      legitimate historical mentions (changelog entries, dated narrative), each verified intentional.
- [ ] Both plugins install cleanly locally; `/agent-help` shows 12 loomwright agents;
      `/qa-executor` resolves via selvedge; a real QA run emits a `QA_RESULT` that the selvedge hook
      validates. **Verified by running it, not by reading the wiring.**
- [ ] Full CI green — all seven gates plus every plugin's `test-*.sh` hard-gate loop.

## Out of scope

Doc narrative beyond `agent-help.md` (05). `QA_SYSTEM_BLUEPRINT.md` relocation (05). Agent-memory
store migration (06). Selvedge's own doc-currency gate (06). CHANGELOG / README migration notes (07).

## Outcomes Rubric

- QA subsystem lives in selvedge and actually runs there — proven by an executed QA run, not a trace
- Atomicity is justified per-cut against a named gate, and nothing separable was swept in
- Every mechanically-forced pin moved in the same commit: budgets, parity rows, shared prefix, index
- Hook count re-derived from `hooks.json` with output attached; 22 vs 23 settled by measurement
- No moved or edited test went vacuous — each changed assertion is mutation-controlled
- No loomwright-owned shared asset duplicated; no cross-plugin `${CLAUDE_PLUGIN_ROOT}` path
- Old counts swept repo-wide with flexible separators; remaining hits verified intentional


## Status: done_with_escalation — ABANDONED (owner dropped the selvedge extraction track 2026-08-22)
- **Evidence:** `.supervisor/automate/automate-2026-08-18-124023.md` (queue rows 04–07 "abandoned: owner dropped the selvedge extraction track on 2026-08-22; not pursued"); PR #157 CLOSED unmerged; branch `feature/relocate-qa-to-selvedge` retained on origin.
- **Why this stamp:** `is_done()` in automate-helpers.sh honours only `done` / `done_with_escalation`, so this is the only marker that keeps `/automate` from re-enqueuing a dropped item. Slices 01–03 DID merge (#153/#155/#156) and are stamped done separately.
- **Reconciled:** 2026-09-21 by hand.
