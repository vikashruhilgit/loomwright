# Review-heal — Until-mergeable dispatch signal and postmortem tail

The dispatching side of the drain: the signal the Supervisor dispatcher (`scripts/dispatch-pr-review.sh`) sets and the `review-pr-runner` reads, and the churn-gated postmortem tail the driver's `postmortem` step fires after the result block is written. A drain round never reads this file; read it when changing the dispatcher, the runner's env-var reading, or the postmortem tail. `SKILL.md` keeps every heading below as a pointer, so each `§"…"` citation still resolves. A `§"…"` citation below with no file named before it names a section of `SKILL.md`.

## Until-Mergeable Dispatch Signal (AC7 signal contract — PINNED)

> **This subsection is the SINGLE SOURCE OF TRUTH for how the until-mergeable signal is threaded from Supervisor's detached dispatcher → the `review-pr-runner` agent → its inline `/review-pr`.** The dispatcher (the **SETTER**, owned by the Supervisor/dispatcher subtask) and the runner (the **READER**, owned by the runner-agent subtask) must NOT diverge — so the concrete names are pinned here and consumed verbatim.

The Supervisor auto-dispatch launches the runner as a fresh detached HEADLESS process via the **`--agent` runner form** — `--agent loomwright:review-pr-runner "<pr-url>"` in print mode (`-p`); `scripts/dispatch-pr-review.sh` owns the full command line.

The `--agent` form has **NO flag surface** — you cannot pass `--until-mergeable` (or any `/review-pr` flag) on this command line, because the positional is the PR URL handed to the agent, not a slash string. So the signal is threaded via **environment variables** (NOT a `/review-pr` slash string in the dispatcher, NOT a new positional argument). This deliberately avoids the **11.1.1 spawn-depth auto-delegation trap**: there is no Task-spawn of the runner and no slash-command re-parse layer that could re-trigger auto-delegation.

**Pinned environment-variable contract:**

| Env var (SETTER: dispatcher / S4) | READER: runner → inline `/review-pr` | Semantics |
|---|---|---|
| **`LOOMWRIGHT_UNTIL_MERGEABLE`** | when truthy (`1` / `true`), the runner invokes its inline `/review-pr <pr-url>` **with `--until-mergeable`** | the master on/off signal. Absent or falsy ⇒ default diff-only loop (AC7 byte-for-byte unchanged). |
| **`LOOMWRIGHT_CHECK_WAIT_TIMEOUT`** | optional; when set, forwarded as **`--check-wait-timeout <value>`** | scoped check-wait bound (§"Wait-For-Settled-Checks"). |
| **`LOOMWRIGHT_FIX_FLOOR`** | when set, forwarded verbatim as **`--fix-floor <value>`** in BOTH loops (until-mergeable or not) | the fix-time severity floor (§"Fix floor"), resolved by the dispatcher in the checkout that holds `.supervisor/config.json` — the detached drain's sibling worktree has no `.supervisor/`. `invalid` is forwarded as-is so `/review-pr` refuses it (`fix_floor_invalid`). |
| **`LOOMWRIGHT_REVIEW_CHECK_PATTERN`** | optional; when set, forwarded as **`--review-check-pattern <value>`** | review-producing check selector glob (§"All-Channel Read" / §"Wait-For-Settled-Checks"). |

- The runner reads these env vars and **translates them into the corresponding `/review-pr` flags** on its inline invocation; the inline `/review-pr` body then runs the until-mergeable drain defined in `SKILL.md` §"Until-Mergeable Mode". Only `LOOMWRIGHT_UNTIL_MERGEABLE` is the on/off gate; the other three are forwarded ONLY when set.
- **Default-ON / opt-out at the Supervisor layer** is owned by the dispatcher subtask via the `auto_until_mergeable` config (see `SKILL.md`'s Pinned Canonical Names table) — when enabled, Supervisor sets `LOOMWRIGHT_UNTIL_MERGEABLE=1` on the dispatched process; opting out simply leaves it unset (or falsy), which restores the default loop. The skill defines only the *signal contract*; the *policy* of whether to set it lives at the Supervisor layer and is referenced, not re-coined, here.

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

`/pr-postmortem` is dispatched as a **fresh detached HEADLESS print-mode (`-p`) OS process** — NEVER a nested `Task` spawn. The detached form keeps the postmortem off the loop's path entirely (the dispatcher always exits 0, AC12); why it stays detached now that nesting is allowed: `docs/rationale/review-heal.md` §"Why the postmortem launches detached". The `-p`/`--print` flag is **required**: plain `claude "<prompt>"` (no `-p`) starts an *interactive REPL* which, detached with stdin from `/dev/null` and no TTY, never executes the slash command and never exits — `-p` runs the prompt non-interactively and exits. The dispatcher's launch line is:

```
( nohup "$CLAUDE_BIN" -p "/pr-postmortem $PR_URL" >>"$RUN_LOG" 2>&1 </dev/null & ) >/dev/null 2>&1 || true
```

(or a no-op when `claude`/config is absent). A per-PR marker under `.supervisor/postmortem-dispatch/` guards against re-dispatch — **once per PR per checkout** (persistent, not session-scoped); a PR that re-churns in a later session will not re-dispatch unless its marker file is removed. The exact invocation the tail makes (the driver's `postmortem` step, `script:review-heal-next-step.sh postmortem`, runs it from the plugin install root):

```
bash "<plugin root>/scripts/dispatch-pr-postmortem.sh" "<pr-url>" \
  --fix-cycles "$fix_cycles" \
  --decision "$decision" \
  $( [ "$repeat_check_failure" = true ] && printf -- '--repeat-check-failure' ) \
  $( [ "$unresolved_bot_feedback" = true ] && printf -- '--unresolved-bot-feedback' ) \
  [--postmortem-churn-threshold N] [--no-auto-postmortem]
```

The tail's exit status is **ignored** — the dispatcher always exits 0 and the decision is already emitted.
