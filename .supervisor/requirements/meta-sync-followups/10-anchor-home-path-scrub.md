# 10 — Anchor the `home_path` scrub so it matches home paths, not every `/users/<x>/` segment

## Status: parked (merged 2026-10-06 into `meta-sync-followups/11-scrub-precision.md` as Part A — do not run this file; work the merged item)

## Depends on
08-meta-sync-hardening.md

## Touches
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/agents/launch-pad.md
changelog.d/meta-sync-followups-10-anchor-home-path-scrub.md

## Problem
Filed 2026-10-05 by the owner at PR #391's park. s3-c's Phase 4.5 reviewer reproduced it (exit 2): the scrub rule
`home_path${TAB}i${TAB}/(Users|home)/[A-Za-z0-9._-]+/` (`meta-sync.sh`'s scrub table) is case-insensitive and
unanchored, so any `/users/<x>/` segment trips it — an API route such as `/api/users/<42>/orders` in a brief, a
requirement or a review note blocks the lane's whole trail push. It hit live in S3: the reviewer's own example in
s3-c's result sidecar would have blocked that lane's push, and the lane rewrote it by hand. `04` (#391) worked around
it in prose (the home-path rule now tells authors to write every such segment with a placeholder); the regex itself
still over-matches. Out of `04`'s scope because `meta-sync.sh` is in `08`'s Touches (same wave).

## Scope
1. Anchor the rule to where a home path can start: start of line, or after a character that cannot be part of a
   path segment (whitespace, quote, backtick, `(`, `=`, `:`, `,`) — so `/api/users/<42>/` does NOT match, while these
   still DO: `/Users/<x>/…` at line start, `` `/Users/<x>/` ``, `--state-dir /Users/<x>/…`, `"/home/<x>/…"`, `file:///Users/<x>/`,
   `HOME=/Users/<x>/`. Decide (and record here) whether case-insensitivity stays: macOS is `/Users`, Linux `/home`, but a
   case-insensitive volume accepts `/users/<x>/` as a real home path.
   (In this file `<x>` and `<42>` stand for a real name or id: written literally they would trip today's scrub and
   block this record's own push. The test uses the real forms.)
2. A table test in `test-meta-sync.sh`: every case above, plus the S3 false positive verbatim.
3. **Folded in 2026-10-06 (owner, from claude-review's review of #391 at `1f0571b`):**
   - a CI guard that re-runs `04`'s acceptance grep (no literal home-path examples in `loomwright/agents`,
     `loomwright/commands`, `loomwright/skills`) so a later PR cannot silently reintroduce one — as a leg in
     `test-meta-sync.sh` or a `check-*.sh` gate, whichever the repo's existing guards use (decide in the brief);
   - `meta-sync.sh`'s scrub-table header comment (the `home_path` row) rewritten to describe the shipped regex exactly.
4. Update `04`'s home-path rule sentence in `supervisor-readiness/SKILL.md` and `launch-pad.md` (Phase 5 action 3b)
   to the new, narrower scope — the "any `/users/<x>/` segment, anywhere" wording is true only for the old regex.

## Non-goals
Other scrub rules. Rewriting history already on `loomwright-meta`.

## Acceptance criteria
- The table test passes; `/api/users/<42>/orders` pushes (exit 0), `--state-dir /Users/<x>/.supervisor` is refused
  (exit 2, `home_path`).
- The rule sentence in both files and the `meta-sync.sh` header comment match the shipped regex.
- The example-grep guard fails on a fixture that reintroduces a literal home-path example.
- `bash scripts/ci-local.sh` green; a `changelog.d/` fragment.

## Validation (must pass before merge)
- Running system: in a scratch clone with a local bare remote (no GitHub push), `meta-sync.sh push` of one record with
  each table case — record exit codes in the PR.
