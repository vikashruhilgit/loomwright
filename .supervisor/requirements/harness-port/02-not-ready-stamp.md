# 02 — Not-ready stamp honoured by intake (`proposed` / `parked` skip)

## Status: pending

## Problem
`loomwright/scripts/automate-helpers.sh` `is_done()` matches only `^## Status:[[:space:]]*done(_with_escalation)?\b`;
`resolve_folder` and `resolve_backlog_dir` enqueue **every** other `*.md`. The intake is a denylist on `done`, not an
allowlist on "ready" — there is no marker a queue reads as ready, so a worker (item 01 rule (b)) or a human writing
`## Status: proposed` / `## Status: parked` gets the file **picked and run**. The only working skip today is the
`proposed/` subfolder (`"$dir"/*.md` does not recurse), which `/propose` relies on and `commands/propose.md`
documents. Without this item, "parked ⇒ skipped" is false and a design-only story would be executed.

## Goal
A `## Status: proposed` or `## Status: parked` stamp is a real skip for folder and backlog-dir intake, with the
subfolder convention preserved; run-file resume semantics are untouched.

## Scope
1. **`loomwright/scripts/automate-helpers.sh`:** add `is_not_ready() { grep -qE '^## Status:[[:space:]]*(proposed|parked)\b' "$1" 2>/dev/null; }`
   beside `is_done`, with a header comment stating it is used by `resolve_folder` and `resolve_backlog_dir` ONLY
   and MUST NOT be folded into `is_done` (shared with `resume-glob`, whose run files use `running|paused|done` —
   decision H2). Call it in both loops: `is_done "$f" && continue; is_not_ready "$f" && continue`. Update the
   usage lines at the top of the file (`resolve-folder … # §2 list *.md not "## Status: done"` → "… not done and
   not proposed|parked"). `resolve_backlog` (the checklist-line parser) is unchanged — a `- [ ]` line names a path,
   not a status; document that the pointed-to file's stamp is honoured only on the dir-fallback path, OR add the
   same file-stamp check when the payload resolves to an existing file (implementer's call; record which).
2. **`loomwright/scripts/test-automate-helpers.sh`:** a fixture dir with five files — `## Status: proposed`,
   `## Status: parked`, `## Status: done`, `## Status: done_with_escalation`, no stamp — asserting `resolve-folder`
   prints exactly the unstamped file; the same for `resolve-backlog <missing-doc>` (dir fallback); and that
   `resume-glob` over a dir containing a run file with `## Status: paused` STILL prints it (the negative control
   that proves `is_done` was not widened). **Mutation control:** with `is_not_ready` returning 1 unconditionally,
   the proposed/parked assertions must fail. Run under `bash` (memory `bash-tool-runs-zsh-not-bash`).
3. **`loomwright/skills/automate-loop/SKILL.md` §2 (source resolution):** one paragraph: two skips exist — the
   `proposed/` subfolder (not scanned) and the `## Status: proposed|parked` heading stamp (scanned, skipped);
   `## Status: done` / `done_with_escalation` remain the terminal stamps. A skipped-by-stamp file is NOT checked off
   and does NOT count toward `## Status: done` of the run (it simply is not in the Queue).
4. **`loomwright/commands/propose.md`:** one-sentence cross-reference under the "Promote" paragraph: a file may
   also be kept un-runnable in place with `## Status: proposed`; moving out of `proposed/` AND removing/changing the
   stamp are both needed to run it.
5. **Docs:** CHANGELOG paragraph; version bump.

## Non-goals
No change to `is_done`, `resume-glob`, `queue-checkoff`, `gate-eval`, or any `## Status: done` semantics. No new
status vocabulary beyond `proposed|parked`. No recursion into subfolders.

## Acceptance criteria
- Fixture run: `bash loomwright/scripts/automate-helpers.sh resolve-folder <fixture>` prints only the unstamped file;
  `resume-glob` over a `## Status: paused` run file still lists it.
- Mutation control fails as specified.
- `grep -n 'is_not_ready' loomwright/scripts/automate-helpers.sh` shows the definition + exactly two call sites
  (`resolve_folder`, `resolve_backlog_dir`) — and `grep -n 'is_done()' …` shows the regex UNCHANGED vs
  `git show origin/main:loomwright/scripts/automate-helpers.sh`.
- `automate-loop/SKILL.md` §2 and `commands/propose.md` carry the two-skip wording.
- Full test loop + root checks green.

## Verified premises (re-check before starting)
- `automate-helpers.sh`: `is_done` definition and comment (reads "Authority for what the completion tail writes here:
  skills/self-heal-advisory/SKILL.md step 2.5"); `resolve_folder`, `resolve_backlog`, `resolve_backlog_dir`,
  `resume-glob` bodies; header usage lines for `resolve-folder` / `resume-glob`.
- `commands/propose.md` §5 "Writes a directory contract" and the "Promote" paragraph.
- `docs/RESULT_SCHEMAS.md` §AUTOMATE_RUN: run-file `## Status: running | paused | done` vocabulary.
