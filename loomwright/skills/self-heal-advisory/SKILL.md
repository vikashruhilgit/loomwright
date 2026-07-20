---
name: self-heal-advisory
description: Supervisor Phase 4.5 protocol authority. Part 1 — advisory-only machinery (pre-review enrichments, System Twin conformance/benchmark/ground-truth, contract-builder WRITE path, delta line, hard-signal dual emission; never changes heal_decision or blocks the PR). Part 2 — the full Phase 4.5 SELF_HEAL loop protocol (on-entry actions, base-mismatch cleanup, bounded review-and-fix loop, rubric grading, red-team lens, completion-tail procedure), Read on demand at Phase 4.5 entry, deliberately not preloaded.
version: "1.3.0"
lastUpdated: 2026-07-20
---

# Self-Heal Protocol (Supervisor Phase 4.5)

This skill is the **Phase 4.5 protocol authority**, in two parts:

- **Part 1 (below)** — the **advisory-only machinery**: pre-review enrichments
  (`prior_churn` / `area_knowledge` / `house_rules`), System Twin
  conformance/benchmark/ground-truth checks, the contract-builder WRITE path, the
  advisory Twin delta line, and hard-signal dual emission. Nothing in Part 1 ever
  changes `heal_decision` or blocks the PR.
- **Part 2 (bottom of this file)** — the **Phase 4.5 SELF_HEAL loop protocol**, moved
  verbatim from `agents/supervisor.md`: on-entry actions, base-mismatch cleanup, the
  bounded review-and-fix loop, Outcomes Rubric grading, the advisory red-team lens,
  fix-task crash handling, and the completion-tail procedure.

`agents/supervisor.md` keeps the load-bearing gate surface visible in the agent prompt —
the short Phase 4.5 stanza (entry/exit conditions, mandate, invariant tracking), the
VERBATIM completion-tail guard, the phase Output block, and the SUPERVISOR_RESULT block
definition — and points here for the procedure.

**Scope guard:** for the STANDALONE review→fix→re-review machinery keyed off a PR URL
(`/review-pr`), the extracted-contract authority remains `skills/review-heal/SKILL.md`.
Part 2 here is the Supervisor-embedded Phase 4.5 instance of that loop.

**HARD ADVISORY CONTRACT (applies to every step in Part 1):** nothing in Part 1 ever
changes `heal_decision`, triggers a fix iteration, blocks the PR, or fails the task.
Every failure path is non-fatal: log via `record_decision(...)` and continue. Under
tool-budget pressure (YELLOW/RED zones), Part 1 steps are the FIRST to skip — the gates
still run (Part 2's review-and-fix loop + the completion-tail guard in
`agents/supervisor.md`).

**When to read this file:** the Supervisor reads it ONCE at Phase 4.5 entry (it is
deliberately NOT in the Supervisor's preloaded `skills:` list — preloading would
re-inject ~950 lines into every session; on-demand reading keeps the agent prompt
focused on gates).

---

# Part 1 — Advisory machinery

## Prior-churn advisory (pre-review enrichment)

Unlike the three post-review checks below (which run AFTER the Code Reviewer loop has
completed), this advisory runs **at Phase 4.5 entry, BEFORE the first Code Reviewer
spawn** — because its sole purpose is to enrich the reviewer prompt. It feeds the
prior-churn miss-classes of the integrated diff's touched files into the Code Reviewer
prompt so the self-heal review prioritizes sweeping for root-cause classes that have
**churned before on those same files** (recurring `self_heal_miss` / root-cause classes /
flow stages mined from the postmortem corpus).

> **HARD ADVISORY CONTRACT — `prior_churn` is advisory input to the REVIEW lens ONLY.**
> Exactly like the contract-conformance / benchmark / ground-truth checks and the Rubric
> Grader, `prior_churn` is **advisory only**: it **NEVER changes `heal_decision`**,
> **NEVER drives the fix task** (the corpus is NOT passed to workers/fixers — only the
> Code Reviewer prompt receives the summary, per the roadmap non-goal), **NEVER triggers a
> fix iteration on its own**, and **NEVER gates or blocks the PR**. It is **fail-safe**:
> the reader (`read-postmortem.sh`) ALWAYS exits 0, and on empty output the phase proceeds
> with **no enrichment** (the reviewer prompt simply omits the prior-churn line). The reader
> emits **EMPTY output on a NO-HIT** (corpus present but no touched-path overlap) — it does
> NOT print a "no prior churn" sentinel line — so an empty `prior_churn` reliably means
> "no prior churn" and the enrichment is omitted; a non-empty `prior_churn` always denotes a
> real hit. (Never thread a "no prior churn recorded" string into the reviewer prompt.) Under
> tool-budget pressure this step is among the first to skip — the gates still run
> (Part 2's review-and-fix loop + the completion-tail guard in `agents/supervisor.md`).

```
# touched files = the same integrated-diff scope the Code Reviewer reviews. When
# BASE_BRANCH==main this is `git diff origin/main...HEAD`; for a stacked iteration
# (BASE_BRANCH != main) it is `git diff $BASE_BRANCH...HEAD` — the SAME DIFF-SCOPE OVERRIDE.
touched = paths from the integrated diff (read-only):
          BASE_BRANCH==main  -> git diff --name-only origin/main...HEAD
          BASE_BRANCH!=main  -> git diff --name-only $BASE_BRANCH...HEAD

prior_churn = ""   # advisory summary; empty string when no prior churn (proceed with no enrichment)

# Pass the touched paths as COMMAND-LINE ARGUMENTS (args take precedence — STDIN is NEVER
# read, so an args-bearing call can never block on an open-but-idle pipe in a non-TTY agent
# context). NEVER pipe the paths on stdin. See ${CLAUDE_PLUGIN_ROOT}/scripts/read-postmortem.sh.
if touched is non-empty:
  prior_churn = bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-postmortem.sh" <touched files...>
  # The reader emits a bounded markdown summary ONLY on a REAL hit (recurring root-cause classes /
  # flow stages / self_heal_miss for files that churned before). On a NO-HIT (corpus present but no
  # overlap) OR absent/empty corpus OR missing jq it emits NOTHING — no sentinel line — and ALWAYS
  # exits 0. So an empty `prior_churn` reliably means "no prior churn": proceed with no enrichment.
  # Guard the reviewer-prompt enrichment on `prior_churn` being NON-EMPTY; never thread a
  # "no prior churn recorded" string into the prompt. Do NOT restate the reader's internals here.

record_decision(phase: SELF_HEAL, decision: "prior_churn: {non-empty | empty}", rationale: "advisory pre-review enrichment — heal_decision unchanged, fixers never see the corpus")
```

`prior_churn` is threaded into the `code-reviewer` Task prompt as advisory, non-gating
context (the exact prompt line lives in Part 2 §"Review-and-fix loop" below).
It is NOT emitted as a SUPERVISOR_RESULT field and does NOT bump `schema_version` — it is
additive prose enrichment of the reviewer prompt only.

---

## Area-knowledge advisory (graph-community bridge)

A **sibling** to the "Prior-churn advisory (pre-review enrichment)" section above — it runs
at the SAME point (**Phase 4.5 entry, BEFORE the first Code Reviewer spawn**) on the SAME
integrated-diff touched-file scope, and enriches the SAME reviewer prompt. Where prior-churn
joins by EXACT path against the postmortem corpus, this advisory joins by **graph community**
against the pre-built findings→community **bridge** (`read-bridge.sh`): touched paths →
communities → the prior recorded findings / churn / lessons for those communities. The
community join catches a near-miss touched path that exact-path matching drops, so the
self-heal review gets area knowledge even when `prior_churn` is empty for those files. It is
the community-level companion to `read-postmortem.sh`'s exact-path read — see the shared seam
in `skills/brain-context/SKILL.md` §"Bridge read (area knowledge)".

> **HARD ADVISORY CONTRACT — `area_knowledge` is advisory input to the REVIEW lens ONLY.**
> Exactly like `prior_churn`, the contract-conformance / benchmark / ground-truth checks, and
> the Rubric Grader, `area_knowledge` is **advisory only**: it **NEVER changes `heal_decision`**,
> **NEVER drives the fix task** (the bridge corpus/index is NOT passed to workers/fixers — only
> the Code Reviewer prompt receives the summary, keeping the two review lenses independent),
> **NEVER triggers a fix iteration on its own**, and **NEVER gates or blocks the PR**. It is
> **fail-safe**: the reader (`read-bridge.sh`) ALWAYS exits 0, and on empty output the phase
> proceeds with **no enrichment** (the reviewer prompt simply omits the area-knowledge line).
> The reader emits **EMPTY output on a NO-HIT** (bridge present but no touched-path overlaps any
> finding-bearing community) — it does NOT print a "no area knowledge" sentinel line — so an
> empty `area_knowledge` reliably means "no area knowledge" and the enrichment is omitted; a
> non-empty `area_knowledge` always denotes a real hit. (Never thread a "no area knowledge
> recorded" string into the reviewer prompt.) Under tool-budget pressure (YELLOW/RED zones) this
> step is among the FIRST to skip — the gates still run (Part 2's review-and-fix loop + the completion-tail guard in `agents/supervisor.md`).

```
# touched files = the same integrated-diff scope the Code Reviewer reviews (and the same the
# prior-churn advisory above uses). When BASE_BRANCH==main this is `git diff origin/main...HEAD`;
# for a stacked iteration (BASE_BRANCH != main) it is `git diff $BASE_BRANCH...HEAD` — the SAME
# DIFF-SCOPE OVERRIDE.
touched = paths from the integrated diff (read-only):
          BASE_BRANCH==main  -> git diff --name-only origin/main...HEAD
          BASE_BRANCH!=main  -> git diff --name-only $BASE_BRANCH...HEAD

area_knowledge = ""   # advisory summary; empty string when no area knowledge (proceed with no enrichment)

# Pass the touched paths as COMMAND-LINE ARGUMENTS (args take precedence — STDIN is NEVER read,
# so an args-bearing call can never block on an open-but-idle pipe in a non-TTY agent context).
# NEVER pipe the paths on stdin. read-bridge.sh self-gates on .supervisor/bridge/bridge.json — it
# is called UNCONDITIONALLY (NOT wrapped in any "if a brain is detected" / graph-presence
# conditional), exactly like read-postmortem.sh self-gates on the postmortem corpus.
# See ${CLAUDE_PLUGIN_ROOT}/scripts/read-bridge.sh.
if touched is non-empty:
  area_knowledge = bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-bridge.sh" <touched files...>
  # The reader emits a bounded markdown advisory ONLY on a REAL hit (touched paths fall in a
  # community with prior recorded findings / churn / lessons). On a NO-HIT (bridge present but no
  # overlap) OR absent graph/bridge OR missing jq it emits NOTHING — no sentinel line — and ALWAYS
  # exits 0. A *stale* graph (HEAD past built_at_commit) is NOT a no-op — it still emits, with a
  # one-line "treat as a hint — graph may be stale" caveat. So an empty `area_knowledge` reliably
  # means "no area knowledge": proceed with no enrichment. Guard the reviewer-prompt enrichment on
  # `area_knowledge` being NON-EMPTY; never thread a "no area knowledge recorded" string into the
  # prompt. Do NOT restate the reader's internals here.

record_decision(phase: SELF_HEAL, decision: "area_knowledge: {non-empty | empty}", rationale: "advisory pre-review enrichment (graph-community bridge) — heal_decision unchanged, fixers never see the corpus")
```

`area_knowledge` is threaded into the `code-reviewer` Task prompt as advisory, non-gating
context (the exact **AREA-KNOWLEDGE ADVISORY** prompt line lives in Part 2
§"Review-and-fix loop" below, included only when non-empty). The bridge read counts under the
existing `brain_context` tag in `knowledge_sources_used` (the bridge IS the brain-context
read path — see `skills/brain-context/SKILL.md` §"Bridge read (area knowledge)") — it does NOT introduce a new
tag and does NOT bump `schema_version`; it is additive prose enrichment of the reviewer
prompt only.

---

## House-rules advisory (committed convention enrichment)

A **sibling** to the "Prior-churn advisory (pre-review enrichment)" and "Area-knowledge
advisory (graph-community bridge)" sections above — it runs at the SAME point (**Phase 4.5
entry, BEFORE the first Code Reviewer spawn**) on the SAME integrated-diff touched-file scope,
and enriches the SAME reviewer prompt. Where prior-churn joins by EXACT path against the
postmortem corpus and area-knowledge joins by graph community against the bridge, this advisory
reads the committed **house-rules substrate** (`.agent/rules/*.json`) via `read-rules.sh` and
threads the surviving valid team conventions into the reviewer prompt as a bias for the review
lens. It is the house-rules companion to `read-postmortem.sh` / `read-bridge.sh` — see the
substrate + reader contract in `skills/rules/SKILL.md`.

> **HARD ADVISORY CONTRACT — `house_rules` is advisory input to the REVIEW lens ONLY.**
> Exactly like `prior_churn` / `area_knowledge`, the contract-conformance / benchmark /
> ground-truth checks, and the Rubric Grader, `house_rules` is **advisory only**: it **NEVER
> changes `heal_decision`**, **NEVER drives the fix task** (the rules text is NOT passed to
> workers/fixers via this seam — only the Code Reviewer prompt receives it, keeping the review
> lens independent), **NEVER triggers a fix iteration on its own**, and **NEVER gates or blocks
> the PR**. It is **subordinate to CLAUDE.md — on any conflict, CLAUDE.md wins.** It is
> **fail-safe**: the reader (`read-rules.sh`) ALWAYS exits 0, and on empty output the phase
> proceeds with **no enrichment** (the reviewer prompt simply omits the house-rules line). The
> reader emits **EMPTY output on no valid rule** (substrate absent, no `*.json`, or zero valid
> rules survive) — it does NOT print a "no rules" sentinel line — so an empty `house_rules`
> reliably means "no house rules" and the enrichment is omitted; a non-empty `house_rules`
> always denotes at least one surviving valid rule. (Never thread a "no house rules recorded"
> string into the reviewer prompt.) The reader emits each rule's `check` as **DATA (text) only —
> it NEVER executes, evals, sources, or `bash -c`s a `check`**; this seam calls the READER ONLY
> and NEVER pipes/evals/sources the reader output. Under tool-budget pressure (YELLOW/RED zones)
> this step is among the FIRST to skip — the gates still run (Part 2's review-and-fix loop + the completion-tail guard in `agents/supervisor.md`).

```
# touched files = the same integrated-diff scope the Code Reviewer reviews (and the same the
# prior-churn / area-knowledge advisories above use). When BASE_BRANCH==main this is
# `git diff origin/main...HEAD`; for a stacked iteration (BASE_BRANCH != main) it is
# `git diff $BASE_BRANCH...HEAD` — the SAME DIFF-SCOPE OVERRIDE.
touched = paths from the integrated diff (read-only):
          BASE_BRANCH==main  -> git diff --name-only origin/main...HEAD
          BASE_BRANCH!=main  -> git diff --name-only $BASE_BRANCH...HEAD

house_rules = ""   # advisory summary; empty string when no valid house rules (proceed with no enrichment)

# Pass the touched paths as COMMAND-LINE ARGUMENTS (args take precedence — STDIN is NEVER read,
# so an args-bearing call can never block on an open-but-idle pipe in a non-TTY agent context).
# NEVER pipe the paths on stdin. read-rules.sh self-gates on .agent/rules/*.json — call it
# UNCONDITIONALLY (NOT wrapped in any "if a rules store is detected" conditional), exactly like
# read-postmortem.sh / read-bridge.sh self-gate. See ${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh.
#
# v1 NOTE (forward-compat call shape): in v1 the house-rules substrate applies REPO-WIDE —
# read-rules.sh emits ALL valid rules regardless of the touched paths (the `applies_to` field is
# INERT / reserved for slice 3b-ii enforcement filtering). STILL pass the diff scope as args, both
# for forward-compat (so path filtering wires in with no seam change) and to keep the args-not-stdin
# no-hang call shape identical to the two advisories above. The reader NEVER executes a `check` —
# checks are surfaced as DATA only.
house_rules = bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" <touched files...>
  # The reader emits a bounded advisory markdown block (subordinate-to-CLAUDE.md header + one bullet
  # per surviving valid rule, `must` rules flagged, each `check` shown as DATA text) ONLY when >=1
  # valid rule survives. On no valid rule (absent substrate / no *.json / all skipped) OR missing jq
  # it emits NOTHING — no sentinel line — and ALWAYS exits 0. So an empty `house_rules` reliably means
  # "no house rules": proceed with no enrichment. Guard the reviewer-prompt enrichment on `house_rules`
  # being NON-EMPTY; never thread a "no house rules recorded" string into the prompt. Do NOT restate
  # the reader's internals here.

record_decision(phase: SELF_HEAL, decision: "house_rules: {non-empty | empty}", rationale: "advisory pre-review enrichment (committed house rules) — heal_decision unchanged, subordinate to CLAUDE.md, fixers never act on it as a gate")
```

`house_rules` is threaded into the `code-reviewer` Task prompt as advisory, non-gating
context (the exact **HOUSE-RULES ADVISORY** prompt line lives in Part 2
§"Review-and-fix loop" below, included only when non-empty). It is NOT emitted as a SUPERVISOR_RESULT
field and does NOT bump `schema_version` — it is additive prose enrichment of the reviewer
prompt only, subordinate to CLAUDE.md.

---

## Post-review advisory checks

Run all three after the Code Reviewer loop has completed (regardless of
`heal_decision`); they populate the `contract_conformance`, `benchmark_result`, and
`ground_truth` objects consumed by the completion-tail "Emit SUPERVISOR_RESULT" step (step 5) in Part 2 below.

### Contract-conformance check (READ path — runs after the Code Reviewer pass)

After the Code Reviewer loop has run (regardless of `heal_decision`), check the **integrated feature-branch diff** against any existing System Contracts for the touched subsystems. This produces the `contract_conformance` object on `SUPERVISOR_RESULT` (and the matching flat `session_end` fields — see "Hard-signal dual emission" below).

> **HARD ADVISORY CONTRACT — this check NEVER changes a gate.** Exactly like the Rubric Grader, the contract-conformance check is **advisory only**: it **NEVER changes `heal_decision`**, **NEVER triggers a fix iteration**, and **NEVER blocks the PR**. Its findings carry `severity: info | advisory` by construction — never `blocking`/`high`. It is reported in `SUPERVISOR_RESULT` for human review and aggregated by ST4; it is not a quality gate. It runs read-only against committed state and dispatches no fixes.

```
# touched subsystems = the files/paths in the integrated diff (the same scope the Code Reviewer
# reviewed). When BASE_BRANCH==main this is `git diff origin/main...HEAD`; for a stacked iteration
# (BASE_BRANCH != main) it is `git diff $BASE_BRANCH...HEAD` — same DIFF-SCOPE OVERRIDE the reviewer used.
touched = paths from the integrated diff (read-only):
          BASE_BRANCH==main  -> git diff --name-only origin/main...HEAD
          BASE_BRANCH!=main  -> git diff --name-only $BASE_BRANCH...HEAD

contract_conformance = { checked: false, status: "skipped", contracts_evaluated: 0, violations: 0, findings: [] }

for each subsystem id derivable from `touched` (a path or a logical subsystem name):
  # read-side provenance gate; NEVER `cat` the contract files directly.
  contract = bash ${CLAUDE_PLUGIN_ROOT}/scripts/read-system-contract.sh --subsystem "<id>"
  if contract has a verified body (not "(no verified System Twin contracts)"):
    contract_conformance.checked = true
    contract_conformance.contracts_evaluated += 1
    # Compare the integrated diff against the contract's `invariants` / `behavioral_specs`.
    # Any apparent divergence is recorded as an ADVISORY finding (severity info|advisory only).
    for each invariant the diff appears to violate:
      contract_conformance.findings += { subsystem: "<id>", invariant: "<text>", severity: "advisory", detail: "<what in the diff diverges>" }

contract_conformance.violations = len(contract_conformance.findings)
if not contract_conformance.checked:
  # No verified contracts exist for any touched subsystem, OR read-system-contract.sh emitted nothing
  # (no sha tool / empty store). Graceful no-op.
  contract_conformance.status = "skipped"        # (use "unverified" instead when the tooling itself was unavailable)
elif contract_conformance.violations == 0:
  contract_conformance.status = "pass"
else:
  contract_conformance.status = "advisory_violations"

record_decision(phase: SELF_HEAL, decision: "contract_conformance: {status} ({violations} advisory)", rationale: "advisory only — heal_decision unchanged")
```

**Contract-conformance rules:**
- Absent contracts (empty `.supervisor/twin/`, or `read-system-contract.sh` emits nothing) → `checked: false`, `status: skipped` (or `unverified` if the tooling itself was unavailable), `contracts_evaluated: 0`, `violations: 0`. Graceful no-op — never an error, never a fix.
- `status: pass` requires `violations: 0`; `status: advisory_violations` requires `violations >= 1` and a non-empty `findings[]` (each `severity: info | advisory`).
- This is a READ of the twin store via `read-system-contract.sh` only — it NEVER writes the twin store (the WRITE happens in the completion tail, below).
- It runs on EVERY Phase 4.5 (PASS or ESCALATED); unlike the Rubric Grader it is not gated on PASS, because conformance reporting is informational and does not depend on trusting the code state.


### Benchmark run (populates `benchmark_result`)

Run the deterministic "provable-done" benchmark to populate `benchmark_result`:

```
bench = bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-benchmark.sh
# Parse the single `BENCHMARK_JSON: {...}` line -> benchmark_result (ran, status, name, metric,
# value, baseline, delta, unit). The script is deterministic, reads/writes its baseline under
# .supervisor/twin/benchmark-baseline.json (gitignored), and ALWAYS exits 0 — on any failure it
# emits status: unverified with value: null. Treat a parse miss as benchmark_result.ran=false,
# status: unverified. The benchmark is informational; it NEVER changes heal_decision or blocks the PR.
```

`run-benchmark.sh` does not update its baseline on a plain run (the `--update-baseline` flag is the sole write path, reserved for an explicit operator/maintainer baseline-set); Phase 4.5 invokes it WITHOUT that flag, so the heal loop measures-but-does-not-move the baseline.


### Ground-truth execution (M2b slice 1a — runs after the Code Reviewer pass)

After the Code Reviewer loop has run (regardless of `heal_decision`), execute the project-declared **executable acceptance checks** for this run and report whether they pass. This produces the `ground_truth` object on `SUPERVISOR_RESULT` (and the matching flat `session_end` fields — see "Hard-signal dual emission" below). Where the contract-conformance check reads the twin store and the benchmark validates the hard-signal fixtures, this runner executes the *actual acceptance checks the brief/project declares* and reports a hard PASS/FAIL signal. It runs on EVERY Phase 4.5 (PASS or ESCALATED), read-only against committed state, after the Code Reviewer loop — exactly like the contract-conformance block, it is NOT gated on PASS.

> **HARD ADVISORY CONTRACT — this check NEVER changes a gate.** Exactly like the contract-conformance check and the Rubric Grader, the ground-truth execution is **advisory only**: it **NEVER changes `heal_decision`**, **NEVER triggers a fix iteration**, and **NEVER blocks the PR**. Its findings carry `severity: advisory` by construction — never `blocking`/`high`. It is reported in `SUPERVISOR_RESULT` for human review and aggregated by ST4; it is not a quality gate. The runner ALWAYS exits 0 (a check's non-zero exit is a normal `fail` tally, never a script crash), so this step can never fail the phase.

```
# Resolve checks from the in-progress brief's `## Executable Acceptance` section (pass --brief),
# falling back to .supervisor/twin/ground-truth.json when the brief has no such section.
ground_truth = { checked: false, status: "skipped", checks_total: 0, checks_passed: 0, findings: [] }

# SAFETY VALVE (unattended/autonomous path): when NON_INTERACTIVE == true — i.e. this run was driven
# by /autonomous, where the brief's `## Executable Acceptance` section is MACHINE-AUTHORED by Launch
# Pad — pass --no-cmd so a `cmd:` bullet can NEVER run arbitrary shell with no human in the loop.
# --no-cmd skips cmd:/bare checks (recorded unverified/"cmd_disabled"); corpus-task: checks still run.
# This is the interim guard until the prompt-level Plan Reviewer control lands (M2b slice 1b — see
# docs/SPIKES/SYSTEM_TWIN_ROADMAP.md §7). In an interactive `/supervisor` run (human at Plan Review),
# cmd: bullets run normally.
NO_CMD_FLAG = (NON_INTERACTIVE == true) ? "--no-cmd" : ""
gt = bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-ground-truth.sh --brief <brief_path> $NO_CMD_FLAG
# Parse the single `GROUND_TRUTH_JSON: {...}` line. A parse miss → treat as
# ground_truth.checked=false, status:"unverified" (mirror the benchmark "treat a parse miss as
# unverified" rule). The runner always exits 0, so this can never fail the phase.

# Mapping from the runner's GROUND_TRUTH_JSON to the SUPERVISOR_RESULT ground_truth object:
ground_truth.checked       = gt.ran            # true when >=1 check actually executed
ground_truth.status        = gt.status         # pass | advisory_failures | unverified | skipped
ground_truth.checks_total  = gt.checks_total
ground_truth.checks_passed = gt.checks_passed
# findings[] = the FAILING per_check entries only (status == "fail"), mapped advisory-by-construction:
for c in gt.per_check where c.status == "fail":
  ground_truth.findings += { check: "<c.kind>:<c.target>",
                             detail: "<c.reason or 'exit non-zero'>",
                             severity: "advisory" }   # always "advisory" here (the schema enum [info, advisory] reserves "info"); NEVER blocking/high (mirror contract_conformance.findings)

record_decision(phase: SELF_HEAL, decision: "ground_truth: {status} ({checks_passed}/{checks_total})", rationale: "advisory only — heal_decision unchanged")
```

**Ground-truth execution rules:**
- The runner resolves checks from the brief's optional `## Executable Acceptance` section (priority) or `.supervisor/twin/ground-truth.json` (fallback). No source → `checked: false`, `status: skipped`, `0/0`, empty `findings[]`. Graceful no-op — never an error, never a fix.
- `status: pass` requires zero failing checks (and ≥1 check executed); `status: advisory_failures` requires ≥1 failing check and a non-empty `findings[]` (each `severity: advisory`); `status: unverified` is the fail-safe tooling path (no `jq`, or checks resolved but none could be verified — e.g. only deferred `qa-executor` checks).
- `qa-executor:` checks are recognized but DEFERRED to M2b slice 1b — the runner records them `unverified` (reason `qa_executor_dispatch_deferred_m2b_1b`) and they never block a `pass`. **Trust boundary (not a sandbox):** the runner itself does no repo writes and no network, but a `cmd:` check runs arbitrary `bash -c` with full shell privileges — so a `## Executable Acceptance` `cmd:` bullet is a trust-sensitive surface (review it at Plan Review, especially for `/autonomous`-generated briefs). `corpus-task` ids are constrained to a single path segment so they cannot escape `eval-corpus`.


---

### Contract builder (WRITE path — completion tail only)

**Runs only on a PASS outcome** (`heal_decision == PASS` or loop-skipped — i.e. the same outcomes that move the job to `done/` in completion-tail step 2, Part 2 below). On the ESCALATED / base-mismatch / invariant-violation paths, SKIP the builder (do not record contracts for a code state we did not pass). This is **propose-only, advisory, and reversible** — it writes the advisory twin store, never plugin code, never a gate.

**First, compute a per-subsystem incident map for THIS run** (advisory blast-radius history — see `docs/RESULT_SCHEMAS.md` §SYSTEM_CONTRACT `incident_history`). This map records ONLY incidents observed *this run* and is passed into the builder Task so it can append (never backfill) `incident_history` entries. Derive it from two sources already computed earlier in Phase 4.5:

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

A subsystem absent from `incident_map` has **no incident this run** → the builder must NOT add an entry for it (and must carry that subsystem's prior `incident_history` unchanged — never fabricate). `incident_history` is **additive / advisory, bounded, deduped, this-run-only**, NEVER a gate, NEVER backfilled, and `schema_version` stays `1` — consistent with the ST1 schema note in `docs/RESULT_SCHEMAS.md` §SYSTEM_CONTRACT.

Spawn an **ephemeral, Bash-capable builder Task** (a `general-purpose` Task — **NOT a new permanent agent**, NOT Context-Keeper) that derives one SYSTEM_CONTRACT per touched subsystem from the integrated feature-branch diff and writes each via `write-system-contract.sh`, passing `incident_map` so it can record this run's `incident_history`:

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

- **Context-Keeper is explicitly OUT of this path.** It remains the sole writer of `state.md` only; it neither writes nor gates `.supervisor/twin/`. The twin store's sole writer is `write-system-contract.sh`, whose worktree-guard is the real enforcement.
- **Pinned repo-root CWD, never a worktree.** `write-system-contract.sh` exits 3 from a linked worktree (top-level `.git` is a FILE, not a dir). By the completion tail, Phase 4 FINALIZE has already removed all worktrees and returned to the main checkout, so the repo root is both natural and correct.
- **Failure is non-fatal.** Any writer non-zero exit, missing-sha-tool no-op, or builder crash is logged via `record_decision(phase: SELF_HEAL, decision: "twin_builder: {n} written / {m} skipped", rationale: "advisory — non-fatal")` and the task proceeds. The builder NEVER changes `heal_decision`, NEVER blocks the PR, and runs AFTER the PR already exists.

---

### Advisory Twin delta line (informational ONLY)

Print one human-readable line summarizing THIS run's Twin hard signal, built from the
`contract_conformance` / `benchmark_result` values already computed above in this phase.
This is a pure echo of `format-twin-delta.sh` output — it NEVER changes `heal_decision`,
NEVER blocks or alters the PR, and NEVER affects control flow. The Supervisor result/gate
behavior is byte-identical with or without this line. The script always exits 0; when this
run produced no Twin signal (fields null/absent, e.g. Twin not exercised) it prints a benign
`Twin: no signal this run` (or pass `--from-session-end` the session_end line instead).

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

The contract-conformance result, the benchmark result, and the ground-truth result are emitted as **the same data in two shapes**, per `docs/RESULT_SCHEMAS.md` §"`session_end` JSONL hard-signal fields":

1. **Nested objects on `SUPERVISOR_RESULT`** (completion-tail step 5 in Part 2 below; block definition in `agents/supervisor.md` §"Result Block (SUPERVISOR_RESULT)"): `contract_conformance`, `benchmark_result`, and `ground_truth` (see the "Result Block" schema). Optional/additive — `schema_version` stays `1`.
2. **FLAT scalar fields on the `session_end` JSONL event** in `.supervisor/logs/{session_id}.jsonl` — this is what `build-insights.sh` (ST4) aggregates via `select(.event=="session_end")`. Write all of them, with the SAME data as the nested objects (field correspondence below). **These flat field names are a hard contract with ST4 — do NOT rename them:**

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
   | `ground_truth_pass_rate` (string "M/N") | the runner's `pass_rate` |

   See the `session_end` log line in `skills/state-management/SKILL.md` §"Session Logging (moved from agents/supervisor.md)" for the exact shape. The flat fields are additive — a `session_end` event without them remains valid (a reader treats absent fields as "not reported this session"; for the `ground_truth_*` fields a reader treats absent as `skipped`).

---

# Part 2 — Phase 4.5 SELF_HEAL Loop Protocol (moved from `agents/supervisor.md`)

> **Provenance & authority:** this Part is the Supervisor Phase 4.5 SELF_HEAL procedure, moved
> VERBATIM from `agents/supervisor.md` §"Phase 4.5: SELF_HEAL" (which keeps only the short phase
> stanza — Purpose / Entry / mandate / invariant tracking / exit conditions — plus the VERBATIM
> **completion-tail guard** and the phase **Output** block). Zero behavior change: every gate,
> error value, bound, and grep-stable string keeps identical semantics. The Supervisor Reads this
> file at Phase 4.5 entry (still NOT preloaded) and executes this Part as the protocol authority.
> Step numbering (on-entry steps 1–4, cleanup step 5, completion-tail steps 0–6 incl. 2.5 / 4.5 /
> 5.5) is preserved verbatim, so cross-file references to e.g. "Phase 4.5 step 5.5" remain valid —
> they now resolve here. The `SUPERVISOR_RESULT` block definition stays in `agents/supervisor.md`
> §"Result Block (SUPERVISOR_RESULT)"; the completion-tail guard (step 0) stays in the agent file —
> gates stay visible in the agent.

**Entry / skip semantics, the Phase 4.5 mandate, invariant-tracking summary, and exit conditions**
live in the `agents/supervisor.md` Phase 4.5 stanza — not restated here. Recap of the one
load-bearing entry rule: the phase ALWAYS runs after Phase 4 FINALIZE; `--skip-self-heal`
short-circuits the review-and-fix LOOP only — the phase transition and the completion tail
always execute.

**On-entry actions:**
1. Transition phase: `Context-Keeper(operation: update_phase, new_phase: SELF_HEAL, completed_phases: [..., FINALIZE])`
1a. Confirm the protocol read: `Read("${CLAUDE_PLUGIN_ROOT}/skills/self-heal-advisory/SKILL.md")` — this file (the Phase 4.5 stanza in `agents/supervisor.md` mandates the Read at phase entry, so executing this Part means it already happened). Part 1 above governs the System Twin advisory steps referenced later in this phase (deliberately NOT preloaded; one read at entry keeps the agent prompt gate-focused).
1b. **Brain consult (optional, on-demand):** if a brain is detected (`graphify-out/graph.json` present OR `LOOMWRIGHT_BRAIN_ROOT` set — see `skills/context-setup/SKILL.md` step 4.5), you MAY also `Read("${CLAUDE_PLUGIN_ROOT}/skills/brain-context/SKILL.md")` for graph-backed blast-radius context on the review (mirrors the on-demand, not-preloaded pattern of step 1a). This is **strictly advisory and fails SAFE** — it NEVER changes `heal_decision`, never gates the PR, and honors the staleness rule (the graph is authoritative only for committed code, never for files this run edited). Absent a brain, skip silently. (Equally available at Phase 1.5 / Phase 2 when reconciling work overlap.)
1c. **Prior-churn advisory (pre-review enrichment — ADVISORY ONLY, fail-safe):** run the **"Prior-churn advisory (pre-review enrichment)"** step from Part 1 of this skill (read at step 1a) to compute the `prior_churn` summary BEFORE the review-and-fix loop. It computes the integrated diff's touched files (`git diff --name-only "$BASE_BRANCH"...HEAD`, defaulting to `origin/main` when `BASE_BRANCH==main` — the SAME DIFF-SCOPE OVERRIDE the reviewer uses) and runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-postmortem.sh" <touched files...>` passing the paths as **command-line ARGUMENTS** (never stdin — an args-bearing call can never block). Capture its bounded markdown as the advisory `prior_churn` summary; **skip silently on empty output** (the reader always exits 0, so `prior_churn` simply stays empty and the reviewer prompt omits the enrichment line). This is **strictly advisory / fail-safe / non-gating** — `prior_churn` NEVER changes `heal_decision`, NEVER drives the fix task (the corpus is fed to the REVIEW lens ONLY, never to workers/fixers), and NEVER gates or blocks the PR. It is threaded into the `code-reviewer` Task prompt in the review-and-fix loop below as advisory context.
1d. **Area-knowledge advisory (graph-community bridge — pre-review enrichment, ADVISORY ONLY, fail-safe):** run the **"Area-knowledge advisory (graph-community bridge)"** step from Part 1 of this skill (read at step 1a) to compute the `area_knowledge` summary BEFORE the review-and-fix loop, as a sibling to step 1c. On the SAME integrated-diff touched-file scope (`git diff --name-only "$BASE_BRANCH"...HEAD`, defaulting to `origin/main` when `BASE_BRANCH==main` — the SAME DIFF-SCOPE OVERRIDE the reviewer uses), run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-bridge.sh" <touched files...>` passing the paths as **command-line ARGUMENTS** (never stdin — an args-bearing call can never block). Capture its bounded markdown as the advisory `area_knowledge` summary; **skip silently on empty output** (the reader always exits 0, so `area_knowledge` simply stays empty and the reviewer prompt omits the enrichment line). **Run this step UNCONDITIONALLY like step 1c — do NOT copy step 1b's "if a brain is detected" graph-presence gate into it.** `read-bridge.sh` self-gates on `.supervisor/bridge/bridge.json` (exactly as step 1c's `read-postmortem.sh` self-gates on the postmortem corpus), so no brain/graph-detection wrapper is needed or wanted. Steps **1b** (a live-graph blast-radius query, gated on Detection) and **1d** (a pre-computed community miss-history lookup, self-gating on the bridge) are **complementary, distinct signals** — not redundant. This is **strictly advisory / fail-safe / non-gating** — `area_knowledge` NEVER changes `heal_decision`, NEVER drives the fix task (the bridge index is fed to the REVIEW lens ONLY, never to workers/fixers — keeping the two review lenses independent), and NEVER gates or blocks the PR. The bridge IS the brain-context read path, so on a hit it counts under the existing `brain_context` tag in `knowledge_sources_used` (REUSE that tag — do NOT invent a new one — and do NOT bump any `schema_version`). It is threaded into the `code-reviewer` Task prompt in the review-and-fix loop below as advisory context (the **AREA-KNOWLEDGE ADVISORY** line, included only when `area_knowledge` is non-empty).
1e. **House-rules advisory (committed convention enrichment — pre-review enrichment, ADVISORY ONLY, fail-safe):** run the **"House-rules advisory (committed convention enrichment)"** step from Part 1 of this skill (read at step 1a) to compute the `house_rules` summary BEFORE the review-and-fix loop, as a sibling to steps 1c/1d. On the SAME integrated-diff touched-file scope (`git diff --name-only "$BASE_BRANCH"...HEAD`, defaulting to `origin/main` when `BASE_BRANCH==main` — the SAME DIFF-SCOPE OVERRIDE the reviewer uses), run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh" <touched files...>` passing the paths as **command-line ARGUMENTS** (never stdin — an args-bearing call can never block). Capture its bounded advisory markdown as the `house_rules` summary; **skip silently on empty output** (the reader always exits 0, so `house_rules` simply stays empty and the reviewer prompt omits the enrichment line). **Run this step UNCONDITIONALLY like steps 1c/1d — do NOT gate it on any "if a rules store is detected" conditional.** `read-rules.sh` self-gates on `.agent/rules/*.json` (exactly as `read-postmortem.sh` / `read-bridge.sh` self-gate on their corpora), so no detection wrapper is needed or wanted. **v1 call-shape NOTE:** in v1 the substrate applies REPO-WIDE — `read-rules.sh` emits ALL valid rules regardless of the touched paths (`applies_to` is inert / reserved for slice 3b-ii), but STILL pass the diff scope as args for forward-compat and the identical args-not-stdin no-hang shape. This is **strictly advisory / fail-safe / non-gating** — `house_rules` NEVER changes `heal_decision`, NEVER drives the fix task (the rules text is fed to the REVIEW lens ONLY via this seam, never to workers/fixers as a gate), and NEVER gates or blocks the PR. It is **subordinate to CLAUDE.md — on any conflict, CLAUDE.md wins.** This seam calls the READER ONLY — it NEVER pipes/evals/sources/`bash -c`s the reader output; each rule's `check` is surfaced as DATA (text) only, NEVER executed. Do NOT bump any `schema_version`. It is threaded into the `code-reviewer` Task prompt in the review-and-fix loop below as advisory context (the **HOUSE-RULES ADVISORY** line, included only when `house_rules` is non-empty).
2. **Initialize invariant tracking:**
   - `skip_self_heal_requested` — set from INIT-parsed flags (true iff `--skip-self-heal` was passed on the command line). Set once here, never mutated.
   - `phase45_review_invoked` — initialize to `false`. Flip to `true` only when the `code-reviewer` Task call below actually executes (first iteration of the review-and-fix loop).
   - `red_team_advisory` — initialize to `"disabled"` HERE, BEFORE the resume-thrash / `--skip-self-heal` early-jump checks below, so the completion-tail Outcome line always has a value even when this phase is bypassed and the Advisory red-team lens (further down) never runs. The lens overrides this to `ran` / `skipped_low_risk` / `error` (or re-affirms `disabled`) when it executes; on a bypass path it remains `"disabled"` (lens never ran).
3. **Resume-thrash guard (if this is a `--continue` run landing in SELF_HEAL):**
   - `Context-Keeper(operation: record_self_heal_resume, increment: true)` → reads the returned count
   - This is the ONLY place the resume counter is incremented: exactly once, at Phase 4.5 entry of a `--continue` run. A pause/crash earlier in the same run does NOT increment — the increment belongs to the next run's entry.
   - If count ≥ 3: abort the loop, mark task `completed_with_escalation` with reason `"self_heal_resume_thrash"`, skip to completion tail with `heal_loop_ran=true, heal_decision=ESCALATED, error: "self_heal_resume_thrash"`. Set `heal_remaining_issues` to the last known open-issue count from state (it may legitimately be 0 — the escalation result is valid because `error` is non-empty, per the SUPERVISOR_RESULT ESCALATED invariant). Do NOT set `phase45_review_invoked=true` based on a prior run's review — that flag tracks only the current run and is not persisted. `red_team_advisory` stays `"disabled"` (initialized in step 2 — the advisory lens lives later in this phase and is bypassed on this early jump).
4. Check `--skip-self-heal` flag: if set, record `record_decision(phase: SELF_HEAL, decision: "loop_skipped", rationale: "--skip-self-heal flag")` and jump to completion tail with `heal_loop_ran=false`. `red_team_advisory` stays `"disabled"` (initialized in step 2; the advisory red-team lens is part of this phase and is bypassed when self-heal is skipped).

5. **Phase 4.5 base-mismatch cleanup (v14.0.0, AC-7 — short-circuits the review-and-fix loop):**

   Before running the heal loop, check whether Phase 4 detected a base-branch mismatch:

   ```
   mismatch = Context-Keeper(operation: get_flag, key: "base_mismatch_detected")
   ```

   If `mismatch` is non-null (Phase 4 set the flag — either real mismatch or `gh pr view` failure under `--non-interactive`):

   1. **Close the orphan PR best-effort** (do not abort on failure — the PR may already be closed, or `gh` may still be unavailable):
      ```bash
      gh pr close "$PR_URL" --comment "Automatically closed by /autonomous loop: base branch mismatch detected — expected ${mismatch.expected}, found ${mismatch.actual}. See SUPERVISOR_RESULT for details. Reason: ${mismatch.reason}." || true
      ```
      Capture the exit code:
      - `0` → `PR_STATE="closed_by_loop"`
      - non-zero → `PR_STATE="close_attempt_failed"`
   2. **Move brief to `failed/`:** if `job:` parameter was used, move the brief from `.supervisor/jobs/in-progress/` → `.supervisor/jobs/failed/` and append an `## Outcome` block with `**Status:** failed`, `**Reason:** base_branch_mismatch`, `**Expected:** ${mismatch.expected}`, `**Actual:** ${mismatch.actual}`, `**PR state:** ${PR_STATE}`.
   3. **Record the decision:** `record_decision(phase: SELF_HEAL, decision: "base_mismatch_cleanup", rationale: "expected=${mismatch.expected}, actual=${mismatch.actual}, pr_state=${PR_STATE}")`.
   4. **Update state:** `Context-Keeper(operation: update_phase, new_phase: LOOP, completed_phases: [..., SELF_HEAL])` with task status `failed`.
   5. **Clear the flag (REQUIRED before returning, even on `gh pr close` failure — read-on-start-clear-on-start invariant):**
      ```
      Context-Keeper(operation: clear_flag, key: "base_mismatch_detected")
      ```
   6. **Reset resume counter:** `Context-Keeper(operation: record_self_heal_resume, increment: false)`.
   7. **Emit single `SUPERVISOR_RESULT` block** with:
      ```yaml
      SUPERVISOR_RESULT:
        schema_version: 1
        task_id: {task_id}
        status: failed
        pr_url: {PR_URL}
        branch: {feature_branch}
        branch_base: {mismatch.expected}    # the BASE_BRANCH we expected
        subtasks_completed: {N}
        subtasks_failed: 0
        heal_loop_ran: false
        heal_iterations: null
        heal_decision: null
        heal_fixable_issues_fixed: 0
        heal_remaining_issues: 0
        error: "base_branch_mismatch: expected ${mismatch.expected}, found ${mismatch.actual} (reason: ${mismatch.reason})"
        pr_state: {PR_STATE}                # "closed_by_loop" | "close_attempt_failed"
        summary: "Phase 4 self-verify detected PR base-branch mismatch; Phase 4.5 closed PR best-effort and moved job to failed/. No code changes were merged."
        cost_profile: {default|cheap|null}
        rubric_score: null
      ```
   8. **Return** from Phase 4.5 — do NOT run the review-and-fix loop, do NOT run the standard completion tail. This is a single exit point that emits exactly one `SUPERVISOR_RESULT`.

   **Field semantics:**
   - `branch_base` is the BASE_BRANCH we expected the PR to target. It is included so the autonomous-loop EVALUATE phase can detect the failure mode without re-parsing `error`.
   - `pr_state` is a new optional field on `SUPERVISOR_RESULT` (v14.0.0 — see schema update in S5). Values: `"closed_by_loop"` | `"close_attempt_failed"` | absent (when no PR action was taken).
   - On absent `gh` (`actual: null`), report `actual` as `null` in the error message and rely on the `reason` field to disambiguate (`gh_unavailable_non_interactive` vs `user_aborted_gh_retry`).

**Review-and-fix loop (runs only when flag is not set, thrash guard passed, AND no base-mismatch cleanup triggered):**

> The standalone equivalent of this loop (the same bounded review→fix→re-review machinery keyed off a PR URL, run by `/review-pr`) is documented in `skills/review-heal/SKILL.md` — that skill is the single source of truth for the extracted contract.

```
heal_iterations = 0
heal_fixable_issues_fixed = 0
max_heal_iterations = {--heal-iterations value, default 3}

while heal_iterations < max_heal_iterations:
  review = Task(
    subagent_type: "loomwright:code-reviewer",
    prompt: "**DIFF-SCOPE OVERRIDE (v14.0.0 stacked-iteration support):** if BASE_BRANCH is supplied below and differs from \"main\", you MUST compute the diff scope as `git diff $BASE_BRANCH...HEAD` and treat that as the entirety of your review scope. Do NOT fall back to `git diff origin/main...HEAD`, do NOT auto-expand to a consistency audit beyond this scope, and do NOT walk the file tree outside the changed files. This is a stacked-branch iteration N+1 review where the parent branch (BASE_BRANCH) already passed its own Phase 4.5 — only this iteration's incremental work is in scope. This directive supersedes the Code Reviewer's standard consistency_audit auto-expand behavior for stacked iterations.

             **DIFFERENT-LENS DIRECTIVE (non-stacked / BASE_BRANCH == \"main\" only — v14.21.0 self-heal hardening):** when BASE_BRANCH == \"main\" (the DIFF-SCOPE OVERRIDE above does NOT apply), this is the holistic post-PR review whose blind spots motivated this directive — a plain re-run of the same diff-scoped reviewer rubber-stamps the same classes it already missed per-subtask. Apply a DIFFERENT lens, not the same one again:
               1. **Run `consistency_audit` mode when self-repo trigger paths match.** If the integrated diff touches any of the `consistency_audit` trigger surfaces defined in `agents/code-reviewer.md`'s **Trigger rule** table (the single authoritative review-trigger taxonomy — do NOT restate the list here; a restated copy is exactly the cross-file drift this phase exists to catch), you MUST run in `review_mode: consistency_audit` (exhaustive cross-file analysis: every count, version string, mirrored prompt, and cross-reference), NOT a plain `diff_review`.
               2. **ALWAYS apply the Self-Heal Miss-Class Checklist regardless of repo.** On EVERY non-stacked heal review — plugin-self OR any external repo where the consistency_audit triggers do not fire — additionally apply the repo-agnostic \"Self-Heal Miss-Class Checklist\" in `skills/quality-checklist/SKILL.md` (backend/API validation mirrors every frontend-schema rule; no `||`/falsy coercion on numeric fields; no positional args to options-object functions; missing branch test coverage; count/version/restated-list drift; cross-reference precision drift). These are the classes that today only surface in 3–6 rounds of post-PR review; catch them here.

             **PRIOR-CHURN ADVISORY (non-gating — include this line ONLY when `prior_churn` is non-empty; omit entirely when empty):** these touched files have churned before with the following recurring root-cause classes — prioritize sweeping for those classes: {prior_churn summary}. This is advisory context, not a gate: it NEVER changes your `decision`, the Supervisor NEVER changes `heal_decision` because of it, it NEVER drives the fix task on its own, and it NEVER gates or blocks the PR. Use it to bias WHERE you look, not WHETHER the diff passes.

             **AREA-KNOWLEDGE ADVISORY (non-gating — include this line ONLY when `area_knowledge` is non-empty; omit entirely when empty):** the graph communities these touched files fall in carry the following prior recorded findings / churn / lessons — prioritize sweeping for those area-specific classes: {area_knowledge summary}. This is advisory context, not a gate: it NEVER changes your `decision`, the Supervisor NEVER changes `heal_decision` because of it, it NEVER drives the fix task on its own, and it NEVER gates or blocks the PR. Use it to bias WHERE you look, not WHETHER the diff passes.

             **HOUSE-RULES ADVISORY (non-gating — include this line ONLY when `house_rules` is non-empty; omit entirely when empty):** the project's committed house rules (`.agent/rules/`, read via `read-rules.sh`) carry the following team conventions — bias your review lens toward flagging diffs that diverge from them ({house_rules summary}). Each rule's `check` is DATA only — do NOT execute, eval, source, or `bash -c` any `check` value. This is advisory context, not a gate: it NEVER changes your `decision`, the Supervisor NEVER changes `heal_decision` because of it, it NEVER drives the fix task on its own, and it NEVER gates or blocks the PR. It is **subordinate to CLAUDE.md — on any conflict, CLAUDE.md wins.** Use it to bias WHERE you look, not WHETHER the diff passes.

             BASE_BRANCH={BASE_BRANCH value or \"main\"}

             Review the integrated feature branch holistically.
             Target: diff between BASE_BRANCH (defaults to origin/main when BASE_BRANCH==main) and {feature_branch}
             Focus: integration issues, cross-cutting concerns, consistency across files, AND the Self-Heal Miss-Class Checklist (see DIFFERENT-LENS DIRECTIVE above).
             Previous per-subtask reviews all passed — look for issues only visible in the integrated view.
             Schema: CODE_REVIEW_RESULT v3 (review_mode: diff_review for a plain integration review, or consistency_audit when self-repo trigger paths match per the DIFFERENT-LENS DIRECTIVE; category field: new/pre_existing/nit/drift).",
    model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default
  )
  phase45_review_invoked = true  # flipped once the code-reviewer Task actually ran
  # Parse CODE_REVIEW_RESULT block from review output

  if review.decision == PASS:
    heal_decision = PASS
    heal_remaining_issues = 0
    break

  if review.decision == NEEDS_HUMAN:
    heal_decision = ESCALATED
    heal_remaining_issues = count(review.issues where category=new AND severity in [BLOCKING, HIGH])
    post findings to PR as comment (gh pr comment)
    break

  # decision == FAIL — by CODE_REVIEW_RESULT rule, at least one new+HIGH/BLOCKING issue exists
  fixable_issues = [i for i in review.issues if i.category == "new" and i.severity in (BLOCKING, HIGH)]

  Task(
    subagent_type: "general-purpose",
    # Tool allowlist: Read, Write, Edit, Bash, Glob, Grep (no Task — fix agent may not dispatch further subagents)
    # Pointer-audit note (deliberate paste — see docs/POINTER_AUDIT.md): the findings list below is
    # NOT file-backed (CODE_REVIEW_RESULT exists only in the reviewer Task's transcript, never on
    # disk), is already bounded by construction (category=new + severity>=HIGH only), and the fix
    # worker provably needs each finding's full file:line + description + suggestion every time —
    # they ARE the work items. Keep the paste; do NOT write findings to a scratch file just to
    # point at it (that would add a write path to a review seam that has none).
    working_dir: main checkout on feature branch,
    prompt: "You are fixing a feature branch before review passes.
             Feature branch: {branch}
             PR: {pr_url}

             Code Reviewer findings to address (severity >= HIGH, category = new):
             {numbered list: file:line + description + suggestion}

             Task:
             1. Address each issue above. Prefer the reviewer's `suggestion` if provided.
             1a. **Fix the CLASS, not just the flagged instance (v14.21.0 self-heal hardening).** For each finding, name its *class* (e.g. \"numeric field coerced with `||`\", \"positional arg passed to an options-object function\", \"backend validation missing a rule the frontend schema enforces\", \"count/version/restated-list drift\", \"cross-reference precision drift\", \"new branch with no test\"). Then scan the FULL feature-branch diff (`git diff $BASE_BRANCH...HEAD`, BASE_BRANCH defaults to origin/main) for EVERY other occurrence of that same class and fix them all in this iteration — not only the one file:line the reviewer flagged. The reviewer samples; you must sweep. Stay within the changed surface — fix other instances of the SAME class introduced by this branch; do not refactor unrelated pre-existing code. **Occurrence cap (budget guard, v14.21.0):** if a single class has more than ~10 branch-introduced occurrences, fix a representative handful and REPORT the class with its full occurrence count + locations in `FIX_RESULT.summary` instead of sweeping all of them this iteration — so one finding cannot balloon an iteration's diff or burn the heal budget; the reported remainder is left for the next iteration's re-review or the human.
             2. Update tests if behaviour changes.
             3. Run type-check and tests locally before finishing.
             3a. **Pre-push self-regression review (anticipatory — REQUIRED, observable).** Before committing, re-read your OWN diff (`git diff $BASE_BRANCH...HEAD` plus your uncommitted changes) and confirm it introduces no downstream regression in **persistence / state / lifecycle / idempotency / concurrency** — e.g. a duplicated write (a split path that now `Save`s twice), changed ordering, a cross-session / cross-request collision (a shared counter or dedup key that now collides), a broken run-once guard, or a new check-then-act race. This is DISTINCT from the step-1a fix-the-class sweep (which sweeps *sibling* instances of the reviewer's finding) and from the Anti-Churn Guardrail (which trips on oscillation across rounds): step 3a re-examines *your own fix* for a regression it might have just introduced. If you find one, fix it in THIS same pass.
             4. Commit with message: \"fix: address review feedback (iteration {N})\"
             5. Do NOT address findings outside the listed classes. (You MUST fix other instances of the SAME class per step 1a; you must NOT chase unrelated findings.)
             6. Do NOT fix pre_existing issues or nits.

             Emit FIX_RESULT block: schema_version: 1, issues_addressed, files_modified, commit_sha, summary — and the `summary` MUST include an observable `self_review:` clause from step 3a naming the downstream-regression risk classes you checked (persistence / state / lifecycle / idempotency / concurrency) and the result (`self_review: clean` or `self_review: fixed-in-pass — <what>`). A FIX_RESULT whose summary has NO `self_review:` clause is an incomplete fix.",
    model: "sonnet"   # ONLY when cost_profile=cheap; omit entirely when cost_profile=default
  )
  # Parse FIX_RESULT; increment heal_fixable_issues_fixed by FIX_RESULT.issues_addressed
  # Self-review-note gate (v14.43.0): FIX_RESULT.summary MUST carry a `self_review:` clause naming the
  # downstream-regression risk classes the fixer checked (persistence/state/lifecycle/idempotency/
  # concurrency). If absent, treat the fix as INCOMPLETE — re-prompt the SAME fix worker once to perform
  # and report the pre-push self-review, or surface it for the next re-review. A missing note must never
  # silently pass as a finished fix. (Best-effort, observable; never --force, never merge.)

  git push  # update PR (regular push, NEVER --force)
  record_decision(phase: SELF_HEAL, decision: "fix iteration {heal_iterations+1}", rationale: FIX_RESULT.summary)

  heal_iterations += 1

# Loop exit
# Re-review guarantee (v14.21.0 self-heal hardening): every fix iteration's edits —
# INCLUDING the fix-the-class SWEEP from step 1a — are re-reviewed at the TOP of the next
# loop iteration (the `review = Task(...)` above). The only un-re-reviewed case is a
# fix/sweep on the FINAL allowed iteration: the loop then exits ESCALATED below and posts
# findings to the PR for human review. So a sweep never ships as a silent clean PASS — it
# is always either re-reviewed by the next iteration or surfaced to a human via ESCALATED.
# Budget tension (accepted): a large class-sweep also enlarges the next iteration's re-review
# diff, so it can consume heal iterations / reviewer call-budget faster — an accepted trade for
# breaking the post-PR review loop, kept bounded by step 1a's "within the changed surface"
# guardrail. (An auditable FIX_RESULT swept-instances field was considered and DEFERRED —
# premature schema growth on a still-soaking advisory instrument.)
if heal_iterations == max_heal_iterations AND review.decision != PASS:
  heal_decision = ESCALATED
  heal_remaining_issues = count(review.issues where category=new AND severity in [BLOCKING, HIGH])
  post findings to PR as comment (when a step-1a class-sweep ran on this FINAL iteration, the comment MUST also note: "class-sweep applied on the final heal iteration — its own edits were NOT re-reviewed; eyeball the swept files", so a human knows to check them)
```

**Multi-voter verification (`--multi-voter-heal` — OPT-IN, DEFAULT OFF; changes WHICH findings get fixed, not the gate shape):**

Resolved at Phase 0 INIT (`skills/supervisor-config/SKILL.md` preamble step 2.9, recorded as `MULTI_VOTER_HEAL`): `--multi-voter-heal` on the command line OR `.supervisor/config.json` `.multi_voter_heal: true` turns it ON; the flag wins over config, and `--no-multi-voter-heal` suppresses even a `true` config value. When `MULTI_VOTER_HEAL == false` (the default), the review-and-fix loop above runs EXACTLY as written — zero behavior change.

When ON, each iteration of the review-and-fix loop above changes in exactly two places:

1. **Two independent parallel reviewers (the vote).** The iteration's review step spawns TWO reviewers in parallel on the SAME integrated feature-branch diff (same DIFF-SCOPE OVERRIDE, same BASE_BRANCH):
   - the existing `loomwright:code-reviewer` Task — **unchanged contract, spawn prompt verbatim as above** (advisory enrichments included, `phase45_review_invoked` still flips on it). Its `CODE_REVIEW_RESULT` remains **THE gating signal**: the loop's PASS / NEEDS_HUMAN / FAIL branching and the `heal_decision` derivation stay keyed to it exactly as written above.
   - a `loomwright:red-team-reviewer` Task as an independent **verification voter** on the same diff scope. This is NOT the standalone advisory red-team lens (see the interaction sub-note below) — the voter runs INSIDE the loop, once per iteration, and its BLOCKING/HIGH-severity findings on this branch's newly-introduced surface (map its severity vocabulary to BLOCKING/HIGH; pre-existing issues stay out of scope, mirroring the `category=new` filter) enter the merge rule below. It votes on findings; it never decides the gate — `heal_decision` NEVER derives from its output (a surviving voter finding can only delay finalization within the existing bound; see the delay-vs-decide invariant below).
2. **Second-opinion refute check (the merge rule — decides WHICH findings get fixed).** Collect the iteration's BLOCKING/HIGH `new` findings from BOTH lenses. A finding triggers a fix task ONLY if it **survives a refute check by the OTHER lens**: ask the other lens — via at most ONE bounded refute spawn PER LENS per iteration (batch that lens's cross-findings into it), or by folding the refute question into the next combined prompt — whether each finding is a false positive, unreachable, or already handled; the refute step's ceiling is therefore ≤2 spawns per iteration (one per lens). Findings the other lens REFUTES are **LOGGED, NOT FIXED**: record each via `record_decision(phase: SELF_HEAL, decision: "multi_voter_refuted", rationale: "<finding> refuted by <lens>")` and include them in the PR comment, clearly labelled refuted/not-fixed. Findings that SURVIVE form the iteration's `fixable_issues` set fed to the fix task above (replacing the single-lens `fixable_issues` derivation for that iteration; the fix-task spawn contract is otherwise unchanged).

**Delay-vs-decide (the precise invariant):** `heal_decision` — the GATE — still derives ONLY from the code-reviewer's `CODE_REVIEW_RESULT` (PASS only from a code-reviewer PASS; ESCALATED on NEEDS_HUMAN / max iterations / thrash); the `--heal-iterations` bound, never-merge, the completion-tail guard, and the completion-tail procedure below are all IDENTICAL to the single-voter path. What the voter CAN do is extend LOOP CONTINUATION within that existing bound: a code-reviewer PASS becomes FINAL only once the iteration's surviving finding set is empty (or the bound escalates), so a surviving voter finding can DELAY finalization by another bounded fix-and-re-review iteration — it can never FLIP a decision (never turns a PASS into FAIL, nor a FAIL into PASS). Multi-voter edits the `fixable_issues` set and the finalization timing inside each iteration; nothing else. Edge rules:
- Code-reviewer PASS + zero surviving red-team findings → PASS, exactly as above.
- Code-reviewer PASS + ≥1 surviving red-team BLOCKING/HIGH finding → spawn a fix task on the surviving set and re-review next iteration (still bounded by `--heal-iterations`; the PASS becomes final only when the surviving set is empty or the bound escalates).
- Code-reviewer FAIL with ALL of its findings refuted (surviving set empty) → do NOT spawn a fix task and do NOT auto-PASS; exit the loop with `heal_decision = ESCALATED` and post the refutation log to the PR — a fully-refuted FAIL is a human call, never a silent pass.
- **Fail-safe degradation:** if the red-team voter (or a refute spawn) errors/times out, log one line via `record_decision` and degrade THAT iteration to the single-voter default above (code-reviewer findings fixed as written; unrefutable voter findings logged, not fixed). Never abort the run on the voter path.

**Per-run counters (additive prose — NO schema bump):** track across all iterations `findings_raised` (BLOCKING/HIGH `new` findings raised by either lens), `findings_refuted` (refuted → logged, not fixed), and `findings_fixed` (survived → dispatched to fix tasks), and carry them inside the `SUPERVISOR_RESULT` `summary` string (e.g. `multi_voter: findings_raised=3 findings_refuted=1 findings_fixed=2`) and the job `## Outcome` block — additive prose only, exactly the `red_team_advisory`-in-summary precedent; do NOT add a new `SUPERVISOR_RESULT` field; `schema_version` stays `1` (see `docs/RESULT_SCHEMAS.md` §SUPERVISOR_RESULT).

**Interaction with the standalone `--red-team` advisory lens (this sub-note is the ONE authority for the interaction — other surfaces cross-reference it, never restate it):**
- The standalone `--red-team` / `--no-red-team` advisory lens (further down in this Part) is **UNTOUCHED and fully independent**: it stays advisory-only, high-risk-only, non-gating, a single pass OUTSIDE the heal loop, resolved by its own `RED_TEAM_ENABLED` (supervisor-config step 2.7) — none of its semantics change whether multi-voter is ON or OFF.
- The flags do NOT alias each other: `--multi-voter-heal` does not enable the advisory lens, `--red-team` does not enable multi-voter, `--no-red-team` does not suppress the verification voter, and `--no-multi-voter-heal` does not suppress the lens.
- When BOTH are active, `red-team-reviewer` may legitimately be spawned twice in one Phase 4.5 with different roles: (1) the verification VOTER inside the loop (per-iteration; feeds the merge rule) and (2) the advisory LENS outside it (single pass, high-risk-only; never feeds any fix). Record their outcomes distinctly (the `multi_voter` counters vs `red_team_advisory`).

**Cost note:** multi-voter is ~2× review spawns per heal iteration (plus the bounded refute spawn). It stays opt-in / default-OFF and graduates to default ONLY if the `docs/SPIKES/FABLE_PARITY_EVAL.md` arm-3 runs show it earns its cost (fewer post-merge defects or review rounds without >1.5× token cost).

**Outcomes Rubric grading (v12.2.0+, runs only after Code Reviewer PASS):**

When the loop exits with `heal_decision == PASS` AND the in-progress brief contains an `## Outcomes Rubric` section (parse the section between the heading and the next `## ` heading; collect every leading-`-` bullet), spawn a Haiku grader to score the PR diff against each rubric item. This is a one-shot read-only evaluation; no fixes are dispatched off the rubric verdict.

```
rubric_bullets = parse_rubric(brief_path)   # [] if no ## Outcomes Rubric section

if heal_decision == PASS and rubric_bullets:
  # Invoke the registered rubric-grader agent. Spawning by `subagent_type` is
  # the reliable enforcement path for `model: haiku` — the Task tool ignores
  # `model:` keywords on the call site, but honors the frontmatter on
  # `agents/rubric-grader.md`. Read-only behavior at runtime is enforced by
  # the agent's `disallowedTools: Write, Edit, Task, NotebookEdit` plus the
  # prompt convention restricting Bash to read-only git inspection.
  # `permissionMode: plan` is preserved in the agent frontmatter for
  # ~/.claude/agents/ compatibility but is silently ignored by Claude Code
  # for plugin-distributed agents (see CLAUDE.md "Hook gotcha"); do not
  # rely on it as a runtime gate.
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

**Rubric grading rules:**
- Grader runs **only when `heal_decision == PASS`**. On ESCALATED or invariant-violation paths, `rubric_score = null` (the rubric is not evaluated against a code state we do not yet trust).
- Grader is **read-only and advisory** — a failing rubric item does NOT change `heal_decision`, does NOT trigger a fix iteration, and does NOT block the PR. It is reported in the SUPERVISOR_RESULT for human review.
- If the brief has no `## Outcomes Rubric` section: `rubric_score = null`. Backward-compatible — pre-v12.2.0 briefs continue to work unchanged.
- If parsing the grader output fails (no `rubric_score: N/M` line): record `record_decision(phase: SELF_HEAL, decision: "rubric_grader_parse_failed", ...)` and set `rubric_score = null`. Do NOT fail the task.
- Grader output is appended to the PR as a comment alongside the heal report (best-effort; comment failure does not fail the task).

**System Twin advisory checks (ADVISORY ONLY — protocol in Part 1 of this skill):**

After the Code Reviewer loop has run (regardless of `heal_decision`), execute the three System Twin advisory steps — **contract-conformance check** (READ of the twin store via `read-system-contract.sh`), **benchmark run** (`run-benchmark.sh`), and **ground-truth execution** (`run-ground-truth.sh --brief <brief_path>`, with `--no-cmd` when `NON_INTERACTIVE == true`) — following the full protocol in Part 1 §"Post-review advisory checks" above (read at Phase 4.5 entry; deliberately not preloaded). They populate the `contract_conformance`, `benchmark_result`, and `ground_truth` objects consumed by completion-tail step 5 below.

> **HARD ADVISORY CONTRACT:** none of these checks ever changes `heal_decision`, triggers a fix iteration, or blocks the PR. Every failure path (missing tooling, parse miss, failing check) is non-fatal — record it and continue. Under budget pressure (YELLOW/RED), skip these first; the gates still run.

**Integration-review invocation details:** Code Reviewer auto-detects Beads (`test -d .beads && bd --version`). When Beads is not active, the CODE_REVIEW_RESULT block is the sole output channel the Supervisor parses. See `agents/code-reviewer.md` "Detect Beads Integration" for full semantics.

**Advisory red-team lens (opt-in, high-risk-only — OPT-IN / DEFAULT-OFF / FAIL-SAFE / strictly NON-GATING):**

Runs AFTER the Code Reviewer holistic pass has produced its decision (and alongside / independent of the System Twin advisory checks), and BEFORE the completion tail. It is a SINGLE pass that lives **OUTSIDE the bounded fix loop** — never a new heal iteration. It is itself opt-in (default-OFF; `--red-team` / `.red_team_high_risk`), mirroring the paired-flag precedent of `--auto-review` / `--no-auto-review` (a `--flag` / `--no-flag` toggle backed by a `.supervisor/config.json` key — note the auto-review *dispatch* is default-ON, only its flag-pairing shape is the precedent), and applies a second, adversarial lens to high-risk integrated diffs.

```
# Guard: default path is a zero-behavior-change silent skip.
if RED_TEAM_ENABLED != true:
    red_team_advisory = "disabled"
    # skip silently — no spawn, no PR comment, no note beyond the one-word record below.
else:
    # High-risk classification — repo-agnostic heuristic computed from the integrated diff.
    diff_paths   = `git diff --name-only $BASE_BRANCH...HEAD`
    diff_content = `git diff $BASE_BRANCH...HEAD`
    changed_lines = added+removed line count of diff_content
    changed_files = count(diff_paths)

    high_risk = (
        # (a) security / financial / migration surfaces (path OR content, case-insensitive)
        any path/content matches (case-insensitive): *auth*, *authz*, *security*,
          *crypto*, *secret*, *token*, *payment*, migrations/ , *migration*
        # (b) workflow-automation / orchestration / cross-agent prompt surfaces —
        #     the roadmap's "workflow automation, or broad cross-agent prompt changes".
        #     In an agent-orchestration repo these prompt/automation contracts ARE the
        #     high-impact surface, so a SMALL diff here can still be high-risk; on a plain
        #     app repo these paths rarely appear, so this branch does not over-fire there.
        OR any changed path matches: .github/workflows/ , hooks/ , agents/ , commands/ , skills/
        OR any path/content matches (case-insensitive): workflow, automation, orchestration
        # (c) sheer size
        OR changed_lines > 400
        OR changed_files > 15
    )

    if not high_risk:
        red_team_advisory = "skipped_low_risk"
        # record a one-line note; do NOT spawn.
    else:
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
          # Post findings to the PR as a clearly-labelled NON-GATING comment.
          # Capture the exit status — a comment-post failure is a fail-safe no-op recorded as
          # "error" per the ADVISORY CONTRACT below, NOT silently masked as a successful "ran".
          # (Do NOT use a bare `|| true` here: it would swallow the failure and mis-record "ran".)
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

**ADVISORY CONTRACT (NON-NEGOTIABLE):**
- Red-team findings **NEVER change `heal_decision`**, **NEVER directly drive the fix task**, **NEVER block the PR or run**, and introduce **NO new gate**. The Code Reviewer's `CODE_REVIEW_RESULT` remains the **SOLE gating signal**.
- If the Code Reviewer INDEPENDENTLY also flags an issue the red-team raised as a `new` BLOCKING/HIGH, the EXISTING class-based fix path handles it — driven by `CODE_REVIEW_RESULT`, **not** by the red-team output. The red-team lens never feeds the fixer.
- **FAIL-SAFE (mirrors the CLAUDE.md "side-effect emitters fail SAFE" invariant):** any red-team spawn error/timeout, or any `gh pr comment` failure, is a **logged one-line no-op** — record `red_team_advisory = "error"` and CONTINUE. It MUST NOT propagate to `SUPERVISOR_RESULT.status`, MUST NOT raise the completion-tail guard, and MUST NOT abort the run.
- **Recording (no `schema_version` bump):** carry `red_team_advisory` (`ran` | `skipped_low_risk` | `disabled` | `error`) into `SUPERVISOR_RESULT.summary` and into the job's `## Outcome` block (e.g. `red_team_advisory: ran`). `disabled` covers BOTH "`RED_TEAM_ENABLED` was false" AND "the self-heal phase was bypassed (`--skip-self-heal` / resume-thrash) so the lens never ran" — the value is initialized to `"disabled"` at phase entry (step 2) so the Outcome line is never empty. This is an additive-optional note only — do NOT add a new required `SUPERVISOR_RESULT` field; `schema_version` stays `1`.

**Fix task crash handling:**
- If the fix Task() returns an error or no FIX_RESULT block: pause the phase by emitting `SUPERVISOR_RESULT` with `status: checkpoint` (the schema has no `paused` status — `checkpoint` is the pause analogue) and exit with the resume command. Do NOT increment the resume counter now — the increment happens at Phase 4.5 entry of the next `--continue` run (on-entry step 3).

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
     - **Red team findings:** {one-line risk/findings summary — include this line ONLY when `red_team_advisory == ran`; omit entirely otherwise. Mirrors the findings carried into `SUPERVISOR_RESULT.summary`; additive markdown only, no schema field.}
     - **Until-mergeable dispatched:** {true|false}
     - **Until-mergeable log:** {RUN_LOG path under .supervisor/logs/ — include this line ONLY when `until_mergeable_dispatched == true`; omit otherwise. Additive markdown only, no schema field. Resolved from the per-PR dispatch marker — the visible trail a branch-dependent downstream consumer reads to know a detached drain is in flight (AC8b).}
     - **Summary:** {brief description of what was done}
     ```
   - On ESCALATED: Move brief from `in-progress/` → `done/`, append outcome section with `**Status:** completed_with_escalation`, plus `**Heal reason:** {needs_human|max_iterations_reached|self_heal_resume_thrash}`, `**Heal remaining issues:** {count}`, and the same `**Red team advisory:** {ran|skipped_low_risk|disabled|error}` line (plus the `**Red team findings:**` one-liner when it ran) — the red-team lens runs before the completion tail regardless of `heal_decision`, so its outcome is recorded on both the PASS and ESCALATED paths.
   - Backward compatibility: If job file is not in `in-progress/`, skip the move step (direct `/supervisor task:` invocation without Launch Pad).

2.5. **Requirement close-out (Beads-absent only — fail-safe side-effect):**

   Runs on the SAME successful outcomes that move the brief to `done/` in step 2 — **PASS / loop-skipped / ESCALATED** (all three move the brief to `done/`, so all three close out the originating requirement). This step closes the requirement→brief→done loop for the Beads-optional flow: Launch Pad (the producer) stamps a `- **Source requirement:** {path}` line on the brief, and this step (the consumer) marks that originating requirement file done.

   This whole step is a **runtime side-effect emitter and MUST fail SAFE** per the CLAUDE.md bimodal-failure invariant: wrap the entire close-out so that ANY error (unreadable brief, missing file, write failure, malformed pointer) is a **logged no-op that NEVER propagates to `SUPERVISOR_RESULT.status` and NEVER fails the run**. It never gates, never alters the PR, never affects control flow — always continue to step 3 regardless of outcome.

   1. **Gate — successful outcome only:** this step runs ONLY on PASS / loop-skipped / ESCALATED. It MUST NOT run on the `failed` / abort / `checkpoint` / invariant-violation / base-mismatch-cleanup paths. **A failed run NEVER marks a requirement done** — those paths exit before this step. (The Phase 4.5 invariant-violation guard above and the base-mismatch cleanup path both exit without reaching here.)
   2. **Gate — Beads-absent only:** probe Beads activity using the existing Persistence-Mode / context-setup convention (`test -d .beads && bd --version`). If Beads is **ACTIVE → SKIP entirely** (no file write): `bd close BD-XX` is the sole source of truth for requirement state when Beads is active. Record `record_decision(phase: SELF_HEAL, decision: "requirement_closeout: skipped_beads", rationale: "Beads active — bd close owns requirement state")` and continue to the outer completion-tail step 3 (reset resume counter).
   3. **Read the provenance pointer:** parse the brief (in `done/` when step 2 performed the move; otherwise wherever it remains) for a `- **Source requirement:** {path}` line under its `## Environment` section. If the line is **absent → no-op** (backward compatible with pre-feature briefs and direct `/supervisor task:` runs that never stamped a pointer). Record `record_decision(phase: SELF_HEAL, decision: "requirement_closeout: noop_no_pointer", rationale: "no Source requirement pointer on brief")` and continue.
   4. **Resolve + safety-check the path:** resolve `{path}` relative to the project root. **Require the resolved path to be UNDER `.supervisor/requirements/` AND to pass `test -f`** (guards against path traversal / injection via the brief field). If it does not resolve, is outside `.supervisor/requirements/`, or the file does not exist → **logged no-op** (NEVER an error that fails the run): record `record_decision(phase: SELF_HEAL, decision: "requirement_closeout: noop_unresolved", rationale: "Source requirement path missing or outside .supervisor/requirements/")` and continue.
   5. **Stamp, do not move:** append a `## Status` block to the requirement file **in place** (do NOT move the requirement file — only the brief moves). **Mirror the brief `## Outcome` granularity** so an escalated requirement is not indistinguishable on disk from a clean pass (the very "done and not-done look identical" problem this feature removes):
      - On **PASS / loop-skipped** → `**Status:** done`.
      - On **ESCALATED** → `**Status:** done_with_escalation`, plus a `- **Heal:** {needs_human|max_iterations_reached|self_heal_resume_thrash} — {heal_remaining_issues} remaining` line carrying the escalation nuance (mirrors the brief `## Outcome` `**Heal reason:**` / `**Heal remaining issues:**` fields).

      Stamp exactly one of these two literal blocks (no inline comments — stamp the block verbatim, substituting the `{...}` placeholders). Each block opens with the namespaced HTML-comment sentinel `<!-- loomwright:requirement-closeout -->` so the idempotent re-stamp keys off **our** marker, never a bare `## Status` heading some other tool may use. On **PASS / loop-skipped**:
      ```markdown
      <!-- loomwright:requirement-closeout -->
      ## Status
      - **Status:** done
      - **Completed:** {ISO 8601 timestamp}
      - **Brief:** {done/ brief path}
      - **PR:** {PR URL}
      ```
      On **ESCALATED** (same fields, escalated status value, plus one `Heal` line):
      ```markdown
      <!-- loomwright:requirement-closeout -->
      ## Status
      - **Status:** done_with_escalation
      - **Completed:** {ISO 8601 timestamp}
      - **Brief:** {done/ brief path}
      - **PR:** {PR URL}
      - **Heal:** {needs_human|max_iterations_reached|self_heal_resume_thrash} — {heal_remaining_issues} remaining
      ```
      **Idempotent — replace, do not duplicate:** locate a prior close-out by the `<!-- loomwright:requirement-closeout -->` sentinel (NOT by a bare `## Status` heading — other tooling may legitimately use that heading for a different purpose, and these `.supervisor/requirements/*.md` files have no fixed heading schema). If the sentinel is present, **REPLACE the whole span** from the sentinel through the end of the `## Status` block it introduces — that is, up to the next `##` heading that appears **after** the `## Status` line, or end-of-file (do NOT stop at the `## Status` heading itself, which is the block's own start); if it is absent, **append** a fresh sentinel-led block. Keying the re-stamp to our own marker makes it collision-proof — an unrelated `## Status` section is never clobbered — and handles the multi-brief case where one requirement spawns several briefs (the latest close-out wins). On success record `record_decision(phase: SELF_HEAL, decision: "requirement_closeout: {done|done_with_escalation}", rationale: "stamped ## Status on {requirement path}")`.

2.6. **Orientation memo proposals (success-only, fail-safe side-effect — additive):**

   Runs on the SAME successful outcomes as step 2.5 — **PASS / loop-skipped / ESCALATED** only; it MUST NOT run on the `failed` / abort / `checkpoint` / invariant-violation / base-mismatch-cleanup paths. The run **MAY** (optional — skip silently when there is nothing durable to say) propose per-area **orientation memos** for the areas this run touched, by writing one proposal file named `<area-slug>.md` (a single `[a-z0-9-]+` segment — the same slug rules `add-orientation.sh` enforces, `readme` reserved) per area to the **gitignored** `.supervisor/orientation-proposals/` directory (`mkdir -p` it first). Each proposal uses the SAME memo format the committed store documents in `.agent/orientation/README.md`: line 1 a machine-parsed header comment `<!-- written_at: <ISO-8601 UTC> | head_sha: <short HEAD sha> | areas: <space-separated repo-relative path prefixes> -->`, line 2 a one-line summary, then a free-form markdown body — the WHOLE file ≤1000 chars (an over-cap proposal would be rejected at promotion time by `add-orientation.sh`, so cap it here).

   **NEVER writes the committed `.agent/orientation/` store.** Promotion into the committed store happens ONLY via the `/dreaming` per-item-approval flow calling `add-orientation.sh` (the store's confirm-gated sole writer) — an automated run proposing memos here can never mutate the committed store.

   This whole step is a **runtime side-effect emitter and MUST fail SAFE** per the CLAUDE.md bimodal-failure invariant: ANY write failure (unwritable/uncreatable dir, disk error) is a **silent logged no-op** — record `record_decision(phase: SELF_HEAL, decision: "orientation_proposals: {n written|noop_write_failed|skipped}", rationale: "advisory — non-fatal")` and continue. It NEVER blocks the completion tail, NEVER changes `heal_decision`, NEVER gates the PR or the run — always continue to step 3 regardless of outcome.

3. **Reset resume counter (unconditional — runs on every exit path: PASS, ESCALATED, or loop-skipped):** `Context-Keeper(operation: record_self_heal_resume, increment: false)`. The completion tail itself is unconditional; so is the reset.

4. **Update state:** `Context-Keeper(operation: update_phase, new_phase: LOOP, completed_phases: [..., SELF_HEAL])` and `record_decision(phase: SELF_HEAL, decision: "{PASS|ESCALATED|loop_skipped}", rationale: "{final reason}")`. Status in state file matches the outcome (`completed` or `completed_with_escalation`).
   - **Canonical on-disk flip MUST happen — regardless of execution mode.** This step flips the canonical lowercase `- status:` line in `.supervisor/state.md` (per `skills/state-management/SKILL.md` §"State File Schema") from `running` to `completed` (or `completed_with_escalation` on the ESCALATED path). On the **parallel path** Context-Keeper performs the flip via `update_phase`. On the **inline main-thread path** (where Context-Keeper is not spawned), the Supervisor MUST instead perform a **direct best-effort write** that flips the same canonical lowercase `- status:` line on disk. This keeps the `hook-dispatch-on-pr-create.sh` session-scope gate (which excludes `completed`/`completed_with_escalation`/`failed`) and `--continue` resume reading a truthful canonical state.
   - **Best-effort / non-fatal (fail-safe invariant):** the flip MUST NEVER fail the run — a write failure is a logged no-op. Do NOT touch the human-readable **bold** `## Outcome` display block; only the on-disk canonical lowercase `.supervisor/state.md` is updated here.

4.5. **System Twin contract builder (WRITE path — completion tail only):**

   **Runs only on a PASS outcome** (`heal_decision == PASS` or loop-skipped — the same outcomes that move the job to `done/` in step 2); SKIP on the ESCALATED / base-mismatch / invariant-violation paths. Compute the per-subsystem incident map for THIS run and spawn the ephemeral, Bash-capable builder Task exactly per Part 1 §"Contract builder (WRITE path)" above — the spawn prompt there is verbatim and authoritative.

   Invariants that must survive any summarization of this step:
   - **Propose-only, advisory, reversible** — writes the advisory twin store, never plugin code, never a gate.
   - **Pinned repo-root CWD, never a worktree** — `write-system-contract.sh` exits 3 from a linked worktree; Phase 4 already removed the worktrees.
   - **Context-Keeper is OUT of this path** — sole writer of the twin store is `write-system-contract.sh`.
   - **Failure is non-fatal** — log `record_decision(phase: SELF_HEAL, decision: "twin_builder: {n} written / {m} skipped", rationale: "advisory — non-fatal")` and continue.

5. **Emit SUPERVISOR_RESULT block for this task** (see `agents/supervisor.md` §"Result Block (SUPERVISOR_RESULT)" — the block definition deliberately stays in the agent file, untouched, and the SubagentStop hook validation is unchanged). Exactly one block per task, emitted here — Phase 5 LOOP emits nothing. When looping to a new task, the next task's Phase 4.5 tail will emit its own block. The SubagentStop hook validates the last block; earlier blocks must still be schema-valid. Include the additive `contract_conformance`, `benchmark_result`, and `ground_truth` objects (computed earlier in this phase), the additive `knowledge_sources_used` array (the memory sources consulted this run, per the tag vocabulary in the Result Block section), and also emit the FLAT hard-signal fields — including a flat `knowledge_sources_used` array carrying the SAME value — onto the `session_end` JSONL event — see "Hard-signal fields (System Twin)" below.

5.5. **Until-mergeable review-drain dispatch (DEFAULT ON — opt-out, best-effort, fire-and-forget):**

   Runs ONLY on a PASS / normal completion that produced a PR (i.e. `PR_URL` is set; skip entirely on the base-mismatch cleanup path, on `status: failed`/`checkpoint`, and whenever no PR was created). When eligible, hand the PR URL to the dispatcher, which launches a fresh, detached standalone review-and-heal run via the **`--agent` runner form** (`loomwright:review-pr-runner`) and, **by default, threads the until-mergeable drain signal** so the runner forwards `--until-mergeable` to its inline `/review-pr` (the external-channel drain — required CI checks, bot reviews/threads/comments, check outputs). **As of AC7 this dispatch is ON BY DEFAULT** after PR creation: it dispatches UNLESS suppressed via `--no-auto-review` OR `.supervisor/config.json` `.auto_review == false`. The until-mergeable signal itself is opt-out via `--no-until-mergeable` OR `.auto_until_mergeable == false` (when opted out the runner runs the plain diff-only `/review-pr`). The signal is threaded via **environment variables** (NOT a `/review-pr` slash string, NOT a positional) per the S2-pinned contract in `skills/review-heal/SKILL.md` §"Until-Mergeable Dispatch Signal" — the `--agent` form has no flag surface, which avoids the 11.1.1 spawn-depth auto-delegation trap. A per-PR marker guards against re-dispatch on a `--continue` re-run, so there is exactly ONE dispatch per PR.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-pr-review.sh" \
     --pr-url "{PR_URL}" \
     {if AUTO_REVIEW_FLAG == suppress: --no-auto-review}{if AUTO_REVIEW_FLAG == force: --auto-review} \
     {if UNTIL_MERGEABLE_FLAG == suppress: --no-until-mergeable} \
     {if CHECK_WAIT_TIMEOUT set: --check-wait-timeout "{CHECK_WAIT_TIMEOUT}"} \
     {if REVIEW_CHECK_PATTERN set: --review-check-pattern "{REVIEW_CHECK_PATTERN}"}
   # always exits 0. Default-ON dispatch (suppressed only by --no-auto-review / .auto_review==false).
   # Default until-mergeable signal (LOOMWRIGHT_UNTIL_MERGEABLE=1 exported by the dispatcher);
   # opted out by --no-until-mergeable / .auto_until_mergeable==false. The optional tuning flags are
   # forwarded ONLY when set; the dispatcher exports them as LOOMWRIGHT_CHECK_WAIT_TIMEOUT /
   # LOOMWRIGHT_REVIEW_CHECK_PATTERN. Omit --auto-review/--no-auto-review when AUTO_REVIEW_FLAG == none.
   ```

   The dispatched drain **NEVER merges** and **NEVER waits on a human** — it stops at a terminal `READY` / `ESCALATED` state and fires a best-effort notification on **both** terminal states (see `skills/review-heal/SKILL.md` §"READY redefinition" for the readiness semantics — not restated here). This step is **strictly best-effort**: the dispatcher ALWAYS exits 0 (missing `claude`/`jq`/config or any error logs one line and exits 0), so it can NEVER hard-fail the completion tail. It NEVER changes `heal_decision`, NEVER alters the PR, and NEVER affects control flow or `SUPERVISOR_RESULT.status` — always continue to step 6 regardless of outcome. Because `/review-pr` never creates a PR, there is no review→review recursion.

   **Hook backstop (v14.34.0 — defense-in-depth).** A `PostToolUse[Bash]` hook (`${CLAUDE_PLUGIN_ROOT}/scripts/hook-dispatch-on-pr-create.sh`, registered in `hooks/hooks.json`) ALSO backstops this dispatch: it fires on the actual `gh pr create` Bash tool call and invokes the SAME `dispatch-pr-review.sh`, so the until-mergeable drain still runs even if this prompt step is skipped on the inline `/autonomous`/`/supervisor` path (where the Supervisor is the main thread and `SubagentStop(supervisor-runner)` never fires). The hook is session-scope gated — an in-progress job exists AND authorization resolves from ONE coherent source: a non-terminal, branch-matching `state.md`, OR (when `state.md` is stale/terminal) a UNIQUE active autonomous `state.json` (matching `current_branch` + brief in `jobs/in-progress/` + non-terminal `current_status` + null `ended_at`); a stale terminal `state.md` no longer short-circuits ahead of the state.json fallback — so it never hijacks unrelated manual PRs. If BOTH this step and the hook fire for the same PR, the dispatcher's per-PR idempotency marker guarantees exactly ONE dispatch — so keeping step 5.5 alongside the hook causes no double-dispatch. **Timing note:** the hook fires at PR-creation time (Phase 4 FINALIZE), one phase EARLIER than step 5.5's completion-tail dispatch (which runs after Phase 4.5 SELF_HEAL). When both paths are live the earlier hook dispatch wins, so the detached drain runs at the same time as the inline self-heal rather than after it. **This timing overlap is now harmless because the two no longer share a checkout:** the detached drain runs in its OWN dispatcher-created sibling worktree (detached-HEAD at the PR head SHA — see `scripts/dispatch-pr-review.sh` and `skills/review-heal/SKILL.md` §"Isolated worktree for the detached dispatched drain"), so it has a separate working dir + index and can no longer check-out / stage / commit in the inline self-heal's working tree. The drain still does only regular pushes (NEVER --force) + re-polls, so a concurrent push at worst yields a non-fast-forward rejection the runner recovers from; nothing is force-clobbered or merged. **Do NOT write `.supervisor/config.json {"auto_review": false}` to suppress the drain for this self-heal race — that rationale is retired now that the drain is working-tree-isolated.** (The `auto_review` flag itself remains as a general opt-out for not wanting the drain at all; it is no longer a workaround for the collision.)

   **Observability (AC8b) — reconcile against the MARKER, never from "did I dispatch".** The drain may have been dispatched by EITHER this step OR the `PostToolUse[Bash]` hook backstop — and the hook fires at `gh pr create` (one phase earlier) and is **invisible to this main-thread context**, returning no signal. So `until_mergeable_dispatched` MUST be resolved from the on-disk per-PR dispatch marker, NOT keyed on whether *this step* invoked the dispatcher. On the inline path this step is sometimes skipped while the hook still dispatched; keying on "did I dispatch" records a **false negative** (this is the exact defect that made a prior run misreport "not dispatched" while the drain was live). Resolve it deterministically — the dispatcher writes a marker whose body contains the exact PR URL, and (post-fix) a `RUN_LOG` whose header line contains `url={PR_URL}` followed by a tab, so both lookups are hash-implementation-agnostic and do not confuse prefix-related PRs (for example `/pull/7` vs `/pull/72`):
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
   Then record `until_mergeable_dispatched: {UM_DISPATCHED}` and (only when true AND a log was found) `until_mergeable_log: {UM_LOG}` on the job's `## Outcome` block (step 2 above) AND on the `session_end` JSONL event. Additively/optionally also surface them on `SUPERVISOR_RESULT` (no `schema_version` bump — additive, advisory, never gated, following the `branch_base`/`pr_state` precedent). **NEVER assert `false` from "I skipped step 5.5" alone** — a marker means the drain is live regardless of which path fired. `false` is truthful ONLY when no marker exists (opted out / no PR / dispatcher no-op). The drain itself fires the terminal `READY`/`ESCALATED` notification asynchronously; the marker + log path are the Supervisor-side trail a downstream consumer reads to know a drain is in flight.

6. **Advisory Twin delta line (informational ONLY):** echo one human-readable line via `format-twin-delta.sh`, built from the `contract_conformance` / `benchmark_result` values computed above — exact invocation in Part 1 §"Advisory Twin delta line" above. The script always exits 0; the line never gates, never alters the PR, never affects control flow.

**Hard-signal fields (System Twin / ST3 — written in BOTH shapes):**

Emit the contract-conformance, benchmark, and ground-truth results as the SAME data in two shapes: (1) nested objects on `SUPERVISOR_RESULT` (step 5 above) and (2) FLAT scalar fields on the `session_end` JSONL event in `.supervisor/logs/{session_id}.jsonl` — the shape `build-insights.sh` (ST4) aggregates. **The flat field names are a hard contract with ST4 — do NOT rename them.** The exact nested→flat field correspondence table lives in Part 1 §"Hard-signal dual emission" above and `docs/RESULT_SCHEMAS.md` §"`session_end` JSONL hard-signal fields". Flat fields are additive — a `session_end` event without them remains valid. Also stamp the additive `plugin_version` field (string, e.g. `"14.24.0"`) onto the same `session_end` event — read it at emission time via `jq -r '.version // "unknown"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"` (fall back to `"unknown"` when the manifest is unreadable); absent `plugin_version` stays valid — `build-insights.sh` groups such events under `"unknown"` in its per-version section. Also stamp the additive FLAT `knowledge_sources_used` array (v14.28.0) onto the same `session_end` event with the SAME value as the nested `SUPERVISOR_RESULT.knowledge_sources_used` array — the surface `build-insights.sh` / `/insights` reads. It is additive and ADVISORY: readers treat an absent field as "none used", it is NEVER gated on, and it does NOT bump `schema_version`. As of v14.33.0 `build-insights.sh` / `/insights` aggregates and surfaces this field in the `## Knowledge sources (memory APPLY)` dashboard section (runs-reporting-a-source count, top source tags, per-version usage); this surface ensures emission.

**Error handling table:**

| Situation | Action |
|-----------|--------|
| CODE_REVIEW_RESULT malformed or missing | Retry review once; if still malformed, pause with resume |
| Fix Task() crashes or returns no FIX_RESULT | Pause phase — emit `SUPERVISOR_RESULT` with `status: checkpoint` (no `paused` status exists in the schema); the resume counter increments at Phase 4.5 entry of the next `--continue` run |
| `git push` fails inside loop | Pause phase; report auth/network error in checkpoint |
| `gh pr comment` fails at escalation | Record findings in `.supervisor/state.md` decisions log; do NOT fail the task — escalation still succeeds, just without PR comment |
| Resume counter ≥ 3 | Abort loop, mark ESCALATED with `self_heal_resume_thrash` reason, run completion tail |
| Tool budget exceeded mid-loop | Checkpoint with `current_phase: SELF_HEAL`, exit with resume command |

The phase **Output** block (the `### Phase 4.5: SELF_HEAL` report format) also stays in
`agents/supervisor.md` — emit it as specified there.
