# Headless /automate and /verify runs end with a named outcome at every question

## Status: pending

Source: batch F story F1a (`2026-11-03-041412-automate-review-pr-and-verify-run-headless-with-a-named-outcome-at-every-question.md`, archive). Re-scoped against main `8ec200e` (plugin v17.35.1). Story F1b (the machine-readable run result envelope) is deferred and is not part of this story.

**As the** owner (Vikash), starting `/automate` and `/verify` as `claude -p` processes with nobody at the terminal,
**I want** every question those two commands can ask to have a named can't-ask outcome that fires on the explicit flag **or** when the ask tool is absent, and never to record a Product Owner `needs_owner` stop as `## Status: done`,
**so that** a headless run either finishes or stops with a reason I can read later, and a stop is never mistaken for success.

### Problem (verified on main 8ec200e)

1. **Product Owner `needs_owner` is recorded as success.** `skills/automate-loop/intake.md` §"Prompt source": on `po_gate: needs_owner (<n> flags)` "the run file then records `## Status: done`, `remaining: 0`", "the same terminal shape as 0 generated files". `## Status: done` means "Queue fully resolved" (`skills/automate-loop/run-file.md` §"`## Status` semantics"), so a reader of the run file sees a finished run, not a stop that is waiting on the owner.
2. **Product Owner gets `--non-interactive` only on the flag.** The same bullet: "Under `--non-interactive-fallback` the intake runs `/product-owner "<prompt>" --non-interactive`". In a headless coordinator with no flag, PO runs inline (not as a subagent), so its own can't-ask signal ("the flag or I am a subagent", `agents/product-owner.md` Context Setup step 4) may not fire, even though the ask tool is absent.
3. **`AUT-QUEUE` has no ask-tool-absent branch and no inventory row.** `intake.md` §"`--limit N`": only `--non-interactive-fallback` skips the confirm, and that path writes "no new `## Progress` line". `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" has no `AUT-QUEUE` row, and it says MN, SA and HP "never consult" the `auto`-tier helper. So a headless coordinator without the flag reaches an ask it cannot make, with no named outcome.
4. **`/verify`'s two queue questions have no gate code and no ask-tool-absent branch.** `commands/verify.md` §"Queue mode" step 2 (two incomplete queues ⇒ `AskUserQuestion`) and step 3 (confirm the resolved Queue) carry no `header:`, and `docs/LANE_GATES.md` / `scripts/lane-policy.sh catalog` have no `VER-*` row. Both fail closed only "under `--non-interactive-fallback`", and that flag is in neither `/verify`'s `## Usage` nor its `## Parameters`, though `## Usage` shows a headless `claude -p "/loomwright:verify …"` line. The inventory's `/verify` row lists contexts MI and MN only, and there is no row for the Queue confirm. `commands/verify.md` §"Notify" also says "`/verify` never calls that tool", which queue mode contradicts.

## Acceptance Criteria

Fixtures: the existing hermetic harnesses (`test-automate-helpers.d/`, `test-lane-policy.sh`, `test-non-interactive-gates-seam.sh`). No network, no model.

**Part A — `/automate`**
- [ ] **A1 (PO stop is never `done`).** Given prompt intake whose `/product-owner` output ends in `po_gate: needs_owner (2 flags)`, when intake handles it, then no run file is created (the precedent is `AUT-SOURCE`'s `no_source_non_interactive`), nothing is enqueued, and the run prints one line `automate: po_needs_owner_non_interactive (2 flags)` (the `<n>` copied from PO's line, never recomputed) followed by PO's flags and draft stories, and stops. `intake.md`, `commands/automate.md` (the `"<prompt>"` and `--non-interactive-fallback` rows), `skills/automate-loop/invariants.md` and the inventory's Product Owner row say so, and no surface still says `## Status: done` or "the same terminal shape as 0 generated files" for `needs_owner`. Test: `test-non-interactive-gates-seam.sh`, new legs that assert the status line on all four surfaces and the absence of the old `done` wording in §"Prompt source".
- [ ] **A2 (files that appeared anyway).** Given PO printed `needs_owner` but a story file appeared anyway, then the file is named in the printed report and never enqueued, and PO is never re-run without the flag. Test: `test-non-interactive-gates-seam.sh` (prose leg: the rule stays in §"Prompt source").
- [ ] **A3 (PO gets the flag when the coordinator cannot ask).** Given the coordinator cannot ask (`--non-interactive-fallback`, **or** the ask tool is absent from its tool set), then intake runs `/product-owner "<prompt>" --non-interactive`. Only an interactive coordinator passes no flag. Test: `test-non-interactive-gates-seam.sh` leg (e), extended to require both triggers in §"Prompt source".
- [ ] **A4 (`/loop` stops on it).** Given a `/loop /loomwright:automate "<prompt>"` tick ends with `po_needs_owner_non_interactive`, then `skills/automate-loop/SKILL.md` §12 "`/loop` driver" lists it with `resume_requires_flag_non_interactive` and `resume_ambiguous` as a stop that must not re-tick. Test: `test-non-interactive-gates-seam.sh`.
- [ ] **A5 (`AUT-QUEUE` can't-ask branch, helper).** Given `automate-helpers.sh queue-confirm --cant-ask <flag|no_ask_tool> <source> <n> <limit>`, then it prints one `skip — cannot ask (<reason>) …` line naming the reason and the limit, for every source and count. `--lane-backlog` still wins (the lane reason is unchanged). A missing or unknown `--cant-ask` value is a usage error (exit 1). Without `--cant-ask` the output is byte-identical to today for every existing leg. Test: `test-automate-helpers.d/16-queue-gates.sh`, new QG legs plus one mutant (drop the `--cant-ask` arm) that turns a leg red. The help golden `fixtures/automate-helpers-help/intake.golden` is regenerated.
- [ ] **A6 (`AUT-QUEUE` can't-ask branch, prose).** Given a run that cannot ask (the flag **or** the ask tool absent), then `AUT-QUEUE` is not asked, `gate-auto.sh` is not consulted, `queue-confirm --cant-ask …` runs, and one `skipped AUT-QUEUE: cannot ask (<reason>) …` `## Progress` line is appended. The Queue is then processed, capped by `--limit`. `intake.md` (the §2 intro and both `--limit N` bullets), `skills/automate-loop/helpers.md`'s `queue-confirm` row and `commands/automate.md`'s `--non-interactive-fallback` row say so. The inventory gains an `AUT-QUEUE` row: contexts MI; MN; HP; never SA. Test: `test-non-interactive-gates-seam.sh` (the inventory row exists and its last cell names `skipped AUT-QUEUE: cannot ask`; §"`--limit N`" names both triggers).
- [ ] **A7 (interactive path unchanged).** Given an interactive run, then `queue-confirm` without `--cant-ask` and the `gate-auto.sh decide AUT-QUEUE` step run exactly as today, and a backlog of at most `--limit` items still records `skipped AUT-QUEUE: backlog queue <n> ≤ limit <N>`. Test: the existing QG1 legs in `16-queue-gates.sh` pass unchanged, and `test-lane-policy.sh` passes unchanged for `AUT-QUEUE`.

**Part B — `/verify`**
- [ ] **B1 (gate codes).** Given `scripts/lane-policy.sh catalog`, then it has `VER-RESUME` (`human-only`, `(free text)`: the options are the incomplete queue ids) and `VER-QUEUE` (`human-only`, `Process` · `Stop`), each purpose naming its can't-ask outcome. `docs/LANE_GATES.md`'s table is regenerated from it, and its intro and the catalog's header comment name `/verify`'s queue asks. `commands/verify.md` §"Queue mode" steps 2 and 3 and `skills/verify-walkthrough/SKILL.md` §10 ask with `header: "VER-RESUME"` / `header: "VER-QUEUE"` and quote `VER-QUEUE`'s two labels. Test: `test-lane-policy.sh`'s catalog ↔ `LANE_GATES.md` check, and its `(gh)` leg running `check-gate-headers.sh` (G2/G3/G5) clean on the real tree.
- [ ] **B2 (`VER-RESUME` can't-ask).** Given two incomplete queue files, no `--resume <run_id>`, and a run that cannot ask (`--non-interactive-fallback` **or** the ask tool absent), then nothing is asked and the run fails closed with `pause_reason: resume_ambiguous`, as the flag path does today. Test: `test-non-interactive-gates-seam.sh` (both triggers named in `commands/verify.md` step 2 and SKILL §10; the inventory row's contexts include HP).
- [ ] **B3 (`VER-QUEUE` can't-ask).** Given a fresh queue and a run that cannot ask, then the Queue confirm is not asked, one `skipped VER-QUEUE: cannot ask (<reason>)` line is appended with `verify-helpers.sh queue-progress-append`, and processing goes on, capped by `--limit`. The inventory gains a `VER-QUEUE` row: contexts MI; MN; HP. Test: `test-non-interactive-gates-seam.sh` (the row and its last cell; the prose names both triggers and the progress line).
- [ ] **B4 (the flag is documented).** Given `commands/verify.md`, then `## Parameters` has a `--non-interactive-fallback` row (queue mode: no question is asked, `VER-RESUME` ⇒ `resume_ambiguous`, `VER-QUEUE` ⇒ skipped and recorded), and `## Usage`'s headless example includes a `--folder` line that passes it. Test: `test-non-interactive-gates-seam.sh`.
- [ ] **B5 (no false claim).** Given `commands/verify.md` §"Notify", then it no longer says `/verify` never calls the ask tool. It says the sign-in pause never asks and that the queue asks (`VER-RESUME`, `VER-QUEUE`) are the only asks. Test: `test-non-interactive-gates-seam.sh` (the old sentence is absent).

**Part C — what print mode does to the ask tool**
- [ ] **C1 (probe recorded).** Given `loomwright/scripts/fixtures/print-mode-ask-probe.json` (shape of `onfailure-block-probe.json`: `_what`, `_how_to_reproduce`, `runs[]`), then it holds at least one live run on the box's CLI (2.1.319 at refresh time) recording whether `AskUserQuestion` appears in the `system/init` tool list of a plain `claude -p` session. The inventory's context paragraph cites it as the evidence for "ask tool absent" in HP. Test: `test-non-interactive-gates-seam.sh` (the fixture parses, has a non-empty `runs[]` with a host version, and the inventory cites its path).

**Edge cases**
- [ ] **E1.** Given PO output `po_gate: needs_owner (0 flags)` (malformed), then the stop is the same (`po_needs_owner_non_interactive (0 flags)`, no run file), never `done`. Test: `test-non-interactive-gates-seam.sh` (the prose names "any `needs_owner` line").
- [ ] **E2.** Given an interactive `/automate "<prompt>"` where PO persists 0 files and prints no `po_gate` line, then the existing "0 generated files ⇒ `## Status: done`" behaviour is unchanged. Test: `test-non-interactive-gates-seam.sh` (that bullet is byte-unchanged).
- [ ] **E3.** Given a lane on its own `lane-create` backlog, then `AUT-QUEUE` is skipped with the lane reason even when the lane cannot ask. Test: `16-queue-gates.sh` (`--lane-backlog --cant-ask flag …` prints the lane reason).

**Error scenarios (mutations)**
- [ ] **M1.** Given a mutation that (a) restores `## Status: done` for `needs_owner` in §"Prompt source", (b) drops the ask-tool-absent trigger from §"`--limit N`", (c) deletes `/verify`'s `--non-interactive-fallback` row, or (d) removes the `header: "VER-QUEUE"` ask site, then at least one leg fails for each: (a)–(c) in `test-non-interactive-gates-seam.sh`, (d) in `check-gate-headers.sh` G5 through `test-lane-policy.sh`'s `(gh)` leg.

## Non-goals
- The machine-readable run result envelope, process exit codes and crash-vs-running detection (story F1b, deferred by the owner).
- `/review-pr`: on main it still has no question gate (`commands/review-pr.md` and `skills/review-heal/` carry no `AskUserQuestion`), so it needs nothing here.
- Any change to `gate-auto.sh`, the `auto` tier or `AUT-QUEUE`'s catalog row (#813, and batch G G3).
- A whole-tree "uncatalogued ask" detector (the source's Part D). On main, `check-gate-headers.sh` (G1–G5) already checks every catalogued code's header and labels, and covers `VER-RESUME` / `VER-QUEUE` once they are in the catalog.
- A new `pause_reason` value or run-file schema change. The PO stop writes no run file.
- Changing the interactive "0 generated files ⇒ `done`" path, or Product Owner's own gates and `<n>` count (#802).
- Detecting print mode from a TTY probe (the inventory forbids a TTY probe as the only signal).
- A Loomwright Studio story or any coordinator code.

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): core to keep = PO `needs_owner` under `/automate` never reads as `done`, plus the `/automate` and `/verify` question gates that still lack a named can't-ask branch. F1b deferred. Drop anything main already covers.
- PO default, pending owner review: **the PO stop writes no run file** and prints `automate: po_needs_owner_non_interactive (<n> flags)`, mirroring `AUT-SOURCE`'s `no_source_non_interactive`. Alternative (the source's OQ-F4): a run-level park with a new `pause_reason: po_needs_owner` and a saved `<run_id>.po-output.md`. Not chosen for three reasons. It adds an enum value to every `pause_reason` consumer (`CURRENT_PAUSE_ENUM` in `automate-helpers.d/runfile.sh`, the lanes readers). A `--resume` of a 0-item park would fall through PICK to `## Status: done`. And the parked run would block every later headless start with `resume_requires_flag_non_interactive`.
- PO default, pending owner review: **`AUT-QUEUE` with nobody to ask proceeds, capped by `--limit`, and records one `skipped AUT-QUEUE: cannot ask (<reason>)` line**. This is the source's OQ-F3 default and today's flag behaviour, and since #813 the catalog marks `AUT-QUEUE` `auto` (it is not a correctness gate). The flag path gains the same `## Progress` line, so the outcome is named in the run file either way. Alternative: stop with `queue_confirm_requires_flag_non_interactive` when the ask tool is absent and the flag is missing (the `AUT-RESUME` precedent).
- PO default, pending owner review: `/verify` gate codes `VER-RESUME` (free text) and `VER-QUEUE` (`Process` · `Stop`), both `human-only`. `VER-QUEUE` with nobody to ask behaves like `AUT-QUEUE` (proceed, capped, recorded).
- PO default, pending owner review: the can't-ask trigger is the explicit flag **or** the ask tool being absent from the tool set (spawn-context knowledge), never a TTY probe alone. Part C's probe backs the "absent in print mode" premise.

## Priority: Phase 2
**Rationale:** nothing breaks for a run with someone at the terminal. The false `done` and the unbranched asks bite only unattended runs, which the Studio coordinator and `/loop` need. The false `done` (A1) is the most important part: it is the only gap whose outcome looks like success.

## Assumptions
- Intake writes the first run file only after the source resolves (`commands/automate.md` Step 0: `intake.md` "writes its first run file from the template"), so on a PO stop no run file exists yet and none needs removing. If the implementer finds one is written earlier, the stop must leave it non-`done` (the owner decides the form).
- A `claude -p` session without a permission host has no `AskUserQuestion` in its tool list. This was seen on 2.1.286 (project memory) but is unverified on 2.1.319; Part C measures it. If the probe shows the tool is present but auto-denies or hangs, the ask-tool-absent trigger cannot be relied on: the documented headless invocation passes `--non-interactive-fallback` for both commands, and a follow-up is filed.
- `verify-helpers.sh queue-progress-append` accepts a free-text line (it is used for per-item lines today).
- `test-loop-inventory.sh` needs `docs/loop-inventory/automate-loop.md` updated when `intake.md` / `helpers.md` bullets change (rows AL-023, AL-164, AL-186, AL-187, AL-546).

## Dependencies
- Depends on: none (#813 and #802 are on main).
- Blocks: F1b (deferred), which would read the outcomes named here.
- Shares `loomwright/docs/ARCHITECTURE_CONTRACTS.md` and `loomwright/docs/LANE_GATES.md` with batch G G3 (file order only, no dependency).

## Risks
- **Restated lists drift.** The `--non-interactive-fallback` effects are restated in `commands/automate.md`'s flag row, `invariants.md` and `intake.md`, and the gate set in the catalog, `LANE_GATES.md` and the inventory. All of them change in the same PR (house rule: a restating copy changes with its authority).
- **Prompt growth.** `commands/automate.md`, `commands/verify.md`, `skills/automate-loop` and `skills/verify-walkthrough` have declared budgets. `check-token-budget.sh` fails on a breach, and a raise goes in `prompt-token-budgets.json` plus the `ARCHITECTURE_CONTRACTS.md` mirror row.
- **History in prompts.** `check-prompt-history-refs.sh` fails a prompt that gains a history reference. No batch, PR or incident names go in the prompts; they go in the changelog fragment.
- **A headless caller that relied on `## Status: done` for a PO stop** now finds no run file. That is the intended change; the changelog fragment names it.

## Validation (must pass before merge)
1. **Static — the gate seams:** `bash loomwright/scripts/test-non-interactive-gates-seam.sh` passes with the new A1–A4, A6, B2–B5, C1, E1, E2 and M1(a–c) legs.
2. **Static — the helper:** `bash loomwright/scripts/test-automate-helpers.sh` passes, including the new `16-queue-gates.sh` legs (A5, A7, E3) and the regenerated help golden.
3. **Static — the catalog:** `bash loomwright/scripts/test-lane-policy.sh` passes (catalog ↔ `LANE_GATES.md`; `check-gate-headers.sh` clean, with M1(d) red under mutation).
4. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes, including `check-token-budget.sh`, `check-doc-currency.sh`, `check-prompt-history-refs.sh`, `test-citation-drift.sh` and `test-loop-inventory.sh`. `bash scripts/check-version-bump.sh` passes with one `changelog.d/` fragment; the version files are never hand-edited.
5. **Running system — the print-mode probe:** the live `claude -p` run(s) behind `print-mode-ask-probe.json` on the box's CLI, with the `system/init` tool list excerpt pasted in the PR.
6. **Running system — a headless PO stop is not `done`:** `claude -p "/loomwright:automate \"<a request that raises a PO flag>\" --non-interactive-fallback"` in a sandbox repo ends with the line `automate: po_needs_owner_non_interactive (<n> flags)` and no new `.supervisor/automate/*.md`. The transcript excerpt is pasted in the PR.

## Depends on
none

## Touches
loomwright/skills/automate-loop/intake.md
loomwright/skills/automate-loop/SKILL.md
loomwright/skills/automate-loop/invariants.md
loomwright/skills/automate-loop/helpers.md
loomwright/commands/automate.md
loomwright/scripts/automate-helpers.d/intake.sh
loomwright/scripts/fixtures/automate-helpers-help/intake.golden
loomwright/scripts/test-automate-helpers.d/16-queue-gates.sh
loomwright/docs/loop-inventory/automate-loop.md
loomwright/commands/verify.md
loomwright/skills/verify-walkthrough/SKILL.md
loomwright/scripts/lane-policy.sh
loomwright/docs/LANE_GATES.md
loomwright/scripts/test-lane-policy.sh
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/scripts/test-non-interactive-gates-seam.sh
loomwright/scripts/fixtures/print-mode-ask-probe.json
loomwright/docs/prompt-token-budgets.json
changelog.d/headless-named-outcomes.md

## Changes since the source was written
- **#813 (v17.29.0, `gate-auto`):** `AUT-QUEUE` is now an `auto`-tier catalog row (`Process!` · `Stop`, no risk read), and interactive intake calls `gate-auto.sh decide AUT-QUEUE` before asking. That covers the source's "confirm the `AUT-QUEUE` row in `LANE_GATES.md`", so it is dropped. The can't-ask branch is still missing: the inventory says MN, SA and HP never consult the helper, and there is still no `AUT-QUEUE` inventory row. Kept as A5–A7.
- **#802 (v17.27.0), and the later contract-change flag:** PO's `<n>` now also counts missing-proof and contract-change flags. This story reads `<n>` verbatim, so nothing changes there.
- **`/verify` inventory row now exists** ("`/verify` queue ambiguous resume", contexts MI; MN, `resume_ambiguous`). The source's "not catalogued" is half true now: the inventory has the resume row but not the confirm, and the gate catalog has neither. The header codes, the ask-tool-absent trigger and the flag documentation are still missing (`commands/verify.md` and `skills/verify-walkthrough/SKILL.md` are unchanged since before the source).
- **`check-gate-headers.sh` (G1–G5) is on main** and checks every catalogued code's header and labels. The source's Part D derived-completeness test is replaced by putting the `VER-*` codes in the catalog, which brings them under G2/G3/G5.
- **PO stop shape changed from a park to "no run file"** (PO default above). The source's `po_needs_owner` pause reason and `.po-output.md` are not built.
- **Dropped:** `/review-pr` (no question gate on main), F1b (deferred), the Studio interface note.
- **Probe host:** the box's CLI is now 2.1.319 (the source said 2.1.317).
