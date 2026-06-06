---
name: review-heal
description: Shared loop contract for the standalone PR review-and-heal workflow (`/review-pr <pr-url>` + `ai-agent-manager-plugin:review-pr-runner`). Single source of truth for the bounded review→fix→re-review loop, PR-URL→branch resolution, the REVIEW_HEAL_RESULT block, and the pinned canonical names consumed by the dispatcher script, the runner agent, and the autonomous EVALUATE step. Use when implementing or invoking standalone PR review-and-heal.
allowed-tools: [Read, Write, Edit, Bash, Task]
version: "1.0.0"
lastUpdated: "2026-06-06"
---

# Review-Heal Skill

The **single source of truth** for the standalone PR review-and-heal loop. This skill is where the canonical names below are *coined* — every other surface (the `/review-pr` command, the `ai-agent-manager-plugin:review-pr-runner` agent, the `dispatch-pr-review.sh` dispatcher, and the `/autonomous` EVALUATE step) consumes these names **verbatim** and must not re-coin or rename them.

The loop is conceptually extracted from Supervisor **Phase 4.5**'s review→fix→re-review machinery (`ai-agent-manager-plugin/agents/supervisor.md`, around the `while heal_iterations < max_heal_iterations` block) so it can run **independently in a fresh session keyed off a PR URL** — with no Supervisor job, no `.supervisor/state.md`, and no worktree fan-out. It mirrors Phase 4.5's semantics exactly; it does **not** invent new ones.

> This is a **reference contract** skill (markdown prose, NOT executable code), in the same spirit as `skills/autonomous-loop/SKILL.md` and `skills/state-management/SKILL.md`.

---

## Pinned Canonical Names

These names are **coined here**. Treat this section as authoritative; all other subtasks reference these without re-coining.

| Kind | Canonical name | Notes |
|---|---|---|
| Result block | **`REVIEW_HEAL_RESULT`** | `schema_version: 1`. Fields below. |
| New agent | **`ai-agent-manager-plugin:review-pr-runner`** | Registered in `agents/review-pr.md`. |
| New command | **`/review-pr <pr-url>`** | Inline main-thread workflow body referencing this skill. |
| New skill | **`review-heal`** | This file. |
| Opt-out flag | **`--no-auto-review`** | Suppresses the post-`/supervisor` auto-dispatch. |
| Enable signal | **`auto_review: true`** in `.supervisor/notify-config.json` (or a **`--auto-review`** flag) | Either turns on auto-dispatch. |
| Dispatcher script | **`ai-agent-manager-plugin/scripts/dispatch-pr-review.sh`** | Gated, config-file-driven, cost/runaway-guarded, **always exits 0**. |

### `REVIEW_HEAL_RESULT` block

```
## REVIEW_HEAL_RESULT
- schema_version: 1
- decision: PASS | ESCALATED        # enum — exactly these two values
- iterations: <int>                 # how many review→fix→re-review cycles ran
- issues_fixed: <int>               # count of new+BLOCKING/HIGH issues addressed by fix workers
- remaining_issues: <int>           # new+BLOCKING/HIGH issues still open at exit
- pr_url: "<string>"                # the PR this run operated on
- notified: <bool>                  # true if a NEEDS_HUMAN notification was attempted
```

**Decision enum is exactly `PASS | ESCALATED`** — there is no `FAIL` in the *result* block. A reviewer `FAIL` is an internal loop signal that drives a fix iteration; it only becomes a terminal outcome as `ESCALATED` (when the loop exhausts or the reviewer escalates).

---

## Two entry senses of "fresh"

The loop is "spawned fresh" in two distinct, non-interchangeable ways:

- **(a) Plain `/supervisor` completion-tail → fresh OS process.** After a `/supervisor` run finishes and (per the enable signal) auto-review is on, the dispatcher launches a brand-new `claude --agent ai-agent-manager-plugin:review-pr-runner` **operating-system process**. This is a true fresh session — the runner is the *main agent* of its own session and can therefore spawn child agents.
- **(b) `/autonomous` EVALUATE → Task-spawned step.** Inside an autonomous run, the review-heal step runs as a **Task-spawned step with fresh isolated context** — NOT a nested `claude` process. (See the execution-contract rule below for why this distinction matters.)

---

## Execution-contract rule (AC9)

The runner **spawns child agents** (a `code-reviewer` for the review, and a `general-purpose` fix worker for the fix). Because *subagents cannot spawn subagents* (Claude Code limitation), the runner must run ONLY as:

- the **main agent of its own session** — `claude --agent ai-agent-manager-plugin:review-pr-runner`, or
- **inline on the main thread** via `/review-pr <pr-url>` (the slash-command body is workflow instructions executed inline).

The runner is **NEVER Task-spawned**. A `Task(ai-agent-manager-plugin:review-pr-runner)` call would land the runner one spawn-level too deep and its own `Task(code-reviewer)` / `Task(general-purpose)` calls would fail. In the `/autonomous` EVALUATE sense (b) above, the *review-heal loop body* is what runs as a Task step — that step itself runs inline review-and-fix logic, it does not Task-spawn the `-runner` agent.

---

## Step 1 — PR-URL → branch resolution

Before the loop runs, resolve the PR's head branch and check it out:

```
HEAD_REF=$(gh pr view <pr-url> --json headRefName --jq '.headRefName')
git fetch origin "$HEAD_REF"
git checkout "$HEAD_REF"
```

- The single input is the **PR URL**. `gh pr view <pr-url> --json headRefName` yields the head branch (`headRefName`); fetch + checkout that branch before entering the loop so the diff and any pushes target the correct branch.
- The review scope is the PR diff: `git diff <base>...HEAD` for the PR's base branch (default `main`). The reviewer is told to scope to exactly this diff.

---

## Step 2 — The bounded review→fix→re-review loop

Mirrors Supervisor Phase 4.5 semantics exactly. **Default bound is 3 iterations** (the `--heal-iterations` analogue).

```
heal_iterations = 0
issues_fixed = 0
max_heal_iterations = 3            # default; bounded

while heal_iterations < max_heal_iterations:
  review = Task(
    subagent_type: "ai-agent-manager-plugin:code-reviewer",
    prompt: "Review the PR-branch diff (git diff <base>...HEAD) for this PR.
             Schema: CODE_REVIEW_RESULT v3, review_mode: diff_review,
             category field: new / pre_existing / nit / drift."
  )
  # Parse the CODE_REVIEW_RESULT block.

  if review.decision == PASS:
    decision = PASS
    remaining_issues = 0
    break                          # done — DO NOT merge (see "No auto-merge")

  if review.decision == NEEDS_HUMAN:
    decision = ESCALATED
    remaining_issues = count(new issues with severity in [BLOCKING, HIGH])
    # STOP — do NOT auto-fix, do NOT merge.
    post findings to PR (gh pr comment ...)
    notify (best-effort — see "Notify on NEEDS_HUMAN")
    break

  # decision == FAIL — by CODE_REVIEW_RESULT rule, >=1 new + BLOCKING/HIGH issue exists.
  fixable = [i for i in review.issues if i.category == "new" and i.severity in (BLOCKING, HIGH)]

  Task(
    subagent_type: "general-purpose",
    # Tool allowlist: Read, Write, Edit, Bash, Glob, Grep — NO Task
    # (the fix worker may not dispatch further subagents).
    prompt: "Address ONLY these new+BLOCKING/HIGH review findings: {fixable}.
             Do NOT touch pre_existing issues or nits. Update tests if behaviour
             changes. Run type-check + tests locally before finishing."
  )
  # issues_fixed += number of findings addressed

  git push                         # update the PR branch — REGULAR push, NEVER --force
  heal_iterations += 1

# Loop exit
if heal_iterations == max_heal_iterations and review.decision != PASS:
  decision = ESCALATED
  remaining_issues = count(new issues with severity in [BLOCKING, HIGH])
  post findings to PR (gh pr comment ...)
  notify (best-effort)
```

### Outcome model

- **PASS** → `decision: PASS`. The diff is clean. The loop is **done**. It does **not** merge.
- **FAIL** (reviewer returned `new` issues with severity BLOCKING/HIGH) → spawn a `Task(general-purpose)` fix worker (allowlist Read / Write / Edit / Bash / Glob / Grep, **no Task**) that addresses ONLY those issues, then `git push` to the PR branch (**never `--force`**), then re-review. Bounded to N iterations (**default 3**).
- **NEEDS_HUMAN** (reviewer escalates) **or loop exhausts with issues remaining** → **STOP. Do NOT auto-fix, do NOT merge.** Post the findings to the PR via `gh pr comment`, fire notifications best-effort, exit with `decision: ESCALATED`.

### Never `--force`

Pushes that update the PR branch are **regular pushes only**. A force-push would clobber concurrent commits on the PR branch (the human author may have pushed). This mirrors Phase 4.5's `git push  # ... NEVER --force` rule.

---

## Step 3 — Notify on NEEDS_HUMAN (best-effort, fire-and-forget)

When the loop exits as `ESCALATED` (reviewer `NEEDS_HUMAN`, or exhausted with issues), fire **best-effort** notifications. These calls **NEVER block and NEVER fail the loop** — both scripts are designed to always exit 0; any error (missing `jq`, missing `curl`, unset webhook URL, malformed payload) is absorbed silently.

- **Desktop banner:** `${CLAUDE_PLUGIN_ROOT}/scripts/notify-desktop.sh` — reads a JSON hook-style payload on **stdin**, builds a `(title, body)` pair, and fires an OS-native banner (macOS `osascript` / clickable `terminal-notifier`; Linux `notify-send`). It is opt-out via `AI_AGENT_MANAGER_DESKTOP_NOTIFICATIONS=0` and **always exits 0**.
- **Webhook:** `${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh` — gated on a resolvable webhook URL (`AI_AGENT_MANAGER_WEBHOOK_URL`, or the `.supervisor/notify-config.json` → `.webhook_url` fallback, which the script resolves internally). The `--event-type gate` path takes its fields from CLI flags (`--gate-type`, `--iteration`, `--session-id`, `--context`) and builds the payload with `jq --arg` exclusively (injection-safe). It POSTs fire-and-forget with a hard 5s timeout and **always exits 0**.

Set `notified: true` in `REVIEW_HEAL_RESULT` whenever a NEEDS_HUMAN/escalation notification was attempted (regardless of whether the banner/webhook actually delivered — delivery is best-effort and unobservable from the loop).

---

## No auto-merge ever

This loop **NEVER merges a PR.** It honors the no-self-trust / don't-weaken-a-gate principle: an automated reviewer that also merges its own approval removes the human gate. The loop's terminal states are:

- `PASS` — clean diff, loop done, **PR left open for a human to merge**.
- `ESCALATED` — findings posted to the PR, notifications fired, **PR left open** for human attention.

Additionally, **`/review-pr` does not create PRs** (it only operates on an existing PR URL). This deliberately prevents a review→review recursion: because the loop produces no new PR, the post-`/supervisor` auto-dispatch (or `/autonomous` EVALUATE) cannot retrigger itself on a PR it just created.

---

## Anti-Patterns

- **Force-pushing the PR branch.** Never `git push --force` — clobbers concurrent author commits. Regular push only.
- **Auto-merging on PASS.** Removes the human gate; explicitly forbidden.
- **Task-spawning the runner.** `Task(ai-agent-manager-plugin:review-pr-runner)` breaks because the runner must spawn its own children — run it as a session main agent or inline via `/review-pr`.
- **Creating a PR from `/review-pr`.** Would open the door to review→review recursion.
- **Letting notify failures abort the loop.** The notify scripts are fire-and-forget; treat their exit codes as advisory only (they always exit 0 anyway).
- **Re-coining any pinned name.** Other subtasks consume the names above verbatim — renaming here breaks the contract.

## Related Skills

- `skills/autonomous-loop/SKILL.md` — the `/autonomous` outer loop; its EVALUATE step is entry sense (b) for review-heal.
- `skills/state-management/SKILL.md` — `.supervisor/` conventions, including `notify-config.json` where `auto_review` and `webhook_url` live.
- Supervisor Phase 4.5 (`agents/supervisor.md`) — the in-Supervisor review→fix→re-review machinery this loop is extracted from.

## Quality Gates

- PR-URL → branch resolved via `gh pr view <pr-url> --json headRefName`; branch fetched + checked out before the loop.
- Review uses `CODE_REVIEW_RESULT` v3 with `review_mode: diff_review`.
- Loop is bounded (default 3); fix worker is `general-purpose` with NO Task in its allowlist.
- PR-branch pushes are regular (never `--force`).
- PASS and ESCALATED are the only terminal `decision` values; no auto-merge in either.
- NEEDS_HUMAN / exhaustion posts findings to the PR and fires best-effort notifications (never blocks the loop).
- `REVIEW_HEAL_RESULT` emitted with all seven fields at `schema_version: 1`.
