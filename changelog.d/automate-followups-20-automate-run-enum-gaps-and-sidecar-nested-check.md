<!-- bump: patch -->
/automate records a drain superseded by a merge, and nested result-object drift is fixed at the writer and checked at write time
`owned_drain_result` gains `superseded_by_merge` for an owned drain that ended without a terminal REVIEW_HEAL_RESULT
because the owner merged the PR mid-drain (the #305 case, which trail PR #311 could only record as an off-enum `null`
and then as an omitted field). The engine writes it at DRAIN or at RECONCILE, skips GATE, closes the item out and
stops at `awaiting_go`; `gate-eval` condition 1 parks it if it ever arrives, and a new test leg pins that.
`sidecar-check` now applies its required/allowed key check to the nested SUPERVISOR_RESULT objects (`ground_truth`,
`contract_conformance`, `benchmark_result`, `risk_classification`, `heal_dismissed` and the findings lists) and the
REVIEW_HEAL_RESULT lists (`dismissed`, `checks_untrusted`, `sub_floor_fixed`), with the key sets written into the two
schema docs. The documented skip form `{checked: false, status: skipped|unverified}` is legal without its counts; a
`ground_truth` without `checked`, or carrying `pass_rate`, fails. The producer prose (the SUPERVISOR_RESULT template in
`agents/supervisor.md` and self-heal-advisory's "Hard-signal dual emission") now states the exact nested shapes: `checked`
is always present and `pass_rate` belongs only to the flat `session_end` field `ground_truth_pass_rate`. The `/automate`
per-item loop runs `sidecar-check` right after writing each result sidecar and appends a `fail` line to `## Progress`
(advisory, never parks).
