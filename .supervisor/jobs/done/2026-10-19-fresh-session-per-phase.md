# Supervisor Job: Run each phase of an /automate item (Launch Pad, Supervisor, owned drain) in its own fresh headless session, with questions reaching the owner through the lane question relay

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-15-163325/L19 (lane L19 clone of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/09-fresh-session-per-phase.md
- **Base commit:** 626f35fab85796da1c0a4da0b2e80480a8249a02

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash + jq + the `claude -p` CLI, all already used by the lane machinery (`automate-lanes.d/launch.sh` `_lanes_spawn`) |
| 2 | Dependency Availability | GO | `claude --help` lists `--settings <file-or-json>`, `--resume`, `--permission-prompt-tool`; no new dependency |
| 3 | Architecture Fit | CAUTION | Rewrites the documented inline-only rule (`ARCHITECTURE_CONTRACTS.md` §"Subagent nesting", §"Question-gate inventory"). Owner chose Proceed (requirement "Owner decisions", Flag 4) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~25 files incl. a 2,600-line driver — above the `context-bound` bound (> 12 files); split into 3 dependency-ordered subtasks |
| 5 | Hard Blockers | CAUTION | (a) the run lock is re-entrant only on an identical session id, so a phase session would park `run_lock_held`; (b) the lane relay hook refuses any checkout without `.supervisor/lane.json`; (c) the Validation "running system" step needs a real end-to-end item, which only the owner can run. All three are designed for below |

**Overall Verdict:** CAUTION

## Task
**Goal:** By default, `/automate` runs each phase of a Queue item — Launch Pad (brief), Supervisor (implement + Phase 4.5), and the owned `/review-pr --until-mergeable` drain — as its own fresh headless `claude -p` session that reads its inputs from disk and writes its result block to a sidecar; a phase's questions reach the owner through the existing lane question relay (defer + resume); `--inline-phases` keeps today's inline behaviour.

**Problem Statement:**
The `/automate` coordinator (owner) needs each item's phases to run outside its own context because today the whole item — Launch Pad, Supervisor, Phase 4.5 and the drain — runs inline in ONE growing main-thread context (median lane item 65M main-session tokens, 647K peak; plan doc §"Why now").
Currently `next-step`'s `run` spawn is one inline `/autonomous --single-iteration` and its `drain` spawn one inline `/review-pr`, and Step 0 of `commands/automate.md` reads both workflow bodies into the coordinator. This costs every item the full context of every phase, and `--parallel 1` only helps across items, not inside a large one.
Success looks like: three `## Progress` `session_id` lines per item naming three distinct phase session ids, and a coordinator that never reads `agents/launch-pad.md`, `agents/supervisor.md`, `skills/self-heal-advisory/` or `skills/review-heal/`.

### Design (the plan the subtasks implement — decided here so the three subtasks agree)

**D1 — Phase-session runner = a new lane-machinery module, not a new script.** `loomwright/scripts/automate-lanes.d/phase.sh`, sourced by `automate-lanes.sh` through the existing module loader, dispatched (and therefore reachable through `automate-helpers.sh` like every lane subcommand) as:
- `phase-check` — read-only, one line, exit 0: `phase-check: ok` or `phase-check: unavailable — <reason>` (no `claude` on PATH; `_lanes_regime_ok` fails; `jq` missing). Fail CLOSED: anything it cannot read is `unavailable`.
- `phase-launch <runfile> <phase> --owner-command '<cmd>' --coordinator-session <sid> -- <phase prompt>` — `<phase>` ∈ `launch-pad` | `supervisor` | `drain`. Same launch-authority rule as `lane-launch` (no `--owner-command` ⇒ `phase-launch: BLOCKED — <phase> — no owner command — need the owner`, exit 3, no process). Phase dir: `.supervisor/automate/<run_id>.phase/<phase>/` holding `stream.log`, `stdin.json`, `.died`, `session`, `pid`, `inbox/questions/`, `inbox/answers/`. Spawns detached via the same `nohup bash "$SELF" _lane-run …` wrapper shape `_lanes_spawn` uses (reuse its flag list, `LANE_ALLOWED_TOOLS`, `LANE_DISALLOWED_FIXED`, `LANE_SYS`), cwd = the run's checkout, plus `--settings '<json>'` carrying ONLY the relay hook (PreToolUse + PermissionRequest `AskUserQuestion` → `automate-lanes.sh relay-hook`), and env `LOOMWRIGHT_PHASE_DIR=<phase dir>` and `LOOMWRIGHT_RUN_LOCK_SESSION_ID=<coordinator sid>`. It writes nothing into `.claude/settings*.json`.
- `phase-wait <runfile> <phase> [--timeout S]` — blocks at most S seconds (default 540, below the Bash tool's 600 s cap) and prints ONE line: `phase-wait: done — session <sid> result <sidecar path>` (exit 0, the process exited with a `"type":"result"` line), `phase-wait: running — session <sid>` (exit 3, call again), `phase-wait: question — <tool_use_id> <question file>` (exit 5, the session deferred on `AskUserQuestion`), `phase-wait: died — <reason>` (exit 6, `.died` marker or no result line).
- `phase-answer <runfile> <phase> <tool_use_id> --owner-command '<cmd>'` (stdin `{"answers":{…},"note":"…"}`) — validates labels exactly as `lanes_answer` does (only the question's own labels; a note alone refused), writes the answer file, resumes the deferred session with `--resume <session>` (the `_lanes_answer_write_resume` path), then returns; the caller goes back to `phase-wait`.

**D2 — The relay hook learns phase dirs, nothing else.** In `lanes_relay_hook`, when the hook's environment carries a non-empty `LOOMWRIGHT_PHASE_DIR` that is a directory under `.supervisor/automate/` ending in `.phase/<phase>`, the question/answer files go to `$LOOMWRIGHT_PHASE_DIR/inbox/{questions,answers}/` and `_lanes_hook_root`'s lane lookup is skipped; with the variable unset the hook is byte-for-byte today's behaviour. No policy lookup in a phase dir (`_lanes_policy_apply` is lane-only): every phase question reaches the coordinator. Inside a lane clone (the lane's own `.claude/settings.local.json` also carries the relay hook) the phase variable wins, so a phase question is never recorded in the lane inbox; if both hook entries fire, the write is idempotent.

**D3 — Coordinator relay = re-ask verbatim.** On `phase-wait: question`, the coordinator asks the owner with ONE `AskUserQuestion` call carrying the recorded question's `header`, text and option labels verbatim, then `phase-answer`. Inside a lane, that ask is itself relayed by the lane's own hook — so a catalogued `allowed` gate (e.g. `LP-SAVE`) is still answered by the lane policy exactly as today, and every other question reaches the wave coordinator's owner. The coordinator never answers a phase question itself. Cannot ask ⇒ the gate's existing named can't-ask status (`docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory"), never a hang.

**D4 — Run lock across sessions.** `run-lock.sh acquire` additionally treats a lock as re-entrant when `LOOMWRIGHT_RUN_LOCK_SESSION_ID` is non-empty and equals the recorded `session_id` (printing the same `run_lock_reentrant owner=<outer> session_id=<id>` line). `release` is unchanged — the variable never makes a release match, so a phase session's own release stays a no-op and only the coordinator frees the lock. `_lanes_spawn` adds `-u LOOMWRIGHT_RUN_LOCK_SESSION_ID -u LOOMWRIGHT_PHASE_DIR` to its `envu` so a lane never inherits either.

**D5 — The driver's fresh spawns.** `automate-next-step.sh` gains a persisted `--inline-phases` flag (`flag_inline_phases`, persisted like `flag_mode`; absent ⇒ fresh phases). With it, every instruction and run-file write is exactly today's. Without it:
- **PICK:** before `current-set`/the `picked` line, the driver runs `phase-check`; anything but `ok` ⇒ a RUN-level park, new `pause_reason: phase_relay_unavailable`, lock released, message naming the reason and `--inline-phases` — nothing spawned.
- **`plan` step (new, before `run`):** `{"do":"spawn","step":"plan","session":"fresh","phase":"launch-pad","what":"launch pad phase",…,"launch":"<the phase-launch command>","sidecar":"<run_id>.launch-pad-result.md","then":…}` — the phase prompt is `/loomwright:launch-pad goal: <item>` (+ `--non-interactive` under `--non-interactive-fallback`), the preserve-verbatim `## Outcomes Rubric` directive `/autonomous` PLAN step 2 gives today, and the instruction to write its `LAUNCH_PAD_RESULT` block verbatim to the sidecar. Report: `{"launch_pad_result_file": <path>, "session_id": <phase sid>}`. The driver validates it with `validate-launch-pad-result.py --raw`, applies `/autonomous` PLAN step 4's status mapping (saved ⇒ remember `saved_brief_path`; discarded / blocked / aborted ⇒ the same no-PR outcome and `status_reason` `/autonomous` would report), and checks `has_rubric` preservation when the requirement carried a rubric.
- **`run` step:** `session: fresh`, `phase: supervisor`, prompt `/loomwright:supervisor job: <saved brief> [--non-interactive] [--cheap] [--max-tokens N]` + "write `SUPERVISOR_RESULT` verbatim to `<run_id>.supervisor-result.md`". The `.auto_review` suppress/restore keeps wrapping this step exactly as it wraps today's RUN. Report: the existing `{"supervisor_result_file": …, "session_id": <phase sid>}` shape.
- **`drain` step:** `session: fresh`, `phase: drain`, prompt = today's `invocation` + "write `REVIEW_HEAL_RESULT` verbatim to `<run_id>.review-heal-result.md`". Report: the existing `{"review_heal_result_file": …}` / `{"no_terminal_block": true}` shapes, plus `session_id`.
- **Step names (closed list):** fresh mode adds the driver step values `plan` (the Launch Pad spawn) and `phase-guard` (the PICK-time `phase-check` park, beside today's `lane-guard`), plus `plan-result` if the result handling follows today's `run` / `run-result` split. `run` and `drain` keep their names. Subtask 2 adds every new `ns_dispatch` arm to the schema doc's step list (`one of the driver's \`case\` arms:`) in the same change, because `test-automate-next-step.sh` section D compares that list with `ns_dispatch`.
- **Which session id each phase records:** each report's `session_id` is the id that phase's token ledger is filed under (`emit-token-ledger.sh` prefers the plugin id in `.supervisor/state.md`, else the Claude Code uuid). For `supervisor`, that is the `- session_id:` in `.supervisor/state.md` after the phase, which is today's RUN fallback rule. For `launch-pad` and `drain`, no Supervisor state is written, so it is the Claude Code uuid that `phase-wait` prints. The coordinator reports the id `phase-wait` printed, and the driver resolves the supervisor one from `state.md` exactly as `ns_run_record` does today.
- **Progress line shape (kept parseable):** each fresh phase appends `session_id <sid> (<item>) phase=<phase>`. The `(<item>)` part is byte-identical to today's line, so `read-token-ledger.sh --run-id` (`grep -oE 'session_id [A-Za-z0-9_-]+'`) and `--per-item` (`pi_cc_ids`, which matches text after ` (` starting `<item>)`) both read all three phases unchanged. `phase-timing.sh`, which today keeps the LAST `session_id` match as the item's one session, is changed to prefer the `phase=supervisor` line (or an un-suffixed line, the inline form) when timing Supervisor phases.
- The fix-now re-drain spawn is unchanged (a coordinator Task `general-purpose` agent — out of scope, "changing what each phase does" is a non-goal).

**D6 — Docs.** `commands/automate.md` Step 0 reads `commands/autonomous.md` / `commands/review-pr.md` ONLY under `--inline-phases`. `ARCHITECTURE_CONTRACTS.md`: legend gains **HR** = headless phase session with relay; every gate reached from a phase session lists HR with its can't-ask status unchanged; §"Subagent nesting" says the workflows stay inline *inside their phase session*. Skill split files, the schema doc, and the loop inventory follow (subtask 3).

## Acceptance Criteria
- [ ] AC1 — Given a Queue item run without `--inline-phases`, when the driver walks it, then it emits three `spawn` instructions with `"session":"fresh"` and `phase` `launch-pad`, `supervisor`, `drain` in that order, and `## Progress` gains one `session_id <sid> (<item>) phase=<phase>` line per phase. This is asserted by new `test-automate-next-step.sh` legs with three distinct fake session ids. A `test-read-token-ledger.sh` leg then shows that `--run-id` sums one fake ledger per phase and `--per-item` resolves all three ids, and a `test-phase-timing.sh` leg shows that the supervisor phase's id is the one timed.
- [ ] AC2 — Given `--inline-phases`, when the driver walks the same item, then every instruction and the run file are byte-identical to today's (the existing `test-automate-next-step.sh` and `test-automate-golden.sh` expectations pass unchanged with the flag supplied by the harness).
- [ ] AC3 — Given no relay (`phase-check` prints `unavailable — …`) and no `--inline-phases`, when PICK runs, then the run parks `pause_reason: phase_relay_unavailable` with no `picked` line and no spawn, the run lock released; asserted by a `test-automate-next-step.sh` leg and a `phase-check` leg in `test-automate-lanes.sh` (stub `claude` without `--permission-prompt-tool` ⇒ `unavailable`).
- [ ] AC4 — Given a phase session that calls `AskUserQuestion`, when it runs under `phase-launch`, then the relay hook records the question under the phase dir (never the lane inbox), the session defers, `phase-wait` prints `question — <id> <file>` (exit 5), and `phase-answer` with a valid label writes the answer and resumes the SAME session id with `--resume`; asserted in a new `test-automate-lanes.d/06-phase-sessions.sh` part with the existing `claude` stub (`STUB_MODE=defer`).
- [ ] AC5 — Given `phase-launch` with no `--owner-command`, then it prints `phase-launch: BLOCKED — …` and exits 3 with no process started.
- [ ] AC6 — Given a lock held by `automate:<run_id>` with session S, when a process with `LOOMWRIGHT_RUN_LOCK_SESSION_ID=S` acquires with its own session id, then it prints `run_lock_reentrant …` and exits 0, AND its `release` with its own owner/session leaves the lock held; asserted in `test-run-lock.sh`. A lane spawn's environment carries neither `LOOMWRIGHT_RUN_LOCK_SESSION_ID` nor `LOOMWRIGHT_PHASE_DIR` (asserted from the stub's `ENV` log).
- [ ] AC7 — Given a `launch-pad` phase report whose `LAUNCH_PAD_RESULT` is `discarded` / `blocked` / `aborted` / malformed, then the driver records the same no-PR outcome and `status_reason` `/autonomous` PLAN step 4 maps it to, and emits no `run` spawn.
- [ ] AC8 — Given the docs, then `ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" carries the HR legend entry and every Launch Pad / Supervisor / review-heal gate row lists HR with its named can't-ask status unchanged, §"Subagent nesting" no longer says `/automate` runs every phase inline, `commands/automate.md` Step 0 reads `autonomous.md`/`review-pr.md` only under `--inline-phases`, and `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-loop-inventory.sh` and `bash scripts/check-token-budget.sh` pass.
- [ ] AC9 — Given the change, then a committed evidence file `docs/evidence/as09-fresh-session-per-phase.md` contains the `<passed>/<total>` lines of `test-automate-next-step.sh`, `test-automate-lanes.sh`, `test-automate-golden.sh` and `test-run-lock.sh` from the final head, and names the requirement's Validation step 2 (one real item end to end, each phase's session id, the coordinator's peak context from item 03's report) as the owner's running-system step still to run; the PR body links to it.
- [ ] AC10 — `bash scripts/check-version-bump.sh` passes with a `changelog.d/as09-fresh-session-per-phase.md` fragment (`<!-- bump: minor -->` per the requirement) and no hand-edited version file.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

> Grounded at base `626f35fab85796da1c0a4da0b2e80480a8249a02`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-lanes.sh`** — keep: the module loader's one-line shape the bundler matches, `_lanes_source common || { return 1 2>/dev/null || exit 1; }` (a new `phase` module gets its own `# >>> automate-lanes.d/phase.sh` / `# <<< automate-lanes.d/phase.sh` marker pair and one `_lanes_source phase || …` line, or `_lanes_bundle` stops reproducing the single-file form); reuse: `LANE_ALLOWED_TOOLS`, `LANE_DISALLOWED_FIXED`, `LANE_SYS` for phase sessions; mirror: `lanes_main`'s `case "$sub" in` arm list (one arm per new subcommand) and the `automate-helpers.sh` dispatch/help header that lists lane subcommands (`hdr-lanes.golden` pins it); pinned by: `test-automate-lanes.sh` (`tal_part 05-timeline-and-gate`, plus a new `tal_part 06-phase-sessions` line) and `test-automate-lanes-modules.sh`. That test's `ARMS="lane-create:lanes_create …` must equal `lanes_main`'s arms in order, and its `MODS_WANT="common create launch relay remove notify-guards status-read park-leaks status readiness wave"` must name every module. It also holds each module to 800 lines, so `phase.sh` stays within 800 lines or splits.
- **`loomwright/scripts/automate-lanes.d/relay.sh`** — keep: `[ -s "$root/.supervisor/lane.json" ] || { echo '{}'; return 0; }` for every call without `LOOMWRIGHT_PHASE_DIR`, the `PermissionRequest` deny re-ask, the `tool_use_id` charset guard `*[!A-Za-z0-9_-]*`, and the always-exit-0 hook contract; reuse: the existing question/answer JSON shapes and `_lanes_answer_write_resume`; mirror: `lanes_answer`'s label validation (one unknown label refuses the whole answer).
- **`loomwright/scripts/automate-lanes.d/launch.sh`** — keep: `local -a envu=(-u CLAUDECODE -u CLAUDE_PID -u LOOMWRIGHT_HOLDER_PID)` (extend it, never drop an entry), `_lanes_gate`'s BLOCKED exit 3 / HELD exit 4 semantics, `_lanes_regime_ok`; reuse: `lanes_run_wrapper`'s `.died` rule (no `"type":"result"` line ⇒ `.died`).
- **`loomwright/scripts/run-lock.sh`** — keep: `if [ -n "$SESSION_ID" ] && [ "$lk_session" = "$SESSION_ID" ]; then` (the acquire re-entrancy branch — extend it with the env comparison) and the release condition `|| { [ -n "$SESSION_ID" ] && [ -n "$lk_session" ] && [ "$lk_session" = "$SESSION_ID" ]; }; then` UNCHANGED (the env variable must never make a release match); pinned by: `test-run-lock.sh`.
- **`loomwright/scripts/automate-next-step.sh`** — keep: one instruction per call, the closed `do` enum `spawn | ask | park | done`, `ns_emit spawn run "$x"` / `ns_emit spawn drain` field sets when `--inline-phases` is in force, the `pending_what` routing on `"/autonomous run"` / `"owned drain"` (`:2501-2535` region), `ns_check_text_pair`'s inline-XOR-file rule, exit 1 = helper/writer failure / exit 2 = refusal with nothing written; reuse: `st_set`/`st` for the new `flag_inline_phases` (as `flag_mode` at `if [ -n "$MODE" ]; then st_set flag_mode "$MODE"`), `ns_run_park` for the new park (as the `lane-guard` park `ns_run_park lane-guard live_lane`), `ns_take_text`/`ns_write_text` for the new `launch_pad_result_file`; mirror: `docs/result-schemas/automate-run.md` §"next-step instruction" (the `spawn` field list and report shapes) and `test-automate-next-step.sh` (which mirrors the `do` enum); pinned by: `test-automate-next-step.sh`, `test-automate-golden.sh` (44 fixture cases).
- **`loomwright/scripts/automate-helpers.sh`** — keep: the delegating dispatch line shape `lane-status|lane-feed|lane-readiness|lane-drain-check|validation-gate|lane-park-notify|lane-wait) exec bash "$(dirname "$0")/automate-lanes.sh" "$cmd" "$@" ;;` (extend one of the existing delegating lines with `phase-check|phase-launch|phase-wait|phase-answer`, never add a second exec path) and one `#:` help-header line per subcommand; pinned by: `fixtures/automate-helpers-help/hdr-lanes.golden`.
- **`loomwright/scripts/phase-timing.sh`**: keep the `m = re.match(r"session_id ([A-Za-z0-9_-]+)", t)` parse and its behaviour on a run with only un-suffixed lines (inline mode). The change only chooses which matching line wins when `phase=` suffixes are present. It is pinned by `test-phase-timing.sh`.
- **`loomwright/scripts/read-token-ledger.sh`** (not modified, mirrored): `pi_cc_ids`'s `rest = substr($0, i + 11); n = index(rest, " (")` requires the text after ` (` to start with `<item>)`. The new Progress line keeps that prefix byte-for-byte.
- **`loomwright/scripts/automate-helpers.d/runfile.sh`** — keep: `CURRENT_PAUSE_ENUM=" awaiting_merge ready_for_release awaiting_go …"` as the one validated enum `current-set` reads (extend with `phase_relay_unavailable`, leading/trailing space convention kept).
- **`loomwright/commands/automate.md`** — keep: the `<!-- index-only:begin -->` / `<!-- split:begin ../skills/automate-loop/command-lanes.md -->` markers `test-automate-loop-split.sh` checks; its token ceiling (263 tokens headroom at base) — net-neutral or shrink.

## Closed enumerations touched

> Sibling grep at base `626f35fa`: `git grep -nF 'live_lane' -- ':!CHANGELOG.md'` → 55 hits in 26 files (closed lists below; the rest are prose, fixtures for the lane-guard case, or test legs about lanes).

- **`phase_relay_unavailable`** (sibling: `live_lane`, a RUN-level `pause_reason`) — must be named in:
  - `loomwright/scripts/automate-helpers.d/runfile.sh` — `CURRENT_PAUSE_ENUM=` — extend.
  - `loomwright/docs/result-schemas/automate-run.md` — the `- pause_reason: awaiting_merge|…` template line and the `| `pause_reason` |` field row — extend.
  - `loomwright/docs/result-schemas/automate-run/sections-status-queue.md` — the `paused` row's pause_reason list — extend.
  - `loomwright/docs/result-schemas/schema-versioning.md` — additive-value history — add one entry.
  - `loomwright/skills/automate-loop/SKILL.md` — §3 template `- pause_reason:` line, §3 "`## Status` semantics" `paused` list, and the RUN-level parks row of the `current-set` table — extend.
  - `loomwright/docs/loop-inventory/automate-loop.md` — new rule row(s) for the park.
  - `loomwright/scripts/automate-next-step.sh` — STEPS header comment (the `lane-guard` line) — add the new phase-check line.
  - `loomwright/scripts/fixtures/automate-golden/pick-time-lane-guard-park/*`, `test-automate-helpers.d/15-lane-seams.sh`, `test-automate-lanes.d/01-create-to-wait.sh`, `test-automate-trail.d/01-sidecar-trail-pr.sh`, `automate-lanes.d/notify-guards.sh`, `ARCHITECTURE_CONTRACTS.md:527` row — no change: they are about the lane guard specifically, not a list of every pause_reason.
- **Driver step values `plan` and `phase-guard`, `what` value `"launch pad phase"`** (siblings `run`, `lane-guard`, `"/autonomous run"`). They must be named in `docs/result-schemas/automate-run.md` §"next-step instruction": the `spawn` rows and the step list on the line containing `one of the driver's \`case\` arms:`. Extend both in **Subtask 2**, since `test-automate-next-step.sh` section D compares that list with `ns_dispatch`. They must also be named in the `do`/`what` mirror in `test-automate-next-step.sh` (extend).
- **Lane subcommands `phase-check`, `phase-launch`, `phase-wait`, `phase-answer` and module `phase`** (siblings `lane-wait`, `relay`). They must be named in `lanes_main`'s `case` in `automate-lanes.sh` (extend), `test-automate-lanes-modules.sh` `ARMS=` and `MODS_WANT=` (extend), the module-loader marker pair `# >>> automate-lanes.d/phase.sh` (add), and `automate-helpers.sh`'s lane dispatch/help header plus `fixtures/automate-helpers-help/hdr-lanes.golden` (extend).
- **Progress line `session_id <sid> (<item>) phase=<phase>`** (sibling: `session_id <sid> (<item>)`). Readers: `read-token-ledger.sh` `--run-id` and `pi_cc_ids`, no change needed because the prefix is kept. `phase-timing.sh` must be extended to choose the supervisor line.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-run-lock.sh` — env re-entrancy leg (AC6) | delete the new `LOOMWRIGHT_RUN_LOCK_SESSION_ID` comparison in `run-lock.sh` acquire ⇒ the leg reads `run_lock_held` |
| `test-run-lock.sh` — env never releases (AC6) | add the env comparison to the release condition in `run-lock.sh` ⇒ the leg sees the lock freed |
| `test-automate-lanes.d/06-phase-sessions.sh` — phase question lands in the phase dir (AC4) | delete the `LOOMWRIGHT_PHASE_DIR` branch in `relay.sh` ⇒ the hook prints `{}` (no lane.json) and no question file appears |
| `test-automate-lanes.d/06-phase-sessions.sh` — lane env strip (AC6) | drop `-u LOOMWRIGHT_RUN_LOCK_SESSION_ID` from `envu` in `launch.sh` ⇒ the stub's ENV log shows the variable |
| `test-automate-next-step.sh` — relay-unavailable park (AC3) | flip the `phase-check` result test so `unavailable` proceeds ⇒ a `plan` spawn is emitted instead of the park |
| `test-automate-next-step.sh` — inline parity (AC2) | default `flag_inline_phases` to off when `--inline-phases` is passed ⇒ golden/parity cases see `plan` spawns |
| `test-automate-next-step.sh` — three fresh spawns, three ids (AC1) | flip `"session":"fresh"` → `"session":"inline"` for the supervisor spawn in `automate-next-step.sh` ⇒ the leg's spawn assertion fails |
| `test-phase-timing.sh` — supervisor phase timed (AC1) | delete the `phase=supervisor` preference in `phase-timing.sh` ⇒ the drain session is timed |
| `test-automate-lanes.d/06-phase-sessions.sh` — owner-command required (AC5) | delete the `--owner-command` check in `phase.sh` `lanes_phase_launch` ⇒ the stub sees a spawn and no BLOCKED line |
| `test-automate-next-step.sh` — plan-step status mapping (AC7) | map `discarded` to the saved branch in the driver's `plan` result handling ⇒ a `run` spawn is emitted |
| `test-automate-lanes.d/06-phase-sessions.sh` — phase-check unavailable (AC3) | make `lanes_phase_check` in `phase.sh` skip its `_lanes_regime_ok` call ⇒ the stub without `--permission-prompt-tool` reads `phase-check: ok` |
| `test-read-token-ledger.sh` — per-item resolves all three phase ids (AC1) | have the driver append `session_id <sid> phase=<phase> (<item>)` (suffix before the item) in `automate-next-step.sh` ⇒ `pi_cc_ids` no longer matches `<item>)` and `--per-item` misses the phase ids |
| `test-automate-lanes.d/06-phase-sessions.sh` — PHASE_DIR env strip (AC6) | drop `-u LOOMWRIGHT_PHASE_DIR` from `envu` in `launch.sh` ⇒ the stub's ENV log shows the variable |
| `test-automate-helpers` current-set enum leg | delete `phase_relay_unavailable` from `CURRENT_PAUSE_ENUM` in `runfile.sh` ⇒ the park's `current-set` exits 1 |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Phase-session runner, relay routing, cross-session run lock | AC3 (phase-check leg), AC4, AC5, AC6 | 7 modify, 2 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Driver fresh spawns, `--inline-phases`, relay-unavailable park, schema step list, phase-timing | AC1, AC2, AC3, AC7 | 8 modify, 0–2 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | Contract docs, skill/command text, schema, loop inventory, changelog, evidence | AC8, AC9, AC10 | ~15 modify, 2 create | `skills/automate-loop/SKILL.md` | BLOCKED (by #2) |

### Subtask Contracts

```yaml
# Subtask 1 — phase-session runner (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/automate-lanes.d/phase.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/phase.sh", name: "lanes_phase_launch"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/phase.sh", name: "lanes_phase_check"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/phase.sh", name: "lanes_phase_wait"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/phase.sh", name: "lanes_phase_answer"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "phase-launch"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/relay.sh", name: "LOOMWRIGHT_PHASE_DIR"}
  - {kind: "symbol", path: "loomwright/scripts/run-lock.sh", name: "LOOMWRIGHT_RUN_LOCK_SESSION_ID"}
  - {kind: "file", path: "loomwright/scripts/test-automate-lanes.d/06-phase-sessions.sh"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.d/phase.sh"
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/automate-lanes.d/relay.sh"
  - "loomwright/scripts/automate-lanes.d/launch.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/hdr-lanes.golden"
  - "loomwright/scripts/run-lock.sh"
  - "loomwright/scripts/test-run-lock.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.d/06-phase-sessions.sh"
  - "loomwright/scripts/test-automate-lanes-modules.sh"
external_requires:
  - "claude CLI with -p, --resume, --settings, --permission-prompt-tool (stubbed in tests)"

# Subtask 2 — driver (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "flag_inline_phases"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "phase_relay_unavailable"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "launch_pad_result_file"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/runfile.sh", name: "phase_relay_unavailable"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "phase-guard"}
  - {kind: "symbol", path: "loomwright/scripts/phase-timing.sh", name: "phase=supervisor"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "phase-launch"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-lanes.d/phase.sh", name: "lanes_phase_check"}
lanes:
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/automate-helpers.d/runfile.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/test-automate-golden.sh"
  - "loomwright/scripts/test-automate-helpers.d/*.sh"
  - "loomwright/scripts/fixtures/automate-golden/**"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/scripts/phase-timing.sh"
  - "loomwright/scripts/test-phase-timing.sh"
  - "loomwright/scripts/test-read-token-ledger.sh"
external_requires: []

# Subtask 3 — contract docs (BLOCKED by #2)
provides:
  - {kind: "file", path: "docs/evidence/as09-fresh-session-per-phase.md"}
  - {kind: "file", path: "changelog.d/as09-fresh-session-per-phase.md"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "HR"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "phase_relay_unavailable"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "--inline-phases"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "flag_inline_phases"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "phase_relay_unavailable"}
lanes:
  - "loomwright/skills/automate-loop/*.md"
  - "loomwright/commands/automate.md"
  - "loomwright/commands/autonomous.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/docs/result-schemas/automate-run/sections-status-queue.md"
  - "loomwright/docs/result-schemas/schema-versioning.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "docs/evidence/as09-fresh-session-per-phase.md"
  - "changelog.d/as09-fresh-session-per-phase.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (2 calls 1's subcommands) | YES (requires) |
| Subtask 2 | Subtask 3 | none (3 documents 2's behaviour; 2 owns automate-run.md's §"next-step instruction", 3 only its pause_reason lines afterwards — legal, 2 → 3 ordered) | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after 1)
- **Batch 3:** Subtask 3 (after 2)
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |
| 3 | `skills/automate-loop/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Fresh phases become the DEFAULT for every `/automate` run, including lanes already in a wave | HIGH | AC2 proves `--inline-phases` is byte-identical; `phase-check` parks fail-CLOSED before any spawn when the relay is missing; the changelog fragment names `--inline-phases` as the rollback |
| Phase session acquires `.supervisor/run.lock` with its own session id ⇒ `run_lock_held` | HIGH | D4: env-scoped acquire re-entrancy, release untouched; AC6 pins both directions and the lane env strip |
| A phase question recorded in the LANE inbox inside a lane clone (both hooks fire) | MEDIUM | D2: `LOOMWRIGHT_PHASE_DIR` wins and short-circuits the lane lookup; AC4 asserts nothing lands in `.supervisor/inbox/` |
| Lane policy no longer answers `LP-SAVE` because the phase hook defers | MEDIUM | D3: the coordinator re-asks with the same header and labels, so the lane hook's exact policy lookup still applies; covered by a 06-part leg feeding a policy-carrying `lane.json` |
| `/autonomous`'s PLAN responsibilities (LAUNCH_PAD_RESULT validation, rubric preservation, status mapping) are skipped when it is bypassed | MEDIUM | D5 `plan` step reimplements them in the driver using the same validator and `has_rubric`; AC7 |
| Long phases outlive a 10-minute Bash call | MEDIUM | `phase-wait --timeout` default 540 s, exit 3 = call again — the `ci-local.sh --wait` pattern; never `pgrep -f` on its own command |
| `commands/automate.md` has 263 tokens of budget headroom | LOW | Keep the Step 0 edit net-neutral by moving detail into `per-item-loop.md`; only if impossible, raise the ceiling in `prompt-token-budgets.json` (measured + ~10%) with its `ARCHITECTURE_CONTRACTS.md` mirror row |
| 44 golden cases change if the harness does not pass `--inline-phases` | MEDIUM | Subtask 2 passes the flag in the harness's single driver-call wrapper and adds new fresh-mode cases, rather than editing 44 fixtures |
| A stale `.supervisor/state.md` from an earlier item makes the launch-pad or drain phase's ledger file under the old plugin id (`emit-token-ledger.sh` prefers state.md) | LOW | The existing emitter behaviour, unchanged by this item. AC1's ledger leg uses a fresh state per phase. The risk is named in the evidence file as a measurement limit |
| Validation step 2 (real end-to-end run) cannot run inside the PR | MEDIUM | AC9 records it as the owner's running-system step; the item's validation gate surfaces it at the park |
| Feasibility (Phase 2.5): architecture rule rewrite + scope above the context bound | MEDIUM | Owner Flag 4 Proceed; 3-subtask context-bound split |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-19-fresh-session-per-phase.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-20T00:12:48Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/628
- **Branch:** feature/fresh-session-per-phase
- **Files changed:** 31
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Fresh session per phase for /automate items (phase-session runner, relay routing, cross-session run-lock re-entry, driver plan/run/drain fresh spawns, phase_relay_unavailable park, --inline-phases, docs). Iteration-3 review PASSed; its at-floor MEDIUM test gap + the red required CI check were fixed in af92919, which was not re-reviewed (final iteration).

## Not verified
- **real claude -p phase session (--settings hook merge, hook env inheritance, defer + --resume)** — stub-only; owner's running-system Validation step (subtask 1)
- **a real phase-launch → phase-wait → --result loop with the claude CLI** — stubbed; owner's Validation step 2 (subtask 2)
- **real claude -p phase session incl. coordinator re-ask and can't-ask branch** — stub-only; owner's Validation step 2 (subtask 3)
- **check-vendor-coupling.sh** — 8 breaches in Subtask 1/2 script files — carried to Phase 4.5 (fixed in 6316c0c) (subtask 3)
