# Supervisor Job: `/automate --parallel 1` runs each Queue item in one fresh lane that parks like a sequential item

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (orphaned worktrees of merged PRs — advisory, unrelated)
- **Source requirement:** .supervisor/requirements/twin-remediation/08b-single-lane-sequential.md
- **Base commit:** ef3d47b0fba851d16d3de0d98ecf3abc40e019b3

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq, the same as `automate-lanes.sh` today; no new tool |
| 2 | Dependency Availability | GO | Reuses `read-token-ledger.sh`, `setup-memory.sh mode`, `automate-merge-watch.sh`, `lane-convert-ready`, `fleet-closeout` — all present at base |
| 3 | Architecture Fit | GO | Lanes already run one item per clone with relay, launch authority and resume; single-lane mode is a wave of one that parks `awaiting_merge` and is closed out by the existing `lane-convert-ready` re-run path (`awaiting_merge/awaiting_merge) phase=closeout`) and `fleet-closeout` |
| 4 | Scope vs Supervisor Capability | CAUTION | ~20 files; surfaces outside the requirement's `## Touches`: `automate-helpers.d/runfile.sh`, `automate-wave.sh`, `test-wave-build.sh`, `docs/ARCHITECTURE_CONTRACTS.md`, `docs/TELEMETRY.md`, `docs/result-schemas/automate-run/*.md`, `docs/result-schemas/schema-versioning.md`, `commands/agent-help.md` — needed so no doc claims "a READY lane parks `ready_for_release`" for a single lane and so the park is enforced by a script, not prose |
| 5 | Hard Blockers | CAUTION | (a) Requirement AC "existing tests pass unedited" vs Scope 1 "`--auto-merge` stays refused with lanes": test E3 (`check "E3 --parallel 1 --auto-merge ok"`) pins the opposite and MUST flip — it is a `--parallel` path, so the "no `--parallel` ⇒ byte-unchanged" AC still holds; (b) no past lane ever armed a merge watcher, and its survival past the headless `claude -p` lane exit is unverified (owner decision 2 below); (c) the requirement's Validation 2 (a real `--parallel 1` run) spawns a detached Opus lane, opens a real PR and needs the owner's typed command — not runnable inside this item's own run |

**Overall Verdict:** CAUTION

**Owner decisions (2026-10-14, Launch Pad Phase 2, AskUserQuestion):**
1. **Branch mode OFF ⇒ refuse at start.** With branch mode off a single lane's close-out would open its own `chore/<parent>-L<n>-trail-<k>` PR the parent's `trail-gate` never sees, and `fleet-closeout` never finalizes the lane (`human — $lane not finalized`), so the parent Queue is never checked off. `--parallel 1` is refused unless `setup-memory.sh mode` reads `on <branch>`.
2. **Arm the watcher, prove survival.** The single lane arms the ordinary merge watcher at its `awaiting_merge` park; a committed test proves a watcher launched with the documented line outlives the process that launched it; the real-lane proof is the operator's running-system validation (listed under Not verified if not run). The `--resume` → `fleet-closeout` backstop stays the stated fallback.
3. **Whole-run token ceiling.** `--max-tokens T` on `--parallel 1` bounds the WHOLE run (sequential semantics), not T per lane.

## Task
**Goal:** Make `/automate --parallel 1` a "single-lane mode": each Queue item, in Queue order, runs in ONE fresh lane (new clone, new session) that, on a READY drain, parks `awaiting_merge` with a merge watcher exactly like a sequential item — no `ready_for_release`, no wave PR, no `wave-build` — and is closed out on the owner's `--resume` by the existing `lane-convert-ready` + `fleet-closeout` path, after which the next item gets a new lane.

**Problem Statement:**
The owner needs long sequential `/automate` runs to stop accumulating every item in one growing session (2026-10-13: ~200 MB of transcript in sessions that touched 2+ items).
Currently `--parallel 1` deliberately enters no lane code path, and a lane can only park `ready_for_release` and wait for a wave PR — so there is no way to get a fresh session per item with sequential merge semantics.
Success looks like: `--parallel 1` on a 2-item Queue runs item 1 in L1, parks `awaiting_merge` with a live watcher and no wave PR; after the merge and `--resume`, item 2 runs in L2 with a fresh session id; a run without `--parallel` is byte-unchanged.

## Acceptance Criteria
- [ ] 1. **init-check.** Given `init-check --parallel 1 --auto-merge`, then it prints `refuse: auto_merge_with_parallel` (exit 1) — test E3 is FLIPPED to this (flipped, not deleted). Given `init-check --parallel 1` and `setup-memory.sh mode` (read through the existing `SETUP_MEMORY` seam, `LOOMWRIGHT_LANES_SETUP_MEMORY`, `--root` = the current checkout's git top level) printing anything other than a line starting `on ` (`off`, `unknown …`, empty, a failing reader), then it prints `refuse: single_lane_requires_branch_mode` (exit 1); with `on <branch>` it prints `ok`. Check order: the existing range check, then the `--auto-merge` refusal (so `--parallel 1 --auto-merge` refuses `auto_merge_with_parallel` without reading the mode), then the N = 1 mode read. Given N in 2..10 (with or without `--auto-merge`), the output is byte-identical to base and NO mode read happens (E1–E6's N>1 legs unchanged).
- [ ] 2. **lane-create marker.** Given `lane-create <parent> <item> <n> --parallel 1`, then `lane.json` carries `"single_lane": true`; given `--parallel N` with N ≥ 2, or no `--parallel` at all (the `[ -n "$par" ] || par="$n"` default), then the key is ABSENT (every other key and its order byte-shaped as today). Only an explicit `--parallel 1` writes it.
- [ ] 3. **Fresh lane numbers.** Given `--parallel 1`, `lane-create` accepts lane numbers 1..99 and refuses (stderr `lane-create: refused — lane L<n> already used in this run (single-lane takes a fresh number)`, exit 1, nothing created) a number already present in the parent's `<run_id>.lanes` table; without `--parallel 1` the existing `case "$n" in [1-9]|10)` bound is unchanged. Every reader that matches lane names already accepts two digits (`L[0-9]|L[0-9][0-9]`) — the worker re-checks every lane-name reader under `loomwright/scripts/` (at least `automate-lanes.sh`, `automate-wave.sh`, `automate-helpers.sh`, `automate-helpers.d/resume.sh`, `automate-dismissed.sh`, `automate-trail.sh`, `notify-desktop.sh`, `guard-lane-wait-armed.sh` — all accept L10..L99 at base per Plan Review) and lists any it had to widen.
- [ ] 4. **Whole-run token ceiling (owner decision 3).** Given `lane-create … --parallel 1 --max-tokens T`, then before cloning it computes SPENT = the sum of (a) every lane in the parent's table whose directory exists, read with the same `read-token-ledger.sh` call `_lanes_tokens` uses, and (b) every table lane whose directory is gone, read from its parent `## Progress` line `fleet closeout: <lane> tokens TOTAL=<n>` (AC 9); a gone lane with no such line (AC 9 and the `lane-remove` rule below write it for every removal path), or a live lane whose reader answers `LEDGER_UNREADABLE=1`, makes SPENT unreadable. SPENT unreadable ⇒ refuse `lane-create: refused — token_ceiling ledger_unreadable`; SPENT ≥ T ⇒ refuse `lane-create: refused — token_ceiling total=<SPENT> max=<T>`; both exit 1, nothing created. Otherwise `lane.json` records `max_tokens = T − SPENT` (the lane's own ceiling-check then enforces the remaining budget). Without `--parallel 1` the `mt=$((10#$maxt / par))` split is unchanged.
- [ ] 5. **The park seam.** A new read-only subcommand `lane-park [--root <dir>]` (dispatch arm + `#:` help line in `automate-helpers.sh`) prints exactly one line and exits 0: `awaiting_merge` when `<root>/.supervisor/lane.json` is absent (not a lane) or carries `"single_lane": true`; `ready_for_release` when lane.json is present without it, or is unreadable / not a JSON object (fail toward the park that arms no watcher and waits for the coordinator).
- [ ] 6. **Enforced, not prose.** `current-set` (in `automate-helpers.d/runfile.sh`) refuses — exit 1, run file byte-unchanged, one stderr line naming `single_lane` — an item form with `--status ready_for_release` or a `--pause-reason ready_for_release` when the checkout holding the run file (the directory two levels above `.supervisor/automate/<run_id>.md`) has a `.supervisor/lane.json` with `"single_lane": true`. With no lane.json, or a lane.json without the key, `current-set` is byte-unchanged in output and effect.
- [ ] 7. **The single lane's READY park (prose, `skills/automate-loop/lanes.md` + `per-item-loop.md`).** Inside a lane the GATE writes the park `lane-park` prints. On `awaiting_merge` (a single lane): `validation-gate` first (unchanged); the dismissed-findings step in the decide-then-park order (lanes keep it — the park-first list stays for "a run that is neither a lane nor `--non-interactive-fallback`"); `current-set <rf> --item <path> --status awaiting_merge --pr <url> --branch <b> --pause-reason awaiting_merge`; arm the merge watcher with the SAME launch line §6 "Post-merge close-out" gives; the sequential park's ready-to-merge notify (NOT `lane-park-notify`, whose message is "do not merge yet — wave open"); then `run-lock.sh release`. **The RECONCILE re-check** (`per-item-loop.md` §6 step 4 "Re-check at RECONCILE (step 1)", which today writes `in a lane, \`--status ready_for_release --pause-reason ready_for_release\``) likewise writes the park `lane-park` prints: in a single lane `--status awaiting_merge --pause-reason awaiting_merge`, with no second watcher (the `escalated` park already armed one) and no `lane-park-notify` / `lane-readiness` call. `ready_for_release` (N>1) is byte-unchanged prose. `lane-park-notify` gains no behaviour change (it already skips a run file not at its park).
- [ ] 8. **Watcher survival (owner decision 2).** A committed test leg takes the launch line FROM ITS DOCUMENTED SOURCE — the `automate-merge-watch.sh` header's usage line (`#   env -u CLAUDE_PID -u CLAUDECODE nohup bash automate-merge-watch.sh \` and its continuation), read from the script file with the placeholders substituted, never a hand-typed copy — and runs it in `loomwright/scripts/test-automate-lanes.sh`, from a short-lived `bash -c` parent against a stub `gh` that reports `OPEN`, waits for the parent to exit, and asserts the `<run_id>.merge-watch` marker's pid is alive (`kill -0`) and `ps -ww -p <pid> -o command=` shows `automate-merge-watch.sh` with that `pr_url`; the leg then stops the watcher and `wait`s/cleans up so no child leaks into the piped suite.
- [ ] 9. **Coordinator flow (prose, new `lanes.md` subsection "Single-lane mode (`--parallel 1`)").** The parent `## Run Config` carries `- parallel: 1` (the coordinator-routing marker); no `plan-waves`, no intake lint, no wave-policy ask, no `current-wave` (`## Current` gets no `- wave:` line), no `wave-build`; per item: the first `- [ ]` Queue row (plain §6 order); `lane-status --leaks --snapshot`; `lane-create <parent> <item> <n> --parallel 1 [--max-tokens T]` with n = 1 + the highest lane number in the table (a `token_ceiling` refusal parks the parent `## Status: paused`, `current-set --pause-reason token_ceiling`, and releases the `automate-lanes:<run_id>` lock); `lane-launch`; sampler; `lane-wait` (it already treats `awaiting_merge`/`awaiting_go` as quiet and exits `idle`). At the lane's park the coordinator runs `lane-drain-check` (AC 10) and appends its line to the parent `## Progress`. On each `--resume`: `lane-status`; then `fleet-closeout <parent>` alone closes out a lane `lane-status` reads `merged`, `awaiting_go` (the lane's own watcher already ran `closeout`) or `done` — its per-lane backstop (`merged|awaiting_go|done)` → `lane-convert-ready`) runs the close-out; `fleet-closeout`, ONLY when the parent `## Run Config` reads `- parallel: 1`, appends `fleet closeout: <lane> tokens TOTAL=<n>` (the lane's `read-token-ledger.sh` TOTAL, `unknown` when unreadable) to the parent `## Progress` BEFORE that lane's `lane-remove`; once the lane is removed and its item checked off, the same `--resume` picks the next `- [ ]` item into a NEW lane (the `--resume` is the owner's go, exactly as a sequential `--resume` after a close-out picks the next item). `--limit N` counts processed items as in §2. The `fleet-closeout` parent finalize still ends the run when the Queue empties. `fleet-closeout` on an N>1 parent is byte-unchanged (no tokens line). **`lane-remove` (plain and `--abandon`) on a lane whose parent `## Run Config` reads `- parallel: 1`** appends the same `fleet closeout: <lane> tokens TOTAL=<n>` line to the parent `## Progress` before deleting the lane directory, unless that lane already has one (so an abandoned single lane never leaves the whole-run ceiling stuck at `ledger_unreadable`). **A single lane parked `escalated` (or any non-merged park):** `fleet-closeout` reports `waiting — L<n> <state>` as today and the next item does NOT start; the owner resolves the PR or abandons the lane (`lane-remove --abandon`, then `--resume`).
- [ ] 10. **Drain guard (Scope 3), read by markers.** A new read-only subcommand `lane-drain-check <lane_dir>` (dispatch arm + `#:` help line) prints one line and exits 0: `drain-guard: violation — <reason>` when (a) `<lane>/.supervisor/review-dispatch/` holds a marker named by the dispatcher's own hash of the lane `## Current` `pr:` URL (the `PR_HASH` computation in `dispatch-pr-review.sh` — reuse it, never re-derive a different hash), or (b) after the LAST `picked` line of the lane run file's `## Progress` there are 0 or ≥ 2 lines starting (after one timestamp token) `owned drain started — `, or ≥ 2 starting `owned drain started (fix-now re-drain) — `, or (c) `<lane>/.supervisor/automate/<run_id>.config-backup.json` exists; else `drain-guard: ok — <n> owned drain(s), no dispatch marker, no config backup`; an unreadable lane/run file ⇒ `drain-guard: unknown — <reason>` (observation fails SAFE).
- [ ] 11. **No wave PR for a single lane.** `wave-build` refuses a parent whose `## Run Config` carries `- parallel: 1`: `wave-build: refused — single-lane mode (no wave PR)`, exit 1, nothing created (pinned in `test-wave-build.sh`).
- [ ] 12. **Default unchanged.** Without `--parallel`: no new code path runs (init-check/lane-create/lane-park/lane-drain-check are never called; `current-set` and `fleet-closeout` outputs are byte-identical when no lane.json / no `- parallel: 1` exists). Existing suites pass with edits ONLY to: E3 (AC 1), the `lg_intro` pin in `test-automate-helpers.sh` (the quoted `**Without the flag, or with N = 1, no lane code path is entered**` sentence changes), `fixtures/automate-helpers-help/hdr-lanes.golden` (regenerated for the new `#:` lines), the dispatch-membership loop (`for ln_s in lane-create …`) gaining the two new subcommands, and any existing `init-check --parallel 1` leg that now needs the mode seam — the worker lists every edited pre-existing assertion in its hand-back.
- [ ] 13. **Docs.** `commands/automate.md` flag table + usage line (N = 1 = single-lane mode; refused with `--auto-merge` and with branch mode off); `skills/automate-loop/lanes.md` (the intro's "Without the flag, or with N = 1, no lane code path is entered" sentence rewritten to state single-lane mode exactly; INIT bullets; the new subsection; the "Terminal park" paragraph names the `lane-park` seam), `command-lanes.md`, `per-item-loop.md` (every "a lane's READY park is `ready_for_release`" clause qualified to N>1 lanes), `SKILL.md` §3 template comment (`parallel: <N|absent>` — present on any `--parallel` parent run, 1 included), §3's three unqualified `ready_for_release` claims (the Item lifecycle line "`ready_for_release` (a lane's READY park, §14)", the `paused` definition "a lane's terminal READY park, inside a lane only", and the `current-set` table row "Lane READY park (§14 — inside a lane only, replaces the `awaiting_merge` park)") qualified to N>1 lanes with the single lane's park stated (`lane-park` → `awaiting_merge`), §1.5 table rows for `lane-park` / `lane-drain-check`; `docs/result-schemas/automate-run.md` and `docs/result-schemas/automate-run/{sections-status-queue,item-lifecycle,parallel-lanes}.md` (the `parallel` row, the item lifecycle, the new `fleet closeout: <lane> tokens TOTAL=<n>` Progress line); `docs/ARCHITECTURE_CONTRACTS.md` Lanes table "Marker" row (lane.json fields gain `single_lane`) and "Merge" row; each `--parallel` mention in `commands/agent-help.md` (the flag line, the long description's "a READY lane parks `ready_for_release`", the later pointer); `docs/TELEMETRY.md`'s `automate_ready_for_release` row qualified to N>1 lanes (a single lane never calls `lane-park-notify`); `skills/automate-loop/resume.md` "Start order" paragraph (its init-check refusal list gains `single_lane_requires_branch_mode`; its "sequential or `--parallel N>1`" new-run guard sentence names single-lane mode); `docs/result-schemas/schema-versioning.md` gains ONE new additive entry (AUTOMATE_RUN: `- parallel: 1` = single-lane mode, the lane.json `single_lane` key, the `fleet closeout: <lane> tokens TOTAL=<n>` Progress line) — the existing 2026-10-08 entry is a historical record and is NOT edited. Each points to `lanes.md` rather than restating the flow.
- [ ] 14. **Changelog.** `changelog.d/tr08b-single-lane-sequential.md` fragment per `changelog.d/README.md`; no hand-edit of the version files.
- [ ] 15. **Running-system validation (requirement Validation 2) — evidence file.** Given the worker cannot spawn a real lane from inside this item's own run, when it hands back, then a committed `docs/evidence/tr08b-single-lane-sequential.md` (Markdown, never `*.log` — the root `.gitignore`'s bare `*.log` would make `git add` skip it) records Validation 2 as NOT verified: the trivial-item `--parallel 1` run, what it must show (the lane's `## Current` at the `awaiting_merge` park; the `<run_id>.merge-watch` marker pid alive after the lane's `claude -p` process exited; no wave PR; after merge + `--resume`, item 2 in a NEW lane with a fresh session id) and the exact operator commands to run it; it also records the fenced output of AC 8's watcher-survival leg and of one `lane-drain-check` run on a fixture lane. The worker reports Validation 2 in its `not_verified` hand-back, and the PR body links to the file.

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

## Touched-file invariants

> Grounded at base `ef3d47b0fba851d16d3de0d98ecf3abc40e019b3`. The worker re-checks every entry for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-lanes.sh`** — keep: `set -uo pipefail`, bash 3.2 (no `${arr[@]}` on a possibly-empty array under `set -u` — use a guard); `init-check` stdout exactly `ok` or `refuse: <reason>`, exit 1 on refusal (`lanes_init_check() {` … `if [ "$n" -gt 1 ] && [ "$am" = 1 ]; then echo "refuse: auto_merge_with_parallel"`), pinned by E1–E6; `lane-create`'s refusals on stderr with exit 1 and `_abort` cleanup, its last stdout line `lane-create: $lane $C run_id=…`, the "never reused" leftover-directory refusal (`never reused" >&2`), the lane.json writer (`parallel: $parallel, max_tokens: $mt, created: $created, policy: $policy}`) — a new key is appended, never reorders the others (A7's jq-array pin reads `.schema_version, .lane, … .max_tokens`); `lane-convert-ready`'s lines matched by `fleet-closeout` (`"lane-convert-ready: converted $lane to awaiting_merge"*`, `^lane-convert-ready: (finalize|refused|FAILED)`) and its `awaiting_merge/awaiting_merge) phase=closeout` branch; `fleet-closeout`'s `fleet closeout: $lane $item done (PR ${lpr:-none recorded})` line and `lock kept — $n Queue item(s) remain unchecked`; `lane-status` observation always exit 0 and its `--json` `.lanes[] | [.lane, .path, .item, .run_id, .state]` fields; `_LANES_WAIT_QUIET='["awaiting_merge","awaiting_go","done","removed","abandoned"]'` unchanged; the coordinator writes nothing into a launched lane beyond the header's three exceptions (the watcher is armed BY THE LANE, never by the coordinator); `_lanes_tokens` (`# TOTAL-CALL`) reused, not copied. reuse: the `SETUP_MEMORY="${LOOMWRIGHT_LANES_SETUP_MEMORY:-$HERE/setup-memory.sh}"` seam and `bash "$SETUP_MEMORY" --root "$1" mode` call shape; `LOOMWRIGHT_LANES_TOKEN_LEDGER` seam. pinned by: `loomwright/scripts/test-automate-lanes.sh` (E1–E6, A7, the convert-ready / fleet-closeout blocks).
- **`loomwright/scripts/automate-helpers.sh`** — keep: every lane subcommand has BOTH an `exec bash … automate-lanes.sh` dispatch arm and a `#:` help line (the dispatch-membership pin in `test-automate-helpers.sh`, `for ln_s in lane-create …`); the `#:` header is rendered into `fixtures/automate-helpers-help/hdr-lanes.golden` (regenerate, never hand-edit). The `#:  lane-create … # parallel-automate/05 (--parallel N>1 only)` line is updated to say `--parallel 1` = single-lane.
- **`loomwright/scripts/automate-helpers.d/runfile.sh`** — keep: `CURRENT_STATUS_ENUM=" running awaiting_merge ready_for_release escalated failed rate_limit drain_died done "` UNCHANGED (no new value); `current-set` refusals exit 1 with the file byte-unchanged; identical values print `current-set: unchanged`; the write goes through `_runfile_install … full`. The new single-lane refusal is checked before any write and only reads lane.json (jq, `has("single_lane")`-style — never `.single_lane // empty`, which collapses `false`). pinned by: `test-automate-helpers.sh` current-set blocks.
- **`loomwright/scripts/automate-wave.sh`** — keep: `_wb_refuse() { _wb "refused — $*"; exit 1; }` shape; refusals before any worktree/branch is created. The single-lane refusal uses `_wb_refuse`.
- **`loomwright/scripts/automate-merge-watch.sh`** — NOT modified (only exercised by AC 8's test). Its single-instance marker (TSV `pid`/`pr_url`/`started`) and `unset CLAUDE_PID CLAUDECODE` are what AC 8 asserts against.
- **`loomwright/scripts/test-automate-lanes.sh`, `loomwright/scripts/test-automate-helpers.sh`** — keep: the hermetic first executable line (`hermetic-test-env.sh`, enforced by `scripts/check-test-hermetic.sh`); the `check`/counter shape and the final result line; every leg that starts a background process (AC 8's watcher, any stub sleeper) kills it and `wait`s, so no leaked child holds the runner's stdout (`ci-local | tail` hang lesson); the dispatch-membership pin is TWO loops in `test-automate-helpers.sh` (the `#:` help-line loop and the exec-arm loop, both `for ln_s in lane-create …`) — `lane-park` and `lane-drain-check` join BOTH; `hdr-lanes.golden` is regenerated by the test's own golden-write mode, never hand-edited; E1–E6 keep their order, only E3's expectation flips.
- **`loomwright/scripts/test-wave-build.sh`** — keep: the hermetic first executable line (`. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"`), the stub-seam export line (`export LOOMWRIGHT_LANES_META_SYNC="$T/meta-sync.sh" LOOMWRIGHT_LANES_SETUP_MEMORY="$T/setup-memory.sh" LOOMWRIGHT_LANES_POLICY="$T/policy.sh"`), the fixture (bare fake origin + primary clone, stub `ci-local.sh` / `bump-version.sh`, lanes made by the REAL `lane-create`) and every existing wave-build refusal/opened leg byte-unchanged; the AC 11 single-lane leg is appended.
- **Prose surfaces** (`skills/automate-loop/*.md`, `commands/automate.md`, `commands/agent-help.md`, `docs/ARCHITECTURE_CONTRACTS.md`, `docs/result-schemas/**`) — keep every `run-lock.sh acquire … --session-id` line intact (test-run-lock test 16); `scripts/test-automate-loop-split.sh` index/split parity (a new `###` heading in `lanes.md` needs its index stub in `SKILL.md`); citation-drift: no new bare `file:N` — descriptive anchors or pinned citations only; `commands/automate.md` is token-budgeted if listed in `loomwright/docs/prompt-token-budgets.json` (check; `check-token-budget.sh` must stay green); doc-currency (`scripts/check-doc-currency.sh`) green.

## Closed enumerations touched

> Sibling greps at base `ef3d47b`.

- **lane.json key `single_lane`** (sibling: `max_tokens`) — `git grep -n max_tokens -- loomwright | grep -i lane` hits: `loomwright/scripts/automate-lanes.sh` (the lane.json writer + header Files block), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` Lanes "Marker" row (`` `parallel`, `max_tokens`, `created` `` — a closed field list: MUST name `single_lane`), `loomwright/scripts/test-automate-lanes.sh` A7 (tolerates a new key; no change).
- **Run Config `- parallel: 1`** (sibling: `parallel: <N`) — `git grep -ln "parallel: <N"` hits: `loomwright/skills/automate-loop/SKILL.md` (§3 template comment "ONLY present on a --parallel N>1 parent run"), `loomwright/docs/result-schemas/automate-run.md`, `loomwright/docs/result-schemas/automate-run/sections-status-queue.md` ("present only on a `--parallel N>1` parent run") — all three must say "any `--parallel` parent run (N = 1 = single-lane mode)"; `lanes.md` INIT bullet 2 ("`## Run Config` gains `- parallel: N`** on a `--parallel N>1` parent run only").
- **init-check refusal `single_lane_requires_branch_mode`** (sibling: `auto_merge_with_parallel`) — `git grep -n auto_merge_with_parallel` hits: `automate-lanes.sh`, `test-automate-lanes.sh`, `skills/automate-loop/lanes.md` INIT bullet, `skills/automate-loop/resume.md` "Start order" paragraph (`refuse: auto_merge_with_parallel` or `refuse: parallel_out_of_range` stops the start) — each list of init-check refusals names the new one; `commands/automate.md` does not carry the token (its `--parallel` row says "`--auto-merge` with N > 1" in prose) — extend that prose row. `docs/result-schemas/schema-versioning.md`'s 2026-10-08 entry ("`- parallel: N` Run Config line") is a dated historical record: no edit — a NEW additive entry is added instead (AC 13).
- **Parent `## Progress` line `fleet closeout: <lane> tokens TOTAL=<n>`** (sibling: `fleet closeout: <lane> <item> done (PR <url>)`) — hits: `automate-lanes.sh` (writer + header), `docs/result-schemas/automate-run/parallel-lanes.md` (the `--parallel` Progress-lines table — closed: MUST add the row, noting single-lane only).
- **"A READY lane parks `ready_for_release`" claim** — `git grep -ln ready_for_release` (19 files); the ones making the unqualified claim: `SKILL.md` (§3 lifecycle line, `paused` definition, `current-set` table "Lane READY park" row), `docs/TELEMETRY.md` (`automate_ready_for_release` row), `lanes.md`, `per-item-loop.md`, `docs/result-schemas/automate-run/item-lifecycle.md`, `ARCHITECTURE_CONTRACTS.md` Lanes "Merge" row, `commands/agent-help.md`, `commands/automate.md` — each qualified to N>1 lanes.
- **No new `status` / `pause_reason` value** — `CURRENT_STATUS_ENUM` and the `pause_reason` enum are untouched (`token_ceiling` already exists).

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| E3 (flipped) — `--parallel 1 --auto-merge` ⇒ refuse | restore `[ "$n" -gt 1 ]` in the auto-merge refusal ⇒ `ok`, red |
| init-check branch-mode leg (stub mode `off`) ⇒ `refuse: single_lane_requires_branch_mode` | delete the mode check ⇒ `ok`, red |
| init-check N>1 makes no mode read (stub that fails loudly if called) | read the mode for every N ⇒ red |
| lane-create `--parallel 1` ⇒ lane.json `single_lane: true` (FIRST LEG — the requirement's mutation control) and `lane-park --root <lane>` prints `awaiting_merge` | in `lane-park`'s single-lane branch print `ready_for_release` ⇒ red |
| lane-create without `--parallel` / with `--parallel 2` ⇒ no `single_lane` key, `lane-park` ⇒ `ready_for_release` | write `single_lane` whenever `par == 1` (the default `par="$n"`) ⇒ `lane-create … 1` without the flag red |
| `lane-park` with malformed lane.json ⇒ `ready_for_release` | treat unreadable as single-lane ⇒ red |
| `lane-park` with NO lane.json (not a lane) ⇒ `awaiting_merge` | print `ready_for_release` when the file is absent ⇒ red |
| lane-drain-check on an unreadable lane run file ⇒ `drain-guard: unknown — …` | fall through to `ok` on an unreadable run file ⇒ red |
| current-set refuses `ready_for_release` in a single-lane checkout (file byte-unchanged) | delete the single-lane refusal ⇒ write happens, red |
| current-set unchanged with no lane.json (`awaiting_merge` / `ready_for_release` both written) | make the refusal unconditional ⇒ red |
| fresh lane number: L1 reused under `--parallel 1` ⇒ refused | delete the "already used" table check ⇒ red |
| lane number 11 accepted under `--parallel 1`, still refused without it | widen the bound for every caller ⇒ the no-flag leg red |
| token ceiling: SPENT ≥ T ⇒ `token_ceiling total=…`; SPENT < T ⇒ lane.json `max_tokens` = T − SPENT; a gone lane with no tokens line ⇒ `ledger_unreadable` | drop the gone-lane `fleet closeout: … tokens TOTAL=` read ⇒ SPENT under-counts, red; keep `T / par` ⇒ max_tokens wrong, red |
| fleet-closeout on a `- parallel: 1` parent writes `fleet closeout: <lane> tokens TOTAL=<n>` before lane-remove; on an N>1 parent writes none | write it unconditionally ⇒ N>1 leg red; write it after lane-remove ⇒ the ordering assertion red |
| watcher survival (AC 8) | remove `nohup` (or the trailing `&` detachment) from the documented launch line in the `automate-merge-watch.sh` header ⇒ the leg runs the drifted line, the marker pid is dead after the parent exits (or the parent blocks), red |
| `lane-remove` (plain AND `--abandon`, one leg each) on a `- parallel: 1` parent writes the tokens line before deleting; on an N>1 parent writes none | delete that write ⇒ the next `lane-create --max-tokens` refuses `ledger_unreadable`, red; write it unconditionally ⇒ N>1 leg red |
| lane-drain-check: dispatch marker present ⇒ `violation` | drop the marker check ⇒ red |
| lane-drain-check: two plain `owned drain started — ` lines after the last `picked` ⇒ `violation`; one plain + one fix-now ⇒ `ok` | count from the FIRST `picked` instead of the last (fixture has an earlier item's drain) ⇒ red; count both forms together ⇒ the fix-now leg red |
| lane-drain-check: config backup present ⇒ `violation` | drop the backup check ⇒ red |
| wave-build on a `- parallel: 1` parent ⇒ `refused — single-lane mode (no wave PR)` | delete the refusal ⇒ red |
| dispatch membership: `lane-park`, `lane-drain-check` | remove either dispatch arm ⇒ the membership loop red |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Single-lane mode: init-check, lane-create marker/numbering/ceiling, lane-park + current-set guard, drain check, fleet-closeout tokens line, wave-build refusal, tests, docs | all | 19 modify, 2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "single_lane_requires_branch_mode"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "single_lane"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lane-park [--root"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lane-drain-check"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "tokens TOTAL="}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "lane-park [--root"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "lane-drain-check"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/runfile.sh", name: "single_lane"}
  - {kind: "symbol", path: "loomwright/scripts/automate-wave.sh", name: "single-lane mode"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-lanes.sh", name: "single_lane_requires_branch_mode"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-lanes.sh", name: "lane-drain-check"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "single_lane"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/lanes.md", name: "Single-lane mode"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/per-item-loop.md", name: "lane-park` prints"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "single-lane"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run/parallel-lanes.md", name: "tokens TOTAL="}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "single_lane"}
  - {kind: "file", path: "changelog.d/tr08b-single-lane-sequential.md"}
  - {kind: "file", path: "docs/evidence/tr08b-single-lane-sequential.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/runfile.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/automate-wave.sh"
  - "loomwright/scripts/test-wave-build.sh"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/scripts/fixtures/automate-helpers-help/"
  - "loomwright/skills/automate-loop/"
  - "loomwright/commands/automate.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/result-schemas/automate-run/"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/result-schemas/schema-versioning.md"
  - "changelog.d/tr08b-single-lane-sequential.md"
  - "docs/evidence/tr08b-single-lane-sequential.md"
external_requires:
  - "jq (already required by automate-lanes.sh)"
  - "ps with -o command= (BSD/macOS and procps Linux) for the watcher-survival leg"
```

### Design notes for the worker (decided here; do not re-open)
- **Single-lane = an explicit flag, never inferred.** `lane-create`'s `par` defaults to `n` (`[ -n "$par" ] || par="$n"`), so `parallel == 1` in lane.json does NOT mean single-lane; only an explicit `--parallel 1` writes `single_lane: true`. Track "flag given" separately from `par`.
- **Branch-mode refusal lives in `init-check`** (the first step of §4's start order whenever `--parallel` is passed), N = 1 only; the reader is the existing `SETUP_MEMORY` seam with `--root "$(git rev-parse --show-toplevel)"`; anything but a first line starting `on ` refuses (fail CLOSED).
- **Item order:** the first `- [ ]` Queue row — `plan-waves` is never called for N = 1 (`loomwright/scripts/automate-helpers.d/plan-waves.sh` header: "never called when N = 1").
- **Park-order inside a lane:** decide-then-park (the lane's existing order), never the park-first list.
- **Token totals of removed lanes** are carried ONLY by the parent `## Progress` line AC 9 writes; `lane-create` parses it with an anchored match on `fleet closeout: <lane> tokens TOTAL=` and treats `unknown` / absence as unreadable (fail CLOSED → `token_ceiling ledger_unreadable`). Honest limit (state it in `lanes.md`): like every ledger read, it never counts the coordinator's own main-thread tokens or CI spend.
- **No coordinator-armed watcher** — the lane arms it (the coordinator's no-write-into-a-lane rule stands). If the real lane's watcher dies with the `claude -p` process, the `--resume` → `lane-convert-ready` → `fleet-closeout` path closes the lane out anyway; `lanes.md` states that fallback.
- **Vendor ratchet:** prose additions naming `claude -p` / `CLAUDE_PID` may raise counts in `loomwright/docs/vendor-coupling-manifest.json`; run `scripts/check-vendor-coupling.sh` AFTER `git add` and raise allowances with a reason only where the new text needs it.
- **Tests:** stubs via the existing seams (`LOOMWRIGHT_LANES_SETUP_MEMORY`, `LOOMWRIGHT_LANES_TOKEN_LEDGER`, PATH-stub `gh`); every leg that starts a background process kills and `wait`s it (piped-suite leaked-child lesson); run the changed suites once piped through `tail` to prove no hang.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope beyond `## Touches` (every out-of-Touches surface listed in Feasibility row 4) (Feasibility (Phase 2.5)) | HIGH | Each is named in lanes and ACs; edits are bounded to the single-lane qualification; no N>1 behaviour changes (AC 12) |
| Prior churn on `automate-helpers.sh` (26), `test-automate-lanes.sh` (9), `automate-lanes.sh` (8), `lanes.md` (2) with recurring `drain_churn` / `self_heal_churn` and a prior `self_heal_miss` (Prior churn (postmortem ledger)) | HIGH | Every new behaviour has a pin + a one-line mutation (Pin mutations); restated lists updated in the same change as their authority (house rule); worker runs doc-currency + citation-drift + token-budget + vendor ratchet before hand-back |
| E3 and `lg_intro` pins must flip although the requirement says existing tests pass unedited (Feasibility (Phase 2.5)) | MEDIUM | Both are `--parallel` paths; AC 12 enumerates the only permitted pre-existing edits and the worker lists every one |
| The real lane's watcher may not survive `claude -p` exit (Feasibility (Phase 2.5)) | MEDIUM | AC 8 proves detachment from a short-lived parent; the `--resume` backstop closes the lane out regardless; the real-lane proof is the operator's Validation 2 (Not verified otherwise) |
| Whole-run ceiling under-counts if a lane is removed without the tokens line (hand `lane-remove`) | MEDIUM | Missing line ⇒ `ledger_unreadable` ⇒ refuse (fail CLOSED), never a silent overspend |
| The `/automate` validation gate reads a PR-body `validation 2` passage that FINALIZE's template does not write | LOW | Operator's act at the park: paste the evidence (or `AUT-WAIVE` with words), as on 39b; the committed evidence file (AC 15) is the worker's deliverable |
| Leaked background processes from watcher/stub legs hang the piped suite | MEDIUM | Every leg kills and waits what it started; piped `tail` run once |

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-14-tr08b-single-lane-sequential.md
```

## Plan Review
- **Reviewer decision:** PASS (attempt 3/3) | **Attempts:** 3/3
- **Attempt 1:** FAIL — 1 HIGH (AC 15's evidence only in the PR body, Criterion 20), 3 MEDIUM (RECONCILE re-check path wrote `ready_for_release` in a lane; init-check refusal enumeration hit list; no invariants entry for the two test scripts), 3 LOW — all fixed.
- **Attempt 2:** PASS — 4 MEDIUM (SKILL.md's three unqualified `ready_for_release` claims + TELEMETRY row; `lane-park` provides tokens satisfied at base by `lane-park-notify`; abandoned lane left the whole-run ceiling stuck; watcher-survival mutation edited the test, not the documented launch line), 3 LOW — all fixed (at-floor refine, re-reviewed).
- **Attempt 3:** PASS — 1 MEDIUM, 4 LOW.

| # | Severity | Section | Description | Resolution |
|---|----------|---------|-------------|------------|
| 1 | MEDIUM | Touched-file invariants | `test-wave-build.sh` (in lanes) had no invariants entry | fixed (owner override — post-PASS edit, not re-reviewed: cap exhausted) |
| 2 | LOW | Pin mutations | plain `lane-remove`, `lane-park` with no lane.json, `drain-guard: unknown` had no pin rows | fixed (owner override, not re-reviewed) |
| 3 | LOW | Acceptance Criteria | AC 8 did not name its test file | fixed → `test-automate-lanes.sh` (owner override, not re-reviewed) |
| 4 | LOW | Feasibility | row 4 restated a stale surface count | fixed → count-free list (owner override, not re-reviewed) |
| 5 | LOW | Review coverage | prompt budget for commands/automate.md, remaining READY-claim wordings, changelog.d/README.md, SKILL.md index stub parity | deferred to the worker's hand-back re-check (check-token-budget / doc-currency / test-automate-loop-split enforce them) |

**Owner decision (2026-10-15, Phase 6):** "Apply fixes, then save" — the post-PASS edits above were applied without a fourth review; Phase 4.5 is the next lens on them.

## Outcome
- **Status:** completed
- **Completed:** 2026-10-15T02:04:49Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/548
- **Branch:** feature/tr08b-single-lane-sequential
- **Files changed:** 27
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed (guard_armed: ok at INIT)
- **Summary:** /automate --parallel 1 is single-lane mode: init-check refusals (auto-merge at any N; branch mode off), lane.json single_lane (explicit flag only), fresh lane numbers 1..99, whole-run token ceiling (SPENT incl. removed lanes' recorded tokens lines), lane-park + current-set single-lane refusal, lane-drain-check marker guard, fleet-closeout/lane-remove tokens line, wave-build refusal, docs. Phase 4.5: 3 reviews (PASS+2 MEDIUM → PASS+1 MEDIUM → PASS), 2 fix rounds (403f3ab drain-check optional-timestamp/colon reader + shared tokens-line reader + invariants.md scope; 06ce6f5 lanes.md pointer); risk_classification high_risk true (advisory); ground_truth 2/2; contract_conformance advisory_violations 1 (automate-lanes.sh twin invariant "N = 1 nothing here runs" — superseded by design); rules gate none; 2 LOW dismissed below the MEDIUM floor; pin-mutation gate 21 unverified (prose rows — held by hand by worker + reviewers for lane-park, current-set, drain-check counting).

## Not verified
- **Validation 2: a real /automate --parallel 1 run (lane at its awaiting_merge park; watcher pid alive after the lane's claude -p exits; no wave PR; item 2 in a new lane with a fresh session id)** — needs a detached headless lane, a real PR and an owner-typed command; commands in docs/evidence/tr08b-single-lane-sequential.md (subtask 1)
- **lanes.md "Single-lane mode" prose as executed by a live agent** — only the script seams are tested (subtask 1)
