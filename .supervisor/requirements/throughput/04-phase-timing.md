# 04 — Phase timing: per-phase wall-clock and machine-vs-owner time, derived from the log

## Status: parked — superseded by `.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md` (owner decision 2026-10-09: implementation-quality/01 + throughput/01–09 merged into ONE item / ONE PR; this file is kept as that file's Part source)

## Depends on
../implementation-quality/01-prevent-findings-at-write-time.md

## Touches
loomwright/scripts/phase-timing.sh
loomwright/scripts/test-phase-timing.sh
loomwright/scripts/fixtures/phase-timing/
loomwright/scripts/emit-lifecycle.sh
loomwright/scripts/test-emit-lifecycle.sh
loomwright/scripts/hook-dispatch-on-pr-create.sh
loomwright/scripts/test-hook-dispatch-on-pr-create.sh
loomwright/scripts/automate-dismissed.sh
loomwright/scripts/test-automate-dismissed.sh
loomwright/scripts/automate-trail.sh
loomwright/scripts/test-automate-trail.sh
loomwright/scripts/build-insights.sh
loomwright/scripts/test-insights.sh
loomwright/commands/insights.md
loomwright/hooks/hooks.json
loomwright/docs/HOOKS.md
loomwright/docs/result-schemas/session-end-jsonl.md
loomwright/docs/result-schemas/agent-lifecycle-jsonl.md
loomwright/docs/result-schemas/automate-run.md
loomwright/skills/automate-loop/SKILL.md
loomwright/docs/vendor-coupling-manifest.json
scripts/ci-local.sh
scripts/test-ci-local.sh
changelog.d/throughput-04-phase-timing.md

## Problem
Nobody can say where an `/automate` item's time went without hand work. Finding out where PR #435's 5 h 12 m went (run `.supervisor/automate/automate-2026-10-08-121222.md`, session log `.supervisor/logs/auto-2026-10-08-123152.jsonl`) meant hand-joining subagent transcripts, ci-slot run logs and `gh run list`. Nothing can answer the red-team's first question, which is how much of an item is machine time and how much is waiting on the owner.

What the log has today (verified 2026-10-09):

- **The session log** (95 lines) has `agent_lifecycle` ×84, `token_ledger` ×6, `subtask_complete` ×3, and one each of `autonomous_start` and `session_end`. It has **no `phase_transition` event**. Across all of `.supervisor/logs/*.jsonl`, `phase_transition` appears in only 4 logs, and the last is from 2026-06-13. That is by design. `loomwright/scripts/emit-progress-event.sh`'s header ("WHY THIS EXISTS") measured 785 hook-written `token_ledger` events against 6 agent-written `phase_transition` events. `skills/state-management/SKILL.md` §"Session Logging" retired prompt-written progress events for that reason. **This item must not bring back a prompt-written phase event.**
- **`session_end` has no duration field.** None of the 116 `session_end` records in the corpus carries `duration_seconds`, but `build-insights.sh` (its §1 `jq` record collector) reads `.duration_seconds // null` and renders it when present. It is a reader slot nothing writes. `session_end` is appended by the Supervisor model at the Phase 4.5 completion tail (`skills/self-heal-advisory/SKILL.md` §"Hard-signal dual emission"; there is no helper script). A duration added there would be a model-computed number with the same miss rate as `phase_transition`.
- **Part of the session is in the wrong file.** Events before `autonomous_start` go to the Claude Code UUID log `.supervisor/logs/33e9ed8c-64ae-4ee8-8563-8468e749516f.jsonl` (138 lines), not to the `auto-…` log, because the plugin session id does not exist yet. That includes Launch Pad's plan-reviewer spans (12:12:59Z–12:21:02Z) and the owner question at 12:21:08Z. The run file's `run created (session <uuid>)` line and the `auto-2026-10-08-123152.owner` sidecar (`cc_session_id=`) are the join keys. No reader uses them.
- **The `## Progress` lines are timestamped at the automate boundaries**: `picked` 12:12:45Z, `ran /autonomous → PR` 14:15:29Z, `owned drain started` 14:15:58Z, `drain READY` 14:17:25Z, `owned drain started (fix-now re-drain…)` 15:08:30Z, `fix-now re-drain READY` 16:41:29Z, `parked awaiting_merge` 17:24:50Z. The exceptions are the `dismissed: <decision> …` lines. `automate-dismissed.sh` (the `progress-append … "dismissed: $decision $name — $snippet"` call) writes them **without a timestamp**, so the moment the owner answered is not recorded.
- **When the owner was asked is recorded; when the owner answered is not.** `PreToolUse[AskUserQuestion]` and `Notification[permission_prompt]` write `agent_lifecycle` `state: waiting` rows (orca-derived/01, done, PR #231). Nothing fires on the answer: `hooks.json` has no `PostToolUse[AskUserQuestion]` leaf. The only proxy is the next debounced `working` heartbeat (`LOOMWRIGHT_LIFECYCLE_HEARTBEAT_DEBOUNCE`, default 60 s, `emit-lifecycle.sh` header), which is an upper bound, not a fact.
- **PR creation time is not in the log.** The PR was created at 13:22:00Z (`gh pr view 435 --json createdAt`), so FINALIZE ran *before* Phase 4.5 (first reviewer at 13:23:02Z). A reader cannot place that boundary from local data. The `gh pr create` `PostToolUse[Bash]` hook (`hook-dispatch-on-pr-create.sh`) already fires on it but logs no event.
- **`/insights` computes no wall-clock.** `commands/insights.md`, `build-insights.sh` and `build-loop-evidence.sh` aggregate counts and decisions only.
- **ci-local runs cannot be attributed by time window.** Run logs in `~/.local/state/loomwright/ci-slots/<repo-key>/runs/` are named `<tree>-<origin/main>-<OS>-<ts>-<pid>.log` (`ci-local.sh` `content_key()` / `open_log()`). They are shared by every session and checkout, and only the newest 20 are kept. In #435's window (base `9a65ecb`) there are 10 full runs. Seven match a #435 commit tree. **One (`5bdf5a4…`, 14:26Z) is PR #438's commit `0cdf464`'s tree.** Two (`3e7bc89…` 14:29Z, `96b9fcf…` 15:31Z, both FAIL) match no commit tree, because they ran on uncommitted working trees. The log header names only the key, with no HEAD and no branch, so tree matching alone cannot attribute those two.

What the existing rows already reconstruct (the replay this item must automate; derived by hand on 2026-10-09):

| Span | Wall | Machine / owner | Source |
|---|---|---|---|
| pick → `autonomous_start` | 19 m 07 s | ≈ 8 m Launch Pad + plan review (12:12:59–12:21:02) · ≈ 10 m owner (asked 12:21:08, next `working` 12:31:13) | run file + **UUID log** |
| worker | 12:33:25 → 13:20:37 | machine (one validator-rejected stop at 13:19:44) | `agent_lifecycle` / `subtask_complete` |
| PR created | 13:22:00 | — | `gh` only (not in the log) |
| Phase 4.5 reviewer iterations | 13:23:02–13:31:07 · 14:01:15–14:07:54 · 14:10:09–14:13:23 | machine | `agent_lifecycle` rows, code-reviewer `agent_id`s |
| pick → drain READY | **2 h 04 m 40 s** | — | run file |
| post-READY (READY → park) | **3 h 07 m 25 s** | ≈ 2 m owner (asks 14:18:33 / 14:19:23 → 14:20:46) · fix-now fix pass 14:21:49–15:07:53 (machine) · **re-drain 15:08:30 → 16:41:29 (1 h 32 m 59 s)** · ≈ 43 m owner (asked 16:41:41, next `working` 17:24:51) | run file + lifecycle rows |
| park → merge | 6 h 38 m | owner (outside the 5 h 12 m) | `gh` `mergedAt` 00:02:40Z |

So about 55 m of the 5 h 12 m pick→park was owner wait. That figure is only estimable today, and only from heartbeat upper bounds. The 51 m between READY and the re-drain start, which looks like owner time in the run file, was almost all machine time (the fix-now fix pass). The evidence brief (`00-overview.md`) says the third Phase 4.5 iteration took "~11 m". The lifecycle rows show 14:07:54 → 14:13:23 (≈ 5.5 m, including its 32 s fix pass). That discrepancy is the kind this item removes.

## Goal
For any Supervisor run and any `/automate` item, a script answers from local logs alone: how long each phase took, and how much of the item was machine time versus waiting on the owner. `/insights` shows it. A timestamp that was never recorded reads as `null` (unknown), never as 0, and nothing in the pipeline is a model-computed duration.

## Scope
1. **One derivation, one reader script: `loomwright/scripts/phase-timing.sh` (NEW).** Read-only and fail-SAFE (exit 0; unreadable input ⇒ `null` fields plus one stderr note). Input is a run file (`--run <runfile>`) or a session id (`--session <id>`). Output is one JSON record per item or session. Build on orca-derived/01's lifecycle ledger; do not add a parallel clock or any new heartbeat.
   - **Join:** the plugin session log plus the Claude Code UUID log, keyed by `cc_session_id` (rows), the run file's `run created (session <uuid>)` and `session_id <id>` lines, and the `<session>.owner` sidecar.
   - **Supervisor spans:** plan (first plan-reviewer `working` → last plan-reviewer `ended`, when present), execute (first worker `working` → last non-rejected worker `subtask_complete`), finalize (→ `pr_created`, item 3c), Phase 4.5 per iteration (one span per code-reviewer `agent_id`, from its first `working` to its `ended`, plus the fix pass between iterations), and completion (→ `session_end.ts`).
   - **Ordering:** phases are ordered by their timestamps, never assumed. #435 ran FINALIZE before Phase 4.5.
   - **Automate per-item spans** come from the `## Progress` timestamps: pick→`autonomous_start`, `/autonomous`, each owned drain (start → READY/ESCALATED), each fix-now pass, and READY→park.
   - **Missing endpoints:** a span with a missing endpoint is `null`. A run that reports an `owned_drain_result` value outside today's enum (see Scope 4) closes the drain span at that line's ts, or leaves it `null`. It is never guessed.
2. **Owner-wait intervals.** `asked` is the `waiting` row's ts (`reason: ask_user`; `permission_prompt` counts only when no `ask_user` row is within the debounce window, so one question is not counted twice). `answered` is the new row in 3a. Each interval carries `exact: true` when `answered` came from 3a. On logs written before this item, `answered` falls back to the next main-scope `working` row with `exact: false` (an upper bound). Owner time is the sum of intervals; machine time is wall time minus owner time. Each is `null` when its inputs are missing, never 0.
3. **The minimum new emission points.** These are hook-written or script-written, fail-SAFE (exit 0, `|| true` per `CLAUDE.md` §"Plugin Hooks"), and never invent a value.
   - **3a.** Add a `PostToolUse[AskUserQuestion]` leaf → `emit-lifecycle.sh answered`. It writes `agent_lifecycle` `state: working`, `reason: answered`, and the payload's tool-use id, so it pairs with the `PreToolUse` `waiting` row. It bypasses the heartbeat debounce. **Probe first:** record one real `PostToolUse[AskUserQuestion]` payload (key set, whether a tool-use id is present in both Pre and Post) in this file before writing the emitter, using the recipe in `~/.claude/CLAUDE.md` (a temporary hook in `.claude/settings.local.json`). If no shared id exists, pair by order and say so.
   - **3b.** `automate-dismissed.sh` writes its `dismissed:` Progress line with the same leading `<ts>` every other Progress line carries. That ts is the moment the decision was recorded.
   - **3c.** `hook-dispatch-on-pr-create.sh` appends one `pr_created` event (`ts`, PR URL) to the session log it already resolves. It records the PR only and never changes the dispatch gate.
   - **3d.** `scripts/ci-local.sh` writes `HEAD` sha and branch as one additive header line in each run log. This lets a run on an uncommitted tree be attributed by HEAD, not by time.
4. **Schemas, additive only (`schema_version` unchanged).** Follow the rule in `docs/result-schemas/schema-versioning.md` (rule 3) and the additive-field precedent in `session-end-jsonl.md` (`reason`, `plugin_version`, `knowledge_sources_used`).
   - **Persisted record.** The automate per-item summary is persisted as ONE script-written `item_timing` JSONL event that `automate-trail.sh closeout` appends by calling `phase-timing.sh --run` (fail-SAFE). Document it in `session-end-jsonl.md` as a "related additive session-log event", the way `token_ledger` is noted there.
   - **`session_end` gets no model-written duration.** `build-insights.sh` attaches the derived spans to its in-memory `session_end` record and stops reading the dead `duration_seconds` slot, or feeds that slot from the derivation. Say which.
   - **Closed enums.** `agent_lifecycle`'s `reason: answered` on a `working` row is additive (`working` carries no reason vocabulary today). `state` is NOT extended. This item adds **no** `pause_reason` or `owned_drain_result` value. If implementation finds it needs one, the brief carries a `## Closed enumerations touched` section (per `automate-followups/27`), and the value lands together with `automate-followups/20`.
   - **Relation to `automate-followups/20`.** AF/20 proposes `owned_drain_result: superseded_by_merge`. Its second proposal, `awaiting_go`, is already in the `pause_reason` enum (`automate-run.md`, written only by `closeout`, since commit `4bf97cc`). The timing reader must close a drain span on `superseded_by_merge` if AF/20 lands first.
   - **Relation to `automate-followups/27`.** AF/27 is the brief rule that makes "which closed lists does this new value belong to" a required section. This item follows that rule. Both AF items are pending, with no hard dependency. AF/20 also edits `automate-trail.sh` / `automate-run.md`, so run them sequentially, never in one wave (the shared Touches already prevent co-scheduling).
5. **`/insights` (`build-insights.sh`, `commands/insights.md`)** gets a `## Wall-clock (phases · machine vs owner)` section:
   - per-phase medians and the latest run's spans;
   - for each automate item, pick→park, owner time, machine time, and the share of owner time that is `exact`;
   - a `null` span renders as "not recorded", never 0.
6. **ci-local time line per item.** `phase-timing.sh --run` lists the item's ci-local runs, each with start, wall seconds and verdict.
   - **Attribution** is by tree key only: the log's `<tree>` matches a commit tree on the item's branch (`git log --format=%T <base>..<head>`), or 3d's HEAD is on that branch. It is **never by time window**, because a PR #438 run sat inside PR #435's window.
   - **Unattributable runs** are counted as `unattributed`, not dropped and not guessed.
   - **Pruned logs:** only 20 logs are kept, so `closeout`'s `item_timing` captures the list at merge time. Runs pruned before that make the list `null` (incomplete), not empty.
7. **Not folded in:** `proposed/insights-stranded-closeouts-counted-as-failed.md`. It is the same surface (`build-insights.sh`'s `session_end` collector) but a different defect, status classification. It stays a separate proposal. This item must not make it worse: the derivation gives a `close-stranded-run.sh` synthetic `session_end` (`reason: session_ended_without_completion`) `null` spans, never a session duration ending at the close-out.

## Acceptance criteria
- **Replay (headline).** `phase-timing.sh --run .supervisor/automate/automate-2026-10-08-121222.md`, over `auto-2026-10-08-123152.jsonl` and the UUID log `33e9ed8c-….jsonl`, reproduces each of these within one minute:
  - pick → drain READY: 2 h 04 m 40 s
  - post-READY (READY → park): 3 h 07 m 25 s
  - fix-now re-drain: 15:08:30 → 16:41:29
  - pick → `autonomous_start`: 19 m 07 s, split into plan review ≈ 8 m and owner ≈ 10 m (`exact: false`)
  - the three Phase 4.5 reviewer spans in the table above
  - the two post-READY owner waits (≈ 2 m, ≈ 43 m, `exact: false`)

  Paste the record in the PR body. Copy these logs, trimmed to the rows the derivation reads, into `loomwright/scripts/fixtures/phase-timing/` (NEW directory; the source logs are gitignored on disk), so the replay is a committed test in `test-phase-timing.sh` (NEW). The fixtures sit under the `core`-classed `loomwright/scripts/*` glob, so run the vendor-coupling gate on them too.
- **Owner-wait fixture.** With a `waiting` row plus a 3a `answered` row, owner time is exact and `exact: true`. With no `answered` row, it falls back with `exact: false`. With no `waiting` row, owner time is `0` only when the log provably spans the item and contains no ask; otherwise it is `null`.
- **Mutation controls.** Each must turn a test red:
  - delete the `cc_session_id` join (the 19-minute split must go red);
  - make a missing endpoint yield 0 instead of `null`;
  - attribute ci-local runs by time window (the `5bdf5a4…` #438 run must not appear in #435's list).
- **Emitter tests.** 3a, 3b, 3c and 3d each have a test, and each emitter exits 0 on an empty or malformed payload. 3b's ts line passes `test-automate-dismissed.sh` with its count assertions updated, not removed. The `hooks.json` leaf for 3a carries `|| true`, and the `docs/HOOKS.md` hook table gains its row.
- **Vendor-coupling ratchet.** `emit-lifecycle.sh` / `hook-dispatch-on-pr-create.sh` are `core`. Remove any new hook-protocol token before raising an allowance. A raise carries an added `allowance_reasons` entry (`scripts/check-vendor-coupling.sh` header, "TO RAISE AN ALLOWANCE").
- **`/insights`.** A fixture corpus shows the wall-clock section, and `null` spans render as "not recorded".
- **No model-computed number.** `grep` the diff: no agent or skill prose instructs a model to compute or write a duration.

## Validation (must pass before merge)
1. `bash scripts/ci-local.sh` green (the full run).
2. New tests fail on the base commit and pass on the branch: `test-phase-timing.sh`, the 3a–3d emitter legs, and the insights leg.
3. The replay record above, pasted in the PR body, with each known span's delta (must be ≤ 60 s).
4. **Running system** (operator follow-up after merge, not a merge gate): the next real `/automate` item's `item_timing` line, showing `exact: true` owner intervals.

## Non-goals
- **Reintroducing `phase_transition`** or any prompt-written progress event. The derivation reads hook- and script-written rows only (see Problem).
- **Changing gates, `heal_decision`, the drain, or the dismissed-findings decision itself.** This item measures and decides nothing.
- **The stranded-close-out bucketing** (`proposed/insights-stranded-closeouts-counted-as-failed.md`). Not folded in; see Scope 7.
- **GitHub CI wall-clock per push** (`gh run list` timings). This is local-log-only, consistent with `/insights`' "no data leaves your machine". A later item may add it.
- **The output-token source.** This is separate, and not about timing. Session 33e9ed8c's 15 subagent transcripts hold 398 assistant message ids. **356 of them (89%) carry only the stream-start placeholder `output_tokens`, with no final `stop_reason` line.** So the F8 limit in `loomwright/docs/TELEMETRY.md` §"Transcript usage" ("output tokens of a message whose final line is absent … are UNDER-counted", described there as "common in older transcripts") is the **common** case in current transcripts, not an edge case. This needs its own follow-up on where output tokens come from. Pointer only; not scoped here.
