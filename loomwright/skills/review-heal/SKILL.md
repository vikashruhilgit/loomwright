---
name: review-heal
description: Shared loop contract for the standalone PR review-and-heal workflow (`/review-pr <pr-url>` + `loomwright:review-pr-runner`). Single source of truth for the bounded review→fix→re-review loop, PR-URL→branch resolution, the REVIEW_HEAL_RESULT block, and the pinned canonical names consumed by the dispatcher script, the runner agent, and the autonomous EVALUATE step. Use when implementing or invoking standalone PR review-and-heal.
allowed-tools: [Read, Write, Edit, Bash, Task]
version: "1.6.0"
lastUpdated: "2026-08-04"
---

# Review-Heal Skill

The **single source of truth** for the standalone PR review-and-heal loop. This skill is where the canonical names below are *coined* — every other surface (the `/review-pr` command, the `loomwright:review-pr-runner` agent, the `dispatch-pr-review.sh` dispatcher, and the `/autonomous` EVALUATE step) consumes these names **verbatim** and must not re-coin or rename them.

The loop is conceptually extracted from Supervisor **Phase 4.5**'s review→fix→re-review machinery (`loomwright/agents/supervisor.md`, around the `while heal_iterations < max_heal_iterations` block) so it can run **independently in a fresh session keyed off a PR URL** — with no Supervisor job and no `.supervisor/state.md`. The **inline** `/review-pr` session has no worktree fan-out (it operates on the main thread's checkout), but the **detached dispatched** until-mergeable drain runs in its own dispatcher-created sibling worktree (see §"Isolated worktree for the detached dispatched drain"). It mirrors Phase 4.5's semantics exactly; it does **not** invent new ones.

> This is a **reference contract** skill (markdown prose, NOT executable code), in the same spirit as `skills/autonomous-loop/SKILL.md` and `skills/state-management/SKILL.md`.

---

## Pinned Canonical Names

These names are **coined here**. Treat this section as authoritative; all other subtasks reference these without re-coining.

| Kind | Canonical name | Notes |
|---|---|---|
| Result block | **`REVIEW_HEAL_RESULT`** | `schema_version: 1` (default loop) / `schema_version: 2` under `--until-mergeable` (adds the `READY` decision + drain fields — schema owned by `docs/RESULT_SCHEMAS.md`). |
| New agent | **`loomwright:review-pr-runner`** | Registered in `agents/review-pr.md`. |
| New command | **`/review-pr <pr-url>`** | Inline main-thread workflow body referencing this skill. |
| New skill | **`review-heal`** | This file. |
| Opt-out flag | **`--no-auto-review`** | Suppresses the post-`/supervisor` auto-dispatch. |
| Enable signal | **`auto_review: true`** in `.supervisor/config.json` (legacy `.supervisor/notify-config.json` is still read as a fallback; new path wins when both exist) (or a **`--auto-review`** flag) | Either turns on auto-dispatch. |
| Dispatcher script | **`loomwright/scripts/dispatch-pr-review.sh`** | Gated, config-file-driven, cost/runaway-guarded, **always exits 0**. |
| Until-mergeable mode | **`--until-mergeable`** | Opt-in, **heal-only** drain loop (§"Until-Mergeable Mode") that **replaces** the default loop's review half — **absent ⇒ byte-for-byte the default loop**. |
| Earned fallback trigger | **`no_review_lens_posted`** | Coined in §"Earned Fallback Review — `no_review_lens_posted`". True when §U1's existing read shows no bot-authored finding in any channel AND every review-producing check is green-with-empty-output/absent/skipped. Gates the drain's ONE exception to heal-only: exactly one `code-reviewer` diff review per drain run, fail-CLOSED toward running it. |
| Drain bound | **`--max-rounds N`** (default 5) | Hard ceiling on drain rounds (§"Until-Mergeable Mode"), **mechanized** by `scripts/drain-rounds.sh` (`init`/`bump`/`check`/`read`) — the SAME ledger call on the SAME §U4 path both entry senses run, never a private per-path counter (AC1/AC2). |
| Severity floor | **`--severity-floor <BLOCKING\|HIGH\|MEDIUM\|LOW>`** (default `HIGH`) | **Termination-only** — see §"Termination-only severity floor (`sub_floor_converged`)". Does NOT gate whether a finding is fixed (Validate-Then-Fix, §U3.5, is unchanged); gates only whether a round whose entire fixed yield was below this severity starts another round. |
| Required-check fallback | **`--required-checks all-non-neutral`** | Opt-in fallback when branch-protection metadata is unreadable (default = fail closed → `ESCALATED`). |
| Scoped check-wait bound | **`--check-wait-timeout N`** (seconds) | Bounded wait for the **scoped set** (required + review-producing checks) to settle (§"Wait-For-Settled-Checks"). Only applies under `--until-mergeable`; **default 600** (10 min), polled every **15s**. Forwarded from the dispatcher via `LOOMWRIGHT_CHECK_WAIT_TIMEOUT`. |
| Review-producing check selector | **`--review-check-pattern <glob>`** (default `*review*`/`claude*`) | Globs that mark a check as "review-producing" (in addition to required checks), widening the scoped wait/scan set (§"All-Channel Read", §"Wait-For-Settled-Checks"). Combinable with the `notify-config` include/exclude list. Forwarded from the dispatcher via `LOOMWRIGHT_REVIEW_CHECK_PATTERN`. |
| Supervisor-layer enable | **`auto_until_mergeable`** (config, Supervisor layer) | Default-ON/opt-out semantics for whether Supervisor's auto-dispatch threads `--until-mergeable`. **Owned by the Supervisor/dispatcher subtask**, referenced here (§"Until-Mergeable Dispatch Signal"); the drain loop itself only sees the resolved env-var signal. |
| READY decision | **`READY`** | Drain terminal state — required checks green AND review-producing checks settled AND no unresolved **validated** bot findings across ALL channels (§"READY redefinition" is the single source of truth). Merge-identical to `PASS`/`ESCALATED` (**never merges**). Emitted ONLY under `--until-mergeable`. |
| Postmortem opt-out | **`--no-auto-postmortem`** (or `auto_postmortem: false`) | Suppresses the churn-gated postmortem tail (§"Postmortem Dispatch Tail"). |
| Postmortem threshold | **`--postmortem-churn-threshold N`** (default 2; `.postmortem_churn_threshold`) | Fix-cycle trigger bar for the postmortem tail. |
| Postmortem dispatcher | **`loomwright/scripts/dispatch-pr-postmortem.sh`** | Churn-gated, config-driven, **always exits 0**, NEVER alters the decision (§"Postmortem Dispatch Tail"). |

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

Under `--until-mergeable` the block stays **`schema_version: 2`** (adds `decision: READY` plus the ADDITIVE/OPTIONAL drain fields — e.g. `channels_scanned`, `findings_validated`, `findings_dismissed`, `checks_waited`, and — as of this change — `termination_reason` (`converged` | `bound_hit` | `sub_floor_converged`, AC6), `severity_floor`, `sub_floor_fixed[]`). These new fields are additive only; the **authoritative schema text lives in `docs/RESULT_SCHEMAS.md`** — there is **no schema_version bump beyond 2**, and no `gh pr merge` field/path ever exists (never-auto-merge invariant).

**Decision enum is exactly `PASS | ESCALATED`** — there is no `FAIL` in the *result* block. A reviewer `FAIL` is an internal loop signal that drives a fix iteration; it only becomes a terminal outcome as `ESCALATED` (when the loop exhausts or the reviewer escalates).

---

## Two entry senses of "fresh"

The loop is "spawned fresh" in two distinct, non-interchangeable ways:

- **(a) Plain `/supervisor` completion-tail → fresh OS process.** After a `/supervisor` run finishes and (per the enable signal) auto-review is on, the dispatcher launches a brand-new detached **HEADLESS** `claude -p --agent loomwright:review-pr-runner <pr-url>` **operating-system process**. This is a true fresh session — the runner is the *main agent* of its own session and can therefore spawn child agents (`-p` does not change that — it is still the top-level agent of its headless session). The `-p`/`--print` flag is **required**: `--agent` only *selects* the agent, it does NOT switch to headless mode, so plain `claude --agent …:review-pr-runner "<url>"` (no `-p`) is an *interactive* session that — detached with stdin from `/dev/null` and no TTY — is fragile and can hang on the first permission prompt instead of exiting. `-p` runs non-interactively and exits. The dispatcher adds **no** `--permission-mode` / `--dangerously-skip-permissions` (consistent with `dispatch-pr-postmortem.sh`); it relies on the project's existing permission settings (best-effort), so in a locked-down project the runner's fixes/pushes may be auto-denied (review-only) — it still exits cleanly. See `scripts/dispatch-pr-review.sh`.
- **(b) `/autonomous` EVALUATE → Task-spawned step.** Inside an autonomous run, the review-heal step runs as a **Task-spawned step with fresh isolated context** — NOT a nested `claude` process. (See the execution-contract rule below for why this distinction matters.)

---

## Execution-contract rule (AC9)

The runner **spawns child agents** (a `code-reviewer` for the review, and a `general-purpose` fix worker for the fix). Because *subagents cannot spawn subagents* (Claude Code limitation), the runner must run ONLY as:

- the **main agent of its own session** — `claude --agent loomwright:review-pr-runner`, or
- **inline on the main thread** via `/review-pr <pr-url>` (the slash-command body is workflow instructions executed inline).

The runner is **NEVER Task-spawned**. A `Task(loomwright:review-pr-runner)` call would land the runner one spawn-level too deep and its own `Task(code-reviewer)` / `Task(general-purpose)` calls would fail. In the `/autonomous` EVALUATE sense (b) above, the *review-heal loop body* is what runs as a Task step — that step itself runs inline review-and-fix logic, it does not Task-spawn the `-runner` agent.

---

## Step 1 — PR-URL → head resolution (isolation-aware)

Before the loop runs, resolve the PR's head and get the working tree onto it. **How** depends on which entry sense (above) is running:

- **Inline `/review-pr` session (no concurrent self-heal to collide with):** check out the head branch on the main thread's checkout:

  ```
  HEAD_REF=$(gh pr view <pr-url> --json headRefName --jq '.headRefName')
  git fetch origin "$HEAD_REF"
  git checkout "$HEAD_REF"
  ```

- **Detached dispatched drain (the `dispatch-pr-review.sh` → `review-pr-runner` path — runs CONCURRENT with an inline Phase 4.5 self-heal):** the **dispatcher already created an isolated sibling worktree** (detached-HEAD at the PR head SHA) and launched the runner *inside it*. The runner therefore **does NOT run its own `git checkout "$HEAD_REF"`** — it operates inside the dispatcher-provided worktree, so it never checks-out / stages / commits in the inline session's working tree. See §"Isolated worktree for the detached dispatched drain".

- The single input is the **PR URL**. `gh pr view <pr-url> --json headRefName` yields the head branch (`headRefName`).
- The review scope is the PR diff: `git diff <base>...HEAD` for the PR's base branch (default `main`). The reviewer is told to scope to exactly this diff.

### Isolated worktree for the detached dispatched drain (PINNED)

> **Scope:** isolation targets ONLY the **detached dispatched** drain — the one path that runs CONCURRENT with an inline Phase 4.5 self-heal. The inline `/review-pr` session has no concurrent self-heal and stays worktree-free.

`scripts/dispatch-pr-review.sh` isolates the detached drain so it never shares a working tree/index with the inline self-heal:

- **Sibling worktree, detached HEAD.** The dispatcher creates `../{project}-review-{pr_hash_short}` (a SIBLING of the primary checkout, OUTSIDE the tracked tree — never nested under the repo, which an inline `git add -A` could otherwise sweep) via `git worktree add --detach <path> <head-sha>`. Detached-HEAD at the head SHA avoids "branch already checked out" when the PR head == the inline session's current branch.
- **Trap-owned cleanup (executable, not a prompt step).** The dispatcher backgrounds a wrapper process that owns `trap cleanup EXIT`; on the runner's exit (READY/ESCALATED, error, OR crash) the trap removes ONLY that hash-keyed worktree + lock dir. Cleanup is NOT a runner markdown instruction the agent can skip.
- **Marker reflects real dispatch.** An atomic per-PR lock is taken BEFORE the worktree; the durable per-PR marker is written ONLY AFTER the worktree + RUN_LOG header succeed (lock = "someone is dispatching"; marker = "a dispatch genuinely started").
- **Always fail-safe.** The dispatcher ALWAYS `exit 0`; the drain NEVER merges and NEVER `--force`-pushes.

---

## Step 2 — The bounded review→fix→re-review loop

Mirrors Supervisor Phase 4.5 semantics exactly. **Default bound is 3 iterations** (the `--heal-iterations` analogue).

```
heal_iterations = 0
issues_fixed = 0
max_heal_iterations = 3            # default; bounded

while heal_iterations < max_heal_iterations:
  review = Task(
    subagent_type: "loomwright:code-reviewer",
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
             changes. Run type-check + tests locally before finishing. Before pushing,
             PRE-PUSH SELF-REGRESSION REVIEW: re-read your own diff and confirm it introduces no
             downstream regression in persistence/state/lifecycle/idempotency/concurrency (duplicated
             writes, changed ordering, cross-session collisions, broken run-once guards, check-then-act
             races); fix any in this same pass. PRINT an observable `self_review:` line naming the risk
             classes checked and the result (`clean` | `fixed-in-pass: <what>`) — a fix that pushes with
             no `self_review:` line is incomplete."
  )
  # issues_fixed += number of findings addressed
  # Self-review gate (v14.43.0): the fix worker MUST print a `self_review:` line (risk classes checked +
  # clean|fixed-in-pass). A missing line means the anticipatory self-review was skipped → treat the fix as
  # incomplete (re-prompt once / surface); never silently accept it as done.

  push_fix_to_pr()                 # fork-aware: same-repo ⇒ git push origin HEAD:<head_ref> (REGULAR, NEVER --force); fork ⇒ no push, degrade to ESCALATED (see "Fork-aware push")
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
- **FAIL** (reviewer returned `new` issues with severity BLOCKING/HIGH) → spawn a `Task(general-purpose)` fix worker (allowlist Read / Write / Edit / Bash / Glob / Grep, **no Task**) that addresses ONLY those issues, then **fork-aware push** to the PR branch (same-repo: explicit refspec, **never `--force`**; fork: degrade to ESCALATED — see "Fork-aware push"), then re-review. Bounded to N iterations (**default 3**).
- **NEEDS_HUMAN** (reviewer escalates) **or loop exhausts with issues remaining** → **STOP. Do NOT auto-fix, do NOT merge.** Post the findings to the PR via `gh pr comment`, fire notifications best-effort, exit with `decision: ESCALATED`.

### Never `--force`

Pushes that update the PR branch are **regular pushes only**. A force-push would clobber concurrent commits on the PR branch (the human author may have pushed). This mirrors Phase 4.5's `git push  # ... NEVER --force` rule.

### Fork-aware push (PINNED — same-repo vs cross-repo)

Whether (and how) a fix push happens depends on whether the PR head is on `origin`:

- **Same-repo PR** (`isCrossRepository == false`): push via an **explicit refspec** so the local detached-HEAD worktree updates the exact PR branch — `git push origin HEAD:<head_ref>` (**REGULAR push, NEVER `--force`**). The explicit `HEAD:<head_ref>` form is required because the detached drain worktree has no current branch name to push by default.
- **Fork / cross-repo PR** (`isCrossRepository == true`, head NOT on `origin`): **do NOT push to `origin`** — `git push origin HEAD:<head_ref>` would update the wrong ref or fail. Instead **degrade to review-only**: post the findings as a PR comment and exit `decision: ESCALATED`. The drain detects fork status from the dispatcher-threaded signal (`LOOMWRIGHT_PR_IS_FORK=1`, head ref in `LOOMWRIGHT_PR_HEAD_REF`) or directly via `gh pr view <pr-url> --json isCrossRepository,headRepositoryOwner`. The default diff-only `/review-pr` loop is fork-aware in the same way.

This closes a latent gap in the prior bare `git push`, which had no fork awareness and would have pushed to the wrong ref on a fork PR.

---

## Step 3 — Notify on NEEDS_HUMAN (best-effort, fire-and-forget)

When the loop exits as `ESCALATED` (reviewer `NEEDS_HUMAN`, or exhausted with issues), fire **best-effort** notifications. These calls **NEVER block and NEVER fail the loop** — both scripts are designed to always exit 0; any error (missing `jq`, missing `curl`, unset webhook URL, malformed payload) is absorbed silently.

- **Desktop banner:** `${CLAUDE_PLUGIN_ROOT}/scripts/notify-desktop.sh` — reads a JSON hook-style payload on **stdin**, builds a `(title, body)` pair, and fires an OS-native banner (macOS `osascript` / clickable `terminal-notifier`; Linux `notify-send`). It is opt-out via `LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0` and **always exits 0**.
- **Webhook:** `${CLAUDE_PLUGIN_ROOT}/scripts/send-webhook.sh` — gated on a resolvable webhook URL (`LOOMWRIGHT_WEBHOOK_URL`, or the `.supervisor/config.json` → `.webhook_url` fallback, which the script resolves internally). The `--event-type gate` path takes its fields from CLI flags (`--gate-type`, `--iteration`, `--session-id`, `--context`) and builds the payload with `jq --arg` exclusively (injection-safe). It POSTs fire-and-forget with a hard 5s timeout and **always exits 0**.

Set `notified: true` in `REVIEW_HEAL_RESULT` whenever a NEEDS_HUMAN/escalation notification was attempted (regardless of whether the banner/webhook actually delivered — delivery is best-effort and unobservable from the loop).

---

## No auto-merge ever

This loop **NEVER merges a PR.** It honors the no-self-trust / don't-weaken-a-gate principle: an automated reviewer that also merges its own approval removes the human gate. The loop's terminal states are:

- `PASS` — clean diff, loop done, **PR left open for a human to merge**.
- `ESCALATED` — findings posted to the PR, notifications fired, **PR left open** for human attention.

Additionally, **`/review-pr` does not create PRs** (it only operates on an existing PR URL). This deliberately prevents a review→review recursion: because the loop produces no new PR, the post-`/supervisor` auto-dispatch (or `/autonomous` EVALUATE) cannot retrigger itself on a PR it just created.

---

## Until-Mergeable Mode

> **This whole section is the SINGLE SOURCE OF TRUTH for until-mergeable readiness semantics.** Other subtasks (the `/review-pr` command body, the `review-pr-runner` agent, the dispatcher script, and `docs/RESULT_SCHEMAS.md`) **reference** the definitions coined here — the channel set (§"All-Channel Read"), the scoped wait (§"Wait-For-Settled-Checks"), validate-then-fix (§"Validate-Then-Fix"), the READY equivalence (§"READY redefinition"), and the dispatch signal contract (§"Until-Mergeable Dispatch Signal") — and must NOT re-duplicate or re-coin them.

`--until-mergeable` is an **opt-in, heal-only** drain loop that **replaces** the default diff-only loop's review half above — under this flag the drain runs **no `code-reviewer` of its own by default** (§U4's pseudocode spawns only the `general-purpose` fix worker). The **ONE exception** is the **earned fallback** (§"Earned Fallback Review — `no_review_lens_posted`" below): at most one diff review per drain run, run only when the drain's own read shows no review lens actually posted. It drains the **machine-speed external review signals** on a PR across **ALL review channels** — **required** CI check-runs, **review-producing** checks, automated/bot **formal reviews**, **inline review threads**, **PR issue comments**, and **bot check-run output/annotations** — **validating** each detected bot finding and auto-fixing the validated ones (regardless of the bot's stated severity), pushing, and re-polling until the **READY** condition (§"READY redefinition") holds, then stops with `decision: READY` and fires a "ready to merge" notification. **It NEVER merges** (see "No auto-merge ever") and **NEVER waits on a human** — human approval, `reviewDecision: REVIEW_REQUIRED`, and human-authored unresolved threads/comments are surfaced/notified but are explicitly **not** readiness blockers.

> **AC7 — absent ⇒ unchanged.** When `--until-mergeable` is NOT passed, `/review-pr` runs the existing diff-only review→fix→re-review loop (Step 2) **byte-for-byte** — same `PASS`/`ESCALATED` terminal states, same `REVIEW_HEAL_RESULT` `schema_version: 1`, no external-state reads, no all-channel scan, no scoped check-wait, no postmortem tail. This mode is purely opt-in; nothing about the default path changes.

### Step U1 — All-Channel Read each round (AC1, AC2, AC2b, PINNED)

> **"All-Channel Read" is canonical (single source of truth).** The readiness decision is computed over the **UNION** of every channel listed here. Reading one channel (e.g. only `reviews` objects) is insufficient — #64's actionable MEDIUM landed as a **PR issue comment**, a channel `gh pr view --json reviews` never returns.

Each drain round begins by reading the PR's external review state across **all** of these channels. Some signals need MORE than `gh pr view --json` — do **not** invent a `--json reviewThreads` flag (it does not exist):

```
# (a) core PR state — single gh pr view (formal reviews + check rollup + corroborating fields)
gh pr view <pr-url> --json statusCheckRollup,reviews,latestReviews,reviewDecision,mergeable,mergeStateStatus

# (b) inline review threads + each thread's first-comment author type — GraphQL only
gh api graphql -f query='
  query($owner:String!,$repo:String!,$number:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$number){
        reviewThreads(first:100){
          pageInfo{ hasNextPage }
          nodes{
            isResolved
            comments(first:1){ nodes{ author{ login __typename } body } }
          }
        }
      }
    }
  }' -F owner=<owner> -F repo=<repo> -F number=<number>

# (c) PR issue comments — THE #64 CHANNEL GAP. claude-code-review.yml posts via
#     `gh pr comment` (an issue comment), NOT a review object, so reviews/latestReviews
#     never return it. Each element already carries {user.login, body}.
gh api repos/<owner>/<repo>/issues/<number>/comments?per_page=100

# (d) check-run conclusions + output text/annotations — the finding can live in the
#     check OUTPUT, not just the conclusion. For each relevant check-run id from
#     statusCheckRollup:
gh api repos/<owner>/<repo>/check-runs/<id>/annotations   # annotation `message`/`title` text
#     plus the check-run `output` { title, summary, text } already present in the rollup / detail.
```

**Per-channel BODY/CONTENT extraction (AC2b — critical):** for EVERY channel you MUST extract and classify on the **body/content text**, not metadata alone:

- **formal reviews** (`reviews` / `latestReviews`) → each review's **`.body`** text (plus `.user.login`).
- **inline review threads** (`reviewThreads`) → each thread's first-comment **`body`** (plus `author.login`/`__typename`).
- **PR issue comments** → each comment **`.body`** (plus `.user.login`).
- **check-run output/annotations** → the annotation `message`/`title` and check `output.{title,summary,text}` **text**. A check-run has no `.user.login`/`.body` comment shape, and its findings do NOT follow comment authorship/marker conventions — a check named `claude-review` (or app-slug `claude-code`) is not the literal `claude[bot]` login `bot_author_re` matches, and an output body like `MEDIUM: SQL injection at line 42` contains no word-bounded `review` for `review_marker_re`. So check-output findings are **NOT routed through the comment classifier** (whose `(bot_author_re, review_marker_re)` gate is tuned for the comment/review/thread channels). Instead, the **"is this a review bot?" decision for a check-run is owned by §U2.5's review-producing classification** (the configurable `--review-check-pattern`, default `*review*`/`claude*`): a check that §U2.5 already classified **review-producing** AND has non-empty output/annotation **text** yields that text as a **candidate finding directly**. False positives are caught downstream by **validate-then-fix** (§U3.5) — an ungroundable candidate is dismissed, never auto-fixed — so the author/marker gate is redundant here and would only re-drop real findings.

> Reading `reviews[].state` / a comment's author / a check's `conclusion` **alone is insufficient**: those are metadata. The actionable finding — like #64's MEDIUM — lives in the **body/output text**. For comment/review/thread channels classify on `(login, body)`; for check-runs use §U2.5's review-producing determination + non-empty output text. Never gate on state/conclusion in isolation.

**Classify the comment/review/thread channels via the shared helper — do NOT re-implement the regexes.** Pipe each of those channels' real `{user.login, body}` items through **`loomwright/scripts/classify-bot-review.sh`** (stdin = JSON array of comment-like objects, stdout = only the bot-authored review findings, original objects passed through; empty/invalid → `[]`, exit 0). The classifier owns `bot_author_re` / `review_marker_re` as its single source of truth — this skill **never** redefines them. Check-output candidate findings (above) are unioned in separately. The readiness decision is computed over that combined **UNION**.

```
bot_findings = (
    classify(reviews ∪ latestReviews bodies)             # via scripts/classify-bot-review.sh
  ∪ classify(reviewThreads first-comment bodies)        # only unresolved threads feed the blocker set
  ∪ classify(issue_comments)
  ∪ review_producing_check_outputs                       # §U2.5-classified checks w/ non-empty output text — NOT through the comment classifier; validate-then-fix gates false positives
)   # each classify(...) == `<channel-json-array> | bash scripts/classify-bot-review.sh`
```

**Channel set + non-goals (AC2):** the covered channel set is exactly **{formal reviews, inline review threads, PR issue comments, check-run output/annotations}** PLUS the **check rollup** for the green/settled gate. **Deliberately-excluded non-goals:** **commit comments** (`repos/.../commits/<sha>/comments`) and **review-summary-vs-thread duplication** are out of scope — bots post actionable findings via the four covered channels, and commit comments are not a review surface the supported bots use. Pagination beyond the first page of each channel is a non-goal under the same fail-CLOSED-on-truncation discipline below.

**Corroborating-only fields:** `mergeStateStatus` / `mergeable` conflate "required check failing" with "approval missing" (which we deliberately ignore), so they are **never** the sole basis for a READY/ESCALATED decision.

**Fail-CLOSED per channel — "unknown ⇒ never READY" (AC1, AC8):** any channel read whose failure could *hide* a finding is treated as **unknown**, and an unknown channel **MUST NOT claim READY** → the loop exits `decision: ESCALATED`. Concretely:

- **Inline threads (R1, unchanged):** if the GraphQL thread query errors (or returns no parseable thread set), thread-state is **unknown** → MUST NOT claim READY → `ESCALATED`. Unknown is never treated as "no blocking threads".
- **Thread truncation is unknown too (fail-CLOSED, >100 threads):** `reviewThreads(first:100)` caps at 100 and is **not paginated**. If `reviewThreads.pageInfo.hasNextPage == true`, the set is truncated — an unresolved bot thread could exist beyond #100 — so a truncated read is **unknown** thread-state → MUST NOT claim READY → `ESCALATED`, exactly like a GraphQL error. (Full pagination is a deliberate non-goal: escalating on the rare >100-thread PR keeps the fail-CLOSED contract consistent without unbounded paging; the drain re-polls as it resolves threads, so a churning PR converges below the cap.)
- **PR issue comments:** if `gh api .../issues/<n>/comments` errors, the issue-comment channel is **unknown** → MUST NOT claim READY → `ESCALATED` (a #64-style finding could be hiding there). The classifier's own empty/invalid-input `[]` is NOT an error — it means "read succeeded, no bot findings"; only a non-zero `gh api` read failure is "unknown".
- **Check-run output/annotations:** if `statusCheckRollup` itself is unreadable, the required-check gate already fails CLOSED (§U2). If the rollup is readable but a per-check `annotations`/`output` fetch errors for a **required or review-producing** check, that check's findings are **unknown** → MUST NOT claim READY → `ESCALATED`. An annotation-fetch error on an **unrelated optional** check does NOT force escalation (it is outside the gated set, mirroring AC3).

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

### Step U2.5 — Wait-For-Settled-Checks (scoped, bounded) (AC3, AC4, PINNED)

> **"Wait-For-Settled-Checks" is canonical.** The drain MUST NOT declare READY while any check **in the scoped set** is still in flight (`QUEUED`/`IN_PROGRESS`/pending). It waits — bounded — for ONLY that scoped set, then **re-scans ALL channels** (so a late-posting review comment is seen). It NEVER waits on the whole rollup.

**The scoped set = required checks (always) + review-producing checks.** A check is **review-producing** when EITHER:

1. it is a **required** check (always in scope), OR
2. its **name or app** matches the review-bot pattern — default globs **`*review*`** / **`claude*`**, overridable via **`--review-check-pattern <glob>`** and a `notify-config` **include/exclude** list.

**Include/exclude policy (explicit):** the effective review-producing predicate is `(required) OR (name/app matches --review-check-pattern OR notify-config `review_check_include`) AND NOT (name/app matches notify-config `review_check_exclude`)`. The **exclude list wins** over the include/pattern match (so an operator can carve out a noisy non-review check that happens to match `*review*`). Required checks are NEVER excluded by this policy — they are gated by §U2 regardless.

**Bounded wait:**

```
deadline = now + check_wait_timeout          # --check-wait-timeout N (seconds); DEFAULT 600 (10 min)
poll_interval = 15                           # seconds between scoped-set polls (DEFAULT)
while now < deadline AND rounds < max_rounds:
  scoped = [c in rollup if is_required(c) or is_review_producing(c)]   # NEVER the whole rollup
  in_flight = [c in scoped if c.status in (QUEUED, IN_PROGRESS) or c.state is pending]
  if in_flight == []:
     break                                    # scoped set settled — proceed to re-scan ALL channels (U1)
  sleep(poll_interval); re-read statusCheckRollup
```

- **AC3 hard constraint — optional checks never block/escalate by themselves.** An **unrelated optional** check (deploy / preview / security scanner that emits no review feedback and is neither required nor review-producing) that is perpetually `QUEUED`/`IN_PROGRESS` is **outside the wait set**: it MUST NEVER, by itself, block READY or force escalation. The wait observes ONLY the scoped set.
- **Re-scan after settle:** once the scoped set settles, the round **re-scans ALL channels (U1)** before deciding — this is what lets a review comment that lands *after* `ci` went green (e.g. #64's `claude-review` posting ~5 min later) be seen rather than missed.
- **AC4 fail-safe (fail-CLOSED).** If the bounded wait elapses (`now >= deadline`) with a **required OR review-producing** check still in flight → exit `decision: ESCALATED`, surfacing exactly which scoped check(s) were still pending. An **unrelated optional** check still pending at the bound does **NOT** force escalation (AC3 dominates). `--max-rounds` remains the hard outer ceiling; the per-round wait never exceeds the round budget.

### Step U3 — Bot-vs-human thread classification (AC15)

An unresolved review thread is a **READY-blocker ONLY** when its first comment's author is a **bot**:

- `author.__typename == "Bot"`, **OR**
- `author.login` matches `*[bot]` (the GitHub App login convention).

Human-authored — or **unknown/unclassifiable** — unresolved threads are **surfaced in the notification but NEVER block READY** (AC3): the loop never waits on a human. (Unknown-author threads are surfaced so a human sees them before they merge; per R11 this is acceptable because READY never auto-merges.) Note the asymmetry with U1's fail-safe: a *GraphQL error* (no thread data at all) → `ESCALATED`; a *successfully-read* thread whose author cannot be classified as a bot → does not block (treated like a human thread, surfaced only).

### Step U3.5 — Validate-Then-Fix (replaces the BLOCKING/HIGH floor) (AC5, PINNED)

> **"Validate-Then-Fix" is canonical.** It **replaces** the old `fixable = actionable BLOCKING/HIGH items …` severity floor. Severity is no longer a gate on *whether* a finding is considered — EVERY detected bot finding (from any channel, at any stated severity) is run through validation. A real **MEDIUM** like #64 must be fixed; the old floor would have silently dropped it.

For each finding in the classified `bot_findings` UNION (§U1), apply this three-way decision:

1. **Validate (evidence-citing — mitigates R4, no rubber-stamping).** The finding is **confirmed** ONLY when it (a) maps to a **concrete current-branch location** (file + line/region that still exists in the checked-out head state) AND (b) is **actionable** (describes a change that can be made). Validation must **cite the evidence** (the grounding location); a finding that **cannot be grounded** on the current branch is **dismissed, not fixed** — never rubber-stamp a finding into a fix without grounding it.
2. **Confirmed + auto-fixable → FIX regardless of stated severity.** Dispatch the existing fix-worker model: `Task(general-purpose)` with tool allowlist **Read / Write / Edit / Bash / Glob / Grep — NO Task**, told to address ONLY the validated findings; then **fork-aware push** (same-repo: explicit refspec, **REGULAR push, NEVER `--force`**; fork: no push → degrade to ESCALATED — see "Fork-aware push"); then **re-scan ALL channels** (U1). A confirmed MEDIUM/LOW is fixed exactly like a confirmed HIGH — there is no severity floor.
3. **Confirmed but NOT auto-fixable (needs human judgment) → BLOCKS READY.** It is surfaced/escalated (counted in `remaining_issues`); it does not get a blind fix.
4. **Validated as stale / invalid / already-addressed → DISMISSED.** Recorded as dismissed (`findings_dismissed`); does **NOT** block READY and is **not** fixed.

`findings_validated` counts findings confirmed (cases 2+3); `findings_dismissed` counts case 4. Only **case-3 (confirmed-but-not-auto-fixable)** findings remain as READY-blockers after a round — case-2 findings are fixed (and may recur, governed by the Anti-Churn Guardrail), case-4 findings are gone.

### Step U4 — The bounded drain loop

> **Mechanized bound (AC1/AC2, D2).** `max_rounds` has exactly ONE authoritative default below (5) and the ceiling itself is enforced by `scripts/drain-rounds.sh` — an executable ledger, not a prose-tracked variable — so it binds identically on BOTH entry paths (inline `/review-pr` and the detached `review-pr-runner`) that read this SAME §U4 body. Neither path keeps a private counter; both call `init`/`check`/`bump` against the same per-PR ledger. This closes F1 (there was never a real inline-vs-runner asymmetry to begin with — see §"Provenance" in the brief this shipped from) by making the ONE shared bound actually executable instead of prose both paths were merely expected to obey.

```
max_rounds = 5                      # default; --max-rounds N overrides; HARD ceiling — the ONE authoritative home for this value
severity_floor = "HIGH"             # default; --severity-floor overrides — TERMINATION-ONLY (see below), never a fix-time gate
fix_cycles = 0                      # how many fix→push cycles ran (postmortem-gate input)
churn_rounds = 0                    # consecutive rounds whose fingerprint set didn't shrink
fingerprints_prev = {}              # see "Anti-Churn Guardrail"
repeat_check_failure = false        # a required check that was fixed re-failed (postmortem input; AC13)
unresolved_bot_feedback = false     # bot finding (any channel) still open after >=1 fix (postmortem input)
dismissed = []                      # findings validated as stale/invalid/already-addressed (additive result field)
channels_scanned = []               # which channels were read this run (additive result field)
checks_waited = []                  # scoped checks the loop waited on to settle (additive result field)
sub_floor_fixed = []                # findings FIXED (never declined) in a sub_floor_converged terminal round (additive result field)
termination_reason = null           # converged | bound_hit | sub_floor_converged (AC6) — set on exactly one matching exit path
checks_ever_fixed = {}              # required-check names this drain has attempted to fix — AC13 input for the confirming pass
fallback_review_ran = false         # run-scoped (AC3); the earned fallback fires at MOST once per drain run —
                                     # this flag is what the mechanized bound cannot re-trigger it through

drain-rounds.sh init <pr_url> <max_rounds>   # MECHANIZED — same ledger call BOTH entry paths make; never a private counter (AC1/AC2)

loop:
  gate = drain-rounds.sh check <pr_url>      # OK (exit 0, continue) | BOUND_HIT (exit 1) | "ESCALATED: unreadable_round_ledger" (exit 2)
  if gate != "OK":                            # AC1 — ceiling reached; AC5 — fail CLOSED, never loop/pass silently on an unreadable ledger
    decision = ESCALATED
    termination_reason = "bound_hit" if gate == "BOUND_HIT" else null   # an unreadable ledger is a hard stop, not a "bound"
    post remaining findings to PR (gh pr comment ...); notify (best-effort)
    break

  required = discover_required_checks()   # Step U2 — ESCALATED (fail closed) if unavailable & not --required-checks all-non-neutral
  wait_for_scoped_checks_to_settle()      # Step U2.5 — bounded; ESCALATED if a required/review-producing check is still in flight at the bound (optional pending never escalates)
  scan = read_all_channels()             # Step U1 — re-scans ALL channels AFTER the scoped set settles; ESCALATED if any gated channel is "unknown"
  bot_findings = classify_all_channels(scan)   # Step U1 — UNION across reviews/latestReviews/reviewThreads/issue-comments/check-outputs via scripts/classify-bot-review.sh
  # NOTE (AC1): this loop deliberately spawns NO Task(loomwright:code-reviewer) of its own — the drain is
  # heal-only by default. The ONE exception is the earned fallback below (see the READY branch and
  # §"Earned Fallback Review — `no_review_lens_posted`"), gated on `no_review_lens_posted` and capped at
  # exactly one spawn per drain run via `fallback_review_ran`.

  required_failing = [c for c in required if c.state not in GREEN_STATES]

  # Step U3.5 — Validate-Then-Fix EVERY bot finding (any stated severity); no severity floor AT FIX TIME —
  # reading B, "PINNED SEMANTICS": a finding is NEVER declined a fix on severity grounds.
  validated      = [f for f in bot_findings if validate(f) == CONFIRMED]   # evidence-cited, grounded on current branch
  dismissed     += [f for f in bot_findings if validate(f) == STALE_OR_INVALID]
  auto_fixable   = [f for f in validated if is_auto_fixable(f)]
  needs_human    = [f for f in validated if not is_auto_fixable(f)]        # confirmed but not auto-fixable → blocks READY

  # Earned fallback gate (AC3) — the ONE exception to heal-only, checked ONLY on a round that would
  # otherwise declare READY, and at most once per drain run (fallback_review_ran). Full contract:
  # §"Earned Fallback Review — `no_review_lens_posted`" below — not restated here.
  if required_failing == [] and auto_fixable == [] and needs_human == [] and not fallback_review_ran:
    fallback_review_ran = true            # set BEFORE the spawn — never re-triggers, even on error
    if compute_no_review_lens_posted(bot_findings, scan):   # reuses THIS round's §U1 read, no new fetch;
                                                             # fails CLOSED to true (run it) on ambiguity
      fallback_review = Task(
        subagent_type: "loomwright:code-reviewer",
        prompt: "Review the PR-branch diff (git diff <base>...HEAD).
                 Schema: CODE_REVIEW_RESULT v3, review_mode: diff_review."
      )
      # REASSIGN (not just describe) — this is what makes the READY test below read POST-fallback
      # values instead of the stale pre-fallback ones. Feed fallback_review.issues into THIS round's
      # §U3.5 Validate-Then-Fix pipeline exactly like any other channel's bot_findings (`new`-category
      # only, matching Step 2's CATEGORY filter — but per §U3.5 there is no severity floor here, so a
      # validated MEDIUM/LOW is fixed exactly like a HIGH):
      fallback_findings = [i for i in fallback_review.issues if i.category == "new"]
      validated    += [f for f in fallback_findings if validate(f) == CONFIRMED]
      dismissed    += [f for f in fallback_findings if validate(f) == STALE_OR_INVALID]
      auto_fixable  = [f for f in validated if is_auto_fixable(f)]        # RE-DERIVE from the now-larger
      needs_human   = [f for f in validated if not is_auto_fixable(f)]   # `validated` — not appended to the stale lists
      # A PASS result (no `new` issues) leaves fallback_findings == [] so auto_fixable/needs_human are
      # unchanged and the READY test below still passes. A FAIL result with an auto-fixable finding now
      # populates auto_fixable, so the READY test below correctly fails and the round falls through to
      # the existing fix-dispatch branch (Task(general-purpose) + fork-aware push) — the fallback finding
      # reaches the fix worker exactly like a channel finding would. A FAIL result with a confirmed-but-
      # not-auto-fixable finding populates needs_human, so the READY test below fails and the round falls
      # into the "needs_human != [] and auto_fixable == []" branch → decision = ESCALATED — it blocks
      # READY instead of being silently discarded.

  # READY ⇔ required green AND scoped review-producing checks settled (already true here) AND
  #         no unresolved VALIDATED bot findings remain across ALL channels (fallback findings included).
  if required_failing == [] and auto_fixable == [] and needs_human == []:
    decision = READY                      # AC6 — see "READY redefinition"
    termination_reason = "converged"      # a genuine empty-yield round — every channel WAS re-scanned this round; distinct from sub_floor_converged (AC6)
    notify "ready to merge" (best-effort: desktop + webhook)
    break

  if auto_fixable == [] and needs_human != []:
    # only human-judgment findings remain (can't auto-fix) → surface + stop
    decision = ESCALATED
    remaining_issues = len(needs_human)
    post findings to PR (gh pr comment ...); notify (best-effort)
    break

  # else — validated auto-fixable signals remain. Dispatch a fix worker (AC5).
  fixable = required_failing + auto_fixable        # fix validated findings regardless of stated severity
  checks_ever_fixed += { c.name for c in required_failing }   # AC13 input — this drain attempted to fix these
  Task(
    subagent_type: "general-purpose",
    # Tool allowlist: Read, Write, Edit, Bash, Glob, Grep — NO Task.
    prompt: "Address ONLY these required-check failures and VALIDATED bot findings
             (from reviews, inline threads, PR issue comments, check outputs, or the earned-fallback
             diff review): {fixable}.
             Do NOT touch human-authored / unknown-author findings, optional-check items,
             or dismissed/stale findings. Update tests if behaviour changes; run
             type-check + tests locally. Before pushing, PRE-PUSH SELF-REGRESSION REVIEW:
             re-read your own diff and confirm it introduces no downstream regression in
             persistence/state/lifecycle/idempotency/concurrency (duplicated writes, changed ordering,
             cross-session collisions, broken run-once guards, check-then-act races); fix any in this same
             pass. PRINT an observable `self_review:` line naming the risk classes checked and the result
             (`clean` | `fixed-in-pass: <what>`) — a fix that pushes with no `self_review:` line is incomplete."
  )
  fix_cycles += 1

  # Self-review gate (v14.43.0, drain): the drain fix worker MUST print a `self_review:` line (risk classes
  # checked + clean|fixed-in-pass). A missing line means the anticipatory self-review was skipped → treat the
  # fix as incomplete (re-prompt once / surface); never silently accept it as done.

  push_fix_to_pr()                      # fork-aware: same-repo ⇒ git push origin HEAD:<head_ref> (REGULAR, NEVER --force); fork ⇒ no push, degrade to ESCALATED (see "Fork-aware push")
  pushed_sha = capture_head_sha()       # R1 — captured AT THIS INSTANT; the confirming pass below binds to exactly this SHA, never a re-read of "current" HEAD

  # --- Termination-only severity floor (AC3/AC4/AC11/AC12; §"Termination-only severity floor" below) ---
  # Eligible ONLY when EVERYTHING fixed this round is below severity_floor: no required-check fix was in
  # play (required_failing was empty going into this round) and no needs_human finding was left behind —
  # i.e. this round's ENTIRE yield was sub-floor bot findings, all of which WERE fixed (reading B, never
  # declined). A round that also fixed a required-check failure or left a needs_human finding is NEVER
  # sub-floor-eligible, regardless of the bot findings' severities.
  sub_floor_eligible = (required_failing == []) and (needs_human == []) and (auto_fixable != [])
                       and all(severity_rank(f) < severity_rank(severity_floor) for f in auto_fixable)
  if sub_floor_eligible:
    outcome = confirming_required_check_pass(pushed_sha, required)   # SHA-BOUND — full contract below (AC11, R1)
    if outcome.result == "GREEN":
      # AC12 — the earned-fallback gate is NOT re-run here, and that is CORRECT rather than an omission.
      # PROOF it cannot be earned on this path: sub_floor_eligible requires `auto_fixable != []`, and
      # auto_fixable ⊆ validated ⊆ bot_findings, so reaching this branch GUARANTEES bot_findings != [].
      # But `no_review_lens_posted`'s condition 1 (§"Earned Fallback Review") requires bot_findings to be
      # EMPTY. The two are mutually exclusive by construction — so on a sub-floor termination a review lens
      # demonstrably DID post (that non-empty union IS the evidence), and the fallback is by definition
      # unearned. Plan Review's "Hole 3" is therefore VACUOUS on this path, not unhandled.
      # Do NOT "fix" this by calling compute_no_review_lens_posted() here: it can only ever return false,
      # which is unreachable dead code that falsely advertises a guard (a drain review round caught exactly
      # that shipped in an earlier cut of this change). If a future edit ever lets sub_floor_eligible hold
      # with bot_findings == [], this proof breaks and the gate must be reinstated.
      decision = READY
      termination_reason = "sub_floor_converged"   # NOT auto-merge-eligible (AC9) — see automate-loop §10 cond 1
      sub_floor_fixed += auto_fixable
      notify "ready to merge" (best-effort)
      drain-rounds.sh bump <pr_url>                # this round still counts against the ceiling
      break
    else:   # RED, UNREADABLE, or the bounded SHA-settle wait itself elapsed (still-not-settled) — Hole 1
      decision = ESCALATED                              # NEVER READY on a red/unknown/unbound-checked SHA
      if outcome.result == "RED" and (outcome.failing_names & checks_ever_fixed) != {}:
        repeat_check_failure = true                      # AC13 — a check that HAD been fixed re-failed; there
                                                           # is no later round to catch this otherwise (Hole 2)
      post remaining findings to PR (gh pr comment ...); notify (best-effort)
      drain-rounds.sh bump <pr_url>
      break

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
  drain-rounds.sh bump <pr_url>            # MECHANIZED — replaces the bare `rounds += 1`; the `check` at the
                                            # TOP of the next loop iteration is what actually enforces the bound
  continue to top of loop

# Emit REVIEW_HEAL_RESULT (v2). rounds is READ from the ledger (drain-rounds.sh read <pr_url>) at emit
# time — the ledger is the single source of truth for the count on BOTH entry paths.
rounds = $(drain-rounds.sh read <pr_url> | jq -r '.rounds // 0')   # `read` prints the WHOLE ledger
#          JSON ({"rounds":N,"max_rounds":M}) and takes NO field argument — extract with jq, never by
#          passing a second positional arg (it is silently ignored).
iterations = rounds        # the back-compat v1 analogue — same value as `rounds`. fix_cycles is the
                            # distinct fix→push count (≤ rounds).
```

`GREEN_STATES` are the check states that count as passing (e.g. `SUCCESS`; `NEUTRAL`/`SKIPPED` are non-blocking). `severity_rank` orders `BLOCKING > HIGH > MEDIUM > LOW` (matching `CODE_REVIEW_RESULT`'s severity enum, `docs/RESULT_SCHEMAS.md`); "below `severity_floor`" means strictly lower rank. `unresolved_bot_feedback = true` when a bot-authored finding **(from any channel — thread, review, issue comment, or check output)** remains unresolved after at least one fix cycle — feeds the Postmortem Dispatch Tail alongside `repeat_check_failure` (set per AC13 above, or by the pre-existing "required check re-fails in a later round" case on the normal path).

### Termination-only severity floor (`sub_floor_converged`) — AC3/AC4/AC9/AC11/AC12/AC13

> **PINNED SEMANTICS — reading B (fix-then-stop) only; reading A (find-then-defer) is FORBIDDEN.** Round N runs Validate-Then-Fix **completely** — every validated finding, at every severity including sub-floor, **is fixed and pushed**. `--severity-floor` decides ONLY that round N+1's re-scan does not start. No finding is ever declined a fix on severity grounds; §U3.5 ("A confirmed MEDIUM/LOW is fixed exactly like a confirmed HIGH — there is no severity floor") and its §Anti-Patterns counterpart (§U3.5, "no severity floor") and the Anti-Pattern below all remain true statements after this change — see AC4.

**WHERE the check sits (mandatory shape — split the skipped work, never skip the whole round).** A `sub_floor_converged` termination still runs the **confirming required-check pass** against the **pushed** SHA; it skips ONLY the expensive all-channel bot-finding re-scan + validate pass (§U4's `read_all_channels()`/`classify_all_channels()` re-scan and the §U3.5 Validate-Then-Fix pass that follows it). Wiring the check at the *bottom* of a round (after `push_fix_to_pr()`, as in the pseudocode above) — rather than declining the fix up front — is what keeps this compatible with reading B and with the earned-fallback gate (AC12, which the pseudocode re-evaluates FOR the skipped round rather than bypassing it).

**`confirming_required_check_pass(pushed_sha, required)` (AC11, R1 — SHA-BINDING IS LOAD-BEARING):**

```
deadline = now + check_wait_timeout       # same bound as §U2.5's Wait-For-Settled-Checks
poll_interval = 15
while now < deadline:
  view = gh pr view <pr-url> --json headRefOid,statusCheckRollup
  if view.headRefOid != pushed_sha:
    sleep(poll_interval); continue         # rollup describes a DIFFERENT commit — not settled for OUR SHA yet
  scoped_required = [c in view.statusCheckRollup if is_required(c)]
  # NOTE: this is a COUNT check, not an identity filter. `gh`'s statusCheckRollup has NO per-check
  # SHA field — the whole rollup already corresponds to pushed_sha, because the headRefOid guard
  # above returned/looped otherwise. So `materialized` is just "how many of the required contexts
  # have appeared in this SHA's rollup yet", distinguishing NOT-YET-CREATED (GitHub has not
  # materialised the check run) from CREATED-BUT-PENDING (which the in_flight test below catches).
  # Do not go looking for a per-check SHA field to filter on; there isn't one.
  materialized = [c in rollup_for_pushed_sha if is_required(c)]   # count vs len(required), see note
  if len(materialized) < len(required):
    sleep(poll_interval); continue         # a required check has NOT YET been re-created for pushed_sha —
                                            # NOT-settled, NEVER treated as green (this is the race R1 names:
                                            # an absent entry is indistinguishable from "not yet queued" and
                                            # falling through would silently read the PRIOR commit's SUCCESS)
  in_flight = [c in scoped_required if c.status in (QUEUED, IN_PROGRESS) or c.state is pending]
  if in_flight != []:
    sleep(poll_interval); continue
  failing = [c for c in scoped_required if c.state not in GREEN_STATES]
  return { result: "RED" if failing != [] else "GREEN", failing_names: {c.name for c in failing} }
return { result: "UNREADABLE", failing_names: {} }   # bound elapsed with the SHA never fully settled — Hole 1's fail-safe
```

`READY` (`sub_floor_converged`) only when this returns `GREEN` for the exact `pushed_sha`. `RED`, `UNREADABLE`, or a `headRefOid` mismatch that never resolves within the bound all degrade to `ESCALATED` — never `READY` on a red or unknown SHA. This mirrors the `ready_sha` vs `head_sha` check in `automate-helpers.sh`'s `gate-eval` condition 2 (specified at `automate-loop/SKILL.md` §10 condition 2) — the drain simply never adopted SHA-binding before this change (`headRefOid` appeared zero times in this skill).

**The residual (R2 — the honest cost).** This does **not** skip a full round of wall-clock (the required-check re-settle still runs, and pushing a fix re-triggers `ci`, which is where the wall-clock actually lives) — it skips one round's all-channel bot-finding re-scan + validate pass, and it accepts that a finding round N+1's re-scan would have *discovered* (as opposed to one already known and fixed) is never found. Bounded by the floor: only a round whose ENTIRE yield was sub-floor skips it. `sub_floor_converged` is therefore explicitly **NOT** auto-merge-eligible (AC9 — see `automate-loop/SKILL.md` §10 condition 1) even though it is `decision: READY`.

---

### Earned Fallback Review — `no_review_lens_posted` (AC3, PINNED)

> **This subsection is the SINGLE SOURCE OF TRUTH for the earned fallback.** `agents/review-pr.md` and `commands/review-pr.md` reference `no_review_lens_posted` by name; they do not restate its trigger or contract.

The drain is **heal-only by default** (§U4) — it spawns no `code-reviewer` of its own. But Finding B (verified live against PRs #118/#117/#116/#115, per `docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` Fix 7) showed a real gap: `claude-code-action` **self-skips on any workflow-touching PR and still exits 0** (#117: green in 14s, zero posted comments, vs #118's 3m53s with a real posted review). A blanket heal-only cut would leave exactly **ONE** LLM lens on such a PR — the opposite of the two-lens intent. The fallback closes that gap by running the drain's own diff review **only when it is earned** — i.e. only when the pass that was supposed to supply that information verifiably did not run. This is exactly `AGENT_GUIDELINES.md` §"Review Counter-Pressure Rule" part 2 applied to the drain — **cite that section for why the fallback exists; it is not restated here.**

**Trigger, computed from §U1's existing read — NO new fetch.** `no_review_lens_posted` is true when BOTH hold, using the SAME `bot_findings` / `scan` §U1 already produced this round:

1. `bot_findings` (the §U1 UNION across reviews/latestReviews/reviewThreads/issue-comments/check-outputs) is **empty**, AND
2. every **review-producing** check (§U2.5's classification) is **green-with-empty-output, absent, or skipped** — no review-producing check posted a non-empty finding.

**The issue-comment channel is authoritative for "posted"; never gate on `--json reviews` alone.** All four measured PRs (#118/#117/#116/#115) had `reviews: 0` while every real finding arrived as an issue comment — so, like §U1 itself, this trigger reads the FULL `bot_findings` union (which already includes the issue-comment channel), never `reviews`/`latestReviews` in isolation.

**Effect — exactly one fallback review per drain run.** See the `fallback_review_ran` gate in §U4's pseudocode above (set to `true` BEFORE the spawn, so it never re-triggers even on error): on a round that would otherwise declare READY, if `no_review_lens_posted` holds, the drain runs exactly one `Task(loomwright:code-reviewer)` diff review reusing Step 2's machinery (`review_mode: diff_review`). Its findings are folded into the SAME round's §U3.5 Validate-Then-Fix inputs as any other channel's `bot_findings` — no separate fix mechanism, no separate push path. The run remains bounded by `--max-rounds` exactly like every other round.

**Fail-CLOSED direction is TO RUNNING the review — deliberately the opposite of the channel-unknown ⇒ `ESCALATED` rule, and both apply.** If the trigger itself cannot be computed (e.g. a review-producing check's output/annotation emptiness is ambiguous even though every §U1-gated channel read succeeded), treat `no_review_lens_posted` as **true** and run the fallback. This does not weaken §U1's existing unknown-channel rule: if any §U1-gated channel is genuinely **unknown** (a GraphQL thread error/truncation, an errored issue-comment read, an errored required/review-producing check-output fetch), §U1's existing fail-closed rule already forces `ESCALATED` before this trigger is even reached — `ESCALATED` still wins for readiness in that case. This trigger's own fail-closed gap is narrower: a successfully-read scan whose "did a review lens post anything" classification is itself ambiguous. There the two directions diverge on purpose, and the reason is asymmetric cost: an unnecessary review wastes tokens; a skipped necessary one ships a defect (`AGENT_GUIDELINES.md` §"Review Counter-Pressure Rule", part 2) — running the extra review is the cheaper mistake.

**Why the `Task(loomwright:code-reviewer)` spawn is legal here (spawn-depth reachability — this repo's most expensive trap).** §U4's loop otherwise spawns only `general-purpose`; the fallback is the first place the drain loop itself spawns a `code-reviewer`, making the drain spawn-dependent for the first time. That is safe **only because every caller that can reach `--until-mergeable` runs as the main agent of its own process** — the detached `-runner` launched by `dispatch-pr-review.sh` (a fresh headless `claude -p` OS process), or an inline `/review-pr` on the main thread — both are spawn-capable top-level agents. The `/autonomous` EVALUATE step is explicitly **not** such a caller, for two SEPARATE reasons cited from two SEPARATE subsections of `docs/RESULT_SCHEMAS.md` §"REVIEW_HEAL_RESULT" (conflating them produces an unsupported sentence):

- it is a **non-`--until-mergeable` caller** and therefore continues to emit `schema_version: 1` — see §"Schema versions (v1 still accepted)", the `schema_version: 2` bullet, which is where the non-caller set is actually enumerated ("every non-`--until-mergeable` caller — the default `/review-pr` loop, the plain-`/supervisor` completion-tail auto-dispatch, and the `/autonomous` EVALUATE step — continues to emit `schema_version: 1`");
- and, separately, it runs as a **Task-spawned step** with fresh isolated context — see §"Emission contexts" (a bold paragraph, not a `###` heading — grep the text; it says only that the step is Task-spawned and parses the block, and does NOT itself support the non-caller claim above).

Routing the drain through a Task step in the future would turn this fallback into a hard failure — *subagents cannot spawn subagents* (this skill's §"Execution-contract rule (AC9)"; `agents/review-pr.md`'s mirror of the same rule; the 11.1.1 `-runner` trap) — so a future caller-side change that Task-spawns a `--until-mergeable` drain would silently break this fallback's `code-reviewer` spawn. Keep this note next to the fallback so that change cannot land unnoticed.

---

### READY redefinition (AC6, canonical single source of truth)

> **This is the authoritative READY definition for `--until-mergeable`. S3/S4/S5 reference it; they do not restate it.**
>
> **`READY ⇔ required checks green AND review-producing checks settled (the scoped set — unrelated optional checks excluded) AND no unresolved validated bot findings remain across ALL channels (reviews + latestReviews + reviewThreads + PR issue comments + check outputs).`**

- **Human signals are surfaced but NEVER blocking** (never-wait-on-humans preserved): human approval, `reviewDecision: REVIEW_REQUIRED`, and human-authored / unknown-author findings & threads are surfaced/notified but are explicitly **not** READY blockers.
- "No unresolved validated bot findings" means: after §U3.5 Validate-Then-Fix, there is no remaining **confirmed** finding — neither an auto-fixable one awaiting a fix nor a confirmed-but-not-auto-fixable (case-3) one. Dismissed (case-4) findings never block.
- "Review-producing checks settled" is enforced by §U2.5 — the round cannot even reach the READY test while a scoped check is in flight; an unrelated optional check pending is excluded from the gate.
- `--max-rounds` is the hard ceiling (mechanized — `scripts/drain-rounds.sh`) and the Anti-Churn Guardrail still governs oscillation; neither weakens this READY definition.
- **`sub_floor_converged` is a variant READY, not a separate condition.** It holds this SAME definition for a round's fixed findings, confirmed via the SHA-bound confirming required-check pass instead of a fresh all-channel re-scan — see §"Termination-only severity floor (`sub_floor_converged`)". It is READY for terminal-state purposes (PR left open, notified) but explicitly **not** auto-merge-eligible (AC9).

### Terminal states (until-mergeable)

- **`READY`** — the READY redefinition above holds: required checks green AND review-producing (scoped) checks settled AND no unresolved validated bot findings across ALL channels. Loop done; **PR left open for a human to merge** (merge-identical to `PASS`); "ready to merge" notification fired. `termination_reason: converged` (AC6).
- **`READY` (`sub_floor_converged`)** — a round whose entire fixed yield was below `--severity-floor` terminates READY without a further all-channel re-scan, PROVIDED the SHA-bound confirming required-check pass (§"Termination-only severity floor") is green for the pushed commit. `termination_reason: sub_floor_converged` (AC6); **not** auto-merge-eligible (AC9).
- **`ESCALATED`** — `--max-rounds` exhausted with signals remaining (`termination_reason: bound_hit`, AC6); OR only confirmed-but-not-auto-fixable (human-judgment) findings remain; OR a fail-closed condition tripped (any gated channel "unknown" — GraphQL thread query errored / truncated, issue-comment read errored, required-or-review-producing check-output fetch errored; required-check metadata unavailable without `--required-checks all-non-neutral`; the §U2.5 bounded wait elapsed with a required/review-producing check still in flight; OR — new — the AC11 confirming pass found the pushed SHA's required checks red/unreadable, `termination_reason` left unset); OR the round-ledger itself was unreadable (AC5, `termination_reason` left unset). Findings posted to the PR, notifications fired, **PR left open**.

There is **no `READY`-that-merges**. `READY` (either `termination_reason`) is terminal-stop-and-notify, exactly like `PASS`/`ESCALATED` (AC6). **No `gh pr merge` is ever issued (AC8).**

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

## Until-Mergeable Dispatch Signal (AC7 signal contract — PINNED)

> **This subsection is the SINGLE SOURCE OF TRUTH for how the until-mergeable signal is threaded from Supervisor's detached dispatcher → the `review-pr-runner` agent → its inline `/review-pr`.** The dispatcher (the **SETTER**, owned by the Supervisor/dispatcher subtask) and the runner (the **READER**, owned by the runner-agent subtask) must NOT diverge — so the concrete names are pinned here and consumed verbatim.

The Supervisor auto-dispatch launches the runner as a fresh detached HEADLESS process via the **`--agent` runner form**:

```
claude -p --agent loomwright:review-pr-runner "<pr-url>"
```

The `--agent` form has **NO flag surface** — you cannot pass `--until-mergeable` (or any `/review-pr` flag) on this command line, because the positional is the PR URL handed to the agent, not a slash string. So the signal is threaded via **environment variables** (NOT a `/review-pr` slash string in the dispatcher, NOT a new positional argument). This deliberately avoids the **11.1.1 spawn-depth auto-delegation trap**: there is no Task-spawn of the runner and no slash-command re-parse layer that could re-trigger auto-delegation.

**Pinned environment-variable contract:**

| Env var (SETTER: dispatcher / S4) | READER: runner → inline `/review-pr` | Semantics |
|---|---|---|
| **`LOOMWRIGHT_UNTIL_MERGEABLE`** | when truthy (`1` / `true`), the runner invokes its inline `/review-pr <pr-url>` **with `--until-mergeable`** | the master on/off signal. Absent or falsy ⇒ default diff-only loop (AC7 byte-for-byte unchanged). |
| **`LOOMWRIGHT_CHECK_WAIT_TIMEOUT`** | optional; when set, forwarded as **`--check-wait-timeout <value>`** | scoped check-wait bound (§"Wait-For-Settled-Checks"). |
| **`LOOMWRIGHT_REVIEW_CHECK_PATTERN`** | optional; when set, forwarded as **`--review-check-pattern <value>`** | review-producing check selector glob (§"All-Channel Read" / §"Wait-For-Settled-Checks"). |

- The runner reads these env vars and **translates them into the corresponding `/review-pr` flags** on its inline invocation; the inline `/review-pr` body then runs the until-mergeable drain defined in this section. Only `LOOMWRIGHT_UNTIL_MERGEABLE` is the on/off gate; the other two are optional tuning that are forwarded ONLY when set.
- **Default-ON / opt-out at the Supervisor layer** is owned by the dispatcher subtask via the `auto_until_mergeable` config (see the flags table) — when enabled, Supervisor sets `LOOMWRIGHT_UNTIL_MERGEABLE=1` on the dispatched process; opting out simply leaves it unset (or falsy), which restores the default loop. This skill defines only the *signal contract*; the *policy* of whether to set it lives at the Supervisor layer and is referenced, not re-coined, here.

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
| `fix_cycles > postmortem_churn_threshold` (default **2**) | `--postmortem-churn-threshold N` or `.postmortem_churn_threshold` in `.supervisor/config.json` (read via jq) |
| `decision == ESCALATED` (escalated / timed-out) | the loop's final decision |
| same required CI/check failure repeats after a fix | `repeat_check_failure` |
| bot/automated feedback remained unresolved after ≥1 fix | `unresolved_bot_feedback` |

If **NONE** trip (`fix_cycles ≤ threshold` AND `decision != ESCALATED` AND no repeat check failure AND no lingering bot feedback) → **no postmortem is dispatched** (AC9).

### Opt-out (AC13)

`--no-auto-postmortem` (or `auto_postmortem: false` in `.supervisor/config.json`) opts out **entirely** — no postmortem regardless of churn. (NB: the config value is the boolean `false`; the dispatcher reads it as a raw value, never via jq `// empty`, so the falsy `false` is not silently coerced away.)

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

- **Force-pushing the PR branch.** Never `git push --force` — clobbers concurrent author commits. Regular push only (same-repo via explicit refspec `git push origin HEAD:<head_ref>`).
- **Pushing to `origin` for a fork/cross-repo PR.** The head ref is NOT on `origin`, so `git push origin HEAD:<head_ref>` updates the wrong ref or fails. Degrade to review-only `ESCALATED` instead (see "Fork-aware push").
- **The detached drain checking out the PR head in the inline working tree.** The detached dispatched drain runs inside the dispatcher-created sibling worktree — it must NOT `git checkout "$HEAD_REF"` in the inline session's checkout (that is the exact same-tree collision this isolation removes). Worktree creation + removal are owned by the dispatcher's trap-wrapper, never a runner prompt step.
- **Auto-merging on PASS.** Removes the human gate; explicitly forbidden.
- **Task-spawning the runner.** `Task(loomwright:review-pr-runner)` breaks because the runner must spawn its own children — run it as a session main agent or inline via `/review-pr`.
- **Creating a PR from `/review-pr`.** Would open the door to review→review recursion.
- **Letting notify failures abort the loop.** The notify scripts are fire-and-forget; treat their exit codes as advisory only (they always exit 0 anyway).
- **Re-coining any pinned name.** Other subtasks consume the names above verbatim — renaming here breaks the contract.
- **Inventing a `gh pr view --json reviewThreads` flag.** Unresolved threads + author type are GraphQL-only (Step U1). The `--json` flag does not exist; use `gh api graphql`.
- **Claiming READY when any gated channel signal is unknown.** A GraphQL thread error/truncation, an errored issue-comment read, an errored required/review-producing check-output fetch, or unreadable branch-protection metadata must each fail CLOSED to `ESCALATED` — never default-to-green (AC1/AC8).
- **Reading only one channel (or only metadata).** Reading only `reviews` objects misses the #64 PR **issue comment**; reading `reviews[].state` / `conclusion` / author **alone** misses the body where the actionable finding lives. Read ALL channels (§"All-Channel Read") and classify on `(login, body)` text (AC2/AC2b).
- **Re-implementing the bot regexes.** `bot_author_re` / `review_marker_re` live ONLY in `scripts/classify-bot-review.sh`. Pipe each channel's items through that helper — never redefine the patterns here.
- **Reinstating a BLOCKING/HIGH severity floor.** §U3.5 Validate-Then-Fix replaced it: a validated MEDIUM (like #64) MUST be fixed. Never drop a finding solely because its stated severity is below HIGH. **`--severity-floor` (§"Termination-only severity floor") is NOT a reinstatement of this anti-pattern** — it is a TERMINATION-time gate only ("does round N+1 start"), never a fix-time gate ("is this finding fixed"). Every validated finding at every severity is still fixed within its round (reading B); implementing the floor as a fix-time filter (reading A, "find-then-defer") IS this anti-pattern and is forbidden.
- **"Find-then-defer" (reading A) for `sub_floor_converged`.** Declining to fix a sub-floor finding, reporting it, and terminating is the anti-pattern above wearing a different name. The ONLY authorized shape is reading B: fix everything the round found (any severity), THEN decide whether round N+1 starts.
- **Waiting on the whole rollup (or letting an optional check block/escalate).** The scoped wait (§"Wait-For-Settled-Checks") observes ONLY required + review-producing checks; an unrelated optional pending check must never block READY or force escalation (AC3).
- **Threading `--until-mergeable` as a slash string or positional in the `--agent` dispatcher.** The `--agent` runner form has no flag surface — thread the signal via the pinned env vars (§"Until-Mergeable Dispatch Signal"); a slash-string re-parse risks the 11.1.1 auto-delegation trap.
- **Blocking READY on a human.** Human approval, `REVIEW_REQUIRED`, and human/unknown-author threads & comments are surfaced, never gated (AC3/AC15/AC8). The drain loop waits only on bots + required/review-producing checks.
- **Letting the postmortem tail change the decision.** The decision is emitted BEFORE dispatch; the dispatcher always exits 0 and only appends to the trend file. A postmortem failure must be invisible to `REVIEW_HEAL_RESULT.decision` (AC12).
- **Dispatching `/pr-postmortem` as a nested `Task`.** Subagents cannot spawn subagents — launch a fresh detached `claude` process via `dispatch-pr-postmortem.sh` (R10).

## Related Skills

- `skills/autonomous-loop/SKILL.md` — the `/autonomous` outer loop; its EVALUATE step is entry sense (b) for review-heal.
- `skills/state-management/SKILL.md` — `.supervisor/` state-file conventions.
- The run-behavior config `.supervisor/config.json` (where `auto_review` and `webhook_url` live; legacy `.supervisor/notify-config.json` is still read as a fallback, new path wins when both exist) is documented in the dispatch scripts (`scripts/dispatch-pr-review.sh`, `scripts/send-webhook.sh`) and `commands/supervisor.md`.
- Supervisor Phase 4.5 (`agents/supervisor.md`) — the in-Supervisor review→fix→re-review machinery this loop is extracted from.

## Quality Gates

- PR-URL → head resolved via `gh pr view <pr-url> --json headRefName`. **Inline** `/review-pr`: branch fetched + checked out on the main thread's checkout. **Detached dispatched** drain: runs inside the dispatcher-created isolated sibling worktree (detached-HEAD at the head SHA) — no `git checkout` in the inline tree (§"Isolated worktree for the detached dispatched drain").
- Review uses `CODE_REVIEW_RESULT` v3 with `review_mode: diff_review`.
- Loop is bounded (default 3); fix worker is `general-purpose` with NO Task in its allowlist.
- PR-branch pushes are **fork-aware**: same-repo via explicit refspec `git push origin HEAD:<head_ref>` (regular, never `--force`); fork/cross-repo degrades to review-only `ESCALATED` (§"Fork-aware push").
- **`PASS`, `ESCALATED`, and — under `--until-mergeable` only — `READY` are the terminal `decision` values** (`READY` covers both `termination_reason: converged` and `sub_floor_converged`); no auto-merge in any of them.
- NEEDS_HUMAN / exhaustion posts findings to the PR and fires best-effort notifications (never blocks the loop).
- `REVIEW_HEAL_RESULT` emitted with all seven fields at `schema_version: 1` (default loop); `schema_version: 2` with `decision: READY` plus additive/optional drain fields (`channels_scanned`, `findings_validated`, `findings_dismissed`, `checks_waited`, `termination_reason`, `severity_floor`, `sub_floor_fixed`) under `--until-mergeable` (authoritative schema in `docs/RESULT_SCHEMAS.md`; no bump beyond 2).
- **`--until-mergeable` absent ⇒ default loop byte-for-byte unchanged** (AC7) — the all-channel scan, scoped check-wait, validate-then-fix, anti-churn, and postmortem-tail logic are strictly opt-in.
- Under `--until-mergeable`: ALL channels read each round — `gh pr view --json statusCheckRollup,reviews,latestReviews,…` PLUS `gh api graphql` review-threads PLUS `gh api .../issues/<n>/comments` (these comment/review/thread channels classified through `scripts/classify-bot-review.sh`, no re-implemented regexes) PLUS review-producing check-run output/annotations (gated by §U2.5's review-producing classification, NOT the comment author/marker regex); the scoped wait (§U2.5) settles required + review-producing checks before each READY test (optional checks excluded); every bot finding is validate-then-fixed (no severity floor **at fix time** — `--severity-floor` is termination-only, see above); **READY ⇔ required green AND scoped review-producing settled AND no unresolved validated bot findings across ALL channels** (§"READY redefinition"); fails CLOSED to `ESCALATED` on any unknown gated channel or an elapsed scoped wait; bounded by `--max-rounds` (default 5, **mechanized** via `scripts/drain-rounds.sh`, AC1/AC2); **never auto-merges — no `gh pr merge` anywhere — and never waits on a human (AC8)**.
- Postmortem Dispatch Tail runs AFTER the decision is emitted, is churn-gated (default threshold 2), opt-out via `--no-auto-postmortem`, and can never alter `REVIEW_HEAL_RESULT.decision` (`dispatch-pr-postmortem.sh` always exits 0).
- **Under `--until-mergeable` the drain is heal-only by default** — it spawns NO `Task(loomwright:code-reviewer)` of its own. The **ONE exception** is the earned fallback: when `no_review_lens_posted` holds (§U1's existing read shows no review lens posted in any channel AND every review-producing check is green-with-empty-output/absent/skipped), the drain runs exactly one diff review per drain run before declaring READY, fail-CLOSED toward running it (§"Earned Fallback Review — `no_review_lens_posted`").
