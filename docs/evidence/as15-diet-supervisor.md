# as15 — the Supervisor carries rules, not stories: evidence

Requirement: `.supervisor/requirements/automate-speed/15-diet-supervisor.md`. Base commit: `3a03dfa66d7de22ff93b0327affa60aa752948d2`. Subtasks 1–3 append to this file as they land; Subtask 4 finishes it (final measurements, gate results). Every number below was measured from the repo root unless a `cd` is shown.

## Baseline

Re-measured at the base commit before any delta was reported. The four group files were copied out of the base commit into a scratch dir:

```bash
for f in agents/supervisor.md commands/supervisor.md skills/self-heal-advisory/SKILL.md skills/async-orchestration/SKILL.md; do
  mkdir -p "$SCRATCH/loomwright/$(dirname "$f")"
  git show 3a03dfa:loomwright/$f > "$SCRATCH/loomwright/$f"
done
cd "$SCRATCH/loomwright" && wc -c agents/supervisor.md commands/supervisor.md skills/self-heal-advisory/SKILL.md skills/async-orchestration/SKILL.md
```

```
  105710 agents/supervisor.md
   60305 commands/supervisor.md
  176146 skills/self-heal-advisory/SKILL.md
   49133 skills/async-orchestration/SKILL.md
  391294 total
```

History references (the requirement's regex, per file, same scratch copy):

```bash
RX='#[0-9]{2,4}\b|queue/[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2}|item [0-9]+'
for f in agents/supervisor.md commands/supervisor.md skills/self-heal-advisory/SKILL.md skills/async-orchestration/SKILL.md; do
  printf '%s %s\n' "$f" "$(grep -oE "$RX" "$f" | wc -l | tr -d ' ')"
done
```

```
agents/supervisor.md 3
commands/supervisor.md 5
skills/self-heal-advisory/SKILL.md 19
skills/async-orchestration/SKILL.md 4
```

31 in total (3 / 5 / 19 / 4), matching the requirement.

### Subtask 1 — the Supervisor pair

After subtask 1 (`cd loomwright && wc -c agents/supervisor.md commands/supervisor.md`):

```
   80196 agents/supervisor.md
   42896 commands/supervisor.md
  123092 total
```

The pair went from 166,015 to 123,092 bytes (−42,923, −25.9%): `agents/supervisor.md` −24.1%, `commands/supervisor.md` −28.9%. History references in the pair: 8 → 1 (`agents/supervisor.md` keeps `#512`, part of the Phase 4 gate line `test-release-refold.sh` pins byte-for-byte; `commands/supervisor.md` 0).

What moved to `docs/rationale/supervisor.md`: the model warning, Inputs/Outputs, the architecture diagrams, the Preloaded Skill Routing (4f) audit (the section keeps its heading and a short rule naming which skill is Read at which phase), the Phase 4 / Phase 4.5 / Resume / Spawn Contracts / Session Logging 4f parentheticals, the Input/Output Format and Usage examples, the example session, dry-run output, plan-first workflow, workflow comparison, tips, related commands, troubleshooting, see-also, the tool-call estimate table, and the "why" behind the lane-recording, adjudication, run-lock, branch-ancestry, drain-observability and resume-stale rules. Restated text inside each file was collapsed (Sequential step 2 now points at Single-Agent step 2's readers; the tool-budget notes became one paragraph). The two resume refusals moved from Troubleshooting into §"Checkpoints and Resume", with their conditions and remedies unchanged.

The completion-tail guard in `agents/supervisor.md` keeps its conditions and actions byte-identical; only its closing "This guard exists so that…" sentence (inventory row SV-174, kind `story`) moved to the rationale doc.

### Subtask 2 — async-orchestration

After subtask 2 (`cd loomwright && wc -c skills/async-orchestration/SKILL.md skills/async-orchestration/finalize.md`):

```
   24137 skills/async-orchestration/SKILL.md
    8168 skills/async-orchestration/finalize.md
   32305 total
```

async-orchestration went from 49,133 to 32,305 bytes all-modes (−16,828, −34.2%). The read sets it serves shrink further, because `finalize.md` loads at Phase 4 only: Phase 2 PLAN and every Execute Manager spawn (its one preloaded skill) now read `SKILL.md` alone, 24,137 bytes (−50.9%). `check-token-budget.sh`: `.agents["execute-manager"]` 31,155 / 42,568 proxy tokens (computed before value ≈ 37,404: the preload shrank by 24,996 bytes / 4), `.skills["async-orchestration"]` 8,076 / 15,760 (2 `.md` files).

Group running total after subtask 2 (`wc -c` on the four sources + `finalize.md`): 80,151 + 43,001 + 176,146 + 24,137 + 8,168 = 331,603 bytes (base 391,294; −15.3% so far; the AC2 target ≤ 273,905 needs subtask 3's self-heal-advisory cut). `agents/supervisor.md` and `commands/supervisor.md` changed by −45 / +105 bytes in this subtask (the Phase 2 / Phase 4 Read lines and the routing sentence).

History references in async-orchestration (same regex): 4 → 3 across the two files — `SKILL.md` 1 (the frontmatter `lastUpdated` date), `finalize.md` 2 (`#512` in the step 5.5 heading line and `#511` in the `## Evidence` explainer — both inside lines `test-release-refold.sh` / `test-pr-body-evidence-seam.sh` pin byte-for-byte). `#431` moved to the rationale doc.

What moved to `docs/rationale/supervisor.md` (new sections §"Async orchestration — why the rules read as they do" and §"Phase 4 FINALIZE — why the steps read as they do"): the Part 2 provenance block, the file-overlap and worktree-layout examples, the Execute context-budget tables, the "why this gate exists" paragraph, the adjudication options' full cost notes, the `provides:`/`lanes:` paste and house-rules "why" comments, and the history behind salvage-before-remove, the cleanup audit, the release re-fold placement, stacked base branches, the FINALIZE scope reduction and the PR body sections. Restated rules collapsed inside the file: the "no per-subtask reviewer" rule (stated five times) is one Quick Rules bullet plus short pointers; the no-brief fallback (stated three times in spawn prompts) is one rule under "Pointers, not payloads"; Part 1's Phase 4 merge/cleanup commands, the Merge Conflict report and the Part 2 worktree-lifecycle phase sequence restated FINALIZE steps 2–4 and are now pointers. The stale illustrative `WORKER_RESULT` block (an older field set) was dropped in favour of the `docs/RESULT_SCHEMAS.md` pointer. Routing: `agents/supervisor.md` Phase 2 Reads `SKILL.md` only ("Phase 2 does not need `finalize.md`"); Phase 4 Reads `finalize.md` + `skills/commit/SKILL.md`; `commands/supervisor.md` Phase 4 names `finalize.md`. `scripts/supervisor-next-step.sh` and `scripts/fixtures/supervisor-golden/**` are unchanged (`git diff --stat 3a03dfa -- …` prints nothing).

`docs/vendor-coupling-manifest.json`: `finalize.md` carries no counted token (the gate does not list it), so it gets no allowance; `SKILL.md` measured 18 (base 22: two task-output polls, one spawn-type key and one ask-tool name deleted with restated text, none moved) and its allowance was lowered 23 → 18 with a note.

## Behaviour questions

Found while moving text; listed here and not fixed (AC9).

1. **Does the inline path load `agents/supervisor.md`?** `commands/supervisor.md` §"Inline-path canonical state writes" says the inline `/supervisor` and `/autonomous` paths never load `agents/supervisor.md`. The same file's §"What This Does" sends the inline main thread to `agents/supervisor.md` for Phase 1 actions 0–3 and the Phase 4 gate list, and its execution contract says the completion-tail guard lives verbatim only there. If the inline path really never loads the agent file, the inline path has no copy of the guard text or the Phase 1 task-selection actions.
2. **`--max-tokens` on the Parallel Path.** The `--max-tokens` parameter row in `commands/supervisor.md` says each Phase 3 poll-loop iteration sums the session ledger and parks before spawning another worker/reviewer round. `agents/supervisor.md` (Sequential Path scope note) says only the Sequential Path's own loop checks the ledger and the Parallel Path's poll loop does not. Neither `agents/execute-manager.md`, `skills/async-orchestration/SKILL.md` nor `scripts/supervisor-next-step.sh` mentions `read-token-ledger.sh` or `MAX_TOKENS`, so the agent prompt matches the code and the command row overstates. The same row also describes the Phase 0 run-lock acquire, which runs whether or not `--max-tokens` is set.
3. **Phase 4.5 NEEDS_HUMAN / max iterations.** `commands/supervisor.md` §"Gate Decisions" maps a Phase 4.5 `NEEDS_HUMAN` to "Checkpoint, pause, exit with resume command" and `FAIL` at max iterations to "Checkpoint, escalate to human". `agents/supervisor.md` Phase 4.5 exit conditions map both to `heal_decision == ESCALATED` → `completed_with_escalation`, findings posted to the PR, job → `done/` (a normal exit, not a checkpoint), and its own Error Handling table says the exhausted loop marks ESCALATED and exits normally.
4. **Phase 4 no longer re-reads `SKILL.md`.** Before, the Phase 4 Read of `skills/async-orchestration/SKILL.md` was a compaction refresh of the whole file, Part 2 FINALIZE procedure and §"Subagent Spawn Contracts" together. Phase 4 now Reads `finalize.md` (the procedure) and not `SKILL.md`. The only spawns Phase 4 makes on the driver path are Context-Keeper ops and the `finalize-merge` / `finalize-publish` instructions, whose JSON carries the agent and payload itself; but a delegated `--legacy` run whose context compacted during a long Phase 3 would no longer get the spawn-contract shapes refreshed at Phase 4. Owner to confirm the refresh was only ever for the FINALIZE procedure (the rationale doc's §"Async-orchestration routing" says so).
5. **Two out-of-lane citations still point at `SKILL.md` for text now in `finalize.md`.** `loomwright/docs/supervisor-legacy-phases.md` (§"Phase 4 (FINALIZE)" protocol-authority line, the `--legacy` path) names `skills/async-orchestration/SKILL.md` **Part 2 — Supervisor FINALIZE Protocol** — it still resolves, one hop later, through the `# Part 2` stub. `loomwright/scripts/validate-execute-result.py` (a comment) cites `skills/async-orchestration/SKILL.md` §"Cleanup worktrees", which is now `finalize.md` step 4. Neither file is in subtask 2's lanes; not edited.
6. **The adjudication text dropped its ask-tool mention.** `SKILL.md` §"Scope Expansion Adjudication" said the Supervisor presents the four options "to the user via" the host's ask tool; the same section's closing sentence already says the Supervisor presents them, and `agents/supervisor.md` §"Adjudication Handling" (driver `ask`, Can't-ask rule ⇒ `adjudication_required_non_interactive`) is where that happens. The restatement was removed, not the rule; listed because an unconditional "via the ask tool" read as if the Execute Manager-side text promised an ask even under `--non-interactive`.

## Proposed hooks

None from subtask 1. No rule in the pair needed a new hook to leave the prompt: every `rule` row was either kept short in place (`global`, anchor-checked), sat at the one step it governs (`step-scoped`), or was already enforced by an existing script (SV-058 → `script:build-state.sh`, its one line kept so the model does not write the `## Session` block itself).

None from subtask 2 either: every async-orchestration `rule` row is `global` (anchor-checked), `step-scoped`, or homed on the script that already enforces it (`supervisor-next-step.sh`, `verify-provides.sh`, `validate-worker-result.py`, `worktree-audit.sh report`).

## Pin mutations

Subtask 1 repointed no test: no needle any test reads moved out of the pair (every pinned line stayed in place, byte-identical), and no committed pinned `file:N` citation points into the pair: `grep -rnE 'agents/supervisor\.md:[0-9]|commands/supervisor\.md:[0-9]' loomwright/scripts scripts loomwright/docs/rationale` prints only two historical fixture records (`scripts/fixtures/harvest-ledger/results.jsonl`, `scripts/fixtures/corpus-briefs/done/2026-07-23-curation-anti-rot.md`) — frozen data quoting old line numbers, not citations `test-citation-drift.sh` checks (it stays green).

`test-loop-inventory.sh` mutation controls on a scratch copy (`cp -R loomwright scripts "$SCRATCH/mut/"`; the unmutated scratch copy is green first: `loop-inventory: OK — 2226 rows across 4 groups`):

| Row (home) | Mutation | Mutant checked | Result |
|---|---|---|---|
| SV-746 (`global`, `agents/supervisor.md`) | `grep -v 'The frontmatter \`skills:\` list is empty: no protocol skill is preloaded.'` | non-empty, 649 → 648 lines, differs (`cmp`) | exit 1, `FAIL SV-746: anchor not found in agents/supervisor.md` |
| SV-340 (`global`, `commands/supervisor.md`) | `grep -v 'Recover: \*\*do NOT delete the state file\*\*'` (one line, which also carries the SV-339 and SV-341 anchors) | differs (`cmp`) | exit 1, `FAIL SV-339`, `FAIL SV-340`, `FAIL SV-341: anchor not found in commands/supervisor.md` |

### Subtask 2 — repointed pins

Tests repointed (needles byte-identical; only the file a needle is read from changed): `test-check-children-settled.sh` (new `ASYNC_FIN` for the Point 5 needles; `ASYNC` still reads §"Spawning a Worker" from `SKILL.md`), `test-not-verified-transport-seam.sh` (new `ASYNCFIN` for the PR Body Template and its explainer; the Sequential/Single-Agent cross-reference stays on `SKILL.md`), `test-pr-body-evidence-seam.sh` (`AO` → `finalize.md`), `test-release-refold.sh` (`AO` → `finalize.md`, its in-suite drop-the-line mutant follows), `test-worktree-salvage.sh` (new `ASYNC_FINALIZE`: the salvage-above-remove loop now covers `SKILL.md`, `finalize.md` and workflow-management; the FINALIZE step-4 order check reads `finalize.md`). `test-check-contract-parity.sh` gained the `finalize.md` fixture file and one red leg. Citations: the three pinned citations in `reconcile-resume-state.sh` were re-derived from `async-orchestration/SKILL.md` lines 536 (twice) and 543–545 to `async-orchestration/finalize.md` lines 15 (twice) and 21–23, `[pins: …]` byte-identical; the bare SKILL.md lines 546–548 comment citation in `test-reconcile-resume-state.sh` is now the descriptive anchor `finalize.md §"Phase 4 FINALIZE procedure" step 3, the merge -m lines`.

Controls, each on a scratch copy (`cp -R loomwright scripts "$SCRATCH/pm-<test>/"`, `git init` + `git add -A` there); the deleted line is in `finalize.md`, never the `SKILL.md` stub; each mutant checked non-empty and `cmp`-different first (100 → 99 lines); the unmutated scratch run is the baseline the new FAIL lines are diffed against:

| Pin | Mutation (`grep -vF` on `finalize.md`) | Unmutated scratch | Mutant |
|---|---|---|---|
| `test-check-children-settled.sh` Point 5 needles | the line starting `1. **Pre-merge safety gate**` | rc 0 | rc 1: `async-orchestration SKILL.md missing the script cite or children_unsettled`, `… does not mention rejected_stop_ids` |
| `test-not-verified-transport-seam.sh` (e) explainer | the `## Not verified` explainer line (needle `**` + backtick + `## Not verified` + backtick + ` section`) | rc 0 | rc 1: `(e) PR-body explainer does not name the aggregation source`, `… does not state the omitted-entirely rule` |
| `test-pr-body-evidence-seam.sh` `EVR` | the `## Evidence` explainer line (same needle shape) | rc 1 (PART 5 only: the scratch copy has no root `.gitignore`, so `docs/evidence/*.log` is not ignored — environmental, not this pin) | rc 1, plus `FINALIZE ## Evidence rule` |
| `test-release-refold.sh` `seam_finalize` | the `5.5. **Release re-fold` line | rc 0 | rc 1: `seam: FINALIZE step 5.5 runs it after step 5's commits, before write-marker and step 6's push` |
| `test-worktree-salvage.sh` AC-11 | the `worktree-salvage.sh ../{project}-{subtask_id}` line | rc 0 | rc 1: `AC-11 seams (… prose_ok=0 missing=' async-orchestration:41' finalize_salvage= finalize_remove=41)` |
| `scripts/check-contract-parity.sh` new ENUMS row | `sed 's/SUPERVISOR_RESULT.status: failed/SUPERVISOR_RESULT.status: refused/'` on `finalize.md`, gate run with `--root "$SCRATCH/mut"` | rc 0 | rc 1: `PARITY [enum-literal] skills/async-orchestration/finalize.md: 'status: refused' is outside the allowed set` |
| `test-loop-inventory.sh` `global` row | `grep -vF 'Read by the Supervisor at Phase 4 FINALIZE entry only.'` (that line also carries SV-678's anchor) | `loop-inventory: OK — 2238 rows across 4 groups` | rc 1: `FAIL SV-678` and `FAIL SV-750: anchor not found in skills/async-orchestration/finalize.md` |
| `test-loop-inventory.sh` group sources | drop `skills/async-orchestration/finalize.md` from the `supervisor)` arm of a scratch copy of the test | rc 0 | rc 1: `## Sources lists skills/async-orchestration/finalize.md, which is not a source of the group`, then one `file '…finalize.md' is not a source of the supervisor group` per row (53 FAIL lines; `finalize.md` has no `###`/`####` heading, so this — not heading coverage — is the line that names it) |

## Results

Subtask 1, after the change (each script's own summary line):

| Gate / test | Result |
|---|---|
| `loomwright/scripts/test-loop-inventory.sh` | 43/43 passed (`loop-inventory: OK — 2226 rows across 4 groups`) |
| `scripts/check-doc-currency.sh` | OK |
| `loomwright/scripts/test-citation-drift.sh` | 26 passed, 0 failed |
| `scripts/check-token-budget.sh` | OK, 0 breaches (`.agents.supervisor` 20049 / 30378, `.commands.supervisor` 10724 / 16002 proxy tokens) |
| `scripts/check-contract-parity.sh` | OK |
| `scripts/check-vendor-coupling.sh` | OK, 0 breaches (`agents/supervisor.md` 37 / 40, `commands/supervisor.md` 15 / 15, `docs/loop-inventory/supervisor.md` 32 / 35); the rationale doc carries no counted token |
| `scripts/check-shared-prefix.sh` | OK |
| pinning tests of the pair | `test-check-children-settled.sh` 61/61, `test-non-interactive-gates-seam.sh` 64/64, `test-not-verified-transport-seam.sh` 25/25, `test-phase45-rounds-seam.sh` 61/61, `test-release-refold.sh` 26/26, `test-rules-seams.sh` 135/135, `test-run-lock.sh` 82/82, `test-verify-provides.sh` 163/163, `test-build-handoff.sh` 93/93, `test-check-contract-parity.sh` 20/20, `test-supervisor-next-step.sh` 105/105 |

Inventory rows of the pair after subtask 1 (no `story` or `rule` row homed `prose`):

```bash
awk -F' \\| ' '/^\| SV-/ && ($2=="agents/supervisor.md" || $2=="commands/supervisor.md") && ($6=="rule" || $6=="story") { h=$7; sub(/#.*/, "", h); print $2, $6, h }' \
  loomwright/docs/loop-inventory/supervisor.md | sort | uniq -c
```

```
  55 agents/supervisor.md rule global
   1 agents/supervisor.md rule script:build-state.sh
   1 agents/supervisor.md rule script:supervisor-next-step.sh plan
  30 agents/supervisor.md rule step-scoped
  13 agents/supervisor.md story rationale:docs/rationale/supervisor.md
  38 commands/supervisor.md rule global
   2 commands/supervisor.md story rationale:docs/rationale/supervisor.md
```

Two rows were added (SV-746, the on-demand skill routing rule that replaces the 4f audit; SV-747, the two-lens review rule under §"Architecture"); `## Counts` and the gap list were recomputed (rows 745 → 747, rule 303 → 305, GAP 491 → 493). Re-anchored rows whose text moved within its file: SV-017, SV-057, SV-058, SV-059, SV-071, SV-122, SV-286, SV-331, SV-335–SV-341, SV-345.

### Subtask 2 — results

Subtask 2, after the change (each script's own summary line):

| Gate / test | Result |
|---|---|
| `loomwright/scripts/test-loop-inventory.sh` | 43/43 passed (`loop-inventory: OK — 2238 rows across 4 groups`) |
| `scripts/check-doc-currency.sh` | OK |
| `loomwright/scripts/test-citation-drift.sh` | 26 passed, 0 failed |
| `scripts/check-token-budget.sh` | OK, 0 breaches (`.agents["execute-manager"]` 31155 / 42568, `.agents.supervisor` 20037 / 30378, `.commands.supervisor` 10750 / 16002, `.skills["async-orchestration"]` 8076 / 15760 proxy tokens) |
| `scripts/check-contract-parity.sh` | OK (new row `skills/async-orchestration/finalize.md\|status\|…`, the `agents/supervisor.md` allowlist copied; `SKILL.md` had no row and still carries no status literal) |
| `scripts/check-vendor-coupling.sh` | OK, 0 breaches (`skills/async-orchestration/SKILL.md` 18 / 18; `finalize.md` and the rationale doc carry no counted token) |
| `scripts/check-shared-prefix.sh` | OK |
| pinning tests | `test-check-children-settled.sh` 61/61, `test-not-verified-transport-seam.sh` 25/25, `test-pr-body-evidence-seam.sh` 77/77, `test-release-refold.sh` 26/26, `test-worktree-salvage.sh` 71/71, `test-reconcile-resume-state.sh` 23/23, `test-context-digest.sh` 37/37, `test-phase45-rounds-seam.sh` 61/61, `test-rules-seams.sh` 135/135, `test-verify-provides.sh` 163/163, `test-worktree-audit.sh` 176/176, `test-check-contract-parity.sh` 21/21, `test-non-interactive-gates-seam.sh` 64/64, `test-run-lock.sh` 82/82, `test-build-handoff.sh` 93/93, `test-supervisor-next-step.sh` 105/105 (golden fixtures unchanged), `test-skills-index-companion.sh` 7/7, `scripts/check-skills-index-sync.sh` OK, `test-rule-conformance-seam.sh` 146/146, `test-gen-color-legend.sh` 20/20, `scripts/test-check-vendor-coupling.sh` 338/338, `scripts/test-check-token-budget.sh` OK |

Inventory rows of async-orchestration after subtask 2 (no `story` or `rule` row homed `prose`):

```bash
awk -F' \\| ' '/^\| SV-/ && ($2 ~ /async-orchestration/) && ($6=="rule" || $6=="story") { h=$7; sub(/#.*/, "", h); print $2, $6, h }' \
  loomwright/docs/loop-inventory/supervisor.md | sort | uniq -c
```

```
  47 skills/async-orchestration/SKILL.md rule global
   1 skills/async-orchestration/SKILL.md rule script:validate-worker-result.py
   1 skills/async-orchestration/SKILL.md rule script:verify-provides.sh
  12 skills/async-orchestration/SKILL.md rule step-scoped
   7 skills/async-orchestration/SKILL.md story rationale:docs/rationale/supervisor.md
   6 skills/async-orchestration/finalize.md rule global
   1 skills/async-orchestration/finalize.md rule script:supervisor-next-step.sh finalize
   2 skills/async-orchestration/finalize.md rule script:supervisor-next-step.sh handover
   1 skills/async-orchestration/finalize.md rule script:supervisor-next-step.sh pr-verify
   1 skills/async-orchestration/finalize.md rule script:worktree-audit.sh report
   9 skills/async-orchestration/finalize.md rule step-scoped
   6 skills/async-orchestration/finalize.md story rationale:docs/rationale/supervisor.md
```

`finalize.md` joined the group's `## Sources` and the `supervisor)` arm of `test-loop-inventory.sh` (and its header comment). Rows whose text moved to `finalize.md` had their file cell changed (SV-616–618, SV-678–SV-718); re-anchored rows: SV-609, SV-616–618, SV-622, SV-633, SV-651, SV-677, SV-678, SV-695, SV-713–715, SV-722, SV-727, SV-728, SV-736, and the pair rows SV-066, SV-143, SV-152, SV-746 (action/anchor text follows the new Read routing). Twelve rows added: SV-749 (the Part 2 stub routing rule) and SV-750 (finalize.md load-by-phase rule), both `global`; SV-748, SV-751–SV-759, `story` rows homed in the rationale doc. `## Counts` and the gap list recomputed (rows 747 → 759, rule 305 → 307, story 21 → 31, GAP 493 → 505).
