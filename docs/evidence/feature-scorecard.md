# Evidence — feature scorecard on real data, and where the `tmp.*` heal-signal rows came from

Real output from this repository, captured 2026-11-01 on branch `feature/feature-scorecard-2-dep` (base
`26eda74`, plus the registry and builder from subtask 1). Nothing below is hand-written except the prose,
the headings and the `~` that stands for the owner's home directory.

The data is the **primary checkout's** state dir, `~/Documents/work/AI/ai-agent-manager/.supervisor`, read
**read-only**. The wave's lane checkouts have no `heal-signal/`, `review-heal/` or `pin-mutations/`
records, so they cannot answer this. Nothing was written into the primary checkout:

- the scorecard reads it through `--state-dir` and writes nothing;
- `/insights` ran against a **copy** of the state dir, because `build-insights.sh` writes its dashboard
  under `<checkout>/.supervisor/insights/`.

A marker file made before the run was compared with `find <state dir> -newer <marker>` afterwards. It
listed one file, `automate/automate-2026-11-01-195532.fleet.log`. That is the log of this wave's own
fleet coordinator, which was still running. Neither command reads or writes it.

## 1. The scorecard (AC14)

### Command (run from the repo root)

```bash
date -u +%Y-%m-%dT%H:%M:%SZ          # 2026-11-01T17:00:09Z
bash loomwright/scripts/build-feature-scorecard.sh \
  --state-dir ~/Documents/work/AI/ai-agent-manager/.supervisor
```

### Output (verbatim, exit 0, empty stderr)

```text
# Feature scorecard (advisory, read-only — verdicts are suggestions; nothing is changed)

State dir: ~/Documents/work/AI/ai-agent-manager/.supervisor · window: all retained records (oldest record read: 2026-09-22T01:34:03Z) · min_sample: 5
Counts cover only the records still on disk (logs/ is age-swept by retention-sweep.sh). One record file = one run opportunity.

| feature | critical | runs available | ran | caught | catch rate | cost total | cost per catch | last fired | verdict |
|---|---|---|---|---|---|---|---|---|---|
| risk_classification | yes | 88 | 80 | 74 | 92% | unknown | unknown | 2026-11-01T08:19:13Z | keep |
| red_team_advisory | yes | 88 | 0 | unknown | n/a | proxy:3833132B | unknown | - | insufficient data |
| rubric_score | no | 88 | 7 | 0 | 0% | proxy:7327454B | n/a | 2026-10-10T19:42:30Z | review: costs without catching |
| contract_conformance | no | 88 | 6 | 2 | 33% | unknown | unknown | 2026-10-31T10:16:43Z | keep |
| ground_truth | no | 88 | 71 | 0 | 0% | unknown | n/a | 2026-11-01T08:19:13Z | review: costs without catching |
| benchmark_result | no | 88 | 45 | 0 | 0% | unknown | n/a | 2026-11-01T08:19:13Z | review: costs without catching |
| heal_dismissed | no | 88 | 84 | 3 | 3% | unknown | unknown | 2026-11-01T08:19:13Z | keep |
| fallback_review_ran | no | 5 | 3 | unknown | unknown | unknown | unknown | 2026-11-01T09:24:49Z | insufficient data |
| pin-mutations | no | 12 | 10 | 1 | 10% | unknown | unknown | 2026-10-29T05:58:01Z | keep |
| multi_voter_heal | no | 88 | 0 | 0 | n/a | unknown | n/a | - | review: never ran |
| read-orientation | no | - | - | - | - | - | - | - | no record |

## Needs an emitter
- read-orientation

## Unregistered (optional SUPERVISOR_RESULT fields in neither the registry nor not_features)
- none
```

(The `State dir:` line printed the absolute path. Here the home directory is written as `~`.)

### The same table inside `/insights` (AC3 on real data)

```bash
R="$(mktemp -d)/ai-agent-manager"; mkdir -p "$R"
git -C "$R" init -q && git -C "$R" remote add origin https://github.com/vikashruhilgit/loomwright.git
cp -Rp ~/Documents/work/AI/ai-agent-manager/.supervisor "$R/.supervisor"   # -p keeps the mtimes the builder dates records by
rm -rf "$R/.supervisor/insights"                                           # derived output only
(cd "$R" && bash <repo>/loomwright/scripts/build-insights.sh)              # exit 0; 106 run notes; ~41 s
```

The copy is named `ai-agent-manager` and has the same `origin`, so the dashboard's project identity
matches the primary's. Results:

- The dashboard's `## Feature scorecard` table has exactly one row per feature `id`. Each row has the
  verdict that `build-feature-scorecard.sh --json --state-dir "$R/.supervisor"` returns, and there are no
  extra rows. This was checked by comparing the sorted `(id, verdict)` pairs.
- That `--json` is identical to the `--json` from the primary state dir, except for `record_paths`, which
  name the state dir each one read.
- The dashboard's `critical` column prints the JSON booleans (`true` / `false`). The builder's markdown
  prints `yes` / `no`. The numbers and verdicts are the same.

### Heal-signal section on the same data (AC7 on real data)

```text
## Heal-signal catch-rate (MEASURE)
_Sourced from `.supervisor/heal-signal/results.jsonl`. Numbers withheld: the ledger is **stale**, so they would not describe this project now._

- **stale** — newest row is 79 day(s) old (limit 14) and names: tmp.b13ufHtALK (this project: ai-agent-manager, loomwright)
- **Refresh:** `bash "<plugin>/scripts/measure-heal-signal.sh"`
```

`<plugin>` replaces the absolute scripts directory that the dashboard resolves at run time. Before this
change, the section showed numbers from that ledger as if they were current.

## 2. Heal-signal `tmp.*` rows — root cause (AC11)

### What the ledger holds

The primary's `.supervisor/heal-signal/results.jsonl` ends with six rows, all with `n: 0` and
`recall_pct: null`:

| recorded_at (UTC) | repos |
|---|---|
| 2026-08-14T11:42:32Z | `tmp.zcvIGabSPp` |
| 2026-08-14T11:42:33Z | `tmp.1M8CKqXjV5` |
| 2026-08-14T11:42:33Z | `tmp.HAlx2nq4HN` |
| 2026-08-14T11:42:33Z | `tmp.gUAQZroVul` |
| 2026-08-14T11:42:34Z | `tmp.L5nsgKJnWb` |
| 2026-08-14T11:42:34Z | `tmp.b13ufHtALK` |

The newest full run also overwrote `_summary.json` and `labels.jsonl` in the same dir. Its
`labels_unjoined` is `["o/r#9", "o/r#10"]`. Those two PRs exist nowhere except one fixture: case (d)
of `loomwright/scripts/test-measure-heal-signal-distribution.sh`, which writes a ledger with
`"number":9,"agent_generated_guess":true` and `"number":10,"categories":[{"class":"plan_gap",…}]`. The rows
were recorded at 17:12 local time (+0530). Commit `e20c941`, which added that test file and
`--distribution`, was made ten minutes later, at 17:22 the same day.

### Writer and mechanism

- **Writer:** `loomwright/scripts/test-measure-heal-signal-distribution.sh`, run from inside the real
  checkout with `MHS_WRAPPER` pointing at a broken copy of `measure-heal-signal.sh`. The file's header
  says that variable "exists ONLY for mutation control".
- **Mechanism:** the wrapper sets the engine's `--self-repo` to the **current directory's** git root. The
  engine's default `--out` is `<self-repo>/.supervisor/heal-signal/`. The suite makes several calls of the
  form `--repo <mktemp fixture> --distribution` with no `--out`. A wrapper that drops `--distribution`
  turns each of those calls into a full measurement. That measurement appends a trend row naming the
  fixture's basename (`tmp.XXXXXXXXXX`, macOS `mktemp -d`) to the ledger of whatever checkout the suite
  was started from. At this point the suite fails, as a mutation control should, but the rows have
  already been written.

### Reproduced (before any fix)

In a scratch git repo used as the working directory, with a copy of the wrapper whose
`ARGS+=(--distribution)` line was removed (checked: differs from the original and parses):

```bash
cd <scratch git repo>
MHS_WRAPPER=<mutant>/measure-heal-signal.sh \
  bash loomwright/scripts/test-measure-heal-signal-distribution.sh   # RESULT: 21 passed, 14 failed
jq -c '{recorded_at,repos,n}' .supervisor/heal-signal/results.jsonl
# {"recorded_at":"2026-11-01T16:39:23Z","repos":["tmp.i7jl94LKiw"],"n":0}
# {"recorded_at":"2026-11-01T16:39:23Z","repos":["tmp.ZxDtNhCPsC"],"n":0}
# {"recorded_at":"2026-11-01T16:39:23Z","repos":["tmp.L5ZcVXTfJ2"],"n":0}
jq -c .labels_unjoined .supervisor/heal-signal/_summary.json      # ["o/r#9","o/r#10"]
```

One such run appends three rows: cases (a), (d)-empty and (d)-malformed. Case (b) passes its own `--out`.
The suite's last call leaves the same `labels_unjoined` as the real ledger. Six real rows fit **two**
such runs. That count is an inference; it was not logged.

This was not a one-off manual run, so code changed.

### Fix — the write is now impossible

`test-measure-heal-signal-distribution.sh` now changes directory into a scratch `git init` repo before its
first wrapper call. It also makes `MHS_WRAPPER` absolute first, so a relative override still works. Every
call, real or broken, now resolves its self-repo to that scratch dir. A broken wrapper can only write
there, and the scratch dir is deleted when the suite exits.

The wrapper and engine are unchanged. A real user run still defaults to the current repo's
`.supervisor/heal-signal/`, and `--no-ledger` / `--distribution` still write nothing.

### Regression test — red before, green after

Case 11 of `loomwright/scripts/test-measure-heal-signal.sh` repeats the incident. It:

1. builds the broken wrapper (removes `ARGS+=(--distribution)`; checks the result is non-empty, differs
   from the original and passes `bash -n`);
2. runs the whole distribution suite with it from a **sentinel** checkout;
3. asserts that the suite goes red (the mutation control still works) **and** that the sentinel has no
   `.supervisor/heal-signal/`.

Run in a scratch copy of the scripts where the only difference is the distribution suite:

```text
--- pre-fix suite (git show HEAD:loomwright/scripts/test-measure-heal-signal-distribution.sh)
  ok: the broken wrapper still turns the distribution suite red (mutation control is live, rc=1)
  FAIL: the broken-wrapper run wrote into the invoking checkout: {"schema_version": 1, "recorded_at": "2026-11-01T16:57:43Z", "repos": ["tmp.7tIeej2dHn"], "n": 0, …}
RESULT: 15 passed, 1 failed
--- fixed suite
  ok: the broken wrapper still turns the distribution suite red (mutation control is live, rc=1)
  ok: no heal-signal ledger was written into the invoking checkout
RESULT: 16 passed, 0 failed
```

### What was deliberately left alone

The six `tmp.*` rows are still in the primary's ledger, because that checkout is read-only for this
work. `/insights` now reports them as `stale` instead of showing them as numbers. To clear the readout,
run the printed refresh command from the primary checkout; the next row it appends is current and
names the project. Deleting the six rows by hand is the owner's call.
