<!-- bump: minor -->
`/automate` next-step driver, part 2 — `automate-next-step.sh` owns RUN's and DRAIN's bookkeeping
`loomwright/scripts/automate-next-step.sh` (automate-speed/07) now runs every deterministic step around RUN and
DRAIN, so the model is told only to spawn `/autonomous --single-iteration --requirement <item>` and the owned
`/review-pr --until-mergeable --no-auto-postmortem` drain and to hand back their result blocks. `--start run`
suppresses `.auto_review` before the `/autonomous` spawn (a malformed `.supervisor/config.json` exits 2
`config_malformed` with nothing written) and the RUN report restores it before the owned-drain spawn, never at
DRAIN. The driver writes the session-id line, the PR through `current-set` before the `ran /autonomous` line (or the
pinned no-PR line), the verbatim supervisor-result sidecar with its `sidecar-check`, and runs the rate-limit park
check. The DRAIN report gets the pinned start and terminal drain lines (the fix-now re-drain's too), `owned_drain_*`,
the verbatim review-heal sidecar with its `sidecar-check` and `learning-emit`, then GATE. A drain with no terminal
block whose PR merged becomes `superseded_by_merge` and goes to the close-out (no sidecar, no learning line, no
GATE). A second owned-drain spawn in the same pass exits 2 `drain_already_owned`. New driver steps (`run`,
`run-result`, `run-record`, `rate-limit`, `drain`, `drain-result`, `superseded`, `awaiting-go`, `learning-emit`), the
`spawn` values `"/autonomous run"` and `"owned drain"`, the RUN and DRAIN report shapes and `done` `status: "stopped"`
are documented in `docs/result-schemas/automate-run.md` §"next-step instruction". `test-automate-next-step.sh` drives
eight more golden cases through the driver byte for byte (new `next-step.results` directives: `expect-exit:`, `gh:`,
`file:`, `sidecar:`, `out:`) and gates the restore order, the single drain, the malformed-config abort and the
superseded path with mutation controls.
