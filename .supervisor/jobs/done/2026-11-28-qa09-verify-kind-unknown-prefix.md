# Supervisor Job: Loomwright checks a brief's `verify:` lines with Selvedge, and a mistyped check prefix is never run as shell

## Environment
- **Project:** yellowtail (an Orca worktree of the loomwright marketplace repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: vikashruhilgit/loomwright-two-requirement-items
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (one prunable worktree under the session scratch dir)
- **Source requirement:** .supervisor/requirements/qa-split/09-loomwright-verify-kind-and-unknown-prefix-root-fix.md
- **Base commit:** 9a6a850ee5d07ebde56fedfada437ae86b4d509d

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe scripts + jq, the stack `run-ground-truth.sh` and `exec-acceptance-lib.sh` already use. |
| 2 | Dependency Availability | GO | No new library. Selvedge is the sibling plugin in this repo (`selvedge/bin/selvedge`, `selvedge 0.12.1`), driven only through its public CLI, as owner decision D4 sets out. Absent ⇒ `unverified (verify_plugin_absent)`. |
| 3 | Architecture Fit | GO | The ground-truth runner already delegates one kind to another script (`rule:` → `rules-check.sh`); `verify:` follows the same delegation shape. |
| 4 | Scope vs Supervisor Capability | CAUTION | 20 files (17 modify, 3 create) is past the 12-file context bound, so the brief splits into 2 subtasks (`context-bound`). |
| 5 | Hard Blockers | CAUTION | (a) `selvedge run` reads the working-tree `selvedge.json` and takes no `--base` (`selvedge/lib/runner/run.mjs`: `const { config, root } = loadConfig({ cwd: runDir });`; `plan` takes `--base`). Owner decision 2026-11-28: the merge does not wait for that Selvedge fix; this PR names the gap as an open item. (b) the `selvedge` on this machine's `PATH` is a stale 0.7.1 copy in the plugin cache, not 0.12.1. |

**Overall Verdict:** CAUTION

## Task
**Goal:** In one PR: refuse any unknown `<word>:` prefix in a brief's `## Executable Acceptance` (never hashed, never run); add a `verify:` kind (with `qa-executor:` as an alias) whose lines are all checked in ONE Selvedge run, its verdicts mapped to per-check results; and show `verify:` counts wherever the ground-truth result is shown.

**Problem Statement:**
The owner, running Loomwright on a project with a UI, needs a brief's `verify:` lines checked by Selvedge in Phase 4.5, and needs a mistyped prefix refused instead of run.
Currently `classify_kind`'s last arm is `*)              printf 'cmd\n' ;;`, so `verfy: the cart total updates` is hashed into the stamp and, once stamped, run as shell. `qa-executor:` lines are recognised but spawn nothing (reason `qa_executor_dispatch_deferred_m2b_1b`). Nothing in Loomwright calls Selvedge.
This leaves acceptance criteria about what a user sees with no evidenced verdict, and any future kind name can turn into a shell command by accident.
Success looks like: a `frobnicate: x` line is `unverified (unknown_kind)` and never executed; two `verify:` lines produce exactly one Selvedge run folder and two per-check results from its `verdict.json`; the shown result reads `verify 1 PASS · 1 NOT_VERIFIABLE`, never a bare `pass`.

## Design decisions
- decision: where the Selvedge driver (CLI discovery, the criteria → plan → freeze → run → verdict chain, `verdict.json` mapping) lives. The chain is `criteria from-text` (stdin) → `plan <criteria.json> --base <ref>`, Selvedge's one-go form that runs init, the planner, `--validate` and `--freeze` (its help: `plan in one go: --init, the planner, --validate, --freeze. Prints the run folder`) → `run <run-dir>` (it refuses an unfrozen folder, `not_frozen`) → `verdict.json`, which `run` writes and `verdict <run-dir>` re-derives
  chosen: a new sourced module `loomwright/scripts/ground-truth-verify.sh`, sourced by `run-ground-truth.sh` exactly as it sources `exec-acceptance-lib.sh`, called once per run from a pre-resolution block modelled on the `rule:` one
  rejected: append the driver to `run-ground-truth.sh` — fails blast radius as a design (the runner is 693 lines, already past the 500-line large-file threshold, and the driver is a separate concern) and reversibility is partial (swapping the driver touches the runner's whole body)
  rejected: put it in `exec-acceptance-lib.sh` — breaks that file's stated contract `Functions (all pure — no I/O beyond reading the given `<brief>` path; no execution, no writes)`
  evidence: the one existing `verdict.json` reader, `loomwright/scripts/propose-from-verify.sh` (header: `per criterion `verdict` (PASS|FAIL|BLOCKED|NOT_VERIFIABLE)`, `SUPPORTED_SCHEMA_VERSION=1`), reads finished run folders and never calls the CLI or maps to ground-truth checks, so it is not the driver; the driver mirrors it by refusing any `schema_version` other than 1 (`verify_verdict_unreadable`) and accepting exactly that verdict set; `wc -l` at base: run-ground-truth.sh 693, exec-acceptance-lib.sh 198; `skills/supervisor-readiness/SKILL.md` §"Module layout" (500-line threshold, a CREATE module for a separate concern); the runner already sources one sibling: `. "$SCRIPT_DIR/exec-acceptance-lib.sh"`
  revisit when: a second caller needs the Selvedge driver outside ground truth (then it moves to a shared module, not a copy)
  status: confirmed (owner decision 2026-11-28 extended `## Touches` with this module by name)

## Acceptance Criteria

**Part A: unknown prefix**
- [ ] A1: Given a brief line `frobnicate: x`, when `run-ground-truth.sh --brief` runs, then that check is `unverified` with reason `unknown_kind`, nothing is executed (a marker file the line would create is absent afterwards), and the line is not part of `exec_acceptance_hash`.
- [ ] A2: Given a brief whose only Executable Acceptance line is `frobnicate: x`, when `exec-acceptance-hash.sh` runs, then it prints `none`.
- [ ] A3: Given a bare shell line with no prefix (`bash scripts/x.sh`, `npm test -- --grep "a: b"`), when classified, then it is still `cmd`, hashed and stamp-gated exactly as today.
- [ ] A4: Given a line that starts with a known kind (`cmd:`, `corpus-task:`, `rule:`, `verify:`, `qa-executor:`), when classified, then its kind is unchanged by Part A. A prefix is `<word>:` followed by a space or the end of the line, `<word>` = a letter, then letters, digits, `-` or `_`.
- [ ] A5: Given Plan Review reads a brief with an `unknown_kind` line, when it runs Criterion 14, then it raises one `executable_acceptance` issue naming the line and saying it will not run.

**Part B: the `verify:` kind**
- [ ] B1: Given `verify: <text>` and `qa-executor: <text>` lines, when classified, then both are `verify`, and a test pins that `qa-executor:` keeps working as the same kind.
- [ ] B2: Given two `verify:` lines and a reachable Selvedge, when ground truth runs, then exactly one Selvedge run folder is created, and each line gets its own per-check result taken from that run's `verdict.json` (lines map to `criteria.json` ids in order).
- [ ] B3: Given a Selvedge verdict per criterion, when mapped, then PASS → `pass`, FAIL → `fail`, and BLOCKED or NOT_VERIFIABLE → `unverified` carrying Selvedge's reason (for example `unverified (NOT_VERIFIABLE material_assumption)`).
- [ ] B4: Given neither `SELVEDGE_BIN` nor `selvedge` on `PATH`, when a `verify:` line is checked, then it is `unverified` with reason `verify_plugin_absent`, and the runner still exits 0.
- [ ] B5: Given Selvedge exits with a refusal, or its run folder has no readable `verdict.json`, when mapped, then every `verify:` line is `unverified` with a named reason (`verify_refused` / `verify_verdict_unreadable`), never `pass`. A non-zero exit from `selvedge run` with a readable `verdict.json` is a normal result (its exit is 1 on any FAIL), read from the file, never from the exit code.
- [ ] B6: Given `--no-cmd` / `GROUND_TRUTH_NO_CMD=1` (unattended `/automate`), when ground truth runs, then `verify:` lines are still checked (D15a: a step plan has no shell), while `cmd:` lines stay disabled as today.
- [ ] B7: Given a PR branch that edits `selvedge.json`, when Loomwright runs Selvedge, then Selvedge is told to read `selvedge.json` from the base branch (`plan <criteria.json> --base <ref>`), so the PR's edit has no effect at plan time (D15b); the one-go `plan` also freezes, so validate and freeze read the same base config. A stub-`SELVEDGE_BIN` test asserts `--base <ref>` reaches `plan`. It also asserts that the driver calls `run` only on the folder `plan` printed, and that it never calls `run` when `plan` exits non-zero (that case is `verify_refused`). `run` takes no `--base` in Selvedge 0.12.1 (it calls `loadConfig({ cwd: runDir })`), so D15b holds at plan time only. Per the 2026-11-28 owner decision this PR does not wait for a Selvedge release: the gap is named as an open item in the evidence file (`## Open items`, citing `loadConfig({ cwd: runDir })` in `selvedge/lib/runner/run.mjs`) and in the PR body's open items, which link that section. The fix is a later, separate Selvedge change. Loomwright never works around it and never passes an unsupported flag to `run`.
- [ ] B8: Given unapproved env hooks in the target repo, when Selvedge runs, then the result is `unverified (BLOCKED env_hooks_unapproved)`; Loomwright never approves a hook itself (no `selvedge env approve` call anywhere in the driver; a test greps for it).

**Part C: showing the result**
- [ ] C1: Given a brief with `verify:` lines, when `exec-acceptance-hash.sh` runs, then the `verify:` lines (in their stripped form) are part of the hash, and editing one changes the hash. A brief with no `verify:` line hashes exactly as at base, so existing stamps stay valid.
- [ ] C2: Given a brief with `verify:` lines and no stamp, when ground truth runs, then the `verify:` lines still run: the stamp gates `cmd:` lines only.
- [ ] C3: Given Plan Review reads a brief with `verify:` lines, when it runs Criterion 14, then it lists them at LOW with what they will check, and they never by themselves make the decision NEEDS_HUMAN.
- [ ] C4: Given a run with 1 `verify:` PASS and 1 `verify:` NOT_VERIFIABLE, when the ground-truth result is shown, then it reads with the counts, for example `verify 1 PASS · 1 NOT_VERIFIABLE`, never a bare `pass`; a test pins this. The shown places are: the runner's `Verify:` stdout line and an additive `verify_counts` key on `GROUND_TRUTH_JSON` (both present only when there is ≥1 `verify:` line); the Phase 4.5 finding (`completion-tail.md`'s `record_decision("ground_truth: …")` line appends the counts). At base there is no PR-body ground-truth line: FINALIZE writes the PR body before Phase 4.5 runs. The PR body's verdict counts section is item 10 (a non-goal here), and it will read this `Verify:` line. `SUPERVISOR_RESULT.ground_truth` (the NESTED line) keeps its key set and status enum, which `/automate` sidecar-check pins, so it is out of scope for the counts.
- [ ] C5: Given any `verify:` FAIL, when Phase 4.5 finishes, then `heal_decision` is unchanged by it, no fix iteration starts because of it, and `gate-eval` still has seven conditions (a test asserts both).
- [ ] C6: Given the kind list (`cmd`, `corpus-task`, `rule`, `verify`, plus `unknown_kind`) is copied in the runner's header, `exec-acceptance-lib.sh`'s header, `plan-reviewer.md`, `launch-pad.md` and `docs/result-schemas/ground-truth-json.md`, when this PR lands, then every copy says the same thing (house rule: a restated list changes in the same change as its authority), and a test pins it.

**Validation (from the requirement)**
- [ ] V1: `bash scripts/ci-local.sh --affected` passes, including `test-run-ground-truth.sh` and `test-exec-acceptance-hash.sh` with the new legs (the `verify:` legs use a stub `SELVEDGE_BIN` that writes a fixed `verdict.json`).
- [ ] V2: `check-qa-removal-manifest.sh --expect 12` still passes, with its `qa-executor:` keep rows updated to the alias wording.
- [ ] V3: Given Selvedge's bundled sample app (`selvedge sample-app`), when `run-ground-truth.sh --brief <a brief with two verify: lines>` runs against it, then a committed evidence file `docs/evidence/qa-split-09-verify-kind.md` contains the command, the full output (one result per line from one Selvedge run folder, plus the counts line), the `selvedge --version` it ran, an `## Open items` section naming the D15b run-time gap (B7), and the line `Verdict: PASS for Validation 3`; the PR body links to it.
- [ ] V4: `bash scripts/check-version-bump.sh` passes (the PR carries a `changelog.d/` fragment and hand-edits no version file).

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| runner + classifier (Subtask 1) | `loomwright/scripts/exec-acceptance-lib.sh` (198), `loomwright/scripts/run-ground-truth.sh` (693 — gains only the `verify`/`unknown_kind` arms, the source line and the counts line; the driver lives in the new module), `loomwright/scripts/exec-acceptance-hash.sh` (44) | `loomwright/scripts/ground-truth-verify.sh` (the Selvedge driver — Design decisions) | HIGH |
| runner tests (Subtask 1) | `loomwright/scripts/test-run-ground-truth.sh` (820 — the requirement's Validation 1 names this file for the new legs, the single test home of the runner), `loomwright/scripts/test-exec-acceptance-hash.sh` (164) | — | HIGH |
| evidence (Subtask 1) | — | `docs/evidence/qa-split-09-verify-kind.md` | HIGH |
| prompt + doc copies (Subtask 2) | `loomwright/agents/plan-reviewer.md` (428), `loomwright/agents/launch-pad.md` (912 — edits sentences in place, no new heading), `loomwright/skills/self-heal-advisory/completion-tail.md` (522 — in-place edits to the existing Ground-truth section), `loomwright/skills/supervisor-readiness/SKILL.md` (566 — in-place edit of the Executable Acceptance kind bullets), `loomwright/docs/result-schemas/ground-truth-json.md` (307 — the schema's single home), `loomwright/docs/result-schemas/supervisor-result.md` (235), `loomwright/docs/qa-removal-manifest.md` (594 — keep-row edits only), `loomwright/docs/prompt-token-budgets.json` (82), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1040 — budget mirror rows only), `loomwright/docs/loop-inventory/supervisor.md` (1338 — the SV-398 row only), `loomwright/docs/loop-inventory/launch-pad-autonomous.md` (1008 — the LP-140 effect cell and its gap-list note only), `loomwright/scripts/test-rule-conformance-seam.sh` (463 — the Criterion 14 classifier pin plus the kind-list-copies pin, next to it) | `changelog.d/qa-split-09-verify-kind.md` | HIGH |

> **Validator-owned surfaces:** `check-doc-currency.sh` (doc surface; no counts change here), `check-token-budget.sh` (`launch-pad` has 1 token of headroom at base, so any growth in `agents/launch-pad.md` or its preloaded `supervisor-readiness` skill needs a budget raise in `prompt-token-budgets.json` and its `ARCHITECTURE_CONTRACTS.md` mirror row), `check-qa-removal-manifest.sh --expect 12` (keep rows), `test-loop-inventory.sh` (live `q:`/`h:` anchors and heading coverage in `completion-tail.md` and `launch-pad.md`), `check-prompt-history-refs.sh` (history refs in prompts may not rise).

**Not changed, on purpose:** `loomwright/docs/result-schemas/schema-versioning.md` (its `qa-executor` mention is a v14.19.0 history entry, not a live list); `loomwright/docs/RESULT_SCHEMAS.md` (in Touches, but it only carries index rows pointing at `ground-truth-json.md` and restates no kind or reason list); `skills/async-orchestration/finalize.md` (the PR body; item 10); `selvedge/` (released on its own).

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| Subtask 1 | Subtask 2 | none (Subtask 2 is ordered after 1 because its copies quote 1's final kind list and reason names) | YES (dependency, not overlap) |

## Touched-file invariants

> Grounded at base `9a6a850ee5d07ebde56fedfada437ae86b4d509d`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/exec-acceptance-lib.sh`** — keep: sourced, never executed, sets no shell options (`this file itself
# sets no shell options`); `classify_kind` is the ONE classifier both consumers read (`IDENTICAL rule to run-ground-truth.sh's execution-time`); `exec_acceptance_hash` prints `none` when its filtered list is empty and returns 1 only with no sha256 tool (`printf 'none\n'`); bash 3.2-safe, no associative arrays. Change: the `qa-executor:*)` arm maps to `verify`, a `verify:*)` arm is added, and the final `*)` arm prints `unknown_kind` when the line matches the prefix grammar (A4) and `cmd` otherwise. The hash keeps `cmd` lines and adds `verify` lines, so a brief with no `verify:` line hashes byte-identically to base (C1). reuse: `trim` / `strip_bullet`; no `grep -E` subprocess per line where a `case` glob or bash `[[ =~ ]]` suffices (bash 3.2 `=~` is fine; quote nothing on its right side). pinned by: `test-exec-acceptance-hash.sh` (`(b) corpus-task:/qa-executor:-only brief => none` — that leg's expectation changes, see Pin mutations), `test-rule-conformance-seam.sh` (`` `corpus-task:` / `qa-executor:` / `rule:` prefix ``).
- **`loomwright/scripts/run-ground-truth.sh`** — keep: `# Exit:   always 0.`; exactly two machine lines in order (`GROUND_TRUTH_JSON:` then `GROUND_TRUTH_NESTED:`); the NESTED key set `{checked,status,checks_total,checks_passed[,findings]}` (no new key there; `/automate` sidecar-check refuses any other); the status fold (`if [ "$failures" -gt 0 ]; then`) is unchanged for every kind; the stamp gate block between `# MUTATION_CONTROL_BEGIN: exec-acceptance-stamp-gate` and its END marker stays byte-identical (a mutation control in the test splices it); `--no-cmd` wins for `cmd:`/`rule:` only (B6). reuse: `append_check`, the `rule:` pre-resolution pattern ("each made at most ONCE per run"), `PROJECT_ROOT` as the cwd for every child, stdin `</dev/null`. mirror: the `verify` per_check entries use `kind: "verify"`, `target` = the criterion text, `status` ∈ `pass|fail|unverified`; an `unverified` one's `reason` is `"<VERDICT> <selvedge reason>"` for BLOCKED/NOT_VERIFIABLE (so it renders `unverified (NOT_VERIFIABLE material_assumption)`), else a Loomwright reason. pinned by: `test-run-ground-truth.sh` (`qa_executor_dispatch_deferred_m2b_1b` leg (e) changes — see Pin mutations; the mutation control `MUTATION_CONTROL_BEGIN: exec-acceptance-stamp-gate`), `test-pr-postmortem-gather.sh` (names the runner as a convention only).
- **`loomwright/scripts/exec-acceptance-hash.sh`** — keep: thin wrapper over the lib, prints `sha256:<hex>` or `none`; its header comment (`list of `cmd:`/bare bullets ONLY (`corpus-task:`/`qa-executor:` bullets excluded), or the literal`) is rewritten to the new hash input (cmd + verify lines), and that copy is part of C6. pinned by: `test-exec-acceptance-hash.sh`, `test-run-ground-truth.sh`.
- **`loomwright/scripts/test-run-ground-truth.sh`** / **`test-exec-acceptance-hash.sh`** — keep: `ok`/`no` helper idiom and the isolated temp `CWD`; every `verify:` leg uses a stub `SELVEDGE_BIN` (a bash script under the test's temp dir that writes `criteria.json`, a run folder under `.selvedge/runs/<id>/` and a fixed `verdict.json`), never a real browser or model; `PATH` is scrubbed of any real `selvedge` for the B4 leg (`env PATH=<minimal>`), since this machine has a stale `selvedge` on `PATH`. Every existing leg that now dispatches Selvedge because of the alias — (e) and (e2) in `test-run-ground-truth.sh` — also sets a stub `SELVEDGE_BIN` (or scrubs `PATH`), never resolving a real `selvedge`; leg (c) in `test-exec-acceptance-hash.sh` changes its expectation (see Pin mutations).
- **`loomwright/skills/self-heal-advisory/completion-tail.md`** — keep (live loop-inventory anchors, `test-loop-inventory.sh`): the heading `### Ground-truth execution (M2b slice 1a — runs after the Code Reviewer pass)` (SV-390), and the substrings `findings are `severity: advisory` only. The runner ALWAYS exits 0` (SV-391), `bullet executes ONLY when the brief's `## Configuration` section carries a stamp` (SV-392), `NO_CMD_FLAG = (NON_INTERACTIVE == true) ? "--no-cmd" : ""` (SV-393), `No GROUND_TRUTH_NESTED line (runner failed / not run)` (SV-394), `(the failing per_check entries, severity "advisory") when any failed` (SV-395), `The runner resolves checks from the brief's optional `## Executable` (SV-396), `` `status: pass` requires zero failing checks (and ≥1 check executed); `` (SV-397), `run the contract-conformance check, the benchmark and the ground-truth execution` (SV-535); `this check NEVER changes a gate`; no new `###`/`####` heading (heading coverage needs an inventory row). The status enum `pass,advisory_failures,advisory_violations,unverified,skipped,failed,checkpoint` read by `scripts/check-contract-parity.sh` is unchanged. Change: the `qa-executor:` deferral bullet becomes the `verify:` rule (checked by Selvedge, advisory, still runs under `--no-cmd`), and `record_decision(phase: SELF_HEAL, decision: "ground_truth: {status} ({checks_passed}/{checks_total})"` appends ` · {Verify line}` when the runner printed one.
- **`loomwright/agents/plan-reviewer.md`** — keep: Criterion 14's classifier sentence still contains `` `corpus-task:` / `qa-executor:` / `rule:` prefix `` (pinned by `test-rule-conformance-seam.sh`), extended to name `verify:`; the decision-table row `Criterion 14 finds ≥1 `cmd:`/bare Executable Acceptance bullet with NO well-formed `## Configuration` stamp` stays the only Criterion 14 NEEDS_HUMAN trigger (C3: `verify:` lines are LOW visibility; A5: an `unknown_kind` line is one `executable_acceptance` issue, LOW, "will not run", and does not by itself escalate).
- **`loomwright/agents/launch-pad.md`** — keep: the anchors `**Affirmative rule** — emit the section when BOTH conditions hold` (LP-109), `For every `enforcement: must` rule in the block whose `check` is not `(none)`` (LP-111), `**`approve-and-stamp`** — compute the current stamp` (LP-139), `**`strip-cmd-bullets`** — remove every flagged` (LP-140); no new heading; Phase 5 action 6 still never emits `cmd:` bullets (writing `verify:` lines is item 10). Change: the two "keep any `corpus-task:`/`qa-executor:` bullets" phrases name `verify:` (and its `qa-executor:` alias) and `rule:`.
- **`loomwright/docs/qa-removal-manifest.md`** — keep: the 5-column row grammar `check-qa-removal-manifest.sh` parses (`| path | reference | action | item | note |`) and the `keep` action for every `qa-executor:` row; a row's reference must still `grep -F` in its file (else `pending`, and `MISMATCH` at `--expect 12`). The row naming `qa_executor_dispatch_deferred_m2b_1b` in `run-ground-truth.sh` changes its reference to text the new code really carries (e.g. `qa-executor:*)` in the lib), and the "kept until Phase 3 item 09 or D18" notes become the alias wording. pinned by: `test-check-qa-removal-manifest.sh` (uses its own fixture manifest, unaffected).
- **`loomwright/docs/prompt-token-budgets.json`** + **`ARCHITECTURE_CONTRACTS.md`** — keep: every budget entry has its mirror row; raise only the entries `check-token-budget.sh` reports over (measured + ~10%), in place.
- **`loomwright/docs/loop-inventory/supervisor.md`** — keep: the nine-cell row grammar; SV-398 keeps its id, file cell and `step-scoped` home; only its `q:` text and effect cell change to the new `verify:` sentence.
- **`loomwright/docs/loop-inventory/launch-pad-autonomous.md`** — keep: LP-140's anchor `q: **`strip-cmd-bullets`** — remove every flagged` (a live `prose` anchor, `test-loop-inventory.sh`) and its nine cells; only the effect cell's `keep corpus-task:/qa-executor:` and the gap-list note `strip-cmd-bullets must keep corpus-task:/qa-executor: bullets` change to name `verify:` (alias `qa-executor:`) and `rule:`, matching the launch-pad.md sentence.
- **`loomwright/scripts/test-rule-conformance-seam.sh`** — keep: the `ok`/`no`/`has` helper idiom and the Criterion 14 needle `` has "$PR" '`corpus-task:` / `qa-executor:` / `rule:` prefix' ``. If the plan-reviewer.md sentence changes shape, the needle moves in the same commit (it must still find the sentence that names all the non-`cmd` prefixes). Change: add the C6 pin next to that needle. It reads the five copies (runner header, lib header, plan-reviewer.md, launch-pad.md, ground-truth-json.md) and fails naming the file whose copy lacks `verify` or `unknown_kind`.

## Closed enumerations touched

> Sibling grep at base `9a6a850`: `git grep -nF "cmd_unapproved" -- . ':!CHANGELOG.md'` → 28 hits in 10 files; `git grep -nE "cmd\|corpus-task\|qa-executor|\{cmd, corpus-task" -- . ':!CHANGELOG.md'` → 4 hits in 3 files.

- **`verify` (kind) and `unknown_kind` (kind + reason)** (siblings: `qa-executor`, `rule`) — must be named in:
  - `loomwright/scripts/exec-acceptance-lib.sh` — `classify_kind`'s `case` arms and the header's `classify_kind <line>                 -> `cmd` | `corpus-task` | `qa-executor` | `rule`` — extend.
  - `loomwright/scripts/run-ground-truth.sh` — header `where kind in {cmd, corpus-task, qa-executor, rule}`, the target-extraction `case "$kind" in` and the execution `case` — extend.
  - `loomwright/docs/result-schemas/ground-truth-json.md` — `` `kind` — one of `cmd | corpus-task | qa-executor`. `` (already missing `rule`; fixed here) and `` `kind ∈ {cmd, corpus-task, qa-executor, rule}` `` — extend.
  - `loomwright/agents/plan-reviewer.md`, `loomwright/agents/launch-pad.md`, `loomwright/skills/supervisor-readiness/SKILL.md` — the prefix lists in Criterion 14, Phase 6 action 2a and the kind bullets — extend.
  - `loomwright/docs/result-schemas/schema-versioning.md` — `cmd|corpus-task|qa-executor` — no change: a v14.19.0 history entry, not a live list.
- **Selvedge verdict set `PASS|FAIL|BLOCKED|NOT_VERIFIABLE` and `verdict.json` `schema_version` 1** (a mirror, not a new value) — must match in:
  - `loomwright/scripts/ground-truth-verify.sh` — the mapping `case` — create, mirroring the next row.
  - `loomwright/scripts/propose-from-verify.sh` — `SUPPORTED_SCHEMA_VERSION=1` and its verdict set — no change: the existing second reader of the same file; a Selvedge schema bump updates both readers in one change.
- **reasons `unknown_kind`, `verify_plugin_absent`, `verify_refused`, `verify_verdict_unreadable`, and the `<VERDICT> <selvedge reason>` form** (sibling: `cmd_unapproved`) — must be named in:
  - `loomwright/docs/result-schemas/ground-truth-json.md` — the `reason` "Known values" list — extend.
  - `loomwright/scripts/run-ground-truth.sh` — header per-kind block — extend.
  - `loomwright/skills/self-heal-advisory/completion-tail.md`, `loomwright/skills/supervisor-readiness/SKILL.md`, `loomwright/agents/plan-reviewer.md` — mention `cmd_unapproved` in prose about the stamp gate, not a list of every reason — no change beyond the `verify:` sentence.
  - `loomwright/docs/loop-inventory/supervisor.md`, `loomwright/docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` — inventory / history — no change (SV-398 is updated for the deferral text, not as a reason list).
  - reason `qa_executor_dispatch_deferred_m2b_1b` is removed from the runner; its other hits (`ground-truth-json.md`, `completion-tail.md`, `qa-removal-manifest.md`, `test-run-ground-truth.sh`) are all in this File Impact Map.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-run-ground-truth.sh` — A1 `frobnicate: x` is `unverified`/`unknown_kind` and its marker file is absent | flip `printf 'unknown_kind\n'` → `printf 'cmd\n'` in `loomwright/scripts/exec-acceptance-lib.sh` |
| `test-exec-acceptance-hash.sh` — A2 `frobnicate: x`-only brief prints `none` | flip `printf 'unknown_kind\n'` → `printf 'cmd\n'` in `loomwright/scripts/exec-acceptance-lib.sh` |
| `test-exec-acceptance-hash.sh` — A3 `npm test -- --grep "a: b"` is still `cmd` and hashed | (in the prefix test) flip `( |$)` grammar to `:` anywhere — a reviewer-applied mutation: the line would turn `unknown_kind` |
| `test-run-ground-truth.sh` — B1 `qa-executor: x` → per_check `kind:"verify"` | delete `qa-executor:*)` in `loomwright/scripts/exec-acceptance-lib.sh` |
| `test-run-ground-truth.sh` — B2 two `verify:` lines ⇒ exactly one `.selvedge/runs/*` folder | reviewer-applied: move the driver call inside the per-line loop (one run per line) |
| `test-run-ground-truth.sh` — B4 no `SELVEDGE_BIN`, no `selvedge` on PATH ⇒ `verify_plugin_absent`, exit 0 | reviewer-applied: drop the `command -v selvedge` fallback's empty check so the driver runs an empty command |
| `test-run-ground-truth.sh` — B5 stub writes no `verdict.json` ⇒ every line `verify_verdict_unreadable`, never `pass` | reviewer-applied: default an unread criterion to `pass` in `ground-truth-verify.sh` |
| `test-run-ground-truth.sh` — B6 `--no-cmd` still runs `verify:` (stub invoked) | reviewer-applied: add the `NO_CMD` early-return to the verify pre-resolution block |
| `test-run-ground-truth.sh` — B7 stub records `--base <ref>` on its `plan` call | reviewer-applied: drop `--base "$base_ref"` from the `plan` invocation in `ground-truth-verify.sh` |
| `test-exec-acceptance-hash.sh` — C1 a `verify:` edit changes the hash; a verify-free brief hashes as at base | flip `[ "$kind" = "cmd" ]` (the hash filter) back to cmd-only in `loomwright/scripts/exec-acceptance-lib.sh` |
| `test-run-ground-truth.sh` — C4 output contains `verify 1 PASS · 1 NOT_VERIFIABLE` | reviewer-applied: delete the `Verify:` line's echo in `run-ground-truth.sh` |
| `test-run-ground-truth.sh` — C5 heal half: a stubbed `verify:` FAIL appears in `GROUND_TRUTH_NESTED.findings` with `severity:"advisory"` (the only severity Phase 4.5's loop never turns into a fix task), and `heal_decision`'s inputs are untouched (no new key outside the NESTED key set) | flip `severity: "advisory"` → `severity: "blocking"` in `loomwright/scripts/run-ground-truth.sh` |
| `test-run-ground-truth.sh` — C5 gate half: the body of `gate_eval` in `scripts/automate-helpers.sh` (from `gate_eval() {` to its closing brace) contains none of `ground_truth`, `GROUND_TRUTH`, `verify_counts`, `selvedge`, `verify:` (0 hits at base; a bare `verify` is not a needle, since `rev-parse --verify` and a `nothing countable to verify` comment are already there), and in the header comment block that ends at `gate_eval() {`, `#   cond 7 ` is the last `#   cond N` line (no `#   cond 8` anywhere before the function) | reviewer-applied: add an eighth condition to `gate_eval` that parks on `ground_truth.status != "pass"` |
| `test-rule-conformance-seam.sh` — C6 every copy names `verify` and `unknown_kind` | reviewer-applied: remove `verify` from the kind list in `docs/result-schemas/ground-truth-json.md` |
| `test-exec-acceptance-hash.sh` — leg (b) changes: a `corpus-task:` + `qa-executor:` brief no longer prints `none` (the alias is hashed) | the expectation is rewritten in this PR; mutation: flip the hash filter back to cmd-only (same as C1) |
| `test-exec-acceptance-hash.sh` — leg (c) changes: the mixed brief (`corpus-task:`, `cmd: true`, `qa-executor: x`, `npm test`) now hashes identically to the cmd + verify subset (`cmd: true`, `qa-executor: x`, `npm test`), with `corpus-task:` still excluded | the expectation is rewritten in this PR; mutation: flip the hash filter back to cmd-only (the mixed hash then equals the cmd-only subset and the new leg goes red) |
| `test-run-ground-truth.sh` — leg (e) changes: `qa-executor: x` with a stub `SELVEDGE_BIN` writing a PASS `verdict.json` ⇒ per_check `kind:"verify"`, `status:"pass"` (the deferral reason is gone) | delete `qa-executor:*)` in `loomwright/scripts/exec-acceptance-lib.sh` (the line turns `unknown_kind`) |
| `test-run-ground-truth.sh` — leg (e2) changes: `cmd: true` + `qa-executor: x` with a stub `SELVEDGE_BIN` writing a PASS verdict ⇒ status `pass`, total 2, passed 2 | reviewer-applied: default every `verify` result to `unverified` in `ground-truth-verify.sh` (passed drops to 1) |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Classifier, runner, Selvedge driver, tests, evidence | A1–A4, B1–B8, C1, C2, C4 (runner + JSON half), C5, V1, V3 | 5 modify, 2 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Prompt and doc copies, manifest, budgets, inventory rows, changelog | A5, C3, C4 (Phase 4.5 finding half), C6, V2, V4 | 12 modify, 1 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/ground-truth-verify.sh"}
  - {kind: "symbol", path: "loomwright/scripts/exec-acceptance-lib.sh", name: "unknown_kind"}
  - {kind: "symbol", path: "loomwright/scripts/run-ground-truth.sh", name: "verify_plugin_absent"}
  - {kind: "symbol", path: "loomwright/scripts/run-ground-truth.sh", name: "verify_counts"}
  - {kind: "symbol", path: "loomwright/scripts/test-run-ground-truth.sh", name: "SELVEDGE_BIN"}
  - {kind: "file", path: "docs/evidence/qa-split-09-verify-kind.md"}
requires: []
lanes:
  - "loomwright/scripts/exec-acceptance-lib.sh"
  - "loomwright/scripts/run-ground-truth.sh"
  - "loomwright/scripts/ground-truth-verify.sh"
  - "loomwright/scripts/exec-acceptance-hash.sh"
  - "loomwright/scripts/test-run-ground-truth.sh"
  - "loomwright/scripts/test-exec-acceptance-hash.sh"
  - "docs/evidence/qa-split-09-verify-kind.md"
external_requires:
  - "selvedge CLI 0.12.1 public commands (criteria from-text, plan --base, run, verdict) and its sample-app, for the V3 real run only"
  - "a later, separate Selvedge fix in which `run` reads selvedge.json from the base (D15b run-time half; per the 2026-11-28 owner decision this PR does not wait for it and names it as an open item)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/agents/plan-reviewer.md", name: "unknown_kind"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/ground-truth-json.md", name: "verify_plugin_absent"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/completion-tail.md", name: "verify:"}
  - {kind: "file", path: "changelog.d/qa-split-09-verify-kind.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/exec-acceptance-lib.sh", name: "unknown_kind"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/run-ground-truth.sh", name: "verify_plugin_absent"}
lanes:
  - "loomwright/agents/plan-reviewer.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/skills/self-heal-advisory/completion-tail.md"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/docs/result-schemas/ground-truth-json.md"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "loomwright/docs/qa-removal-manifest.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
  - "loomwright/scripts/test-rule-conformance-seam.sh"
  - "changelog.d/qa-split-09-verify-kind.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | YES (requires edge) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): `selvedge run` reads the PR head's `selvedge.json` (no `--base`), so D15b holds at plan time only. | HIGH | Owner decision 2026-11-28: ship with the gap named, never a Loomwright workaround; the fix is a later, separate Selvedge change. The worker records the finding (`loadConfig({ cwd: runDir })` in `selvedge/lib/runner/run.mjs`) in the evidence file's `## Open items` and the PR body's open items. Loomwright passes `--base` only to commands that accept it. |
| Feasibility (Phase 2.5): a stale `selvedge` (0.7.1) is first on this machine's `PATH`. | MEDIUM | `SELVEDGE_BIN` wins over `PATH`. The V3 run sets `SELVEDGE_BIN=<checkout>/selvedge/bin/selvedge` and records `selvedge --version` in the evidence. Tests scrub `PATH`. |
| Feasibility (Phase 2.5): scope is 20 files, past the 12-file context bound. | MEDIUM | Split context-bound into 2 subtasks. Subtask 2 is ordered after Subtask 1 and quotes its final kind list and reason names; the C6 pin catches a copy that drifts. |
| Cost per self-heal iteration: ground truth runs once per Phase 4.5 iteration, and each `verify:` run plans again with a model (heal has gone 3/3 on most items since 2026-10-12). | MEDIUM | Selvedge's budget caps one run (BLOCKED `budget_exceeded`). Replaying the first frozen plan is a follow-up (requirement non-goal). |
| Time: the runner has no per-check timeout, and a plan plus a browser run takes minutes. | MEDIUM | Selvedge's own budgets (`SELVEDGE_RUN_BUDGET_MS`, planner token budget) bound it; the driver adds no timeout of its own. |
| Prompt injection at plan time: the planner reads the page. | MEDIUM | Bounded by Selvedge's step plan (no shell), origin allowlist and validation; not eliminated. Loomwright never approves an env hook (B8). |
| Alias changes hashing: a stamped brief that carries a `qa-executor:` line gets a new hash, so its `cmd:` lines read `cmd_unapproved` until re-stamped. | LOW | Scanned 278 done briefs (433 Executable Acceptance bullets): 0 carry a stamp beside a `qa-executor:` line, and 0 bare lines match the Part A prefix grammar. Briefs with no `verify:` line hash as at base. |
| Loop-inventory live anchors in `completion-tail.md` / `launch-pad.md` break on a sentence rewrite (`test-loop-inventory.sh` FAILs). | MEDIUM | The Touched-file invariants list every live anchor to keep. No new `###` heading in either file. |
| `launch-pad` token budget has 1 token of headroom. | LOW | Raise it in `prompt-token-budgets.json` and the `ARCHITECTURE_CONTRACTS.md` mirror (measured + ~10%) in Subtask 2. |
| History references in prompt edits (e.g. "D18", "item 09", "red team C7") raise `check-prompt-history-refs.sh` counts. | LOW | Keep decision ids and item numbers in `CHANGELOG`/rationale and the changelog fragment, never in agent/skill prose. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-28-qa09-verify-kind-unknown-prefix.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-28T04:24:06Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/995
- **Branch:** feature/qa09-verify-kind-unknown-prefix
- **Files changed:** 22
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** unknown (no_driver_handover)
- **Summary:** Unknown <word>: prefixes in Executable Acceptance are refused (unverified unknown_kind, never run or hashed); a verify: kind (qa-executor: alias) is checked in one Selvedge run via the new ground-truth-verify.sh with per-check results and a Verify counts line; every kind-list copy updated and pinned. Phase 4.5 PASS after 2 fix rounds (prose/comment corrections only). Run fell back from the next-step driver to the legacy path at ACQUIRE (driver's git checkout main is refused when main is checked out in another worktree).

## Not verified
- **Supervisor Phase 4.5 ground-truth call on a brief with verify: lines** — stub tests and the V3 hand run only (subtask 1)
- **Plan Reviewer Criterion 14 on a brief with verify:/unknown_kind lines** — LLM prompt; only its text is pinned (subtask 2)
- **Phase 4.5 record_decision ground_truth line with the Verify suffix** — prompt prose; runner output reproduced in a scratch dir only (subtask 2)
