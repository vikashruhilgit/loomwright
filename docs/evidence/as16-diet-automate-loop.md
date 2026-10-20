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

## Proposed hooks

- (Subtask 1) None — no rule in SKILL.md, invariants.md or the command body needed a new hook to leave the prompt.

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
