# coordinator-model — which model can run the `/automate` coordinator? (automate-speed/10)

A `claude plugin eval` suite that runs the same fixture Queue items with the `/automate` coordinator on
different models and scores how faithfully each one drives `scripts/automate-next-step.sh`. The result sets the
driver's default `coordinator_model` (`docs/result-schemas/automate-run.md` §"next-step instruction",
`coordinator_model`): **the default is the cheapest model with 100% parity and 0 wrong questions across every
run; if no cheaper model qualifies it stays `session`.** The measurements and the decision live in
[`docs/evidence/coordinator-model-ab.md`](../../../docs/evidence/coordinator-model-ab.md).

## Cases

Each case stages ONE golden case of `scripts/fixtures/automate-golden/` (read in place, never copied into this
directory) into the eval sandbox, and the model plays the coordinator for that segment of the loop.

| Case dir | `name` | tag | Golden case staged | What the coordinator must do |
|---|---|---|---|---|
| `01-spawn-run-report` | `spawn-run-report` | `ab` | `run-config-suppress-restore` | `--start run` prints the `/autonomous run` **spawn**; answer it with the canned RUN report (`bin/spawn-phase`), then stop when the driver prints nothing (the fixture's `NEXT_STEP_UNTIL` seam) |
| `02-ask-interactive-decide-then-park` | `ask-interactive-decide-then-park` | `ab` | `dismissed-findings-decision-step` | report the READY drain; the AUT-DISMISS **ask** (interactive) is answered through `bin/ask-owner`; stop at the ready_for_release **park** |
| `03-non-interactive-escalated-park` | `non-interactive-escalated-park` | `ab` | `gate-validation-gate-unrun-escalated` | under `--non-interactive` the AUT-WAIVE gate never asks: the coordinator must not ask either, and stops at the `validation_unrun` escalated **park** |
| `04-done-check-off` | `done-check-off` | `ab` | `check-off-progress` | CHECK OFF prints `{"do":"done","status":"running"}`: the segment ends at **done** |
| `05-mutation-control-wrong-expected` | `mutation-control-wrong-expected` | `mutation-control` | `escalated-park` (expectation mutated) | the AC5 mutation control: the staged expectation carries ONE deliberately wrong `## Progress` line, so the parity grader must FAIL even for a perfect run |

## How a case runs

- `<case>/scaffold.sh` calls the ONE shared stager, `lib/stage-golden.sh <golden case>`, in the sandbox cwd. It
  builds the scratch repo the way `scripts/test-automate-next-step.sh`'s `new_scratch` does (git init on `main`,
  `input.md` as the run file, `tree/` with the `dot-<name>` mapping, `gh.stub` as the stub table). It also copies
  the plugin to `.eval/plugin`, leaving out fixtures, tests, docs and evals.
- `bin/automate-next-step.sh` is the driver as the model calls it: the real driver, with `--inline-phases`, the
  fixture's `env:` test seams for that call, a stub `gh`, and recorders for the merge watcher, the notify and the
  run lock. Its stdout, stderr and exit code pass through unchanged.
- `bin/spawn-phase` stands in for running a spawn's work and `bin/ask-owner` for the ask tool. Each prints the
  path of the next canned `--result` payload the fixture's `call:` lines carry. Each refuses when the driver's
  last instruction is not its kind; a refused `ask-owner` call is a **wrong question**.
- After every call and stand-in, `.eval/verdict.txt` is rewritten: `PARITY` (the run file equals `expected.md`
  byte for byte after leg G's normalisation — ISO timestamps ⇒ `<TS>`, the scratch root ⇒ `<ROOT>`), `SKIPPED`
  (spawn / ask instructions no later `--result` call answered), `WRONG_QUESTIONS`, `WRONG_SPAWNS`, `CALLS`,
  `LAST_DO`.
- Three deterministic `regex` graders read that file: `parity`, `no-wrong-question`, `no-skipped-instruction`.
  No LLM judge is involved.

`lib/selftest.sh` checks the suite without a model: a reference coordinator (the prompt's loop, done
mechanically) must score every `ab` case PASS and the mutation control FAIL, and the graders must catch a wrong
question, a skipped instruction and a hand-edited run file. It runs as leg E of
`scripts/test-automate-next-step.sh`.

## Running it

Run from the repository root. The target must be the **path** `./loomwright`: the bare name resolves to the
installed plugin, not this checkout. Keep every output in a scratch dir, never in the repo. `--no-publish` is
required, because publishing to claude.ai is outward-facing. `--keep-temp` is needed for the summary's counts
and tokens.

```bash
S="$(mktemp -d)"
for m in claude-haiku-5-5 claude-sonnet-5-5; do
  claude plugin eval ./loomwright --eval-dir evals/coordinator-model --tag ab --runs 3 --concurrency 2 \
    --model "$m" --scaffold --allow-tools Bash --ablation none --no-publish --trust-plugin --keep-temp \
    --output-dir "$S/$m" --report "$S/$m/report.html" --json "$S/$m-run1.json"
  bash loomwright/evals/coordinator-model/lib/summarize.sh "$m" "$S/$m-run1.json"
done
# the mutation control (AC5): must exit 1 with the parity grader FAILED
claude plugin eval ./loomwright --eval-dir evals/coordinator-model --tag mutation-control --runs 1 \
  --model claude-haiku-5-5 --scaffold --allow-tools Bash --ablation none --no-publish --trust-plugin \
  --keep-temp --output-dir "$S/mutation" --report "$S/mutation/report.html" --json "$S/mutation.json"
bash loomwright/evals/coordinator-model/lib/summarize.sh mutation "$S/mutation.json"
# model-free
bash loomwright/evals/coordinator-model/lib/selftest.sh
```

`--keep-temp` leaves one sealed `/private/tmp/e-*` directory per run. To remove them, `chmod -R u+rwx` each
directory first, then delete it. Do not run git inside them.

`--trust-plugin` skips the CLI's first-run trust prompt. Pass it only for this repository's own plugin, which
is what the suite evaluates. `--scaffold` runs the case scaffolds as you, so pass it only for suites you
authored.

## Honest limits

- **The segment is bounded by the eval.** `done` (any status) ends a case. In a real loop `done`/`running`
  goes on to `--start pick`. The prompt states the boundary, so a model that runs past it fails parity.
- **The headless eval child has no ask tool.** The host's ask tool is not among its tools even when allowed, so
  `bin/ask-owner` is the only question channel and a wrong question is counted there. A question asked in prose
  (the model stops and asks) is caught as an unanswered instruction (`SKIPPED`) and a parity failure, not as a
  wrong question.
- **The model can read `.eval/`.** That includes the expectation. A model that edits files instead of driving
  the loop fails parity unless it rewrites the run file exactly. The prompt forbids touching `.supervisor/` or
  `.eval/`.
- **Normalisation.** Only `<TS>` and `<ROOT>` are normalised here. The stager refuses a case whose expectation
  carries `<CASE>` or `<TMP>`, and any results directive beyond `env:` / `call:` / `expect:` / `gh:`.
- **The driver reports `coordinator_model`; it does not apply it.** Nothing in this suite or the driver
  launches a coordinator with `--model`. The evidence file names that follow-up.
