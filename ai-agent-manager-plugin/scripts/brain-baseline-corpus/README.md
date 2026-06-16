# Brain Baseline Eval Corpus

Version-controlled fixtures for the **Phase 0 baseline eval harness**
(`ai-agent-manager-plugin/scripts/brain-baseline-eval.sh`). See
`ai-agent-manager-plugin/docs/SPIKES/BRAIN_INTEGRATION_EVOLUTION.md` §"Phase 0 — Baseline eval
harness" for the full rationale.

These fixtures capture **current (grep-first) behavior** so that "graph-first helps" is provable,
not asserted. They are checked into git so runs are reproducible and the corpus is reviewable.

**Location:** this directory (`ai-agent-manager-plugin/scripts/brain-baseline-corpus/`, a sibling of
`eval-corpus/`) is the default corpus the harness resolves via `$SCRIPT_DIR/brain-baseline-corpus`.
It is deliberately **not** under `.supervisor/` — that path is gitignored, so a corpus there would be
neither checked in nor reviewable. Override the location with `BRAIN_BASELINE_CORPUS_DIR`. The
harness's *output* history (`.supervisor/eval/brain-baseline.jsonl`) is a separate runtime artifact and
correctly stays gitignored.

## What this corpus is NOT

- It is **not** the `eval-corpus/` consumed by `run-eval.sh` (that writes
  `.supervisor/eval/results.jsonl`, which `/insights` reads).
- The baseline harness writes a **separate** file, `.supervisor/eval/brain-baseline.jsonl`, and per
  the design doc's v1 rule **`/insights` deliberately ignores it** — it must never pollute the
  existing eval fitness-function trend.

## Corpus format

**One `.md` file per corpus item.** `README.md` is documentation and is skipped by the harness — it is
not a corpus item. The item id is the filename without the `.md` extension (e.g. `q1-what-calls.md`
→ id `q1-what-calls`).

Each fixture file should document, for a human running the spike:

1. **Question / task** — the structural question, implementation task, or review/QA task.
2. **Expected answer or rubric** — what a correct answer looks like (used for manual scoring).
3. **Target repo / graph** — which codebase + Graphify graph the question is asked against
   (e.g. `sports-management`).
4. **Mode** — `baseline` (grep-first) or `graph-first`. The harness stamps the run mode via
   `BRAIN_BASELINE_MODE`; the fixture just records which mode the question is intended to compare.

The design-doc corpus target is **5 structural questions + 3 implementation tasks + 2 review/QA
tasks** (10 items total).

## Manual scoring (v1 — no auto-grader)

The harness auto-captures nothing about correctness; the human running the spike supplies it per item
via environment variables, keyed by the **sanitized** item id (every non-alphanumeric char becomes
`_`). For item id `q1-what-calls`:

| Field | Env var | Default | Values |
|---|---|---|---|
| `correct` | `BRAIN_BASELINE_CORRECT_q1_what_calls_reservationCreate` | `false` | `1`/`true`/`yes` ⇒ true |
| `tool_calls` | `BRAIN_BASELINE_TOOLCALLS_q1_what_calls_reservationCreate` | `0` | integer |
| `missed_context` | `BRAIN_BASELINE_MISSED_q1_what_calls_reservationCreate` | `false` | `1`/`true`/`yes` ⇒ true |
| `note` | `BRAIN_BASELINE_NOTE_q1_what_calls_reservationCreate` | `""` | free-text one-liner |

Example:

```sh
BRAIN_BASELINE_MODE=baseline \
BRAIN_BASELINE_CORRECT_q1_what_calls_reservationCreate=true \
BRAIN_BASELINE_TOOLCALLS_q1_what_calls_reservationCreate=7 \
ai-agent-manager-plugin/scripts/brain-baseline-eval.sh
```

The harness always exits 0; un-scored items still produce well-formed records (neutral placeholders).

> **Status — seeded, NOT yet decision-grade (v1).** This corpus currently ships **2 of the planned 10
> items** (target: 5 structural + 3 implementation + 2 review/QA; see `docs/SPIKES/BRAIN_INTEGRATION_EVOLUTION.md`
> §"Phase 0"). The harness is complete, but the §Phase 0 "graph-first beats baseline" exit criterion
> cannot be evaluated until the corpus is populated — treat the current numbers as a smoke test of the
> instrument, not a baseline measurement. Populating the remaining 8 items is a tracked follow-up.

## Output record schema

One JSON object per corpus item, appended to `.supervisor/eval/brain-baseline.jsonl`:

```json
{"id":"q1-what-calls-reservationCreate","mode":"baseline","correct":false,"tool_calls":0,"missed_context":false,"note":"","recorded_at":"2026-06-16T00:00:00Z"}
```
