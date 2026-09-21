# 00 — Review-gate brief-conformance queue overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp is the ONLY thing `resolve-folder` honours, so it is what keeps `/automate` from enqueuing this file)

**Origin:** 2026-09-13 Reddit review of the plugin: *"curious if the review step actually diffs a worker's
output against the brief, or if it's more presence based, like it exists mainly so a human has to click
approve. those two versions break really differently once something's actually under pressure."*
Owner validated the question against the code the same day and accepted both fixes ("fix this in the next
release"). Reply promised: brief criteria fed to the gating reviewer + manager re-verifies deliverables.

## What the code does today (verified 2026-09-13 — cite, do not re-derive)
| Layer | Reads the brief? | Gates? | Where |
|---|---|---|---|
| Per-subtask `outputs_verified` | yes — `provides:` presence only (`test -f` / `grep -nE`) | yes | `agents/worker.md` §"After writing the summary file: verify own `provides:`"; consumed by `agents/execute-manager.md` §"v12 outputs_verified gate" and `agents/supervisor.md` Single-Agent Path step 3 / Sequential Path |
| Phase 4.5 Code Reviewer | **no** — spawn prompt carries BASE_BRANCH, diff target, PRIOR-CHURN and HOUSE-RULES lines; no brief path, no criteria | yes — `heal_decision` derives ONLY from its `CODE_REVIEW_RESULT` | `skills/self-heal-advisory/SKILL.md` §"Review-and-fix loop" spawn prompt |
| Rubric Grader | yes — `## Outcomes Rubric` vs diff | advisory (`/autonomous` multi-iter re-plan; `/automate --auto-merge` cond 5 only) | same skill §"Outcomes Rubric grading" |
| Ground truth | yes — `## Executable Acceptance` runs | never (`"advisory only — heal_decision unchanged"`) | same skill §"Ground-truth execution" |

Two facts drive the two items:
1. The gate is worker-**self-reported**: Execute Manager parses the worker's claim (`check_run: "worker
   self-verification (Step 5.5)"`) and never re-runs the checks on disk. A dead worker leaves the gate with
   no input at all (memory `outputs-verified-silent-noop-on-dead-worker`).
2. The only blocking LLM lens never sees what was asked for, so clean work that drifted from the brief passes
   both gates and lands as `PASS` with a low `rubric_score` nobody acts on.

## Decisions taken (owner, 2026-09-13)
| # | Decision | Why |
|---|---|---|
| R1 | **No new gate.** Both items make the EXISTING gates stop trusting inputs they shouldn't. `heal_decision` still derives only from `CODE_REVIEW_RESULT`; the advisory-only status of rubric / ground_truth / contract_conformance is UNCHANGED. | CLAUDE.md §Failure-Mode Invariants; NORTH_STAR "Nothing gating". Making ground-truth failures block is a separate decision, deliberately NOT in this queue. |
| R2 | Brief conformance enters the reviewer as an **enrichment line** shaped exactly like PRIOR-CHURN / HOUSE-RULES, and unaddressed criteria are ordinary findings (`category: new`, severity per rule in 01) so they flow into the existing fix loop unchanged. | Reuses the seam that already exists; no new schema field, no new parser. |
| R3 | The manager-side re-check is a **script** (`scripts/verify-provides.sh`), deterministic, no LLM, run against the worktree/checkout the worker wrote to; its on-disk result is authoritative over the worker's `outputs_verified`. | A grep costs nothing; a prompt-level "re-check" would be the same self-report one hop later. |
| R4 | Standalone `/review-pr` (`review-heal`) is OUT of scope — it is keyed to a PR URL and has no brief. | Different entry point, different contract; noted as a follow-up, not smuggled in. |
| R5 | High-risk is a **park condition with no override** — not a flag, not a config key, not a project-side exclude list. Projects may only ADD risk surfaces. | The commenter's point: an opt-out re-creates the leak. Trust stays a per-PR function of six booleans; nothing accumulates. |

## Order
01, 02 and 03 are independent — may run in parallel. All ship in the same release bump (CHANGELOG top entry).

**03 origin (second external comment, 2026-09-13):** *"trust probably shouldn't be one number across the whole
repo … auth, payments, or a migration … deserve to stay behind manual review indefinitely."* Verified: the gate
has NO trust score (5 per-PR booleans — the "streak buys trust" mechanism cannot occur), but it IS path-blind;
the existing `high_risk` heuristic feeds only the advisory red-team lens, never the merge gate.

| Item | Delivers | Closes |
|---|---|---|
| 01 brief-conformance-in-phase45-review | BRIEF-CONFORMANCE enrichment line in the Phase 4.5 reviewer spawn prompt + mirror in `agents/code-reviewer.md` + seam test | gating reviewer blind to the brief |
| 02 manager-reverifies-provides | `scripts/verify-provides.sh` + consumer wiring in execute-manager poll loop and supervisor inline paths + tests | self-reported deliverable gate; dead-worker silent no-op |
| 03 high-risk-park-in-trusted-merge-gate | `scripts/classify-risk.sh` (+ committed `.agent/risk.json` add-only extension) + 6th fail-closed `gate-eval` condition, NO override flag | path-blind auto-merge: auth/payments/migrations merge on the same conditions as a lint fix |

## /automate handling
- 01, 02 and 03 are normal code-change items — one file = one item.
- Every new script is fail-SAFE as an emitter (always exit 0, reason on stderr) but its CONSUMER fails CLOSED
  toward the adjudication checkpoint on unreadable/missing output — see item 02's invariant block.
- Prompt files are programs: state-trace the changed spawn prompts (memory `feedback_prompt_is_program_state_trace`);
  sync `commands/*.md` prose if any flag/enumeration changes (memory `agent-command-mirror-drift-on-fixes`).
