---
description: Read-only post-hoc analysis of an existing PR — categorize each review round into one of 6 root-cause classes, attribute it to a flow stage, print a root-cause report, and append one fail-safe trend line to .supervisor/postmortem/results.jsonl
---

> **Execute this workflow inline as the main thread.** Do NOT delegate to any agent via the Task tool — `/pr-postmortem` is a thin, read-only analysis shell that runs entirely inline on the main thread. It spawns no sub-agents and makes no extra model/API calls beyond the main thread's own reasoning. The governing protocol is `${CLAUDE_PLUGIN_ROOT}/skills/pr-postmortem/SKILL.md`.

# Command: /pr-postmortem

## Purpose

After an agent-generated PR has absorbed several rounds of post-PR review-and-fix, `/pr-postmortem` asks **"why did this PR need back-and-forth?"** It gathers the PR's review/churn signals (read-only), buckets each review round into a reproducible root-cause class, attributes it to a flow stage, prints a human-readable root-cause report, and appends one trend line so the churn becomes a measurable signal instead of anecdote. The trend file is the **seed corpus for a future synthetic eval harness**.

## Usage

```bash
/pr-postmortem <pr-url>                              # full URL: https://github.com/OWNER/REPO/pull/N
/pr-postmortem OWNER/REPO#N                          # short form
```

## What This Does

### Step 0 — Load the canonical protocol skill (always)

Before anything else, read the governing protocol so the workflow runs the up-to-date version rather than a remembered shape. Use `${CLAUDE_PLUGIN_ROOT}` — the canonical Claude Code variable that resolves to the plugin install dir at runtime (works on both maintainer dev checkouts and marketplace installs). Never use `loomwright/...` here — that path only resolves for the plugin maintainer:

```
Read ${CLAUDE_PLUGIN_ROOT}/skills/pr-postmortem/SKILL.md
```

### Then execute the skill's protocol inline (in order)

1. **Parse input** — a PR URL or `OWNER/REPO#N`; pass it straight to the gather script.
2. **Gather (read-only)** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-postmortem-gather.sh" "<input>"`, parse its single JSON object. On `{"status":"unavailable",...}` print one clear line and exit gracefully (no partial write).
3. **Categorize** each review round into exactly one of `plan_gap | missing_context | convention_mismatch | execution_bug | quality_gap | scope_too_large`, set the optional `self_heal_miss` flag, and attribute a `flow_stage` (`launch_pad | worker | self_heal | unknowable`).
4. **Print** the categorized root-cause report (PR identity, size, review_rounds, per-round breakdown, root-cause narrative).
5. **Append** exactly one `POSTMORTEM_RESULT` JSON line to `.supervisor/postmortem/results.jsonl` (jq-built, fail-safe).

See `skills/pr-postmortem/SKILL.md` for the full class definitions, the categorization heuristics, the jq-built append snippet, and the trend-line schema. **That skill is the authority** — this command is just the entry point.

## Curation cadence (reporting only — this command NEVER declines)

`/pr-postmortem` reports its curation cadence and contributes to the SessionStart nudge, but — unlike `/dreaming` and `/insights` — **it never declines and has no `--force` flag.** Both of its invocation forms above are targeted at ONE named PR, so a gate answering "only 3 PRs since your last run, come back later" would refuse to answer a direct question the user just asked. The declining gate applies only to the corpus-wide passes.

Before the report, print the readiness lines from the probe (this command shell prints them; `skills/pr-postmortem/SKILL.md` stays the single source of truth for the report itself and is untouched):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/curation-status.sh" status
```

`/pr-postmortem`'s last run is **derived, never stored**: it is the max `.ts` over `.supervisor/postmortem/results.jsonl` records with **`.source != "automate_drain"`**. That filter is load-bearing — since v15.28.0 the ledger is a unified corpus with two producers, and the engine-native `automate_drain` lines appended by `automate-helpers.sh learning-emit` were never *run* by a human. Drain and command records interleave chronologically, so a bare `map(.ts)|max` would report an engine append as "you ran /pr-postmortem". The probe's `pending` count for this command ("merged PRs absent from the ledger") is computed **only on an explicit `status` invocation**. The SessionStart nudge is strictly local-only — it makes no `gh` call and therefore **never mentions `/pr-postmortem` at all**; its line is built from the `/dreaming` and `/insights` rows only. So this command contributes to the *cadence record* (its derived `last_run` shows up in `status`), not to the nudge text.

**The pending count is windowed and is a lower bound.** It comes from `gh pr list --state merged --limit 50`, i.e. only the **50 most recent merged PRs**. On a repo past that mark — this one is already past PR #134 — an older merged PR that was never postmortem'd falls outside the window and is not counted, so the reported number can undercount the real backlog. The cap is deliberate: one bounded round-trip, no pagination, on an advisory probe. Read `pending` as "at least N", never as a total.

### Run report (four mandatory lines)

Every `/pr-postmortem` run ends with these four lines, in addition to the categorized root-cause report:

- **When it last ran** — the `last_run` / `age_days` the probe reported (`never` when the ledger holds no command-authored record).
- **What changed since** — the delta the probe reported (`unknown` is a legitimate answer here; never substitute a fabricated `0`).
- **What it produced this time** — the categorized rounds and the one appended trend line.
- **What that will improve** — the concrete downstream effect (e.g. "this PR's churn class now feeds the heal-signal catch-rate section of `/insights`").

## Guarantees

- **Read-only on the analyzed repo.** Only `gh pr view` (read-only, via the gather script) touches the PR. Nothing is written, branched, committed, or commented on the analyzed PR or its repo.
- **Inline, no sub-agents.** Runs entirely on the main thread; no `Task` spawns, no extra API calls.
- **Fail-safe.** The command **always exits 0**. If the gather script returns `unavailable`, it prints one line and stops with no trend write. The trend append is best-effort (jq-built, injection-safe) and a failed append prints one warning but never crashes — the report has already printed.
- **The only write** is exactly one JSONL line to `.supervisor/postmortem/results.jsonl` under the current working `.supervisor/` (never the analyzed repo). This append-only trend file is the seed corpus for the deferred synthetic eval harness.

## Related Commands

- `/review-pr <pr-url>` — the active review-and-heal loop on an existing PR (review → fix → re-review). `/pr-postmortem` is the read-only retrospective complement: it explains churn, it does not fix.
- `/dreaming` — read-only post-hoc reflection over completed sessions; complementary trend-style introspection.
- `/agent-help` — list of all plugin commands.

## See Also

- `loomwright/skills/pr-postmortem/SKILL.md` — full protocol, 6-class definitions, flow-stage attribution, jq-built trend-line schema (the authority).
- `loomwright/scripts/pr-postmortem-gather.sh` — the read-only gather script this command runs.
