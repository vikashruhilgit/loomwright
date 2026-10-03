# 06 — Retention without amnesia

## Problem

Nothing prunes `.supervisor/`. The only retention logic anywhere in the plugin is in
`send-telemetry.sh`, which governs what it posts, not what accumulates on disk. Measured on the
main checkout 2026-09-10:

| directory | files | size |
|---|---:|---:|
| `logs/` | 132 | 7.4 M |
| `drain-rounds/` | 729 | 2.8 M |
| `floor/` | 1 | 208 K |
| `review-dispatch/` | 28 | 112 K |
| `history/` | 16 | 84 K |
| `heal-signal/` | 6 | 16 K |
| `postmortem-dispatch/` | 4 | 16 K |

The oldest session log is dated 2026-04-26 — four and a half months. Growth is unbounded and there
is no policy, so today the answer to "what can be deleted?" is "nobody has decided".

**But the naive fix is worse than the problem, and this is the real content of this item.** Three
things in that table look like garbage and are not:

1. **`review-dispatch/` markers are idempotency guards, durable *by design*.**
   `dispatch-pr-review.sh` writes a per-PR marker so the same PR is never re-dispatched, and
   `PITFALLS.md` records that a stale worktree is deliberately left on disk rather than
   force-removed *because the marker preserves idempotency*. Deleting a marker re-arms
   re-dispatch for that PR. A retention sweep that treats them as old files would silently
   re-enable duplicate drains.

2. **Session logs are load-bearing input to four consumers.** `build-insights.sh`,
   `build-loop-evidence.sh`, `build-floor.sh` and `curation-status.sh` all read
   `.supervisor/logs/*.jsonl`.
   `curation-status.sh` in particular derives its SessionStart cadence nudge from *the count
   of session logs accumulated since `/dreaming` and `/insights` last ran* — so deleting old
   logs does
   not merely shrink a directory, it **falsifies the signal that tells you your recorded knowledge
   has gone stale**, in the direction of "everything is fine". A retention policy that quietly
   resets the cadence counter is an amnesia machine.

3. **Five files under `.supervisor/` are tracked and committed** — `memory/LESSONS.md`,
   `memory/PROJECT_MEMORY.md`, two provenance sidecars, and `postmortem/results.jsonl`. These are
   the Twin's accumulated judgment, deliberately un-ignored by the `/setup memory` managed block.
   They are the single most valuable thing in the directory and the least distinguishable from the
   rest by age.

So this is not a cleanup task. It is a question of **which of these artifacts are evidence and
which are exhaust**, answered per directory, with the destructive action gated behind that answer.

## Goal

A stated retention policy, one that names what each directory is for and what consumes it, and a
tool that enforces it — reporting by default and deleting only what has been explicitly classified
as exhaust.

## Scope

1. **Classify every directory under `.supervisor/` before deleting anything from it.** Each gets a
   recorded verdict: *tracked* (never touched), *guard* (durable by design, never aged out),
   *consumed* (an input to a named consumer — retention must account for that consumer), or
   *exhaust* (safe to age out). The classification is the deliverable; the sweep is downstream of
   it. A directory with no verdict is not swept.

2. **Report-only by default; deletion is explicitly opted into.** The default invocation prints
   what it *would* remove, per directory, with the classification and the reason. Deleting requires
   a distinct flag. This is an irreversible operation on gitignored data with no remote copy —
   dry-run-by-default is the floor, not a nicety.

3. **Consumers are accounted for, not ignored.** For anything classified *consumed*, the policy
   states how the consumer stays honest after a sweep. For the curation cadence specifically, the
   count it derives must not silently reset — either the sweep preserves what the counter needs, or
   the counter is re-based explicitly and visibly. Deciding this is in scope; silently breaking it
   is not.

4. **Never touch the five tracked files, under any flag.** Asserted, not merely intended.

5. **Fail-SAFE.** Always exits 0. An unreadable directory, an unparseable file, an absent tool
   degrades to "not swept", never to a broader delete.

## Non-goals

- **Not** deleting `review-dispatch/` markers on an age rule. If they are ever to be reclaimed it is
  on a *PR-closed* rule with the marker's own semantics, and that is a separate decision — out of
  scope here beyond classifying them as guards.
- **Not** deleting anything under `.supervisor/memory/` or `.supervisor/postmortem/`.
- **Not** touching `.supervisor/salvage/` in this item. Salvaged content is rescued uncommitted
  work; retention for it presupposes item 05's decisions about what lands there.
- **Not** running automatically from a hook. A destructive sweep on session start is precisely the
  wrong trigger. It is an operator-invoked tool.
- **Not** compressing or archiving as a substitute for deciding. Moving exhaust into a tarball
  postpones the classification rather than making it.

## Depends on

Item 05 — only so that `salvage/` has an owner and known contents before retention considers it.
Independent of items 01–04.

---

## Release-surface obligations

- `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — the `.supervisor/` directory table gains the
  retention classification per directory; this is where the policy lives.
- `loomwright/docs/OBSERVABILITY.md` and `loomwright/docs/TELEMETRY.md` — anything describing the
  session-log corpus as complete becomes conditional once a sweep exists.
- `loomwright/docs/PITFALLS.md` — a new entry: the two artifacts that look deletable and are not.
- `CHANGELOG.md` + `loomwright/.claude-plugin/plugin.json` — version bump, counts in place. If a
  command is added, the command count moves and `check-doc-currency.sh` fails every surface
  claiming the old number in the same commit.

**Honest limit to document, not to paper over:** deletion here is irreversible — this data is
gitignored and exists in exactly one place. No sweep can be undone, and the tool should say so at
the point of use rather than only in a doc.

---

## Acceptance criteria

**AC-1 (tracked files are untouchable).** With every aggressive flag the tool accepts, the five
tracked files are unmodified and present. Asserted by content hash before and after, for each file
individually.

**AC-2 (guards are not aged out).** A `review-dispatch/` marker older than any threshold the tool
supports is **not** removed. Asserted with an artificially aged fixture, because a marker old
enough to look stale is exactly the one that is still load-bearing.

**AC-3 (report-only default).** The default invocation deletes nothing. Asserted by a full
before/after directory listing, not by parsing the tool's own claim about what it did.

**AC-4 (deletion requires the explicit flag, and works).** With the flag, files classified exhaust
are removed and files in every other class are not. Both halves asserted — a tool that deletes
nothing passes AC-3 vacuously.

**AC-5 (consumer honesty).** After a sweep, the curation cadence signal does not silently report a
smaller backlog than the truth. Whichever resolution the policy takes — preserve the input, or
re-base the counter visibly — is asserted directly against `curation-status.sh`'s output. This is
the criterion that distinguishes a retention policy from an amnesia bug.

**AC-6 (unclassified ⇒ untouched).** A directory under `.supervisor/` with no recorded
classification is never swept, including one that did not exist when the policy was written.
Asserted with a novel directory name, so the tool fails closed against future additions.

**AC-7 (fail-safe).** Unreadable directory, unparseable file, absent `jq`/`git`: exit 0, nothing
deleted, the condition reported. Asserted per case.

**AC-8 (no hook invocation).** A grep over `hooks.json` finds no invocation of the sweep. Pinned
positively so a future change that wires it into a hook fails the suite.

**AC-9 (mutation control).** Removing the tracked-file exclusion turns AC-1 red; removing the guard
exclusion turns AC-2 red. Both classes are otherwise indistinguishable from exhaust by age alone,
which is exactly why they need controls.

## Outcomes Rubric

- Every directory has a recorded verdict, and the verdict — not the file's age — decides its fate.
- The two artifacts that look like garbage and are not are excluded, with assertions that would
  catch their removal.
- The curation signal survives the sweep honestly, or is re-based visibly; it is not allowed to
  quietly under-report.
- The destructive path is opt-in, and the read-only default is asserted against the filesystem
  rather than the tool's own report.
- An unclassified directory is skipped, so the policy fails closed as the plugin grows.
- Nothing runs the sweep automatically.
- The irreversibility is surfaced where an operator will actually see it.

## Status: done
- **Completed:** 2026-09-12T11:37:00Z
- **Brief:** loomwright-stateloop/.supervisor/jobs/done/2026-09-12-retention-without-amnesia.md (worktree; requirement dir absent there so brief-repair reports no in-progress match — expected; stamped at /automate RESUME tick after PR #213 merged 2026-09-12T10:52:02Z)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/213
