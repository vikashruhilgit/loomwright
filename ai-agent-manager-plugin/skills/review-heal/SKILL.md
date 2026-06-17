---
name: review-heal
description: Shared loop contract for the standalone PR review-and-heal workflow (`/review-pr <pr-url>` + `ai-agent-manager-plugin:review-pr-runner`). Single source of truth for the bounded review→fix→re-review loop, PR-URL→branch resolution, the REVIEW_HEAL_RESULT block, and the pinned canonical names consumed by the dispatcher script, the runner agent, and the autonomous EVALUATE step. Use when implementing or invoking standalone PR review-and-heal.
allowed-tools: [Read, Write, Edit, Bash, Task]
version: "1.1.0"
lastUpdated: "2026-06-17"
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
| Result block | **`REVIEW_HEAL_RESULT`** | `schema_version: 1` (default loop) / `schema_version: 2` under `--until-mergeable` (adds the `READY` decision + drain fields — schema owned by `docs/RESULT_SCHEMAS.md`). |
| New agent | **`ai-agent-manager-plugin:review-pr-runner`** | Registered in `agents/review-pr.md`. |
| New command | **`/review-pr <pr-url>`** | Inline main-thread workflow body referencing this skill. |
| New skill | **`review-heal`** | This file. |
| Opt-out flag | **`--no-auto-review`** | Suppresses the post-`/supervisor` auto-dispatch. |
| Enable signal | **`auto_review: true`** in `.supervisor/notify-config.json` (or a **`--auto-review`** flag) | Either turns on auto-dispatch. |
| Dispatcher script | **`ai-agent-manager-plugin/scripts/dispatch-pr-review.sh`** | Gated, config-file-driven, cost/runaway-guarded, **always exits 0**. |
| Until-mergeable mode | **`--until-mergeable`** | Opt-in drain loop (§"Until-Mergeable Mode"). Strictly additive — **absent ⇒ byte-for-byte the default loop**. |
| Drain bound | **`--max-rounds N`** (default 5) | Hard ceiling on drain rounds (§"Until-Mergeable Mode"). |
| Required-check fallback | **`--required-checks all-non-neutral`** | Opt-in fallback when branch-protection metadata is unreadable (default = fail closed → `ESCALATED`). |
| READY decision | **`READY`** | Drain terminal state — required checks green AND no unresolved bot-authored threads. Merge-identical to `PASS`/`ESCALATED` (**never merges**). Emitted ONLY under `--until-mergeable`. |
| Postmortem opt-out | **`--no-auto-postmortem`** (or `auto_postmortem: false`) | Suppresses the churn-gated postmortem tail (§"Postmortem Dispatch Tail"). |
| Postmortem threshold | **`--postmortem-churn-threshold N`** (default 2; `.postmortem_churn_threshold`) | Fix-cycle trigger bar for the postmortem tail. |
| Postmortem dispatcher | **`ai-agent-manager-plugin/scripts/dispatch-pr-postmortem.sh`** | Churn-gated, config-driven, **always exits 0**, NEVER alters the decision (§"Postmortem Dispatch Tail"). |

### `REVIEW_HEAL_RESULT` block

```
## REVIEW_HEAL_RESULT
- schema_version: 1
- decision: PASS | ESCALATED        # enum — exactly these two values (READY is added under --until-mergeable, schema v2 — see docs/RESULT_SCHEMAS.md)
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

- **(a) Plain `/supervisor` completion-tail → fresh OS process.** After a `/supervisor` run finishes and (per the enable signal) auto-review is on, the dispatcher launches a brand-new detached **HEADLESS** `claude -p --agent ai-agent-manager-plugin:review-pr-runner <pr-url>` **operating-system process**. This is a true fresh session — the runner is the *main agent* of its own session and can therefore spawn child agents (`-p` does not change that — it is still the top-level agent of its headless session). The `-p`/`--print` flag is **required**: `--agent` only *selects* the agent, it does NOT switch to headless mode, so plain `claude --agent …:review-pr-runner "<url>"` (no `-p`) is an *interactive* session that — detached with stdin from `/dev/null` and no TTY — is fragile and can hang on the first permission prompt instead of exiting. `-p` runs non-interactively and exits. The dispatcher adds **no** `--permission-mode` / `--dangerously-skip-permissions` (consistent with `dispatch-pr-postmortem.sh`); it relies on the project's existing permission settings (best-effort), so in a locked-down project the runner's fixes/pushes may be auto-denied (review-only) — it still exits cleanly. See `scripts/dispatch-pr-review.sh`.
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

## Until-Mergeable Mode

`--until-mergeable` is an **opt-in, strictly additive** drain loop layered *on top of* the default diff-only loop above. It drains the **machine-speed external review signals** on a PR — **required** CI check-runs, automated/bot reviews, and unresolved **bot-authored** review threads — auto-fixing the actionable BLOCKING/HIGH items, pushing, and re-polling until **all required checks are green AND no unresolved bot-authored review threads remain**, then stops with `decision: READY` and fires a "ready to merge" notification. **It NEVER merges** (see "No auto-merge ever") and **NEVER waits on a human** — human approval, `reviewDecision: REVIEW_REQUIRED`, and human-authored unresolved threads are surfaced/notified but are explicitly **not** readiness blockers.

> **AC7 — absent ⇒ unchanged.** When `--until-mergeable` is NOT passed, `/review-pr` runs the existing diff-only review→fix→re-review loop (Step 2) **byte-for-byte** — same `PASS`/`ESCALATED` terminal states, same `REVIEW_HEAL_RESULT` `schema_version: 1`, no external-state reads, no postmortem tail. This mode is purely opt-in; nothing about the default path changes.

### Step U1 — Read external state each round (AC1, PINNED)

Each drain round begins by reading the PR's external review state. Two signals need MORE than `gh pr view --json` — do **not** invent a `--json reviewThreads` flag (it does not exist):

```
# (a) core PR state — single gh pr view
gh pr view <pr-url> --json statusCheckRollup,reviews,latestReviews,reviewDecision,mergeable,mergeStateStatus

# (b) unresolved review threads + each thread's first-comment author type — GraphQL only
gh api graphql -f query='
  query($owner:String!,$repo:String!,$number:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$number){
        reviewThreads(first:100){
          pageInfo{ hasNextPage }
          nodes{
            isResolved
            comments(first:1){ nodes{ author{ login __typename } } }
          }
        }
      }
    }
  }' -F owner=<owner> -F repo=<repo> -F number=<number>
```

- `mergeStateStatus` / `mergeable` are **corroborating only** — they conflate "required check failing" with "approval missing" (which we deliberately ignore), so they are never the sole basis for a READY/ESCALATED decision.
- **Fail-safe (R1):** if the GraphQL thread query errors (or returns no parseable thread set), thread-state is **"unknown"** → the loop **MUST NOT claim READY** → it exits `decision: ESCALATED`. Unknown is never treated as "no blocking threads".
- **Truncation is unknown too (fail-CLOSED, >100 threads):** `reviewThreads(first:100)` caps at 100 and is **not paginated**. If `reviewThreads.pageInfo.hasNextPage == true`, the thread set is truncated — an unresolved bot thread could exist beyond #100 that this read never saw, and a truncated read otherwise *looks* like a complete one. So a truncated read is treated as **unknown** thread-state → the loop **MUST NOT claim READY** → it exits `decision: ESCALATED`, exactly like a GraphQL error. (Full pagination is a deliberate non-goal: escalating on the rare >100-thread PR keeps the U1 fail-CLOSED contract consistent — an undetected truncation must never become a false READY — without unbounded paging. The drain also re-polls as it resolves threads, so a genuinely-churning PR converges below the cap.)

### Step U2 — Required-check discovery (AC14, PINNED, fail CLOSED)

"Checks green" gates on **required** checks ONLY (optional/non-required failing checks never block READY). Discover the required contexts from branch-protection metadata:

```
# REST
gh api repos/<owner>/<repo>/branches/<base>/protection/required_status_checks
# …or GraphQL baseRef.branchProtectionRule.requiredStatusCheckContexts
```

- Gate READY only on the discovered required contexts; cross-reference them against `statusCheckRollup`.
- **Fail CLOSED:** if required-check metadata is **unavailable** (insufficient permissions, no branch protection, API error), the loop **MUST NOT claim READY** — it exits `decision: ESCALATED`. This is the "correctness gates fail CLOSED" invariant: an unverifiable required-check set is treated as not-green, never as green.
- **Escape hatch:** `--required-checks all-non-neutral` opts into a fallback that treats **every** check whose state is not `NEUTRAL`/`SKIPPED` as blocking (i.e. ignore the metadata gap and gate on all non-neutral checks). This is the only way to proceed without branch-protection metadata; default behavior remains fail-closed.

### Step U3 — Bot-vs-human thread classification (AC15)

An unresolved review thread is a **READY-blocker ONLY** when its first comment's author is a **bot**:

- `author.__typename == "Bot"`, **OR**
- `author.login` matches `*[bot]` (the GitHub App login convention).

Human-authored — or **unknown/unclassifiable** — unresolved threads are **surfaced in the notification but NEVER block READY** (AC3): the loop never waits on a human. (Unknown-author threads are surfaced so a human sees them before they merge; per R11 this is acceptable because READY never auto-merges.) Note the asymmetry with U1's fail-safe: a *GraphQL error* (no thread data at all) → `ESCALATED`; a *successfully-read* thread whose author cannot be classified as a bot → does not block (treated like a human thread, surfaced only).

### Step U4 — The bounded drain loop

```
rounds = 0
max_rounds = 5                      # default; --max-rounds N overrides; HARD ceiling
fix_cycles = 0                      # how many fix→push cycles ran (postmortem-gate input)
churn_rounds = 0                    # consecutive rounds whose fingerprint set didn't shrink
fingerprints_prev = {}              # see "Anti-Churn Guardrail"
repeat_check_failure = false        # a required check failed AGAIN after a fix (postmortem input)
unresolved_bot_feedback = false     # bot thread still open after >=1 fix (postmortem input)

while rounds < max_rounds:
  read external state            # Step U1
  required = discover_required_checks()   # Step U2 — ESCALATED (fail closed) if unavailable & not --required-checks all-non-neutral
  threads  = classify_threads()           # Step U3 — ESCALATED if GraphQL errored OR truncated (pageInfo.hasNextPage) — thread-state unknown

  required_failing = [c for c in required if c.state not in GREEN_STATES]
  blocking_threads = [t for t in threads if t.unresolved and t.author_is_bot]

  if required_failing == [] and blocking_threads == []:
    decision = READY                      # AC3 — required green AND no unresolved bot threads
    notify "ready to merge" (best-effort: desktop + webhook)
    break

  # else — actionable machine signals remain. Dispatch a fix worker (AC2).
  fixable = actionable BLOCKING/HIGH items from required_failing + blocking_threads
  Task(
    subagent_type: "general-purpose",
    # Tool allowlist: Read, Write, Edit, Bash, Glob, Grep — NO Task.
    prompt: "Address ONLY these required-check failures and bot-authored review-thread
             findings: {fixable}. Do NOT touch human-thread or optional-check items.
             Update tests if behaviour changes; run type-check + tests locally."
  )
  fix_cycles += 1

  git push                              # REGULAR push, NEVER --force (see "Never --force")

  # --- anti-churn bookkeeping (see "Anti-Churn Guardrail" for the rationale) ---
  fingerprints_now = { fingerprint(f) for f in fixable }   # {file, issue_category, rule} per finding
  repeat_after_fix = (fingerprints_now ∩ fingerprints_prev) != {}   # a supposedly-fixed class recurred
  if not (fingerprints_now ⊊ fingerprints_prev):           # set did NOT strictly shrink vs last round
    churn_rounds += 1
  else:
    churn_rounds = 0                                       # progress made → reset
  if repeat_after_fix or churn_rounds >= 2:                # trip condition (AC5/R3)
    run ONE deep "fix-the-class" self-review               # exactly once per trip; then continue
  fingerprints_prev = fingerprints_now
  rounds += 1

# Loop exit without READY → exhausted
if rounds == max_rounds and decision != READY:
  decision = ESCALATED                  # AC4 — bounded, never unbounded
  post remaining findings to PR (gh pr comment ...)
  notify (best-effort)

# Emit REVIEW_HEAL_RESULT (v2). iterations == rounds — the drain's bounded outer-loop
# counter IS the v1 `iterations` analogue (the `while rounds < max_rounds` loop mirrors v1's
# `while heal_iterations < max_heal_iterations`); the back-compat `iterations` field carries
# the same value as `rounds` so a v1 consumer reads a meaningful count. fix_cycles is the
# distinct fix→push count (≤ rounds).
iterations = rounds
```

`GREEN_STATES` are the check states that count as passing (e.g. `SUCCESS`; `NEUTRAL`/`SKIPPED` are non-blocking). Mark `repeat_check_failure = true` when a required check that was fixed re-fails in a later round, and `unresolved_bot_feedback = true` when a bot-authored thread remains unresolved after at least one fix cycle — both feed the Postmortem Dispatch Tail.

### Terminal states (until-mergeable)

- **`READY`** — required checks green AND no unresolved bot-authored threads. Loop done; **PR left open for a human to merge** (merge-identical to `PASS`); "ready to merge" notification fired.
- **`ESCALATED`** — `--max-rounds` exhausted with signals remaining, OR a fail-closed condition tripped (GraphQL thread query errored → thread-state unknown; required-check metadata unavailable without `--required-checks all-non-neutral`). Findings posted to the PR, notifications fired, **PR left open**.

There is **no `READY`-that-merges**. `READY` is terminal-stop-and-notify, exactly like `PASS`/`ESCALATED` (AC6).

---

## Anti-Churn Guardrail

The drain loop (and, by extension, any review→fix loop) can **oscillate** — a fix for one finding re-surfaces the same class of finding next round. The guardrail bounds that without ever going unbounded.

### Fingerprint (AC5, R3)

Each actionable finding is fingerprinted by the triple **`{file, issue_category, rule}`**:

- `file` — the path the finding points at.
- `issue_category` — the `CODE_REVIEW_RESULT`/check category (e.g. `new`, the failing check name, the bot-rule id).
- `rule` — the specific rule/lint id / check context that flagged it.

Two findings with the same triple across rounds are "the same class".

### Trip condition

The guardrail **trips** when EITHER:

1. a fingerprint that was supposedly fixed **repeats** in a later round (a *repeat* fingerprint after a fix), OR
2. `churn_rounds ≥ 2` (the same finding-class set has failed to shrink across two consecutive rounds).

### On a trip — ONE deep "fix-the-class" self-review

When tripped, run **exactly one** deep "fix-the-class" self-review pass **per trip**: instead of patching the symptom again, the fix worker is told to find and fix the *whole class* (the root cause shared by the repeating fingerprints), not the single instance. Then continue the loop.

- The deep pass runs **once per trip** — it does not re-fire every round.
- `--max-rounds` remains the **hard ceiling**: if oscillation persists, the loop still exits `ESCALATED` at `max_rounds`. The guardrail makes oscillation *less likely*, it never overrides the bound (R3 — "could loop forever" mitigation).

This mirrors the spirit of Supervisor Phase 4.5's bounded heal loop: bounded iterations + one escalation lever, never an open-ended retry.

---

## Postmortem Dispatch Tail

After an `--until-mergeable` run **finalizes its decision and emits `REVIEW_HEAL_RESULT`**, a churn-gated, fail-safe tail conditionally fires the EXISTING read-only `/pr-postmortem <pr-url>` so a meaningful-churn PR captures a learning signal. This tail can **NEVER** change whether the PR is declared ready.

### Cardinal guarantee (AC12, R9)

- The loop's `decision` is **computed and emitted BEFORE** the tail runs. The tail reads it as an input only.
- The dispatcher (`scripts/dispatch-pr-postmortem.sh`) is **fire-and-forget and `exit 0` on EVERY path** (mirrors `dispatch-pr-review.sh`).
- `/pr-postmortem` is **read-only** on the analyzed repo and **only appends** one JSONL line to `.supervisor/postmortem/results.jsonl` — it mutates no repo file.
- Therefore a postmortem dispatcher / gather / append **failure leaves `REVIEW_HEAL_RESULT.decision` unchanged** and the merge-ready result is identical to a run where postmortem succeeded. `postmortem_dispatched` is informational, NEVER a gate input — and because the result block is emitted **before** the tail runs, it reports the **churn-gate / dispatch-request** decision (knowable at emit time), **not** a guarantee the postmortem launched or completed (the best-effort dispatcher may still no-op).

### Churn gate (AC9/AC10/AC11) — fires only on meaningful churn

Auto-postmortem is **ON by default within `--until-mergeable`** but **churn-gated** — a clean PR is a silent no-op (AC9). The tail dispatches when **ANY** of these OR-triggers is true:

| Trigger | Source |
|---|---|
| `fix_cycles > postmortem_churn_threshold` (default **2**) | `--postmortem-churn-threshold N` or `.postmortem_churn_threshold` in `.supervisor/notify-config.json` (read via jq) |
| `decision == ESCALATED` (escalated / timed-out) | the loop's final decision |
| same required CI/check failure repeats after a fix | `repeat_check_failure` |
| bot/automated feedback remained unresolved after ≥1 fix | `unresolved_bot_feedback` |

If **NONE** trip (`fix_cycles ≤ threshold` AND `decision != ESCALATED` AND no repeat check failure AND no lingering bot feedback) → **no postmortem is dispatched** (AC9).

### Opt-out (AC13)

`--no-auto-postmortem` (or `auto_postmortem: false` in `.supervisor/notify-config.json`) opts out **entirely** — no postmortem regardless of churn. (NB: the config value is the boolean `false`; the dispatcher reads it as a raw value, never via jq `// empty`, so the falsy `false` is not silently coerced away.)

### Launch form (R10 — fresh detached process, NEVER a nested Task)

`/pr-postmortem` is dispatched as a **fresh detached HEADLESS `claude -p` OS process** — NEVER a nested `Task` spawn. The review-heal loop body is itself Task-spawned in the `/autonomous` EVALUATE sense (b), so a nested `Task(/pr-postmortem)` would land one spawn-level too deep (subagents cannot spawn subagents). The `-p`/`--print` flag is **required**: plain `claude "<prompt>"` (no `-p`) starts an *interactive REPL* which, detached with stdin from `/dev/null` and no TTY, never executes the slash command and never exits — `-p` runs the prompt non-interactively and exits. The dispatcher's launch line is:

```
( nohup "$CLAUDE_BIN" -p "/pr-postmortem $PR_URL" >>"$RUN_LOG" 2>&1 </dev/null & ) >/dev/null 2>&1 || true
```

(or a no-op when `claude`/config is absent). A per-PR marker under `.supervisor/postmortem-dispatch/` guards against re-dispatch — **once per PR per checkout** (persistent, not session-scoped); a PR that re-churns in a later session will not re-dispatch unless its marker file is removed. The exact invocation the tail makes:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-pr-postmortem.sh" "<pr-url>" \
  --fix-cycles "$fix_cycles" \
  --decision "$decision" \
  $( [ "$repeat_check_failure" = true ] && printf -- '--repeat-check-failure' ) \
  $( [ "$unresolved_bot_feedback" = true ] && printf -- '--unresolved-bot-feedback' ) \
  [--postmortem-churn-threshold N] [--no-auto-postmortem]
```

The tail's exit status is **ignored** — the dispatcher always exits 0 and the decision is already emitted.

---

## Anti-Patterns

- **Force-pushing the PR branch.** Never `git push --force` — clobbers concurrent author commits. Regular push only.
- **Auto-merging on PASS.** Removes the human gate; explicitly forbidden.
- **Task-spawning the runner.** `Task(ai-agent-manager-plugin:review-pr-runner)` breaks because the runner must spawn its own children — run it as a session main agent or inline via `/review-pr`.
- **Creating a PR from `/review-pr`.** Would open the door to review→review recursion.
- **Letting notify failures abort the loop.** The notify scripts are fire-and-forget; treat their exit codes as advisory only (they always exit 0 anyway).
- **Re-coining any pinned name.** Other subtasks consume the names above verbatim — renaming here breaks the contract.
- **Inventing a `gh pr view --json reviewThreads` flag.** Unresolved threads + author type are GraphQL-only (Step U1). The `--json` flag does not exist; use `gh api graphql`.
- **Claiming READY when a required-check or thread signal is unknown.** A GraphQL thread error or unreadable branch-protection metadata must fail CLOSED to `ESCALATED` — never default-to-green.
- **Blocking READY on a human.** Human approval, `REVIEW_REQUIRED`, and human/unknown-author threads are surfaced, never gated (AC3/AC15). The drain loop waits only on bots + required checks.
- **Letting the postmortem tail change the decision.** The decision is emitted BEFORE dispatch; the dispatcher always exits 0 and only appends to the trend file. A postmortem failure must be invisible to `REVIEW_HEAL_RESULT.decision` (AC12).
- **Dispatching `/pr-postmortem` as a nested `Task`.** Subagents cannot spawn subagents — launch a fresh detached `claude` process via `dispatch-pr-postmortem.sh` (R10).

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
- `REVIEW_HEAL_RESULT` emitted with all seven fields at `schema_version: 1` (default loop); `schema_version: 2` with `decision: READY` under `--until-mergeable`.
- **`--until-mergeable` absent ⇒ default loop byte-for-byte unchanged** (AC7) — the drain, anti-churn, and postmortem-tail logic are strictly opt-in.
- Under `--until-mergeable`: external state read via `gh pr view --json statusCheckRollup,…` PLUS `gh api graphql` review-threads PLUS branch-protection required-check discovery; READY gates on **required** checks + **bot-authored** unresolved threads only; fails CLOSED to `ESCALATED` on unknown thread/required-check state; bounded by `--max-rounds` (default 5); **never auto-merges (the no-auto-merge invariant holds — READY is terminal-stop-and-notify)**.
- Postmortem Dispatch Tail runs AFTER the decision is emitted, is churn-gated (default threshold 2), opt-out via `--no-auto-postmortem`, and can never alter `REVIEW_HEAL_RESULT.decision` (`dispatch-pr-postmortem.sh` always exits 0).
