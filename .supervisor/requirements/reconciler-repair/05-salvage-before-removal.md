# 05 — Salvage before removal, mechanically

## Problem

`.supervisor/` is gitignored except five tracked files, so everything a run produces inside a
worktree — session logs, drain rounds, worker summaries, scratch — exists only in that worktree
and is destroyed when it is removed. That is the intended design for scratch state. What is not
intended is losing **uncommitted work**.

Two removal paths, with different exposure:

- **Supervisor FINALIZE step 4** uses plain `git worktree remove`, which refuses a dirty worktree.
  Safe by accident of git's default, and it turns data loss into a stalled cleanup instead.
- **`dispatch-pr-review.sh`** uses `git worktree remove --force` in its `trap cleanup EXIT`, in the
  defensive pre-add cleanup, and in the wrapper teardown. `--force` discards uncommitted changes
  without asking.

The repo already knows this hurts, because it has been paid twice. `.supervisor/salvage/` holds two
hand-made rescues:

- `worktrees-2026-09-01/` — three worktrees (`elated-curie-0e0f16`, `happy-mendel-b6f963`,
  `gifted-tereshkova-57a7c5`), each with `BASE_SHA`, `tracked.patch`, `modified/`, `untracked/`,
  and a hand-written `README.md` explaining that `tracked.patch` is against the worktree's own HEAD
  and will not apply to `main`.
- `busy-darwin-2026-08-03/` — a worktree removed 2026-09-09 carrying an unshipped reconciler and a
  `stamp-requirement-status.sh` sentinel fix that never landed on main, preserved as
  `tracked-changes.patch` with a `PROVENANCE.txt`.

That second one is the sharp edge: the salvaged content included **a fix that main still does not
have**. The rescue happened because a human thought to look before deleting. Nothing in the plugin
does.

The convention is already designed — it just isn't code. A directory per removed worktree holding
`BASE_SHA`, a patch against that base, verbatim copies of modified tracked files, verbatim
untracked files, and a README explaining recovery. Mechanizing an existing, twice-validated
convention is a much smaller task than inventing one.

## Goal

No removal path can silently discard uncommitted work: anything not committed is preserved, in the
shape the two existing rescues already use, before the worktree goes.

## Scope

1. **A salvage step that runs before removal, on every plugin-owned removal path.** It captures,
   for a worktree with uncommitted content: the base SHA, a patch against that worktree's own HEAD,
   verbatim copies of modified tracked files, and verbatim untracked files — the structure
   `worktrees-2026-09-01/` already uses, because it was written by someone recovering from this
   exact loss and it records what they needed.

2. **A README written by the tool, not by hand.** It must state the two things the existing one had
   to explain: `modified/` holds usable verbatim files and needs no patch application, and
   `tracked.patch` is against `BASE_SHA` and will **not** apply to current `main`. A salvage a
   reader cannot use is not a salvage.

3. **Nothing to salvage ⇒ no directory.** A clean worktree produces no artifact and no noise. The
   overwhelmingly common case must stay invisible.

4. **Fail-SAFE, and it must not wedge cleanup.** Salvage is a side-effect emitter: it always exits
   0, and a salvage failure never prevents the removal that was going to happen. Blocking cleanup
   on a failed backup would trade a rare data loss for a common stuck worktree — and the
   `dispatch-pr-review.sh` trap must still complete its teardown under all conditions.

5. **Ignored runtime state is explicitly out of the captured set.** Session logs, drain rounds and
   scratch under `.supervisor/` are per-checkout by design and are not "uncommitted work". Capturing
   them would bury the signal — the untracked-file capture must exclude them deliberately, and say
   so.

## Non-goals

- **Not** changing which removals happen, or when. Every current removal still occurs; this item
  only inserts a capture before it.
- **Not** auto-applying, auto-committing or auto-branching a salvaged patch. Recovery stays a
  human decision — the existing README's manual `git checkout -b … && git apply` is the contract.
- **Not** un-forcing `dispatch-pr-review.sh`'s `--force`. The trap must complete under crash and
  error conditions; the fix is to capture first, not to make teardown refusable.
- **Not** a general backup system. Scope is the moment before a plugin-owned `git worktree remove`.
- **Not** retention of the salvage directory itself — that belongs to item 06.

## Depends on

Item 04 is **recommended but not required**. Independent of items 01–03.

---

## Release-surface obligations

- `loomwright/docs/PITFALLS.md` — the stray-worktree entry tells the reader to run
  `git worktree remove --force` by hand; it must now say what is preserved and where.
- `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — the worktree-lifecycle section gains the salvage
  step; `.supervisor/salvage/` becomes a named directory with an owner rather than an ad-hoc one.
- `loomwright/skills/async-orchestration/SKILL.md` — FINALIZE step 4 is the authority for the
  Supervisor removal path and must describe the new step.
- `loomwright/skills/review-heal/SKILL.md` — the sibling-worktree lifecycle paragraph.
- `CHANGELOG.md` + `loomwright/.claude-plugin/plugin.json` — version bump, counts in place.

**Honest limit to document, not to paper over:** a hard kill skips the salvage exactly as it skips
the `trap`, so a SIGKILL can still lose uncommitted work. This narrows the window; it does not
close it.

---

## Acceptance criteria

**AC-1 (dirty tracked file preserved).** A worktree with a modified tracked file, removed through a
plugin-owned path, leaves a salvage directory containing that file verbatim and byte-identical to
its pre-removal content.

**AC-2 (untracked file preserved).** An untracked file (excluding the ignored runtime state of
AC-5) is preserved verbatim.

**AC-3 (patch and base recorded).** `BASE_SHA` names the worktree's own HEAD and `tracked.patch`
applies cleanly onto a checkout of that SHA. Asserted by actually applying it, not by checking the
file is non-empty.

**AC-4 (clean worktree ⇒ nothing).** Removing a clean worktree creates no salvage directory.
Asserted on the directory not existing, so the common path stays silent.

**AC-5 (ignored runtime state excluded).** A worktree containing only gitignored `.supervisor/`
content is treated as clean — no salvage directory. Asserted explicitly, because a naive
"copy all untracked files" implementation passes AC-2 and fails this.

**AC-6 (removal still happens on salvage failure).** With the salvage step forced to fail
(unwritable destination, absent tool), the worktree is **still removed** and the caller still exits
0. Asserted for both the FINALIZE path and the `dispatch-pr-review.sh` trap path.

**AC-7 (trap path covered).** The `--force` teardown in `dispatch-pr-review.sh` salvages before
removing. Asserted on that path specifically — it is the one that discards without asking, and an
implementation covering only FINALIZE would pass AC-1 while leaving the real exposure open.

**AC-8 (README is accurate).** The generated README names `BASE_SHA`, states that `tracked.patch`
does not apply to current `main`, and points at `modified/` first. Asserted on content, since a
README that omits the base-SHA caveat sends the reader into a failing `git apply`.

**AC-9 (no collision).** Two worktrees salvaged in the same run land in distinct directories and
neither overwrites the other.

**AC-10 (mutation control).** Disabling the salvage step turns AC-1, AC-2 and AC-7 red while AC-4
stays green — so a suite whose fixtures are all clean worktrees cannot pass with the mechanism
removed.

## Outcomes Rubric

- A convention proven twice by hand is now executed by code, in the same shape, for the same reason.
- The path that actually discards work (`--force` in the drain trap) is covered, not just the path
  that already refuses.
- Cleanup is never wedged by a failed salvage; the fail-SAFE direction is asserted, not assumed.
- Per-checkout runtime state is deliberately excluded, so the salvage holds work and not noise.
- The generated README carries the base-SHA caveat the hand-written one needed.
- The clean case stays completely silent.
- The residual hard-kill window is documented rather than implied away.

## Status: done
- **Completed:** 2026-09-11T20:11:37Z
- **Brief:** loomwright-stateloop/.supervisor/jobs/done/2026-09-11-salvage-before-removal.md (worktree; requirement dir absent there so step 2.5 was noop_unresolved; stamped at /automate RESUME tick 9)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/212
