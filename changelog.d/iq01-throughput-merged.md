<!-- bump: minor -->
Prevent findings at write time and make each review cycle cheaper (implementation-quality/02: iq01 + throughput 01–09 in one PR)
IQ01 — prevent findings at write time. A worker now runs a four-part self-review (checklist, adversarial repro, sweep, touched-file invariants) before hand-back and reports it as `self_review` on WORKER_RESULT, enforced by `validate-worker-result.py` rule 13. Launch Pad briefs carry a `## Touched-file invariants` section, checked by the new Plan Reviewer Criterion 18. The worker's `maxTurns` is raised with its measured justification, and its prompt budget is raised 9062 → 9949. A findings-per-item metric (`heal_first_decision`, `heal_new_findings`) lands on SUPERVISOR_RESULT and `session_end` and is shown by `/insights`.

T01 — the drain's sub-floor stop decision is a script. `drain-subfloor-decision.sh` returns `continue`, `READY sub_floor_converged` or `ESCALATED`, and review-heal calls it instead of evaluating pseudocode.

T02 — every fix-now prompt at the dismissed-findings decision shows a derived wall-clock cost estimate, read from the `dismissed-cost` estimator in `automate-dismissed.sh`.

T03 — the scoped check-wait stays under the 600 s foreground cap. `wait-for-checks.sh --call-max` resumes across calls against a persisted total deadline; without the flag its output is byte-identical and it writes no state. Its state directory has a retention-sweep row.

T04 — phase timing. `phase-timing.sh` derives per-phase wall-clock and machine-versus-owner time from local logs. `/insights` gains a Wall-clock section, and closeout appends one `item_timing` event. A new post-call hook leaf records the answered question, `pr_created` is logged on PR creation, the dismissed Progress line is timestamped, and each ci-local log carries the HEAD sha and branch.

T05 — a full `ci-local` run fails in seconds on a red cheap gate. A derived early phase runs every non-test ci.yml gate plus early-marked tests before the pool.

T06 — no serial tail. The three `serial` tests were made pool-safe and unmarked after ten green loaded-pool runs each.

T07 — fixed-sleep test races wait on the condition instead. `wait-lib.sh` gives self-tests clock-bounded condition waits; S6, N8, AA-F12 and the automate-trail races use it; `test-no-fixed-sleep-race.sh` ratchets fixed sleeps per file with a `# fixed-sleep-ok:` escape hatch.

T08 — GitHub CI shards the self-test suite over a 3-way matrix behind ONE aggregating `ci` job that fails closed. `run-self-tests.sh` gains `--shard K/N` and `--list`, balanced by a committed weights fixture.

T09 — a vendor-coupling BREACH now says what to do. Under each BREACH row the gate lists the added token-bearing lines (counted by the same awk counter), the ways out in order (reword, reuse the existing reference, move the code to an adapter-classed file, raise), and a ready-to-paste raise row. That row's placeholder reason still fails raise_check until it is replaced. With no base it says `base unavailable` and lists every token-bearing line. Strictness is unchanged, and the manifest's class layout is untouched (owner decision A). Three dismissed LOW items are folded in: the frontmatter summary label, the class list living only in the manifest, and integer raise rows with `-0` refused by both layers.
