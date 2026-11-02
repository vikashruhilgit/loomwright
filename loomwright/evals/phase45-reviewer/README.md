# phase45-reviewer — does the current reviewer catch its own recorded misses?

A `claude plugin eval` suite that replays recorded Supervisor Phase 4.5 reviewer misses against the current
`loomwright:code-reviewer`. Each case puts one merged PR's **pre-drain** diff in front of the reviewer, using the
exact round-1 spawn prompt Phase 4.5 sends. A deterministic grader then checks whether the reviewer flagged the
file a later fix changed, at or above a severity floor. Clean **controls** measure noise. A PR that changes the
reviewer prompt, the Phase 4.5 protocol or its model routing reports the before/after `caught` count from this
suite.

## The command

Run it from the repository root. It is model-backed and on-demand only, and spends your Claude credential (one
reviewer per case). Never run it from CI.

```bash
bash loomwright/evals/phase45-reviewer/lib/run.sh                 # every case
bash loomwright/evals/phase45-reviewer/lib/run.sh --model <model> # extra args go to `claude plugin eval`
```

`lib/run.sh` first checks that `claude plugin eval --help` exits 0, with `claude` found through `PATH`. If it
does not, the script prints `phase45-reviewer: missing tool: claude plugin eval` on stderr, exits non-zero and
prints no count. Otherwise it runs

```bash
claude plugin eval ./loomwright --eval-dir evals/phase45-reviewer --scaffold --allow-tools Bash --ablation none \
  --no-publish --trust-plugin --keep-temp --output-dir "$S/out" --report "$S/report.html" --json "$S/eval.json"
```

into a `mktemp -d` dir `$S`, then `lib/summarize.sh`. The report has one row per case (`CAUGHT`, `MISSED`,
`MISSED (unparseable)`, `MISSED (no reply)`, `UNSTAGEABLE`, `CLEAN` or `NOISE`, or `?` when a case has no kept
sandbox), followed by:

```
caught: X/Y
unstageable: <n>
no_reply: <n>
noise: <sum> BLOCKING/HIGH on <m> controls
model: … / wall_clock: … / turns: … / cost_usd: …
```

- **Y** counts every miss case except `UNSTAGEABLE` ones. A staged miss whose reviewer crashed, timed out or never
  replied stays in Y as `MISSED (no reply)`, and a `?` row stays in Y as not caught. A failed spawn therefore reads
  `caught: 0/<n>` with `no_reply: <n>`, never `0/0`.
- **m** counts the controls whose reply was graded (`CLEAN` or `NOISE`). Noise on a control is reported. It never
  fails anything on its own.
- The CLI exits 1 whenever a case scores below its threshold. An `UNSTAGEABLE` case has no reply, so it always
  does. `lib/run.sh` reports that exit and still summarises.

**Tag filter.** The suite holds only `miss` and `control` cases, so `lib/run.sh` passes no tag filter. To run a
subset, pass `--tag` through. `claude plugin eval --help` documents it as `--tag <tag...>  Filter cases by tag
(repeatable)`: it takes one or more values (`--tag control`, `--tag miss control`) and may also be repeated
(`--tag miss --tag control`). Because the option is variadic, put it after the target and before another `--flag`.
`lib/run.sh` already places your args after its own flags. The help does not say whether several tags match as
any-of or all-of. Each case here carries one tag, so only any-of would select anything.

`--keep-temp` leaves one sealed temp dir per run. To remove one, `chmod -R u+rwx` it first, then delete it. Do not
run git inside it.

## Layout

| Path | Owner | What it is |
|---|---|---|
| `case-template.yaml` | suite | the ONE prompt and grader every case uses |
| `<NN>-<kind>-pr<N>/case.yaml` | corpus builder | the template with only `name`, `description` and `tags` filled in |
| `<NN>-<kind>-pr<N>/case.env` | corpus builder | the staging inputs ONLY: `PR=`, `BASE_SHA=`, `HEAD_SHA=` (the pre-drain head) |
| `<NN>-<kind>-pr<N>/scaffold.sh` | corpus builder | one line: `exec bash "$(dirname "${BASH_SOURCE[0]}")/../lib/stage-case.sh" "$(dirname "${BASH_SOURCE[0]}")"` |
| `lib/stage-case.sh` | suite | the shared stager (below) |
| `lib/render-prompt.sh` | suite | renders the Phase 4.5 round-1 reviewer prompt from the plugin under test |
| `lib/grade.sh` | suite | `grade.sh <reply file> <case_id> <corpus tsv>`, deterministic, no LLM |
| `lib/summarize.sh` | suite | `summarize.sh <eval --json> <suite dir> [<corpus tsv>]`, the report |
| `lib/run.sh` | suite | the command |
| `lib/selftest.sh` | suite | the model-free check |

Case dirs, and the corpus table row for each one, are written only by
`loomwright/scripts/build-reviewer-replay-case.sh --pr <N> … --confirm`. The owner confirms each case.

**Template contract.** A case's `case.yaml` is `case-template.yaml` with three lines replaced: `name: CASE_ID`
(use the case dir name), the `CASE_DESCRIPTION` line, and `tags: [CASE_KIND]` (`[miss]` or `[control]`). Every
byte from `execution:` on stays identical to the template, and the selftest fails any case where it does not.

**The expectations live outside the plugin.** They are in the repo-root table
`docs/evidence/phase45-reviewer-corpus.tsv`, tab-separated with a header line:

```
case_id	pr	kind	expected_file	severity_floor
```

`kind` is `miss` or `control`. `severity_floor` is `BLOCKING`, `HIGH`, `MEDIUM` or `LOW`. A control leaves
`expected_file` and `severity_floor` empty.

## How a case runs

1. **Staging** (`lib/stage-case.sh`, run by the case's `scaffold.sh` in the eval sandbox's cwd). It finds the
   source repo from `BASH_SOURCE`, as `coordinator-model/lib/stage-golden.sh` does, and writes `.eval/case-id`,
   `.eval/base_sha` and `.eval/head_sha`. If either sha is not a commit of the source repo, it writes
   `.eval/unstageable` and stops with exit 0, and the case grades `UNSTAGEABLE`. Otherwise it renders the prompt
   to `.eval/review-prompt.md` and builds a scratch repo:
   - the `git archive` of `BASE_SHA` as the root commit on branch `replay`
   - `refs/remotes/origin/main` set to that commit
   - one commit with `git diff --binary BASE_SHA HEAD_SHA` applied

   The reviewer's `git diff "origin/main...HEAD"` therefore shows exactly the pre-drain diff. `.eval/` is in the
   scratch repo's `.git/info/exclude`, and nothing is written into the source repo.
2. **The prompt** (`lib/render-prompt.sh`). It is read in place from the plugin under test, at
   `skills/self-heal-advisory/SKILL.md`. The script takes the `prompt: "…"` argument of the one `Task(` whose
   agent-type line names `loomwright:code-reviewer` (the exact anchor is the script's `ANCHOR`), and drops every paragraph that says `include this
   line ONLY when`. Those are the prior-churn, house-rules, brief-conformance, deviations, pin-mutation and
   module-shape blocks, and all of their inputs are empty in a round-1 replay. It also unescapes `\"` and
   substitutes `{BASE_BRANCH}`→`main`, `{STACKED}`→`false` and `{feature_branch}`→`replay`. The script fails
   closed, naming the anchor, when the anchor is missing or duplicated or when a `{` placeholder remains. The
   selftest renders the live file, so an edit that breaks the shape turns CI red.
3. **The run** (the `case.yaml` prompt). On `.eval/unstageable`, the eval child replies `UNSTAGEABLE` and stops.
   Otherwise it spawns ONE agent through the `Agent` tool, of agent type
   `loomwright:loomwright:code-reviewer` (the double prefix; the single-prefix form errors), with the text of
   `.eval/review-prompt.md` as the agent's prompt. It writes the reply verbatim to `.eval/reviewer-reply.md`
   with a Bash heredoc, then stops. It does not grade. A case uses round 1 only and never runs a fix task.
4. **The eval's own grader** is the same for every case: `regex` `^CODE_REVIEW_RESULT:` over
   `.eval/reviewer-reply.md`. **Its pass/fail means "a reply was captured", never "caught".**
5. **Grading** happens after the run and outside the sandbox. `lib/summarize.sh` maps each kept sandbox to its
   case through `.eval/case-id`, opening the sealed kept dir with `chmod u+rwx`, and grades it with the grader in
   `PHASE45_GRADE` (default `lib/grade.sh`) against the case's corpus row. `lib/grade.sh` reads the LAST
   `CODE_REVIEW_RESULT` block through the plugin's own `scripts/result_block_parser.py`, the parser the Code
   Reviewer's result validator uses, so "parseable" means what the real Phase 4.5 consumer can read. A miss is
   `CAUGHT` when some issue has severity at or above the floor (BLOCKING > HIGH > MEDIUM > LOW) and `file` equal
   to the expected file. A control is `CLEAN` or `NOISE`, plus a `NOISE: <BLOCKING/HIGH count>` line.

## Model-free selftest

```bash
bash loomwright/evals/phase45-reviewer/lib/selftest.sh
```

It needs no model and no network, only bash, git, jq and python3. It covers:

- the grader on canned replies: hit, plain miss, wrong file, below the floor, unparseable, no reply, last block
  wins, a noisy control, and the mutation control (a wrong expected file against a hit reply must not be
  `CAUGHT`)
- the rendered live prompt
- the one-protocol check over every `case.yaml`
- staging into a scratch source repo: the exact diff, no expectation in the sandbox, the source untouched, and
  `UNSTAGEABLE` for a nonexistent sha
- `lib/summarize.sh` over fixture kept sandboxes
- `lib/run.sh` under a `PATH` stub that shadows `claude`

To run the grader checks through another grader, set `PHASE45_GRADE=<path>`. An always-`CAUGHT` mutant must
produce a line starting `FAIL: mutation-control`. The selftest runs as a leg of
`loomwright/scripts/test-build-reviewer-replay-case.sh`.

## Honest limits

- **Run-to-run variance.** Reviewer output differs between runs. Compare the same cases on both reviewers, and do
  not treat a one-case swing as a signal on its own.
- **The corpus comes from this repo only.** Cases are merged PRs of this public repo's `main`.
- **The eval's pass/fail is not the score.** It means a reply was captured. The score is `caught: X/Y` from
  `lib/summarize.sh`.
- **The expectation never enters the sandbox or the plugin root, but the source checkout is reachable.** The
  sandbox gets only the case id, the two shas and the rendered prompt. Both the archive and the replayed diff
  exclude `loomwright/evals/phase45-reviewer/` and `docs/evidence/phase45-reviewer-*`, because a newer `BASE_SHA`
  would otherwise carry the suite and its table. A replayed PR's own changes to those paths are not replayed.
  However, the reviewer could still reach the source checkout by absolute path, which holds the corpus table and
  the post-fix versions of the replayed files (the plugin under test is that checkout's `./loomwright`). Before
  counting a run, check each kept trace for a read of `phase45-reviewer-corpus.tsv` or `evals/phase45-reviewer/`.
  A run that read either is reported, not counted.
- **Round 1, with empty advisory inputs.** A real Phase 4.5 round can carry a brief's acceptance criteria, house
  rules, deviations, pin-mutation verdicts and module-shape facts. The replay omits all of them, so a miss that
  only those inputs would surface is not catchable here.
- **The sandbox is the repo at `BASE_SHA`.** That includes the tracked `CLAUDE.md` and the tracked project
  agent memory of that time, such as the code-reviewer's, so the reviewer sees the project context of the original run, not
  today's.
- **Reaching the agent is unverified.** No run has yet shown that the eval child's `Agent` tool can spawn the
  plugin agent `loomwright:loomwright:code-reviewer`. If it cannot, every staged miss case reads
  `MISSED (no reply)` and stays in the denominator (`caught: 0/<n>`, `no_reply: <n>`), which is visible and
  never inflates the score.
- **Block form.** The eval's `regex` grader matches only the YAML form `CODE_REVIEW_RESULT:` at line start.
  `lib/grade.sh` also parses the `## CODE_REVIEW_RESULT` bullet form, so a reply in that form still gets a real
  grade even though the eval's own grader fails it.
