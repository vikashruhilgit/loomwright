# 05 — Doc and contract boundary: what selvedge owns, what loomwright keeps

**Depends on:** 04 (the files are in selvedge; only their descriptions are still wrong).

## Problem — the counts are right but the story still says QA lives in loomwright

Slice 04 updated every claim a gate can see. It deliberately left the *narrative* alone, because
`check-doc-currency.sh` scans only high-confidence version/count phrasings and explicitly does **not**
cover agent enumerations, workflow prose, or capability tables. So after 04 the repo is green and
substantially untrue: a dozen loomwright docs still describe QA Strategist and QA Executor as
loomwright agents, and one 362-line design document for a subsystem that no longer lives here.

This is the "a claim no check backs" class the repo has already generalized. Nothing will catch these
mechanically — only a deliberate sweep will.

## The ownership question that must be answered first

Owner decision 2 says: do **not** duplicate the `QA_RESULT` schema section into selvedge. That
settles duplication but not **location**. Three surfaces need an explicit, recorded ruling:

| Surface | Ruling to make | Recommendation |
|---|---|---|
| `docs/RESULT_SCHEMAS.md` §`QA_RESULT` | Stays in loomwright as the single cross-plugin contract registry, or moves to selvedge with loomwright keeping a pointer? | **Stays.** It is one section in a registry that also defines the 13 other result blocks and the shared `schema_version` discipline; splitting it fragments the contract surface. Selvedge's agent prompt points at it. |
| `docs/QA_SYSTEM_BLUEPRINT.md` (362 lines) | Move to selvedge, or keep? | **Moves.** It is a whole-document design for the QA subsystem with no non-QA content — the clean case, and the opposite of the `QA_RESULT` section. |
| `AGENT_GUIDELINES.md` result-block list + QA agent rows | Stays (it is the repo-root shared contract, with no loomwright copy — `test-agent-memory-permission.sh`'s header says creating one would fork the contract into a file no gate scans) | **Stays**, with the QA rows re-labelled as selvedge-provided. |

Record the ruling and its reasoning **in the docs themselves**, not only in a PR body. The distinction
being drawn — *whole-document subsystem design moves; a section of a shared registry does not* — is
the reusable rule, and it should be written down as such.

## Scope

### 1. Move `docs/QA_SYSTEM_BLUEPRINT.md` to `selvedge/docs/`

Update every inbound pointer. `CLAUDE.md` §References lists it inside the
`loomwright/docs/{RESULT_SCHEMAS,ARCHITECTURE_CONTRACTS,…,QA_SYSTEM_BLUEPRINT,…}.md` brace expansion —
that expansion must lose the entry, and gain a pointer to selvedge instead. A brace list is exactly
the kind of surface a naive grep for `QA_SYSTEM_BLUEPRINT` finds but a careless edit half-fixes.

### 2. Sweep the loomwright docs that describe QA as loomwright's

Each of these has verified QA content. Re-verify counts at execution time — the list is a starting
point, not a substitute for a fresh grep:

| Surface | Nature of the QA content |
|---|---|
| `docs/ARCHITECTURE.md` | agent inventory / workflow narrative |
| `docs/ARCHITECTURE_CONTRACTS.md` | §Agent Invariants rows, capability matrix, context budgets, cost-profile rows, token-budget mirror table |
| `docs/RESULT_SCHEMAS.md` | `QA_RESULT` section header + `QA_SESSION_PLAN` / `QA_SESSION_COVERAGE`; producer attribution needs the selvedge namespace |
| `docs/TELEMETRY.md` | the `loomwright:qa-executor` row in the agent table + Rubric C — reconcile with 03's dormancy banner |
| `docs/HOOKS.md` | §Hook Table — the authoritative always-current hook table; the QA row leaves |
| `docs/FAILURE_ESCALATION.md` | QA escalation paths |
| `docs/POINTER_AUDIT.md` | pointer inventory naming QA paths |
| `docs/IMPROVEMENTS_ROADMAP.md` | QA roadmap items |
| `AGENT_GUIDELINES.md` | result-block list, per-agent memory table, the agent inventory rows, and the hook-kinds sentence naming `qa-executor` among the `SubagentStop` validators |
| `skills/telemetry/SKILL.md` | the `agent:qa-weak` label example |
| `skills/workflow-management/SKILL.md` | the hook-conversion note naming `qa-executor` |
| `skills/SKILLS_INDEX.md` | any residual QA prose outside the 5 rows removed in 04 |
| `CLAUDE.md` | §The 14 Agent Roles quick map (2 rows leave), §References brace list, and the latest-change banner |
| `docs/SPIKES/*` | `FABLE_PARITY_EVAL.md`, `EVAL_FINDINGS_AND_FIXES.md`, `QA_AND_DURABILITY_BACKLOG.md`, `SYSTEM_TWIN_ROADMAP.md`, `CODE_GRAPH_OWNERSHIP.md`, `BRAIN_INTEGRATION_EVOLUTION.md` |
| `scripts/result_block_parser.py` | a comment enumerating validated agents incl. `qa-executor` |

### 3. SPIKES docs get banners, not edits

Follow the precedent set when the graphify tier was retired: spike/evidence docs are **historical
records** and are not rewritten to match present reality. `FABLE_PARITY_EVAL.md` in particular holds
an *unrun* eval whose QA arms are still a live plan (see the twin-remediation queue's item 07). Add a
dated status banner noting the QA agents now ship in `selvedge` and the doc's QA references are
historical — **do not** silently rewrite the measurements or the plan.

### 4. Selvedge's own docs

Selvedge needs enough to stand up as a plugin: its README expanded with what the two agents do, the
companion requirement, and pointers **back** to loomwright for `RESULT_SCHEMAS.md` (`QA_RESULT`),
`AGENT_GUIDELINES.md`, and `quality-checklist`. Those back-pointers are the visible form of the
companion model — they must be prose pointers, **never** `${CLAUDE_PLUGIN_ROOT}` paths into another
plugin.

## Constraints / invariants

- **Counts unchanged.** 04 already set them. `check-doc-currency.sh` must stay green with no count
  edits in this slice — if a count changes here, something in 04 was wrong.
- **No duplication.** Selvedge points at loomwright's shared docs; it does not copy them.
- **Derive, never restate.** Do not create a second copy of the hook table, the result-schema
  contract, or the agent inventory inside selvedge. This repo has already had a duplicated hook table
  silently drift from 9 to 21 hooks while nobody noticed.
- **Grep terms come from the files' own vocabulary.** Two independent audits in this repo previously
  returned a false clean by grepping a guessed string form. Derive the sweep terms from the actual
  text (`qa-executor`, `qa-strategist`, `QA Executor`, `QA Strategist`, `QA_RESULT`,
  `QA_SESSION_PLAN`, `QA_SESSION_COVERAGE`, `QA_SYSTEM_BLUEPRINT`, `playwright-e2e`, `qa-gates`,
  `qa-strategy`, `qa-test-patterns`, `qa-orchestration`), and record the method alongside the result.
- **Descriptive anchors, not bare line numbers**, in any new committed prose —
  `scripts/test-citation-drift.sh` fails a new bare unpinned `file:N`.
- `CLAUDE.md`'s latest-change banner is written **without version numbers or counts** (they live in
  `plugin.json` and `CHANGELOG.md`), per its own §Full release history rule.

## Acceptance criteria

- [ ] `QA_SYSTEM_BLUEPRINT.md` relocated to `selvedge/docs/`; every inbound pointer updated —
      including `CLAUDE.md` §References' **brace expansion**, verified by opening the line, not by a
      grep hit count.
- [ ] The three ownership rulings (`QA_RESULT` section, blueprint, `AGENT_GUIDELINES.md`) recorded
      **in the docs themselves**, each with its reasoning, and the reusable distinction stated:
      whole-document subsystem design moves, a section of a shared registry does not.
- [ ] Every surface in the §2 table swept, or explicitly listed as deliberately unchanged with a
      reason. "No hits" is not an acceptable outcome for a file the table names — re-grep with terms
      derived from the file's own vocabulary.
- [ ] `CLAUDE.md` §The 14 Agent Roles quick map reflects the remaining agents; its latest-change
      banner is updated and carries **no** version string or count.
- [ ] `docs/HOOKS.md` §Hook Table — the authoritative source — no longer lists the QA matcher and
      agrees with `hooks.json`.
- [ ] `docs/TELEMETRY.md` reconciled with 03's Rubric C decision; if kept dormant, the banner is
      present and dated, and the agent-table row does not read as live.
- [ ] SPIKES docs carry dated status banners and are **otherwise unedited** — measurements, retracted
      claims, and unrun plans preserved (the graphify-retirement precedent).
- [ ] Selvedge README expanded with the companion requirement and prose back-pointers; **zero**
      `${CLAUDE_PLUGIN_ROOT}` paths crossing a plugin boundary anywhere in the repo (grep-proven).
- [ ] Counts provably unchanged from 04; all CI gates green.
- [ ] A `consistency_audit`-style pass confirms no remaining loomwright surface describes QA
      Strategist or QA Executor as a loomwright-shipped agent.

## Out of scope

Any file relocation other than the blueprint. Any count change. Agent-memory store migration (06).
CHANGELOG / user migration announcement (07).

## Outcomes Rubric

- Blueprint moved with every inbound pointer fixed, brace expansion included
- Ownership rulings recorded in-repo with reasoning and a reusable rule, not just applied
- Full narrative sweep with terms derived from the files' own vocabulary, method recorded
- SPIKES evidence preserved and banner-marked, never rewritten
- Selvedge documents the companion contract with prose back-pointers, no cross-plugin paths
- Zero duplication of loomwright-owned shared docs; counts untouched


## Status: done_with_escalation — ABANDONED (owner dropped the selvedge extraction track 2026-08-22)
- **Evidence:** `.supervisor/automate/automate-2026-08-18-124023.md` (queue rows 04–07 "abandoned: owner dropped the selvedge extraction track on 2026-08-22; not pursued"); PR #157 CLOSED unmerged; branch `feature/relocate-qa-to-selvedge` retained on origin.
- **Why this stamp:** `is_done()` in automate-helpers.sh honours only `done` / `done_with_escalation`, so this is the only marker that keeps `/automate` from re-enqueuing a dropped item. Slices 01–03 DID merge (#153/#155/#156) and are stamped done separately.
- **Reconciled:** 2026-09-21 by hand.
