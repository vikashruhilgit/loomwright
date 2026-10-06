# 11 — Scrub precision: the `home_path` scrub matches home paths only, and the schema examples are scrub-safe

## Status: done (2026-10-06, PR #399 merged `1b5adb5`, done directly — not a lane)

## Merged from (2026-10-06, owner decision: fewer, larger items — a run costs ~$17–20 plus 4+ owner questions even for a tiny change)
- Part A: `10-anchor-home-path-scrub.md` — 10 — Anchor the `home_path` scrub so it matches home paths, not every `/users/<x>/` segment
- Part B: `09-scrub-safe-schema-examples.md` — 09 — Scrub-safe worktree paths in the result-schema examples and fixtures

The originals are parked with a pointer here. Their text is kept below VERBATIM as parts (headings
demoted, their Status / Depends on / Touches folded into this file's own sections). Nothing was paraphrased.

## Depends on
08-meta-sync-hardening.md

## Touches
loomwright/scripts/meta-sync.sh
loomwright/scripts/test-meta-sync.sh
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/agents/launch-pad.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/scripts/result-validator-fixtures/execute-checkpoint-valid.md
loomwright/scripts/result-validator-fixtures/execute-result-valid.md
changelog.d/meta-sync-followups-11-scrub-precision.md

## Goal
One change set on the `home_path` scrub: the regex is anchored to real home paths, with a guard and exact wording (A), and the result-schema examples and fixtures no longer carry a literal home-path form (B).

## Acceptance criteria
- Every part's own acceptance criteria hold, on one branch and one PR.

## Validation (must pass before merge)
1. Baseline full loop once for the merged branch, `<passed>/<total>` and `SKIP` counts, base and branch.
2. Every part's own Validation steps, labelled by part in the PR body. A part with no Validation section is
   checked by running its acceptance criteria, and the PR body says so.
3. Any "Running system" step a part names is run, or listed under "Not verified" with the reason.
4. Rollback: `git revert`.

## Parts

### Part A — 10 — Anchor the `home_path` scrub so it matches home paths, not every `/users/<x>/` segment

#### Problem
Filed 2026-10-05 by the owner at PR #391's park. s3-c's Phase 4.5 reviewer reproduced it (exit 2): the scrub rule
`home_path${TAB}i${TAB}/(Users|home)/[A-Za-z0-9._-]+/` (`meta-sync.sh`'s scrub table) is case-insensitive and
unanchored, so any `/users/<x>/` segment trips it — an API route such as `/api/users/<42>/orders` in a brief, a
requirement or a review note blocks the lane's whole trail push. It hit live in S3: the reviewer's own example in
s3-c's result sidecar would have blocked that lane's push, and the lane rewrote it by hand. `04` (#391) worked around
it in prose (the home-path rule now tells authors to write every such segment with a placeholder); the regex itself
still over-matches. Out of `04`'s scope because `meta-sync.sh` is in `08`'s Touches (same wave).

#### Scope
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

#### Non-goals
Other scrub rules. Rewriting history already on `loomwright-meta`.

#### Acceptance criteria
- The table test passes; `/api/users/<42>/orders` pushes (exit 0), `--state-dir /Users/<x>/.supervisor` is refused
  (exit 2, `home_path`).
- The rule sentence in both files and the `meta-sync.sh` header comment match the shipped regex.
- The example-grep guard fails on a fixture that reintroduces a literal home-path example.
- `bash scripts/ci-local.sh` green; a `changelog.d/` fragment.

#### Validation (must pass before merge)
- Running system: in a scratch clone with a local bare remote (no GitHub push), `meta-sync.sh push` of one record with
  each table case — record exit codes in the PR.

### Part B — 09 — Scrub-safe worktree paths in the result-schema examples and fixtures

#### Problem
Filed 2026-10-05 by the owner at PR #391's park (one of its "Not verified" items; out of `04`'s scope because
`RESULT_SCHEMAS.md` is in `automate-followups/32`'s Touches, which runs in the same wave).
The worktree-path examples read `/Users/<literal "name">/myapp-...` (`RESULT_SCHEMAS.md` the two `path:` lines of the
EXECUTE_RESULT example; `execute-checkpoint-valid.md` `active_worktrees`; `execute-result-valid.md` two `path:` lines).
`name` is inside the `meta-sync.sh` `home_path` class `[A-Za-z0-9._-]+`, so any record that copies an example
verbatim is refused by the scrub (exit 2), blocking the lane's whole trail push. `04` set the convention:
placeholders in angle brackets (`/Users/<name>/`), which fall outside the class.

#### Scope
1. Rewrite the five example paths to the `04` placeholder form (`/Users/<name>/myapp-add-jwt-guard`), keeping
   every fixture valid for `result-validator.sh` (the validator must still accept the fixtures).
2. Check, and record in this file, whether a REAL EXECUTE_RESULT / checkpoint written into a managed sidecar
   (`.supervisor/automate/*.md`) carries an absolute worktree path that trips the scrub on a lane's trail push (S2's
   handover names `reconcile-status` paths in run files as one cause of blocked pushes). If it does, that is a
   separate item — file it, do not widen this one.

#### Non-goals
Changing the scrub regex (`10`). Changing what the schemas require.

#### Acceptance criteria
- `grep -nE '/(Users|home)/[A-Za-z0-9._-]+/' loomwright/docs/RESULT_SCHEMAS.md loomwright/scripts/result-validator-fixtures/`
  returns nothing.
- The result-validator self-test passes with the rewritten fixtures.
- `bash scripts/ci-local.sh` green; a `changelog.d/` fragment.

#### Validation (must pass before merge)
- The grep above, and the validator test, on the PR head.
