# Supervisor Job: next-step driver, part 2 — DRAIN and RUN bookkeeping move into the script

## Environment
- **Project:** automate-2026-10-15-163325/L10 (lane L10 clone of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (lane clone: out-of-scope findings go to `.supervisor/requirements/proposed/`, never a new Queue item)
- **Source requirement:** .supervisor/requirements/automate-speed/07-next-step-drain-and-run.md
- **Base commit:** c7d4f9a770326e6b6ebb975c5ac544f167c4667a

## Feasibility
**Verdict:** CAUTION

| # | Check | Verdict | Detail |
|---|---|---|---|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + BSD userland + jq, same as `automate-next-step.sh` and every `automate-*.sh` helper |
| 2 | Dependency Availability | GO | dependency 06 is `## Status: done` (PR #575 merged, in base c7d4f9a); every helper the new steps call already exists (`config-suppress` / `config-restore` / `config-orig`, `sidecar-check`, `reconcile-item`, `closeout`, `closeout-classify`, `learning-emit`) |
| 3 | Architecture Fit | GO | the driver already owns the tail and the fix-now re-drain `spawn`; this item adds steps in front of `gate` using the same sidecar, writers and instruction schema |
| 4 | Scope vs Supervisor Capability | CAUTION | one script + its test harness + ~9 golden cases + four prose/doc files + the inventory; large but one coherent change (same shape as item 06, which needed 2 sequential subtasks) |
| 5 | Hard Blockers | CAUTION | (a) the requirement's Scope list does not name the "Rate-limit park (end of RUN, before DRAIN)" check, yet it decides whether DRAIN runs: once the driver owns the RUN→DRAIN transition, leaving it in prose would make the model read the session log before reporting. This brief puts it IN scope (a `run-result` sub-step) — see Risk Assessment. (b) two RUN/DRAIN golden cases do not fit the current `test-automate-next-step.sh` harness: `learning-emit-end-of-drain` compares the postmortem ledger, not the run file, and `drain-pinned-start-line-current-not-set` expects exit 3 — the harness needs a ledger comparison and an exit-code expectation |

## Task
**Goal:** Extend `loomwright/scripts/automate-next-step.sh` so it owns every deterministic step around RUN and DRAIN — the `auto_review` suppress/restore that wraps RUN, the RUN result and session-id recording, the supervisor-result sidecar + `sidecar-check`, the rate-limit park check, the owned drain's pinned start line / `owned_drain_*` keys / review-heal sidecar + `sidecar-check`, the drain-superseded-by-merge branch (⇒ closeout), and learning-emit — so the model is told only "spawn `/autonomous --single-iteration --requirement <path>`" and "spawn the owned `/review-pr --until-mergeable` drain" and hands back the result; move the migrated prose out of the default-mode skill files into the `--legacy`-only file (owner decision D5), re-home its inventory rows, and repoint the tests that pin it.

**Problem Statement:**
The `/automate` coordinator needs the RUN/DRAIN middle of the per-item loop to be script-driven because it is the densest bookkeeping prose left in `per-item-loop.md` §6 steps 2–3 and §7 (plan doc §Why now: 62% of the read set is bookkeeping prose).
Currently, after item 06 only the tail (gate → park/closeout) is driven by `automate-next-step.sh`; the model still performs the config toggle, session-id line, sidecar writes, drain start/result lines, `owned_drain_*` line, superseded-by-merge branch and learning-emit by hand from prose. This causes large per-turn context and hand-executed steps that drift.
Success looks like: the driver prints `spawn` instructions for the two model-owned pieces of work and writes every other RUN/DRAIN line itself, byte-identical to today's golden run files.

## Acceptance Criteria
- [ ] AC1 — Given each RUN/DRAIN golden case under `loomwright/scripts/fixtures/automate-golden/` — at least `run-config-suppress-restore`, `run-record-pr`, `drain-owned-drain-started`, `drain-pinned-start-line-current-not-set`, `drain-superseded-by-merge`, `learning-emit-end-of-drain`, `rate-limit-park` and `dismissed-fix-now-re-drain` — when its `input.md` + `tree/` + `gh.stub` + `setup` are driven through `automate-next-step.sh` by a new per-case `next-step.results` file (the existing grammar, extended as needed: e.g. an `expect-exit: <n>` directive for the `current_not_set` exit 3 case and a ledger comparison against `expected.out` for `learning-emit-end-of-drain`), then the resulting run file is byte-identical to that case's existing `expected.md` (same normalisation as today: ISO ts → `<TS>`, scratch root → `<ROOT>`, case dir → `<CASE>`, work dir → `<TMP>`) and, for `learning-emit-end-of-drain`, the normalised ledger equals `expected.out` — asserted by `loomwright/scripts/test-automate-next-step.sh`, with every one of these cases added to its `REQUIRED_CASES` list. Existing cases' `input.md` / `expected.md` / `expected.out` / `steps` are read-only; model-authored free-text lines (e.g. `ran /autonomous → PR … (SUPERVISOR_RESULT completed: …)`, `drain round 1: …`, `drain READY (…)`) arrive through `--result` (a `progress_note`-style field / list), never by editing an expected file.
- [ ] AC2 — Given a pass that already emitted its owned drain `spawn`, when the caller asks the driver for another owned drain spawn for the same pass (the same item + PR, before that drain's report arrived, or after it for any reason other than the one sanctioned fix-now re-drain), then `automate-next-step.sh` exits 2 with a named status on stderr (e.g. `next-step: drain_already_owned — …`), prints no instruction, and the run file and every `.supervisor/` sidecar are byte-unchanged; the sanctioned fix-now re-drain still runs at most once per item (today's `fix_now_reentered` rule) — asserted by a `test-automate-next-step.sh` leg.
- [ ] AC3 — Given a malformed pre-existing `.supervisor/config.json` (not parseable JSON), when the driver reaches the RUN step, then it aborts before emitting the `/autonomous` spawn with a named status on stderr (e.g. `next-step: config_malformed — …`, the helper `config-suppress` exit 2 surfaced), writes no `auto_review suppressed` line, leaves `config.json` byte-unchanged and creates no `<run_id>.config-backup.json` (today's behaviour) — asserted by a `test-automate-next-step.sh` leg.
- [ ] AC4 — Given a drain that returns without a terminal `REVIEW_HEAL_RESULT` while its PR reads `merged` (`reconcile-item`), when the driver receives that drain result, then it writes `owned_drain_result: superseded_by_merge` (keeping the pass's `owned_drain_started`), the `<ts> drain superseded_by_merge — PR merged before a terminal REVIEW_HEAL_RESULT` line, writes NO `<run_id>.review-heal-result.md`, runs NO `learning-emit`, skips GATE and the dismissed-findings step, and closes the item out (`closeout … --session-id <sid>` classified by `closeout-classify`, then `## Status: paused` + `pause_reason: awaiting_go` + run-lock release) — the `drain-superseded-by-merge` golden case through the driver is byte-identical (AC1) and a leg asserts no review-heal sidecar and no new ledger line exist; any other `reconcile-item` verdict writes nothing for the drain (the item stays `running`).
- [ ] AC5 — Given the config toggle, when the RUN step runs, then the suppress happens BEFORE the `/autonomous` spawn is printed and the restore runs when the RUN result (or a RUN failure report) is handed back and BEFORE the owned drain spawn is printed — never at DRAIN — with `auto_review_original` read through `config-orig <config> <backup>` (backup-first, call-order-safe), restore = overwrite-from-backup or delete-if-originally-absent, the transient backup deleted on a clean restore; the RECONCILE crash-restore of a stranded backup stays where it is (item 08) and unchanged.
- [ ] AC6 — Given the migrated tree, when `bash loomwright/scripts/test-loop-inventory.sh` runs, then it passes; every inventory row whose prose was migrated (the RUN / DRAIN / Rate-limit / Learning-emit / §7 rows, AL-253…AL-266, AL-288…AL-291, AL-298…AL-307, AL-380…AL-393 at base) has home `script:automate-next-step.sh <step>` naming a real `case` arm of the driver (or `rationale:`/`global` with the reason when a row is not a step) — except AL-387 (§7's "Crash-restore" bullet), whose home points at `resume.md`'s RECONCILE crash-restore step (it stays prose there, item 08), never a driver step; every golden case driven by the driver is named in the test cell of the rows it covers.
- [ ] AC7 — Given the migrated steps, when the default-mode skill files are read, then their step-by-step RUN/DRAIN prose is gone from `per-item-loop.md` (replaced by a short "run `automate-next-step.sh`" pointer per step); the only remaining copy is the `--legacy`-only file (`skills/automate-loop/legacy-tail.md`, extended, or a sibling read only under `--legacy`), moved verbatim, and `commands/automate.md`'s `--legacy` row and Step 0 entry say `--legacy` now selects the pre-driver RUN, DRAIN and tail prose; a committed evidence file `docs/evidence/as07-next-step-drain-and-run.md` contains `wc -c loomwright/skills/automate-loop/*.md` before (baseline `330343 total`) and after, the DEFAULT-mode read-set size before and after (Step 0's sequential read set, excluding the `--legacy`-only file), the inventory GAP count before (132) and after, and `<passed>/<total>` for each Validation-step test; the PR body links to it.
- [ ] AC8 — Given the tests that pin the moved prose — `loomwright/scripts/test-automate-dismissed.sh`'s B leg "the PICK ask sits inside §6 step 1 (PICK), before RUN" (`ln_of "$SK" "2. **RUN**"`), its single-drain qualifier `SURF` anchors (`3. **DRAIN** — own **exactly ONE** inline`, `suppresses the default dispatch and owns exactly ONE inline drain`, `After suppression, DRAIN owns **exactly ONE** inline`, plus the SKILL.md / `commands/automate.md` ones that stay) and its unqualified-"exactly ONE inline" scan — when the prose moves, then each pin still finds its anchor exactly where the rule now lives (moved verbatim, so the assembled `$SK` still contains it once) or is repointed in the same change, every pointer stub left in `per-item-loop.md` that mentions an owned inline drain carries the qualifier `at most one owner-requested fix-now re-drain per item`, no stub reuses an anchor a first-match leg reads, and `bash loomwright/scripts/test-automate-dismissed.sh` and `bash loomwright/scripts/test-automate-helpers.sh` report 0 failures.
- [ ] AC9 — Given the change, when `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 | sort -u` runs, then it prints exactly the same file list as base c7d4f9a (the driver, its test, the legacy file and the evidence file carry the string only negated, if at all) — asserted by the existing `test-automate-next-step.sh` S leg.

## Validation (must pass before merge)
1. `bash loomwright/scripts/test-automate-next-step.sh`, `test-automate-golden.sh`, `test-automate-helpers.sh`, `test-automate-dismissed.sh`, `test-loop-inventory.sh`, `test-automate-loop-split.sh`, `test-result-schemas-split.sh`, `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh`; report `<passed>/<total>` in the evidence file.
2. Mutation controls (inside `test-automate-next-step.sh`, each mutant gated non-empty + differs + `bash -n`): (a) a driver copy that restores the toggle after DRAIN instead of after RUN (the restore moved from the RUN-result step to the drain-result step) ⇒ a leg goes red (the `run-config-suppress-restore` parity and/or an order leg asserting `config.json` is restored before the drain spawn is printed); (b) a driver copy whose second-drain refusal is removed ⇒ the AC2 leg goes red.
3. Running system (scoped to what a lane can run hermetically, the same scoping item 06 used): in a scratch `git init` repo (gh stubbed, no network), drive one item from PICK (`## Current` `status: running`, `picked` line) through the driver: the RUN step's `spawn` answered with a fixed `SUPERVISOR_RESULT` / session id, the DRAIN step's `spawn` answered with a fixed READY `REVIEW_HEAL_RESULT`, on to the tail; paste the run file's `## Progress` lines from `auto_review suppressed` to `drain READY`, fenced, into the evidence file AND into the PR body under a `validation 3` line. Validation 1 (each suite's `<passed>/<total>` summary line) and Validation 2 (each mutation control's verdict line) are ALSO pasted, fenced, under `validation 1` / `validation 2` lines in the PR body (the `validation-gate` reads all three from the PR body); the evidence file stays the authority.

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound — subtask 1 (driver steps + harness extensions + ~9 `next-step.results` fixtures, several hundred lines of new bash that must read the golden cases and the helper contracts) and subtask 2 (prose move across `per-item-loop.md` ~80KB, the `--legacy` file, the ~190KB inventory, MAP.tsv, SKILL.md index/§1.5/§3 rows and the pinned-prose tests) each fill a worker context; subtask 2 consumes subtask 1's step names.
- **Lane PR rule:** this runs in a `--parallel` lane — ship a `changelog.d/as07-next-step-drain-and-run.md` fragment (`<!-- bump: minor -->`), never a version bump; `bash scripts/check-version-bump.sh` passes.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Phase 3: File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|---|---|---|---|
| driver | `loomwright/scripts/automate-next-step.sh` | — | HIGH |
| driver-test | `loomwright/scripts/test-automate-next-step.sh`; `loomwright/scripts/fixtures/automate-golden/<RUN/DRAIN cases>/` (a new `next-step.results` per case only — `input.md`/`expected.md`/`expected.out`/`steps` unchanged) | — | HIGH |
| schema + release | `loomwright/docs/result-schemas/automate-run.md` (§"next-step instruction": new `what` values, new `--result` shapes, the `step` list) | `changelog.d/as07-next-step-drain-and-run.md`, `docs/evidence/as07-next-step-drain-and-run.md` | HIGH |
| prose migration | `loomwright/skills/automate-loop/per-item-loop.md`, `loomwright/skills/automate-loop/legacy-tail.md`, `loomwright/skills/automate-loop/SKILL.md` (split index headings, §1.5 driver row, §3 transition-table rows), `loomwright/commands/automate.md` (`--legacy` row, Step 0 entry, step-4 map line keeping its qualifier); `resume.md`, `modes-and-merge-gate.md`, `invariants.md`, `lanes.md`, `intake.md`, `branch-mode.md`, `command-lanes.md` ONLY where they cite a moved anchor and the pointer must change | — | MEDIUM |
| pinned-prose tests | `loomwright/scripts/test-automate-dismissed.sh` (B "before RUN" leg / SURF anchors / qualifier scan — only if a move cannot keep the anchor byte-identical), `loomwright/scripts/test-automate-helpers.sh` (only if a leg turns out to read moved text) | — | MEDIUM |
| inventory + map | `loomwright/docs/loop-inventory/automate-loop.md`, `loomwright/scripts/fixtures/automate-golden/MAP.tsv` | — | HIGH |

> **Validator-owned surfaces:** `test-loop-inventory.sh` (every `###` heading of every `skills/automate-loop/*.md` needs a row; `script:<file> <sub>` must be a real case arm; `## Counts` must match the table), `test-automate-golden.sh` (units extracted live from `resume.md` / `per-item-loop.md` / `modes-and-merge-gate.md`; deleting §6 items 2/3 makes `|L1.2` / `|L1.3` stale and renumbering 4–6 makes `|L1.4`–`|L1.6` stale — every removed unit's MAP row removed, every new unit mapped, in the same change), `test-automate-loop-split.sh` (SKILL.md index ↔ split files incl. the "Cited sub-section anchors" table; Step 0 list), `test-result-schemas-split.sh` (owns `docs/result-schemas/*.md`), `check-doc-currency.sh`, `test-citation-drift.sh`, `check-token-budget.sh` (`.skills[automate-loop]` headroom ≈5.3k proxy tokens, `.commands[automate]` ≈363 — if either goes over, raise its entry in `loomwright/docs/prompt-token-budgets.json` and the mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" in the same change — both are in subtask 2's lanes for that case only).

## Touched-file invariants
> Grounded at base `c7d4f9a770326e6b6ebb975c5ac544f167c4667a`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-next-step.sh`** — keep: the closed instruction set `{"do":"spawn",…}` / `{"do":"ask",…}` / `{"do":"park",…}` / `{"do":"done",…}`; the exit-code contract `Exit codes: 0 an instruction printed (or a NEXT_STEP_UNTIL stop); 1 a helper / writer failure` with exit 2 = nothing written (`[ "$NS_RC" = 2 ] && exit 2`); the idempotent re-print (`if [ -n "$pending" ]; then printf '%s\n' "$pending"; exit 0; fi`); the sidecar binding `ns_bound` (pending state bound to item + PR); REPORT VALIDATION before the first write (`ns_check_report`, `ns_field_ok`); the WRITERS rule `The run file is written ONLY through automate-helpers.sh` (`ns_call_writer`, which surfaces a non-zero exit — `progress-append`'s exit 3 `current_not_set` included — never swallows it); the fix-now once-only rule (`st_set fix_now_reentered true` in `ns_spawn_fixnow`, offer gated by `ns_fixnow_reentered`); reuse: `ns_emit` / `ns_emit_park` / `ns_progress` / `ns_status` / `ns_lock` / `ns_release` / `st_set` / `st_del`, and the overridable side-effect seams `NEXT_STEP_WATCH_CMD` / `NEXT_STEP_NOTIFY_CMD` / `NEXT_STEP_LOCK_CMD` (add a seam rather than running a non-hermetic command — e.g. the learning-emit `gh pr view … files` fetch and the plugin version read); mirror: the driver never merges — it calls `automate-helpers.sh gate-eval` only; never a multi-line value through `awk -v` (SKILL.md Anti-Patterns: BSD awk "newline in string") when building a `runfile-write` payload; fired by: the model at §6 (no hook); pinned by: `loomwright/scripts/test-automate-next-step.sh` (`REQUIRED_CASES`, the D leg that compares the schema's `step` list with the real `case` arms, the S leg's positive-grep list).
- **`loomwright/scripts/automate-next-step.sh` header text** — the USAGE entry-point paragraph (`Entry point: "drain result reported"` … `(item 07 moves it here later)`) and the Honest-limits sentence naming DRAIN/RUN bookkeeping (item 07) as still prose become false after this change: rewrite both in the same change.
- **`loomwright/scripts/automate-helpers.sh`** (NOT edited — called; the config subcommands live in `loomwright/scripts/automate-helpers.d/config.sh`): `config-suppress` aborts exit 2 on a malformed config (`config.sh`: `malformed ⇒ abort`; SKILL.md §1.5 row: `malformed ⇒ abort exit 2`); `config-orig <config_path> [<backup_path>]` must get the backup path once suppress ran (SKILL.md §1.5: "pass `<backup_path>` whenever `config-suppress` has already run"); `progress-append` guard: a `picked `, `ran /autonomous` or `owned drain started` line over an unset `## Current` exits 3 `current_not_set` with the line appended (`drain-pinned-start-line-current-not-set` expects exactly that); `current-set` is the only writer of `## Current`'s item / `pause_reason` lines (`current-set <rf> --item <path> --status running --pr <url> --branch <b>` BEFORE the `ran /autonomous → PR` line); `learning-emit` always exits 0 and its result never changes a decision; `sidecar-check` always exits 0 (`ok <path>` / `fail <path>: <reason>`, a `fail` line `progress-append`ed as `<ts> sidecar-check: fail …`, never a park).
- **`loomwright/scripts/test-automate-next-step.sh`** — keep: every existing leg (G/I/Q/S/C/V/B/D) green and its mutation controls (`gated non-empty + differs + bash -n`); the S-leg mutant built at run time so the test source never holds the positive merge literal on one line; the hermetic setup (`mktemp -d`, sandboxed HOME, stub `gh` first on PATH); extend the `next-step.results` grammar (`env:` / `pre:` / `call:` / `expect:`) additively — document any new directive in the header's grammar block.
- **`loomwright/scripts/test-automate-golden.sh`** (NOT edited — must stay green): M5/M8 need `### Termination (two exits)` in `per-item-loop.md` exactly once; `FAIL: stale map row <id>` fires when a unit disappears — update `MAP.tsv` in the same change.
- **`loomwright/scripts/test-loop-inventory.sh`** (NOT edited): home grammar `prose, script:<file>[ <sub>], hook:<leaf>, step-scoped, global or rationale:<doc>#<anchor>`; a `prose` row needs a live anchor in its file; `## Counts` equals the table.
- **`loomwright/scripts/test-automate-dismissed.sh`** (EDITED only if needed): `SK` assembled by `fixtures/automate-loop-split/assemble.sh` from SKILL.md + every split file (`legacy-tail.md` after `per-item-loop.md`); `ln_of "$SK" "2. **RUN**"`; the `SURF` list requires `first_line "$SK" <anchor>` to contain `at most one owner-requested fix-now re-drain per item`; the unqualified scan covers every line matching `exactly ONE\*\* inline|exactly ONE inline|ONE owned inline|ONE inline \`/review-pr` in `$SK` and `commands/automate.md`.
- **`loomwright/scripts/test-automate-helpers.sh`** (EDITED only if a leg reads moved text): keep every existing leg green and every mutation control; `QG_LOOP="$HERE/../skills/automate-loop/legacy-tail.md"` (item 06's repoint) stays — repoint only an anchor that moved verbatim, never delete a mutant to make the suite pass.
- **`loomwright/docs/prompt-token-budgets.json`** (EDITED only if a ceiling is exceeded): entries are measured + ~10% (`"automate-loop": {"budget": 87895, "measured": 79904, …}`); `measured` must equal the mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", changed in the same commit; `check-token-budget.sh` fails CI CLOSED.
- **`loomwright/commands/automate.md` + `loomwright/scripts/test-automate-loop-split.sh`** — keep: Step 0's index-only list names every split file in documented order; `legacy-tail.md` stays an `**Only when** --legacy was passed` entry (never **Always**); `4. **Per-item loop.**` keeps `at most one owner-requested fix-now re-drain per item`; command-doc ceiling ≈363 proxy tokens of headroom.
- **`loomwright/skills/automate-loop/SKILL.md`** — keep: every `### ` heading of a split file appears in the index under its `<!-- split:begin <file> -->` block; the §1.5 table is "the SPEC each subcommand implements" (update the `automate-next-step.sh` row to name the RUN/DRAIN steps; do not restate the driver header); the `- **Double until-mergeable drain.**` and `- Single drain: \`.auto_review:false\` set before` lines keep the qualifier.

## Closed enumerations touched
> Sibling grep at base `c7d4f9a`: `grep -rnF '"fix-now re-drain"' loomwright/` → hits in `loomwright/scripts/automate-next-step.sh` (`what: "fix-now re-drain"`), `loomwright/scripts/test-automate-next-step.sh`, `loomwright/docs/result-schemas/automate-run.md` (the `spawn` row), `loomwright/skills/automate-loop/per-item-loop.md` (§6 step 3 pinned-line note — prose, moves).

- **New `spawn.what` values** (sibling: `"fix-now re-drain"`) — e.g. `"/autonomous run"` and `"owned drain"` (final strings the worker's) — must be named in:
  - `loomwright/docs/result-schemas/automate-run.md` §"next-step instruction" — the `spawn` row of the closed `do` table — extend.
  - `loomwright/scripts/automate-next-step.sh` — the emitter — extend.
  - `loomwright/scripts/test-automate-next-step.sh` — the legs that assert instruction shapes — extend.
- **New driver steps** (sibling: `fix-now`) — e.g. `run`, `run-result`, `drain`, `drain-result` — must be named in:
  - `loomwright/scripts/automate-next-step.sh` — `ns_dispatch` `case` arms and the header's STEPS block — extend.
  - `loomwright/docs/result-schemas/automate-run.md` — the "Common fields" `step` list (`one of the driver's case arms: gate, validation, …`) — extend; the D leg checks it against the arms.
  - `loomwright/docs/loop-inventory/automate-loop.md` — homes `script:automate-next-step.sh <step>` — extend.
- **No new** `pause_reason` / `status` / `owned_drain_result` / `escalation_cause` value: `rate_limit`, `superseded_by_merge`, `awaiting_go` already exist in `current-set`'s enums. New named exit-2 statuses (`drain_already_owned`, `config_malformed` — final names the worker's) are stderr messages, not a closed list.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-automate-next-step.sh` — run-config-suppress-restore parity / restore-before-drain order leg | move the `config-restore` call from the RUN-result step into the drain-result step of a driver copy (Validation 2a) |
| `test-automate-next-step.sh` — AC2 second-drain refusal leg | delete the second-drain refusal check in a driver copy (Validation 2b) |
| `test-automate-next-step.sh` — AC3 malformed-config leg | in a driver copy, ignore the non-zero `config-suppress` exit and emit the `/autonomous` spawn anyway |
| `test-automate-next-step.sh` — AC4 superseded leg | in a driver copy, write the review-heal sidecar on the superseded path |
| `test-automate-next-step.sh` — drain-pinned-start-line-current-not-set exit-3 expectation | in a driver copy, swallow the `progress-append` exit status (`|| true`) on the drain start line |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory

## Design notes (binding for the worker)
- **Entry point.** After PICK (`## Current` `status: running`, `pr: null`, last segment starts with `picked <item>`), the loop calls the driver once (e.g. `automate-next-step.sh <rf> --start run --mode … --session-id …` — exact flag the worker's, documented in the header and schema); the driver suppresses the toggle and prints `{"do":"spawn","what":"/autonomous run",…}` carrying the exact invocation (`/autonomous --single-iteration --requirement <item>` + the passthrough flags `--non-interactive-fallback` / `--notify` / `--cheap` / `--max-tokens N` the loop hands it — passthrough flags are NOT persisted in the run file). The model answers with a RUN report (`--result`: the verbatim `SUPERVISOR_RESULT` text or a file path to it, plus the `.supervisor/state.md` session id, plus optional free-text note(s)); the driver restores the toggle, records the session-id line, the PR via `current-set` BEFORE the `ran /autonomous → PR` line (or the pinned `ran /autonomous — no PR: <status_reason> (<why>)` line), writes `<run_id>.supervisor-result.md` verbatim + `sidecar-check`, runs the rate-limit check (the session-log read the moved prose specifies; a hit parks `rate_limit` + releases the lock), then prints `{"do":"spawn","what":"owned drain",…}` with `/review-pr <pr> --until-mergeable --no-auto-postmortem`. The drain report (the verbatim `REVIEW_HEAL_RESULT`, or a "no terminal block" report) is handed back; the driver writes the pinned start line (head sha from the report or a seam), `owned_drain_*`, the review-heal sidecar + `sidecar-check`, learning-emit, or the superseded branch, then continues at today's `gate`. The fix-now re-drain spawn's `then:` text is updated so its pinned lines / `owned_drain_*` are written by the driver too.
- **Back-compat.** The existing tail entry (a drain report `--result` with nothing pending while `## Current` reads `running`) keeps working unchanged — every existing leg stays green.
- **Free text.** Lines that are model-authored in the recorded runs (`ran /autonomous → PR … (…)`, `drain round N: …`, `drain READY (…)`, `auto_review suppressed (backup …) — running /autonomous --single-iteration`) must reproduce the golden bytes: driver-authored where the format is fixed, `--result` free text where it is not (document which in the schema).
- **Already migrated by item 06 (not re-done here):** the requirement's Scope also lists `validation-gate`, the dismissed-findings drafts and the owner decision step (`ask` with its can't-ask status) — those are the driver's existing `validation` / `dismissed` / `decide` steps, with their golden cases already carrying `next-step.results`.
- **Not migrated (Non-goals):** PICK / RECONCILE / resume and the RECONCILE crash-restore of a stranded config backup (item 08); fresh sessions (item 09).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Driver RUN/DRAIN steps, schema, harness extensions + `next-step.results` fixtures, changelog fragment, evidence (driver legs) | AC1–AC5, AC9, Validation 1–3 (driver legs) | 3 modify + ~9 fixture files, 2 create | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Prose move to the `--legacy` file, pointers, SKILL.md index/§1.5/§3, `commands/automate.md`, inventory re-home, MAP.tsv, pinned-prose tests, evidence (after-values) | AC6–AC8, Validation 1 (inventory/golden/split/dismissed/helpers/doc-currency/citation/token legs) | ~9 modify | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-next-step.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-next-step.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-golden/run-config-suppress-restore/next-step.results"}
  - {kind: "file", path: "loomwright/scripts/fixtures/automate-golden/drain-superseded-by-merge/next-step.results"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "next-step instruction"}
  - {kind: "file", path: "changelog.d/as07-next-step-drain-and-run.md"}
  - {kind: "file", path: "docs/evidence/as07-next-step-drain-and-run.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/fixtures/automate-golden/*/next-step.results"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "changelog.d/as07-next-step-drain-and-run.md"
  - "docs/evidence/as07-next-step-drain-and-run.md"
external_requires:
  - "jq on PATH (already required by automate-helpers.sh)"

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/skills/automate-loop/legacy-tail.md"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "--legacy"}
  - {kind: "symbol", path: "loomwright/docs/loop-inventory/automate-loop.md", name: "script:automate-next-step.sh"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/automate-next-step.sh"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-automate-next-step.sh"}
lanes:
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/skills/automate-loop/legacy-tail.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/automate.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/scripts/fixtures/automate-golden/MAP.tsv"
  - "loomwright/scripts/test-automate-dismissed.sh"   # pin repoint only, if a move cannot keep an anchor byte-identical
  - "loomwright/scripts/test-automate-helpers.sh"   # pin repoint only, if a leg reads moved text
  - "loomwright/skills/automate-loop/resume.md"   # only a cross-reference pointer to a moved anchor
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"   # only a cross-reference pointer
  - "loomwright/skills/automate-loop/invariants.md"   # only a cross-reference pointer
  - "loomwright/skills/automate-loop/lanes.md"   # only a cross-reference pointer
  - "loomwright/skills/automate-loop/intake.md"   # only a cross-reference pointer
  - "loomwright/skills/automate-loop/branch-mode.md"   # only a cross-reference pointer
  - "loomwright/skills/automate-loop/command-lanes.md"   # only a cross-reference pointer
  - "loomwright/docs/prompt-token-budgets.json"   # only if a ceiling is exceeded
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"   # only the matching Prompt Token Budgets mirror row
  - "docs/evidence/as07-next-step-drain-and-run.md"   # sequential share: subtask 2 fills the after-values
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | `docs/evidence/as07-next-step-drain-and-run.md` | YES (ordered by `requires`) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1 — needs the driver's step names)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `loomwright/skills/automate-loop/SKILL.md` §1.5 (helper contracts), `per-item-loop.md` §6 steps 2–3, "Rate-limit park", "Learning-emit at end-of-DRAIN", §7; `skills/unit-testing/SKILL.md` |
| 2 | `loomwright/skills/automate-loop/SKILL.md` (split index), `loomwright/docs/loop-inventory/automate-loop.md` header (home grammar); `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Rate-limit park check is not in the requirement's Scope list but sits on the RUN→DRAIN seam the driver now owns (source: Feasibility (Phase 2.5)) | MEDIUM | Migrated as part of the RUN-result step; its golden case `rate-limit-park` is driven through the driver (AC1); if the owner disagrees it is a single step to leave in prose |
| Two golden cases do not fit the current harness (ledger output; exit 3) (source: Feasibility (Phase 2.5)) | MEDIUM | Extend the `next-step.results` grammar additively (an exit expectation, a ledger compare); never edit `expected.*` |
| Deleting §6 items 2–3 and the §7 / Rate-limit / Learning-emit headings breaks `test-automate-golden.sh` (stale map rows, renumbered `L1.k`) or `test-loop-inventory.sh` / `test-automate-loop-split.sh` | HIGH | Move headings verbatim into the `--legacy` file, update MAP.tsv, the inventory and the SKILL.md index in the same commit; keep `### Termination (two exits)` once in per-item-loop.md; run every Validation 1 suite before done |
| Pointer stubs reuse a first-match anchor or drop the single-drain qualifier (`test-automate-dismissed.sh` SURF / qualifier scan) | HIGH | Stubs carry `at most one owner-requested fix-now re-drain per item` whenever they mention an owned inline drain and never carry `2. **RUN**` / `3. **DRAIN** — own` anchors (those live once, moved verbatim) |
| Toggle restored at the wrong seam re-opens the double-drain race (both default dispatches fire during `/autonomous`) | HIGH | AC5 + Validation 2a mutation control |
| A second owned drain for the same pass | HIGH | AC2 refusal + Validation 2b mutation control |
| A second merge path appears in the driver | HIGH | Driver calls `gate-eval` only; existing S leg + its mutant (AC9) |
| `commands/automate.md` has ≈363 proxy tokens of headroom | MEDIUM | Keep the `--legacy` wording short; raise the budget entry + ARCHITECTURE_CONTRACTS mirror row only if needed |
| `validation-gate` reads `## Validation` entries 1–3 from the PR body and marks each NOT-RUN without a matching fenced `validation <n>` passage | MEDIUM | FINALIZE pastes fenced output under `validation 1` / `validation 2` / `validation 3` lines in the PR body and links the evidence file |
| Validation 3 is a hermetic scratch-repo drive, not a live `/automate` session consuming the RUN/DRAIN instructions | LOW | Stated honestly in the evidence file's "Not verified" note; the live consumption is item 08's path |

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-17-next-step-drain-and-run.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-17T08:57:10Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/594
- **Branch:** feature/as07-next-step-drain-and-run
- **Files changed:** 23
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** automate-next-step.sh now owns RUN and DRAIN bookkeeping (--start run|drain; config toggle wrapping RUN, sidecars + sidecar-check, rate-limit check, owned-drain lines, superseded_by_merge close-out, learning-emit); 8 RUN/DRAIN golden cases byte-identical through it; RUN/DRAIN prose moved to legacy-tail.md (--legacy); inventory GAP 132→125. Phase 4.5: 3 reviews / 2 fix rounds (reserved-prefix forgery, rate-limit empty session id, B-leg re-anchor, AL-387 home; reader-prefix completeness, RUN-report replay), final review PASS (2 LOW).

## Not verified
- **live /automate session consuming the /autonomous run and owned drain spawns** — hermetic scratch drive only; live consumption is item 08's path (subtask 1)
- **test-automate-helpers.sh W19 on a clean checkout** — fails identically on base c7d4f9a with the same gitignored queue; skips in CI (subtask 1)
- **live /automate session consuming the RUN/DRAIN prose pointers** — no live model run; hermetic driver legs only (subtask 2)
