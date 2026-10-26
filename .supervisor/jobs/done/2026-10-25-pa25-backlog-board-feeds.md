# Supervisor Job: Backlog board feeds — a Floor `backlog` surface, a `lane-status` pointer and a once-a-day SessionStart stamp nudge, all read through one new `backlog --offline` mode

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L9
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/parallel-automate/25-backlog-board-feeds.md
- **Base commit:** ec67b67652390f9843d032379b486df289cbaaa4

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq scripts, the same stack as every touched file |
| 2 | Dependency Availability | GO | 18a's `item-state` / `backlog` engine is merged on main (`automate-helpers.d/backlog.sh`, PR #690) |
| 3 | Architecture Fit | CAUTION | `backlog --json` takes ~34 s in this repo (two `gh pr list` reads + the right-size pass) and ~5 s with both off. The SessionStart startup arm is offline by contract, and `build-floor.sh` is a deterministic projector, so neither can make the live reads. Owner decision (Launch Pad, 2026-10-25): add `backlog --offline` |
| 4 | Scope vs Supervisor Capability | CAUTION | 16 files change (> 12), so the split is `context-bound`; 4 subtasks |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make the places the owner already looks (the Floor projection, `lane-status`, session start) show the backlog board's answer, or point at it. Every number comes from 18a's classifier through ONE new read mode, `automate-helpers.sh backlog --json --offline`, and is never re-derived.

**Problem Statement:**
The owner needs to see which requirement items need a decision without remembering to run `/backlog`.
Currently the board answers only when someone runs `/backlog`; the Floor projection, `lane-status` and session start show nothing derived from it. This causes merged-but-unstamped and conflicting items to sit unnoticed.
Success looks like: `floor.json` carries a `backlog` surface (state totals + the items needing a decision), `lane-status` prints one pointer line to `/backlog`, and a fresh session start prints at most one line a day when any item reads `merged_unstamped` or `conflict`.

**Owner decisions (Launch Pad Phase 2, LP-CLARIFY, 2026-10-25):**
- **Scope 2 dropped.** `meta-sync push` does NOT write a generated `BACKLOG.md`. The `loomwright-meta` branch is public and world-readable. `meta-sync.d/commands.sh`, `meta-sync.d/managed.sh` and `test-meta-sync.d/01-sync-core.sh` are NOT touched. (Non-goal, below.)
- **Offline read mode.** The Floor and SessionStart feeds read the board through a new `backlog --offline` flag. It skips the two `gh pr list` reads and the right-size call, and takes the existing gh-failure path exactly: `github: unverified`, the right-size column `unknown`. The state rules are unchanged (the precedence in the `backlog.sh` header). Honest limit, stated in each feed's docs: an item whose only merge evidence is a merged PR on GitHub (no run-file `- [x]` row, no `fleet closeout` line) is NOT counted `merged_unstamped` by these feeds; it reads `unknown` (or its open-path state), exactly as `backlog` reads it when gh fails today.

**Non-goals:** changing `item-state` / board state semantics; any stamp written without the owner; a generated `BACKLOG.md` in `meta-sync`'s managed set (owner decision above); a new `hooks.json` leaf (`hooks.json` is guard-protected); the resume/clear/compact arms of `session-resume.sh`; `lane-status --json` (the `/lanes` add-on reads it).

**Design (binding):**
1. **`backlog --offline`** (`automate-helpers.d/backlog.sh`): accepted by `backlog` in every mode (`--json`, `--state`, `--unknown`, `--verify-list`). When set: `_bl_context` makes no `"$GH"` call and leaves `_BL_GH=unverified` (the same code path as both reads failing); `backlog_board` starts no right-size job and reports the right-size column as `unknown` (the same as a failed right-size call). The output keys stay the same (no new key). The `#:  backlog` help line and `fixtures/automate-helpers-help/backlog.golden` name the flag; `commands/backlog.md`'s flag table and the `item-state · backlog · backlog-stamp` row of `skills/automate-loop/helpers.md` document it and its honest limit. `item-state` gets no flag.
2. **Floor `backlog` surface** (`build-floor.sh`): reader = `bash "$SELF_DIR/automate-helpers.sh" backlog --json --offline --root "$GITROOT"`. Key `backlog`; `source` `.supervisor/requirements`; `basis` names the reader and "one item per requirement `*.md`, github lookups skipped (offline)". Status: `.supervisor/requirements` absent ⇒ `absent`, no `count`; reader absent, non-zero exit, or output that is not a JSON object with numeric `item_count` and object `totals` ⇒ `unverified`, no `count`, plus an `add_note` line; else `counted`, `count` = `item_count`, `detail` = `{github, totals, needs_decision}`. `needs_decision` = `[{item, state, evidence}]` for every item in state `merged_unstamped`, `conflict`, `brief_shipped` or `unknown`, `LC_ALL=C` sorted by `path`. The surface-count claims are updated in the same change (House Rules below).
3. **`lane-status` pointer** (`automate-lanes.d/status.sh`): in `lanes_status`, the two plain-view branches (terse default and `--verbose`) print ONE more line after the renderer's output: `backlog: every requirement item's state — run /backlog`. It is printed in `status.sh`, NOT inside `_lanes_render` / `_lanes_render_terse` in `status-read.sh`, so those renderers' byte goldens stay untouched. `_lanes_watch` renders each frame through `lanes_status … --verbose`, so every `--watch` frame also ends with the pointer line, once. That is accepted and asserted (AC7). `--json`, `--inbox`, `--leaks`, `--resources`, `--tokens`, the `no lane table` line and the `status unreadable` line are unchanged. The pointer makes no backlog call.
4. **SessionStart nudge** (`session-resume.sh`, startup arm ONLY): a new helper `backlog_nudge_line`, DEFINED ABOVE THE CASE beside the other startup-arm helpers, composed by `startup_arm_emit` as a seventh block into the ONE envelope (the header's "at most SIX advisory blocks" becomes SEVEN, with an item 7 description). Gate order, mirroring `curation_nudge_line`: (a) permanent opt-out `LOOMWRIGHT_BACKLOG_NUDGE=0|off|false|no`; (b) own cwd-relative `[ -d ".supervisor/requirements" ]` check; (c) the calendar-day marker `$SR_STATE/.backlog-nudge-shown` (host-mode aware like the other markers): when its first line equals today's `date +%Y-%m-%d`, return silently BEFORE running the reader. When the marker path is empty (host mode with no valid state dir, `SR_STATE` empty), also return silently and skip the reader, so it can never run on every session; (d) the sibling reader `"$script_dir/automate-helpers.sh" backlog --json --offline --root "$PWD"` (absent/unreadable sibling ⇒ silent), run in the background and bounded by `LOOMWRIGHT_SR_BACKLOG_TIMEOUT` seconds (default 10), with the same background + 0.1 s poll + kill idiom as `sr_pr_state` (bash 3.2 has no `timeout`). Timeout, non-zero exit, or unparsable JSON ⇒ print nothing, write no marker, return 0. (e) On a successful read, write today's date to the marker (braced redirection, same load-bearing shape as the curation marker). This holds whether or not a line prints: the check itself runs at most once per calendar day, which bounds its cost to one ~5 s read a day. Then N = `totals.merged_unstamped + totals.conflict`; N > 0 ⇒ print exactly `N backlog items need a stamp — run /backlog --verify` (N as a number); N = 0 ⇒ nothing. With no line, the startup envelope stays byte-identical to the pre-change arm. The nudge never calls gh (the startup arm's offline contract).

## Acceptance Criteria
- [ ] AC1 — Given a fixture requirements tree and a `gh` stub that logs every call, when `automate-helpers.sh backlog --json --offline` runs, then the stub logs zero calls, the document's `github` is `unverified` and `right_size` is `unknown`, and every item's `state` equals the state the same tree reads with a failing `gh` (no `--offline`). `backlog --offline` combined with `--state`, `--unknown` and `--verify-list` is accepted, and `test-automate-helpers-dispatch.sh` passes against the updated `backlog.golden`.
- [ ] AC2 — Given a fixture tree with exactly one `merged_unstamped` item (a run file's plain `- [x] <path>` row, no done stamp on the item), when `build-floor.sh` runs, then `floor.json`'s `surfaces.backlog` has `status: counted`, `detail.totals.merged_unstamped == 1`, and that item in `detail.needs_decision`; given no `.supervisor/requirements/`, then `surfaces.backlog.status == "absent"` with no `count` key; given a failing reader, then `status == "unverified"` with no `count` key and one `notes[]` line.
- [ ] AC3 — Given that same fixture tree, when the startup arm of `session-resume.sh` runs (`{"source":"startup"}` on stdin), then the envelope's `additionalContext` contains exactly one line `1 backlog items need a stamp — run /backlog --verify`; given a tree with no `merged_unstamped` or `conflict` item, then the line is absent and the startup output is byte-identical to the pre-change arm's output on the same tree.
- [ ] AC4 — Given the one-`merged_unstamped` fixture and `.supervisor/.backlog-nudge-shown` holding today's `date +%Y-%m-%d`, when the startup arm runs, then no backlog line prints and the reader is not run (a reader stub logs zero calls). With the marker holding yesterday's date, the line prints and the marker then holds today's date.
- [ ] AC5 — Given a reader that exits non-zero, prints non-JSON, or outlives `LOOMWRIGHT_SR_BACKLOG_TIMEOUT`, when the startup arm runs, then no backlog line prints, no marker is written, and the hook exits 0 (fail-SAFE test, one case per failure mode). `LOOMWRIGHT_BACKLOG_NUDGE=0` silences the line on the one-item fixture.
- [ ] AC6 — Given the existing `(zb)` "startup makes zero gh calls" fixture extended with a requirements tree, when the startup arm runs with a gh stub on PATH, then gh is still called zero times.
- [ ] AC7 — Given a lane table, when `lane-status` runs in its default and `--verbose` plain views, then the last line of each is exactly `backlog: every requirement item's state — run /backlog`; one `--watch` frame (`LOOMWRIGHT_LANES_WATCH_ITERATIONS=1`) contains that line exactly once; `lane-status --json` output is unchanged; and the `Q10g` / `Q10h` renderer goldens (`fixtures/terse-output/lane-status/`) pass unedited.
- [ ] AC8 — Given the new `backlog` surface key, when `test-build-floor.sh` runs, then its `ALL_KEYS` names `backlog`, and every surface-count assertion derives its number from `ALL_KEYS` rather than a literal `14`; `docs/result-schemas/floor-projection.md`'s key list names `backlog` and its required-key block parses green; `docs/result-schemas/schema-versioning.md` carries a new top `FLOOR_PROJECTION additive \`backlog\` surface` entry.
- [ ] AC9 — Given the `changelog.d/pa25-backlog-board-feeds.md` fragment (`<!-- bump: minor -->`), when `bash scripts/check-version-bump.sh` runs, then it passes. This is a parallel-wave lane: the PR carries the fragment only and never runs `bump-version.sh`.
- [ ] AC10 — Given the integrated feature branch checked out where `.supervisor/requirements/` exists, i.e. this lane's main checkout (the L9 clone root), NOT a worker git worktree (`.supervisor/*` is gitignored, so a worktree has no requirements tree and the reader exits 1), when one fresh session start is simulated there (`printf '{"source":"startup"}' | bash loomwright/scripts/session-resume.sh`, marker removed first), then a committed evidence file `docs/evidence/pa25-backlog-board-feeds.md` holds four things: the command and checkout, the nudge line or its absence, that checkout's `item_count`, and the `automate-helpers.sh backlog --json --offline` totals (`jq .totals`) that explain it. The PR body links to the file.
- [ ] AC11 — Given the targeted suites, when they run, then `test-build-floor.sh`, `test-session-resume.sh`, `test-automate-lanes.sh` (its `.d/01-create-to-wait.sh`), `test-automate-helpers.sh` (its `.d/18-backlog.sh`), `test-automate-helpers-dispatch.sh`, `scripts/check-doc-currency.sh` and `loomwright/scripts/test-citation-drift.sh` pass, and `bash scripts/ci-local.sh` is green before push.

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

**How this brief honors them:** the surface count ("fourteen" / `14`) is restated today in `build-floor.sh`'s header, `floor-projection.md` (twice) and `test-build-floor.sh`. Subtask 2 removes each prose literal and replaces it with a pointer to the authority: "one key under `surfaces`; the key list is the `surfaces:` line of the annotated block in `docs/result-schemas/floor-projection.md`". It also derives every test count from `ALL_KEYS` (`set -- $ALL_KEYS; $#`). Historical entries in `schema-versioning.md` ("A fourteenth surface key, `agents`") are dated records and stay. The new key `backlog` is added to the key list in that ONE schema line and to `ALL_KEYS`, in the same change as `build-floor.sh`.

## Touched-file invariants

> Grounded at base `ec67b67652390f9843d032379b486df289cbaaa4`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-helpers.d/backlog.sh`** — keep: the fail-safe read section `set +e   # FAIL-SAFE reads from here: a source that cannot be read degrades, never aborts`; the read-only promise `READ-ONLY (item-state, backlog): writes only its own mktemp dir (trap-removed); never git`; the closed state set `_BL_STATES="done abandoned parked proposed brief_shipped merged_unstamped pr_open in_flight conflict open unknown"` (unchanged, no new state); usage errors still `exit 1` via `_bl_fail`. reuse: the existing unverified path, `_BL_GH=unverified`, and the existing right-size failure branch `rsz=unknown`, rather than any new state or key. mirror: the help line `#:  backlog          [--json] [--state <s>]` is assembled into `--help` and pinned byte-for-byte by `fixtures/automate-helpers-help/backlog.golden` (`test-automate-helpers-dispatch.sh`, `GOLDEN_DIR="$HERE/fixtures/automate-helpers-help"`). pinned by: `test-automate-helpers.d/18-backlog.sh` (`BL4 usage errors exit 1 with nothing on stdout`). Test seams (`LOOMWRIGHT_LANE_STATUS_BIN`, `LOOMWRIGHT_RIGHT_SIZE_BIN`) stay tests-only; `--offline` is a real flag, not a seam.
- **`loomwright/scripts/build-floor.sh`** — keep: `exit 0 ALWAYS - a projector must never break its caller.`; evidence-only derivation (`key is ABSENT (not 0)` when a surface is not counted); one wall-clock read (`the script reads the wall clock EXACTLY ONCE`); output via `jq -S`, so the same tree gives the same bytes. The backlog reader's own mktemp is the child's and is trap-removed; build-floor itself still writes only `.supervisor/floor/floor.json`. Reword the DISCIPLINE line `No temp files, no lock files, no redirects outside that one directory.` to say the backlog reader child keeps its own trap-removed mktemp dir and reads `lane-status --json`. Make that edit together with the removal of the header's `FOURTEEN` literal. reuse: `add_surface <key> <source> <basis> <status> [count] [reason] [mtime] [detail_json]` and `add_note`; resolve the sibling from `SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"` (resolved before the `cd`). pinned by: `test-build-floor.sh` (`ALL_KEYS="state jobs_pending jobs_in_progress jobs_done jobs_failed automate_runs logs \`, `all 14 sections counted and non-zero`, `ANTI-VACUITY: an EMPTY fixture fails the zero/absent guard on all 14 sections`, `all 14 surfaces carry a non-empty basis`). The fixture tree must gain a requirements item so the "counted and non-zero" pass stays non-vacuous, and the empty fixture must read `backlog` absent. Keep the suite hermetic: stub lane reads with `LOOMWRIGHT_LANE_STATUS_BIN` and put a failing `gh` stub on PATH. The reader makes no gh call under `--offline`, and the stub proves it.
- **`loomwright/docs/result-schemas/floor-projection.md`** — keep: `test-build-floor.sh` **parses the required-key set out of the annotated block below**. The key list `Keys are stable snake_case names (state, jobs_pending` gains `backlog`; the annotated block stays parseable. mirror: `build-floor.sh`'s emitted key set and `ALL_KEYS`.
- **`loomwright/docs/result-schemas/schema-versioning.md`** — reuse: the newest-first entry style `- **FLOOR_PROJECTION additive …** (<date>): …`; add one entry at the top of the FLOOR_PROJECTION group.
- **`loomwright/scripts/automate-lanes.d/status.sh`** — keep: `if [ "$json" = 1 ]; then printf '%s\n' "$doc"; elif [ "$verbose" = 1 ]; then _lanes_render "$doc"; else _lanes_render_terse "$doc"; fi`. Only the two non-JSON branches gain the pointer line; `--json` stays byte-identical because the `/lanes` add-on reads it (`loomwright-lanes/hooks/register.tsx`: `lane($, configured, 'lane-status', ['--json'])`), and so does `backlog.sh`'s own lane read (`automate-lanes.sh" lane-status --json`). `automate-lanes.d/status-read.sh` is NOT edited: its renderers are pinned by `Q10g --verbose renderer is byte-identical to the pre-change plain view (verbose.golden)` and `Q10h terse renderer = header + each lane's first line (default.golden)`. pinned by: `test-automate-lanes.d/01-create-to-wait.sh` `Q10c` (expects `"0:8:0:1"`, header + 7 lane lines, 0 non-lane lines) and `Q10d` (compares `sed 1d` of the default view with the verbose lane lines). Both must be updated to account for exactly one trailing pointer line (e.g. `"0:9:1:1"` and comparing `sed '1d;$d'`), with a new assertion that the last line is the pointer.
- **`loomwright/scripts/session-resume.sh`** — keep: `INVARIANT: ALWAYS exits 0`; `# Intentionally NO \`set -e\` / pipefail.`; the startup arm's offline contract (`HONEST LIMIT of the startup line: this path is offline (no forge call, ever)`); one envelope (`startup_arm_emit` joins blocks with the `${body:+$body$nl}` rule); helpers defined above the case (`# ---- Startup-arm helpers (DEFINED ABOVE THE CASE ON PURPOSE)`), since `startup) startup_arm_emit; exit 0 ;;` would otherwise hit rc 127 silently; markers via `SR_STATE` (`[ -n "$SR_STATE" ] && marker="$SR_STATE/.curation-nudge-shown"`), written with the braced redirect (`BRACES ARE LOAD-BEARING`). reuse: `sr_pr_state`'s background + poll + kill idiom (`kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null`) for the timeout; the sibling resolution `script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"`. Update the header's `composes at most SIX advisory blocks into ONE envelope` (and its numbered list) to seven. fired by: `hooks.json` SessionStart `bash \"${CLAUDE_PLUGIN_ROOT}/scripts/session-resume.sh\" || true` (unchanged; no new leaf). pinned by: `test-session-resume.sh` (`copy_hook_sparse() { cp "$HOOK" "$1/session-resume.sh"; }`: sparse dirs carry no `automate-helpers.sh`, so every existing byte-identical startup case stays silent), and `(zb)` (`startup makes zero gh calls`).
- **`loomwright/docs/HOOKS.md`** — the SessionStart `session-resume.sh` row (`on \`startup\` it runs ONLY its dedicated startup arm`) gains one sentence on the backlog nudge: offline `backlog --offline` read, calendar-day marker `.supervisor/.backlog-nudge-shown`, `LOOMWRIGHT_BACKLOG_NUDGE=0` opt-out, `LOOMWRIGHT_SR_BACKLOG_TIMEOUT`, fail-safe, and the honest limit. No hook count is restated.
- **`loomwright/commands/backlog.md`, `loomwright/skills/automate-loop/helpers.md`** — mirror: the flag table row (`| \`--json\` | off |` style) and the helpers row (`| \`item-state\` · \`backlog\` · \`backlog-stamp\` |`) name `--offline` and its honest limit. Their token budgets in `loomwright/docs/prompt-token-budgets.json` must still hold (`check-token-budget.sh`); if a ceiling is exceeded, raise that entry and its `ARCHITECTURE_CONTRACTS.md` mirror row in the same change.

## Closed enumerations touched

> Sibling grep at base `ec67b676`: `grep -rnF 'worker_summaries' --exclude=CHANGELOG.md --exclude-dir=.supervisor --exclude-dir=node_modules .` → 5 hits in 3 files.

- **`backlog`** (floor surface key; sibling: `worker_summaries`) — must be named in:
  - `loomwright/docs/result-schemas/floor-projection.md` — the `surfaces: object` line's key list (`Keys are stable snake_case names (state, jobs_pending, …, rules, agents)`) — extend.
  - `loomwright/scripts/test-build-floor.sh` — `ALL_KEYS="state jobs_pending … worker_summaries rules agents"` — extend.
  - `loomwright/scripts/test-build-floor.sh` — `check_pair worker_summaries   "$EXP_WORKER_SUMMARIES"` (per-key expected-count pairs) — extend: add a `check_pair backlog` with the fixture's item count.
  - `loomwright/scripts/build-floor.sh` — `count_glob "worker_summaries" ".supervisor/worker-summaries"` — the emitter itself, extend (new `add_surface "backlog" …` block).
  - `loomwright/scripts/test-build-floor.sh` — `cmp_real worker_summaries "$(real_n …)"` (the real-checkout cross-check) — no change: it compares glob counts for glob surfaces; the backlog count comes from the reader, and a real-tree cross-check would make the suite depend on this repo's live backlog.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-automate-helpers.d/18-backlog.sh` — AC1 zero-gh-calls under `--offline` | in `automate-helpers.d/backlog.sh` `_bl_context`, remove the `--offline` guard so the two `"$GH" pr list` reads run again ⇒ the stub logs 2 calls, red |
| `test-build-floor.sh` — AC2 `surfaces.backlog` counted with `merged_unstamped == 1` | in `build-floor.sh`, delete the `add_surface "backlog"` call on the counted branch ⇒ key missing, red |
| `test-build-floor.sh` — AC2 failing reader ⇒ `unverified`, no `count` | in `build-floor.sh`, make the reader-failure branch call `add_surface` with status `counted` and count `0` ⇒ red |
| `test-automate-lanes.d/01-create-to-wait.sh` — AC7 last line is the pointer | in `automate-lanes.d/status.sh`, delete the line that prints `backlog: every requirement item's state — run /backlog` ⇒ red |
| `test-session-resume.sh` — AC3 nudge line present | in `session-resume.sh` `startup_arm_emit`, delete the line that appends the `backlog_nudge_line` output to `body` ⇒ red |
| `test-session-resume.sh` — AC4 today's marker silences the nudge and skips the reader | in `session-resume.sh` `backlog_nudge_line`, delete the `return 0` taken when the marker's date equals today ⇒ the reader runs and the line prints, red |
| `test-session-resume.sh` — AC5 failing reader ⇒ silent, no marker | in `session-resume.sh` `backlog_nudge_line`, write the marker before the reader runs ⇒ the marker exists after a failed read, red |
| `test-session-resume.sh` — AC5 timeout ⇒ silent | in `session-resume.sh` `backlog_nudge_line`, delete the deadline `kill` in the poll loop ⇒ the hung-reader case outlives the test's wall-clock bound or prints, red |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `backlog --offline` read mode + docs + changelog fragment | AC1, AC9, AC11 (its suites) | 5 modify (+2 conditional: token budgets), 1 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Floor `backlog` surface + schema docs + count pointers | AC2, AC8, AC11 (its suites) | 4 modify, 0 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |
| 3 | `lane-status` pointer line | AC7, AC11 (its suites) | 2 modify, 0 create | `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 4 | Once-a-day SessionStart stamp nudge + HOOKS.md + running-system evidence | AC3, AC4, AC5, AC6, AC10, AC11 (its suites) | 3 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-helpers.d/backlog.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "--offline"}
  - {kind: "symbol", path: "loomwright/scripts/fixtures/automate-helpers-help/backlog.golden", name: "--offline"}
  - {kind: "symbol", path: "loomwright/commands/backlog.md", name: "--offline"}
  - {kind: "file", path: "changelog.d/pa25-backlog-board-feeds.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.d/backlog.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/backlog.golden"
  - "loomwright/scripts/test-automate-helpers.d/18-backlog.sh"
  - "loomwright/commands/backlog.md"
  - "loomwright/skills/automate-loop/helpers.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/pa25-backlog-board-feeds.md"
external_requires:
  - "jq, bash 3.2 (macOS) — already required by the touched scripts"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "--offline"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/floor-projection.md", name: "backlog"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/schema-versioning.md", name: "FLOOR_PROJECTION additive `backlog` surface"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "--offline"}
lanes:
  - "loomwright/scripts/build-floor.sh"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/docs/result-schemas/floor-projection.md"
  - "loomwright/docs/result-schemas/schema-versioning.md"
external_requires: []

# Subtask 3
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.d/status.sh", name: "run /backlog"}
requires: []
lanes:
  - "loomwright/scripts/automate-lanes.d/status.sh"
  - "loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh"
external_requires: []

# Subtask 4
provides:
  - {kind: "symbol", path: "loomwright/scripts/session-resume.sh", name: "backlog_nudge_line"}
  - {kind: "symbol", path: "loomwright/scripts/session-resume.sh", name: "LOOMWRIGHT_BACKLOG_NUDGE"}
  - {kind: "symbol", path: "loomwright/docs/HOOKS.md", name: ".backlog-nudge-shown"}
  - {kind: "file", path: "docs/evidence/pa25-backlog-board-feeds.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "--offline"}
lanes:
  - "loomwright/scripts/session-resume.sh"
  - "loomwright/scripts/test-session-resume.sh"
  - "loomwright/docs/HOOKS.md"
  - "docs/evidence/pa25-backlog-board-feeds.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
Subtask 1 ──→ Subtask 4
Subtask 3 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO (ordered by `requires`) |
| Subtask 1 | Subtask 3 | none | NO |
| Subtask 1 | Subtask 4 | none | NO (ordered by `requires`) |
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 2 | Subtask 4 | none | NO |
| Subtask 3 | Subtask 4 | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 3 (parallel)
- **Batch 2:** Subtask 2, Subtask 4 (parallel, after Subtask 1)
- **Recommended workers:** 2
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |
| 3 | `skills/unit-testing/SKILL.md` |
| 4 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): a live board read is ~34 s, and the startup arm and the Floor cannot make it | HIGH | Owner decision: read through `backlog --offline` (~5 s here). The startup nudge runs at most once per calendar day, is time-bounded by `LOOMWRIGHT_SR_BACKLOG_TIMEOUT` (default 10 s), and fails silent |
| Feasibility (Phase 2.5): 16 files change, so the split is `context-bound` | MEDIUM | 4 subtasks with disjoint lanes; Subtasks 2 and 4 consume only the `--offline` flag from Subtask 1 |
| Offline honest limit: an item merged only on GitHub (no run-file `- [x]` row, no `fleet closeout` line) reads `unknown`, not `merged_unstamped`, so the nudge and the Floor under-report it | MEDIUM | State the limit in `commands/backlog.md`, `HOOKS.md` and the Floor `basis`; `/backlog` (live) and `/backlog --verify` stay the authoritative check |
| The calendar-day marker is stamped after every successful check, so an item that becomes `merged_unstamped` later the same day waits until the next day's first session | LOW | A deliberate cost bound (one ~5 s read a day), documented in the helper's comment and `HOOKS.md`; `/backlog` shows it at any time |
| `build-floor.sh` gains a ~5 s child read per run, and its output now depends on local lane state through `backlog`'s `lane-status --json` read | LOW | Hermetic tests stub lanes via `LOOMWRIGHT_LANE_STATUS_BIN`; the determinism test (two runs differ only in `generated_at_epoch`) must stay green |
| Existing startup-arm tests assert byte-identical silence; a nudge that fires in their fixtures turns them red | MEDIUM | The sibling `automate-helpers.sh` is absent in `copy_hook_sparse` dirs ⇒ silent; new cases copy or stub the sibling explicitly |
| `lane-status` plain-text consumers parse its lines | LOW | The `/lanes` add-on reads `--json` only (verified in `loomwright-lanes/hooks/register.tsx`); `Q10c`/`Q10d` are updated for the one trailing line |
| Simulating a fresh session for AC10 runs the real startup arm, whose `reconcile-jobs.sh --repair-merged` moves only disk-proven merged briefs | LOW | Run it in the lane's main checkout (the only place `.supervisor/requirements/` exists; a worker worktree has none). That is the same behavior every real session start there already has. Record the full output in the evidence file |
| Repo-wide drift from a literal surface count ("fourteen" / `14`) | MEDIUM | Replace prose literals with pointers to the schema key list and derive test counts from `ALL_KEYS` (House Rules); grep `fourteen` and `14 surfaces` repo-wide before hand-back (the lesson: a green `check-doc-currency.sh` is necessary, not sufficient) |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-25-pa25-backlog-board-feeds.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-26T04:31:31Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/709
- **Branch:** feature/pa25-backlog-board-feeds
- **Files changed:** 24
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** `backlog --offline` read mode; Floor `backlog` surface; `lane-status` plain-view pointer line; once-a-day SessionStart stamp nudge; AC10 evidence committed. Phase 4.5: iteration 1 PASS with 2 MEDIUM at fix floor MEDIUM (nudge timeout cost documented as an owner decision; restated lane-status descriptions swept, 7 copies + help golden), fixed in d12e504; iteration 2 PASS (2 LOW dismissed). FINALIZE children check skipped by the owner (labels in state.md, not agent ids; all real children settled). Pre-push ci-local not green: run 1 all 179 self-tests passed but the leak gate caught pre-existing sleep 300/90 survivors; run 2 one host-load watchdog timeout in test-automate-next-step.sh plus the same leak — neither from this diff; GitHub required checks green. Open owner decision: LOOMWRIGHT_SR_BACKLOG_TIMEOUT default 10 s vs ~21 s offline read under load (no marker on timeout).

## Not verified
- **build-floor.sh / session-resume.sh consumers of backlog --json --offline** — land in subtasks 2 and 4 (subtask 1)
- **build-floor.sh on real L9 checkout** — writes floor.json outside worktree; reader alone gave 457 items (subtask 2)
- **symlinked .supervisor/requirements** — pre-existing backlog.sh find limitation, reads 0 (subtask 2)
- **loomwright-lanes /lanes pane (lane-status --json)** — add-on tests not run; --json untouched, Q10m asserts (subtask 3)
- **AC10 on integrated branch in main checkout** — owed at FINALIZE by the worker; done by Supervisor at FINALIZE (docs/evidence/pa25-backlog-board-feeds.md) (subtask 4)
- **reader cost on quiet host** — all measured at load 9-90 (subtask 4)
- **ci-local.sh --affected** — 900s watchdog timeouts under load; suites run individually, all pass (subtask 4)
