# Supervisor Job: Prompt diet — automate-loop carries rules, not stories, and loads by phase (automate-speed/16)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-15-163325/L22 (lane L22 clone of the loomwright repo)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/automate-speed/16-diet-automate-loop.md
- **Base commit:** ee3d7ea3bb069c50a07c3b37222c52c88202263b

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt files + bash 3.2 tests; no new stack |
| 2 | Dependency Availability | GO | No new dependency; `test-loop-inventory.sh` already resolves `rationale:<doc>#<anchor>` / `global` / `step-scoped` / `script:` homes, and its `automate-loop)` arm globs `skills/automate-loop/*.md`, so a new split file is picked up without editing the checker |
| 3 | Architecture Fit | GO | Same shape as the merged automate-speed/13, /14 and /15 diets (rationale doc + inventory re-homing + load-by-mode reads); automate-loop is already a split index (parallel-automate/22) with Step 0 "Only when" reads (automate-speed/25) |
| 4 | Scope vs Supervisor Capability | CAUTION | 275,768 bytes of runtime prose over 10 files and 584 inventory rows; > 800 changed lines ⇒ `context-bound` split into 5 serialized subtasks |
| 5 | Hard Blockers | CAUTION | The ≥ 30% read-set cut must come from deleting script-owned prose and moving stories, while pinned needles stay byte-identical; the supervisor diet (automate-speed/15) reached −26.0% under the same constraint and escalated on it |

**Overall Verdict:** CAUTION

## Task
**Goal:** Cut the automate-loop group's runtime prompts (`skills/automate-loop/{SKILL,branch-mode,command-lanes,intake,invariants,lanes,modes-and-merge-gate,per-item-loop,resume}.md` and `commands/automate.md`) to instructions and short rules: every story moves to a new `docs/rationale/automate-loop.md`, every rule keeps a non-prose home in `docs/loop-inventory/automate-loop.md`, and every remaining section loads only at the step that uses it, with nothing the `next-step` driver owns read on a normal run. No behaviour change.

**Problem Statement:**
The `/automate` coordinator needs its prompts to cost only what the executing model uses at the moment it uses it.
Currently the ten runtime files total 275,768 bytes at the base commit (per-item-loop.md 66,665; lanes.md 57,472; SKILL.md 46,413; commands/automate.md 30,161; modes-and-merge-gate.md 27,208; resume.md 18,941; intake.md 10,379; branch-mode.md 7,592; invariants.md 6,826; command-lanes.md 4,111) and carry 28 history references. Every start reads SKILL.md, invariants.md and the command body in full (83,400 bytes), including sections such as the run-file template whose writes the driver now owns ("never writes the run file itself"). The inventory still has 26 `story` rows, none homed in a rationale doc: 3 are homed `global`, 4 `script:` and 19 `rationale:` headings inside runtime split files.
Success looks like: the read set is at least 30% smaller, there are fewer history references, every `story` row is homed in `docs/rationale/automate-loop.md`, and every gate test stays green.

## Acceptance Criteria
- [ ] AC1 — Given `loomwright/docs/loop-inventory/automate-loop.md` after this item, when its rows are counted by kind and home, then every row of kind `story` has home `rationale:docs/rationale/automate-loop.md#<anchor>` (never `prose`, `global`, `script:…`, or a `rationale:` heading inside a runtime file under `skills/automate-loop/`). A story row that contains a rule is split first, and the rule part gets its own `rule` row. Every `rule` row has home `script:…`, `hook:…`, `step-scoped` or `global`, never `prose`. A rule row homed `script:`/`hook:` names a script `case` arm or hook leaf that exists at base. When its prose is deleted, one line stays only where the model would otherwise attempt the blocked action. `test-loop-inventory.sh` passes: heading coverage, live anchors for `prose`/`global`, rationale anchors resolve, `## Counts` and the gap list are recomputed from the table, and every new heading has a row.
- [ ] AC2 — Given the measured set (the ten runtime files above plus every new runtime file this item creates under `loomwright/skills/automate-loop/`, but NOT `docs/rationale/automate-loop.md`, the inventory doc, the changelog fragment or the evidence file), when `wc -c` is summed over it, then the total is ≤ 193,037 bytes (≥ 30% below 275,768). Text moved from a measured file into `helpers.md`, or into any other file the coordinator can read at runtime, counts against the cut: `helpers.md`'s before/after size is reported, and it must not grow. The default-path read set (SKILL.md + invariants.md + commands/automate.md + any file Step 0 marks **Always**) is reported too. Then a committed evidence file `docs/evidence/as16-diet-automate-loop.md` contains the before and after numbers and the commands that produced them, and the PR body links to it. If the target cannot be reached without rewording or deleting a pinned needle, the evidence file records the shortfall and the blocking pins under "Behaviour questions", and the pins are not reworded. A recorded shortfall leaves AC2 **unmet**: the run reports it as an open criterion and escalates to the owner. It is never counted as met.
- [ ] AC3 — Given the history-reference regex `'#[0-9]{2,4}\b|queue/[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2}|item [0-9]+'` (count = `grep -ohE … | wc -l` over the measured set), when it is run at the base commit and on the after tree, then the after count is lower than the before count. At base it is 28: SKILL.md 4, lanes.md 8, modes-and-merge-gate.md 3, per-item-loop.md 11, resume.md 1, commands/automate.md 1, other files 0. Then `docs/evidence/as16-diet-automate-loop.md` contains the command, the before count and the after count.
- [ ] AC4 — Given a sequential `/automate` run (no `--parallel`, no `--inline-phases`, branch mode off), when `commands/automate.md` Step 0 and `skills/automate-loop/SKILL.md` are followed, then no file or section whose steps `scripts/automate-next-step.sh` owns (PICK, RECONCILE, RUN, DRAIN, GATE, park, close-out, the run-file writes) is read unconditionally. Every such section sits in a split file whose Step 0 entry is **Only when** with a named trigger: a driver exit non-zero, an instruction that does not say what to do, or an owner request. Item 25's existing **Only when** triggers for `helpers.md`, `intake.md`, `resume.md`, `per-item-loop.md`, `modes-and-merge-gate.md`, `branch-mode.md`, `lanes.md` and `command-lanes.md` stay byte-identical. Then `docs/evidence/as16-diet-automate-loop.md` contains the Step 0 read list after the change, one line per section of the after-tree `SKILL.md` naming why it stays in the default read set, and a grep showing no unconditional `Read` of a driver-owned file. The transcript assertion is Validation 3, an owner pre-merge step recorded as "Not run" unless a live run was made.
- [ ] AC5 — Given the parallel-automate/22 split structure, when the after tree is checked, then `test-automate-loop-split.sh` passes:
  - every heading of every split file has its `See [<file>](<file>).` entry in its `SKILL.md` (or `commands/automate.md`) split block, in order;
  - every `*.md` in `skills/automate-loop/` is named by exactly one block;
  - Step 0 names every skill split file, in documented order;
  - every citation of `automate-loop/SKILL.md §N` or a quoted anchor still resolves. A heading that leaves a runtime file keeps a one-line pointer, or a `## Cited sub-section anchors` row, wherever a tracked citation uses it.

  Its move-only proof (check E) is expected to print SKIP for the edited files: that check proves the split commit, it does not freeze the files.
- [ ] AC6 — Given any test, gate or script that greps text from a group file (found by `grep -rlF` of each file's name under `loomwright/scripts/` and root `scripts/`; at base these include `test-automate-next-step.sh`, `test-rules-gate-seams.sh`, `test-automate-dismissed.sh`, `test-non-interactive-gates-seam.sh`, `test-automate-helpers.sh`, `test-automate-trail.sh`, `test-run-lock.sh`, `test-session-resume.sh`, `test-build-handoff.sh`, `test-build-loop-evidence.sh`, `test-classify-risk.sh`, `test-context-digest.sh`, `test-harvest-conventions.sh`, `test-automate-golden.sh` and the `automate-golden` fixtures), when text moves, then:
  - every pinned needle stays byte-identical, in a file the test reads (directly, or through `fixtures/automate-loop-split/assemble.sh`);
  - pinned text is never moved to the rationale doc and never reworded;
  - a test is repointed (path only) when its needle moves to a new split file.

  The positive-form merge grep (`grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`) must still print exactly the file list in `test-automate-next-step.sh`'s `SURFACE_BASE`. So the rationale doc adds no positive-form hit, and `per-item-loop.md`, `modes-and-merge-gate.md` and the inventory doc each keep at least one.
- [ ] AC7 — Given every invariant of CLAUDE.md §"Failure-Mode Invariants" that appears in this group, when the after tree is grepped for each one, then each stays in a runtime prompt (`invariants.md` §11, SKILL.md, the command body, or the split file at its step) or in an enforcing script or hook, and its inventory row names that home. The invariants are: the single `gh pr merge --squash` executor and its self-resolving seven-condition gate, never-merge for review-heal and Phase 4.5, single-drain ownership and the config toggle, two review lenses, bimodal fail-closed/fail-safe, the can't-ask branches and their named statuses, and the human-stamped countable must-rule gate (condition 7).
- [ ] AC8 — Given a rule whose prose could only leave the prompt behind a NEW hook, when the worker reaches it, then its prose stays and a draft is filed to `.supervisor/requirements/proposed/`. No hook is added. Given a behaviour question found while moving text, it is recorded and not fixed. Then `docs/evidence/as16-diet-automate-loop.md` contains a "Proposed hooks" list of each filed draft's path and a "Behaviour questions" list.
- [ ] AC9 — Given moved text, when the after tree is checked, then:
  - no count or version claim is added to it;
  - every `file:line` citation in the rationale doc is pinned (`[pins: …]`) or replaced by a descriptive anchor (`test-citation-drift.sh` green);
  - no install-root token of a class `scripts/check-vendor-coupling.sh` counts is added to the rationale doc;
  - each new runtime split file gets a `loomwright/docs/vendor-coupling-manifest.json` allowance and a note (`moved by automate-speed/16 … — no reference added`) when it carries a counted token, and the source file's allowance is lowered by the count it gave up.
- [ ] AC10 — Given the lane release rule, when the PR is opened, then it carries `changelog.d/as16-diet-automate-loop.md` (`<!-- bump: minor -->`, prose headline + body). It does not run `bump-version.sh` and does not edit `plugin.json`, `marketplace.json` or `CHANGELOG.md`. Prompt-budget ceilings in `loomwright/docs/prompt-token-budgets.json` are not lowered here (item 18 owns that) and must still pass.
- [ ] AC11 — Validation 1–2: given the finished tree, when the gates run, then each of these passes, reported `<passed>/<total>` (or the script's OK line): `test-loop-inventory.sh`, `scripts/check-doc-currency.sh`, `test-citation-drift.sh`, `scripts/check-token-budget.sh`, `scripts/check-vendor-coupling.sh`, `test-automate-loop-split.sh`, and every test listed under AC6. The mutation control also runs: delete one real `global` row's anchored line from a scratch copy of its source file, then run `test-loop-inventory.sh --root <scratch>`. It goes red naming that row, and the mutant is checked non-empty and different before it is trusted. Then `docs/evidence/as16-diet-automate-loop.md` contains every result and the mutant's command and output. The baseline (275,768 bytes; 28 history references) is re-measured at `ee3d7ea` with the commands written into the evidence file before any delta is reported. Validation 3 (one real item after the change, its result block pasted) is listed as an owner pre-merge step unless it was run.

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

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| default read set (index + command + invariants) | `loomwright/skills/automate-loop/SKILL.md`, `loomwright/skills/automate-loop/invariants.md`, `loomwright/commands/automate.md`, `loomwright/docs/loop-inventory/automate-loop.md`, `loomwright/docs/vendor-coupling-manifest.json`, `loomwright/skills/SKILLS_INDEX.md` (only if SKILL.md's frontmatter `version:` changes) | `loomwright/docs/rationale/automate-loop.md`, `docs/evidence/as16-diet-automate-loop.md`, at most one new driver-owned split file under `loomwright/skills/automate-loop/` (e.g. for the §3 run-file template; name chosen by the worker) | HIGH (new split file MEDIUM) |
| per-item + resume | `loomwright/skills/automate-loop/per-item-loop.md`, `loomwright/skills/automate-loop/resume.md`, SKILL.md split-block entries, inventory, rationale doc, pinning tests only if a needle moves file | — | HIGH |
| lanes | `loomwright/skills/automate-loop/lanes.md`, `loomwright/skills/automate-loop/command-lanes.md`, `loomwright/skills/automate-loop/branch-mode.md`, SKILL.md / command split-block entries, inventory, rationale doc | — | HIGH |
| gate + intake | `loomwright/skills/automate-loop/modes-and-merge-gate.md`, `loomwright/skills/automate-loop/intake.md`, SKILL.md split-block entries, inventory, rationale doc | — | HIGH |
| evidence + release | `docs/evidence/as16-diet-automate-loop.md` (created by Subtask 1) | `changelog.d/as16-diet-automate-loop.md` | HIGH |

**Not modified (by design):** `loomwright/skills/automate-loop/helpers.md` (no `story`/`prose` rows; text moved into it would count against AC2), `loomwright/scripts/automate-next-step.sh` and its golden fixtures (its instruction strings name `skills/automate-loop/lanes.md`, which keeps its name), `loomwright/scripts/test-loop-inventory.sh` (its `automate-loop)` arm already globs `skills/automate-loop/*.md`), `loomwright/docs/prompt-token-budgets.json` (item 18 lowers ceilings).

> **Validator-owned surfaces:**
> - `test-loop-inventory.sh` scans every `skills/automate-loop/*.md` and `commands/automate.md`, and resolves `rationale:` docs.
> - `test-automate-loop-split.sh` checks the split index, Step 0's file list and every tracked `automate-loop/SKILL.md §…` citation.
> - `check-doc-currency.sh` scans `loomwright/docs/`, `skills/`, `commands/` and `SKILLS_INDEX.md`.
> - `test-citation-drift.sh` checks every committed `file:N` citation.
> - `check-token-budget.sh` covers the `.skills["automate-loop"]` and `.commands.automate` ceilings. They only shrink here.
> - `check-vendor-coupling.sh` enforces the per-file allowances.
> - `test-automate-next-step.sh` `leg_surface` checks the merge-grep surface list.

## Touched-file invariants

> Grounded at base `ee3d7ea3bb069c50a07c3b37222c52c88202263b`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/skills/automate-loop/SKILL.md`** — keep: it stays the split INDEX. Each moved run of sections sits between `<!-- split:begin <file> -->` and `<!-- split:end <file> -->`. Each split-file heading gets exactly one `See [<file>](<file>).` line, and index-only prose sits in `<!-- index-only:begin -->` blocks. The `## Cited sub-section anchors` table keeps a row for every quoted anchor a tracked citation uses. The `## §N` headings `§1`–`§14` keep their numbers (citations resolve `§N` to an index heading). `## Coordinator loop — run next-step; do the one instruction; report the result` stays in the default read set. Frontmatter `version:` / `lastUpdated:` may take a minor bump, mirrored in `skills/SKILLS_INDEX.md`'s `| Automate Loop | \`automate-loop/\` |` row in the same change. Only Subtask 1 bumps it; Subtasks 2–4 leave the frontmatter alone. pinned by: `test-automate-loop-split.sh` (checks B, C, D, F, G, H); `test-loop-inventory.sh`; the readers that read it through `fixtures/automate-loop-split/assemble.sh` (`test-automate-helpers.sh`, `test-automate-trail.sh`, `test-non-interactive-gates-seam.sh`, `test-run-lock.sh`, `test-session-resume.sh`, …).
- **`loomwright/commands/automate.md`** — keep: Step 0's read block (`Read ${CLAUDE_PLUGIN_ROOT}/skills/automate-loop/SKILL.md   # the AUTHORITY`) and its per-file **Always** / **Only when** list naming every skill split file in documented order. Each item-25 trigger line stays byte-identical, and a new split file gets its own **Only when** line. Keep the `--auto-merge` row's `PARK: ctx_carries_gate_owned_key` text and the `**Invariant (durable):**` never-merge line. The vendor-coupling allowance `"loomwright/commands/automate.md": 8` may only go down. pinned by: `test-automate-loop-split.sh` check F; `test-non-interactive-gates-seam.sh`; `test-automate-trail.sh`; `test-automate-dismissed.sh`; `test-loop-inventory.sh`.
- **`loomwright/skills/automate-loop/invariants.md`** — keep: `## §11 — Invariant preservation` and every invariant row it carries (all `global`); its index-only block naming the post-split grep hit paths. pinned by: `test-automate-loop-split.sh` (index-only gating leg), `test-loop-inventory.sh`.
- **`loomwright/skills/automate-loop/per-item-loop.md`** — keep: the positive-form `gh pr merge --squash` mention (in the `**Honest limits.**` bullet); every needle `test-automate-dismissed.sh` reads from `PIL` and from the assembled skill (`2. **RUN — run next-step**`, the dismissed-findings subsection heading); the `### Rate-limit park (end of RUN, before DRAIN)` heading (the fixture leg `PIL=` in `test-loop-inventory.sh` anchors on it). pinned by: `test-automate-dismissed.sh`, `test-automate-next-step.sh` (`SURFACE_BASE`), `test-loop-inventory.sh`, `fixtures/automate-golden/**` question-gate fixtures.
- **`loomwright/skills/automate-loop/modes-and-merge-gate.md`** — keep: it still holds `## §10` (`test-rules-gate-seams.sh`: `AL="loomwright/skills/automate-loop/modes-and-merge-gate.md"`, pin 6's needles are §10 text); the line `On all seven holding: \`gh pr merge --squash --match-head-commit <live head> <url>\``; the conditions 6 and 7 no-override wording. pinned by: `test-rules-gate-seams.sh`, `test-automate-next-step.sh` (`SURFACE_BASE`), `test-automate-loop-split.sh` check H.
- **`loomwright/skills/automate-loop/lanes.md`** — keep: its file name and the headings that `automate-next-step.sh` and `automate-lanes.sh` cite (both name `skills/automate-loop/lanes.md`); the `Single-lane mode` section the command's `--parallel` row cites. pinned by: `test-automate-next-step.sh`, `fixtures/automate-golden/**` (`08b-single-lane-sequential.md`), `test-loop-inventory.sh`.
- **`loomwright/skills/automate-loop/resume.md`** — keep: its headings `## §4 — RESUME = glob + reconcile (run-file is BELIEF; git/gh is TRUTH)` and `## §5 — Skipped / abandoned items` (the SKILL.md split block `<!-- split:begin resume.md -->` carries one `See [resume.md](resume.md).` entry for each, and `§4` / `§5` citations resolve to them); its Step 0 trigger line in `commands/automate.md` (`- \`resume.md\`, **Only when** a \`next-step --resume\` call exits non-zero`) byte-identical; every needle the assembled-skill readers take from it. pinned by: `test-automate-loop-split.sh` (checks B, C, F, G); `test-session-resume.sh` and `test-run-lock.sh` through `fixtures/automate-loop-split/assemble.sh`; `test-loop-inventory.sh`.
- **`loomwright/skills/automate-loop/intake.md`** — keep: the lane bullet's Progress line `skipped AUT-QUEUE:` text byte for byte (`test-automate-helpers.d/16-queue-gates.sh` reads it through `QG_INTAKE="$HERE/../skills/automate-loop/intake.md"`); the `queue-confirm` ask-or-skip bullet (`**Ask or skip — \`queue-confirm\``) and gate id `AUT-QUEUE`; the `## §2` heading and its five `###` source/lint/limit headings (one SKILL.md entry each). pinned by: `test-automate-helpers.d/16-queue-gates.sh` (via `test-automate-helpers.sh`), the `automate-golden` question-gate fixtures, `test-automate-loop-split.sh`, `test-loop-inventory.sh`.
- **`loomwright/skills/automate-loop/command-lanes.md`** — keep: it stays the split target of `commands/automate.md` (the command body's `<!-- split:begin ../skills/automate-loop/command-lanes.md -->` block, never a new file under `commands/`); its heading `### Lanes (\`--parallel N\`) and launch authority`; its Step 0 line `- \`command-lanes.md\`, **Only when** the lanes trigger of the row above holds`. pinned by: `test-automate-loop-split.sh` (checks B, C, F; its header maps `commands/automate.md -> skills/automate-loop/command-lanes.md`), `test-loop-inventory.sh`.
- **`loomwright/skills/automate-loop/branch-mode.md`** — keep: `## §13 — Branch mode (opt-in, default OFF)` (cited as `§13` by `commands/automate.md`); the `**\`meta-entry\` FIRST, on every entry.**` rule (the Step 0 trigger reads `meta-entry` output); its Step 0 line `- \`branch-mode.md\`, **Only when** \`meta-entry\` prints anything but \`meta-entry: off\``. pinned by: `test-automate-loop-split.sh`, `test-loop-inventory.sh`, the `automate-golden` branch-mode fixtures.
- **Repointed `loomwright/scripts/test-*.sh` (only if a needle moves to a new split file)** — keep: the needle byte-identical; the test's legs, fail messages and assertions unchanged; only the path (or the file list) a needle is read from changes, and a test that reads the assembled skill keeps reading it through `fixtures/automate-loop-split/assemble.sh` (check H forbids a raw read of the index). pinned by: the test itself (re-run after the repoint) and `test-automate-loop-split.sh` check H.
- **`loomwright/docs/loop-inventory/automate-loop.md`** — keep:
  - the shape: `## Sources`, `## Inventory`, `## Gap list (ordered by risk)`, `## Counts` in that order; the nine-column header `| id | file | anchor | condition | action | kind | home | implemented by | test |`; ids `AL-NNN` never reused (new rows take new ids);
  - `## Sources` equal to the `automate-loop)` arm (a new split file is added there too);
  - at least one positive-form `gh pr merge --squash` row (it is in `SURFACE_BASE`);
  - the vendor-coupling allowance `"loomwright/docs/loop-inventory/automate-loop.md": 12`, which may only go down.

  pinned by: `test-loop-inventory.sh`, `test-automate-next-step.sh`.
- **`loomwright/docs/vendor-coupling-manifest.json`** — keep: valid JSON; one allowance + one note per counted file; the note shape of the parallel-automate/22 entries (`moved by parallel-automate/22 split — no reference added`). pinned by: `scripts/check-vendor-coupling.sh`.

## Pin mutations

Pins are not added or changed by design (AC6). A pin changes only when its needle moves to a new split file and the test is repointed. The worker that repoints a test writes the concrete literal into the evidence file and runs the row on a scratch copy, after checking the mutant is non-empty and differs from the original.

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| each repointed `loomwright/scripts/test-*.sh` needle (Subtasks 1–4) | delete the line holding that needle's governed text in the NEW split file ⇒ the test goes red |
| `loomwright/scripts/test-loop-inventory.sh` — a `global` row's live anchor | delete the anchored line in its source file (scratch copy) ⇒ `FAIL <id>: anchor not found` |
| `loomwright/scripts/test-automate-loop-split.sh` — check F (Step 0 names every split file) | delete the new split file's **Only when** line in `commands/automate.md` (scratch copy) ⇒ check F fails |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Default read set diet: `SKILL.md` (Part C — driver-owned sections out of the always-read index), `invariants.md`, `commands/automate.md`; create the rationale doc and the evidence skeleton (baseline measured first) | AC1 (rows of these 3 files), AC4, AC5, AC6, AC7, AC8, AC9 | ~6 modify, 2–3 create | — | LAUNCHABLE |
| 2 | `per-item-loop.md` + `resume.md` diet: delete prose of rows the driver's `case` arms own (pinned needles kept), stories to rationale | AC1 (their rows), AC5, AC6, AC7, AC8, AC9 | ~5 modify | — | BLOCKED (by #1) |
| 3 | `lanes.md` + `command-lanes.md` + `branch-mode.md` diet | AC1 (their rows), AC5, AC6, AC7, AC8, AC9 | ~6 modify | — | BLOCKED (by #2) |
| 4 | `modes-and-merge-gate.md` + `intake.md` diet | AC1 (their rows), AC5, AC6, AC7, AC8, AC9 | ~5 modify | — | BLOCKED (by #3) |
| 5 | Finish the evidence file, changelog fragment, full validation | AC2, AC3, AC10, AC11 | 1 modify, 1 create | — | BLOCKED (by #4) |

**Evidence file:** Subtask 1 creates `docs/evidence/as16-diet-automate-loop.md` with the headings Baseline, Read set (Step 0), Behaviour questions, Proposed hooks, Pin mutations and Results. It writes the baseline measured at `ee3d7ea` before any edit. Subtasks 1–4 append their behaviour questions, filed proposals, pin-mutation records and running `wc -c` totals. Subtask 5 finishes it with the final measurements and gate results.

**Per-subtask work rule (Subtasks 1–4):** for each inventory row of the subtask's files:
- `story` ⇒ move the text to a `###` section of `docs/rationale/automate-loop.md`, under the `## <group>` heading the subtask's `provides` names. Subtask 1 creates the doc with its `# Rationale — automate-loop` title, and each of Subtasks 2–4 adds its own `##` heading verbatim. Set home `rationale:docs/rationale/automate-loop.md#<slug>`. A story paragraph that contains a rule is split first, and the rule keeps or gets its own row. A pinned needle never moves to the rationale doc.
- `rule` or `deterministic` homed `script:<file> <sub>` / `hook:<leaf>`, where that arm or leaf exists ⇒ delete the prose. Keep one line only where the model would otherwise attempt the blocked action, or where a pinned needle sits in it.
- applies at one step ⇒ `step-scoped`, moved next to that step.
- applies everywhere ⇒ `global`, rewritten short. A `global` row's anchor must stay a live substring of its file, so update the `q:` anchor in the same change.

Then:
- Keep the split index in step: a heading removed from a split file loses its SKILL.md entry, unless a tracked citation uses it. In that case the heading stays with a one-line pointer.
- Recompute `## Counts` and the gap list from the table, and add a row for every new heading.
- Run `test-loop-inventory.sh`, `test-automate-loop-split.sh`, `test-automate-next-step.sh` and every test that reads the subtask's files after every move.

Moving text never changes a condition or an action.

**Subtask 5 scope:** it measures and records; it does not edit runtime prose. A gate that fails at Subtask 5 is recorded in the evidence file's Results with its output and handed to Phase 4.5 heal, where the fix task can edit the failing file. Subtask 5 does not widen its own lanes.

### Subtask Contracts

```yaml
# Subtask 1 — default read set diet + rationale doc + evidence skeleton (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/docs/rationale/automate-loop.md"}
  - {kind: "symbol", path: "loomwright/docs/rationale/automate-loop.md", name: "# Rationale — automate-loop"}
  - {kind: "file", path: "docs/evidence/as16-diet-automate-loop.md"}
requires: []
lanes:
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/automate-loop/invariants.md"
  - "loomwright/skills/automate-loop/*.md"
  - "loomwright/commands/automate.md"
  - "loomwright/docs/rationale/automate-loop.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/scripts/test-*.sh"
  - ".supervisor/requirements/proposed/*.md"
  - "docs/evidence/as16-diet-automate-loop.md"
external_requires: []

# Subtask 2 — per-item-loop.md + resume.md diet (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/skills/automate-loop/per-item-loop.md"}
  - {kind: "symbol", path: "loomwright/docs/rationale/automate-loop.md", name: "## per-item-loop and resume"}
requires:
  - {from: "1", kind: "file", path: "loomwright/docs/rationale/automate-loop.md"}
lanes:
  - "loomwright/skills/automate-loop/per-item-loop.md"
  - "loomwright/skills/automate-loop/resume.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/docs/rationale/automate-loop.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/scripts/test-*.sh"
  - ".supervisor/requirements/proposed/*.md"
  - "docs/evidence/as16-diet-automate-loop.md"
external_requires: []

# Subtask 3 — lanes.md + command-lanes.md + branch-mode.md diet (BLOCKED by #2)
provides:
  - {kind: "file", path: "loomwright/skills/automate-loop/lanes.md"}
  - {kind: "symbol", path: "loomwright/docs/rationale/automate-loop.md", name: "## lanes and branch mode"}
requires:
  - {from: "2", kind: "symbol", path: "loomwright/docs/rationale/automate-loop.md", name: "## per-item-loop and resume"}
lanes:
  - "loomwright/skills/automate-loop/lanes.md"
  - "loomwright/skills/automate-loop/command-lanes.md"
  - "loomwright/skills/automate-loop/branch-mode.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/commands/automate.md"
  - "loomwright/docs/rationale/automate-loop.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/scripts/test-*.sh"
  - ".supervisor/requirements/proposed/*.md"
  - "docs/evidence/as16-diet-automate-loop.md"
external_requires: []

# Subtask 4 — modes-and-merge-gate.md + intake.md diet (BLOCKED by #3)
provides:
  - {kind: "file", path: "loomwright/skills/automate-loop/modes-and-merge-gate.md"}
  - {kind: "symbol", path: "loomwright/docs/rationale/automate-loop.md", name: "## merge gate and intake"}
requires:
  - {from: "3", kind: "symbol", path: "loomwright/docs/rationale/automate-loop.md", name: "## lanes and branch mode"}
lanes:
  - "loomwright/skills/automate-loop/modes-and-merge-gate.md"
  - "loomwright/skills/automate-loop/intake.md"
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/docs/rationale/automate-loop.md"
  - "loomwright/docs/loop-inventory/automate-loop.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/scripts/test-*.sh"
  - ".supervisor/requirements/proposed/*.md"
  - "docs/evidence/as16-diet-automate-loop.md"
external_requires: []

# Subtask 5 — evidence + changelog fragment + validation (BLOCKED by #4)
provides:
  - {kind: "file", path: "docs/evidence/as16-diet-automate-loop.md"}
  - {kind: "file", path: "changelog.d/as16-diet-automate-loop.md"}
requires:
  - {from: "4", kind: "symbol", path: "loomwright/docs/rationale/automate-loop.md", name: "## merge gate and intake"}
lanes:
  - "docs/evidence/as16-diet-automate-loop.md"
  - "changelog.d/as16-diet-automate-loop.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3 ──→ Subtask 4 ──→ Subtask 5
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | SKILL.md (split-block entries), inventory, rationale doc, vendor manifest, evidence file | YES |
| Subtask 2 | Subtask 3 | SKILL.md, inventory, rationale doc, vendor manifest, evidence file | YES |
| Subtask 3 | Subtask 4 | SKILL.md, inventory, rationale doc, vendor manifest, evidence file | YES |
| Subtask 4 | Subtask 5 | `docs/evidence/as16-diet-automate-loop.md` | YES (measures the finished tree) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after #1)
- **Batch 3:** Subtask 3 (after #2)
- **Batch 4:** Subtask 4 (after #3)
- **Batch 5:** Subtask 5 (after #4)
- **Recommended workers:** 1
- **Estimated batches:** 5

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | — (precedent: `loomwright/docs/rationale/supervisor.md` intro + layout, `docs/evidence/as15-diet-supervisor.md`, `docs/evidence/as25-automate-load-by-mode.md` for the Step 0 **Only when** form) |
| 2 | — (precedent: automate-speed/15 subtask rule; `test-automate-loop-split.sh` header for the index contract) |
| 3 | — (same as 2) |
| 4 | — (same as 2) |
| 5 | — (precedent: `docs/evidence/as15-diet-supervisor.md` Results layout, incl. "Not run — Validation 3") |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope vs Supervisor Capability: ~276 KB / 584 rows exceeds one worker's context (Feasibility (Phase 2.5)) | HIGH | `context-bound` split into 5 serialized subtasks, one file group each; each worker reads only its files and their inventory rows |
| The 30% target is not reachable without touching pinned needles; the supervisor diet stopped at −26.0% and escalated (Feasibility (Phase 2.5)) | HIGH | Measure `wc -c` after each subtask. The biggest honest sources are the prose of the ~230 `script:`-homed rows in per-item-loop.md, resume.md and modes-and-merge-gate.md (the driver runs those steps), stories, and duplicated restatements between SKILL.md and the command body. If still short, AC2 records the shortfall and the blocking pins rather than rewording them |
| Deleting a section heading breaks a tracked `automate-loop/SKILL.md §…` citation or a split-index entry (check B/G) | HIGH | Remove the SKILL.md entry in the same edit; keep a one-line pointer (or an anchors-table row) for any heading a tracked citation uses; run `test-automate-loop-split.sh` after every move |
| The rationale doc or a deletion changes the positive merge-grep surface list pinned in `test-automate-next-step.sh` `SURFACE_BASE` | HIGH | AC6: quote merge text in the rationale doc only in negated form or not at all; keep the per-item-loop.md / modes-and-merge-gate.md / inventory mentions; run the grep after each subtask |
| A rule silently dropped while deleting "script-owned" prose | HIGH | Delete only when the row's `script:`/`hook:` home names an arm/leaf that exists at base (`test-loop-inventory.sh` checks the arm); keep one line where the model would otherwise attempt the action; mutation control (AC11) |
| Prior churn on SKILL.md (35), commands/automate.md (24), per-item-loop.md (10), lanes.md (6), inventory (5); recurring classes `self_heal_churn`, `drain_churn` (Prior churn (postmortem ledger)) | MEDIUM | Cross-reference/verbatim drift is the recurring class: after each move grep the old wording repo-wide and update or point every restating copy in the same change (house rule); re-run the pinning tests before hand-back |
| Concurrent lanes in this wave edit `vendor-coupling-manifest.json`, `SKILLS_INDEX.md`, the inventory docs | MEDIUM | Keep edits to shared files line-local (one manifest key pair per file, one index row) so the wave merge stays a clean 3-way merge |
| Behaviour change sneaks in while rewriting a rule short | MEDIUM | Non-goal: same condition, same action; any behaviour question goes to the evidence file, not a fix |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 5
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-20-as16-diet-automate-loop.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-20T12:02:06Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/636
- **Branch:** feature/as16-diet-automate-loop
- **Files changed:** 18
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 0
- **Heal reason:** needs_human
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** automate-loop prompt diet across 5 serialized subtasks — measured set 275,768 → 149,318 bytes (−45.9%), default read set 83,400 → 47,094, history refs 28 → 1, every story row homed in docs/rationale/automate-loop.md, all gates green except two base-identical failures. Code Reviewer NEEDS_HUMAN: AC4 partly met — commands/automate.md's always-read "Short overview" still maps driver-owned steps; moving it needs a second new split file the brief capped at one (owner decides: accept as pointer, or lift the cap).

## Not verified
- **live /automate run following the new Step 0 read list (AC4 transcript, Validation 3)** — no live run made; owner pre-merge step (subtask 1)
- **a NEW-run intake reading run-file.md before writing its first run file** — needs a multi-step interactive /automate run (subtask 1)
- **live /automate run reading per-item-loop.md or resume.md after a driver failure** — no live run made (subtask 2)
- **test-automate-lanes failing-set identity vs base** — counts only at subtask 2; later proven by FAIL-list diff in subtask 5 (subtask 2)
- **live /automate --parallel coordinator run following the dieted lanes.md** — no live lanes run (subtask 3)
- **live /automate --auto-merge gate run** — no real PR went through gate-eval (subtask 4)
- **live /automate intake (prompt/folder/backlog + AUT-QUEUE ask)** — helper tests + scratch repro only (subtask 4)
- **AC4 transcript assertion: a default /automate run never Reads a driver-owned split file** — needs a live run (Validation 3) (subtask 5)
