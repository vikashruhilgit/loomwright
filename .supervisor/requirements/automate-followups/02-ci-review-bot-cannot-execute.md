# 02 — The `claude-review` CI bot reviews statically only: decide whether (and how) it may execute

## Status: pending

> **Origin (2026-09-26).** Surfaced by `/automate` run `automate-2026-09-22-013403`, item twin-loop/08
> (PR #267). The `claude-review` CI bot reviewed commit 53c0992 and reported **no findings**. The Phase 4.5
> integrated review of the SAME commit failed it with **4 HIGH findings, each reproduced by executing code**
> in scratch repos:
> - ambient-env replay laundering;
> - an accepted check stored advisory and never run;
> - a repo-wide candidate failing on arrival;
> - an invalid-ERE token producing an always-pass check.
>
> The bot's own comments say why: "this sandbox does not permit executing bash scripts … verified statically".
> It missed every one because each looks correct on read and fails only at runtime.

## Problem
`.github/workflows/claude-code-review.yml` passes the reviewer a deliberately read-only allowlist
(`claude_args: --allowed-tools "Read,Grep,Glob,…,Bash(git log:*),…,Bash(gh pr view:*)"`). The workflow's own
comments record why every broader `Bash(...)` wildcard was removed: `git branch:*` admitted `-D`/`-M`,
`find:*` admitted `-exec`/`-delete`, and so on. **This is a hardening decision, not an oversight.** The
reviewer reads attacker-influenced PR content, so letting it execute repo scripts means running PR-authored
code under the workflow's token and secrets.

The cost of that decision is now measured. A green `claude-review` on this repo means "reads right", never
"exercised", and CLAUDE.md's "two review lenses" contract treats the bot as the second lens. When the bot is
static-only and Phase 4.5 does not reproduce, a runtime-only defect has no lens at all.

## Goal
Make an explicit, recorded decision, not a drift, on whether the CI reviewer gets ANY execution capability,
and make the reviewer's limit visible wherever its verdict is consumed.

## Options to decide between (owner decision; do not pre-pick)
1. **Keep static-only; make the limit explicit.**
   - The bot prints a machine-readable `execution: none` marker.
   - The drain / `REVIEW_HEAL_RESULT` surfaces "second lens was static-only".
   - Phase 4.5's reproduce-by-executing becomes the documented sole runtime lens.
   - Cheapest, and adds no new attack surface.
2. **Execute the repo's own test suites only, in an isolated job.**
   - A separate job with NO secrets and a read-only token (`permissions: contents: read`, no
     `CLAUDE_CODE_OAUTH_TOKEN` in that job) runs `scripts/test-*.sh`.
   - Its result is fed to the reviewer as an artifact; the reviewer itself stays read-only.
   - Note: `ci.yml` may already run exactly this. Verify the overlap before building anything.
3. **Grant the reviewer a narrow execution allowlist** (e.g. `Bash(bash loomwright/scripts/test-*.sh:*)`).
   - It runs PR-authored code with the review job's credentials.
   - Needs a threat-model pass (red-team review) before adoption. Likely rejected; listed for completeness.

## Scope (depends on the option chosen)
- Option 1: `claude-code-review.yml` prompt text; `skills/review-heal/SKILL.md` (surface the marker);
  `docs/RESULT_SCHEMAS.md` if a result field is added.
- Option 2: a new or modified workflow job; artifact hand-off.
- **Workflow-file caveat (CLAUDE.md, machine-level lessons):** `anthropics/claude-code-action` **skips itself
  on any PR that modifies a workflow file** and exits 0. A PR changing the reviewer can never test itself. Merge
  it, then verify with a NON-workflow PR, asserting on posted comments (`gh pr view <n> --json comments`), never
  on the check's conclusion.

## Non-goals
- No change to the `gh pr merge --squash` single-executor invariant or the auto-merge gate.
- No weakening of the existing allowlist hardening without a red-team pass.

## Acceptance criteria
- [ ] The decision (1/2/3, or a variant) is recorded here with its rationale before any implementation.
- [ ] Whichever option: a follow-up non-workflow PR demonstrates the new behaviour in a POSTED comment or
  artifact, not just a green check.
- [ ] Wherever a `claude-review` verdict is consumed as a review lens (drain READY reasoning, PR body, docs),
  its execution capability is stated. "No findings" from a static-only reviewer is never presented as runtime
  verification.

## Verified premises (re-check before starting)
- `.github/workflows/claude-code-review.yml` `claude_args` allowlist: read-only git/gh/text tools, no script
  execution (read at `main @ 91c117e`, 2026-09-26).
- PR #267 comments: `claude[bot]` 2026-09-25T16:33:04Z (reviewed 53c0992, "No correctness, security, or
  documentation-drift issues found"), with Phase 4.5's round-1 FAIL of the same SHA recorded in run file
  `automate-2026-09-22-013403.md` `## Progress`.
