# Supervisor Job: Merge one parked awaiting_merge item through the existing gate (`/automate --merge-parked <run_id>`)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-11-06-131342/L1 (lane L1 of `--parallel 2` run automate-2026-11-06-131342)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (source requirement is gitignored under `.supervisor/*`, so its provenance is not git-verifiable — expected for this repo's handoff dir)
- **Source requirement:** .supervisor/requirements/2026-11-05-192934-merge-one-parked-item-through-the-gate.md
- **Base commit:** d42212f2beb5880501c6e656156ca7014696d6c5

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + BSD userland + jq + `gh`, exactly the driver's stack |
| 2 | Dependency Availability | GO | `gh api` (compare `behind_by`, issue comments, reviews, review comments) already used by helpers; `run-lock.sh`, `closeout`, `gate-eval`, `queue-checkoff`, `remaining` all exist |
| 3 | Architecture Fit | GO | a new driver entry beside `--resume` / `--start`, reusing `ns_gate_eval`, `ns_reconcile_merged`'s closeout, `ns_checkoff`, `ns_awaiting_go`, `ns_terminate`'s done branch |
| 4 | Scope vs Supervisor Capability | CAUTION | 16 files (13 modify + 3 create, > 12) ⇒ `context-bound` split into 2 subtasks |
| 5 | Hard Blockers | CAUTION | Validation 2 needs a freshly parked `vikashruhilgit/studio-sandbox` item and the p14 probe (`probes/p14-loomwright-merge-one-parked-item.md` in `vikashruhilgit/loomwright-studio`, verified present); PR 822 (same hotspot) is MERGED (2026-11-05), so the branch-after-822 risk is cleared |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add a one-time driver entry `automate-next-step.sh --merge-parked <run_id>` (owner command `/automate --merge-parked <run_id>`) that re-enters ONE item parked `awaiting_merge`, checks its READY is still current, runs the existing `automate-helpers.sh gate-eval` unchanged, and on `MERGE` finishes the item through the normal closeout (with trail) + CHECK OFF, then stops — no drain, no lane, no next item, `## Run Config` stays `mode: safe`.

**Problem Statement:**
An owner (or Loomwright Studio's opt-in "merge when ready" playbook) with an `/automate` item parked `awaiting_merge` needs one documented command that puts that item through the existing `--auto-merge` gate, because safe mode parks a ready PR and the docs name only a human merge.
Currently, `--resume <run> --auto-merge` parks again without merging: `ns_reconcile` routes an open PR to `ns_reconcile_open` → `ns_open_pr_park` with no mode check (`gate-eval` is reached only via `ns_after_validation` after a drain); the resume entry resets `NS_STATE='{}'`, wiping `ready_sha` (stored nowhere else), so condition 2 would always park `head_sha_moved`; condition 7 pins the checkout to the live head; the normal merge tail (`ns_sync` → `closeout --no-trail`, `ns_terminate` → `running`) would continue the loop and strand the trail; the flag is silently recorded as `flag_mode: auto-merge` while doing nothing; and condition 3 cannot see a late PR comment. This blocks two Studio phase 8 items (issue vikashruhilgit/loomwright#829).
Success looks like: p14 answers yes on a fresh sandbox item — one invocation merges, finishes the item, starts no drain and needs no hand edit.

## Acceptance Criteria

**Happy path**
- [ ] AC1 — Given an item parked `awaiting_merge` whose READY is current and whose seven conditions hold, when `--merge-parked <run_id>` runs, then `gate-eval` prints `MERGE`, the PR is squash-merged by `gate-eval` alone, closeout runs with its trail, and the item is checked off with no hand edit.
- [ ] AC2 — Given items remain after that merge, when the entry finishes, then `## Status: paused`, `pause_reason: awaiting_go`, and no item is picked.
- [ ] AC3 — Given no items remain, when the entry finishes, then the run reaches the existing done termination, trail included.
- [ ] AC4 — Given any outcome, when the entry finishes, then `## Run Config` still reads `mode: safe` and no drain, lane or phase session was spawned (no `{"do":"spawn"}` instruction is ever printed by this entry).

**Edge cases**
- [ ] AC5 — Given a parked item, when `--resume` runs first and `--merge-parked` after, then the ctx handed to `gate-eval` carries the recorded `ready_sha`, `drain_result: READY` (from `## Current`'s `owned_drain_result: READY`) and the recorded `termination_reason` (a test pins all three: the sidecar wipe cannot lose a gate input).
- [ ] AC6 — Given a fix-now re-drain that ended READY on a new head, when the entry runs, then the recorded `ready_sha` and `termination_reason` are the re-drain's (the `- ready_sha:` line is rewritten in place by the re-drain's `drain-result`, never appended twice).
- [ ] AC24 — Given a READY report with no `ready_sha`, when the drain result is recorded, then no `- ready_sha:` line is written. Given `## Current` moves to another item (item-form `current-set`), then the line is dropped.
- [ ] AC7 — Given the live head differs from the recorded `ready_sha`, when the entry runs, then it parks `PARK: head_sha_moved`, says a person must decide, and spawns nothing.
- [ ] AC8 — Given a PR comment or review newer than `ready_at`, when the entry runs, then it parks with a named reason and `gate-eval` does not run.
- [ ] AC9 — Given `behind_by` > 0 for the PR's base (GitHub compare API — never `mergeStateStatus`), when the entry runs, then it parks with a named reason and `gate-eval` does not run.
- [ ] AC10 — Given the checkout is not on the PR head, when the entry runs, then it parks naming the branch to check out, and HEAD and the working tree are unchanged.
- [ ] AC11 — Given a live merge watcher, when the entry merges, then one closeout does the work, the check-off appears once, and the watcher exits without a second closeout (a test covers the watcher polling during the merge — it reads `closeout: skipped — run lock held`, transient — and after it).
- [ ] AC12 — Given a condition parks, when the entry finishes, then the run stays `awaiting_merge` with its `PARK: <reason>` recorded in `## Progress`, exactly one watcher is live, and the run lock is released.
- [ ] AC13 — Given undecided per-finding dismissed drafts, when the entry merges, then they stay pending for the next interactive PICK, as after any `--auto-merge` `MERGE`.
- [ ] AC14 — Given `--resume --auto-merge` on a parked open PR, when it parks, then the message names `--merge-parked` and says the flag was not applied, and `flag_mode` is not recorded in the sidecar. Behaviour on a run with no open PR is unchanged.

**Error scenarios**
- [ ] AC15 — Given a run parked before this change (no recorded `ready_sha`), when the entry runs, then it parks with a named reason and never substitutes the live head.
- [ ] AC16 — Given `## Current` is anything but `awaiting_merge` with a READY drain (`escalated`, `ready_for_release`, `running`, `done`), when the entry runs, then it refuses naming the status and writes nothing.
- [ ] AC17 — Given a lane (`.supervisor/lane.json`) or a `--parallel` parent (`## Run Config` `parallel: N`), when the entry runs, then it refuses by name and writes nothing.
- [ ] AC18 — Given the PR already reads MERGED, when the entry runs, then it closes the item out with no gate and no merge. Given it reads CLOSED, then it reports it the way RECONCILE does and never checks the item off.
- [ ] AC19 — Given `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`, when it runs on the branch, then every path is a surface `skills/automate-loop/invariants.md` already enumerates.

**Durable READY record + docs**
- [ ] AC20 — Given a drain (first or fix-now re-drain) ends READY, when `drain-result` records it, then `## Current` carries one `- ready_sha: <sha> | ready_at: <ISO-8601 Z> | termination_reason: <tr>` line (written through `ns_current_line` → `runfile-write`; a READY report with no `ready_sha` writes NO line, so AC15's park still applies and the live head is never substituted), and an item-form `current-set` that changes the item drops that line (mirroring the `escalation_cause` drop in `runfile.sh`); `skills/automate-loop/run-file.md` states that any input a later session's gate pass needs lives in the run file, never only in the sidecar.
- [ ] AC21 — Given the docs, when read, then `commands/automate.md`, `skills/automate-loop/resume.md` (a section titled exactly `### Merging one parked item`), `run-file.md`, `helpers.md`, `docs/result-schemas/automate-run.md` and `docs/loop-inventory/automate-loop.md` (the new steps and park reasons) describe the entry, and the token budgets (with their `ARCHITECTURE_CONTRACTS.md` mirror rows) pass `check-token-budget.sh`.

**Validation (evidence-file form)**
- [ ] AC22 — Given `bash scripts/ci-local.sh --affected` and `bash scripts/check-version-bump.sh`, when run on the branch, then both pass (incl. `check-token-budget.sh`, `check-doc-currency.sh`, `check-prompt-history-refs.sh`, `test-citation-drift.sh`), with a `changelog.d/merge-one-parked-item.md` fragment and no hand-edited version file.
- [ ] AC23 — Given this branch's plugin copy and a NEW item parked `awaiting_merge` on `vikashruhilgit/studio-sandbox`, when it is re-entered per `probes/p14-loomwright-merge-one-parked-item.md` (`vikashruhilgit/loomwright-studio`), merging only through the gate, then a committed evidence file `docs/evidence/merge-one-parked-item.md` contains the fenced command output showing one invocation merged, finished the item, started no drain and needed no hand edit, with the column-0 line `Verdict: PASS for Validation 2`, and the PR body links to it.

## Scope widening
- loomwright/scripts/fixtures/automate-golden/learning-emit-end-of-drain/expected.md
- accepted: AUT-OVERLAP 2026-11-06

> Why: grepping every golden case's `next-step.results` for a drain report that carries both `review_heal_result` and `ready_sha` finds exactly two cases, `dismissed-fix-now-re-drain` (already in Touches) and `learning-emit-end-of-drain` (its drain ends `decision: READY`). Only cases that go through the `drain-result` step write the new line; the `gate-eval-*` cases hand `--result` straight to GATE and gain nothing.

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
| driver | `loomwright/scripts/automate-next-step.sh` (3518 — appended: it is the single reader/writer of the run file from resume to the item's end and has no module loader; the new entry reuses ~10 of its private `ns_*` helpers, so a separate file would need a loader this story does not own) | — | HIGH |
| run-file writer | `loomwright/scripts/automate-helpers.d/runfile.sh` (694 — extends `current_set`'s existing per-item-line drop, the single authority for `## Current` item changes; no new subcommand, so `automate-helpers.sh` dispatch is untouched) | — | HIGH |
| tests | `loomwright/scripts/test-automate-next-step.sh` (2684 — only the `TNS_PARTS` / `TNS_GROUPS` registration lines) | `loomwright/scripts/test-automate-next-step.d/13-merge-parked.sh` (the one home for every new leg; parts are ≤ 370 lines today) | HIGH |
| golden fixtures (copies of `## Current`) | `loomwright/scripts/fixtures/automate-golden/dismissed-fix-now-re-drain/expected.md` (fixture: its `## Current` block gains the `- ready_sha:` line), `loomwright/scripts/fixtures/automate-golden/learning-emit-end-of-drain/expected.md` (fixture, same single line; see `## Scope widening`). These are the only two cases whose `next-step.results` holds a drain report with both `review_heal_result` and `ready_sha`. Confirm by running `test-automate-golden.sh` + `test-automate-next-step.sh` after the writer lands. Any other case that changes is a behaviour change to investigate, not to re-bless | — | HIGH |
| schema/inventory docs (test-pinned closed lists) | `loomwright/docs/result-schemas/automate-run.md` (159), `loomwright/docs/loop-inventory/automate-loop.md` (791 — row-per-claim table, the single inventory authority; new rows appended in its existing `## Inventory` table. Shared by both subtasks, sequentially: Subtask 1 adds the rows anchored in its own files, Subtask 2 the rows anchored in its prose docs) | — | HIGH |
| prose docs + budgets | `loomwright/commands/automate.md` (123), `loomwright/skills/automate-loop/resume.md` (46), `loomwright/skills/automate-loop/run-file.md` (81), `loomwright/skills/automate-loop/helpers.md` (62), `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1063 — only the mirror rows of the two budgets that move) | `changelog.d/merge-one-parked-item.md` | HIGH |
| evidence | — | `docs/evidence/merge-one-parked-item.md` | MEDIUM (needs the live sandbox run) |

> **Validator-owned surfaces:** `scripts/test-automate-next-step.d/07-doc-mirror.sh` (doc step list = driver `case` arms), `scripts/test-loop-inventory.sh` (inventory rows vs their homes), `check-token-budget.sh` (`.commands.automate`, `.skills["automate-loop"]` in `prompt-token-budgets.json` + `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror), `check-doc-currency.sh`, `test-citation-drift.sh` (no new bare `file:N` citation) — all folded into the map above.

**Not touched (companion item `2026-11-05-192935-trust-unprotected-private-free-and-empty-checks.md` owns them):** `loomwright/scripts/automate-helpers.sh`, `loomwright/skills/automate-loop/modes-and-merge-gate.md`. Also untouched: rows AL-420 and AL-421 of `loomwright/docs/loop-inventory/automate-loop.md`, whose rule cells the companion item edits (this item only adds rows), and `automate-merge-watch.sh` (its `closeout: skipped — run lock held` transient retry is already the needed behaviour).

## Touched-file invariants

> Grounded at base `d42212f2beb5880501c6e656156ca7014696d6c5`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-next-step.sh`** — keep: the writer rule `# WRITERS. The run file is written ONLY through automate-helpers.sh` (the new `- ready_sha:` line goes through `ns_current_line` → `runfile-write`, never a direct edit); the gate call `gl="$(bash "$H" gate-eval "$PR" "$CTXF" --root "$ROOT" 2>"$errf")"` and its ctx of `exactly the six loop-owned keys` (the entry supplies `drain_result` (from `owned_drain_result`), `termination_reason` and `ready_sha` (from the `- ready_sha:` line) from `## Current` into the existing ctx — no new ctx key, no `gh pr merge` anywhere in this script); the resume wipe `NS_STATE='{}'` stays (the fix is that the gate input no longer lives only there); the lock idiom `ns_lock() { # acquire|release` (acquire before `gate-eval`, hold through closeout, release on every exit — park, refuse-after-acquire, done); the watcher liveness test `ns_watch_live() {` (pid + `ps -ww`, `never \`pgrep -f\``), so a park leaves exactly one watcher; the existing merged-PR closeout in `ns_reconcile_merged` (closeout WITH trail — never `ns_sync`'s `out="$(bash "$H" closeout "$RF" "$ITEM" "$PR" --no-trail`) and the stop `ns_awaiting_go() {`; the flag persistence line `if [ -n "$MODE" ]; then st_set flag_mode "$MODE"` stays unchanged (it runs before dispatch). The AC14 "not recorded" behaviour is undone inside `ns_open_pr_park` instead (`st_del flag_mode` when this call's `MODE` is `auto-merge`), so only the parked-open-PR `--resume --auto-merge` path changes; `ns_open_pr_park() {` keeps its message for every other case; the lane test `ns_lane() { [ -e "$ROOT/.supervisor/lane.json" ]; }` and `ns_parallel()` decide the AC17 refusals; portability `bash 3.2 + BSD userland + jq.` (no `timeout`, no GNU `date -d`; `gh` only through `ns_gh` so `LOOMWRIGHT_GH_BIN` stubs it); every new step is a `case` arm of `ns_dispatch` and is listed in the header's `# STEPS` block. pinned by: `test-automate-next-step.d/07-doc-mirror.sh` (`docarms="$(grep -F`, the doc's step list must equal the driver's `case` arms; the closed `do` enum `ask done park spawn ` — this entry adds no new `do` value and no new spawn `what`).
- **`loomwright/scripts/automate-helpers.d/runfile.sh`** — keep: `current_set` is the only writer of the item/pause_reason lines and the status enum `CURRENT_STATUS_ENUM=" running awaiting_merge` is unchanged (no new status or pause value: a guard park stays `awaiting_merge` with its `PARK: <reason>` only in `## Progress`); reuse the existing per-item drop (`the \`- escalation_cause:\` line is per-item park state`, `CS_DROP_ESC`) for the `- ready_sha:` line on an item change; refusals stay exit 1 with the file byte-unchanged; the `#:` usage lines feed `fixtures/automate-helpers-help/runfile.golden` — do not edit a `#:` line (no new subcommand is needed). pinned by: `test-automate-helpers.d/02-runfile.sh` (`owned_drain_started`).
- **`loomwright/scripts/test-automate-next-step.sh`** — keep: the part registry `TNS_PARTS="01-golden-idem-gates` and `TNS_GROUPS="1=` (the new part `13-merge-parked` is added to both, in one pool group — `pg_select` checks the map); legs stub `gh` on PATH / via `LOOMWRIGHT_GH_BIN` and never touch the network; every mutant is gated on non-empty + differs + `bash -n` (project lesson fa32a308).
- **`loomwright/docs/result-schemas/automate-run.md`** — keep: the Common-fields step list (`one of the driver's \`case\` arms:`) equals `ns_dispatch`'s arms exactly — every new arm added there in the same subtask; the `do` table rows (`spawn`/`ask`/`park`/`done`) unchanged; the `## Current` layout block (beside `- pending_decisions: <n> | fix_now_reentered: <true|false>`) gains the `- ready_sha:` line. pinned by: `test-automate-next-step.d/07-doc-mirror.sh` (`docarms="$(grep -F`).
- **`loomwright/docs/loop-inventory/automate-loop.md`** — keep: the section shape (`## Sources`, `## Inventory`, `## Gap list (ordered by risk)`, `## Counts`, nothing else); the row format `| id | file | anchor | condition | action | kind | home | implemented by | test |` with unique `AL-<n>` ids (continue after the last id; never edit rows AL-420 / AL-421, which the companion item owns); every `###`/`####` heading of a listed Source (`skills/automate-loop/resume.md` among them — so `### Merging one parked item` needs an `h:` row) is some row's `h:` anchor (HEADING COVERAGE); a `prose`/`global` row's `h:`/`q:` anchor must exist in its file (LIVE ANCHORS) — so a row is added only by the subtask that writes its anchor; a `script:automate-next-step.sh <step>` home must name a real `case` arm; the six `## Counts` lines are recomputed after each subtask's rows. pinned by: `loomwright/scripts/test-loop-inventory.sh` (`HEADING COVERAGE (AC2)`, `LIVE ANCHORS (AC4)`).
- **`loomwright/commands/automate.md`** — keep (when rewriting rows for budget headroom, never drop these pinned needles): the parameter rows naming `needs_owner`, `no_source_non_interactive` and `resume_requires_flag_non_interactive` (pinned by `test-non-interactive-gates-seam.sh` (f)/(g)/(h)); Step 0's ordered list of every skill split file (pinned by `test-automate-loop-split.sh` F); `(each fix-now option shows its derived wall-clock cost)` (pinned by `test-automate-dismissed.sh` C8); no positive `gh pr merge --squash` mention (invariants.md grep).
- **`loomwright/skills/automate-loop/resume.md`** — keep: `` `Continue` · `Start new` · `Archive` `` (pinned by `test-lane-policy.sh` G3); its `## §4` / `## §5` headings; the new `### Merging one parked item` heading is exact (requirement) and gets its inventory `h:` row in the same subtask.
- **`loomwright/scripts/fixtures/automate-golden/<case>/expected.md`** — regenerated only for the `- ready_sha:` line the new writer adds; every other byte unchanged (a diff touching more than that line is a behaviour change to investigate, not to re-bless). pinned by: `test-automate-golden.sh`, `test-automate-next-step.sh`.
- **`loomwright/docs/prompt-token-budgets.json`** — read by `check-token-budget.sh` (fails CLOSED); a budget moves only with its `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row in the same change; `commands/automate.md` has ~500 tokens of headroom (measured 4968 / budget 5465) — rewrite rows rather than extend them.

## Closed enumerations touched

> Sibling grep at base `d42212f`: `grep -rnF 'awaiting-go' --exclude=CHANGELOG.md loomwright/` → 9 hits in 3 files; `grep -rnF 'rules_gate_head_mismatch' --exclude=CHANGELOG.md loomwright/ docs/` → 20+ hits (gate-owned; this story adds no gate park reason).

- **new driver step arm(s)** (e.g. `merge-parked`, `merge-guard`; sibling: `awaiting-go`) — must be named in:
  - `loomwright/scripts/automate-next-step.sh` — `ns_dispatch`'s `case` and the header `# STEPS` block — extend.
  - `loomwright/docs/result-schemas/automate-run.md` — the `one of the driver's \`case\` arms:` list in **Common fields** — extend (pinned by 07-doc-mirror D).
  - `loomwright/docs/loop-inventory/automate-loop.md` — the AL rows citing `script:automate-next-step.sh <step>` — extend with rows for the new steps.
- **new pre-gate park reasons** (e.g. `ready_sha_missing`, `ready_stale_feedback`, `base_moved_since_ready`, `checkout_not_on_pr_head`; sibling: the gate's `head_sha_moved` — which the entry reuses verbatim for AC7) — must be named in:
  - `loomwright/docs/loop-inventory/automate-loop.md` — park-reason rows — extend.
  - `loomwright/skills/automate-loop/resume.md` §"Merging one parked item" — the reason list — extend.
  - `loomwright/scripts/automate-helpers.d/runfile.sh` `CURRENT_PAUSE_ENUM` — no change: these are `## Progress` `PARK: <reason>` text; `pause_reason` stays `awaiting_merge`.
  - `loomwright/scripts/automate-helpers.sh` gate PARK reasons — no change: not gate reasons (companion item owns the file).
- **new `## Current` line `- ready_sha: … | ready_at: …`** (sibling: `- pending_decisions:`) — must be named in:
  - `loomwright/docs/result-schemas/automate-run.md` §"Run-file layout"/§"`## Current` fields" — extend.
  - `loomwright/skills/automate-loop/run-file.md` (restates the layout — updated in the same change, house rule) — extend.
  - `loomwright/scripts/fixtures/automate-golden/dismissed-fix-now-re-drain/expected.md` (and any other golden case whose replay records a READY drain carrying `ready_sha`) — the expected run-file copy — extend.
  - `loomwright/scripts/fixtures/automate-golden/drain-owned-drain-started/expected.md` — no change: its READY report carries no `ready_sha`, so no line is written.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-automate-next-step.d/13-merge-parked.sh` — AC5 resume-then-merge-parked hands the recorded `ready_sha` to gate-eval | in `automate-next-step.sh`, make the entry read `ready_sha` from the sidecar (`st ready_sha`) instead of `## Current` ⇒ the leg must go red |
| `13-merge-parked.sh` — AC5 ctx carries the recorded `termination_reason` after `--resume` | make the entry read `termination_reason` from the sidecar (`st termination_reason`) |
| `13-merge-parked.sh` — AC20 READY drain writes the `- ready_sha:` line | delete the `ns_current_line "- ready_sha:"` call in `ns_drain_result` |
| `13-merge-parked.sh` — AC6 fix-now re-drain overwrites the line (its `ready_sha`) | skip that call when `kind = fixnow` |
| `13-merge-parked.sh` — AC6 the re-drain's `termination_reason` is recorded | write the first drain's `termination_reason` (`st termination_reason`) instead of the re-drain block's `tr` in the ready line |
| `13-merge-parked.sh` — AC24 a READY report with no `ready_sha` writes no line | drop the `[ -n "$rs" ]` guard so the line is written with an empty `ready_sha` |
| `13-merge-parked.sh` — AC8 late comment parks, gate-eval not called | delete the comment/review-newer-than-`ready_at` check line |
| `13-merge-parked.sh` — AC9 `behind_by > 0` parks | flip `-gt 0` → `-gt 999` in the `behind_by` test |
| `13-merge-parked.sh` — AC10 checkout not on head parks, HEAD unchanged | delete the HEAD-vs-live-head check line |
| `13-merge-parked.sh` — AC15 no recorded `ready_sha` parks (never the live head) | replace the empty-`ready_sha` park with a fallback to `ns_pr_head` |
| `13-merge-parked.sh` — AC2 items remain ⇒ `awaiting_go`, no pick | route the MERGE tail to `ns_terminate` (which returns `running`) |
| `13-merge-parked.sh` — AC12 park releases the run lock | delete the `ns_release` call on the guard-park path |
| `13-merge-parked.sh` — AC14 `--resume --auto-merge` on parked open PR records no `flag_mode` | delete the `st_del flag_mode` line in `ns_open_pr_park` (the parked-open-PR `--resume --auto-merge` path) ⇒ the sidecar carries `flag_mode: auto-merge` and the leg goes red |
| `13-merge-parked.sh` — AC17 lane refuses, writes nothing | delete the `ns_lane` refusal line in the entry |
| `13-merge-parked.sh` — AC20/AC24 item change drops the `- ready_sha:` line | in `runfile.sh` `current_set`, delete the `- ready_sha:` drop line |
| `13-merge-parked.sh` — AC1 MERGE ⇒ closeout with trail + one check-off | replace the entry's closeout call with `ns_sync`'s `--no-trail` closeout |
| `13-merge-parked.sh` — AC3 no items remain ⇒ done termination with trail | route the zero-remaining branch to `ns_awaiting_go` instead of the done termination |
| `13-merge-parked.sh` — AC4 no `spawn` instruction is ever printed | route the entry's head-moved branch to `NEXT=drain` |
| `13-merge-parked.sh` — AC7 `PARK: head_sha_moved` + "a person must decide" | delete the live-head-vs-`ready_sha` comparison line (the gate's own cond 2 then decides) |
| `13-merge-parked.sh` — AC11 single closeout while the watcher polls (`closeout: skipped — run lock held`) | delete the entry's run-lock acquire before `gate-eval` |
| `13-merge-parked.sh` — AC13 dismissed drafts stay pending after MERGE | follow up undecided drafts `--auto` on the entry's MERGE path |
| `13-merge-parked.sh` — AC16 non-`awaiting_merge` status refuses, run file byte-unchanged | delete the entry's status refusal line |
| `13-merge-parked.sh` — AC18 CLOSED PR is never checked off | send the entry's `gone`/closed branch to the check-off step |
| `13-merge-parked.sh` — AC18/AC2 MERGED-at-entry ends at the entry tail (awaiting_go, no pick) | route the MERGED branch's tail to `ns_after_reconcile` (`NEXT=trail-gate`) |
| `13-merge-parked.sh` — AC2 a closeout leftover resolves to the entry tail | leave `after_leftover` unset on the entry's closeout (falls to checkoff → terminate → `running`) |
| `13-merge-parked.sh` — AC12 a gate PARK reruns no decision step | keep `ns_gate_eval`'s `NEXT=dismissed` on the entry's PARK path |
| `13-merge-parked.sh` — AC18 MERGED PR closes out with no `gate-eval` call | send the entry's merged branch to `gate-eval` first |
| `13-merge-parked.sh` — the entry's own awaiting_go message (not the superseded-drain text) | make the entry call `ns_awaiting_go` with its default (superseded-drain) message |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `--merge-parked` entry, durable READY record, pre-gate guard, `--resume --auto-merge` message, tests, test-pinned schema/inventory docs | AC1–AC20, AC24, AC22 (its part) | 7 modify, 1 create | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Prose docs, their inventory rows, budgets, changelog fragment, Validation 2 evidence on studio-sandbox | AC21, AC22, AC23 | 7 modify (incl. the shared inventory doc), 2 create | `skills/automate-loop/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "--merge-parked"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "- ready_sha:"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/runfile.sh", name: "- ready_sha:"}
  - {kind: "file", path: "loomwright/scripts/test-automate-next-step.d/13-merge-parked.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-next-step.sh", name: "13-merge-parked"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "--merge-parked"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/automate-loop.md", name: "--merge-parked"}
requires: []
lanes:
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/automate-helpers.d/runfile.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.d/13-merge-parked.sh"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/scripts/fixtures/automate-golden/dismissed-fix-now-re-drain/expected.md"
  - "loomwright/scripts/fixtures/automate-golden/learning-emit-end-of-drain/expected.md"
external_requires:
  - "gh CLI (pr view, api compare/{base}...{sha} behind_by, issue comments, reviews, review comments) — stubbed in tests"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/skills/automate-loop/resume.md", name: "### Merging one parked item"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "--merge-parked"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/run-file.md", name: "ready_sha"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/helpers.md", name: "--merge-parked"}
  - {kind: "file", path: "changelog.d/merge-one-parked-item.md"}
  - {kind: "file", path: "docs/evidence/merge-one-parked-item.md"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/automate-loop.md", name: "### Merging one parked item"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "--merge-parked"}
  - {from: "1", kind: "symbol", path: "loomwright/docs/loop-inventory/automate-loop.md", name: "--merge-parked"}
lanes:
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/commands/automate.md"
  - "loomwright/skills/automate-loop/resume.md"
  - "loomwright/skills/automate-loop/run-file.md"
  - "loomwright/skills/automate-loop/helpers.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/merge-one-parked-item.md"
  - "docs/evidence/merge-one-parked-item.md"
external_requires:
  - "vikashruhilgit/studio-sandbox (public) — a NEW item parked awaiting_merge with this branch's plugin copy"
  - "vikashruhilgit/loomwright-studio probes/p14-loomwright-merge-one-parked-item.md"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 2 ──→ Subtask 1   (docs describe and the evidence run exercises the entry Subtask 1 builds)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/docs/loop-inventory/automate-loop.md` (legal: Subtask 2 requires Subtask 1, so the shared lane is ordered; Subtask 2 re-verifies Subtask 1's `--merge-parked` rows still resolve after its own edit) | YES |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/automate-loop/SKILL.md` (§6, §8, §10; `per-item-loop.md`, `invariants.md`), `skills/unit-testing/SKILL.md` |
| 2 | `skills/automate-loop/SKILL.md` (`resume.md`, `run-file.md`, `helpers.md`) |

### Design notes for the worker (decided here; owner decisions in the requirement)
- Entry shape: `automate-next-step.sh --merge-parked <automate_dir> --run <run_id> --session-id <sid> [--root …]` (exclusive with `--resume` / `--start` / `--result`; NOT a `--resume` form). Order: refuse (lane / parallel parent / status ≠ `awaiting_merge` or `owned_drain_result` ≠ READY — name the status, write nothing) → run-lock acquire → `reconcile-item`: MERGED ⇒ the `ns_reconcile_merged` closeout + CHECK OFF, no gate; CLOSED/gone ⇒ the RECONCILE report, never checked off → guard: no `- ready_sha:` ⇒ park; live head ≠ `ready_sha` ⇒ `PARK: head_sha_moved` + "a person must decide"; checkout HEAD ≠ live head ⇒ park naming `headRefName` (touch nothing); any issue comment / review / review comment with `created_at`/`submitted_at` > `ready_at` ⇒ park; compare `behind_by` > 0 ⇒ park → `ns_gate_eval` with `ready_sha` from `## Current` → `MERGE` ⇒ closeout with trail → CHECK OFF → remaining > 0 ⇒ `ns_awaiting_go`, else `ns_terminate`'s done branch; `PARK:` ⇒ status stays `awaiting_merge`, one progress line, lock released, existing watcher left alone (arm one only if `ns_watch_live` finds none). It works under `--inline-phases` / host mode because it spawns nothing.
- **One entry-owned tail (do not reuse the loop's tails).** Three existing helpers would continue the loop:
  - `ns_reconcile_merged` ends in `ns_after_reconcile`, which sets `NEXT=trail-gate`.
  - `ns_checkoff` hard-codes `NEXT=terminate`, and `ns_terminate`'s remaining>0 branch emits `running`.
  - `ns_leftover` with no `after_leftover` set falls through to checkoff, then terminate.

  So the entry calls only the closeout + `closeout-classify` pair that `ns_reconcile_merged` uses (with trail and `--session-id`), never `ns_after_reconcile`. All three success paths converge on ONE entry-owned tail (e.g. a `merge-parked-finish` step arm): CHECK OFF, then remaining > 0 ⇒ `ns_awaiting_go` with the entry's own message, else `ns_terminate`'s done branch (trail included). The three paths are: MERGED-at-entry (AC18), gate `MERGE` (AC1), and a closeout leftover the owner resolved. The entry sets `after_leftover` to that tail. The check-off step it uses must not fall through to `ns_terminate`'s `running` branch: either add a mode to `ns_checkoff` that sets `NEXT` to the entry tail, or have the entry tail call the check-off writer itself.
- **Gate PARK path.** On a gate `PARK: <reason>` the entry REPLACES `ns_gate_eval`'s `NEXT=dismissed` (and its `park_kind`/`order` routing) with its own park step: it writes one `## Progress` `PARK: <reason>` line, leaves status `awaiting_merge`, releases the lock, and arms a watcher only if `ns_watch_live` finds none. It never reruns the dismissed-drafts / decision step / `ns_park`. The entry's own guard parks (AC7–AC10, AC15) use that same park step.
- **`flag_mode` on `--resume --auto-merge` (AC14).** The `st_set flag_mode` line runs in the top-level preamble, before the driver knows the run will reach `ns_open_pr_park`, so the skip cannot live on that line. Mechanism: capture, before the preamble refills `MODE` from the sidecar, whether THIS command line carried an explicit `--mode auto-merge` (e.g. `NS_MODE_ARG`). Inside `ns_open_pr_park`, only when that explicit flag was given, run a plain `st_del flag_mode` (no "restore": `--resume` has already wiped the sidecar) and append "`--auto-merge` was not applied — use `/automate --merge-parked <run_id>`" to the park message. Every other caller keeps its message unchanged.
- **Gate-checked provides names.** `outputs_verified` greps each `provides` name literally. Subtask 1's text in `docs/result-schemas/automate-run.md` and its rows in `docs/loop-inventory/automate-loop.md` therefore spell the literal flag `--merge-parked` at least once, beside the bare step-arm names.
- **Companion rows.** Rows AL-420 and AL-421 in `docs/loop-inventory/automate-loop.md` belong to the companion item. Never edit them; new rows continue after the highest existing id.
- Feeding the gate: `ns_gate_eval` builds its ctx from the sidecar (`dr="$(st drain_result)"; tr="$(st termination_reason)"; rs="$(st ready_sha)"`). Leave `ns_gate_eval` and its ctx keys alone. Before calling it, the entry sets those three sidecar keys from `## Current`: `drain_result` from `owned_drain_result`, and `termination_reason` and `ready_sha` from the `- ready_sha:` line. It never reads the values the sidecar held before the entry ran (AC5's pins).
- Writing the ready line: `ns_drain_result` already holds `dec`, `tr` (from the REVIEW_HEAL_RESULT block) and the report `r`. When `dec = READY` and `rj "$r" ready_sha` is non-empty, write `- ready_sha: <sha> | ready_at: $(ns_ts) | termination_reason: <tr>` with one `ns_once once_dr_ready`-guarded `ns_current_line` call. The key carries the `once_dr_` prefix so that `ns_clear_once once_dr_` clears it before a fix-now re-drain. The call runs for both `kind = first` and `kind = fixnow`. `ns_current_line` replaces the line in place, so a re-drain overwrites it.
- Host mode (requirement Assumption 3, "test it"): at base, `automate-next-step.sh` never reads `LOOMWRIGHT_HOST_STATE_DIR` (it is read only by `host-mode.sh`, `build-capabilities.sh` and `guard-test-integrity.sh`). One `13-merge-parked.sh` leg sets it to a scratch dir and asserts that the entry still reads and writes the run file and the `<run_id>.next-step.json` sidecar under the given automate dir, and writes nothing under the scratch dir. The evidence file records the host-mode finding.
- `ready_at` is the time the READY drain report is recorded (`ns_ts`), so the drain's own comments precede it; verify against a real drain's comment timestamps (requirement Assumption 2) and record the finding in the evidence file.
- Dismissed drafts after `MERGE`: reuse `ns_dismissed`'s pending-write for `order: merge`, but the entry then sets NEXT to its OWN closeout-with-trail → check-off → awaiting_go/done step — never `sync` (whose `--no-trail` closeout and `ns_terminate` `running` tail the brief forbids).
- New docs must not add a positive `gh pr merge --squash` mention (AC19); refer to "`gate-eval`, the one merge executor".
- `ns_awaiting_go`'s park message is hardcoded for the superseded-drain case ("PR merged before the drain's terminal REVIEW_HEAL_RESULT …"); the entry must pass or select its own message (e.g. "merged through gate-eval by --merge-parked — the item is closed out; the next item waits for /automate --resume") and the test leg pins it.
- Inventory rows split by anchor: Subtask 1 adds the rows anchored in its scripts / `automate-run.md` or homed `script:automate-next-step.sh <step>` (and recomputes `## Counts`); Subtask 2 adds the rows anchored in the prose it writes — the `### Merging one parked item` heading's `h:` row and its park-reason list among them — and recomputes `## Counts` / the gap list again. Run `bash loomwright/scripts/test-loop-inventory.sh` at the end of each subtask.
- If the Validation 2 sandbox run cannot be completed, `docs/evidence/merge-one-parked-item.md` still exists and records exactly what ran, with NO `Verdict: PASS` line (the validation gate then parks for the owner); never write the line without the observed output.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 16 files > 12 — context-bound | MEDIUM | split into 2 dependency-ordered subtasks; each subtask owns the inventory rows anchored in its own files (Subtask 1: rows homed `script:automate-next-step.sh <step>` / anchored in its scripts and `automate-run.md`; Subtask 2: rows anchored in the prose docs it writes, plus their `## Counts` / gap-list updates), so `test-loop-inventory.sh` and `07-doc-mirror.sh` are green after each subtask |
| Feasibility (Phase 2.5): Validation 2 needs a live sandbox park + p14 re-entry; a Supervisor worker may lack the time or session shape to run `/automate` on another repo | HIGH | the worker runs it with this branch's plugin copy (`--plugin-dir`); if it cannot, the evidence file records exactly what ran and NO `Verdict: PASS` line, so the `/automate` validation gate parks `validation_unrun` for the owner — never a fabricated PASS |
| `automate-next-step.sh` is the plugin's hotspot (3518 lines); a new entry can disturb resume / PICK binding (`ns_bound`) | HIGH | the entry runs before `ns_bound`'s discard logic with its own sidecar scope; full `test-automate-next-step.sh` (all 3 groups) + `test-automate-golden.sh` must stay green |
| The pre-gate comment guard parks every re-entry if a drain posts a comment at/after READY (requirement Assumption 2) | MEDIUM | `ready_at` = report-recorded time; a test leg with a drain comment 1s before `ready_at` must not park; checked on the live sandbox run |
| Merge watcher double closeout | MEDIUM | hold the run lock from before `gate-eval` through closeout; the watcher's `closeout: skipped — run lock held` is transient and it retries, then finds the item done; AC11 test leg |
| `commands/automate.md` near its token budget | LOW | rewrite rows instead of extending; raise budget only with its `ARCHITECTURE_CONTRACTS.md` mirror row |
| Companion item in the same wave owns `automate-helpers.sh` / `modes-and-merge-gate.md` | MEDIUM | no edit to either; no new helper subcommand (the ready line is written through `ns_current_line` → `runfile-write`) |
| A busy `main` sends most re-entries back to the owner (`behind_by` > 0) | LOW | accepted owner decision; fails toward a person |

## Plan Review
- **Decision:** PASS on attempt 3/3 (requirement_fit: fulfils). The MEDIUM issues from attempts 1 and 2 were fixed and re-reviewed.
- **Deferred (LOW):** `ns_open_pr_park` has a single caller, the reconcile step's open-PR branch, which runs on `--start` too. So the explicit `--mode auto-merge` check also adds the "not applied" text and the `flag_mode` delete when a `--start --mode auto-merge` reaches an open PR. This is harmless, since the flag is not applied there either. AC14's test leg uses `--resume`.

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-06-merge-one-parked-item-through-the-gate.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-06T19:26:43Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/842
- **Branch:** feature/merge-one-parked-item-through-the-gate
- **Files changed:** 14
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 0
- **Heal reason:** needs_human
- **Heal remaining issues:** 7
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** --merge-parked entry, durable ready_sha record, pre-gate guards, docs, inventory and changelog fragment shipped in PR #842. Escalated because AC23 (Validation 2 / p14 on studio-sandbox) needs the owner; also open: HIGH test group 3 exceeds 900 s (split 13-merge-parked into group 4), MEDIUM no ## Current re-read after the run-lock acquire, and three doc-list drifts (resume.md/AL-615 merged path, automate-run.md refusal list, agent-help.md/README.md).

## Not verified
- **Validation 2 / p14 on vikashruhilgit/studio-sandbox** — owner-run probe with interactive Run 1; evidence file carries no PASS verdict (subtask 2)
- **real gate-eval and real closeout reached through --merge-parked** — the suite stubs both (subtask 1)
- **a running automate-merge-watch.sh during the merge** — modelled by a session-less run-lock acquire (subtask 1)
- **test-automate-next-step.sh groups 2 and 3 to completion under ci-local** — killed by the 900 s watchdog under load; a direct re-run passed 82/0 and 103/0 (subtask 2)
- **a real host session running /automate --merge-parked** — only the HOST test leg ran (subtask 2)
- **full bash scripts/ci-local.sh pre-push run** — not run as one pooled run (subtask 2)
