# Vendor-coupling ratchet — LOOMWRIGHT_ROOT indirection + CI gate

> Story for `twin-remediation/10-harness-portability.md`. Item 10 §2 specifies the
> `LOOMWRIGHT_ROOT` indirection but has **no mechanism to hold the line afterwards** — this story
> supplies it. Architecture rule (memory `portability-core-vs-adapter`, unchanged): vendor-neutral
> CORE, harness-specific ADAPTERS; native primitives land in the Claude adapter, never the core.

## Problem (measured 2026-08-22)

Item 10 was written 2026-07-23 against v15.13.0. Re-measured today, the seam it set out to shrink
has instead **kept growing** while the requirement sat unexecuted — prompt-layer coupling
up 31%, and script portability down from 82% to 70%:

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

Refs by area today (repo-wide, 309): commands 86 · skills 65 · scripts 64 · agents 46 · docs 25 ·
hooks 23.

**Basis note:** the July record measured the prompt layer and `.sh` scripts only; the repo-wide
309 figure has no July counterpart and is a new baseline, not a delta. The load-bearing regression
is the **82% → 70% script-portability drop**, which is measured on identical basis both dates.

**Root cause:** nothing in CI gates the addition of new Claude-specific coupling to core assets.
Portability is asserted in a memory and a requirement doc, but no check enforces it, so every
release is free to weld more on — and did. A one-shot inventory (item 10 §1) produces a number
that is stale the week after it is published. The standing "natives in the adapter, never the
core" rule (which also reconciles item 10 against item 09's native-primitive adoption) is
likewise unenforced prose.

This is the same class as memory `rules-violated-by-their-own-surrounding-text` — a claim no
check backs.

## Goal

Make vendor-neutrality a **mechanically enforced ratchet**: the core's coupling count can go down
or stay flat, never up, without an explicit reviewed exemption.

## Scope

1. **`LOOMWRIGHT_ROOT` indirection (item 10 §2, unblocked here).** Resolve once, defaulting from
   `CLAUDE_PLUGIN_ROOT` when present, so the core stops naming a vendor. Claude Code marketplace
   installs and dev checkouts must both keep resolving — verify both, do not assume.
2. **CORE/ADAPTER classification made machine-readable.** A committed manifest declaring which
   paths are CORE (must be vendor-neutral), ADAPTER (may name any harness freely), or COUPLED
   (grandfathered debt, with a per-path allowance count). Without this the gate cannot tell a
   legitimate adapter ref from a regression.
3. **The ratchet gate (`scripts/check-vendor-coupling.sh`).** Counts vendor-specific references
   per CORE/COUPLED path and fails when a count **exceeds** its declared allowance. Allowances
   ratchet down as debt is paid; raising one requires editing the manifest in the same PR, which
   is reviewable. Fails **CLOSED** — this is a correctness gate, not a runtime emitter, so it
   must NOT carry the `|| true` convention (see CLAUDE.md §"Failure-Mode Invariants").
4. **Wire into CI** alongside the existing doc-currency/token-budget gates.
5. **Mutation control.** Prove the gate can actually fail: a test that injects a vendor ref into a
   CORE path and asserts non-zero exit. Per memory `shared-fixture-default-disarms-its-own-assertion`
   and `rules-violated-by-their-own-surrounding-text`, a guard written to catch this class is
   itself typically vacuous until mutated.

## Non-goals

- No mass rewrite of the 284 existing refs — they are grandfathered as declared allowances. This
  story stops the growth; item 10's inventory pays the debt down.
- No degradation of Claude Code, which remains the primary and most capable target.
- No new advisory stores (freeze-compatible).

## Acceptance criteria

- [ ] Given a CORE-classified script, when a new `CLAUDE_PLUGIN_ROOT` (or other vendor) reference
      is added, then CI fails with the offending path and the declared-vs-actual counts.
- [ ] Given an ADAPTER-classified path, when vendor references are added, then CI passes —
      adapters are allowed to exploit every primitive their harness offers.
- [ ] Given the manifest allowance is raised in the same commit, then CI passes (the raise is
      visible in review rather than silent).
- [ ] Given `CLAUDE_PLUGIN_ROOT` is set, then `LOOMWRIGHT_ROOT` resolves to the same path;
      given it is unset but the repo layout is a dev checkout, then resolution still succeeds.
- [ ] Mutation control: injecting a vendor ref into a CORE path makes the gate exit non-zero
      (asserted by a test, not by inspection).
- [ ] Gate carries no `|| true`; it is a fail-CLOSED correctness gate.
- [ ] No regression: existing gates green; marketplace-install path resolution verified, not assumed.

## Outcomes Rubric

- Machine-readable CORE/ADAPTER/COUPLED manifest committed
- `LOOMWRIGHT_ROOT` indirection with verified Claude-path compatibility
- Ratchet gate fails closed on new core coupling, passes on adapter coupling
- Mutation control proves the gate is not vacuous
- Declared allowances match today's measured counts (no silent grandfathering of a wrong baseline)

## Assumptions

- The 284 refs are dominated by legitimately-adapter surfaces (commands/hooks/agent frontmatter);
  classification will confirm or refute this. **Not yet verified** — if most refs sit in code that
  should be CORE, the allowance table will be large and the debt real.
- `${CLAUDE_PLUGIN_ROOT}` remains Claude Code's canonical plugin-root variable (per CLAUDE.md).

## Dependencies

- Blocks: the Cursor adapter spike (item 10 §5) — building an adapter while the core keeps
  absorbing vendor refs means porting a moving target.
- Coordinates with: `twin-remediation/09-native-flow-adoption.md` — this gate is the mechanism
  that enforces 09's "adapter, never core" constraint.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Classification is wrong; gate blocks legitimate work | Friction, gate gets disabled | Start allowances at measured counts (nothing fails on day one); tune before ratcheting down |
| Grep-based detection misses computed/derived refs | False sense of coverage | Memory `derived-pin-invisible-to-literal-grep` — also sweep data-structure consumers and hard-coded `loomwright/{agents,skills,commands}` paths |
| Gate is vacuous (matches nothing) | Silent no-op, worst outcome | Mandatory mutation control in AC |

## Status: done
- Shipped in 15.38.0 via PR https://github.com/vikashruhilgit/loomwright/pull/160 on 2026-08-31T03:55:26Z (merge commit dc03cc4)
