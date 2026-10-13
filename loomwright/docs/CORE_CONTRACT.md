# Loomwright Core Contract

This document is what a **harness adapter implements**. Loomwright's core is plain files, bash + `jq` engine
scripts and prose protocols. An adapter for a host agent harness (Claude Code today; Cursor or Codex next) makes
three things work. It keeps the **file protocol** below readable and writable at the stated paths. It invokes the
**CLI surface** with the stated argv/stdin and honours the stated exit-code convention. It supplies the **five
capability ports**, or accepts the documented degraded fallback for each one it cannot supply. Anything a harness
offers beyond this belongs in that harness's adapter, never in the core (`ARCHITECTURE_CONTRACTS.md`
§"Portability").

core_contract_version: 1

**Compatibility policy.** Additive changes keep the version: a new optional file, a new script entry, a new port
binding, a new fallback, a new matrix row. Removing or renaming a path, a script entry, a port or an exit code, or
changing the meaning of an existing one, bumps `core_contract_version`. An adapter branches on this marker, never on
the plugin version (which changes every release and says nothing about this contract).

**Pointer-first.** Every section names the authoritative source for its detail. This page is an index and a set of
promises; where it and its authority disagree, the authority wins and this page is the defect. It deliberately
states no counts of agents, commands, skills, hooks or scripts. Those live in `loomwright/.claude-plugin/plugin.json`,
`loomwright/hooks/hooks.json` and the directories themselves.

| Topic | Authority |
|---|---|
| Result blocks every agent emits | `docs/RESULT_SCHEMAS.md` (+ `docs/result-schemas/`) |
| What the installed plugin offers a host (outbound) | `docs/CAPABILITIES_CONTRACT.md` → generated `loomwright/capabilities.json` |
| Who writes which state file | `docs/ARCHITECTURE_CONTRACTS.md` §"State Ownership" |
| How long each `.supervisor/` directory lives | `docs/ARCHITECTURE_CONTRACTS.md` §"`.supervisor/` retention policy" |
| Which run history syncs to a metadata branch | `docs/ARCHITECTURE_CONTRACTS.md` §"Metadata branch" |
| Core vs adapter classification, literal-coupling ratchet | `docs/vendor-coupling-manifest.json` + `scripts/check-vendor-coupling.sh`; `docs/ARCHITECTURE_CONTRACTS.md` §"Portability" |
| `state.md` schema | `skills/state-management/SKILL.md` |
| Hook wiring and the decision shapes hooks print | `loomwright/hooks/hooks.json`, mirrored in `docs/HOOKS.md` |
| Each script's own argv/stdout/exit contract | that script's header comment |

---

## 1. File protocol

Two plain-file trees, both rooted at the repository's top level. Neither requires anything from the harness except
ordinary file reads and writes and `git`.

**Tracking vocabulary.** *gitignored*: never committed. *tracked*: committed. *opt-in*: un-ignored in place by
`/setup memory`, and gitignored until then (`loomwright/scripts/setup-memory.sh`, its managed `.gitignore` block is
the list). *meta-branch*: in a repo that chose branch mode instead, synced to a dedicated metadata branch by
`loomwright/scripts/meta-sync.sh` rather than committed (its `is_managed` predicate is the list). "opt-in / meta-branch"
means the path follows whichever mode the repo chose.

### 1.1 `.supervisor/` — runtime state

| Path | Writer (sole writer where one exists) | Lifecycle | Tracking | Authority |
|---|---|---|---|---|
| `jobs/pending/` → `jobs/in-progress/` → `jobs/done/` \| `jobs/failed/` | Launch Pad creates in `pending/`; Supervisor moves forward; `reconcile-jobs.sh --repair` and `automate-helpers.sh brief-repair` are evidence-gated second/third movers | A brief moves one way only; `done/` and `failed/` are read-only after the move | `pending/`, `in-progress/` gitignored; `done/`, `failed/` opt-in / meta-branch | §"State Ownership"; `docs/result-schemas/` |
| `state.md` | Context-Keeper (sole writer on the parallel path); its `## Session` block is projected by `build-state.sh` from the session log | Rewritten per session; archived to `history/` at FINALIZE | gitignored | `skills/state-management/SKILL.md`; §"State Ownership" |
| `logs/<session_id>.jsonl` | Append-only: hook emitters (`emit-progress-event.sh`, `emit-lifecycle.sh`, `emit-token-ledger.sh`), `checkpoint.sh`, Supervisor / Execute Manager / Worker | One file per session; consumers glob `*.jsonl` explicitly; the only directory with a partial age-out (`retention-sweep.sh`) | gitignored | §"State Ownership"; §"`.supervisor/` retention policy" |
| `automate/<run_id>.md` | `automate-helpers.sh` (atomic run-file writes, append-only `## Progress`) | One run file per `/automate` run, `## Status: done` when finished | opt-in / meta-branch | `docs/result-schemas/automate-run.md`; `skills/automate-loop/SKILL.md` |
| `automate/<run_id>.*` sidecars | Result sidecars (`.supervisor-result.md`, `.review-heal-result.md`) written verbatim by the engine; transient `.config-backup.json` (exists only during a tick); `.dismissed-decisions` by `automate-dismissed.sh` | Sidecars carry no run-file title line, so RESUME never lists them | `.dismissed-decisions` meta-branch in branch mode, otherwise gitignored; the others gitignored | `docs/result-schemas/automate-run.md` §"AUTOMATE_RUN" |
| `requirements/` | The user (intake); `stamp-requirement-status.sh` stamps `## Status:` | Read by `/automate`; a done stamp closes an item | opt-in / meta-branch | §"`.supervisor/` retention policy" |
| `requirements/proposed/` | `propose-work.sh` and `automate-dismissed.sh` (propose-only) | Never enqueued; a human promotes by moving a file out | as `requirements/` | the directory's own `README.md`; `skills/automate-loop/SKILL.md` |
| `postmortem/results.jsonl` | Append-only, one jq-built line per `/pr-postmortem` run (`skills/pr-postmortem/SKILL.md`); curated by `curate-postmortem.sh` | Never aged out; read back by `read-postmortem.sh` | opt-in, gated on the ledger allowlist (`setup-memory.sh`); meta-branch with a line-union merge | §"`.supervisor/` retention policy"; §"Metadata branch" |
| `memory/` | `write-lessons.sh` (`LESSONS.md`), `write-project-memory.sh` (`PROJECT_MEMORY.md`), each with its provenance sidecar | Never aged out; read via `read-lessons.sh` / `read-project-memory.sh`, never `cat` | opt-in | `setup-memory.sh` header; §"`.supervisor/` retention policy" |
| `config.json` | The user; the `/automate` engine toggles it around RUN through `automate-helpers.sh config-suppress` / `config-restore` (byte-for-byte backup, restored in a finally-style cleanup) | Persistent run configuration | gitignored | `CLAUDE.md` §"Failure-Mode Invariants" (single-drain ownership) |
| `run.lock` | `run-lock.sh` (sole writer) | One run per checkout; reclaimed only when its pid is dead and it is old | gitignored | `run-lock.sh` header |

In branch mode the learning stores — `twin/contracts/*.md` + `twin/.provenance.jsonl`, `agent-memory-proposals/*.md` and the two eval JSONL files (`eval/results.jsonl`, `eval/brain-baseline.jsonl`) — are meta-branch too (the `is_managed` predicate above is the list), published only with the user-scope consent `setup-memory.sh consent` records (`docs/ARCHITECTURE_CONTRACTS.md` §"Metadata branch").

Every other `.supervisor/` directory (`twin/`, `worker-summaries/`, `history/`, `floor/`, …) has exactly one row in
§"`.supervisor/` retention policy", which is the authoritative directory list. This table restates only what an
adapter must know to run the engine. In host mode (`LOOMWRIGHT_HOST_MODE=1`) hook-written state moves out of the
repo but keeps this relative layout (`host-mode.sh` header).

### 1.2 `.agent/` — committed conventions

| Path | Writer | Lifecycle | Tracking | Authority |
|---|---|---|---|---|
| `rules/*.json` | `add-rule.sh` (`/rules add`, `/rules retract`), `seed-rules.sh`; read by `read-rules.sh` | Human-curated house rules; the reader never executes a `check` | tracked | `skills/rules/SKILL.md`; `.agent/rules/README.md` |
| `orientation/<area>.md` | `add-orientation.sh` (promotion from `/dreaming`); read by `read-orientation.sh` | Per-area memos, superseded rather than edited | tracked | `.agent/orientation/README.md` |
| `companions.json` | Hand-authored (no writer script) | Read by `automate-helpers.sh plan-waves` to expand `## Touches` | tracked | `skills/automate-loop/SKILL.md` (the `plan-waves` row) |
| `lane-policy.json` (optional) | Hand-authored; honoured only while human-stamped through `rules-check.sh` | Read by `lane-policy.sh resolve`; absent ⇒ no project policy answers | tracked when present (an untracked file is ignored) | `lane-policy.sh` header; `docs/LANE_GATES.md` |
| `meta-sync-deny.txt` (optional) | Hand-authored | Read by `meta-sync.sh` scrub as data, one ERE per line | tracked when present | §"Metadata branch" |

**Why `.agent/` is not under the harness's config directory.** That directory is named after one vendor, and each
harness reads its own. Conventions stored there would be invisible to every other harness, and every reference to
them would be literal vendor coupling. A repo-relative directory with a neutral name is readable by any process that
can open a file. That is **portability by construction**: no adapter has to translate it.

---

## 2. CLI surface

### 2.1 Failure convention (bimodal — invariant)

- **Correctness gates fail CLOSED.** When a gate cannot decide, it exits non-zero, prints a named `PARK` or refusal,
  or prints a verdict its consumer must park on. Silently passing is never an option. Some gates always exit 0 but
  their **verdict** fails closed: the consumer parks on anything but an explicit pass.
- **Side-effect emitters fail SAFE.** Telemetry, webhooks, notifications, progress and lifecycle rows, advisory
  readers: every failure path ends in `exit 0` and the caller's work continues.
- **Hook wiring.** Every hook entry in `hooks.json` that calls a fail-SAFE script carries `|| true` as
  belt-and-suspenders. A **fail-CLOSED blocking hook carries no `|| true`**, because the suffix would neuter it. The
  test-integrity and finalize-publish guards are wired that way. Which leaves lack the suffix is read from
  `hooks.json`; the contract is in `docs/HOOKS.md`.
- Authority: `CLAUDE.md` §"Failure-Mode Invariants" and §"Plugin Hooks".

### 2.2 Engine entry points (an index — each script's header is the per-script authority)

All paths are under `loomwright/scripts/`. "see header" marks a value this index does not restate because the
header does not state it in one line. Read the header before relying on that column.

| Role | Script | argv | stdin | stdout | exit | Mode |
|---|---|---|---|---|---|---|
| State / run file | `automate-helpers.sh` | `<subcommand> …`; the usage list is assembled from the header's `#:` lines (`--help`) | per subcommand (`relay-hook` reads hook JSON) | per subcommand, see the `--help` list (e.g. `gate-eval` ⇒ `MERGE` / `PARK …`; `lane-status` one line per lane; `dismissed-drafts` TSV `draft` rows plus a summary line) | per subcommand, see the `--help` list: typically 0; 1 = usage error or a refusal (`init-check`, `pick-guard`, `lane-info` outside a lane, `lane-convert-ready`, `wave-build`); 2 = a subcommand-specific failure (`lane-wait` usage error, `wave-build` STOPPED, `fleet-closeout` pull failure, `lane-convert-ready` failed push); `lane-launch` 3 = `BLOCKED`, 4 = `HELD` | helpers SAFE; `gate-eval` CLOSED (any failed / unreadable condition ⇒ PARK) |
| State / run file | `run-lock.sh` | `acquire --owner <label> [--session-id <id>] [--root <dir>] [--force-unlock]` · `release --owner <label> \| --session-id <id> [--root <dir>]` · `status [--root <dir>]` | see header | acquire: nothing, or `run_lock_reentrant …`; held: `run_lock_held owner=… pid=… age=…`; status: `LOCKED …` / `UNLOCKED` | acquire 0 ok / 1 held; release is an idempotent 0; usage 1 | CLOSED (a held lock never proceeds) |
| Result parsing | `result_block_parser.py` | library imported by the validators; `--raw` = stdin is the agent's output text with no JSON envelope | the stop-event hook payload (or raw text) | `{}` = allow, `{"decision": "block", "reason": "…"}` = re-prompt the agent | always 0 (one exit point, `emit`) | the verdict blocks through the host's decision; unparseable stdin ⇒ allow |
| Result validation | `validate-*-result.py` | `[--raw]`; the code-review validator also takes `--main-session` | as above | as above | always 0 | as above |
| Progress / state | `emit-progress-event.sh` | see header | the stop-event hook payload | none; appends one `subtask_complete` line to the session log, then runs `build-state.sh` | always 0 | SAFE |
| Progress / state | `build-state.sh` | `<session_id> [main_root]` | see header | none; rewrites only `state.md`'s `## Session` block (temp file + rename) | always 0 | SAFE |
| Emitter | `emit-lifecycle.sh` | subcommand on argv[1] (`waiting [reason]`, `answered`, `heartbeat`, …); anything else is a silent no-op | the hook payload | none; appends an `agent_lifecycle` row | always 0 | SAFE |
| Emitter | `send-webhook.sh` | `[--event-type supervisor_result \| gate …]` (`gate` takes its fields from flags) | the hook payload (not read for `gate`) | see header (its effect is an HTTP POST) | always 0 | SAFE |
| Emitter | `notify-desktop.sh` | see header | the hook payload | none; an OS notification plus one `notifications.log` audit line | always 0 | SAFE |
| Gate | `rules-gate-verdict.sh` | `[--root <tree>]` | delegated calls run with stdin from `/dev/null` | exactly one JSON line `{"verdict": "ok\|none\|fail\|unresolved\|unstamped\|cmd_disabled\|unreadable", …}` | always 0 | verdict CLOSED (any doubt ⇒ a verdict the consumer parks on) |
| Gate | `classify-risk.sh` | `<base_ref> <head_ref> [--root <dir>]` · `--kind-table` | see header | one JSON object (`high_risk` true / false / null + `reasons`) | always 0 | emitter SAFE; consumers fail CLOSED on anything but an explicit `false` |
| Gate | `guard-test-integrity.sh` | none (hook leaf); armed by the companion `guard-arm.sh` | the pre-tool hook payload | the host's deny JSON on a deny | 0 allow / 2 deny | CLOSED; no `\|\| true` |
| Gate | `guard-finalize-publish.sh` | none (hook leaf) · `write-marker [--skip-children-check] [--expect-id <id>]…` | the pre-tool hook payload (guard mode) | guard: the host's deny JSON on a deny; `write-marker`: one JSON line (the marker written, or `{"status":"refused",…}`) | guard 0 allow / 2 deny; `write-marker` 0 written / 1 refused | CLOSED; no `\|\| true` |
| Gate | `verify-provides.sh` | `<brief> <subtask-id> [--root <dir>]` · `--parse-only` · `--kind-table` | see header | one JSON object (`outputs_verified`, `outputs_gap`, status) | always 0 | emitter SAFE; consumers fail CLOSED on `missing` / `unverifiable` |
| Reader | `read-rules.sh` | `[touched paths …]` (route `applies_to`) | see header | an advisory markdown block, subordinate to `CLAUDE.md` | always 0 | SAFE |
| Reader | `read-lessons.sh` | none | see header | verified, fresh lessons grouped by category | always 0 | SAFE |
| Reader | `read-postmortem.sh` | `[paths …]`; arguments take precedence | newline-separated paths, read only when no arguments are given | advisory matches | always 0 | SAFE |
| Reader | `read-token-ledger.sh` | `--session <id> \| --run-id <id> [--root <checkout>]…` | see header | exactly one line `INPUT=… OUTPUT=… CACHE_READ=… CACHE_CREATE=… TOTAL=… EVENTS=… [LEDGER_UNREADABLE=1]` | 0; usage 1 | SAFE (an unreadable ledger prints zeros plus the marker) |
| Host contract | `build-capabilities.sh` | `[--root <plugin-root>] [--out <file>] [--check]` | see header | writes `capabilities.json`; `--check` prints one line on drift | 0 ok / 1 stale or source inconsistency / 2 usage | CLOSED (the staleness gate) |
| Host contract | `host-mode.sh` | sourced library (`lw_host_mode`, `lw_host_state_dir`, …) | — | each function prints a path or nothing | function return codes per header (0 / 1 / 2) | writers skip on an unresolved dir (SAFE); guards deny (CLOSED) |
| Root resolution | `resolve-loomwright-root.sh` | sourced (sets `LOOMWRIGHT_ROOT`) or executed | — | executed: the resolved root | 0 resolved / 1 unresolved | CLOSED (never prints a guessed root) |

**This table is an index.** The authority for every row is that script's own header comment. When a header and
this row disagree, the header wins. The fix is to update this row in the same change as the header (house rule:
a restating copy is updated with its authority, or replaced by a pointer).

---

## 3. Capability ports

Each port lists what the core needs, the core seams that consume it, the Claude Code adapter's binding today, and
the **degraded fallback** for a harness without it. A fallback with no existing seam is labelled
**proposed (not implemented)**. Everything else names the shipped seam it rests on.

### 3.1 run-a-subagent

- **Core needs:** start an agent with its own context window from a prompt, and get its final report back.
- **Consuming seams:** Supervisor Phase 3 (`agents/supervisor.md` §"Single-Agent Path" / §"Sequential Path" /
  §"Parallel Path"), `agents/execute-manager.md`, `agents/worker.md`, the Phase 4.5 code reviewer
  (`skills/self-heal-advisory/SKILL.md`), and the result validators that check each report.
- **Claude Code binding:** the host's subagent spawn tool, with agent definitions in `loomwright/agents/*.md`. Spawn
  shapes live in `skills/async-orchestration/SKILL.md` §"Subagent Spawn Contracts".
- **Degraded fallback:** the **Single-Agent Path** is shipped. It uses one blocking worker, no fan-out and no
  Execute Manager, and is the default below the decomposition threshold. Running the worker protocol inline on the
  main thread with no spawn at all is **proposed (not implemented)**. If it were built, the Phase 4.5 review would
  lose its separate context and would no longer be an independent lens.

### 3.2 run-in-background

- **Core needs:** start long work without blocking the orchestrator, and learn later that it finished.
- **Consuming seams:** Execute Manager Step 3–4 (background workers + poll loop), the detached until-mergeable
  drain (`dispatch-pr-review.sh`), and `/automate --parallel` lanes (`automate-lanes.sh lane-launch`, `lane-wait`).
- **Claude Code binding:** the host's background-task parameter on spawns and shell calls, plus the host's
  headless CLI for detached lanes and drains.
- **Degraded fallback:** **foreground polling at the same seam**, which is shipped in two forms. The Sequential Path
  runs each worker blocking, one at a time. The `/automate` engine sets `auto_review: false` and runs its one
  until-mergeable drain inline instead of detached. Lanes have no foreground form. Without this port,
  `/automate --parallel` is unavailable and the queue runs sequentially.

### 3.3 isolate-a-workspace

- **Core needs:** concurrent writers that cannot see each other's half-finished files.
- **Consuming seams:** parallel workers in sibling git worktrees (`docs/ARCHITECTURE_CONTRACTS.md` §"Worktree Naming
  Convention", created with `git worktree add` by Execute Manager), lane clones under `<primary>-lanes/`, and the
  review lens's throwaway sandbox clone (`adapters/providers/lens-run.sh`).
- **Claude Code binding:** none of the harness's own isolation features. The core creates the worktree itself with
  `git` and passes its path in the spawn prompt. The harness only has to let a subagent work in a given directory.
- **Degraded fallback:** **sequential execution in one checkout**, shipped as the Sequential Path (`--sequential`).
  It executes strictly serially in one working tree, so the concurrent-sibling hazard cannot occur.

### 3.4 react-to-an-event

- **Core needs:** run a script at fixed points in the agent loop: session start, before and after a tool call,
  when an agent stops, when the main turn ends. The script's exit code and JSON must be able to block or re-prompt.
- **Consuming seams:** the result validators (`validate-*-result.py`), emitters (`emit-progress-event.sh`,
  `emit-lifecycle.sh`, `send-webhook.sh`, `notify-desktop.sh`, `emit-token-ledger.sh`), guards
  (`guard-test-integrity.sh`, `guard-finalize-publish.sh`) and `session-resume.sh`.
- **Claude Code binding:** `loomwright/hooks/hooks.json`, documented row by row in `docs/HOOKS.md`.
- **Degraded fallback:** **explicit invocation of the same script at the same seam.** The scripts already accept
  explicit calls: the validators take `--raw` agent text, and `guard-finalize-publish.sh write-marker` is already run
  explicitly at FINALIZE. No orchestrator prose yet wires explicit calls for a hookless harness, so that wiring is
  **proposed (not implemented)**. What is **lost** without hooks, honestly:
  - a **fail-CLOSED pre-tool guard has no explicit-invocation equivalent**. A script called before or after a
    command cannot intercept that command, so the test-integrity guard and the publish deny half of the finalize
    guard become advisory;
  - the validators' **re-prompt** (block, then the agent retries) is lost. An explicit check can only report a bad
    result block after the agent has stopped;
  - **guaranteed firing** is lost. An emitter that depends on the orchestrator remembering to call it brings back
    the miss rate that hook-written progress events replaced (`emit-progress-event.sh` header §WHY).

### 3.5 deliver-instructions

- **Core needs:** project conventions and the agent's own protocol in the model's context at the start of work.
- **Consuming seams:** the project's `CLAUDE.md`, agent prompt bodies (`loomwright/agents/*.md`),
  `docs/shared-agent-prefix.md`, skill preloading, and the vendor-neutral readers whose output agents fold into
  their own context or into spawn prompts: `read-rules.sh` (house rules in the Worker prompt, `agents/supervisor.md`),
  `read-lessons.sh` (Supervisor planning) and `read-orientation.sh` (Launch Pad, Orchestrator).
- **Claude Code binding:** the host's project instruction file plus agent-file frontmatter `skills:` preloading.
- **Degraded fallback:** **inline the vendor-neutral instruction subset in the first prompt.** The reader half is
  shipped: the readers are plain scripts, and the Worker spawn prompt already carries the house-rules output. A root `AGENTS.md` carrying
  the vendor-neutral subset does not exist in this repo; authoring one is **proposed (not implemented)**.

---

## 4. Root resolution

`loomwright/scripts/resolve-loomwright-root.sh` is the **one place the harness's install-root variable is read**. It
publishes the vendor-neutral `LOOMWRIGHT_ROOT`. Precedence, summarised from its header (the authority): the harness
variable, if set; else a pre-set `LOOMWRIGHT_ROOT` (a non-Claude adapter sets the neutral name directly); else the
dev-checkout location derived from the script's own path. It fails closed and never prints a guessed root.

It is **ADAPTER-classed** in `docs/vendor-coupling-manifest.json` and therefore not counted by the coupling ratchet.
This is deliberate: its whole job is to name the harness variable once so nothing else has to, and a gate that
flagged it would be flagging the seam that removes the coupling everywhere else.

**Honest state.** The scripts that read the install root **at runtime** now get it from the resolver
(twin-remediation/11): the validate-entry lookup in the six memory/rule writers and the rules auditor, plus
`validate-entry.sh`, `build-handoff.sh` and `automate-lanes.sh`. Each sources the resolver in a subshell (so nothing
is exported into its own shell or its children), and each falls back to its old location-derived path when the
resolver beside it is missing. Behaviour change: with the harness variable unset, a pre-set `LOOMWRIGHT_ROOT` now
wins over that location-derived path. Not every mention of the harness variable is migrated, on purpose:

- `set-otel-resource-attrs.sh` stays on the harness variable. It is Claude-only adapter code (its gate, its outputs and
  the version manifest it reads are all Claude Code's), and its header says so.
- Printed instructions that the script never expands (in `audit-rules.sh`, `build-insights.sh`,
  `guard-finalize-publish.sh` and `propose-domain.sh`) still name the harness variable. They are text for the host
  shell to run, and that shell only has the harness variable unless an adapter exports `LOOMWRIGHT_ROOT` into it.
- The two `hooks.json` parsers (`build-capabilities.sh`, `scripts/check-contract-parity.sh`) match the harness
  variable because the hook manifest, which is adapter-classed, spells it that way.
- Comments, recorded fixture data, and tests that assert the prompt layer or `hooks.json` spell the harness variable
  are left alone.

---

## 5. Harness capability matrix (re-verified 2026-10-11)

Every cell is either `VERIFIED 2026-10-11 [Sn]`, read from the official vendor page fetched with `curl -sL` at the
time listed below, or `UNVERIFIED` with the reason. No cell is filled from recollection.

**Standing limit.** A capability documented by the vendor is not proof that Loomwright works there. Existence is
not fidelity. Whether a hook payload carries what our validators read, and whether a loader honours our
frontmatter, stays UNVERIFIED until a real run on that harness is observed (§5.3). Vendor capabilities move fast:
**re-verify at adapter-build time**.

### 5.1 Matrix

| Port | Claude Code (reference) | Cursor | Codex |
|---|---|---|---|
| run-a-subagent | VERIFIED [S15]: custom subagents in agent files, each with its own context | VERIFIED [S4]: subagents with their own context; custom agents in `.cursor/agents/`, and Cursor also loads the Claude and Codex project agent directories for compatibility; nesting since Cursor 2.5 (a subagent launched by a subagent cannot launch further) | VERIFIED [S10]: subagent workflows enabled by default (`agents.enabled` defaults to true); built-in `default` / `worker` / `explorer` agents; custom TOML agents in `.codex/agents/` |
| run-in-background | VERIFIED [S15]: subagents run in foreground or background | VERIFIED [S4]: explicit foreground and background modes (`is_background`), plus cloud subagents on their own VM and branch [S7] | VERIFIED [S10]: parallel subagent threads, collected by the main thread; a background-agent panel in the IDE; async (background) command hooks [S8]. UNVERIFIED: a primitive that detaches one subagent while the parent keeps working. The fetched pages do not state one |
| isolate-a-workspace | VERIFIED [S15]: per-subagent temporary git worktree (`isolation: worktree`) | VERIFIED [S4][S6]: subagent-level isolated project copies (one git worktree per subagent); worktrees in the Agents Window and `/worktree` in the IDE; `.cursor/worktrees.json` setup | VERIFIED [S13]: desktop-app Codex-managed worktrees (detached HEAD, under the Codex home directory). UNVERIFIED: subagent-level isolation. The subagents page does not state it |
| react-to-an-event | VERIFIED [S14]: hook events; plugin hooks in `hooks/hooks.json`; exit code 2 blocks | VERIFIED [S1]: `.cursor/hooks.json` (project), `~/.cursor/hooks.json` (user), team and enterprise sources; events include `preToolUse`, `postToolUse`, `postToolUseFailure`, `subagentStart`, `subagentStop`, `stop`, `sessionStart`, `sessionEnd`, `preCompact`, `beforeShellExecution`; exit 0 = use output, exit 2 = deny, any other exit = fail-open unless `failClosed: true`. VERIFIED [S2]: loads Claude Code hooks from that harness's settings files (on by default) and maps their event names and response shapes | VERIFIED [S8]: `hooks.json` or inline `[hooks]` in `config.toml` at user and repo `.codex/` layers, plus plugin-bundled `hooks/hooks.json`; **enabled by default** (`[features].hooks`, with `codex_hooks` kept as a deprecated alias); non-managed hooks must be reviewed and trusted before they run; matching hooks launch concurrently; exit 2 blocks; events include `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `Stop`, `SessionStart`, `SessionEnd`, `Interrupt` |
| deliver-instructions | VERIFIED [S17]: `CLAUDE.md`; reads `AGENTS.md` only when no `CLAUDE.md` exists in or above the working directory | VERIFIED [S3]: `.cursor/rules/*.mdc` project rules, plus `AGENTS.md` at the root and in subdirectories. UNVERIFIED: reading `CLAUDE.md`. The rules page does not mention it | VERIFIED [S9]: `AGENTS.md` (global, then root down to the cwd), `AGENTS.override.md`, `project_doc_fallback_filenames`, capped by `project_doc_max_bytes` |
| skills | VERIFIED [S16]: `SKILL.md` folders, including plugin skills at `<plugin>/skills/<name>/SKILL.md` | VERIFIED [S5]: `SKILL.md` folders in `.agents/skills/` and `.cursor/skills/`, plus home variants; for compatibility Cursor also loads the Claude and Codex skill directories (project and home). Frontmatter: `name`, `description` required; `paths`, `disable-model-invocation`, `metadata` optional | VERIFIED [S11]: `SKILL.md` folders in `.agents/skills` scanned from the cwd up to the repo root, `$HOME/.agents/skills`, `/etc/codex/skills`, bundled system skills; plugins for distribution |

### 5.2 Contrast with the requirement's 2026-08-22 matrix

- **Changed.**
  - Codex hooks no longer need opting in: they are on by default, and the old feature key is a deprecated alias.
  - Codex's event list now includes `SessionEnd` and `Interrupt`.
  - Codex plugins can bundle `hooks/hooks.json`.
  - Codex hooks need a trust review: an untrusted hook is skipped, which an adapter must account for.
  - Codex skills discovery is now documented as `.agents/skills` paths, not just "`SKILL.md`".
  - Cursor's background work is an explicit subagent mode. It was "via subagents".
  - Cursor offers subagent-level worktree isolation.
  - Cursor loads Claude and Codex agent directories as well as their skill directories.
  - Cursor's hook surface lists more events, and an opt-in `failClosed`.
  - Cursor's subagent-stop payload schema is now documented (§5.3).
  - Reference column: Claude Code reads `AGENTS.md` when no `CLAUDE.md` exists, and has per-subagent worktree
    isolation.
- **Confirmed.**
  - Cursor's nesting limit since 2.5.
  - Cursor's project and user `hooks.json` locations.
  - Cursor's exit-0 / exit-2 semantics.
  - Cursor's `.cursor/rules/*.mdc` plus `AGENTS.md`.
  - Cursor's discovery of the Claude and Codex skill directories.
  - Codex subagents enabled by default.
  - Codex `AGENTS.md`.
  - Every Codex event the 2026-08-22 row listed is still present.
- **Could not be re-verified.**
  - Whether Cursor or Codex loads a Claude Code **plugin** as installed (plugin-distributed `hooks.json`, a plugin's
    `skills/` directory). Cursor's third-party page names settings-file locations only [S2].
  - Codex subagent-level isolation.
  - Whether Cursor reads `CLAUDE.md`.
  - Whether either loader tolerates our extra skill frontmatter keys (`version`, `lastUpdated`).
  - Every behavioural question in §5.3.

### 5.3 Payload fidelity — what the docs now say, and what stays UNVERIFIED

The validators resolve a finished agent's report through one ladder: inline final-message fields, then the
subagent-scoped transcript path, then the session transcript path (`PAYLOAD_TEXT_KEYS` /
`PAYLOAD_TRANSCRIPT_KEYS` in `result_block_parser.py`). The parser and `validate-execute-result.py` also read the
payload's `cwd`, and the code-review validator reads its `agent_type`.

- **Cursor [S1][S2].** The documented subagent-stop input carries a subagent-type field, `status`, `task`,
  `description`, `summary`, `duration_ms`, `message_count`, `tool_call_count`, `loop_count`, `modified_files` and a
  subagent transcript path. The common input carries `workspace_roots` and `transcript_path`. Neither carries `cwd`
  or `agent_type`. None of the ladder's inline keys is documented (Cursor's `summary` is not in the
  ladder), so on the documented schema the validators fall through to the transcript path. That transcript's format
  is not documented. A Claude-format block decision is honoured as an automatic follow-up, only when `status` is
  `completed`, and Claude-format hooks default to no loop limit. **Behaviour: UNVERIFIED.** On the documented schema
  alone, the validators would not find an inline report.
- **Codex [S8].** The documented subagent-stop input carries the inline final-message field and the subagent
  transcript path under the **same names** the ladder reads, plus `agent_type`, a continuation flag, and a common
  `cwd`. A block decision asks Codex to continue the subagent. Codex states its transcript format is not a stable
  interface. **Behaviour: UNVERIFIED.** The names match on paper, but no run has been observed.

### 5.4 Sources

Fetched with `curl -sL -m 30` on 2026-10-11 (UTC). Every Codex URL redirected, inside OpenAI, from
`developers.openai.com/codex/…` to `learn.chatgpt.com/docs/…`, and the redirect target is what was read. Raw fetches
were kept in a scratch directory outside the repository.

| # | Requested URL | Served from (after redirect) | Fetched (UTC) |
|---|---|---|---|
| S1 | https://cursor.com/docs/agent/hooks | https://cursor.com/docs/hooks | 2026-10-11T13:09Z |
| S2 | https://cursor.com/docs/reference/third-party-hooks | (same) | 2026-10-11T13:10Z |
| S3 | https://cursor.com/docs/context/rules | https://cursor.com/docs/rules | 2026-10-11T13:09Z |
| S4 | https://cursor.com/docs/context/subagents | https://cursor.com/docs/subagents | 2026-10-11T13:09Z |
| S5 | https://cursor.com/docs/context/skills | https://cursor.com/docs/skills | 2026-10-11T13:09Z |
| S6 | https://cursor.com/docs/configuration/worktrees | (same) | 2026-10-11T13:09Z |
| S7 | https://cursor.com/docs/background-agent | https://cursor.com/docs/cloud-agent | 2026-10-11T13:09Z |
| S8 | https://developers.openai.com/codex/hooks | https://learn.chatgpt.com/docs/hooks | 2026-10-11T13:09Z |
| S9 | https://developers.openai.com/codex/guides/agents-md | https://learn.chatgpt.com/docs/agent-configuration/agents-md | 2026-10-11T13:09Z |
| S10 | https://developers.openai.com/codex/subagents | https://learn.chatgpt.com/docs/agent-configuration/subagents | 2026-10-11T13:09Z |
| S11 | https://developers.openai.com/codex/skills | https://learn.chatgpt.com/docs/build-skills | 2026-10-11T13:09Z |
| S12 | https://developers.openai.com/codex/config-reference | https://learn.chatgpt.com/docs/config-file/config-reference | 2026-10-11T13:09Z |
| S13 | https://developers.openai.com/codex/environments/git-worktrees | https://learn.chatgpt.com/docs/environments/git-worktrees | 2026-10-11T13:12Z |
| S14 | https://code.claude.com/docs/en/hooks | (same) | 2026-10-11T13:09Z |
| S15 | https://code.claude.com/docs/en/sub-agents | (same) | 2026-10-11T13:09Z |
| S16 | https://code.claude.com/docs/en/skills | (same) | 2026-10-11T13:09Z |
| S17 | https://code.claude.com/docs/en/memory | (same) | 2026-10-11T13:09Z |

S12 was fetched and read for project trust (`projects.<path>.trust_level`), which gates whether Codex loads a
project's `.codex/` layer, hooks included.

**Adapter hazard found in passing (Cursor) [S6].** Cursor's automatic worktree cleanup keeps a machine-wide cap. It
re-discovers worktrees created outside its own manager, including plain `git worktree add`, and may delete them.
A Cursor adapter must keep the core's parallel-worker worktrees out of that cleanup or raise the cap. This is
UNVERIFIED in practice.
