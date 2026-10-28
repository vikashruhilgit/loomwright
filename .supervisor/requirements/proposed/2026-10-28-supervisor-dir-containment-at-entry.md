# Refuse to start a run when `.supervisor` resolves outside the checkout — STUB

## Status: proposed (stub — split out of the config-writer symlink item as owner decision D1, 2026-10-28; verify premises against CLAUDE.md invariants before promoting)

**As a** maintainer running `/automate`, `/supervisor` or `/autonomous` in a repo I cloned,
**I want** the run to refuse to start when `.supervisor` (or `.supervisor/automate`) is a symlink whose real
location is outside the checkout,
**so that** run files, `state.md`, logs, briefs and sidecars can never be written somewhere else on my machine.

## Why (from the parent item)

`2026-10-28-config-writer-symlink-containment.md` closes the config-file writes only. A symlinked
`.supervisor` still redirects every other plugin write under it. `scripts/meta-sync.d/managed.sh`
(`list_local`) already refuses a symlinked `.supervisor` ("run history must live inside the checkout"); this
item would apply the same stance at run entry.

## Intended shape (to be re-verified, not built from this text)

- One check at the entry points (for example `automate-helpers.sh init-check` / `pick-guard`, Supervisor INIT,
  `/autonomous` INIT), using `contained-path-lib.sh` from the parent item. On failure it refuses with a
  named status and writes nothing, including no run file.
- Decide whether hook-invoked emitters that write under `.supervisor` (fail-SAFE, always exit 0) should skip
  their write, rather than block, when `.supervisor` is outside. CLAUDE.md's bimodal-failure invariant says
  emitters must stay exit 0.

## Depends on
2026-10-28-config-writer-symlink-containment.md

## Touches
unknown
