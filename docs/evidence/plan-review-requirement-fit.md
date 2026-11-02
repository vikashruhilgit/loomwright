# Plan Review requirement fit — live runs (Validation 3)

**What this proves:** the branch's Plan Reviewer, given a requirement and a brief the way Launch Pad's Phase 5.5 spawn contract passes them, rates the brief's fit to the requirement as the answer key in `loomwright/scripts/fixtures/plan-review-requirement-fit/README.md` says: `fulfils`, `under`, `over`, `fulfils`. It also shows each mapping line by line, and every result block passes the branch's `validate-plan-review-result.py` (rules 1–8).

**Prompt under test:** commit `1414422` on `feature/requirement-to-plan-checks-1`. That commit holds `agents/plan-reviewer.md` Criterion 22; the runs used that working tree.

**Plugin load:** every run's stream-json `system/init` event lists exactly one `loomwright` plugin, `{"name": "loomwright", "path": "<worktree>/loomwright", "source": "loomwright@inline"}`. So only the branch's copy was loaded, not an installed one. Per-run excerpts are below.

## Exact commands

The prompt for each pair is built in the spawn-contract shape: the brief between `--- BRIEF START ---` / `--- BRIEF END ---`; one `verify-provides.sh --parse-only` line per subtask between `--- GATE PARSE ---` markers; the requirement verbatim between `--- SOURCE REQUIREMENT ---` / `--- SOURCE REQUIREMENT END ---`; a short CLAUDE.md context; and the closing line `Check every review criterion. Output a PLAN_REVIEW_RESULT block.` No `--- APPLICABLE RULES ---` block is included, because no house rule routes to these files. The builder (`build-prompt.sh <worktree> <pair>`):

```bash
#!/usr/bin/env bash
set -eu
WT="$1"; P="$2"; D="$WT/loomwright/scripts/fixtures/plan-review-requirement-fit"
B="$D/$P-brief.md"; R="$D/$P-requirement.md"
printf '%s\n\n' "Review the following Supervisor-Ready Brief for quality, completeness, and correctness."
printf '%s\n' '--- BRIEF START ---'; cat "$B"; printf '%s\n\n' '--- BRIEF END ---'
printf '%s\n' '--- GATE PARSE ---'
for n in 1 2 3; do grep -q "^# Subtask $n\$" "$B" && bash "$WT/loomwright/scripts/verify-provides.sh" "$B" "$n" --parse-only; done
printf '%s\n\n' '--- GATE PARSE END ---'
printf '%s\n' '--- SOURCE REQUIREMENT ---'; cat "$R"; printf '%s\n\n' '--- SOURCE REQUIREMENT END ---'
cat <<'CTX'
Project CLAUDE.md context:
Loomwright is a Claude Code plugin (markdown agent/command/skill prompts, bash scripts, Python validators). Plugin files live under loomwright/ (agents/, commands/, skills/, scripts/, docs/). Prompt size budgets live in loomwright/docs/prompt-token-budgets.json with mirror rows in loomwright/docs/ARCHITECTURE_CONTRACTS.md, checked by scripts/check-token-budget.sh. Release notes go in a changelog.d/ fragment. Pre-push: bash scripts/ci-local.sh. Tests are loomwright/scripts/test-*.sh.

Check every review criterion. Output a PLAN_REVIEW_RESULT block.
CTX
```

Each run, from the worktree root (the parent session's lane variables are unset, so the child does not join the parent's `/automate` run):

```bash
bash build-prompt.sh "$WT" <pair> > <pair>.prompt.txt
cd "$WT" && env -u LOOMWRIGHT_LANES_COORDINATOR_PID -u LOOMWRIGHT_PHASE_DIR -u LOOMWRIGHT_LANE_RESUME_PATH \
  -u LOOMWRIGHT_RUN_LOCK_SESSION_ID -u LOOMWRIGHT_WEBHOOK_URL \
  claude -p --plugin-dir "$WT/loomwright" --agent loomwright:loomwright:plan-reviewer \
  --max-budget-usd 3 --output-format stream-json --verbose < <pair>.prompt.txt > <pair>.jsonl
python3 -I "$WT/loomwright/scripts/validate-plan-review-result.py" --raw < <(jq -r 'select(.type=="result") | .result' <pair>.jsonl)
```

`<pair>` is `fulfils`, `missing`, `extra` and `supporting`. The extra row `noreq` is an A8 probe: the same `fulfils` prompt with the whole `--- SOURCE REQUIREMENT ---` block removed (`awk '/^--- SOURCE REQUIREMENT ---$/{skip=1} !skip{print} /^--- SOURCE REQUIREMENT END ---$/{skip=0; getline}'`), while the brief still names a `Source requirement:`. `claude` is `2.1.314 (Claude Code)`, model `claude-opus-5-5`, run 2026-11-02.

## Results

```text
fulfils     requirement_fit: fulfils   decision: PASS   validator: {}
missing     requirement_fit: under     decision: FAIL   validator: {}
extra       requirement_fit: over      decision: PASS   validator: {}
supporting  requirement_fit: fulfils   decision: FAIL   validator: {}
noreq       requirement_fit: skipped   decision: PASS   validator: {}
```

| Pair | `requirement_fit` line (verbatim) | `decision` line (verbatim) | Answer key | Validator (`--raw`) | Session id | Cost / turns |
|---|---|---|---|---|---|---|
| `fulfils` | `requirement_fit: fulfils` | `decision: PASS` | `fulfils` — match | `{}` | `c5227822-7f26-4c90-86d0-871bcc9f5436` | $0.47 / 12 |
| `missing` | `requirement_fit: under` | `decision: FAIL` | `under` — match | `{}` | `489e5369-b615-4d42-bfb3-d72af5041bfe` | $0.31 / 11 |
| `extra` | `requirement_fit: over` | `decision: PASS` | `over` — match | `{}` | `a9e34255-69c0-4c8a-b6ff-15e9ebf70059` | $0.38 / 15 |
| `supporting` | `requirement_fit: fulfils` | `decision: FAIL` | `fulfils` — match | `{}` | `3dcd43b7-b123-4f18-a31f-7ad7e3a5c5e9` | $0.48 / 16 |
| `noreq` | `requirement_fit: skipped` | `decision: PASS` | `skipped` — match | `{}` | `afbab554-23b9-4cb1-9d99-fde3cfd5e7c6` | $0.39 / 13 |

**Verdict: PASS for Validation 3.** The four pairs rate `fulfils`, `under`, `over`, `fulfils`, as the key says.

- **`missing`** (A2): the reviewer named requirement AC3 (`/obsidian`) as `missing` in a HIGH `requirement_fit` issue, rated the brief `under`, and decided FAIL.
- **`extra`** (A3): it named Subtask 2 (troubleshooting sections) as `extra` in a MEDIUM `requirement_fit` issue, rated the brief `over`, and decided PASS, so Launch Pad refines it at its fix floor. It also mapped Subtask 3 (budgets, changelog fragment) as `supporting`.
- **`supporting`** (A5): it mapped the test subtask and the budgets/changelog subtask as `supporting`, raised no `requirement_fit` issue, and rated the brief `fulfils`.
- **`noreq`** (A8): it rated the brief `skipped` with one LOW `requirement_fit` note, never `fulfils`.
- **Mapping tables** (A4): every run printed a `### Requirement fit` table before its block, one row per requirement line and per brief unit.

**Decisions that come from other criteria, not from Criterion 22:**
- `supporting`'s FAIL comes from Criteria 4 and 5. Its test subtask reads the tables Subtask 1 writes but is LAUNCHABLE beside it, and without that parallel pair the `genuine-parallelism` split reason fails. The reviewer is right; this is a known limit of the fixture, now noted in its README. Its `requirement_fit` is still `fulfils`, and no `requirement_fit` issue is raised.
- The MEDIUM `touched_file_invariants` notes on several pairs are about the fixtures' own invariants entries (a template anchor, uncovered pins on `handoff.md` / `review-pr.md`). They are unrelated to Criterion 22.

**Honest limits:**
- One sample per pair. Model output varies, so this shows the prompt can produce these ratings, not that it always will.
- These `claude -p` runs have no SubagentStop retry, but all five blocks were valid on the first emission.
- A6 (a literal goal, so only the `extra` check runs) and A7 (a unit that delivers a requirement non-goal) were not run live. They are pinned only by the prompt text and its seam tests.
- The fixtures name a placeholder `Base commit` of all zeros. One run noted this as a LOW issue.

## Verbatim reviewer output

### `fulfils` — verbatim reviewer output

Plugin load (init event): `[{"name": "loomwright", "path": "<worktree>/loomwright", "source": "loomwright@inline", "version": "17.26.0"}]`

````text
### Requirement fit
| Direction | Line or unit | Maps to |
|---|---|---|
| requirement → brief | Goal: "can see on the command's own page what each exit code means" | Subtask 1 (AC1–AC3) |
| requirement → brief | AC1 "`## Exit codes` table on janitor.md" | Brief AC1 · `commands` group |
| requirement → brief | AC2 "`## Exit codes` table on handoff.md" | Brief AC2 · `commands` group |
| requirement → brief | AC3 "`## Exit codes` table on obsidian.md" | Brief AC3 · `commands` group |
| requirement → brief | AC4 "every code the script can return is in the table…" | Brief AC4 |
| requirement → brief | Validation 1 "`check-doc-currency.sh` passes" | Brief AC5 + `corpus-task: doc-currency-green` |
| requirement → brief | Non-goal "No change to any exit code, or to any script" | `respected` (no script is in the File Impact Map or `lanes:`) |
| requirement → brief | Non-goal "No `## Exit codes` section on any other command" | `respected` (only the three named command pages change) |
| brief → requirement | AC1 / AC2 / AC3 | Req AC1 / AC2 / AC3 |
| brief → requirement | AC4 | Req AC4 |
| brief → requirement | AC5 | Validation 1 |
| brief → requirement | Group `commands` (janitor.md, handoff.md, obsidian.md) | Req AC1–AC3 |
| brief → requirement | Group `budgets + release` (prompt-token-budgets.json, ARCHITECTURE_CONTRACTS.md mirror rows, changelog.d fragment) | `supporting` (budget and changelog upkeep) |

```markdown
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: PASS
  requirement_fit: fulfils
  issues:
    - severity: MEDIUM
      section: "Touched-file invariants"
      category: "touched_file_invariants"
      description: "18c: the entry for loomwright/docs/prompt-token-budgets.json quotes its anchor as a template, `{\"budget\": N, \"measured\": M, \"note\": \"…\"}`, with placeholder values. That string does not appear literally in the file. The real rows read, for example, `\"handoff\": {\"budget\": 1721, \"measured\": 1564, \"note\": ...}` (rows for handoff, janitor and obsidian at lines 74/76/78). The file exists and the named consumer exists at the root as `scripts/check-token-budget.sh`, which reads `.[$t][$k].budget` for `.commands` entries. So the entry is right in substance, but its anchor cannot be found with a literal grep."
      suggestion: "Quote a literal anchor that exists in the file, such as `\"janitor\": {\"budget\": 1470, \"measured\": 1336,`, or name the consumer's literal `'.[$t][$k].budget // \"null\"'` from scripts/check-token-budget.sh as the pin."
  summary: "Brief is sound; passes with one MEDIUM note. All 5 MODIFY paths exist (3 command pages, prompt-token-budgets.json, ARCHITECTURE_CONTRACTS.md). The CREATE parent changelog.d/ exists. All three scripts behind the commands exist (janitor-report.sh, build-handoff.sh, build-vault.sh), and the budget and mirror rows for the three commands exist (ARCHITECTURE_CONTRACTS.md lines 758/760/762). The single subtask is the default, so no Split reason is needed. Mode single-agent with Workers: 1 is consistent. Parallelism passes vacuously. The contract block has a `# Subtask 1` anchor; GATE PARSE reports parsed with provides_count 4, no warnings, and requires: []. The changelog fragment provide is valid because this subtask never runs the version bump. Every lanes: path resolves and there is no overlap. Skill agent-output exists. ACs are testable Given/When/Then, and AC4 matches the requirement's both-ways check. Module layout: ARCHITECTURE_CONTRACTS.md (1051 lines) is past the threshold but has its line count and a reason (it already owns the budget mirror rows), so no finding. Requirement fit is fulfils: all 4 requirement ACs and Validation 1 are covered, both non-goals are respected, and the budget and changelog work is supporting. Skipped because their trigger is absent: Criterion 11 (no Feasibility section), 13 (no Base Branch line), 14 (only a corpus-task bullet), 15 (no canonical-source claim), 17 (no APPLICABLE RULES block), 19 (no new enum value or test pin), 20 (no PR-body evidence)."
```
````

### `missing` — verbatim reviewer output

Plugin load (init event): `[{"name": "loomwright", "path": "<worktree>/loomwright", "source": "loomwright@inline", "version": "17.26.0"}]`

````text
### Requirement fit
| Direction | Line or unit | Maps to |
|---|---|---|
| requirement → brief | Goal "A user of `/janitor`, `/handoff` or `/obsidian` can see…" | Partly covered: AC1 and AC2 cover janitor and handoff · `/obsidian` is `missing` |
| requirement → brief | AC1 "`## Exit codes` table on janitor.md" | Brief AC1 + `commands` group |
| requirement → brief | AC2 "`## Exit codes` table on handoff.md" | Brief AC2 + `commands` group |
| requirement → brief | AC3 "`## Exit codes` table on obsidian.md" | `missing` (no brief AC, File Impact Map row or lane names `loomwright/commands/obsidian.md`) |
| requirement → brief | AC4 "any of the three tables… every code the script can return" | Brief AC3, but only for two of the three tables · the obsidian part is `missing` |
| requirement → brief | Validation 1 "`bash scripts/check-doc-currency.sh` passes" | Brief AC4 + `corpus-task: doc-currency-green` |
| requirement → brief | (non-goal) "No change to any exit code, or to any script" | `respected` (no script in File Impact Map or lanes) |
| requirement → brief | (non-goal) "No `## Exit codes` section on any other command" | `respected` |
| brief → requirement | AC1 (janitor table) | Req AC1 |
| brief → requirement | AC2 (handoff table) | Req AC2 |
| brief → requirement | AC3 (table vs. script `exit` statements) | Req AC4 |
| brief → requirement | AC4 (doc-currency passes) | Validation 1 |
| brief → requirement | Group "commands" (janitor.md, handoff.md) | Req AC1, AC2 |
| brief → requirement | Group "budgets + release" (token budgets, ARCHITECTURE_CONTRACTS mirror rows, changelog fragment) | `supporting` |

```markdown
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: FAIL
  requirement_fit: under
  issues:
    - severity: HIGH
      section: "Task / Acceptance Criteria / File Impact Map"
      category: "requirement_fit"
      description: "The requirement's AC3 is not covered: \"Given `loomwright/commands/obsidian.md`, when a user reads it, then an `## Exit codes` table lists each exit code `/obsidian` can return and what it means.\" Its Goal also names `/obsidian` (\"A user of `/janitor`, `/handoff` or `/obsidian` can see…\"), and its AC4 covers \"any of the three tables\". The brief's Goal, ACs, File Impact Map and lanes cover only janitor and handoff. Checked: `loomwright/commands/obsidian.md` exists (Glob), and it has its own budget row (`\"obsidian\": {\"budget\": 1518, \"measured\": 1380, …}` at line 78 of prompt-token-budgets.json). So the brief left it out; the file is not missing. Dropping obsidian is not one of the requirement's non-goals."
      suggestion: "Add `/obsidian`. Add a brief AC for `loomwright/commands/obsidian.md`'s `## Exit codes` table. Extend brief AC3 to all three tables, compared with the script `/obsidian` runs. Add obsidian.md to the `commands` group of the File Impact Map with its line count, plus a `provides` symbol entry and a `lanes:` entry. Add the `obsidian` row to the Touched-file invariants entry and to the budgets work (JSON plus the ARCHITECTURE_CONTRACTS mirror row). Update the Goal and title to say three commands."
    - severity: LOW
      section: "Acceptance Criteria"
      category: "requirement_fit"
      description: "Brief AC3 checks each table against \"the `exit` statements of the script\". The requirement's AC4 is wider: \"every code the script can return\". `janitor-report.sh` has no literal `exit <N>` statement: a Grep for `exit [0-9]+` matched only build-handoff.sh (6 hits). Its exit status therefore comes from function returns or the last command's status, and a check limited to `exit` statements could miss codes."
      suggestion: "Reword AC3 as \"every exit status the script can return (explicit `exit N`, the status of the final command or function, and `set -e` aborts), and no status it never returns\". This matches the requirement's AC4."
  summary: "FAIL on Criterion 22: the requirement asks for exit-code tables on three commands (janitor, handoff, obsidian), and the brief covers only two. Requirement AC3 (obsidian) is missing, and requirement AC4 is only partly covered. The rest of the brief is sound. All 4 modify paths exist, and the create path's parent `changelog.d/` exists. The `janitor`/`handoff` budget rows exist in prompt-token-budgets.json (lines 74 and 76) and in the ARCHITECTURE_CONTRACTS.md mirror table (lines 758 and 760). The single-subtask decomposition needs no Split reason, and parallelism passes trivially because there is only one subtask. Mode, worker count and the reduced Parallelism form are correct. The contract block has a `# Subtask 1` anchor, and GATE PARSE reports parsed with provides_count 3 and no parse_warnings. The changelog fragment is never folded into CHANGELOG.md, because no version-bump step runs. Every lane resolves, and there is no lane overlap. The `agent-output` skill exists. Executable Acceptance has only a `corpus-task:` bullet, so no stamp is needed. The Touched-file invariants entry names a real file and a real pinning script (`scripts/check-token-budget.sh`). ARCHITECTURE_CONTRACTS.md (1051 lines) has its line count recorded, and the edit extends budget mirror rows that file already owns, so it is not a module-layout finding. Skipped: Criteria 11 (no Feasibility section), 13 (no Base Branch line), 15 (no canonical-source claim), 17 (no APPLICABLE RULES block), 19 (no new enum value or pin) and 20 (no criterion relies on the PR body as evidence). Criterion 18 ran because the budgets JSON is pinned by a CI script; it found nothing. Fix: add /obsidian everywhere."
```
````

### `extra` — verbatim reviewer output

Plugin load (init event): `[{"name": "loomwright", "path": "<worktree>/loomwright", "source": "loomwright@inline", "version": "17.26.0"}]`

````text
Checks done: all paths exist, the contract blocks parse, and two test pins need a note. Writing up the review now.

### Requirement fit
| Direction | Line or unit | Maps to |
|---|---|---|
| requirement → brief | Goal "can see on the command's own page what each exit code means" | Subtask 1 |
| requirement → brief | AC1 "`janitor.md` … `## Exit codes` table" | Subtask 1 |
| requirement → brief | AC2 "`handoff.md` … `## Exit codes` table" | Subtask 1 |
| requirement → brief | AC3 "`obsidian.md` … `## Exit codes` table" | Subtask 1 |
| requirement → brief | AC4 "every code the script can return is in the table…" | Subtask 1 (brief AC4) |
| requirement → brief | Validation 1 "`bash scripts/check-doc-currency.sh` passes" | Subtask 3 (brief AC6 + `corpus-task: doc-currency-green`) |
| requirement → brief | (non-goal) "No change to any exit code, or to any script" | `respected` |
| requirement → brief | (non-goal) "No `## Exit codes` section on any other command" | `respected` (Subtask 2 adds `## Troubleshooting`, not `## Exit codes`) |
| brief → requirement | Subtask 1 "Exit-code tables on three command pages" | AC1–AC4 |
| brief → requirement | Subtask 2 "Troubleshooting sections on three command pages" | `extra` (no requirement line covers `/review-pr`, `/backlog` or `/pr-postmortem` troubleshooting) |
| brief → requirement | Subtask 3 "Budgets and changelog fragment" | `supporting` (also carries Validation 1) |

PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: PASS
  requirement_fit: over
  issues:
    - severity: MEDIUM
      section: "Task / Subtask Structure"
      category: "requirement_fit"
      description: "Subtask 2 'Troubleshooting sections on three command pages' (brief AC5, and the second half of the brief's Goal: '`/review-pr`, `/backlog` and `/pr-postmortem` each gain a `## Troubleshooting` section…') serves no line of the source requirement. The requirement's Goal, AC1–AC4 and Validation cover only the exit-code tables for /janitor, /handoff and /obsidian. It is not a non-goal violation, because the non-goal forbids `## Exit codes` on other commands, not `## Troubleshooting`. Knock-on effects: Subtask 2 is the only reason the brief has more than one parallel group. Without it, `Split reason: genuine-parallelism` no longer holds (one group of 3 files), and the brief would go back to the default single subtask. Subtask 3's budget rows also grow from three to six."
      suggestion: "Remove Subtask 2, AC5 and the Troubleshooting clause from the Goal. Drop review-pr.md, backlog.md and pr-postmortem.md from the File Impact Map and the budget rows. Collapse to a single-subtask brief (Mode: single-agent, Workers: 1, no Split reason). If the Troubleshooting work is wanted, give it its own requirement file."
    - severity: MEDIUM
      section: "Touched-file invariants"
      category: "touched_file_invariants"
      description: "18b coverage: two of the modified command pages are pinned by tests, and the `## Touched-file invariants` section has no entry for either. Its only entry is `loomwright/docs/prompt-token-budgets.json`, which is grounded: the `\"budget\"`/`\"measured\"` row shape is present at lines 17–86 and `scripts/check-token-budget.sh` exists. The uncovered pins: `loomwright/scripts/test-build-handoff.sh` check (p) reads `commands/handoff.md` and requires it to mention `--publish`. `loomwright/scripts/test-review-heal-next-step.sh` pins about 17 verbatim lines of `commands/review-pr.md` (RH-292…RH-308, e.g. `## Parameters`, `## What This Does`, `**PASS** → done. The diff is clean. **Does NOT merge**`). `test-loop-inventory.sh` also lists review-pr.md."
      suggestion: "Add an entry for `loomwright/commands/handoff.md`: keep the `--publish` mention, pinned by `test-build-handoff.sh` (p). Add one for `loomwright/commands/review-pr.md`: keep every RH-292…RH-308 anchor line verbatim and only add sections, pinned by `test-review-heal-next-step.sh`. If Subtask 2 is removed per the issue above, only the handoff.md entry is needed."
  summary: "Decision PASS, requirement_fit `over`. Two MEDIUM findings, neither blocks the save. Checked: all 8 MODIFY paths exist (Glob), the changelog.d/ parent exists, the agent-output skill exists, and the contract blocks parse (GATE PARSE 3/3/2). The dependency graph has no cycles; Subtask 3 is correctly BLOCKED by #1 and #2, and the LAUNCHABLE pair #1/#2 shares no files or lanes. Workers 2 equals the largest batch width; Mode parallel is correct. The Split reason's file counts (3+3) hold as written. ARCHITECTURE_CONTRACTS.md (1051 lines) carries its line count and a one-line reason (budget mirror rows it already owns), so Criterion 21 has no finding. Executable Acceptance is corpus-task only, and doc-currency-green exists in eval-corpus. Skipped as not applicable: Criteria 11, 13, 14 (no cmd bullets), 15, 17 (no rules block), 19 and 20. Main finding: Subtask 2 (Troubleshooting for /review-pr, /backlog, /pr-postmortem) is scope the source requirement never asks for. Removing it would also make this the default single-subtask brief. Second finding: the touched-file invariants miss the test pins on handoff.md and review-pr.md."
````

### `supporting` — verbatim reviewer output

Plugin load (init event): `[{"name": "loomwright", "path": "<worktree>/loomwright", "source": "loomwright@inline", "version": "17.26.0"}]`

````text
I've checked every path and the three scripts; here is the review.

## Plan review: exit-code tables for /janitor, /handoff and /obsidian

**Decision: FAIL.** Subtask 2 can't pass its own acceptance criterion without Subtask 1's tables, yet the brief runs the two in parallel. That missing dependency is the only reason given for splitting the work. One subtask would fix it.

### What I checked
- **Files:** All six files to modify exist, and so do the parent folders for the four new files (`loomwright/scripts/`, `loomwright/scripts/fixtures/`, `changelog.d/`). The recorded line counts look plausible, and the three budget rows are in both `prompt-token-budgets.json` (lines 74, 76, 78) and `ARCHITECTURE_CONTRACTS.md` (lines 758, 760, 762).
- **Skills:** `agent-output` and `unit-testing` both exist.
- **Scripts:**
  - `build-handoff.sh` and `build-vault.sh` contain only literal `exit 0` statements.
  - `janitor-report.sh` ends with `jr_act "$@"; exit $?` and `jr_report "$@"; exit $?`. Its exit code `2` comes from `return 2` inside those functions (lines 884–891 and 952–954). Its header says "ALWAYS exits 0 … a usage error exits 2."
- **Contract blocks:** All three parse cleanly, each `requires` matches a sibling's `provides`, there are no cycles, and the lanes don't overlap.
- **Requirement fit:** The brief matches the requirement. Nothing is missing and nothing extra is added.
- **Criteria not applicable:** 11, 13, 14, 15, 17 and 20 don't apply here. 14 is skipped because the only acceptance bullet is a `corpus-task:`.
- **File size:** Criterion 21 isn't a finding. `ARCHITECTURE_CONTRACTS.md` has 1051 lines, but the brief only updates budget rows that file already holds, and says why.

### Requirement fit
| Direction | Line or unit | Maps to |
|---|---|---|
| requirement → brief | Goal "see on the command's own page what each exit code means" | Subtask 1 |
| requirement → brief | AC1 "janitor.md … `## Exit codes` table" | Subtask 1 (brief AC1) |
| requirement → brief | AC2 "handoff.md … `## Exit codes` table" | Subtask 1 (brief AC2) |
| requirement → brief | AC3 "obsidian.md … `## Exit codes` table" | Subtask 1 (brief AC3) |
| requirement → brief | AC4 "every code the script can return is in the table" | Subtask 1 (brief AC4; the wording is narrower, see the MEDIUM issue) |
| requirement → brief | Validation 1 "`check-doc-currency.sh` passes" | Subtask 1 (brief AC5 + `corpus-task: doc-currency-green`) |
| requirement → brief | (non-goal) "No change to any exit code, or to any script" | `respected` (only new files under `test-*`/fixtures) |
| requirement → brief | (non-goal) "No `## Exit codes` section on any other command" | `respected` (lanes cover only the three pages) |
| brief → requirement | Subtask 1 "Exit-code tables on three command pages" | AC1–AC4, Goal, Validation 1 |
| brief → requirement | Subtask 2 "Test for the exit-code tables" | `supporting` (test for AC4) |
| brief → requirement | Subtask 3 "Budgets and changelog fragment" | `supporting` (budget + changelog fragment) |

```markdown
PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: FAIL
  requirement_fit: fulfils
  issues:
    - severity: HIGH
      section: "Parallelism Analysis"
      description: "Criterion 5 — missing dependency. Subtask 2 (LAUNCHABLE, Batch 1) owns AC6: `bash loomwright/scripts/test-command-exit-codes.sh` passes, and fails when a table row is deleted. That test reads the `## Exit codes` tables in janitor.md, handoff.md and obsidian.md. Grep shows those tables do not exist at base; Subtask 1 creates them. Subtask 2's worker cannot satisfy AC6 in its own worktree, and the brief's own Risk Assessment admits it ('it is run against the merged result in Batch 2'). The per-subtask gate is outputs_verified + tests, so Subtask 2 checkpoints with a red test or a test it never ran green. Its contract says `requires: []`, though it really consumes Subtask 1's three `## Exit codes` symbols."
      suggestion: "Make Subtask 2 BLOCKED (by #1), with `requires` entries for the three `## Exit codes` symbols. Better: see the next issue and collapse to one subtask."
    - severity: HIGH
      section: "Configuration"
      description: "Criterion 4 — the Split reason fails once the dependency is fixed. `genuine-parallelism` needs at least 2 zero-overlap groups that can run in parallel, each with 3 or more files. Only the Subtask 1 + Subtask 2 pair qualifies, and Subtask 2 really depends on Subtask 1 (issue above). That leaves the chain 1 → 2 and 1 → 3 with no genuine parallelism. `context-bound` does not apply either: about 9 files in total (3 modify + 3 create + 2 modify + 1 create), well under 12, and no stated change over 800 lines. `file-conflict` does not apply: the overlap matrix shows no shared file."
      suggestion: "Collapse to one subtask: `Mode: single-agent`, `Workers: 1`, no `Split reason:` line. Use one contract block that merges all provides and lanes, with `requires: []`. The worker writes the tables, then the test, then re-measures the budgets and writes the changelog fragment, in order."
    - severity: MEDIUM
      section: "Acceptance Criteria"
      description: "Criterion 3 — AC4 is narrower than the requirement. The brief says 'when it is compared with the `exit` statements of the script'. The requirement's AC4 says 'every code the script can return'. janitor-report.sh has no literal `exit N`: it ends with `exit $?` (lines 969–970), and its code `2` comes from `return 2` inside jr_act and jr_report (lines 884–891 and 952–954; the header at lines 15 and 146–147 says 'a usage error exits 2'). A test written to the brief's wording, by scanning `exit` statements, finds no codes for /janitor. It would also miss the `0` row there, or flag it as unreachable. The only Pin mutations row ('delete the `0` row' in handoff.md) never exercises this case."
      suggestion: "Reword AC4 to the requirement's form ('every code the script can return, including codes returned by functions that the final `exit $?` passes through'). Have the test take each script's code set from the header's documented codes or from the fixture `scripts.tsv`, not from a grep for `exit`. Add a Pin mutations row: 'delete the `2` row of the `## Exit codes` table in `loomwright/commands/janitor.md`'."
    - severity: MEDIUM
      section: "Subtask Contracts"
      description: "Criterion 12 — Subtask 3's contract is incomplete and partly vacuous. It re-measures all three command pages but `requires` only janitor.md's `## Exit codes`; handoff.md and obsidian.md are not listed. Its provide `{kind: symbol, path: prompt-token-budgets.json, name: janitor}` names a key that already exists at base (line 76: `\"janitor\": {\"budget\": 1470, \"measured\": 1336, …}`). The outputs_verified gate therefore passes even if the subtask does nothing."
      suggestion: "Require all three `## Exit codes` symbols. For the budget output, name something that only exists after the change (e.g. the changelog fragment, which is already a provide), or drop the vacuous symbol. This goes away if the brief collapses to one subtask."
    - severity: MEDIUM
      section: "Touched-file invariants"
      category: "touched_file_invariants"
      description: "Criterion 18b — the three changed command pages have no entry. `loomwright/commands/janitor.md`, `handoff.md` and `obsidian.md` are measured by `scripts/check-token-budget.sh` against their `.commands` budget rows (fail-closed). They also get a table that the new test pins. The only entry covers prompt-token-budgets.json. Its anchor, `{\"budget\": N, \"measured\": M, \"note\": \"…\"}`, is a template, not a literal; the backticked `janitor`/`handoff`/`obsidian`/`.commands` literals do appear in the file."
      suggestion: "Add one entry per command page: keep the existing sections (e.g. janitor.md's §'What it does' steps, which ARCHITECTURE_CONTRACTS.md line 829 cites), add only `## Exit codes`; pinned by `scripts/check-token-budget.sh` and `loomwright/scripts/test-command-exit-codes.sh`."
  summary: "FAIL on two linked HIGH issues. (1) Subtask 2 is LAUNCHABLE in parallel with Subtask 1, but its own AC6 (the new test passes) needs Subtask 1's tables, which do not exist at base. (2) With that dependency fixed, the `genuine-parallelism` split reason no longer holds: about 9 files in total, under the context-bound limit, no file conflict. Recommend collapsing to a single-agent, one-subtask brief. Also MEDIUM: AC4's 'exit statements' wording would miss janitor-report.sh's code 2, which comes from `return 2` via `exit $?`; Subtask 3's contract requires only janitor's table and its budget-key provide already exists at base; the touched-file invariants have no entries for the three command pages. All file paths, skills and lanes check out; the gate parse is clean. The brief covers every requirement AC, the Validation entry and both non-goals, so requirement_fit is fulfils."
```
````

### `noreq` — verbatim reviewer output

Plugin load (init event): `[{"name": "loomwright", "path": "<worktree>/loomwright", "source": "loomwright@inline", "version": "17.26.0"}]`

````text
### Requirement fit
| Direction | Line or unit | Maps to |
|---|---|---|
| requirement → brief | (coverage half not run: no `--- SOURCE REQUIREMENT ---` block was pasted, though `## Environment` names `.supervisor/requirements/fixture-small-commands-exit-codes.md`) | `skipped` |
| brief → requirement | AC1 "`## Exit codes` table on janitor.md" | Goal (janitor) |
| brief → requirement | AC2 "`## Exit codes` table on handoff.md" | Goal (handoff) |
| brief → requirement | AC3 "`## Exit codes` table on obsidian.md" | Goal (obsidian) |
| brief → requirement | AC4 "every reachable code is listed and no unreachable one is" | Goal ("matching the script it runs") |
| brief → requirement | AC5 "`check-doc-currency.sh` passes" | `supporting` |
| brief → requirement | FIM group "commands" (3 command pages) | Goal |
| brief → requirement | FIM group "budgets + release" (token budgets, ARCHITECTURE_CONTRACTS mirror, changelog fragment) | `supporting` |
| brief → requirement | Non-goal "no exit code or script changes" | `respected` (no `scripts/*.sh` in File Impact Map or lanes) |
| brief → requirement | Non-goal "no `## Exit codes` on any other command" | `respected` (only the 3 pages are touched) |

PLAN_REVIEW_RESULT:
  schema_version: 1
  decision: PASS
  requirement_fit: skipped
  issues:
    - severity: MEDIUM
      section: "Touched-file invariants"
      category: "touched_file_invariants"
      description: "18b: the brief modifies `loomwright/commands/handoff.md`, and a test pins that file. `loomwright/scripts/test-build-handoff.sh` case (p) runs `grep -qF -- \"--publish\" \"$HANDOFF_MD\"` and fails on 'mirror drift'. The `## Touched-file invariants` section has an entry only for `prompt-token-budgets.json`, so this pinned file is not covered."
      suggestion: "Add an entry for `loomwright/commands/handoff.md`: keep the `--publish` mention (both `build-handoff.sh` invocation lines); pinned by `loomwright/scripts/test-build-handoff.sh` case (p)."
    - severity: LOW
      section: "Environment"
      category: "requirement_fit"
      description: "The coverage half of Criterion 22 could not run. `## Environment` names `Source requirement: .supervisor/requirements/fixture-small-commands-exit-codes.md`, but the spawn prompt carried no `--- SOURCE REQUIREMENT ---` block. The extra/non-goal half was run against the brief's own Goal and Non-goals and found no `extra` unit."
      suggestion: "Launch Pad should paste the requirement file between the SOURCE REQUIREMENT markers so missing requirement lines can be checked."
    - severity: LOW
      section: "Environment"
      description: "`Base commit` is all zeros (`0000…0000`), which does not resolve to a real commit. The line counts in the File Impact Map are said to be 'at base', so they cannot be tied to a commit. The live files do match the counts: obsidian.md content reaches line 61, and the other two are consistent."
      suggestion: "Record the real base SHA, or add a `Base Branch:` line in `## Configuration`."
  summary: "Brief is sound, with one MEDIUM gap. Criterion 1: all 5 MODIFY paths exist (3 command pages, prompt-token-budgets.json, ARCHITECTURE_CONTRACTS.md), and the create target's parent `changelog.d/` exists. Each page runs the script the brief names (janitor-report.sh, build-handoff.sh, build-vault.sh). Criterion 2: the budget rows for janitor/handoff/obsidian exist under `.commands` (JSON lines 74–78), with mirror rows at ARCHITECTURE_CONTRACTS lines 758–762, so the approach matches CLAUDE.md. Criterion 3: ACs are Given/When/Then and testable; no Outcomes Rubric. Criteria 4–6 and 10: 1 subtask, single-agent, Workers 1, so no Split reason is needed and parallelism passes vacuously. Criterion 7: skill `agent-output` exists. Criteria 8–9: risks and all required sections are present. Criterion 12: the contract block is anchored `# Subtask 1`; GATE PARSE shows parsed with provides_count 4 and no warnings; requires is empty; the changelog fragment is fine in provides because the subtask runs no version bump. Criterion 14: only a `corpus-task:` bullet, so no stamp is needed. Criterion 16: lanes are declared and resolve; there is no same-wave pair. Criterion 18: the budgets entry is grounded (`.commands` is in check-token-budget.sh), but handoff.md, which test-build-handoff.sh pins, has no entry (MEDIUM). Criterion 21: ARCHITECTURE_CONTRACTS.md (1051 lines) is past the 500 threshold, but the change extends budget mirror rows the file already owns, with the reason stated, so this is not a finding. Criterion 22: rating `skipped` because the requirement block is absent; no extra or non-goal units. Criteria 11, 13, 15, 17, 19 and 20 do not apply. No BLOCKING or HIGH issues."
````

