## `session_end` JSONL hard-signal fields (System Twin)

> **Related additive session-log event (not a result-block schema):** `"event":"token_ledger"` lines may also appear in `.supervisor/logs/{session_id}.jsonl`, emitted fail-SAFE by `scripts/emit-token-ledger.sh` on SubagentStop. The log `session_id` prefers the active plugin id from `.supervisor/state.md` (so ledger lines join the same file as `session_end`); the Claude Code UUID is retained as additive `cc_session_id`. Schema, proxy rules, and hook coverage live in `docs/TELEMETRY.md` §Token ledger — not duplicated here. `/insights` surfaces an advisory `## Token economics` rollup from those lines.

The System Twin hard signal is emitted not only as the nested `SUPERVISOR_RESULT.contract_conformance`
/ `.benchmark_result` objects (see SUPERVISOR_RESULT, above) but ALSO as **FLAT scalar fields on the
`session_end` event** in the per-session log `.supervisor/logs/{session}.jsonl`. This is what
`scripts/build-insights.sh` aggregates — it reads these via `select(.event=="session_end")`,
exactly like it already reads `rubric_score`. It does NOT parse the nested SUPERVISOR_RESULT objects.

```jsonl
{"event":"session_end", ...,
 "contract_conformance_status":"pass|advisory_violations|unverified|skipped",
 "contract_violations": 0,
 "benchmark_status":"pass|regressed|improved|unverified|skipped",
 "benchmark_metric":"<string>",
 "benchmark_value": <number|null>,
 "benchmark_delta": <number|null>,
 "ground_truth_status":"pass|advisory_failures|unverified|skipped",
 "ground_truth_checks_total": 0,
 "ground_truth_checks_passed": 0,
 "ground_truth_pass_rate":"<M/N>",
 "knowledge_sources_used":["project_memory","lessons:testing","agent_memory:code-reviewer","twin:scripts/build-insights.sh","brain_context"],
 "plugin_version":"14.24.0"}
```

> The session_end record carries both an `event` and a (legacy) `type` key with the same value
> `"session_end"`. **`event` is canonical going forward** — `build-insights.sh` filters on `.event`;
> the duplicate `type` is retained only for backward-compatibility with older logs. New consumers
> should read `.event`. **This applies to machine-written close-out records too:** the record
> `scripts/close-stranded-run.sh` appends on `SessionEnd` carries BOTH keys, deliberately — dropping
> the legacy `type` would make the close-out invisible to `build-insights.sh`'s older filter path.

**`reason` (additive, optional — added v15.49.0):** a short lowercase snake_case string explaining
WHY the session ended, present only when a machine writer had a specific reason to record. Known
values: `session_ended_without_completion` — written by `scripts/close-stranded-run.sh` (the
`SessionEnd` hook) when a session ends while `.supervisor/state.md` is still non-terminal and this
session owns the run's log; that record always pairs `reason` with `"status":"failed"`. Absent (the
common case — an ordinary agent-written `session_end`) means "no specific reason recorded" and is
NOT an error. Purely additive: no `schema_version` change, no reader is required to consume it, and
records with or without it remain valid. See `docs/TELEMETRY.md` §"Run ownership" for the ownership
rule that decides whether the close-out writes at all.

**Hard-signal field contract (the same data in two shapes):** the FLAT `session_end` fields above
and the nested `SUPERVISOR_RESULT.contract_conformance` / `.benchmark_result` objects carry **the
same hard-signal data in two shapes**. ST3 writes both; the field correspondence is:
- `contract_conformance_status` ⇔ `contract_conformance.status`
- `contract_violations` ⇔ `contract_conformance.violations`
- `benchmark_status` ⇔ `benchmark_result.status`
- `benchmark_metric` ⇔ `benchmark_result.metric`
- `benchmark_value` ⇔ `benchmark_result.value` (`null` when not measured)
- `benchmark_delta` ⇔ `benchmark_result.delta` (`null` when no baseline)
- `ground_truth_status` ⇔ `ground_truth.status` (System Twin / M2b slice 1a, added v14.19.0)
- `ground_truth_checks_total` ⇔ `ground_truth.checks_total`
- `ground_truth_checks_passed` ⇔ `ground_truth.checks_passed`
- `ground_truth_pass_rate` (string `"M/N"`) ⇔ the runner's `pass_rate`
- `knowledge_sources_used` (flat array, added v14.28.0) ⇔ `SUPERVISOR_RESULT.knowledge_sources_used` — the advisory, non-gating memory-usage telemetry array; absent ⇒ "none used"; the flat `session_end` array is the surface `build-insights.sh` reads — as of v14.33.0 it aggregates and surfaces the field in the `## Knowledge sources (memory APPLY)` dashboard section (runs-reporting-a-source count, top source tags, per-version usage). The nested SUPERVISOR_RESULT object is the same data in the other shape. Additive — no `schema_version` change.
- `heal_first_decision` (`PASS` | `FAIL` | `NEEDS_HUMAN` | `null`) ⇔ `SUPERVISOR_RESULT.heal_first_decision`, and `heal_new_findings` (integer | `null`) ⇔ `SUPERVISOR_RESULT.heal_new_findings` — the findings-per-item metric (iq02 IQ01): the Phase 4.5 loop's first iteration decision and the `category: new` findings summed over every iteration; both `null` when the loop did not run. Absent ⇒ not reported (older events). `build-insights.sh` turns them into the Summary's first-pass PASS rate and findings per item. Additive — no `schema_version` change.

`build-insights.sh` (ST4 / measure-path) reads the FLAT `session_end` fields — these field names
are a contract with ST3 (writer) and ST4 (aggregator); do not rename them. The flat fields are
additive to the `session_end` event; events without them remain valid (a reader treats absent
fields as "not reported this session"; the `ground_truth_*` fields, when absent, are treated as
`"skipped"`).

**`plugin_version` (additive, optional):** the `session_end` event also carries a `plugin_version`
string (e.g. `"14.24.0"`), read at emission time from
`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` via jq with an `"unknown"` fallback when the
manifest is unreadable. Purely additive — events without it remain valid, and `build-insights.sh`
groups them under `"unknown"` in its per-version insights section. No `schema_version` change
anywhere; never rename or restructure the existing flat fields above.

> **Illustrative `plugin_version` values are version-agnostic — do NOT bump them per-release.**
> The `"14.24.0"` shown in the `e.g.` above and in the sample `session_end` / `POSTMORTEM_RESULT`
> JSONL blocks elsewhere in this file (and the mirror block in `agents/supervisor.md`) illustrate the
> *format* only — the real value is read at runtime from `plugin.json` via jq, so these placeholders
> have no currency requirement and `check-doc-currency.sh` deliberately does not scan them. Bumping
> them every release is a drift-treadmill the gate cannot enforce (they just re-stale at the next
> version). Leave them frozen. Only genuine current-claims — the manifest `version`/headline, the
> `plugin.json (vX.Y.Z)` annotations — track the live version. (CLAUDE.md no longer carries a
> per-release banner: it points at `CHANGELOG.md` instead.) See CLAUDE.md
> §"Doc currency is CI-enforced".

> **ST4 aggregation status (M2b slice 1a):** `build-insights.sh` currently aggregates the
> `contract_*` / `benchmark_*` flat fields. The `ground_truth_*` flat fields are **written now**
> (forward-compatible) but their dashboard aggregation is a **deliberate follow-up** — slice 1a
> ships the write side; wiring `ground_truth_*` into `build-insights.sh` is left to a later slice so
> this change set does not touch the insights-owned files.

---

