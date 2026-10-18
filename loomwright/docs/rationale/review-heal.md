# Rationale — review-heal

Stories, history and explanations moved out of the runtime prompts of the `review-heal` loop group (`skills/review-heal/SKILL.md`, `commands/review-pr.md`, `agents/review-pr.md`). Nothing here is read at runtime and nothing here is a rule: every rule stayed in a runtime prompt or moved to the script that enforces it (`docs/loop-inventory/review-heal.md` records each row's home). A `story` row's home is `rationale:docs/rationale/review-heal.md#<slug>`, where `<slug>` is one of the headings below (lowercase, spaces to `-`, other characters dropped). A `rule` row homed here is a restatement whose rule part has its own row elsewhere; the bullet below names that row.

## Where the loop comes from

### Extraction from Phase 4.5

The loop is conceptually extracted from Supervisor **Phase 4.5**'s review→fix→re-review machinery (`agents/supervisor.md`, around the `while heal_iterations < max_heal_iterations` block) so it can run **independently in a fresh session keyed off a PR URL** — with no Supervisor job and no `.supervisor/state.md`. The **inline** `/review-pr` session has no worktree fan-out (it operates on the main thread's checkout), but the **detached dispatched** until-mergeable drain runs in its own dispatcher-created sibling worktree (`skills/review-heal/SKILL.md` §"Isolated worktree for the detached dispatched drain").

`skills/review-heal/SKILL.md` is a **reference contract** skill (markdown prose, not executable code), in the same spirit as `skills/autonomous-loop/SKILL.md` and `skills/state-management/SKILL.md`. Since automate-speed/12 the `--until-mergeable` drain's control flow is executed by `scripts/review-heal-next-step.sh`; the skill keeps the contracts the driver's `contract` strings cite.

### Review-pr purpose

`/review-pr` runs the **standalone PR review-and-heal loop** against an existing Pull Request URL. It resolves the PR's head branch, runs a bounded **review→fix→re-review** loop (Code Reviewer → on FAIL, a `general-purpose` fix worker → push → re-review), and leaves the PR open for a human. It is the loop of Supervisor **Phase 4.5** factored out so it can run **independently in a fresh session keyed off a PR URL** — no Supervisor job, no `.supervisor/state.md`. The **inline** `/review-pr` session has no worktree fan-out (it works on the main thread's checkout); the **detached dispatched** until-mergeable drain (launched by `dispatch-pr-review.sh`) runs in its own dispatcher-created sibling worktree so it never shares a working tree with an inline Phase 4.5 self-heal.

The loop contract is defined by the **`review-heal` skill** (`skills/review-heal/SKILL.md`) — the single source of truth for the bounded-loop semantics, PR-URL→branch resolution, notifications, the no-auto-merge rule, and the `REVIEW_HEAL_RESULT` block.

### Review-pr usage

```bash
/review-pr <pr-url>                          # Review-and-heal the given PR (e.g. https://github.com/owner/repo/pull/42)
/review-pr <pr-url> --until-mergeable        # Opt-in: drain machine-speed external signals until READY (never merges)
/review-pr <pr-url> --until-mergeable --max-rounds 8 --postmortem-churn-threshold 3
```

## Entry senses and the execution contract

### Why the dispatched runner is a headless process

Entry sense (a): after a `/supervisor` run finishes and auto-review is on, the dispatcher launches a brand-new detached **headless** `--agent loomwright:review-pr-runner <pr-url>` operating-system process. This is a true fresh session — the runner is the *main agent* of its own session and can therefore spawn child agents (the print flag does not change that; it is still the top-level agent of its headless session). The print flag (`-p` / `--print`) is **required**: `--agent` only *selects* the agent, it does not switch to headless mode, so an `--agent` launch without it is an *interactive* session that — detached with stdin from `/dev/null` and no TTY — is fragile and can hang on the first permission prompt instead of exiting. With the flag the run is non-interactive and exits.

The dispatcher **pins** the runner's permission regime instead of inheriting the project's: a headless mode that honours an explicit tool allowlist, plus that allowlist and a denylist (red-team-hardening item 01). It refuses to dispatch when the installed CLI cannot pin that regime, and degrades the drain to review-only when the project's ambient default is permissive. The flag values and both fallbacks live in `scripts/dispatch-pr-review.sh`'s header (its PERMISSIONS and REGIME PROBE sections). A tool call outside the allowlist is denied, never prompted, so the run still exits cleanly.

### Why the runner is never Task-spawned

The original reason for the rule was that *subagents cannot spawn subagents*. The host now allows subagent nesting (three layers by default, and a host setting can lower it — the host's sub-agents documentation), so that reason no longer holds; the rule is **retained pending owner review; see agnostic-phase1/06** (`docs/ARCHITECTURE_CONTRACTS.md` §"Subagent nesting"). A `Task`-spawned runner's children sit one layer deeper, and under a lowered limit its own `Task(code-reviewer)` / `Task(general-purpose)` calls would fail — the `/review-pr` command's delegated-runner failure reads "Task/Agent tool unavailable". The same history is why `commands/review-pr.md` opens with the inline-execution banner.

## The dispatcher's isolated worktree

### Isolated worktree mechanics

Isolation targets ONLY the **detached dispatched** drain — the one path that runs CONCURRENT with an inline Phase 4.5 self-heal. The inline `/review-pr` session has no concurrent self-heal and stays worktree-free. `scripts/dispatch-pr-review.sh` owns all of it (its header is the authority):

- **Sibling worktree, detached HEAD.** The dispatcher creates `../{project}-review-{pr_hash_short}` (a SIBLING of the primary checkout, OUTSIDE the tracked tree — never nested under the repo, which an inline `git add -A` could otherwise sweep) via `git worktree add --detach <path> <head-sha>`. Detached-HEAD at the head SHA avoids "branch already checked out" when the PR head is the inline session's current branch.
- **Trap-owned cleanup (executable, not a prompt step).** The dispatcher backgrounds a wrapper process that owns `trap cleanup EXIT`; on the runner's exit (READY/ESCALATED, error, or crash) the trap removes ONLY that hash-keyed worktree + lock dir. Before its `--force` the trap salvages the worktree's uncommitted content (a crashed or SIGTERMed runner's half-applied fix) to the DISPATCHING checkout's `.supervisor/salvage/<name>-<ts>/` (passed as `--dest`, beside the per-PR marker — not necessarily the primary checkout) via `scripts/worktree-salvage.sh` (fail-safe, `|| true`, the removal runs regardless); a hard kill (SIGKILL / power loss) skips both the salvage and the trap.
- **Marker reflects real dispatch.** An atomic per-PR lock is taken BEFORE the worktree; the durable per-PR marker is written ONLY AFTER the worktree + RUN_LOG header succeed (lock = "someone is dispatching"; marker = "a dispatch genuinely started").
- **Always fail-safe.** The dispatcher ALWAYS `exit 0`; the drain never merges and never `--force`-pushes (both stay rules in the skill: §"No auto-merge ever", §"Never `--force`").

## The default loop

### Fix floor table

The table of which severities each `FIX_FLOOR` fixes and which pass as dismissed follow-ups is carried by `scripts/fix-floor.sh`'s header (the authority); the skill used to restate it and now points there. A finding with no stated severity is always fixed, so a bot finding that states none is handled exactly as before the setting existed.

### Never force-push

A force-push would clobber concurrent commits on the PR branch (the human author may have pushed). The rule mirrors Phase 4.5's `git push  # ... NEVER --force` rule.

### Why fork-aware push

The fork-aware push closes a latent gap in the prior bare `git push`, which had no fork awareness and would have pushed to the wrong ref on a fork PR. The explicit `HEAD:<head_ref>` refspec exists because the detached drain worktree has no current branch name to push by default.

### Notification scripts

Both notifiers are fire-and-forget and always exit 0; any error (missing `jq`, missing `curl`, unset webhook URL, malformed payload) is absorbed silently. Their headers are the authority:

- `scripts/notify-desktop.sh` reads a JSON hook-style payload on stdin, builds a `(title, body)` pair, and fires an OS-native banner (macOS `osascript` / clickable `terminal-notifier`; Linux `notify-send`). Opt-out: `LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0`.
- `scripts/send-webhook.sh` is gated on a resolvable webhook URL (`LOOMWRIGHT_WEBHOOK_URL`, or the configured fallback the script resolves internally). The `--event-type gate` path builds its payload with `jq --arg` exclusively (injection-safe) and POSTs with a hard 5s timeout.

### No auto-merge and no PR creation

The loop never merges because of the no-self-trust / don't-weaken-a-gate principle: an automated reviewer that also merges its own approval removes the human gate. `/review-pr` never creates a PR because that would open a review→review recursion: a loop that produces no new PR cannot retrigger the post-`/supervisor` auto-dispatch (or `/autonomous` EVALUATE) on a PR it just created.

### Result block fields

The full list of `schema_version: 2` drain fields (`channels_scanned`, `findings_validated`, `findings_dismissed`, `checks_waited`, `termination_reason`, `severity_floor`, `sub_floor_fixed[]`, `rejected_instruction_like`, `dismissed`, `checks_untrusted`, `rules_gate`, and on `ESCALATED` only `escalation_cause` with its `escalation_*` companions) is owned by `docs/RESULT_SCHEMAS.md`; the skill no longer restates it. They arrived with red-team-hardening item 01 (`rejected_instruction_like`), dismissed-findings-01 (`dismissed`), ci-trust-probe-01 (`checks_untrusted`, `ci_untrusted`), automate-followups/07 (`rules_gate`) and automate-followups/31 (`escalation_cause`).

## Until-mergeable surface notes

### How supervisors auto-run threads until-mergeable

Supervisor's post-run auto-dispatch launches the runner through the headless `--agent loomwright:review-pr-runner "<pr-url>"` form, which has no flag surface (it avoids the 11.1.1 spawn-depth auto-delegation trap), so it cannot pass `/review-pr` flags on the command line. It threads the signal through environment variables that the `review-pr-runner` agent reads and translates into flags (the reader's table is `agents/review-pr.md` §"Reading the dispatch signal", rows RH-357 … RH-360; the setter is `scripts/dispatch-pr-review.sh`, row RH-321):

- `LOOMWRIGHT_UNTIL_MERGEABLE` (truthy ⇒ runner forwards `--until-mergeable`; absent/falsy ⇒ default diff-only loop) — row RH-322,
- `LOOMWRIGHT_CHECK_WAIT_TIMEOUT` (⇒ `--check-wait-timeout`) — row RH-323,
- `LOOMWRIGHT_REVIEW_CHECK_PATTERN` (⇒ `--review-check-pattern`) — row RH-324, and
- `LOOMWRIGHT_FIX_FLOOR` (⇒ `--fix-floor`, in both loops — the dispatcher resolves it in the checkout that holds `.supervisor/config.json`) — row RH-325.

Authoritative contract (setter ↔ reader, default-ON/opt-out policy): `skills/review-heal/SKILL.md` §"Until-Mergeable Dispatch Signal".

### Why every channel is read

Reading only `reviews` objects misses a PR **issue comment** — the PR #64 finding landed there, and `gh pr view --json reviews` never returns it; reading `reviews[].state` / `conclusion` / author alone misses the body where the actionable finding lives. The driver's `read` / `classify` steps read ALL channels and classify on `(login, body)` text.

## Anti-patterns restated elsewhere

### Anti-patterns history

- `prose_subfloor_stop` (implementation-quality/02 T01): on PR #435 a prose evaluation ran a whole extra round (~33 min) past a GREEN confirming pass and listed both rounds' findings in `sub_floor_fixed`.
- `oversized_wait_call` (implementation-quality/02 T03): required `ci` here runs 11–15 min, and a single `wait-for-checks.sh` call past the host's 600 s foreground cap is moved to the background — the `background_wait` death. The driver's `wait` step now passes `--call-max 540` and resumes on `CONTINUE` (row RH-257).
- `background_wait` (red-team-hardening item 04): under a headless run, ending the turn IS process exit, and the drain dies mid-wait with no `REVIEW_HEAL_RESULT` ever produced.
- Threading `--until-mergeable` as a slash string or positional in the `--agent` dispatcher risks the 11.1.1 auto-delegation trap; the dispatcher threads the pinned env vars instead (row RH-274).

### Restated anti-patterns

Each bullet restated a rule whose own row and home are named after it; the restatement left the runtime prompt.

- **Force-pushing the PR branch.** Never `git push --force` — clobbers concurrent author commits. Regular push only (same-repo via explicit refspec `git push origin HEAD:<head_ref>`). — rule rows RH-048, RH-050 (§"Never `--force`", §"Fork-aware push").
- **Pushing to `origin` for a fork/cross-repo PR.** The head ref is not on `origin`, so `git push origin HEAD:<head_ref>` updates the wrong ref or fails. Degrade to review-only `ESCALATED` instead. — row RH-051.
- **The detached drain checking out the PR head in the inline working tree.** The detached dispatched drain runs inside the dispatcher-created sibling worktree — it must not `git checkout "$HEAD_REF"` in the inline session's checkout. Worktree creation + removal are owned by the dispatcher's trap-wrapper, never a runner prompt step. — rows RH-023, RH-026.
- **Auto-merging on PASS.** Removes the human gate; explicitly forbidden. — rows RH-057, RH-058.
- **Task-spawning the runner.** AC9 forbids `Task(loomwright:review-pr-runner)` — run it as a session main agent or inline via `/review-pr`. — row RH-020.
- **Creating a PR from `/review-pr`.** Would open the door to review→review recursion. — row RH-060.
- **Letting notify failures abort the loop.** The notify scripts are fire-and-forget; treat their exit codes as advisory only (they always exit 0 anyway). — row RH-053.
- **Re-coining any pinned name.** Other subtasks consume the names verbatim — renaming breaks the contract. — rows RH-001, RH-003.

### Anti-patterns moved to their scripts

These bullets left the prompt because the script that now runs the step enforces them (the row's `script:` home):

- **Inventing a `gh pr view --json reviewThreads` flag.** Unresolved threads + author type are GraphQL-only; the flag does not exist; `drain-gh-read.sh review-threads` reads them (row RH-267).
- **Reading only one channel (or only metadata).** See §"Why every channel is read" (row RH-269).
- **Re-implementing the bot regexes.** `bot_author_re` / `review_marker_re` live only in `scripts/classify-bot-review.sh` (row RH-270).
- **Reinstating a hard-coded BLOCKING/HIGH severity floor.** Validate-Then-Fix replaced it: at the default `FIX_FLOOR` (`MEDIUM`) a validated MEDIUM (like the PR #64 finding) must be fixed. The only fix-time severity gate is the configured `FIX_FLOOR`, read through `scripts/fix-floor.sh`; `--severity-floor` is a termination-time gate only, never a fix-time filter (row RH-271; the not-an-alias rule stays in the skill as row RH-035).
- **Waiting on the whole rollup (or letting an optional check block/escalate).** The scoped wait observes only required + review-producing checks (row RH-273).
- **Letting the postmortem tail change the decision.** The decision is emitted before dispatch; the dispatcher always exits 0 and only appends to the trend file (row RH-276).
- **Dispatching `/pr-postmortem` as a nested `Task`.** `dispatch-pr-postmortem.sh` launches a fresh detached process (row RH-277).

## Quality gates restated elsewhere

### Quality gates

The skill's closing checklist restated rules each stated once above it; every bullet is listed with the row that carries its rule.

- PR-URL → head resolved via `gh pr view <pr-url> --json headRefName`; inline: fetch + checkout on the main thread's checkout; detached: run inside the dispatcher's isolated sibling worktree, no `git checkout` in the inline tree (RH-281 → RH-022, RH-023).
- Review uses `CODE_REVIEW_RESULT` v3 with `review_mode: diff_review` (RH-282 → RH-036 (the Step 2 review prompt) and RH-305).
- Loop is bounded (default 3); fix worker is `general-purpose` with NO Task in its allowlist (RH-283 → RH-036, RH-040).
- PR-branch pushes are fork-aware: same-repo via explicit refspec `git push origin HEAD:<head_ref>` (regular, never `--force`); fork/cross-repo degrades to review-only `ESCALATED` (RH-284 → RH-048, RH-050, RH-051).
- `PASS`, `ESCALATED`, and — under `--until-mergeable` only — `READY` are the terminal `decision` values (`READY` covers both `termination_reason: converged` and `sub_floor_converged`); no auto-merge in any of them (RH-285 → RH-013, RH-057, the skill's §"READY redefinition").
- NEEDS_HUMAN / exhaustion posts findings to the PR and fires best-effort notifications (RH-286 → RH-047, RH-053).
- `REVIEW_HEAL_RESULT` emitted with all seven fields at `schema_version: 1` (default loop); `schema_version: 2` with `decision: READY` plus additive drain fields under `--until-mergeable`; no bump beyond 2 (RH-287 → RH-012).
- `--until-mergeable` absent ⇒ default loop byte-for-byte unchanged (AC7) (RH-288 → RH-005, RH-064).
- Under `--until-mergeable`: ALL channels read each round, scoped wait, validate-then-fix at or above `FIX_FLOOR`, the READY equivalence, fail CLOSED to `ESCALATED` on any unknown gated channel or an elapsed scoped wait, bounded by `--max-rounds` (default 5, `scripts/drain-rounds.sh`), never auto-merges and never waits on a human (RH-289 → the `## Until-Mergeable Mode` rows, RH-268, RH-275, RH-057).
- The postmortem tail runs after the decision is emitted, is churn-gated (default threshold 2), opt-out via `--no-auto-postmortem`, and never alters `REVIEW_HEAL_RESULT.decision` (RH-290 → RH-008, `scripts/dispatch-pr-postmortem.sh`).
- Under `--until-mergeable` the drain is heal-only by default; the one exception is the earned fallback review, fail-CLOSED toward running it (RH-291 → RH-062 and the Earned Fallback Review rows).

## Related surfaces

### Related skills

- `skills/autonomous-loop/SKILL.md` — the `/autonomous` outer loop; its EVALUATE step is entry sense (b) for review-heal.
- `skills/state-management/SKILL.md` — `.supervisor/` state-file conventions.
- The run-behavior config `.supervisor/config.json` holds `auto_review`, and a `webhook_url` there is only an informational mirror for the local run-view UI: the authoritative webhook destination is the user-scope egress file resolved by `scripts/resolve-egress-config.sh` (legacy `.supervisor/notify-config.json` is still read as a fallback for that informational read; the new path wins when both exist). It is documented in the dispatch scripts (`scripts/dispatch-pr-review.sh`, `scripts/send-webhook.sh`) and `commands/supervisor.md`.
- Supervisor Phase 4.5 (`agents/supervisor.md`) — the in-Supervisor review→fix→re-review machinery this loop is extracted from.

### Review-pr see also

- `skills/review-heal/SKILL.md` — the authoritative loop contract (pinned names, bounded-loop semantics, notify, no-auto-merge, `REVIEW_HEAL_RESULT`).
- `agents/review-pr.md` — the `loomwright:review-pr-runner` agent this command runs inline.
- `commands/supervisor.md` — Supervisor Phase 4.5, the in-job review→fix→re-review machinery this loop is extracted from.

### Review-pr runner related

`agents/review-pr.md` keeps its own `## Related` list (that file is not edited by the prompt diet); its text is:

- `skills/review-heal/SKILL.md` — **the authority** for this loop (pinned names, bounded-loop semantics, notify, no-auto-merge, `REVIEW_HEAL_RESULT`).
- `agents/supervisor.md` Phase 4.5 — the in-Supervisor review→fix→re-review machinery this loop is extracted from.
