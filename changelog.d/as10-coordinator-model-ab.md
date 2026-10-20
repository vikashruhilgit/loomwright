<!-- bump: minor -->
The /automate coordinator's model is a measured setting with an escalate-on-failure valve (automate-speed/10)
`.supervisor/config.json` now takes a `coordinator_model` key (`session`, `claude-haiku-5-5` or `claude-sonnet-5-5`).
`automate-next-step.sh` resolves it and every instruction carries the result, the inline `--resume` `start_new` included.
An absent key resolves to the driver's default, which is set from the A/B measurement. An invalid value falls back to
`session` with one named stderr line and is never a refusal. A one-directional valve keeps a ledger,
`.supervisor/automate/coordinator-model.jsonl`, with one line per new coordinator `--result` report. Three refused
reports in the last 20 switch any cheaper model back to `session` and write one `escalated` record. That record holds
until the owner deletes the ledger. A refused report's ledger line is the one named exception to "exit 2 ⇒ nothing
written". The new `claude plugin eval` suite `loomwright/evals/coordinator-model/` stages golden fixture items into
scratch repos. The model plays the coordinator, and deterministic graders score run-file parity, wrong questions and
skipped instructions; a mutation-control case proves the parity grader fails. `docs/evidence/coordinator-model-ab.md`
records the Haiku 5.5 vs Sonnet 5.5 runs. Both scored 9/12 parity with 0 wrong questions. All three failures are one case,
broken by the eval sandbox's refused `mktemp -d`, so the default stays `session`. It also states that `token-economy/06`'s valve is
superseded for the coordinator. `test-automate-next-step.sh` gains the CM and E legs and the M10 mutants.
