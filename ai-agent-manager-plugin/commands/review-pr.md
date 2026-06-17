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
/review-pr <pr-url>                          # Review-and-heal the given PR (e.g. https://github.com/owner/repo/pull/42)
/review-pr <pr-url> --until-mergeable        # Opt-in: drain machine-speed external signals until READY (never merges)
/review-pr <pr-url> --until-mergeable --max-rounds 8 --postmortem-churn-threshold 3
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `<pr-url>` | Yes | — | The full URL of an existing PR. `gh pr view <pr-url> --json headRefName` resolves the head branch, which is fetched + checked out before the loop. The review scope is the PR diff (`git diff <base>...HEAD`, base default `main`). |
| `--until-mergeable` | No | off | **Opt-in, strictly additive** drain mode. Layers the external-signal drain loop on top of the default diff-only loop: reads **required** CI check-runs + automated/bot reviews + unresolved **bot-authored** review threads, auto-fixes the actionable BLOCKING/HIGH items, pushes, and re-polls until **required checks are green AND no unresolved bot-authored review threads remain** → `decision: READY` + "ready to merge" notification. **Never merges.** **Absent ⇒ behavior is byte-for-byte the existing diff-only loop** (AC7). Authority: `review-heal` skill §"Until-Mergeable Mode". |
| `--max-rounds N` | No | `5` | Hard ceiling on `--until-mergeable` drain rounds. On exhaustion without reaching READY, the loop exits `decision: ESCALATED`, posts remaining findings via `gh pr comment`, and notifies — never unbounded (AC4). Only meaningful with `--until-mergeable`. |
| `--required-checks all-non-neutral` | No | fail closed | **Opt-in fallback** for `--until-mergeable` when branch-protection required-check metadata is **unreadable** (insufficient permissions / no branch protection / API error). Default behavior **fails CLOSED** — unreadable metadata ⇒ the loop MUST NOT claim READY and exits `ESCALATED` (AC14). Passing `all-non-neutral` opts into treating every check whose state is not `NEUTRAL`/`SKIPPED` as blocking, so the drain can proceed without the metadata. |
| `--no-auto-postmortem` | No | postmortem on (churn-gated) | Opt out **entirely** of the churn-gated postmortem tail — no `/pr-postmortem` is dispatched regardless of churn (AC13). Config equivalent: `auto_postmortem: false` in `.supervisor/notify-config.json`. Only meaningful with `--until-mergeable`. |
| `--postmortem-churn-threshold N` | No | `2` | Fix-cycle trigger bar for the churn-gated postmortem tail: postmortem fires only when `fix_cycles > N` (among the other OR-triggers — AC11). Config equivalent: `.postmortem_churn_threshold` in `.supervisor/notify-config.json` (read via jq). Only meaningful with `--until-mergeable`. |

## What This Does

1. **PR-URL → branch resolution.** `HEAD_REF=$(gh pr view <pr-url> --json headRefName --jq '.headRefName')`; `git fetch origin "$HEAD_REF"`; `git checkout "$HEAD_REF"`.
2. **Bounded review→fix→re-review loop** (default 3 iterations — the `--heal-iterations` analogue):
   - `Task(ai-agent-manager-plugin:code-reviewer)` reviews the PR-branch diff (`CODE_REVIEW_RESULT` v3, `review_mode: diff_review`).
   - **PASS** → done. The diff is clean. **Does NOT merge** — the PR is left open for a human.
   - **FAIL** (≥1 `new` + BLOCKING/HIGH issue) → spawn a `Task(general-purpose)` fix worker (Read / Write / Edit / Bash / Glob / Grep, **no Task**) that addresses ONLY those findings, then `git push` to the PR branch (**never `--force`**), then re-review.
   - **NEEDS_HUMAN, or the loop exhausts with issues remaining** → **STOP. Do NOT auto-fix, do NOT merge.** Post findings to the PR (`gh pr comment`), fire best-effort notifications (`notify-desktop.sh` / `send-webhook.sh`), exit as `ESCALATED`.
3. **No auto-merge, no PR creation.** Terminal states leave the PR open: `PASS` (human merges) and `ESCALATED` (human attention). `/review-pr` never creates a PR, which prevents a review→review recursion.

> **Without `--until-mergeable` the behavior above is byte-for-byte the existing diff-only loop (AC7).** The new mode is strictly additive and opt-in — the default path reads no external state, runs no postmortem tail, and emits only `PASS`/`ESCALATED` at `schema_version: 1`.

## `--until-mergeable` mode (opt-in drain)

When `--until-mergeable` is passed, an **additive** drain loop runs on top of the default loop. It drains the **machine-speed** external review signals and never waits on a human. Authority is the `review-heal` skill §"Until-Mergeable Mode"; this command documents the surface only — it does not re-coin any name.

1. **Each round reads external state.** `gh pr view <url> --json statusCheckRollup,reviews,latestReviews,reviewDecision,mergeable,mergeStateStatus` PLUS `gh api graphql` for unresolved review threads (each thread's `isResolved` + first-comment `author.login`/`__typename`) PLUS branch-protection **required-check discovery** (AC14). A GraphQL thread-query error or unreadable required-check metadata fails **CLOSED** to `ESCALATED` (never default-to-green) — unless `--required-checks all-non-neutral` is set.
2. **Fix → push → re-poll.** Actionable required-check failures and unresolved **bot-authored** threads are handed to a `Task(general-purpose)` fix worker (Read / Write / Edit / Bash / Glob / Grep, **no Task**), followed by a regular `git push` (**never `--force`**), then the loop re-polls.
3. **READY terminal state (AC3).** When **all required checks are green AND no unresolved bot-authored review threads remain**, the loop exits `decision: READY` and fires the desktop + webhook **"ready to merge"** notification best-effort (`notify-desktop.sh` / `send-webhook.sh`). **It never merges** — there is no `gh pr merge` anywhere; `READY` is terminal-stop-and-notify, merge-identical to `PASS`/`ESCALATED`, and the PR is left open for a human. **READY ⇔ required checks green AND no unresolved bot-authored threads.** Human approval, `reviewDecision: REVIEW_REQUIRED`, and human-authored unresolved threads are **surfaced/notified but NEVER awaited** — the loop never blocks on a human.
4. **Bounded by `--max-rounds` (default 5).** On exhaustion without reaching READY, the loop exits `decision: ESCALATED` (AC4), posts remaining findings via `gh pr comment`, and notifies — never unbounded. An anti-churn guardrail runs one deep "fix-the-class" self-review on oscillation but never overrides the `--max-rounds` ceiling.
5. **Churn-gated auto-postmortem tail.** After the decision is computed and `REVIEW_HEAL_RESULT` is emitted, a fail-safe tail conditionally fires the existing read-only `/pr-postmortem <pr-url>` via `scripts/dispatch-pr-postmortem.sh`. It is **ON by default within `--until-mergeable` but churn-gated** — a clean/low-churn PR is a silent no-op. It fires when ANY of: `fix_cycles > postmortem-churn-threshold` (default **2**, set via `--postmortem-churn-threshold N` / `.postmortem_churn_threshold`), `decision == ESCALATED`, a required check re-failed after a fix, or bot feedback remained unresolved after a fix (AC10/AC11). Opt out entirely with `--no-auto-postmortem` (or `auto_postmortem: false`) — AC13. The dispatcher **always exits 0** and can NEVER change `REVIEW_HEAL_RESULT.decision` — the decision is emitted before dispatch.

## Output — `REVIEW_HEAL_RESULT`

The run ends by emitting a `REVIEW_HEAL_RESULT` block (defined by the `review-heal` skill): `schema_version: 1` for the default diff-only loop, or `schema_version: 2` under `--until-mergeable` (which adds the `READY` decision + drain fields — schema owned by `docs/RESULT_SCHEMAS.md`):

```
## REVIEW_HEAL_RESULT
- schema_version: 1
- decision: PASS | ESCALATED        # enum — PASS|ESCALATED (default loop); READY is added only under --until-mergeable (v2)
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
