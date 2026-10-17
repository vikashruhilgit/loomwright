# Supervisor Job: next-step driver, part 1 — the script owns the run file and the loop's tail (gate, park, closeout)

## Environment
- **Project:** automate-2026-10-15-163325/L9 (lane L9 clone of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (lane clone: no new follow-up items mid-run — out-of-scope findings go to `.supervisor/requirements/proposed/`)
- **Source requirement:** .supervisor/requirements/automate-speed/06-next-step-driver-tail.md
- **Base commit:** 142540b8210a4b206e87e2b4349999c9978f8e29

## Feasibility
**Verdict:** CAUTION

| Check | Result | Note |
|---|---|---|
| Tech stack | GO | bash 3.2 + jq, same as every `automate-*.sh` helper |
| Dependencies | GO | deps 04 (inventory), 05 (golden cases), 25 (load-by-mode) are `## Status: done` on this base |
| Architecture fit | GO | `automate-helpers.sh` already implements every tail step; the driver sequences them |
| Scope | CAUTION | one script + its test + four prose/doc files + the inventory + MAP.tsv; large but one coherent change |
| Hard blockers | CAUTION | the requirement's Scope line "the automate-loop group's GAP count then reaches 0" is not reachable by linking golden cases: 147 rows are GAP today and many are `story`/`rule` rows no golden case covers (see Risk Assessment). It is NOT an acceptance criterion; this brief scopes it to "link every case, report the GAP count before/after" |

## Task
**Goal:** Add `loomwright/scripts/automate-next-step.sh`, the single reader and writer of a `/automate` run file for the loop's TAIL. Called with the run file it runs every deterministic tail step itself and prints exactly ONE JSON instruction for the model (`{"do":"spawn",…}` / `{"do":"ask",…}` / `{"do":"park",…}` / `{"do":"done"}`); the model reports a step's result with `--result <json>`. Migrate GATE (validation gate, safe-mode park, `--auto-merge` → `gate-eval`), the park writes (park state, merge-watcher arming, notify, `run-lock.sh release`) and closeout/SYNC + CHECK OFF into it; replace their prose in `skills/automate-loop/per-item-loop.md` / `modes-and-merge-gate.md` with "run next-step"; keep the old prose path selectable with `--legacy` in `commands/automate.md`.

## Acceptance Criteria
- [ ] Given each TAIL golden case under `loomwright/scripts/fixtures/automate-golden/` (at least: `escalated-park`, `park-first-ready-park`, `park-first-decisions-recorded`, `gate-validation-gate-unrun-escalated`, `gate-validation-waive`, `gate-eval-merge`, every `gate-eval-*-park`, `sync-closeout-no-trail`, `check-off-progress`, `termination-limit-reached`, `termination-queue-resolved`, `closeout-leftover-gate-non-interactive`, `dismissed-findings-decision-step`), when its `input.md` + `tree/` + `gh.stub` + `setup` are driven through `automate-next-step.sh` (with the case's fixed model/owner answers supplied as `--result` JSON from a new per-case `next-step.results` file), then the resulting run file is byte-identical to that case's existing `expected.md` (same normalisation as `test-automate-golden.sh`: ISO ts → `<TS>`, scratch root → `<ROOT>`) — asserted by `loomwright/scripts/test-automate-next-step.sh`.
- [ ] Given the same run file, when `automate-next-step.sh <rf>` runs twice with no `--result`, then both calls print the byte-identical instruction and the run file (and every sidecar) is byte-unchanged after the second call — asserted by `test-automate-next-step.sh`.
- [ ] Given a park in a non-interactive run (`--non-interactive`), when the driver reaches a question gate (validation `AUT-WAIVE`, dismissed-findings decisions), then the instruction is never `{"do":"ask"}`: it carries the gate's named can't-ask outcome (e.g. the `escalated` park with `escalation_cause: validation_unrun`; `pending_decisions: <n>` recorded) — asserted by `test-automate-next-step.sh`. Every interactive `{"do":"ask"}` carries `question`, `header` (catalog code or empty for human-only gates), `options` (catalog labels) and `cant_ask` (the named status the caller uses when it cannot ask).
- [ ] Given the change, when `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not " | cut -d: -f1 | sort -u` runs, then it prints exactly the same file list as the base commit 142540b — baseline: `loomwright/commands/agent-help.md`, `loomwright/docs/loop-inventory/automate-loop.md`, `loomwright/scripts/automate-helpers.sh`, `loomwright/scripts/fixtures/automate-golden/drain-superseded-by-merge/tree/dot-supervisor/requirements/automate-followups/11-post-park-lifecycle.md`, `loomwright/scripts/result_block_parser.py`, `loomwright/scripts/test-automate-helpers.sh`, `loomwright/skills/automate-loop/modes-and-merge-gate.md`, `loomwright/skills/automate-loop/per-item-loop.md`; `automate-next-step.sh` CALLS `automate-helpers.sh gate-eval` and contains the string only inside a negated sentence, if at all — asserted by a `test-automate-next-step.sh` leg that also proves a mutant driver with an unguarded positive mention turns that leg red.
- [ ] Given the driver passes `gate-eval` a ctx, when the `gate-eval-merge` case runs through the driver, then the ctx carries ONLY the six documented keys (`drain_result`, `termination_reason`, `ready_sha`, `trust_unprotected`, `review_heal_result_path`, `supervisor_result_path`) — asserted by `test-automate-next-step.sh` reading the ctx file the driver wrote.
- [ ] Given the migrated tree, when `bash loomwright/scripts/test-loop-inventory.sh` runs, then it passes; every inventory row whose prose was migrated has home `script:automate-next-step.sh <step>` where `<step>` is a real `case` arm label in the driver; every golden case is named in the test cell (as `test-automate-golden.sh`, or `test-automate-next-step.sh` for tail rows) of the rows it covers.
- [ ] Given the migrated steps, when the default-mode skill files are read, then their step-by-step prose is gone from the default-mode files `per-item-loop.md` / `modes-and-merge-gate.md` (replaced by a one-paragraph "run `automate-next-step.sh`" pointer per step); the only remaining copy is `legacy-tail.md`, read only under `--legacy` (owner decision D5) until item 08 retires it, and a committed evidence file `loomwright/docs/evidence/as06-next-step-driver-tail.md` contains: `wc -c loomwright/skills/automate-loop/*.md` before (baseline `320545 total`) and after, the size of the DEFAULT-mode read set before and after — `wc -c` of the `skills/automate-loop/*.md` files Step 0 of `commands/automate.md` loads on a sequential run, EXCLUDING `legacy-tail.md` (read only under `--legacy`); the full-glob total may be recorded separately but labelled as such — the inventory GAP count before (147) and after, the invariant-grep file list before and after, and `<passed>/<total>` for each Validation-step test; the PR body links to it.
- [ ] Given `/automate --legacy`, when the run reaches the tail, then `commands/automate.md` routes the tail through the pre-change prose (kept selectable, e.g. a `skills/automate-loop/legacy-tail.md` holding the moved text verbatim, read only under `--legacy` — with ONE exception: no line containing the positive (non-negated) `gh pr merge --squash` string moves. The §9 mode bullets (incl. the `--auto-merge` GATE bullet) and the whole §10 gate spec are SPECIFICATION, not step-by-step tail prose, and stay in `modes-and-merge-gate.md` unchanged, so the AC4 surface list cannot grow; legacy-tail.md points to them instead of copying them), until item 08 retires it; without `--legacy` the tail is "run next-step".

- [ ] Given the tests that pin the migrated prose — `loomwright/scripts/test-automate-helpers.sh` QG3a / QG3a' (they read `per-item-loop.md` directly via `QG_LOOP` and pin the park-first list lead line `**Order — sequential interactive READY park (park first, then ask):**` and the heading `### Dismissed-findings decision step (before the park)`) and `loomwright/scripts/test-automate-dismissed.sh`'s B legs (they read the assembled `skills/automate-loop/SKILL.md` — index + split files via `fixtures/automate-loop-split/assemble.sh` — and pin the §6 step-4 GATE line, the decision-step subsection lists and the §9 park bullets) — when the prose moves, then each pin is repointed IN THE SAME CHANGE to where the rule now lives (`legacy-tail.md`, or the driver's case arm), every existing mutation control that turns that pin red is kept (re-targeted at the new file, still gated non-empty + differs + `bash -n` / line-count), and both suites pass: `bash loomwright/scripts/test-automate-helpers.sh` and `bash loomwright/scripts/test-automate-dismissed.sh` report 0 failures. A pin is exempted (its prose left in place) ONLY when the inventory row for it says why. (Source requirement Scope, added after the wave-2 Plan Review FAIL×3 of 2026-10-16.)

## Validation (must pass before merge)
1. `bash loomwright/scripts/test-automate-next-step.sh`, `test-automate-golden.sh`, `test-automate-helpers.sh`, `test-automate-dismissed.sh`, `test-loop-inventory.sh`, `test-result-schemas-split.sh` (owns `docs/result-schemas/*.md`, which subtask 1 edits), `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh` (and `test-automate-loop-split.sh`, which the SKILL.md index edit touches); report `<passed>/<total>` in the evidence file.
2. Mutation controls (inside `test-automate-next-step.sh`, each mutant gated non-empty + differs + `bash -n`): (a) a driver copy that skips `gate-eval` and parks directly ⇒ the `gate-eval-merge` case goes red; (b) a driver copy with an unguarded `gh pr merge --squash` line ⇒ the invariant-grep leg goes red.
3. Running system (scoped to the tail on purpose: DRAIN/RUN move into the driver only in item 07, a Non-goal here, so 'one real Queue item end to end with the driver path' means the driver-owned path from the drain result to the park): in a scratch `git init` repo (gh stubbed, no network), drive one item's tail end to end through `automate-next-step.sh` from a post-drain run file (`--result` = a READY drain) to the `awaiting_merge` park; paste the run file's tail `## Progress` lines, fenced, into the evidence file AND into the PR body under a `validation 3` line. The `validation-gate` reads ALL THREE entries from the PR body, so Validation 1 (each suite's `<passed>/<total>` summary lines) and Validation 2 (each mutation control's verdict line) are ALSO pasted, fenced, under `validation 1` / `validation 2` lines in the PR body; the evidence file remains the authority.

## Configuration
- **Base Branch:** main
- **Recommended workers:** 1 (2 subtasks, sequential)
- **Mode:** sequential
- **Split reason:** context-bound — subtask 1 (driver + test harness, ~1500 lines of new bash that must read ~30 golden cases and the helper contracts) and subtask 2 (prose migration across a 191KB inventory, a 106KB prose file and the MAP) each fill a worker context; subtask 2 consumes subtask 1's step names.
- **Lane PR rule:** this runs in a `--parallel` lane — ship a `changelog.d/as06-next-step-driver-tail.md` fragment (`<!-- bump: minor -->`), never a version bump; `bash scripts/check-version-bump.sh` passes.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Phase 3: File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|---|---|---|---|
| driver | — | `loomwright/scripts/automate-next-step.sh` | HIGH |
| driver-test | `loomwright/scripts/fixtures/automate-golden/<tail cases>/` (new `next-step.results` file per tail case only — `input.md`/`expected.md`/`expected.out`/`steps` unchanged) | `loomwright/scripts/test-automate-next-step.sh` | HIGH |
| schema + release | `loomwright/docs/result-schemas/automate-run.md` | `changelog.d/as06-next-step-driver-tail.md`, `loomwright/docs/evidence/as06-next-step-driver-tail.md` | HIGH |
| prose migration | `loomwright/skills/automate-loop/per-item-loop.md`, `loomwright/skills/automate-loop/modes-and-merge-gate.md`, `loomwright/skills/automate-loop/SKILL.md` (index headings + §1.5 table row for the driver), `loomwright/commands/automate.md` (`--legacy`, Step 0 read list); other split files (`intake.md`, `resume.md`, `invariants.md`, `branch-mode.md`, `lanes.md`, `command-lanes.md`) ONLY where they cross-reference a moved step and the pointer must change | `loomwright/skills/automate-loop/legacy-tail.md` (verbatim moved prose, read only under `--legacy`) | MEDIUM |
| pinned-prose tests | `loomwright/scripts/test-automate-helpers.sh` (QG3a/QG3a' + their `qg_prose_check` / `qg_move` mutation controls: repoint `QG_LOOP`), `loomwright/scripts/test-automate-dismissed.sh` (B legs: make the assembled text they read still contain the moved rules — e.g. include `legacy-tail.md` in what `$SK` is built from — and keep every B mutant) | — | HIGH |
| inventory + map | `loomwright/docs/loop-inventory/automate-loop.md`, `loomwright/scripts/fixtures/automate-golden/MAP.tsv` | — | HIGH |

> **Validator-owned surfaces:** `test-loop-inventory.sh` (heading coverage of every `skills/automate-loop/*.md` — a NEW split file `legacy-tail.md` needs rows; a deleted heading needs its rows re-homed), `test-automate-golden.sh` (units extracted live from `resume.md`/`per-item-loop.md`/`modes-and-merge-gate.md`; a deleted heading or numbered item makes its `MAP.tsv` row stale), `test-automate-loop-split.sh` (SKILL.md index ↔ split files, incl. the "Cited sub-section anchors" table), `check-doc-currency.sh`, `test-citation-drift.sh`, `check-token-budget.sh` (skills/commands ceilings — `.skills[automate-loop]` counts EVERY `*.md` in the dir, `legacy-tail.md` included, so the dir total can GROW (headroom ≈7.7k proxy tokens); `commands/automate.md` has ≈690 proxy tokens of headroom. If either goes over, raise its entry in `loomwright/docs/prompt-token-budgets.json` and the mirror row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" in the same change — both then join subtask 2's lanes).

## Touched-file invariants
Stamped at base commit 142540b8210a4b206e87e2b4349999c9978f8e29. Existing scripts modified: `test-automate-helpers.sh`, `test-automate-dismissed.sh` (pin repoint only); every other script below is NOT edited. These are the contracts of the files the change edits or must mirror:
- `loomwright/scripts/test-automate-golden.sh` (NOT edited — must stay green): mutation leg M5 builds its mutant by deleting the heading `### Termination (two exits)` from `per-item-loop.md` and "a leg whose mutant cannot be built FAILS" — so that heading must remain in `per-item-loop.md` exactly once. Units are `<file>|<heading>` and `<file>|<heading>|L<k>.<n>` for column-0 numbered items; `FAIL: stale map row <id>` fires when a unit disappears — every removed unit's `MAP.tsv` row is removed in the same change, every new unit gets a row.
- `loomwright/scripts/test-loop-inventory.sh` (NOT edited): home grammar `prose, script:<file>[ <sub>], hook:<leaf>, step-scoped, global or rationale:<doc>#<anchor>`; `script:<file> <sub>` passes iff the file "has a line that is a shell `case` arm whose `|`-separated labels (quotes stripped) include <sub>, followed by `)`" — every driver step named in a home must be a real case arm; `## Counts` lines must equal the table after every re-home.
- `loomwright/scripts/automate-helpers.sh` (NOT edited — the driver calls it): `gate-eval` refuses a ctx carrying a gate-owned key (`PARK: ctx_carries_gate_owned_key`); `skills/automate-loop/modes-and-merge-gate.md` §10 calls it "the only code path that executes `gh pr merge --squash`" — the driver shells out `bash "$H" gate-eval <pr> <ctx.json> --root <checkout>`, never reimplements a condition.
- `runfile-write` / `progress-append` / `current-set` / `current-escalation` / `queue-checkoff` are the only writers the driver may use for the run file ("never write the file another way"); `progress-append` exits 3 `current_not_set` on a guarded prefix with an unset `## Current` — the driver must surface a non-zero helper exit, never swallow it.
- Positive-grep surface list (CLAUDE.md §Failure-Mode Invariants; `skills/automate-loop/invariants.md` §11: "so the surface list stays at these five however many conditions the gate has"): the change must not add or remove a file with a positive `gh pr merge --squash` line — `modes-and-merge-gate.md` lines `at the GATE, \`gh pr merge --squash\` fires **only**` and `On all seven holding: \`gh pr merge --squash --match-head-commit` stay put; the driver, `test-automate-next-step.sh`, legacy-tail.md, the schema doc, the evidence file and the inventory edits carry the string only negated, if at all. In particular the Validation 2b mutant in `test-automate-next-step.sh` is BUILT at run time so the test source never holds the positive literal on one line (e.g. `m="gh pr merge"; printf '%s --squash "$pr"\n' "$m" >> "$mutant"`, or concatenated pieces) — the test file must not join the AC4 surface list.
- `### Termination (two exits)` (test-automate-golden.sh M5/M8 anchor) and its body STAY in `per-item-loop.md` exactly once; `legacy-tail.md` points to it and never copies that heading (no duplicate index entry, no ambiguous citation anchor).
- `skills/automate-loop/SKILL.md` index: every `### ` heading of a split file appears in the index under its `<!-- split:begin <file> -->` block (`test-automate-loop-split.sh`).
- `loomwright/scripts/test-automate-helpers.sh` (EDITED — subtask 2): `QG_LOOP="$HERE/../skills/automate-loop/per-item-loop.md"`, `QG_LEAD='**Order — sequential interactive READY park (park first, then ask):**'`, `QG_CITED='### Dismissed-findings decision step (before the park)'`; `qg_order` requires the list lines carrying `--status awaiting_merge`, `automate-merge-watch.sh`, `run-lock.sh release` to precede `park-ask-gate` (with `--wait 75`), which precedes `Ask the owner`; `qg_lead` requires the lead line exactly once and the heading present. The mutants `lead-dup.md` / `heading-mut.md` and the `qg_move` reorder mutants are built FROM `$QG_LOOP` — repoint the variable and every mutant follows; never delete a mutant to make the suite pass.
- `loomwright/scripts/test-automate-dismissed.sh` (EDITED — subtask 2): `SK="$TOP/automate-loop-skill.md"; bash "$ASM" "$REPO/loomwright/skills/automate-loop/SKILL.md" "$SK"` (ASM = `fixtures/automate-loop-split/assemble.sh`, which expands the index's `<!-- split:begin <file> -->` blocks); the B legs `first_line "$SK" "4. **GATE**"` (case `*"Dismissed-findings decision step (before the park)"*"**is written FIRST**"*"park-ask-gate"*…`), `SUBH` subsection body `sub_body`, `"**Safe mode (default):**"`, `"otherwise fail **CLOSED** → park + notify"`, `"**\`ESCALATED\` never merges and PARKS the run**"`, `"**PICK-time pending-decisions ask"` (stays in per-item-loop.md — PICK is item 08's), and the CLAUDE.md order mutant. Moved text must still be reachable from what `$SK` is assembled from, byte-identical, or the leg is repointed to the file that holds it.
- `commands/automate.md` Step 0 + `loomwright/scripts/test-automate-loop-split.sh` checks C and F: C ("NO ORPHANS") requires every `*.md` in `skills/automate-loop/` except SKILL.md to be named by exactly one `split:begin` block (SKILL.md or commands/automate.md); F (`check_step0`, `cmp` of `step0-want` vs `step0-have`) requires Step 0's index-only list to name EVERY skill split file, in documented order. Step 0's list already mixes **Always** entries (`per-item-loop.md`, `modes-and-merge-gate.md`, `invariants.md`) with **Only when** entries (`intake.md`, `resume.md`, `branch-mode.md`, `lanes.md`, `command-lanes.md`). Therefore `legacy-tail.md` MUST be (a) registered in exactly ONE `<!-- split:begin legacy-tail.md -->` block, in SKILL.md's index (so the assembled `$SK` that `test-automate-dismissed.sh` builds contains it), and (b) named in Step 0's index-only list in documented order as an `**Only when** --legacy was passed` entry — NEVER an **Always** entry. That leaves the default (non-`--legacy`) read set without it and keeps C and F green.
- Anchor uniqueness (first-match hazard): `test-automate-dismissed.sh`'s `sub_body` takes the FIRST `### Dismissed-findings decision step (before the park)` heading in `$SK`, and `first_line "$SK" "4. **GATE**"` takes the FIRST matching line; `test-automate-helpers.sh`'s `qg_lead` requires the park-first lead line exactly once. So the pointer stubs left in `per-item-loop.md` MUST NOT carry the exact anchors `4. **GATE**`, `### Dismissed-findings decision step (before the park)` or `**Order — sequential interactive READY park (park first, then ask):**` — each anchor lives exactly once, in `legacy-tail.md` (re-home the MAP.tsv and inventory rows of a removed heading/numbered item instead). Alternatively a leg may read `legacy-tail.md` directly, as `QG_LOOP` will; either way no leg may silently match a stub.

## Closed enumerations touched
- New closed enum: the instruction `do` values `spawn | ask | park | done` — authority: `loomwright/docs/result-schemas/automate-run.md` (new §"next-step instruction"), mirrored by the driver's own emitter and by `test-automate-next-step.sh`. `grep -rnF '"do":' loomwright/` (base): no hits — no other closed list to update.
- No new `pause_reason` / `status` / `escalation_cause` value is added (the requirement's Non-goal: no gate condition or park semantics change). The driver reuses the existing enums `current-set` validates.

## Pin mutations
- `test-automate-next-step.sh` golden-parity pin ⇐ mutation: in a driver copy, replace the `gate-eval` call with a direct `awaiting_merge` park ⇒ `gate-eval-merge` red (Validation 2a).
- invariant-grep pin ⇐ mutation: append an unguarded `gh pr merge --squash "$pr"` line to a driver copy ⇒ the grep leg red (Validation 2b).
- idempotency pin ⇐ mutation: make the no-`--result` path re-run its last side-effecting step instead of re-printing the stored instruction ⇒ "run file unchanged on the second call" red.
- can't-ask pin ⇐ mutation: drop the `--non-interactive` check before emitting `ask` ⇒ the non-interactive case red.
- ctx-shape pin ⇐ mutation: add `"high_risk": false` to the driver's ctx ⇒ the ctx-key leg red.
- QG3a (repointed) ⇐ mutation: in `legacy-tail.md`, move the `run-lock.sh release` list item below the `park-ask-gate` item ⇒ QG3a red (the existing `qg_move` control, now built from the new file).
- QG3a' (repointed) ⇐ mutation: duplicate the lead line, or alter the cited heading, in the new file ⇒ QG3a' red (the existing `lead-dup.md` / `heading-mut.md` controls).
- dismissed B GATE leg (repointed) ⇐ mutation: drop `**is written FIRST**` from the moved step-4 GATE line ⇒ "B: GATE step 4 order wrong" red.
- dismissed B subsection legs (repointed: decide-then-park order, park-first order/gate/ask, `pf_lock`, D3 order/batch, "subsection states:" wants) — the existing built-in mutants (`pf-lock-mutant`, `d3-mutant`, `d3-batch-mutant`) are rebuilt from the NEW source text (the assembled `$SK` incl. `legacy-tail.md`) and must still turn their legs red; for the legs with no built-in mutant: swap the park-first list's `run-lock.sh release` item and its `park-ask-gate` item in `legacy-tail.md` ⇒ "B: park-first order" red; move `4. Only then write the park state` above `2. **Interactive**` in the decide-then-park list ⇒ "B: subsection order" red; delete the phrase `at most ONCE per item` from the moved subsection ⇒ "B: subsection lacks: at most ONCE per item" red.

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory

## Design notes (binding for the worker)
- **Invocation:** `automate-next-step.sh <runfile> [--result <json>|--result-file <f>] [--mode safe|auto-merge] [--non-interactive] [--trust-unprotected] [--root <checkout>] [--session-id <sid>]`; plain bash 3.2 + jq, `. hermetic-test-env.sh`-compatible, resolves `automate-helpers.sh` as its sibling. Each tail step is a `case` arm (`gate`, `validation`, `dismissed`, `park`, `gate-eval`, `sync`, `checkoff`, `terminate` — final names are the worker's, but they are the strings the inventory homes cite).
- **Idempotency mechanism:** the driver stores the instruction it last printed (and the step it is waiting on) in a gitignored sidecar `.supervisor/automate/<run_id>.next-step.json` (confirm `git check-ignore` reads it ignored — a `*.json` beside the run file, like `<run_id>.config-backup.json`); a call with no `--result` while an instruction is pending re-prints it verbatim and writes nothing. State is otherwise derived from the run file (`## Current`, last `picked` segment of `## Progress`).
- **Byte parity:** where prose pins an exact line (e.g. `<ts> parked awaiting_merge <pr_url> — <n> dismissed decision(s) pending`, `dismissed-drafts`' summary line, `gate-eval: <line>`), the driver writes exactly that. Where today's golden `expected.md` carries a model-authored free-text line (e.g. `escalated-park`'s `owned drain ESCALATED … merge watcher armed`), the line arrives through `--result` (a `progress_note` field) so the case passes unchanged — document this in the schema section.
- **Side effects that cannot run hermetically** (merge-watcher launch, notify, `run-lock.sh release`) are executed by the driver through overridable command variables (e.g. `NEXT_STEP_WATCH_CMD`, `NEXT_STEP_NOTIFY_CMD`, `NEXT_STEP_LOCK_CMD`) that the test points at recorders, mirroring how `test-automate-golden.sh` supplies the watcher marker as fixed input. The launch line stays the §6 "Post-merge close-out" one.
- **Not migrated (Non-goals):** DRAIN/RUN bookkeeping (item 07), PICK/RECONCILE/resume (item 08). The prose for those stays; the driver's entry point is "drain result reported".

## Subtask Structure

| # | Title | Criteria | Est. Files | Skills | Status |
|---|---|---|---|---|---|
| 1 | Driver script, instruction schema, its test harness + per-case results fixtures, changelog fragment | AC1–AC5, Validation 1–3 (driver legs), evidence file | 4 create + tail case dirs | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | Prose migration: tail prose → "run next-step", `--legacy` path, SKILL.md index, inventory re-home + golden-case links, MAP.tsv, repoint the pinned-prose tests | AC6–AC9, Validation 1 (inventory/golden/split/helpers/dismissed/doc-currency/citation legs) | 8 modify + 1 create | `skills/automate-loop/SKILL.md`, `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/automate-next-step.sh"}
  - {kind: "file", path: "loomwright/scripts/test-automate-next-step.sh"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "next-step instruction"}
  - {kind: "file", path: "changelog.d/as06-next-step-driver-tail.md"}
  - {kind: "file", path: "loomwright/docs/evidence/as06-next-step-driver-tail.md"}
requires: []
lanes:
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/scripts/fixtures/automate-golden/*/next-step.results"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "changelog.d/as06-next-step-driver-tail.md"
  - "loomwright/docs/evidence/as06-next-step-driver-tail.md"
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
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/automate-loop/legacy-tail.md"
  - "loomwright/commands/automate.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/scripts/fixtures/automate-golden/MAP.tsv"
  - "loomwright/scripts/test-automate-helpers.sh"   # QG3a/QG3a' repoint only
  - "loomwright/scripts/test-automate-dismissed.sh"   # B-leg repoint only
  - "loomwright/skills/automate-loop/intake.md"   # only a cross-reference pointer to a moved step
  - "loomwright/skills/automate-loop/resume.md"   # only a cross-reference pointer to a moved step
  - "loomwright/skills/automate-loop/invariants.md"   # only a cross-reference pointer to a moved step
  - "loomwright/skills/automate-loop/branch-mode.md"   # only a cross-reference pointer to a moved step
  - "loomwright/skills/automate-loop/lanes.md"   # only a cross-reference pointer to a moved step
  - "loomwright/skills/automate-loop/command-lanes.md"   # only a cross-reference pointer to a moved step
  - "loomwright/docs/prompt-token-budgets.json"   # only if a ceiling is exceeded (see validator note)
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"   # only the matching Prompt Token Budgets mirror row
  - "loomwright/docs/evidence/as06-next-step-driver-tail.md"   # sequential share: subtask 2 fills the after-values (read-set size, GAP after, grep list after, inventory/golden/split/doc-currency/citation pass counts) once #1 has written the driver-leg results
external_requires: []
```

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (requires the driver's case-arm names from #1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References
- `loomwright/skills/automate-loop/SKILL.md` §1.5 (helper contracts the driver sequences), per-item-loop.md §6 steps 4–6, "Dismissed-findings decision step", "Post-merge close-out"; modes-and-merge-gate.md §9/§10
- `loomwright/skills/unit-testing/SKILL.md` (mutation-gated legs: non-empty + differs + `bash -n`)

## Risk Assessment

| Risk | Impact | Source | Mitigation |
|---|---|---|---|
| Requirement Scope says the automate-loop GAP count "reaches 0"; 147 rows are GAP today, many `story`/`rule` rows no golden case covers | MEDIUM | Feasibility (Phase 2.5) | Not an AC. Link every golden case into every row it covers, report before/after GAP in the evidence file, and name the residual honestly; do not invent test cells for story/rule rows |
| Deleting prose headings/numbered items breaks `test-automate-golden.sh` (stale map rows, M5's `### Termination (two exits)` anchor) or `test-automate-loop-split.sh` (index drift) — neither test file is in scope | HIGH | Touched-file invariants | Keep every heading the golden legs anchor on; update `MAP.tsv` and the SKILL.md index in the same commit; run both suites before declaring done |
| Byte-parity with free-text golden lines tempts editing `expected.md` | HIGH | Requirement AC | `expected.md`/`expected.out`/`steps` of existing cases are read-only; free text arrives via `--result` |
| Deleting pinned prose while the pinning tests stay as they are (the wave-2 L5 Plan Review FAIL×3 cause): `test-automate-helpers.sh` QG3a/QG3a' and `test-automate-dismissed.sh` B legs go red | HIGH | Prior run (L5, 2026-10-16) | Both tests are in subtask 2's lanes; repoint each pin in the same commit as the prose moves, keep every mutant, run both suites before done (AC9) |
| `legacy-tail.md` must be both registered (split checks C/F) and kept out of the default read | MEDIUM | Touched-file invariants | Register it in one SKILL.md `split:begin` block and name it in Step 0 as an `**Only when** --legacy was passed` entry (never **Always**); record the default read-set size before/after in the evidence file |
| A pointer stub in per-item-loop.md reusing a test anchor makes a first-match leg read the stub | MEDIUM | Touched-file invariants | Stubs never carry `4. **GATE**`, the decision-step heading or the park-first lead line; each anchor exists exactly once (in legacy-tail.md) |
| A second merge path: the driver must never execute the squash merge itself | HIGH | CLAUDE.md §Failure-Mode Invariants | Driver calls `gate-eval` only; grep leg + mutation control |
| Concurrent lanes in this wave edit `skills/automate-loop/*` / the inventory | MEDIUM | Wave plan | Keep edits scoped to tail sections; `wave-build` merges lane heads and stops on conflict |
| `validation-gate` (`_lanes_validation_rows` in `automate-lanes.sh`) reads the requirement's `## Validation` entries 1, 2 and 3 and marks each NOT-RUN unless the PR body carries a matching `validation <n>` passage with fenced output | MEDIUM | per-item-loop §6 step 4 | The committed evidence file stays the authority; FINALIZE ALSO pastes fenced output into the PR body under a `validation 1` line (each suite's `<passed>/<total>` summary lines), a `validation 2` line (each mutation control's verdict line) and a `validation 3` line (the run file's tail `## Progress` lines), and links the evidence file |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-10-16-next-step-driver-tail.md

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-16T09:04:27Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/575
- **Branch:** feature/as06-next-step-driver-tail
- **Files changed:** 37
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** automate-next-step.sh tail driver + test harness (72 legs; 19 tail golden cases byte-identical), tail prose moved to legacy-tail.md (--legacy), pinned-prose tests repointed, inventory re-homed (GAP 147→132). Phase 4.5: 3 review→fix iterations; iteration-3 fix (9224d2c) addressed both remaining HIGH findings but was not re-reviewed.

## Not verified
- **a real /automate session consuming the driver's instructions** — the skill prose drove the tail until subtask 2; only the driver suite and the scratch-repo run exercise it (subtask 1)
- **default side-effect commands (real watcher launch, desktop notify, lane-park-notify/lane-readiness)** — tests point NEXT_STEP_WATCH_CMD/NOTIFY_CMD at recorders (subtask 1)
- **escalated park inside an N>1 lane** — no golden case covers it (subtask 1)
- **concurrent driver invocations on one run file** — not guarded by the driver; relies on the PICK lock (subtask 1)
- **/automate default-mode tail driven by a live model following the step-4 pointer** — no live /automate session run (subtask 2)
- **/automate --legacy Step 0 trigger** — prose-only; AL-558/AL-559 left GAP (subtask 2)
