# Lane gate catalog

Every question the engine (`/automate`, `/autonomous`, and the Launch Pad, Supervisor and Product Owner flows they run inline) asks the owner through the host's ask tool is one **gate**. Each gate has a short stable **code**, its canonical option **labels**, and a **policy**:

- `allowed` — a routine formality. A human-stamped project policy or an owner-set wave policy may answer it in a lane, by exact lookup.
- `human-only` — a real decision. No policy ever answers it, whatever a policy file says. A Plan Review FAIL or NEEDS_HUMAN, any MEDIUM-or-higher finding, an output gap or adjudication, a pre-flight OVERLAP or SUPERSEDED, per-finding dismissed drafts and fix-now, close-out leftovers, Launch Pad clarification, NO-GO, the executable-acceptance stamp and memory facts, Supervisor INIT config, and anything that merges, deletes or pushes are all `human-only`.

**Authority.** The table below is a MIRROR. The one authoritative table is `loomwright/scripts/lane-policy.sh catalog` (TSV: `code<TAB>policy<TAB>labels-joined-by-|<TAB>purpose`). Change a gate there, then regenerate this table in the same change with `bash loomwright/scripts/lane-policy.sh catalog --markdown`. `loomwright/scripts/test-lane-policy.sh` parses this table back into TSV and fails when the two differ. It also fails on any code longer than 12 characters, the ask tool's `header` limit (`commands/dreaming.md`).

## How a gate says who it is

- The engine asks an `allowed` gate with `header` = its code and exactly the labels listed here. A `(Recommended)` marker is allowed on any label and is stripped before comparison.
- A `human-only` gate is asked with **no** code in its header. Its row exists so the catalog is complete and so a policy naming it can be recognised and dropped.
- A question whose `header` is not a catalog code is **always** human. So is a question whose labels, with `(Recommended)` stripped, are not exactly this row's labels as a set, a multi-select question, and any call that batches a human question with routine ones. A policy answer is all or nothing per call.

## Where a policy answer comes from

`lane-policy.sh resolve <parent_runfile> [--root <primary>]` runs in the PRIMARY checkout at `lane-create` and merges two sources. The wave source wins per code:

1. **Project policy** — `.agent/lane-policy.json`, tracked: `{"schema_version":1,"answers":{"<code>":"<label>",…}}`. It counts ONLY while it is stamped through the existing `rules-check.sh` stamp valve (`skills/rules/SKILL.md` §8 / §8.1; there is no second valve). Every one of these must hold:
   - a selected must-rule with id `lane-policy` exists (`rules-check.sh --list-selected`);
   - that rule's `binds` array names `.agent/lane-policy.json`. The rule is read with `jq` as data, and its `check` is never run here;
   - the policy file is git-tracked, so its content is part of the stamped hash;
   - `rules-check.sh --stamp-state` prints `stamp<TAB>match`.

   Otherwise the whole project policy is ignored and reported (`lane-policy: project policy ignored — <reason>`), never partially applied. A rule that fits: id `lane-policy`, `enforcement: must`, a check that always passes on a valid file (for example `jq -e .schema_version .agent/lane-policy.json`), `binds: [".agent/lane-policy.json"]`. The stamp hashes the WHOLE selected must-rule set, so editing the policy file, this rule or any other must-rule turns project answers off until a human re-runs `/rules check --confirm`.
2. **Wave policy** — `lane-policy.sh wave-set <parent_runfile> <code>=<label> …` writes `.supervisor/automate/<run_id>.wave-policy.json` and one parent `## Progress` line `wave policy: <code>=<label>, …`. The coordinator calls it only with the owner's own answers at wave planning. It refuses (exit 1, nothing written) a code that is not `allowed` or a label that is not one of that code's labels.

`resolve` keeps only `allowed` codes with valid labels and reports and drops anything else (`lane-policy: dropped <source> <code> — <reason>`). It prints `{"policy_sha": …, "sources": […], "answers": {…}}`. `policy_sha` is the sha256 of the compact, key-sorted JSON of `answers` (`null` when empty). `lane-create` carries that object into the lane's `lane.json` as `policy`, or `null` when nothing is answered.

`lane-policy.sh decide <question_json> --policy-json <lane.json>` is the lane's exact lookup. It prints `{"0":"<label>",…}`, each label being the question's own option label with any marker kept, only when every question in the call passes the rules above and has a policy answer. Otherwise it prints `human`. Codes are checked against this catalog three times: at `wave-set`, at `resolve` and at `decide`.

## Honest limits

- The wave policy file is not owner-authenticated. It has the same trust level as the lane answer-pending file.
- The stamp is keyed per clone, so a lane cannot verify it. Verification happens in the primary at `lane-create`. Removing the stamp turns policy answering off at the **next** `lane-create`, and a lane already created keeps the policy carried at creation.
- `lane.json` is writable inside the lane. The worst a tampered policy can do is answer an `allowed` gate with one of that gate's own labels: `decide` re-checks the catalog and the `policy_sha`.

## Catalog

<!-- lane-policy catalog: BEGIN (generated by `lane-policy.sh catalog --markdown` — do not hand-edit) -->
| Code | Policy | Labels | Purpose |
|---|---|---|---|
| `AUT-RESUME` | allowed | `Continue` · `Start new` · `Archive` | /automate start finds an incomplete run (automate-loop SKILL §4 step 4) |
| `AUT-QUEUE` | allowed | `Process` · `Stop` | /automate Queue confirm before processing (automate-loop SKILL §2 "--limit N") |
| `AUT-SUMMARY` | allowed | `Keep summary` · `Drop summary` | /automate keep or drop a LOW/INFO summary draft — summary drafts only (§6 dismissed-findings decision step and the PICK-time ask) |
| `LP-SAVE` | allowed | `Save and exit` · `Refine further` · `Edit sections` · `Discard` | Launch Pad Phase 6 save — carries this code ONLY on a Plan Review PASS with zero issues |
| `SUP-CHILDREN` | allowed | `proceed anyway` · `investigate` · `abort` | Supervisor FINALIZE Point 5 children unsettled (async-orchestration SKILL) |
| `AUT-SOURCE` | human-only | `(free text)` | bare /automate: what do you want to automate? |
| `AUT-PENDING` | human-only | `Follow-up (keep draft)` · `Drop` | /automate PICK-time decision on a per-finding dismissed draft |
| `AUT-DISMISS` | human-only | `Follow-up (keep draft)` · `Fix now on this PR` · `Drop` | /automate per-finding dismissed draft at the park, including fix-now |
| `AUT-LEFTOVER` | human-only | `Clean up now` · `Keep and continue` · `Stop` | /automate close-out leftover gate (cleans up or deletes) |
| `PO-ASSUME` | human-only | `Proceed anyway` · `Refine requirements` · `Abort` | Product Owner assumption-check soft gate (/automate prompt intake) |
| `LP-CLARIFY` | human-only | `(free text)` | Launch Pad Phase 2 clarification |
| `LP-NO-GO` | human-only | `Override and continue` · `Revise goal` · `Abort` | Launch Pad Phase 2.5 feasibility NO-GO |
| `LP-SAVE-NOTE` | human-only | `Save and exit` · `Refine further` · `Edit sections` · `Discard` | Launch Pad Phase 6 save on a Plan Review PASS that carries any issue or note (asked with no code) |
| `LP-NEEDHUMAN` | human-only | `Override and save` · `Refine further` · `Discard` | Plan Review NEEDS_HUMAN, or any MEDIUM-or-higher finding |
| `LP-EXEC-ACC` | human-only | `approve-and-stamp` · `strip-cmd-bullets` · `discard` | Launch Pad executable-acceptance stamp |
| `LP-FAIL` | human-only | `Refine offline` · `Discard` | Plan Review FAIL after the third attempt |
| `LP-MEMORY` | human-only | `(free text)` | Launch Pad project-memory candidate facts |
| `SUP-INIT` | human-only | `(free text)` | Supervisor INIT config (max workers, task) |
| `SUP-OVERLAP` | human-only | `proceed-anyway` · `revise-scope` · `abort` | Supervisor Phase 1.5 pre-flight OVERLAP or SUPERSEDED |
| `SUP-ADJ-GAP` | human-only | `A: Re-queue producer` · `B: Insert remediation subtask` · `C: Exit to Launch Pad` · `D: Update consumer brief` | Supervisor EXECUTE adjudication: an output gap (requires_gap) |
| `SUP-ADJ-LANE` | human-only | `A: Re-queue writer with the sibling lane excluded` · `B: Serialize the pair (add a requires edge)` · `C: Exit to Launch Pad` · `D: Widen the writer's declared lane` | Supervisor EXECUTE adjudication: a lane collision (lane_collision) |
| `SUP-GH-RETRY` | human-only | `retry` · `skip-verify-once` · `abort` | Supervisor FINALIZE PR-base verification after gh failed twice |
| `AN-RUBRIC` | human-only | `continue-to-next-iteration` · `merge-and-continue` · `stop-here` · `force-continue-anyway` | /autonomous rubric gate between iterations (merges or continues) |
| `AN-NO-RUBRIC` | human-only | `continue` · `stop` | /autonomous no-rubric gate |
| `AN-MERGE-VFY` | human-only | `merge-and-continue` · `stop-here` · `force-continue-anyway` | /autonomous merge-verify re-prompt |
| `AN-PR-BASE` | human-only | `retry` · `skip-verify-once` · `abort` | /autonomous PR-base verification after gh failed twice |
| `AN-ESCALATED` | human-only | `(free text)` | /autonomous review-heal ESCALATED |
<!-- lane-policy catalog: END -->
