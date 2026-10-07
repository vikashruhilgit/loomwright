# 12 — Policy answers for routine lane questions, so the owner answers decisions, not formalities

## Status: parked (waits on item 05's lane inbox — Scope 13 `lane-answer` and `source: human|policy`)

## Depends on
05

## Touches
loomwright/scripts/lane-policy.sh
loomwright/scripts/test-lane-policy.sh
loomwright/docs/LANE_GATES.md
loomwright/skills/automate-loop/SKILL.md
loomwright/commands/automate.md
loomwright/docs/result-schemas/automate-run.md
changelog.d/parallel-automate-12-lane-policy-answers.md

## Problem
Owner goal: 5–10 lanes at once. In S1 v2, two lanes asked **15 questions in 10 deferred calls over about 2 hours**
(one every ~8 minutes). At 10 lanes that is about 75 questions per wave. Classifying v2's 15 by what the owner
actually decided:
- **Routine (8):** "start a new run" over a stale paused run (2); confirm a one-item queue (1); save a brief that
  Plan Review passed with 0 issues (1); keep or drop a LOW-only summary draft (3); proceed past the children-settled
  check when the only unsettled child is a finished non-plugin `Explore` agent, the known gap in
  `automate-followups/17` (1). The owner picked the recommended option every time.
- **Real decisions (7):** refine a brief carrying a MEDIUM finding; save-with-notes vs re-review on 4 LOW notes;
  an output-gate gap; four fix-now / follow-up picks on MEDIUM findings.

A second problem blocks any automation of the first: **the same gate is phrased differently each time.** v2-a's
resume gate had header `Resume` and option `Start new (Recommended)`; v2-b's had `Resume?` and `Start new run
(Recommended)`. Nothing stable identifies a gate or its options today.

## Goal
Each engine gate carries a stable id and canonical option labels. The owner can write a small, human-stamped
policy that pre-answers named routine gates; such answers are recorded as `source: policy`, listed for review, and
never cover a decision class the gate catalog marks human-only. Real decisions still reach the owner, batched.

## Scope
1. **Gate catalog** `loomwright/docs/LANE_GATES.md`: every `AskUserQuestion` the engine can raise in a lane
   (resume, queue confirm, Launch Pad Phase 6 save/refine, output gap, children-settled, pre-flight overlap,
   dismissed findings per severity, summary keep/drop, …) with a stable `gate_id`, its canonical option labels, and
   `policy: allowed | human-only`. Human-only, always: Plan Review FAIL or any MEDIUM-or-higher finding, an output
   gap, pre-flight OVERLAP, fix-now/follow-up/drop on MEDIUM-or-higher, anything that merges, deletes or pushes.
2. **Gates say who they are:** the engine's prose asks every catalogued gate with `header` = its short gate code
   and the catalog's exact labels (a `(Recommended)` marker stays allowed), so the defer hook can read
   `gate_id` and the options deterministically. A question with no known code is always human.
3. **Policy file** — tracked project config, the same store and the same human-stamp valve that `rules-check.sh`
   applies to a rule's `check` command (read `skills/rules/SKILL.md` §8; do not invent a second valve). Shape:
   `{gate_id: label}` for `policy: allowed` gates only. Unstamped, malformed or naming a human-only gate ⇒ ignored
   and reported, never partially applied (fail CLOSED toward asking the human).
4. **`lane-policy.sh decide <question.json>`**: prints the policy label or `human`. Item 05's defer hook calls it;
   on a label it writes the answer file through the same guarded `lane-answer` path with `source: policy`,
   `policy_sha`, and resumes the lane; on `human` the question goes to the inbox as today.
5. **Visible and revocable:** `lane-status` and the lanes pane show policy answers in a digest ("3 answered by
   policy since 09:00"), each with gate, label and time; the run file's `## Progress` records each one; removing the
   stamp turns all policy answering off at the next question.
6. **Batched inbox:** `lane-status` groups every lane's pending human questions in one list (oldest first), so the
   owner answers a round at a time.
7. **Tests:** a policy label is applied for an allowed gate and recorded `source: policy`; a human-only gate in the
   policy is ignored and reported; unstamped policy ⇒ every question goes to the human; an unknown header ⇒ human;
   a label not in the catalog ⇒ refused; the drifted v2 phrasings map to one gate id after Scope 2.

## Non-goals
- No model-judged answers: policy is an exact lookup, never an LLM decision.
- No policy for anything that merges, deletes, pushes or changes a finding's fate at MEDIUM or above.

## Acceptance criteria
- Replaying v2's 15 questions through `lane-policy.sh` with a policy covering the 8 routine gates sends exactly the
  7 real decisions to the human.
- With no stamped policy, behaviour is identical to item 05 (every question to the human).

## Validation (must pass before merge)
1. **Baseline:** full loop on base and branch, `<passed>/<total>` and `SKIP` counts.
2. **Unchanged path:** no policy file ⇒ the lane inbox round trip from item 05's tests passes unchanged.
3. **Running system:** one real lane with a stamped two-gate policy; paste the run file's policy lines and the
   inbox showing only the remaining human questions.
4. **A failure this must catch:** let a policy name a human-only gate and apply it ⇒ the test fails.
5. **Rollback:** `git revert`, or remove the stamp (instant off).

## Verified premises (re-check before starting)
- The 15 v2 questions and their answers: S1 run record, relays 1–8, and `ai-agent-manager-lanes-v2/v2-*/.supervisor/
  s1-questions/` + `s1-answers/` (answer files carry `source: human`, `via`).
- Item 05 Scope 13 already defines the answer file with `source: human|policy`.

## Evidence
S1 v2 run record (relays 1–8 and the v1/v2 comparison table).
- **Wave w1 (2026-10-04) adds a routine gate:** Phase 1.5 pre-flight returned OVERLAP with **0 open PRs**, only because 4 of the last 20 commits on `main` (all merged, all in the lane's own base `95e8601`) touched files the brief edits. The owner picked "Proceed anyway". A pre-flight OVERLAP whose every hit is already contained in the branch's base and has no open PR is a candidate for `policy: allowed`, or better, for pre-flight itself to classify as CLEAR, since "overlap with your own base" is not competing work. A pre-flight OVERLAP against an OPEN PR stays human-only.
- **Wave w1, more routine gates:** w1-10 asked about 3 dismissed-finding drafts whose findings were **already fixed on the PR** (named commits, regression tests added), each with "Drop (Recommended)". The owner dropped all three. A draft whose finding the lane can show fixed on the current head (commit plus test named) is a `policy: allowed` drop candidate. A draft whose fix cannot be shown stays human.
- **S3 wave 2 (2026-10-07, owner, relayed by S3 session 2216aefd) — the same gate asked inconsistently:** the
  stale-runs "Start new run?" question was asked by lane s3-f but NOT by s3-e or s3-g, all three in the same state
  (one other incomplete run). Evidence only; operator note for the brief: a policy can pre-answer only a gate that
  fires predictably, so whether this gate fires may need the same pinning as its phrasing (S3 record §"Wave 2
  result", gap 5).

## Touches re-pointed 2026-10-07 (S3 operator f849e0cc, after pa/11's split — #408, v15.124.0)
- `RESULT_SCHEMAS.md` → `result-schemas/automate-run.md`: the Scope names no block of its own; its schema text is the
  run file's `## Progress` policy-answer lines (Scope 5) and the `source: policy` answer record item 05 defines
  under §AUTOMATE_RUN.
