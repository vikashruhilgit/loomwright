# Unattended runs refuse to start on a Claude Code below the floor or with Loomwright's hooks not loaded (run-start config check, part 1 of 3)

## Status: pending

**As the** owner (Vikash), whose Supervisor runs, `/automate` items and `--parallel` lanes run for hours with nobody watching,
**I want** one run-start config check, `config-integrity.sh check`, that the existing Supervisor INIT and `/automate` PICK points call. In this first part it refuses an unattended run when the Claude Code CLI is older than the floor, when Loomwright's own hooks did not load in this session, or when the CLI version differs from the one I approved. It also creates the one user-scope approved-state file and the owner-terminal `approve` that parts 2 and 3 extend,
**so that** a run never starts while every fail-closed guard is silently missing (a CLI too old to honour `onFailure: "block"`, `--bare`, or the plugin not loaded), and the check, its statuses and its park points exist once before the plugin, MCP, hook and instruction legs are added.

This is part **08a** of item 08, the owner-approved single run-start config check (archive H4). It carries batch I1's CLI floor, F2c's "host can fail closed" checks and batch E P's exact CLI pin. Parts **08b** (plugins, marketplaces, MCP servers, settings hooks) and **08c** (instruction files) add legs to the same script, file and call sites. Read on `main` `8ec200e` (plugin 17.35.1).

## Problem (verified on main 8ec200e)

- None of the scripts the sources planned exist: `config-integrity.sh`, `plugin-pin.sh`, `host-guard-check.sh`, `cli-version-lib.sh`, `mcp-allowlist.sh`, `instruction-baseline.sh`, `owner-terminal-lib.sh` are all absent under `loomwright/scripts/`.
- **No runtime CLI version check.** `docs/ARCHITECTURE_CONTRACTS.md` §"Minimum Claude Code CLI version" says no manifest field can enforce a floor and gives only a prose recommendation. `docs/HOOKS.md` says a host older than 2.1.295 ignores `onFailure` and fails open. The evidence is `scripts/fixtures/onfailure-block-probe.json` (2.1.286 ran the tool, 2.1.296 blocked). No script compares the running CLI with anything.
- **No hooks-loaded check.** The SessionStart leaf (`hooks.json` → `session-resume.sh … || true; stamp-requirement-status.sh … || true`) writes no per-session "hooks are live" fact. A `--bare` session (`CLAUDE_CODE_SIMPLE=1`) or a `claude -p` without the plugin has none of the fail-closed guards, and nothing notices.
- **The call sites exist and fit.** `sn_init()` in `scripts/supervisor-next-step.sh` resolves the base, bootstraps `.supervisor/` (step 4), moves the brief `pending/` → `in-progress/` (step 6), then arms the guard (step 7). `sn_park` exists for a stopped run. The `/automate` PICK chain is `pick → lane-guard → phase-guard → ceiling → meta-push`. `ns_ceiling()` hands on with `NEXT=meta-push`, and `ns_run_park()` writes a RUN-level park that releases the run lock.
- `pause_reason` is a closed set: `CURRENT_PAUSE_ENUM` in `scripts/automate-helpers.d/runfile.sh`, restated in `docs/result-schemas/automate-run.md` (two copies), `automate-run/sections-status-queue.md`, `schema-versioning.md`, `skills/automate-loop/run-file.md`, `per-item-loop.md`, `docs/loop-inventory/automate-loop.md` and `ARCHITECTURE_CONTRACTS.md` (found by grepping `phase_relay_unavailable`, the last value added).
- This Mac runs Claude Code **2.1.319** (`claude --version`, 2026-11-09).

## Scope

### The approved-state file and `approve`
- New `loomwright/scripts/config-integrity.sh`. Its header is the single authority for the surface table (one row per host × kind × source file × key, each citing the Claude Code doc and read date), the item kinds, the statuses and the park reasons. Docs point at it.
- File: `~/.claude/loomwright/approved-config.json`, mode `0600`, `schema_version: 1`. Global sections plus `repos.<repo-key>` sections for project-scoped items. The repo key is `resolve-egress-config.sh`'s `REPO_SLUG`, so a lane clone (whose `origin` is set to the primary's URL by `automate-lanes.d/create.sh`) shares its primary's key.
- Part 1 records one item kind: `cli` (`{version}`, read from `claude --version`).
- `approve [--project <root>]` prints what would be approved (new, changed, removed items) and writes nothing. `approve … --confirm` writes the file. It refuses with `config_write_needs_owner_terminal` when `CLAUDECODE` is set or stdin is not a TTY, so a run can never approve itself. The check is a small function inside the script (no separate helper file until a second caller exists).
- A repo-relative file can only request, never grant: anything under `.supervisor/` or `.agent/` that names an approval is printed as `REPO_REQUESTED_*` and never changes a status (the `egress.json` rule).

### `check` and its first two legs
- `check [--project <root>] [--session-id <id>] [--json] [--report]` prints one `CONFIG_INTEGRITY_CHECK` v1 object. Exit 0 = `match` or `absent`; exit 1 = refuse. It runs `claude --version` (5 s timeout) and nothing else of the CLI. It never runs a hook it judges.
- **`cli` leg (not opt-in):**
  - The floor lives in one machine-readable file, `loomwright/docs/cli-floor.json`: `{schema_version: 1, min_cli: "2.1.319", why: [...]}`. `why` names the owner-set mill floor (2026-11-09) and the `onFailure: "block"` evidence (`scripts/fixtures/onfailure-block-probe.json`). No script carries the literal.
  - The comparison is inclusive and parses a suffix (`2.1.319 (Claude Code)`). Below the floor ⇒ `cli_below_min`. A hang, a non-zero exit or an unparsable string ⇒ `unreadable`, never `ok`.
  - When the approved file holds a `cli` item and the version differs ⇒ `drift` item `{kind: cli, why: changed}` (batch E P's exact pin).
  - The floor leg runs and refuses even when the approved file is absent.
- **`hooks_loaded` leg (not opt-in):**
  - `session-resume.sh` writes `.supervisor/guard/hooks-live/<session_id>` as its **first** action on every SessionStart source (startup, resume, clear, compact), before anything that can fail. Host mode uses the redirected guard dir, as `guard-arm.sh` does. Markers older than 7 days are pruned.
  - `check` reads the marker for the driver's `--session-id`. `CLAUDE_CODE_SIMPLE=1`, or no marker for this session ⇒ `hooks_not_loaded`. A missing or malformed session id ⇒ `unreadable`. The check re-reads once after 1 s before deciding, to cover marker timing in `claude -p`.
- **Status precedence** (the worst one wins): `unreadable` > `cli_below_min` > `hooks_not_loaded` > `drift` > `absent` > `match`. `absent` means no approved file: the opt-in legs proceed with one advisory line naming `config-integrity.sh approve`.
- The run never sees content: refusal lines, the session log and the run file carry kinds, names, versions, hashes and counts only.
- Every gate call appends one `config_integrity_check` line (status, per-leg results, no content) to `.supervisor/logs/<session_id>.jsonl`. The append is fail-SAFE and separate from the fail-CLOSED decision.

### Call sites (existing start points only; no new hook leaf)
1. **Supervisor INIT** (`sn_init`): after the step-4 bootstrap and **before the step-6 brief move** and the step-7 guard arm.
   - Unattended (`non_interactive` true) and exit 1 ⇒ `sn_park init failed config_integrity_<status> "<message>"`. The message names the first item and the fix (`config-integrity.sh approve` in the owner's terminal, or update the CLI). The brief stays in `pending/`.
   - Interactive: `cli_below_min` and `unreadable` still park (nobody can make an old CLI honour the key). `hooks_not_loaded` and `drift` print one warning line, record a Decisions Log entry and proceed.
2. **`/automate` PICK:** a new driver step `config-integrity` between `ceiling` and `meta-push` (`ns_ceiling` hands on to it; it hands on to `meta-push`), run at every PICK.
   - Exit 1 ⇒ `ns_run_park config-integrity config_integrity_refused "<ts> config-integrity: <status> (<first kind>:<first name>)" 1 "<message>"`: a RUN-level park, nothing picked, the run lock released, so `--resume` continues after the fix.
   - Empty or unrecognised output ⇒ treated as `unreadable` (a fail-SAFE reader feeding a gate never reads as clean).
   - `## Current` gets `config_integrity: <status>`.
   - Lanes are covered because each lane runs its own PICK and Supervisor INIT. `automate-lanes.d/launch.sh` is not edited.
3. **SessionStart advisory:** `session-resume.sh` runs `check --report` (3 s budget; on timeout it prints nothing). On any refusing status it adds one advisory line, for example "Claude Code 2.1.318 is older than the floor 2.1.319: unattended runs will refuse to start", or "config changed since you approved it: <n> items — run `config-integrity.sh approve` in your terminal". It prints this at most once per session, never refuses, and exits 0.

- `pause_reason` gains exactly one value, `config_integrity_refused`. Every copy of the closed set and every consumer is edited in the same change.
- **No override flag in v1.** The only way past `drift` is the owner-terminal `approve`, and the only way past `cli_below_min` is updating the CLI. No config key and no env var can skip it. If an override is ever added it must be an explicit `--skip-config-integrity` flag recorded in `## Run Config` and the Decisions Log.

### Docs and records
- `docs/result-schemas/config-integrity.md`: the approved-state file, `CONFIG_INTEGRITY_CHECK` v1 and the `config_integrity_check` event. Indexed in `docs/RESULT_SCHEMAS.md`; `capabilities.json` regenerated with `build-capabilities.sh`.
- `docs/result-schemas/supervisor-result.md`: the `config_integrity_<status>` park errors.
- `ARCHITECTURE_CONTRACTS.md`: §"Minimum Claude Code CLI version" gains a paragraph saying the floor is now enforced at run start, pointing at `docs/cli-floor.json` with no literal, plus one fail-closed refusal row. `docs/HOOKS.md`: the `onFailure` paragraph points at the floor file and the SessionStart row mentions the hooks-live marker.
- Loop-inventory rows (`docs/loop-inventory/supervisor.md`, `automate-loop.md`), the `per-item-loop.md` PICK bullet, the `run-file.md` `## Current` key, token budgets for any grown prompt file, and one `changelog.d/` fragment.

## Acceptance Criteria

All tests run under `hermetic-test-env.sh` with no network and no live `claude`. Fixtures: a temp `HOME`, a stub `claude` on `PATH` that logs every argv and answers `--version` with `2.1.318`, `2.1.319`, `2.1.320 (Claude Code)`, a hang, a non-zero exit or `garbage`, a temp `.supervisor/guard/`, and a TTY seam. New suite: `loomwright/scripts/test-config-integrity.sh`.

**Happy path**
- [ ] Given stub `2.1.319`, a hooks-live marker for session S and no approved file, when `check --session-id S --json` runs, then `absent`, exit 0, one advisory line naming `approve`, `cli: {floor: "2.1.319", actual: "2.1.319", status: "ok"}`, one `config_integrity_check` log line, and the stub logged only `--version`. *(test-config-integrity.sh)*
- [ ] Given stub `2.1.320 (Claude Code)`, then `ok` (suffix parsed, inclusive floor). *(test-config-integrity.sh)*
- [ ] Given an owner-terminal `approve --confirm` on stub `2.1.319`, then `approved-config.json` is mode `0600` and holds the `cli` item. When the stub then answers `2.1.320`, then `drift` with `{kind: cli, why: changed}`, exit 1. *(test-config-integrity.sh)*
- [ ] Given a SessionStart payload for session S (every source: startup, resume, clear, compact), when `session-resume.sh` runs, then `.supervisor/guard/hooks-live/S` exists and the hook exits 0, including when a later step of the script fails. *(test-session-resume.sh)*
- [ ] Given Supervisor INIT `--non-interactive` with stub `2.1.318`, then the next-step output is a park with error `config_integrity_cli_below_min`, the brief is still in `pending/`, and no guard arm, branch, worktree or spawn instruction is emitted. *(test-supervisor-next-step.sh)*
- [ ] Given `/automate` with two items and `hooks_not_loaded`, then PICK parks `pause_reason: config_integrity_refused` with a Progress line naming `hooks_not_loaded`, `## Current` shows `config_integrity: hooks_not_loaded`, the run lock is released and nothing is picked. After the fixture is fixed, `--resume` picks item 1. *(new case in loomwright/scripts/test-automate-next-step.d/)*

**Edge cases**
- [ ] Given stub `2.1.318` and **no approved file**, then `cli_below_min`, exit 1 (the floor is not opt-in). *(test-config-integrity.sh)*
- [ ] Given `CLAUDE_CODE_SIMPLE=1` with a marker present, then `hooks_not_loaded`. Given an interactive Supervisor INIT with `hooks_not_loaded`, then one warning line plus a Decisions Log entry and the run proceeds. Given stub `2.1.318` at an interactive INIT, then it parks. *(test-config-integrity.sh, test-supervisor-next-step.sh)*
- [ ] Given host mode (`LOOMWRIGHT_HOST_MODE=1`), then the marker write and the check use the redirected guard dir. Given a marker older than 7 days for another session, then it is pruned and the caller's own is kept. *(test-session-resume.sh, test-config-integrity.sh)*
- [ ] Given a drifted fixture, when `session-resume.sh` runs `check --report`, then exactly one advisory line with the count and the `approve` command, and exit 0. Given a delay seam over 3 s, then no advisory line and exit 0. *(test-session-resume.sh)*
- [ ] Given a repo `.supervisor/config.json` that names an approval, then it appears only as `REPO_REQUESTED_*` and the status is unchanged. *(test-config-integrity.sh)*

**Error scenarios**
- [ ] Given the stub hanging past 5 s, exiting non-zero or printing `garbage`, a malformed approved file, a missing or malformed `--session-id`, or `jq` missing, then `unreadable`, exit 1, and each driver parks (`config_integrity_unreadable` at INIT, `config_integrity_refused` at PICK). Never `match` or `absent`. *(test-config-integrity.sh, test-supervisor-next-step.sh, test-automate-next-step.d/)*
- [ ] Given empty output from `check` at PICK, then the driver parks as `unreadable`. *(test-automate-next-step.d/)*
- [ ] Given `CLAUDECODE=1` or a non-TTY stdin, when `approve --confirm` runs, then exit 1 with `config_write_needs_owner_terminal` and the file is unchanged. *(test-config-integrity.sh)*
- [ ] Given `pause_reason: config_integrity_refused`, then `CURRENT_PAUSE_ENUM` accepts it and every restating copy lists it; a grep leg fails when one copy lacks it. *(test-automate-next-step.d/ doc-mirror case)*
- [ ] Given `docs/cli-floor.json`, then `min_cli` is at least the newest host in `onfailure-block-probe.json` whose run shows `tool_ran: false`, and `grep -rn "2\.1\.319" loomwright/ --include=*.sh` finds nothing. *(test-config-integrity.sh)*
- [ ] Given each mutation, then at least one case fails: (a) an unreadable version treated as `ok`; (b) the floor leg skipped when the file is `absent`; (c) `|| true` added to either driver call site; (d) the marker written after a fallible step; (e) content (a full hook command or an instruction line) printed by `check`, the log or a park. *(test-config-integrity.sh)*
- [ ] Given `hooks.json`, then this change adds no leaf. *(test-config-integrity.sh)*

## Non-goals
- **I1's permission-deny `PermissionRequest` hook** (deny a tool call instead of waiting on a prompt). Deferred by the owner. The floor keeps its owner-set value without that hook's probe as evidence.
- **G1's in-run install guard** (Bash parsing of `claude mcp add`, `npx`/`uvx`, writes to `.mcp.json`). Rejected by the owner.
- **New call sites:** lane launch (`automate-lanes.d/launch.sh`), the detached drain (`dispatch-pr-review.sh`) and a pre-`gate-eval` re-check (F2c, P). Lanes are covered by their own PICK and INIT; the detached drain is not covered.
- A new hook leaf, a new preflight framework, or any change to `gate_eval()`, its seven conditions or the sole-merge-executor invariant.
- P's known-bad CLI list (`2.1.312`, `2.1.313`): the 2.1.319 floor already refuses both.
- Hashing the CLI binary.
- Adding `config-integrity.sh` to `guard-test-integrity.sh` `is_protected_basename()` (a one-line follow-up).
- Plugins, marketplaces, MCP servers and settings hooks (part 08b). Instruction files (part 08c).

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): H4 is the SINGLE run-start config check. It absorbs batch E P, G1's MCP allowlist, G2, I1's CLI floor and F2c. One user-scope approved-state file, one owner-terminal `approve`, one `check` at the Supervisor INIT and `/automate` PICK points. It fails CLOSED with named statuses for unattended runs, is advisory in the SessionStart leaf, and adds no new hook. G1's Bash-parsing install guard is rejected; I1's permission-deny hook is deferred.
- PO default, pending owner review: the item is split into three PRs (08a core + CLI floor + hooks loaded; 08b what loads; 08c instruction files) because the combined scope does not fit one PR.
- PO default, pending owner review: one floor value, `min_cli: "2.1.319"`, in `docs/cli-floor.json`. It covers both the mill floor (I1) and the `onFailure` floor (F2c), and a test keeps it at or above the probed `onFailure` evidence.
- PO default, pending owner review: the floor and hooks-loaded legs are not opt-in. The exact CLI pin is opt-in (only when an approved file exists), and an approved-CLI mismatch is `drift`.
- PO default, pending owner review: an interactive Supervisor parks on `cli_below_min` and `unreadable`, and warns and proceeds on `hooks_not_loaded` and `drift`. `/automate` PICK parks on every refusing status.
- PO default, pending owner review: no override flag in v1.
- PO default, pending owner review: no approved file ⇒ `absent`, which proceeds with an advisory line (opt-in, as P, G1 and G2 had it).

## Priority: P1
**Rationale:** an old CLI or a session without the plugin's hooks silently turns off every fail-closed guard, and nothing notices. This part also builds the file, the statuses and the two park points that 08b and 08c only add legs to.

## Assumptions
- SessionStart hooks run before the first turn in `claude -p` sessions, so the marker exists when INIT or PICK runs. The 1 s re-read covers small delays; the running-system validation confirms it.
- The driver's `--session-id` equals the SessionStart payload's `session_id` for the same session (`guard-arm.sh` relies on the same identity). The running-system validation confirms it.
- `CLAUDE_CODE_SIMPLE=1` reaches the Bash tool of a `--bare` session (from `claude --help`). `--safe-mode` is covered by the missing marker either way.
- **Honest limit:** a compromised CLI can lie about its version, and a check run inside it can be lied to. The check catches old, bare and plugin-less hosts, not a hostile one.

## Dependencies
- Depends on: none.
- Blocks: 08b and 08c (they add legs to this script, file and call sites).
- Soft: the H2 sign-in-expiry story (pending) would add a PICK step next to this one; whichever lands second serialises on `automate-next-step.sh`, `supervisor-next-step.sh` and the `pause_reason` copies.

## Risks
- **Every CLI auto-update parks unattended runs** once an approved file pins the CLI version, until the owner re-runs `approve`. The SessionStart advisory warns before a run.
- **Floor on every install:** the plugin is public, so a 2.1.319 floor refuses unattended runs for every user on an older CLI. Intended, but say so in the changelog fragment.
- **False `hooks_not_loaded`** if the marker write fails or arrives late. Mitigation: the marker is written first, the check re-reads once, and interactive runs only warn.
- **Mirror drift** across the `pause_reason` copies. Mitigation: the grep leg plus the house rule that a restating copy changes with its authority.

## Validation (must pass before merge)
1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, including `loomwright/scripts/test-config-integrity.sh`, `test-session-resume.sh`, `test-supervisor-next-step.sh`, the new `test-automate-next-step.d/` case, `build-capabilities.sh --check`, `check-doc-currency.sh`, `test-citation-drift.sh`, `check-token-budget.sh`, `check-prompt-history-refs.sh` and `check-test-hermetic.sh`.
2. **Static — release:** one `changelog.d/` fragment, version files never hand-edited, and `bash scripts/check-version-bump.sh` passes.
3. **Running system — a bare session is refused:** on this Mac (2.1.319), a live `claude -p --plugin-dir <checkout>/loomwright` session with `CLAUDE_CODE_SIMPLE=1` running `/loomwright:supervisor --non-interactive` on a scratch brief parks at INIT with `config_integrity_hooks_not_loaded`, while the same session without that variable passes the check (proving the marker and session-id assumptions). Excerpts go in `docs/evidence/config-integrity.md` with `Verdict: PASS for Validation 3`.
4. **Running system — PICK park:** a live `/loomwright:automate --backlog <one-item fixture> --non-interactive-fallback` run against an approved file whose `cli` item is edited to `2.1.318` parks `pause_reason: config_integrity_refused` before anything is picked, and `--resume` after `approve --confirm` picks the item. Recorded in the same evidence file with `Verdict: PASS for Validation 4`.

## Depends on
none

## Touches
loomwright/scripts/config-integrity.sh
loomwright/scripts/test-config-integrity.sh
loomwright/scripts/fixtures/config-integrity
loomwright/docs/cli-floor.json
loomwright/scripts/session-resume.sh
loomwright/scripts/test-session-resume.sh
loomwright/scripts/supervisor-next-step.sh
loomwright/scripts/test-supervisor-next-step.sh
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.d/16-config-integrity.sh
loomwright/scripts/automate-helpers.d/runfile.sh
loomwright/docs/result-schemas/automate-run.md
loomwright/docs/result-schemas/automate-run/sections-status-queue.md
loomwright/docs/result-schemas/schema-versioning.md
loomwright/docs/result-schemas/supervisor-result.md
loomwright/docs/result-schemas/config-integrity.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/capabilities.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/HOOKS.md
loomwright/docs/loop-inventory/supervisor.md
loomwright/docs/loop-inventory/automate-loop.md
loomwright/skills/automate-loop/per-item-loop.md
loomwright/skills/automate-loop/run-file.md
loomwright/docs/prompt-token-budgets.json
docs/evidence/config-integrity.md
changelog.d/config-check-core-cli-floor-hooks-loaded.md

## Changes since the sources were written
- Nothing from any source has shipped on main `8ec200e` (17.35.1). Every planned script is absent.
- The box's CLI is now 2.1.319 (H4 and I1 recorded 2.1.319; P 2.1.316; G 2.1.318; F 2.1.317).
- The PICK chain now has `phase-guard` between `lane-guard` and `ceiling`. The new step still sits after `ceiling`.
- The evidence directory is the root `docs/evidence/`, not `loomwright/docs/evidence/` as H4's Touches had it.
- `docs/result-schemas/supervisor-result.md` lists park errors and is now in Touches (missing from the sources).
- Merged from the sources: F2c's separate `host-guard-check.sh` and `--skip-host-guard-check` flag, P's `plugin-pin.sh` and I1's `permission-deny-probe.json` floor fixture all collapse into this one script and one floor file.
