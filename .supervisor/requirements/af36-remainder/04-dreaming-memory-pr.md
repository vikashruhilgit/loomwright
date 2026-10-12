# af36-remainder/04 — /dreaming offers one memory PR

## Status: pending

## Split from
`automate-followups/36-s3-engine-fixes.md` Part C §C (originally `meta-sync-followups/05` §C), split 2026-10-12
per that file's Re-scope section. Scope and acceptance text below is carried VERBATIM; only Depends on / Touches /
Validation are rewritten for today's tree (main 3e354b5).

## Depends on
none

## Touches
loomwright/commands/dreaming.md
loomwright/commands/agent-help.md
loomwright/capabilities.json
changelog.d/af36-04-dreaming-memory-pr.md

## Problem
Curated memory reaches `main` only when someone opens a memory PR by hand (the last was #344). `/dreaming`'s
documented PR path carries `.agent/rules/*.json` only ("never any other store", `commands/dreaming.md`).

## Scope (verbatim from af/36 Part C §C)
1. After its per-item Accepts, `/dreaming` offers ONE PR carrying only `.supervisor/memory/` and
   `.claude/agent-memory/` changes it wrote in this run. Paths are staged explicitly (never `git add -A`), and it
   refuses when those paths already held uncommitted changes it did not author, matching the rules PR.
2. Two gates, as for the rules PR: per-item Accept (content), then a separate Pre-push confirmation (push). It never
   merges: `gh pr create`, then stop.
3. Amend the documented PR-path rule in `commands/dreaming.md` (today: "carries **only** `.agent/rules/*.json` …
   never any other store"), and every prompt that restates it. Decide and state whether the memory PR and the rules
   PR are one branch or two. `CLAUDE.md` stays out of scope: its edits remain a hand PR, and the doc says so.

## Implementation notes (2026-10-12, read-only check of main 3e354b5)
- Prompts restating the PR-path rule: `commands/dreaming.md` (the "What the PR path may and may not touch" note and
  its delivery steps, `git add .agent/rules`), `commands/agent-help.md` (§"/dreaming"), and `capabilities.json`
  (mentions the Pre-push confirmation — check whether it restates the store list). Grep again before editing.
- This is prompt-as-program: state-trace the delivery steps for (a) memory-only, (b) rules-only, (c) both, (d) a
  dirty pre-existing memory path ⇒ refuse, (e) Pre-push declined ⇒ no branch, nothing pushed.

## Non-goals
`CLAUDE.md` edits (stay a hand PR). Writing orientation notes. Seeding agent memory for launch-pad, product-owner and
qa-strategist. The meta-sync stores (af36-remainder/03).

## Acceptance criteria
- **C1** Given an accepted memory change and no Pre-push confirmation, then no branch is created and nothing is
  pushed. Given both gates, then the PR carries only `.supervisor/memory/` and `.claude/agent-memory/` paths, and
  `/dreaming` never merges it.
- The one-branch-or-two decision is stated in `commands/dreaming.md`, and every prompt that restated the old
  rules-only rule now agrees with it.
- `gh pr merge` does not appear in any new `/dreaming` text (CLAUDE.md's single-executor invariant grep stays at its
  five surfaces).

## Validation (must pass before merge)
1. `scripts/check-doc-currency.sh` + `loomwright/scripts/test-citation-drift.sh` + token-budget (+ vendor ratchet
   after `git add`), and any test that pins `commands/dreaming.md` text (grep `scripts/` and `loomwright/scripts/`
   for `dreaming.md`). The full `scripts/ci-local.sh` runs at `wave-build` (owner rule 2026-10-12).
2. The state trace (a)–(e) above, pasted in the PR body.
3. Running system: one real `/dreaming` run in a scratch clone that accepts one memory item, declines Pre-push
   (nothing pushed), then re-runs and confirms (PR opened against a throwaway remote or left as a local branch). If not
   possible inside the lane, list it under "Not verified".
4. The single-executor grep from CLAUDE.md §"Failure-Mode Invariants" still resolves to its five surfaces.
5. Rollback: `git revert`.

## Provenance
Owner direction, 2026-10-03, session cc4eaee3 (after M1). The rules-only PR rule's design gap was resolved in the
original `meta-sync-followups/05` review.
