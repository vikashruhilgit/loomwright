## EVAL_RESULT (System Twin eval harness)

Emitted by `scripts/run-eval.sh` — the System Twin **eval instrument** (M2a). It is a
deterministic runner/scorer that measures plugin *output quality* against a fixed corpus of tasks
under `scripts/eval-corpus/` (one self-contained dir per task, each carrying an executable
`check.sh` whose exit code is the per-task verdict). The script prints a human/grep per-task block
plus a `Pass rate: M/N` line, AND exactly ONE machine-readable line `EVAL_RESULT: {...}` (jq-built
for injection safety). The harness ALWAYS exits 0.

The **`pass_rate` (M/N) is the fitness-function signal** — the headline metric tracked
release-over-release. The runner is deterministic: the same corpus + same checks produce identical
`tasks_total` / `tasks_passed` / `pass_rate` / `per_task` every run. The **determinism invariant
covers those tallies/per_task only**; the contextual `commit` / `date` fields legitimately vary
per run and are explicitly NOT part of the invariant.

```json
EVAL_RESULT: {
  "schema_version": 1,
  "tasks_total": 4,
  "tasks_passed": 4,
  "pass_rate": "4/4",
  "per_task": [ {"id": "doc-currency-green", "status": "pass"}, ... ],
  "commit": "268a6be",
  "date": "2026-06-06T17:35:45Z",
  "status": "ok"
}
```

**Field contract (schema_version: 1):**
- `schema_version` — integer, required, always `1`.
- `tasks_total` — integer; count of corpus tasks discovered (dirs under the corpus carrying an
  executable `check.sh`). `0` in the fail-safe path.
- `tasks_passed` — integer; count whose `check.sh` exited `0`.
- `pass_rate` — string `"M/N"` (e.g. `"4/4"`). The **fitness-function signal trackable
  release-over-release**. `"0/0"` in the fail-safe path.
- `per_task` — array of `{id, status}` objects, one per discovered task, in deterministic sorted
  order. `id` is the task-dir basename; `status` is one of `pass | fail` (a non-zero `check.sh` is
  a normal `fail` tally, never a script crash). `[]` in the fail-safe path.
- `commit` — short commit SHA at run time, or `"unknown"` if `git` is unavailable. **Contextual —
  NOT part of the determinism invariant.**
- `date` — ISO 8601 UTC timestamp at run time, or `"unknown"`. **Contextual — NOT part of the
  determinism invariant.**
- `status` — one of:
  - `ok` — normal: the corpus ran and the tallies are real.
  - `unverified` — fail-safe: the corpus dir is missing OR `jq` is unavailable, so the eval could
    not run. Emitted with `tasks_total: 0`, `tasks_passed: 0`, `pass_rate: "0/0"`, `per_task: []`
    (mirroring `run-benchmark.sh`'s fail-safe — an eval that cannot run must never break its
    caller).

**Scope honesty (M2a vs M2b):** this is the eval **instrument** (M2a, shipped v14.17.0) — a fitness
function over an output-quality corpus. It is **DISTINCT from the canary benchmark**
(`BENCHMARK_JSON` / `scripts/run-benchmark.sh`), which validates the `session_end` hard-signal
pipeline and is named/stored separately on purpose ("eval" ≠ "benchmark"). The eval harness does
**NOT** auto-run the full Launch Pad→Supervisor agent loop in CI against the corpus, and does **NOT**
wire ground-truth execution into Supervisor Phase 4.5 — **both are explicit M2b follow-ups**
(deferred). See `scripts/run-eval.sh` (the runner/scorer) and `scripts/eval-corpus/` (the corpus +
per-task `check.sh` checks), and `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` §4 (M2) for milestone status.

---

