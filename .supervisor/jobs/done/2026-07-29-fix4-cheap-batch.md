# Supervisor Job: Fix 4 cheap verified batch — 4a + 4b + 4e (4d dropped on a falsified premise)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — v15.16.0 banner matches `plugin.json`)
- **Git:** clean, branch `main` @ `2bef2d9` (PR #116 merge commit, verified via `git branch --contains`)
- **GitHub CLI:** ✓ Authenticated (`vikashruhilgit`)
- **Worktrees:** none
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** `.supervisor/requirements/final-state/03-fix4-cheap-batch.md`

## Feasibility

Phase 2.5 = **CAUTION** (proceeding). Three grounded findings; the first removes a quarter of the
stated scope.

### F1 — 4d's premise is falsified (measured, not argued). The split is DROPPED.

The requirement states: *"`self-heal-advisory/SKILL.md` is 110,714 bytes / 1,015 lines; Phase 4.5
needs only Part 2 (starts ~line 508) and reads the whole file per heal iteration."* Every clause of
that is wrong or overstated:

| Claim | Measured reality |
|---|---|
| "Phase 4.5 needs only Part 2" | Part 2 invokes **all ten** Part 1 sections. Part 2 steps 1c/1d/1e each read *"run the … step from **Part 1** of this skill"* verbatim, and Part 2 calls back again at §"System Twin advisory checks" (*"protocol in Part 1 of this skill"*), §"Contract builder", §"Advisory Twin delta line", and §"Hard-signal dual emission". Part 1's ten sections are §Prior-churn advisory, §Area-knowledge advisory, §House-rules advisory, §Post-review advisory checks, §Contract-conformance check, §Benchmark run, §Ground-truth execution, §Contract builder (WRITE path), §Advisory Twin delta line, §Hard-signal dual emission. There is no Part 1 material Phase 4.5 does not use. |
| "reads the whole file **per heal iteration**" | The Read is **once at phase entry** — `agents/supervisor.md` Phase 4.5 §"Protocol authority (read at phase entry)", corroborated by Part 2 step 1a. Not per iteration. |
| "110,714 bytes / 1,015 lines" | Line count actual: **1,014**. Byte figures must be **re-derived with `wc -c` at write time** (see ST-4) rather than copied from here. |
| implied saving | Part 2 is roughly two-thirds of the file, so even a clean split saves a minority of *one* read. |

> **Citation convention for this brief and for ST-4's durable record:** cite **section names, not
> absolute line numbers**, inside `self-heal-advisory/SKILL.md`. It is a 1,014-line file under
> active edit; the repo's own "absolute line-ref drift in prose edits" lesson applies, and a spike
> record pinned to line numbers re-stales on the next commit. (An earlier draft of this brief
> carried four wrong line numbers for exactly this reason — the section names were right.)

Consequence: the source AC *"Phase 4.5 reads only Part 2 post-split (verified by the Read call
sites)"* is **not satisfiable** without also moving the Part 1 procedures Part 2 calls — which is
the split undone.

### F2 — the 4d → 4f ordering dependency does not exist either

The spike orders 4f (item 07) *"strictly after 4d — routing an unsplit 110,714-byte skill changes
when it is paid, not how much"* (`EVAL_FINDINGS_AND_FIXES.md:316`). That models
`self-heal-advisory` as a 4f routing target. **It is not one.** `agents/supervisor.md:10-17` shows
`supervisor-runner` preloads exactly seven skills — `workflow-management`, `async-orchestration`,
`state-management`, `context-summarization`, `supervisor-readiness`, `commit`, `quality-checklist`.
`self-heal-advisory` is **absent**; it is already read-on-demand on *both* the agent and inline
paths (the spike's own 4f table puts it in the "Read on demand" column for both). 4f's real
double-pay is `async-orchestration` at 9,078 proxy tokens.

So dropping 4d **does not strand 4f or item 07** — but the false ordering must be corrected in the
docs, or item 07 will start from a dead precondition. That correction is **Subtask 4** of this
brief.

### F3 — 4e is sound but has two hard constraints

- **No PyYAML.** `python3 -c "import yaml"` fails on this machine (macOS system Python **3.9.6**).
  The template validator (`validate-launch-pad-result.py`) documents this and hand-parses four flat
  scalar fields. But `WORKER_RESULT` carries `outputs_verified` (array of objects with
  `kind`/`path`/`name`/`status`) and `EXECUTE_RESULT`/`EXECUTE_CHECKPOINT` carry
  `subtasks_completed`/`worktrees`/`merge_order` arrays — a strictly harder parse than the template.
  **Resolution (user decision):** ONE shared parser module + five thin per-schema validators, so the
  nested-YAML-subset parser is written, hardened and self-tested **once**.
- **Hook edits cannot be shown firing in-PR.** Re-verified this session: the installed plugin at
  `~/.claude/plugins/cache/atelier/loomwright/15.16.0` is a **copy, not a symlink** (different
  inodes for `hooks/hooks.json`; identical content). A PR editing `loomwright/hooks/hooks.json` does
  not take effect until reinstall. Self-tests over fixtures ARE producible; a live "the converted
  hook fired" count is NOT. Same limitation item 02 hit and recorded.

### Scope deviations from the source requirement (deliberate, justified — do NOT "fix" back)

1. **4d (split `self-heal-advisory`) is REMOVED from scope** — premise falsified per F1. Replaced by
   Subtask 4, which corrects the false claim rather than acting on it.
2. **The requirement's "five validator scripts modelled on validate-launch-pad-result.py" becomes
   one shared parser module + five thin validators** (F3, user decision). The *modelled-on*
   contract still holds: exit-0-by-contract, decide via stdout JSON, same payload-extraction ladder.
3. **`## Status` note appended to the source requirement file** recording (1) and its reasoning, so
   the dropped sub-fix is auditable rather than silently lost.

### Expected rubric score: 3/4 (not a defect)

The `## Outcomes Rubric` below is copied **verbatim** from the source requirement per the
preserve-verbatim contract. Item 3 — *"4d split landed, all readers + gates synced"* — will FAIL,
**by decision, on falsified-premise grounds** (F1/F2, user-confirmed). Do **not** reword the rubric
to manufacture a 4/4; the yardstick stays as its author wrote it. Same convention item 02 used for
its item 4.

## Task

**Goal:** Land the three surviving Fix 4 sub-fixes — leaf turn-budget visibility (4a), a Phase 4.5
anti-overlap rule (4b), and the conversion of five mechanical `type: prompt` SubagentStop hooks to
deterministic `type: command` validator scripts (4e) — and correct the two falsified spike claims
that 4d rested on, so item 07 inherits a true premise.

### What 4e actually removes

Five model calls per qualifying run, each carrying the finishing agent's transcript at a 30s
timeout, replaced by zero-token scripts. The five and what they assert (verbatim from
`hooks/hooks.json`, all mechanical — presence, type, enum membership, cross-field invariants):

| Matcher | Result block | Nature of checks |
|---|---|---|
| `SubagentStop[worker]` | `WORKER_RESULT` v1/v2 | 8 numbered rules; nested `outputs_verified` entry shape; `outputs_gap`/`status` cross-field invariant; destructive-command scan |
| `SubagentStop[execute-manager]` | `EXECUTE_RESULT` \| `EXECUTE_CHECKPOINT` | 6 rules; `toolset_gap` rejection; bidirectional all-or-nothing adjudication tri-field |
| `SubagentStop[supervisor-runner]` | `SUPERVISOR_RESULT` v1 | 13 rules; `heal_*` cross-field matrix; `rubric_score` `"N/M"` format |
| `SubagentStop[qa-executor]` | `QA_RESULT` v1 | 5 rules; integer counts; status enum |
| `SubagentStop[plan-reviewer]` | `PLAN_REVIEW_RESULT` v1 | 6 rules; decision enum; FAIL⇒BLOCKING/HIGH issue |

**The `code-reviewer` prompt hook is LEFT IN PLACE** — explicitly out of scope per the requirement
(*"unless its logic is deliberately ported and tested"*). It runs cross-field + severity-cap logic
richer than presence-checking. Post-change it is the **one remaining prompt validator** on a
SubagentStop matcher; every doc surface that says "6 prompt validators" must say so.

**Hook count is UNCHANGED at 24.** These are type conversions, not additions.

## Acceptance Criteria

- [ ] **AC-1 (4a):** `agents/worker.md` and `agents/code-reviewer.md` each state their own turn
      budget (both are `maxTurns: 40`) in prose the agent actually reads, **with the honesty caveat
      stated**: advisory, ~90% adherence, do not expect behavior change.
- [ ] **AC-2 (4b):** `skills/self-heal-advisory/SKILL.md` Part 2's review-and-fix loop carries one
      anti-overlap rule — do not re-derive what a prior gate already found.
- [ ] **AC-3 (4e substrate):** a shared parser module plus five per-schema validators exist under
      `loomwright/scripts/`, each **exit-0-by-contract**, deciding via stdout `{"ok": true}` /
      `{"ok": false, "reason": "..."}`, reusing the template's payload-extraction ladder
      (`last_assistant_message` → `result_block` → `output` → `agent_output` →
      `agent_transcript_path` → `transcript_path`).
- [ ] **AC-4 (4e tests):** every new script has a self-test covering, **per schema**, at minimum:
      valid block; **missing block**; **malformed/unparseable payload**; **missing required key**;
      **explicit-null required key** (the nullable-vs-absent lesson — assert key *presence*, not
      just truthiness); and at least one **cross-field invariant violation**. Falsify, do not merely
      confirm.
- [ ] **AC-5 (4e wiring):** the five `type: prompt` entries in `hooks/hooks.json` are replaced by
      `type: command` entries carrying `|| true` per the convention (valid **only** because these
      are exit-0-by-contract validators, exactly like `validate-launch-pad-result.py`); the
      `code-reviewer` prompt entry is byte-unchanged; total hook count stays **24**.
- [ ] **AC-6 (mirrors):** the inert `~/.claude/agents/`-compat frontmatter `hooks:` blocks in
      `agents/worker.md` and `agents/execute-manager.md` are converted in the same change (their own
      NOTE comments say "keep the two in sync"). `agents/code-reviewer.md`'s frontmatter block is a
      `Stop` hook, not one of the five — leave it.
- [ ] **AC-6b (contract-parity gate survives the conversion):** `scripts/check-contract-parity.sh`
      still enforces its pin-drift guard after the five prompts are deleted, and exits 0.
      **This is not optional doc-sync — the gate breaks CI without it** (see R0). Its
      `hook_prompt()` helper selects `hk.get("type")=="prompt"` and an empty result is a hard
      `pin-drift` error, so six of its seven MANIFEST rows (worker, execute-manager ×2, qa-executor,
      supervisor-runner, plan-reviewer) would error out; only `code-reviewer` survives. **Chosen
      repair — preserve the guard's intent, do not weaken it:** extend the helper so that when a
      matcher has no `type: prompt` hook, it resolves the matcher's validator command entry,
      extracts the referenced script path, and returns **that script's source** as the rule text —
      the runtime rule source moved from a prompt string into a `.py` file, so the guard should
      grep the `.py`. Field names must therefore appear literally in each validator's source (they
      will, as dict keys / constants).

      **Selection rule (LOAD-BEARING — an ambiguous rule fails OPEN and silently guts the gate):**
      three of the five affected matchers carry MORE THAN ONE `type: command` entry after the
      conversion — `loomwright:worker` also has `emit-progress-event.sh`, `loomwright:qa-executor`
      also has the telemetry fan-out, and `loomwright:supervisor-runner` has **both** the telemetry
      fan-out and `send-webhook.sh`. So "the matcher's command entry" is not well defined, and the
      naive readings are both wrong: concatenating every command entry's source fails **OPEN**
      (`send-telemetry-core.sh` alone mentions `pr_url` / `heal_decision` / `heal_loop_ran` /
      `summary` / `schema_version`, so a pin-drift grep would pass on a field the real validator
      dropped), while taking the first entry fails CLOSED with spurious red CI and couples the gate
      to hook ordering that nothing asserts. **Required rule:** select the command entry whose
      command string references `validate-<x>-result.py`, and **hard-error as `pin-drift` when zero
      or more than one entry matches** — never fall through to an unrelated script.

      Also verify check 1(b) still passes: it greps the AGENT `.md` for each pinned field, and AC-6
      deletes frontmatter prompt text from `worker.md` / `execute-manager.md` — confirm no pinned
      field loses its last occurrence in those files rather than assuming it.
- [ ] **AC-6c (the gate repair is itself falsifiably tested):** `loomwright/scripts/test-check-contract-parity.sh`
      covers the new fallback branch. **Today it cannot:** its `make_fixture()` synthesizes a
      `hooks.json` in which every matcher carries a `type: prompt` hook, so the new branch receives
      **zero** fixture coverage, and the only thing exercising it would be the "real repo tree
      passes" case — a one-directional green check that a fail-OPEN implementation satisfies just
      as happily as a correct one. AC-4 demands falsification-not-confirmation of the five new
      validators; the gate that keeps CI alive gets the same standard. Add fixtures asserting:
      (a) a matcher with no prompt hook and one validator command hook selects the right source AND
      still fires `pin-drift` when a pinned field is removed from that source; (b) a matcher whose
      only command entries are unrelated scripts **errors** rather than silently passing;
      (c) a matcher with two validator-matching command entries errors (the >1 case).
- [ ] **AC-7 (doc correction):** the falsified 4d premise and the void 4d→4f ordering are corrected
      at all four surfaces (Subtask 4 table), with the measured figures recorded.
- [ ] **AC-8 (gates):** all **seven** repo-root gates pass — enumerated from disk, not memory:
      `check-command-sync.sh`, `check-contract-parity.sh`, `check-doc-currency.sh`,
      `check-shared-prefix.sh`, `check-skills-index-sync.sh`, `check-token-budget.sh`,
      `validate-version.sh`. Plus every `loomwright/scripts/test-*.sh` that exists, **plus the two
      ROOT-level self-tests CI also runs** — `scripts/test-check-token-budget.sh` and
      `scripts/test-check-shared-prefix.sh` — which a `scripts/check-*.sh` glob misses and which the
      `loomwright/scripts/test-*.sh` clause misses too (they live at the repo root). Neither is
      affected by this change, but item 02 failed CI on exactly one gate run from memory; enumerate
      from `.github/workflows/ci.yml` and from disk, not from this list.
- [ ] **AC-9 (honest measurement):** the PR records the **real** delta — new script LOC added,
      prompt-hook characters removed, and the fact that the token saving is **runtime model calls
      avoided**, not prompt-inventory bytes. Do not claim a budget reduction that did not happen
      (item 02's lesson).

## Outcomes Rubric
- 4a budgets visible in leaf prose with caveat
- 4b anti-overlap rule present
- 4d split landed, all readers + gates synced
- 4e five hooks converted with self-tests; reviewer hook untouched or deliberately ported

## Executable Acceptance

- corpus-task: doc-currency-green
- corpus-task: version-consistent
- corpus-task: parity-emit-block

> **Why only `corpus-task:` bullets here.** `scripts/run-ground-truth.sh` collects **only leading
> `-` bullets** between this heading and the next `## ` heading — a fenced ```bash block yields
> ZERO checks, and the section then silently falls through to the `.supervisor/twin/` fallback,
> which per CLAUDE.md §Failure-Mode Invariants reads as **UNVERIFIED, not clean**. Separately,
> `skills/supervisor-readiness/SKILL.md` forbids a machine-authored brief from emitting `cmd:` or
> bare-shell bullets (any bare bullet is classified `kind=cmd` and executed via `bash -c` with full
> shell privileges), so re-bulleting shell one-liners would trade an inert section for a
> trust-sensitive one. The hook-shape assertions therefore live in **ST-5's verification
> checklist**, run and pasted into the PR by the worker. `parity-emit-block` is included
> deliberately — it is the corpus task most likely to catch an AC-6b regression.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | 4e substrate — shared parser + 5 validators + self-tests | AC-3, AC-4 | 0 modify, 7 create | unit-testing, error-handling | LAUNCHABLE |
| 2 | 4e wiring — contract-parity repair + its test, hooks.json, frontmatter mirrors | AC-5, AC-6, AC-6b, AC-6c | 5 modify, 0 create | quality-checklist, unit-testing | BLOCKED by #1 |
| 3 | 4a + 4b — leaf budget prose + anti-overlap rule | AC-1, AC-2 | 3 modify, 0 create | quality-checklist | BLOCKED by #2 |
| 4 | Doc correction — falsified 4d premise + void 4d→4f ordering | AC-7 | 4 modify, 0 create | — | BLOCKED by #3 |
| 5 | Release surface — doc sync (6 hook-type surfaces), version bump, all 7 gates | AC-8, AC-9 | 9 modify, 0 create | commit | BLOCKED by #4 |

**Totals:** 7 created + 21 modified = **28 file touches** across ~26 distinct files
(`agents/worker.md` appears in ST-2 and ST-3; `hooks.json` and `check-contract-parity.sh` are
produced by ST-2 and re-read by ST-5).

### Subtask 1 — 4e substrate (LAUNCHABLE)

```yaml
provides:
  - {kind: "file", path: "loomwright/scripts/result_block_parser.py"}
  - {kind: "symbol", path: "loomwright/scripts/result_block_parser.py", name: "extract_payload_text"}
  - {kind: "symbol", path: "loomwright/scripts/result_block_parser.py", name: "find_last_block"}
  - {kind: "symbol", path: "loomwright/scripts/result_block_parser.py", name: "parse_block"}
  - {kind: "symbol", path: "loomwright/scripts/result_block_parser.py", name: "emit"}
  - {kind: "file", path: "loomwright/scripts/validate-worker-result.py"}
  - {kind: "file", path: "loomwright/scripts/validate-execute-result.py"}
  - {kind: "file", path: "loomwright/scripts/validate-supervisor-result.py"}
  - {kind: "file", path: "loomwright/scripts/validate-qa-result.py"}
  - {kind: "file", path: "loomwright/scripts/validate-plan-review-result.py"}
  - {kind: "file", path: "loomwright/scripts/test-result-validators.sh"}
requires: []
external_requires:
  - "python3 >= 3.9 (stdlib only — PyYAML is NOT available on the target macOS system Python)"
```

**Create** (names indicative; the worker may adjust for consistency with existing script naming):
- `loomwright/scripts/result_block_parser.py` — the shared module. Two responsibilities, both
  lifted from and kept behaviour-compatible with `validate-launch-pad-result.py`:
  1. **Payload extraction ladder** — `last_assistant_message` → `result_block` → `output` →
     `agent_output` → `agent_transcript_path` → `transcript_path` (subagent-scoped path preferred
     over the shared session one). Plus `--raw` mode.
  2. **Block location + nested-YAML-subset parse** — find the **LAST** `<NAME>:` block (the
     most-recent-emission-wins contract), then parse the indented body into a dict supporting:
     scalars with the five YAML null spellings (`null`/`Null`/`NULL`/`~`/empty-after-colon),
     quoted literals (a quoted `"null"` is the **string**, not null), inline flow-style arrays
     (`[a, b]`), block sequences (`- item`), and **sequences of mappings** (the
     `outputs_verified: [ {kind, path, name?, status} ]` shape). Anything outside this subset must
     be reported as a parse failure, never silently coerced.
  3. A shared `emit(ok, reason)` — single exit point, **always `sys.exit(0)`**.
- `loomwright/scripts/validate-worker-result.py`
- `loomwright/scripts/validate-execute-result.py`
- `loomwright/scripts/validate-supervisor-result.py`
- `loomwright/scripts/validate-qa-result.py`
- `loomwright/scripts/validate-plan-review-result.py`
- `loomwright/scripts/test-result-validators.sh` — one self-test harness driving all five plus the
  parser, over fixtures. Follow the existing convention (`test-*.sh`, prints `N/M`, exit non-zero on
  failure). Fixtures go under a sibling dir, mirroring `scripts/progress-event-fixtures/`.

**Each validator's rule set is the CURRENT prompt text, transcribed exactly.** The prompts are in
`loomwright/hooks/hooks.json` — read them from there, do not paraphrase from
`docs/RESULT_SCHEMAS.md` (the prompts encode runtime rules the schema doc lists only "for
transparency", e.g. the worker's `.worker-summary.md` / `summary_file_write_failed` check and the
destructive-command scan). **Every numbered rule in each prompt must have a corresponding check and
a test.** Reason strings should match the prompts' quoted reason strings where the prompt specifies
one verbatim.

**Invariants (a violation here is a security regression, not a bug):**
- **ALWAYS exit 0.** These are `type: command` hooks carrying `|| true`; a non-zero exit would be
  masked, and a blocking gate must never be built this way (CLAUDE.md §Failure-Mode Invariants).
- **Unparseable stdin ⇒ `emit(True)`**, matching the template: if the hook plumbing is malformed we
  cannot validate, and we must not break the agent loop. A **missing result block** is different —
  that is `ok: false` with a reason.
- **Assert key PRESENCE for nullable-but-required fields** (`jq has()`-equivalent). A
  present-but-null field and an absent field are different outcomes and both need a test.
- No new third-party dependency. Standard library only.

### Subtask 2 — 4e wiring (BLOCKED by #1)

```yaml
provides:
  - {kind: "file", path: "loomwright/hooks/hooks.json"}
  - {kind: "file", path: "scripts/check-contract-parity.sh"}
  - {kind: "symbol", path: "scripts/check-contract-parity.sh", name: "hook_prompt"}
  - {kind: "file", path: "loomwright/scripts/test-check-contract-parity.sh"}
  - {kind: "file", path: "loomwright/agents/worker.md"}
  - {kind: "file", path: "loomwright/agents/execute-manager.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/validate-worker-result.py"}
  - {from: "1", kind: "file", path: "loomwright/scripts/validate-execute-result.py"}
  - {from: "1", kind: "file", path: "loomwright/scripts/validate-supervisor-result.py"}
  - {from: "1", kind: "file", path: "loomwright/scripts/validate-qa-result.py"}
  - {from: "1", kind: "file", path: "loomwright/scripts/validate-plan-review-result.py"}
  - {from: "1", kind: "file", path: "loomwright/scripts/test-result-validators.sh"}
external_requires: []
```

- `scripts/check-contract-parity.sh` — **do this FIRST, before deleting any prompt** (AC-6b, R0).
  Extend `hook_prompt()` with the command-type fallback and its explicit selection rule, then
  confirm the gate still exits 0 both before and after the hooks.json edit. Deleting the prompts
  first leaves the repo red in between and makes the two changes hard to review separately.
- `loomwright/scripts/test-check-contract-parity.sh` — extend with the three fallback fixtures
  required by AC-6c, in the same subtask. A gate repair with no falsifiable test is how a fail-open
  guard ships green.
- `loomwright/hooks/hooks.json` — replace the five `type: prompt` entries with `type: command`
  entries of the shape `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/validate-<x>-result.py" || true`,
  matching `validate-launch-pad-result.py`'s existing entry byte-for-byte in style. Leave the
  `code-reviewer` prompt entry, both wildcard prompt hooks (`Stop`, `TaskCompleted`), and every
  existing `type: command` entry untouched. Preserve entry ORDER within each matcher.
- `loomwright/agents/worker.md`, `loomwright/agents/execute-manager.md` — convert the mirrored
  frontmatter `hooks:` blocks. Keep the existing NOTE comment.
- Re-run `test-result-validators.sh` plus a `jq -e .` parse of `hooks.json`.

### Subtask 3 — 4a + 4b (BLOCKED by #2)

```yaml
provides:
  - {kind: "file", path: "loomwright/agents/worker.md"}
  - {kind: "file", path: "loomwright/agents/code-reviewer.md"}
  - {kind: "file", path: "loomwright/skills/self-heal-advisory/SKILL.md"}
requires:
  - {from: "2", kind: "file", path: "loomwright/hooks/hooks.json"}
  - {from: "2", kind: "file", path: "loomwright/agents/worker.md"}
external_requires: []
```

> `requires` on ST-2's `agents/worker.md` is a **serialization contract, not a data dependency** —
> both subtasks edit that file (frontmatter vs prompt body). The chain forces the order so the two
> edits never race.

- `loomwright/agents/worker.md` — state the 40-turn budget in the prompt body with the adherence
  caveat.
- `loomwright/agents/code-reviewer.md` — same.
- `loomwright/skills/self-heal-advisory/SKILL.md` — one anti-overlap sentence in Part 2's
  review-and-fix loop.

**Placement warning (a gate, not a style note):** both agent files carry the byte-identity-guarded
`<!-- SHARED-AGENT-PREFIX v1 BEGIN -->` / `END` block (`agents/worker.md:20-29`,
`agents/code-reviewer.md:33-41`), enforced fail-closed by `scripts/check-shared-prefix.sh` in CI.
**The 40-turn prose MUST go OUTSIDE that block in both files** — a single character inserted inside
it fails the gate.

**Budget warning (measured, load-bearing):** `worker` and `code-reviewer` have per-agent budgets in
`docs/prompt-token-budgets.json`; `self-heal-advisory` is NOT preloaded by any agent so it enters no
budget. `check-token-budget.sh` is a **ceiling-only ratchet** — it breaches only when live weight
exceeds budget, so ST-2's frontmatter deletion (which shrinks `worker` / `execute-manager`) is safe
and needs no budget action. If 4a's prose does breach, raise the budget in the SAME change with a
one-line note AND update the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" (the
gate asserts the two match). Keep 4a's prose short; it is meant to be nearly free.

### Subtask 4 — Doc correction (BLOCKED by #3)

```yaml
provides:
  - {kind: "file", path: "loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md"}
  - {kind: "file", path: "loomwright/docs/SPIKES/FINAL_STATE_GOAL.md"}
  - {kind: "file", path: ".supervisor/requirements/final-state/07-route-freshness-tools.md"}
  - {kind: "file", path: ".supervisor/requirements/final-state/03-fix4-cheap-batch.md"}
requires:
  - {from: "3", kind: "file", path: "loomwright/skills/self-heal-advisory/SKILL.md"}
external_requires: []
```

Correct the falsified claims. **Record the measurements** — a bare deletion loses the evidence.

**Re-derive the byte figures immediately before writing them** (`wc -c` on the file and on the
Part 2 slice) rather than copying them from this brief's Feasibility section. And **cite Part 1/
Part 2 sections by NAME, not line number** — see the citation-convention note in F1.

| File | What to correct |
|---|---|
| `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §4d (`:251-255`) | The premise. Part 2 invokes all ten Part 1 sections; the Read is once at phase entry; actual size 111,834 B / 1,014 lines; Part 2 alone is 72,521 B. State that the split was **evaluated and rejected**, with the date, not silently dropped. |
| `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §4f ordering (`:316`) | Remove the "strictly after 4d" precondition. `self-heal-advisory` is not a 4f routing target — it is already read-on-demand on both paths; 4f's double-pay is `async-orchestration` (9,078 proxy tokens). |
| `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` §4e (`:257`, `:259`) | **Do not restate the measurement** — `"22 entries across 10 events. Eight are type: prompt"` is a frozen as-measured spike snapshot and stays. Add a dated *"landed in v15.17.0; five of the six converted, `code-reviewer` deliberately retained"* note, mirroring §4d's "evaluated and rejected, with the date" treatment. This keeps the two sub-fixes' records consistent. |
| `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md` (`:72`, **`:76`**, `:82-83`) | Same ordering correction at **all three** sites — the execution-order rows AND the "4d before 4f" note. `:76` reads *"Fix 4f/4g/4c — route-not-preload (**after 4d**), …"* and is easy to miss; leaving it reproduces the exact dead precondition F2 removes. After editing, `grep -n '4d' ` the file to confirm no fourth site remains. **Do not renumber or re-litigate any D-decision** — this corrects an ordering rationale, not an owner decision. |
| `.supervisor/requirements/final-state/07-route-freshness-tools.md` (`:3-4`) | Drop "Strictly AFTER item 03 (4d split)" and the parenthetical. Note item 07 is unblocked. Its `## Non-goals` line *"No skill content changes (03 did the split)"* also needs correcting — 03 did **not** do the split. |
| `.supervisor/requirements/final-state/03-fix4-cheap-batch.md` | Append a `## Status` note recording that 4d was dropped, why, and where the correction landed. Do **not** rewrite the original Scope/AC/Rubric text — append only, so the original yardstick stays auditable. |

### Subtask 5 — Release surface (BLOCKED by #4)

```yaml
provides:
  - {kind: "file", path: "loomwright/.claude-plugin/plugin.json"}
  - {kind: "file", path: ".claude-plugin/marketplace.json"}
  - {kind: "file", path: ".claude-plugin/README.md"}
  - {kind: "file", path: "CLAUDE.md"}
  - {kind: "file", path: "README.md"}
  - {kind: "file", path: "CHANGELOG.md"}
  - {kind: "file", path: "AGENT_GUIDELINES.md"}
  - {kind: "file", path: "loomwright/commands/agent-help.md"}
  - {kind: "file", path: "loomwright/skills/workflow-management/SKILL.md"}
requires:
  - {from: "4", kind: "file", path: "loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md"}
  - {from: "2", kind: "file", path: "loomwright/hooks/hooks.json"}
  - {from: "2", kind: "file", path: "scripts/check-contract-parity.sh"}
external_requires:
  - "gh CLI authenticated (PR creation happens in Supervisor Phase 4, not this subtask)"
```

Version `15.16.0` → **`15.17.0`**. Doc-currency fails CI closed on stale count/version claims.

**Hook-type claims to correct — SIX surfaces (the count stays 24; the TYPE mix changes):**
- `CLAUDE.md` hook narrative (`:153`) — append the v15.17.0 clause; correct *"Prompt-based
  validation uses fast haiku model with 30s timeout"* (now true of only three hooks: `code-reviewer`
  SubagentStop, `Stop`, `TaskCompleted`); extend the `type: command` enumeration.
- `CLAUDE.md` hook TABLE — annotate `type:command — validate-<x>-result.py` on exactly **five** rows,
  identified **by matcher name**: `SubagentStop (worker)`, `SubagentStop (execute-manager)`,
  `SubagentStop (supervisor)`, `SubagentStop (qa-executor)`, `SubagentStop (plan-reviewer)`.
  **Do NOT touch** the `SubagentStop (worker) progress event` row (already `type:command`) or the
  `SubagentStop (code-reviewer)` row (**stays a prompt hook per AC-5** — annotating it would
  contradict AC-5).
- `.claude-plugin/README.md:504` — **"6 prompt validators" is now wrong**; it becomes 1 prompt
  validator + 5 `type: command` validators.
- `loomwright/commands/agent-help.md:968` — *"They use fast prompt-based validation (haiku model,
  30s timeout)"* is now wrong for most hooks.
- `loomwright/skills/workflow-management/SKILL.md:380` — *"Uses fast haiku model for evaluation"*;
  verify the surrounding context before editing (it may describe a different hook).
- **`AGENT_GUIDELINES.md:354`** — *"Hooks use prompt-based validation (fast haiku model, 30s
  timeout). WorktreeCreate and StopFailure use `type: "command"` for zero-latency logging."* **Both
  sentences are wrong post-change.** This file IS in `check-doc-currency.sh`'s FILES list. Its
  `:320` line (*"Worker and Execute Manager have SubagentStop hooks in frontmatter for schema-based
  validation"*) stays TRUE after AC-6 and needs no edit; the generic frontmatter example around
  `:305-309` is illustrative and stays.

**Verification checklist — run these and paste the output into the PR body** (they are deliberately
NOT `## Executable Acceptance` bullets; see the note there):

```bash
# baseline on main @ 2bef2d9 was 16 command + 8 prompt = 24; expect 21 + 3 after conversion
grep -c '"type": *"command"' loomwright/hooks/hooks.json   # expect 21
grep -c '"type": *"prompt"'  loomwright/hooks/hooks.json   # expect 3
# exactly ONE prompt hook left on any SubagentStop matcher, and it is code-reviewer
jq '[.hooks.SubagentStop[] | .hooks[] | select(.type=="prompt")] | length' loomwright/hooks/hooks.json
jq -r '.hooks.SubagentStop[] | select([.hooks[].type] | index("prompt")) | .matcher' loomwright/hooks/hooks.json
# every command entry still ends in || true (16/16 held pre-change)
jq -r '[.. | objects | select(.type? == "command") | .command] | length as $n | ([.[] | select(test("\\|\\| true\\s*$"))] | length) as $m | "\($m)/\($n)"' loomwright/hooks/hooks.json
# every validator is exit-0-by-contract on garbage — report per-file, do not mask in a loop
for v in loomwright/scripts/result_block_parser.py loomwright/scripts/validate-*-result.py; do
  printf 'garbage' | python3 "$v" >/dev/null 2>&1; echo "$? $v"
done
# all root-level gates AND self-tests, enumerated from disk (not from the brief's list)
for g in $(ls scripts/check-*.sh scripts/validate-*.sh scripts/test-*.sh); do bash "$g" >/dev/null 2>&1; echo "$? $g"; done
# plugin-level self-tests
for t in loomwright/scripts/test-*.sh; do bash "$t" >/dev/null 2>&1; echo "$? $t"; done
# cross-check against what CI actually invokes
grep -n 'scripts/' .github/workflows/ci.yml
# stale-phrasing sweep (a green doc-currency run is necessary but NOT sufficient)
grep -rn "haiku model\|prompt-based validation\|6 prompt validators" --include='*.md' . | grep -v CHANGELOG
```

**Version-annotation sites** (9 found; some are deliberately frozen — verify before touching):
`loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (version field **and**
the `vX.Y.Z` string inside `description` — update **in place**, never append another clause),
`.claude-plugin/README.md:430`, `loomwright/commands/agent-help.md:1084`, `CLAUDE.md:15/:28`,
`README.md:9`, `CHANGELOG.md`. **Do NOT bump** `docs/TELEMETRY.md:222`,
`docs/prompt-token-budgets.json` notes, or `docs/ARCHITECTURE_CONTRACTS.md:345/349/353` — those are
historical/frozen annotations of what shipped in v15.16.0 (CLAUDE.md's frozen-example-value
convention). CLAUDE.md keeps only the two most recent release notes — move the v15.15.0 note to
`CHANGELOG.md`.

**Run all seven gates enumerated from disk** (`ls scripts/check-*.sh scripts/validate-*.sh`) — item
02's PR failed CI on the one gate its author ran from memory instead.

## Parallelism Analysis

### Dependency Graph
```
ST-1 (substrate) → ST-2 (wiring) → ST-3 (4a+4b) → ST-4 (doc correction) → ST-5 (release)
```

Strictly sequential. ST-2 must not wire hooks to scripts that do not yet exist and pass their own
tests. ST-5 must be last because it counts and describes everything before it.

### File Overlap Matrix

| | ST-1 | ST-2 | ST-3 | ST-4 | ST-5 |
|---|---|---|---|---|---|
| ST-1 | — | — | — | — | — |
| ST-2 | none | — | `agents/worker.md` | — | — |
| ST-3 | none | `agents/worker.md` | — | — | — |
| ST-4 | none | none | `self-heal-advisory/SKILL.md` (different sections) | — | — |
| ST-5 | none | none | none | none | — |

`agents/worker.md` is touched by ST-2 (frontmatter `hooks:`) and ST-3 (prompt body) — different
regions, but serialized anyway by the dependency chain.

### Batch Plan
- **Recommended workers:** 1
- Four sequential batches after ST-1; one worker throughout, no worktrees.

## Skill References
- `skills/unit-testing/SKILL.md` — self-test structure, falsification over confirmation (ST-1)
- `skills/error-handling/SKILL.md` — the exit-0-by-contract / fail-safe posture (ST-1)
- `skills/quality-checklist/SKILL.md` — pre/post gates (ST-2, ST-3)
- `skills/commit/SKILL.md` — conventional commits (ST-5)

## Risk Assessment

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R0 | **Deleting the five prompts breaks `check-contract-parity.sh` and fails CI.** Its `hook_prompt()` selects only `type=="prompt"`; an empty result is a hard `pin-drift` error (`fail=1` → exit 1). Six of its seven MANIFEST rows lose their prompt hook. Found by Plan Review, not by the author — the gate's premise is that the runtime rule source *is* a prompt string. | **BLOCKING** | AC-6b scopes the repair into ST-2 with a chosen design (command-type fallback that greps the referenced validator source), and ST-2 sequences the gate fix BEFORE the prompt deletion so the repo is never red mid-subtask. Also re-check parity check 1(b), which greps the agent `.md` for pinned fields that AC-6 is deleting frontmatter text around. |
| R0b | **The AC-6b repair itself fails OPEN.** Three affected matchers carry multiple `type: command` entries; a fallback that concatenates them would grep `send-telemetry-core.sh` — which mentions `pr_url`, `heal_decision`, `heal_loop_ran`, `summary`, `schema_version` — and pass pin-drift on a field the real validator dropped. The gate would go green while enforcing nothing. Found by Plan Review attempt 2, in a design this brief had itself proposed. | **HIGH** | AC-6b pins an explicit selection rule (match on `validate-<x>-result.py`; hard-error on 0 or >1 matches). AC-6c requires falsifiable fixtures for that branch — today `test-check-contract-parity.sh` makes every fixture matcher prompt-type, so the branch would otherwise be covered only by a one-directional "real tree passes" check that a fail-open build also satisfies. |
| R1 | The nested-YAML-subset parser silently mis-parses a real emission, so a validator passes garbage or rejects a valid block. This is the whole change's correctness surface. | **HIGH** | Parser is written once and self-tested once (that is the reason for the shared module). AC-4 mandates malformed + missing-key + explicit-null + cross-field cases per schema. Any construct outside the supported subset must be an explicit parse failure, never a silent coercion. |
| R2 | Cannot verify the converted hooks actually fire — the installed plugin is a copy, not a symlink (verified: different inodes). | **HIGH** | Accepted and disclosed, exactly as item 02 did. Self-tests over fixtures are the in-PR evidence; a live re-measure needs a reinstall and is an **operator** step. The PR must say this plainly rather than implying live verification. |
| R3 | A validator exits non-zero on an edge (uncaught exception before `emit`), and `\|\| true` masks it — the hook silently validates nothing. | **HIGH** | Wrap `main()` so ANY exception still routes through `emit`. AC's executable check pipes garbage to every validator and asserts exit 0. Note this is exactly the failure mode CLAUDE.md warns about for a *blocking* gate — these are not blocking, but a silently-dead validator is still a real loss. |
| R4 | Transcribing 38 numbered prompt rules across five schemas drops or subtly weakens one, and nothing catches it — the prompt is deleted in the same change. | **MEDIUM** | Transcribe from `hooks.json` (the runtime source), not from `RESULT_SCHEMAS.md`. ST-2 is a separate subtask from ST-1 specifically so the reviewer sees the old prompt text and the new script in the same diff. Reviewer should count rules on both sides. |
| R5 | Doc-currency drift — the type-mix claims live in five surfaces the gate does NOT scan (it scans counts/versions, not prose about hook types). | **MEDIUM** | ST-5 enumerates all five explicitly. After editing, grep the OLD phrasings (`haiku model`, `6 prompt validators`, `prompt-based validation`) repo-wide; a green doc-currency run is necessary but not sufficient. |
| R6 | A token budget breaches on 4a's prose and CI fails closed. | **LOW** | Keep 4a short. If it breaches, raise budget + mirror row in the SAME change (the gate asserts JSON and table agree). |
| R7 | Correcting the spike docs is read as re-litigating an owner decision. | **LOW** | ST-4 corrects a *measurement* and an *ordering rationale*. D1–D11 are untouched. Stated explicitly in the subtask. |

## Configuration
- **Base Branch:** main
- **Workers:** 1
- **Mode:** sequential
- **Split reason:** context-bound
- **Cost profile:** cheap (Sonnet — forwarded from `/automate --cheap`)
- **Heal iterations:** 3 (default)
- **Version target:** 15.17.0

> **Split reason justification (`context-bound`, per `skills/supervisor-readiness/SKILL.md`
> §"Decomposition Threshold": > 12 files changed OR > 800 changed lines):** ~25 distinct files
> (7 created + 20 modified touches) and, on ST-1 alone, a shared parser plus five validators plus a
> self-test harness transcribing **38 numbered rules** (8 worker + 6 execute-manager + 13
> supervisor-runner + 5 qa-executor + 6 plan-reviewer, counted from `hooks.json`) — comfortably over
> 800 changed lines. Both predicates of the one bound fire independently. `file-conflict` and
> `genuine-parallelism` do not: the only file overlap is `agents/worker.md` across two already-
> serialized subtasks, and there are no ≥ 2 zero-overlap groups of ≥ 3 files each.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-29-fix4-cheap-batch.md

## Outcome

> **Reconstructed post-hoc on 2026-08-03, not written by the completion tail.** This run's Phase 4.5
> never reached its completion tail — the session died after heal iteration 2 (see "Why this block is
> reconstructed" below). Every field here is sourced from ground truth (GitHub, git, and the
> `/automate` run file's `## Progress` lines for item 03) or explicitly marked **UNKNOWN**. Fields the
> completion tail would normally record from live run state, and which no artifact preserves, are NOT
> guessed.

- **Status:** completed (merged) — *outcome established from ground truth, not from a run-emitted `SUPERVISOR_RESULT`*
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/118 — `MERGED` 2026-07-30T09:37:52Z
- **Merge commit:** `23a2b04` — verified an ancestor of `origin/main` (`git merge-base --is-ancestor` + `git branch -r --contains`)
- **Branch:** `feature/fix4-cheap-batch` (base: `main` @ `2bef2d9`)
- **Diff:** 38 files, +6254/−93
- **Version:** 15.16.0 → 15.17.0 · counts UNCHANGED 14 agents / 21 commands / 41 skills / 24 hooks · hook type-mix 16 command + 8 prompt → **21 command + 3 prompt**
- **All 7 CI gates:** green (`ci` SUCCESS, `claude-review` SUCCESS)
- **heal_loop_ran:** true
- **heal_iterations:** **≥ 2** — heal 1 (`9b496fe`) and heal 2 (`4f63dea` + `125e6b4`) are both on the branch. Whether a third iteration ran, or the loop exited on a clean re-review, is **UNKNOWN**.
- **heal_decision:** **UNKNOWN** — never recorded. The last logged state (2026-07-30 03:15) is *"re-review FAILED AGAIN … heal iteration 2 (of 3) in progress"*. Two heal commits landed after that, but no re-review verdict survives in any artifact.
- **heal_remaining_issues:** **UNKNOWN** — same cause.
- **rubric_score:** **UNKNOWN** — never recorded. The brief carries a 4-bullet `## Outcomes Rubric`, so the Rubric Grader was in scope, but no score was emitted. Known independently of the grader: rubric item 3 ("4d split landed") is a **documented FAIL-by-decision** — 4d was dropped at the Phase 2.5 gate on a falsified premise, user-approved, and the rubric was deliberately kept verbatim rather than reworded (so the expected ceiling was 3/4, not 4/4).
- **red_team_advisory:** disabled — the recorded invocation was `/autonomous --single-iteration --cheap`; `--red-team` was not passed and it is default-OFF.
- **Until-mergeable dispatched:** false — the default detached drain was SUPPRESSED by `/automate` per `skills/automate-loop/SKILL.md` §7 (`auto_review=false`, sidecar `__ABSENT__`). The engine's **owned inline drain never ran either**: the session died before DRAIN. Verified marker-based, not from control flow — no `.supervisor/review-dispatch/` marker mentions PR #118 and no `review-pr-runner` process existed at reconcile time.

### Why this block is reconstructed

The `/automate` engine's own RECONCILE tick on 2026-07-30 recorded the crash: *"run file still showed it `- [ ]` (crash between merge and check-off)"*, and restored a crash-stranded `auto_review=false` suppression left behind by the dead tick. The same crash is why the completion tail's two other steps never ran: the brief stayed in `in-progress/` and no `## Outcome` was appended. Corroborating evidence — the session log
`.supervisor/logs/8d43da72-9b5b-4793-8599-d06e27b3a8b3.jsonl` contains **650 `token_ledger` + 638 `subtask_complete` events and zero `session_end`**, i.e. only hook-written records, no agent-written terminal marker.

The PR was merged by a human at 2026-07-30T09:37:52Z, ~2h15m after the last heal commit.

### Subtask outcomes (from the `/automate` run file's `## Progress` lines for item 03)

| # | Subtask | Commits | Review outcome |
|---|---------|---------|----------------|
| 1 | 4e substrate — shared parser + 5 validators + self-tests | `0518a6d` → heal `8bb71a9` → `ee54d40` (LOW residue) | PASS after 1 heal iter |
| 2 | 4e wiring — contract-parity repair + hooks.json + frontmatter mirrors | `3f534da` → heal `8b09b54`, `b50bc23` → `f2e1d1f` (LOW residue) | PASS after 2 heal iters |
| 3 | 4a + 4b — leaf budget prose + anti-overlap rule | `2040a9f` | PASS first time |
| 4 | Doc correction — falsified 4d premise + void 4d→4f ordering | `a6f4433` → heal `4781216` | FAIL (completeness) → PASS |
| 5 | Release surface — 6 hook-type doc surfaces, version bump, 7 gates | `7c2c794` + `03b5535` | PASS |

**Phase 4.5 (integrated):** heal 1 `9b496fe` (HIGH — YAML-comment stripping) → re-review FAIL; heal 2 `4f63dea` + `125e6b4` (markdown framing branch, a fourth fail-open, and a test harness that could silently lose cases). Verdict after heal 2: **UNKNOWN**.

### Substantive record worth keeping

- **4d was rejected on a falsified premise, not deferred.** The requirement claimed Phase 4.5 "needs only Part 2 and reads the whole file per heal iteration". Measured: Part 2 invokes **all ten** Part 1 sections, and the Read happens **once at phase entry**, not per iteration. The dependent claim that item 07 (4f) was "strictly after 4d" rested on the same wrong model — `self-heal-advisory` was never among the preloaded skills, so it was never a 4f routing target. ST-4 corrected all four surfaces so item 07 would start from a true premise.
- **The same fail-open class surfaced by three distinct routes** across ST-1, ST-2 and Phase 4.5 — value parsing, block framing via blank-line tolerance, then markdown framing. Each round was demonstrated with an exit-0 reproduction rather than argued, and one round falsified the *predecessor's own written justification* for a documented deviation. A documented deviation defended by a false safety argument is worse than an undocumented one.
- **The test harness could silently lose cases** — the parser check block is one Python script whose output a bash `case` consumes by PASS/FAIL prefix, so an exception aborts it, later checks emit nothing, and the traceback is discarded (demonstrated at 290 → 287 with `fail=0` and no diagnostic). This matters disproportionately because the PR states plainly that **no converted hook has been observed FIRING** — the suite is the change's only evidence.

### Review channel

One `claude-review` PR issue comment (2026-07-29T17:20:41Z, 0 formal reviews) — *"Findings below are minor; nothing blocking."* It independently re-verified the hook count/type-mix claim (21 command / 3 prompt / 24 total). Note it was posted **before** the final three commits (`9b496fe`, `4f63dea`, `125e6b4`), so those never went through a CI review cycle.
