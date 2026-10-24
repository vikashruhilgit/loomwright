#!/usr/bin/env bash
# automate-trail.sh — the `/automate` engine's post-park lifecycle MUTATORS.
# PROTOCOL AUTHORITY: `skills/automate-loop/SKILL.md` §6 "Trail PR after merge
# and at run end" (and §1.5's rows for each subcommand). trail-pr is called only
# by closeout (after its merge evidence gate), at `## Status: done`, and on a
# skip/abandon check-off — never at a park (§14's lane wave end and
# `lane-remove --abandon` run it inside a parked lane; the same gate); its _evidence_gate drops a
# done-stamped requirement / done brief whose PR is not merged regardless. Dispatched from
# `automate-helpers.sh` (`exec bash "$(dirname "$0")/automate-trail.sh" <subcmd>`)
# so the helper itself stays read-only toward git; THIS script is the carve-out.
#
# SCOPE OF ITS MUTATIONS (the whole list — anything else is a bug):
#   * `trail-pr` commits ONLY this run's explicit trail paths, from a temporary
#     `git worktree` off fresh origin/<default branch> (or off this run's open
#     trail branch), pushes ONLY to `chore/<run_id>-trail-<n>` (never forced),
#     opens/reuses ONE PR via `gh pr create`, stages the trail-branch-tip blobs
#     of every path that branch changes in the primary checkout's index (see
#     "Checkout contract" below), and records them in the gitignored
#     `<run_id>.trail-staged` beside the run file.
#   * BRANCH MODE (`setup-memory.sh mode` = `on <branch>`; SKILL §"Branch mode"): `trail-pr`
#     opens NO PR and creates no trail worktree — it runs `meta-sync.sh push --paths-from` with
#     the same evidence-gated candidate list (the gitignore drop skipped), and on failure appends
#     one `meta-push FAILED:` Progress line, notifies, and writes the gitignored
#     `<run_id>.meta-push-failed` marker; `trail-unstage` and closeout's re-stage are skipped.
#     Mode off ⇒ everything below is unchanged.
#   * `trail-unstage` only drops this run's trail-path index entries
#     (`git restore --staged -- <path>`); working copies are never touched.
#   * `trail-gate` (PICK) reads this run's open trail PRs; only when none is
#     open does it run closeout's step-4 sync (_sync_primary: re-stage the
#     landed recorded trail blobs, `git checkout <base>`, `git pull --ff-only`).
#   * `closeout` removes ONLY this PR's head-branch worktrees (HEAD == the PR's
#     headRefOid AND clean after `worktree-salvage.sh` AND its gitignored runtime
#     content salvaged + verified — `--ignored` verdict `ignored: ok`) and that local branch
#     (`git branch -D`, only when its tip == the PR's headRefOid), switches the primary to the base branch
#     and `git pull --ff-only`s it (first re-staging the recorded trail blobs
#     that landed upstream — index only), appends the requirement stamp, checks the
#     Queue item off, and calls trail-pr. It NEVER commits in the primary.
#   * `finalize-empty` (under `run-lock.sh --owner automate-finalize:<run_id>`)
#     rewrites ONLY a closed-out run's `## Status: paused` → `done` and its
#     `## Current` `pause_reason` → `null` (`current-set` on a staged copy, then
#     one validated runfile-write), appends
#     two Progress lines, calls trail-pr `--reason done`, appends ONE
#     `<ts> process registry: <summary>` Progress line (`proc-registry.sh
#     summary`, read-only) then ONE `<ts> sweep (dry run): <summary>` Progress
#     line (a DRY sweep — never `--apply`) and — branch mode off — trail-unstage
#     for that run. Nothing else.
#   * `closeout-others` runs `closeout` (and, branch mode off, `trail-unstage`)
#     for OTHER runs' merged in-flight items and appends ONE record line to the
#     --record run file. Nothing else.
#   * `sweep` (dry run by default) is read-only; ONLY with `--apply` it runs
#     `git worktree remove` (never `--force`) on a plugin-made linked worktree and
#     `git branch -D` on a local branch, each ONLY when closeout's own squash-safe
#     rule holds (newest PR MERGED AND tip == its headRefOid), the worktree is
#     clean, no live process has its cwd there, and `worktree-salvage.sh
#     --ignored` printed `ignored: ok`. App-made / lane / unknown-origin worktrees
#     are reported, never touched. Nothing else.
#   * Neither subcommand merges anything (the sole merge executor is `automate-helpers.sh
#     gate-eval`, SKILL §11), trail-pr never calls `run-lock.sh` (closeout takes it around steps 3–7);
#     neither runs `git reset`,
#     `git stash`, `git add -A`/`git add .`, or a force push.
#
# Modules (sourced in this order from automate-trail.d/):
# - sidecar.sh: sidecar-check — sidecar_check (its python checker and key tables).
# - trail-pr.sh: trail-pr — trail_cleanup, _in_list, _trail_is_run_draft, _trail_candidates,
#     _done_prs, _outcome_prs, _gate_keep, _evidence_gate, _trail_owned, _stage_tip,
#     _branch_mode, _trail_meta_fail, _trail_meta_push, trail_pr.
# - stage-sync.sh: trail-unstage, trail-gate — trail_unstage, trail_gate, _restage_landed,
#     _restore_prior, _sync_primary.
# - closeout.sh: closeout — _run_lock_in, co_release, _co_current, _co_stamped, closeout.
# - finalize.sh: finalize-empty, closeout-others — fe_release, _fe_ineligible,
#     _in_lane_clone, _lane_run_id, finalize_empty, closeout_others.
# - sweep.sh: sweep — _sw_line, _sw_rule, _sw_live_read, _sw_live, _sw_plugin_made, sweep_run.
# This file keeps the header, the globals (GH, JQ, LSOF, HERE), the module loader, the source
# lines and main; `--help` greps the whole bundle (_trail_bundle), as the single file did.
#
# Subcommands:
#   sidecar-check <path>
#       One line: `ok <path>` or `fail <path>: <reason>`. Locates the LAST
#       REVIEW_HEAL_RESULT / SUPERVISOR_RESULT block with result_block_parser.py
#       and checks its keys against the tables below (required keys, no
#       non-schema key, canonical `channels_scanned`, `risk_classification`
#       carries `reasons`) and the same required/allowed check on every nested
#       object and list item (NESTED below). A file that cannot be checked is a `fail`.
#   trail-pr <runfile> [--reason <reason>]
#       One line: `trail-pr: opened <url>` | `trail-pr: pushed <url>` |
#       `trail-pr: skipped — <reason>`. Sidecars that fail `sidecar-check` are
#       excluded and named INSIDE that same line (`; excluded <path> — <reason>`),
#       and so is a done-stamped requirement / done brief whose PR is not merged
#       (`; excluded <path> — pr not merged`, _evidence_gate),
#       so the loop can append it to `## Progress` with one progress-append.
#   closeout <runfile> <item> <pr_url> [--session-id <sid>] [--no-trail]
#       The post-merge close-out (SKILL §6 "Post-merge close-out"): evidence
#       gate, brief repair, squash-safe worktree/branch cleanup, base-branch
#       sync, requirement stamp, Queue check-off, trail-pr. One line per step
#       (`closeout: <verb> — …`, brief-repair/trail-pr lines passed through);
#       idempotent; steps 3–7 run under run-lock.sh (re-enters a PICK lock via
#       --session-id; releases with --owner only). --no-trail (any position)
#       skips ONLY the trail-pr step and prints `trail-pr: skipped — --no-trail`
#       in its place — the `--auto-merge` SYNC and a merged lane's
#       lane-convert-ready re-run use it (automate-followups/38).
#   trail-unstage <runfile>
#       One line: `trail-unstage: unstaged <n> path(s) — <paths>` |
#       `trail-unstage: skipped — <reason>` (`nothing staged` when clean). Run at
#       PICK, before RUN: drops the trail entries trail-pr staged so the next
#       item's branch + commit cannot sweep them.
#   finalize-empty <runfile>
#       `finalize-empty: finalized <runfile>` + the trail-pr (+ trail-unstage)
#       line, or ONE `finalize-empty: skipped — <reason>` line. Finalizes ONLY a
#       paused / awaiting_go / remaining-0 / `## Current` status-done run (the
#       state closeout leaves after the last check-off); SKILL §4 step 1 runs it
#       through `automate-helpers.sh resume-glob <dir> --finalize`. In a lane
#       clone (`.supervisor/lane.json` present, parallel-automate/05) any run but
#       the lane's own ⇒ `skipped — lane clone (not this lane's run)`.
#   closeout-others <automate_dir> [--record <runfile>]
#       The cross-run close-out (SKILL §4 "Start order"): closeout of every OTHER
#       run whose ## Current names a not-done item with a merged PR, mode-off
#       trail-unstage, that closeout's closeout-classify answer, one
#       `closeout-others: record(ed) — cross-run closeout <run_id> <item>: …` line
#       (no PR URL). Untouched runs print nothing. In a lane clone ONE line
#       `closeout-others: skipped — lane clone` (the coordinator closes other runs
#       out once, in the primary — parallel-automate/05 Scope 3 amendment).
#   trail-gate <runfile>
#       One line: `trail-gate: PARK — trail PR open <url>…` |
#       `trail-gate: PARK — <unreadable reason>` | `trail-gate: clear — no open
#       trail PR; synced — <base> at <sha>` | `…; sync skipped — <reason>`. Run
#       at PICK after RECONCILE, before trail-unstage: the single-open-PR
#       invariant counts this run's own trail PR (SKILL §8); fail-CLOSED read.
#   sweep [--apply] [--root <checkout>]
#       One `sweep: would-remove|removed|kept <kind> <path-or-branch> — <reason>`
#       line per candidate (kinds: worktree, branch, app, lane, other; worktrees
#       first), then exactly ONE `sweep: summary — …` line, last. Dry run by
#       default (changes nothing); `--apply` removes only what the dry run reports
#       `would-remove`. Always exit 0. See sweep_run below.
#
# CHECKOUT CONTRACT (decision 4 of the post-park-lifecycle brief, proved by the
# post-merge-pull legs of test-automate-trail.sh): after a successful push, AND
# on the no-diff "already up to date" skip against an open trail PR, trail-pr
# sets the primary checkout's INDEX entry of EVERY path the trail branch changes
# (every push on it, not only the latest delta) to that path's blob at the trail
# branch tip (`git update-index --add --cacheinfo`; never the working copy),
# recording each in `<run_id>.trail-staged`, and leaves working copies untouched. A later plain `git checkout main && git pull` then
# fast-forwards over those paths (index == incoming blob), and bytes that exist
# only locally BY DESIGN — Progress lines the live run file gained after the
# push, other runs' postmortem ledger lines — survive as ordinary unstaged
# modifications. Those staged entries WOULD ride along in any commit made from
# the primary index (`git checkout -b` carries them; a plain `git commit`
# commits the whole index), so the loop runs `trail-unstage` at PICK, before
# the next commit-producing phase, and `closeout` re-applies the contract at
# its own pull for the recorded blobs that have landed upstream. The next
# trail-pr (the next closeout, skip/abandon check-off or run end) re-stages every path its open trail PR
# carries, including ones an earlier PICK dropped. trail-unstage clears the
# union of the record and today's candidates. Honest limits: between a PICK and
# the next trail-pr, a HAND-run `git pull` over a merged trail PR refuses
# (closeout's sync does not); a trail PR closed unmerged leaves its entries
# staged until the next PICK's trail-unstage. The trail branch is NEVER
# rebased: once origin/<default branch> moves the postmortem ledger (another
# run's trail PR, a postmortem line) after this run's trail branch was cut, a
# later push/no-diff re-trail stages the trail-TIP ledger blob, which lacks
# main's new line — the trail PR then conflicts at the ledger's EOF, and both a
# hand pull and closeout's sync refuse (fail-safe: no reset, nothing lost);
# resolve the trail PR by hand. When closeout's `git pull --ff-only` refuses,
# the entries it re-staged are put back to their prior index state
# (_restore_prior), so a refused sync leaves the index as it found it.
# Queue-derived candidates are restricted to `.supervisor/requirements/**.md`:
# a Queue item naming any other path is never committed by the trail.
#
# Always exits 0 (a runtime side-effect emitter — CLAUDE.md §"Failure-Mode
# Invariants"). bash 3.2 / BSD-userland safe. Seams: LOOMWRIGHT_GH_BIN,
# LOOMWRIGHT_JQ_BIN (same as automate-helpers.sh), LOOMWRIGHT_LSOF_BIN (sweep's
# liveness read).

set -uo pipefail

GH="${LOOMWRIGHT_GH_BIN:-gh}"
JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
LSOF="${LOOMWRIGHT_LSOF_BIN:-lsof}"
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# >>> module loader (_trail_source / _trail_bundle) — entry-only, belongs to no module
# The subcommands live in automate-trail.d/<name>.sh (automate-speed/19, a move-only split; the
# Modules map in the header names what each holds). Each is sourced by ONE `_trail_source <name>`
# line between `# >>> automate-trail.d/<name>.sh` and `# <<< automate-trail.d/<name>.sh` markers,
# at the position its text held when this was a single file, so `_trail_bundle` (this script with
# each such line replaced by the module's text) reproduces that file's line order. `--help` greps
# the bundle: the single file's help grep read the whole file, body comment lines included.
# Listed by name, never globbed: a stray file in automate-trail.d/ is never sourced.
# A missing or unreadable module fails CLOSED (exit 1, the file named), never a silent no-op —
# the ONE non-zero exit of this fail-SAFE emitter, and only on a broken install (precedent:
# automate-helpers.sh's _ah_source). The dir comes from this file's ${BASH_SOURCE[0]}; `$0` and
# HERE are unchanged, so every sibling lookup still resolves beside this entry point.
_trail_source() {
  local _trail_f
  _trail_f="$(dirname "${BASH_SOURCE[0]}")/automate-trail.d/$1.sh"
  { [ -f "$_trail_f" ] && [ -r "$_trail_f" ]; } \
    || { echo "automate-trail: missing module file: automate-trail.d/$1.sh" >&2; exit 1; }
  . "$_trail_f"
}
# _trail_bundle [<entry>] — print <entry> (default: this script) with every `_trail_source <name>`
# line replaced by automate-trail.d/<name>.sh read from beside it. Self-contained (a test evals
# this one function): a missing, unreadable or empty module prints one stderr line naming it and
# exits 1.
_trail_bundle() {
  local _trail_e="${1:-${BASH_SOURCE[0]}}"
  TRAIL_MOD="$(dirname "$_trail_e")/automate-trail.d" awk '
    /^_trail_source [a-z][a-z-]*$/ {
      f = ENVIRON["TRAIL_MOD"] "/" $2 ".sh"; n = 0
      while ((r = (getline l < f)) > 0) { print l; n++ }
      close(f)
      if (r < 0 || n == 0) { print "automate-trail: missing module file: automate-trail.d/" $2 ".sh" > "/dev/stderr"; exit 1 }
      next
    }
    { print }
  ' "$_trail_e"
}
# <<< module loader
# >>> automate-trail.d/sidecar.sh
_trail_source sidecar
# <<< automate-trail.d/sidecar.sh
# >>> automate-trail.d/trail-pr.sh
_trail_source trail-pr
# <<< automate-trail.d/trail-pr.sh
# >>> automate-trail.d/stage-sync.sh
_trail_source stage-sync
# <<< automate-trail.d/stage-sync.sh
# >>> automate-trail.d/closeout.sh
_trail_source closeout
# <<< automate-trail.d/closeout.sh
# >>> automate-trail.d/finalize.sh
_trail_source finalize
# <<< automate-trail.d/finalize.sh
# >>> automate-trail.d/sweep.sh
_trail_source sweep
# <<< automate-trail.d/sweep.sh
# --------------------------------------------------------------------------- #
# dispatch
# --------------------------------------------------------------------------- #
main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    sidecar-check) sidecar_check "$@" ;;
    trail-pr)      trail_pr "$@" ;;
    closeout)      closeout "$@" ;;
    trail-unstage) trail_unstage "$@" ;;
    trail-gate)    trail_gate "$@" ;;
    finalize-empty) finalize_empty "$@" ;;
    closeout-others) closeout_others "$@" ;;
    sweep)         sweep_run "$@" ;;
    ""|-h|--help)  _trail_bundle | grep -E '^#   [a-z]' | sed 's/^#   /  /' ;;
    *) echo "automate-trail: unknown subcommand: $cmd" >&2 ;;
  esac
  return 0
}

main "$@"
exit 0
