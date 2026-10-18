<!-- bump: minor -->
`/review-pr --until-mergeable` next-step driver — `review-heal-next-step.sh` owns the drain loop's bookkeeping
`loomwright/scripts/review-heal-next-step.sh` (automate-speed/12) now runs every deterministic step of the review-heal
drain loop, so the model is handed one JSON instruction at a time: validate these findings, run this fix worker, or run
the earned fallback review, each answered with `--result`, and a `done` carrying the verbatim `REVIEW_HEAL_RESULT`.
The driver executes the round ledger (`drain-rounds.sh`), the all-channel read, required-check discovery, the
resumable scoped wait (exit 3 on `CONTINUE`), classification and the `EXTERNAL_TEXT` envelopes, the CI trust probe,
the fix floor, the rules gate, the `no_review_lens_posted` trigger (exactly one fallback review spawn per drain run;
a second request exits 2 `fallback_already_spawned`), the dismissed-findings marker comment, the READY / ESCALATED /
`termination_reason` decision, the sub-floor stop, anti-churn bookkeeping, `escalation_cause`, the notification, the
result block and the postmortem tail. It never merges and never force-pushes. The instruction shape is documented once
in `docs/result-schemas/review-heal-next-step.md`. `no_review_lens_posted` is read from each review-producing
check's OUTPUT, never its conclusion (a red review job that posted nothing earns the fallback): its file-anchored annotations
(file-less `.github` ones stay candidate text but never count as posted alone) plus the check run's `output.{title,summary,text}` through a new read-only
`drain-gh-read.sh check-run`. `rounds` counts every drain round actually run (a READY or ESCALATED final round
included, bumped once). The notification is desktop + webhook (`send-webhook.sh` gate types `review_heal_ready` /
`review_heal_escalated`) and surfaces open human threads and `REVIEW_REQUIRED`, never awaiting them. Eleven golden cases under `scripts/fixtures/review-heal-golden/` pin
the result block and ledger byte for byte through `test-review-heal-next-step.sh`, which also gates idempotent
re-prints, the fallback refusal, no-merge / no-force, the closed enums, report validation, the resumable wait, the
fail-closed branches and the prose rules that stay, with mutation controls. The drain's pseudocode and code blocks in
`skills/review-heal/SKILL.md` and the `--until-mergeable` mechanics in `commands/review-pr.md` are replaced by pointers
to the driver steps (the review-heal read set shrinks from 175663 to 150246 bytes), the driver is admitted to the
detached drain's pinned allowlist (`DRAIN_SCRIPTS` in `dispatch-pr-review.sh`), and the review-heal loop inventory
reaches `GAP review-heal: 0`: every row names a driver step or a test that fails when its text or behaviour is removed.
