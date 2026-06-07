# Eval Corpus — format spec

This directory is the **task corpus** for the System Twin **EVAL harness**
(`../run-eval.sh`). The eval harness is an **output-quality fitness function**: it scores plugin
output against a fixed set of tasks, each with an executable, deterministic acceptance check.

> **Eval ≠ benchmark.** The **eval** harness (`run-eval.sh` + this corpus) is a *fitness function over
> an output-quality corpus* — it measures whether produced outputs satisfy task acceptance checks.
> The **canary benchmark** (`run-benchmark.sh` + `benchmark-corpus/`) is the *hard-signal pipeline
> canary* — it validates `session_end` hard-signal fixtures and produces `selftest_pass_count`. They
> are deliberately separate in naming, directory, and purpose. Do not conflate the two.

---

## Task format

Each task is a **self-contained directory** under this corpus:

```
eval-corpus/
  <task-id>/
    spec.md      # what the task asks (human-readable)
    check.sh     # executable; exit 0 = pass, non-0 = fail; deterministic
```

- **`<task-id>`** — the directory name. Used verbatim as the task `id` in results. Tasks are
  discovered and scored in **sorted (deterministic) order** by id.
- **`spec.md`** — a human-readable description of what the task asks for. Not parsed by the runner;
  it documents intent for authors and reviewers.
- **`check.sh`** — the acceptance check. **Must be executable** (`chmod +x check.sh`). The runner
  invokes it with `cd <task-id>/ && bash check.sh`, so it may reference task-local files by relative
  path. **Exit 0 = pass, any non-zero exit = fail.** It MUST verify the outcome **deterministically**
  — the same inputs must always yield the same exit status (no wall-clock, network, or random
  dependence in the pass/fail decision).

A directory with **no `check.sh` at all is not a task** and is not counted. A directory whose
`check.sh` is **present but not executable** is counted as a **FAIL** (and the runner prints a stderr
warning) rather than silently dropped — this prevents a forgotten `chmod +x` from quietly shrinking
the denominator `N` and masking a regression.

---

## How `run-eval.sh` discovers and scores tasks

1. Resolves the corpus dir: `$EVAL_CORPUS_DIR` if set, else `<script-dir>/eval-corpus`.
2. Finds every immediate child directory containing a `check.sh`, in **sorted order**.
3. Runs each executable `check.sh` (`cd` into the task dir first). Exit 0 → `pass`; non-0 → `fail`.
   A failing check is a normal **fail tally**, never a script crash. A present-but-non-executable
   `check.sh` is counted as a `fail` (with a stderr warning), not silently skipped.
4. Tallies `M` passes out of `N` tasks and prints a per-task line plus a `Pass rate: M/N` line.

### Determinism invariant

Same corpus → identical `tasks_total`, `tasks_passed`, `pass_rate`, and `per_task`. The `commit` and
`date` fields are **contextual** and legitimately vary run to run — they are **not** part of the
determinism invariant. Task discovery uses `LC_ALL=C sort`, so `per_task` ordering is stable across
locales (not just filesystem enumeration order). Tasks are direct children of the corpus dir
(`find -mindepth 1 -maxdepth 1`), so sorting by full path is equivalent to sorting by `id` — the
`per_task` array is ordered by `id`.

### Portability of the seed tasks (maintainer-side)

The seed corpus tasks `doc-currency-green`, `version-consistent`, and `eval-selftest-green` are
**dogfooded against this development repo**: their `check.sh` resolves the repo root via
`git rev-parse --show-toplevel` and invokes repo-local scripts (`scripts/check-doc-currency.sh`,
`scripts/validate-version.sh`, `ai-agent-manager-plugin/scripts/test-run-eval.sh`). They are therefore
**maintainer-side checks** — they pass only when run inside this repo and would fail in a marketplace
install under an arbitrary user project. `fixture-unit-test` is the only fully self-contained,
location-independent task. Corpus *authors* are free to write either kind; the runner itself is
location-independent (it scores whatever `check.sh` files it finds).

### Fail-safe

If the corpus dir is missing **or** `jq` is unavailable, the runner emits an `EVAL_RESULT` line with
`status: "unverified"`, `tasks_total: 0`, `pass_rate: "0/0"`, `per_task: []`, and **exits 0**. An eval
that cannot run must never break its caller.

---

## The `EVAL_RESULT:` line

The runner emits exactly **one** machine-readable line (compact JSON, jq-built for injection safety):

```
EVAL_RESULT: {"schema_version":1,"tasks_total":N,"tasks_passed":M,"pass_rate":"M/N","per_task":[...],"commit":"...","date":"...","status":"ok"}
```

| Field            | Type   | Meaning |
|------------------|--------|---------|
| `schema_version` | int    | Always `1`. |
| `tasks_total`    | int    | `N` — number of discovered tasks (dirs with an executable `check.sh`). |
| `tasks_passed`   | int    | `M` — number whose `check.sh` exited 0. |
| `pass_rate`      | string | `"M/N"`. |
| `per_task`       | array  | `[{"id":"<task-id>","status":"pass"\|"fail"}, ...]`, sorted by `id`. |
| `commit`         | string | `git rev-parse --short HEAD`, or `"unknown"` outside a git repo. **Contextual.** |
| `date`           | string | ISO 8601 UTC (`YYYY-MM-DDThh:mm:ssZ`). **Contextual.** |
| `status`         | string | `"ok"` on a normal run; `"unverified"` on the fail-safe path. |

---

## Out of scope (M2b follow-ups)

The following are **not** part of this harness and are deferred to M2b:

- **No CI auto-run of the full agent loop** — `run-eval.sh` runs the corpus checks only; it does not
  drive the plugin's agent loop end-to-end in CI.
- **No Phase 4.5 ground-truth wiring** — the eval result is not yet consumed by the Supervisor's
  Phase 4.5 self-heal as a ground-truth signal.
