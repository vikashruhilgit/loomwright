# Supervisor Job: Host mode — when LOOMWRIGHT_HOST_MODE=1, no Loomwright hook writes into the session's repo

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-10-09-174540/L2 (lane clone of loomwright)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (the session must carry LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1 — it does; see Risk Assessment)
- **Source requirement:** .supervisor/requirements/host-contract/02-host-mode-no-repo-writes.md
- **Base commit:** e41f657bbd4a29488db42ed3ceb902b15af4a598

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 hook scripts + jq; same stack as every touched file |
| 2 | Dependency Availability | GO | no new dependency; the helper is plain bash |
| 3 | Architecture Fit | GO | mirrors the existing sourced-helper pattern (`loom-log-owner.sh`'s `loom_main_root`) |
| 4 | Scope vs Supervisor Capability | CAUTION | ~19 existing scripts + hooks.json + generated contract; split `context-bound` |
| 5 | Hard Blockers | GO | the guard self-hosting cost is covered by the session opt-out (owner relaunched with it) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add one host-neutral switch, `LOOMWRIGHT_HOST_MODE=1`. When it is set, no Loomwright hook creates or modifies any path in the session's working directory. Redirected state goes to `LOOMWRIGHT_HOST_STATE_DIR` when the host provides one, and the fail-CLOSED gates keep enforcing.

**Problem Statement:**
A host (Loomwright Studio first) running agent sessions in an owner's real repos needs Loomwright to keep its state out of those repos. A Studio probe on 15.123.0 found one SDK session added `.claude/settings.local.json` (OTEL env), `.supervisor/logs/<session>.jsonl` and a lifecycle heartbeat file. That silently changes the owner's later sessions and leaves untracked files. Success: with the switch on, `git status --porcelain --ignored` in the session repo shows nothing new after a SessionStart, a SubagentStop and a Stop hook run. With the switch off, every hook is byte-for-byte unchanged.

**Owner decisions (2026-10-09, recorded in the run file):**
- **D1, gate state without a state dir:** with host mode on and NO valid `LOOMWRIGHT_HOST_STATE_DIR`, the fail-CLOSED gates' state goes to a per-user directory OUTSIDE the repo: `${TMPDIR:-/tmp}/loomwright-host-<uid>/<repo-hash>/`, where `<repo-hash>` = the first 12 hex of a hash of the repo's absolute main-worktree path. "Gate state" means the guard markers, the finalize-gate marker AND the state that gate reads (the `## Session` block of `state.md`, the plugin session log and its `.owner` file). Every other hook write SKIPS. The requirement's "nothing new is written anywhere" test therefore reads: nothing in the repo, and outside it only under that per-user gate root.
- **D2:** this run carries `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` so the worker may edit the guard-protected `guard-arm.sh`, `guard-test-integrity.sh` and `hooks.json` (HOOKS.md "Self-hosting cost").

**Design (binding for every subtask — one resolver, never a restated copy):** a new sourceable helper `loomwright/scripts/host-mode.sh` (bash 3.2, no side effects on source, same header style as `loom-log-owner.sh`) with exactly these functions:
- `lw_host_mode` — return 0 iff `LOOMWRIGHT_HOST_MODE` is exactly `1`.
- `lw_host_state_dir [root]` — print `$LOOMWRIGHT_HOST_STATE_DIR` and return 0 only when it is an absolute path (`/`-prefixed), an existing directory, and NOT inside `[root]` (the repo's main worktree, when given). Else print nothing and return 1.
- `lw_state_dir <root>` — the `.supervisor`-equivalent for NON-gate writes. Host mode off: print `<root>/.supervisor`, return 0. On with a valid state dir: print it, return 0. On without one: print nothing, return 1 (the caller SKIPS its write and keeps its fail-SAFE exit 0).
- `lw_gate_state_dir <root>` — the `.supervisor`-equivalent for GATE state (D1). Off: `<root>/.supervisor`. On with a valid state dir: that dir. On without one: the per-user gate root of D1. It prints the path and never creates it; a writer creates it with `mkdir -p` under `umask 077`.
- `lw_state_md_read <root>` — the path every hook READS `state.md` from (the session id, status, branch and the sections build-state preserves). The repo `state.md` (the agent-authored seed) decides which run is current. Under host mode it prints `lw_gate_state_dir`'s `state.md` in two cases: that copy's `## Session` `session_id` EQUALS the repo copy's, or the repo copy is absent. In every other case it prints `<root>/.supervisor/state.md`, READ-ONLY under host mode. That covers a gate copy that is missing, or stale from an earlier run with a different session id. The gate dir outlives runs, so a gate copy alone never wins over a newer repo seed. Off mode: always `<root>/.supervisor/state.md`, as today.
- **Agent-authored state (Plan Review attempt 1 finding):** `.supervisor/state.md` is CREATED by an agent, not a hook — Context-Keeper's `initialize` seeds `## Session` with the Write tool at the repo path. Agent writes are outside this item's hook-only scope, so under host mode the repo `state.md` can exist and say `running` before any hook has projected one. Rules:
  1. A hook never writes or edits the repo `state.md` under host mode. `build-state.sh` writes its projection to `lw_gate_state_dir`'s `state.md`, taking the non-`## Session` sections it preserves from `lw_state_md_read`. Its lock also lives in the gate dir.
  2. `seed-run-owner.sh` keeps its trigger (an agent Write/Edit to the repo `.supervisor/state.md`) and reads the run id from the file that was written. It writes only the `.owner` sidecar, through `lw_gate_state_dir`.
  3. `guard-finalize-publish.sh` fails CLOSED on the UNION. Under host mode the run is LIVE when EITHER the repo `state.md` OR the gate-dir `state.md` reads `running`/`checkpoint`, and the live session id is taken from `lw_state_md_read`. A live run's publish is denied unless the marker for that session id exists in `lw_gate_state_dir`. A missing or stale redirected file never makes the gate `allow`.
  4. Emitters that take the session id from `state.md` read it via `lw_state_md_read`.
  Honest limit, recorded in HOOKS.md: under host mode the projected `## Session` block lives only in the gate dir, so the repo `state.md` keeps Context-Keeper's seed values.
- The redirected layout keeps the `.supervisor/` relative layout under the resolved dir: `<dir>/logs/<session>.jsonl`, `<dir>/state.md`, `<dir>/guard/<id>.json`, `<dir>/logs/<id>.finalize-gate`.
- Every hook script that writes resolves its directory through this helper. Every READ of the same state inside hook scripts resolves through the SAME function as its writer, so readers and writers never disagree.

## Acceptance Criteria
- [ ] AC1: Given `LOOMWRIGHT_HOST_MODE=1` (with or without a state dir), when the SessionStart, SessionEnd, SubagentStop (worker), PostToolUse (AskUserQuestion, Bash, Write|Edit, Task), PreToolUse (AskUserQuestion, Agent|Task), Notification, StopFailure and Stop hook leaves of `hooks.json` run against a throwaway git repo, then `git status --porcelain --ignored` shows nothing new in that repo. This includes `.claude/settings.local.json` and `.supervisor/`.
- [ ] AC2: Given host mode on and `LOOMWRIGHT_HOST_STATE_DIR` set to a valid absolute directory outside the repo, when the same hooks run, then the lifecycle, agent_identity, token ledger and progress events land under `$LOOMWRIGHT_HOST_STATE_DIR/logs/<session>.jsonl` in the SAME line format as today, and `state.md` lands at `$LOOMWRIGHT_HOST_STATE_DIR/state.md`.
- [ ] AC3: Given `LOOMWRIGHT_HOST_MODE` unset (or any value other than `1`), when any hook runs, then its behaviour is byte-for-byte unchanged and every existing `test-*.sh` passes unchanged.
- [ ] AC4: Given host mode on, when a session is armed (`guard-arm.sh arm-from-payload` for a worker spawn), then `guard-test-integrity.sh` still denies a protected edit for that session, reading its marker from `lw_gate_state_dir`. `guard-finalize-publish.sh` likewise still denies an unmarked publish in a live run, reading `state.md`, the session log and its marker from `lw_gate_state_dir`. When only the agent-written repo `state.md` exists (status `running`), or a stale gate-dir copy from an earlier run (terminal status, different session id) sits beside a live repo copy, the publish is still denied. This holds both with a state dir and, per D1, without one (gate root under `${TMPDIR}`). A protected-path check also covers the redirected guard dir and `host-mode.sh` itself, so an armed agent cannot disarm by editing either.
- [ ] AC5: Given host mode on and `LOOMWRIGHT_HOST_STATE_DIR` unset, relative, missing, a file, or inside the repo, when every fail-SAFE hook runs, then each exits 0 and writes nothing in the repo; non-gate writes are skipped, and gate state goes only to the per-user gate root (D1).
- [ ] AC6: `docs/HOOKS.md` gains ONE host-mode section that names both env vars, states D1, and lists every hook script `hooks.json` invokes (plus the inline StopFailure leaf) with its classification — `redirects` / `skips` / `unaffected` — so item 03 can declare them without re-auditing.
- [ ] AC7: The PR ships `changelog.d/host-contract-02-host-mode-no-repo-writes.md` and NO version bump (wave lane; the wave branch carries the one bump).
- [ ] AC8: `bash loomwright/scripts/build-capabilities.sh --check` passes. If the StopFailure leaf or the audit changed, `loomwright/capabilities.json` is regenerated by the generator, never hand-edited.

## Touched-file invariants

> Grounded at base `e41f657bbd4a29488db42ed3ceb902b15af4a598`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/emit-lifecycle.sh`, `emit-agent-identity.sh`, `emit-token-ledger.sh`, `emit-progress-event.sh`, `close-stranded-run.sh`, `seed-run-owner.sh`** — keep: fail-SAFE, never a non-zero exit — `mkdir -p "$LOG_DIR" 2>/dev/null || exit 0` (emit-lifecycle, emit-progress-event, close-stranded-run, seed-run-owner) / `printf '%s\n' "$LINE" >> "$LOG_FILE" 2>/dev/null || true` (emit-agent-identity, emit-token-ledger); main-worktree anchoring `main_root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"`; the JSONL line shapes are unchanged (consumers: build-state.sh, read-token-ledger.sh, build-floor). Reuse: `loom-log-owner.sh` (already sourced by emit-lifecycle). These write gate-input state, so they resolve through `lw_gate_state_dir` (D1). Fired by: SubagentStop / PostToolUse / PreToolUse / StopFailure / SessionEnd leaves in `hooks/hooks.json`. Pinned by: test-emit-lifecycle.sh, test-agent-identity.sh, test-token-ledger.sh, test-progress-state.sh, test-close-stranded-run.sh, test-seed-run-owner.sh, test-hook-payload-contract.sh.
- **`loomwright/scripts/build-state.sh`, `reproject-state-on-terminal.sh`** — keep: `[ -n "$MAIN_ROOT" ] && [ -d "$MAIN_ROOT" ] || exit 0` and the atomic `mv -f "$TMP" "$STATE_MD"` projection; reproject only calls build-state (`STATE_MD=".supervisor/state.md"` is its read path). Under host mode the projection is WRITTEN to `lw_gate_state_dir`'s `state.md` and its preserved sections are READ via `lw_state_md_read` (the agent-authored state rules in the Design block). Pinned by: test-progress-state.sh, test-seed-run-owner.sh.
- **`loomwright/scripts/guard-arm.sh`, `guard-test-integrity.sh`** — keep: guard-test-integrity's evaluation order "(i) .supervisor/guard/ absent or empty -> allow, no jq" (the inert path stays jq-free and fork-cheap — resolving the dir must not add a `jq` call there), its deny mechanics (exit 2 + `permissionDecision: "deny"`), and its hooks.json leaves carrying NO `|| true`; guard-arm's `arm-from-payload` "Always exits 0" and the per-session marker design (`<id>.json`, prune > 7 days). Change: `GUARD_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.supervisor/guard"` resolves via `lw_gate_state_dir` in BOTH files (one rule); `is_protected_path_arg` and the Write|Edit check also cover the resolved guard dir, and `is_protected_basename` gains `host-mode.sh`. Pinned by: test-guard-test-integrity.sh (protected-basename matrix).
- **`loomwright/scripts/guard-finalize-publish.sh`** — keep: "the marker format has exactly one writer and one reader", `rm -f "$MARKER" 2>/dev/null` before every write, `refuse "log_dir_unwritable"` (fail-CLOSED write-marker), and the deny path. Change: `resolve_root`'s `STATE_MD="$ROOT/.supervisor/state.md"` / `LOG_DIR="$ROOT/.supervisor/logs"` resolve via `lw_gate_state_dir "$ROOT"`; HEAD is still read from `$PROJ`. Pinned by: test-guard-finalize-publish.sh.
- **`loomwright/scripts/set-otel-resource-attrs.sh`** — keep: `printf 'export OTEL_RESOURCE_ATTRIBUTES=%q\n' "$ATTR" >> "${CLAUDE_ENV_FILE}"` (session-scoped, still allowed under host mode) and `exit 0` everywhere. Change: under host mode it never reaches `SL="$ROOT/.claude/settings.local.json"` — classification `skips` for that write. Pinned by: test-set-otel-resource-attrs.sh.
- **`loomwright/scripts/session-resume.sh`, `stamp-requirement-status.sh`, `worktree-audit.sh`, `notify-desktop.sh`, `send-telemetry.sh`, `hook-dispatch-on-pr-create.sh`** — keep each script's terminal `exit 0` / fail-SAFE posture. Non-gate writes resolve via `lw_state_dir` (redirect with a state dir, skip without). The nudge markers (`.supervisor/.curation-nudge-shown` and others), `notifications.log`, `.notified-ids`, `telemetry.log`, and `worktrees.log` (`printf '%s\n' "$line" >> "$dir/worktrees.log"`) all follow that rule. Repo CONTENT mutations SKIP under host mode, never redirect: stamp-requirement-status's `>> "$req"` on a requirement file, and session-resume's `reconcile-jobs.sh --repair-merged` brief moves. worktree-audit only calls the read-only `--print-base-ref`, and its one repo write is `worktrees.log`. Under host mode, hook-dispatch-on-pr-create does not dispatch: `dispatch-pr-review.sh` writes markers, logs and a sibling worktree. Its own session-log line is gate-class state (D1), so it follows `lw_gate_state_dir`. Pinned by: test-session-resume.sh, test-stamp-requirement-status.sh, test-worktree-audit.sh, test-notify-desktop.sh, test-hook-payload-contract.sh, test-hook-dispatch-on-pr-create.sh.
- **`loomwright/hooks/hooks.json`** — keep: every fail-SAFE leaf's `|| true`; the two guard leaves and the finalize-publish leaf WITHOUT `|| true`; leaf order. Change: only the StopFailure leaf's inline `mkdir -p .supervisor/logs && echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] STOP_FAILURE $payload" >> .supervisor/logs/failures.log`. It must not write in the repo under host mode, and its off-mode line format must stay byte-identical: the §6 rate-limit park reads `failures.log`. Pinned by: test-hook-payload-contract.sh, test-build-capabilities.sh (and `capabilities.json` via `build-capabilities.sh --check`).

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely.
  - enforcement: advisory
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority.
  - enforcement: advisory

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Helper + gate-input emitters | AC1, AC2, AC3, AC5 (emitters) | 8 modify, 1 create | `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Fail-CLOSED gates | AC4, AC3 | 3 modify | `skills/error-handling/SKILL.md` | BLOCKED (by #1) |
| 3 | Session/notify/telemetry hooks + hooks.json StopFailure + capabilities | AC1, AC3, AC5, AC8 | 8 modify (+ build-capabilities.sh only if its audit must change) | `skills/error-handling/SKILL.md`, `skills/ci-cd/SKILL.md` | BLOCKED (by #1) |
| 4 | test-host-mode.sh + HOOKS.md host-mode section + changelog fragment | AC1–AC7 verification, AC6, AC7 | 1 modify, 2 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1, #2, #3) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/host-mode.sh"}
  - {kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_host_mode"}
  - {kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_host_state_dir"}
  - {kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_state_dir"}
  - {kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_gate_state_dir"}
  - {kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_state_md_read"}
  - {kind: "symbol", path: "loomwright/scripts/emit-lifecycle.sh", name: "lw_gate_state_dir"}
  - {kind: "symbol", path: "loomwright/scripts/build-state.sh", name: "lw_gate_state_dir"}
requires: []
lanes:
  - "loomwright/scripts/host-mode.sh"
  - "loomwright/scripts/emit-lifecycle.sh"
  - "loomwright/scripts/emit-agent-identity.sh"
  - "loomwright/scripts/emit-token-ledger.sh"
  - "loomwright/scripts/emit-progress-event.sh"
  - "loomwright/scripts/build-state.sh"
  - "loomwright/scripts/seed-run-owner.sh"
  - "loomwright/scripts/reproject-state-on-terminal.sh"
  - "loomwright/scripts/close-stranded-run.sh"
external_requires: []

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/guard-arm.sh", name: "lw_gate_state_dir"}
  - {kind: "symbol", path: "loomwright/scripts/guard-test-integrity.sh", name: "lw_gate_state_dir"}
  - {kind: "symbol", path: "loomwright/scripts/guard-test-integrity.sh", name: "host-mode.sh"}
  - {kind: "symbol", path: "loomwright/scripts/guard-finalize-publish.sh", name: "lw_gate_state_dir"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_gate_state_dir"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_state_md_read"}
lanes:
  - "loomwright/scripts/guard-arm.sh"
  - "loomwright/scripts/guard-test-integrity.sh"
  - "loomwright/scripts/guard-finalize-publish.sh"
external_requires:
  - "Session env LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1 (owner decision D2) so edits to guard-protected basenames are allowed"

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/scripts/set-otel-resource-attrs.sh", name: "lw_host_mode"}
  - {kind: "symbol", path: "loomwright/scripts/session-resume.sh", name: "lw_host_mode"}
  - {kind: "symbol", path: "loomwright/scripts/stamp-requirement-status.sh", name: "lw_host_mode"}
  - {kind: "symbol", path: "loomwright/scripts/notify-desktop.sh", name: "lw_state_dir"}
  - {kind: "symbol", path: "loomwright/scripts/send-telemetry.sh", name: "lw_state_dir"}
  - {kind: "symbol", path: "loomwright/scripts/worktree-audit.sh", name: "lw_state_dir"}
  - {kind: "symbol", path: "loomwright/scripts/hook-dispatch-on-pr-create.sh", name: "lw_host_mode"}
  - {kind: "symbol", path: "loomwright/hooks/hooks.json", name: "LOOMWRIGHT_HOST_MODE"}
  - {kind: "file", path: "loomwright/capabilities.json"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_state_dir"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_host_mode"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_gate_state_dir"}
lanes:
  - "loomwright/scripts/set-otel-resource-attrs.sh"
  - "loomwright/scripts/session-resume.sh"
  - "loomwright/scripts/stamp-requirement-status.sh"
  - "loomwright/scripts/worktree-audit.sh"
  - "loomwright/scripts/notify-desktop.sh"
  - "loomwright/scripts/send-telemetry.sh"
  - "loomwright/scripts/hook-dispatch-on-pr-create.sh"
  - "loomwright/hooks/hooks.json"
  - "loomwright/capabilities.json"
  - "loomwright/scripts/build-capabilities.sh"
external_requires:
  - "Session env LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1 (owner decision D2) — hooks.json is a guard-protected basename"

# Subtask 4
provides:
  - {kind: "file", path: "loomwright/scripts/test-host-mode.sh"}
  - {kind: "symbol", path: "loomwright/docs/HOOKS.md", name: "LOOMWRIGHT_HOST_STATE_DIR"}
  - {kind: "file", path: "changelog.d/host-contract-02-host-mode-no-repo-writes.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/host-mode.sh", name: "lw_gate_state_dir"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/guard-test-integrity.sh", name: "lw_gate_state_dir"}
  - {from: "3", kind: "symbol", path: "loomwright/hooks/hooks.json", name: "LOOMWRIGHT_HOST_MODE"}
lanes:
  - "loomwright/scripts/test-host-mode.sh"
  - "loomwright/docs/HOOKS.md"
  - "changelog.d/host-contract-02-host-mode-no-repo-writes.md"
external_requires: []
```

**Per-subtask notes (the worker's checklist):**
- **Subtask 1:** create `host-mode.sh` exactly per the Design block. Source it from each lane script beside its existing anchoring (fail-SAFE: if sourcing fails AND `LOOMWRIGHT_HOST_MODE=1`, the script exits 0 without writing; when the switch is unset, behaviour must not depend on the helper loading). Replace each `"$main_root/.supervisor"` / `"$MAIN_ROOT/.supervisor"` write base with `lw_gate_state_dir`. When host mode is off the helper returns `<root>/.supervisor`, byte-identical paths. Keep any existing "`.supervisor` must already exist" presence check, applied to the RESOLVED dir: under the per-user gate root, create it (`umask 077; mkdir -p`) only where today's code already creates `.supervisor/logs`. Readers of `state.md`/session logs in these scripts use the same resolver.
- **Subtask 2:** both guard scripts resolve `GUARD_DIR` through `lw_gate_state_dir` (with the repo root from `${CLAUDE_PROJECT_DIR:-$PWD}`, as today — guard-arm is intentionally worktree-scoped, keep that). guard-test-integrity's inert path (i) must stay jq-free; sourcing a bash-only helper is fine. Extend the protected-path checks to the resolved guard dir and add `host-mode.sh` to `is_protected_basename`. In guard-finalize-publish, `LOG_DIR` (marker + session log) moves to `lw_gate_state_dir`, and `STATE_MD` is read via `lw_state_md_read` (Design rule 3 — a running repo `state.md` with no gate-dir copy is LIVE, deny). HEAD/branch reads stay on `$PROJ`. The provides entry naming `host-mode.sh` asserts that literal is present in `is_protected_basename`'s list.
- **Subtask 3:** set-otel: under host mode skip the whole settings.local.json block (the CLAUDE_ENV_FILE export still runs). Skip under host mode: session-resume's `reconcile-jobs.sh --repair-merged` brief moves, stamp-requirement-status's requirement-file append, and hook-dispatch's dispatch. worktree-audit's `--print-base-ref` is read-only and unchanged. Logs and markers: `lw_state_dir`. hooks.json StopFailure leaf: under host mode, append to `<state dir>/logs/failures.log` when a valid state dir exists, else skip. Off mode stays byte-identical in effect (the inline form may stay inline or move to a small script — the worker picks the smaller diff). Then run `bash loomwright/scripts/build-capabilities.sh --check`. If it is stale, regenerate with the generator, and update its hand-audit `w` table in `build-capabilities.sh` only when a NEW script is invoked by a hook leaf.
- **Subtask 4:** `test-host-mode.sh` must be co-located, hermetic (no network, no gh — PATH stubs), bash 3.2 safe, and scrub inherited flags with `env -u LOOMWRIGHT_HOST_MODE -u LOOMWRIGHT_HOST_STATE_DIR` on off-legs. Legs:
  - (a) host mode + state dir: run a SessionStart, a SubagentStop (worker payload) and a Stop leaf exactly as `hooks.json` spells them (`CLAUDE_PLUGIN_ROOT` set) in a throwaway `git init` repo with `TMPDIR` pointed at a scratch dir. Assert `git status --porcelain --ignored` is empty and that the events are in the state dir.
  - (b) host mode, no state dir: same, plus every hook exits 0 and nothing is written outside the repo except under `$TMPDIR/loomwright-host-<uid>/` (D1).
  - (c) an armed session still gets a deny from `guard-test-integrity.sh` under host mode, in both (a) and (b).
  - (c2) `guard-finalize-publish.sh` under host mode, in both the state-dir and D1 cases, denies a `gh pr create` payload in two setups: a live run whose `state.md` and session log are in `lw_gate_state_dir` with no marker, and a live run whose ONLY `state.md` is the agent-written repo copy (`status: running`). After `write-marker`, the same publish is allowed.
  - (c3) stale gate copy, in both the state-dir and D1 cases: a gate-dir `state.md` with `status: complete` and an old session id sits beside a repo `state.md` with `status: running` and a new session id. Assert `lw_state_md_read` returns the repo copy, the publish is denied, and a worker SubagentStop then projects the NEW session into the gate dir (emit-progress-event + build-state).
  - Legs (a) and (b) also run a SessionEnd leaf and a PostToolUse[AskUserQuestion] leaf.
  - (d) off mode is unchanged: the same hooks write `.supervisor/` as today.
  - (e) mutation control: copy one hook (e.g. emit-agent-identity.sh) into a scratch plugin root with its host-mode check removed, and assert leg (a) then FAILS. Gate the mutant on non-empty, differs from the original, and passes `bash -n` (lesson fa32a308).
  
  The HOOKS.md section lists every `hooks.json` script plus the inline StopFailure leaf with its classification. Do not restate counts. The changelog fragment follows `changelog.d/README.md`.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──┐
Subtask 1 ──→ Subtask 3 ──┼──→ Subtask 4
Subtask 1 ────────────────┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 1 | Subtask 2/3 | none (they consume the helper) | YES (requires) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2, Subtask 3 (parallel)
- **Batch 3:** Subtask 4
- **Recommended workers:** 2
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md` |
| 2 | `skills/error-handling/SKILL.md` |
| 3 | `skills/error-handling/SKILL.md`, `skills/ci-cd/SKILL.md` |
| 4 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Edits to `guard-arm.sh` / `guard-test-integrity.sh` / `hooks.json` are denied once a worker arms the session | HIGH | Owner relaunched with `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` (D2); if a deny still appears, stop and report — never work around the guard |
| A gate reader and its writer resolve different dirs → the gate goes silently inert under host mode (fail OPEN) | HIGH | One resolver (`lw_gate_state_dir`) for every gate writer AND reader; test leg (c) asserts a deny under host mode in both state-dir cases |
| Off-mode drift breaks an existing consumer (state.md projection, rate-limit park on failures.log, capabilities contract) | HIGH | Helper returns `<root>/.supervisor` byte-identically when off; run the whole suite with `bash scripts/ci-local.sh`; `build-capabilities.sh --check` |
| `LOOMWRIGHT_HOST_STATE_DIR` pointed inside the repo would re-introduce repo writes | MEDIUM | `lw_host_state_dir` rejects a dir inside the main worktree (falls to D1 behaviour) |
| `.supervisor`-existence presence checks (`plugin_present`) evaluated against the repo instead of the resolved dir would make redirect a no-op | MEDIUM | Apply each presence check to the resolved dir; test leg (a) asserts events landed |
| Inherited `LOOMWRIGHT_HOST_MODE` in a dev shell turns off-mode fixtures into false passes | MEDIUM | `env -u` on every off-leg (lessons ef916b74 / edc10b50) |
| Scope CAUTION (Feasibility check 4): ~19 scripts + hooks.json + generated contract exceed one worker's context | MEDIUM | `context-bound` split into 4 subtasks with disjoint lanes; each worker re-checks its own Touched-file invariants entries before hand-back |
| The agent-authored repo `state.md` and the gate-dir projection diverge under host mode, including a stale gate copy from an earlier run hiding a live repo seed | HIGH | `lw_state_md_read` selects by session-id match, with the repo seed deciding the current run; finalize-publish is live on the union of both copies (deny); test legs (c2) and (c3); HOOKS.md names the divergence as an honest limit |
| Per-user gate root collides across repos | LOW | `<repo-hash>` keyed on the absolute main-worktree path; `umask 077` |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-09-host-mode-no-repo-writes.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-10T06:42:32Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/450
- **Branch:** feature/hc-02-host-mode-no-repo-writes
- **Files changed:** 28
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Host mode (LOOMWRIGHT_HOST_MODE=1) — every hooks.json writer routes through loomwright/scripts/host-mode.sh (redirect to LOOMWRIGHT_HOST_STATE_DIR, skip, or D1 per-user gate root); fail-CLOSED gates still deny; off mode byte-identical. Phase 4.5: 3 review→fix iterations (4+2+1 HIGH, all reproduced and fixed); the iteration-3 fix (204f941) is unreviewed. Ground truth 2/2; risk high (hooks/size); rules_check none.

## Not verified
- **Agent-written session_end under host mode** — the agent appends it to the repo log, while build-state/reproject read the gate log; agent writes are out of the hook-only scope (subtask 1)
- **A live Claude Code hook firing under host mode** — exercised by direct script invocation with synthetic payloads, not a real session (subtask 1)
- **A live PreToolUse hook firing under host mode** — direct script invocation only (subtask 2)
- **The capabilities.json host-split rule** — no pinned case in test-build-capabilities.sh (subtask 3)
- **The /automate §6 rate-limit park** — it reads the repo failures.log, so it misses the redirected STOP_FAILURE line under host mode (subtask 3)
- **docs/CAPABILITIES_CONTRACT.md §writes[]** — does not mention the host-split rule (subtask 3)
- **bash 3.2 runtime** — only /bin/bash -n was checked under 3.2 (subtask 3)
- **The runtime shell for hook commands** — the suite runs leaves with sh -c (subtask 4)
- **Writes to absolute paths outside the repo, HOME, TMPDIR and the state dir** — the suite observes only those dirs (subtask 4)
