# Evidence — af39a: `sweep` dry run against this repo's primary checkout (AC8)

Captured 2026-10-15T08:28:14Z → 2026-10-15T08:28:59Z on macOS (Darwin 25.6.0), in this repo's primary checkout on branch
`feature/af39a-sweep` at `2d4276d` ("fix: address review feedback (iteration 2)" — the head after
every code change of review iterations 1 and 2; the working tree was clean). This replaces the
first capture, taken at `2d13140` before iteration 1 changed `sweep`'s output (the `would-remove`
reason now names the gitignored-content coverage check, and that check now keeps two worktrees).
Real `git`, real `gh` (the dry run only reads PRs), real `lsof`. The repo is public, so the one edit
to the transcript is path redaction: the primary checkout's parent directory reads `<parent>`.
Nothing else was changed or hand-written.

## Command

```bash
{ git worktree list --porcelain; git branch -v; } | shasum -a 256   # before
bash loomwright/scripts/automate-trail.sh sweep                      # dry run (no --apply), exit 0, stderr empty
{ git worktree list --porcelain; git branch -v; } | shasum -a 256   # after
```

## Checksum of `git worktree list --porcelain` + `git branch -v` (unchanged)

```text
before: 8656b5f820b585963a02f80a4111eafa70596a9ff1a3e15f0ede408cd965d72e
after:  8656b5f820b585963a02f80a4111eafa70596a9ff1a3e15f0ede408cd965d72e
```

## What it found, per kind

- **plugin worktrees** (`<parent>/aam-*` siblings): 3 `would-remove` (branch's newest PR MERGED at the local tip,
  clean, every gitignored entry salvageable or regenerable, no live process); 3 `kept`: 1 dirty (uncommitted
  changes), 2 holding unsalvaged ignored content (`.supervisor/check-wait/` — see the open decision below).
- **app worktrees** (`<parent>/ai-agent-manager/.claude/worktrees/`): 2 `kept app` — one clean and merged (the app
  removes it), one on a branch with no PR. Never removed.
- **lane / other worktrees:** none.
- **branches** (68 examined): 23 `would-remove` (newest PR MERGED, tip == its `headRefOid` — 3 of them are the
  branches of `would-remove` worktrees, judged in the same run); 45 `kept`: 31 no PR, 5 newest PR CLOSED unmerged,
  2 tip moved after the merge, 5 checked out in a kept worktree (the dirty one, the two holding
  `.supervisor/check-wait/`, and both app worktrees), 1 current branch of the primary, 1 base branch.
- **summary:** 26 `would-remove`, 50 `kept` (8 worktrees, 68 branches examined).

## Open owner decision: `.supervisor/check-wait/`

`.supervisor/check-wait/` is a plugin runtime directory the review drain writes. It is on neither the
`--ignored` salvage list nor the regenerable rule, so the coverage check
(`worktree-salvage.sh --check-ignored`, read-only) treats it as unsalvaged and `sweep` keeps every
worktree that holds it: here `aam-script-telemetry` and `aam-untrack-readiness`, which the first capture
listed as `would-remove`. Whether it should be salvaged (added to the salvage list) or treated as
regenerable is an open owner decision. This capture records the current behaviour and does not change it.

## Full output (sanitized)

```text
sweep: would-remove worktree <parent>/aam-drain-allowlist — branch fix/drain-allowlist-f1: PR #532 MERGED, tip == merged head 3d5be98c1ec6; clean; every gitignored entry salvageable or regenerable; no live process (gitignored runtime content is salvaged and verified first)
sweep: would-remove worktree <parent>/aam-gate-match-head — branch fix/gate-merge-match-head-commit: PR #531 MERGED, tip == merged head 9408385e779a; clean; every gitignored entry salvageable or regenerable; no live process (gitignored runtime content is salvaged and verified first)
sweep: kept worktree <parent>/aam-lanes-finished — dirty (uncommitted changes on feat/lanes-finished-collapsed)
sweep: would-remove worktree <parent>/aam-remove-floor — branch feat/remove-floor-web-page: PR #529 MERGED, tip == merged head 98da6aefffb8; clean; every gitignored entry salvageable or regenerable; no live process (gitignored runtime content is salvaged and verified first)
sweep: kept worktree <parent>/aam-script-telemetry — unsalvaged ignored content: .supervisor/check-wait/
sweep: kept worktree <parent>/aam-untrack-readiness — unsalvaged ignored content: .supervisor/check-wait/
sweep: kept app <parent>/ai-agent-manager/.claude/worktrees/drop-old-slug — clean and merged (branch chore/drop-old-slug-allowlist: PR #527 MERGED, tip == merged head 3e8ac1a1922d) — left in place; the app removes its own worktrees
sweep: kept app <parent>/ai-agent-manager/.claude/worktrees/funny-booth-859264 — branch claude/distracted-hermann-b24d73: no PR for this branch — left in place; the app removes its own worktrees
sweep: kept branch backup/citation-drift-prerebase — no PR for this branch
sweep: would-remove branch chore/dreaming-2026-10-02 — PR #344 MERGED, tip == merged head e6dfb378b73f
sweep: kept branch chore/drop-old-slug-allowlist — checked out in worktree <parent>/ai-agent-manager/.claude/worktrees/drop-old-slug
sweep: would-remove branch chore/m1-untrack-run-history — PR #361 MERGED, tip == merged head f4282631dc0e
sweep: would-remove branch chore/meta-scrub-cleanup — PR #359 MERGED, tip == merged head b06a5054bcb9
sweep: kept branch chore/parallel-automate-queue — no PR for this branch
sweep: kept branch chore/parallel-automate-redteam-fixes — no PR for this branch
sweep: would-remove branch chore/release-15.126.0 — PR #444 MERGED, tip == merged head 0d3c120743cc
sweep: would-remove branch chore/release-15.128.1 — PR #467 MERGED, tip == merged head 856df84870bd
sweep: would-remove branch chore/triage-proposed-2026-10-01 — PR #343 MERGED, tip == merged head 2ec967b486ae
sweep: kept branch claude/blissful-mccarthy-76f25d — no PR for this branch
sweep: kept branch claude/bold-chaum-3e3282 — no PR for this branch
sweep: kept branch claude/clever-yalow-8e6b82 — no PR for this branch
sweep: kept branch claude/distracted-hermann-b24d73 — checked out in worktree <parent>/ai-agent-manager/.claude/worktrees/funny-booth-859264
sweep: kept branch claude/elastic-borg-fac857 — no PR for this branch
sweep: kept branch claude/eloquent-herschel-f50fef — no PR for this branch
sweep: kept branch claude/funny-bohr-eeb394 — no PR for this branch
sweep: kept branch claude/great-cohen-9a08fc — no PR for this branch
sweep: kept branch claude/happy-mestorf-4f1dec — no PR for this branch
sweep: kept branch claude/laughing-chaplygin-b0c916 — no PR for this branch
sweep: kept branch claude/laughing-visvesvaraya-26206d — no PR for this branch
sweep: kept branch claude/loomwright-automate-resume-adf48d — no PR for this branch
sweep: kept branch claude/mystifying-keller-4e5b49 — no PR for this branch
sweep: kept branch claude/relaxed-burnell-73f491 — no PR for this branch
sweep: kept branch claude/rule-enforcement-parking-d792ff — no PR for this branch
sweep: kept branch claude/strange-lewin-f5588d — no PR for this branch
sweep: kept branch claude/vigilant-solomon-1b5c03 — no PR for this branch
sweep: kept branch dev-temp — no PR for this branch
sweep: would-remove branch docs/final-state-d1-d2-amendment — PR #316 MERGED, tip == merged head 2a63137ccfaf
sweep: kept branch feat/lanes-finished-collapsed — checked out in worktree <parent>/aam-lanes-finished
sweep: would-remove branch feat/remove-floor-web-page — PR #529 MERGED, tip == merged head 98da6aefffb8
sweep: kept branch feat/script-failure-telemetry — checked out in worktree <parent>/aam-script-telemetry
sweep: kept branch feature/af39a-sweep — current branch of the primary
sweep: would-remove branch feature/lanes-pane-ux — PR #507 MERGED, tip == merged head f35fd4301ff7
sweep: kept branch feature/relocate-qa-to-selvedge — newest PR #157 is CLOSED unmerged
sweep: kept branch feature/review-drain-st1 — no PR for this branch
sweep: kept branch feature/review-drain-st2 — no PR for this branch
sweep: kept branch feature/review-drain-st3 — no PR for this branch
sweep: kept branch feature/v12-S1 — no PR for this branch
sweep: kept branch feature/v12-S2 — no PR for this branch
sweep: kept branch feature/v12-S3 — no PR for this branch
sweep: kept branch feature/v12-S4 — no PR for this branch
sweep: kept branch feature/v12-S5 — no PR for this branch
sweep: would-remove branch fix/automate-runfile-write-fail-closed — PR #322 MERGED, tip == merged head 4e03626c03c6
sweep: would-remove branch fix/automate-trail-pr-behind-main — PR #356 MERGED, tip == merged head 742690b0d944
sweep: would-remove branch fix/bash53-locale-prefix-segfault — PR #355 MERGED, tip == merged head 56ebd80b6e37
sweep: kept branch fix/claude-review-no-exec — no PR for this branch
sweep: kept branch fix/curation-status-sigpipe-race — tip bbcbcecd3973 moved after merge (PR #368 merged head fc1ccbd5a555)
sweep: kept branch fix/curation-status-test-json-stderr — tip f3dd56f38d93 moved after merge (PR #364 merged head 2c2e61bc6d27)
sweep: would-remove branch fix/drain-allowlist-f1 — PR #532 MERGED, tip == merged head 3d5be98c1ec6
sweep: would-remove branch fix/gate-merge-match-head-commit — PR #531 MERGED, tip == merged head 9408385e779a
sweep: would-remove branch fix/harvest-c3-path-independent — PR #363 MERGED, tip == merged head a7657ab537b4
sweep: would-remove branch fix/lane-task-plan-push — PR #457 MERGED, tip == merged head 01fcd5f7edfe
sweep: kept branch fix/post-merge-residual-defects — newest PR #50 is CLOSED unmerged
sweep: kept branch fix/pr-postmortem-round-undercount — newest PR #49 is CLOSED unmerged
sweep: would-remove branch fix/repo-scan-gates-skip-ignored — PR #362 MERGED, tip == merged head bc9eb0a415c7
sweep: kept branch fix/reviewer-posts-from-workflow — newest PR #143 is CLOSED unmerged
sweep: would-remove branch fix/token-ledger-transcript-identity-gate — PR #439 MERGED, tip == merged head c83f7f187e26
sweep: kept branch fix/untrack-pr-readiness-after-untrack — checked out in worktree <parent>/aam-untrack-readiness
sweep: would-remove branch fix/w2-lane-defects — PR #466 MERGED, tip == merged head 12a36944408a
sweep: kept branch main — base branch
sweep: kept branch pr-12 — no PR for this branch
sweep: kept branch pr-24 — no PR for this branch
sweep: kept branch release/v13.1.0 — newest PR #13 is CLOSED unmerged
sweep: would-remove branch wave/automate-2026-10-14-041009-w1 — PR #541 MERGED, tip == merged head 3925a6323390
sweep: would-remove branch wave/w2 — PR #465 MERGED, tip == merged head 94fa1b3b67ed
sweep: would-remove branch wave/w3 — PR #474 MERGED, tip == merged head df7ced0a195a
sweep: would-remove branch wave/w4 — PR #481 MERGED, tip == merged head 801bff0b9f5a
sweep: summary — dry run: 26 would-remove, 50 kept (8 worktree(s), 68 branch(es) examined)
```
