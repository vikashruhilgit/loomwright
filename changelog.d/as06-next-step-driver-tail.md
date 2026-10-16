<!-- bump: minor -->
`/automate` tail driver — `automate-next-step.sh` runs GATE, park and close-out from the run file
New `loomwright/scripts/automate-next-step.sh` (automate-speed/06) is the single reader and writer of a `/automate`
run file for the loop's tail. Given the run file and the model's drain report (`--result`), it runs every
deterministic tail step itself — the validation gate, safe mode's park-first park, `--auto-merge`'s
`automate-helpers.sh gate-eval` (still the only merge executor; the driver only calls it and hands it the six-key
ctx), the dismissed-findings decision step, the park writes with the merge watcher, notify and run-lock release,
SYNC's `closeout --no-trail` through the close-out leftover gate, CHECK OFF and the two termination exits — and
prints exactly one JSON instruction (`do`: `spawn` | `ask` | `park` | `done`, documented in
`docs/result-schemas/automate-run.md` §"next-step instruction"). A call with no `--result` re-prints the pending
instruction and writes nothing; under `--non-interactive` no question gate asks — each takes its named can't-ask
outcome. `test-automate-next-step.sh` drives every tail golden case through the driver from a per-case
`next-step.results` file to its existing `expected.md`, byte for byte, and gates idempotency, the can't-ask
branches, the merge-surface grep and the ctx shape with mutation controls.
