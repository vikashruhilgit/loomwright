# 02 — Runtime defects need an executing lens by default: label the static CI bot, make the Phase 4.5 reviewer reproduce

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
Close the actual gap: a runtime-only defect must have a lens that EXECUTES by default, not only when a human
remembered to ask for it. Also stop a static-only green from reading as runtime verification.

## Decision (owner, 2026-09-26): option 1 PLUS reproduce-by-default in the Phase 4.5 reviewer
Options 2 and 3 were rejected on evidence, not taste:
- **They would not have caught PR #267's bugs.** The full test suite was GREEN on 53c0992. The 4 HIGHs were
  found by Phase 4.5 writing NEW attack scripts in scratch repos, not by running existing tests.
- **Option 2 already exists.** `ci.yml` runs the whole suite as a hard gate on every push.
- **Option 3 adds attack surface for no gain.** It runs PR-authored code under the review job's credentials,
  and still only re-runs existing tests.

The finding that makes option 1 insufficient on its own: the Phase 4.5 reviewer's standing contract
(`agents/code-reviewer.md` §5 "Execution-Grounded Verification") only says to type-check and *"run ONLY the
specific existing tests that cover the diff"*. Those tests were green, so the DEFAULT reviewer would have passed
#267 exactly as the bot did. The HIGHs were caught only because the `/automate` main thread hand-wrote "REPRODUCE
by executing in a `mktemp -d` scratch dir" into that one spawn prompt. The next run gets that only if someone
remembers.

## Scope
**Part 1: label the static lens (option 1).**
- `claude-code-review.yml` prompt: every posted review states, in a fixed machine-readable line, that it is
  static-only (e.g. `execution: none`).
- `skills/review-heal/SKILL.md`: where the drain reasons about a bot review lens, record that the lens was
  static-only; never present "no findings" from it as runtime verification. `docs/RESULT_SCHEMAS.md` only if a
  result field is genuinely needed (flag it, don't silently add one).

**Part 2: reproduce-by-default in the Phase 4.5 reviewer (the part that closes the gap).**
- `agents/code-reviewer.md` §5: for a **load-bearing** correctness or security claim in the diff, the reviewer
  writes and runs a minimal adversarial repro in a scratch dir **outside the repo** (`mktemp -d`), driving the
  REAL changed scripts. Mirror the wording of the ad-hoc prompt that caught #267's bugs.
- This stays inside §5's existing mutation guardrails ("never mutates the working tree, writes artifacts"): a
  scratch dir outside the checkout is not the working tree. Say so explicitly in §5 rather than loosening the
  guardrail. A repro that would need to write inside the repo is reported `unverified`, per §5's existing rule.
- `skills/self-heal-advisory/SKILL.md` Part 2 §"Review-and-fix loop" (the authoritative Phase 4.5 spawn
  wording): carry the same instruction, so every Phase 4.5 spawn gets it without a human adding it.
- **Token budget:** `code-reviewer` is at 22846 / 25131 (2285 headroom). Re-measure live, and raise per the
  measured+~10% rule with a Re-measure log entry if breached.
- **Workflow-file caveat (CLAUDE.md, machine-level lessons):** `anthropics/claude-code-action` **skips itself
  on any PR that modifies a workflow file** and exits 0. Part 1 cannot test itself. Merge it, then verify with a
  NON-workflow PR, asserting on posted comments (`gh pr view <n> --json comments`), never on the check's
  conclusion. Consider shipping Part 1 (workflow) and Part 2 (agent/skill) as separate PRs for that reason.

## Non-goals
- No change to the `gh pr merge --squash` single-executor invariant or the auto-merge gate.
- No widening of the `claude-review` allowlist (options 2 and 3 rejected, above).
- The reviewer still never mutates the working tree. Scratch-dir repro only.

## Acceptance criteria
- [ ] `code-reviewer.md` §5 and the self-heal-advisory Phase 4.5 spawn wording both instruct scratch-dir
  adversarial repro for load-bearing claims, and both state that it is outside the working tree.
- [ ] **Regression evidence (the load-bearing AC):** re-run a Phase 4.5 review of PR #267's original commit
  (53c0992, in a scratch worktree) with the DEFAULT spawn prompt and NO hand-added repro instruction. It must
  report at least the replay-laundering HIGH (ambient `RULES_CHECK_CONFIRM=1` + `--if-stamped`), reproduced by
  execution. If it does not, the contract change is not strong enough.
- [ ] The `claude-review` workflow posts the static-only marker. Verified on a follow-up NON-workflow PR via its
  posted comment.
- [ ] Wherever a `claude-review` verdict is consumed as a review lens (drain READY reasoning, PR body, docs), its
  static-only status is stated.
- [ ] `check-token-budget.sh` green; the full test loop green.

## Verified premises (re-check before starting)
- `.github/workflows/claude-code-review.yml` `claude_args` allowlist: read-only git/gh/text tools, no script
  execution (read at `main @ 91c117e`, 2026-09-26).
- PR #267 comments: `claude[bot]` 2026-09-25T16:33:04Z (reviewed 53c0992, "No correctness, security, or
  documentation-drift issues found"), with Phase 4.5's round-1 FAIL of the same SHA recorded in run file
  `automate-2026-09-22-013403.md` `## Progress`.
