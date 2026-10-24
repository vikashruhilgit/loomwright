# Supervisor Job: One read-only `/backlog` board — every requirement item's real state, derived from evidence (parallel-automate/18a)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L6
- **CLAUDE.md:** ✓ Found (fresh — plugin layout, invariants and gates match the tree at base)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/parallel-automate/18a-backlog-board.md
- **Base commit:** 237adab3f71e30ac817b34b9fb630e50e9661cb2

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe shell + jq, the same stack as every `automate-helpers.d/` family |
| 2 | Dependency Availability | GO | the dependency 18b has merged: `right-size --json` is on main (PR #675, `fe03dbb`). `lane-status --json`, `is_done`, `_rs_skip_path` and `gh` are all present |
| 3 | Architecture Fit | GO | a new helper family `automate-helpers.d/backlog.sh` sourced by the dispatcher by name, plus one read-only command doc. Same shape as `right-size` and `plan-waves` |
| 4 | Scope vs Supervisor Capability | CAUTION | ~30 files, >800 changed lines (engine + fixture tree + tests + command + count/gate/budget surfaces). Needs a `context-bound` split |
| 5 | Hard Blockers | GO | none. The open owner decision (conflict dating and settling) was answered at Launch Pad, see Task |

**Overall Verdict:** CAUTION

## Task
**Goal:** Ship `/backlog`, a read-only command whose one reader (`automate-helpers.sh item-state`, with the board subcommand `backlog`) derives every requirement item's state from evidence: run files, live lanes, merged PRs and the item's own stamp, never from a hand-kept label. It shows a right-size column, `--json`, `--state`, `--unknown` and an owner-gated `--verify`. It also guards `reconcile-status --apply` from stamping ABANDONED over a `conflict` item.

**Problem Statement:**
The owner needs one honest answer to "what is pending / done / in flight", because requirement `## Status:` lines and `_BACKLOG.md` checkboxes are not updated on merge.
Currently, of 271 items measured 2026-10-22, 224 had shipped while most still read `## Status: pending`, and answering took a hand cross-check of run files, `git log` and merged PRs. This causes miscounts (39 "pending" by first line vs 26 really open) and re-offered shipped work.
Success looks like `/backlog` totals equalling the item-file count, each state counted once, every value recomputed from sources on each run, and no stamp written without the owner's per-item approval.

**Owner decisions (answered at this Launch Pad session, 2026-10-24 — binding on the brief):**
- **D-conflict-1 — no date wins.** A `pending`/`ready` item named by any run file's `- [x] <path>  # abandoned: …` or `# skipped: …` Queue row reads `conflict` until the owner settles it. The board shows both sources with their dates: the row's run file and its run_id date, and the item's last dated stamp, or `undated`. The settle marker is a line `- **Kept open:** <YYYY-MM-DD> — supersedes <run_id>` in the item file. It clears the conflict for every abandoned/skipped row whose run_id date is on or before that marker's date. A row from a later run raises the conflict again. **Guard rule (the ONE statement — the invariants and tests use exactly this):** `reconcile-status --apply` never stamps ABANDONED from a Queue row on an item whose first `## Status:` line is explicit `pending`/`ready`, whether that item reads `conflict` or was kept open (a kept-open item's stale row must never abandon it). A `conflict` item prints an `info` row instead. Every other not-done, in-scope item named by such a row (status-less, `brief-shipped`, an off-enum value) is stamped exactly as today. The owner decision covers only `pending`/`ready`, so nothing else changes.
- **D-conflict-2 — settled inside `/backlog --verify`.** `--verify` lists `conflict` items beside the evidence-less ones. For each, the owner picks `Abandon` (the engine ABANDONED stamp), `Keep open` (the dated marker above) or `Skip`. Nothing is written without that per-item answer.
- **Pre-existing (from `_BACKLOG.md`, 2026-10-22):** the board is a new `/backlog` command, not an `/automate --board` flag.

**State model (the ONE closed set — `item-state` prints exactly one per item; the board totals count each once):**
`done` · `abandoned` · `parked` · `proposed` · `brief_shipped` · `merged_unstamped` · `pr_open` · `in_flight` · `conflict` · `open` · `unknown`. Plus one RUN state, `stale_run`, listed under "Runs needing attention" and never counted as an item. The header's list in the requirement is not exhaustive. `open`, `abandoned`, `proposed` and `brief_shipped` come from the Source text's state list, which the header does not contradict.

**Precedence (first match wins; every row names the evidence line it rests on):**
1. The item's own terminal stamp. `is_done` matches on ANY `## Status:` line, so an appended done stamp under a first-line `pending` reads `done`. A `## Status: done_with_escalation — ABANDONED (…)` heading reads `abandoned`. `parked (merged … into X)` / `parked (split … into X)` read X's state (recursion bounded to one hop per item, cycle ⇒ `unknown (parked chain cycle)`) and name X. Any other `parked` reads `parked`. A `proposed` heading, or a file under `proposed/`, reads `proposed`. The item's own stamp beats any run file's `## Current`, and that run is reported as `stale_run`.
2. Merge evidence with no done stamp ⇒ `merged_unstamped`. Evidence is a run file's plain `- [x] <path>` Queue row (no `# skipped:`/`# abandoned:` suffix) or a `fleet closeout: … <path> done` line. Otherwise it is a merged PR, from ONE cached `gh pr list --state merged` read per pass, whose `headRefName` or title names the item's slug.
3. `conflict` per D-conflict-1.
4. A live claim. A non-done run file's `## Current` naming the item, or a live lane's item from `lane-status --json` (`.lanes[]`), reads `in_flight` with the run/lane name. When that claim's PR reads OPEN in the one cached `gh pr list --state open` read, it is `pr_open` with the PR.
5. `## Status: brief-shipped` ⇒ `brief_shipped`. Explicit `pending`/`ready` ⇒ `open`. Anything else (no status line, or a value outside the enum) ⇒ `unknown`, with the offending line or `no status line`.
`gh` unavailable or failing ⇒ every PR field reads `unverified`. A claim whose PR state cannot be read stays `in_flight` with PR `unverified`, never `pr_open` and never silently `open`. The board header prints `github: unverified`.

**Item set:** every `*.md` under `<root>/.supervisor/requirements/`, minus the files `_rs_skip_path` already skips (`00-*`, `_*`, `README*`, `operator-run/`, a top-level `<slug>-plan.md`). It reuses that function and never restates the list. `proposed/` files are items (state `proposed`).

**Out of scope (MVP):** the board's feeds — the Floor `floor.json` surface, `BACKLOG.md` at meta push, and the SessionStart nudge — are item 25. A `wave` column (Source text A2) is deferred: the header's A2 correction names only the table, `--json`, `--state`, totals and the right-size column. No GitHub read other than the two cached PR lists. No stamp outside `--verify`'s per-item owner answer, or `reconcile-status`'s existing evidence rule.

## Acceptance Criteria
- [ ] AC1 — Given a hermetic fixture tree under `loomwright/scripts/fixtures/backlog-state/` (no test reads the live backlog), when `automate-helpers.sh item-state <item> --root <fixture>` runs, then it prints exactly one state from the closed set plus its evidence. Every state has its own fixture case. The cases include: first-line `pending` plus an appended done stamp ⇒ `done`; no status line ⇒ `unknown` with `no status line`; a lane backlog item named in a stubbed `lane-status --json` ⇒ `in_flight` with the lane name; a `parked` item named by an unfinished run's `## Current` ⇒ `parked` with that run listed `stale_run`; a `pending` item with an older run's `# abandoned:` row ⇒ `conflict` showing both sources and dates.
- [ ] AC2 — Given a fixture item stamped `pending` whose path is checked `- [x]` (no skip/abandon suffix) in a fixture run file, when `/backlog` (`automate-helpers.sh backlog --root <fixture>`) runs, then that item reads `merged_unstamped`, never `pending`/`open`, naming the run-file line.
- [ ] AC3 — Given a fixture item stamped `parked (merged <date> into `X` as Part B — …)` with X stamped done, when `item-state` runs, then it reads `done` and names X.
- [ ] AC4 — Given `backlog --json`, when it runs on the fixture tree, then stdout is ONE jq-built JSON object whose per-state totals sum to the item count (each item counted once), and the JSON round-trips (`jq -c . | jq -e` equal). `--state <s>` filters rows to that state while totals stay whole-tree.
- [ ] AC5 — Given a fixture with `gh` stubbed to fail (`LOOMWRIGHT_GH_BIN`), when `backlog` runs, then every PR field reads `unverified`, the header says `github: unverified`, and no item reads `pr_open` or changes to `open` because of the failure.
- [ ] AC6 — Given a fixture item stamped `- **Kept open:** <date> — supersedes <run_id>` dated on or after that run, when `item-state` runs, then it reads its own status (`open`), not `conflict`. Given a later run's abandoned row for the same item, then it reads `conflict` again.
- [ ] AC7 — Given `reconcile-status <fixture root> --apply` over a `pending` item named by a `# abandoned:` row (a `conflict`), when it runs, then the item file is byte-unchanged and one `info\t<rel>\tconflict\t<run file>` row is printed. Given a `pending` item carrying `- **Kept open:** <date> — supersedes <run_id>` dated on or after that row's run (not `conflict`), then the file is also byte-unchanged and no `plan`/`stamped` row names it. Given a `## Status: brief-shipped` item named by a `# abandoned:` row, then it is still stamped ABANDONED (unchanged behaviour outside `pending`/`ready`). Given a status-less item named by such a row, then it is still stamped `done_with_escalation — ABANDONED (<row verbatim>)` (the existing path, legs H4/H5b re-grounded on status-less fixtures).
- [ ] AC8 — Given `backlog`'s right-size column, when the board runs, then it calls `right-size --json` ONCE over the whole item list (no second Touches scan, no per-item call) and shows each item's verdict. A right-size failure reads `unknown` in that column only.
- [ ] AC9 — Given `backlog --unknown`, then it lists every `unknown` and `brief_shipped` item with the reason and a suggested fix (stamp done with the PR that shipped it, mark abandoned, or add `## Status: pending`) and writes nothing. Given `backlog --verify-list [item…]`, then it lists only items with no merge evidence (`brief_shipped`, `unknown`, `conflict`, or the named items), with candidate merged PRs from the cached list, and writes nothing.
- [ ] AC10 — Given `automate-helpers.sh backlog-stamp <item> <done|done_with_escalation|abandoned|kept-open> …` without `--confirm`, then it exits 1 and writes nothing. With `--confirm` it writes exactly the engine shape: `done` mirrors closeout's line set: `<!-- loomwright:requirement-closeout -->` + `## Status: done` + `- **Completed:** <UTC ts>` + `- **Brief:** <repo-relative done/ brief, or \`unknown\` when none>` + one `- **PR:**` line per PR (`done_with_escalation` the same lines under `## Status: done_with_escalation`, plus `- **Owed:** <text>`); ABANDONED is `## Status: done_with_escalation — ABANDONED (<reason>)`; `kept-open` is the D-conflict-1 marker. It refuses an already-done item, a path outside `<root>/.supervisor/requirements/`, and an absolute home path in any argument. Every refusal is exit 1 with nothing written.
- [ ] AC11 — Given `commands/backlog.md`, then it documents `/backlog` (table grouped by folder, `--json`, `--state <s>`, `--unknown`, `--verify [item…]`). `--verify` asks per item through catalog gates `BL-VERIFY` / `BL-CONFLICT` (human-only, added to `lane-policy.sh catalog`, `docs/LANE_GATES.md` regenerated, a Question-gate inventory row in `ARCHITECTURE_CONTRACTS.md`). It writes only via `backlog-stamp --confirm`, then publishes the stamped files with the existing `meta-sync.sh push --branch …`. Can't-ask (non-interactive or subagent) ⇒ lists proposals, writes nothing, leading token `verify_requires_owner`. `check-gate-headers.sh` passes.
- [ ] AC12 — Given the new command, then `/agent-help` has a `### … /backlog ` section and an index line, `prompt-token-budgets.json` has a `.commands.backlog` entry (measured + ~10%) with its `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row, `prompt-history-refs-baseline.json` has a `loomwright/commands/backlog.md` entry, and `check-doc-currency.sh`, `check-token-budget.sh`, `check-prompt-history-refs.sh`, `test-citation-drift.sh` and `bash loomwright/scripts/build-capabilities.sh --check` pass. Every restated command count either moves with the directory or is removed (house rule: prefer removing).
- [ ] AC13 — Given the targeted tests, then `bash loomwright/scripts/test-automate-helpers.sh 18-backlog`, `… 10-reconcile-status`, `bash loomwright/scripts/test-automate-helpers-dispatch.sh` (help golden) and `bash loomwright/scripts/test-lane-policy.sh` pass. Each new pin turns red under its `## Pin mutations` row.
- [ ] AC14 — Given the running system, when `automate-helpers.sh backlog --json` runs read-only on this repo's live `.supervisor/requirements/`, then a committed evidence file `docs/evidence/pa18a-backlog-board.md` contains the command, the state totals (summing to the item count), five sample rows, and for each `done` sample the PR or run-file line behind it, and the PR body links to it. No absolute home path appears in the file (`/Users/<name>/` placeholder form only).
- [ ] AC15 — Given the release rule, then the branch carries `changelog.d/pa18a-backlog-board.md` and `bash scripts/check-version-bump.sh` passes. In this N > 1 wave the lane PR carries the fragment only and never bumps (`wave-build` folds it).

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
  - id: documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it
  - enforcement: advisory
  - category: documentation
  - check (data only, NOT executed by this reader): (none)
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

## Touched-file invariants

> Grounded at base `237adab3f71e30ac817b34b9fb630e50e9661cb2`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-helpers.sh`** — keep: the family loader sources each family BY NAME between markers (`Listed by name, never globbed`). Add `# >>> automate-helpers.d/backlog.sh` / `_ah_source backlog` / `# <<< …` the same way as `# >>> automate-helpers.d/right-size.sh`. Keep `set -euo pipefail`, and keep the dispatcher read-only apart from its named carve-outs. `backlog-stamp` is a NEW owner-invoked writer: document it in the header as the next carve-out beside `A fifth carve-out, in THIS process: \`merge-items\`` (writes ONLY one requirement file under `<root>/.supervisor/requirements/`, only under `--confirm`, never git, never `gh`). reuse: `is_done() { grep -qE` (matches ANY `## Status:` line, which is what makes AC1's appended stamp read `done`), and never write a second done predicate. mirror: help usage follows the header rule `ADDING A SUBCOMMAND? Add its` `#:  ` line beside the implementation plus the same line in `fixtures/automate-helpers-help/backlog.golden`, and insert `backlog` into `_AH_HELP_SEGMENTS="config runfile …"` after `right-size` and before `hdr-lanes` (`… plan-waves right-size backlog hdr-lanes`). Add `case` arms in the `main()` style of `right-size)      right_size "$@" ;;`. pinned by: `test-automate-helpers-dispatch.sh` (`SEGMENTS="config runfile …"` plus its `fixture-set mutant` control).
- **`loomwright/scripts/automate-helpers.d/reconcile-status.sh`** — keep: `set +e   # FAIL-SAFE` (always exit 0); `is_done "$fabs" && continue` and `_rs_skip_path "$fabs" "$proj_root" && continue` before any write (NEVER DOWNGRADES); `NO ABSOLUTE PATHS` in every printed row and written line; dry run by default. reuse: the abandoned-row matcher `"- [x] "*"  # abandoned: "*)` stays the one parser. The guard is D-conflict-1's guard rule, word for word: skip an item whose first `## Status:` line is explicit `pending`/`ready` (kept-open included). Every other status keeps today's stamping, so `_rs_strip_trailing_status` stays live on this path, and call backlog.sh's shared predicate `_bl_is_conflict` (one definition of "conflict") only to choose between printing the `info …\tconflict` row and skipping silently. mirror: the OUTPUT block's `info\t<repo-relative file>\tbrief-shipped` row gains a sibling `info\t<rel>\tconflict\t<run file>`. Its one consumer, `automate-next-step.sh`'s `[ "$k" = plan ] || continue`, ignores `info` rows and must stay unchanged. The usage line `#:  reconcile-status` and `fixtures/automate-helpers-help/reconcile-status.golden` change together. The lane writer `AB_HEAD="## Status: done_with_escalation $em ABANDONED ($row)"` in `automate-lanes.d/remove.sh` writes its own stamp and is NOT routed through this guard, so leave it untouched. pinned by: `test-reconcile-jobs.sh` (`_printf_fmt "$RSTAT" '\n## Status: done_with_escalation '`, which extracts the ABANDONED printf from this file, so keep that printf one line with that prefix); `test-no-pipefail-grep-q.sh`'s `WRITER_BASELINE` ratchet (`1 loomwright/scripts/automate-helpers.d/reconcile-status.sh`), so add no producer-piped-into-`grep -q` site here or in the new `backlog.sh` (use the here-string / process-substitution form); and `test-automate-helpers.d/10-reconcile-status.sh` legs H4 (`ABROW='- [x] .supervisor/requirements/qh/05-abandoned.md  # abandoned: owner dropped track 2026-09-01'`) and H5b (`printf '# ab\n\n## Status: pending\n'`). Their fixtures are `pending` items, which become `conflict`, so re-ground both on status-less items (`# ab` with no `## Status:` line) so they still prove the ABANDONED path (never weaken their assertions), and add the conflict leg.
- **`loomwright/scripts/test-automate-helpers.sh`** — keep: `TAH_PARTS="01-config …"` is the ONE part list, and a file in `test-automate-helpers.d/` missing from it fails (`FAIL: test part not in TAH_PARTS`). Append `18-backlog`. The bundle runs the families as one file, so backlog.sh must parse under bash 3.2 (`set -u`-safe arrays).
- **`loomwright/scripts/test-automate-helpers-dispatch.sh`** — keep: `SEGMENTS="config runfile …"` order equals `_AH_HELP_SEGMENTS` + `incidental`, and the `fixture-set mutant` vacuity control stays. Insert `backlog` at the same position as in the dispatcher (after `right-size`, before `hdr-lanes`).
- **`loomwright/scripts/lane-policy.sh`** — keep: the catalog is the ONE gate authority (`_lp_row LP-FAIL      human-only 'Refine offline|Discard'` row shape: code, policy, `|`-joined labels, purpose). Follow `Adding, removing or relabelling a row: regenerate` and regenerate `docs/LANE_GATES.md`'s table with `lane-policy.sh catalog --markdown` in the same change. New rows are `human-only` (a status stamp is a real decision). Consumers: `check-gate-headers.sh` G2/G3/G5 (every code needs a `header: "<code>"` ask site quoting all labels, here in `commands/backlog.md`) and `test-lane-policy.sh`.
- **Gate-read data/doc surfaces (Subtask 2):** `loomwright/docs/prompt-token-budgets.json` — `check-token-budget.sh` fails CLOSED on a command doc with no `.commands[<stem>]` entry, and its `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror cell must equal the JSON budget; `loomwright/docs/prompt-history-refs-baseline.json` — one entry per scanned prompt and the baseline may only go down (`check-prompt-history-refs.sh` `raise_check`), so add `loomwright/commands/backlog.md` at its measured count (aim 0: no history in a runtime prompt) and change no other entry; `loomwright/commands/agent-help.md` — `check-doc-currency.sh` greps `^### .*/${cmd} ` per command file; `loomwright/skills/automate-loop/helpers.md` — in `test-loop-inventory.sh`'s automate-loop group, every `###`/`####` heading needs an inventory row, so edit table rows only and add no heading.
- **Consumed, not modified (mirror exactly):** `automate-helpers.d/right-size.sh` (`# --json — stdout is ONE JSON array`: join on its `item` display name); `automate-lanes.d/status.sh` (`parent_run_id: null, machine: $m, lanes: []`: read `.lanes[]`, with absent or failing output ⇒ no lane claims, never an error); `automate-trail.d/closeout.sh` (the done shape `<!-- loomwright:requirement-closeout -->\n## Status: done`. `backlog-stamp done` writes the same line set and order, with one `- **PR:**` line per PR as AC10 specifies).

## Closed enumerations touched

> Sibling greps at base `237adab`, run with `--exclude=CHANGELOG.md --exclude-dir=.supervisor --exclude-dir=.git` from the repo root.

- **help segment `backlog`** (sibling: `grep -rnF 'plan-waves right-size hdr-lanes'` → 2 hits in 2 files):
  - `loomwright/scripts/automate-helpers.sh` — `_AH_HELP_SEGMENTS="config runfile …"` — extend.
  - `loomwright/scripts/test-automate-helpers-dispatch.sh` — `SEGMENTS="config runfile …"` — extend.
- **test part `18-backlog`** (sibling: `grep -rnF '16-queue-gates 17-right-size'` → 1 hit):
  - `loomwright/scripts/test-automate-helpers.sh` — `TAH_PARTS="01-config …"` — extend.
- **gate codes `BL-VERIFY`, `BL-CONFLICT`** (sibling: `grep -rnF 'LP-FAIL'` → 10 hits in 5 files):
  - `loomwright/scripts/lane-policy.sh` — the `_lp_catalog_rows` catalog — extend.
  - `loomwright/docs/LANE_GATES.md` — the regenerated mirror table — extend.
  - `loomwright/agents/launch-pad.md`, `loomwright/commands/launch-pad.md`, `loomwright/docs/loop-inventory/launch-pad-autonomous.md` — LP-FAIL's own ask sites and inventory row — no change: they are Launch Pad's gates, not a list of every gate.
  - `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" (lists gates by name, so not a sibling hit, but a closed list of every question gate) — extend with one `/backlog --verify` row.
- **command `backlog`** (sibling: `grep -rnF 'commands/handoff.md'` → 10 hits in 7 files, plus `"handoff"` in `prompt-token-budgets.json`):
  - `loomwright/docs/prompt-history-refs-baseline.json` — one entry per scanned prompt — extend (`loomwright/commands/backlog.md`).
  - `loomwright/docs/prompt-token-budgets.json` `.commands` — extend, plus the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row — extend.
  - `loomwright/docs/vendor-coupling-manifest.json` — per-path allowance — extend ONLY if `check-vendor-coupling.sh` measures a vendor reference in `commands/backlog.md` or a new fixture (allowance + reason, the existing fixture convention); otherwise no change.
  - `loomwright/docs/command-parts/agent-help/knowledge.md`, `loomwright/scripts/build-handoff.sh`, `loomwright/scripts/test-build-handoff.sh`, `loomwright/scripts/fixtures/harvest-ledger/results.jsonl`, `docs/evidence/as24-terse-script-output.md` — handoff-specific text or frozen data — no change.
  - `loomwright/commands/agent-help.md` — `check-doc-currency.sh`'s `command-documented` check needs `### … /backlog ` — extend (plus the index line naming where it lives).
  - Count surfaces (`grep -rnE '\b23\b.{0,30}(command|slash)'`): `CLAUDE.md` (`(23 entry points)`), `README.md` (`(23 commands)`, `all 23 slash commands`), `.claude-plugin/README.md` (its intro paragraph and `# Slash commands (23)`), `loomwright/docs/command-parts/agent-help/guide.md` (`# Slash commands (23)`), and both manifest descriptions (`23 slash commands`). Manifest descriptions update in place (CLAUDE.md rule). Every other one is removed where the sentence survives without it, else updated, and `check-doc-currency.sh` decides.
- **command `backlog` in `loomwright/capabilities.json`** (found by name, not path: `grep -nF '"name": "handoff"' loomwright/capabilities.json` → 1 hit) — the generated `commands` list, checked by CI's `bash loomwright/scripts/build-capabilities.sh --check` — extend by regenerating with `bash loomwright/scripts/build-capabilities.sh` after `commands/backlog.md` lands. The lane never bumps, so nothing else regenerates it.
- **reconcile-status `info` row value `conflict`** (sibling: the `brief-shipped` info row; `grep -rnF 'info\t'` over its consumers):
  - `loomwright/scripts/automate-helpers.d/reconcile-status.sh` — OUTPUT block + usage line — extend.
  - `loomwright/scripts/fixtures/automate-helpers-help/reconcile-status.golden` — extend (same line).
  - `loomwright/skills/automate-loop/helpers.md` — the `reconcile-status` table row — extend (a row edit, no new `###` heading, so `test-loop-inventory.sh` needs no new row).
  - `loomwright/scripts/automate-next-step.sh` (`[ "$k" = plan ] || continue`) and `skills/automate-loop/resume.md` ("`info` rows are never appended") — no change: both skip `info` rows.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — appended-done-stamp ⇒ `done` | in `backlog.sh`, replace the `is_done` call in the stamp step with a read of the FIRST `## Status:` line only (Source text Validation 4) |
| `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — `- [x]` row ⇒ `merged_unstamped` (AC2) | delete the run-file plain check-off evidence lookup line in `backlog.sh` |
| `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — parked-into-X ⇒ X's state (AC3) | delete the follow-`into X` line in `backlog.sh` (item then reads `parked`) |
| `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — totals sum (AC4) | drop one state from the totals reduction in `backlog.sh` |
| `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — gh failure ⇒ `unverified` (AC5) | map a failed `gh pr list` to an empty OPEN list read as verified (`unverified` flag never set) |
| `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — stamp beats `## Current`, run `stale_run` (AC1) | swap precedence steps 1 and 4 in `backlog.sh` (the parked item reads `in_flight`) |
| `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — conflict + Kept-open clear/re-raise (AC1, AC6) | flip the run-date comparison `<=` → `<` (or delete the Kept-open lookup) in the shared conflict predicate |
| `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — `backlog-stamp` refuses without `--confirm` (AC10) | delete the `--confirm` guard line in `backlog-stamp` |
| `loomwright/scripts/test-automate-helpers.d/18-backlog.sh` — right-size called once (AC8) | move the `right-size --json` call inside the per-item loop (the call-count stub sees N calls) |
| `loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh` — conflict item left byte-unchanged (AC7) | delete the conflict-guard line added to `_rs_process_abandoned` in `loomwright/scripts/automate-helpers.d/reconcile-status.sh` |
| `loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh` — kept-open `pending` item left byte-unchanged (AC7) | drop the explicit-`pending`/`ready` skip from the guard in `_rs_process_abandoned`, keeping only the `_bl_is_conflict` check (the kept-open item then gets ABANDONED) |
| `loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh` — `brief-shipped` + abandoned row still stamped (AC7) | widen the guard's skip from explicit `pending`/`ready` to any `## Status:` line (the brief-shipped item is then left unstamped) |
| `loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh` — H4 (re-grounded on a status-less item) | delete `ABANDONED (%s)` in `loomwright/scripts/automate-helpers.d/reconcile-status.sh` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Engine: `item-state` / `backlog` / `backlog-stamp` family + reconcile-status conflict guard + fixtures + tests | AC1–AC10, AC13 (helpers + dispatch legs) | 7 modify, 4 create (+ fixture tree) | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Surfaces: `/backlog` command, gates, agent-help, budgets, counts, helpers.md, fragment, live-run evidence | AC11, AC12, AC13 (`test-lane-policy.sh`), AC14, AC15 | 16 modify (1 conditional), 3 create | `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1 — engine (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/automate-helpers.d/backlog.sh"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "item_state()"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "backlog_board()"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "backlog_stamp()"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "_ah_source backlog"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-helpers-help/backlog.golden"}
  - {kind: "file", path: "loomwright/scripts/fixtures/backlog-state/README.md"}
  - {kind: "file", path: "loomwright/scripts/test-automate-helpers.d/18-backlog.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-helpers.sh", name: "18-backlog"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "_bl_is_conflict"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.d/reconcile-status.sh", name: "_bl_is_conflict"}
requires: []
lanes:
  - "loomwright/scripts/automate-helpers.d/backlog.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/automate-helpers.d/reconcile-status.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help/backlog.golden"
  - "loomwright/scripts/fixtures/automate-helpers-help/reconcile-status.golden"
  - "loomwright/scripts/fixtures/backlog-state/**"
  - "loomwright/scripts/test-automate-helpers.d/18-backlog.sh"
  - "loomwright/scripts/test-automate-helpers.d/10-reconcile-status.sh"
  - "loomwright/scripts/test-automate-helpers.sh"
  - "loomwright/scripts/test-automate-helpers-dispatch.sh"
  - "loomwright/docs/vendor-coupling-manifest.json"
external_requires:
  - "jq (already required by every automate-helpers family)"
  - "gh CLI (optional at run time; every test stubs it via LOOMWRIGHT_GH_BIN)"

# Subtask 2 — command + surfaces + evidence (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/commands/backlog.md"}
  - {kind: "symbol", path: "loomwright/commands/agent-help.md", name: "/backlog"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "BL-VERIFY"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "BL-CONFLICT"}
  - {kind: "symbol", path: "loomwright/docs/LANE_GATES.md", name: "BL-VERIFY"}
  - {kind: "symbol", path: "loomwright/docs/prompt-token-budgets.json", name: "backlog"}
  - {kind: "symbol", path: "loomwright/docs/prompt-history-refs-baseline.json", name: "loomwright/commands/backlog.md"}
  - {kind: "file", path: "changelog.d/pa18a-backlog-board.md"}
  - {kind: "file", path: "docs/evidence/pa18a-backlog-board.md"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "backlog_board()"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/backlog.sh", name: "backlog_stamp()"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/automate-helpers.d/reconcile-status.sh", name: "_bl_is_conflict"}
lanes:
  - "loomwright/commands/backlog.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/command-parts/agent-help/ops.md"
  - "loomwright/docs/command-parts/agent-help/guide.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/prompt-history-refs-baseline.json"
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/docs/LANE_GATES.md"
  - "loomwright/skills/automate-loop/helpers.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - ".claude-plugin/README.md"
  - "README.md"
  - "CLAUDE.md"
  - "changelog.d/pa18a-backlog-board.md"
  - "docs/evidence/pa18a-backlog-board.md"
  - "loomwright/capabilities.json"
  - "loomwright/docs/vendor-coupling-manifest.json"
external_requires:
  - "gh CLI authenticated (the live AC14 run reads merged/open PRs read-only)"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `loomwright/docs/vendor-coupling-manifest.json` (each adds only its own files' allowances; legal, as #2 is reachable from #1) | YES (dependency) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1. The command doc, help text and evidence run quote the engine's real flags and output)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): ~30 files and >800 lines exceed one worker's context | HIGH | `context-bound` split. The engine lands first with its own tests, and surfaces/evidence follow against real output |
| Prior churn (postmortem ledger): touched manifests, `CLAUDE.md`, `.claude-plugin/README.md` and `ARCHITECTURE_CONTRACTS.md` carry 293 prior rounds, `self_heal_miss: yes` (drain_churn, convention_mismatch, self_heal_churn) | HIGH | Change count claims in place or remove them. After the edit, grep the OLD value `23` (command context) repo-wide, because a green `check-doc-currency.sh` is necessary, not sufficient. Run `bash scripts/ci-local.sh` before push |
| Re-grounding legs H4/H5b could hide a weakened ABANDONED path | MEDIUM | Their assertions stay byte-identical. Only the fixture item becomes status-less. The `delete ABANDONED (%s)` mutation row must turn H4 red |
| A per-item `gh` call over ~270 items is slow and rate-limited | MEDIUM | Exactly two cached `gh pr list` reads per pass (merged, open) with a fixed `--limit`, matched locally. The test stub counts calls |
| New gate codes trip `check-gate-headers.sh` G3/G5 or `test-lane-policy.sh` | MEDIUM | Add the catalog rows, regenerate `LANE_GATES.md` with `catalog --markdown`, and write each `header: "BL-…"` ask in `commands/backlog.md` quoting every label exactly |
| Fixtures quoting real requirement text raise `check-vendor-coupling.sh` | LOW | Write synthetic fixture items (no hook-event or harness tokens). Add a manifest allowance with a reason only if a measured reference is unavoidable |
| Live evidence run leaks an absolute home path (meta-sync `home_path` scrub) | MEDIUM | Item paths are repo-relative by construction, and the evidence file uses the `/Users/<name>/` placeholder form. Grep the file for `/Users/`/`/home/` before commit |
| Deferring the `wave` column could read as a dropped A2 item | LOW | Stated as out-of-scope MVP in Task (the header's A2 correction does not name it). Item 25 or a follow-up can add it |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-24-pa18a-backlog-board.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-24T08:13:46Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/690
- **Branch:** feature/pa18a-backlog-board
- **Files changed:** 72
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Shipped `/backlog`: the read-only item-state / backlog board (automate-helpers.d/backlog.sh), the owner-gated backlog-stamp writer, the reconcile-status D-conflict-1 guard, the hermetic fixtures and 18-backlog tests, the command doc with the BL-VERIFY/BL-CONFLICT gates, the count/budget/capability surfaces, live evidence (447 items, totals sum) and a changelog fragment (no bump). Phase 4.5 fixed 7 at-floor findings over 3 iterations (substring PR matching, AC5 gh-failure handling, stamp argument validation, slug-boundary and cross-folder match leaks). Iteration 3's fix (20e0500) was pushed but not re-reviewed, so this escalated by max iterations. Targeted tests are green on 20e0500: 18-backlog 97/97, 10-reconcile-status 60/60, dispatch 51/51. 4 LOW findings were dismissed as follow-ups (PR comment).

## Not verified
- **lane-status claims from a real lane wave** — only a stubbed lane-status --json fixture (subtask 1)
- **skills/automate-loop/helpers.md reconcile-status row** — Subtask 2's lane at the time; since updated by subtask 2 (subtask 1)
- **/backlog --verify owner flow (BL-VERIFY/BL-CONFLICT gates)** — needs an interactive owner session (subtask 1)
- **pin rows 1-12 through run-pin-mutations.sh** — prose mutations marked not_machine_applicable; verified by hand by the worker and the reviewers (subtask 1)
- **/backlog --verify interactive ask-and-stamp flow** — needs the owner answering each item; the live run wrote no stamp (subtask 2)
- **--verify publish via meta-sync.sh push** — needs a write to the shared metadata branch (subtask 2)
- **github: unverified path on live data** — gh worked on the live run; covered by the hermetic fixtures only (subtask 2)
