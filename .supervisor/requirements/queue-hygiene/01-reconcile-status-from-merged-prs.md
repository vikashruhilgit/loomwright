# 01 — Reconcile REQUIREMENT status from merged PRs (the half PR #243 did not cover)

> **Scope note (2026-09-22).** The brief half of this problem shipped in PR #243 (v15.84.0):
> `reconcile-jobs.sh --repair-merged` attributes a stranded `jobs/in-progress/` brief to the one
> `Merge pull request #N from <owner>/…/<slug>` commit on the local base ref and moves it to
> `done/`, and `session-resume.sh` runs that mechanically at SessionStart. The judgement trail
> (`requirements/`, `jobs/done|failed/`, `automate/*.md`) is version-controlled since the same PR.
> This item is what remains: the REQUIREMENT file's `## Status:` line, the abandoned-track stamp,
> and the worktree salvage check. It does NOT re-open the brief arm.

## Problem
Only the `/automate` per-item loop writes a requirement's `## Status: done` line (automate-loop
SKILL.md §6 check-off). Every other way a PR reaches `main` — `gh pr merge` by the owner, the GitHub
UI, a hand-started `/supervisor`, a `/review-pr` heal the owner merges — leaves the requirement
untouched, and `is_done()` (`automate-helpers.sh`) treats an absent or `pending` status as
enqueueable. Measured 2026-09-21 on this repo at v15.81.0:

- **8 requirement files pending/absent-status whose PR had merged** — `loom-floor-ui/05` (#177),
  `/06` (#181), `floor-ui-redesign/01` (#185), `verify-walkthrough/07` (#230 — its PR body cites
  the file path verbatim and the file still said `## Status: pending`), `selvedge-extraction/01–03`
  (#153/#155/#156), `final-state/03` (v15.17.0). `resolve-folder` re-offered every one of them.
- **4 files still `pending` for a track the owner dropped on 2026-08-22** (`selvedge-extraction/04–07`);
  the abandonment was recorded only as `# abandoned:` rows in `automate-2026-08-18-124023.md`.
- **6 orphaned worktrees, all merged; one (`pr227-fix`) held ~98 lines of uncommitted test that had
  never reached `main`.** `worktree-audit.sh` advised removal without diffing — the salvage became
  PR #244 only because a human looked first.
- 24 files at `## Status: brief-shipped` whose AC were never promoted (listed, never auto-promoted).

All 12 status fixes were applied by hand (they are in the trail commit of #243). The mechanism
gap is that ground truth — a merged PR that names the requirement — is never read back.

## Goal
A fail-safe, dry-run-default `reconcile-status` pass that writes the requirement's status from
ground truth the same way `--repair-merged` now writes the brief's lifecycle move, so hand-merged
work stops being re-enqueued and dropped tracks stop looking pending.

## Scope
1. **Requirement ← merged PR.** For each `*.md` under `.supervisor/requirements/**` that
   `is_done()` rejects (skip `00-*`, `_*`, `README*`, and `operator-run/` subfolders): the PR is
   MERGED and either (a) its body cites the file's repo-relative path, or (b) its head branch
   equals the slug recorded in the file's `done/` brief. Resolve PR state through the existing
   `reconcile-item` verb (`merged|open|gone`) — no second `gh` parser. On a hit append the §6 stamp
   shape byte-for-byte: `## Status: done (PR #n, merge <sha7>)` + `- **Completed:**` /
   `- **Brief:**` / `- **PR:**` lines. Never downgrade an existing `done`; a stale trailing
   `## Status: pending` line is removed when the stamp is written (verify-walkthrough/07 shape).
2. **Abandoned track ← automate run file.** A queue row carrying `# abandoned:` in any
   `.supervisor/automate/*.md` is an owner decision; stamp that requirement
   `## Status: done_with_escalation — ABANDONED (<row text verbatim>)` so `is_done()` honours it.
3. **Worktree report gains merge + salvage columns.** `worktree-audit.sh report` prints, per
   orphan, `merged` when its HEAD is an ancestor of `origin/<base>` (base resolved the way
   `reconcile-jobs.sh vcs_base_ref` does — reuse it, do not copy it) and `salvage: <n> files` for
   any uncommitted OR unpushed delta. The SessionStart advisory must never say "remove by hand"
   for a worktree with `salvage > 0`.
4. **Dry run by default.** `automate-helpers.sh reconcile-status <requirements_root>` prints the
   plan (file → proposed stamp, with the PR URL or run-file row that justifies it) and writes only
   under `--apply`. `brief-shipped` files are LISTED with job + PR and never promoted — AC
   verification stays a human act. `/automate --resume` RECONCILE (§4) runs the dry-run pass and
   appends one `## Progress` line naming any file it would stamp, before PICK.
5. **Release surfaces (same convention as every other queued item):** one CHANGELOG paragraph; version bump
   in `plugin.json` + `marketplace.json` + CHANGELOG only (descriptions updated IN PLACE — anti-rebloat rule);
   counts unchanged.

## Non-goals
- No change to `is_done()` semantics (absent status still means pending — write the status,
  never infer it). No new hook, no new gate, no GitHub writes, no worktree removal, no promotion
  of `brief-shipped`. No re-implementation of the brief arm (#243) or PR-state resolution
  (`reconcile-item`).

## Acceptance criteria
- Fixture root with (a) a done file, (b) a pending file whose PR merged and cites the path, (c) a
  pending file whose PR is open, (d) an `operator-run/` file, (e) an index `00-*` file:
  `reconcile-status` prints exactly one plan line (for b) and writes nothing; `--apply` stamps (b)
  only, and `is_done` then returns true for it. **Mutation control:** delete the path citation
  from (b)'s PR body fixture → no plan line, no stamp.
- A run-file fixture with one `# abandoned:` row stamps exactly that requirement with
  `done_with_escalation`; a row without the marker stamps nothing.
- `worktree-audit.sh report` on a merged worktree with one uncommitted file prints `merged` and
  `salvage: 1 files`; clean merged → `merged` only; **falsify:** a HEAD that is not an ancestor
  never prints `merged`. The SessionStart advisory text for a `salvage > 0` worktree contains no
  removal instruction.
- `/automate --resume` on a folder containing (b) leaves a `## Progress` line naming (b) before
  the PICK line.
- Re-running the 2026-09-21 audit (§Problem) on this repo after `--apply` yields zero (b)-class
  files; the 12 hand-applied stamps are byte-identical to what the tool would have written.
- Both loops green: `loomwright/scripts/test-*.sh` and root `scripts/test-*.sh` +
  `scripts/check-vendor-coupling.sh` — the `gh` calls make this ADAPTER-side or
  allowance-declared; declare, never raise a core allowance.

## Outcomes Rubric
- Ground truth flows INTO the queue; nothing flows out
- Absent status stays pending; the tool writes status, never infers it
- Dry-run default; `--apply` is the only writer; `brief-shipped` never auto-promoted
- Abandoned owner decisions become machine-readable where `is_done()` looks
- A merged worktree with unmerged bytes is reported as salvage, never as removable
- Stamp shape byte-compatible with §6; PR state via `reconcile-item`; base ref via `vcs_base_ref`


## Status: done (PR #247, merge bc4d502)
- **Completed:** 2026-09-26T02:14:28Z
- **Brief:** unknown
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/247
