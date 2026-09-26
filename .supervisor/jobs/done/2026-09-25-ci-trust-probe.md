# Supervisor Job: CI trust — live infra probe on red required checks, fail-CLOSED (`ci_untrusted`)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: automate-hardening-2026-09-22 (worktree; the run's isolation branch, base main @ ee09946)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/harness-port/07-ci-trust-probe.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | One new bash script (`ci-run-probe.sh`, fail-safe/read-only, `gh api .../jobs` + jq) matching this repo's existing script conventions, plus markdown skill/doc/agent edits. |
| 2 | Dependency Availability | GO | No new dependency; reuses `gh api`, `jq` — both already used throughout `review-heal/SKILL.md`'s existing GraphQL/REST reads. |
| 3 | Architecture Fit | GO | Extends the EXISTING fail-CLOSED discipline already governing §U2 required-check discovery (unavailable metadata ⇒ ESCALATED, never a silent READY) with a NEW evidence-based classification for a red required check specifically — precedent-following, not novel plumbing. |
| 4 | Scope vs Supervisor Capability | GO | 6-file, single cohesive transport-chain change (one new script + its call site in the drain loop + the schema field it emits + the gate condition that must fail-closed on it + doc/command mirrors). Every file depends on the same `checks_untrusted[]` / `ci_untrusted` shape — splitting would only add coordination overhead. |
| 5 | Hard Blockers | GO | No migration, no credentials beyond the already-required `gh auth`, no missing modules. |

**Overall Verdict:** GO

## Task
**Goal:** For every RED REQUIRED check in the owned `/review-pr --until-mergeable` drain, probe the run once (steps count, runner assignment, known-infra-failure annotation patterns) and classify it `untrusted_infra` when the evidence says nothing ran — never re-classify a green check, never exclude an untrusted check from READY-blocking. When the ONLY remaining READY-blockers are `untrusted_infra` checks, the drain terminates `ESCALATED` with `termination_reason: ci_untrusted`, naming each check and suggesting (never executing) `gh run rerun <id> --failed`.

**Problem Statement:**
A required check can be red for reasons unrelated to the diff — the job never started (account billing/spending block, ~2–4s at startup), it was queued and never assigned a runner (cancelled), or a reviewer action skipped itself and exited 0. The drain today treats check conclusions as ground truth: a never-ran red check is healed against as if it were a real test failure. A previously-considered fix (a dated CLAUDE.md note) was rejected by the owner (decision H3) — it tells the drain nothing about THIS run, and the owner's own records show such notes going stale within hours.

## Acceptance Criteria
- [ ] `loomwright/scripts/ci-run-probe.sh` (new, fail-safe, read-only): input = a check-run's `detailsUrl`/run id + repo; output = ONE jq-built JSON object `{check, verdict: "ran"|"untrusted_infra"|"unknown", reason, steps_count, runner_assigned, annotation_match}` on stdout, **always exits 0**. `gh` missing/unauthenticated/rate-limited ⇒ `verdict: "unknown"`. Evidence rules (ANY one ⇒ `untrusted_infra`): `steps_count == 0`; no runner ever assigned (`runner_name` null AND `started_at` null, OR conclusion `cancelled` with 0 steps); an annotation or job `message` matching the FIXED generic pattern list `account payments|spending limit|billing|quota|rate limit exceeded|workflow validation error|not started` (GitHub's own generic strings — no project/account/repo names baked in). `unknown` is explicitly NOT `untrusted_infra` — an unreadable probe never claims infra-fault. Exactly ONE `gh api repos/<owner>/<repo>/actions/runs/<run_id>/jobs` call per red required check, bounded by `--max-probes 5` (default), no pagination.
- [ ] `loomwright/scripts/test-ci-run-probe.sh` (new): fixture JSON cases — `steps_count: 0` ⇒ `untrusted_infra`; a real failing job (real steps, real failure) ⇒ `ran`; an annotation-pattern match ⇒ `untrusted_infra` with the matched reason; `gh` stubbed to fail/timeout ⇒ `unknown`, exit 0 in every case (never non-zero).
- [ ] `loomwright/skills/review-heal/SKILL.md` §U2.5 Wait-For-Settled-Checks / §U4 (the bounded drain loop): after the settled-checks read, for EACH red required check, run the probe (bounded by `--max-probes`). `untrusted_infra` ⇒ append `{check, reason, run_id}` to `checks_untrusted[]`; do NOT spawn a fix worker for it; do NOT count it as a validated/dismissed finding. Because an `untrusted_infra` verdict means the required check's true state is UNKNOWN (not green), the round CANNOT reach READY on it — when the only remaining READY-blockers are `untrusted_infra` checks, the drain terminates `ESCALATED`, `termination_reason: ci_untrusted`, and the notification text names each check + its reason + `"re-run when infra is healthy: gh run rerun <id> --failed"` (suggested text only — see Non-goals). `ran` and `unknown` verdicts leave existing behaviour byte-identical (a `ran` red check is still healed normally; an `unknown` red check still blocks READY the way an unclassified red check already does today). Green required checks are NEVER probed (probing is red-check-only, bounded work). Add one sentence to the READY redefinition section stating the invariant explicitly: "an `untrusted_infra` required check is not green; READY is unreachable while one exists." Re-measure `review-pr`'s token budget live (`loomwright/docs/prompt-token-budgets.json`) — do not trust the source requirement's cited "1737" figure (live figures at brief-authoring time: budget 34614, measured 33893, headroom 721 — already stale) and raise + mirror in `ARCHITECTURE_CONTRACTS.md` only if breached by the added prose.
- [ ] `loomwright/docs/RESULT_SCHEMAS.md` §REVIEW_HEAL_RESULT (v2 drain fields, OPTIONAL/additive, NO schema_version bump — matching the existing convention for `channels_scanned`/`findings_dismissed`/`dismissed`): add `checks_untrusted: [{check: string, reason: string, run_id: string|null}]` (absent when empty — never `[]` on the wire), and extend the `termination_reason` enum documentation (currently `converged | bound_hit | sub_floor_converged | null` at the field's definition, its field-contract table row, and its "ESCALATED" terminal-state bullet — all THREE citation sites, not just one) to also include `ci_untrusted`.
- [ ] `loomwright/skills/automate-loop/SKILL.md` §10 ("Trusted auto-merge gate") — Plan Review caught this genuine enum-consumer missing from the source requirement's own "read every consumer" instruction: this section's `ctx.json` shape documentation (`"termination_reason": "converged|bound_hit|sub_floor_converged"`) and its restating prose both need `ci_untrusted` added — this section explicitly calls itself "the SPEC gate-eval implements," so it must stay in sync with the header-comment enum update above.
- [ ] **`loomwright/scripts/automate-helpers.sh` gate-eval — VERIFY FIRST for PARK logic, but the header-comment enum update below is UNCONDITIONAL.** Plan Review confirmed (read the actual function, `gate_eval()` around line ~595-608) that **Condition 1 already requires `drain_result == "READY"` before any other check runs** (`if [ "$drain_result" != "READY" ]; then echo "PARK: drain_not_ready"; return 0; fi`) — and per this item's own Scope §2, a `ci_untrusted` termination ALWAYS pairs with `decision: ESCALATED`, never `READY`. So a `ci_untrusted` ctx should already PARK via the pre-existing `drain_not_ready` path with NO new PARK-logic code needed in `gate_eval()` itself. Confirm this by reading the function in full (including the Condition-1b `sub_floor_converged` special-case immediately below it, and the artifact cross-check that follows) — if a genuine PARK-logic gap exists, fix it fail-closed. **Regardless of that verification's outcome, unconditionally update the header-comment enum documentation at `automate-helpers.sh:503`** (`# "termination_reason": "converged|bound_hit|sub_floor_converged",  # cond 1b`) to include `ci_untrusted` — this is both accurate documentation of the now-4-value enum AND what makes this subtask's `provides:` entry for this file genuinely satisfiable (a `ci_untrusted` string literal must appear in the file for `verify-provides.sh`'s symbol grep to find it, independent of whether any PARK-logic branch changed).
- [ ] `loomwright/scripts/test-automate-helpers.sh`: new test case — a `ctx.json` with `drain_result: "ESCALATED"` (or, as a defense-in-depth mutation control, a deliberately-malformed `drain_result: "READY"` + `termination_reason: "ci_untrusted"` combination, to prove even a hypothetically-corrupted ctx can't merge on this reason) both PARK. Assert the printed reason.
- [ ] `loomwright/commands/review-pr.md` Parameters/outcome prose: name the new terminal reason `ci_untrusted` alongside the existing `termination_reason` enum mentions (memory: `agent-command-mirror-drift-on-fixes` — `check-command-sync.sh` does not cover this prose, so it must be synced by hand). Check `loomwright/agents/review-pr.md` too, if it independently restates `termination_reason`.
- [ ] `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` → the same five sanctioned surfaces (this item touches none of them).
- [ ] `grep -rn 'gh run rerun' loomwright/scripts` → 0 hits (the re-run command is suggested in notification/doc TEXT only, never constructed or executed by any script).
- [ ] `grep -nE 'date -d|date -j|stat -' loomwright/scripts/ci-run-probe.sh` → 0 hits (no BSD/GNU `date` flag divergence, no `stat` portability trap — this script needs no timestamp arithmetic at all per its evidence rules).
- [ ] CHANGELOG.md gains one paragraph; `plugin.json` + `marketplace.json` version bump (patch — additive, non-breaking; current version 15.100.0 → 15.101.0, re-verify live at implementation time in case another item merged first). README.md/CLAUDE.md are NOT touched.
- [ ] `scripts/check-token-budget.sh` green (review-pr re-measured, raised only if breached); full test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh`) green; `scripts/check-doc-currency.sh` green.

## Non-goals (from the source requirement — do not implement)
No CLAUDE.md dated note (the rejected H3 approach). No date arithmetic anywhere (the BSD/GNU `date -d`/`date -j` trap this repo's own CLAUDE.md documents as a machine-level lesson). No READY exemption for an `untrusted_infra` check — it still blocks READY, just with an honest classification instead of a false heal-attempt. No change to which checks are required (§U2 stays fail-CLOSED, untouched). No re-run triggered by the drain itself — `gh run rerun` is suggested to the human in notification text only, NEVER constructed or executed by any script (an unattended re-run under an active billing block would burn the same exhausted quota). Green-but-silent reviewer runs (the workflow-validation self-skip case) are already covered by the existing `no_review_lens_posted` / Earned Fallback Review mechanism — do not duplicate that; cross-reference it if relevant.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Parallelism Analysis
- **Mode:** single-agent (no fan-out) — one LAUNCHABLE subtask, no dependents, no file-conflict/context-bound/genuine-parallelism reason to split (see Feasibility #4).
- **Recommended workers:** 1

## Skill References
| Skill | Justification |
|---|---|
| quality-checklist | Standard pre/post-implementation quality gates for any worker task. |
| review-heal | Authority for the `/review-pr --until-mergeable` drain's §U2/§U2.5/§U4 required-check machinery this item extends, and the `READY`/`ESCALATED` terminal-state contract. |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | CI trust probe: new fail-safe read-only script → drain §U2.5/§U4 classification + ESCALATED/ci_untrusted termination → schema fields → gate-eval verification/test → doc/command mirror | all | 6 modify, 2 create | quality-checklist, review-heal | LAUNCHABLE |

```yaml
# Subtask 1 — CI trust probe, end-to-end (LAUNCHABLE)
subtask_id: ci-trust-probe-01
title: "CI trust: live infra probe on red required checks, fail-CLOSED ci_untrusted classification"
lanes:
  - loomwright/scripts/ci-run-probe.sh
  - loomwright/scripts/test-ci-run-probe.sh
  - loomwright/skills/review-heal/SKILL.md
  - loomwright/skills/automate-loop/SKILL.md
  - loomwright/docs/RESULT_SCHEMAS.md
  - loomwright/scripts/automate-helpers.sh
  - loomwright/scripts/test-automate-helpers.sh
  - loomwright/commands/review-pr.md
  - loomwright/agents/review-pr.md
  - loomwright/docs/prompt-token-budgets.json
  - loomwright/docs/ARCHITECTURE_CONTRACTS.md
  - CHANGELOG.md
  - loomwright/.claude-plugin/plugin.json
  - .claude-plugin/marketplace.json
requires: []
external_requires: []
provides:
  - {kind: "file", path: "loomwright/scripts/ci-run-probe.sh"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "checks_untrusted"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "ci_untrusted"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "ci_untrusted"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "checks_untrusted"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "ci_untrusted"}
out_of_lane: []
```

## File Impact Map
- **Modify:** review-heal/SKILL.md, automate-loop/SKILL.md (§10's `ctx.json` example + prose enum — Plan Review caught this missing; that section is its own text's "SPEC gate-eval implements"), RESULT_SCHEMAS.md, automate-helpers.sh (header-comment enum unconditionally; PARK logic only if a genuine gap is found), test-automate-helpers.sh, review-pr.md (command), review-pr.md (agent, if it restates the enum), prompt-token-budgets.json (+ possibly ARCHITECTURE_CONTRACTS.md), CHANGELOG.md, plugin.json, marketplace.json.
- **Create:** ci-run-probe.sh, test-ci-run-probe.sh.

## Risk Assessment
- **False-positive `untrusted_infra` classification would let a genuinely-broken CI run escalate as "infra fault" and get suggested for a blind re-run.** Mitigation: the evidence rules are deliberately narrow (zero steps, no runner ever assigned, or a matched GENERIC GitHub-native string) — a check that ran real steps and genuinely failed is never `untrusted_infra`, verified by the AC's own "real failed job ⇒ ran" fixture and the "byte-identical to origin/main" AC for that case.
- **The gate-eval Scope item may already be satisfied by existing code (see the AC's own verify-first instruction).** Risk: the worker blindly adds redundant/conflicting logic instead of confirming the existing `drain_not_ready` path already covers this. Mitigation: the AC explicitly requires reading the function first and being honest in the File Impact Map about whether a code change was actually needed.
- **`--max-probes 5` bound must be genuinely enforced, not just documented** — an unbounded probe loop on a PR with many red required checks would multiply `gh api` calls unpredictably. Mitigation: this is a hard AC (bounded, no pagination), test it directly with >5 red-check fixtures if easy to construct.

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1

## Handoff
Run: `/supervisor job: .supervisor/jobs/pending/2026-09-25-ci-trust-probe.md`

## Environment Validation
- ✓ `gh` authenticated, ✓ `jq` available, ✓ existing `test-automate-helpers.sh` present as an extension point for the gate-eval test case.
