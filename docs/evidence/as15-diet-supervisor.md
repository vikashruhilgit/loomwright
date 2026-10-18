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

### Subtask 3 — self-heal-advisory

After subtask 3 (`cd loomwright && wc -c skills/self-heal-advisory/*.md agents/supervisor.md commands/supervisor.md`):

```
   54843 skills/self-heal-advisory/SKILL.md
   52730 skills/self-heal-advisory/completion-tail.md
    4401 skills/self-heal-advisory/escalation.md
    8929 skills/self-heal-advisory/multi-voter.md
   16188 skills/self-heal-advisory/on-entry.md
   79620 agents/supervisor.md
   43057 commands/supervisor.md
```

self-heal-advisory went from 176,146 to 137,091 bytes all-modes (−39,055, −22.2%). Per Phase 4.5 run without `--multi-voter-heal`, the multi-voter file (8,929) is never Read; an ordinary iteration needs `SKILL.md` alone (54,843, −68.9% against the old whole-file Read), entry adds `on-entry.md`, the post-loop step adds `completion-tail.md`, and `escalation.md` is Read only on a base mismatch or a fix-task crash.

Group running total after subtask 3 (`wc -c` on the four sources + `finalize.md` + the four self-heal split files): 79,620 + 43,057 + 137,091 + 24,137 + 8,168 = **292,073 bytes all-modes** (base 391,294; −25.4%). Default path (no `--multi-voter-heal`, so `multi-voter.md` excluded): 283,144 bytes (−27.6%). **AC2 is NOT met by subtask 3: the all-modes target ≤ 273,905 is short by 18,168 bytes.** Why it stopped here: the remaining bulk is text a test pins byte-for-byte or a spawned agent receives verbatim — the code-reviewer spawn prompt (~12.4 KB, pinned line by line by six seam tests), the fix-task prompt (~6.1 KB), the contract-builder prompt (~4.3 KB), the loop pseudo-code (~14 KB) — and every further cut there is a reword of a pinned or agent-facing instruction, which this item's non-goal (no behaviour change) and AC7 (never reword pinned text) rule out. Candidates for whoever closes the gap, none attempted: the pair's Phase 4.5 restatements (`commands/supervisor.md` §"What This Does" until-mergeable / timing / R9 / observability paragraphs, ~4.5 KB; `agents/supervisor.md` Phase 4.5 one-line pointers, ~2.5 KB) — each carries inventory anchors and an AC8 invariant, so each needs its rows re-anchored in the same change.

History references (same regex) in self-heal-advisory: 19 → 5 across the five files — all in `SKILL.md`: `#431/#432` in the `### House-rule verdicts line` heading (an `h:` inventory anchor and a §-citation target), `#512` twice (the release re-fold comment in the loop and the error-table row `test-release-refold.sh` pins byte-for-byte), and the frontmatter `lastUpdated` date. The split files carry none.

## Behaviour questions

Found while moving text; listed here and not fixed (AC9).

1. **Does the inline path load `agents/supervisor.md`?** `commands/supervisor.md` §"Inline-path canonical state writes" says the inline `/supervisor` and `/autonomous` paths never load `agents/supervisor.md`. The same file's §"What This Does" sends the inline main thread to `agents/supervisor.md` for Phase 1 actions 0–3 and the Phase 4 gate list, and its execution contract says the completion-tail guard lives verbatim only there. If the inline path really never loads the agent file, the inline path has no copy of the guard text or the Phase 1 task-selection actions.
2. **`--max-tokens` on the Parallel Path.** The `--max-tokens` parameter row in `commands/supervisor.md` says each Phase 3 poll-loop iteration sums the session ledger and parks before spawning another worker/reviewer round. `agents/supervisor.md` (Sequential Path scope note) says only the Sequential Path's own loop checks the ledger and the Parallel Path's poll loop does not. Neither `agents/execute-manager.md`, `skills/async-orchestration/SKILL.md` nor `scripts/supervisor-next-step.sh` mentions `read-token-ledger.sh` or `MAX_TOKENS`, so the agent prompt matches the code and the command row overstates. The same row also describes the Phase 0 run-lock acquire, which runs whether or not `--max-tokens` is set.
3. **Phase 4.5 NEEDS_HUMAN / max iterations.** `commands/supervisor.md` §"Gate Decisions" maps a Phase 4.5 `NEEDS_HUMAN` to "Checkpoint, pause, exit with resume command" and `FAIL` at max iterations to "Checkpoint, escalate to human". `agents/supervisor.md` Phase 4.5 exit conditions map both to `heal_decision == ESCALATED` → `completed_with_escalation`, findings posted to the PR, job → `done/` (a normal exit, not a checkpoint), and its own Error Handling table says the exhausted loop marks ESCALATED and exits normally.
4. **Phase 4 no longer re-reads `SKILL.md`.** Before, the Phase 4 Read of `skills/async-orchestration/SKILL.md` was a compaction refresh of the whole file, Part 2 FINALIZE procedure and §"Subagent Spawn Contracts" together. Phase 4 now Reads `finalize.md` (the procedure) and not `SKILL.md`. The only spawns Phase 4 makes on the driver path are Context-Keeper ops and the `finalize-merge` / `finalize-publish` instructions, whose JSON carries the agent and payload itself; but a delegated `--legacy` run whose context compacted during a long Phase 3 would no longer get the spawn-contract shapes refreshed at Phase 4. Owner to confirm the refresh was only ever for the FINALIZE procedure (the rationale doc's §"Async-orchestration routing" says so).
5. **Two out-of-lane citations still point at `SKILL.md` for text now in `finalize.md`.** `loomwright/docs/supervisor-legacy-phases.md` (§"Phase 4 (FINALIZE)" protocol-authority line, the `--legacy` path) names `skills/async-orchestration/SKILL.md` **Part 2 — Supervisor FINALIZE Protocol** — it still resolves, one hop later, through the `# Part 2` stub. `loomwright/scripts/validate-execute-result.py` (a comment) cites `skills/async-orchestration/SKILL.md` §"Cleanup worktrees", which is now `finalize.md` step 4. Neither file is in subtask 2's lanes; not edited.
6. **The adjudication text dropped its ask-tool mention.** `SKILL.md` §"Scope Expansion Adjudication" said the Supervisor presents the four options "to the user via" the host's ask tool; the same section's closing sentence already says the Supervisor presents them, and `agents/supervisor.md` §"Adjudication Handling" (driver `ask`, Can't-ask rule ⇒ `adjudication_required_non_interactive`) is where that happens. The restatement was removed, not the rule; listed because an unconditional "via the ask tool" read as if the Execute Manager-side text promised an ask even under `--non-interactive`.


Subtask 3 (self-heal-advisory):

7. **`$NO_CMD_FLAG` is read before the step that defines it.** The per-iteration rules-check replay (`SKILL.md` §"Rules-check replay") "reuses `$NO_CMD_FLAG` UNCHANGED from the Ground-truth execution step", but ground truth runs after the loop (`completion-tail.md`). On the first iteration the owning step has not run yet, so the replay depends on the model deriving the same `NON_INTERACTIVE ? "--no-cmd" : ""` value early. True before the split too (the order was hidden by both sections sitting in Part 1); not changed.
8. **Step 1g is an on-entry step that runs every iteration.** It is numbered with the on-entry actions but the loop pseudo-code never calls it explicitly at the top of an iteration; only the reviewer prompt's DEVIATIONS ADVISORY line and the `fixer_deviations` carriage imply the re-run. It now sits in `SKILL.md` (the every-iteration file) with a pointer from `on-entry.md`; the loop text is unchanged.
9. **Out-of-lane comment citations name `SKILL.md` for text now in a split file.** `scripts/adapters/providers/lens-run.sh` (§"Multi-voter verification"), `scripts/classify-risk.sh` (§"Advisory red-team lens"), `scripts/rules-audit-line.sh` (§"Rules-store audit"), `scripts/run-ground-truth.sh`, `scripts/read-system-contract.sh`, `scripts/session-resume.sh` / `scripts/reconcile-jobs.sh` / `scripts/verify-run.sh` / `scripts/pr-postmortem-gather.sh` (completion-tail steps 2 / 2.5 / 5), and the next-step driver's handover string (`SKILL.md Part 2`, deliberately unedited). Each still resolves one hop later through `SKILL.md`'s pointer list and index; repointing them is outside this lane.
10. **Fix-task crash is stated twice.** `SKILL.md`'s error-handling table row and `escalation.md` §"Fix task crash handling" both say "pause with `status: checkpoint`; the resume counter increments at the next entry". They agree; the table stayed in `SKILL.md` because its other rows apply on every iteration.
## Proposed hooks

None from subtask 1. No rule in the pair needed a new hook to leave the prompt: every `rule` row was either kept short in place (`global`, anchor-checked), sat at the one step it governs (`step-scoped`), or was already enforced by an existing script (SV-058 → `script:build-state.sh`, its one line kept so the model does not write the `## Session` block itself).

None from subtask 2 either: every async-orchestration `rule` row is `global` (anchor-checked), `step-scoped`, or homed on the script that already enforces it (`supervisor-next-step.sh`, `verify-provides.sh`, `validate-worker-result.py`, `worktree-audit.sh report`).


None from subtask 3: every self-heal-advisory `rule` row is `step-scoped` at the step it governs (100 rows) or `global` (1: the HARD ADVISORY CONTRACT line, anchor-checked); no rule needed a new hook to leave the prompt.

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

### Subtask 3 — repointed pins

Tests repointed (needles byte-identical; only the file a needle is read from changed): `test-brief-conformance-seam.sh` (new `SKILL_ENTRY` = `on-entry.md` for the `25 bullets` cap and step `1f.`), `test-execution-directive-seam.sh` (new `SKILL_MV` = `multi-voter.md` for the refute-scope leg), `test-closed-enum-pins-seam.sh` (new `SHA_TAIL` = `completion-tail.md` for the Heal-reason list, `also pre-increment`, `**Rules-check replay line`, `already escalated with`; its two fixture briefs name `completion-tail.md` for those three rows and in their touch sets — out of lane, see the worker result), `test-system-contract.sh` §20, `test-rules-audit-line.sh`, `test-classify-risk.sh` E4, `test-not-verified-transport-seam.sh` (f), `test-automate-trail.d/05-finalize-closeout-others.sh` DS3 (all → `completion-tail.md`), `test-rules-seams.sh` (`on-entry.md` added to `SEAMS`, and it replaces `SKILL.md` in `ARGS_BEARING` and the after-span `c_mut_run` — the args-bearing `read-rules.sh` call moved there), `test-validate-code-review-result.sh` (the `--with-ids` read check reads `on-entry.md`; the HOUSE-RULES prompt anchor still reads `SKILL.md`). New: two ENUMS rows each for `completion-tail.md` and `escalation.md` in `scripts/check-contract-parity.sh` (allowlists copied from `SKILL.md`'s rows), fixture files and two red legs in `test-check-contract-parity.sh`.

Controls: the needle's line(s) were deleted (`grep -vF`) **in place in the committed split file** (not the `SKILL.md` pointer), the test run, and the file restored with `git checkout --` (`git status` clean afterwards) — a deviation from subtask 2's scratch-copy procedure, taken for the turn budget; every mutant was checked non-empty and `cmp`-different first. Each test was green unmutated in the same tree (Results below).

| Pin | Mutation (`grep -vF`, split file) | Mutant |
|---|---|---|
| `test-brief-conformance-seam.sh` cap | `25 bullets` in `on-entry.md` | rc 1: `(b) cap token '25 bullets' count: total=0 in-section=0` |
| `test-rules-seams.sh` (D)/(C) | `read-rules.sh" <touched files...>` in `on-entry.md` | rc 1: `[self-heal-advisory/on-entry.md] (D) read-rules.sh invoked with NO path-argument placeholder` |
| `test-validate-code-review-result.sh` `--with-ids` | same line in `on-entry.md` | rc 1 (house_rule_verdicts parity) |
| `test-system-contract.sh` §20 | `if twin_store_status == "dark" or touched_contract_withheld:` in `completion-tail.md` | rc 1: `(20) SEED FAILED — could not locate the three anchors (withheld= …)` |
| `test-rules-audit-line.sh` AC1 | `rules_audit: clean` in `completion-tail.md` | rc 1: `AC1 self-heal-advisory is missing the rules-audit-line invocation / state trace` |
| `test-classify-risk.sh` E4 | every `classify-risk.sh` line in `completion-tail.md` | rc 1: `E4 lens still restates the heuristic or lacks the call` |
| `test-not-verified-transport-seam.sh` (f) | `appended to the brief itself, on BOTH the PASS/loop-skipped and ESCALATED outcomes` | rc 1: `(f) step 2 does not state the both-outcomes rule` |
| `test-execution-directive-seam.sh` (c) | `2. **Second-opinion refute check` in `multi-voter.md` | rc 1: `(c) multi-voter refute: only the code-reviewer-lens refute carries the directive` |
| `test-closed-enum-pins-seam.sh` | `also pre-increment` in `completion-tail.md` | rc 1: `anchor gone from self-heal-advisory completion-tail.md: also pre-increment` |
| `test-automate-trail.sh` DS3 | `2.5. **Requirement close-out` in `completion-tail.md` | rc 1 (DS3) |
| `test-loop-inventory.sh` group sources | drop `skills/self-heal-advisory/multi-voter.md` from the `supervisor)` arm | rc 1: `FAIL supervisor: ## Sources lists skills/self-heal-advisory/multi-voter.md, which is not a source of the group`, `FAIL SV-513: file '…multi-voter.md' is not a source of the supervisor group` |
| `scripts/check-contract-parity.sh` new ENUMS rows | fixture legs in `test-check-contract-parity.sh`: `status: paused` appended to `completion-tail.md`, `heal_decision: FAILED` appended to `escalation.md` | both legs rc 1 as asserted (23/23 passed) |

**AC4 grep** (`cd loomwright && grep -rn 'multi-voter\.md' agents/supervisor.md commands/supervisor.md skills/self-heal-advisory/*.md skills/async-orchestration/*.md`) — every hit is conditional or descriptive, none an unconditional Read:

```
agents/supervisor.md:67   … `multi-voter.md` only under `--multi-voter-heal`)
agents/supervisor.md:302  … `multi-voter.md` ONLY when `MULTI_VOTER_HEAL` is true (never on the default path) …
agents/supervisor.md:339  … Protocol authority …: `skills/self-heal-advisory/multi-voter.md`, Read only when `MULTI_VOTER_HEAL` is true.
commands/supervisor.md:73 … `multi-voter.md` only when `MULTI_VOTER_HEAL` is true …
skills/self-heal-advisory/SKILL.md:3    (frontmatter description) multi-voter.md (only under --multi-voter-heal)
skills/self-heal-advisory/SKILL.md:17   | `multi-voter.md` | only when `MULTI_VOTER_HEAL == true` | …
skills/self-heal-advisory/SKILL.md:384  … only when `MULTI_VOTER_HEAL == true`, Read `multi-voter.md` … When `MULTI_VOTER_HEAL == false` (the default) do NOT Read it …
skills/self-heal-advisory/on-entry.md:107  (a §"Delay-vs-decide" citation, no Read)
```

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

### Subtask 3 — results

Subtask 3, after the change (each script's own summary line; all run in one tree after the last edit):

| Gate / test | Result |
|---|---|
| `loomwright/scripts/test-loop-inventory.sh` | 43/43 passed |
| `scripts/check-doc-currency.sh` | OK |
| `loomwright/scripts/test-citation-drift.sh` | 26 passed, 0 failed |
| `scripts/check-token-budget.sh` | OK |
| `scripts/check-contract-parity.sh` | OK (four new rows: `skills/self-heal-advisory/{completion-tail,escalation}.md\|status\|…` and `…\|heal_decision\|…`; existing rows byte-identical) |
| `scripts/check-vendor-coupling.sh` | OK (`SKILL.md` 7 / 7, `completion-tail.md` 16, `on-entry.md` 5, `multi-voter.md` 1; `escalation.md` and the rationale doc carry no counted token) |
| pinning tests | `test-brief-conformance-seam.sh` 26/26, `test-deviations-advisory-seam.sh` 30/30, `test-execution-directive-seam.sh` 50/50, `test-closed-enum-pins-seam.sh` 79/79, `test-rules-gate-seams.sh` 26/26, `test-rules-seams.sh` 139/139, `test-rules-audit-line.sh` 32/32, `test-phase45-rounds-seam.sh` 61/61, `test-not-verified-transport-seam.sh` 25/25, `test-pr-body-evidence-seam.sh` 77/77, `test-system-contract.sh` 124/124, `test-classify-risk.sh` 45/45, `test-validate-code-review-result.sh` 86/86, `test-release-refold.sh` 26/26, `test-read-rules.sh` 117/117, `test-automate-dismissed.sh` 246/246, `test-automate-trail.sh` 786/786, `test-check-contract-parity.sh` 23/23 |
| pair tests | `test-check-children-settled.sh` 61/61, `test-run-lock.sh` 82/82, `test-non-interactive-gates-seam.sh` 64/64, `test-build-handoff.sh` 93/93, `test-verify-provides.sh` 163/163 |

Inventory rows of self-heal-advisory after subtask 3 (no `story` or `rule` row homed `prose`; same `awk` as subtask 2 with `self-heal` in place of `async-orchestration`):

```
   1 skills/self-heal-advisory/SKILL.md rule global
  30 skills/self-heal-advisory/SKILL.md rule step-scoped
  45 skills/self-heal-advisory/completion-tail.md rule step-scoped
   1 skills/self-heal-advisory/completion-tail.md story rationale:docs/rationale/supervisor.md
   7 skills/self-heal-advisory/escalation.md rule step-scoped
   7 skills/self-heal-advisory/multi-voter.md rule step-scoped
   1 skills/self-heal-advisory/multi-voter.md story rationale:docs/rationale/supervisor.md
  11 skills/self-heal-advisory/on-entry.md rule step-scoped
   1 skills/self-heal-advisory/on-entry.md story rationale:docs/rationale/supervisor.md
```

The four split files joined the group's `## Sources` and the `supervisor)` arm of `test-loop-inventory.sh` (and its header comment). Every self-heal row's file cell follows its text; 70 rows were re-anchored to the trimmed wording (SV-346–SV-587 range); the kind counts and the gap list are unchanged (no row added or removed). Stories moved to `docs/rationale/supervisor.md` §"Self-heal advisory — why the protocol reads as it does" (no install-root token; two vendor tokens reworded out on the gate's first run).

### Subtask 3 — bounded duplication pass (coordinator request)

One bounded pass for duplicated text only — no rule reworded, no pinned needle touched, every inventory anchor kept live (no row needed re-anchoring):

- `commands/supervisor.md` §"What This Does": the until-mergeable, timing-note, R9 and observability paragraphs now state each rule once and point at `skills/self-heal-advisory/completion-tail.md` step 5.5 for the procedure; the awk snippet and the inline-path sections are unchanged (43,057 → 41,274).
- `agents/supervisor.md` Phase 4.5 one-line pointers (rubric condition, drain dispatch, marker rule, red-team lens) cut to the rule plus a pointer; the heal-only / earned-fallback invariant kept (79,620 → 78,917).
- `completion-tail.md`: the rules-store audit's contract blockquote no longer restates what its state trace says (52,730 → 52,521).

Searched and left alone: (1) the spawn prompts — the code-reviewer prompt's lines are pinned substring-by-substring (brief-conformance (a), deviations (e)/(f), validate-code-review-result's verdict window, execution-directive, phase45-rounds) and the DIFFERENT-LENS class list is held to mirror parity with `skills/quality-checklist/SKILL.md`; the fix-task and contract-builder prompts go to `general-purpose` Tasks, which carry no agent prompt of their own, so nothing in them is already carried by the spawned agent. (2) Same-rule-twice inside a split file: the remaining repeats (step 1g vs §"Deviations advisory", steps 1e/1f vs their sections) carry needles pinned on both copies.

Group all-modes after this pass: 78,917 + 41,274 + 137,882 + 24,137 + 8,168 = **289,378 bytes** (base 391,294; −26.0%); default path without `multi-voter.md`: 280,449. **AC2 is still NOT met — 15,473 bytes over 273,905.** Closing it needs a reword of pinned or agent-facing prompt text, which this item rules out; stopped here as instructed. All gates and pinning tests re-run green after the pass (same set as the results table above, 29/29 scripts rc 0).

## Final measurements (subtask 4)

Measured on the finished branch (HEAD `0c80063`, clean tree) on 2026-10-19, from the repo root unless a `cd` is shown. The records above are left as written. One arithmetic slip in them: the subtask 3 duplication-pass line gives self-heal-advisory as 137,882; the five files sum to 136,882 (see below). The 289,378 total on that line is correct.

### AC2 — runtime read set (`wc -c`) — **AC2 NOT MET**

Before, re-measured at the base commit into a scratch dir (same commands as §"Baseline"):

```bash
S=$(mktemp -d)
for f in agents/supervisor.md commands/supervisor.md skills/self-heal-advisory/SKILL.md skills/async-orchestration/SKILL.md; do
  mkdir -p "$S/loomwright/$(dirname "$f")"; git show 3a03dfa:loomwright/$f > "$S/loomwright/$f"
done
cd "$S/loomwright" && wc -c agents/supervisor.md commands/supervisor.md skills/self-heal-advisory/SKILL.md skills/async-orchestration/SKILL.md
```

```
  105710 agents/supervisor.md
   60305 commands/supervisor.md
  176146 skills/self-heal-advisory/SKILL.md
   49133 skills/async-orchestration/SKILL.md
  391294 total
```

After, all modes. These are the four sources plus every split file this item created. `git diff --name-status 3a03dfa -- loomwright/skills loomwright/agents loomwright/commands` lists the five `A` files below and no others. The rationale and inventory docs are not counted.

```bash
cd loomwright && wc -c agents/supervisor.md commands/supervisor.md \
  skills/self-heal-advisory/SKILL.md skills/self-heal-advisory/on-entry.md skills/self-heal-advisory/completion-tail.md \
  skills/self-heal-advisory/escalation.md skills/self-heal-advisory/multi-voter.md \
  skills/async-orchestration/SKILL.md skills/async-orchestration/finalize.md
```

```
   78917 agents/supervisor.md
   41274 commands/supervisor.md
   54843 skills/self-heal-advisory/SKILL.md
   16188 skills/self-heal-advisory/on-entry.md
   52521 skills/self-heal-advisory/completion-tail.md
    4401 skills/self-heal-advisory/escalation.md
    8929 skills/self-heal-advisory/multi-voter.md
   24137 skills/async-orchestration/SKILL.md
    8168 skills/async-orchestration/finalize.md
  289378 total
```

| Read set | Bytes | Change vs 391,294 | Against AC2 target ≤ 273,905 |
|---|---|---|---|
| **All modes**: all nine files (the AC2 measure) | **289,378** | −101,916 (**−26.0%**) | **NOT MET**: 15,473 bytes over |
| Default path: no `--multi-voter-heal` and no escalation, so without `multi-voter.md` and `escalation.md` | 276,048 | −115,246 (−29.5%) | also over, by 2,143 |
| Default path including `escalation.md` (a base mismatch or a fix-task crash) | 280,449 | −110,845 (−28.3%) | over, by 6,544 |
| *Information only, NOT the honest read-set figure:* the requirement's literal Touches list, the four original files alone | 199,171 | −192,123 (−49.1%) | n/a |

The last row is not a read-set measure. It leaves out the 90,207 bytes of split-file text that a run still Reads at the step that needs it. Most of that text moved out of the four files and was not cut. The figure is here because the requirement's Touches list names only the four files. It does not count toward AC2.

Per source, all modes: `agents/supervisor.md` −25.3%; `commands/supervisor.md` −31.6%; self-heal-advisory (five files, 136,882) −22.3%; async-orchestration (two files, 32,305) −34.2%.

**AC2 is NOT met.** The all-modes total is 289,378 bytes, 26.0% below the base, against a target of at least 30%. The default-path set (29.5%) also misses the target. Subtask 3 recorded why it stopped: most of the remaining bytes are text that a test pins byte-for-byte, or text that a spawned agent receives verbatim. That includes the code-reviewer spawn prompt (~12.4 KB, pinned line by line by six seam tests), the fix-task prompt (~6.1 KB), the contract-builder prompt (~4.3 KB) and the loop pseudo-code (~14 KB). Every further cut there means rewording a pinned or agent-facing instruction, and this item rules that out twice: by its no-behaviour-change non-goal, and by AC7 (pinned text is never reworded). The bounded duplication pass (above) took the pair's Phase 4.5 restatements that subtask 3 had listed as candidates. That pass moved the total from 292,073 to 289,378. Nothing it left can be cut without rewording. Closing the remaining 15,473 bytes needs an owner decision: either allow the pinned needles to be reworded together with their tests, or accept the 26.0% reduction.

### AC3 — history references

The requirement's regex, per file, over the base-commit scratch copy and the after tree:

```bash
RX='#[0-9]{2,4}\b|queue/[0-9]+|20[0-9]{2}-[0-9]{2}-[0-9]{2}|item [0-9]+'
# before: in "$S/loomwright", the four sources; after: in loomwright/, the nine files above
for f in <files>; do printf '%s %s\n' "$f" "$(grep -oE "$RX" "$f" | wc -l | tr -d ' ')"; done
grep -noE "$RX" agents/supervisor.md commands/supervisor.md skills/self-heal-advisory/*.md skills/async-orchestration/*.md   # after, the hits
```

- Before (base commit): **31** (`agents/supervisor.md` 3, `commands/supervisor.md` 5, `skills/self-heal-advisory/SKILL.md` 19, `skills/async-orchestration/SKILL.md` 4).
- After: **9**. AC3 is met (9 < 31). Each of the nine is kept on purpose:

```
agents/supervisor.md:290:#512                         the Phase 4 gate line test-release-refold.sh pins byte-for-byte
skills/self-heal-advisory/SKILL.md:5:2026-10-19       frontmatter lastUpdated
skills/self-heal-advisory/SKILL.md:71:#431            ### House-rule verdicts line heading (an h: inventory anchor and a §-citation target)
skills/self-heal-advisory/SKILL.md:71:#432            same heading
skills/self-heal-advisory/SKILL.md:361:#512           the release re-fold comment in the loop
skills/self-heal-advisory/SKILL.md:403:#512           the error-table row test-release-refold.sh pins
skills/async-orchestration/SKILL.md:6:2026-10-19      frontmatter lastUpdated
skills/async-orchestration/finalize.md:53:#512        step 5.5 heading line (pinned by test-release-refold.sh)
skills/async-orchestration/finalize.md:98:#511       ## Evidence explainer (pinned by test-pr-body-evidence-seam.sh)
```

`commands/supervisor.md`, `on-entry.md`, `completion-tail.md`, `escalation.md` and `multi-voter.md` carry none.

### AC1 — story and rule rows by home

Command (every `story` and `rule` row of the group, counted by home; the rationale anchor and a `script:` home's sub-key are stripped):

```bash
AWKC='/^\| SV-[0-9]+ \|/ { n = split($0, c, " \\| "); k = c[6]; h = c[7]; sub(/#.*/, "", h); sub(/ .*/, "", h); if (k == "story" || k == "rule") print k "\t" h }'
git show 3a03dfa:loomwright/docs/loop-inventory/supervisor.md | awk "$AWKC" | sort | uniq -c   # before
awk "$AWKC" loomwright/docs/loop-inventory/supervisor.md | sort | uniq -c                     # after
```

Before:

```
 298 rule	prose
   5 rule	script:supervisor-next-step.sh
  21 story	prose
```

After:

```
 147 rule	global
   1 rule	script:build-state.sh
   5 rule	script:supervisor-next-step.sh
   1 rule	script:validate-worker-result.py
   1 rule	script:verify-provides.sh
   1 rule	script:worktree-audit.sh
 151 rule	step-scoped
  31 story	rationale:docs/rationale/supervisor.md
```

Zero `story` or `rule` rows are homed `prose`. No `rule` row has a `rationale:` home. The 307 rule rows and 31 story rows match the inventory's `## Counts` (`rule: 307`, `story: 31`, `rows: 759`, `GAP: 505`). The rule total grew 303 → 307 and the story total 21 → 31, because rows were added for new headings and split stories (see the subtask 1 and 2 results).

### AC4 — the multi-voter Read is conditional everywhere

The command is `cd loomwright && grep -rn 'multi-voter\.md' agents/supervisor.md commands/supervisor.md skills/self-heal-advisory/*.md skills/async-orchestration/*.md`, re-run on the final tree. Every hit is conditional on `MULTI_VOTER_HEAL` / `--multi-voter-heal`, or is descriptive (no Read). The matched text:

```
agents/supervisor.md:67     … `multi-voter.md` only under `--multi-voter-heal`). …
agents/supervisor.md:302    … `multi-voter.md` ONLY when `MULTI_VOTER_HEAL` is true (never on the default path); …
agents/supervisor.md:339    … Protocol authority …: `skills/self-heal-advisory/multi-voter.md`, Read only when `MULTI_VOTER_HEAL` is true.
commands/supervisor.md:73   … `multi-voter.md` only when `MULTI_VOTER_HEAL` is true, …
skills/self-heal-advisory/SKILL.md:3     (frontmatter description) … multi-voter.md (only under --multi-voter-heal) …
skills/self-heal-advisory/SKILL.md:17    | `multi-voter.md` | only when `MULTI_VOTER_HEAL == true` | multi-voter verification |
skills/self-heal-advisory/SKILL.md:384   … only when `MULTI_VOTER_HEAL == true`, Read `multi-voter.md` … When `MULTI_VOTER_HEAL == false` (the default) do NOT Read it …
skills/self-heal-advisory/on-entry.md:107   … `multi-voter.md` §"Delay-vs-decide" … (a citation, no Read)
```

A second grep, `grep -rnE 'self-heal-advisory/\*|self-heal-advisory/"|every file (in|of) this skill' <same files>`, found no whole-directory or glob Read. Its only hit is the HARD ADVISORY CONTRACT line in `SKILL.md`, which says the contract applies "in every file of this skill" and is not a Read. The transcript-level assertion (a default-path run never Reads the file) is part of Validation 3 below.

### Validation 1 — AC12 gates and every repointed test

These ran one after another from the worktree root on the final tree. Each output went to its own log, and each script's own summary line is quoted below.

| Gate / test | Exit | Result |
|---|---|---|
| `bash loomwright/scripts/test-loop-inventory.sh` | 0 | `RESULT: 43/43 passed` (`loop-inventory: OK — 2238 rows across 4 groups`) |
| `bash scripts/check-doc-currency.sh` | 0 | `✓ doc-currency: all checked version/count claims match the authoritative source.` (no pass/total; exit code reported) |
| `bash loomwright/scripts/test-citation-drift.sh` | 0 | `citation-drift: 26 passed, 0 failed` |
| `bash scripts/check-token-budget.sh` | 0 | `breaches: 0 \| errors: 0` (`.agents.supervisor` 19729 / 30378, `.commands.supervisor` 10318 / 16002, `.skills["self-heal-advisory"]` 34219 / 48440 (5 files), `.skills["async-orchestration"]` 8076 / 15760 (2 files) proxy tokens) |
| `bash scripts/check-contract-parity.sh` | 0 | `✓ contract-parity: all hook-enforced fields present and all status/decision literals in-enum.` (no pass/total; exit code reported) |
| `bash scripts/check-vendor-coupling.sh` | 0 | `breaches: 0 \| errors: 0` (`agents/supervisor.md` 37/40, `commands/supervisor.md` 15/15, self-heal `SKILL.md` 7/7, `completion-tail.md` 16/16, `on-entry.md` 5/5, `multi-voter.md` 1/1, async `SKILL.md` 18/18) |

The repointed tests are every `test-*.sh` that `git diff --name-only 3a03dfa -- 'loomwright/scripts/test-*'` lists. `test-loop-inventory.sh` is in the table above. `test-automate-trail.d/05-finalize-closeout-others.sh` runs inside `test-automate-trail.sh`.

| Test | Exit | Result | Pin-mutation control |
|---|---|---|---|
| `test-brief-conformance-seam.sh` | 0 | 26 passed, 0 failed | subtask 3 table |
| `test-check-children-settled.sh` | 0 | 61 passed, 0 failed | subtask 2 table |
| `test-check-contract-parity.sh` | 0 | 23/23 passed | its own red legs for the new ENUMS rows (subtasks 2, 3) |
| `test-classify-risk.sh` | 0 | 45 passed, 0 failed | subtask 3 table (E4) |
| `test-closed-enum-pins-seam.sh` | 0 | 79 passed, 0 failed | subtask 3 table |
| `test-execution-directive-seam.sh` | 0 | 50 passed, 0 failed | subtask 3 table |
| `test-not-verified-transport-seam.sh` | 0 | 25 passed, 0 failed | subtask 2 (e), subtask 3 (f) |
| `test-pr-body-evidence-seam.sh` | 0 | 77 passed, 0 failed | subtask 2 table |
| `test-reconcile-resume-state.sh` | 0 | 23 passed, 0 failed | comment-anchor change only, so no needle; the pinned citations in `reconcile-resume-state.sh` get the control below |
| `test-release-refold.sh` | 0 | 26 passed, 0 failed | subtask 2 table |
| `test-rules-audit-line.sh` | 0 | 32 passed, 0 failed | subtask 3 table |
| `test-rules-seams.sh` | 0 | 139 passed, 0 failed | subtask 3 table |
| `test-system-contract.sh` | 0 | 124 passed, 0 failed | subtask 3 table (§20) |
| `test-validate-code-review-result.sh` | 0 | `pass=86 fail=0` | subtask 3 table |
| `test-worktree-salvage.sh` | 0 | 71 passed, 0 failed | subtask 2 table |
| `test-automate-trail.sh` | 0 | 786 passed, 0 failed | subtask 3 table (DS3) |

All 22 scripts exited 0 (6 gates and 16 test scripts).

The subtask 3 controls were run in place on the committed split file and then restored with `git checkout --`. That is a recorded deviation from the scratch-copy procedure, and the tree is clean now (`git status --short` prints nothing).

**Citation pin control (`reconcile-resume-state.sh` → `finalize.md`).** This was run on a `mktemp -d` scratch repo: `loomwright/`, `scripts/` and `.gitignore` copied in, then `git init` and `git add -A`, with `HOME` relocated. The `subtask: {subtask_a} — {title}` line (line 15) was deleted from the copy of `finalize.md`. The mutant is non-empty and differs from the original (100 → 99 lines, `cmp`). The unmutated scratch run already fails one check, `citation-drift: 25 passed, 1 failed`. That failure is `(C2)` for the allowlist entry `loomwright/skills/claude-md-validation/SKILL.md|CLAUDE.md:42`: the scratch copy has no root `CLAUDE.md`, so that bare citation does not resolve. It is environmental and unrelated to this pin. The mutant adds the pin's own failure:

```
rc=1
    loomwright/scripts/reconcile-resume-state.sh cites loomwright/skills/async-orchestration/finalize.md:15 but 'subtask: {subtask_a} — {title}' is not within +/-3 lines of it
    loomwright/scripts/reconcile-resume-state.sh cites loomwright/skills/async-orchestration/finalize.md:15 but 'subtask: {subtask_a} — {title}' is not within +/-3 lines of it
FAIL: (B) 2 pinned citation(s) have DRIFTED off their anchor
citation-drift: 24 passed, 2 failed
```

### Validation 2 — mutation control on a real `global` row

The row is SV-349 (`skills/self-heal-advisory/SKILL.md`, `q: no advisory step ever changes `heal_decision`, triggers a fix iteration`, home `global`). It is the HARD ADVISORY CONTRACT line and the only `global` row in self-heal-advisory. The control ran on a `mktemp -d` scratch copy (`cp -R loomwright scripts "$M/"`, `HOME="$M/home"`). The anchored line was deleted with `grep -vF` from the copy of `SKILL.md`. The mutant was checked first: non-empty, 407 → 406 lines, and `cmp`-different. The test then ran as `bash loomwright/scripts/test-loop-inventory.sh --root "$M/loomwright"`.

```
# unmutated scratch copy
loop-inventory: OK — 2238 rows across 4 groups
rc=0
# mutant
FAIL SV-349: anchor not found in skills/self-heal-advisory/SKILL.md
loop-inventory: FAIL — 1 problem(s)
rc=1
```

## Not run — Validation 3

Validation 3 is a running-system step: one real item that exercises this group after the change, with the phase's result block pasted. It is a **pre-merge owner step outside this job**. This job does not run it and does not make up its result block. It is also the only place AC4's transcript assertion can be checked: on a run without `--multi-voter-heal`, Phase 4.5 never Reads `skills/self-heal-advisory/multi-voter.md`. The grep above shows only that every Read instruction is conditional. Before merge, the owner does one of two things:

- Run one live item on the changed prompts. For example, `/automate` on a one-item queue drives `/autonomous --single-iteration` and, through it, the Supervisor's Phase 4 FINALIZE and Phase 4.5. Paste that run's fenced `SUPERVISOR_RESULT` block into the PR body, and confirm from the transcript that `finalize.md` was Read at Phase 4 only and `multi-voter.md` was never Read.
- Or waive Validation 3 through the human-only `AUT-WAIVE` ask that `/automate`'s `validation-gate` raises.

Until one of the two happens, the gap stays visible and the gate fails closed.
