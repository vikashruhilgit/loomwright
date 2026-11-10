# Armed runs deny Write, Edit, MultiEdit and NotebookEdit paths that resolve outside the repository's worktrees

## Status: pending

Source: batch H item H1 (`loomwright-archive/requirements/batchH/2026-11-05-041317-armed-runs-deny-any-tool-or-mcp-file-path-that-resolves-outside-the-repositorys-worktrees.md` and its `_BACKLOG-2026-11-05-041317-batch-h-h1-path-containment-guard.md`). Narrowed by the owner to the write tools; refreshed against main `8ec200e` (plugin 17.35.1).

**As the** owner (Vikash), whose Supervisor runs, `/review-pr` drains and `/automate` lanes run workers with nobody watching,
**I want** every path given to the `Write`, `Edit`, `MultiEdit` or `NotebookEdit` tool during an armed Loomwright run to be resolved to its real location (symlinks followed, `..` and absolute paths handled) and denied unless it lands in an explicitly allowed write root, failing closed when the path cannot be resolved,
**so that** an armed agent cannot write to `~/.ssh`, another repository, the installed plugin, `~/.claude/` config or `/etc` through a symlinked directory, a `../../` path or an absolute path, and containment no longer rests on the prompt's "work ONLY in the worktree" line.

## Problem (verified on main 8ec200e)

- **No write-path containment.** `loomwright/hooks/hooks.json` PreToolUse has four groups: `AskUserQuestion` (fail-SAFE emitters), `Bash` (fail-CLOSED `guard-test-integrity.sh` and `guard-finalize-publish.sh`, each `"onFailure": "block"`, no `|| true`), `Write|Edit` (fail-CLOSED `guard-test-integrity.sh`) and `Agent|Task` (the `guard-arm.sh arm-from-payload || true` backstop). No leaf matches `MultiEdit` or `NotebookEdit`, and no hook resolves a tool path.
- **The test-integrity guard checks basenames on purpose.** `docs/HOOKS.md`'s `PreToolUse (Write|Edit)` row says it matches `tool_input.file_path`'s "BASENAME (never `realpath`)". `evaluate_write_edit()` in `guard-test-integrity.sh` denies only protected basenames and a few directory substrings, so a write to `/etc/x` or through `inside-link -> /elsewhere` is allowed.
- **A tested physical-path library exists.** `loomwright/scripts/contained-path-lib.sh`: `cpl_phys` resolves symlinks (40-hop cap), resolves a missing target through its nearest existing ancestor, and returns 1 for a relative path, a dangling symlink, an over-long chain, or a `.`/`..` in the missing tail; `cpl_inside` compares ancestors by device+inode and treats an exhausted cap as outside. It is used today only by repo-relative config writers, never by a hook.
- **The arming model to reuse.** `guard-arm.sh` writes one marker per session at `<gate dir>/guard/<session_id>.json` (Supervisor INIT, the review-heal entry, the dispatcher pre-arm, the `Agent|Task` backstop) and only `SessionEnd` removes it. `guard-test-integrity.sh` resolves the gate dir through `host-mode.sh`'s `lw_gate_state_dir_existing` (never creates; rc 2 = no gate dir = inert) and allows without `jq` when no marker file exists.
- **Settings `env` reaches hook processes** (`docs/HOOKS.md` §"Guard contract", probed 2026-09-23). A repository can commit `.claude/settings.json` with an `env` block, so any env-variable knob that widens this guard can be set by the repo being worked on.
- **The crash-wiring suite names its guards by hand.** `test-guard-onfailure.sh` builds its aborting copies with `for g in guard-test-integrity.sh guard-finalize-publish.sh`, and picks the (C)/(D) payload by exact matcher (`'Write|Edit'`). A new guard would get only the "script missing" crash case, never the "aborts after `set -u`" case.

## The allowed write set (normative)

When the session is armed, a write path is allowed **only** if its physical path (`cpl_phys`) lies inside one of these roots (`cpl_inside`, each root resolved with `cd -P` on every call, nothing cached across calls):

| # | Root | Covers | How it is found |
|---|---|---|---|
| W1 | Every worktree of the session's repository | the main checkout (so `.supervisor/` there stays writable from a linked worktree: Context-Keeper's `state.md`, briefs, requirements, agent-memory proposals), Supervisor worker worktrees (`../{repo}-{task_id}-{slug}`), drain worktrees, host-native `.claude/worktrees/`, and a `--plugin-dir` checkout of this plugin when it is inside the repo | `git -C <anchor> worktree list --porcelain`, every `worktree <path>` line; `<anchor>` = payload `cwd`, else `CLAUDE_PROJECT_DIR`. An entry that does not resolve (a `prunable` worktree whose directory is gone) is skipped, never "allow all" |
| W2 | The temp roots: physical `$TMPDIR` (when it is an absolute existing directory) and physical `/tmp` | `mktemp -d` scratch-dir repros (`agents/worker.md` self-review, `agents/code-reviewer.md` §5) and the host's session scratchpad (`/tmp/claude-<uid>/…`, `/private/tmp` on macOS) | env + literal `/tmp` |
| W3 | The host's auto-memory dir for this project: `dirname(transcript_path)/memory/` | the main thread's own auto-memory writes | payload `transcript_path` (a subagent's payload carries the session's transcript path, `progress-event-fixtures/guard-probe-2026-09-23/p2-inner-subagent-bash.json`) |
| W4 | The host's plans dir: `<C>/plans/`, where `<C>` is the grandparent of `dirname(transcript_path)` and only when `dirname(transcript_path)`'s parent is named `projects` | a plan file written in plan mode by an armed session | derived from `transcript_path` |

**Carve-out (denied even inside W2):** anything under `<temp root>/loomwright-host-<uid>/`, the host-mode per-user gate root (`host-mode.sh` D1: guard markers, finalize-gate marker, gate `state.md`). Its contents are written only by scripts, never by an agent's Write tool.

**Denied when armed (everything else), named so nobody has to guess:** the installed plugin (`${CLAUDE_PLUGIN_ROOT}` when it is outside the worktrees), every other path under `~/.claude/` (`CLAUDE.md`, `settings.json`, other projects' memory, `~/.claude/loomwright/*.json` user-scope consent and config: those are written by scripts through `Bash` + `jq`, e.g. `/telemetry enable`, which this guard never sees), other repositories, sibling lane clones (`<primary>-lanes/<run_id>/L<n>/` is a separate clone; each lane session's own clone is its W1), directories added with `--add-dir`, `$HOME` dotfiles, a host state dir set by `LOOMWRIGHT_HOST_STATE_DIR`, and `/etc`.

An unarmed session (no marker for its `session_id`) is not affected at all.

## Scope

### Part A — `loomwright/scripts/guard-path-containment.sh` (new)
- A PreToolUse command hook in the existing guards' style: bash 3.2, a top-level `set -u` line, siblings sourced from `"${BASH_SOURCE[0]%/*}"` (never from an env variable). Deny = `exit 2` plus `hookSpecificOutput.permissionDecision: "deny"` JSON; allow = exit exactly `0` with empty stdout.
- **Evaluation order (cheap first, as `guard-test-integrity.sh`):**
  1. source `host-mode.sh`; gate dir absent (`lw_gate_state_dir_existing` rc 2) or no `*.json` marker in `<gate dir>/guard/` ⇒ allow, no `jq`, no `git`;
  2. host mode on and the gate dir unresolvable (rc 1, or `host-mode.sh` not loadable with `LOOMWRIGHT_HOST_MODE=1`) ⇒ deny `path_guard_unavailable: gate state dir unresolvable`;
  3. `jq` missing, payload unparseable, `tool_input` or `session_id` absent ⇒ deny `path_guard_unavailable: <why>`;
  4. no marker for this payload's `session_id` ⇒ allow;
  5. `tool_name` not one of `Write`, `Edit`, `MultiEdit`, `NotebookEdit` ⇒ allow (the regex matcher can route another tool here; MCP and read tools are out of scope);
  6. path = `tool_input.file_path` (`notebook_path` for `NotebookEdit`); empty or absent ⇒ deny `path_guard_unavailable: no path in tool_input` (a payload-shape change must not read as "nothing to check");
  7. `contained-path-lib.sh` not loadable ⇒ deny `path_guard_unavailable: resolver missing`;
  8. a leading `~/` expands with `$HOME`; a relative path joins the anchor (`cwd`, else `CLAUDE_PROJECT_DIR`, else deny `path_guard_unavailable: no cwd`); `cpl_phys` non-zero ⇒ deny `path_unresolvable`;
  9. build W1–W4; `git worktree list` failing (not a repo, `git` missing) ⇒ deny `path_guard_unavailable: worktree roots unreadable`;
  10. inside the carve-out ⇒ deny `path_outside_worktree`; inside any of W1–W4 ⇒ allow; else deny `path_outside_worktree`.
- **Deny text:** one stderr line `path_containment_guard: denied write — <reason> — <the path as given>`, with the two `agent_type` variants of `deny_variant()` in `guard-test-integrity.sh` (subagent: record it and escalate NEEDS_HUMAN; main thread: a Loomwright run is armed in this session). It never names an env variable, the marker path or `guard-arm`.
- **No opt-out and no extra-roots knob in v1.** `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` does not disable this guard.

### Part B — wiring
- `hooks.json` PreToolUse gains one group, matcher `Write|Edit|MultiEdit|NotebookEdit`, one leaf: `type: command`, `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guard-path-containment.sh"`, `"onFailure": "block"`, **no `|| true`**, no `async`/`asyncRewake`. The existing `Write|Edit` → `guard-test-integrity.sh` group is unchanged; a deny from either hook blocks.
- `guard-test-integrity.sh`: `is_protected_basename()` adds `guard-path-containment.sh` and `contained-path-lib.sh`. No other change to that script.
- `test-guard-onfailure.sh`: the aborting-copy loop is built from the scripts named by the fail-CLOSED PreToolUse leaves in `hooks.json` (no hand list); (C), (D) and the mutation control pick the `Edit` payload for any matcher containing `Write` or `Edit`. Its (A) check that the two existing guards stay fail-CLOSED is kept; the new guard's own wiring is pinned by its own suite.

### Part C — docs and generated contracts
- `docs/HOOKS.md`: one Hook Table row (trigger, the four tools, the W1–W4 table by pointer to the script header, the carve-out, deny reasons, honest limits); §"Guard contract": one sentence that this guard shares the marker lifecycle and arm points but not the opt-out; §"Host mode": one row, class `redirects (gate)` (reads markers from the gate dir, never creates it). No count restated.
- `docs/CORE_CONTRACT.md` §2.2: one `Gate` row beside `guard-test-integrity.sh`.
- `capabilities.json` regenerated with `build-capabilities.sh`; `docs/vendor-coupling-manifest.json` gains the measured allowances (with reasons) for the two new scripts, from `check-vendor-coupling.sh --print-allowances`.
- One `changelog.d/write-path-containment-guard.md` fragment (`<!-- bump: minor -->`).

## Acceptance Criteria

Fixtures (all in the new suite `loomwright/scripts/test-guard-path-containment.sh`, sourcing `hermetic-test-env.sh`, no network, no model): a temp git repo `<main>` with one linked worktree `<wt>` (`git worktree add`), a marker `<main>/.supervisor/guard/S.json`, `CLAUDE_PROJECT_DIR=<main>`, a fake `transcript_path=<home>/.claude/projects/-x/S.jsonl`, `HOME` and `TMPDIR` relocated into the test temp dir, symlinks `<main>/out -> <outside>`, `<main>/in -> <main>/lib`, a dangling `<main>/dead`, a 41-hop chain, a stub `git` that exits 1, a `jq` stub that records calls, and a `PATH` without `jq`.

**Happy path — each allowed root**
- [ ] Given armed session `S`, when `Write file_path=<main>/src/a.ts`, `<wt>/src/a.ts`, `<main>/.supervisor/state.md` (with `cwd=<wt>`), or a relative `src/a.ts` with `cwd=<wt>` is checked, then exit 0 with empty stdout (W1). Test: `test-guard-path-containment.sh`.
- [ ] Given `Write` to `$TMPDIR/repro.x/f`, `/tmp/claude-<uid>/s/scratchpad/f` or `/private/tmp/f`, then exit 0 (W2). Test: same suite.
- [ ] Given `Write` to `dirname(transcript_path)/memory/x.md` and to `<home>/.claude/plans/p.md`, then exit 0 (W3, W4); given `Write` to `dirname(transcript_path)/S.jsonl`, then deny (only `memory/` is a root). Test: same suite.
- [ ] Given `Edit`, `MultiEdit` (`file_path`) and `NotebookEdit` (`notebook_path`) payloads naming `<wt>/n.ipynb`, then exit 0. Test: same suite.

**Denials**
- [ ] Given `Write file_path=/etc/x`, `<home>/.ssh/x`, `<main>/../other-repo/x`, `<home>/.claude/CLAUDE.md`, `<home>/.claude/loomwright/egress.json`, or `<plugin-root-outside-repo>/scripts/x.sh`, then exit 2, `permissionDecision: "deny"`, stderr names `path_outside_worktree`. Test: same suite.
- [ ] Given `Edit file_path=<main>/out/x` where `out -> <outside>`, then deny `path_outside_worktree`; given `<main>/in/x` where `in -> <main>/lib`, then allow (the physical path is judged, not the spelling). Test: same suite.
- [ ] Given `Write` to `<TMPDIR>/loomwright-host-<uid>/abc/logs/S.finalize-gate` or `/tmp/loomwright-host-<uid>/x`, then deny (carve-out). Test: same suite.
- [ ] Given `Write file_path=~/notes.txt`, then it is expanded with `$HOME` and denied. Test: same suite.

**Edge cases**
- [ ] Given `Write file_path=<main>/new/deeper/f.txt` (missing parents), then allow; given `<main>/new/../../x`, then deny `path_unresolvable`. Test: same suite.
- [ ] Given no marker for the payload's `session_id` (or no `.supervisor/guard/` at all), then every fixture above exits 0 and the `jq` and `git` stubs record no call. Test: same suite.
- [ ] Given `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1`, then `/etc/x` is still denied. Test: same suite.
- [ ] Given `tool_name` `Read` or `mcp__fake__write_file` routed to the script with a marker present, then exit 0 (out of scope, never a false deny). Test: same suite.
- [ ] Given a worktree entry whose directory was deleted (`prunable`), then writes to `<main>` still allow and nothing outside is allowed. Test: same suite.
- [ ] Given host mode (`LOOMWRIGHT_HOST_MODE=1`, valid `LOOMWRIGHT_HOST_STATE_DIR`) with the marker in `<state dir>/guard/`, then `<wt>/a` is allowed and `<state dir>/x` is denied. Test: same suite.
- [ ] Given an armed `Write` to `<main>/loomwright/scripts/guard-path-containment.sh` or `<main>/loomwright/scripts/contained-path-lib.sh`, then `guard-test-integrity.sh` denies it as a protected configuration path. Test: `test-guard-test-integrity.sh`.

**Error scenarios (fail closed)**
- [ ] Given a marker present and: the dangling symlink, the 41-hop chain, `jq` missing, an unparseable payload, `tool_input` absent, `file_path` absent, `contained-path-lib.sh` missing, the stub `git` exiting 1, or host mode with an unresolvable gate dir, then exit 2 with `path_unresolvable` or `path_guard_unavailable: <why>`, never 0. Test: same suite.
- [ ] Given `hooks.json`, then the new group's matcher is exactly `Write|Edit|MultiEdit|NotebookEdit`, its leaf has `"onFailure": "block"`, no `|| true` and no `async`. Test: same suite (wiring pin) and `test-guard-onfailure.sh` (A).
- [ ] Given `test-guard-onfailure.sh`, then (C) runs the new leaf against both a missing script and an aborting copy and each blocks, (D) shows the inert `Edit` payload exits 0 with empty stdout, and no guard script name appears in the abort-copy loop. Test: `test-guard-onfailure.sh`.
- [ ] Given mutants of the guard that (a) treat a `cpl_phys` failure as allow, (b) check the path as typed instead of physically, (c) honour `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS`, (d) drop the carve-out, (e) allow an absent `file_path`, or (f) a `hooks.json` copy with `|| true` on the new leaf, then at least one assertion fails for each. Test: same suite (mutation section).
- [ ] Given the change, then `build-capabilities.sh --check`, `test-build-capabilities.sh` (the new script's §"Host mode" row exists), `check-vendor-coupling.sh`, `check-doc-currency.sh` and `test-citation-drift.sh` pass. Tests: as named.

## Non-goals
- **The read side is REJECTED by the owner:** no guard on `Read`, `Glob`, `Grep` or `LS`. The plugin root and user-scope files live outside the repo, so a fail-closed read guard would block agents reading their own docs.
- **MCP tools (`mcp__*`) are REJECTED by the owner**, with the read side.
- A second path resolver: `contained-path-lib.sh` is reused unchanged.
- Paths inside a `Bash` command (`cp x ../other`, `cat > ~/.ssh/x`); that is the sandbox and egress work (batch B), recorded as an honest limit in the `docs/HOOKS.md` row.
- Binding each subagent to its own worktree (source OQ-H35): every worktree of the repo is allowed, so a worker can still write in a sibling worker's worktree.
- An extra-roots env variable or any opt-out (see Owner decisions).
- Unarmed sessions, a failed arm (batch F F2b) and a CLI without `onFailure` (F2c); this guard inherits those gaps like the other guards.
- Any `CLAUDE.md` or `CAPABILITY_BASELINE.json` edit, a `/rules` entry, and Studio's own path guard.

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review, narrowed to write tools; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): write tools only (`Write`, `Edit`, `MultiEdit`, `NotebookEdit`); the `Read`/`Glob`/`Grep`/`LS` side and `mcp__*` are REJECTED. Reuse `contained-path-lib.sh` (`cpl_phys` / `cpl_inside`); no second resolver. The allowed set must be explicit and tested, because a false denial halts a worker.
- Inherited (batch H constraint): a default hook in `hooks.json`, not a `/rules` entry; armed runs only (source OQ-H29).
- PO default, pending owner review — 1. The allowed write set is W1–W4 plus the gate-root carve-out above. Temp roots are read-write (the source's OQ-H33 made them read-only, but with the read side gone a write deny on `$TMPDIR` would break the `mktemp -d` repro step that workers and the Phase 4.5 reviewer run).
- PO default, pending owner review — 2. No `LOOMWRIGHT_PATH_GUARD_EXTRA_ROOTS` in v1. Settings `env` reaches hook processes, so a repo-committed `.claude/settings.json` could widen the guard for whoever runs in that repo. Alternative: a user-scope allowlist in `~/.claude/loomwright/`, as a follow-up story.
- PO default, pending owner review — 3. `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` does not disable this guard; it is about gate config, not containment (source OQ-H34).
- PO default, pending owner review — 4. `git worktree list` failing, an absent path field, an unresolvable path, or a missing resolver all deny; nothing on the armed path fails open.
- PO default, pending owner review — 5. Directories added with `--add-dir` and sibling lane clones are not write roots; the hook cannot see `--add-dir`, and lanes reach each other only through scripts.
- PO default, pending owner review — 6. A tool name the regex matcher routes here that is not one of the four write tools is allowed, not denied.

## Priority: MVP (batch H P1)
**Rationale:** every existing guard trusts the write path as typed, and armed runs are unattended by design. The write side carries the damage (a planted file in `~/.ssh`, `~/.claude/CLAUDE.md` or another repo), and it is the half that does not block agents reading their own docs.

## Assumptions
- Claude Code 2.1.317 `PreToolUse` payloads for `Write`, `Edit` and `MultiEdit` carry `tool_input.file_path`, `NotebookEdit` carries `tool_input.notebook_path`, and all carry `cwd`, `session_id` and `transcript_path`. `cwd`, `session_id` and `transcript_path` are confirmed for `Bash` in `progress-event-fixtures/guard-probe-2026-09-23/`; the write-tool field names are not. The implementer captures one payload per tool before writing the extractor, and commits them as fixtures. If `MultiEdit` no longer exists on this host, the matcher term is harmless.
- A subagent's payload carries the parent session's `session_id` and `transcript_path` (confirmed in `p2-inner-subagent-bash.json`), so one marker and one W3/W4 derivation cover the session's workers.
- Auto-memory lives at `<project dir>/memory/` and plan files at `<config dir>/plans/` under the default host settings. A user who relocates either gets a deny with the path named.
- `onFailure: "block"` blocks on a crash on 2.1.295+ (`fixtures/onfailure-block-probe.json`).

## Dependencies
- Depends on: none.
- Soft (batch F, not landed on main 8ec200e: no `audit-guard-failure-modes.sh`, `host-guard-check.sh` or `docs/guard-arm-points.json`): F2b also edits `guard-test-integrity.sh`; F2a also edits `docs/HOOKS.md` and `test-guard-onfailure.sh`. They serialise on those files; until F2b and F2c land, an unarmed run or an old CLI leaves this guard inert, like the others.
- Blocks: none.

## Risks
- **False denial of a legitimate write we did not find.** Mitigation: the allowed set is a table in the script header, each root has a test, and the deny line names the path and reason. The implementer greps `agents/`, `commands/` and `skills/` for `Write`/`Edit` to `~`, `$HOME`, `/tmp` or `${CLAUDE_PLUGIN_ROOT}` paths and lists the hits in the PR (the refresh found none: `/telemetry` writes `egress.json` through `Bash` + `jq`).
- **An interactive session stays armed until it ends.** After a `/supervisor` run, the main thread is still denied writes to `~/.claude/CLAUDE.md` or another project's memory until `SessionEnd`. Documented in the deny text and the HOOKS.md row.
- **Latency:** each armed write pays one `jq` and one `git worktree list`; the inert path pays neither.
- **Self-protection cost:** with `contained-path-lib.sh` a protected basename, a later armed run that edits it is denied; such a change needs a human session or the existing `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` for the test-integrity guard.
- **The arming check is a second copy** of `guard-test-integrity.sh`'s steps (i)–(iv). Both call the same `lw_gate_state_dir_existing` resolver, so the path rule is not restated; the script header names the copy.

## Validation (must pass before merge)
1. **Static — the new suite:** `bash loomwright/scripts/test-guard-path-containment.sh` passes, including the mutation section and the wiring pin.
2. **Static — touched suites:** `test-guard-onfailure.sh`, `test-guard-test-integrity.sh`, `test-contained-path-lib.sh`, `test-build-capabilities.sh` and `test-host-mode.sh` pass; `build-capabilities.sh --check` and `bash scripts/check-vendor-coupling.sh` pass.
3. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes (it includes `check-doc-currency.sh`, `test-citation-drift.sh` and `check-test-hermetic.sh`). `bash scripts/check-version-bump.sh` passes with the one `changelog.d/write-path-containment-guard.md` fragment; `plugin.json`, `marketplace.json` and `CHANGELOG.md` are never hand-edited.
4. **Running system — an armed run is contained:** in an armed session on Claude Code 2.1.317 with the plugin loaded (`--plugin-dir`), a `Write` to `~/.ssh/loomwright-probe`, a `Write` through a committed `out -> $HOME/elsewhere` symlink (a target outside every root, temp included), and a `Write` to `~/.claude/CLAUDE.md` are each denied with the named reason, while a `Write` in a linked worktree, a `Write` under `mktemp -d`, and an `Edit` of the main checkout's `.supervisor/state.md` succeed. Transcript excerpts and the captured payload of each write tool go in the PR.

## Depends on
none

## Touches
loomwright/scripts/guard-path-containment.sh
loomwright/scripts/test-guard-path-containment.sh
loomwright/hooks/hooks.json
loomwright/scripts/guard-test-integrity.sh
loomwright/scripts/test-guard-test-integrity.sh
loomwright/scripts/test-guard-onfailure.sh
loomwright/docs/HOOKS.md
loomwright/docs/CORE_CONTRACT.md
loomwright/capabilities.json
loomwright/docs/vendor-coupling-manifest.json
loomwright/scripts/progress-event-fixtures/guard-probe-2026-09-23
changelog.d/write-path-containment-guard.md

## Changes since the source was written
- **Narrowed to write tools (owner, 2026-11-09).** The `Read`/`Glob`/`Grep`/`LS` matcher, the `mcp__.*` leaf, the MCP key-name extraction, the read-only roots (plugin root, temp) and their ACs are removed. One group (`Write|Edit|MultiEdit|NotebookEdit`) replaces the source's two.
- **Temp became read-write** (PO default 1): the source's OQ-H33 read-only temp made sense only with the read side; on the write side it would deny the `mktemp -d` repro step. The gate-root carve-out replaces the source's reason for it (stopping planted `loomwright-host-<uid>` entries).
- **Host per-project dir narrowed** from all of `dirname(transcript_path)` (source OQ-H31) to its `memory/` subdir, so an armed agent cannot overwrite transcripts. The plans dir (W4) is added.
- **Host-mode gate dir dropped as a write root.** Only scripts write there, and the test-integrity guard already denies the Write tool there under host mode.
- **Extra-roots variable dropped** (PO default 2): `docs/HOOKS.md` records that settings `env` reaches hooks, so the variable would be repo-settable.
- **Absent path field now denies** (the source allowed "no candidate paths"), so a payload-shape change cannot silently disable the guard.
- **Base moved** from `993f8f31` (17.31.0) to `8ec200e` (17.35.1). `hooks.json`, `guard-test-integrity.sh`, `contained-path-lib.sh` and `test-guard-onfailure.sh` are unchanged. `guard-arm.sh` and `host-mode.sh` changed only in lock-wording comments, and `docs/HOOKS.md` in four rows outside the guard rows. Batch F still has not landed.
- **Touches the source missed:** `loomwright/capabilities.json` (a new hook leaf changes it; `build-capabilities.sh --check` is a CI step), the `docs/HOOKS.md` §"Host mode" row (`test-build-capabilities.sh` fails on a hook script without one), `docs/vendor-coupling-manifest.json` (new scripts carry hook-protocol tokens), `docs/CORE_CONTRACT.md` §2.2 (the guard index), and the payload-capture fixtures. `test-guard-onfailure.sh`'s hand list is only partly replaced: the abort-copy loop is derived, the existing two-guard membership check stays, and the new guard's wiring is pinned in its own suite, so adding `|| true` to the new leaf still fails a test.
