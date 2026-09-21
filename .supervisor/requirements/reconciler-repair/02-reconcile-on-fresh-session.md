# 02 — A fresh session reconciles too

## Problem

`reconcile-jobs.sh` is wired at SessionStart through `session-resume.sh`, which classifies
in-progress briefs rather than asserting they are mid-run. But the hook only reaches that code on
`resume`, `clear` and `compact`. A **fresh** session — `source=startup`, which is what starting the
next piece of work actually is — hits a dedicated arm in the `case "$SOURCE"` dispatch that runs
the curation nudge and `exit 0`s before the reconcile block is ever evaluated.

So the reconciler fires on the path where the operator is already returning to known context, and
does not fire on the path where they have none. A brief stranded by a session that died is
therefore invisible to every fresh session that follows it — which is precisely how
`2026-09-05-floor-ui-redesign.md` (PR #185, merged 2026-09-05) sat unnoticed for five days.

The obvious fix is wrong and the file says so. The `startup)` arm exists as a **dedicated** arm
rather than a widened shared gate for a stated, load-bearing reason (`session-resume.sh` header,
SEAM NOTE): widening the gate to include `startup` would expose every fresh session in every
plugin-active repo to the observability probe's `curl`, the desktop notification, the
prior-session header, Sections 1–5, the unconditional recovery hints, and the house-rules nudge.
That is a large, noisy behaviour change on the most frequent event the plugin sees.

Two further constraints follow from where the arm sits. Because it `exit`s from inside the case —
above the shared `[ ! -d ".supervisor" ]` bail and above the emit at the bottom — anything it
calls must carry its **own** `hookSpecificOutput` envelope (a bare `printf` is dropped or shown as
raw JSON), and must be **defined above** the case (every other helper is defined below it, which
would make the call `rc=127`, swallowed silently).

## Goal

A fresh session learns that a brief is stranded, and learns nothing else it does not already get —
same envelope discipline, same `.supervisor/` gating, same silence when there is nothing to say.

## Scope

1. **Extend the dedicated `startup)` arm. Do not widen the shared `resume|clear|compact` gate.**
   The arm gains the stranded-brief classification and nothing else from Sections 1–5. The rules
   nudge's firing surface stays unchanged and still does not fire on startup.

2. **Reuse `reconcile-jobs.sh --porcelain`.** It is offline by construction and measured at ~0.9s
   over a 72-brief corpus, which is what makes it admissible on the startup path. It stays
   offline: **no forge call may be introduced on this path**, and the classification is read
   through the existing porcelain contract rather than re-derived.

3. **Report only what the disk can evidence, and only when there is something.** A repo with no
   in-progress briefs, or none classified stranded, produces output byte-for-byte identical to
   today. An absent, unreadable or silent reconciler degrades to silence — never to a claim.

4. **Bounded and quiet.** This fires on every fresh session in every plugin-active repo, so the
   addition is a small number of lines naming the stranded briefs and their evidence, under the
   arm's own envelope, well inside the SessionStart `additionalContext` cap. It carries an
   env-block opt-out mirroring the rules and curation nudges, and a 24h mtime-windowed debounce
   marker mirroring the same two, so a repo with a long-lived strand is not nagged every session.

5. **Classification only.** The line reports; it does not repair, and it does not tell the reader
   the work is finished. `unknown` means unverified and must be presented as such.

## Non-goals

- **Not** running `--repair` from a hook. An auto-move keyed on inferred evidence retires a
  genuinely active job on a false positive; the detect-vs-repair split is deliberate and stays.
- **Not** widening the shared gate, and not moving any of Sections 1–5 onto the startup path.
- **Not** adding a hook entry. This changes the body of a script an existing SessionStart entry
  already runs, so the `hooks.json`-derived counts do not move.
- **Not** introducing a network call, a `gh` invocation, or anything else that could make session
  startup slow or offline-incorrect.

## Depends on

**Item 01 (`01-brief-pointer-extraction.md`).** Ordering matters and is not merely tidy: two of the
three briefs on this checkout classify `unknown` today because their pointer does not parse. Making
the classification fire on every fresh session *before* the extractor is fixed would surface those
false `unknown`s to every new session — turning a silent gap into recurring noise, which is the
failure this file's own SEAM NOTE argues against. Land 01 first.

---

## Release-surface obligations

- `loomwright/docs/HOOKS.md` — the SessionStart row states the startup path is silent and
  enumerates what runs on resume/clear/compact. That row becomes wrong the moment this lands and
  must be updated in the same change.
- `loomwright/scripts/session-resume.sh` — the header SEAM NOTE is the authority for why the arm
  is dedicated. Extend it to cover the new call; do not leave it describing only the curation
  nudge.
- `loomwright/docs/PITFALLS.md` — the stranded-brief entry says to run the reconciler by hand;
  amend it to say when the reader will now be told automatically.
- `CHANGELOG.md` + `loomwright/.claude-plugin/plugin.json` — version bump, `description` counts
  updated **in place**.
- **Citations:** new `file.ext:N` references in committed prose need `` [pins: `<literal>`] `` or a
  descriptive anchor.

**Honest limit to document, not to paper over:** the startup path stays offline, so a brief whose
only evidence of shipping is on the forge still classifies `unknown` here. A fresh session will
report it as unverified, not as stranded. Say so; do not close the gap by adding a `gh` call to a
hook.

---

## Acceptance criteria

**AC-1 (fires on startup).** With `source=startup` in a repo holding a brief the reconciler
classifies stranded, the hook emits a valid `hookSpecificOutput` JSON envelope naming that brief.
Asserted by parsing the emitted JSON, not by grepping raw stdout — a bare `printf` from this arm
is exactly the failure mode the SEAM NOTE warns about.

**AC-2 (silent when there is nothing).** With `source=startup` in a repo with no in-progress
briefs, output is **byte-for-byte identical** to the pre-change behaviour. Asserted against a
captured baseline, not by eyeballing that it "looks the same".

**AC-3 (no `.supervisor/` ⇒ no output).** In a repo with no `.supervisor/` directory, `startup`
emits nothing. The arm exits above the shared bail, so it owns this check itself.

**AC-4 (the gate is not widened).** With `source=startup`, none of the following occur: the
observability probe's `curl`, the desktop notification, the prior-session header, any of Sections
1–5, the recovery hints, the house-rules nudge. Asserted per item, because a single "no extra
output" assertion passes vacuously if the arm silently failed.

**AC-5 (resume path unchanged).** With `source=resume`, behaviour is unchanged, including the
existing in-progress classification and the neutral fallback when the reconciler is unavailable.

**AC-6 (helper is reachable).** The function the `startup)` arm calls is defined **above** the
case. Pinned by an assertion that the arm's exit status is not 127 — the rc a
defined-below-the-case helper would produce, which the hook's always-exit-0 discipline would
otherwise swallow without trace.

**AC-7 (offline).** No forge CLI invocation occurs on the startup path. Asserted with a `gh` stub
on `PATH` that fails loudly if called, so the check cannot pass merely because the sandbox has no
network.

**AC-8 (fail-safe).** An absent, non-executable, erroring or silent `reconcile-jobs.sh` leaves
startup silent and the hook exiting 0. Each degradation asserted separately.

**AC-9 (opt-out and debounce).** The env-block opt-out suppresses the line permanently; the 24h
marker suppresses it within the window and allows it after. Both asserted, including that the
marker does not suppress the *first* sighting.

**AC-10 (mutation control).** Reverting the `startup)` arm's new call turns AC-1 red while AC-2
through AC-5 stay green. Without this, a suite whose fixtures never contain a stranded brief would
pass with the mechanism deleted.

## Outcomes Rubric

- The reconciler now fires on the path where the operator has no context, which is the case it was
  always for.
- The dedicated-arm seam is respected: nothing else moved onto the startup path, and each excluded
  behaviour is asserted individually rather than in aggregate.
- The startup path is still offline, still fail-safe, still always exit 0, and adds no hook.
- The new line reports classification and never asserts completion; `unknown` still reads as
  unverified.
- The envelope and helper-placement traps the file's own header names are both covered by
  assertions that would catch them.
- The suite is mutation-controlled, so it cannot pass with the change removed.
- Every doc surface that describes the startup path as silent is corrected in the same commit.
- The remaining offline limit is documented rather than closed with a network call.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-11T09:33:12Z
- **Brief:** loomwright-stateloop/.supervisor/jobs/done/2026-09-11-reconcile-on-fresh-session.md (worktree; requirement dir absent there so step 2.5 was noop_unresolved; stamped at /automate RESUME)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/209
