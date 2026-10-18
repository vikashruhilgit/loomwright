# Review-heal — Escalation cause

Read this file only when the drain ends `ESCALATED` (the driver's `escalate` step has already set the fields it describes); a drain that ends `READY` never reads it. `SKILL.md` keeps the heading below as a pointer, so every `§"Escalation cause"` citation still resolves.

### Escalation cause (automate-followups/31)

Every `ESCALATED` v2 exit also sets `escalation_cause` + `escalation_check`/`_run_id`/`_attempt`/`_sha` (values and meaning: `docs/result-schemas/review-heal-result.md`):

| ESCALATED site | `escalation_cause` |
|---|---|
| bound hit; §U2.5 wait elapsed; confirming pass red/unreadable/unsettled (on `pushed_sha`) | the classifier's fields |
| only human-judgment findings | `findings` |
| rules gate, round ledger, `ci_untrusted` (keeps its `termination_reason`), channel-unknown, fork, release re-fold refused (#512), required-check metadata unavailable | `other` |

`findings`/`other` set the four companions to `null`. The classifier is one fail-safe call, `scripts/automate-helpers.sh escalation-cause <pr_url> --sha <sha>`: it prints one `escalation_cause: <cause> check=… run_id=… attempt=… sha=…` line; copy each field as-is. The cause is informational — it never changes `decision`, and nothing here reruns a check (`gh run rerun` stays human), merges, pushes or approves.
