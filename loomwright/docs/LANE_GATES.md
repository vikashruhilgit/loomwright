# Lane gate catalog

Every question the engine (`/automate`, `/autonomous`, and the Launch Pad, Supervisor and Product Owner flows they run inline) asks the owner through the host's ask tool is one **gate**, and so is each per-item stamp question of `/backlog --verify`. Each gate has a short stable **code**, its canonical option **labels**, and a **policy**, one of three tiers:

- `allowed` — a routine formality. A human-stamped project policy or an owner-set wave policy may answer it in a lane, by exact lookup.
- `auto` — a formality whose catalog-designated answer (its `!` label) is applied **without asking**, in and out of a lane, by the deterministic helper `loomwright/scripts/gate-auto.sh` — unless one of its escalation triggers fires (§"The `auto` tier" below). Which gates are `auto` is read from the catalog's `policy` column; no other surface lists them. A policy answers an `auto` gate only where `lane-policy.sh`'s `_lp_policy_answerable` allows it: the `auto` codes that were `allowed` before the tier existed stay policy-answerable exactly as before, and the codes in its `_LP_POLICY_EXEMPT` list never are.
- `human-only` — a real decision. No policy ever answers it, whatever a policy file says. A Plan Review FAIL or NEEDS_HUMAN, any MEDIUM-or-higher finding, an output gap or adjudication, a pre-flight OVERLAP or SUPERSEDED, per-finding dismissed drafts and fix-now, close-out leftovers, waiving an unrun running-system Validation step, Launch Pad clarification, NO-GO, the executable-acceptance stamp, a house-rule override and memory facts, Supervisor INIT config, a requirement status stamp (`/backlog --verify`), and anything that merges, deletes or pushes are all `human-only`.

**Authority.** The table below is a MIRROR. The one authoritative table is `loomwright/scripts/lane-policy.sh catalog` (TSV: `code<TAB>policy<TAB>labels-joined-by-|<TAB>purpose`). Change a gate there, then regenerate this table in the same change with `bash loomwright/scripts/lane-policy.sh catalog --markdown`. `loomwright/scripts/test-lane-policy.sh` parses this table back into TSV and fails when the two differ. It also fails on any code longer than 12 characters, the ask tool's `header` limit (`commands/dreaming.md`).

## How a gate says who it is

- The engine asks **every** gate it does not auto-answer, `allowed`, `auto` and `human-only` alike, with `header` = its code and exactly the labels listed here. A `(Recommended)` marker is allowed on any label and is stripped before comparison. A human-only code only names the gate: `decide` never answers it, whatever a policy says.
- A label ending in `?` is optional, and the `?` is not part of it. The ask offers either every label or only the ones without `?`, never another subset. `LP-SAVE` uses it: a PASS on the last Plan Review attempt leaves no attempt to refine or edit, so that ask offers `Save and exit` · `Discard`, and a policy answer still applies to it.
- A label ending in `!` is the **auto label** of an `auto` row — the one answer `gate-auto.sh` applies — and the `!` is not part of it either. Every `auto` row carries exactly one `!` label and no other row carries any, so a reader that strips only `?` (the `SUP-*` emitter in `supervisor-next-step.sh`) never meets one. Every reader that compares catalog labels to an ask strips both markers; this table keeps them raw.
- `loomwright/scripts/check-gate-headers.sh` fails an engine ask that drifts from this table: prose under `agents/`, `commands/` or `skills/` that spells out a gate's options without naming its code, a `header:` that is not a catalog code or whose block lacks one of its labels, a gate with no `header: "<code>"` ask site at all, and an empty `header: ""` in a next-step emitter.
- A question whose `header` is not a catalog code is **always** human. So is a question whose labels, with `(Recommended)` stripped, are not exactly this row's labels as a set, a multi-select question, and any call that batches a human question with routine ones. A policy answer is all or nothing per call.

## The `auto` tier

`loomwright/scripts/gate-auto.sh decide <code> [--offered <label>]… [--recommended <label>] [--max-severity BLOCKING|HIGH|MEDIUM|LOW|NONE] [--risk-paths <file>] [--risk-diff <base> <head>] [--destructive] [--runfile <path>] [--off] [--root <dir>]` prints exactly one line: `answer <label>` (the row's `!` label) or `ask <trigger>`. The engine calls it only on a path that would otherwise ask the owner. A run that cannot ask (non-interactive, or prose running inside a subagent) keeps its own named can't-ask status, unchanged. Any one trigger means the gate is asked, and every trigger is a deterministic read — never a model's confidence:

- `off` — the off switch: `--off`, a `- auto_gates: off` line in the run file's `## Run Config` (any value but `on` reads off), `auto_gates: false` in the lane's `.supervisor/lane.json`, or `{"auto_gates": false}` in `.supervisor/config.json` (read with `has("auto_gates")`, so a `false` never collapses to "unset").
- `not_auto` — the code's catalog policy is not `auto`. `allowed` and `human-only` codes are never answered by this helper.
- `label` — the offered labels, `(Recommended)` stripped, are not exactly the row's labels or its non-`?` core; or `--recommended` names a label other than the `!` label; or the row has no `!` label.
- `destructive` — `--destructive`: the answer would delete, discard, merge or push.
- `severity` — `--max-severity` is `MEDIUM` or higher, or is unparseable; for `LP-SAVE-NOTE` a missing value asks too.
- `high_risk` — `classify-risk.sh` reports `high_risk: true` **or `null`** over `--risk-paths` (its `--paths` mode) or `--risk-diff` (its refs mode). No risk flag ⇒ no risk read.

An error (no `jq`, an unknown code, an unreadable catalog, `--root`, run file, `lane.json` or config) prints `ask <reason>`: the tier fails toward asking, never toward an answer. Per gate, the risk read is: `LP-SAVE` / `LP-SAVE-NOTE` — `classify-risk.sh --paths` over the brief's File Impact Map paths; `AUT-RESUME` — the refs diff of the run's open PR, and no risk read when it has none; `AUT-QUEUE` — none.

Every decision leaves a record. `gate-auto.sh record <runfile> <code> <label> <reason> [--item <item>]` appends one `## Progress` line `auto-answered <code>: <label> — <reason>[ (item <item>)]`; `gate-auto.sh record <runfile> <code> --escalated <trigger> [--item <item>]` appends `auto-escalated <code>: <trigger>[ (item <item>)]`. Both are fail-safe (exit 0), and with no run file (a standalone `/launch-pad`) the line is printed on stdout instead. `gate-auto.sh list <runfile>` prints the block the owner reads at every park and at the run's end: `Auto-answered gates (<n>):` and one row per `auto-answered` line, or nothing at all when there are none.

**Owner decision.** `LP-SAVE-NOTE` left `human-only` for the `auto` tier by the owner's deliberate decision, made on the evidence that its recommended `Save and exit` was taken every time it was asked. It moved to the `auto` tier only: it is listed in `_LP_POLICY_EXEMPT`, so `wave-set`, `resolve` and `decide` still refuse it and no policy answers it, escalated or not.

## Where a policy answer comes from

`lane-policy.sh resolve <parent_runfile> [--root <primary>]` runs in the PRIMARY checkout at `lane-create` and merges two sources. The wave source wins per code:

1. **Project policy** — `.agent/lane-policy.json`, tracked: `{"schema_version":1,"answers":{"<code>":"<label>",…}}`. It counts ONLY while it is stamped through the existing `rules-check.sh` stamp valve (`skills/rules/SKILL.md` §8 / §8.1; there is no second valve). Every one of these must hold:
   - a selected must-rule with id `lane-policy` exists (`rules-check.sh --list-selected`);
   - that rule's `binds` array names `.agent/lane-policy.json`. The rule is read with `jq` as data, and its `check` is never run here;
   - the policy file is git-tracked, so its content is part of the stamped hash;
   - `rules-check.sh --stamp-state` prints `stamp<TAB>match`.

   Otherwise the whole project policy is ignored and reported (`lane-policy: project policy ignored — <reason>`), never partially applied. A rule that fits: id `lane-policy`, `enforcement: must`, a check that always passes on a valid file (for example `jq -e .schema_version .agent/lane-policy.json`), `binds: [".agent/lane-policy.json"]`. The stamp hashes the WHOLE selected must-rule set, so editing the policy file, this rule or any other must-rule turns project answers off until a human re-runs `/rules check --confirm`.
2. **Wave policy** — `lane-policy.sh wave-set <parent_runfile> <code>=<label> …` writes `.supervisor/automate/<run_id>.wave-policy.json` and one parent `## Progress` line `wave policy: <code>=<label>, …`. The coordinator calls it only with the owner's own answers at wave planning. It refuses (exit 1, nothing written) a code that is not policy-answerable (an `allowed` code, or an `auto` code outside `_LP_POLICY_EXEMPT`) or a label that is not one of that code's labels.

`resolve` keeps only policy-answerable codes with valid labels and reports and drops anything else (`lane-policy: dropped <source> <code> — <reason>`). It prints `{"policy_sha": …, "sources": […], "answers": {…}}`. `policy_sha` is the sha256 of the compact, key-sorted JSON of `answers` (`null` when empty). `lane-create` carries that object into the lane's `lane.json` as `policy`, or `null` when nothing is answered.

`lane-policy.sh decide <question_json> --policy-json <lane.json>` is the lane's exact lookup. It prints `{"0":"<label>",…}`, each label being the question's own option label with any marker kept, only when every question in the call passes the rules above and has a policy answer. Otherwise it prints `human`. Codes are checked against this catalog three times: at `wave-set`, at `resolve` and at `decide`.

## Honest limits

- The wave policy file is not owner-authenticated. It has the same trust level as the lane answer-pending file.
- The stamp is keyed per clone, so a lane cannot verify it. Verification happens in the primary at `lane-create`. Removing the stamp turns policy answering off at the **next** `lane-create`, and a lane already created keeps the policy carried at creation.
- `lane.json` is writable inside the lane. The worst a tampered policy can do is answer a policy-answerable gate with one of that gate's own labels: `decide` re-checks the catalog and the `policy_sha`.
- `AUT-QUEUE` is auto-answered with no risk read: no item is picked yet, so there is nothing to classify. Its triggers are the off switch and the label check only.
- `classify-risk.sh --paths` runs only the path, trusted-root and project `paths[]` classes over the listed paths; content and size cannot be judged from a path list. The check is an allow-list: a line holding any byte outside `[A-Za-z0-9._/+@-]` (backticks, bold, quotes, `:40`, `(40)`, a markdown link or a `|` cell, as in a copied `` `CLAUDE.md` (40) `` cell), a leading `/`, an empty or `.`/`..` segment, or a line wrapped in `_…_`, reads `null` (`paths_malformed`), so it escalates `high_risk`. A real path with another legal byte (`,`, `=`, `~`, `%`, a space) reads `null` too: the gate asks, the safe direction. Its class (b) flags any path under `agents/`, `commands/`, `skills/` or `hooks/`, so in an agent-orchestration repo (this one) most briefs still escalate `LP-SAVE` / `LP-SAVE-NOTE` to the owner. That is accepted, not a bug.
- The tier moves the rubber stamp rather than removing it: the owner sees every auto-answer only in the `gate-auto.sh list` block at a park or at the run's end, after the fact.

## Catalog

<!-- lane-policy catalog: BEGIN (generated by `lane-policy.sh catalog --markdown` — do not hand-edit) -->
| Code | Policy | Labels | Purpose |
|---|---|---|---|
| `AUT-RESUME` | auto | `Continue!` · `Start new` · `Archive` | /automate start finds an incomplete run (automate-loop SKILL §4 step 4); auto only with one incomplete run and no rebuilt ## Current, risk read from its open PR diff |
| `AUT-QUEUE` | auto | `Process!` · `Stop` | /automate Queue confirm before processing (automate-loop SKILL §2 "--limit N"); auto with no risk read (no item is picked yet) |
| `AUT-SUMMARY` | allowed | `Keep summary` · `Drop summary` | /automate keep or drop a LOW/INFO summary draft — the fallback only: dismissed-drafts recorded follow-up automatically on every summary draft (drop one by deleting it from proposed/), so this asks only when that auto-keep was refused (§6 dismissed-findings decision step and the PICK-time ask) |
| `LP-SAVE` | auto | `Save and exit!` · `Refine further?` · `Edit sections?` · `Discard` | Launch Pad Phase 6 save on a Plan Review PASS with zero issues (Refine / Edit only while a review attempt is left); auto unless the File Impact Map paths are high-risk |
| `SUP-CHILDREN` | allowed | `proceed anyway` · `investigate` · `abort` | Supervisor FINALIZE Point 5 children unsettled (async-orchestration SKILL) |
| `AUT-SOURCE` | human-only | `(free text)` | bare /automate: what do you want to automate? |
| `AUT-PENDING` | human-only | `Follow-up (keep draft)` · `Drop` | /automate PICK-time decision on a per-finding dismissed draft — the fallback only: PICK records every undecided draft follow-up automatically, so this asks only about a draft whose automatic follow-up was refused (§6 dismissed-findings decision step) |
| `AUT-DISMISS` | human-only | `Fix none (follow-up all)` · `Fix all listed on this PR` · `Fix selected on this PR?` | /automate ONE batched ask at the park over the MEDIUM+ per-finding dismissed drafts while a fix-now re-drain is available (every other draft is followed up with no question); Fix selected names the draft numbers in the answer note and is offered only when two or more are listed (§6 dismissed-findings decision step) |
| `AUT-LEFTOVER` | human-only | `Clean up now?` · `Keep and continue` · `Stop` | /automate close-out leftover gate (cleans up or deletes; Clean up now is offered only when a cleanup is possible) |
| `AUT-WAIVE` | human-only | `Waive this step` · `Keep parked` | /automate READY park: waive a running-system Validation step validation-gate reports unrun (owner words from the answer note; cannot ask ⇒ stays escalated, validation_unrun) |
| `AUT-OVERLAP` | human-only | `Serialize` · `Continue in parallel` · `Defer to next wave` · `Revise` | /automate --parallel N>1 coordinator scope re-gate: a lane held scope_hold after its Launch Pad save shares files with another live lane of the wave (or its set is unreadable); ONE ask naming the lane, the other lanes, the shared files and any pending widening; answered through lane-scope-decide; cannot ask ⇒ the lane stays held |
| `PO-ASSUME` | human-only | `Proceed anyway` · `Refine requirements` · `Abort` | Product Owner assumption-check soft gate, pre-persist house-rule check and missing-proof (no Validation) flag (/automate prompt intake) |
| `PO-RULE-MUST` | human-only | `Refine requirements` · `Change the rule via /rules` · `Abort` | Product Owner pre-persist house-rule check on a must-rule conflict (no override option: a must rule is never overridden) |
| `LP-CLARIFY` | human-only | `(free text)` | Launch Pad Phase 2 clarification |
| `LP-NO-GO` | human-only | `Override and continue` · `Revise goal` · `Abort` | Launch Pad Phase 2.5 feasibility NO-GO |
| `LP-SCOPE` | human-only | `Extend Touches` · `Revise plan` · `Stop` | Launch Pad Phase 6, before the save question: ONE ask listing every brief path outside the item Touches (automate-lanes.sh scope-outside); Extend records them in the brief ## Scope widening section; human-only by owner decision; cannot ask ⇒ scope_widening_non_interactive, nothing saved |
| `LP-SAVE-NOTE` | auto | `Save and exit!` · `Refine further?` · `Edit sections?` · `Discard` | Launch Pad Phase 6 save on a Plan Review PASS that carries any issue or note (Refine / Edit only while a review attempt is left); auto by owner decision unless an issue is MEDIUM or higher or the File Impact Map paths are high-risk, never answered by a policy |
| `LP-NEEDHUMAN` | human-only | `Override and save` · `Refine further?` · `Discard` | Plan Review NEEDS_HUMAN, or any MEDIUM-or-higher finding (Refine only while a review attempt is left) |
| `LP-EXEC-ACC` | human-only | `approve-and-stamp` · `strip-cmd-bullets` · `discard` | Launch Pad executable-acceptance stamp |
| `LP-RULE-OVR` | human-only | `record-override` · `honor-rule` · `discard` | Launch Pad Plan Review 17c: an AC contradicts an advisory house rule with no owner override (owner words from the answer note; cannot ask ⇒ rule_conflict_non_interactive) |
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
| `BL-VERIFY` | human-only | `Stamp done?` · `Stamp done with escalation?` · `Abandon` · `Skip` | /backlog --verify per-item stamp of an item with no merge evidence (the stamp options only when a merged PR is named; cannot ask ⇒ verify_requires_owner, nothing stamped) |
| `BL-CONFLICT` | human-only | `Abandon` · `Keep open` · `Skip` | /backlog --verify per-item settle of a conflict item (an abandoned/skipped Queue row vs its own pending/ready; cannot ask ⇒ verify_requires_owner, nothing stamped) |
| `JAN-ACT` | human-only | `(free text)` | /janitor: which actionable report rows to act on (multi-select, nothing pre-selected), and the second confirmation before a force-unlock; cannot ask ⇒ report only, nothing acted on |
<!-- lane-policy catalog: END -->
