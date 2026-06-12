---
name: pr-postmortem
description: Inline, READ-ONLY post-hoc analysis protocol for `/pr-postmortem <pr-url>` — gathers an existing PR's review/churn signals via pr-postmortem-gather.sh, categorizes each review round into one of 6 root-cause classes, attributes it to a flow stage, prints a human-readable root-cause report, and appends one fail-safe POSTMORTEM_RESULT trend line to .supervisor/postmortem/results.jsonl. Use when implementing or invoking the `/pr-postmortem` command.
allowed-tools: [Read, Bash]
version: "1.3.0"
lastUpdated: "2026-06-13"
---

# PR Postmortem Skill

The **single source of truth** for the `/pr-postmortem <pr-url>` workflow. This is a **reference contract** skill (markdown prose, NOT executable code), in the same spirit as `skills/autonomous-loop/SKILL.md` and `skills/review-heal/SKILL.md`. The `/pr-postmortem` command (`commands/pr-postmortem.md`) is a thin inline shell that points here as its authority.

The goal: after an agent-generated PR has absorbed multiple rounds of post-PR review-and-fix, ask **"why did this PR need back-and-forth?"** and bucket each round into a reproducible root-cause class — so the churn becomes a measurable trend instead of anecdote. The accumulated trend file (`.supervisor/postmortem/results.jsonl`) is the **seed corpus for a future synthetic eval harness** (the deferred M2b part-2b headless-`claude` evaluator described in `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md`).

---

## Hard Invariants

1. **READ-ONLY on the analyzed repo.** The workflow runs `gh pr view` plus a fail-safe `gh api repos/{owner}/{repo}/issues/{n}/comments` fetch (both read-only) through the gather script and reasons inline. It NEVER writes to, branches, commits to, or comments on the analyzed PR or its repo.
2. **Inline on the main thread.** No sub-agents are spawned (no `Task`), no extra model/API calls beyond the main thread's own reasoning. Categorization is done by the main thread reading the gathered JSON.
3. **The ONLY write is the trend append** — exactly one JSONL line to `.supervisor/postmortem/results.jsonl` under the *current working* `.supervisor/`, never the analyzed repo. The append is **jq-built (injection-safe), fail-safe, and MUST NEVER crash the command.**
4. **Graceful on unavailable.** If the gather script returns `{"status":"unavailable",...}`, print one clear line and exit — no partial trend write, no stack trace.
5. **`${CLAUDE_PLUGIN_ROOT}` for the gather script.** Always invoke it as `${CLAUDE_PLUGIN_ROOT}/scripts/pr-postmortem-gather.sh` — the canonical Claude Code variable that resolves to the plugin install dir at runtime. Never use a repo-relative `ai-agent-manager-plugin/...` path; that only resolves for the maintainer (documented invariant in CLAUDE.md).

---

## The 6 Root-Cause Classes

Each review round is assigned **exactly ONE** class. Definitions are crisp so categorization is reproducible across runs:

| Class | Definition (assign when the round's evidence shows…) |
|---|---|
| `plan_gap` | The brief/plan itself was incomplete or wrong — a requirement, acceptance criterion, or edge case was never specified, so the implementation faithfully built the wrong/partial thing. The reviewer is pointing at *missing intent*, not a coding mistake. |
| `missing_context` | The implementation was reasonable given what the worker saw, but it lacked context that existed elsewhere in the codebase (an existing helper, a sibling module's pattern, a prior decision). Reviewer says "we already have X" / "this duplicates Y" / "see existing Z". |
| `convention_mismatch` | The code works but violates a project convention, style, naming, structure, or doc-currency rule (e.g. count claims, lint, formatting, import order, frontmatter keys). Reviewer is enforcing *how we do things here*, not correctness. |
| `execution_bug` | A genuine defect in the produced code — wrong logic, off-by-one, null/falsy coercion, a broken branch, an unhandled case, a typo that changes behavior. The intent and context were fine; the code is wrong. |
| `quality_gap` | Non-defect quality shortfalls: missing tests, missing error handling, weak validation parity, missing branch coverage, inadequate logging — the code is correct but under-hardened. (Distinct from `execution_bug`: nothing is *wrong*, something is *missing*.) |
| `scope_too_large` | The PR tried to do too much at once, making review hard and churn likely — the reviewer asks to split, descope, or the round exists mostly because the diff was sprawling. Size/`changed_files`/`additions` are the dominant signal. |

### Optional `self_heal_miss` flag (boolean, per round)

Set `self_heal_miss: true` when the round is something **Supervisor Phase 4.5 self-heal should have caught but didn't** — i.e. the finding falls in the repo-agnostic Self-Heal Miss-Class Checklist (`skills/quality-checklist/SKILL.md`): backend-mirrors-frontend validation parity, `||`/falsy coercion on numeric fields, positional args to options-object functions, missing branch coverage, count/cross-ref drift. These rounds are the highest-signal entries for hardening self-heal. Default `false` when unsure.

### Flow-stage attribution (per round)

Attribute each round to the stage of the agent flow where the root cause was introduced:

| Stage | Assign when… |
|---|---|
| `launch_pad` | Root cause is upstream planning — `plan_gap`, or a `scope_too_large` that a better-scoped brief would have prevented. |
| `worker` | Root cause is in implementation — `execution_bug`, `convention_mismatch`, `missing_context`, or a `quality_gap` a worker should have covered. |
| `self_heal` | The round is a `self_heal_miss` — Phase 4.5 had the integrated diff and should have caught it. |
| `unknowable` | Evidence is too thin to attribute confidently (e.g. an approval with no actionable body, or a CI-only signal with no comment). Prefer this over guessing. |

---

## Protocol (inline, in order)

### Step 1 — Parse input
Accept a PR URL (`https://github.com/OWNER/REPO/pull/N`) or the short form `OWNER/REPO#N`. Pass the raw argument straight to the gather script — input validation lives there (it emits `{"status":"unavailable","reason":"bad_input"}` on a malformed reference).

### Step 2 — Run the Subtask-1 gather script
```bash
GATHERED="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-postmortem-gather.sh" "<input>")"
```
The script emits exactly ONE JSON object on stdout and always exits 0. Two shapes:

- **Success** (NO `status` field): `{ repo, number, title, agent_generated_guess, additions, deletions, changed_files, commits:[{headline,is_review_fix}], review_rounds, review_rounds_source, review_comments:[{author,snippet}], ci_checks:[{name,state}] }`.
- **Unavailable**: `{"status":"unavailable","reason":"<slug>"}` (slugs: `jq_unavailable`, `gh_unavailable`, `bad_input`, `pr_inaccessible`, `normalize_failed`).

**`review_rounds` counts three signals** (MAX of the three): review-fix commit headlines (the narrow phrase set — whose `address(es)? review` alternative accepts an optional intervening "code" since v14.23.3, covering "address code review findings …" headlines the adjacency requirement missed on vendsy/hub#139 — plus the two explicit anchored forms `pr #N review` / `review #N` — word-bounded, so "preview #2" never matches), formal churn-review submissions, and **bot-authored issue-comment review rounds** — a comment whose author looks like a review bot (login `claude`, `github-actions*`, or any `*[bot]`) and whose body carries a review marker (a word-bounded "review" ANYWHERE in the body — widened in v14.23.2 from the heading-anchored form because HUB-shape bot comments open with `## Overview` and mention review only in running text; still word-bounded so "Deploy Preview" never matches), followed by at least one later push (comment `created_at` vs commit `committedDate`). The third signal covers repos whose review feedback arrives as CI-workflow comments (e.g. `claude[bot]` from a claude-review workflow) instead of GitHub review objects — the mode that previously reported `review_rounds: 0` despite real churn. `review_rounds_source` names the dominant signal (`fix_commits` | `formal_reviews` | `bot_comments` | `none`; ties resolve in that order). The issue-comments fetch is fail-safe and bounded to a single `?per_page=100` page: if it errors, the gather degrades to the two legacy signals, and hostile-typed comment fields degrade element-locally — never an unavailable emit, never a non-zero exit. Known bounded over-count: an all-clear closer ("recommend merge") followed by any later commit (housekeeping, version bump, rebase) books one phantom bot round — accepted noise for a trend-only signal (`review_rounds` is a MAX); a phrasing-based negative anchor on closers was considered and rejected as brittle.

Detect the unavailable shape:
```bash
if printf '%s' "$GATHERED" | jq -e 'has("status") and .status == "unavailable"' >/dev/null 2>&1; then
  reason="$(printf '%s' "$GATHERED" | jq -r '.reason // "unknown"')"
  echo "pr-postmortem: PR data unavailable ($reason) — nothing to analyze. No trend line written."
  exit 0
fi
```
This is Invariant 4: clear one-liner, graceful exit, NO partial trend write.

### Step 3 — Categorize each review round
For each review round / review-fix signal (driven by `review_rounds`, the `review_comments[]` bodies, and the `is_review_fix` commits), the main thread assigns:
- exactly one **class** from the 6 above,
- the optional **`self_heal_miss`** boolean,
- a **`flow_stage`** from the 4 above,
- a short **evidence snippet** (the review-comment snippet or review-fix commit headline that justifies the call).

Categorization heuristics (reproducible, evidence-first):
- Read the `review_comments[].snippet` text — the language usually maps directly to a class (e.g. "already have"/"duplicates" → `missing_context`; "split this PR"/"too big" → `scope_too_large`; "missing test"/"no error handling" → `quality_gap`; "this is wrong"/"breaks when" → `execution_bug`; "naming"/"style"/"count is stale" → `convention_mismatch`; "we never specced"/"requirement missing" → `plan_gap`).
- If `review_rounds` exceeds the number of usable comment snippets, attribute the residual rounds to the `is_review_fix` commit headlines; if even those are thin, classify the residual round as `flow_stage: unknowable` with the best-fit class and a noted low-confidence evidence snippet.
- **`review_comments[]` is a superset of the rounds — never derive the round count from it.** The gather script intentionally includes approval-bodied reviews (e.g. an `APPROVED` "LGTM after fix") AND review-shaped bot issue comments (including a final all-clear comment with no follow-up push, which is correctly not a round) in `review_comments[]` as context, but only `review_rounds` counts as rounds. Categorize exactly `review_rounds` rounds; treat surplus comment snippets (approvals, follow-up acknowledgements, post-final-push bot comments) as evidence/context only.
- When `review_rounds_source` is `bot_comments`, the per-round evidence usually lives in the bot-comment snippets (`review_comments[]` entries from a review-bot author — login `claude`, `github-actions*`, or any `*[bot]`) — read those first, then fall back to commit headlines.
- Apply the Self-Heal Miss-Class Checklist to set `self_heal_miss` (and thereby lean `flow_stage: self_heal`) where the evidence matches one of its classes.

### Step 4 — Print the categorized root-cause report
Human-readable, to stdout. Include:
- **PR identity:** `repo#number — title`, and `agent_generated_guess`.
- **Size:** `additions`/`deletions`/`changed_files`.
- **review_rounds** total.
- **Per-round lines:** `round N: class=<class>  self_heal_miss=<bool>  flow_stage=<stage>  evidence="<snippet>"`.
- **Root-cause narrative:** 2–4 sentences answering *why this PR needed back-and-forth* — the dominant class, whether self-heal should have caught it, and the stage most implicated.

### Step 5 — Append exactly ONE POSTMORTEM_RESULT trend line (fail-safe)
Append-only, jq-built, best-effort. Mirror the `record_result` pattern in `scripts/run-eval.sh` (mkdir -p, single `jq` build, `>>`, the whole block wrapped so any failure is swallowed and the command still exits 0). The report from Step 4 is already printed, so the append is genuinely best-effort.

```bash
# Best-effort trend append — MUST NEVER crash the command.
if command -v jq >/dev/null 2>&1; then
  {
    mkdir -p .supervisor/postmortem \
    && printf '%s' "$GATHERED" | jq -c \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
        --argjson categories "$CATEGORIES_JSON" \
        --argjson self_heal_misses "$SELF_HEAL_MISSES" \
        --argjson flow_stages "$FLOW_STAGES_JSON" \
        --arg summary "$SUMMARY" \
        --arg plugin_version "$(jq -r '.version // "unknown"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)" \
        '{
           schema_version: 1,
           ts: $ts,
           repo: .repo,
           number: .number,
           agent_generated_guess: .agent_generated_guess,
           review_rounds: .review_rounds,
           additions: .additions,
           deletions: .deletions,
           changed_files: .changed_files,
           categories: $categories,
           self_heal_misses: $self_heal_misses,
           flow_stages: $flow_stages,
           summary: $summary,
           plugin_version: $plugin_version
         }' >> .supervisor/postmortem/results.jsonl
  } 2>/dev/null || echo "pr-postmortem: trend append failed (best-effort) — report above is complete."
else
  echo "pr-postmortem: jq unavailable — skipping trend append (best-effort). Report above is complete."
fi
exit 0
```

Where the main thread builds, before the snippet:
- `CATEGORIES_JSON` — a JSON array of per-round objects `[{round, class, self_heal_miss, flow_stage, evidence}]`, itself jq-built (`jq -cn` with `--arg`/`--argjson`) so no untrusted PR text is string-interpolated.
- `SELF_HEAL_MISSES` — integer count of rounds with `self_heal_miss: true`.
- `FLOW_STAGES_JSON` — object tallying rounds per stage, e.g. `{"launch_pad":1,"worker":2,"self_heal":0,"unknowable":0}`.
- `SUMMARY` — the one-line root-cause narrative (plain string, passed via `--arg`).

**Injection safety:** every value flows through `--arg`/`--argjson`; the analyzed PR's repo/title/number come straight off the already-jq-built `$GATHERED` object via field access (`.repo`, `.number`, …). No PR text is ever concatenated into a JSON string.

---

## POSTMORTEM_RESULT trend-line schema (`schema_version: 1`)

One JSON object per line in `.supervisor/postmortem/results.jsonl`:

| Field | Type | Notes |
|---|---|---|
| `schema_version` | int | `1` |
| `ts` | string | UTC `YYYY-MM-DDTHH:MM:SSZ` |
| `repo` | string | `owner/repo` (from gather) |
| `number` | int | PR number (from gather) |
| `agent_generated_guess` | bool | best-effort agent-PR heuristic (from gather) |
| `review_rounds` | int | from gather |
| `additions` / `deletions` / `changed_files` | int | size (from gather) |
| `categories` | array | per-round `[{round, class, self_heal_miss, flow_stage, evidence}]` |
| `self_heal_misses` | int | count of rounds flagged `self_heal_miss` |
| `flow_stages` | object | tally per stage `{launch_pad, worker, self_heal, unknowable}` |
| `summary` | string | one-line root-cause narrative |
| `plugin_version` | string | **additive, optional** — plugin version at analysis time, read defensively from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` via jq (`"unknown"` fallback); absent in older lines, which remain valid — `schema_version` stays `1` |

This file is **append-only** and the **seed corpus for the deferred synthetic eval harness**. It is never read back by this skill (write-only trend), and lives under the current working `.supervisor/`, never the analyzed repo.

---

## Failure Modes (all fail-safe — command always exits 0)

| Situation | Behavior |
|---|---|
| Gather returns `unavailable` | Print one line with the reason; exit 0; NO trend write. |
| `jq` missing at append time | Print one best-effort warning; skip append; exit 0 (report already printed). |
| `mkdir`/`>>` fails (read-only fs, perms) | Swallowed by the wrapper; print one best-effort warning; exit 0. |
| Thin evidence for a round | Classify `flow_stage: unknowable` with a best-fit class and a low-confidence evidence note — never invent reviewer intent. |

## See Also

- `ai-agent-manager-plugin/scripts/pr-postmortem-gather.sh` — the read-only gather script whose single JSON object this protocol consumes.
- `ai-agent-manager-plugin/commands/pr-postmortem.md` — the thin inline command shell that points here.
- `ai-agent-manager-plugin/scripts/run-eval.sh` — the `record_result` append-only JSONL pattern this skill mirrors.
- `ai-agent-manager-plugin/skills/quality-checklist/SKILL.md` — the Self-Heal Miss-Class Checklist used to set `self_heal_miss`.
