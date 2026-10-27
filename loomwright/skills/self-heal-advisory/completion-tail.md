# Self-Heal Protocol — after the loop (rubric, advisory checks, red-team lens, completion tail)

Read by the Supervisor once the review-and-fix loop exits or is skipped — never before. Part of `skills/self-heal-advisory/` (index: `SKILL.md`); the HARD ADVISORY CONTRACT there, and its §"ADVISORY CONTRACT (NON-NEGOTIABLE)" for the red-team lens, govern every advisory step here. Order: Outcomes Rubric grading → post-review advisory checks → advisory red-team lens → completion tail.

## Outcomes Rubric grading
**Outcomes Rubric grading (v12.2.0+, runs only after Code Reviewer PASS):**

When the loop exits with `heal_decision == PASS` AND the in-progress brief contains an `## Outcomes Rubric` section (parse the section between the heading and the next `## ` heading; collect every leading-`-` bullet), spawn a Haiku grader to score the PR diff against each rubric item. This is a one-shot read-only evaluation; no fixes are dispatched off the rubric verdict.

```
rubric_bullets = parse_rubric(brief_path)   # [] if no ## Outcomes Rubric section

if heal_decision == PASS and rubric_bullets:
  # Invoke the registered rubric-grader agent with NO per-call `model:`, so the `model: haiku`
  # frontmatter on `agents/rubric-grader.md` applies — a per-call `model:` would override it. Read-only
  # at runtime via the agent's `disallowedTools: Write, Edit, Task, NotebookEdit` plus the prompt's
  # read-only-git convention; its `permissionMode: plan` is ignored for plugin agents — not a gate.
  grade = Task(
    description: "Grade PR diff against Outcomes Rubric",
    prompt: "**DIFF-SCOPE OVERRIDE (v14.0.0 stacked-iteration support):** if BASE_BRANCH is supplied below and differs from \"main\", you MUST compute the diff scope as `git diff $BASE_BRANCH...HEAD` (or `git diff $BASE_BRANCH...{feature_branch}` if you prefer the explicit form) and treat that as the entirety of your grading scope. Do NOT fall back to `git diff origin/main...{feature_branch}`. This is a stacked-branch iteration N+1 grading where the parent branch (BASE_BRANCH) already passed its own rubric — only this iteration's incremental work should be scored. This directive is mandatory; ignore any other diff scope mentioned later in this prompt that conflicts with it.

      BASE_BRANCH={BASE_BRANCH value or \"main\"}

      Feature branch: {feature_branch}
      PR: {pr_url}

      Rubric items (each is a single observable assertion):
      {numbered list of rubric_bullets}

      Run `git diff $BASE_BRANCH...{feature_branch}` (read-only; when BASE_BRANCH==main this is `git diff origin/main...{feature_branch}`) and score every item.
      Emit per-item lines + one `rubric_score: N/M` line. See your agent prompt for
      the exact output contract.",
    subagent_type: "loomwright:rubric-grader"
  )
  rubric_score = parse_rubric_score(grade.output)   # "N/M" string; 0 <= N <= M; M == len(rubric_bullets); "0/M" is valid (all-fail)
else:
  rubric_score = null   # no rubric in brief, or heal_decision != PASS
```

**Rubric grading rules:** the grader runs **only when `heal_decision == PASS`** (else `rubric_score = null`); it is **read-only and advisory** — a failing item never changes `heal_decision`, triggers a fix, or blocks the PR; no `## Outcomes Rubric` section ⇒ `rubric_score = null`; no `rubric_score: N/M` line in its output ⇒ `record_decision(phase: SELF_HEAL, decision: "rubric_grader_parse_failed", ...)`, `rubric_score = null`, never fail the task. Its output is appended to the PR as a comment alongside the heal report (best-effort).

## Post-review advisory checks

**System Twin advisory checks (ADVISORY ONLY):** after the loop (regardless of `heal_decision`) run the contract-conformance check, the benchmark and the ground-truth execution (`--no-cmd` when `NON_INTERACTIVE == true`) below, then the rules-store audit; they populate `contract_conformance`, `benchmark_result` and `ground_truth` for completion-tail step 5. Non-fatal on every failure path; first to skip under YELLOW/RED budget.
### Contract-conformance check (READ path — runs after the Code Reviewer pass)

After the Code Reviewer loop has run (regardless of `heal_decision`), check the **integrated feature-branch diff** against any existing System Contracts for the touched subsystems; this produces `contract_conformance` (and its flat `session_end` fields — §"Hard-signal dual emission").

> **HARD ADVISORY CONTRACT — this check NEVER changes a gate.** It **NEVER changes `heal_decision`**, **NEVER triggers a fix iteration**, and **NEVER blocks the PR**; its findings carry `severity: info | advisory` by construction — never `blocking`/`high`. Reported in `SUPERVISOR_RESULT` for human review and aggregated by ST4; read-only against committed state; dispatches no fixes.
```
# touched subsystems = the files/paths in the integrated diff (the same scope the Code Reviewer
# reviewed). When BASE_BRANCH==main this is `git diff origin/main...HEAD`; for a stacked iteration
# (BASE_BRANCH != main) it is `git diff $BASE_BRANCH...HEAD` — same DIFF-SCOPE OVERRIDE the reviewer used.
touched = paths from the integrated diff (read-only):
          BASE_BRANCH==main  -> git diff --name-only origin/main...HEAD
          BASE_BRANCH!=main  -> git diff --name-only $BASE_BRANCH...HEAD

contract_conformance = { checked: false, status: "skipped", contracts_evaluated: 0, violations: 0, findings: [] }

# STORE-HEALTH PROBE — TWO scopes, unioned: the whole-store probe catches a store that is dark for ids
# this PR does not touch; a per-id `--subsystem` read says `dark` EXACTLY when that id had a stored
# contract the gate withheld (an unstored id reports `empty`, never `dark`), which catches a merely
# DEGRADED store whose dropped subsystem is the one this PR touches. Never sample the store status inside
# the loop and keep the last value (order-dependent). Measured scope table: docs/rationale/supervisor.md
# §"Contract-conformance store-health probe".
twin_store_status = bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-system-contract.sh | grep '^twin_store_status:'
  # -> empty | healthy | degraded | dark. Always exits 0; an unreadable/absent reader leaves this
  #    unset, which is treated as "not dark" below (fail-safe: never invent a dark verdict).
touched_contract_withheld = false

for each subsystem id derivable from `touched` (a path or a logical subsystem name):
  # read-side provenance gate; NEVER `cat` the contract files directly.
  contract = bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-system-contract.sh --subsystem "<id>"
  if that output's `twin_store_status:` is `dark`:
    # This id HAS a stored contract and the gate withheld it. Not "nothing to check" — could not
    # check. True even when the store as a whole is only `degraded`.
    touched_contract_withheld = true
  if contract has a verified body (not "(no verified System Twin contracts)"):
    contract_conformance.checked = true
    contract_conformance.contracts_evaluated += 1
    # Compare the integrated diff against the contract's `invariants` / `behavioral_specs`.
    # Any apparent divergence is recorded as an ADVISORY finding (severity info|advisory only).
    for each invariant the diff appears to violate:
      contract_conformance.findings += { subsystem: "<id>", invariant: "<text>", severity: "advisory", detail: "<what in the diff diverges>" }

contract_conformance.violations = len(contract_conformance.findings)

# STATUS. The withheld test is FIRST and is NOT nested under `not checked`: `pass` must mean "checked,
# and clean" — a run that could not read a contract it was supposed to check has not earned it.
if twin_store_status == "dark" or touched_contract_withheld:
  # A contract EXISTS and the gate withheld it — for every subsystem (`dark` store) or for one this
  # PR touched (`touched_contract_withheld`, reachable while the store is only `degraded`). This
  # This run could not fully check: record it as neither `pass` nor `skipped`.
  #
  # It does NOT suppress real findings: divergences among the subsystems that COULD be read are
  # still reported, because an actual violation is more actionable than an incomplete-check notice.
  if contract_conformance.violations >= 1:
    contract_conformance.status = "advisory_violations"
  else:
    contract_conformance.status = "unverified"     # never `pass`, never `skipped`
elif not contract_conformance.checked:
  # Nothing was stored for any touched subsystem, or the reader emitted nothing (no sha tool /
  # empty store) — and nothing was withheld. Genuinely nothing to do. Graceful no-op.
  contract_conformance.status = "skipped"        # (use "unverified" instead when the tooling itself was unavailable)
elif contract_conformance.violations == 0:
  contract_conformance.status = "pass"
else:
  contract_conformance.status = "advisory_violations"

# Name the withheld ids in the decision line — `violations` counts invariant divergences ONLY (a withheld
# contract is a check that did not happen, not a violation).
record_decision(phase: SELF_HEAL, decision: "contract_conformance: {status} ({violations} advisory{, N withheld: <ids> if any})", rationale: "advisory only — heal_decision unchanged")
```

**Contract-conformance rules:**
- Absent contracts (empty `.supervisor/twin/`, or the reader emits nothing) → `checked: false`, `status: skipped` (or `unverified` if the tooling was unavailable), `0` / `0`. Graceful no-op — never an error, never a fix.
- **A WITHHELD contract is not an absent one.** Record `status: unverified`, not `skipped`, when the whole-store probe prints `twin_store_status: dark` or a `--subsystem` read for a touched id prints `dark` (that id has a stored contract the gate withheld — reachable while the store overall is only `degraded`). **The withheld test is evaluated FIRST, independently of `checked`**; real divergences still win the status (`advisory_violations`), and the withheld ids are named in the decision line, never counted as violations. Surface the reader's loud `!!` block naming the repair (`scripts/reprovenance-twin-contracts.sh`) rather than swallowing it. Never work around a drop by `cat`-ing the contract files — the drop is the gate's verdict, not a malfunction.
- `status: pass` requires `violations: 0`; `status: advisory_violations` requires `violations >= 1` and a non-empty `findings[]` (each `severity: info | advisory`).
- READ-only via `read-system-contract.sh` — it NEVER writes the twin store (the WRITE is the completion tail's contract builder). It runs on EVERY Phase 4.5 (PASS or ESCALATED), not gated on PASS.


### Benchmark run (populates `benchmark_result`)

Run the deterministic "provable-done" benchmark (`run-benchmark.sh`, WITHOUT `--update-baseline` — the heal loop measures but never moves the baseline):

```
bench = bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-benchmark.sh
# Parse the single `BENCHMARK_JSON: {...}` line -> benchmark_result (ran, status, name, metric,
# value, baseline, delta, unit). The script is deterministic, reads/writes its baseline under
# .supervisor/twin/benchmark-baseline.json (gitignored), and ALWAYS exits 0 — on any failure it
# emits status: unverified with value: null. Treat a parse miss as benchmark_result.ran=false,
# status: unverified. The benchmark is informational; it NEVER changes heal_decision or blocks the PR.
```


### Ground-truth execution (M2b slice 1a — runs after the Code Reviewer pass)

After the loop (regardless of `heal_decision`, PASS or ESCALATED, read-only), execute the project-declared **executable acceptance checks** and report whether they pass — the `ground_truth` object (and its flat `session_end` fields).

> **HARD ADVISORY CONTRACT — this check NEVER changes a gate:** never `heal_decision`, never a fix iteration, never blocks the PR; findings are `severity: advisory` only. The runner ALWAYS exits 0 (a failing check is a normal `fail` tally).
```
# Resolve checks from the in-progress brief's `## Executable Acceptance` section (pass --brief),
# falling back to .supervisor/twin/ground-truth.json when the brief has no such section.
ground_truth = { checked: false, status: "skipped", checks_total: 0, checks_passed: 0, findings: [] }

# SAFETY VALVE (--no-cmd): only when NON_INTERACTIVE == true. A default, interactive `/autonomous "goal"`
# run has NON_INTERACTIVE == false (/autonomous forwards --non-interactive ONLY when its OUTER call had
# --non-interactive-fallback), so a `cmd:`/bare bullet runs exactly as under a plain interactive
# `/supervisor`. --no-cmd skips cmd:/bare checks entirely (recorded unverified/"cmd_disabled");
# corpus-task:/qa-executor: checks are unaffected either way.
#
# The REAL guard on every OTHER path is the content-keyed stamp gate `run-ground-truth.sh` enforces via
# `scripts/exec-acceptance-hash.sh` / `scripts/exec-acceptance-lib.sh`: a --brief-sourced `cmd:`/bare
# bullet executes ONLY when the brief's `## Configuration` section carries a stamp whose hash matches the
# CURRENT bullet list exactly (absent/stale -> unverified, reason "cmd_unapproved", never executed) — see
# `docs/RESULT_SCHEMAS.md` §"`## Executable Acceptance`" and `agents/plan-reviewer.md` Criterion 14.
NO_CMD_FLAG = (NON_INTERACTIVE == true) ? "--no-cmd" : ""
# Run from the pinned repo-root CWD: the runner derives the PROJECT ROOT (handed to each corpus-task
# check.sh as EVAL_PROJECT_ROOT) from the caller's git toplevel. `--project <dir>` exists for callers
# that cannot pin CWD.
gt = bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-ground-truth.sh --brief <brief_path> $NO_CMD_FLAG
# The runner prints TWO machine lines (issue #616 — two hand-mapped objects wrote `ran`/`pass_rate` and
# were refused at the trail push):
#   GROUND_TRUTH_NESTED: {...}  — the SUPERVISOR_RESULT ground_truth object ALREADY in schema shape:
#                                 checked (<- ran), status, checks_total, checks_passed, and findings[]
#                                 (the failing per_check entries, severity "advisory") when any failed.
#   GROUND_TRUTH_JSON: {...}    — the runner's own record; the FLAT session_end fields read it.
ground_truth = <the GROUND_TRUTH_NESTED value, copied VERBATIM>   # never add, rename or drop a key
# No GROUND_TRUTH_NESTED line (runner failed / not run) → ground_truth = {checked: false, status: unverified}.
# /automate refuses a RUN report whose ground_truth has any other key set (exit 2, nothing written).
# Flat fields (Hard-signal dual emission below): ground_truth_status/_checks_total/_checks_passed from
# either line; ground_truth_pass_rate = GROUND_TRUTH_JSON's pass_rate — FLAT ONLY.

record_decision(phase: SELF_HEAL, decision: "ground_truth: {status} ({checks_passed}/{checks_total})", rationale: "advisory only — heal_decision unchanged")
```

**Ground-truth execution rules:**
- The runner resolves checks from the brief's optional `## Executable Acceptance` section (priority) or `.supervisor/twin/ground-truth.json` (fallback). No source → `checked: false`, `status: skipped`, `0/0`, empty `findings[]`. Graceful no-op — never an error, never a fix.
- `status: pass` requires zero failing checks (and ≥1 check executed); `status: advisory_failures` requires ≥1 failing check and a non-empty `findings[]` (each `severity: advisory`); `status: unverified` is the fail-safe tooling path (no `jq`, or checks resolved but none could be verified — e.g. only deferred `qa-executor` checks).
- `qa-executor:` checks are DEFERRED to M2b slice 1b (recorded `unverified`, reason `qa_executor_dispatch_deferred_m2b_1b`; they never block a `pass`). **Trust boundary (not a sandbox):** a `cmd:` check runs arbitrary `bash -c` with full shell privileges — review `## Executable Acceptance` `cmd:` bullets at Plan Review (especially `/autonomous`-generated briefs); `corpus-task` ids are a single path segment, so they cannot escape `eval-corpus`.

### Rules-store audit (automate-followups/09 — advisory, NEVER gates)

Re-validate the committed `.agent/rules/` store once per Phase 4.5 run through ONE deterministic always-exit-0 helper, `scripts/rules-audit-line.sh`, which runs the read-only `audit-rules.sh` engine (`skills/rules/SKILL.md` §11) over the feature-branch checkout and maps its report to exactly one `rules_audit:` line (plus an optional `rules_gate_trigger:` line). It EXECUTES NOTHING — every rule `check` is linted as text — so it has no `$NO_CMD_FLAG` valve and no stamp interplay.

> **HARD ADVISORY CONTRACT — this check NEVER changes a gate.** Nothing it reports enters Part 2's findings or the review-and-fix loop, and nothing escalates. Read-only; the helper ALWAYS exits 0; it runs ONCE per run and lints the store, not the diff.
```
out = run(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rules-audit-line.sh" --root <the feature-branch checkout>)
# Contract: always exit 0; stdout is EXACTLY one or two lines (mapping: the helper's own header — not restated here).
lines = out.stdout split on newlines
rules_audit_line        = lines[0] if lines[0] starts with "rules_audit: " else "rules_audit: unexamined"   # an absent/garbled helper never reads as clean
rules_gate_trigger_line = lines[1] if lines[1] starts with "rules_gate_trigger: " else none

record_decision(phase: SELF_HEAL, decision: rules_audit_line [+ "; " + rules_gate_trigger_line when present], rationale: "read-only store audit (audit-rules.sh via rules-audit-line.sh)")
```

**Rules-store audit state trace** (exactly one `rules_audit:` line per run):
- `rules_audit: clean` — no BLOCKING finding (a store with no `.agent/rules/` directory is also `clean`). `heal_decision` is unchanged; nothing enters Part 2's findings or the loop; nothing escalates.
- `rules_audit: findings <n> (<kinds>)` — `<n>` BLOCKING store findings of the listed kinds (e.g. `findings 1 (no_mechanism)`). `heal_decision` is unchanged; NOT synthesized into Part 2's findings, NOT fed to the loop, NOT escalated — a human runs `/rules audit` for the evidence and the `/rules add --supersedes` / retract action.
- `rules_audit: unexamined` — the engine could not examine the store (exit 2, an absent or garbled engine/helper, a disagreeing report); NEVER reported as `clean`. `heal_decision` is unchanged; nothing enters Part 2's findings or the loop; nothing escalates.
- `rules_gate_trigger: …` (optional second line, any state) — the store holds a `must` rule with a non-empty `check` while the parked `proposed/automate-followups-08-…` file exists: that item is now actionable. Promotion stays a human act.

## Advisory red-team lens

**Advisory red-team lens (opt-in, high-risk-only — OPT-IN / DEFAULT-OFF / FAIL-SAFE / strictly NON-GATING):**

Runs AFTER the Code Reviewer holistic pass has produced its decision (independent of the System Twin advisory checks) and BEFORE the completion tail. It is a SINGLE pass **OUTSIDE the bounded fix loop** — never a new heal iteration. Opt-in (default-OFF; `--red-team` / `.red_team_high_risk`, resolved as `RED_TEAM_ENABLED`); it applies a second, adversarial lens to high-risk integrated diffs. Its ADVISORY CONTRACT (NON-NEGOTIABLE) is in `SKILL.md`.

```
# High-risk classification — UNCONDITIONAL (decision D1): one deterministic Bash call, no LLM, BEFORE the
# RED_TEAM_ENABLED guard, so SUPERVISOR_RESULT.risk_classification is present whether or not the spawn runs.
# The heuristic lives in ONE place — scripts/classify-risk.sh (`classify-risk.sh --kind-table` prints the
# rules). Do NOT restate the pattern list here. The same script is condition 6 of the /automate
# trusted-merge gate, which re-runs it on the SHA it judges — this value is advisory and never gates anything.
rc = JSON of `classify-risk.sh "$BASE_BRANCH" HEAD`   # the plugin's scripts/classify-risk.sh, invoked like the sibling scripts in this Part
     # fail-SAFE emitter, always exit 0: {"high_risk": true|false|null, "reasons": [...], ...}
     # null = unclassifiable — the safe direction for an ADVISORY lens is to run it, so null is treated like true.
high_risk = rc.high_risk                      # true | false | null
risk_classification = {high_risk: rc.high_risk, reasons: rc.reasons}   # → SUPERVISOR_RESULT (additive, optional)
record_decision(phase: SELF_HEAL, decision: "risk_classification: {true|false|null}",
                rationale: "<rc.reasons joined '; ', or the unclassifiable reason>")

# Guard: default path is a zero-behavior-change silent skip (the classification above still ran).
if RED_TEAM_ENABLED != true:
    red_team_advisory = "disabled"
    # skip silently — no spawn, no PR comment, no note beyond the one-word record below.
else:
    if high_risk == false:
        red_team_advisory = "skipped_low_risk"
        # record a one-line note; do NOT spawn.
    else:   # true OR null — spawn
        # Spawn EXACTLY ONE advisory pass — single, outside the heal loop, never a heal iteration.
        try:
          rt = Task(
            subagent_type: "loomwright:red-team-reviewer",
            description: "Advisory red-team lens on integrated high-risk diff (non-gating)",
            prompt: "Advisory, NON-GATING adversarial review of the integrated feature-branch diff.
                     Feature branch: {branch}
                     PR: {pr_url}
                     Diff scope: git diff $BASE_BRANCH...HEAD (BASE_BRANCH={BASE_BRANCH value or \"main\"}).
                     This is a SINGLE advisory pass OUTSIDE the self-heal loop. Your findings are
                     informational only — they do NOT gate the PR and do NOT drive any fix.
                     Report your attack-vector findings per your normal red-team output contract."
          )
          # Post as a clearly-labelled NON-GATING comment. Capture the exit status — a failure is recorded "error",
          # never masked as "ran" (so no bare `|| true` here).
          if gh pr comment "$PR_URL" --body "🔴 Advisory red-team review (non-gating) — high-risk diff\n\n{rt findings summary}" ; then
            red_team_advisory = "ran"
            rt_findings_oneline = "{one-line risk/findings summary from rt}"
          else:
            # comment post failed — fail-safe: log a one-line no-op, record "error", CONTINUE.
            record_decision(phase: SELF_HEAL, decision: "red_team_advisory_comment_failed", rationale: "gh pr comment returned non-zero")
            red_team_advisory = "error"
        catch (any spawn error / timeout / non-zero):
          # FAIL-SAFE: log one line and CONTINUE. Never abort the run on this path.
          record_decision(phase: SELF_HEAL, decision: "red_team_advisory_error", rationale: "{brief error}")
          red_team_advisory = "error"
```

## Completion tail
**Completion tail (always runs — both when the loop ran and when it was skipped):**

0. **Completion-tail guard — LIVES VERBATIM IN `agents/supervisor.md` (deliberately NOT moved
   here; gates stay visible in the agent file):** before any other completion-tail action, apply
   the guard exactly as written in the `agents/supervisor.md` Phase 4.5 stanza — subject to its
   thrash-escalation exception, if `skip_self_heal_requested == false` AND
   `phase45_review_invoked == false`, abort with `status: failed` per the agent file and do NOT
   proceed to the steps below.

1. Determine outcome:
   - `heal_decision == PASS` OR `heal_loop_ran == false` (loop skipped): task succeeds cleanly
   - `heal_decision == ESCALATED`: task succeeds with escalation

2. **Job lifecycle completion** (if `job:` parameter was used):
   - On PASS / loop-skipped: Move brief from `in-progress/` → `done/`, append outcome section:
     ```markdown
     ## Outcome
     - **Status:** completed
     - **Completed:** {ISO 8601 timestamp}
     - **PR:** {PR URL}
     - **Branch:** {feature branch name}
     - **Files changed:** {count}
     - **Heal loop ran:** {true|false}
     - **Heal decision:** {PASS|null}
     - **Heal iterations:** {N|null}
     - **Red team advisory:** {ran|skipped_low_risk|disabled|error}
     - **Red team findings:** {one-line risk/findings summary — ONLY when `red_team_advisory == ran`; omit otherwise}
     - **Until-mergeable dispatched:** {true|false}
     - **Until-mergeable log:** {RUN_LOG path under .supervisor/logs/ — ONLY when `until_mergeable_dispatched == true`; omit otherwise}
     - **Summary:** {brief description of what was done}
     ```
   - On ESCALATED: Move brief from `in-progress/` → `done/`, append outcome section with `**Status:** completed_with_escalation`, plus `**Heal reason:** {needs_human|max_iterations_reached|self_heal_resume_thrash|rules_gate_unresolved|rules_fail_then_unstamped}`, `**Heal remaining issues:** {count}`, and the same `**Red team advisory:** {ran|skipped_low_risk|disabled|error}` line (plus the `**Red team findings:**` one-liner when it ran) — the red-team lens runs before the completion tail regardless of `heal_decision`, so its outcome is recorded on both the PASS and ESCALATED paths.
   - **`## Not verified` section (optional, harness-port/04) — appended to the brief itself, on BOTH the PASS/loop-skipped and ESCALATED outcomes above:** aggregate every worker's `not_verified` sub-list from `state.md`'s `## Worker Results` — the SAME aggregation the FINALIZE PR body's `## Not verified` section uses (`skills/async-orchestration/SKILL.md` Part 2) — and append one `## Not verified` section to the brief (after the `## Outcome` block just appended), one bullet per item across ALL workers: `- **<surface>** — <reason> (subtask <id>)`. **OMITTED ENTIRELY** (no heading, no "none" line) when every worker's `not_verified` list is absent/empty. This is the surface `/verify`'s `acs <ticket>` command reads back (`loomwright/scripts/verify-run.sh`) — the PR body's copy of the same section is for the human only. REPORT-ONLY: never gates this step, `heal_decision`, or the job-lifecycle move.
   - Backward compatibility: If job file is not in `in-progress/`, skip the move step (direct `/supervisor task:` invocation without Launch Pad).

2.5. **Requirement close-out — deferred to the post-merge `closeout` (this step writes NOTHING to the requirement):**

   On every outcome that reaches this step (**PASS / loop-skipped / ESCALATED**) the completion tail writes **nothing** to the originating requirement file (the brief's `- **Source requirement:**`): no `## Status:` line of any value, no sentinel-led close-out block. A requirement's done stamp means **its PR merged**, and the PR is still OPEN here.

   - **Who closes it out:** `automate-helpers.sh closeout` (`scripts/automate-trail.sh`) is the sole writer of the requirement's sentinel-led done block, and stamps only after its evidence gate reads the PR `MERGED` (`skills/automate-loop/SKILL.md` §6 "Post-merge close-out"); the human-run `reconcile-status --apply` is the only other done writer, evidence-gated the same way.
   - **Where Phase 4.5's verdict goes:** the brief's `## Outcome` block (step 2: `**Status:** completed` / `completed_with_escalation`, `**Heal reason:**`, `**Heal remaining issues:**`) and, under `/automate`, the run file — never the requirement.
   - **Record:** `record_decision(phase: SELF_HEAL, decision: "requirement_closeout: deferred_to_post_merge", rationale: "requirement done stamp is written only by closeout after the PR reads MERGED")`, then continue to step 2.6. Fail-SAFE: recording is the step's only action, and a failure to record never changes `SUPERVISOR_RESULT.status`.
   - **Honest limit — one path gets no automatic done stamp:** a plain `/supervisor` or `/autonomous` run outside `/automate`. `closeout` needs an `/automate` run file and a caller — `/automate --resume`'s RECONCILE, the merge watcher (`automate-merge-watch.sh`), `closeout-others`, `--auto-merge` SYNC (`closeout --no-trail`) and a merged `--parallel` lane's `lane-convert-ready` re-run (`closeout --no-trail`) — so on that path recovery after the merge is a human step: `automate-helpers.sh reconcile-status <requirements_root> --apply`, or a hand-written `## Status: done`. `stamp-requirement-status.sh` records `## Status: brief-shipped` once the brief lands in `done/` — deliberately not a done value. A missed done stamp is recoverable, a false one is not (`docs/rationale/supervisor.md` §"Requirement close-out deferral").

2.6. **Orientation memo proposals (success-only, fail-safe side-effect — additive):**

   Runs on the SAME outcomes as step 2.5 (**PASS / loop-skipped / ESCALATED** only — never on the `failed` / abort / `checkpoint` / invariant-violation / base-mismatch-cleanup paths). The run **MAY** propose per-area **orientation memos** for the areas it touched: one `<area-slug>.md` per area (a single `[a-z0-9-]+` segment, `readme` reserved — `add-orientation.sh`'s slug rules) in the **gitignored** `.supervisor/orientation-proposals/` (`mkdir -p` first), in the memo format of `.agent/orientation/README.md` (line 1 `<!-- written_at: <ISO-8601 UTC> | head_sha: <short HEAD sha> | areas: <space-separated repo-relative path prefixes> -->`, line 2 a one-line summary, then markdown), the WHOLE file ≤1000 chars.

   **NEVER writes the committed `.agent/orientation/` store** — only the `/dreaming` per-item-approval flow calling `add-orientation.sh` promotes. A runtime side-effect emitter that MUST fail SAFE: any write failure is a logged no-op — `record_decision(phase: SELF_HEAL, decision: "orientation_proposals: {n written|noop_write_failed|skipped}", rationale: "advisory — non-fatal")` — and the tail always continues to step 3.

3. **Reset resume counter (unconditional — runs on every exit path: PASS, ESCALATED, or loop-skipped):** `Context-Keeper(operation: record_self_heal_resume, increment: false)`. The completion tail itself is unconditional; so is the reset.

4. **Record the outcome:** `record_decision(phase: SELF_HEAL, decision: "{PASS|ESCALATED|loop_skipped}", rationale: "{final reason}")`.
   - **Terminal status is derived, not flipped here.** `scripts/build-state.sh` derives `.supervisor/state.md`'s `- status:` (`completed` / `completed_with_escalation` / `failed`) from the run's `session_end` event — see `docs/TELEMETRY.md`; `scripts/reproject-state-on-terminal.sh` (under the `PostToolUse[Bash]` matcher) re-invokes the projector as soon as a non-terminal `state.md` and a `session_end`-carrying log are both observed. Do not re-add a status-flip prompt instruction here — a remaining edge is closed by another mechanical hook site, not a written instruction.

4.5. **System Twin contract builder (WRITE path — completion tail only):**

   **Runs only on a PASS outcome** (`heal_decision == PASS` or loop-skipped — the same outcomes that move the job to `done/` in step 2); SKIP on the ESCALATED / base-mismatch / invariant-violation paths. Compute the per-subsystem incident map for THIS run and spawn the ephemeral, Bash-capable builder Task exactly per §"Contract builder (WRITE path — completion tail only)" below — the spawn prompt there is verbatim and authoritative.

   Its invariants (propose-only; pinned repo-root CWD; Context-Keeper out of the path; failure non-fatal) are the bullets under §"Contract builder (WRITE path — completion tail only)" below.

5. **Emit SUPERVISOR_RESULT block for this task** (definition: `agents/supervisor.md` §"Result Block (SUPERVISOR_RESULT)"; the SubagentStop hook validates the last block, earlier blocks must still be schema-valid). Exactly one block per task, emitted here — Phase 5 LOOP emits nothing. Include the additive `contract_conformance`, `benchmark_result` and `ground_truth` objects and the `knowledge_sources_used` array (tag vocabulary in the Result Block section), and emit the FLAT hard-signal fields — including a flat `knowledge_sources_used` with the SAME value — onto the `session_end` JSONL event (see "Hard-signal fields (System Twin)" below).

   **`heal_dismissed` — include when non-empty, omit when empty** (same rule as `REVIEW_HEAL_RESULT.dismissed`, `docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT): the list accumulated across every loop iteration, verbatim.

   **Dismissed-findings marker comment (same shape as the drain's — `skills/review-heal/SKILL.md` §"Dismissed-findings marker comment", not restated here).** When `heal_dismissed` is non-empty, post ONE `gh pr comment` at this same completion-tail point, body `<!-- loomwright:dismissed round=<n> -->` followed by one `- **<finding>** — <reason> (<source>)` bullet per `heal_dismissed` item. **Round number `<n>` (1-indexed, exit-path-aware):** `heal_iterations + 1` when the loop ended on a break — `PASS`, `NEEDS_HUMAN`, or the `rules_gate_unresolved` / `rules_fail_then_unstamped` break (also pre-increment) — i.e. whenever `heal_iterations < max_heal_iterations`; `heal_iterations` UNCHANGED on loop exhaustion (`heal_iterations == max_heal_iterations`, the SAME condition as the "Loop exit" guard in `SKILL.md`). `heal_decision == PASS` always takes the `+1` form. When `heal_loop_ran=false` no comment is posted. Post once, never edited later. `classify-bot-review.sh`'s `--skip-marker` default-ON filter (`skills/review-heal/SKILL.md` §U1) keeps a later `--until-mergeable` drain on the same PR from mis-classifying it as a human finding. Why the anchor is exit-path-aware: `docs/rationale/supervisor.md` §"Dismissed marker round anchor".

5.5. **Until-mergeable review-drain dispatch (DEFAULT ON — opt-out, best-effort, fire-and-forget):**

   Runs ONLY on a PASS / normal completion that produced a PR (`PR_URL` set; skip on the base-mismatch cleanup path, on `status: failed`/`checkpoint`, and when no PR was created). Hand the PR URL to the dispatcher, which launches a fresh, detached standalone review-and-heal run via the **`--agent` runner form** (`loomwright:review-pr-runner`) and **by default threads the until-mergeable drain signal** (the external-channel drain — required CI checks, bot reviews/threads/comments, check outputs). Dispatch is ON BY DEFAULT, suppressed by `--no-auto-review` OR `.supervisor/config.json` `.auto_review == false`; the until-mergeable signal is opt-out via `--no-until-mergeable` OR `.auto_until_mergeable == false`. The signal travels as **environment variables** (never a `/review-pr` slash string or positional — the `--agent` form has no flag surface) per `skills/review-heal/SKILL.md` §"Until-Mergeable Dispatch Signal". A per-PR marker guarantees exactly ONE dispatch per PR.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-pr-review.sh" \
     --pr-url "{PR_URL}" \
     {if AUTO_REVIEW_FLAG == suppress: --no-auto-review}{if AUTO_REVIEW_FLAG == force: --auto-review} \
     {if UNTIL_MERGEABLE_FLAG == suppress: --no-until-mergeable} \
     {if CHECK_WAIT_TIMEOUT set: --check-wait-timeout "{CHECK_WAIT_TIMEOUT}"} \
     {if REVIEW_CHECK_PATTERN set: --review-check-pattern "{REVIEW_CHECK_PATTERN}"}
   # always exits 0. The optional tuning flags are forwarded ONLY when set (exported as LOOMWRIGHT_CHECK_WAIT_TIMEOUT /
   # LOOMWRIGHT_REVIEW_CHECK_PATTERN). Omit --auto-review/--no-auto-review when AUTO_REVIEW_FLAG == none.
   ```

   The dispatched drain **NEVER merges** and **NEVER waits on a human** — it stops at a terminal `READY` / `ESCALATED` state and notifies on both (`skills/review-heal/SKILL.md` §"READY redefinition"). Strictly best-effort: the dispatcher ALWAYS exits 0, so it can NEVER hard-fail the completion tail; it NEVER changes `heal_decision`, the PR, control flow or `SUPERVISOR_RESULT.status` — always continue to step 6. `/review-pr` never creates a PR, so there is no review→review recursion.

   **Hook backstop.** A `PostToolUse[Bash]` hook (`${CLAUDE_PLUGIN_ROOT}/scripts/hook-dispatch-on-pr-create.sh`) invokes the SAME `dispatch-pr-review.sh` when the PR is opened (session-scope gated), so the drain still runs when this step is skipped; the per-PR marker keeps it to ONE dispatch, and the drain's own worktree makes overlap with the inline self-heal harmless. **Do NOT write `.supervisor/config.json {"auto_review": false}` to suppress the drain for this self-heal race** (`docs/rationale/supervisor.md` §"Drain timing and the retired workaround").

   **Observability (AC8b) — reconcile against the MARKER, never from "did I dispatch"** (the hook dispatch is invisible here; `docs/rationale/supervisor.md` §"Dispatch observability false negative"). Match the exact PR URL in the marker body and `url={PR_URL}` + tab in the RUN_LOG header (no prefix confusion):
   ```bash
   # MARKER present ⇔ the dispatcher ran past its claude-on-PATH check for this PR
   # (via step 5.5 OR the hook). Match the marker BODY's exact PR URL, not the
   # hash-keyed filename or a URL substring, so this is independent of the dispatcher's hashing tool.
   if awk -v url="{PR_URL}" '$0 == url || $2 == url { found=1; exit } END { exit(found ? 0 : 1) }' .supervisor/review-dispatch/* 2>/dev/null; then
     UM_DISPATCHED=true
     # Best-effort log pointer: the RUN_LOG header carries `url={PR_URL}` followed by a tab (first match — the per-PR marker means normally exactly one log per PR).
     UM_LOG="$(grep -rlF "$(printf 'url=%s\t' "{PR_URL}")" .supervisor/logs/review-pr-dispatch-*.log 2>/dev/null | head -1)"
   else
     UM_DISPATCHED=false; UM_LOG=
   fi
   ```
   Record `until_mergeable_dispatched: {UM_DISPATCHED}` and (only when true AND a log was found) `until_mergeable_log: {UM_LOG}` on the job's `## Outcome` block (step 2) AND the `session_end` JSONL event (optionally on `SUPERVISOR_RESULT` too — additive, never gated). **NEVER assert `false` from "I skipped step 5.5" alone** — `false` is truthful ONLY when no marker exists (opted out / no PR / dispatcher no-op).

6. **Advisory Twin delta line (informational ONLY):** echo one line via `format-twin-delta.sh` from `contract_conformance` / `benchmark_result` — exact invocation in §"Advisory Twin delta line" below; it never gates, alters the PR, or affects control flow.
7. **Rules-check replay line (report line, executable-rule-candidates/01; its gating effect lives in Part 2, automate-followups/07):** surface the LAST iteration's `rules_check_line` (`SKILL.md` §"Rules-check replay") alongside step 6's line — the Phase 4.5 report only, not the PR body (written at Phase 4 FINALIZE); NO nested `SUPERVISOR_RESULT` field and NO flat `session_end` field. The gate it reports on already acted inside the loop: a countable stamped `fail` became BLOCKING `rule_findings` (so `heal_decision: PASS` means every countable stamped check passed or none was countable), and `unresolved`/`unreadable` already escalated with `rules_gate_unresolved` (an `unstamped` after a remembered countable fail, with `rules_fail_then_unstamped`).
8. **Rules-store audit line (report line ONLY, automate-followups/09):** surface `rules_audit_line` (computed ONCE per run, §"Rules-store audit" above), then `rules_gate_trigger_line` when present, alongside step 7's line — same placement contract: the Phase 4.5 report only, NOT the PR body, no `SUPERVISOR_RESULT` or `session_end` field. No gate is behind it.
9. **House-rule verdicts line (report line ONLY):** surface the LAST iteration's `house_rules_line` (`SKILL.md` §"House-rule verdicts line") alongside steps 7–8, same placement contract. It names every `violated` / `conflicts_with_requirement` rule with its reason; it never alters `heal_decision`, the PR, or control flow.

**Hard-signal fields (System Twin / ST3 — written in BOTH shapes):**

Emit the contract-conformance, benchmark, and ground-truth results as the SAME data in two shapes: (1) nested objects on `SUPERVISOR_RESULT` (step 5 above) and (2) FLAT scalar fields on the `session_end` JSONL event in `.supervisor/logs/{session_id}.jsonl` — the shape `build-insights.sh` (ST4) aggregates. **The flat field names are a hard contract with ST4 — do NOT rename them** (correspondence: §"Hard-signal dual emission" below and `docs/RESULT_SCHEMAS.md` §"`session_end` JSONL hard-signal fields"). Flat fields are additive — a `session_end` event without them remains valid. Also stamp onto the same event the additive `plugin_version` (string) — read at emission time via `jq -r '.version // "unknown"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"` (`"unknown"` when the manifest is unreadable; absent stays valid) — and the additive FLAT `knowledge_sources_used` array with the SAME value as `SUPERVISOR_RESULT.knowledge_sources_used`, each tag written in the canonical form of `docs/result-schemas/session-end-jsonl.md` §"Knowledge-source tag vocabulary" (base tag lowercase, `-` → `_`, `:<qualifier>` verbatim) (advisory, never gated; readers treat absent as "none used"; no `schema_version` bump).
### Contract builder (WRITE path — completion tail only)

**Runs only on a PASS outcome** (`heal_decision == PASS` or loop-skipped — the outcomes that move the job to `done/`, completion-tail step 2); SKIP on the ESCALATED / base-mismatch / invariant-violation paths. **Propose-only, advisory, and reversible** — it writes the advisory twin store, never plugin code, never a gate.

**First, compute this run's per-subsystem incident map** (`docs/RESULT_SCHEMAS.md` §SYSTEM_CONTRACT `incident_history`) — incidents observed *this run* only, from two sources already computed in Phase 4.5, passed to the builder so it can append (never backfill):

```
incident_map = {}   # subsystem id -> [ {kind, summary} ]   (this-run incidents only)

# (a) Conformance violations — group contract_conformance.findings by subsystem.
for f in contract_conformance.findings:           # each: {subsystem, invariant, severity, detail}
  incident_map[f.subsystem] += { kind: "conformance_violation",
                                 summary: f.invariant }   # the violated invariant text (short human string)

# (b) Self-heal fixes — map each fix iteration's modified files to a subsystem id.
#     Use the SAME id convention the builder uses (docs/RESULT_SCHEMAS.md §SYSTEM_CONTRACT):
#     repo-root-relative PATH for a file-backed subsystem; a stable LOGICAL name for a
#     cross-file concern. For file-backed paths the id IS the repo-root-relative path.
for each fix iteration that ran in the review-and-fix loop:        # FIX_RESULT per iteration
  for path in FIX_RESULT.files_modified:
    sid = subsystem_id_for(path)                  # repo-root-relative path (file-backed)
    incident_map[sid] += { kind: "self_heal_fix",
                           summary: "self-heal fixed {FIX_RESULT.issues_addressed} issue(s) in {path}" }
```

A subsystem absent from `incident_map` gets NO new entry (its prior `incident_history` is carried unchanged — never fabricate); `incident_history` is additive, bounded, deduped, this-run-only, never a gate; `schema_version` stays `1`.

Spawn an **ephemeral, Bash-capable builder Task** (`general-purpose` — NOT a new permanent agent, NOT Context-Keeper) that derives one SYSTEM_CONTRACT per touched subsystem and writes each via `write-system-contract.sh`, passing `incident_map`:

```
Task(
  subagent_type: "general-purpose",
  # Tool allowlist: Read, Bash, Glob, Grep (no Task — the builder may not dispatch further subagents).
  working_dir: PINNED REPO-ROOT CWD — the main checkout (NEVER a worktree).
  prompt: "You are the ephemeral System Twin contract builder (advisory, propose-only).

    Repo root (CWD): {repo_root}     # the main checkout — you MUST run from here.
    Touched diff scope: {BASE_BRANCH==main ? 'git diff origin/main...HEAD' : 'git diff $BASE_BRANCH...HEAD'}
    Provenance derived_from: {commit SHA or that diff expression}
    Run timestamp (ISO 8601): {run_iso8601}     # use as incident_history entry `date`
    Session id: {session-id}                      # use as incident_history entry `source` (== --source)
    This-run incident map (subsystem id -> [{kind, summary}], this-run incidents ONLY):
      {incident_map as derived above — empty {} if this run had no conformance violation and no self-heal fix}

    For EACH touched subsystem, derive a structured SYSTEM_CONTRACT (schema in docs/RESULT_SCHEMAS.md
    §SYSTEM_CONTRACT): subsystem, invariants, dependencies, behavioral_specs, and provenance
    (derived_from = the diff/commit above, source = this session id).
    Pick the `subsystem` id per the convention in docs/RESULT_SCHEMAS.md §SYSTEM_CONTRACT — the
    repo-root-relative PATH for a file-backed subsystem (e.g. 'scripts/build-insights.sh') or a
    stable LOGICAL name for a cross-file concern (e.g. 'supervisor-phase45'). Use the SAME id the
    Launch Pad reader would derive (it is the lookup key); do not abbreviate the path.
    Do NOT populate provenance.content_hash — that field is informational only and a file cannot
    contain its own hash. OMIT it from the contract body you write; write-system-contract.sh
    computes the authoritative content_hash from the written bytes and records it in the ledger.

    INCIDENT HISTORY (additive/advisory, bounded, deduped, this-run-only — see
    docs/RESULT_SCHEMAS.md §SYSTEM_CONTRACT). For EACH touched subsystem you derive a contract for:
      1. Read the subsystem's EXISTING contract FIRST to recover any prior incident_history:
           bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-system-contract.sh --subsystem '<id>'
         Graceful: if none / not verified / no prior incident_history, start from the empty list [].
      2. If the This-run incident map above has an entry for THIS subsystem id, APPEND one new
         incident_history entry PER mapped incident to the (prior) list:
           {date: "{run_iso8601}", kind: <kind from map>, summary: "<summary from map>", source: "{session-id}"}
         If the map has NO entry for this subsystem, carry the prior list UNCHANGED (never fabricate).
      3. DEDUPE: do not add an entry identical in kind+summary+source to one already present.
      4. BOUND: keep only the most recent 5 entries. The list is chronological oldest-first —
         always APPEND new entries at the end (step 2) and drop from the FRONT so the newest entry
         is always the last line (the Launch Pad reader, ST3, treats the last line as most recent).
      5. Write the merged list into the contract body using EXACTLY this on-disk shape — one entry
         per line as an inline YAML flow-map (HARD contract with the Launch Pad reader, ST3):
           incident_history:
             - {date: "<ISO8601>", kind: <conformance_violation|self_heal_fix|other>, summary: "<short text>", source: "<session-id>"}
         Omit the `incident_history:` key entirely when the merged list is empty.
      This is additive (schema_version stays 1), advisory, bounded, deduped, and this-run-only —
      NEVER a gate, NEVER backfilled.

    Write each contract from THIS pinned repo-root CWD via:
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-system-contract.sh \\
           --subsystem '<id>' --contract-file <tmpfile> --source '<session-id>'

    HARD RULES:
    - Run write-system-contract.sh ONLY from the repo-root CWD. It REFUSES (exit 3) from a linked
      git worktree (the sole-writer / pinned-CWD guard). Worktrees were already removed by Phase 4
      FINALIZE, so the repo root is the natural and correct location — do NOT cd into any worktree.
    - This is advisory/propose-only. A non-zero exit from the writer (e.g. exit 0 no-op when no sha
      tool, exit 2 bad call) MUST NOT fail the task — log it and continue.
    - Do NOT write .supervisor/state.md or any other state; the twin store is owned solely by
      write-system-contract.sh, and Context-Keeper is NOT in this path.

    Emit a one-line summary: how many contracts written / skipped."
)
```

- **Context-Keeper is explicitly OUT of this path** — it neither writes nor gates `.supervisor/twin/`; the twin store's sole writer is `write-system-contract.sh`, whose worktree guard is the real enforcement.
- **Pinned repo-root CWD, never a worktree** — `write-system-contract.sh` exits 3 from a linked worktree; Phase 4 FINALIZE already removed the worktrees.
- **Failure is non-fatal** — log `record_decision(phase: SELF_HEAL, decision: "twin_builder: {n} written / {m} skipped", rationale: "advisory — non-fatal")` and proceed; the builder NEVER changes `heal_decision`, NEVER blocks the PR, and runs AFTER the PR exists.

---

### Advisory Twin delta line (informational ONLY)

Print one human-readable line summarizing THIS run's Twin hard signal from the `contract_conformance` / `benchmark_result` values computed above — a pure echo of `format-twin-delta.sh` output that NEVER changes `heal_decision`, the PR, or control flow. The script always exits 0; with no Twin signal this run it prints a benign `Twin: no signal this run` (or pass `--from-session-end` the session_end line instead).
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/format-twin-delta.sh" \
  --conformance-status "{contract_conformance.status}" \
  --violations "{contract_conformance.violations}" \
  --benchmark-status "{benchmark_result.status}" \
  --benchmark-name "{benchmark_result.name}" \
  --benchmark-metric "{benchmark_result.metric}" \
  --benchmark-value "{benchmark_result.value}" \
  --benchmark-delta "{benchmark_result.delta}"
# echo the single line into the Phase 4.5 output (advisory). Never gates.
```

---

### Hard-signal dual emission (ST3 — written in BOTH shapes)

The contract-conformance, benchmark and ground-truth results are emitted as **the same data in two shapes** (`docs/RESULT_SCHEMAS.md` §"`session_end` JSONL hard-signal fields"):

1. **Nested objects on `SUPERVISOR_RESULT`** (completion-tail step 5; block definition in `agents/supervisor.md` §"Result Block (SUPERVISOR_RESULT)"): `contract_conformance`, `benchmark_result`, `ground_truth`. Optional/additive — `schema_version` stays `1`.
2. **FLAT scalar fields on the `session_end` JSONL event** in `.supervisor/logs/{session_id}.jsonl` — what `build-insights.sh` (ST4) aggregates via `select(.event=="session_end")`; write all of them with the SAME data. **These flat field names are a hard contract with ST4 — do NOT rename them:**

   | flat `session_end` field | from nested |
   |--------------------------|-------------|
   | `contract_conformance_status` | `contract_conformance.status` |
   | `contract_violations` | `contract_conformance.violations` |
   | `benchmark_status` | `benchmark_result.status` |
   | `benchmark_metric` | `benchmark_result.metric` |
   | `benchmark_value` (number\|null) | `benchmark_result.value` |
   | `benchmark_delta` (number\|null) | `benchmark_result.delta` |
   | `ground_truth_status` | `ground_truth.status` |
   | `ground_truth_checks_total` | `ground_truth.checks_total` |
   | `ground_truth_checks_passed` | `ground_truth.checks_passed` |
   | `ground_truth_pass_rate` (string "M/N") | the runner's `pass_rate` — FLAT ONLY: never a key of the nested `ground_truth` |

   **Nested shapes, exactly (`/automate` `sidecar-check` fails any other key set; `docs/result-schemas/supervisor-result.md` "Nested-object key sets"):** the flat table above maps nested → flat and never the reverse, so no flat-only field (`pass_rate` / `ground_truth_pass_rate`) is ever copied into a nested object.
   - `ground_truth: {checked: <bool>, status: <s>, checks_total: <n>, checks_passed: <n>, findings: [...]}` — `checked` is ALWAYS present (`gt.ran`), including on `status: pass`. Write it by copying the runner's `GROUND_TRUTH_NESTED:` line verbatim — it is already this shape.
   - `contract_conformance: {checked: <bool>, status: <s>, contracts_evaluated: <n>, violations: <n>, findings: [...]}`.
   - `benchmark_result: {ran, status, name, metric, value, baseline, delta, unit}` — on a parse miss `{ran: false, status: unverified}`.
   - **Skip form** (nothing to check): `ground_truth: {checked: false, status: skipped}` / `contract_conformance: {checked: false, status: skipped}` (or `status: unverified`) — complete as written; the counts and `findings` may be written as `0` / `[]` or omitted.

   **Findings-per-item fields (iq02 IQ01, additive, same value and name in both shapes):** `heal_first_decision` (the loop's first `iter_decision` — `PASS` / `FAIL` / `NEEDS_HUMAN`) and `heal_new_findings` (`category: new` `review.issues` summed over every iteration) — both `null` when `heal_loop_ran == false`; REPORT-ONLY, never read by the loop, never change `heal_decision`.

   Base `session_end` shape: `skills/state-management/SKILL.md` §"Session Logging (moved from agents/supervisor.md)". The flat fields are additive — readers treat absent as "not reported this session" (absent `ground_truth_*` as `skipped`).

The phase **Output** block (the `### Phase 4.5: SELF_HEAL` report format) also stays in
`agents/supervisor.md` — emit it as specified there.
