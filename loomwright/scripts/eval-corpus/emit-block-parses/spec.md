# Task: emit-block-parses

## What this task asks

Every emit-block template in an agent prompt must, copied verbatim, **parse**
under `result_block_parser.py`.

This is the layer below `parity-emit-block`. That task asks whether the required
field *names* are present in the template; this one asks whether the template is
a shape the parser can actually read. A template can satisfy the first and fail
the second, and one did: the adjudication `EXECUTE_CHECKPOINT` templates in
`execute-manager.md` carried all five required fields — `parity-emit-block`
green — but wrapped `adjudication_options: [...]` across two lines and, in the
lane-collision variant, wrapped a quoted `reason` across three. The parser
supports a strict YAML subset that **rejects a flow collection continued onto a
second line** and **rejects block scalars (`>` / `|`) outright**, so both
templates were rejected at the *parse* step, before rule 6 was ever consulted.
An agent copying the template would have been told its block was malformed.

## How it's checked

`check.sh` parses the `MANIFEST` table out of the repo-root
`scripts/check-contract-parity.sh` — the same single source of field truth
`parity-emit-block` reuses, deliberately rather than adding another parallel
table. For each `matcher|agent|block|fields` row it:

1. Extracts **every** emit-template occurrence for the block from the agent
   file, in either authoring style (YAML anchor line `BLOCK:` plus its indented
   body, captured until dedent or a fence line; or a markdown `## BLOCK`
   heading plus its bullets). Unlike `parity-emit-block`, occurrences are kept
   **separate** rather than unioned — parseability is a per-template property.
2. Normalizes authoring placeholders: `{subtask_id}` → `x`, `[...]` → `[x]`.
   Both substitutions are **within a single line** and never add or remove a
   line break, so line structure — which is precisely what a wrapped flow
   collection or a block scalar gets wrong — passes through untouched. This is
   load-bearing: a normalizer that reflowed text could normalize away the defect
   class the task exists to catch. Mutation control M1 below pins it.
3. Runs `parse_block()` and fails on any non-empty `errors` list.

**Oracle scope is parse-level only.** Semantic rules — worktree paths must
resolve to siblings, an adjudication needs a non-empty evidence array, and so on
— are deliberately *not* asserted. A template's placeholder values cannot
satisfy them, so asserting them would make the task untestable rather than
stronger. Rule conformance belongs to the SubagentStop hook and
`test-result-validators.sh`; **line-structure** conformance belongs here.

A row whose template cannot be located is passed over in silence rather than
failed: `parity-emit-block` already reports that condition in its own wording,
and duplicating it would blur which oracle caught what. The vacuous-pass risk
that opens up is closed by a separate guard — if *no* template is located for
*any* row, the extraction itself is broken and the task fails (M5).

Deterministic and read-only.

## Mutation controls

These are **executed, not merely documented** — `loomwright/scripts/test-emit-block-parses.sh`
runs them against a mktemp fixture tree (`--root <dir>` carrying
`scripts/check-contract-parity.sh`, `loomwright/agents/`, and
`loomwright/scripts/result_block_parser.py`) and is picked up by CI's
hard-gating `test-*.sh` loop.

| # | Mutation | Expected | Automated |
|---|---|---|---|
| M0 | unmutated tree | PASS (17 templates) | yes |
| M1 | re-wrap `adjudication_options: [...]` across two lines | FAIL — `unexpected end of flow collection` | yes |
| M2 | fold the lane-collision `reason` into a `>-` block scalar | FAIL — `unsupported YAML construct: block scalar (>)` | yes |
| M3 | restore `execute-manager.md` to its pre-fix content (the as-merged PR #154 text) | FAIL — the historical defect is caught | no — verified once against git history 2026-08-23; it is M1 and M2 co-occurring, which the automated pair covers |
| M4 | collapse the options to a **single-line** flow sequence | PASS — the task checks parseability, not house style | yes |
| M5 | rename every block anchor so extraction finds nothing | FAIL — vacuous pass is rejected, not silently green | yes |

M4 matters as much as M1: an oracle that only accepted block sequences would be
enforcing a style preference under the guise of a correctness check.

Each mutation asserts its own anchor is present and unique before applying, so a
future re-styling of the template makes the self-test **fail loudly** ("template
restyled without updating this test") rather than silently mutate nothing and
pass — the shared-fixture-disarms-its-own-assertion failure mode.

## Portability

**Maintainer-side** (like `parity-emit-block` and `doc-currency-green`): it
depends on this repo's `scripts/check-contract-parity.sh`,
`loomwright/agents/`, and `loomwright/scripts/result_block_parser.py`. It
requires `python3` — the parser is Python, and re-implementing its accepted
subset in awk would be a second source of truth for the exact thing under test.
It would not pass in a marketplace install under an arbitrary user project.
