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

Before anything else, read the governing protocol so the workflow runs the up-to-date version rather than a remembered shape. Use `${CLAUDE_PLUGIN_ROOT}` — the canonical Claude Code variable that resolves to the plugin install dir at runtime (works on both maintainer dev checkouts and marketplace installs). Never use `ai-agent-manager-plugin/...` here — that path only resolves for the plugin maintainer:

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

- `ai-agent-manager-plugin/skills/pr-postmortem/SKILL.md` — full protocol, 6-class definitions, flow-stage attribution, jq-built trend-line schema (the authority).
- `ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh` — the read-only gather script this command runs.
