# Review of wave PR #397 (S3 wave 1, v15.123.0) — recovered locally 2026-10-06

## Status: pending (triage: each finding needs an owner decision — fix-now / follow-up / drop)

Provenance: claude-review posted nothing on #397 (twice). The same prompt + `--allowed-tools`, run locally with
`claude -p --output-format json` on #397's merge commit `f0b4b66` (gh pr comment removed so nothing was posted),
produced this review: 5 top-level turns, 0 permission denials, $4.72. That run is the evidence behind
`parallel-automate/19`. Static review — nothing below was executed.

Reviewed bd5557d5 (wave S3w1 → v15.123.0: automate-followups/32 Parts A/B/C, scrub-safe brief template, meta-sync hardening, ci-local `--last`/`--affected`).

**Overall:** solid wave. The version files are consistent: both manifests and the top CHANGELOG entry say 15.123.0. The agent, command, skill and hook counts are unchanged and still match the directories. The `## Current` enums agree across the `automate-helpers.sh` validator, `automate-loop` SKILL §3, RESULT_SCHEMAS §AUTOMATE_RUN and `commands/automate.md`, and `closeout_leftover` is in every one of them. `--affected` cannot write the pass stamp: it exits before `cached_exit` and the stamp write, and AF3 has a mutation control for that. The template `Project:` line and its restated examples now consistently use `~/…` (`supervisor-readiness` SKILL and `launch-pad.md` 3b agree). The new symlink handling in meta-sync fails closed: a dangling link or a loop is a hazard, and a non-managed symlink is never hashed or pushed.

### Findings

**1. `ci-local.sh`: `--affected` logs evict full-run logs, so `--last` stops working** (confirmed by reading)
- `open_log` (`scripts/ci-local.sh:238-254`) prunes every log in `runs/` to a single shared `keep_runs=20`, and `-affected.log` files count toward that cap.
- `--last` (`:295-300`) skips `*-affected.log` and reads only full-run logs.
- **Scenario:** do one full run, then use the `--affected` inner loop 20 times. The `runs/` pool is shared by every checkout and lane, so parallel lanes get there faster. The full log is pruned, and `--last` prints `no saved full-run log` or `stale-key` even though the current tree passed.
- **Fix:** give full and affected logs separate caps, or never evict a finished full log to make room for an affected one.
- **Missing test:** no test mixes 20 or more affected logs with one full log. The existing tests (PR), (PI) and (LA3) don't cover it.

**2. `AGENT_GUIDELINES.md:81` overstates what is kept** (doc drift)
- "Every run keeps its transcript" is not true. A cached PASS found before the slot is taken writes no log, `--list` writes no log, and only the newest 20 logs survive (fewer full-run ones, because of finding 1).
- The verdict list also leaves out `UNVERIFIED`, which `--last` does emit (exit 1, `ci-local.sh:311-312`).

**3. `session-resume.sh:446` keeps a third, drifted copy of the run-title pattern** (cross-reference / restated-pattern drift, confirmed)
- `automate_inflight_lines` uses `^#[[:space:]]*automate[[:space:]]+run[[:space:]]*:`.
- The canonical `RUN_TITLE_ERE` (`automate-helpers.sh:745`, `build-handoff.sh:60`) also accepts a leading BOM and up to 3 spaces of indent. That was hardened in v15.121.0.
- **Scenario:** a run file with a BOM is picked up by `resume-glob` and `/automate --resume`, but this SessionStart probe skips it. A PR that merged but was never closed out then shows no line at all, not even `merge state unverified`, so the gap is silent.
- **Fix:** reuse `RUN_TITLE_ERE` here and add a BOM leg next to (za)–(ze).

**4. `closeout-classify`'s `*kept*` override matches item and branch names** (confirmed by reading)
- At `automate-helpers.sh:1045`, `case "$t" in *kept*) cls=leftover` runs on the whole line, after the table has already classified it.
- **Scenario:** a clean `checked — - [x] reqs/kept-sessions.md` or `already removed (no worktree on feat/kept-x)` is turned into a leftover. That raises an owner question every time, or parks `closeout_leftover` in a non-interactive run.
- **Fix:** anchor the match on the real forms, e.g. `*"; kept "*`, `"skipped — kept worktree "*` and `*" kept)"`, and add a negative test with `kept` in a path.

**5. `closeout-others` leftover path has no test coverage** (missing branch coverage)
- The leftover summary is built with `first`, `cut -f5` and `cut -f6-`. That path also includes the `<url>` scrubbing and the fallback when `closeout-classify` prints nothing (`automate-trail.sh` around 1599-1606).
- None of it is exercised: CO1 covers only `complete`, CO2 only untouched runs, CO3 only the case with no record file.
- So the changelog's claim that the cross-run record line "carries NO PR URL" is untested on the one path where a URL could actually appear.

### Questions and smaller notes
- **Lock held by another lane:** `skipped — run lock held by …` is deliberately mapped to `leftover|lock` (`automate-helpers.sh:988`). Under `closeout-others`, though, the lock is often held by a different live lane in the same checkout. A non-interactive start then parks `closeout_leftover` for a run that is merely busy. Should this map to `run_lock_held`, or be retried later, instead?
- **CHANGELOG headline wording:** it says "symlinked non-managed files sync". Per the code, the header comments and the entry body, such symlinks are ignored (never synced and no longer refused). The behavior is right; only the headline and test 38's title mislead.
- **Probe can stall resumes:** `session-resume.sh`'s `sr_pr_state` makes up to 5 `gh` calls one after another, each with a 5 s timeout. With `gh` offline or unauthenticated, that can add about 25 s to every resume, clear or compact. It still exits 0 and stays quiet, but consider one overall deadline, or stopping after the first `unverified`.
- **Untested refusal in meta-sync:** the unreadable meta-base branch in `load_base` (`[ ! -r "$META_BASE" ]` → `base_branch_mismatch`) has no test leg, unlike the other new refusals. It would need a root guard.
- **Leftover home-path examples:** `RESULT_SCHEMAS.md:194,198` still show `/Users/<name>/myapp-…`. These are worktree-path examples in a result schema, not the brief template, but the changelog's "no home-path examples" is not fully true across the tree.
- **`current-rebuild` leaves `pause_reason` as is:** it sets `status: running` but keeps `pause_reason` (often `awaiting_go`), so `## Current` contradicts itself until the owner's ask.
- **`finalize-empty` write order:** it writes `done` before `trail-pr`, so a failed `trail-pr` is never retried. This matches the live Termination exit, but it is worth a comment.

**Not covered:** I did not run `check-token-budget.sh`. A byte-count estimate puts launch-pad plus its preloaded skills at about 42.3k against a 45.9k budget, and `worker.md` at about 8.3k against 9.1k, so no breach is expected.

execution: none — static review; this reviewer cannot run code in CI, so runtime behavior is NOT verified by this review.
