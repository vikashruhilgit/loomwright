# Rules Baseline — the per-class findings/misses record `.agent/rules/` is measured against

> **This is a RECORD, not an experiment.** It exists so that "the rules worked" and "the rules
> were ignored" stop being indistinguishable — by writing down, *before* a harvested rule batch
> lands, what the findings corpus looked like. It is a single observational snapshot of one
> repo's own ledger with **no control arm**, **small N**, and labels that are mostly a model's
> post-hoc guess. Read §"What this record cannot tell you" before drawing any conclusion from a
> later row. Nothing here gates anything: rules stay advisory and subordinate to `CLAUDE.md`.

## How to re-derive every number below

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/measure-heal-signal.sh" --distribution
```

That is the whole instrument. It reads `.supervisor/postmortem/results.jsonl` and prints what
follows; it writes **nothing** — no artifact, no trend line, not even its `--out` directory — so
re-running it can never change what it measures. Every figure in this file came out of that
command, not out of a plan document; a reader who doubts a number should run it rather than
trust this file.

## Baseline row — 2026-08-14 (pre-rules)

Measured on `vikashruhilgit/loomwright` immediately **before** the first harvested `.agent/rules/`
batch was proposed. At the time of measurement `.agent/rules/` held **one** rule, so this row is
the "conventions store is effectively empty" state.

- **Records:** 85 · **Findings:** 226 · **Self-heal misses:** 95
- **Ledger `.repo` values present** (named rather than filtered — the corpus is already own-repo
  only by a committed gate, so nothing is dropped here): `vikashruhilgit/loomwright` (43 records),
  `vikashruhilgit/ai-agent-manager` (42 records). Both are this repo under its old and current
  slug; there are zero foreign records.

| class | findings | share of findings | misses | share of misses | miss-rate |
|---|--:|--:|--:|--:|--:|
| `convention_mismatch` | 107 | 47% | 60 | 63% | 56% |
| `quality_gap` | 46 | 20% | 17 | 18% | 37% |
| `execution_bug` | 36 | 16% | 11 | 12% | 31% |
| `drain_churn` | 27 | 12% | 6 | 6% | 22% |
| `missing_context` | 5 | 2% | 1 | 1% | 20% |
| `plan_gap` | 3 | 1% | 0 | 0% | 0% |
| `scope_too_large` | 2 | 1% | 0 | 0% | 0% |

**Label quality on this row:** **84 of 85** records (99%) carry `agent_generated_guess: true`.

**The one sentence this row is for:** `convention_mismatch` is the largest class in *both*
columns — 47% of all findings and 63% of all self-heal misses — which is why a conventions store
is the thing being invested in. It is also the class with the highest miss-rate of any
well-populated class (56% of its findings were missed by self-heal), i.e. the class review is
worst at catching, not merely the most common.

### Reading notes (what the columns are, exactly)

- A **finding** is one `categories[]` entry of one ledger record. Counts are over **raw records**
  — no per-PR dedup and no join — because the class distribution is a property of the findings
  corpus, not of the PR set. (This is deliberately a *different* view from the same script's
  confusion matrix, which dedups per PR because it is answering a per-PR question.)
- A **miss** is a finding whose `self_heal_miss` is exactly `true`. Absent and `null` are not
  misses, so records predating the field cannot inflate the miss column.
- **share of findings** = the class's findings ÷ 226. **share of misses** = the class's misses ÷
  95. **miss-rate** = the class's misses ÷ its own findings. The first two answer "how much of
  the corpus is this class?"; the third answers "how often does this class get past review?"
- Percentages are rounded to whole numbers by the instrument, so a column may not sum to exactly
  100%.

## What this record cannot tell you

Stated here, in the record itself, so no later reader can quote a row without the caveat:

1. **The labels are mostly guesses.** 84 of the 85 records carry `agent_generated_guess: true`:
   `self_heal_misses` and the class assignment are a model's post-hoc classification of review
   churn, not verified ground truth. A shift in a class's share may be a shift in how the
   classifier labels, not in what the repo produced.
2. **N is small, and the unit is not independent.** 85 records over one repo's history, with
   findings clustered inside PRs — a handful of unusually churny PRs move a class's share on
   their own. Treat differences of a few points as noise.
3. **There is no control arm.** Nothing about this design isolates the effect of rules. The repo
   keeps changing for every other reason at the same time: agent prompts, gates, reviewers,
   what is being built, who is reviewing. There is no parallel repo running without rules.
4. **Therefore: a rising `convention_mismatch` share after rules land is NOT proof the rules
   failed.** It is a signal to **investigate whether the rules are being injected and read at
   all** — check that `read-rules.sh` is producing non-empty output at the DO-side seam, that
   the relevant rule's `applies_to` actually matches the changed paths, and that the finding
   would have been prevented by a rule that exists rather than one nobody wrote. Only after
   those are ruled out is "the rules did not help" even a candidate explanation. The symmetric
   warning applies to a *falling* share: it is not proof they worked.
5. **This is a record, not a benchmark.** If a controlled comparison is ever wanted, it needs a
   design this file does not have (a holdout arm, human-verified labels, a pre-registered
   metric). Nothing here should be cited as evidence of effect size.

## Re-measurement instruction

The comparison this file exists to host is a **later row appended below**, never an edit to the
baseline row above.

1. Wait until at least **N = 20 further PRs** have landed with the rules store populated (a
   number chosen so a class's share is not dominated by two or three PRs; it is a judgement, not
   a power calculation).
2. Re-run `measure-heal-signal.sh --distribution`.
3. **Append** a new dated row in the section below — same table shape, same label-quality line,
   plus one line naming what changed in the store since the previous row (how many rules,
   whether any `applies_to` was widened) and one line naming anything else that plausibly moved
   the numbers.
4. Do **not** rewrite the baseline row, and do not delete a row that came out unfavourably. The
   value of this file is entirely in it being append-only.

## Subsequent rows

_None yet — the baseline above is the only measurement. The first comparison row is due after
the re-measurement instruction's N is reached, and is an operator step **after** the rules PR
merges; a PR cannot measure its own effect from inside itself._
