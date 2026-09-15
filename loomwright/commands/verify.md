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

# Headless (claude -p) — use the NAMESPACED form; bare /verify is "Unknown command" under detached claude -p:
claude -p "/loomwright:verify .supervisor/requirements/checkout/01-coupon.md"
```

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `<ticket-path>` | Yes | Path to the ticket. Under `.supervisor/requirements/` it is read as a `requirement`; under `.supervisor/jobs/` as a `brief`. Any other path exits 2 (`ticket_unresolved`). |
| `--branch <name>` | No | Branch whose HEAD is recorded on the `run_start` line and diffed against the base for `<run_dir>/diff.stat`. Default: `git branch --show-current`. |
| `--cheap` | No | Forwarded to the executor spawn as `model: "sonnet"` guidance per `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles". Default (`inherit`) unchanged when absent. |

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

4. **Spawn the executor in `--verify` mode** (the ONLY child; it owns env start/seed/auth-probe/spec authoring/walk/reset/stop/finish):
   ```
   Task(
     description: "Verify: <ticket basename> in <run_dir>",
     prompt: "--verify <run_dir>\nTicket: <ticket-path>\nBranch: <name or current>\n<--cheap passthrough note when given>",
     subagent_type: "loomwright:qa-executor"
     [, model: "sonnet"   # ONLY when --cheap was passed]
   )
   ```
   **DO NOT** run the walkthrough protocol yourself. **DO NOT** call `verify-env.sh start` from the main thread — the executor starts what it stops.

5. **Report.** On return, do NOT re-run `verify-run.sh finish` (the executor ran it; `run_end` is already the last line). Print `<run_dir>/summary.md` (the counts row `PASS: n · FAIL: n · BLOCKED: n · NOT_VERIFIABLE: n · total: n` and the per-AC table) and the `VERIFY_RESULT` block's `summary` field. If the executor returned without a `VERIFY_RESULT` (turn limit, crash), print `summary.md` as-is and say the block is missing — the evidence lines already written are the checkpoint.

## What it records

| file | writer | content |
|---|---|---|
| `<run_dir>/evidence.jsonl` | `verify-helpers.sh evidence-append` only | `run_start`, `env` (`non_prod_assert`, `start`, `seed`, `reset`, `stop`), `auth`, one `ac` per criterion, `run_end` |
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
