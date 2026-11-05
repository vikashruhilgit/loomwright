# Supervisor Job: Ask once about files outside Touches and re-check lane overlap before coding starts

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (orphaned/stale worktrees under `.claude/worktrees/` and one prunable scratchpad worktree — none block a new worktree)
- **Source requirement:** .supervisor/requirements/2026-11-03-174840-lane-scope-regate.md
- **Base commit:** 993f8f31a82df00dcf3c2bf0e5ad2ed87041674f

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe scripts + markdown prompts + the `loomwright-lanes` TSX pane — all existing stack |
| 2 | Dependency Availability | GO | No new dependency; reuses `plan-waves --touches`, `_lanes_declared`, `_lanes_is_declared`, `gate-auto.sh`, the lane park/resume mechanics |
| 3 | Architecture Fit | CAUTION | Part B adds a new lane park (`scope_hold`) and a coordinator-side subcommand; a new lane state reaches every consumer of lane states, the optional `/lanes` pane included |
| 4 | Scope vs Supervisor Capability | CAUTION | ~25 files across two parts → needs a stated split (`context-bound`) |
| 5 | Hard Blockers | GO | None. The two Running-system Validation steps need a live `/launch-pad` and a live `/automate --parallel 2` on fixture items — achievable, but costly and easy to leave unrun |

**Overall Verdict:** CAUTION

## Task
**Goal:** Ask once about files outside Touches and re-check lane overlap before coding starts.

**Problem Statement:**
The plugin owner running `/automate` (sequential or `--parallel N`) needs every widening of an item past its `## Touches` to reach them as ONE question with the full list, and needs the coordinator to compare a lane's final file set with every other live lane of the wave before that lane writes code, because today (issue #808) one Launch Pad pass asked about outside-Touches files four times under four headers (two of them improvised, so no policy or `check-gate-headers.sh` could see them), a "Save and exit" silently accepted four more files, and two widened lanes then edited `kernel.ts` / `sessions/policy.ts` in parallel with nothing noticing until `wave-build`'s warn-only overlap check.
Success looks like: a re-run of an item like loomwright-studio item 06 shows one scope question with the full list; a replay of wave 3 of `automate-2026-11-02-150636` asks about the shared files before either lane writes code.

## Acceptance Criteria

### Part A — one question for files outside Touches (`LP-SCOPE`)
- [ ] A1. Given a brief whose files include paths outside the item's Touches (as `plan-waves <item> --touches` reads them, companions included), when Launch Pad reaches its save step (Phase 6), then it asks ONE question under the new catalog code `LP-SCOPE` with the complete outside-Touches list, BEFORE the `LP-SAVE` / `LP-SAVE-NOTE` question.
- [ ] A2. Given that question, then its options are one fixed label set covering extend / revise / stop (`Extend Touches` · `Revise plan` · `Stop`), and the code (policy `human-only`, per the owner decision — it moves to `allowed` only after Part B ships, which is NOT this change), labels and purpose appear in `lane-policy.sh catalog` and the regenerated `docs/LANE_GATES.md` table.
- [ ] A3. Given the owner chooses `Extend Touches`, then the brief records the accepted outside-Touches paths in ONE section a later reader can find (`## Scope widening`, one `- <path>` line per accepted path plus an `- accepted: LP-SCOPE <YYYY-MM-DD>` line), and the save question that follows (and its `gate-auto.sh decide` note/severity input) no longer mentions them.
- [ ] A4. Given every brief path is inside Touches, then no scope question is asked (zero new questions on the common path).
- [ ] A5. Given feasibility's only blocker is files outside Touches, then Launch Pad does not ask `LP-NO-GO`; the files are carried to the one `LP-SCOPE` question instead. A NO-GO for any other reason is unchanged.
- [ ] A6. Given the item's Touches is `unknown` (`plan-waves --touches` prints `unknown…`), then no scope question is asked.
- [ ] A7. Given Launch Pad needs a free-form answer that is not a catalog gate (a design or contract question such as item 06's `Grant form`), then it asks under `LP-CLARIFY`, never an improvised header — stated as a rule in `agents/launch-pad.md`'s Critical Rules.
- [ ] A8. Given the Touches set cannot be read (`plan-waves --touches` fails), then the scope question is still asked, listing every brief path and saying the declared set was unreadable — never silently skipped.
- [ ] A9. Given Launch Pad cannot ask (a subagent, or `--non-interactive`), then it takes a NAMED can't-ask branch that persists nothing it was not allowed to (save nothing, `status: aborted`, summary leading `scope_widening_non_interactive: <n> path(s) outside Touches`), and that branch is listed in `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" and in the Critical Rules' Can't-ask rule.
- [ ] A10. The outside-Touches list is computed by a deterministic helper, never by the model: `automate-lanes.sh scope-outside <item> <brief>` prints `inside`, `unknown`, or `outside <n>` / `unreadable <n>` followed by one path per line, reading Touches through `_lanes_declared`'s own `plan-waves --touches` call and comparing with `_lanes_is_declared` (the matcher `wave-build`'s overlap check uses).
- [ ] A11. Given the gate set changed, then `bash loomwright/scripts/test-lane-policy.sh`, `bash loomwright/scripts/check-gate-headers.sh` and `bash loomwright/scripts/check-token-budget.sh` pass (`header: "LP-SCOPE"` has an ask site; the Launch Pad agent/command budgets are re-measured in `loomwright/docs/prompt-token-budgets.json` and its `ARCHITECTURE_CONTRACTS.md` mirror rows).
- [ ] A12 (Running system, Part A Validation 2). Given a live `/launch-pad` on a fixture item whose ACs need one file outside its Touches, then a committed evidence file `docs/evidence/lane-scope-regate-one-question.md` contains the fixture, the command, the one `LP-SCOPE` question it asked (header, list, labels) and the save question that followed it, plus the column-0 line `Verdict: PASS for Validation 2`, and the PR body links to it.

### Part B — re-check lane overlap before coding starts (`AUT-OVERLAP`)
- [ ] B1. Given a lane (`.supervisor/lane.json` with `parallel` > 1) whose Launch Pad phase saved its brief, when the lane's driver reaches `plan-result` → `run`, then it does not start the Supervisor phase: after the pinned `launch-pad saved <brief>` line it parks the lane with `pause_reason: scope_hold` through `automate-helpers.sh current-set` (item `status` stays `running` — no new item status; `## Status: paused`), a park the lane run file survives a coordinator crash with, and the coordinator's `lane-wait` reports it. `current-set` accepts the value only because `scope_hold` joins `CURRENT_PAUSE_ENUM` in `automate-helpers.d/runfile.sh`.
- [ ] B2. Given a held lane, then the coordinator runs `automate-lanes.sh lane-scope-check <lane>`, which compares that lane's declared set (`_lanes_declared`: Touches + brief `path:` lines) with every other LIVE lane of the wave — a sibling with a saved brief by its `_lanes_declared` set, a sibling with no saved brief yet by its planner-reserved Touches only — using `_lanes_is_declared` in both directions (the same matcher as `wave-build`'s `_lanes_wave_overlap`), and prints `clear`, `overlap — <file> shared with <lane>…` lines, or `unreadable — <what>`.
- [ ] B3. Given `clear` and no pending widening, then the lane is released (`lane-scope-decide <lane> continue` with no question: one parent `## Progress` line `scope re-gate: <lane> clear`) and resumes into its Supervisor phase. Release mechanism: `lane-scope-decide` clears the park through `current-set` (`## Status: running`, `pause_reason: null`), writes one lane `## Progress` line `scope re-gate released (<decision>)`, and relaunches the lane with the existing `lane-launch <lane_dir> --continue --owner-command '<cmd>'`; the lane's driver resumes at `run` with the brief named by the pass's `launch-pad saved <brief>` line (`ns_segment_brief`) — never re-running PICK or the Launch Pad phase (except on `Revise`).
- [ ] B4. Given an overlap, then the owner gets ONE question from the coordinator under the new `human-only` code `AUT-OVERLAP` with labels `Serialize` · `Continue in parallel` · `Defer to next wave` · `Revise`, naming the lane, the other lane(s) and the shared files.
- [ ] B5. Given `Continue in parallel`, then the choice is recorded in the parent run file's `## Progress` (`scope re-gate: <lane> continue in parallel — shares <files> with <lanes>`) and the lane starts; given `Serialize`, then the lane stays held (`scope_wait: <other lane>` recorded) until the other lane reaches `ready_for_release`, and the coordinator then merges that lane's exact PR head into the held lane's branch (as `wave-build` merges an exact head) before releasing it; given `Defer to next wave`, then the item leaves this wave through the existing abandon path and is left unchecked in the parent Queue so the next `plan-waves` plans it into a later wave; given `Revise`, then the lane re-runs its Launch Pad phase, and that new save re-checks (B6).
- [ ] B6. Given a lane's brief is saved again (a re-plan), then the check runs again on the new set; and given lane X checked against lane Y's reserved Touches because Y had not saved yet, then Y's own later save re-checks against X (the check is two-way by construction: every save holds).
- [ ] B7. Given a single-lane run (`--parallel 1`, lane.json `parallel: 1`) or a sequential run (no lane.json), then no hold and no check happen (the driver goes `plan-result` → `run` exactly as today).
- [ ] B8. Given `--inline-phases` (no `launch-pad saved` line is written), then `skills/automate-loop/lanes.md` and `per-item-loop.md` state that limit and the run behaves as today; it is a stated limit, not a silent pass.
- [ ] B9. Given a lane under `--parallel N > 1`, then its Launch Pad does NOT ask `LP-SCOPE` itself: it records the outside-Touches list in the brief's `## Scope widening` section marked `- decision: pending-coordinator`, and the coordinator's re-gate asks at most ONE question about it — `AUT-OVERLAP` (its text also lists the widening) when an overlap exists, else `LP-SCOPE` relayed with the same list — so the owner is never asked twice about the same widening.
- [ ] B10. Given a lane's set cannot be read (brief or Touches unreadable), then `lane-scope-check` prints `unreadable — <what>` and the coordinator does NOT treat the lane as clear: it asks the owner under `AUT-OVERLAP` naming what was unreadable (fail CLOSED).
- [ ] B11. Given the coordinator session is gone while a lane is held, then the hold survives (it is the lane run file's park), `lane-status` (and `--json`, and the `/lanes` pane) shows the lane as `scope_hold` — a state the owner must act on, rendered as waiting — and `lane-status --inbox` lists it; `guard-lane-wait-armed.sh` blocks the coordinator's turn end while a `scope_hold` lane has no recorded decision.
- [ ] B12. Given the change, then `bash loomwright/scripts/test-automate-lanes.sh`, `bash loomwright/scripts/test-automate-next-step.sh`, `bash loomwright/scripts/test-lane-policy.sh` and `bash scripts/test-lanes-addon.sh` pass, including a case with two lanes whose saved briefs share a file; `bash scripts/ci-local.sh --affected` passes.
- [ ] B13 (Running system, Part B Validation 2). Given a live `/automate --parallel 2` on two fixture items whose declared Touches are disjoint but whose briefs share a file, then a committed evidence file `docs/evidence/lane-scope-regate-held-lane.md` contains the run's `lane-status` output showing the second lane held (`scope_hold`) before its Supervisor phase and the ONE coordinator `AUT-OVERLAP` question naming the shared file, plus the column-0 line `Verdict: PASS for Validation 2`, and the PR body links to it.

## Scope widening

> This brief's own plan needs files outside the item's `## Touches` (the very case Part A asks about; Part A is not yet shipped, so the owner sees them here and at the save question). Each is a CREATE or a registration line the new code needs:
- loomwright/scripts/automate-lanes.d/scope.sh — the new module (the separate concern; Module layout)
- loomwright/scripts/test-automate-lanes.d/08-scope-regate.sh — the new test part (the largest existing parts are past the 500-line threshold)
- loomwright/scripts/test-automate-lanes.sh — one `tal_part 08-scope-regate` line (parts are listed by name, never globbed)
- loomwright/scripts/test-automate-lanes-modules.sh — `MODS_WANT` gains `scope`, `ARMS` gains the three new arms (closed lists)
- loomwright/scripts/automate-helpers.d/runfile.sh — `scope_hold` in `CURRENT_PAUSE_ENUM` (else `current-set` refuses the park)
- loomwright/scripts/test-automate-helpers.d/15-lane-seams.sh — its pause_reason template tail pin
- loomwright/skills/automate-loop/run-file.md — the `- pause_reason:` template line and RUN-level parks row
- loomwright/docs/result-schemas/automate-run/sections-status-queue.md — the `paused` row
- docs/evidence/lane-scope-regate-one-question.md — Part A Validation 2 evidence
- docs/evidence/lane-scope-regate-held-lane.md — Part B Validation 2 evidence
- decision: pending-owner (Launch Pad Phase 6 save question)

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| gate catalog | `loomwright/scripts/lane-policy.sh` (469) · `loomwright/docs/LANE_GATES.md` (100, regenerated) · `loomwright/scripts/test-lane-policy.sh` (791 — appended: the single catalog suite) | — | HIGH |
| Launch Pad prompt | `loomwright/agents/launch-pad.md` (897 — appended: the single authority for Launch Pad's gates) · `loomwright/commands/launch-pad.md` (243) · `loomwright/docs/prompt-token-budgets.json` (re-measure) | — | HIGH |
| scope helper + re-gate | `loomwright/scripts/automate-lanes.sh` (422 — loader line, dispatch arms, header) · `loomwright/scripts/automate-lanes.d/readiness.sh` (543 — one added variable distinguishing `unknown` from unreadable; no new responsibility) | `loomwright/scripts/automate-lanes.d/scope.sh` (`scope-outside`, `lane-scope-check`, `lane-scope-decide`) | HIGH |
| driver hold | `loomwright/scripts/automate-next-step.sh` (3447 — appended: the per-item step table is its single home; the hold is one branch in `ns_plan_result`) · `loomwright/scripts/test-automate-next-step.d/05-fresh-phases.sh` (20) · `loomwright/scripts/automate-helpers.d/runfile.sh` (694 — one value in `CURRENT_PAUSE_ENUM`, no new responsibility; outside Touches) · `loomwright/scripts/test-automate-helpers.d/15-lane-seams.sh` (150 — the pause_reason template tail pin; outside Touches) | — | HIGH |
| lane state surfaces | `loomwright/scripts/automate-lanes.d/status-read.sh` (800 — AT the 800-line module cap: in-place regex edit only, zero net growth; the held-lane `--inbox` row's reader lives in `scope.sh` and is called from `_lanes_inbox` by replacing, not adding, lines) · `loomwright/scripts/automate-lanes.d/status.sh` (303) · `loomwright/scripts/guard-lane-wait-armed.sh` (154) · `loomwright-lanes/hooks/register.tsx` (1023 — appended: the WAITING set lives there) · `loomwright-lanes/tests/pane.test.tsx` (677 — appended beside the existing state pins) | — | MEDIUM |
| tests | `loomwright/scripts/test-automate-lanes.sh` (outside Touches — one part line) · `loomwright/scripts/test-automate-lanes-modules.sh` (313 — its closed `MODS_WANT` / `ARMS` lists; outside Touches) | `loomwright/scripts/test-automate-lanes.d/08-scope-regate.sh` | HIGH |
| docs | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1057 — appended: the Question-gate inventory and budget mirror live there) · `loomwright/docs/result-schemas/automate-run.md` (159) · `loomwright/skills/automate-loop/run-file.md` (81 — pause_reason template + RUN-level parks row; outside Touches) · `loomwright/docs/result-schemas/automate-run/sections-status-queue.md` (26 — the `paused` row; outside Touches) · `loomwright/skills/automate-loop/lanes.md` (103) · `loomwright/skills/automate-loop/per-item-loop.md` (114) | `changelog.d/2026-11-03-174840-lane-scope-regate.md` · `docs/evidence/lane-scope-regate-one-question.md` · `docs/evidence/lane-scope-regate-held-lane.md` | HIGH |

Touches files NOT planned to change (listed by the requirement, no change found necessary — a worker may touch them only if a test proves it): `loomwright/scripts/automate-lanes.d/phase.sh`, `relay.sh`, `wave.sh` (its `_lanes_wave_overlap` is reused through `_lanes_declared` + `_lanes_is_declared`, not edited), `test-automate-lanes.d/01-create-to-wait.sh`, `05-timeline-and-gate.sh`, `06-phase-sessions.sh` (new legs go to the new part 08).

> **Validator-owned surfaces:** `check-gate-headers.sh` (scans `agents/`, `commands/`, `skills/`, next-step emitters), `test-lane-policy.sh` (parses `LANE_GATES.md` back into TSV), `check-token-budget.sh` (`prompt-token-budgets.json` + the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror), `check-doc-currency.sh` — all in the map above.

**Total estimated files:** 25 modify + 5 create

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `993f8f31a82df00dcf3c2bf0e5ad2ed87041674f`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/lane-policy.sh`** — keep: the catalog is the ONE authoritative table (`_lp_row LP-FAIL` rows) and `_LP_POLICY_EXEMPT="LP-SAVE-NOTE"` unchanged; new rows are `human-only`, codes ≤ 12 chars; reuse: `_lp_row`; mirror: `docs/LANE_GATES.md` is regenerated with `lane-policy.sh catalog --markdown`, never hand-edited (`do not hand-edit`); pinned by: `loomwright/scripts/test-lane-policy.sh` (parses the table back into TSV).
- **`loomwright/agents/launch-pad.md`** / **`loomwright/commands/launch-pad.md`** — keep: every ask names a catalog code (`header: "LP-NO-GO"` form), the Can't-ask rule's closed key set (`validate-launch-pad-result.py --raw` blocks any unknown key — a named status rides in `summary` as its leading token), the `gate-auto.sh decide` auto answer for `LP-SAVE` / `LP-SAVE-NOTE` unchanged (LP-SCOPE runs before it); mirror: the command doc restates Phase 6 options (`LP-SAVE-NOTE`); pinned by: `check-gate-headers.sh`, `check-token-budget.sh` (`"launch-pad": {"budget"`), `test-rule-conformance-seam.sh` (`LP-RULE-OVR`).
- **`loomwright/scripts/automate-lanes.sh`** — keep: modules are `Listed by name, never globbed` (add `_lanes_source scope || { return 1 2>/dev/null || exit 1; }` between `# >>> automate-lanes.d/scope.sh` / `# <<<` markers so `_lanes_bundle` inlines it), the header's `# Modules (sourced in this order` list and its `lane-status state, first match wins` list updated; reuse: the `lanes_main` dispatch form (`phase-wait) lanes_phase_wait "$@" ;;`).
  pinned by: `loomwright/scripts/test-automate-lanes-modules.sh` — `MODS_WANT="common create launch relay remove notify-guards status-read park-leaks status evidence readiness wave phase"` gains `scope` in source order, `ARMS="lane-create:lanes_create` gains `scope-outside:lanes_scope_outside` (Subtask 1) and `lane-scope-check:lanes_scope_check`, `lane-scope-decide:lanes_scope_decide` (Subtask 2); every module stays `-le 800` lines.
- **`loomwright/scripts/automate-helpers.d/runfile.sh`** — keep: `current-set` validates every reason against `CURRENT_PAUSE_ENUM=" awaiting_merge` (add `scope_hold` before `live_lane`); `CURRENT_STATUS_ENUM` unchanged (the hold keeps item `status: running`); pinned by: `test-automate-helpers.d/15-lane-seams.sh` (`|live_lane|phase_relay_unavailable|null$` tail on `run-file.md` and `automate-run.md` — keep the tail exact by inserting `scope_hold` before `live_lane` in both templates).
- **`loomwright/skills/automate-loop/*.md`, `agents/launch-pad.md`, `commands/launch-pad.md`** — keep: `test-loop-inventory.sh` HEADING COVERAGE: new prose goes under EXISTING `###`/`####` headings; a new heading needs its row in `docs/loop-inventory/launch-pad-autonomous.md` / `automate-loop.md` in the same change (those inventory files then join the worker's lanes).
- **`loomwright/scripts/automate-lanes.d/readiness.sh`** — keep: `_lanes_declared`'s contract and its two consumers (scope fence + `wave.sh` `_lanes_wave_overlap`): `LD_TOUCHES=known; LD_NOTE=""` keeps exactly `known | unknown`; any distinction of an `unknown…` Touches from a failed `plan-waves --touches` is a NEW variable, never a third `LD_TOUCHES` value; reuse: `_lanes_is_declared() {` as the only matcher; pinned by: the scope-fence and overlap legs in `test-automate-lanes.d/02-readiness-to-convert.sh`.
- **`loomwright/scripts/automate-next-step.sh`** — keep: the pinned progress line `launch-pad saved $brief` written byte for byte BEFORE any hold (read by `progress-line-match.sh`), `ns_once` idempotence, and `NEXT=run; return 0` as the path for every non-lane and `parallel: 1` run; the hold reads lane.json `parallel` (written by `lane-create`: `parallel: $parallel`) and parks through the existing `current-set` park form; pinned by: `test-automate-next-step.d/05-fresh-phases.sh` (`leg_fresh_plan_mapping`).
- **`loomwright/scripts/automate-lanes.d/status-read.sh`** / **`status.sh`** — keep: status-read.sh is exactly 800 lines at base and `test-automate-lanes-modules.sh` caps every module at `-le 800` — zero net growth there; every reader fails SAFE (`an absent or unreadable source prints`); `_lanes_parked` already maps a non-null pause_reason to the state, so `scope_hold` needs no new arm there; the step-state mapping `test("^(awaiting_input|answer_pending|ready_for_release|awaiting_merge)$")` gains `scope_hold` (waiting on the owner); `_LANES_WAIT_LIVE='["created","running","held_for_load","answer_pending"]'` is NOT extended (a held lane is not live — `lane-wait` must report it as a `state <lane> scope_hold` event); `--inbox` gains the held-lane row.
- **`loomwright/scripts/guard-lane-wait-armed.sh`** — keep: `ALWAYS exits 0`, the documented Stop block shape (`{"decision":"block","reason":"…"}`), the live set `read from there, never restated`; add one block condition: a lane whose run file parks `scope_hold` with no recorded `lane-scope-decide` line.
- **`loomwright-lanes/hooks/register.tsx`** — keep: `const WAITING = new Set(['awaiting_input', 'answer_pending'])` semantics (add `scope_hold`, so the pane counts it as waiting for the owner and toasts it); the mod reaches Loomwright only through `lane-status` / `lane-feed` / `lane-answer`; pinned by: `loomwright-lanes/tests/pane.test.tsx`, run by `scripts/test-lanes-addon.sh`.
- **`loomwright/scripts/test-automate-lanes.sh`** — keep: parts sourced `by name` with `tal_part 07-evidence-files` form; the new part's first line is the standalone-refusal guard (`declare -F tal_pgrep >/dev/null && [ -n "${T:-}" ]`).

## Closed enumerations touched

> Sibling grep at base `993f8f3`: `git grep -n -F 'LP-RULE-OVR' -- ':!CHANGELOG.md'` → 13 hits in 7 files; `git grep -n -F 'held_for_load' -- ':!CHANGELOG.md'` → 39 hits in 16 files.

- **`LP-SCOPE`, `AUT-OVERLAP`** (sibling: `LP-RULE-OVR`) — must be named in:
  - `loomwright/scripts/lane-policy.sh` — the catalog (`_lp_row LP-RULE-OVR`) — extend.
  - `loomwright/docs/LANE_GATES.md` — the generated catalog table — extend (regenerate).
  - `loomwright/agents/launch-pad.md` — `LP-SCOPE` ask site (`header: "LP-SCOPE"`) and the Can't-ask rule — extend.
  - `loomwright/commands/launch-pad.md` — the Phase 6 mirror — extend.
  - `loomwright/skills/automate-loop/lanes.md` — the `AUT-OVERLAP` ask site (`header: "AUT-OVERLAP"`, every gate needs one) — extend.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — §"Question-gate inventory" — extend (one row each, with its can't-ask status).
  - `loomwright/docs/loop-inventory/launch-pad-autonomous.md` — a per-prose-question inventory row (`LP-145`), not a closed list every gate must appear in — no change.
  - `loomwright/scripts/test-rule-conformance-seam.sh` — 17c-specific pins — no change.
- **`scope_hold`** (pause_reason + lane state; sibling: `held_for_load` for the state, `phase_relay_unavailable` for the pause_reason — second grep: `git grep -n -F 'phase_relay_unavailable'`) — must be named in:
  - `loomwright/scripts/automate-helpers.d/runfile.sh` — `CURRENT_PAUSE_ENUM` (`current-set` refuses any other value) — extend.
  - `loomwright/skills/automate-loop/run-file.md` — the `- pause_reason:` template line and the RUN-level parks row — extend.
  - `loomwright/docs/result-schemas/automate-run/sections-status-queue.md` — the `paused` row — extend.
  - `loomwright/scripts/test-automate-helpers.d/15-lane-seams.sh` — template tail pin `|live_lane|phase_relay_unavailable|null$` — no change when `scope_hold` is inserted before `live_lane`; add one `current-set --pause-reason scope_hold` leg.
  - `loomwright/scripts/test-automate-lanes-modules.sh` — closed `MODS_WANT` / `ARMS` lists (for the new module and arms, not the value) — extend.
  - `loomwright/docs/result-schemas/automate-run.md` — the `pause_reason:` enum line (`phase_relay_unavailable|null`) and the field table — extend.
  - `loomwright/scripts/automate-lanes.d/status-read.sh` — the step-state `waiting` mapping — extend; `_lanes_parked` — no change (prints any non-null pause_reason).
  - `loomwright/scripts/automate-lanes.sh` — the header's `lane-status state, first match wins` list — extend.
  - `loomwright-lanes/hooks/register.tsx` — the `WAITING` set — extend.
  - `loomwright/skills/automate-loop/lanes.md` — the lane states/launch outcomes prose — extend.
  - `loomwright/scripts/automate-lanes.d/status.sh` — `_LANES_WAIT_LIVE` — no change (a held lane is not live; it is reported as a state event).
  - `loomwright-lanes/types/index.d.ts` — `state: string` (open) — no change.
  - `loomwright/scripts/fixtures/terse-output/lane-status/status.json`, `docs/loop-inventory/automate-loop.md`, `docs/rationale/automate-loop.md`, `launch.sh`, `relay.sh`, `test-automate-lanes.d/01`, `03` — `held_for_load`-specific (launch admission), not lists of every state — no change.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-lane-policy.sh` — LP-SCOPE / AUT-OVERLAP rows are `human-only` | change LP-SCOPE's catalog row policy in `loomwright/scripts/lane-policy.sh` from `human-only` to `allowed` |
| `08-scope-regate.sh` — `scope-outside` lists a brief path outside Touches | delete the `_lanes_is_declared` test in `scope-outside` (`loomwright/scripts/automate-lanes.d/scope.sh`) so every path reads inside |
| `08-scope-regate.sh` — Touches `unknown` ⇒ `unknown`, no list | make the `unknown` arm in `scope-outside` fall through to the outside listing |
| `08-scope-regate.sh` — `plan-waves --touches` failure ⇒ `unreadable <n>` + every brief path | make the unreadable arm print `inside` |
| `08-scope-regate.sh` — two lanes whose saved briefs share a file ⇒ `overlap — <file> shared with <lane>` | drop the reverse-direction `_lanes_is_declared` call in `lane-scope-check` |
| `08-scope-regate.sh` — a sibling with no saved brief is compared by its reserved Touches | pass an empty brief for every sibling regardless of whether one is saved — must still match through Touches; and delete the Touches half so the leg goes red |
| `08-scope-regate.sh` — an unreadable lane set ⇒ `unreadable — …`, never `clear` | make the unreadable branch of `lane-scope-check` print `clear` |
| `05-fresh-phases.sh` — lane.json `parallel: 2` ⇒ `launch-pad saved` line then the `scope_hold` park, no Supervisor spawn | delete the hold branch in `ns_plan_result` (`loomwright/scripts/automate-next-step.sh`) |
| `05-fresh-phases.sh` — lane.json `parallel: 1` / no lane.json ⇒ straight to `run` | change the hold's `parallel > 1` test to `parallel >= 1` |
| `08-scope-regate.sh` — `scope_hold` reads step state `waiting` in `lane-status --json` | remove `scope_hold` from the step-state waiting regex in `status-read.sh` |
| `08-scope-regate.sh` (or the guard's own suite) — coordinator turn end blocked while a `scope_hold` lane has no decision | delete the scope-hold condition in `loomwright/scripts/guard-lane-wait-armed.sh` |
| `15-lane-seams.sh` — `current-set --pause-reason scope_hold` accepted | remove `scope_hold` from `CURRENT_PAUSE_ENUM` in `loomwright/scripts/automate-helpers.d/runfile.sh` (the 05-fresh-phases hold leg goes red too) |
| `08-scope-regate.sh` — `lane-scope-decide <lane> continue` un-parks (pause_reason null) and relaunches with `--continue` | make `lane-scope-decide` skip its `current-set` call ⇒ the lane stays `scope_hold` |
| `05-fresh-phases.sh` — a released lane resumes at `run` with the saved brief, no second Launch Pad spawn | make the resume path ignore `ns_segment_brief` ⇒ a Launch Pad spawn appears |
| `loomwright-lanes/tests/pane.test.tsx` — `scope_hold` counts as waiting | remove `scope_hold` from the `WAITING` set in `loomwright-lanes/hooks/register.tsx` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Part A — `LP-SCOPE` gate, `scope-outside` helper, Launch Pad Phase 6/2.5 wiring | A1–A12 | 10 modify, 5 create | `skills/supervisor-readiness/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Part B — lane `scope_hold`, `lane-scope-check` / `lane-scope-decide`, `AUT-OVERLAP`, state surfaces | B1–B13 | 20 modify, 1 create | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-lanes.d/scope.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/scope.sh", name: "lanes_scope_outside"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "scope-outside"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "LP-SCOPE"}
  - {kind: "symbol", path: "loomwright/docs/LANE_GATES.md", name: "LP-SCOPE"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "scope_widening_non_interactive"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "## Scope widening"}
  - {kind: "file", path: "loomwright/scripts/test-automate-lanes.d/08-scope-regate.sh"}
  - {kind: "file", path: "changelog.d/2026-11-03-174840-lane-scope-regate.md"}
  - {kind: "file", path: "docs/evidence/lane-scope-regate-one-question.md"}
requires: []
lanes:
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/docs/LANE_GATES.md"
  - "loomwright/scripts/test-lane-policy.sh"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/automate-lanes.d/scope.sh"
  - "loomwright/scripts/automate-lanes.d/readiness.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes-modules.sh"
  - "loomwright/scripts/test-automate-lanes.d/08-scope-regate.sh"
  - "changelog.d/2026-11-03-174840-lane-scope-regate.md"
  - "docs/evidence/lane-scope-regate-one-question.md"
external_requires:
  - "a live claude session able to run /launch-pad on a fixture item (Part A Validation 2)"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/scope.sh", name: "lanes_scope_check"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/scope.sh", name: "lanes_scope_decide"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lane-scope-check"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "AUT-OVERLAP"}
  - {kind: "symbol", path: "loomwright/docs/LANE_GATES.md", name: "AUT-OVERLAP"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "scope_hold"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "scope_hold"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/status-read.sh", name: "scope_hold"}
  - {kind: "symbol", path: "loomwright/scripts/guard-lane-wait-armed.sh", name: "scope_hold"}
  - {kind: "symbol", path: "loomwright-lanes/hooks/register.tsx", name: "scope_hold"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/lanes.md", name: "AUT-OVERLAP"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "scope_hold"}
  - {kind: "file", path: "docs/evidence/lane-scope-regate-held-lane.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-lanes.d/scope.sh", name: "lanes_scope_outside"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "LP-SCOPE"}
  - {from: "1", kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "## Scope widening"}
lanes:
  - "loomwright/scripts/automate-lanes.d/scope.sh"
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.d/05-fresh-phases.sh"
  - "loomwright/scripts/automate-helpers.d/runfile.sh"
  - "loomwright/scripts/test-automate-helpers.d/15-lane-seams.sh"
  - "loomwright/skills/automate-loop/run-file.md"
  - "loomwright/docs/result-schemas/automate-run/sections-status-queue.md"
  - "loomwright/scripts/test-automate-lanes-modules.sh"
  - "loomwright/scripts/automate-lanes.d/status-read.sh"
  - "loomwright/scripts/automate-lanes.d/status.sh"
  - "loomwright/scripts/guard-lane-wait-armed.sh"
  - "loomwright-lanes/hooks/register.tsx"
  - "loomwright-lanes/tests/pane.test.tsx"
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/docs/LANE_GATES.md"
  - "loomwright/scripts/test-lane-policy.sh"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/commands/launch-pad.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/skills/automate-loop/lanes.md"
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/scripts/test-automate-lanes.d/08-scope-regate.sh"
  - "changelog.d/2026-11-03-174840-lane-scope-regate.md"
  - "docs/evidence/lane-scope-regate-held-lane.md"
external_requires:
  - "a live claude session able to run /automate --parallel 2 on two fixture items (Part B Validation 2)"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `lane-policy.sh`, `LANE_GATES.md`, `test-lane-policy.sh`, `agents/launch-pad.md`, `commands/launch-pad.md`, `prompt-token-budgets.json`, `ARCHITECTURE_CONTRACTS.md`, `automate-lanes.sh`, `scope.sh`, `08-scope-regate.sh`, the changelog fragment | YES (legal: 2 is reachable from 1 via `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1 — it extends Subtask 1's module, catalog rows and `## Scope widening` contract)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/supervisor-readiness/SKILL.md` (brief sections the new `## Scope widening` joins), `skills/unit-testing/SKILL.md` |
| 2 | `skills/automate-loop/SKILL.md` + `skills/automate-loop/lanes.md` (lane park / resume / wave mechanics), `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): a new lane park/state reaches every consumer of lane states, the `/lanes` pane included | MEDIUM | `scope_hold` is a pause_reason, so `_lanes_parked` already surfaces it; extend only the closed lists in §"Closed enumerations touched"; `bash scripts/test-lanes-addon.sh` covers the pane |
| Feasibility (Phase 2.5): ~25 files in one PR | HIGH | `context-bound` split into two ordered subtasks; Part B builds on Part A's module and catalog rows |
| A hold that is never released stalls the wave | HIGH | The hold is a run-file park (survives the coordinator), shown by `lane-status`/`--inbox`, reported by `lane-wait`, and blocks the coordinator's Stop via `guard-lane-wait-armed.sh` until a `lane-scope-decide` line exists |
| "Serialize" needs a new piece (merge the other lane's exact head into the held lane's branch before release) | MEDIUM | Reuse `wave-build`'s exact-head merge form; a merge conflict stops and asks the owner (never force-resolved); test with two fixture lanes |
| The model computing a set difference wrongly | MEDIUM | Deterministic `scope-outside` helper (A10); Launch Pad only renders its output |
| `agents/launch-pad.md` / `commands/launch-pad.md` grow past their token budgets | MEDIUM | Re-measure with `check-token-budget.sh` in the same change; keep the new Phase 6 action tight and cite `LANE_GATES.md` instead of restating labels |
| Both Running-system Validation steps are numbered `2` (one per Part) in the merged requirement; the `/automate` validation gate may not tell them apart | MEDIUM | One evidence file per Part, each with `Verdict: PASS for Validation 2`; if the gate reads the step as unrun, the owner decides at the `AUT-WAIVE` park |
| Running-system validations are live, costly runs and easy to leave unrun | MEDIUM | Fixture items under a scratch requirements dir; record the exact commands and outputs in the evidence files |
| A concurrent session in this checkout runs `git checkout -- <file>` on files under edit (project memory) | LOW | Work in the Supervisor worktree only; commit early |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-04-lane-scope-regate.md
```

## Plan Review: PASS (attempt 2/3, requirement_fit: fulfils)

Saved by the owner's "Save and exit" at `LP-SAVE-NOTE`. Issues still open (below the HIGH fix floor; `deferred` — the Supervisor worker resolves them and Phase 4.5 checks them):

| # | Severity | Section | Description | Resolution |
|---|----------|---------|-------------|------------|
| 1 | MEDIUM | File Impact Map | The driver-hold legs (parallel:2 hold, parallel:1 / no lane.json, resume at `run` via `ns_segment_brief`) belong in `loomwright/scripts/test-automate-next-step.sh` (the runner that defines every leg `05-fresh-phases.sh` calls), which is not in the map or lanes. Add it (outside Touches) or define the legs inside the part, with the reason | deferred |
| 2 | MEDIUM | AC B5 | `Defer to next wave`: `lane-remove --abandon` writes its abandon record only for a `gone` lane, and a `scope_hold` lane has no PR. Build the smallest new piece (`lane-scope-decide defer` releasing the item's claim so the next `plan-waves` plans it again) and pin it (mutation: skip the un-claim ⇒ the item is not re-planned) | deferred |
| 3 | MEDIUM | AC B5 | `Serialize`: name the ref the other lane's exact head merges into while the held lane has no feature branch yet (the lane clone's checked-out base before Supervisor ACQUIRE), state how Phase 1.5 PRE-FLIGHT SYNC treats a base ahead of `origin/<base>`, and pin the release | deferred |
| 4 | MEDIUM | Touched-file invariants | `15-lane-seams.sh` also pins `run-file.md`'s RUN-level parks row (`` `meta_unreachable`, `closeout_leftover`, `live_lane` | `current-set <rf> --pause-reason <reason>` ``): insert `scope_hold` before `meta_unreachable`, never between `closeout_leftover` and `live_lane` | deferred |
| 5 | MEDIUM | Closed enumerations touched | `loomwright/docs/result-schemas/schema-versioning.md` (the AUTOMATE_RUN additive-value log) needs one additive-value line for `scope_hold` | deferred |
| 6 | LOW | Subtask Structure | The per-subtask Est. Files counts do not match the lanes (S1: 11 modify + 4 create; S2: ~26 lanes) | deferred |
| 7 | LOW | AC B3 | `lanes.md`: a `lane-scope-decide` release via `lane-launch --continue` does not count as the lane's one stall `--continue` | deferred |

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-04T19:36:04Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/822
- **Branch:** feature/lane-scope-regate
- **Files changed:** 33
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 1
- **Heal reason:** needs_human
- **Heal remaining issues:** 3
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Part A (LP-SCOPE gate, deterministic scope-outside helper, Launch Pad Phase 6 one-question wiring) and Part B (scope_hold lane park, lane-scope-check / lane-scope-decide, AUT-OVERLAP gate, inbox/json/pane/Stop-guard surfaces) shipped in PR #822. Review iteration 1 found 3 HIGH; fix 82f3f61 made the brief-path reader skip external_requires and re-ran A12 live (Verdict: PASS). Iteration 2 returned NEEDS_HUMAN: B13's live run held both lanes but asked LP-SCOPE first and then 2 AUT-OVERLAP questions in one call, so its verdict and B9's "never asked twice" are the owner's call. Required check ci is red on test-token-ledger.sh (concurrency leg), which also fails on main at the base commit.

## Not verified
- **A12 live /launch-pad after the action 1a wording fix** — superseded: the fix-1 live re-run passed (Verdict: PASS); the "a LOW note remains ⇒ LP-SAVE-NOTE" case was not exercised (subtask 1)
- **ci-local.sh --affected after the vendor-coupling fix** — the failing gate passed alone; later --affected runs were green (subtask 1)
- **B13 live /automate --parallel 2 run** — run live in fix-1 but no verdict: LP-SCOPE was asked first, then one call carrying 2 AUT-OVERLAP questions; owner judges (subtask 2)
- **full scripts/ci-local.sh pool** — workers ran --affected only; GitHub CI shard 1 red on test-token-ledger.sh, also red on main (subtask 2)
