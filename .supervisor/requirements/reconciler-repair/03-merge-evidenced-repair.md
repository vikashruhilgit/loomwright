# 03 — Repair where the evidence is strongest: the merge the engine just made

## Problem

Nothing in the plugin reads PR merge state for the purpose of lifecycle cleanup. The only
`gh`-backed merge reads are `automate-helpers.sh`'s trusted-merge gate and `add-rule.sh`; the sole
PR-event hook is `PostToolUse[Bash]` on `gh pr create`. **There is no merge-triggered seam at
all.**

That leaves the lifecycle reconciler in a bind it cannot solve on its own. `reconcile-jobs.sh` is
**offline by construction** — `session-resume.sh` runs it on every resume, where a network
round-trip would be a latency and offline-correctness problem — so the strongest evidence a brief
could possibly have, *its PR is merged*, is exactly the evidence it is forbidden to fetch. It
falls back to weaker proxies (an automate run file recording a merge, or a requirement already
stamped done) and reports `unknown` when neither exists. Measured on this checkout: 3 of 3
in-progress briefs classify `unknown`, and even after item 01 fixes pointer resolution, a brief
whose only evidence lives on the forge stays `unknown`.

This is also where the detect-only question belongs. `reconcile-jobs.sh` deliberately never
repairs on inference, and a SessionStart hook must never auto-move a brief — an auto-move on a
false positive retires a genuinely active job. But that argument is about **weak** evidence. When
the engine has just merged a PR itself, it is not inferring anything: it performed the merge, it
holds the `pr_url`, and `gh` can confirm the state in one call. Repair belongs there, and nowhere
weaker.

`skills/automate-loop/SKILL.md` §6 already has the two seams:

- **Step 5 SYNC** — runs after a successful merge in `--auto-merge` mode. This is the exact
  moment "the PR for this task merged" is known with certainty.
- **Step 1 RECONCILE** — re-checks ground truth for any in-flight item before picking the next
  one. This is where a **safe-mode** item matters: safe mode parks items `awaiting_merge` and a
  human merges them later, so the engine never witnesses that merge. Without this second seam the
  feature would cover only `--auto-merge` runs and would silently miss the default mode.

## Goal

When the engine knows a task's PR merged, the brief for that task stops claiming to be in
progress — repaired on hard evidence, at the two points where the engine has it.

## Scope

1. **Two seams, both required, both scoped to the engine's own items.**
   - At **step 5 SYNC**, after a successful merge: repair the brief for the item just merged.
   - At **step 1 RECONCILE**, when an item previously parked `awaiting_merge` is found merged:
     repair that item's brief before picking the next one.
   Neither seam performs a global sweep. The engine repairs the briefs for items **in its own
   Queue**, identified by the `pr_url` it already recorded — never an arbitrary brief it did not
   process.

2. **Reuse `reconcile-jobs.sh --repair` rather than re-coining the move.** The lifecycle move,
   the `## Outcome` block, the escalation-aware wording and the containment guards all live there
   and must not be duplicated. What this item adds is a way to supply forge evidence to a
   reconciler that cannot fetch it — the engine passes what it already knows.

3. **The offline invariant is preserved for every other caller.** The resume path must remain
   free of forge calls. Whatever mechanism carries the evidence (an argument, an evidence file,
   an explicit online flag) must be **opt-in and off by default**, so that
   `reconcile-jobs.sh --porcelain` invoked from `session-resume.sh` behaves exactly as it does
   today. Assert this, do not merely intend it.

4. **Fail-SAFE, never gating.** This is a runtime side-effect, not a correctness gate. A failed
   `gh` call, an unreadable brief, an ambiguous match or an absent reconciler leaves the item's
   Queue outcome, `## Status`, the GATE decision and the merge decision **completely unchanged**,
   exactly like the `learning-emit` and `postmortem_dispatched` invariants. It never converts a
   merged item into a parked one, and it never blocks the next item.

5. **Evidence recorded, not asserted.** The repair is noted in `## Progress` alongside the
   existing per-item line so the run file shows what was repaired and on what basis.

## Non-goals

- **Not** moving repair into a hook, and **not** giving `session-resume.sh` a forge call. The
  detect-only posture on the resume path is deliberate and stays.
- **Not** a global sweep of `.supervisor/jobs/in-progress/`. Briefs the engine did not process
  have no engine-held evidence, and repairing them would be the inference this design rejects.
- **Not** changing the trusted-merge gate, its five conditions, or the single-executor invariant.
  This item reads merge state; it never causes a merge.
- **Not** relaxing `reconcile-jobs.sh`'s `unknown`-is-never-repaired rule. Evidence gets stronger;
  the rule does not get weaker.

## Depends on

**Item 01.** A brief whose source-requirement pointer does not parse cannot be matched to the item
the engine merged, so the repair would no-op on exactly the briefs most likely to be stranded.
Item 02 is independent of this one.

---

## Release-surface obligations

- `loomwright/skills/automate-loop/SKILL.md` — §6 steps 1 and 5 gain the seam; §1.5's helper table
  gains a row if a helper subcommand is added. The loop contract is authoritative and must not be
  restated elsewhere.
- `loomwright/commands/automate.md` — the Parameters table and prose mirror the loop; the
  agent↔command mirror is a known drift surface that no gate covers.
- `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — the `.supervisor/jobs/in-progress/` row names the
  movers; the engine becomes a third and must be listed.
- `loomwright/docs/PITFALLS.md` — the stranded-brief entry describes the offline limit; amend it
  to say where the online repair now happens.
- `CHANGELOG.md` + `loomwright/.claude-plugin/plugin.json` — version bump, `description` counts
  updated **in place**. No hook is added, so hook counts do not move.

**Honest limit to document, not to paper over:** a `/supervisor` or `/autonomous` run outside the
engine still has no online repair — nothing witnessed its merge. Those briefs remain a manual
`reconcile-jobs.sh --repair`. Say so plainly rather than implying the gap is closed everywhere.

---

## Acceptance criteria

**AC-1 (auto-merge seam).** In `--auto-merge` mode, an item whose PR the engine merged has its
brief moved `in-progress/` → `done/` with an `## Outcome` block, in the same tick.

**AC-2 (safe-mode seam).** An item parked `awaiting_merge` in a prior tick, whose PR merged
out-of-band before the next tick, is repaired at step 1 RECONCILE. Asserted with a stubbed forge
reporting the merge, because this is the path a `--auto-merge`-only implementation silently
misses.

**AC-3 (scoped to own items).** A brief in `in-progress/` that is **not** in the engine's Queue is
untouched by both seams. Asserted by fixture: two briefs present, one enqueued, one not; only the
enqueued one moves.

**AC-4 (offline invariant, negative).** `reconcile-jobs.sh --porcelain` invoked the way
`session-resume.sh` invokes it makes **no** forge call. Asserted with a `gh` stub on `PATH` that
fails loudly if executed, so the check cannot pass merely because the sandbox lacks network.

**AC-5 (fail-safe, per failure mode).** Each of these leaves the item's Queue state, `## Status`,
the GATE decision and the merge decision byte-for-byte unchanged, and the tick continues:
`gh` absent; `gh` returning non-zero; `gh` returning unparseable output; the brief unreadable;
the reconciler absent or non-executable; no brief matching the item. Asserted separately — one
aggregate "nothing broke" assertion passes vacuously if the seam never ran at all.

**AC-6 (never repairs on absence).** An item whose PR is confirmed **not** merged is not repaired,
and its brief stays in `in-progress/`. Evidence-positive only: absence of evidence is never
evidence of completion.

**AC-7 (unknown still unrepaired).** A brief that resolves but for which the engine holds no merge
evidence still classifies `unknown` and is not moved. The stronger evidence path must not become a
back door around the existing rule.

**AC-8 (idempotent).** Running the seam twice for the same item performs the move once, appends
one `## Outcome` block, and the second run is a clean no-op — matching the crash/`--resume`
discipline the run file already requires.

**AC-9 (mutation control).** Removing the step 5 call turns AC-1 red while AC-2 stays green, and
removing the step 1 call turns AC-2 red while AC-1 stays green. Without this, one seam can be
missing entirely and the suite still passes.

## Outcomes Rubric

- The repair happens where the evidence is strongest, and the weak-evidence path stays detect-only
  rather than being loosened to match.
- Both engine modes are covered; the default (safe) mode is not left as an afterthought behind an
  `--auto-merge`-only implementation.
- The resume path is still offline, and that is asserted with a stub rather than assumed.
- Every failure mode is individually asserted, and none of them can change a merge or gate outcome.
- The reconciler's move logic is reused, not duplicated — there is still one mover implementation.
- Repairs are recorded in the run file with their basis, so a reader can falsify them.
- The remaining gap (runs outside the engine) is documented rather than implied away.

## Status: done
- **Completed:** 2026-09-11T12:37:15Z
- **Brief:** loomwright-stateloop/.supervisor/jobs/done/2026-09-11-merge-evidenced-repair.md (worktree; requirement dir absent there so step 2.5 was noop_unresolved; stamped at /automate RESUME tick 7)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/210
