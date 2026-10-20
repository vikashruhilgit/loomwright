# automate-speed/10 — coordinator-model A/B (Haiku 5.5 vs Sonnet 5.5)

**Decision: the default `coordinator_model` stays `session`.** Neither cheaper model reached 100% parity across all
runs: both scored 9/12. The three failing runs are the same case for both models, `non-interactive-escalated-park`
(runs 1–3), and the cause is the eval environment, not the model (see "The failing case" below). Under AC2's rule —
the cheapest model with 100% parity and 0 wrong questions across every run — no cheaper model qualifies, so the
driver ships `NS_CM_DEFAULT=session`. The `test-automate-next-step.sh` "absent key ⇒ default" pin reads that value
from the driver.

## What was run

- **Frozen commit:** `edd34d16474ee35b3ed7b416422a051dd54418ce` (`fix(evals): give the coordinator-model eval child a
  writable TMPDIR`). It is the commit that adds the suite in its measured form, on top of `7a6ca2f`, which added the
  suite, the setting and the valve. Every A/B figure below was measured at `edd34d1` with a clean tree.
- **CLI:** Claude Code 2.1.300, `claude plugin eval`. Graders are deterministic `regex` checks over the run's own
  `.eval/verdict.txt` (no LLM judge), so there is no judge cost.
- **Suite:** `loomwright/evals/coordinator-model/` (README there). It has four `ab` cases (spawn, interactive ask +
  park, non-interactive park, done) and one `mutation-control` case. Each case stages a golden fixture item into a
  scratch repo. The model plays the coordinator against the real driver.

Exact commands (from the repository root; `$S` is a `mktemp -d` scratch dir, never the repo):

```bash
for m in claude-haiku-5-5 claude-sonnet-5-5; do
  claude plugin eval ./loomwright --eval-dir evals/coordinator-model --tag ab --runs 3 --concurrency 2 \
    --model "$m" --scaffold --allow-tools Bash --ablation none --no-publish --trust-plugin --keep-temp \
    --output-dir "$S/$m" --report "$S/$m/report.html" --json "$S/$m-run1.json"
  bash loomwright/evals/coordinator-model/lib/summarize.sh "$m" "$S/$m-run1.json"
done
```

Both invocations exited 1, because the CLI exits non-zero when any case scores below its 1.0 threshold. The
results were kept out of the repo (`--output-dir`, `--report` and `--json` all under `$S`; `--no-publish`).

## Per-case results (3 runs per case per model)

Grader columns: `parity` means the run file equals `expected.md` byte for byte after leg G's normalisation. `no
wrong question` means no ask was made while no `ask` was pending. `no skipped` means every spawn / ask
instruction was answered. **Token source:** each eval child's own trace, from its `result` line's `usage`
(input / cache-creation / cache-read / output). The eval JSON carries cost and turns but no token counts.
`read-token-ledger.sh --per-item` cannot key these children: their transcripts live in the eval's sealed sandbox,
and the run file's `session_id` lines are the fixture's canned ones. **Cost** is the eval JSON's `costUsd` (list
price).

| claude-haiku-5-5 — case | run | score | parity | no wrong question | no skipped | WRONG_QUESTIONS | SKIPPED | calls | last do | turns | cost USD | tokens in / cache-create / cache-read / out |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| spawn-run-report | 1 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | none | 5 | 0.004627890000000001 | 10 / 16717 / 91999 / 727 |
| spawn-run-report | 2 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | none | 5 | 0.0045560900000000005 | 10 / 16587 / 91719 / 641 |
| spawn-run-report | 3 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | none | 5 | 0.00459797 | 10 / 16596 / 91727 / 721 |
| ask-interactive-decide-then-park | 1 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | park | 5 | 0.004638970000000001 | 10 / 17170 / 92597 / 556 |
| ask-interactive-decide-then-park | 2 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | park | 5 | 0.004611560000000001 | 10 / 17087 / 92316 / 540 |
| ask-interactive-decide-then-park | 3 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | park | 5 | 0.004616790000000001 | 10 / 17091 / 92309 / 549 |
| non-interactive-escalated-park | 1 | 0.6666666666666666 | FAIL | PASS | PASS | 0 | 0 | 1 | park | 3 | 0.0037977800000000006 | 6 / 15965 / 47918 / 250 |
| non-interactive-escalated-park | 2 | 0.6666666666666666 | FAIL | PASS | PASS | 0 | 0 | 1 | park | 3 | 0.00379796 | 6 / 15988 / 47926 / 241 |
| non-interactive-escalated-park | 3 | 0.6666666666666666 | FAIL | PASS | PASS | 0 | 0 | 1 | park | 3 | 0.00377386 | 6 / 15904 / 47796 / 229 |
| done-check-off | 1 | 1 | PASS | PASS | PASS | 0 | 0 | 1 | done | 3 | 0.0038086500000000007 | 6 / 15891 / 47885 / 302 |
| done-check-off | 2 | 1 | PASS | PASS | PASS | 0 | 0 | 1 | done | 3 | 0.0037638100000000007 | 6 / 15894 / 47891 / 211 |
| done-check-off | 3 | 1 | PASS | PASS | PASS | 0 | 0 | 1 | done | 3 | 0.0037598700000000002 | 6 / 15887 / 47887 / 206 |
| **total** | 12 runs | passed 9/12 | parity 9/12 | | | | | | | turns 48 | 0.050351200000000006 | |
| claude-sonnet-5-5 — case | run | score | parity | no wrong question | no skipped | WRONG_QUESTIONS | SKIPPED | calls | last do | turns | cost USD | tokens in / cache-create / cache-read / out |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| spawn-run-report | 1 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | none | 5 | 0.0755151 | 10 / 15700 / 88451 / 385 |
| spawn-run-report | 2 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | none | 5 | 0.07505500000000001 | 10 / 15656 / 88410 / 357 |
| spawn-run-report | 3 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | none | 5 | 0.0755206 | 10 / 15655 / 88406 / 404 |
| ask-interactive-decide-then-park | 1 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | park | 5 | 0.0776526 | 10 / 16229 / 89266 / 379 |
| ask-interactive-decide-then-park | 2 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | park | 5 | 0.07765170000000002 | 10 / 16231 / 89277 / 378 |
| ask-interactive-decide-then-park | 3 | 1 | PASS | PASS | PASS | 0 | 0 | 2 | park | 5 | 0.0768438 | 10 / 16161 / 89198 / 326 |
| non-interactive-escalated-park | 1 | 0.6666666666666666 | FAIL | PASS | PASS | 0 | 0 | 1 | park | 3 | 0.0673437 | 6 / 15216 / 46477 / 182 |
| non-interactive-escalated-park | 2 | 0.6666666666666666 | FAIL | PASS | PASS | 0 | 0 | 1 | park | 3 | 0.06689389999999999 | 6 / 15132 / 46339 / 172 |
| non-interactive-escalated-park | 3 | 0.6666666666666666 | FAIL | PASS | PASS | 0 | 0 | 1 | park | 3 | 0.0670623 | 6 / 15149 / 46343 / 182 |
| done-check-off | 1 | 1 | PASS | PASS | PASS | 0 | 0 | 1 | done | 3 | 0.066654 | 6 / 15122 / 46440 / 151 |
| done-check-off | 2 | 1 | PASS | PASS | PASS | 0 | 0 | 1 | done | 3 | 0.066247 | 6 / 15002 / 46170 / 161 |
| done-check-off | 3 | 1 | PASS | PASS | PASS | 0 | 0 | 1 | done | 3 | 0.0663642 | 6 / 15053 / 46302 / 151 |
| **total** | 12 runs | passed 9/12 | parity 9/12 | | | | | | | turns 48 | 0.8588039000000001 | |

| Model | runs | parity | wrong questions | skipped instructions | cost USD (12 runs) |
|---|---|---|---|---|---|
| `claude-haiku-5-5` | 12 | **9/12** (fails: `non-interactive-escalated-park` ×3) | **0** | **0** | 0.0504 |
| `claude-sonnet-5-5` | 12 | **9/12** (fails: `non-interactive-escalated-park` ×3) | **0** | **0** | 0.8588 |

On the three cases the environment did not break (`spawn-run-report`, `ask-interactive-decide-then-park`,
`done-check-off`), **both models scored 100% parity, 0 wrong questions and 0 skipped instructions on all 9 runs
each**, at about 1/17 of the cost for Haiku. That is a signal, not a qualification: AC2 is "across all runs", and
the full set was not clean.

## The failing case (named, per AC2)

`non-interactive-escalated-park` (golden case `gate-validation-gate-unrun-escalated`) failed parity in all 6 runs,
3 per model, with the identical 2-line diff:

```
< - escalation_cause: validation_unrun | check: V2 Running system | …
> - escalation_cause: validation_unrun | check: no temp dir | …
< - validation-gate: unrun — V2 Running system: …
> - validation-gate: unrun — no temp dir
```

Every one of the 6 runs issued the case's entry command exactly. Two runs appended a harmless `; echo exit=$?`.
Each made 1 call, ended at the expected `park`, and asked nothing. The difference comes from inside the driver:
`validation-gate`'s `mktemp -d` (`scripts/automate-lanes.d/readiness.sh`, the `no temp dir` fallback) is refused
inside the eval child's OS sandbox. The same case passes model-free (`lib/selftest.sh`), so the failure belongs to
the environment.

What was tried:
- The first A/B at `7a6ca2f` failed this case the same way, 9/12 for each model.
- `edd34d1` points the wrapper's `TMPDIR` at a directory inside the sandbox cwd, which is writable per the sandbox
  settings. `selftest.sh` now poisons `TMPDIR`, so the inherited-TMPDIR form of the defect fails CI.
- The re-run at `edd34d1` still failed this case.

The root cause inside the sandbox is **not established** (honest limit). The other cases' temp-file helpers succeed
in the same sandbox. The follow-up is to establish why `mktemp -d` is refused there. Possible fixes: make
`validation-gate` honour a writable temp root, or run the suite with a sandbox setting that allows it. After the
fix, re-run the A/B before any default change.

## Mutation control (AC5)

```bash
claude plugin eval ./loomwright --eval-dir evals/coordinator-model --tag mutation-control --runs 1 \
  --model claude-haiku-5-5 --scaffold --allow-tools Bash --ablation none --no-publish --trust-plugin \
  --keep-temp --output-dir "$S/mutation" --report "$S/mutation/report.html" --json "$S/mutation.json"
```

Exit 1: **the parity grader FAILED**, as required. The staged expectation carries one deliberately wrong
`## Progress` line. The coordinator itself drove the case correctly: 1 call, `park`, no wrong question, nothing
skipped.

| mutation — case | run | score | parity | no wrong question | no skipped | WRONG_QUESTIONS | SKIPPED | calls | last do | turns | cost USD | tokens in / cache-create / cache-read / out |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mutation-control-wrong-expected | 1 | 0.6666666666666666 | FAIL | PASS | PASS | 0 | 0 | 1 | park | 3 | 0.0037685600000000007 | 6 / 15893 / 47786 / 223 |
| **total** | 1 runs | passed 0/1 | parity 0/1 | | | | | | | turns 3 | 0.0037685600000000007 | |

Model-free, `bash loomwright/evals/coordinator-model/lib/selftest.sh` reports **PASS: 13 FAIL: 0**:
- a reference coordinator scores every `ab` case PASS;
- the mutation control scores PARITY: FAIL;
- the graders catch a wrong question, an unanswered ask or spawn, and a hand-edited run file.

It runs as leg E of `test-automate-next-step.sh`.

## Test results (AC6)

- `bash loomwright/scripts/test-automate-next-step.sh`: **PASS: 180 FAIL: 0**, against a baseline of 153/0 at
  `ee3d7ea`. The suite adds the CM legs, the E leg, the D-leg mirror checks and the M10a–n mutants. Each mutant
  turns its CM leg red.
- The eval suite's single passing run on the chosen model: **not available**. The chosen default is `session`,
  the session's own model, and the A/B measured only the two candidate ids. On both candidates, every run of the
  three environment-clean cases passed: 9/9 each.

## Applying the setting (follow-up)

The driver resolves and reports `coordinator_model` on every instruction. Nothing in this change launches a
coordinator with `--model`. If a later A/B qualifies a cheaper model, the follow-up is to wire the value into two
places:
- `automate-lanes.sh`'s lane spawn;
- the owner's own `/automate` launch.

## `token-economy/06` is superseded for the coordinator (AC7)

`token-economy/06-model-router-gate.md` proposed an escalate-on-failure valve: three FAILs in the last 20 switch
back to the stronger model, one-directionally. **For the coordinator, 06 is superseded: its valve is folded into
this setting.** The ledger is `.supervisor/automate/coordinator-model.jsonl`. Three refused coordinator reports in
the last 20 switch any configured cheaper model to `session`. The one `escalated` record holds until the owner
deletes the ledger. 06's routing of other task classes is untouched: judgment phases stay on the strong model,
owner decision D3.
