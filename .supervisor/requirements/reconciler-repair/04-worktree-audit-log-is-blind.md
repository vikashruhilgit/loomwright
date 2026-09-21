# 04 — The worktree audit log watches the wrong worktrees

## Problem

`docs/IMPROVEMENTS_ROADMAP.md` item #6 is marked **RESOLVED**: a `WorktreeRemove` hook was added in
v15.5.0 mirroring the long-shipped `WorktreeCreate`, so "worktree cleanup is verifiable from the
log instead of manual-only". Measured on this checkout 2026-09-10, it is not verifiable, for two
independent reasons — and nothing reads the log either way.

**(a) The population is wrong.** `.supervisor/logs/worktrees.log` holds 4 `WORKTREE_CREATED`
entries. Every one names a native Claude Code agent worktree:

```
"name":"agent-a32d58c33bef83568"
"name":"agent-ade7d003f4810b3eb"
"name":"agent-aaae9bc352896ae5e"
"name":"agent-a81149d83c7b9b82c"
```

There is **not one** `../project-*` entry — the shape Supervisor's Phase 3 creates — anywhere in
the file, and the last entry is dated 2026-06-06 while **85 briefs have completed since**. Those
are Supervisor runs, each of which creates worktrees via a shell `git worktree add`. The strongly
supported reading is that these hooks fire on Claude Code's own worktree events and **not** on a
shell `git worktree add`, which means the audit log structurally cannot see the very worktrees
FINALIZE is responsible for cleaning up. *This mechanism is inferred from the population evidence,
not yet proven — establishing it is the first task of this item, not an assumption to build on.*

**(b) The payload key does not exist.** Both hooks end with

```
python3 -c "import sys,json; print(json.load(sys.stdin).get('worktree_path',''))"
```

but across all 4 recorded payloads the keys present are exactly `session_id`, `transcript_path`,
`cwd`, `hook_event_name`, `name`. **No payload carries `worktree_path`.** The extraction has
returned the empty string for the entire life of the `WorktreeCreate` hook, and `WorktreeRemove` —
written by mirroring it — inherits the same mistake. This is the recorded `SubagentStop` payload
lesson recurring in a different hook: a hook written against an assumed payload shape rather than
an observed one.

**(c) Nothing consumes the log.** A repo-wide grep finds only the hook that writes it and four doc
rows describing it. There is no reader, so neither (a) nor (b) has ever been noticed. This is the
same class as the two parsers in item 01 and the vacuous pre-condition in
`hook-dispatch-on-pr-create.sh`: a mechanism that cannot do its job, standing because no one asks
it to.

The consequence is that Supervisor's FINALIZE step 4 worktree cleanup — a **prompt instruction**,
not code — has no verification at all. A run that dies during Phase 3 leaves worktrees behind and
the only signal is a human running `git worktree list`. The FINALIZE pre-merge gate's item 3 ("no
orphaned worktrees") checks only the merge set, so it cannot see a run that never reached FINALIZE.

## Goal

The worktree audit log records the worktrees the plugin actually creates, in a shape a reader can
correlate, and something reads it.

## Scope

1. **Measure first, then fix.** Establish empirically which events the `WorktreeCreate` /
   `WorktreeRemove` hooks fire on, and what their payloads contain, by observing a real firing —
   not by reading the hooks documentation and not by reasoning from the current log. Record the
   observed payload shape. Every later decision in this item depends on that measurement, and a
   wrong assumption here reproduces the exact defect being fixed.

2. **Log the field that exists.** Whatever identifying field the payload actually carries is what
   gets logged, in a form that lets a `CREATED` line be matched to its `REMOVED` line. If no
   correlatable identifier exists in the payload, say so and log what does — an honest partial
   record beats an empty string.

3. **Cover the Supervisor population.** If the hooks do not fire for shell `git worktree add` (as
   the evidence suggests), the plugin's own worktree lifecycle must record itself where it happens
   — the Execute Manager's create in Phase 3 step 2a and FINALIZE step 4's removal — using the
   existing fail-SAFE emitter discipline. The log must end up covering the worktrees the plugin
   is responsible for, by whichever mechanism actually works.

4. **A reader that closes the loop.** A reconciler comparing recorded-created-and-not-removed
   against live `git worktree list`, reporting orphans. Read-only and fail-SAFE, in the shape of
   the reconcilers that already exist. Where it is surfaced is an implementation choice; that it
   exists and is exercised is not.

5. **Correct the roadmap.** Item #6 is marked RESOLVED on the strength of a hook that does not
   observe the population it was added for. Restate it honestly rather than silently re-closing it.

## Non-goals

- **Not** auto-removing any worktree. A worktree can hold uncommitted work (item 05 owns that);
  an automatic removal keyed on inferred orphan status is exactly the destructive inference this
  family of reconcilers refuses. Report only.
- **Not** replacing FINALIZE's prompt-instructed cleanup with code in this item. Verification
  first; making the cleanup itself executable is a separate decision that this item's measurements
  should inform.
- **Not** adding a blocking gate. Every emitter here stays always-exit-0 per the bimodal invariant.

## Depends on

Nothing. Independent of items 01–03.

---

## Release-surface obligations

- `loomwright/docs/IMPROVEMENTS_ROADMAP.md` — item #6's RESOLVED verdict is wrong and must be
  restated with what was actually measured.
- `loomwright/docs/HOOKS.md` — the two worktree rows describe what the hooks log; correct them.
- `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — the WorktreeCreate line, and the worktree-lifecycle
  section if the recording point moves.
- `loomwright/hooks/hooks.json` — if a hook entry is added or removed the count moves, and
  `check-doc-currency.sh` fails every surface claiming the old number in the same commit. Editing
  a hook's command string in place does **not** move it.
- `CHANGELOG.md` + `loomwright/.claude-plugin/plugin.json` — version bump, counts in place.

**Honest limit to document, not to paper over:** a hard kill (SIGKILL, power loss) skips any
in-process recording, so the log can never be complete. It is a reconciliation input, not a
ledger — `git worktree list` stays the ground truth and the reader must treat it that way.

---

## Acceptance criteria

**AC-1 (payload shape is measured, not assumed).** The observed payload of a real firing is
recorded in the change — as a fixture or in committed prose. The implementation reads only fields
shown to exist in it. This is the criterion the whole item rests on.

**AC-2 (no empty-string extraction).** No hook command extracts a key absent from the measured
payload. Asserted by feeding the recorded payload through the hook command and requiring the
identifying output to be non-empty.

**AC-3 (create/remove correlate).** A recorded create and its matching remove can be paired by a
reader with no ambiguity. Asserted on fixtures containing two concurrent worktrees, so a scheme
that only works for one at a time fails.

**AC-4 (Supervisor worktrees appear).** A worktree created the way the plugin's own flow creates
one produces a log entry. Asserted against the real creation path, not a synthetic hook payload —
this is the population the log misses today.

**AC-5 (orphan detection, positive).** A worktree recorded created, not recorded removed, and
present in `git worktree list` is reported as an orphan.

**AC-6 (orphan detection, negative).** A worktree created and removed normally is **not** reported.
Asserted explicitly: a reader that flags everything is as useless as one that flags nothing.

**AC-7 (ground truth wins).** A worktree recorded created but absent from `git worktree list` is
**not** reported as an orphan — it is gone, however it went. The log is an input, never the
authority.

**AC-8 (fail-safe).** Absent log, unreadable log, malformed line, absent `git`: the reader degrades
to no verdict and exits 0. Asserted per case.

**AC-9 (read-only).** The reader creates, removes and modifies nothing. Asserted by comparing a
full directory listing and `git worktree list` before and after.

**AC-10 (mutation control).** Reverting the identifier fix turns AC-2 and AC-3 red. A fixture
corpus built from the current empty-string behaviour would otherwise pass.

## Outcomes Rubric

- The payload shape is established by observation, and the change reads only fields shown to exist.
- The log covers the worktrees the plugin actually creates, not only the ones it never cleans up.
- Something reads the log, so a future drift in it can be noticed at all.
- Orphan detection is asserted in both directions and defers to `git worktree list` as truth.
- Nothing is auto-removed; the reader reports and stops.
- The roadmap's RESOLVED verdict is corrected rather than quietly re-closed.
- Every emitter still always exits 0, and no gate was added.
- The completeness limit under hard kill is documented rather than engineered around.

## Status: done
- **Completed:** 2026-09-11T16:32:56Z
- **Brief:** loomwright-stateloop/.supervisor/jobs/done/2026-09-11-worktree-audit-log.md (worktree; requirement dir absent there so step 2.5 was noop_unresolved; stamped at /automate RESUME tick 8)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/211
