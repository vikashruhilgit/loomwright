---
description: Walk a ticket's acceptance criteria through the RUNNING app — one evidenced PASS / FAIL / BLOCKED / NOT_VERIFIABLE verdict per criterion, advisory only
---

> **Execute this workflow inline as the main thread.** `/verify` is a thin shell: its main-thread steps are **shell-outs to `${CLAUDE_PLUGIN_ROOT}/scripts/verify-run.sh`** (so the tested code IS the executed code) plus ONE Task spawn of the QA Executor in `--verify` mode. Do not delegate the shell itself via the Agent tool — the executor is the only child, and it must be a first-level Task descendant so its `SubagentStop` hook (`validate-qa-result.py`, the `VERIFY_RESULT` branch) fires.

> **Execution contract:** the protocol — AC extraction, AC → spec derivation, the four verdicts, the V7 mutation carve-out, evidence-per-AC, budget — is defined ONCE in `${CLAUDE_PLUGIN_ROOT}/skills/verify-walkthrough/SKILL.md`. This command documents the *surface* only and does not restate it.

# Command: /verify

## Purpose

No other surface verifies a ticket against the running app: `## Executable Acceptance` is `cmd:` / `corpus-task:` only, `/qa-executor` crawls the whole app from discovery and forbids form submission, and Phase 4.5 / CI review read the diff. `/verify <ticket>` reads the ticket's acceptance criteria, **refuses to touch anything not proven non-prod**, starts the app from the committed `.agent/verify.json` contract, walks each AC with Playwright, and appends exactly one of four verdicts per AC with evidence — where `PASS` is recorded ONLY when the Then was observed, and `NOT_VERIFIABLE` says so when it cannot be.

**Advisory only.** A verify run changes no `heal_decision`, blocks no PR, and merges nothing. Its outputs are `<run_dir>/summary.md` (derived from `evidence.jsonl`) and the executor's `VERIFY_RESULT` block.

## Usage

```bash
/verify <ticket-path>                        # a requirement (.supervisor/requirements/…) or a brief (.supervisor/jobs/…)
/verify <ticket-path> --branch <name>        # verify that branch's HEAD (default: the current branch)
/verify <ticket-path> --cheap                # run the executor on Sonnet (see docs/ARCHITECTURE_CONTRACTS.md §"Cost Profiles")
/verify --resume <run_id>                    # resume a run that paused for a human sign-in (needs_auth / session_expired)

# Headless (claude -p) — use the NAMESPACED form; bare /verify is "Unknown command" under detached claude -p:
claude -p "/loomwright:verify .supervisor/requirements/checkout/01-coupon.md"
```

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `<ticket-path>` | Yes (unless `--resume`) | Path to the ticket. Under `.supervisor/requirements/` it is read as a `requirement`; under `.supervisor/jobs/` as a `brief`. Any other path exits 2 (`ticket_unresolved`). |
| `--branch <name>` | No | Branch whose HEAD is recorded on the `run_start` line and diffed against the base for `<run_dir>/diff.stat`. Default: `git branch --show-current`. |
| `--cheap` | No | Forwarded to the executor spawn as `model: "sonnet"` guidance per `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles". Default (`inherit`) unchanged when absent. |
| `--resume <run_id>` | No (mutually exclusive with `<ticket-path>`) | Resumes the paused run at `.supervisor/verify/<run_id>` — see "Resume flow" below. Errors, never silently starting a new run, when that dir does not exist. |

## Main-thread steps

Every deterministic step is a shell-out; the main thread never re-implements what `verify-run.sh` does.

1. **Read the protocol.** `Read("${CLAUDE_PLUGIN_ROOT}/skills/verify-walkthrough/SKILL.md")` — the four verdicts and the carve-out are needed to read the result, not just to produce it.

2. **Preflight (contract → non-prod proof → run dir).** Run in ONE Bash call and capture stdout and the exit status in two statements:
   ```bash
   out=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-run.sh" preflight <ticket-path> [--branch <name>]); rc=$?
   ```
   Then branch on `rc`:
   | `rc` | meaning | action |
   |---|---|---|
   | `3` | no verification contract at `.agent/verify.json` (or unreadable) — nothing was created, nothing was called | **print `out` verbatim** — it names the absence AND the bootstrap line (`propose-verify.sh --non-prod … --confirm`) — and **STOP** |
   | `1` | `non_prod_assert_failed` — the contract's non-prod assertion did not pass; the run dir holds only `run_start` + the failing `env` line | print the reason and **STOP** — fail CLOSED, nothing was started |
   | `2` | `ticket_unresolved` / usage — the path is not a requirement or brief, or has no `## Acceptance Criteria` | print the reason and **STOP** |
   | `0` | contract read, non-prod proven in THIS run, run dir minted | continue |

3. **Parse the run dir.** `run_dir=$(printf '%s\n' "$out" | tail -1 | sed -n 's/^run_dir=//p')` — `preflight` prints `run_dir=<path>` as its LAST stdout line. Empty ⇒ STOP with `run_dir_unparsed`.

4. **Spawn the executor in `--verify` mode** (the ONLY child; it owns env start/seed/auth-check/spec authoring/walk/reset/stop/finish):
   ```
   Task(
     description: "Verify: <ticket basename> in <run_dir>",
     prompt: "--verify <run_dir>\nTicket: <ticket-path>\nBranch: <name or current>\n<--cheap passthrough note when given>",
     subagent_type: "loomwright:qa-executor"
     [, model: "sonnet"   # ONLY when --cheap was passed]
   )
   ```
   **DO NOT** run the walkthrough protocol yourself. **DO NOT** call `verify-env.sh start` from the main thread — the executor starts what it stops.

5. **Report.** On return, do NOT re-run `verify-run.sh finish` (the executor ran it, UNLESS the run paused — see below; `run_end` is already the last line when it did run). Read the `VERIFY_RESULT` block's `status` / `pause_reason`:
   | `status` | action |
   |---|---|
   | `paused` | The run stopped for a human sign-in — no spec was authored/walked/finished beyond the point of the pause. Print the pause instruction (below) and **STOP**. Do NOT print `summary.md`'s counts row as if the run finished. |
   | `completed` / `aborted` | Print `<run_dir>/summary.md` (the counts row `PASS: n · FAIL: n · BLOCKED: n · NOT_VERIFIABLE: n · total: n` and the per-AC table) and the `VERIFY_RESULT` block's `summary` field. |

   If the executor returned without a `VERIFY_RESULT` (turn limit, crash), print `summary.md` as-is and say the block is missing — the evidence lines already written are the checkpoint.

   **Pause instruction (`status: paused`, either `pause_reason`).** Read the real `storage_state_path` / `base_url` from `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-verify.sh" --repo <dir>` (never hard-coded) and print exactly:
   ```
   npx playwright codegen --save-storage=<storage_state_path> <base_url>
   sign in, close the window
   /verify --resume <run_id>
   ```
   The plugin process never opens a browser itself and never echoes anything read from the storage-state file — only its path.

   **Storage-state gitignore warning (fresh runs only, once).** Immediately before printing the pause instruction for a run reached via `<ticket-path>` (never on a `--resume` invocation's own report — this check is one-shot, on the FIRST pause): when the contract's `auth.method` is `storage_state`, run `git -C <dir> check-ignore -q <storage_state_path>`; a non-zero exit (the path is NOT ignored) prints ONE warning naming the path (it contains session cookies). A zero exit (already ignored) prints nothing.

## Resume flow (`--resume <run_id>`)

A separate entry point — no ticket path, no preflight, no new run dir:

1. `run_dir=.supervisor/verify/<run_id>`. `[ -d "$run_dir" ]` or **STOP** with an error naming the missing dir — never silently start a fresh run under that id. Then guard against resuming a run that already finished (never merely paused): `jq -r 'select(.event=="run_end") | .status' "$run_dir/evidence.jsonl" 2>/dev/null | tail -1` — a non-empty result means a `finish` line was already appended (`completed` or `aborted`) and there is nothing paused to resume; print an error naming the run's already-`<status>` state and **STOP** rather than proceeding into `auth-check` on a finished run (a finished run has no ambiguity to resolve, and re-entering `auth-check` on it would silently re-probe a run nobody paused).
2. Run in ONE Bash call, capturing stdout and the exit status in two statements:
   ```bash
   out=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-run.sh" auth-check "$run_dir" --repo <dir>); rc=$?
   ```
3. `rc == 4` ⇒ print the SAME pause instruction as step 5 above, verbatim (no new run dir, no `resume` line appended) and **STOP**.
4. `rc == 0` ⇒ append `{event: resume, reason: human_signed_in}`:
   ```bash
   ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   jq -cn --arg ts "$ts" --arg run_id "<run_id>" \
     '{schema_version: 1, ts: $ts, run_id: $run_id, event: "resume", reason: "human_signed_in"}' \
     | bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-helpers.sh" evidence-append "$run_dir" -
   ```
   then spawn the executor exactly as step 4 above (`--verify <run_dir>`; no special resume flag on the agent boundary — the executor detects resume from the run dir's own contents, see `agents/qa-executor.md`). Derive `Ticket:` / `Branch:` for the Task prompt from the `run_start` line already in `evidence.jsonl` (`jq -r 'select(.event=="run_start") | .ticket_path'` / `.branch`), never re-asked.
5. Continue at step 5 (Report) above — this time WITHOUT the one-shot gitignore check (already done on the first pause).

## What it records

| file | writer | content |
|---|---|---|
| `<run_dir>/evidence.jsonl` | `verify-helpers.sh evidence-append` only | `run_start`, `env` (`non_prod_assert`, `start`, `seed`, `reset`, `stop`), `auth` (incl. `needs_auth`/`expired`), `pause`/`resume` (needs_auth / session_expired), one `ac` per criterion, `run_end` |
| `<run_dir>/acs.json`, `diff.stat` | `verify-run.sh preflight` | the extracted ACs; the branch-vs-base diff summary (advisory) |
| `<run_dir>/specs/<ac_id>.spec.ts` | the executor | one `[ACn]`-titled spec per verifiable AC (template in the skill) |
| `<run_dir>/artifacts/<ac_id>/` | `verify-run.sh walk` | screenshots, traces, non-2xx bodies, page body on failure |
| `<run_dir>/summary.md` | `verify-helpers.sh summary-build` | DERIVED — never hand-edited |

Where each verdict may come from — `PASS` / `FAIL` only from `walk`'s reporter ingest, `NOT_VERIFIABLE` / `BLOCKED` from `verify-run.sh verdict` — is documented in `docs/RESULT_SCHEMAS.md` §VERIFY_RESULT; `verify-run.sh verdict … PASS` is refused (`pass_requires_observation`).

## Requirements

- A committed `.agent/verify.json` (bootstrap: `propose-verify.sh --non-prod <regex|env=NAME=VAL|cmd=<shell>> --confirm` — `preflight` prints the exact line when it is absent)
- The contract's `non_prod_assert` must PASS in this run — there is no override
- `@playwright/test` resolvable from the target repo (`npx --no-install playwright`); when it is not, every remaining AC is recorded `BLOCKED` / `playwright_unavailable` and the run finishes `aborted` — the plugin never installs it
- `jq`, `git`, `python3`, `node`/`npx`

## See Also

- `/qa-executor` — the full discovery-driven L1 protocol (`--verify` is its narrow mode)
- `${CLAUDE_PLUGIN_ROOT}/skills/verify-walkthrough/SKILL.md` — the protocol authority
- `docs/RESULT_SCHEMAS.md` §VERIFY_ENV / §VERIFY_EVIDENCE / §VERIFY_RESULT — the three schemas a run touches
- `/agent-help` — list all commands
