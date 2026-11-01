<!-- bump: minor -->
Phase 4.5 heal rounds can converge on what the last fix changed (heal_review_scope)
The Supervisor Phase 4.5 review-and-fix loop re-reviewed the whole PR on every heal round, so rounds kept finding new
nits in code no fix had touched and a dismissed finding could come back each round. A new `.supervisor/config.json`
key, `heal_review_scope`, resolved once at INIT (`skills/supervisor-config/SKILL.md` step 2.11), shapes rounds 2 and
later. `files` reviews only the files the previous round's fix commit(s) changed, each read whole, with the full PR
diff as read-only context (acceptance-criterion, pin-mutation, environment and still-standing earlier-round findings stay
reportable wherever they point), and drops a finding this run already dismissed when it comes back at the same or a lower
severity. A re-reported fixed finding is never dropped: it means the fix did not hold, so it reaches the fix task and
is counted as `repeat_of_fixed`. `shadow`, the default, reviews and fixes exactly as before and records what `files`
would have covered and dropped. `full` is the kill switch. Round 1 is the full PR diff in every mode, and the
reviewer prompt under `shadow` and `full` is byte-identical to the previous one. The new
`loomwright/scripts/heal-review-scope.sh` owns the mode, scope, fingerprint, record, suppress and `--shadow-report`
steps, and its header is the one authority for their value sets. It writes one record per round and per finding to
the gitignored `.supervisor/heal-rounds/<brief>.jsonl` with no finding prose, and `--shadow-report` is the read-only
evidence for promoting `files` to the default. A missing or failing helper falls back to the full review and never
stops the loop. `agents/code-reviewer.md` gains the reporting rule for the new HEAL RE-REVIEW SCOPE prompt line.
`test-heal-review-scope.sh` covers the helper, and `test-heal-review-scope-seam.sh` pins the two guarded prompt lines
against the frozen base prompt in `scripts/fixtures/phase45-reviewer-prompt-base.txt`. The `self-heal-advisory` skill
budget is raised for the new loop steps.
