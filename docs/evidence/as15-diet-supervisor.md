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

## Behaviour questions

Found while moving text; listed here and not fixed (AC9).

1. **Does the inline path load `agents/supervisor.md`?** `commands/supervisor.md` §"Inline-path canonical state writes" says the inline `/supervisor` and `/autonomous` paths never load `agents/supervisor.md`. The same file's §"What This Does" sends the inline main thread to `agents/supervisor.md` for Phase 1 actions 0–3 and the Phase 4 gate list, and its execution contract says the completion-tail guard lives verbatim only there. If the inline path really never loads the agent file, the inline path has no copy of the guard text or the Phase 1 task-selection actions.
2. **`--max-tokens` on the Parallel Path.** The `--max-tokens` parameter row in `commands/supervisor.md` says each Phase 3 poll-loop iteration sums the session ledger and parks before spawning another worker/reviewer round. `agents/supervisor.md` (Sequential Path scope note) says only the Sequential Path's own loop checks the ledger and the Parallel Path's poll loop does not. Neither `agents/execute-manager.md`, `skills/async-orchestration/SKILL.md` nor `scripts/supervisor-next-step.sh` mentions `read-token-ledger.sh` or `MAX_TOKENS`, so the agent prompt matches the code and the command row overstates. The same row also describes the Phase 0 run-lock acquire, which runs whether or not `--max-tokens` is set.
3. **Phase 4.5 NEEDS_HUMAN / max iterations.** `commands/supervisor.md` §"Gate Decisions" maps a Phase 4.5 `NEEDS_HUMAN` to "Checkpoint, pause, exit with resume command" and `FAIL` at max iterations to "Checkpoint, escalate to human". `agents/supervisor.md` Phase 4.5 exit conditions map both to `heal_decision == ESCALATED` → `completed_with_escalation`, findings posted to the PR, job → `done/` (a normal exit, not a checkpoint), and its own Error Handling table says the exhausted loop marks ESCALATED and exits normally.

## Proposed hooks

None from subtask 1. No rule in the pair needed a new hook to leave the prompt: every `rule` row was either kept short in place (`global`, anchor-checked), sat at the one step it governs (`step-scoped`), or was already enforced by an existing script (SV-058 → `script:build-state.sh`, its one line kept so the model does not write the `## Session` block itself).

## Pin mutations

Subtask 1 repointed no test: no needle any test reads moved out of the pair (every pinned line stayed in place, byte-identical), and no committed pinned `file:N` citation points into the pair: `grep -rnE 'agents/supervisor\.md:[0-9]|commands/supervisor\.md:[0-9]' loomwright/scripts scripts loomwright/docs/rationale` prints only two historical fixture records (`scripts/fixtures/harvest-ledger/results.jsonl`, `scripts/fixtures/corpus-briefs/done/2026-07-23-curation-anti-rot.md`) — frozen data quoting old line numbers, not citations `test-citation-drift.sh` checks (it stays green).

`test-loop-inventory.sh` mutation controls on a scratch copy (`cp -R loomwright scripts "$SCRATCH/mut/"`; the unmutated scratch copy is green first: `loop-inventory: OK — 2226 rows across 4 groups`):

| Row (home) | Mutation | Mutant checked | Result |
|---|---|---|---|
| SV-746 (`global`, `agents/supervisor.md`) | `grep -v 'The frontmatter \`skills:\` list is empty: no protocol skill is preloaded.'` | non-empty, 649 → 648 lines, differs (`cmp`) | exit 1, `FAIL SV-746: anchor not found in agents/supervisor.md` |
| SV-340 (`global`, `commands/supervisor.md`) | `grep -v 'Recover: \*\*do NOT delete the state file\*\*'` (one line, which also carries the SV-339 and SV-341 anchors) | differs (`cmp`) | exit 1, `FAIL SV-339`, `FAIL SV-340`, `FAIL SV-341: anchor not found in commands/supervisor.md` |

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
