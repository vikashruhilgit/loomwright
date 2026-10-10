# Rules Baseline — the per-class findings/misses record `.agent/rules/` is measured against

> **This is a RECORD, not an experiment.** It exists so that "the rules worked" and "the rules
> were ignored" stop being indistinguishable — by writing down, *before* a harvested rule batch
> lands, what the findings corpus looked like. It is a single observational snapshot of one
> repo's own ledger with **no control arm**, **small N**, and labels that are mostly a model's
> post-hoc guess. Read §"What this record cannot tell you" before drawing any conclusion from a
> later row. Nothing here gates anything: rules stay advisory and subordinate to `CLAUDE.md`.

## How to re-derive every number below

```
git worktree add --detach /tmp/baseline-check 5293d06
cd /tmp/baseline-check
git rev-parse --short HEAD:.supervisor/postmortem/results.jsonl   # must print 952ff91
bash loomwright/scripts/measure-heal-signal.sh --distribution
```

**Why the commit and not the blob.** `952ff91` is a **blob** sha — it names the exact ledger bytes,
which is the right thing to pin and why it stays in this file, but it is not a commit-ish and can
never be an argument to `git worktree add` or `git checkout`. This recipe previously led with
`952ff91^{commit}`, which cannot resolve (*"expected commit type, but the object dereferences to
blob type"*) and silently fell through a `2>/dev/null` to a fallback — a first line that never once
ran, in the section whose whole point is that you should run it. The commit `5293d06` selects the
tree; line 3 then verifies you got the pinned ledger bytes.

**This recipe measures; it does not regenerate `HARVEST_DRYRUN_SAMPLE.md`.** A detached worktree has
a `.git` **file** rather than a directory, and `add-rule.sh` refuses to write a store it cannot
anchor there, so a harvest dry run in this worktree is not the run the sample records. Regenerate
that sample from a clean `git clone` at the sha it pins, never by hand and never from a worktree.

That is the whole instrument. It reads `.supervisor/postmortem/results.jsonl` and prints what
follows; it writes **nothing** — no artifact, no trend line, not even its `--out` directory — so
re-running it can never change what it measures. Every figure in this file came out of that
command, not out of a plan document; a reader who doubts a number should run it rather than
trust this file.

**Measure it from a CLEAN checkout at the pinned sha, not from your working tree.** This is not
pedantry — it is the correction that produced this paragraph. The row below was first written
from a working tree whose `.supervisor/postmortem/results.jsonl` carried uncommitted extra
records, so it reported **85** records against a ledger state no other reader could obtain: the
file is git-tracked and grows as PRs land, and every number here is a function of it. A row
measured against an unshared input is unfalsifiable, which is exactly what §"How to re-derive"
claims this file is not.

**Ledger pinned for the row below:** commit **`5293d06`**, at which
`.supervisor/postmortem/results.jsonl` is blob **`952ff91`** and holds **84 records**. Re-derive
either sha with `git rev-parse --short HEAD` and
`git rev-parse --short HEAD:.supervisor/postmortem/results.jsonl` from inside the worktree above;
if `wc -l` on that file is not 84, you are not measuring what this row measured and the numbers
are expected to differ.

## Baseline row — 2026-08-14 (pre-rules)

Measured on `vikashruhilgit/loomwright` immediately **before** the first harvested `.agent/rules/`
batch was proposed. At the time of measurement `.agent/rules/` held **one** rule, so this row is
the "conventions store is effectively empty" state.

- **Ledger state:** commit `5293d06`, blob `952ff91` (see the pin above — this row is not
  re-derivable without it)
- **Records:** 84 · **Findings:** 225 · **Self-heal misses:** 95
- **Ledger `.repo` values present** (named rather than filtered — the corpus is already own-repo
  only by a committed gate, so nothing is dropped here): `vikashruhilgit/ai-agent-manager` (42
  records), `vikashruhilgit/loomwright` (42 records). Both are this repo under its old and current
  slug; there are zero foreign records.

| class | findings | share of findings | misses | share of misses | miss-rate |
|---|--:|--:|--:|--:|--:|
| `convention_mismatch` | 107 | 48% | 60 | 63% | 56% |
| `quality_gap` | 46 | 20% | 17 | 18% | 37% |
| `execution_bug` | 36 | 16% | 11 | 12% | 31% |
| `drain_churn` | 26 | 12% | 6 | 6% | 23% |
| `missing_context` | 5 | 2% | 1 | 1% | 20% |
| `plan_gap` | 3 | 1% | 0 | 0% | 0% |
| `scope_too_large` | 2 | 1% | 0 | 0% | 0% |

**Label quality on this row:** **83 of 84** records (99%) carry `agent_generated_guess: true`.

**The one sentence this row is for:** `convention_mismatch` is the largest class in *both*
columns — 48% of all findings and 63% of all self-heal misses — which is why a conventions store
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
- **share of findings** = the class's findings ÷ 225. **share of misses** = the class's misses ÷
  95. **miss-rate** = the class's misses ÷ its own findings. The first two answer "how much of
  the corpus is this class?"; the third answers "how often does this class get past review?"
- Percentages are rounded to whole numbers by the instrument, so a column may not sum to exactly
  100%.

## What this record cannot tell you

Stated here, in the record itself, so no later reader can quote a row without the caveat:

1. **The labels are mostly guesses.** 83 of the 84 records carry `agent_generated_guess: true`:
   `self_heal_misses` and the class assignment are a model's post-hoc classification of review
   churn, not verified ground truth. A shift in a class's share may be a shift in how the
   classifier labels, not in what the repo produced.
2. **N is small, and the unit is not independent.** 84 records over one repo's history, with
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

**One exception, and it has already been used once — so it is written down rather than left to
judgement.** A row may be corrected when it does not reproduce from its own instrument at its own
pinned input; that is not a re-measurement, it is a repair of a transcription error, and refusing
it would preserve a number that is simply wrong. The baseline row above was corrected on
2026-08-15 for exactly that reason: it had been measured from a dirty working tree carrying
uncommitted ledger records (85 records / 226 findings / 84-of-85 labelled) and did not reproduce
from any committed state. The corrected row (84 / 225 / 83-of-84) is the same measurement taken
against the pinned sha. **The headline claims were unaffected** — `convention_mismatch` was 107
findings and 60 misses before and after; only denominators moved. The append-only rule stands for
everything else: a row that reproduces and that you dislike is not a candidate for this exception.
The structural fix is the pin itself, which makes the next such error detectable by a reader
instead of by a reviewer.

## Subsequent rows

### Row — 2026-10-10 (post-rules window)

**Read this first: the two rows were labelled by different channels, so their class shares are not
comparable.** 72 of the window's 73 records are `source: automate_drain` lines. The `/automate`
`learning-emit` helper writes those from drain counters, not from reading the review: one
`drain_churn` entry when the until-mergeable drain ran fix cycles, one `self_heal_churn` entry when
Phase 4.5 took heal rounds, and `self_heal_miss: true` only on a repeat check failure or unresolved
bot feedback (`loomwright/scripts/automate-helpers.d/learning.sh`, the categories block of its jq
program). The one remaining record has no `source` field: it is a `github_postmortem` line, the
shape `/pr-postmortem` writes. The baseline's 84 records were 46 `github_postmortem` + 10
`manual_postmortem` lines, whose findings a model classified as `convention_mismatch`,
`quality_gap` and so on, plus 28 `automate_drain` lines (the source of all 26 baseline
`drain_churn` findings). So `convention_mismatch` drops from 48% to 2% here mainly because the
window carries almost no classifier-labelled records. That says nothing about whether convention
findings went away, and the rules cannot be credited with it.

- **Ledger pin (the window's input):** commit `1df5d34` on `origin/loomwright-meta`, at which
  `.supervisor/postmortem/results.jsonl` is blob `b4e09cc` and holds 158 lines. The window is
  lines **86–158**. Line 85 is the last line of the ledger at `3f4bb2e`, the commit that landed
  the first harvested rule batch (2026-09-01T05:38:59Z), and the pin's first 85 lines are
  byte-identical to that copy (`cmp`, below), so the line range is exactly "records appended after
  the rules landed".
- **Instrument:** `measure-heal-signal.sh --distribution`, run from `main` at `4e0f255` (script
  blob `a4ffd40`; the baseline ran blob `9ac80e5`, changed by one commit since). The same copy
  re-run on the baseline's pinned ledger (`952ff91`) reproduces the baseline row exactly, so the
  instrument change does not move the baseline numbers.
- **Records:** 73 (baseline 84) · **distinct PRs:** 73 (baseline 70) · **Findings:** 87 (baseline
  225) · **Self-heal misses:** 2 (baseline 95). 9 of the 73 records carry no findings.
- **First / last PR of the window:** #170 (ledger line 86) and #455 (line 158). These are also the
  lowest and highest PR numbers in the window. Every record is `vikashruhilgit/loomwright`. Two
  records carry `number: 0`; their `pr_url` gives #177 and #434.
- **Merge dates:** `gh pr view <n> --json mergedAt` was checked for all 73 distinct PRs. 71 merged
  between 2026-09-02T05:59:57Z (#170) and 2026-10-10T11:37:57Z (#455), so **none merged before**
  `3f4bb2e`. Two were **closed unmerged**: #428 and #429, throwaway `s3-validation` PRs closed on
  2026-10-08. Each contributes one record with zero findings. They stay in the instrument's table
  and add to the record count only.
- **Coverage:** `gh pr list --state merged` finds 220 PRs merged in this repo over the same span.
  The ledger holds a record for 71 of them, which is roughly a third. Which PRs got a record
  depended on which runs emitted one, so the window is not a random sample of the period.

| class | findings | share of findings | misses | share of misses | miss-rate |
|---|--:|--:|--:|--:|--:|
| `drain_churn` | 54 (baseline 26) | 62% (12%) | 0 (6) | 0% (6%) | 0% (23%) |
| `self_heal_churn` | 31 (baseline 0) | 36% (0%) | 0 (0) | 0% (0%) | 0% (n/a) |
| `convention_mismatch` | 2 (baseline 107) | 2% (48%) | 2 (60) | 100% (63%) | 100% (56%) |
| `quality_gap` | 0 (baseline 46) | 0% (20%) | 0 (17) | 0% (18%) | n/a (37%) |
| `execution_bug` | 0 (baseline 36) | 0% (16%) | 0 (11) | 0% (12%) | n/a (31%) |
| `missing_context` | 0 (baseline 5) | 0% (2%) | 0 (1) | 0% (1%) | n/a (20%) |
| `plan_gap` | 0 (baseline 3) | 0% (1%) | 0 (0) | 0% (0%) | n/a (0%) |
| `scope_too_large` | 0 (baseline 2) | 0% (1%) | 0 (0) | 0% (0%) | n/a (0%) |

Each cell shows this row's value, then the baseline's in parentheses. A class absent from a row
reads 0 there. Miss-rate reads `n/a` where that row has no findings for the class, because 0 ÷ 0
has no value. The instrument prints only the three classes present in the window. The baseline
values are copied from the baseline table above.

**Label quality on this row:** **73 of 73** records (100%) carry `agent_generated_guess: true`.
This is less informative than the baseline's 83 of 84: `learning.sh` hard-codes the flag to `true`
on every `automate_drain` line, including lines whose class is a mechanical counter rather than a
guess. On this row the flag does not separate guessed labels from counted ones.

**Extra view, not the instrument's output: findings by record source.** This is a per-`source`
split of the same raw `categories[]` entries, done with `jq`. `measure-heal-signal.sh` does not
print it. It is here only to make the channel shift above visible.

| source | window records / findings | window classes | baseline records / findings |
|---|--:|---|--:|
| `automate_drain` | 72 / 85 | `drain_churn` 54, `self_heal_churn` 31 (0 misses) | 28 / 26 |
| no `source` (`github_postmortem`) | 1 / 2 | `convention_mismatch` 2 (both misses, PR #194) | 46 / 161 |
| `manual_postmortem` | 0 / 0 | — | 10 / 38 |

**Changes to the rules store since the baseline:** the baseline had one rule. `main` at `4e0f255`
has **three** (`.agent/rules/process.json` holds two and `documentation.json` holds one). All three
are `enforcement: advisory` with `check: null`. The two new rules came from the harvest in
`3f4bb2e` and are narrowly scoped. One applies to `CLAUDE.md` and `AGENT_GUIDELINES.md`; the other
applies to `CLAUDE.md` and `loomwright/scripts/*`. **No `applies_to` was widened.** The baseline
rule is still repo-wide (`applies_to: null`), and no rule JSON has changed since `3f4bb2e`. The two
later commits that touched `.agent/rules/`, `9ac669f` and `c0d8a30`, edited only its `README.md`.
The rules store lives on `main`, not on the ledger branch, so this count is read from `main`.

**What else plausibly moved the numbers, and what the rules can and cannot be credited with.** The
first confounder is the labelling-channel shift described at the top of this row. It alone makes
the class shares incomparable. The 2 misses against the baseline's 95 come from the same shift: an
`automate_drain` line marks a miss only on a repeat check failure or unresolved bot feedback, which
is a far narrower test than the classifier's post-hoc judgement. Several review-lane changes also
landed on `main` inside the window, and each is a candidate cause on its own:

- `fea2d7e` (2026-09-26) introduced the `self_heal_churn` class, so that class can only appear
  from the 2026-09-27 records on.
- `d281e2a` (2026-09-27) made Phase 4.5 an executing review lens.
- `8fb6424` (2026-09-29) had the code reviewer read the house rules itself.
- `d36e0d5` and `c0d8a30` (2026-09-29) added the rules gate.
- `ccaef30` (2026-09-23) added worker `deviations`.
- `812b83f` (2026-10-09) added the four-part worker self-review.
- `2e07bc8` (2026-10-03) moved the ledger to `loomwright-meta`.

Most of the 73 PRs could have had a harvested rule injected: 68 list at least one changed path that
a scoped rule routes to (in `read-rules.sh`, `*` crosses `/`). A path match only shows that the rule
could have been injected. It does not show that the rule was read. Every caveat in §"What this
record cannot tell you" still applies, guessed labels included. **No causal claim is made in either
direction.** A like-for-like comparison would need classifier-labelled records for the window, for
example `/pr-postmortem` run over the window's PRs, and this row does not have them.

**Why this row cannot use the recipe at the top of this file.** That recipe pins the ledger on a
`main` commit, but since `2e07bc8` (2026-10-03) `.supervisor/postmortem/results.jsonl` is no longer
tracked on `main`. It lives on `origin/loomwright-meta`. This row therefore uses a substitute, with
the instrument unchanged. The ledger is read from `origin/loomwright-meta` at the pinned commit and
blob. The window is cut out as a line range and written into a scratch git repo. That repo is
passed to the instrument with `--repo`. Nothing was read from the working tree's copy of the
ledger, which exists on disk untracked and is not the pinned input. To re-derive every number in
this row:

```
git fetch origin loomwright-meta main
git worktree add --detach /tmp/remeasure 4e0f255 && cd /tmp/remeasure          # the instrument's commit
git rev-parse --short 1df5d34:.supervisor/postmortem/results.jsonl            # must print b4e09cc
N=$(git show 3f4bb2e:.supervisor/postmortem/results.jsonl | wc -l | tr -d ' ') # 85
cmp <(git show 3f4bb2e:.supervisor/postmortem/results.jsonl) \
    <(git show 1df5d34:.supervisor/postmortem/results.jsonl | head -n "$N") && echo prefix-identical
W=$(mktemp -d); git -C "$W" init -q; mkdir -p "$W/.supervisor/postmortem"
git show 1df5d34:.supervisor/postmortem/results.jsonl | sed -n "$((N+1)),\$p" > "$W/.supervisor/postmortem/results.jsonl"
bash loomwright/scripts/measure-heal-signal.sh --distribution --repo "$W"
```

The distinct-PR count and the merge-date check (a `number: 0` record takes its number from
`pr_url`):

```
jq -r '[.repo, (if (.number//0)==0 then (.pr_url|capture("/pull/(?<n>[0-9]+)").n) else (.number|tostring) end)]|@tsv' \
  "$W/.supervisor/postmortem/results.jsonl" | sort -u > "$W/pairs.tsv"; wc -l < "$W/pairs.tsv"   # 73
while IFS=$'\t' read -r r n; do printf '%s\t%s\n' "$n" "$(gh pr view "$n" --repo "$r" --json mergedAt -q .mergedAt)"; done < "$W/pairs.tsv"
```

The supporting numbers (zero-finding records, the per-source view, rule reach, coverage):

```
L="$W/.supervisor/postmortem/results.jsonl"
jq -s '[.[]|select((.categories|length)==0)]|length' "$L"                                  # 9
jq -r '(.source//"github_postmortem") as $s | .categories[] | [$s,.class,(.self_heal_miss==true)]|@tsv' "$L" | sort | uniq -c
git show 5293d06:.supervisor/postmortem/results.jsonl | jq -r '[(.source//"github_postmortem"), (.categories|length)]|@tsv' \
  | awk '{r[$1]++; f[$1]+=$2} END {for (s in r) print s, r[s] " records", f[s] " findings"}'   # baseline column
jq -s '[.[]|select(any((.changed_paths//[])[]; .=="CLAUDE.md" or .=="AGENT_GUIDELINES.md" or startswith("loomwright/scripts/")))]|length' "$L"   # 68
gh pr list --repo vikashruhilgit/loomwright --state merged --limit 1000 \
  --search "merged:2026-09-01T05:38:59Z..2026-10-10T11:37:57Z" --json number -q 'length'   # 220
git diff --stat 3f4bb2e 4e0f255 -- '.agent/rules/*.json'                                   # empty: no rule JSON changed
```
