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

A task directory **without an executable `check.sh` is not counted** (neither pass nor fail).

---

## How `run-eval.sh` discovers and scores tasks

1. Resolves the corpus dir: `$EVAL_CORPUS_DIR` if set, else `<script-dir>/eval-corpus`.
2. Finds every immediate child directory containing an **executable `check.sh`**, in **sorted order**.
3. Runs each `check.sh` (`cd` into the task dir first). Exit 0 → `pass`; non-0 → `fail`.
   A failing check is a normal **fail tally**, never a script crash.
4. Tallies `M` passes out of `N` tasks and prints a per-task line plus a `Pass rate: M/N` line.

### Determinism invariant

Same corpus → identical `tasks_total`, `tasks_passed`, `pass_rate`, and `per_task`. The `commit` and
`date` fields are **contextual** and legitimately vary run to run — they are **not** part of the
determinism invariant.

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
