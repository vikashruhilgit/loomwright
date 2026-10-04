# 09 — Fewer full suite runs per lane: one per push, a fast affected-only check in between, no re-run to read output

## Status: pending

## Depends on
none

## Touches
scripts/ci-local.sh
scripts/test-ci-local.sh
AGENT_GUIDELINES.md
loomwright/agents/worker.md
changelog.d/parallel-automate-09-ci-local-fewer-full-runs.md

## Problem
In S1 v2 each lane's lead session started `ci-local.sh` **6 times**, for **2 pushes (v2-a)** and **4 pushes
(v2-b)**, not counting the workers' own runs. The guideline asks for one full run before every push
(`AGENT_GUIDELINES.md` §"Pre-push: one command"). The extra runs had two visible causes in the lane logs:
- **re-running only to see the output** ("Rerun local CI capturing output to a log"), because a run's output is
  not kept anywhere once the tool call returns;
- **full runs used as an inner-loop check** after a small fix, where the touched suite alone would have answered.

At 5–10 lanes every avoidable full run is CPU the other lanes wait for (item 08 makes them wait fairly; this item
makes them wait less).

## Goal
A lane runs the full suite **once per push**, reads any earlier run's result from a saved log, and uses a fast,
mapped, affected-only check while iterating.

## Scope
1. **Every run keeps its output:** `ci-local.sh` writes the full transcript to
   `<shared state dir>/runs/<key>-<timestamp>.log` (item 08's location when present, else the git-common-dir) and
   prints the path first and last. `ci-local.sh --last` prints the newest log for the current tree key (and says
   PASS / FAIL / stale-key). Logs are pruned to the newest 20 per repo.
2. **`ci-local.sh --affected`:** maps the working tree's changed files (against `origin/main`'s merge-base,
   untracked included) to the suites that cover them and runs only those, through the same pool runner. The map:
   a changed `loomwright/scripts/<x>.sh` ⇒ `loomwright/scripts/test-<x>.sh` when it exists; a changed test file ⇒
   itself; a changed root `scripts/<x>.sh` ⇒ `scripts/test-<x>.sh`; plus every `check-*.sh` gate `ci.yml` names
   (they are cheap). A changed file with no mapped suite is listed as "not covered by --affected". `--affected`
   NEVER writes a pass stamp and always ends with: `affected-only — not a pre-push gate; run ci-local.sh before
   pushing`.
3. **Guideline and worker prompt:** `AGENT_GUIDELINES.md` §"Pre-push" and the worker prompt's test step say:
   while iterating use `--affected` (or the one suite); before each push, one full `ci-local.sh`; to see a past
   result use `--last`, never a re-run. (The worker prompt is shipped plugin text: it names "the project's
   pre-push command", and this repo's CLAUDE.md maps that to `scripts/ci-local.sh` — no repo-local path in
   shipped code.)
4. **Tests:** `--affected` picks the mapped suite for a changed script, lists an unmapped change, never stamps;
   `--last` finds the newest log for the key and reports stale when the tree changed; log pruning keeps 20.

## Non-goals
- No change to the gate list or to the remote `ci` job; the full run before a push stays mandatory.
- No dependency analysis beyond the file-name map (honest limit: a change that breaks a suite with a different
  name is caught by the full run before the push, not by `--affected`).

## Acceptance criteria
- A lane that pushes twice runs the full suite at most twice (plus any run after a failure), measured in S2.
- `--affected` on a one-script change runs that script's suite plus the cheap gates, in a fraction of a full run.

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch, `<passed>/<total>` and `SKIP` counts.
2. **Unchanged path:** `ci-local.sh` with no flag behaves exactly as before (same gates, same stamp rule).
3. **Running system:** paste `--affected` on a real one-file change, its wall-clock, and `--last` afterwards.
4. **A failure this must catch:** make `--affected` write a stamp ⇒ the "never stamps" test fails.
5. **Rollback:** `git revert`.

## Verified premises (re-check before starting)
- `AGENT_GUIDELINES.md` lines on "Before every push, run `bash scripts/ci-local.sh`" and "For a quick inner-loop
  check … run the one suite you touched" exist (checked 2026-10-04).
- Push and run counts come from the v2 lane logs (`git push` and `ci-local.sh` in the lead session's Bash calls).

## Evidence
S1 v2 lane logs (`ai-agent-manager-lanes-v2/v2-{a,b}/.supervisor/s1h-lane.log`), S1 run record.
