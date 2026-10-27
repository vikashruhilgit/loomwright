## `session_end` JSONL hard-signal fields (System Twin)

> **Related additive session-log event (not a result-block schema):** `"event":"token_ledger"` lines may also appear in `.supervisor/logs/{session_id}.jsonl`, emitted fail-SAFE by `scripts/emit-token-ledger.sh` on SubagentStop. The log `session_id` prefers the active plugin id from `.supervisor/state.md` (so ledger lines join the same file as `session_end`); the Claude Code UUID is retained as additive `cc_session_id`. Schema, proxy rules, and hook coverage live in `docs/TELEMETRY.md` §Token ledger — not duplicated here. `/insights` surfaces an advisory `## Token economics` rollup from those lines.

> **Related additive session-log events (iq02 T04, script-written, not result-block schemas):** `"event":"pr_created"` (`ts`, `url`, `session_id`, optional `cc_session_id`) — appended fail-SAFE by `scripts/hook-dispatch-on-pr-create.sh` when a PR is created; it records the PR only and never changes the dispatch gate. `"event":"item_timing"` — ONE line per PR appended by `automate-trail.sh closeout` (silent, fail-SAFE, idempotent — a closeout re-run finds the PR's row already in the log and appends nothing; `/insights` also renders one row per `pr_url`) carrying the `scripts/phase-timing.sh --run` record for the closed-out item (`item.pick_to_park`, `owner_seconds`, `machine_seconds`, `owner_exact_share`, the supervisor spans) plus `ts` and `pr_url`. Every duration in it is derived from logged timestamps; a missing endpoint is `null`, never 0. **`session_end` gets no duration field:** `build-insights.sh` stops reading the never-written `duration_seconds` slot and instead derives its `## Wall-clock` section with `phase-timing.sh` (no model-written duration anywhere).

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

**A `session_ended_without_completion` record is a STRANDED close-out, not a failed run.** It
records that a session stopped without writing its own `session_end`; most are interactive or
driver sessions whose result was recorded under another id. `failed` is still its `status`
(state.md's status enum is closed), so every reader that counts outcomes must key on the `reason`:
`build-insights.sh` reports these as their own Stranded bucket, outside Failed, the completion-rate
denominator and the per-version table; `build-loop-evidence.sh` excludes them from the funnel and
counts them under Data quality; `/handoff` labels the active session as a stranded close-out;
`phase-timing.sh` already treats the record's timestamp as no completion endpoint. The close-out
also carries `plugin_version`, read from the plugin manifest like every other `session_end`, and
OMITTED (never `"unknown"`) when the manifest cannot be read.

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

### Knowledge-source tag vocabulary

The one list of `knowledge_sources_used` tags. The emitting prompts point here; nothing else
restates it. **Canonical form:** the base tag (before the first `:`) is lowercase with `_`, never
`-`; a `:<qualifier>` is kept verbatim (a `twin:<path>` path is case-sensitive). The set is open,
so a genuinely new source may add a tag, but it adds it here first.

| Tag | Source consulted |
|---|---|
| `project_memory` | `.supervisor/memory/PROJECT_MEMORY.md` |
| `lessons` / `lessons:<category>` | `.supervisor/memory/LESSONS.md` (whole store / one category) |
| `agent_memory:<agent>` | one agent's persistent memory store |
| `twin:<path>` | a System Twin contract, by subsystem id |
| `house_rules` / `house_rules:<scope>` | the committed `.agent/rules/` house rules |
| `prior_churn` | prior review churn on the touched paths, through `read-postmortem.sh` |
| `postmortem_ledger` | the `/pr-postmortem` ledger `.supervisor/postmortem/results.jsonl`, read whole |
| `brief_conformance` | Phase 4.5's brief-conformance check of the diff against the brief |
| `brain_context` | legacy (no live emitter since the graphify-tier retirement); past records stay valid |

**Normalized twice.** The emitter writes the canonical form. `build-insights.sh` also normalizes
every tag at READ time (base tag trimmed, lower-cased, `-` → `_`; qualifier verbatim; a tag repeated
within one run after normalizing counts once), so logs written before this list existed aggregate
into one row per source instead of one per spelling. Read-time normalization fixes spelling only: a
synonym such as `postmortem` or `system_twin` keeps its own row, because folding it into
`postmortem_ledger` / `twin:<path>` would claim a source the record does not name.
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

