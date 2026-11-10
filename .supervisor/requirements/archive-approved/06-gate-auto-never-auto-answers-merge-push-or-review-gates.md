# gate-auto never auto-answers a merge, push or review gate, whatever catalog it is given

## Status: pending

Source: Batch G item G3 (`loomwright-archive/requirements/batchG/2026-11-04-045525-gate-auto-never-auto-answers-a-merge-push-or-review-gate-whatever-catalog-or-environment-it-is-given.md`), approved 2026-11-09 and refreshed against `main` `8ec200e` (v17.35.1).

**As the** owner (Vikash), who lets `/automate`, `/autonomous` and Launch Pad apply a routine gate's answer without asking,
**I want** `gate-auto.sh` to refuse, by its own rule and not the catalog's, to auto-answer any gate that merges, publishes, pushes, creates or merges a PR, comments or reviews, and to judge a destructive answer from the label it would apply,
**so that** a changed or substituted catalog cannot widen the `auto` tier beyond the four routine formalities I approved.

### Problem (verified on main `8ec200e`)

The `auto` tier (`loomwright/scripts/gate-auto.sh`, v17.29.0) applies a gate's `!` label without asking unless an escalation trigger fires. Which gates are `auto` comes only from the catalog, `lane-policy.sh catalog`. Today it has exactly four `auto` rows: `AUT-RESUME`, `AUT-QUEUE`, `LP-SAVE` and `LP-SAVE-NOTE`. Test (cat5) in `test-lane-policy.sh` pins them. Every merge, publish and review gate is `human-only` or `allowed` (`SUP-CHILDREN`).

1. **Nothing backs up the catalog.** In `ga_decide`, the only tier check is the `not_auto` line: the row's policy must equal `auto`. `gate-auto.sh` has no rule of its own that a merge, push or review gate is never auto. The prose rule "anything that merges, deletes or pushes is `human-only`" (`docs/LANE_GATES.md`, the tier list) exists only as catalog data. If the catalog is edited by mistake or replaced, for example with an `AN-RUBRIC auto 'merge-and-continue!|…'` row, `decide` prints `answer merge-and-continue`.
2. **`destructive` depends on the caller.** The `destructive` trigger (the `[ "$destr" = 1 ]` line) fires only when the caller passes `--destructive`. No caller on main passes it:
   - `automate-next-step.sh` `ns_resume_auto` (AUT-RESUME);
   - `agents/launch-pad.md` Phase 6 action 3 (LP-SAVE / LP-SAVE-NOTE);
   - `skills/automate-loop/intake.md` (AUT-QUEUE).

   Only test leg (ga11) reaches the trigger. A destructive `!` label is therefore stopped only by the catalog, which is the thing item 1 shows can be wrong.
3. **Environment seams (optional part).** Lines 72–74 resolve the catalog, the risk classifier and the progress writer from `LOOMWRIGHT_GATE_AUTO_LANE_POLICY`, `LOOMWRIGHT_GATE_AUTO_CLASSIFY_RISK` and `LOOMWRIGHT_GATE_AUTO_HELPERS` whenever they are set. Anyone who controls the environment can therefore supply a catalog with more `auto` rows, a classifier that always says `high_risk: false`, or a writer that drops or forges `auto-answered` records. Only `test-lane-policy.sh` sets them: legs (ga10f) and (ga14d), and the `ga_mut` helper.

### Scope

**Part A — the `never_auto` exclusion (required).**
- `gate-auto.sh` holds its own exclusion list. It never reads that list from the catalog, so it still holds when the catalog is the thing that was replaced. Any one of these three parts excludes a code:
  1. **Named codes:** `SUP-CHILDREN`, `SUP-GH-RETRY`, `AN-RUBRIC`, `AN-NO-RUBRIC`, `AN-MERGE-VFY`, `AN-PR-BASE`, `AN-ESCALATED`, `AUT-DISMISS`, `AUT-WAIVE`.
  2. **Code tokens:** the code, split on `-`, contains one of `MERGE`, `MRG`, `PUSH`, `PUB`, `PUBLISH`, `PR`, `GH`, `REVIEW`, `RVW`, `COMMENT`, `CMT`, `RUBRIC`, `HEAL`, `P45`, `FINAL` or `FINALIZE`. This part covers a Phase 4.5 code or a forged code such as `SUP-PUSH` or `P45-HEAL`. The catalog has no Phase 4.5 code today.
  3. **Label words:** one of the row's labels or the `--offered` labels contains one of `merge`, `merged`, `publish`, `push`, `pushed`, `pr`, `pull request`, `comment`, `review`, `re-review`, `heal` or `rubric`. Before the check, the `?` / `!` markers and `(Recommended)` are stripped. Matching is whole-word and case-insensitive, with hyphen and space as word boundaries.
- The exclusion reads only the code and the labels. It never reads the catalog's purpose column: the purposes of the real `AUT-RESUME` and `LP-SAVE` rows mention "open PR diff" and "Plan Review PASS".
- `decide` prints `ask never_auto` when the exclusion matches, with a stderr line naming the part that matched. The check runs after the code's row is found and parsed, and before `not_auto`. So a real `human-only` excluded code and an excluded row that a catalog marks `auto` both print `ask never_auto`. The checks that come earlier keep their order: `off`, the error asks, then `unknown_code`.
- `record` refuses an `auto-answered` record whose code or label is excluded. It prints one stderr line, writes nothing and exits 0 (fail-safe). It never reads the `<reason>` or `--item` field: real reasons contain "PR", as in `open PR <n> not high-risk`. `--escalated` records are unaffected.
- `never_auto` is added in the same change to every list that restates the triggers:
  - the `gate-auto.sh` header;
  - the `test-lane-policy.sh` header's (ga) line;
  - `docs/LANE_GATES.md` §"The `auto` tier";
  - `docs/ARCHITECTURE_CONTRACTS.md`'s "Three tiers, and the `auto` tier" paragraph.

  `LANE_GATES.md` points to the exclusion in `gate-auto.sh` and does not restate its codes, tokens or words.

**Part B — derived `destructive` (required).**
- `decide` also prints `ask destructive` when the row's `!` label contains a destructive word. The label is compared with markers stripped, as a whole word and case-insensitively. The words are `delete`, `discard`, `drop`, `remove`, `abandon`, `archive`, `clean up`, `cleanup`, `wipe`, `purge`, `reset`, `overwrite`, `force`, `kill` and `prune`. The list lives in `gate-auto.sh` and is never read from the catalog.
- Only the `!` label is judged. `LP-SAVE`'s `Discard` and `AUT-RESUME`'s `Archive` are offered but never applied, so they do not trigger.
- `--destructive` stays as a caller signal, and either one is enough to ask. The trigger keeps its name and its place in the order: after `label`, before `severity`.

**Part C — the three environment seams are ignored (optional; the owner may drop it at planning without changing A or B).**
- `gate-auto.sh` always runs `lane-policy.sh`, `classify-risk.sh` and `automate-helpers.sh` from its own directory (`GA_DIR`). The three `LOOMWRIGHT_GATE_AUTO_*` variables are no longer read. There is no test mode that turns them back on.
- The header's `Seams:` line is replaced by one line stating the sibling-only rule.
- Tests substitute a script with a **copied-script-dir fixture**: a copy of `gate-auto.sh` in a scratch directory, next to the fake scripts and symlinks to the real siblings that the leg needs. Legs (ga10f) and (ga14d) and `ga_mut` move to this fixture. `ga_mut` already copies `gate-auto.sh` into `$ROOT/ga-mut-<name>/`; it now symlinks `lane-policy.sh` and `classify-risk.sh` beside the copy and stops setting the variables.

## Acceptance Criteria

All legs are in `loomwright/scripts/test-lane-policy.sh`, either in group (ga) or in a new sub-group (gx) of that file. They run in the scratch checkout `$GR`, as the existing (ga) legs do, with no network and no `gh`. Fixtures:
- `ga-sub/`: a copied-script-dir holding `gate-auto.sh`, a symlink to the real `classify-risk.sh`, and a fake `lane-policy.sh` whose `catalog` prints the real catalog plus the rows each leg names. A row the leg names replaces the real row with the same code.
- `stub-risk.sh`: prints `{"high_risk":false}`.
- `stub-helpers.sh`: touches a marker file and exits 0.

**Happy path**
- [ ] AC1. Given the real catalog and no `LOOMWRIGHT_GATE_AUTO_*` variable set, when (ga1)–(ga4) run, then they still print `answer Process`, `answer Continue`, `answer Save and exit` and `answer Save and exit`, and (cat5) passes unchanged. Test: existing legs (ga1)–(ga4) and (cat5).
- [ ] AC2. Given every row of the real `lane-policy.sh catalog` whose policy is `auto`, when `decide` runs on it with its exact labels, then none prints `ask never_auto` and none prints `ask destructive`. The leg iterates the catalog, so a future `auto` row that the exclusion or the destructive words would catch fails CI here. Test: new leg (gx1).

**Part A — `never_auto` (substituted catalog)**
- [ ] AC3. Given `ga-sub/` with these `auto` rows, and `decide <code>` run for each with that row's labels offered and `--max-severity NONE`, then every row prints `ask never_auto`:

  | Row | Labels | Part that catches it |
  |---|---|---|
  | `AN-RUBRIC` | `merge-and-continue!\|stop-here` | named, token, label |
  | `SUP-GH-RETRY` | `retry!\|abort` | named, token |
  | `SUP-CHILDREN` | `proceed anyway!\|abort` | named only |
  | `SUP-PUSH` | `Go!\|Stop` | token only |
  | `P45-HEAL` | `Apply!\|Stop` | token only |
  | `AUT-XYZ` | `Publish now!\|Stop` | label only |
  | `AUT-ABC` | `Post comment!\|Skip` | label only |
  | `AUT-PRC` | `Create PR!\|Wait` | label only |

  In the same catalog, `AUT-QUEUE` still prints `answer Process` (control). Test: new legs (gx2a)–(gx2i).
- [ ] AC4. Given the real catalog, when `decide AN-RUBRIC` and `decide SUP-GH-RETRY` run with their exact labels, then each prints `ask never_auto`. `LP-NO-GO` still prints `ask not_auto` and `AUT-SUMMARY` still prints `ask not_auto`. Test: new legs (gx3a), (gx3b); existing (ga9) and (ga9b) unchanged.
- [ ] AC5. Given a `ga-sub/` row `AUT-OK auto 'Approve!|Stop'` whose purpose reads "merge the PR after review", when `decide AUT-OK` runs, then it prints `answer Approve`. This proves the purpose column is never read. Test: new leg (gx4).
- [ ] AC6. Given `record <runfile> AN-RUBRIC merge-and-continue x`, then the run file is byte-for-byte unchanged, the exit is 0 and stderr names the exclusion. Given `record <runfile> AUT-OK 'Push now' x`, the result is the same (the label part). Given `record <runfile> AN-RUBRIC --escalated never_auto`, exactly one `auto-escalated AN-RUBRIC: never_auto` line is appended. Given `record <runfile> AUT-RESUME Continue "open PR 7 not high-risk"`, exactly one `auto-answered` line is appended: the reason is never read. Test: new legs (gx5a)–(gx5d).
- [ ] AC7. **Mutation controls** in `ga_mut` style, each gated on "the mutation landed and the copy passes `bash -n`":
  - deleting the `ask never_auto` line in a copy makes AC3's `AN-RUBRIC` leg print `answer merge-and-continue`;
  - emptying the named-code part makes AC3's `SUP-CHILDREN` leg print an `answer …`;
  - emptying the code-token part makes AC3's `SUP-PUSH` leg print an `answer …`;
  - emptying the label-word part makes AC3's `AUT-XYZ` leg print an `answer …`;
  - removing the `record` refusal makes AC6's first leg append a line.

  Test: new legs (gx-m-neverauto), (gx-m-named), (gx-m-token), (gx-m-label), (gx-m-record).

**Part B — derived `destructive`**
- [ ] AC8. Given a `ga-sub/` row `AUT-DEL auto 'Delete all!|Keep'` and no `--destructive`, then `decide AUT-DEL` prints `ask destructive`. Given `AUT-KEEP auto 'Keep!|Delete all'`, it prints `answer Keep`, because only the `!` label is judged. Test: new legs (gx6a), (gx6b).
- [ ] AC9. Given the real catalog, (ga11) with `--destructive` still prints `ask destructive`. A mutation that deletes the derived check makes AC8's first leg print `answer Delete all`, and the existing `ga_mut destructive` control still fires. Test: (ga11), new (gx-m-derived), existing (ga-m-destructive).

**Part C — seams ignored (only if Part C is kept)**
- [ ] AC10. Given `LOOMWRIGHT_GATE_AUTO_LANE_POLICY` pointing at a fake catalog in which `LP-NO-GO` is `auto` with `Override and continue!`, when `decide LP-NO-GO` runs with its exact labels against the real `gate-auto.sh`, then it prints `ask not_auto`. Test: new leg (gx7a).
- [ ] AC11. Given `LOOMWRIGHT_GATE_AUTO_CLASSIFY_RISK=stub-risk.sh`, when `decide LP-SAVE-NOTE … --max-severity LOW --risk-paths ga-agents.txt` runs, then it prints `ask high_risk`, because the real classifier ran. Test: new leg (gx7b).
- [ ] AC12. Given `LOOMWRIGHT_GATE_AUTO_HELPERS=stub-helpers.sh`, when `record <runfile> AUT-QUEUE Process x` runs, then the stub's marker file does not exist and the run file gained exactly one `auto-answered AUT-QUEUE: Process — x` line. Test: new leg (gx7c).
- [ ] AC13. Given `grep -c 'LOOMWRIGHT_GATE_AUTO_' loomwright/scripts/gate-auto.sh`, then the count is `0`. (ga10f), (ga14d) and every `ga_mut` leg pass through the copied-script-dir fixture with no `LOOMWRIGHT_GATE_AUTO_*` variable set. Test: new leg (gx7d); migrated (ga10f), (ga14d), (ga-m-*).

**Error scenarios**
- [ ] AC14. Given a copied-script-dir whose `lane-policy.sh` prints nothing, then `decide` prints `ask catalog_unreadable`. Given an excluded code that is not in the catalog, such as `SUP-PUSH` in the real catalog, it prints `ask unknown_code`. The exclusion never turns an error into an answer. Test: (ga14d) through the fixture, new leg (gx8).
- [ ] AC15. The can't-ask branches are unchanged. No caller file changes: `automate-next-step.sh`, `agents/launch-pad.md`, `skills/automate-loop/intake.md` and `commands/` are outside Touches. Each caller already treats any `ask <trigger>` as "ask the owner", and a run that cannot ask still never consults the helper. Test: `plan-waves --lint` on this story, plus review against Touches. Existing (ga) legs stay green.

## Non-goals
- Changing which gates are `auto`. The four rows and (cat5) stay as they are, and no row is added or relabelled.
- Changing `lane-policy.sh`, including its own seams `LOOMWRIGHT_LANE_POLICY_RULES_CHECK` and `LOOMWRIGHT_LANE_POLICY_HELPERS`, and `lane-policy.sh decide`'s answering of the `allowed` `SUP-CHILDREN`. The exclusion governs `gate-auto.sh` only.
- Sweeping environment seams in any other script. Batch G items G4 and G5 were rejected.
- Defending against an attacker who controls `PATH`, `BASH_ENV` or exported shell functions, or who can write into the plugin's `scripts/` directory.
- Making any caller pass `--destructive`.
- A stderr note when a `LOOMWRIGHT_GATE_AUTO_*` variable is set, and `pwd -P` resolution of `GA_DIR`. Both were in the source; see Owner decisions.
- Any change to the single `gh pr merge --squash` executor (`automate-helpers.sh` `gate-eval`), which never consults `gate-auto.sh`.
- AUT-QUEUE's can't-ask branch (batch F F1a).

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): the approved core is a catalog-independent `never_auto` exclusion, so `gate-auto.sh` can never auto-answer a merge, publish, push, PR, comment, review, Phase 4.5, AN-RUBRIC or SUP-GH-RETRY gate (Part A), plus `destructive` derived from the label instead of relying on a caller's `--destructive` (Part B).
- 2026-11-09 (Vikash, in chat): the env-seam part is optional and stays in only if it is small. Sibling seam sweeps (G4, G5) are rejected, so scope does not widen to other scripts. Part C is kept as a separate, droppable part. Parts A and B do not need it, because their tests use the copied-script-dir fixture either way.
- OQ-G13: no test mode that re-enables the seams; the three variables are deleted and tests use the copied-script-dir fixture. PO default, pending owner review.
- OQ-G14: a set seam variable is silently ignored, with no stderr note. This changes the source's default (a note per variable) to keep Part C small. PO default, pending owner review.
- OQ-G15: the exclusion has the source's three parts (named codes, code tokens, whole-word label vocabulary) and never reads the purpose column. `AUT-SUMMARY`, `AUT-PENDING`, `AUT-OVERLAP` and `LP-SCOPE` are not named. PO default, pending owner review.
- OQ-G16: the trigger is named `never_auto` and is checked after the row is parsed, before `not_auto`. PO default, pending owner review.
- OQ-G17: destructive is derived from the `!` label only, with the word list held in `gate-auto.sh`; either it or `--destructive` makes the gate ask. PO default, pending owner review.
- `pwd -P` for `GA_DIR` and the `docs/evidence/` red-before file are dropped from the source. The mutation controls in AC7 and AC9 are the standing red proof. PO default, pending owner review.

## Priority: Phase 2 (Batch G item G3, P2, size S)
**Rationale:** this closes a hole in code that has already shipped (v17.29.0). It touches 5 files and has no dependency. It is not MVP for any current run, because the real catalog marks no merge or review gate `auto` today. The risk is a future edit or a substituted catalog, plus an environment-controlled session if Part C is kept.

## Assumptions
- The three call sites of `decide` and `record` invoke `gate-auto.sh` by path and set none of the seams (verified on `8ec200e`). No consumer enumerates trigger names: `ns_resume_auto` passes any `ask <trigger>` through as `auto_reason`, and Launch Pad treats any non-`answer` output as "ask".
- `lane-policy.sh catalog` and `classify-risk.sh` run correctly from a symlink in a scratch directory. `classify-risk.sh` sources no sibling. `lane-policy.sh` resolves `rules-check.sh` and `automate-helpers.sh` beside itself, but `catalog` uses neither.
- `never_auto` is one more free-form value of the existing `auto_reason` field and the `auto-escalated <code>: <trigger>` line, so no `schema_version` changes.

## Dependencies
- Depends on: none (#813 / v17.29.0 is merged).
- Blocks: none.
- File overlap (order only): `loomwright/docs/ARCHITECTURE_CONTRACTS.md` and `loomwright/docs/LANE_GATES.md` with any concurrent gate-catalog story.

## Risks
- **The vocabulary over-matches a future routine gate**, for example an `auto` row labelled "Review later". AC2 fails CI the moment a real `auto` row is excluded, so the owner decides openly. The exclusion is meant to be stricter than the catalog.
- **The vocabulary under-matches** a forged neutral row (no excluded token, no excluded word). The named-code part covers every real merge or review gate. Part C, if kept, stops the catalog being substituted through the environment.
- **Restated trigger lists drift.** The trigger list appears in four places (see Part A). All four change in this PR.
- **Test churn (Part C):** (ga10f), (ga14d) and the 9 `ga_mut` legs move to the fixture. `ga_mut` already copies the script, so the change is mostly adding symlinks.

## Validation (must pass before merge)
1. **Static — the gate-auto legs:** `bash loomwright/scripts/test-lane-policy.sh` passes, including (cat5), (ga1)–(ga16b), the new (gx) legs for AC2–AC14 and every mutation control (AC7, AC9) reporting CONFIRMED.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes, including `check-gate-headers.sh`, the `LANE_GATES.md` catalog-mirror check, `check-doc-currency.sh` and `test-citation-drift.sh`. Run directly any suite it lists as not covered.
3. **Static — release fold:** `bash scripts/check-version-bump.sh` passes with `changelog.d/gate-auto-never-auto.md`. The version files are changed only by `bash scripts/bump-version.sh`, never by hand.

## Depends on
none

## Touches
loomwright/scripts/gate-auto.sh
loomwright/scripts/test-lane-policy.sh
loomwright/docs/LANE_GATES.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/gate-auto-never-auto.md

## Changes since the source was written
- **Base:** the source was written against `origin/main` `e3057ffe` (v17.29.0, the release that carried #813). This refresh reads `main` `8ec200e` (v17.35.1).
- **`gate-auto.sh`:** the only change since #813 is `660fddd`, where the catalog-row lookup now reads `awk … <<<"$row"` instead of a pipe. The seams (lines 72–74), the trigger order, the lone `not_auto` tier check and the caller-only `destructive` line are unchanged, so all three gaps still hold.
- **Callers:** still exactly three (`ns_resume_auto`, Launch Pad Phase 6 action 3, the `intake.md` AUT-QUEUE step), and none passes `--destructive`. Seam users are still only (ga10f), (ga14d) and `ga_mut`.
- **Catalog:** 33 rows at #813 became 35 rows, adding `LP-SCOPE` (v17.32.0) and `AUT-OVERLAP`, both `human-only`. `AUT-DISMISS`'s labels became the batched fix-now form, and `AUT-SUMMARY` became a fallback only (v17.31.0). There are still exactly four `auto` rows, and no new row is a merge, push or review gate.
- **Scope, per the owner's verdict:** the environment-seam work moved from requirement (a) to optional Part C. The stderr note, `pwd -P` and the red-before evidence file were dropped to keep the change at 5 files.
- **Touches:** the source named `loomwright/docs/evidence/…`, a directory that does not exist (evidence lives in the root `docs/evidence/`); that file is dropped anyway. The fragment is renamed `changelog.d/gate-auto-never-auto.md`.
- **New AC6 clause:** `record` judges only the code and label, never the reason. Real reasons contain "PR" (`open PR <n> not high-risk`), and a whole-record match would have refused a legitimate `AUT-RESUME` record.
- **New in Part A:** the `test-lane-policy.sh` header's (ga) trigger list is a fourth restated copy. The source named only three.
