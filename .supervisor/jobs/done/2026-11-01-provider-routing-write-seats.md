# Supervisor Job: Provider routing for write seats (worker, heal fix, drain fix)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (11 leftover worktrees under `.claude/worktrees/` plus one in a scratchpad; none overlaps this item's files)
- **Source requirement:** .supervisor/requirements/provider-routing/04-routing-write-seats.md
- **Base commit:** 5fadddb6237b27ad0434c4b79d3d7e953bb12538

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 scripts, jq, markdown prompts: the stack 03 and 05 already use |
| 2 | Dependency Availability | GO | Builds on 03 (`resolve-routing.sh`, `setup-routing.sh`, egress grants) and 05 (`launch-provider-cli.sh`, the real permission probe). Both merged on main @ 5fadddb |
| 3 | Architecture Fit | CAUTION | The first time a non-Claude CLI writes repo files. CLAUDE.md's invariants still hold (Supervisor-side gates decide; only Claude commits and pushes; no new merge path), but the routing docs currently say seats are read-only, so the doc contract widens |
| 4 | Scope vs Supervisor Capability | CAUTION | Roughly 25 files across scripts, tests and prompt docs. This is over the `context-bound` bound, so the work is split into 3 sequential subtasks |
| 5 | Hard Blockers | GO | None. Only Grok 1.0.70 grades `usable for write seats` today. All tests stub the CLI, so CI needs no live provider |

**Overall Verdict:** CAUTION

## Task
**Goal:** Let the `worker`, Phase 4.5 `heal_fix` and drain `drain_fix` seats run their code edits on a granted, write-eligible non-Claude CLI. The CLI is launched only through the isolated launcher, and the plugin's existing gates decide whether the work counts and who commits or pushes it.

**Problem Statement:**
A maintainer needs to hand code changes to the model they prefer (today, Grok) because 03 only routes read-only seats.
Currently `resolve-routing.sh seat worker` prints `REASON=unknown_seat`, and nothing can start a provider that is allowed to write. The danger: Grok reads `~/.claude/settings.json`, and a `permissions.defaultMode: "auto"` there overrides `--permission-mode dontAsk`. So a write launch under the real HOME is fail-OPEN.
Success looks like this: a write seat routes only with a separate per-seat write grant to a provider graded `usable for write seats`, every write launch goes through `launch-provider-cli.sh` isolated with no way to copy `~/.claude/settings.json` in, and the disk gate, tests/lint and Phase 4.5 still decide whether the work counts.

**Design decisions this brief makes (the requirement left them open; each one is restated in the ACs):**
- **Edit-step routing, not agent replacement.** The Claude worker Task and the Claude fix tasks still spawn exactly as today. On a routed seat, their *edit step* is delegated to the provider through the new `write-run.sh`. On that path the Claude task never edits files itself. After the provider returns, the Claude task runs the same post-edit steps as today: tests/lint, `outputs_verified`, local commit, `WORKER_RESULT` or the fix report. Why: the `WORKER_RESULT` contract, `out_of_lane`, the SubagentStop validators and the commit flow all stay intact. The provider never commits or pushes.
- **Allow-list pin, not deny-list.** A write launch uses the provider's pin mode plus explicit allow rules for file read/edit tools only. There is no shell tool, so the provider cannot run tests. The Claude task runs them. A provider without a `provider_write_argv` table entry cannot run a write seat.
- **D1 holds at resolve time.** `on_unavailable: fallback_to_default` applies only when the run resolves `worker`, at Phase 3 entry. A later per-subtask provider failure goes through the existing Worker Failure path and never falls back to a Claude edit mid-run, so a branch never mixes authors.

## Acceptance Criteria
- [ ] AC1 — Given `resolve-routing.sh`, when `write-seats` is run, then it prints one line per write seat (`worker`, `heal_fix`, `drain_fix`) as the only home of those ids, and `seats` still prints only the read-only seats. When `seat <write-seat>` is run, the same precedence applies (`--route` > `routing.seats.<seat>` > default) and the same six KEY=VALUE lines are printed. A `routing.seats.worker` config key no longer resolves every seat to `unknown_seat`. The resolver's header no longer says every seat is read-only: it documents `write-seats`, and its conductor list qualifies `worker` (the Claude worker Task stays a conductor; only its edit step is routed through the `worker` write seat). The `test-resolve-routing.sh` conductor loop still passes, because `worker` stays out of `seats`.
- [ ] AC2 (D2) — Given `routing.seats.worker` names a granted, write-granted provider and `heal_fix` / `drain_fix` are unset, when `seat heal_fix` or `seat drain_fix` is resolved, then each prints `PROVIDER=claude`, `SOURCE=default`, `REASON=` (empty). A fix seat never inherits the worker's provider.
- [ ] AC3 (write grant) — Given a write seat whose resolved entry is a non-Claude provider, when the user-scope egress file grants that provider in `repos.<slug>.providers` but has no `repos.<slug>.write_grants.<seat>` array naming it, then the seat prints `PROVIDER=claude`, `REASON=write_not_granted`, whatever `on_unavailable` is. A write grant without the read grant prints `provider_not_granted`. `resolve-egress-config.sh` prints a `PROVIDER_WRITE_GRANTS=` line on every run: comma-joined `<seat>:<provider>` pairs, each name filtered to the existing allowlist, emptied by the existing newline guard, and empty on a missing or malformed file. A repo-level file can never supply it.
- [ ] AC4 (config-time eligibility) — Given `setup-routing.sh apply`:
  - When `--seat <write-seat>=<provider>` or the new `--grant-write <write-seat>=<provider>` names a non-Claude provider whose `setup-providers.sh check` verdict is not exactly `usable for write seats`, then it prints `REFUSED (provider_not_write_usable)` and writes nothing, to either target.
  - A read seat still accepts `usable for read-only seats`.
  - `--grant-write` writes only `repos.<slug>.write_grants.<seat>` (jq merge, backup-first, byte-compare idempotent). It never writes a seat, and a seat write never writes a write grant.
  - `remove` also deletes this repo's `write_grants`.
  - `docs/command-parts/setup/providers.md` offers a write seat only to providers marked `usable for write seats`. It asks a separate write-grant question naming the provider, the seat and what that grant allows: editing files in the subtask's checkout, sending the prompt and the readable tracked files to the vendor, network egress not blocked. A declined ask writes no write grant.
- [ ] AC5 (launcher guard) — Given a provider table file whose `PROVIDER_LOGIN_FILES` lists `.claude/settings.json` (or any path whose first segment is `.claude`), when `launch_provider_cli isolated` runs, then that file is never copied into the isolated HOME, while every other declared login file still crosses. A regression test in `test-launch-provider-cli.sh` puts a real `.claude/settings.json` containing `{"permissions":{"defaultMode":"auto"}}` in a temp HOME. It asserts that no `.claude/settings.json` exists under the child's HOME during the call and that a sibling declared login file did cross.
- [ ] AC6 (write runner) — Given the new `scripts/adapters/providers/write-run.sh --provider <p>[:<m>] --seat <write-seat> --worktree <dir> --prompt <file> --out <json>`, then:
  - It exits 0 on every outcome and writes one JSON object to `--out`, holding `write_status`, `provider`, `model`, `changed_files` (always an array), `tree_restored` (`true`/`false`, only after a launch), `cost: "unknown"` and `notes` (present only when the status is not `ok`; for `write_git_tampered` it names every changed fingerprint section and path). Usage errors exit 2.
  - `write_status` is one of:
    - pre-launch refusals, none of which starts a CLI or touches the tree: `provider_unavailable`, `provider_not_granted`, `write_not_granted`, `write_unpinnable` (no `provider_write_argv`), `write_claude_is_task_path` (provider `claude`), `write_tree_dirty` (the worktree had uncommitted or untracked non-ignored changes), `write_repo_settings_present` (the worktree root holds a `.claude/settings.local.json`, or a `.claude/settings.json` with a `permissions` key: a repo-side file that could widen the pin, which the probe never tested);
    - post-launch: `ok`, `write_timeout`, `write_failed`, `write_git_tampered`.
  - `write_git_tampered` means the worktree's own HEAD or branch ref moved, or the remotes, local/common config or non-sample hooks (common dir included) changed. The provider committed or rewired git.
  - **Restore on every non-`ok` post-launch status.** write-run puts the tracked tree back at the pre-launch HEAD and removes untracked non-ignored files. The tree was verified clean before launch, so everything it removes is the provider's. On `write_git_tampered` it also restores the pre-launch byte snapshot of the config file(s) and the hooks dir, removing hook files the provider added, so a planted hook or `core.hooksPath` never survives to run under the real HOME. A restore that cannot be completed reads `write_git_tampered` with `tree_restored: false`, never a softer status.
  - **`write-run.sh --restore <sha> --worktree <dir>`** is the same restore as a mode on its own: tracked tree back to `<sha>`, untracked non-ignored files removed, exit 0, a one-line JSON result. It refuses (named, no change) when HEAD is not `<sha>`. The Claude task calls it when write-run returned `ok` but a post-edit gate then failed (AC9/AC10). It starts no CLI.
  - **Timeout budget.** The CLI timeout passed to `launch_provider_cli` comes from `LOOMWRIGHT_WRITE_CLI_TIMEOUT`. It defaults to 420 seconds, and anything that is not a positive integer falls back to the default (validated the same way `lens-run.sh` validates `LOOMWRIGHT_LENS_CLI_TIMEOUT`). Any value above 480 is clamped to 480, so the launch plus the restore always ends inside the 600-second Bash tool limit (AC9/AC10 make the call with `timeout: 600000`). Without that headroom, a Bash-level kill would leave the provider's partial edits in the tree with no restore.
  - The CLI is started only through `launch_provider_cli isolated`. The file contains no `launch_provider_cli shell` call and takes no home-mode argument, and `test-write-run.sh` asserts both.
  - The provider's reply text never sets `write_status`.
  - The worktree's grant is read from the worktree's own repo through `resolve-egress-config.sh`, like `lens-run.sh`. There is no flag or environment bypass.
  - `test-write-run.sh` has stubbed-CLI cases for:
    - a commit made by the provider;
    - a hook the provider planted in the common hooks dir (status `write_git_tampered`, hook removed afterwards);
    - a sibling worktree's branch committing during the launch (still `ok`);
    - partial edits on a timeout (tree restored);
    - a hung stub CLI under a short `LOOMWRIGHT_WRITE_CLI_TIMEOUT` ends as `write_timeout` with `tree_restored: true`, and an over-cap value is clamped to 480;
    - `--restore` after an `ok` run (tree clean afterwards; refused when HEAD moved);
    - each pre-launch refusal (no CLI started).
- [ ] AC7 (shared fingerprint) — Given `lens-run.sh`'s inline `git_integrity_fingerprint`, when it moves into a new sourced `scripts/adapters/providers/git-integrity-lib.sh` (not named `provider-*.sh`), then `lens-run.sh` and `write-run.sh` both source it.
  - It resolves `.git` paths through `git rev-parse --git-dir` / `--git-common-dir`, so it also reads a linked worktree where `.git` is a file.
  - It takes a refs scope: `all` is lens-run's current behavior, unchanged, and `test-lens-run.sh` passes unchanged. `own` is write-run's: the worktree's HEAD and its own branch ref, plus the common config, remotes and hooks. A sibling worker committing on its own branch during a parallel run is therefore never read as tampering.
- [ ] AC8 (Grok write argv) — Given `provider-grok.sh`, when it defines `provider_write_argv`, then the argv is the lens shape plus `--permission-mode dontAsk` and one `--allow` rule per file read/edit tool only (no shell/Bash tool), with the prompt last. Each tool name cites its source in the file's header (the 2026-10-31 probe enforced `Write` and `Edit` as deny-rule names; any other name cites the vendor permissions doc or is left out). A provider file without `provider_write_argv` gets `write_unpinnable`.
- [ ] AC9 (worker seat, D1) — Given a Supervisor run:
  - At Phase 3 entry it runs `resolve-routing.sh seat worker` once and records `seat_routing worker provider=<p> reason=<r>` with `record_decision`.
  - Every worker spawn of that run (Single-Agent, Sequential, and execute-manager's Step 3 parallel spawn) carries that one resolved provider.
  - On `PROVIDER=claude` the spawn is byte-identical to today.
  - Otherwise the worker delegates its edit step to `write-run.sh` in its own checkout (its worktree; the project root on the Single-Agent Path), as ONE Bash call with `timeout: 600000` (AC6's timeout budget). It never edits files itself on that path, and then runs today's tests/lint, `outputs_verified` and commit.
  - A `write_timeout`, `write_failed` or pre-launch refusal makes the worker fail through `docs/FAILURE_ESCALATION.md` §"Worker Failure" (`write_seat_failed:<write_status>`). write-run already restored the tree, so the one same-worktree retry starts clean, with the same provider and never a Claude edit mid-run.
  - **write-run `ok`, then a post-edit gate fails** (tests/lint, `outputs_verified`): the worker runs `write-run.sh --restore <pre-launch sha>`, then fails `write_seat_failed:post_edit_gate` with the gate output. The one same-worktree retry starts clean and hands that output to the provider in the retry prompt (FAILURE_ESCALATION's "Retry includes previous error context").
  - **`write_git_tampered` stops the whole run.** No retry, no remaining subtasks, no Claude fallback, no merge. The worker reports `WORKER_RESULT` `status: failed`, `error: "write_seat_tampered: <write-run notes>"`. The run stops on that error with the exact shape of the existing token-ceiling stop in `agents/supervisor.md` (which today exists on the Sequential Path only; this stop is added on all three paths): no `--result` to the driver, then Phase 4.5's completion tail so the run lock is released. The run's one `SUPERVISOR_RESULT` is the block that completion-tail step 5 emits ("Exactly one block per task"), never an earlier second block. It has `status: failed`, `error: "write_seat_tampered"`, and `heal_loop_ran: false` with all heal fields null/zero, the shape validator rule 6 requires (the same as the token-ceiling stop). **Job lifecycle:** `skills/self-heal-advisory/completion-tail.md` steps 1-2 gain one branch that precedes the PASS / loop-skipped and ESCALATED branches: when `error` is `write_seat_tampered`, the outcome is a terminal failure (not "succeeds cleanly"). The brief moves `in-progress/` → `failed/`, with an outcome section carrying `**Status:** failed`, `**Error:** write_seat_tampered` and write-run's `notes`. It is never `done/` and never resumable. Per path:
    - **Single-Agent and Sequential** (`agents/supervisor.md`): the stop fires as soon as that worker returns; on the Sequential Path no further subtask is spawned.
    - **Parallel** (`agents/execute-manager.md` poll loop): on that error the Execute Manager does no retry and spawns no further worker. It lets already-running workers finish (each is bounded by its own timeout and nothing kills them), then returns its normal EXECUTE_RESULT with the tampered subtask in `subtasks_failed` and that error. No schema change: `error` is already a free string. Supervisor's Parallel-Path `execute-result` routing (`agents/supervisor.md`) is unchanged (the `subtasks_failed` discriminator lives in `supervisor-next-step.sh`). Instead, before the Parallel-Path hand-back (`--result {"result": …}`), Supervisor scans the returned EXECUTE_RESULT's `subtasks_failed[].error` for `write_seat_tampered`. On a hit it sends no `--result` and takes the stop, so nothing is merged and nothing is finalized.
    - **Completion-tail guard:** the stop reaches the completion tail before any Phase 4.5 review has run, so `agents/supervisor.md`'s `**Thrash-escalation exception:**` is extended to cover `error: "write_seat_tampered"` the same way it covers `self_heal_resume_thrash` (the escalation is valid because `error` is non-empty). The guard's abort for every other error is kept. Without this, the stop would be misreported as an invariant violation and left resumable.
    - In every path, write-run's `notes` (the changed sections and paths, and whether they were restored) go to the owner in the escalation.
  - An empty `PROVIDER` (strict) fails the run at Phase 3 entry before any spawn.
- [ ] AC10 (fix seats) — Given Phase 4.5 resolves `heal_fix` (once per Phase 4.5 entry) and the `--until-mergeable` drain resolves `drain_fix` (once per drain), when the resolved provider is not `claude`, then each fix task delegates its edit step to `write-run.sh`, as ONE Bash call with `timeout: 600000` (AC6's timeout budget), and runs today's post-edit steps.
  - `write_timeout`, `write_failed`, a pre-launch refusal, or write-run `ok` followed by a failing post-edit check (in that last case the task first runs `write-run.sh --restore <pre-launch sha>`), under `fallback_to_default`: the fix task makes the fix itself on the clean tree and logs exactly one `seat_routing <seat> provider=<p> reason=<write_status|post_edit_gate>` line.
  - Under `strict` (tree restored the same way): `heal_fix` takes the existing fix-task crash path (`skills/self-heal-advisory/escalation.md` §"Fix task crash handling": `status: checkpoint`). `drain_fix` answers the driver with the existing `{"pushed": false, "push_failed": "write_seat_failed:<status> — <notes>"}` shape, which the driver's existing `push_failed` branch ends ESCALATED. No driver change is needed.
  - **`write_git_tampered`, under either `on_unavailable`, means no fallback and no further fix iteration:**
    - `heal_fix`: Phase 4.5 exits the heal loop at once and ends the run through the completion tail. The step-5 `SUPERVISOR_RESULT` has `status: failed`, `error: "write_seat_tampered"`, `heal_loop_ran: true`, `heal_decision: ESCALATED` and `heal_iterations` set to the iterations actually run. That satisfies validator rule 7 (`heal_decision` ∈ PASS/ESCALATED when the loop ran), and rule 9 holds because `error` is non-empty. The job lifecycle is AC9's `write_seat_tampered` branch (`failed/`), which precedes the ESCALATED → `done/` branch. It is a terminal failure, not a resumable checkpoint.
    - `drain_fix`: the drain ends ESCALATED through the same `push_failed` answer, carrying `write_seat_tampered` and write-run's `notes`.
- [ ] AC11 (contract docs) — Given `docs/PROVIDER_ROUTING.md`, then a new `## Write seats` section states:
  - eligibility (`usable for write seats` only, refused at config time);
  - the isolated-launch invariant and the Grok `defaultMode: "auto"` reason;
  - the `write_repo_settings_present` refusal;
  - the edit-step routing above;
  - that the provider never commits or pushes and its done claim is ignored;
  - the hook contract: under the isolated launch no Loomwright plugin hook, hook-written state, telemetry or guard runs inside the provider, and the Claude task's own hooks plus the Supervisor-side gates carry the checks;
  - the per-seat write grant;
  - D1 / D2 and the failure rules, including that `write_git_tampered` stops the run and restore happens on every non-`ok` launch and after a failed post-edit gate;
  - the honest limit that gitignored paths inside the worktree (e.g. `.supervisor/`, an ignored `.claude/settings.local.json`) are neither checked by the dirty-tree refusal nor removed by the restore.
  The existing read-only framing is reworded so the doc does not contradict itself: the title, the intro's "a seat is a read-only pipeline step", §"What routes, and what never does" ("never gains a write … path"), the conductor list naming `worker`, the closing line of §"Routed seat protocol" ("A routed seat … never decides a gate the Claude seat did not decide") and §"Cost and honesty"'s "a routed seat has no write, merge or ask path". Each of those is scoped to read seats ("a routed read seat …"), and the write-seat counterpart (no merge or ask path; its edits are judged by the Claude-side gates) is stated in `## Write seats`. Read seats keep every rule they have today; write seats are a separate list with the rules above. The sentences "Write seats are a separate, later decision." and "`resolve-routing.sh seat worker` prints `REASON=unknown_seat`" are gone. The write-seat ids are pointed at (`resolve-routing.sh write-seats`), never listed. `docs/FAILURE_ESCALATION.md` §"Worker Failure" has rows for `write_seat_failed:<write_status>` (retry in a restored tree) and for `write_seat_tampered` (stop the run, no retry, escalate).
- [ ] AC12 (release + gates) — Given the finished branch, then a `changelog.d/provider-routing-write-seats.md` fragment whose headline is `Provider routing for write seats` is folded by `bash scripts/bump-version.sh` as Subtask 3's last step, `bash scripts/check-version-bump.sh` passes, `bash scripts/ci-local.sh --affected` passes, and `bash scripts/check-token-budget.sh` passes (any ceiling raised in the same change with its mirror row).

## Touched-file invariants

> Grounded at base `5fadddb6237b27ad0434c4b79d3d7e953bb12538`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/resolve-routing.sh`**:
  - keep: the exit contract `a refusal is a REASON, not a failure`. Every malformed input resolves to `PROVIDER=claude` with a named reason, and a missing grant never sends.
  - reuse: the self-query `SEAT_IDS=" $(bash "${BASH_SOURCE[0]}" seats`. Build the write-seat ids the same way, from a `write-seats` case arm, so they have one home. Reuse the existing `is_granted()`.
  - pinned by: `test-resolve-routing.sh` (`seat worker is unknown_seat`, which must flip to a resolving expectation, and `doc does not restate every seat id`).
- **`loomwright/scripts/resolve-egress-config.sh`**:
  - keep: fail-safe `trap 'exit 0' EXIT`. Every value passes `strip_if_newline() {` before it is printed. User scope only, never a repo file.
  - mirror: the `PROVIDER_GRANTS` jq filter's `\A[A-Za-z0-9_-]+\z` allowlist, for both seat and provider names.
  - pinned by: `test-resolve-egress-config.sh` Group 7 (`grants_key_always_present`).
- **`loomwright/scripts/setup-routing.sh`**:
  - keep: `Every refusal happens before` any write, and REFUSED/ABORTED write nothing and exit 0. The separation `a grant write never writes a seat.` extends to write grants.
  - reuse: `provider_usable() {` and its `load_verdicts` probe parse. Add the write-usable check beside it; do not run a second probe.
  - pinned by: `test-setup-routing.sh` (`apply: REFUSED (provider_not_usable)`).
- **`loomwright/scripts/adapters/providers/launch-provider-cli.sh`**:
  - keep: `It is the ONE place that starts a provider CLI.` Login-file validation stays in `_lpc_valid_rel() {` or right beside it. `PATH|HOME|TMPDIR) return 1 ;;` stays. The file never reads or prints a login file's content.
  - pinned by: `test-launch-provider-cli.sh`.
- **`loomwright/scripts/adapters/providers/lens-run.sh`**:
  - keep: every `emit_result "lens_mutated_tree"` branch and its fingerprint comparison, unchanged in behavior after `git_integrity_fingerprint() {` moves into the shared lib.
  - pinned by: `test-lens-run.sh` (`G lens_status=lens_mutated_tree`).
- **`loomwright/scripts/adapters/providers/provider-grok.sh`**:
  - keep: `probe_perm_argv() {` byte-identical (it is the eligibility probe) and `PROVIDER_LOGIN_FILES=(".grok/auth.json")`.
  - mirror: the lens contract's prompt-last rule (`provider_build_argv`).
- **`loomwright/skills/async-orchestration/SKILL.md`**:
  - mirror: the existing `**Seat routing (`orchestrator`):**` paragraph form for the new `worker` paragraph.
  - keep: `**Single-Agent Worker (Single-Agent path, exactly 1 subtask):**` and the spawn contract text byte-identical on the `PROVIDER=claude` path.
  - budget: 537 tokens of headroom at base.
- **`loomwright/agents/execute-manager.md`**:
  - keep: the `### Step 3: Spawn Background Workers` spawn and the poll-loop disk gate `verify-provides.sh" --verbose {brief_path} {subtask_id} --root {worktree_path}`, unchanged. A routed worker is gated identically.
- **`loomwright/agents/supervisor.md`**:
  - mirror: the existing token-ceiling stop's exact shape, `proceed to Phase 4.5's completion tail so the run-lock is still released`, for the `write_seat_tampered` stop.
  - keep: the Parallel-Path routing's `subtasks_failed` discriminator text for every other error.
  - keep: no new history refs (the `scripts/check-prompt-history-refs.sh` baseline).
- **`loomwright/skills/self-heal-advisory/SKILL.md`** and **`escalation.md`**:
  - keep: the fix-task prompt `You are fixing a feature branch before review passes.` and the pointer `**Fix task crash handling:**` to escalation.md's `## Fix task crash handling`.
- **`loomwright/skills/self-heal-advisory/completion-tail.md`**:
  - keep: step 2's existing PASS / loop-skipped → `done/` and ESCALATED → `done/` (`completed_with_escalation`) branches byte-identical for every other error. The new `write_seat_tampered` → `failed/` branch is added ahead of them in steps 1-2.
  - keep: step 5's `Exactly one block per task, emitted here`, which is the single emission point for the tamper stop's `SUPERVISOR_RESULT`.
  - budget: shares the `self-heal-advisory` ceiling (1812 tokens of headroom at base) with SKILL.md and escalation.md.
- **`loomwright/skills/review-heal/SKILL.md`**:
  - keep: the drain fix-worker prompt `Address ONLY these required-check failures and VALIDATED bot findings`.
  - mirror: the `**Seat routing (`drain_reviewer`).**` paragraph form.
- **`loomwright/docs/PROVIDER_ROUTING.md`**:
  - pinned by: `test-resolve-routing.sh` Group 9 (`## Routed seat protocol` heading, `resolve-routing.sh seats` pointer, `empty `PROVIDER``, `doc does not restate every seat id`).
  - remove: `Write seats are a separate, later decision.`
- **`loomwright/docs/loop-inventory/supervisor.md`**, **`review-heal.md`**:
  - keep: `test-loop-inventory.sh`'s shape. New rows take fresh ids (above SV-767 / RH-390), and the `## Counts` lines and the gap list are updated to match the table.

## Closed enumerations touched

> Sibling grep at base `5fadddb`: `grep -rnF 'provider_unavailable_strict' --exclude=CHANGELOG.md .` → 6 hits in 3 files; `grep -rnF 'provider_not_usable' --exclude=CHANGELOG.md .` → 5 hits in 3 files; `grep -rlF 'PROVIDER_GRANTS' --exclude=CHANGELOG.md .` → 8 files (`.supervisor/` excluded).

- **`write_not_granted`** (sibling: `provider_unavailable_strict`), a resolver REASON. Must be named in:
  - `loomwright/scripts/resolve-routing.sh`: the header `# REASONS` list. Extend.
  - `loomwright/docs/PROVIDER_ROUTING.md`: the `| REASON | When |` table. Extend.
  - `loomwright/scripts/test-resolve-routing.sh`: the strict assertions. Extend with a `write_not_granted` case.
- **`provider_not_write_usable`** (sibling: `provider_not_usable`), a REFUSED reason. Must be named in:
  - `loomwright/scripts/setup-routing.sh`: the header `REFUSED reasons:` list. Extend.
  - `loomwright/docs/command-parts/setup/providers.md`: the `REFUSED (unknown_seat | …)` list. Extend.
  - `loomwright/scripts/test-setup-routing.sh`: the refusal assertions. Extend.
- **`PROVIDER_WRITE_GRANTS`** (sibling: `PROVIDER_GRANTS`), a resolver output key:
  - `resolve-egress-config.sh`: the documented key list and the printed keys. Extend.
  - `test-resolve-egress-config.sh`: Group 7. Extend.
  - `resolve-routing.sh`: the grant reader. Extend (reads it).
  - `write-run.sh`: created; reads it.
  - `setup-routing.sh`: the `status` grants cell. Extend (shows write grants).
  - `docs/PROVIDER_ROUTING.md`: the consent rule. Extend.
  - `lens-run.sh`: no change. A lens is a read seat and needs no write grant.
  - `test-setup-routing.sh`: extend (`status` shows write grants).
  - `test-resolve-routing.sh`: extend (AC3 cases).
  - Consumers `send-webhook.sh`, `send-telemetry-core.sh`, `rules-check.sh`, `build-capabilities.sh`: no change. They read the KEY=VALUE lines by name and ignore the others, as they did when `PROVIDER_GRANTS` was added.
- **`write_seat_tampered`** (sibling: `release_refold_refused`), a closed SUPERVISOR_RESULT `error` value. Grep: `grep -rnF 'release_refold_refused' --exclude=CHANGELOG.md loomwright scripts` → 19 hits in 10 files.
  - `loomwright/docs/result-schemas/supervisor-result.md`: the additive `error:` value list. Extend.
  - `loomwright/skills/async-orchestration/SKILL.md`: the emit site (the `worker` Seat routing paragraph). Extend.
  - `loomwright/docs/FAILURE_ESCALATION.md`: the escalation row. Extend.
  - `loomwright/agents/supervisor.md`: the stop, beside the token-ceiling stop (Single-Agent step, Sequential loop, Parallel `execute-result` routing). Extend.
  - `loomwright/agents/supervisor.md`: the completion-tail guard's `**Thrash-escalation exception:**` list. Extend (keep the abort for every other error).
  - `loomwright/agents/execute-manager.md`: the poll-loop no-retry rule. Extend.
  - `loomwright/skills/self-heal-advisory/SKILL.md`: the `heal_fix` stop. Extend.
  - `loomwright/skills/self-heal-advisory/completion-tail.md`: steps 1-2 outcome and job-lifecycle branches (`failed/`). Extend.
  - `loomwright/skills/review-heal/SKILL.md`: the `drain_fix` `push_failed` text. Extend.
  - `finalize.md`, `supervisor-next-step.sh`, `review-heal-next-step.sh`, `test-*`, inventory and contract-parity hits: no change. They name only the refold value. `validate-supervisor-result.py` does not enumerate `error`, and this stop sends no `--result`, the same as the token-ceiling stop, so no driver arm is needed.
- **`write_status`** values: a new closed enum owned by `write-run.sh`'s header, with no sibling list. `lens_status` is a different contract and gets no change.

## Pin mutations

None of these rows are machine-applicable (the code they protect does not exist at base), so the Phase 4.5 reviewer applies each one itself.

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-resolve-routing.sh`, D2: unset `heal_fix` resolves `claude`/`default` while `worker` is routed | make `seat heal_fix` fall back to `routing.seats.worker` when its own key is absent |
| `test-resolve-routing.sh`, AC3 `write_not_granted` | delete the write-grant check in `resolve-routing.sh` (a read grant alone then routes a write seat) |
| `test-resolve-routing.sh`, write-seat ids not in `seats` | append `worker` to the `seats)` heredoc |
| `test-resolve-egress-config.sh`, `PROVIDER_WRITE_GRANTS` newline blanking | remove `strip_if_newline` from the `PROVIDER_WRITE_GRANTS` print |
| `test-setup-routing.sh`, `REFUSED (provider_not_write_usable)` | accept `usable for read-only seats` in the write-seat eligibility check |
| `test-launch-provider-cli.sh`, `.claude/settings.json` never crosses | delete the `.claude`-prefix refusal in `launch-provider-cli.sh` |
| `test-write-run.sh`, isolated-only launch | change the launch in `write-run.sh` to `launch_provider_cli shell` |
| `test-write-run.sh`, `write_git_tampered` on a provider commit | drop `head:` / `refs:` from the fingerprint comparison in `write-run.sh` |
| `test-write-run.sh`, `write_tree_dirty` | delete the pre-launch `git status --porcelain` check in `write-run.sh` |
| `test-write-run.sh`, `write_not_granted` | delete the `PROVIDER_WRITE_GRANTS` check in `write-run.sh` |
| `test-write-run.sh`, common-dir hook removed after `write_git_tampered` | delete the hooks-snapshot restore in `write-run.sh` |
| `test-write-run.sh`, partial edits restored on `write_timeout` | delete the post-launch tree restore in `write-run.sh` |
| `test-write-run.sh`, sibling-branch commit during launch stays `ok` | make `write-run.sh` call the fingerprint with refs scope `all` instead of `own` |
| prose pin (Phase 4.5 reviewer): the completion-tail guard exempts `write_seat_tampered` | remove `write_seat_tampered` from the `**Thrash-escalation exception:**` in `agents/supervisor.md` (a worker-side tamper then aborts as an invariant violation) |
| prose pin (Phase 4.5 reviewer): a `write_seat_tampered` run's brief goes to `failed/` | delete the `write_seat_tampered` branch from `completion-tail.md` step 2 (the run then falls to loop-skipped → `done/`, read as success) |
| prose pin (Phase 4.5 reviewer): `heal_fix` tamper result has `heal_decision: ESCALATED` | change AC10's `heal_fix` tamper result in `skills/self-heal-advisory/SKILL.md` to `heal_decision: null` (`validate-supervisor-result.py` rule 7 then rejects the block) |
| `test-write-run.sh`, hung CLI ends `write_timeout` with tree restored | remove the clamp-to-480 and pass the raw `LOOMWRIGHT_WRITE_CLI_TIMEOUT` value through in `write-run.sh` |
| `test-write-run.sh`, `--restore` leaves a clean tree | delete the untracked-file clean step of the restore in `write-run.sh` |
| `test-write-run.sh`, `write_repo_settings_present` | delete the `.claude/settings*.json` pre-launch check in `write-run.sh` |
| `test-resolve-routing.sh`, AC3 write grant without read grant prints `provider_not_granted` | skip the `repos.<slug>.providers` read-grant check for write seats in `resolve-routing.sh` (a write grant alone then routes) |
| `test-resolve-routing.sh`, AC1 write-seat precedence `--route` > `routing.seats.<seat>` > default | make `seat <write-seat>` read `routing.seats.<seat>` before `--route` |
| `test-setup-routing.sh`, `--grant-write` never writes a seat | make `--grant-write <seat>=<p>` also write `routing.seats.<seat>` |
| `test-setup-routing.sh`, a seat write never writes a write grant | make `--seat <write-seat>=<p>` also write `repos.<slug>.write_grants.<seat>` |
| `test-setup-routing.sh`, `remove` deletes this repo's `write_grants` | drop the `write_grants` deletion from `remove` in `setup-routing.sh` |
| `test-launch-provider-cli.sh`, AC5 sibling declared login file still crosses | widen the `.claude`-prefix refusal in `launch-provider-cli.sh` to refuse every `PROVIDER_LOGIN_FILES` entry |
| `test-write-run.sh`, `provider_unavailable` | delete the provider-availability pre-launch check in `write-run.sh` |
| `test-write-run.sh`, `provider_not_granted` | delete the `PROVIDER_GRANTS` read-grant check in `write-run.sh` |
| `test-write-run.sh`, `write_unpinnable` | make `write-run.sh` fall back to `provider_argv` when `provider_write_argv` is undefined |
| `test-write-run.sh`, `write_claude_is_task_path` | delete the provider-`claude` refusal in `write-run.sh` |
| `test-write-run.sh`, `--restore` refused when HEAD moved | delete the HEAD-equals-pre-launch-sha check from `--restore` in `write-run.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Write-seat config, per-seat write grant and config-time eligibility | AC1, AC2, AC3, AC4, AC12 (tests pass) | 7 modify, 0 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Isolated write runner, launcher `.claude/` guard, shared git fingerprint, Grok write argv | AC5, AC6, AC7, AC8, AC12 (tests pass) | 4 modify, 3 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | BLOCKED (by #1) |
| 3 | Wire the three seats into their spawn sites; contract docs, inventory, release fragment + `bash scripts/bump-version.sh` (last step) | AC9, AC10, AC11, AC12 | 16 modify (incl. the bump's `CHANGELOG.md` and both manifests), 1 create (folded and deleted by the bump) | `skills/async-orchestration/SKILL.md`, `skills/self-heal-advisory/SKILL.md`, `skills/review-heal/SKILL.md` | BLOCKED (by #2) |

### File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| 1 config/consent | `loomwright/scripts/resolve-routing.sh` (345), `loomwright/scripts/resolve-egress-config.sh` (277), `loomwright/scripts/setup-routing.sh` (594: appended, the single writer of routing and grants), `loomwright/scripts/test-resolve-routing.sh` (325), `loomwright/scripts/test-resolve-egress-config.sh` (432), `loomwright/scripts/test-setup-routing.sh` (534: appended, the one test of that writer), `loomwright/docs/command-parts/setup/providers.md` (31) | — | HIGH |
| 2 runner | `loomwright/scripts/adapters/providers/launch-provider-cli.sh` (314), `loomwright/scripts/adapters/providers/test-launch-provider-cli.sh` (449), `loomwright/scripts/adapters/providers/lens-run.sh` (597: shrinks, the fingerprint moves out), `loomwright/scripts/adapters/providers/provider-grok.sh` (131) | `loomwright/scripts/adapters/providers/write-run.sh` (new runner: a separate concern from the read-only lens), `loomwright/scripts/adapters/providers/test-write-run.sh`, `loomwright/scripts/adapters/providers/git-integrity-lib.sh` (extract `git_integrity_fingerprint` from `lens-run.sh`, so `write-run.sh` never holds a second copy) | HIGH |
| 3 wiring/docs | `loomwright/skills/async-orchestration/SKILL.md` (424), `loomwright/agents/execute-manager.md` (740: a pointer at Step 3 plus the poll-loop `write_seat_tampered` no-retry rule; the paragraph's home is async-orchestration), `loomwright/agents/supervisor.md` (651: the `write_seat_tampered` stop beside the existing token-ceiling stop, its single home), `loomwright/skills/self-heal-advisory/SKILL.md` (417), `loomwright/skills/self-heal-advisory/escalation.md` (55), `loomwright/skills/self-heal-advisory/completion-tail.md` (520: one branch added to steps 1-2, the job lifecycle's single home), `loomwright/skills/review-heal/SKILL.md` (574: one Seat routing paragraph beside the existing drain_reviewer one, its home by the seat pattern), `loomwright/docs/PROVIDER_ROUTING.md` (129), `loomwright/docs/FAILURE_ESCALATION.md` (430), `loomwright/docs/result-schemas/supervisor-result.md` (230), `loomwright/docs/loop-inventory/supervisor.md` (1306: rows appended, the inventory's one table), `loomwright/docs/loop-inventory/review-heal.md` (419), `loomwright/docs/prompt-token-budgets.json` (only if a ceiling is breached, with its `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1051: one mirror row, no new responsibility) mirror row), and the release fold by `bash scripts/bump-version.sh`: `CHANGELOG.md` (840: edited by the fold only), `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (never hand-edited) | `changelog.d/provider-routing-write-seats.md` (deleted again by the fold) | MEDIUM (the exact budget/inventory touches depend on final wording) |

> **Validator-owned surfaces:** `scripts/check-token-budget.sh` (the skills, agents and `setup` command parts touched above), `loomwright/scripts/test-loop-inventory.sh` (supervisor and review-heal sources), `scripts/check-prompt-history-refs.sh` (no new history refs in prompts: the probe story goes to the changelog fragment, not the skills), `scripts/check-doc-currency.sh`, `loomwright/scripts/test-citation-drift.sh` (no bare `file:N` in committed prose).

### Subtask Contracts

```yaml
# Subtask 1 — write-seat config, write grant, config-time eligibility (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/resolve-routing.sh", name: "write-seats"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-routing.sh", name: "write_not_granted"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-egress-config.sh", name: "PROVIDER_WRITE_GRANTS"}
  - {kind: "symbol", path: "loomwright/scripts/setup-routing.sh", name: "--grant-write"}
  - {kind: "symbol", path: "loomwright/scripts/setup-routing.sh", name: "provider_not_write_usable"}
  - {kind: "symbol", path: "loomwright/docs/command-parts/setup/providers.md", name: "provider_not_write_usable"}
  - {kind: "symbol", path: "loomwright/scripts/test-resolve-routing.sh", name: "write_not_granted"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-routing.sh", name: "provider_not_write_usable"}
  - {kind: "symbol", path: "loomwright/scripts/test-resolve-egress-config.sh", name: "PROVIDER_WRITE_GRANTS"}
requires: []
lanes:
  - "loomwright/scripts/resolve-routing.sh"
  - "loomwright/scripts/resolve-egress-config.sh"
  - "loomwright/scripts/setup-routing.sh"
  - "loomwright/scripts/test-resolve-routing.sh"
  - "loomwright/scripts/test-resolve-egress-config.sh"
  - "loomwright/scripts/test-setup-routing.sh"
  - "loomwright/docs/command-parts/setup/providers.md"
external_requires:
  - "jq (already required by resolve-routing.sh / setup-routing.sh)"

# Subtask 2 — isolated write runner, launcher guard, shared fingerprint, Grok write argv (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/scripts/adapters/providers/write-run.sh"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/write-run.sh", name: "write_git_tampered"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/write-run.sh", name: "write_repo_settings_present"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/write-run.sh", name: "tree_restored"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/write-run.sh", name: "--restore"}
  - {kind: "file", path: "loomwright/scripts/adapters/providers/test-write-run.sh"}
  - {kind: "file", path: "loomwright/scripts/adapters/providers/git-integrity-lib.sh"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/git-integrity-lib.sh", name: "git_integrity_fingerprint"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/lens-run.sh", name: "git-integrity-lib.sh"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/provider-grok.sh", name: "provider_write_argv"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/test-launch-provider-cli.sh", name: ".claude/settings.json"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/resolve-egress-config.sh", name: "PROVIDER_WRITE_GRANTS"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/resolve-routing.sh", name: "write-seats"}
lanes:
  - "loomwright/scripts/adapters/providers/write-run.sh"
  - "loomwright/scripts/adapters/providers/test-write-run.sh"
  - "loomwright/scripts/adapters/providers/git-integrity-lib.sh"
  - "loomwright/scripts/adapters/providers/launch-provider-cli.sh"
  - "loomwright/scripts/adapters/providers/test-launch-provider-cli.sh"
  - "loomwright/scripts/adapters/providers/lens-run.sh"
  - "loomwright/scripts/adapters/providers/provider-grok.sh"
external_requires:
  - "Grok Build CLI permission rule names (vendor permissions doc); tests stub the CLI and need no live provider"

# Subtask 3 — wire seats into spawn sites; contract docs, inventory, release fragment (BLOCKED by #2)
provides:
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "Seat routing (`worker`)"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "Seat routing (`heal_fix`)"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "Seat routing (`drain_fix`)"}
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "write-run.sh"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/escalation.md", name: "write_status"}
  - {kind: "symbol", path: "loomwright/docs/PROVIDER_ROUTING.md", name: "## Write seats"}
  - {kind: "symbol", path: "loomwright/docs/FAILURE_ESCALATION.md", name: "write_seat_failed"}
  - {kind: "symbol", path: "loomwright/docs/FAILURE_ESCALATION.md", name: "write_seat_tampered"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/supervisor-result.md", name: "write_seat_tampered"}
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "write_seat_tampered"}
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "write_seat_tampered"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/completion-tail.md", name: "write_seat_tampered"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/supervisor.md", name: "Seat routing (`worker`)"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/review-heal.md", name: "Seat routing (`drain_fix`)"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "Provider routing for write seats"}  # the fragment is folded and deleted by bump-version.sh in this subtask, so the folded entry is named
requires:
  - {from: "2", kind: "file", path: "loomwright/scripts/adapters/providers/write-run.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/resolve-routing.sh", name: "write-seats"}
lanes:
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/self-heal-advisory/escalation.md"
  - "loomwright/skills/self-heal-advisory/completion-tail.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/docs/PROVIDER_ROUTING.md"
  - "loomwright/docs/FAILURE_ESCALATION.md"
  - "loomwright/docs/result-schemas/supervisor-result.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
  - "loomwright/docs/loop-inventory/review-heal.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/provider-routing-write-seats.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
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
| Subtask 1 | Subtask 2 | none (2 reads 1's `PROVIDER_WRITE_GRANTS` / `write-seats`) | YES (requires) |
| Subtask 2 | Subtask 3 | none (3 names 2's `write-run.sh`) | YES (requires) |
| Subtask 1 | Subtask 3 | none (3's `PROVIDER_ROUTING.md` documents 1's reasons; `test-resolve-routing.sh` Group 9 pins that doc, which is why 3 runs after 1) | YES (transitive) |

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
| 2 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 3 | `skills/async-orchestration/SKILL.md`, `skills/self-heal-advisory/SKILL.md`, `skills/review-heal/SKILL.md` |

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

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5) — first non-Claude writer: a prompt-injected or misbehaving provider edits outside the task, or edits `.git` | HIGH | The pin is an allow-list with no shell tool. `write-run.sh` refuses a dirty tree before launch and fails `write_git_tampered` on any HEAD, refs, remotes, config or hooks change. The disk gate, `out_of_lane`, tests/lint and Phase 4.5 still decide. Honest limit, stated in `PROVIDER_ROUTING.md`: the launcher is not a sandbox (writes outside the worktree and network egress are not blocked), which is why consent is per seat, per provider, in user scope |
| A provider plants a hook or `core.hooksPath` in the shared `.git` (a linked worktree shares the common config and hooks; the project root is the repo itself) | HIGH | `write_git_tampered` restores the config and hooks snapshot, then stops the whole run or heal loop: no retry, no further spawns, no Claude fallback (AC6/AC9/AC10). Honest window: on the Parallel Path, sibling workers that are already running may run git with a planted hook until write-run's restore returns. Pinned by the common-dir hook case in `test-write-run.sh` |
| Repo-side `.claude/settings.local.json` / `.claude/settings.json` `permissions` in the write cwd might widen Grok's pin. Unverified: the 2026-10-31 probe tested only a repo `settings.json` with `defaultMode` | MEDIUM | write-run refuses (`write_repo_settings_present`) before launch. Local consequence, verified at base: this checkout's root holds a gitignored (`.gitignore` `.claude/*`) `.claude/settings.local.json` with a `permissions` key, so a routed worker on the Single-Agent Path refuses here until the owner moves that file. The check is on file existence, not git status. A fresh linked worktree has no such file and is unaffected. A later probe showing Grok ignores repo-level settings can relax this |
| Real-HOME launch is fail-OPEN for Grok (`defaultMode: "auto"` in `~/.claude/settings.json` overrides `dontAsk`) | HIGH | `write-run.sh` takes no home-mode argument and calls only `launch_provider_cli isolated`, pinned by test. The launcher refuses every `.claude/`-prefixed login file, pinned by the AC5 regression test |
| Feasibility (Phase 2.5) — scope is about 25 files over three layers | MEDIUM | Split context-bound into 3 serial subtasks with disjoint lanes. Each worker runs `bash scripts/ci-local.sh --affected` before hand-back |
| Grok allow-rule tool names beyond `Write`/`Edit` are unverified on this machine | MEDIUM | AC8: cite each name's source in `provider-grok.sh`, otherwise leave it out. A wrong name makes the provider edit nothing, so `outputs_verified` fails closed. It cannot widen access |
| `skills/async-orchestration/SKILL.md` has only 537 tokens of headroom | MEDIUM | Keep the `worker` paragraph a pointer to `PROVIDER_ROUTING.md` §"Write seats". If it still breaches, raise the ceiling in the same change with its mirror row (`raise_rule`) |
| D1 broken by a per-subtask fallback | MEDIUM | AC9: resolve once at Phase 3 entry and pass the provider to every spawn. A mid-run failure goes through the Worker Failure path only |
| The edit-step routing keeps a Claude task in the loop (Claude still spends tokens on the wrapper) | LOW | Deliberate: it keeps the `WORKER_RESULT` contract, hooks and commit flow unchanged. A conductor-side runner that drops the wrapper is a later item if cost data warrants it |
| A drain stopped by a `drain_fix` write failure reports `termination_reason: push_failed`, a misnomer | LOW | The reason text carries `write_seat_failed:<write_status>`. A dedicated driver reason is a follow-up, kept out of this item to avoid changing the 1110-line driver and its golden fixtures |
| Driver scripts (`supervisor-next-step.sh`, `review-heal-next-step.sh`) keep emitting a plain worker or fix spawn | LOW | Intended: routing happens in the spawned task's prose, like the read seats. The drivers' golden fixtures are untouched |
| A new `PROVIDER_WRITE_GRANTS` key line reaches the other egress consumers | LOW | They parse KEY=VALUE by name, as when `PROVIDER_GRANTS` was added. The `--affected` run covers their tests |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-01-provider-routing-write-seats.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-01T09:11:46Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/770
- **Branch:** feature/provider-routing-write-seats
- **Files changed:** 37
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Write seats (worker, heal_fix, drain_fix) route their edit step through the new isolated-only write-run.sh to a granted, write-usable provider (per-seat write grant, provider_not_write_usable at config time, launcher .claude guard, shared git-integrity-lib, Grok provider_write_argv), wired into all spawn paths with the write_seat_tampered stop; release v17.24.0. Phase 4.5 ran 3/3 iterations (5 HIGH/BLOCKING security findings fixed across d7618fa, 54ab1b2, 4d57396); the final BLOCKING fix (newline-path deletion in the restore) was not re-reviewed. 7 MEDIUM/LOW findings dismissed below the HIGH floor (PR comment). Driver plan parse artifact ('Group' subtask from the File Impact Map table) corrected by hand — follow-up needed in supervisor-next-step.sh sn_brief_subtasks.

## Not verified
- **docs/PROVIDER_ROUTING.md seat-worker sentence** — stale after subtask 1; fixed in subtask 3 (subtask 1)
- **/setup providers interactive AskUserQuestion flow** — prose-only command part (subtask 1)
- **live Grok write launch with provider_write_argv** — tests stub the CLI; Read/Grep/Glob allow names from the vendor guide, not probed (subtask 2)
- **provider editing a tracked hook under a pre-set core.hooksPath** — scratch repro blocked by the test-integrity guard; code reading only (subtask 2)
- **repo-level .grok/config.toml allow rules in the worktree** — vendor guide says project rules merge; not refused or probed (subtask 2)
- **live routed worker / heal_fix / drain_fix run end to end** — no live provider; result shapes validated only (subtask 3)
- **agents/worker.md consumer of the Write seat spawn line** — not in any lane (subtask 3)
- **driver handling of the new stops** — no driver change by design; not exercised against the drivers (subtask 3)
