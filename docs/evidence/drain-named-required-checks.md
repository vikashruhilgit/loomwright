# Evidence: the drain honours a named required-checks set

Change: `.supervisor/config.json` `required_checks` and `--required-checks name:<a>[,<b>…]` for the
`/review-pr --until-mergeable` drain (GitHub issue #805). Recorded 2026-11-13 on macOS (Darwin 25.6.0) by the
Supervisor's docs worker (Subtask 3), on branch `feature/drain-named-required-checks-3-dep` over base `40b3f49`.

## Validation 2 — a live drain with no readable required-check list

Run 2026-11-13 by the owner's `/automate` coordinator session, at the owner's direction, against PR head
`c99d19e` of this branch. The drain ran headless under `dispatch-pr-review.sh`'s own pinned regime
(`claude -p --permission-mode dontAsk --allowedTools <the dispatcher's allowlist> --agent
loomwright:review-pr-runner`, review-only because the ambient mode resolved permissive), with one addition:
`--plugin-dir <this checkout>/loomwright`, so the drain ran this branch's scripts, not the installed plugin.
Owner and repo names are redacted to `<owner>` / `<sandbox>` / `<private-a>` / `<private-b>`.

**Deviation from the brief's step 1, stated plainly.** The two drains ran on a PUBLIC sandbox repo whose PR
targets an UNPROTECTED base branch (`v2-base`), not on a private GitHub-Free repo: none of the owner's private
repos had an open PR. Both routes reach the same no-list branch of `required_read_no_list`; the private-Free
route (GitHub's paid-plan 403 on both reads) was checked live and read-only on two real private repos (part A),
and the end-to-end drain on the unprotected-404 route (parts B and C). The one thing not exercised end to end is
a full drain whose no-list read was the 403 rather than the 404.

### A — the issue's case read live on private GitHub-Free repos (read-only)

```
$ gh api repos/<owner>/<private-a>/branches/main/protection
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.", ... "status":"403"}
$ gh api repos/<owner>/<private-a>/rules/branches/main
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.", ... "status":"403"}
# <private-b>: the same two 403 bodies

$ out=$(bash loomwright/scripts/drain-gh-read.sh required-checks <owner>/<private-a> main 2>&1); echo "rc=$?"
rc=1
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.", ...
 "documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-status-checks-protection","status":"403"}
$ source loomwright/scripts/required-checks-named.sh; required_read_no_list "$out"; echo $?
0          # no list: a named set may stand in
```

This settles the brief's open question on the issue's exact case (classic paid-plan 403, rulesets paid-plan
403): on c99d19e it lands in the no-list branch, so a configured `required_checks` set is used.

### B — run 1: `"required_checks": ["ci"]` ⇒ READY

Sandbox PR: base `v2-base` (unprotected: `drain-gh-read.sh required-checks` exits 1 with
`{"message":"Branch not protected",...,"status":"404"}`, `required_read_no_list` → 0). Checks on head
`c68b950`: `ci` SUCCESS, `deploy-integration` FAILURE (a job that always `exit 1`s, standing in for a
deployment integration red on the author's permissions).

```
REVIEW_HEAL_RESULT:
  schema_version: 2
  decision: READY
  iterations: 1
  fix_cycles: 0
  checks_waited: [ci]
  termination_reason: converged
  findings_dismissed: 1      # LOW, below_fix_floor: the always-red workflow must not reach main

$ jq -c '{required_mode, required_names, decision, termination_reason}' .supervisor/review-heal/<pr_hash>.next-step.json
{"required_mode":"named","required_names":["ci"],"decision":"READY","termination_reason":"converged"}
```

The red `deploy-integration` check did not block READY.

### C — run 2: `"required_checks": ["cix"]` (typo) ⇒ ESCALATED `required_check_absent`

Same PR and head, `--check-wait-timeout 180`.

```
REVIEW_HEAL_RESULT:
  schema_version: 2
  decision: ESCALATED
  iterations: 1
  escalation_sha: "c68b95086f4c3fdd11142d68fd66084fe932f1d9"

$ jq -c '{required_mode, required_names, decision}' .supervisor/review-heal/<pr_hash>.next-step.json
{"required_mode":"named","required_names":["cix"],"decision":"ESCALATED"}

terminal PR comment:
  review-heal drain ESCALATED (required_check_absent)
  required_check_absent cix — a named required check never reported on c68b95086f4c3fdd11142d68fd66084fe932f1d9
  by the bound; a named check that is missing or never reports blocks READY (ELAPSED
  sha=c68b95086f4c3fdd11142d68fd66084fe932f1d9 required=pending review_producing=settled pending=none)
```

### Observed in passing (not part of this change)

A first attempt at run 2 passed the until-mergeable signal only as `LOOMWRIGHT_UNTIL_MERGEABLE=1` in the
environment, as `dispatch-pr-review.sh` does. Under `dontAsk` the runner could not read its environment
(`env` / `printenv` denied), fell back to the plain diff-only loop and reported `decision: PASS` without waiting
on any check. Passing `--until-mergeable` in the prompt made it run the drain. Run 1 got the drain only because
the runner inferred it. That is a defect in the detached dispatch path, independent of this PR.

Verdict: PASS for Validation 2

## What is covered without a live repo

The hermetic suites on this branch, which stub `gh` and never reach the network, cover every acceptance case
except the live one: `loomwright/scripts/test-review-heal-next-step.sh` (the named mode from the config and from
`name:`, flag over config, readable protection winning, `required_check_absent`, the malformed key, the `name:`
usage errors, the three byte-identical no-list pins, the driver reading `--root`'s config, and no
`--required-checks` in any drain invocation `automate-next-step.sh` builds), its golden case
`fixtures/review-heal-golden/named-required-ready` (READY with a red deployment status outside the set),
`loomwright/scripts/test-wait-for-checks.sh` (`--named-required`: the 200 read wins, the no-list arms take the
set, an absent named check stays pending, no flag means byte-unchanged output),
`loomwright/scripts/test-setup-base-branch.sh` (the advisory line) and
`loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` (a lane clone keeps `required_checks`). These are
stubs: they show the drain does what the code says against the response bodies the tests assume. They do not show
that GitHub answers a real private Free repo with those bodies, which is what Validation 2 checks.
