# as16 — automate-loop carries rules, not stories, and loads by phase: evidence

Requirement: `.supervisor/requirements/automate-speed/16-diet-automate-loop.md`. Base commit: `ee3d7ea3bb069c50a07c3b37222c52c88202263b`. Subtasks 1–4 append to this file as they land; Subtask 5 finishes it (final measurements, gate results). Every number below was measured from the repo root.

## Baseline

Re-measured at the base commit, before any edit, from the git objects (`git show ee3d7ea:<path>`), so no working-tree change can leak into it:

```bash
F="loomwright/skills/automate-loop/SKILL.md loomwright/skills/automate-loop/branch-mode.md
   loomwright/skills/automate-loop/command-lanes.md loomwright/skills/automate-loop/intake.md
   loomwright/skills/automate-loop/invariants.md loomwright/skills/automate-loop/lanes.md
   loomwright/skills/automate-loop/modes-and-merge-gate.md loomwright/skills/automate-loop/per-item-loop.md
   loomwright/skills/automate-loop/resume.md loomwright/commands/automate.md"
RX='#[0-9]{2,4}\b|queue/[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2}|item [0-9]+'
tot=0; htot=0
for f in $F; do
  b=$(git show "ee3d7ea:$f" | wc -c | tr -d ' '); h=$(git show "ee3d7ea:$f" | grep -ohE "$RX" | wc -l | tr -d ' ')
  echo "$f bytes=$b hist=$h"; tot=$((tot+b)); htot=$((htot+h))
done
echo "TOTAL bytes=$tot hist=$htot"
# default-path read set: SKILL.md + invariants.md (Step 0 **Always**) + the command body
git show ee3d7ea:loomwright/skills/automate-loop/SKILL.md ee3d7ea:loomwright/skills/automate-loop/invariants.md \
  ee3d7ea:loomwright/commands/automate.md | wc -c
git show ee3d7ea:loomwright/skills/automate-loop/helpers.md | wc -c
```

```
loomwright/skills/automate-loop/SKILL.md bytes=46413 hist=4
loomwright/skills/automate-loop/branch-mode.md bytes=7592 hist=0
loomwright/skills/automate-loop/command-lanes.md bytes=4111 hist=0
loomwright/skills/automate-loop/intake.md bytes=10379 hist=0
loomwright/skills/automate-loop/invariants.md bytes=6826 hist=0
loomwright/skills/automate-loop/lanes.md bytes=57472 hist=8
loomwright/skills/automate-loop/modes-and-merge-gate.md bytes=27208 hist=3
loomwright/skills/automate-loop/per-item-loop.md bytes=66665 hist=11
loomwright/skills/automate-loop/resume.md bytes=18941 hist=1
loomwright/commands/automate.md bytes=30161 hist=1
TOTAL bytes=275768 hist=28
DEFAULT_READ_SET bytes=83400
helpers.md bytes=45618
```

The baseline matches the requirement: 275,768 bytes and 28 history references over the measured set; the AC2 target is ≤ 193,037 bytes. The default-path read set (SKILL.md + invariants.md + commands/automate.md) is 83,400 bytes. `helpers.md` (not in the measured set, must not grow) is 45,618 bytes.

Gates at the base tree (run before any edit, same commands as the Results below): `test-loop-inventory.sh` 43/43, `test-automate-loop-split.sh`, `test-automate-dismissed.sh` 255/0, `test-non-interactive-gates-seam.sh` 64/0, `test-rules-gate-seams.sh` 26/0, `test-run-lock.sh` 88/0, `test-citation-drift.sh` 26/0, `check-doc-currency.sh`, `check-token-budget.sh` and `check-vendor-coupling.sh` OK.

### Subtask 1 — the default read set (SKILL.md, invariants.md, commands/automate.md)

Running `wc -c` after Subtask 1 — the same loop as the Baseline, run on the working tree, with every `skills/automate-loop/*.md` except `helpers.md` (so the new `run-file.md` is counted) plus the command body:

```bash
F="$(ls loomwright/skills/automate-loop/*.md | grep -v helpers.md) loomwright/commands/automate.md"
for f in $F; do echo "$f bytes=$(wc -c < "$f" | tr -d ' ') hist=$(grep -ohE "$RX" "$f" | wc -l | tr -d ' ')"; done
```

```
loomwright/skills/automate-loop/SKILL.md bytes=21154 hist=1
loomwright/skills/automate-loop/branch-mode.md bytes=7592 hist=0
loomwright/skills/automate-loop/command-lanes.md bytes=4111 hist=0
loomwright/skills/automate-loop/intake.md bytes=10379 hist=0
loomwright/skills/automate-loop/invariants.md bytes=6090 hist=0
loomwright/skills/automate-loop/lanes.md bytes=57472 hist=8
loomwright/skills/automate-loop/modes-and-merge-gate.md bytes=27208 hist=3
loomwright/skills/automate-loop/per-item-loop.md bytes=66665 hist=11
loomwright/skills/automate-loop/resume.md bytes=18941 hist=1
loomwright/skills/automate-loop/run-file.md bytes=10598 hist=0
loomwright/commands/automate.md bytes=19850 hist=0
TOTAL bytes=250060 hist=24
DEFAULT_READ_SET bytes=47094
helpers.md bytes=45618
```

- Measured set: 275,768 → **250,060** bytes (−25,708, −9.3%). The AC2 target (≤ 193,037) still needs −57,023 from Subtasks 2–4.
- Default-path read set (SKILL.md + invariants.md + commands/automate.md; Step 0's only **Always** file is `invariants.md`): 83,400 → **47,094** bytes (−43.5%).
- History references: 28 → **24**. SKILL.md's remaining one is its frontmatter `lastUpdated:` date (counted at base too); `#617` and the `automate-2026-10-04-…` run id moved to the rationale doc.
- `helpers.md`: 45,618 → 45,618 (unchanged, not edited).
- New runtime split file: `skills/automate-loop/run-file.md` (10,598 bytes) — §3 moved out of the always-read index, then trimmed. It carries no counted vendor-coupling token, so it needs no allowance.

What moved where:
- **SKILL.md §1** — the layering story (AL-002) → rationale `### Purpose and layering`; the rules (AL-003 … AL-008) stay, shortened, anchors byte-identical.
- **SKILL.md §3** (run-file template, item lifecycle, `## Status` semantics, crash-safety contract, `## Current` transition table) → split block `<!-- split:begin run-file.md -->`, Step 0 **Only when**. The Lane w1-10 story (AL-075) → rationale `### Why Current moves only through current-set`; the `runfile-write` "why" → rationale `### Why runfile-write validates before rename`. Restated detail that a helper already enforces (the guard's token-matching rules, each `pause_reason`'s owning section, the template comments' history and `died`/`superseded_by_merge` explanations, which `docs/result-schemas/automate-run.md` §"`## Current` fields" owns) was cut; the pinned template lines (`- pause_reason: …|live_lane|phase_relay_unavailable|null`, `- pending_decisions: <n> | fix_now_reentered: <true|false>`) and the RUN-level transition row are byte-identical.
- **SKILL.md §12 Flags** — the second copy of the command's Usage block replaced by a pointer to it (house rule: one copy of a list). Its rows AL-091 … AL-096 now anchor in `commands/automate.md`; two clauses only the skill's copy carried (`refused with a source or --resume`, `; nothing does`) were added to the command's Usage lines so nothing was lost.
- **SKILL.md Anti-Patterns / Quality Gates / Related Skills** — each bullet cut to its rule, every bold label and pinned line byte-identical; the `#617` reference → rationale `### Why a clean bot review is not a dismissed finding`.
- **invariants.md** — version strings and restated explanations cut (`--cheap`'s forwarding chain, the run-lock liveness detail); every §11 invariant and its anchor stays.
- **commands/automate.md** — Purpose cut to one paragraph (story → rationale `### The command body's purpose section`); the third "defined ONCE in the skill" note deleted; parameter rows cut to their rule (each detail is homed at its step — verified: `run_lock_degraded` and `--force-unlock` in `per-item-loop.md`/`helpers.md`, `LEDGER_UNREADABLE` in `automate-helpers.d/runfile.sh`, `plan-waves` in `intake.md`/`helpers.md`); the headless-CLI `/loop` comments replaced by one pointer to skill §12; the Short overview cut to a one-line-per-step map (AL-543 story → rationale `### Why the command keeps a short overview`).
- Inventory: 32 rows (AL-058 … AL-089) now name `run-file.md`; AL-075 is a story (below), the other 31 are re-homed `script:` where the row's `implemented by` names an existing arm, else `step-scoped` (AL-089 stays `judgment`/`prose`, anchor live in `run-file.md`); 3 `story` rows (AL-002, AL-075, AL-543) homed `rationale:docs/rationale/automate-loop.md#…`; one new row AL-587 for the `run-file.md` Step 0 line; `## Sources` gains `run-file.md`; `## Counts` recomputed (585 rows, 138 rule). The SKILL.md frontmatter takes the one minor bump (1.17.0 → 1.18.0, mirrored in `SKILLS_INDEX.md`).
- `vendor-coupling-manifest.json`: `commands/automate.md` 8 → 7 (the dropped headless-CLI comment); SKILL.md stays at 3; no allowance added.

### Subtask 2 — per-item-loop.md and resume.md

The same loop as Subtask 1, on the Subtask 2 working tree:

```
loomwright/skills/automate-loop/SKILL.md bytes=21154 hist=1
loomwright/skills/automate-loop/branch-mode.md bytes=7592 hist=0
loomwright/skills/automate-loop/command-lanes.md bytes=4111 hist=0
loomwright/skills/automate-loop/intake.md bytes=10379 hist=0
loomwright/skills/automate-loop/invariants.md bytes=6090 hist=0
loomwright/skills/automate-loop/lanes.md bytes=57472 hist=8
loomwright/skills/automate-loop/modes-and-merge-gate.md bytes=27208 hist=3
loomwright/skills/automate-loop/per-item-loop.md bytes=29940 hist=0
loomwright/skills/automate-loop/resume.md bytes=9919 hist=0
loomwright/skills/automate-loop/run-file.md bytes=10598 hist=0
loomwright/commands/automate.md bytes=19850 hist=0
TOTAL bytes=204313 hist=12
helpers.md bytes=45618
```

- Measured set: 250,060 → **204,313** bytes (−45,747 this subtask; −71,455 / −25.9% from the 275,768 baseline). `per-item-loop.md` 66,665 → 29,940; `resume.md` 18,941 → 9,919. The AC2 target (≤ 193,037) still needs −11,276 from Subtasks 3–4.
- Default-path read set: unchanged at 47,094 bytes (neither file is read by default).
- History references: 24 → **12** (`per-item-loop.md` 11 → 0, `resume.md` 1 → 0; the run ids, PR numbers, the `(owner decision, 2026-10-07)` date and `red-team-hardening item 04` moved to the rationale doc or were cut).
- `helpers.md`: 45,618 → 45,618 (not edited; nothing was moved into it).

What moved where:
- **Stories → rationale `## per-item-loop and resume`** (15 existing `story` rows re-homed `rationale:docs/rationale/automate-loop.md#…`): the trail-gate incident (AL-241), brief-repair's outside-the-engine limit (AL-311), why no park opens a trail PR and the `--no-trail` cost (AL-345), the checkout contract's re-examination and limits (AL-354, AL-356), the sync-line incident (AL-370), the detached watcher, the pinned lock holder and the `pgrep -f` counting artifact (AL-378), the trail_pr_open options (a)/(b)/(c) and their limit (AL-400 … AL-403), and three rows whose prose had already left the runtime with `legacy-tail.md` (AL-282 validation-gate limits, AL-333 / AL-336 post-release lock, AL-340 decision-step limits — text recovered from `git show 6d51a9a^:loomwright/skills/automate-loop/legacy-tail.md` and rewritten short). Two new `story` rows, AL-588 / AL-589, home the story halves split out of `resume.md` §4's deterministic rows (finalize-before-listing, the lane-clone skip).
- **Script-owned prose deleted** (rows homed `script:automate-next-step.sh <arm>`, `script:automate-helpers.sh <sub>`, `script:automate-merge-watch.sh`, `script:session-resume.sh` — `test-loop-inventory.sh` checks each arm exists): the trail-pr path list, branch reuse, mechanics, dropped-draft retraction and the long checkout contract (now one bullet); `closeout`'s step-by-step detail (now one ordered line); the merge watcher's poll, backoff, settle re-check and single-instance mechanics (now one bullet and a pointer to the script header); the driver steps' restated detail in §6 steps 1–4 and §7; `resume.md` §4's title-line grammar, rebuild details and restated reconcile prose. One line stays wherever the model could otherwise act by hand: never redo a driver step, never `git add -A`, `--force-unlock` is human-only, a `run_lock_degraded` line is not a park, never re-pick a `gone` item, never NULL a superseded drain, `trail-pr` / `brief-repair` never gate and never merge, the can't-ask stops and their statuses.
- **Kept byte-identical (pinned):** every heading and every numbered step (the `automate-golden` `MAP.tsv` maps each heading and `L1.n` unit of both files), the §8 `**Honest limits.**` bullet with the positive-form merge mention, the Dismissed-findings `**Honest limits.**` paragraph, the Rate-limit park paragraph, and every needle the readers take (`test-automate-trail.d/01`, `/04`, `/05`, `test-automate-helpers.d/09`, `/15`, `test-automate-dismissed.sh`, `test-automate-lanes.d/05` AJ4e5, `test-run-lock.sh`, `test-non-interactive-gates-seam.sh`); a needle-bearing paragraph was shortened around its needles, never reworded through them.
- Inventory: AL-387 re-homed `script:automate-next-step.sh reconcile` (it pointed at a `rationale:` heading inside `resume.md`); AL-581 re-pointed to its default-read copy in `SKILL.md`'s Coordinator loop (`q: is never run inline: run its \`launch\` line`, home `global`), and `per-item-loop.md`'s restatement replaced by a pointer to it; `## Counts` recomputed (587 rows, 28 story, 133 GAP), AL-588 / AL-589 added to the gap list.
- `vendor-coupling-manifest.json`: `per-item-loop.md` now carries no counted token (its `AskUserQuestion` and the launcher's two runtime-identity variables, twice each, left with the deleted prose), so its allowance (5) and note are removed; `resume.md` keeps its one (`AskUserQuestion` in the AL-213 anchor). The rationale doc carries no counted token.

### Subtask 3 — lanes.md, command-lanes.md and branch-mode.md

The same loop as Subtask 1, on the Subtask 3 working tree:

```
loomwright/skills/automate-loop/SKILL.md bytes=21154 hist=1
loomwright/skills/automate-loop/branch-mode.md bytes=3931 hist=0
loomwright/skills/automate-loop/command-lanes.md bytes=1093 hist=0
loomwright/skills/automate-loop/intake.md bytes=10379 hist=0
loomwright/skills/automate-loop/invariants.md bytes=6090 hist=0
loomwright/skills/automate-loop/lanes.md bytes=25763 hist=0
loomwright/skills/automate-loop/modes-and-merge-gate.md bytes=27208 hist=3
loomwright/skills/automate-loop/per-item-loop.md bytes=29940 hist=0
loomwright/skills/automate-loop/resume.md bytes=9919 hist=0
loomwright/skills/automate-loop/run-file.md bytes=10598 hist=0
loomwright/commands/automate.md bytes=19850 hist=0
TOTAL bytes=165925 hist=4
helpers.md bytes=45618
```

- Measured set: 204,313 → **165,925** bytes (−38,388 this subtask; −109,843 / −39.8% from the 275,768 baseline). `lanes.md` 57,472 → 25,763; `branch-mode.md` 7,592 → 3,931; `command-lanes.md` 4,111 → 1,093. The AC2 target (≤ 193,037) is now met with 27,112 bytes to spare; Subtask 4 does not need to cut anything for it.
- Default-path read set: unchanged at 47,094 bytes (none of the three files is read by default; `commands/automate.md` was not edited).
- History references: 12 → **4** (`lanes.md` 8 → 0: the run ids, the `2026-10-1x` owner-decision dates and the wave-W3/W4 stories moved to the rationale doc).
- `helpers.md`: 45,618 → 45,618 (not edited; nothing was moved into it).

What moved where:
- **Stories → rationale `## lanes and branch mode`** (4 existing `story` rows re-homed `rationale:docs/rationale/automate-loop.md#…`: AL-149 branch-mode honest limits, AL-150 the command's lanes block, AL-504 wave-close honest limits, AL-512 policy honest limits). Ten new `story` rows, AL-591 … AL-600, home the story and explanation halves split out of rule/deterministic rows: why the primary stays locked, why single-lane mode needs branch mode, the lane-watcher incident, the step-timeline explanation, the kept-answer and resume limits, the wave-end exact-list incidents, watcher survival, the token-ledger history, the leak-check false positives, keep-awake. One new `rule` row, AL-590 (`script:meta-sync.sh pull`, `test-meta-sync.sh`), carries the rule half of AL-149 (offline / managed-path conflict stops the run) that stays in `branch-mode.md`.
- **Script-owned prose deleted** (rows homed `script:automate-lanes.sh <sub>`, `script:automate-wave.sh wave-build`, `script:lane-policy.sh <sub>`, `script:lane-sampler.sh`, `script:automate-trail.sh trail-pr`, `script:meta-sync.sh push`, `script:session-resume.sh`, `script:automate-helpers.sh meta-push-failed`): each subcommand's output lines, refusal lists and mechanics (the `automate-lanes.sh` / `automate-wave.sh` headers are the per-subcommand contract; `lane-status`'s state list is that header's "first match wins" list), the six-step `fleet-closeout` detail (now one line per step), `wave-build`'s refusal list, the policy stamp/resolve/decide mechanics (`docs/LANE_GATES.md` already holds them — the house rule's pointer form), the leak-check section formats. One line stays wherever the coordinator would otherwise act by hand: relay a question verbatim and never answer it, never hand-write the conversion or push lane metadata another way, never auto-abandon a `gone` lane, `--force-unlock` is human-only, never set the gate opt-out, never retry a BLOCKED spawn in another shape, the owner merges the wave PR, the per-outcome actions for `wave-build`, `meta-entry` and `fleet-closeout` lines.
- **`command-lanes.md`** — a second, longer copy of §14 read under the same trigger as `lanes.md`; replaced by a short owner-facing summary (launch authority, single-lane refusals, never-merges) and a pointer to §14.
- **Kept byte-identical (pinned):** every heading of the three files (so no `SKILL.md` split-block entry changed and every `§13`/`§14` quoted-anchor citation still resolves); the per-wave loop's numbering (cited as step 4 / 8 / 9 by `ARCHITECTURE_CONTRACTS.md`, `guard-lane-wait-armed.sh`, `automate-wave.sh`); the §14 intro line `test-automate-helpers.d/15-lane-seams.sh` pins (`**Without the flag, no lane code path is entered**` … ``except the read-only `pick-guard` `` … ``**`--parallel 1` is single-lane mode**``); the Terminal-park sentence `test-automate-trail.d/05` NT6 pins (``it runs no `current-set` but `closeout <the lane's run file> <item> <its ## Current pr> --no-trail` inside the lane``); the two `prose` anchors AL-451 (`**Wave policy (optional, interactive only):**`) and AL-471 (``**`died`, `lost_to_reset`** — reported; the owner decides.``).
- Inventory: five anchors updated where a bold label lost its history tag (AL-439, AL-474, AL-486, AL-491, AL-152); `## Counts` recomputed (598 rows, 139 rule, 38 story, 143 GAP); AL-591 … AL-600 added to the gap list. Rows homed `script:…` / `step-scoped` whose prose was deleted keep their old `q:` anchor, as in Subtask 2 (those homes are not anchor-checked).
- `vendor-coupling-manifest.json`: unchanged — none of the three files carries a counted token (no allowance at base), and the moved text carries none into the rationale doc.

### Subtask 4 — modes-and-merge-gate.md and intake.md

The same loop as Subtask 1, on the Subtask 4 working tree:

```
loomwright/skills/automate-loop/SKILL.md bytes=21154 hist=1
loomwright/skills/automate-loop/branch-mode.md bytes=3931 hist=0
loomwright/skills/automate-loop/command-lanes.md bytes=1093 hist=0
loomwright/skills/automate-loop/intake.md bytes=8057 hist=0
loomwright/skills/automate-loop/invariants.md bytes=6090 hist=0
loomwright/skills/automate-loop/lanes.md bytes=25763 hist=0
loomwright/skills/automate-loop/modes-and-merge-gate.md bytes=12923 hist=0
loomwright/skills/automate-loop/per-item-loop.md bytes=29940 hist=0
loomwright/skills/automate-loop/resume.md bytes=9919 hist=0
loomwright/skills/automate-loop/run-file.md bytes=10598 hist=0
loomwright/commands/automate.md bytes=19850 hist=0
TOTAL bytes=149318 hist=1
helpers.md bytes=45618
```

- Measured set: 165,925 → **149,318** bytes (−16,607 this subtask; −126,450 / −45.9% from the 275,768 baseline). `modes-and-merge-gate.md` 27,208 → 12,923; `intake.md` 10,379 → 8,057. The AC2 target (≤ 193,037) stays met.
- Default-path read set: unchanged at 47,094 bytes (neither file is read by default; `SKILL.md` and the command body were not edited).
- History references: 4 → **1** (`modes-and-merge-gate.md` 3 → 0: `red-team-hardening item 03`, `item 01` and the `2026-09-28` owner-decision date moved to the rationale doc or were cut; the one left is in `SKILL.md`).
- `helpers.md`: 45,618 → 45,618 (not edited; nothing was moved into it).

What moved where:
- **Stories → rationale `## merge gate and intake`** (4 existing `story` rows re-homed `rationale:docs/rationale/automate-loop.md#…`: AL-424 the high-risk honest limit and AL-436 the rules-gate dormancy limit, both under "Honest limits of the high-risk and rules conditions"; AL-427 the checkout-pin honest limits; AL-429 the checkout pin's premise; all four were homed at a `rationale:` heading inside `modes-and-merge-gate.md`). Seven new `story` rows, AL-601 … AL-607, home the story and explanation halves split out of rule/deterministic rows: why the merge is the engine's own step (AL-404), why the gate is self-resolving (AL-411), how condition 1 treats `sub_floor_converged` / `ci_untrusted` / died and superseded values (AL-415), how the checkout pin reads a clean tree and why `.supervisor/` and the agent-memory store are excluded (AL-426), why the Queue is confirmed and when it is skipped (AL-187 / AL-189), why a named file's stamp counts as done and the engine never ticks the backlog doc (AL-179 / AL-180), why the parallel intake lint is information only (AL-182).
- **Script-owned prose deleted** (rows homed `script:automate-helpers.sh gate-eval`, `script:automate-next-step.sh gate|validation|park|gate-eval`, `script:classify-risk.sh`, `script:rules-gate-verdict.sh`, `script:automate-helpers.sh resolve-backlog|resolve-folder` — `test-loop-inventory.sh` checks each arm): the fenced `ctx.json` JSON (the driver writes it — `automate-next-step.sh`'s gate-eval step, `<run_id>.gate-ctx.json`), the verbatim GraphQL block, condition 1's `ci_untrusted` / died-drain reasoning, the checkout pin's git-read recipe (c)/(d), the `unstamped_reason` message texts, the `cmd_disabled` verdict ranking, the backlog path-resolution detail. `gate_eval()`'s header comment in `automate-helpers.sh` already carries the full recipe and every park reason, so §10 now points at it (the house rule's pointer form) instead of keeping a second copy. One line stays wherever the coordinator could otherwise act by hand or the owner needs the park reason: never merge by hand, never write `ctx.json` by hand, every named `PARK:` reason, the no-override wording of conditions 4, 6 and 7, the fix hint.
- **Kept byte-identical (pinned):** both `##` headings, the `§10` numbered list 1–7 (`fixtures/automate-golden/MAP.tsv` maps `§9`, `§10` and `L1.1`–`L1.7`), every `###` heading of `intake.md` (one `SKILL.md` entry each, and `§2 "--limit N"` / `"Backlog-doc source"` / `"Prompt source"` citations), the `--auto-merge` bullet and the bold labels and phrase order `test-automate-dismissed.sh` reads from the §9 bullets, `test-rules-gate-seams.sh` pin 6's needles, the positive-form merge line `On all seven holding: …`, `test-classify-risk.sh` E5's `classify-risk.sh` mention, the queue-confirm bullet's four QG4 needles, the lane bullet's `skipped AUT-QUEUE: lane backlog written by lane-create from the owner's --parallel command`, the bare-`/automate` statuses `test-non-interactive-gates-seam.sh` reads, and the two `prose` anchors AL-409 (`**resolve the PR** (fix + merge, or close), **OR**`) and AL-428 (`**Fix hint for a \`rules_gate_dirty_tree\` park on a clean checkout:**`).
- Inventory: ten anchors updated where a bold label lost its history tag or its sentence was rewritten (AL-405, AL-411, AL-412, AL-418, AL-419, AL-421, AL-422, AL-426, AL-187, AL-189); `## Counts` recomputed (605 rows, 45 story, 150 GAP); AL-601 … AL-607 added to the gap list. The four re-homed story rows keep their old `q:` anchor, as in Subtasks 2–3 (a `rationale:` row's own anchor is not checked).
- `vendor-coupling-manifest.json`: `modes-and-merge-gate.md` 4 → 1 (the trusted-actor path and two agent-memory mentions left with the moved text; one `.claude/` stays in the checkout-pin rule) and its note records the cut; `intake.md` keeps its one (`AskUserQuestion` in the bare-`/automate` bullet). The rationale doc carries no counted token and no positive-form merge mention.

## Read set (Step 0)

After Subtask 1, `commands/automate.md` Step 0 reads (one line per entry; `grep -nE '^Read |\*\*Always\*\*|\*\*Only when\*\*' loomwright/commands/automate.md`):

```
66:Read ${CLAUDE_PLUGIN_ROOT}/skills/automate-loop/SKILL.md   # the AUTHORITY — the coordinator loop, the global rules, the split-file index
67:Read ${CLAUDE_PLUGIN_ROOT}/commands/autonomous.md          # ONLY under --inline-phases: …
68:Read ${CLAUDE_PLUGIN_ROOT}/commands/review-pr.md           # ONLY under --inline-phases: …
76:- `helpers.md`, **Only when** a helper's behaviour is in question …
77:- `intake.md`, **Only when** the start resolves to a NEW run …
78:- `run-file.md`, **Only when** the start resolves to a NEW run (intake writes its first run file from the template), a run-file helper (`runfile-write`, `progress-append`, `queue-checkoff`, `current-set`) or a `next-step` call exits non-zero naming the run file, or the owner asks for a `# skipped:` / `# abandoned:` check-off. …
79:- `resume.md`, **Only when** a `next-step --resume` call exits non-zero …
80:- `per-item-loop.md`, **Only when** a `--start pick|run|drain` or `--result` call exits non-zero …
81:- `modes-and-merge-gate.md`, **Only when** a call answering a `gate`, `validation`, `gate-eval`, `dismissed`, `decide` or `fix-now` instruction exits non-zero …
82:- `invariants.md`, **Always** (read now, with the reads in the code block above).
83:- `branch-mode.md`, **Only when** `meta-entry` prints anything but `meta-entry: off` …
84:- `lanes.md`, **Only when** `--parallel` was passed …
85:- `command-lanes.md`, **Only when** the lanes trigger of the row above holds …
```

The only unconditional reads are `SKILL.md` (line 66) and `invariants.md` (line 82); neither holds a driver-owned step. Every item-25 **Only when** line is byte-identical (only the new `run-file.md` line was inserted, between `intake.md` and `resume.md`, which is its documented order — check F green). The run-file writes (§3) now sit behind the `run-file.md` trigger.

Why each after-tree `SKILL.md` section stays in the default read set:

- `## §1 — Purpose & Layering` + `### Non-goals (v1)` — global scope rules (no adapter framework, no runner agent, single-open-PR invariant, no second tracking file); the story moved out.
- `## Coordinator loop — run next-step; do the one instruction; report the result` — the main thread's whole job on every run (touched-file invariant: stays in the default read set).
- `## §3` … `## §11`, `## §13`, `## §14` and their `###` entries — one `See [<file>](<file>).` line each (the split index; §N numbers kept for citations).
- `## §12` `### Flags` — one pointer line to the command's Usage block; `### \`/loop\` driver` — the headless-tick and stop rules, which the command no longer restates.
- `## Anti-Patterns` — one line per global "never" rule (each points at its step).
- `## Related Skills` — five pointers.
- `## Quality Gates` — the global acceptance checks, incl. the never-merge and single-drain invariants.
- `## Cited sub-section anchors` (index-only) — resolves the tracked citations whose bold label left the index (adds `After a close-out` and `Validate before rename` → `run-file.md`).

**Honest limit (AC4):** `commands/automate.md` "Short overview" is still in the always-read command body. It is a one-line-per-step map of driver-owned steps (2,325 bytes, down from 6,634 — `awk '/^### Short overview/{s=1} /^> \*\*Invariant \(durable\)/{s=0} s' | wc -c` on each tree) and names each step only as "never run one by hand". It stays because tests read the raw command body for its mirrors (`test-automate-trail.d/01` `` `trail-gate` `` / `never at a park`, `/04` `closeout` + `trail-pr`, `/05` `closeout-classify` + `closeout-others` + `closeout --no-trail`, `test-automate-dismissed.sh` C8 and its single-drain scan, which needs at least one qualified `exactly ONE inline` line in the command). Moving it would need a second new split file (the brief allows at most one) and five repointed tests — recorded below as a behaviour question for the owner.

## Behaviour questions

- **(Subtask 1) The command's Short overview is a driver-owned map in the default read set.** AC4 asks that no section whose steps the driver owns is read unconditionally. The overview was cut to a one-line-per-step map and kept in place because five test legs pin its text in the raw command body (Read set above). Owner decision: accept the map as a non-instruction pointer, or approve a second new split file (`skills/automate-loop/command-overview.md`, its own Step 0 **Only when** line) with those test legs repointed (path only).
- **(Subtask 1) `test-automate-dismissed.sh`'s "unqualified drain-ownership" scan fails a surface with zero matching lines** (an empty here-string yields one empty, unqualified line). It forced `commands/automate.md` to keep a qualified `exactly ONE inline` phrase. Recorded, not fixed (the test is outside this diet's behaviour scope).

- **(Subtask 2) Inventory row AL-387 contradicted the driver.** It said RECONCILE's crash-restore of a stranded config backup is "prose there — never a driver step", while `automate-next-step.sh`'s header lists the stranded config-backup restore under its `reconcile` step and refuses `--start run` over a backup (`config_backup_stranded`). The row is re-homed to `script:automate-next-step.sh reconcile`; recorded so the owner can confirm the driver, not the coordinator, owns that restore.
- **(Subtask 2) The golden map freezes the shape of `per-item-loop.md` and `resume.md`.** `fixtures/automate-golden/MAP.tsv` maps every heading and every numbered step of both files, so a section now reduced to a few lines (Brief-repair, Termination) keeps its heading. Merging or dropping such a heading needs a MAP.tsv edit outside this item's lanes.

- **(Subtask 2) `automate-merge-watch.sh`'s header names `SKILL.md` §6 "Post-merge close-out" its PROTOCOL AUTHORITY,** while that section now keeps one bullet and defers the watcher's mechanics to the script header (its rows AL-372 … AL-379 are homed `script:automate-merge-watch.sh`). The header comment is outside this item's lanes and was not edited; the owner decides whether the script header becomes the stated authority.

- **(Subtask 3) The lane's `lane resume: <value>` Progress line is written by the model, not a script.** `automate-lanes.d/launch.sh` only sets `LOOMWRIGHT_LANE_RESUME_PATH`; nothing in `automate-next-step.sh` or the helpers reads it, so the line exists only if the lane's engine follows `lanes.md` INIT. Kept as prose; the owner decides whether the driver's entry should write it.
- **(Subtask 3) `lanes.md` points at the `automate-lanes.sh` header for `lane-status`'s state list and each subcommand's outputs.** The header is now the only full copy; a later header edit has no doc twin to drift from, but the header is a code comment that no test pins against the prose.

- **(Subtask 4) §10 condition 3 said the gate runs `review-heal/SKILL.md` §U1 (b)'s GraphQL query "VERBATIM … (never re-derived)",** while `gate_eval()`'s header says the query is "adapted from review-heal/SKILL.md §U1(b) (same query minus the unused `body` field)". The runtime line now matches the script ("its own copy … minus the unused `body` field"). No test compares the two queries; the owner decides whether one should.
- **(Subtask 4) The folder source's "sibling `_BACKLOG.md` documents a build order ⇒ defer to backlog-doc ordering" rule (AL-176) is model-run only.** `resolve-folder` lists the directory and never looks for a sibling `_BACKLOG.md`, so the rule holds only if the coordinator checks the folder for one before calling the helper. Kept as prose, unchanged.
- **(Subtask 4) §10 now summarises and points at `gate_eval()`'s header comment,** which in turn names `skills/automate-loop/SKILL.md §10 condition 7` as the place `D3's middle form` is explained. Both still resolve (§10 keeps the D3 sentence), but the full park-reason list and the checkout pin's git-read recipe now live only in that header comment, which no test pins against the prose.

## Proposed hooks

- (Subtask 1) None — no rule in SKILL.md, invariants.md or the command body needed a new hook to leave the prompt.

- (Subtask 2) None — every rule left in `per-item-loop.md` / `resume.md` is either executed by an existing driver or helper arm or stays as one prose line; no rule needed a new hook.

- (Subtask 3) None — every lane, wave and branch-mode rule left in the three files is executed by an existing `automate-lanes.sh` / `automate-wave.sh` / `lane-policy.sh` / `meta-sync.sh` arm, the `guard-lane-wait-armed.sh` Stop hook, or stays as one prose line.

- (Subtask 4) None — every merge-gate rule is executed by `automate-helpers.sh gate-eval` (with `classify-risk.sh` / `rules-gate-verdict.sh`) or the driver's `gate` / `validation` / `park` / `gate-eval` steps, and every intake rule by `resolve-folder` / `resolve-backlog` / `queue-confirm` / `plan-waves` or stays as one prose line. The one rule no script runs (AL-176, above) needs a helper change, not a hook.

## Pin mutations

- **(Subtask 1) One test repointed (path only).** `loomwright/scripts/test-automate-lanes.d/01-create-to-wait.sh` AH12 read the template's `^- pause_reason: ` line raw from `skills/automate-loop/SKILL.md`; that line moved, byte-identical, to `skills/automate-loop/run-file.md`, so the read now names `run-file.md`. Concrete literal: `grep -m1 '^- pause_reason: ' "$HERE/../skills/automate-loop/run-file.md"`. Every other pinned needle stayed in a file its test reads (the assembled skill via `fixtures/automate-loop-split/assemble.sh` includes `run-file.md`). Mutation row — AH12's own extraction against the lanes bundle, on the real `run-file.md` and on a scratch copy with the `- pause_reason:` line deleted:

```
mutant gated: non-empty, differs (80 -> 79 lines)
orig: AH12 count=4 (want 4) GREEN; AH12a drift=[] GREEN
mut: AH12 count=3 (want 4) RED; AH12a drift=[awaiting_go ] RED
```
- **(Subtask 1) check F — the new Step 0 line.** Mutant: `commands/automate.md` (scratch copy) with the line holding ``- `run-file.md`, **Only when**`` deleted; check F's own `step0_names` / `want_step0` logic run on both:

```
mutant gated: non-empty, differs (121 -> 120 lines)
original: check F GREEN (helpers.md intake.md run-file.md resume.md per-item-loop.md modes-and-merge-gate.md invariants.md branch-mode.md lanes.md command-lanes.md )
mutant: check F RED — have [helpers.md intake.md resume.md per-item-loop.md modes-and-merge-gate.md invariants.md branch-mode.md lanes.md command-lanes.md ]
```

- **(Subtask 2) No test repointed** — every pinned needle stayed in `per-item-loop.md` / `resume.md`, which the readers already take (raw, or through `fixtures/automate-loop-split/assemble.sh`). Mutation control for the kept `prose` anchors: on a `mktemp -d` copy of `loomwright/` (with `HOME` relocated), the line holding AL-236's anchor (`ONE owner question batching ≤4 leftovers`) deleted from `per-item-loop.md`, then `test-loop-inventory.sh --root <copy>`:

```
mutant gated: non-empty, differs (104 -> 103 lines)
FAIL AL-236: anchor not found in skills/automate-loop/per-item-loop.md
FAIL RH-329: test cell names no existing test-*.sh under loomwright/scripts/ or scripts/: test-check-shared-prefix.sh
loop-inventory: FAIL — 2 problem(s)
# control (the unmutated file restored into the same copy):
loop-inventory: FAIL — 1 problem(s)
```

The RH-329 line is a `--root` artifact on both runs (the copy has no sibling root `scripts/`, where `test-check-shared-prefix.sh` lives); the mutant adds exactly the AL-236 failure.

- **(Subtask 3) No test repointed** — every pinned needle stayed in `lanes.md` / `branch-mode.md`, which the readers take through `fixtures/automate-loop-split/assemble.sh`. Two mutation controls, each on a `mktemp -d` copy, each mutant checked non-empty and different first:
  - the line holding AL-471's live `prose` anchor (``**`died`, `lost_to_reset`** — reported; the owner decides.``) deleted from `lanes.md`, then `test-loop-inventory.sh --root <copy>` (with `HOME` relocated);
  - ``except the read-only `pick-guard` `` reworded to ``except the `pick-guard` `` in `lanes.md`, the skill re-assembled with the copy's `assemble.sh`, and `15-lane-seams.sh`'s own intro check (`grep -F` of the bold line, then its `case` pattern) run on both assemblies.

```
mutant gated: non-empty, differs (102 -> 101 lines)
FAIL AL-471: anchor not found in skills/automate-loop/lanes.md
FAIL RH-329: test cell names no existing test-*.sh under loomwright/scripts/ or scripts/: test-check-shared-prefix.sh
loop-inventory: FAIL — 2 problem(s)
# control:
FAIL RH-329: test cell names no existing test-*.sh under loomwright/scripts/ or scripts/: test-check-shared-prefix.sh
loop-inventory: FAIL — 1 problem(s)

orig: GREEN
mutant differs
mut: RED
```

The RH-329 line is the same `--root` artifact as in Subtask 2; the mutant adds exactly the AL-471 failure.

- **(Subtask 4) No test repointed** — every pinned needle stayed in `modes-and-merge-gate.md` / `intake.md`, which their readers already take (`test-rules-gate-seams.sh` `AL=` and `16-queue-gates.sh` `QG_INTAKE=` raw; the others through `fixtures/automate-loop-split/assemble.sh`). Both of those raw readers run their own gated prose mutants on every run (pin 6's first needle deleted; QG1d' `written by → made by`, QG4 `queue-confirm` call removed), and all three still turn red on the after tree (Results). Mutation control for the kept `prose` anchor AL-428: on a `mktemp -d` copy of `loomwright/` (with `HOME` relocated), the line holding ``**Fix hint for a `rules_gate_dirty_tree` park on a clean checkout:**`` deleted from `modes-and-merge-gate.md`, then `test-loop-inventory.sh --root <copy>`:

```
mutant gated: non-empty, differs (59 -> 58 lines)
FAIL AL-428: anchor not found in skills/automate-loop/modes-and-merge-gate.md
FAIL RH-329: test cell names no existing test-*.sh under loomwright/scripts/ or scripts/: test-check-shared-prefix.sh
loop-inventory: FAIL — 2 problem(s)
# control:
FAIL RH-329: test cell names no existing test-*.sh under loomwright/scripts/ or scripts/: test-check-shared-prefix.sh
loop-inventory: FAIL — 1 problem(s)
```

The RH-329 line is the same `--root` artifact as in Subtasks 2–3; the mutant adds exactly the AL-428 failure.

## Results

### Subtask 1 — results

Run on the Subtask 1 tree (each script from the repo root, `bash <script>`):

| Gate / test | Result |
|---|---|
| `loomwright/scripts/test-loop-inventory.sh` | 43/43 passed |
| `loomwright/scripts/test-automate-loop-split.sh` | 40 passed, 0 failed (check E prints SKIP for the edited files, as expected) |
| `loomwright/scripts/test-automate-next-step.sh` | 153 passed, 0 failed (incl. `leg_surface`: the positive-form merge grep prints exactly `SURFACE_BASE`) |
| `loomwright/scripts/test-automate-dismissed.sh` | 255 passed, 0 failed |
| `loomwright/scripts/test-non-interactive-gates-seam.sh` | 64 passed, 0 failed |
| `loomwright/scripts/test-rules-gate-seams.sh` | 26 passed, 0 failed |
| `loomwright/scripts/test-automate-trail.sh` | 786 passed, 0 failed |
| `loomwright/scripts/test-automate-golden.sh` | 65 passed, 0 failed |
| `loomwright/scripts/test-run-lock.sh` | 88 passed, 0 failed |
| `loomwright/scripts/test-session-resume.sh` | 338 passed, 0 failed |
| `loomwright/scripts/test-build-handoff.sh` | 93 passed, 0 failed |
| `loomwright/scripts/test-build-loop-evidence.sh` | 30 passed, 0 failed |
| `loomwright/scripts/test-classify-risk.sh` | 46 passed, 0 failed |
| `loomwright/scripts/test-context-digest.sh` | 37/37 |
| `loomwright/scripts/test-harvest-conventions.sh` | 172 passed, 0 failed |
| `loomwright/scripts/test-setup-memory.sh` | 574 passed, 0 failed |
| `loomwright/scripts/test-citation-drift.sh` | 26 passed, 0 failed |
| `scripts/check-doc-currency.sh`, `scripts/check-token-budget.sh`, `scripts/check-vendor-coupling.sh`, `scripts/check-skills-index-sync.sh` | OK |
| `loomwright/scripts/test-automate-helpers.sh` | 769 passed, 1 failed — the same failure as at base (`W19 real 22-split-automate-engine-surfaces.md ## Touches parses`, which reads a requirement file and a missing `.agent/companions.json`; no group file involved) |
| `loomwright/scripts/test-automate-lanes.sh` | 953 passed, 42 failed — the identical failure set as at base (`diff` of the sorted `FAIL` lines is empty; lane-policy / inbox legs J*/K*/X*, none reads a group file). Before the AH12 repoint above it was 950/45: the 3 extra failures were AH12/AH12a/AH12c |

### Subtask 2 — results

Run on the Subtask 2 tree (each script from the repo root, `bash <script>`; the machine ran other lanes' suites at the same time, load average up to 133):

| Gate / test | Result |
|---|---|
| `loomwright/scripts/test-loop-inventory.sh` | 43/43 passed |
| `loomwright/scripts/test-automate-loop-split.sh` | 40 passed, 0 failed |
| `loomwright/scripts/test-automate-next-step.sh` | 153 passed, 0 failed (incl. the merge-surface leg: the positive-form grep prints exactly `SURFACE_BASE`) |
| `loomwright/scripts/test-automate-dismissed.sh` | 255 passed, 0 failed |
| `loomwright/scripts/test-automate-trail.sh` | 786 passed, 0 failed |
| `loomwright/scripts/test-automate-golden.sh` | 65 passed, 0 failed |
| `loomwright/scripts/test-session-resume.sh` | 338 passed, 0 failed |
| `loomwright/scripts/test-run-lock.sh` | 88 passed, 0 failed |
| `loomwright/scripts/test-non-interactive-gates-seam.sh` | 64 passed, 0 failed |
| `loomwright/scripts/test-rules-gate-seams.sh` | 26 passed, 0 failed |
| `loomwright/scripts/test-classify-risk.sh` | 46 passed, 0 failed |
| `loomwright/scripts/test-build-handoff.sh` / `test-build-loop-evidence.sh` / `test-context-digest.sh` / `test-harvest-conventions.sh` | 93 / 30 / 37 of 37 / 172 passed, 0 failed |
| `loomwright/scripts/test-command-parts.sh` / `test-curation-status.sh` / `test-rules-docs.sh` / `test-setup-memory.sh` | 37 / 333 / 46 / 574 passed, 0 failed |
| `loomwright/scripts/test-citation-drift.sh` | 26 passed, 0 failed |
| `scripts/check-doc-currency.sh`, `scripts/check-token-budget.sh`, `scripts/check-vendor-coupling.sh`, `scripts/check-skills-index-sync.sh` | OK |
| `loomwright/scripts/test-automate-helpers.sh` | 769 passed, 1 failed — the base failure (`W19 … ## Touches parses`) |
| `loomwright/scripts/test-automate-lanes.sh` | 953 passed, 42 failed — the base counts. A first run under peak load read 949/46 (four extra AD/AM/AH inbox legs, none of which reads a group file); the re-run alone read 953/42. Its two group-file legs pass: AJ4e5 (the raw `per-item-loop.md` no-PR line) and AH12 (`run-file.md`). The failing-set diff against a base run was not re-made here. |

### Subtask 3 — results

Run on the Subtask 3 tree (each script from the repo root, `bash <script>`; four groups ran at once, load average about 24):

| Gate / test | Result |
|---|---|
| `loomwright/scripts/test-loop-inventory.sh` | 43/43 passed |
| `loomwright/scripts/test-automate-loop-split.sh` | 40 passed, 0 failed |
| `loomwright/scripts/test-automate-next-step.sh` | 153 passed, 0 failed; the positive-form merge grep prints exactly `SURFACE_BASE` (`diff` empty) |
| `loomwright/scripts/test-automate-golden.sh` | 65 passed, 0 failed |
| `loomwright/scripts/test-automate-trail.sh` | 786 passed, 0 failed |
| `loomwright/scripts/test-automate-dismissed.sh` | 255 passed, 0 failed |
| `loomwright/scripts/test-run-lock.sh` / `test-session-resume.sh` / `test-setup-memory.sh` | 88 / 338 / 574 passed, 0 failed |
| `loomwright/scripts/test-non-interactive-gates-seam.sh` / `test-rules-gate-seams.sh` / `test-classify-risk.sh` | 64 / 26 / 46 passed, 0 failed |
| `loomwright/scripts/test-command-parts.sh` / `test-curation-status.sh` / `test-rules-docs.sh` | 37 / 333 / 46 passed, 0 failed |
| `loomwright/scripts/test-build-handoff.sh` / `test-build-loop-evidence.sh` / `test-context-digest.sh` / `test-harvest-conventions.sh` | 93 / 30 / 37 of 37 / 172 passed, 0 failed |
| `loomwright/scripts/test-citation-drift.sh` | 26 passed, 0 failed |
| `scripts/check-doc-currency.sh`, `scripts/check-token-budget.sh`, `scripts/check-vendor-coupling.sh`, `scripts/check-skills-index-sync.sh` | OK |
| `loomwright/scripts/test-automate-helpers.sh` | 769 passed, 1 failed — the base failure (`W19 … ## Touches parses`) |
| `loomwright/scripts/test-automate-lanes.sh` | 953 passed, 42 failed — re-run alone; the sorted `FAIL` id list is identical to a run of the same script on `git archive HEAD` (the Subtask 2 tree) extracted to a scratch directory (`diff` empty). The first run, beside the other groups, read 949/46: the four extra were the timing-sensitive `lane-wait` legs AH1g, AH2, AH3b, AH16, none of which reads a group file. |

### Subtask 4 — results

Run on the Subtask 4 tree (each script from the repo root, `bash <script>`; other lanes ran suites at the same time, load average about 28):

| Gate / test | Result |
|---|---|
| `loomwright/scripts/test-loop-inventory.sh` | 43/43 passed |
| `loomwright/scripts/test-automate-loop-split.sh` | 40 passed, 0 failed |
| `loomwright/scripts/test-automate-next-step.sh` | 153 passed, 0 failed; the positive-form merge grep prints exactly `SURFACE_BASE` (`diff` empty) |
| `loomwright/scripts/test-rules-gate-seams.sh` | 26 passed, 0 failed (pin 6 read from `modes-and-merge-gate.md`; its gated mutant red) |
| `loomwright/scripts/test-automate-golden.sh` | 65 passed, 0 failed (`§9`, `§10`, `L1.1`–`L1.7` still mapped) |
| `loomwright/scripts/test-automate-dismissed.sh` | 255 passed, 0 failed (the three §9 bullet-order legs) |
| `loomwright/scripts/test-non-interactive-gates-seam.sh` / `test-classify-risk.sh` | 64 / 46 passed, 0 failed |
| `loomwright/scripts/test-automate-trail.sh` / `test-run-lock.sh` / `test-session-resume.sh` | 786 / 88 / 338 passed, 0 failed |
| `loomwright/scripts/test-build-handoff.sh` / `test-build-loop-evidence.sh` / `test-context-digest.sh` / `test-harvest-conventions.sh` | 93 / 30 / 37 of 37 / 172 passed, 0 failed |
| `loomwright/scripts/test-command-parts.sh` / `test-curation-status.sh` / `test-rules-docs.sh` / `test-setup-memory.sh` | 37 / 333 / 46 / 574 passed, 0 failed |
| `loomwright/scripts/test-citation-drift.sh` | 26 passed, 0 failed |
| `scripts/check-doc-currency.sh`, `scripts/check-token-budget.sh`, `scripts/check-vendor-coupling.sh`, `scripts/check-skills-index-sync.sh` | OK |
| `loomwright/scripts/test-automate-helpers.sh` | 769 passed, 1 failed — the base failure (`W19 … ## Touches parses`); QG1d', QG4 and both intake prose mutants pass |
| `loomwright/scripts/test-automate-lanes.sh` | Not run here — none of its legs reads `modes-and-merge-gate.md` or `intake.md` (`grep -rlF` of both names under `loomwright/scripts/` and `scripts/` does not list it) |
