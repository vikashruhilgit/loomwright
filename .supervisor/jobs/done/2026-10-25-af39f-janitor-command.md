# Supervisor Job: `/janitor` — one read-only report of everything the plugin left running or lying around, then act only on the rows the owner picks (af/39f)

## Environment
- **Project:** L8 (the `automate-2026-10-22-123646` lane checkout of `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (a stale `.supervisor/run.lock` from this lane's own coordinator session, pid dead — not a blocker for planning; Supervisor's own lock handling applies)
- **Source requirement:** .supervisor/requirements/automate-followups/39f-janitor-command.md
- **Base commit:** ec67b67652390f9843d032379b486df289cbaaa4

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash 3.2 + jq scripts and Markdown command docs, the same stack as every sibling (`backlog.md` + `automate-helpers.d/backlog.sh`) |
| 2 | Dependency Availability | GO | Every reader exists at base: `proc-registry.sh` (39e, merged), `automate-helpers.sh sweep` (39a; it already runs `worktree-salvage.sh --check-ignored` per worktree), `lane-status --leaks`, `run-lock.sh status`, `ci-slot.sh status`, `retention-sweep.sh` (report mode), `automate-helpers.sh config-restore`, `lane-remove`, `meta-sync.sh` |
| 3 | Architecture Fit | CAUTION | 39e's registry only COUNTS unregistered look-alikes (`summary --scan`); it has no per-row listing and no guarded stop for an unregistered pid. Owner decision (Launch Pad, 2026-10-25): extend `proc-registry.sh` with `list --scan` + `stop-unregistered` rather than re-derive the predicate in janitor |
| 4 | Scope vs Supervisor Capability | CAUTION | 18 files (> 12) once the validator-owned surfaces are counted ⇒ `context-bound` split into 2 dependency-ordered subtasks |
| 5 | Hard Blockers | GO | None. The dependency (39e) is on `main` |

**Overall Verdict:** CAUTION

## Task
**Goal:** Ship `/janitor`: a new `janitor-report.sh` that prints one grouped, read-only report (registered + unregistered processes, run locks, lanes, worktrees and branches, stale run state, plus report-only "plugin-adjacent" and "not the plugin's" groups) with a suggested action per row, and a command doc that, in an interactive session only, executes the rows the owner picks — each through its existing guarded helper after a re-check.

**Problem Statement:**
The owner needs to see, in one place, every background process and leftover the plugin started, because today each mechanism is tracked separately (merge-watch markers, run lock TTL, drain `.died` markers, lane tables) and nothing shows them together.
Currently the owner finds strays with a hand-run `ps` (2026-10-04: 3 leaked Floor fixture servers, a 27-day-old Python server, an old-code merge watcher) and kills them by hand after re-checking each command line. This costs time and risks killing the wrong process.
Success looks like `/janitor` listing each such item exactly once with owner, age, state, evidence and a suggested action, changing nothing unless the owner picks a row, and stopping exactly the picked row after a command-line re-check.

**Owner decisions (Launch Pad, 2026-10-25):**
- `/janitor` **wraps** `lane-status --leaks` (both stay). Janitor calls only the compare mode `lane-status <parent_runfile> --leaks`, **never `--snapshot`** (`--snapshot` WRITES `<run_id>.leaks-snapshot`, `automate-lanes.d/park-leaks.sh` `lanes_leaks`). With no wave-start snapshot the row reads `leaks: unknown — no snapshot`, shown as-is.
- **Extend `proc-registry.sh`**: `list --scan` lists one `unregistered` row per look-alike using the SAME predicate `summary --scan` counts (one implementation, not a copy), and `stop-unregistered` is the guarded stop for an owner-picked unregistered pid.
- README.md and CLAUDE.md (named in the requirement's Touches) carry no command list or restated command count at base (`git grep` of `Slash commands (N)` / `N slash commands` hits only the two manifest descriptions), so they are not edited. The house rule "a count lives in one authoritative place" applies: the manifests' description counts are updated in place, and no new restated count is added anywhere.

## Acceptance Criteria
- [ ] AC1 (Subtask 1) — Given a registry and a process snapshot with ≥1 unregistered look-alike, when `proc-registry.sh list --scan` runs, then after the registry rows it prints one row per look-alike in the same TSV columns (`id` = `unreg-<pid>`, `kind` = `unregistered`, `pid`, `age`, `class` = `unregistered`, `evidence` naming the matching rule — plugin script path or gone temp python script — plus the pid's `lstart` and command-line hash), the number of `unregistered` rows equals `summary --scan`'s `<u>` on the same snapshot, `list` without `--scan` is byte-identical to base, the registry checksum is unchanged, and the scan predicate exists ONCE in the file (the pinned literals `[ "$age" -gt "$min" ] || continue`, `ex="$ex$p "`, `! _pr_live_ancestor "$pid" "$live" || continue` and `_pr_in_tmp "$path" && [ ! -e "$path" ]` each still occur on exactly one line).
- [ ] AC2 (Subtask 1) — Given an unregistered look-alike, when `proc-registry.sh stop-unregistered --pid <p> --start <lstart> --hash <cmd_hash>` runs without `--apply`, then it prints what it would do and sends no signal; with `--apply` it re-reads the live `lstart` and command-line hash immediately before TERM and again before KILL (the same `_pr_matches` re-check `reap` uses), signals only when both still match AND the pid still satisfies the scan predicate, and refuses (exit 0, one `not signalled: <reason>` line, no signal) a pid that is a live registry entry, a descendant of one, recycled (lstart or hash differs) or gone; a bad argument is a usage error (exit 2); one line is appended to `reap.log`.
- [ ] AC3 (Subtask 1) — Given `test-proc-registry.sh`, then new legs cover AC1 and AC2 and new mutation controls turn them red: deleting `list --scan`'s own row print (against an absolute row count), deleting the `stop-unregistered` hash re-check (against a recycle into a command line that still satisfies the predicate), deleting the live-entry refusal, and dropping the scan-predicate gate inside `stop-unregistered` (against a matching-hash non-look-alike) — each mutant targets a line only its own path uses; every pre-existing mutation control still gates on exactly one changed line and stays red.
- [ ] AC4 (Subtask 2) — Given a hermetic fixture reproducing the 2026-10-04 machine state — a leaked fixture server (an unregistered look-alike), an old merge watcher (a registry entry past its `max_lifetime_s`), a dead run-lock holder, and a merged clean plugin-made worktree (a PATH-stub `gh` reporting its branch's newest PR MERGED at the tip) — when `janitor-report.sh` runs, then each item appears exactly once with group, owner, age, state, evidence and a suggested action with its reason, it exits 0, and a checksum of the registry dir, every run lock, `git worktree list --porcelain` and `git for-each-ref refs/heads` is identical before and after.
- [ ] AC5 (Subtask 2) — Given the same fixture, when `janitor-report.sh --json` runs, then it prints ONE JSON object (`schema_version: 1`, `groups[]`, each row carrying `id`, `group`, `what`, `owner`, `age_s`, `state`, `evidence`, `action`, `reason`) with the same rows as the text table.
- [ ] AC6 (Subtask 2) — Given rows in the "not the plugin's" group (a process matching neither the registry nor the scan predicate, e.g. the host's background sessions) and the "plugin-adjacent" group (`ci-slot.sh status` holders, a keep-awake `caffeinate`), then each row's action is `none` (report-only, naming the native way to close it), and `janitor-report.sh act --confirm <that id>` refuses it with no signal.
- [ ] AC7 (Subtask 2) — Given the non-interactive path (`janitor-report.sh act` without `--confirm`, or with `--report`, or with `CI` set), when it runs on the fixture, then it acts on nothing (same checksum as AC4), prints `janitor: report only — <reason>` and exits 0; a mutation control that deletes that guard turns the leg red.
- [ ] AC8 (Subtask 2) — Given the owner picks the leaked fixture server row, when `janitor-report.sh act --confirm <row id>` runs, then it re-checks that row through its reader (`proc-registry.sh stop-unregistered … --apply` with the row's recorded lstart and hash), stops exactly that process (a second fixture process stays alive), prints what it did and a fresh one-line summary, and the next report no longer lists it; given the pid was recycled between report and act to another command line that still satisfies the scan predicate, it is not signalled (the recycle must keep the predicate true so only the lstart/hash re-check can refuse it).
- [ ] AC8b (Subtask 2) — Given a run lock whose recorded holder is dead and whose age is ≥ 1800s, when the owner picks its `lock-reclaim` row and `janitor-report.sh act --confirm <row id>` runs, then the lock is gone afterwards (`run-lock.sh status` prints `UNLOCKED`), janitor holds no lock, and a lock whose holder is alive, or that is younger than 1800s, is refused by `act --confirm` with no change.
- [ ] AC9 (Subtask 2) — Given `/janitor` (`loomwright/commands/janitor.md`), then the doc only renders `janitor-report.sh` output and runs the owner question: interactive ⇒ one multi-select ask with `header: "JAN-ACT"`, options = the actionable rows grouped, nothing pre-selected, `--force-unlock` only after a second `JAN-ACT` confirmation; can't-ask (`--report`, `--non-interactive`, a headless print-mode session, or the prose running in a subagent) ⇒ report only, exit 0, never act. `JAN-ACT` is a `human-only` free-text row in `lane-policy.sh catalog`, `docs/LANE_GATES.md` is regenerated with `lane-policy.sh catalog --markdown`, `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" gains its row (contexts MI; HP; SA; can't-ask = report only, nothing acted on), and `bash loomwright/scripts/check-gate-headers.sh` passes.
- [ ] AC10 (Subtask 2) — Given the new command, then `commands/agent-help.md` gains a `### 🧹 /janitor — …` section pointing at `docs/command-parts/agent-help/ops.md` (which gains the detail entry and lists `/janitor` in agent-help's split index line), `prompt-token-budgets.json` gains `.commands.janitor` (measured + ~10%) with its mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", `loomwright/capabilities.json` is regenerated by `build-capabilities.sh`, `prompt-history-refs-baseline.json` gains the `commands/janitor.md` entry without the baseline total rising, `vendor-coupling-manifest.json` gains a reasoned allowance only if `check-vendor-coupling.sh` counts a token in a new file, and the two manifest descriptions' command count is updated in place (24 → 25) — `bash scripts/check-doc-currency.sh`, `bash scripts/check-token-budget.sh`, `bash scripts/check-prompt-history-refs.sh`, `bash loomwright/scripts/build-capabilities.sh --check`, `bash scripts/check-vendor-coupling.sh` and `bash loomwright/scripts/test-citation-drift.sh` all pass (every command here is repo-root-relative).
- [ ] AC11 (Subtask 2) — Given the running system, then a committed evidence file `docs/evidence/af39f-janitor-report.md` contains the output of `janitor-report.sh` (the `/janitor --report` path) on the developer machine with home paths written as `/Users/<name>/`, and an `## Interactive run` section recording either the owner's one picked harmless row (or none) and what changed, or the literal `pending — owner run at review`; the PR body links to it.
- [ ] AC12 (Subtask 2) — Given the branch, then `changelog.d/af39f-janitor-command.md` exists (`<!-- bump: minor -->`, a headline, a prose body), no version file is hand-edited, and `bash scripts/check-version-bump.sh` passes.
- [ ] AC13 (both) — Given the branch, then `bash scripts/ci-local.sh` is green, including `test-janitor-report.sh` and `test-proc-registry.sh`.

**Evidence rule:** AC11's evidence lives in the committed `docs/evidence/af39f-janitor-report.md` (a File Impact Map create, in Subtask 2's `lanes:`), never only in the PR body.

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| registry (Subtask 1) | `loomwright/scripts/proc-registry.sh`, `loomwright/scripts/test-proc-registry.sh` | — | HIGH |
| janitor (Subtask 2) | — | `loomwright/scripts/janitor-report.sh`, `loomwright/scripts/test-janitor-report.sh`, `loomwright/commands/janitor.md` | HIGH |
| gate (Subtask 2) | `loomwright/scripts/lane-policy.sh`, `loomwright/docs/LANE_GATES.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | — | HIGH |
| command surfaces (Subtask 2) | `loomwright/commands/agent-help.md`, `loomwright/docs/command-parts/agent-help/ops.md`, `loomwright/docs/prompt-token-budgets.json`, `loomwright/docs/prompt-history-refs-baseline.json`, `loomwright/capabilities.json`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |
| vendor ratchet (Subtask 2) | `loomwright/docs/vendor-coupling-manifest.json` (only if the gate counts a token in a new file) | — | MEDIUM |
| release + evidence (Subtask 2) | — | `changelog.d/af39f-janitor-command.md`, `docs/evidence/af39f-janitor-report.md` | HIGH |

> **Validator-owned surfaces:** `lane-policy.sh` + `LANE_GATES.md` (`check-gate-headers.sh`, `test-lane-policy.sh`), `prompt-token-budgets.json` + its `ARCHITECTURE_CONTRACTS.md` mirror (`check-token-budget.sh`), `prompt-history-refs-baseline.json` (`check-prompt-history-refs.sh`), `capabilities.json` (`build-capabilities.sh --check`), `vendor-coupling-manifest.json` (`check-vendor-coupling.sh`), the two manifest descriptions (`check-doc-currency.sh`). README.md and CLAUDE.md carry no command list or count (checked at base) and are not edited.

**Total estimated files:** 13 modify + 5 create = 18.

## Touched-file invariants

> Grounded at base `ec67b67652390f9843d032379b486df289cbaaa4`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/proc-registry.sh`** — keep: the header IS the contract (`This header IS the contract (no other doc restates`) — document `list --scan` and `stop-unregistered` there, including their exit codes in the `# EXIT CODES:` line; NEVER SIGNAL BY PID ALONE (`NEVER SIGNAL BY PID ALONE. Every TERM and every KILL is preceded`) — `stop-unregistered` re-checks with `_pr_matches` before TERM and before KILL, the same rule `_pr_stop` follows (`_pr_matches "$E_PID" "$E_START" "$E_HASH" || nokill="$PR_WHY"`) — but by SHARING, never copying: factor `_pr_stop`'s TERM → wait → re-check → KILL sequence into one helper that both `_pr_stop` and `stop-unregistered` call, so the pinned `|| nokill="$PR_WHY"` line stays the single place the pre-KILL re-check lives; `stop-unregistered`'s own pre-TERM `_pr_matches` check (and its refusal of a live-entry pid or a pid failing the predicate) sits on lines unique to it, so the Pin mutations rows below have their own targets and never delete reap's; `list` stays read-only and exit 0 (`Read-only: creates nothing, changes nothing. ALWAYS exits 0`); the hermetic scan skip (`# >>> hermetic scan skip`) also gates `list --scan`; the dispatch `case "$sub" in` stays the one subcommand list (`reap) cmd_reap "$@"; exit $? ;;`) and `pr_usage` lists every subcommand. Reuse: ONE snapshot per call (`_pr_snapshot`); `_pr_unreg_count`'s predicate refactored into a row emitter that both `summary --scan` and `list --scan` (and `stop-unregistered`'s predicate check) consume — never a second copy; likewise the live-entry set built in `cmd_summary` (`[ "$E_CLASS" = finished ] || live="$live$E_PID "`) is factored into ONE helper that `summary --scan`, `list --scan` and `stop-unregistered` call, never copied; `_pr_log` for the reap.log line. Today `cmd_list` warns and ignores arguments (`list takes no arguments (ignored: %s)`) — `--scan` becomes the one accepted flag, anything else keeps that warning. Pinned by: `test-proc-registry.sh` mutation controls. The `del` controls (`ex="$ex$p "`, `! _pr_live_ancestor "$pid" "$live" || continue`, `[ "$E_CLASS" = finished ] || live="$live$E_PID "`, `|| nokill="$PR_WHY"`) require their literal on exactly ONE line (`gate_mutant` fails a `del` mutant that removes more than one line) — hence the sharing rule above. The `sub` controls (`[ "$age" -gt "$min" ] || continue`, `_pr_in_tmp "$path" && [ ! -e "$path" ]`, `local files f n=0 nr=0`) replace the first occurrence per line and do not gate on line count; keeping them single-occurrence is the design choice that keeps the predicate in one place, not a gate requirement. Every existing control must still turn its leg red after the refactor (if a control's needle moves into a shared helper, update the control's needle in the same change so it still mutates the shared code).
- **`loomwright/scripts/test-proc-registry.sh`** — keep: every leg isolated under its own `LOOMWRIGHT_PROC_REGISTRY_DIR` and sourcing `hermetic-test-env.sh`; the AC header block at the top lists every leg's AC (add header lines for the new legs, named `leg_list_scan`, `leg_stop_unreg` and `leg_stop_unreg_recycled` — never by a bare AC number, which would collide with this brief's AC12/AC13); new mutation controls use the existing `mk_mutant` / `run_mutant` harness (`gate_mutant <label> — the lesson-fa32a308 gate`), never a hand-rolled sed; the final line `test-proc-registry.sh: $pass passed, $fail failed`.
- **`loomwright/scripts/lane-policy.sh`** — keep: `lp_catalog()` is the ONE authority (`_lp_row BL-VERIFY    human-only`); a code is ≤ 12 characters; a free-text gate's labels are the literal `(free text)` (as `_lp_row LP-CLARIFY`'s row prints). Mirror: `docs/LANE_GATES.md` §"Catalog" is regenerated with `lane-policy.sh catalog --markdown`, never hand-edited (`test-lane-policy.sh` parses it back and fails on drift). Fired by: `scripts/check-gate-headers.sh` G2 (`every \`header: "<CODE-shaped>"\` names a catalog code`) and G5 (`every catalog code has at least one`) — the new code needs its `header: "JAN-ACT"` ask site in `commands/janitor.md`.
- **`loomwright/docs/prompt-token-budgets.json`** — keep: `.commands.<stem>` entries are `{"budget": N, "measured": M, "note": "<one line>"}` like `"backlog": {"budget": 2413, "measured": 2194`; mirror: the `| \`backlog\` | 2413 | 2194 |` row shape in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" (`check-token-budget.sh` fails CLOSED on a missing, drifted or ghost row). The command doc's weight counts `docs/command-parts/janitor/` too if one is created (none is planned).
- **`loomwright/docs/prompt-history-refs-baseline.json`** — keep: one entry per scanned file, zero included (`"loomwright/commands/backlog.md": 0`); the baseline may only go down and its TOTAL may not rise (`baseline total rose: <base> -> <now>` in `scripts/check-prompt-history-refs.sh`) — `commands/janitor.md` carries no history references, so its entry is `0`.
- **`loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`** — keep: edit ONLY the `24 slash commands` token inside each `description` (→ `25 slash commands`), in place; never the `version` field (`bump-version.sh --check`, run by `scripts/check-version-bump.sh`, requires the versions to equal the base's while only a fragment is pending — this lane PR never bumps); each description stays ≤ 600 characters with at most one `vX.Y.Z`-shaped token (`scripts/check-doc-currency.sh`, `check_count '[0-9]+ slash commands'`).
- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: a per-path allowance plus a one-line reason in the reasons map, the shape of `"loomwright/commands/backlog.md": 1` and its `"new command (parallel-automate/18a): ONE install_root reference…"` reason; add an entry only for a new file the gate (`scripts/check-vendor-coupling.sh`, fails CLOSED when a count rises without a reasoned allowance) actually counts, with the measured count.
- **`loomwright/capabilities.json`** — generated: never hand-edit; regenerate with `bash loomwright/scripts/build-capabilities.sh` (CI step `Check the capability contract is current (capabilities.json staleness gate)` runs `--check`).
- **`loomwright/commands/agent-help.md`** — keep: every command has a `### <emoji> /<cmd> ` heading in this file (`grep -qE "^### .*/${cmd} "` in `scripts/check-doc-currency.sh`); split sections point at their part file (`See [../docs/command-parts/agent-help/ops.md]`) and the split index line (``- `ops.md` — `/telemetry`, `/rules`, `/pr-postmortem`, `/autonomous`, `/backlog`.``) names every command in the part.

## Closed enumerations touched

> Sibling grep at base `ec67b67`: `git grep -nF 'BL-VERIFY' -- ':!CHANGELOG.md'` → 7 hits in 5 files.

- **`JAN-ACT`** (sibling: `BL-VERIFY`) — must be named in:
  - `loomwright/scripts/lane-policy.sh` — the catalog `_lp_row` list (`_lp_row BL-VERIFY    human-only`) — extend.
  - `loomwright/docs/LANE_GATES.md` — the `## Catalog` mirror table (`| \`BL-VERIFY\` | human-only |`) — extend (regenerated).
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — §"Question-gate inventory" row (`/backlog --verify\` per-item stamp (\`BL-VERIFY\``) — extend with a `/janitor` row.
  - `loomwright/commands/janitor.md` — the ask site (`header: "JAN-ACT"`) — create.
  - `loomwright/commands/backlog.md` — backlog's own ask sites — no change: a per-command ask site, not a list of gates.
  - `loomwright/docs/command-parts/agent-help/ops.md` — backlog's usage line — no change: names only its own gates.

> Sibling grep at base `ec67b67`: `git grep -c 'commands/backlog.md\|"backlog"\|\`backlog\`' -- ':!CHANGELOG.md' ':!.supervisor'` → 13 files.

- **`janitor`** (command; sibling: `backlog`) — must be named in:
  - `loomwright/capabilities.json` — `commands[]` (`"name": "backlog"`) — extend (regenerated).
  - `loomwright/docs/prompt-token-budgets.json` — `.commands` (`"backlog": {"budget": 2413`) — extend.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — the command budget mirror (`| \`backlog\` | 2413 | 2194 |`) — extend.
  - `loomwright/docs/prompt-history-refs-baseline.json` — `files` (`"loomwright/commands/backlog.md": 0`) — extend.
  - `loomwright/docs/command-parts/agent-help/ops.md` + `loomwright/commands/agent-help.md` — command reference — extend.
  - `loomwright/docs/vendor-coupling-manifest.json` — per-path allowances (`"loomwright/commands/backlog.md": 1`) — extend ONLY if `check-vendor-coupling.sh` counts a token in `commands/janitor.md` or `scripts/janitor-report.sh` (then with a one-line reason like backlog's).
  - `loomwright/commands/backlog.md`, `loomwright/scripts/fixtures/backlog-state/README.md` — no change: backlog's own files.
  - `loomwright/scripts/automate-helpers.sh`, `automate-helpers.d/intake.sh`, `skills/automate-loop/helpers.md`, `skills/automate-loop/intake.md` — no change: "backlog" there is the `/automate` backlog-doc source kind, not the command.

- **`stop-unregistered`** (proc-registry subcommand; sibling: `reap`) — must be named in `loomwright/scripts/proc-registry.sh`'s dispatch `case` (`reap) cmd_reap "$@"; exit $? ;;`), its `pr_usage` heredoc (`proc-registry.sh reap [--apply] [<id>...]`) and its header SUBCOMMANDS / EXIT CODES — extend all three.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-proc-registry.sh` — `leg_list_scan` (asserts the ABSOLUTE row count — exactly the N look-alikes its `LOOMWRIGHT_PROC_PS_SNAPSHOT` fixture holds, N ≥ 1 — and that it equals summary's `<u>`) | delete the `unregistered` TSV row print in `cmd_list`'s `--scan` branch in `loomwright/scripts/proc-registry.sh` — list's own formatting line, which `summary` does not use (the leg sees 0 rows ≠ N) |
| `test-proc-registry.sh` — `leg_stop_unreg_recycled` (the fixture execs into a DIFFERENT command line that STILL satisfies the scan predicate — a second script under the same temp `…/loomwright/scripts/` path, `LOOMWRIGHT_PROC_UNREG_MIN_S=0`, etime ≥ 1s — so only the lstart/hash re-check can refuse it; never `leg_recycled`'s `exec sleep` pattern, which the predicate gate would refuse first) | delete the `_pr_matches` re-check line before TERM in `stop-unregistered` in `loomwright/scripts/proc-registry.sh` |
| `test-proc-registry.sh` — `leg_stop_unreg` (refuses a live registry entry's pid whose lstart and hash match) | delete the live-entry refusal line in `stop-unregistered` in `loomwright/scripts/proc-registry.sh` |
| `test-proc-registry.sh` — `leg_stop_unreg_nonlookalike` (refuses an unregistered pid with a matching lstart and hash that fails the scan predicate, e.g. a plain `sleep`) | delete the scan-predicate refusal line in `stop-unregistered` in `loomwright/scripts/proc-registry.sh` |
| `test-janitor-report.sh` — non-interactive guard leg (brief AC7) | delete the `janitor: report only` guard line of `act` in `loomwright/scripts/janitor-report.sh` |
| `test-janitor-report.sh` — not-the-plugin's no-action leg (brief AC6) | flip the `none` action of the not-the-plugin's group to `stop-unregistered` in `loomwright/scripts/janitor-report.sh` |
| `test-janitor-report.sh` — read-only checksum leg (brief AC4) | add a write into the registry dir in the report path of `loomwright/scripts/janitor-report.sh` (a `sub` mutant, as `test-proc-registry.sh`'s `sumtouch` control does) |

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

## Design notes (binding for Subtask 2)

- `loomwright/scripts/janitor-report.sh [--json] [--root <checkout>]` and `janitor-report.sh act [--confirm] [--report] [--root <checkout>] <row id>...`. The header is the contract (groups, row fields, the closed action set, exit codes). The report path is a fail-SAFE observer: always exit 0, a reader that fails or is absent yields one row `state: unknown — <reader> <why>` in its group, never a guess and never "clean"; usage errors exit 2.
- Rows come ONLY from existing readers, run once each: `proc-registry.sh list --scan` (processes); `run-lock.sh status --root <checkout>` for the primary and each lane under `<primary>-lanes/*` (locks; a dead holder flagged); `automate-helpers.sh lane-status <parent_runfile> --leaks` for each parent run that has a `.lanes` table (lanes; compare mode only); `automate-helpers.sh sweep --root <primary>` dry run (worktrees and branches; it already runs `worktree-salvage.sh --check-ignored`, so a worktree is removable only when sweep says `would-remove`); `retention-sweep.sh --project-root <primary>` report mode plus stranded `*.config-backup.json`, `<run_id>.merge-watch` markers whose watcher is gone and `*.meta-push-failed` markers under `.supervisor/automate/` (stale run state); `ci-slot.sh status` and a keep-awake `caffeinate -i -w` from the registry's one snapshot (plugin-adjacent, report-only).
- The closed action set and its ONLY executors: `reap` → `proc-registry.sh reap --apply <id>`; `stop-unregistered` → `proc-registry.sh stop-unregistered --pid --start --hash --apply`; `sweep-apply` → `automate-helpers.sh sweep --apply --root <primary>` (honest limit: sweep has no per-path filter, so this row applies the whole sweep — the ask labels it that way); `lane-remove` → `automate-helpers.sh lane-remove <lane_dir>`; `lock-reclaim` → offered only for a lock whose `run-lock.sh liveness --root <c>` prints `dead` AND whose `status` age is ≥ 1800s (`run-lock.sh` has no reclaim subcommand: reclaim happens inside `acquire`, and only on a dead holder at that age). `act` re-reads `liveness --pid <recorded pid> --root <c>` and `status` immediately before, then runs `run-lock.sh acquire --owner human:janitor --root <c>` immediately followed by `run-lock.sh release --owner human:janitor --root <c>`, so janitor never keeps the lock; a refused acquire is reported and nothing else is attempted. A lock that is NOT reclaimable (live holder, or younger than 1800s) gets action `none` with that reason; `run-lock.sh release --force-unlock --owner human:janitor --root <c>` is offered only for a dead-holder lock under 1800s, and runs only after a SECOND `JAN-ACT` confirmation. A hermetic leg covers the dead-holder ≥ 1800s reclaim (AC8b); `config-restore` → `automate-helpers.sh config-restore`; `none` (report-only). `act` re-runs the row's reader immediately before acting and refuses a row whose state changed.
- `act` never runs unless `--confirm` is passed (the command doc passes it only after the owner's `JAN-ACT` answer) and never under `--report` or a set `CI`; that guard lives in `janitor-report.sh` so a test can mutate it.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Registry: `list --scan` rows + guarded `stop-unregistered` | AC1, AC2, AC3, AC13 | 2 modify, 0 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | `/janitor`: report script, command doc, gate, docs, evidence, fragment | AC4–AC13 (incl. AC8b) | 11 modify, 5 create | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "stop-unregistered"}
  - {kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "list --scan"}
  - {kind: "symbol", path: "loomwright/scripts/test-proc-registry.sh", name: "stop-unregistered"}
requires: []
lanes:
  - "loomwright/scripts/proc-registry.sh"
  - "loomwright/scripts/test-proc-registry.sh"
external_requires:
  - "jq and ps (BSD and procps), bash 3.2"
```

```yaml
# Subtask 2
provides:
  - {kind: "file", path: "loomwright/scripts/janitor-report.sh"}
  - {kind: "file", path: "loomwright/scripts/test-janitor-report.sh"}
  - {kind: "file", path: "loomwright/commands/janitor.md"}
  - {kind: "symbol", path: "loomwright/commands/janitor.md", name: "JAN-ACT"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "JAN-ACT"}
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "janitor"}
  - {kind: "symbol", path: "loomwright/commands/agent-help.md", name: "/janitor"}
  - {kind: "file", path: "docs/evidence/af39f-janitor-report.md"}
  - {kind: "file", path: "changelog.d/af39f-janitor-command.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "stop-unregistered"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/proc-registry.sh", name: "list --scan"}
lanes:
  - "loomwright/scripts/janitor-report.sh"
  - "loomwright/scripts/test-janitor-report.sh"
  - "loomwright/commands/janitor.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/command-parts/agent-help/ops.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/LANE_GATES.md"
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/prompt-history-refs-baseline.json"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/capabilities.json"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "docs/evidence/af39f-janitor-report.md"
  - "changelog.d/af39f-janitor-command.md"
external_requires:
  - "gh (stubbed on PATH in tests; the sweep reader calls it)"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (Subtask 2 only reads `proc-registry.sh`) | YES — by `requires` |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): 39e's registry only counts unregistered look-alikes; janitor needs rows and a stop | MEDIUM | Subtask 1 extends `proc-registry.sh` (owner decision); the predicate is refactored into ONE emitter so `summary --scan` and `list --scan` cannot diverge |
| Feasibility (Phase 2.5): 18 files across script, command, gate catalog, budgets and generated contract | HIGH | `context-bound` split; Subtask 2's validator-owned surfaces are enumerated in Closed enumerations touched; `ci-local.sh` runs every gate |
| Refactoring `_pr_unreg_count` breaks the existing AC11 mutation controls (they `del` one pinned literal and require exactly one line removed) | HIGH | Keep each pinned literal verbatim on exactly one line (Touched-file invariants); run `test-proc-registry.sh` before and after |
| `lane-status --leaks --snapshot` in the requirement would WRITE a snapshot, breaking the read-only report | HIGH | Call the compare mode only; AC4's checksum covers `.supervisor/automate/` leaks snapshots implicitly via "nothing changes" — include that dir in the test's checksum |
| The hermetic scan skip (`HERMETIC_TEST_ENV=1` with no snapshot) hides live look-alikes from `list --scan` in tests | MEDIUM | Tests supply `LOOMWRIGHT_PROC_PS_SNAPSHOT` for listing legs and a real background fixture under a temp `…/loomwright/scripts/` path with `LOOMWRIGHT_PROC_UNREG_MIN_S=0` for the stop legs; always kill fixtures in the EXIT trap (this item exists because fixture servers leaked) |
| `sweep --apply` is all-or-nothing: picking one worktree row applies every `would-remove` | MEDIUM | Label the option as "apply the sweep (N rows)" and list its rows in the ask; a per-path filter is out of scope |
| A stop leg refused as a flaky false red: with `LOOMWRIGHT_PROC_UNREG_MIN_S=0` the predicate `[ "$age" -gt "$min" ]` still needs an etime ≥ 1s | MEDIUM | The stop legs poll the snapshot until the fixture's etime is ≥ 1s (bounded), never a fixed sleep |
| `act` stopping a process the owner did not mean (pid recycled between report and pick) | HIGH | Every stop goes through `_pr_matches` (lstart + command-line hash) immediately before TERM and before KILL; AC8 tests the recycled case |
| A new `header: "JAN-ACT"` with dynamic labels trips `check-gate-headers.sh` G3 | MEDIUM | Register the code as a `(free text)` gate, as `LP-CLARIFY` is |
| Evidence AC11 needs an owner-picked interactive run a worker cannot perform | LOW | The file allows `pending — owner run at review`; the owner fills it before merge |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-25-af39f-janitor-command.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-26T02:53:31Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/707
- **Branch:** feature/af39f-janitor-command
- **Files changed:** 20
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** /janitor shipped (janitor-report.sh grouped read-only report + --json + guarded act; proc-registry list --scan + stop-unregistered; JAN-ACT gate; all surfaces, evidence, fragment). Phase 4.5 ran 3 FAIL→fix rounds; the final round's one HIGH (vendor-coupling token) was fixed in 655635c but not re-reviewed (check-vendor-coupling OK locally). ci green on f72d3f4; ci on 655635c pending at completion. AC13 full ci-local never observed green locally (exit-124 watchdog under external load).

## Not verified
- **full bash scripts/ci-local.sh (AC13)** — pool suites hit the 1000s watchdog (exit 124) under external machine load; never observed green locally (subtask 2)
- **new legs on Linux procps** — verified on macOS BSD ps only by the worker; GitHub ci (Ubuntu) later green on f72d3f4 (subtask 1)
- **/janitor interactive JAN-ACT ask and second force-unlock confirmation** — needs an interactive owner session; evidence records 'pending — owner run at review' (subtask 2)
