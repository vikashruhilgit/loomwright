## Purpose

The Dreaming command runs target agents in **reflection mode** over recent session logs **and worker summaries** to surface recurring patterns, distill insights, **collect durable memory candidates that workers proposed**, and **propose** bounded project LESSONS, agent persistent-memory entries, and project `CLAUDE.md` updates. It mirrors how human teams retrospectively review past work to extract durable lessons. It also **harvests recorded `convention_mismatch` findings into proposed `.agent/rules/` entries** and delivers accepted ones as a **pull request** rather than an in-place write. Each proposed update requires explicit **per-item** user approval; on Accept, `/dreaming` writes **project-memory facts** and **LESSONS** via the repo-root sole writers and promotes pending **orientation** and **agent-memory** proposals through their own sole writers, while **CLAUDE.md** proposals stay paste-to-apply. Harvested rules take a second gate — a **Pre-push confirmation** — before any branch, push, or PR exists. The memory writes those Accepts made in place may then travel as ONE optional **memory PR**, behind one per-run Pre-push confirmation. `/dreaming` never merges. There is no auto-write and no bulk-accept — Reject/Edit never writes.

This makes `/dreaming` the safe, auditable counterpart to live execution: read past logs and worker summaries, think out loud, and present a structured reflection report that the user can accept, reject, or edit item-by-item — with accepted memory/LESSONS persisted through the guarded sole writers, never by hand.

## Usage

```bash
/dreaming                                          # All agents, last 5 sessions
/dreaming --agent code-reviewer                    # Reflect with Code Reviewer only
/dreaming --agent red-team                         # Reflect with Red Team Reviewer only
/dreaming --agent qa-executor                      # Reflect with QA Executor only
/dreaming --sessions 10                            # All agents, last 10 sessions
/dreaming --agent code-reviewer --sessions 20      # Single agent, deeper history
/dreaming --agent all --sessions 3                 # Explicit all (default), last 3 sessions
/dreaming --full-model                             # Reflection spawns inherit the session model (skip the sonnet default)
/dreaming --force                                  # Skip the curation-readiness check and reflect anyway
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--agent` | No | `all` | Which agent(s) run reflection. Accepts `all`, `code-reviewer`, `red-team`, or `qa-executor`. `all` runs each supported agent in turn and aggregates their reports. Six agents have `memory: project` (Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor); v12.2.0 supports the three review-shaped agents listed above because their session logs carry the structured findings reflection needs (CODE_REVIEW_RESULT issues, red-team attack outcomes, QA_RESULT gates). Launch Pad, Product Owner, and QA Strategist are intentionally out of scope for v12.2.0 and may be added in a follow-up. |
| `--sessions N` | No | `5` | How many of the most recent **unconsumed** `.supervisor/logs/{session_id}.jsonl` files to feed into reflection (obtained from `curation-status.sh unconsumed N` — see GATHER step 1; a plain "N most recent" selection can never reach the tail). Values are clamped to the number of available unconsumed log files. Higher values surface more durable patterns at higher token cost. **This is the consumption window, and it is independent of the readiness `pending` count** — the readiness gate can report a backlog of 60 and a default run will still read 5 of them, leaving the rest for later runs, which then read the next-newest 5. The probe states both numbers (`pending=` and `window=`); raise this deliberately when you want a run to bite off more. The `5` here is the authoritative default — `curation-status.sh` mirrors it in `DREAMING_DEFAULT_WINDOW` and `test-curation-status.sh` group (o) fails if the two drift. |
| `--force` | No | off | Skips the **curation-readiness check** (see "Curation cadence" below) and reflects regardless of how little has accumulated. Without it, `/dreaming` declines — advisory, exit 0, never an error — when fewer than `threshold` **unreflected** session logs remain (logs never fed to reflection that carry reflection signal — *not* "logs newer than the last run"; see the cadence section for why that distinction is load-bearing). **The threshold is an UNVALIDATED starting guess** (in-script default `15`, override at `.curation.thresholds.dreaming` in `.supervisor/config.json`), so `--force` is the expected escape hatch, not an emergency one. |
| `--full-model` | No | off | Skips the default spawn-time model routing. By default (flag absent), each reflection spawn passes `model: "sonnet"` on its Task call — reflection is read-only, backward-looking analysis where the cheaper tier is adequate (authority: `docs/ARCHITECTURE_CONTRACTS.md` §Cost Profiles → "Async analysis surfaces"). With `--full-model`, the `model` param is omitted so reflection spawns `inherit` the session model. This routing applies ONLY to `/dreaming` reflection spawns; the same agents' forward roles (diff review, adversarial audit, voter, test execution) are never downgraded by it. |

