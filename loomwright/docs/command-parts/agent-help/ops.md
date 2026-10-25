### 📡 /telemetry — Opt-In GitHub Issues Telemetry

**Purpose:** Manage the plugin's opt-in telemetry, which is **disabled by default** and posts anonymised run outcomes as GitHub Issues to a repo you name. Consent flows only through this command — hooks **never** prompt. It fails **CLOSED on privacy**: any privacy-whitelist match aborts the post (core exits `2`), and there is **no origin-remote fallback**, because the plugin runs in arbitrary user projects whose origin is the wrong place to send telemetry.

**Usage:** `/telemetry status` · `/telemetry enable` · `/telemetry enable --include-result-block` · `/telemetry disable` · `/telemetry test`

**Learn More:** see `loomwright/commands/telemetry.md` and `loomwright/docs/TELEMETRY.md` for the wrapper-vs-core architecture, the scoring rubric, the privacy whitelist, and the exit-code table (0..5)

---

### 📜 /rules — House Rules Substrate (Committed `.agent/rules/`)

**Purpose:** Maintain the plugin's first **committed-convention** surface — `.agent/rules/*.json`, a version-controlled source of truth for project conventions so an implementer can read them on the DO side, not only get caught on review. Six subcommands: `list` (show all valid rules via the fail-safe `read-rules.sh` reader), `suggest` (scan the repo → PROPOSE rules for human review, never auto-writes), `add` (append-only, confirm-only write to a path-contained `.agent/rules/<category-slug>.json`, with optional `--supersedes` and repeatable `--applies-to` path routing), `retract` (curation/anti-rot: remove one existing rule object by id, confirm-only), `audit` (READ-ONLY, PROPOSE-ONLY re-validation of the STANDING store via `audit-rules.sh` — it has no write mode and NEVER runs a rule's `check`), and `check` (HUMAN-invoked: display + run `must` rules' checks only after explicit confirmation). **Trust boundary:** the reader emits each `check` as DATA and never executes it; `/rules check` requires explicit confirmation (mechanized in `rules-check.sh`, with a default-off `--no-cmd` unattended valve that wins over `--confirm`). **Advisory enforcement is wired (never-gating)** at the worker / Phase 4.5 self-heal / Code Reviewer / SessionStart-nudge seams (the reader is consumed as review/DO-side context, never a gate); `/rules add` and `/rules retract` are both mechanized into the sole-writer `add-rule.sh`. Subordinate to CLAUDE.md (on conflict, CLAUDE.md wins).

**Usage:** `/rules list` · `/rules suggest` · `/rules add` · `/rules retract` · `/rules audit` · `/rules check`

**Learn More:** see `loomwright/commands/rules.md` and the `rules` skill (`skills/rules/SKILL.md`, the protocol authority) for the schema, the fail-safe read contract, the path-contained atomic-append write discipline, and the `check`-is-arbitrary-shell trust boundary

---

### 🩺 /pr-postmortem — PR Review-Churn Root-Cause Analysis (Read-Only)

**Purpose:** On-demand, read-only diagnostic that analyzes a merged or open PR's review-and-fix churn to find the **root cause** of repeated review rounds. Gathers PR metadata, review threads, and diff stats via `scripts/pr-postmortem-gather.sh`, then buckets each review round into one of six root-cause classes (plan gap, missing context, convention mismatch, execution bug, quality gap, scope too large), flags rounds self-heal should have caught (`self_heal_miss`), and maps where in the agent flow (`launch_pad` / `worker` / `self_heal` / `unknowable`) each should have been caught. Never writes code, never gates, never blocks the PR — it appends one advisory `POSTMORTEM_RESULT` record to `.supervisor/postmortem/results.jsonl`, the seed corpus for a future synthetic eval harness.

**Learn More:** see `loomwright/commands/pr-postmortem.md` and the `pr-postmortem` skill for the gather protocol, the miss-class taxonomy, and the `POSTMORTEM_RESULT` schema

---

### 🔁 /autonomous — Continuous Autonomous Loop (v14, stacked PRs)

**Purpose:** Chain `/launch-pad → /supervisor` to drive a requirement to completion. Default mode is **multi-iteration** (cap 10, default 3) with **stacked PRs** — iteration N+1 branches from `iterations[N].branch` — and re-plans on two specific `SUPERVISOR_RESULT` signals. Pass `--single-iteration` (or `--max-iterations 1`) for v13's run-once behavior; `--no-stacked-branches` for the v13 branch-from-`main` cadence.

> **Foreground-assisted automation, not fire-and-forget.** The loop pauses at every existing interactive boundary (Launch Pad Phase 6 save, NO-GO override, Plan Review FAIL × 3, Supervisor adjudication 4-option, and the loop's own rubric gate). You must be at the terminal to answer them — unless you pass `--non-interactive-fallback` (CI / non-TTY: each gate takes its named can't-ask branch instead of asking — a Launch Pad Phase 6 PASS saves the brief (`saved_on_pass_non_interactive`), the others fail closed; full map in `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory"). `--notify` posts a gate-event webhook (resolved from `LOOMWRIGHT_WEBHOOK_URL` or `.supervisor/config.json`; legacy `.supervisor/notify-config.json` is still read as a fallback, new path wins) so an out-of-band notifier can ping you.

**Usage:**
```bash
/autonomous "<requirement string>"                                       # multi-iteration (default, cap 3), stacked PRs
/autonomous --requirement <path/to/file.md>                              # file-supplied requirement
/autonomous "<...>" --max-iterations N                                   # cap iterations at N (max 10)
/autonomous "<...>" --single-iteration                                   # v13 run-once (no loop)
/autonomous "<...>" --no-stacked-branches                                # each iteration branches from main (v13 cadence)
/autonomous "<...>" --non-interactive-fallback --notify                  # CI: named can't-ask branches + webhook pings
```

**Parameters:**
- `"<requirement>"` or `--requirement <path>` (required, choose one)
- `--max-iterations N` — cap for multi-iteration mode (default 3, max 10)
- `--single-iteration` — disable the loop; run Launch Pad → Supervisor once (v13-compat)
- `--no-stacked-branches` — each iteration branches from `main` instead of the prior iteration's branch
- `--non-interactive-fallback` — permit multi-iter in CI / non-TTY; each gate takes its named can't-ask branch instead of prompting (Phase 6 PASS saves, the no-rubric gate accepts, the rest fail closed — see the Question-gate inventory)
- `--notify` — POST gate-event webhooks (fails loud at INIT if no URL resolvable). `--allow-multi-iteration` is **deprecated** (multi-iter is the default now; accepted as a silent no-op)

**Multi-iteration re-plan signals (read from `SUPERVISOR_RESULT` plus iteration-scoped job artifacts):**

| Signal | Action |
|---|---|
| `completed` + `rubric_score N/M` with N<M | Pause for the rubric-gate AskUserQuestion. In the **default stacked-branch mode** the options are continue-to-next-iteration / stop-here / force-continue with **no merge required** (iter N+1 branches from iter N). With `--no-stacked-branches` the gate is merge-and-continue / stop / force and verifies the PR is merged via `gh pr view` (or `git merge-base --is-ancestor` fallback) before re-planning. |
| `failed` + Option-C detected on this iteration's brief | Anchored by `.supervisor/jobs/failed/{basename(current_brief_path)}` existence; `inter_subtask_gap` confirmed by grepping the failed brief contents, `SUPERVISOR_RESULT.error`, or `SUPERVISOR_RESULT.summary` (state.md intentionally not consulted). Re-plan immediately — no merge prompt, no PR was created. |
| anything else | Terminate the loop (done / paused_max_iterations / failed / aborted). |

**When to Use:**
- Multi-step requirements where Launch Pad → Supervisor is the natural chain
- Requirements with `## Outcomes Rubric` you want to iteratively satisfy (the default loop)
- After Phase 4.5 self-heal is not enough to address residual rubric gaps

**When NOT to Use:**
- Single small change with no rubric → `--single-iteration`, or just run `/supervisor` directly
- Crash recovery → no `--continue` yet; clean up manually and restart (the `SessionStart` hook injects recovery context on resume/clear/compact)
- Parallel `/autonomous` runs on the same repo → brief-save detection's primary signal is `LAUNCH_PAD_RESULT.saved_brief_path` (validated by `scripts/validate-launch-pad-result.py`); the `ls`-diff is a pre-v14.2.0 fallback only. Still run one autonomous / launch-pad invocation at a time per repo.

**Learn More:** the full flow diagram is in `loomwright/commands/autonomous.md` §"Flow Diagram"; the signal-extraction algorithm and refined-requirement (Iteration Note) templates are in `loomwright/skills/autonomous-loop/multi-iteration.md` §"Signal 1" and §"Signal 2"; troubleshooting is in `loomwright/docs/rationale/launch-pad-autonomous.md` §"/autonomous — usage notes". The protocol skill is `loomwright/skills/autonomous-loop/SKILL.md`.

---

### 📋 /backlog — Requirement Backlog Board (Read-Only, Owner-Gated Stamps)

**Purpose:** Answer "what is pending, done, in flight" from evidence, never from a hand-kept label. Every `*.md` under `.supervisor/requirements/` gets exactly one state, derived from run files, live lanes (`lane-status --json`), merged and open PRs (two cached `gh pr list` reads) and the item's own `## Status:` stamps. A done stamp appended under a first-line `pending` reads `done`. The board groups rows by folder, names the evidence behind each state, adds a right-size column, and prints totals that add up to the item count. `gh` failing ⇒ `github: unverified`, never a silent `open`.

**Usage:**
```bash
/backlog                       # the board
/backlog --json                # ONE JSON object (totals, items, stale runs)
/backlog --state <s>           # filter rows; totals stay whole-tree
/backlog --unknown             # unknown / brief_shipped items with a suggested fix
/backlog --verify [<item>...]  # owner-gated: propose, ask per item (BL-VERIFY / BL-CONFLICT), stamp only approved items
```

**Writes:** nothing, except `--verify`'s per-item owner-approved stamps through `automate-helpers.sh backlog-stamp --confirm`. In branch mode those are then published with `meta-sync.sh push --branch <branch> --paths-from <list>`. When it cannot ask (a subagent, or a non-interactive session), `--verify` lists its proposals and stamps nothing (`verify_requires_owner`).

**Learn More:** see `loomwright/commands/backlog.md`; the states and their precedence are defined once in the header of `loomwright/scripts/automate-helpers.d/backlog.sh`.

---

### 🧹 /janitor — Leftover Processes, Locks, Lanes and Worktrees (Read-Only, Owner-Picked Actions)

**Purpose:** One grouped report of everything the plugin left running or lying around: registered processes and unregistered look-alikes, run locks, lanes, worktrees and branches, and stale run state. Plugin-adjacent rows (CI-slot holders, a keep-awake) and not-the-plugin's rows (the host's own sessions, other python processes) are listed too, report-only. Each row shows its owner, age, state, evidence and a suggested action with the reason. A reader that fails shows as an `unknown` row, never as a clean group.

**Usage:**
```bash
/janitor                 # the report, then ONE owner question (JAN-ACT) in an interactive session
/janitor --report        # the report only; never asks, never acts
/janitor --json          # ONE JSON object (schema_version 1, groups[], rows)
```

**Writes:** nothing, except the rows the owner picks. Those run through `janitor-report.sh act --confirm`, which re-checks each row first and then calls its one guarded helper: `proc-registry.sh reap` or `stop-unregistered`, `automate-helpers.sh sweep --apply`, `lane-remove` or `config-restore`, and a `run-lock.sh` reclaim. A force-unlock needs a second `JAN-ACT` confirmation. When it cannot ask (a subagent, or a non-interactive session), it prints the report and acts on nothing.

**Learn More:** see `loomwright/commands/janitor.md`; the groups, row ids, actions and executors are defined once in the header of `loomwright/scripts/janitor-report.sh`.

---
