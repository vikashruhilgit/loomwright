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
| `--until-mergeable` | No | off | **Opt-in, strictly additive** drain mode. Layers the external-signal drain loop on top of the default diff-only loop: each round reads **ALL** review channels (formal/bot reviews, inline review threads, **PR issue comments**, and check-run outputs/annotations), waits for the **scoped** required + review-producing check set to settle, **validates** each detected bot finding and auto-fixes the confirmed ones (any stated severity — validate-then-fix, no BLOCKING/HIGH floor), pushes, and re-polls until **READY** → `decision: READY` + "ready to merge" notification. **Never merges, never waits on a human.** **Absent ⇒ behavior is byte-for-byte the existing diff-only loop** (AC7). Authority for the channel set, scoped wait, validate-then-fix, and the READY equivalence: `review-heal` skill §"Until-Mergeable Mode" (the single source of truth — not restated here). |
| `--max-rounds N` | No | `5` | Hard ceiling on `--until-mergeable` drain rounds. On exhaustion without reaching READY, the loop exits `decision: ESCALATED`, posts remaining findings via `gh pr comment`, and notifies — never unbounded (AC4). Only meaningful with `--until-mergeable`. |
| `--required-checks all-non-neutral` | No | fail closed | **Opt-in fallback** for `--until-mergeable` when branch-protection required-check metadata is **unreadable** (insufficient permissions / no branch protection / API error). Default behavior **fails CLOSED** — unreadable metadata ⇒ the loop MUST NOT claim READY and exits `ESCALATED` (AC14). Passing `all-non-neutral` opts into treating every check whose state is not `NEUTRAL`/`SKIPPED` as blocking, so the drain can proceed without the metadata. |
| `--check-wait-timeout N` | No | 600 (10 min) | Seconds to **bounded-wait** for the *scoped* set (required + review-producing checks) to settle before each READY test, so a late-posting review check is seen rather than missed; it NEVER waits on unrelated optional checks. Polled every 15s. Only meaningful with `--until-mergeable`. **Authoritative definition:** `review-heal` skill §"Wait-For-Settled-Checks". |
| `--review-check-pattern <glob>` | No | `*review*` / `claude*` | Glob(s) that mark a check as **review-producing** (in addition to required checks), widening the scoped wait/scan set; combinable with the `config` include/exclude list (exclude wins). Only meaningful with `--until-mergeable`. **Authoritative definition:** `review-heal` skill §"All-Channel Read" / §"Wait-For-Settled-Checks". |
| `--no-auto-postmortem` | No | postmortem on (churn-gated) | Opt out **entirely** of the churn-gated postmortem tail — no `/pr-postmortem` is dispatched regardless of churn (AC13). Config equivalent: `auto_postmortem: false` in `.supervisor/config.json` (legacy `.supervisor/notify-config.json` is still read as a fallback; the new path wins when both exist). Only meaningful with `--until-mergeable`. |
| `--postmortem-churn-threshold N` | No | `2` | Fix-cycle trigger bar for the churn-gated postmortem tail: postmortem fires only when `fix_cycles > N` (among the other OR-triggers — AC11). Config equivalent: `.postmortem_churn_threshold` in `.supervisor/config.json` (read via jq). Only meaningful with `--until-mergeable`. |

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

When `--until-mergeable` is passed, an **additive** drain loop runs on top of the default loop. It drains the **machine-speed** external review signals and never waits on a human. **Authority is the `review-heal` skill §"Until-Mergeable Mode" — the single source of truth for the channel set, the scoped wait, validate-then-fix, and the canonical READY equivalence.** This command documents the surface only; it does not re-coin any name nor restate the READY definition (referenced, not duplicated — R5 mirror-drift avoidance).

1. **Each round reads ALL review channels.** Required CI check-runs (rollup) PLUS **formal/bot reviews**, **inline review threads**, **PR issue comments**, and **check-run outputs/annotations** — the readiness decision is computed over the UNION of every channel (the #64 finding landed as a PR issue comment that `gh pr view --json reviews` never returns). Findings are classified on `(login, body)` text via `scripts/classify-bot-review.sh`. Any **unknown** gated channel (GraphQL thread error/truncation, errored issue-comment read, errored required/review-producing check-output fetch, unreadable required-check metadata) fails **CLOSED** to `ESCALATED` — unless `--required-checks all-non-neutral` is set. See `review-heal` skill §"All-Channel Read" / §"Required-check discovery".
2. **Wait for the scoped check set, then re-scan.** Before each READY test the loop bounded-waits (`--check-wait-timeout N`) for the **scoped** set — required + review-producing checks (default `*review*`/`claude*`, overridable via `--review-check-pattern`) — to settle, then re-scans ALL channels so a late-posting review check is seen. It NEVER waits on unrelated optional checks. See `review-heal` skill §"Wait-For-Settled-Checks".
3. **Validate → fix → push → re-poll.** Every detected bot finding (any channel, **any stated severity** — no BLOCKING/HIGH floor) is **validated** against the current branch; confirmed auto-fixable findings are handed to a `Task(general-purpose)` fix worker (Read / Write / Edit / Bash / Glob / Grep, **no Task**), followed by a regular `git push` (**never `--force`**), then the loop re-polls. Stale/ungrounded findings are dismissed, not fixed. See `review-heal` skill §"Validate-Then-Fix".
4. **READY terminal state (AC3).** When the canonical READY condition holds, the loop exits `decision: READY` and fires the desktop + webhook **"ready to merge"** notification best-effort (`notify-desktop.sh` / `send-webhook.sh`). **It never merges** — there is no `gh pr merge` anywhere; `READY` is terminal-stop-and-notify, merge-identical to `PASS`/`ESCALATED`, and the PR is left open for a human. Human approval, `reviewDecision: REVIEW_REQUIRED`, and human-authored / unknown-author unresolved threads & comments are **surfaced/notified but NEVER awaited** — the loop never blocks on a human. The authoritative READY equivalence (required green AND scoped review-producing settled AND no unresolved validated bot findings across ALL channels) lives in `review-heal` skill §"READY redefinition" — not restated here.
5. **Bounded by `--max-rounds` (default 5).** On exhaustion without reaching READY, the loop exits `decision: ESCALATED` (AC4), posts remaining findings via `gh pr comment`, and notifies — never unbounded. An anti-churn guardrail runs one deep "fix-the-class" self-review on oscillation but never overrides the `--max-rounds` ceiling.
6. **Churn-gated auto-postmortem tail.** After the decision is computed and `REVIEW_HEAL_RESULT` is emitted, a fail-safe tail conditionally fires the existing read-only `/pr-postmortem <pr-url>` via `scripts/dispatch-pr-postmortem.sh`. It is **ON by default within `--until-mergeable` but churn-gated** — a clean/low-churn PR is a silent no-op. It fires when ANY of: `fix_cycles > postmortem-churn-threshold` (default **2**, set via `--postmortem-churn-threshold N` / `.postmortem_churn_threshold`), `decision == ESCALATED`, a required check re-failed after a fix, or bot feedback remained unresolved after a fix (AC10/AC11). Opt out entirely with `--no-auto-postmortem` (or `auto_postmortem: false`) — AC13. The dispatcher **always exits 0** and can NEVER change `REVIEW_HEAL_RESULT.decision` — the decision is emitted before dispatch.

### How Supervisor's auto-run threads `--until-mergeable` (env-var dispatch signal)

Supervisor's post-run auto-dispatch launches the runner via the no-flag-surface form `claude -p --agent ai-agent-manager-plugin:review-pr-runner "<pr-url>"` (avoids the 11.1.1 spawn-depth auto-delegation trap), so it cannot pass `/review-pr` flags on the command line. Instead it threads the signal through environment variables that the `review-pr-runner` agent reads and translates into the flags above:

- `AI_AGENT_MANAGER_UNTIL_MERGEABLE` (truthy ⇒ runner forwards `--until-mergeable`; absent/falsy ⇒ default diff-only loop),
- `AI_AGENT_MANAGER_CHECK_WAIT_TIMEOUT` (⇒ `--check-wait-timeout`), and
- `AI_AGENT_MANAGER_REVIEW_CHECK_PATTERN` (⇒ `--review-check-pattern`).

Authoritative contract (setter ↔ reader, default-ON/opt-out policy): `review-heal` skill §"Until-Mergeable Dispatch Signal".

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
