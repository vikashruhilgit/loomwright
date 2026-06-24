---
name: self-heal-advisory
description: Supervisor Phase 4.5 advisory-only machinery (System Twin conformance/benchmark/ground-truth, contract-builder WRITE path, delta line, hard-signal dual emission). Never changes heal_decision or blocks the PR; read on demand at Phase 4.5 entry, deliberately not preloaded.
version: 1.0.0
lastUpdated: 2026-06-10
---

# Self-Heal Advisory Protocol (Supervisor Phase 4.5)

This skill is the single source of truth for the **advisory-only** steps of Supervisor
Phase 4.5 SELF_HEAL. `agents/supervisor.md` keeps the load-bearing gate logic (the
review-and-fix loop, completion-tail guard, job lifecycle, SUPERVISOR_RESULT emission,
rubric-grader spawn) and points here for everything below.

**Scope guard:** this skill covers ONLY the Supervisor-specific advisory extras. It does
NOT define review→fix→re-review loop semantics — for loop mechanics (bounds, decisions,
escalation) the authority is `skills/review-heal/SKILL.md` and the Phase 4.5 section of
`agents/supervisor.md`.

**HARD ADVISORY CONTRACT (applies to every step in this file):** nothing here ever
changes `heal_decision`, triggers a fix iteration, blocks the PR, or fails the task.
Every failure path is non-fatal: log via `record_decision(...)` and continue. Under
tool-budget pressure (YELLOW/RED zones), these steps are the FIRST to skip — the gates
in `agents/supervisor.md` still run.

**When to read this file:** the Supervisor reads it at Phase 4.5 entry (it is
deliberately NOT in the Supervisor's preloaded `skills:` list — preloading would
re-inject the ~220 extracted lines into every session (this file is ~290 lines
with its own headers and framing); on-demand reading keeps the agent prompt
focused on gates).

---

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
> tool-budget pressure this step is among the first to skip — the gates in
> `agents/supervisor.md` still run.

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
context (the exact prompt line lives in `agents/supervisor.md` §"Review-and-fix loop").
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
> step is among the FIRST to skip — the gates in `agents/supervisor.md` still run.

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
context (the exact **AREA-KNOWLEDGE ADVISORY** prompt line lives in `agents/supervisor.md`
§"Review-and-fix loop", included only when non-empty). The bridge read counts under the
existing `brain_context` tag in `knowledge_sources_used` (the bridge IS the brain-context
read path — see `skills/brain-context/SKILL.md` §"Bridge read") — it does NOT introduce a new
tag and does NOT bump `schema_version`; it is additive prose enrichment of the reviewer
prompt only.

---

## Post-review advisory checks

Run all three after the Code Reviewer loop has completed (regardless of
`heal_decision`); they populate the `contract_conformance`, `benchmark_result`, and
`ground_truth` objects consumed by completion-tail step 5 in `agents/supervisor.md`.

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

**Runs only on a PASS outcome** (`heal_decision == PASS` or loop-skipped — i.e. the same outcomes that move the job to `done/` in step 2). On the ESCALATED / base-mismatch / invariant-violation paths, SKIP the builder (do not record contracts for a code state we did not pass). This is **propose-only, advisory, and reversible** — it writes the advisory twin store, never plugin code, never a gate.

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

1. **Nested objects on `SUPERVISOR_RESULT`** (completion-tail step 5 in `agents/supervisor.md`): `contract_conformance`, `benchmark_result`, and `ground_truth` (see the "Result Block" schema). Optional/additive — `schema_version` stays `1`.
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

   See the `session_end` log line in `agents/supervisor.md` §"Session Logging" for the exact shape. The flat fields are additive — a `session_end` event without them remains valid (a reader treats absent fields as "not reported this session"; for the `ground_truth_*` fields a reader treats absent as `skipped`).
