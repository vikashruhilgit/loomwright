# 00 — Six-phase-loop gaps overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp is the ONLY thing `resolve-folder` honours, so it is what keeps `/automate` from enqueuing this file)

**Origin:** 2026-09-21 owner asked whether https://ship-it-with.ai/chapter-5-six-phase-loop/ (Research → Plan →
Execute → Review → Verify → Ship) has anything Loomwright lacks. The comparison was done against the actual files,
not from memory. Verdict: the six-phase skeleton is already covered and Loomwright is stricter in most places
(Plan Reviewer gate on the brief, `verify-provides.sh` re-checking `provides` on disk, Phase 1.5 PRE-FLIGHT SYNC,
mechanical pointers-not-payloads transport, `fix_cycles` as the repair-rate metric, `getByRole`-only locators in
`/verify`). Four gaps were real; two are cheap, additive, and queued here. Two are parked (see §Parked).
**Authority above this queue:** `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md` (D1–D11), `NORTH_STAR_DIRECTION.md`
§"Explicit NOs", and CLAUDE.md §"Failure-Mode Invariants". If an item and any of these disagree, the file wins.

## The two items
| Item | Delivers | Closes (verified gap) |
|---|---|---|
| 01 worker-deviations | optional additive `deviations: string[]` on `WORKER_RESULT` (validated when present, `out_of_lane` precedent) + `## deviations` heading in `.worker-summary.md` + Context-Keeper carriage into `state.md` `## Worker Results` + Phase 4.5 step 1g **DEVIATIONS ADVISORY** line into the code-reviewer prompt | `grep -i deviat loomwright/agents/worker.md` → 0 hits; `WORKER_RESULT` has no field for "where I departed from the plan / what the brief left open"; Phase 4.5 must *infer* drift from the diff, and the only per-worker narrative (`.worker-summary.md`) lives in a worktree that FINALIZE removes |
| 02 test-integrity-guard | first **blocking** `PreToolUse` hook (`Bash` + `Write\|Edit` matchers): refuse `--no-ver*` / `commit -n` / `core.hooksPath` / hook-disabling env / `git clean -x`, write-shaped Bash aimed at test-runner / lint / git-hook / Claude-settings / guard-source basenames, and `Write\|Edit` on them — **armed only by a per-session marker file** (`.supervisor/guard/<session_id>.json`, rev 4) written fail-loud at Supervisor INIT and review-heal entry, backstopped by a `PreToolUse[Agent\|Task]` leaf on write-capable loomwright spawns, pre-written by the dispatcher for the detached runner via `claude --session-id`, and removed ONLY by SessionEnd; opt-out is process-env only and never named to the model; plus the worker "rule of explanation" (record a `test:` diagnosis for a failing test — honest post-hoc capture, not proof of sequence) | `hooks.json` `PreToolUse` has exactly one matcher (`AskUserQuestion`, a notifier); the worker destructive tripwire (`result_block_parser.py` `_DESTRUCTIVE_PATTERNS`) is post-hoc at `SubagentStop` and covers `rm -rf`/`git push`/`reset --hard`/`DROP`/`TRUNCATE` only — nothing stops an agent editing the gate it is being measured by |

## Order
**01 → 02.** 02 §5 writes `test:` entries into the `deviations` field 01 defines, and both touch `agents/worker.md`
(01 adds to §"Output" / §"memory_candidates", 02 adds to step 2 "Run tests") — the Supervisor's file-overlap
check would flag them if run together. Sequential only.

## Decisions taken (owner accepted "ok do that" on 2026-09-21)
| # | Decision | Why |
|---|---|---|
| S1 | **No new agent, no new command, no schema_version bump.** 01 is an additive field + one advisory line; 02 is one hook script + one prompt line. | NORTH_STAR "No speculative new agents"; `out_of_lane` / `memory_candidates` precedent for additive `WORKER_RESULT` fields (RESULT_SCHEMAS.md §WORKER_RESULT). |
| S2 | **01 is advisory into the review lens only — never a gate, never fed to fixers as an instruction.** Same contract as `brief_conformance` (self-heal-advisory step 1f): the reviewer's response IS ordinary `category: new` findings when a recorded deviation contradicts an acceptance criterion. | CLAUDE.md "two review lenses, not four passes"; keeps `heal_decision` derivation byte-identical. |
| S3 | **02 is the plugin's FIRST fail-CLOSED `type: command` hook, so it must NOT carry `\|\| true`**, and CLAUDE.md §"Plugin Hooks" `\|\| true` convention paragraph + HOOKS.md must say so in the same PR. | CLAUDE.md §Plugin Hooks: "A future blocking gate added as a `type: command` hook must NOT carry `\|\| true` — that would silently neuter it." A guard that can't fire is the class memory `rules-violated-by-their-own-surrounding-text` names. |
| S4 | **02 is armed by ONE MARKER FILE PER SESSION — never a directory listing, never a shared slot — with a fail-loud arm, a hook backstop, a dispatcher pre-arm, and NO tool-call disarm (rev 4).** `.supervisor/guard/<session_id>.json` is written from `CLAUDE_CODE_SESSION_ID` (empty ⇒ exit 3, nothing written, run proceeds visibly `guard: unarmed`) at Supervisor INIT and review-heal loop entry; `arm` writes ONLY its own file and never overwrites or removes another session's (a forged env id makes a junk file that matches no payload); backstopped by a `PreToolUse[Agent\|Task]` leaf that arms from the payload when a namespaced write-capable loomwright agent is spawned; the detached runner is pre-armed by `dispatch-pr-review.sh` writing `<uuid>.json` and launching `claude -p --session-id <uuid>`; removed ONLY by a SessionEnd leaf (dead id ⇒ inert ⇒ pruned by a later `arm`); the hook denies only when `<payload session_id>.json` exists. `/.claude/settings*.json`, the guard's own scripts, `hooks.json`, and the marker dir are protected while armed; `git clean -x` is denied; reading the guard's source is never denied. The opt-out is `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` in Claude Code's process env — a tool call cannot change it for the running session — and the deny line never names it. **No `.supervisor/config.json` key** (rev 1; retracted). | Rev 1 gated on `in-progress/` non-empty (armed forever against the human here; inert in both drains). Rev 2/3 used one shared `armed.json`: a forged-env `arm` overwrote it with a dead id (one-command disarm), and a second session on the same checkout — recurring here — disarmed the first through the backstop. Per-session files have no overwrite rule, so neither path exists. |
| S5 | **02 is a tripwire, not a sandbox** — honest limit stated in HOOKS.md: indirection through a script file (`printf … > x.sh; bash x.sh`), a rename-then-edit, a config living inside `package.json`/`pyproject.toml`, an unlisted path, or an abbreviated flag other than `--no-ver*` are not caught. Heredoc/redirect/`sed -i`/`tee` aimed at a listed basename ARE caught (rev 2) because auto mode routes most edits through Bash. | Same honesty the destructive tripwire already carries (`result_block_parser.py`: "it is a tripwire, not a sandbox"). |
| S6 | **Not taken from the chapter:** held-out test sets and sealed-network verify (no mechanism in a plugin that does not own the runner); per-model "autonomy blocks" (turn-limit resume via SendMessage is the general fix); human-quiz-before-approve (process advice, not plugin surface); compaction keep-lists (phase-entry Reads already act as the compaction refresh, supervisor.md Phase 4 "Protocol authority"). | Scope discipline. |

## Parked (NOT queued — hypotheses, not defects)
- **Separate spec-compliance and code-quality reviewers.** The chapter (citing Anthropic's Fable 5 prompting
  guide) claims a single reviewer answering both questions blurs signal and the second anchors on the first.
  Loomwright deliberately threads `brief_conformance` INTO the one code-reviewer prompt. **No measurement either
  way** — this is an intra-plugin A/B arm for the still-empty `FABLE_PARITY_EVAL` harness (memory
  `twin-remediation-backlog` item 07), not a change to make on faith. The review-lane contract is an invariant;
  do not re-litigate it without an eval result.
- **Evidence trail in the PR body / committed research notes.** `.supervisor/*` is gitignored by design
  (`.gitignore` "loomwright /setup memory" block) and the pointers-not-payloads rule settled brief-in-PR. If wanted
  later: a `## Evidence` section appended to the FINALIZE PR body template (`async-orchestration/SKILL.md`
  §"PR Body Template") carrying `heal_decision` / `rubric_score` / `contract_conformance_status` — values already
  emitted, nothing new computed. Not queued: no defect, only a convenience.

## Follow-ups (queued nowhere yet — write an item when the first two land)
- **`review-heal` advisory carriage.** The standalone `/review-pr` drain's reviewer receives no advisory
  lines at all (`grep -c ADVISORY skills/review-heal/SKILL.md` → 0), so neither `deviations` nor
  `brief_conformance` reach it; 02 §9 is presence-scoped to stay safe there. Generalising 01 §5b's
  `fixer_deviations` list into the drain loop is one small item.
- **Probes P1–P3 in 02** answer questions the whole plugin cares about (`CLAUDE_CODE_SESSION_ID` under
  `claude -p`; `agent_type` on subagent `PreToolUse`; `settings.json` `env` → hook processes). Record them
  as fixtures, then update memory `subagentstop-payload-shape`.
- **Non-Bash command channels.** `mcp__terminal__run_in_terminal`, git MCP servers, and `Workflow` scripts
  run commands the `Bash` matcher never sees. 02 lists this as an honest limit; a third matcher on
  `run_in_terminal` reading the same `tool_input.command` is a cheap follow-up once 02 is stable.
- **`_DESTRUCTIVE_PATTERNS` parity.** 02 adds `git clean -x` to the post-hoc tripwire; a later pass should
  ask whether the rest of 02's Bash array (`--no-ver*`, `core.hooksPath=`, `GIT_CONFIG_PARAMETERS`) belongs
  there too, so the pre-action and post-hoc nets stay in step.

## Discovered during red-team (2026-09-21) — NOT this queue's scope
- **Do command validators block at all?** `scripts/result_block_parser.py` `emit()` prints `{"ok": false,
  "reason": …}` and exits 0; every `validate-*-result.py` hook is wired `… || true`. The documented
  `SubagentStop` decision shape is `{"decision": "block", "reason": …}`. If Claude Code does not honour
  `ok:false`, EVERY converted validator (v15.17.0) has been advisory since conversion while HOOKS.md says
  "decides via stdout JSON". Needs one empirical probe (spawn a worker that emits a malformed block; observe
  whether the stop is blocked) and, if confirmed, a fix to `emit()` — separate PR, spawned as a chip.
- The existing guard for `.supervisor/config.json` being "human-owned" anywhere in the plugin is prose only —
  four scripts write it. Not a defect on its own; it is why S4 moved the opt-out out of the repo.

## Cross-cutting facts every item must respect
- `WORKER_RESULT` is at `schema_version: 2`; additive optional fields do NOT bump it. `out_of_lane` is the
  validated-when-present precedent (`validate-worker-result.py` rule 9); `memory_candidates` is the
  never-validated one. New fields follow `out_of_lane`, and the reason is recorded in RESULT_SCHEMAS.md:
  an unvalidated field silently accepts garbage while `check-contract-parity.sh` stays green.
- `scripts/check-contract-parity.sh` line `worker|worker.md|WORKER_RESULT|…` is a MANIFEST pin — a new field
  must be appended there or the parity gate fails.
- `.worker-summary.md` lives in the worktree (parallel path) and the worktree is removed at FINALIZE; the ONLY
  durable per-worker record is `state.md` `## Worker Results`, written by Context-Keeper's `record_worker_result`
  (`agents/context-keeper.md` declares its parameter contract). Anything Phase 4.5 must see goes through there.
- `loomwright/scripts/test-worktree-audit.sh` AC-2 pins the hooks.json leaf count (39 today) and
  `scripts/check-doc-currency.sh` reads the same count for doc claims — any hook addition updates both in the
  same change (see commit `90546a2` for the last time this bit).
- `bash scripts/check-token-budget.sh` → `worker 5876/5905 — 29 proxy tokens headroom`; it fails CI CLOSED. Both
  items add `worker.md` prose, so both carry the `prompt-token-budgets.json` raise + ARCHITECTURE_CONTRACTS
  raise-log row in scope; whichever lands second re-measures.
- Phase 4.5 fixers emit `FIX_RESULT` in-context and never pass through Context-Keeper (`grep -c
  record_worker_result skills/self-heal-advisory/SKILL.md` → 0). Anything a fixer must be able to say to the
  next iteration's reviewer needs its own carriage (01 §5b).
- Hook payloads carry `session_id` on every event (`scripts/progress-event-fixtures/spawn-probe-2026-09-02/`).
  A SUBAGENT's `PostToolUse` carries `agent_type` + `agent_id` (memory `subagentstop-payload-shape`, verified
  2026-09-05); the in-repo `pretooluse-task-*.json` fixtures are main-thread `Agent` calls and say nothing
  about subagents. `PreToolUse` on a subagent call = probe P2 in 02 before relying on it.
- `CLAUDE_CODE_SESSION_ID` is in the Bash tool env (desktop session, verified) — the only source a prompt-step
  `arm` has; empty must be fail-loud, never a placeholder. **A tool call can set it per-command**
  (`VAR=x cmd`), so nothing may use it to name, overwrite, or remove any file but the caller's own.
- `claude --session-id <uuid>` exists (`claude --help`, verified) — a plugin script that owns a launch can fix
  the child's session id before it starts; the detached drain dispatcher uses this to pre-arm.
- The live plugin is a real directory copy at `~/.claude/plugins/cache/atelier/loomwright/<ver>/` (not a
  symlink to this checkout): a hook script edited in the cache changes behaviour for every session; edited in
  the checkout it changes nothing until reinstall. Any guard must protect its installed copy by basename.
- Concurrent sessions on one checkout are real here (memory `concurrent-heal-loop-sweeps-uncommitted-edits`):
  any per-checkout state an item introduces must be keyed by session, never a single slot.
- Run the FULL `loomwright/scripts/test-*.sh` loop AND root `scripts/check-*.sh` before pushing
  (memory `run-full-ci-suite-loop-before-push`) — `check-vendor-coupling.sh` trips on a literal
  `${CLAUDE_PLUGIN_ROOT}` inside a core COMMENT.
