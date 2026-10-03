# Skills-layer portability probe — does the largest prose block port for free?

> Story for `twin-remediation/10-harness-portability.md`. Item 10 §6 deferred prompt-layer
> portability as "proposal only, do not execute" on the assumption it was the expensive part.
> Vendor capability verified 2026-08-22 makes that assumption testable **cheaply and now** — and
> the answer changes the cost of the whole adapter, so it should run BEFORE the adapter is built.

## Problem

The prompt layer is the bulk of Loomwright's non-portable surface: agents 7,039 + commands 6,547
+ **skills 14,804** lines (measured 2026-08-22). Item 10 treats porting ~27k lines of prose as
the reason to defer full portability and to demand a falsifiable spike first.

But `skills/` is the layer item 10 itself identifies as "the seam" — the shared protocol bodies
already live there rather than in harness-specific wrappers. And per Cursor's official skills
documentation (fetched 2026-08-22), Cursor discovers skills from `.agents/skills/`,
`.cursor/skills/`, **and explicitly `.claude/skills/` / `~/.claude/skills/`** for
Claude/Codex compatibility, using a `SKILL.md` with required `name` + `description` frontmatter —
the same shape Loomwright already authors. Codex likewise consumes `SKILL.md` skills.

If our 41 skills load and execute unmodified under Cursor, the single largest line-count in the
"expensive to port" argument collapses, and the adapter is a small job. If they do not, the
adapter's scope roughly triples. **We are currently sequencing a multi-week decision on an
unmeasured assumption**, and the measurement is hours of work.

## Goal

Replace the assumption "the prompt layer is expensive to port" with evidence, before the adapter
spike (item 10 §5) commits to a scope.

## Scope

1. **Frontmatter conformance audit.** Compare all 41 `skills/*/SKILL.md` frontmatter against
   Cursor's and Codex's documented required/optional fields. Report per-skill PASS / NEEDS-EDIT
   with the specific offending field — not a summary percentage.
2. **Body-portability classification.** Classify each skill: PORTABLE (pure protocol prose),
   COUPLED (names Task-spawn, `${CLAUDE_PLUGIN_ROOT}`, `hooks.json`, or a Claude-only tool), or
   ADAPTER (legitimately Claude-specific and should stay in the adapter). Publish counts and lines.
3. **Live load test — the actual falsification.** Load the skills into a real Cursor session (and
   Codex if cheap) and verify: discovery, invocation by name, and that a skill body which shells
   out to a core script actually runs. Documentation saying a directory is read is **not** evidence
   that our skills work there.
4. **Report the delta honestly.** What loaded, what silently did not, what loaded but misbehaved.
   A probe that only reports success is incomplete evidence (item 10's own standard).

## Non-goals

- No edits to skill bodies to make them pass — this measures the gap, it does not close it.
- No adapter construction. That is item 10 §5, informed by this result.
- No decision to drop or degrade Claude Code support.

## Acceptance criteria

- [ ] Given all 41 skills, when the frontmatter audit runs, then each is reported PASS or
      NEEDS-EDIT with the specific field named.
- [ ] Given the body classification, when published, then every skill is PORTABLE / COUPLED /
      ADAPTER with line counts, and the totals reconcile to the 14,804-line measurement.
- [ ] Given a real Cursor session, when skills are discovered from `.claude/skills/`, then the
      result is recorded as VERIFIED or REFUTED **from an observed run**, with the Cursor version
      and date recorded — never from documentation alone.
- [ ] Given a skill whose body invokes a core script, when invoked under Cursor, then whether the
      script executed is reported as observed fact.
- [ ] Any capability that could not be exercised is labeled **UNVERIFIED**, not assumed working
      (read-before-write rule, `AGENT_GUIDELINES.md`).
- [ ] A go/no-go recommendation for item 10 §5's scope, with the number that drives it.

## Outcomes Rubric

- Per-skill frontmatter conformance, not an aggregate
- PORTABLE/COUPLED/ADAPTER classification reconciling to total lines
- Live-run verification with harness version + date, degradations enumerated
- Explicit UNVERIFIED labels where a claim could not be exercised
- Stated impact on item 10 §5's scope

## Assumptions

- Cursor's `.claude/skills/` compatibility is documented as of 2026-08-22 but **behavioral
  fidelity is UNVERIFIED** — that is precisely what this story tests.
- Access to a Cursor install is available. If not, the story degrades to scope items 1–2 (static
  audit) and item 3 is deferred with that stated plainly rather than inferred.

## Dependencies

- Blocks: `twin-remediation/10-harness-portability.md` §5 (adapter spike) — its scope depends on
  this result.
- Related: the vendor-coupling ratchet story (same batch) — this probe's COUPLED classification
  feeds that story's CORE/ADAPTER/COUPLED manifest.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| "It loaded" is mistaken for "it worked" | False green; adapter scoped too small | AC requires observing a core script actually execute, not just discovery |
| Cursor changes skill discovery between probe and adapter build | Result rots | Record harness version + date; re-verify at adapter build time |
| Probe scope creeps into fixing skills | Becomes the port instead of measuring it | Explicit non-goal; no skill-body edits |
