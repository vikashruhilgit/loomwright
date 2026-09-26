# 04 — The self-test suite fires REAL notifications: make every test hermetic for egress (webhook + desktop)

## Status: pending

> **Origin (2026-09-26).** Surfaced while `/automate` run `automate-2026-09-22-013403` was resumed from a
> terminal and ran the full test loop before a push. Two real alerts reached the owner:
> - **ntfy (network):** five `{"event_type":"gate","gate_type":"drain_died","context":"https://github.com/acme/widgets/pull/42"}`
>   pushes in 12 s (2026-09-26T01:34:16Z–28Z) on the owner's real ntfy topic. `acme/widgets/pull/42` is the
>   suite's placeholder PR, not a real repo.
> - **macOS banner:** "Claude Code — /verify run verify-nourl needs a human sign-in (ticket: t.md)". `verify-nourl`
>   and `t.md` are AC9 fixture values in `test-propose-from-verify.sh`.
>
> Desktop-app sessions did not fire them because their shell lacks the variable. A terminal session inherits
> `export LOOMWRIGHT_WEBHOOK_URL=https://ntfy.sh/<topic>` from `~/.zshrc`, and every test it runs inherits it too.

## Problem
Tests fake `HOME` but not the **environment** or the **OS notifier**, so a production egress path can
fire from a test:

1. **Webhook leak, from the env var.** `send-webhook.sh` gives `LOOMWRIGHT_WEBHOOK_URL` the highest
   precedence, above the user-scope `~/.claude/loomwright/egress.json` (red-team-02 kept it that way on
   purpose). A test that sets `HOME="$fake"` therefore still posts to the real URL. `test-dispatch-pr-review.sh`
   case 37 ("death detection") and its siblings start the REAL dispatcher with a stub `claude` that exits
   without a `REVIEW_HEAL_RESULT`. The detached trap then runs `send-webhook.sh --event-type gate --gate-type
   drain_died --context "$_pr"`, which is the `drain_died` branch of `dispatch-pr-review.sh`'s `trap_cleanup`,
   in the "Best-effort notifications" block.
2. **Desktop leak, from the real notifier.** `test-propose-from-verify.sh` AC9 stages `ln -sf
   "$HERE/notify-desktop.sh" "$STUBDIR3/notify-desktop.sh"`, which is the REAL notifier. It shims only
   `curl wget nc ncat` on `PATH`. The `needs_auth` pause reaches `verify_notify_dispatch` in `verify-helpers.sh`,
   then `notify-desktop.sh`, then `osascript display notification`. AC8-notify in the same file does it
   correctly with a stub notifier. AC9 does not.

This is one defect class, **a test can reach a real egress channel**, and not two bugs. Fixing the two
known sites alone leaves the next test free to do the same. Of the ~24 `test-*.sh` that reference a
notifier or dispatcher, only 4 (`test-webhook.sh`, `test-resolve-egress-config.sh`,
`test-propose-from-verify.sh`, `test-telemetry.sh`) scrub `LOOMWRIGHT_WEBHOOK_URL` at all. None
neutralise `osascript`/`notify-send` apart from `test-notify-desktop.sh`, which exercises the notifier itself.

Effects: false `drain_died` / `needs_auth` alerts on the owner's phone and desktop during every terminal-run
suite, which trains the owner to ignore real ones. A test run also sends fixture data to a third-party
service (ntfy.sh).

## Goal
No test in `loomwright/scripts/test-*.sh`, `scripts/test-*.sh` or `adapters/*/test-*.sh` can reach a real
webhook, telemetry endpoint, or OS notification. This must hold however the test is invoked:
`run-self-tests.sh`, the hand-rolled `for t in …/test-*.sh; do bash "$t"; done` loop agents use before
pushing, or `bash test-x.sh` alone. A new test is covered without anyone remembering to opt in.

## Scope (recommendation, not pre-decided)
- **Egress-scrub + notifier-shim at the choke point.** One sourced helper (e.g. `scripts/test-hermetic.sh`)
  that:
  - unsets every egress env var: `LOOMWRIGHT_WEBHOOK_URL`, `LOOMWRIGHT_TELEMETRY_REPO`, and any other
    `LOOMWRIGHT_*` that routes data out. Derive the list from `send-webhook.sh`, `telemetry*`,
    `resolve-egress-config.sh` and `notify-desktop.sh`. Do not hand-copy it.
  - sets `LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0`. The opt-out already exists in `notify-desktop.sh`.
  - prepends a `PATH` shim dir whose `osascript`, `notify-send`, `terminal-notifier`, `curl` and `wget` record
    the call to a log and exit 0.
  - Tests that deliberately exercise a notifier (`test-webhook.sh`, `test-notify-desktop.sh`, AC8-notify)
    re-enable only what they assert on, inside their own subshell.
- **Where it is applied, one of:**
  - **(A)** `run-self-tests.sh` exports it for every worker. Pick A only together with a test-side guard,
    because it does not cover direct `bash test-x.sh` or the hand-rolled loop.
  - **(B)** every test sources it on line 2, and a lint (`check-*` + its `test-check-*`) fails CI on any
    `test-*.sh` that does not source it. This is the ratchet.
  - **(C)** both.
- **Fix the two known sites** in the same change: dispatcher tests (`test-dispatch-pr-review.sh`,
  `test-hook-dispatch-on-pr-create.sh`, `test-worktree-salvage.sh`, `test-automate-helpers.sh`,
  `test-dispatch-pr-postmortem.sh`) and `test-propose-from-verify.sh` AC9, which gets a stub notifier like
  AC8-notify.
- **Detached children:** the dispatcher's `trap_cleanup` runs in a detached `bash -c` that receives
  `_notify`/`_webhook` as positional args and inherits the env. Confirm the scrubbed env and shimmed
  `PATH` reach that child, and add an assertion. Do not assume it.
- Out of scope: changing `LOOMWRIGHT_WEBHOOK_URL`'s production precedence (a red-team-02 decision), and
  the owner's `~/.zshrc`.

## Acceptance criteria
- [ ] With `LOOMWRIGHT_WEBHOOK_URL=http://127.0.0.1:<port>` pointing at a local listener, and a
      `PATH`-first recording `osascript`/`notify-send`, the FULL suite run through `run-self-tests.sh` produces
      **zero** hits on the listener and **zero** recorded notifier calls, except the ones the notifier's
      own tests assert on, which go to their own stubs.
- [ ] The same holds for a hand-rolled `for t in loomwright/scripts/test-*.sh; do bash "$t"; done`.
- [ ] `test-dispatch-pr-review.sh` case 37 run alone with the env var set sends nothing to the listener,
      and its `.died`-marker + `DRAIN_DIED` assertions still pass.
- [ ] `test-propose-from-verify.sh` AC9 run alone produces no recorded `osascript` call, and AC9 still passes.
- [ ] If option B/C is chosen: a new `test-*.sh` without the helper fails the lint (mutation control: a
      fixture test missing it ⇒ lint red; adding it ⇒ green).
- [ ] Mutation control: removing the helper's `unset LOOMWRIGHT_WEBHOOK_URL` makes the first AC record
      listener hits.
- [ ] The full test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` +
      `scripts/check-vendor-coupling.sh`) is green.

## Verified premises (read at `main @ 4f681d0`, 2026-09-26)
- `send-webhook.sh` resolves the URL from `LOOMWRIGHT_WEBHOOK_URL` first, then the user scope
  `~/.claude/loomwright/egress.json` via `resolve-egress-config.sh`. A fake `HOME` does not neutralise the env var.
- `dispatch-pr-review.sh`: `NOTIFY_BIN`/`WEBHOOK_BIN` resolve to the sibling real scripts. `trap_cleanup`'s
  no-result branch fires both `notify-desktop.sh` (`notification_type: drain_died`) and
  `send-webhook.sh --gate-type drain_died --context "$_pr"`.
- `test-dispatch-pr-review.sh` has no `unset`/`env -u` of `LOOMWRIGHT_WEBHOOK_URL`. Case 37 runs the real path
  (`run_real` + `stub_claude_no_result`).
- `test-propose-from-verify.sh` stages `ln -sf "$HERE/notify-desktop.sh" "$STUBDIR3/notify-desktop.sh"` for
  AC9 and shims only `curl wget nc ncat`.
- `notify-desktop.sh` already honours `LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0` as a silent no-op.
- CI runs the suite through `loomwright/scripts/run-self-tests.sh` (PR #261), which sets no egress env.
- Duplicate check (2026-09-26): no requirement under `.supervisor/requirements/**`, no `origin/main` commit,
  and no open PR covers test-egress hermeticity. Related but distinct, all done: red-team-hardening/02
  (production egress consent), red-team-hardening/04 (added the `drain_died` alert), review-remediation/06
  (notifier unit coverage), verify-walkthrough/05 (`/verify --notify`).
