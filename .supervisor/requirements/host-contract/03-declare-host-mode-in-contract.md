# 03 — Declare host mode in the capability contract (`host_switch` + per-hook `host_mode`)

## Status: pending

> **Origin (2026-10-06).** Split out of item 02 by the S3 operator on the owner's decision ("split"), so 01 (the
> contract) and 02 (host mode in the hooks) can run as parallel wave-3 lanes with no file in common. This item is the
> join: it runs after BOTH have merged. Text below is 02's former scope bullet and AC6, moved verbatim in substance.
> Small enough to be done directly (plain branch + PR, ci-local, owner merges) rather than as a lane, like pa/19.

## Depends on
01
02

## Touches
loomwright/scripts/build-capabilities.sh
loomwright/scripts/test-build-capabilities.sh
loomwright/capabilities.json
loomwright/docs/CAPABILITIES_CONTRACT.md
changelog.d/host-contract-03-declare-host-mode-in-contract.md

## Problem
After 01 and 02, the contract (`capabilities.json`, `host_switch: null`) does not tell a host that host mode exists,
which env vars switch it, or what each hook does under it. A host would have to read `docs/HOOKS.md` — exactly the
internal-file parsing D32 rejects.

## Goal
The contract declares host mode, generated from the plugin's sources like every other field.

## Scope
- `host_switch: {env, state_dir_env, effect}` in `capabilities.json`, with 02's env names (e.g. `LOOMWRIGHT_HOST_MODE`,
  `LOOMWRIGHT_HOST_STATE_DIR`).
- Each hook entry gains `host_mode: "redirects" | "skips" | "unaffected"`, taken from 02's classification (its
  `docs/HOOKS.md` host-mode section). The generator derives it from a source it reads, never a hand-kept list that can
  drift from the hooks; if no machine-readable source exists, add a minimal one in the hook scripts or `HOOKS.md`.
- `CAPABILITIES_CONTRACT.md` documents both fields. Adding them is additive under 01's compatibility policy, so
  `contract_schema_version` stays the same.
- Tests: every hook entry has a `host_mode`; `host_switch` names the env vars 02's scripts actually read (grep, not
  assumed); regenerating is byte-identical; a mutation control (change one hook's classification at the source) makes
  the staleness check fail.

## Acceptance criteria
1. `capabilities.json` declares `host_switch` with the env names 02's hooks read, verified by a test.
2. Every hook entry carries a `host_mode` derived from a source, never hand-edited in the JSON.
3. The contract is regenerated and the staleness check passes; regeneration is byte-identical.
4. `CAPABILITIES_CONTRACT.md` documents both fields as an additive change.
5. Ships a `changelog.d` fragment; the release bump follows separately (or with the next wave's bump).

## Non-goals
Changing hook behaviour (02). Studio reading the contract (Studio's phase 2).
