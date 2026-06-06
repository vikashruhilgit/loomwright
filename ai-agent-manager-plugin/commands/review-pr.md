---
description: Run a bounded review→fix→re-review heal loop against an existing PR URL; never auto-merges
---

> **Execute this workflow inline as the main thread.** Do not delegate to `ai-agent-manager-plugin:review-pr-runner` via the Agent tool — a delegated subagent cannot spawn further subagents ([docs](https://code.claude.com/docs/en/sub-agents)) and the workflow will silently abort with "Task/Agent tool unavailable". To run the agent in its own session instead, launch with `claude --agent ai-agent-manager-plugin:review-pr-runner`.

> **Execution contract:** Inline main-thread execution replaces only the top-level `review-pr-runner`. You MUST still spawn first-level child agents via the Task tool: `ai-agent-manager-plugin:code-reviewer` for each review pass, and a `general-purpose` fix worker (allowlist Read / Write / Edit / Bash / Glob / Grep, **no Task**) for each fix iteration. Do NOT collapse the loop into direct main-thread implementation. **AC9:** the `review-pr-runner` is **never itself Task-spawned** — it runs only as a session main agent (`claude --agent …:review-pr-runner`) or inline via this command; a `Task(…:review-pr-runner)` call lands it one spawn-level too deep and its own child spawns would fail.

# Command: /review-pr

## Purpose

`/review-pr` runs the **standalone PR review-and-heal loop** against an existing Pull Request URL. It resolves the PR's head branch, runs a bounded **review→fix→re-review** loop (Code Reviewer → on FAIL, a `general-purpose` fix worker → push → re-review), and leaves the PR open for a human. It is the loop of Supervisor **Phase 4.5** factored out so it can run **independently in a fresh session keyed off a PR URL** — no Supervisor job, no `.supervisor/state.md`, no worktree fan-out.

The loop contract is defined by the **`review-heal` skill** (`skills/review-heal/SKILL.md`) — the single source of truth for the bounded-loop semantics, PR-URL→branch resolution, notifications, the no-auto-merge rule, and the `REVIEW_HEAL_RESULT` block.

## Usage

```bash
/review-pr <pr-url>          # Review-and-heal the given PR (e.g. https://github.com/owner/repo/pull/42)
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `<pr-url>` | Yes | The full URL of an existing PR. `gh pr view <pr-url> --json headRefName` resolves the head branch, which is fetched + checked out before the loop. The review scope is the PR diff (`git diff <base>...HEAD`, base default `main`). |

## What This Does

1. **PR-URL → branch resolution.** `HEAD_REF=$(gh pr view <pr-url> --json headRefName --jq '.headRefName')`; `git fetch origin "$HEAD_REF"`; `git checkout "$HEAD_REF"`.
2. **Bounded review→fix→re-review loop** (default 3 iterations — the `--heal-iterations` analogue):
   - `Task(ai-agent-manager-plugin:code-reviewer)` reviews the PR-branch diff (`CODE_REVIEW_RESULT` v3, `review_mode: diff_review`).
   - **PASS** → done. The diff is clean. **Does NOT merge** — the PR is left open for a human.
   - **FAIL** (≥1 `new` + BLOCKING/HIGH issue) → spawn a `Task(general-purpose)` fix worker (Read / Write / Edit / Bash / Glob / Grep, **no Task**) that addresses ONLY those findings, then `git push` to the PR branch (**never `--force`**), then re-review.
   - **NEEDS_HUMAN, or the loop exhausts with issues remaining** → **STOP. Do NOT auto-fix, do NOT merge.** Post findings to the PR (`gh pr comment`), fire best-effort notifications (`notify-desktop.sh` / `send-webhook.sh`), exit as `ESCALATED`.
3. **No auto-merge, no PR creation.** Terminal states leave the PR open: `PASS` (human merges) and `ESCALATED` (human attention). `/review-pr` never creates a PR, which prevents a review→review recursion.

## Output — `REVIEW_HEAL_RESULT`

The run ends by emitting a `REVIEW_HEAL_RESULT` block (`schema_version: 1`; defined by the `review-heal` skill):

```
## REVIEW_HEAL_RESULT
- schema_version: 1
- decision: PASS | ESCALATED        # enum — exactly these two values (no FAIL)
- iterations: <int>                 # review→fix→re-review cycles run
- issues_fixed: <int>               # new+BLOCKING/HIGH issues addressed by fix workers
- remaining_issues: <int>           # new+BLOCKING/HIGH issues still open at exit
- pr_url: "<string>"                # the PR this run operated on
- notified: <bool>                  # true if a NEEDS_HUMAN notification was attempted
```

## Prerequisites

1. **GitHub CLI:** `gh` installed and authenticated (for `gh pr view` and `gh pr comment`).
2. **Git repository:** the local clone of the PR's repo, able to fetch + check out the head branch.
3. **An existing PR:** `/review-pr` operates on a PR URL and never creates one.

## See Also

- `skills/review-heal/SKILL.md` — the authoritative loop contract (pinned names, bounded-loop semantics, notify, no-auto-merge, `REVIEW_HEAL_RESULT`).
- `agents/review-pr.md` — the `ai-agent-manager-plugin:review-pr-runner` agent this command runs inline.
- `commands/supervisor.md` — Supervisor Phase 4.5, the in-job review→fix→re-review machinery this loop is extracted from.
