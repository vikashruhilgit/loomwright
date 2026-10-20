# Supervisor Job: Choose the /automate coordinator's model by A/B measurement (Haiku 5.5 vs Sonnet 5.5)

## Environment
- **Project:** automate-2026-10-15-163325/L21 (lane checkout of loomwright)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (source requirement is gitignored under `.supervisor/*`, so its provenance is unverified)
- **Source requirement:** .supervisor/requirements/automate-speed/10-coordinator-model-ab.md
- **Base commit:** ee3d7ea3bb069c50a07c3b37222c52c88202263b

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq driver (`loomwright/scripts/automate-next-step.sh`), the installed `claude plugin eval` CLI (`case.yaml`/`prompt.md` + `graders/*.md`, `--model`, `--runs`, `--scaffold`, `--json`) |
| 2 | Dependency Availability | CAUTION | `claude plugin eval` has never been used in this repo (no `evals/` dir, no `case.yaml` anywhere); grader types beyond `type: llm` must be confirmed from the CLI before authoring a script-based parity grader |
| 3 | Architecture Fit | GO | the driver already owns the instruction schema and reads `.supervisor/config.json` paths (`ns_cfg_paths`); the golden next-step fixtures (`loomwright/scripts/fixtures/automate-golden/*/next-step.results`, 41 cases) are reusable eval inputs |
| 4 | Scope vs Supervisor Capability | GO | single subtask: ~4 modified + ~8–12 created small files, well under 800 changed lines; the eval suite, setting and evidence are coupled by the decision rule |
| 5 | Hard Blockers | CAUTION | the A/B (3 runs × 2 models × the suite) spends real model tokens on the owner's subscription (weekly-cap risk); nothing in Touches launches a coordinator with `--model`, so the setting is resolved and reported by the driver, not yet applied at a launch site |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add an eval suite that runs the same fixture Queue items with the `/automate` coordinator on Haiku 5.5 and on Sonnet 5.5, add a coordinator-model setting (a `.supervisor/config.json` key read by `automate-next-step.sh`, with a one-directional escalate-on-failure valve), and set its default from the measured result.

**Problem Statement:**
The owner needs to know which model the `/automate` coordinator can safely run on, because after items 06–09 the coordinator's job shrank to "run next-step, do the one instruction, report the result". It may not need the strongest model, and Haiku 5.5 costs a small fraction of Sonnet 5.5 or Opus 5.5.
Currently, the coordinator always runs on the session model, and its rule-following reliability on a cheaper model has never been measured (owner decision D3: choose by measurement, not opinion).
Success looks like a committed evidence file with per-case parity, wrong-question counts and tokens for both models, and a default coordinator model that equals the cheapest model with 100% parity and 0 wrong questions. If neither cheaper model qualifies, the default stays the session model.

## Acceptance Criteria
- [ ] AC1 — Given the eval suite under `loomwright/evals/coordinator-model/`, when it is run with each model (`claude plugin eval … --model claude-haiku-5-5` and `--model claude-sonnet-5-5`, 3 runs each, at the frozen commit that adds the suite), then a committed evidence file `docs/evidence/coordinator-model-ab.md` contains the exact commands, per-case parity, the wrong-question count, the skipped-instruction count and tokens for both models, and the PR body links to it.
- [ ] AC2 — Given the measured scores, when the driver resolves an absent `coordinator_model` key, then the driver's default coordinator model equals the cheapest model with 100% parity and 0 wrong questions across all runs. If no cheaper model qualifies, the default stays `session` (the session's own model), and the committed evidence file `docs/evidence/coordinator-model-ab.md` says so and names the failing cases.
- [ ] AC3 — Given `.supervisor/config.json` carries a `coordinator_model` key, when `automate-next-step.sh` prints any instruction, then the instruction carries the resolved `coordinator_model`. "Any instruction" includes the ones built by `ns_base()` and the inline `--resume` no-incomplete-run `start_new` instruction, which resolves the config from the checkout that holds the `--resume <automate_dir>`. The value is `session` (the session's own model) or one model id from the closed list {`claude-haiku-5-5`, `claude-sonnet-5-5`}. An absent key resolves to the default. An invalid value falls back to `session` with one named `next-step:` stderr line, and is never a refusal. `loomwright/docs/result-schemas/automate-run.md` documents the key, its values, the fallback and the new field next to the driver's instruction schema.
- [ ] AC4 — Escalate-on-failure valve, with ONE named exception to the driver's "exit 2 ⇒ nothing written" rule:
  - **Ledger.** The driver keeps a ledger `.supervisor/automate/coordinator-model.jsonl` (never the run file, so golden run files stay byte-identical). It appends one report line `{ts, run_id, item, step, ok}` per NEW coordinator `--result` report:
    - an accepted, non-replayed report ⇒ `ok: true`;
    - a refused report ⇒ `ok: false` plus `reason`. Refusals that count: `--result is not a JSON object`, a report whose shape or fields fail validation (incl. `reserved_prefix`, nested-object and one-line refusals), and a report that does not answer what is pending (incl. a stale or out-of-state report).
    - Appends nothing: a byte-identical replayed report (a replay is not a coordinator run, so §Idempotency's "a replay writes nothing" stays true), a call with no `--result`, a usage error (bad flags or a missing run file), and every non-`--result` exit-2 path.
  - **Window.** A "coordinator run" is one report line. The FAIL window is the last 20 report lines, and `escalated` records are not counted in it. A FAIL is an `ok: false` line.
  - **Escalation.** When ≥3 FAILs fall in the window and the configured value is not `session`, the resolved `coordinator_model` becomes `session` (escalation map: any non-session value ⇒ `session`). The driver appends one `{ts, escalated: true, fails, window, from}` record, only if no `escalated` record exists yet, so at most one record per ledger.
  - **Persistence.** The `escalated` record is found by scanning the WHOLE ledger, not only the 20-line tail. The ledger has a hard byte cap, which is its only bound: no truncation and no rotation. Over the cap, the ledger resolves to `session` and nothing more is appended. So the escalation is one-directional, with no auto-demotion: an `escalated` record keeps `session` in force however many reports follow, until the owner deletes the ledger file. That deletion is the only clearing action, and the schema doc names it.
  - **Bad ledger.** A malformed or over-cap ledger resolves to `session` with a named stderr line. A ledger write failure is fail-SAFE: the append is skipped and the call's result is unchanged.
  - **Docs and tests.** Usage errors and every other exit-2 path still write nothing. `loomwright/docs/result-schemas/automate-run.md`'s "Writers and failures" paragraph names the ledger as the sole exception in the same change. `test-automate-next-step.sh`'s `snapshot()` excludes only that ledger file.
- [ ] AC5 — Given a fixture whose expected run file is deliberately wrong (mutation control), when the suite's parity grader scores it, then the grader fails. The committed evidence file `docs/evidence/coordinator-model-ab.md` records the mutation-control command and its failing result.
- [ ] AC6 — Given the change, then `bash loomwright/scripts/test-automate-next-step.sh` passes with new pins:
  - setting: absent ⇒ default; valid value ⇒ that value; invalid ⇒ `session`; the resume `start_new` instruction carries the field.
  - valve: 2 FAILs/20 ⇒ no escalation; 3/20 ⇒ `session` plus an escalated record; an escalated record followed by 20+ `ok: true` lines ⇒ still `session`; malformed ledger ⇒ `session`; owner deletes the ledger ⇒ the configured value resolves again; a refusal appends exactly one `ok: false` line and changes nothing else under `.supervisor/`; a byte-identical replayed report appends nothing; a no-`--result` re-print writes nothing. The committed evidence file `docs/evidence/coordinator-model-ab.md` records `<passed>/<total>` for that suite and for the eval suite's single passing run on the chosen model.
- [ ] AC7 — Given `token-economy/06-model-router-gate.md` proposed the escalate-on-failure valve, then the committed evidence file `docs/evidence/coordinator-model-ab.md` states that 06 is superseded for the coordinator: its valve is folded into this setting. The PR body links to that statement.
- [ ] AC8 — Given the release rule, then a fragment `changelog.d/as10-coordinator-model-ab.md` (`bump: minor`) exists and `bash scripts/check-version-bump.sh` passes. No version file is hand-edited.

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
| driver setting + valve | `loomwright/scripts/automate-next-step.sh` | — | HIGH |
| driver tests | `loomwright/scripts/test-automate-next-step.sh` | — | HIGH |
| schema doc | `loomwright/docs/result-schemas/automate-run.md` | — | HIGH |
| eval suite | — | `loomwright/evals/coordinator-model/` (`README.md` naming the cases, the fixture each stages and the exact run commands; cases: `prompt.md`/`case.yaml` + `graders/*.md` per case, one shared scaffold script that stages a golden case from `loomwright/scripts/fixtures/automate-golden/<case>/` into a scratch repo, one parity grader that diffs the normalised run file against the case's `expected.md`, one mutation-control case) | MEDIUM (exact grader file shapes depend on the CLI's supported grader types) |
| evidence + release | — | `docs/evidence/coordinator-model-ab.md`, `changelog.d/as10-coordinator-model-ab.md` | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` scans `loomwright/docs/`, so the schema-doc edit must keep its claims current. `loomwright/scripts/test-citation-drift.sh` scans `loomwright/docs/*.md` and `loomwright/scripts/*.sh` for bare `file:N` citations, so cite with descriptive anchors only. `test-automate-golden.sh`'s SCRUB phase forbids `/Users/` and `/home/` in the golden fixtures dir. The eval suite reuses those fixtures in place and never copies them, and its own files must not hold a home path either (`meta-sync.sh` `home_path` scrub).

## Touched-file invariants

> Grounded at base `ee3d7ea3bb069c50a07c3b37222c52c88202263b`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-next-step.sh`**
  - keep:
    - the one-instruction contract `prints exactly ONE JSON instruction for the model on stdout`: the setting adds a field and never a second stdout line. Its warning goes to stderr through `ns_err() { echo "next-step: $*" >&2; }`.
    - `set -uo pipefail` and bash 3.2 safety: no `"${empty[@]}"` under `set -u`.
    - the closed `do` enum (`spawn | ask | park | done`): the setting adds no `do` value and no `case` arm unless the doc's step list is extended in the same change.
    - the run-file write set: the valve ledger lives in its own file under `.supervisor/automate/` (the path the driver already holds as `$AD`), never in the run file, so the 41 golden `next-step.results` cases stay byte-identical.
    - repeat calls are idempotent: a no-`--result` re-print writes nothing. The ledger is appended only when a `--result` is processed.
    - "Exit 2 means … nothing written" (`automate-run.md` §"Writers and failures"): every exit-2 path stays byte-unchanged under `.supervisor/`, with exactly one exception, the `coordinator-model.jsonl` append for a refused report (AC4). Usage errors append nothing.
  - reuse:
    - `ns_base()` (`'{do: $d, step: $s, run_id: $r, item: …'`) builds the common fields for every emitter but one: add `coordinator_model` there. The exception is the inline resume no-incomplete-run instruction (`'{do: "done", step: "resume", run_id: null, …'`). It runs before `ns_resolve_root()`, so `CFG_PATH` is not set yet. It must resolve the config from the `--resume <automate_dir>`'s checkout and add the same field.
    - `ns_cfg_paths() { CFG_PATH="$ROOT/.supervisor/config.json"`: the config path, never a new literal.
    - `"$JQ"`.
    - read the key with `if has("coordinator_model") then … else empty end`, not `// empty` (lesson f0d8d600).
  - mirror: the `**Common fields:**` list in `loomwright/docs/result-schemas/automate-run.md` must name the new field in the same change.
  - fired by: the `/automate` coordinator (`skills/automate-loop/`), and `automate-lanes.sh` lanes via `/loomwright:automate`.
  - pinned by: `loomwright/scripts/test-automate-next-step.sh` legs G, I, D and M. Leg D reads `ns_dispatch() {` arms and `ns_emit (spawn|ask|park|done…)`.
- **`loomwright/scripts/test-automate-next-step.sh`**
  - keep: the single tally `PASS: <n> FAIL: <m>`. Every case stays hermetic (`mktemp -d` checkout, stubbed `gh`, sandboxed HOME), with no network and no real `claude` call. Mutants are gated by `build_mutant()`, and `NS_SKIP_MUTANTS=1` still skips them.
  - keep: `snapshot()` checksums every file under `$CASE_ROOT/.supervisor`, and the existing exit-2 legs assert `[ "$s0" = "$(snapshot)" ]`. Exclude ONLY `.supervisor/automate/coordinator-model.jsonl` from it. Do not weaken any other leg.
  - reuse: `golden_case`, `in_case`, `snapshot`, `build_mutant`, `ok`/`no`. Do not write a parallel harness.
  - pinned by: CI's `loomwright/scripts/test-*.sh` glob, and `bash scripts/ci-local.sh`.
- **`loomwright/docs/result-schemas/automate-run.md`**
  - keep: the line `one of the driver's \`case\` arms:` and the `| \`spawn\` | ` row, both machine-read by leg D. Keep each closed list equal to the driver's.
  - mirror: the new config key sits beside the existing instruction-schema text (section `### next-step instruction (\`automate-next-step.sh\`)`). No `ARCHITECTURE_CONTRACTS.md` edit and no `commands/automate.md` edit: items 16, 18 and 26 own those.

## Closed enumerations touched

> Sibling grep at base `ee3d7ea3bb069c50a07c3b37222c52c88202263b`: `grep -rnF 'Common fields:' --exclude=CHANGELOG.md loomwright docs scripts` → 2 hits in 2 files.

- **`coordinator_model`** (new common instruction field; sibling: `run_id`) — must be named in:
  - `loomwright/docs/result-schemas/automate-run.md`: the `**Common fields:**` list (`do`, `step`, `run_id`, `item`, `pr`), so extend it.
  - `loomwright/scripts/automate-next-step.sh`: `ns_base()`'s object (`run_id: $r, item:`), so extend it.
  - `loomwright/docs/result-schemas/supervisor-result.md`: `**Common fields:**` of the separate `supervisor-next-step.sh` driver needs no change, because this item does not touch that driver.
- **`coordinator_model` values** (new closed enum: `session` plus the allowed model ids): defined once in the driver, and the schema doc restates it beside the key. Both are updated in the same change (house rule "restating copy updated in the SAME change").

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-automate-next-step.sh` — invalid `coordinator_model` ⇒ `session` | replace the invalid-value fallback in `automate-next-step.sh` with a pass-through of the raw configured value |
| `loomwright/scripts/test-automate-next-step.sh` — 3 FAILs in last 20 ⇒ escalated | change the valve threshold `3` to `4` in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — malformed ledger ⇒ `session` | make the malformed-ledger branch resolve the configured (cheaper) model |
| `loomwright/scripts/test-automate-next-step.sh` — escalated + 20 later `ok: true` lines ⇒ still `session` | look for the `escalated` record only in the last-20 tail in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — replayed report appends nothing | drop the replay check before the ledger append in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — every instruction carries `coordinator_model` | delete the `coordinator_model` key from `ns_base()` in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — resume `start_new` instruction carries `coordinator_model` | delete the `coordinator_model` key from the inline resume `start_new` instruction in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — absent key ⇒ default | make the absent-key branch return a closed-list value other than the shipped default (whichever the A/B picked) in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — valid value ⇒ that value | make every configured value resolve to `session` in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — 2 FAILs/20 ⇒ no escalation | change the valve threshold `3` to `2` in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — ledger deleted ⇒ configured value again | make a missing ledger resolve `session` in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — refusal appends exactly one `ok: false` line | delete the ledger append on the exit-2 refusal path in `automate-next-step.sh` |
| `loomwright/scripts/test-automate-next-step.sh` — no-`--result` re-print writes nothing | make the ledger append run on every call, not only on a processed `--result`, in `automate-next-step.sh` |
| `loomwright/evals/coordinator-model/` parity grader — wrong-expected fixture | the mutation-control case itself (AC5): an `expected.md` with one changed `## Progress` line must score FAIL |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Coordinator-model setting + escalate valve + A/B eval suite + evidence | all (AC1–AC8) | 3 modify, ~8–12 create | `skills/unit-testing/SKILL.md`, `skills/automate-loop/SKILL.md` (read-only context) | LAUNCHABLE |

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/evals/coordinator-model/README.md"}
  - {kind: "file", path: "docs/evidence/coordinator-model-ab.md"}
  - {kind: "file", path: "changelog.d/as10-coordinator-model-ab.md"}
  - {kind: "symbol", path: "loomwright/scripts/automate-next-step.sh", name: "coordinator_model"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "coordinator_model"}
  - {kind: "symbol", path: "loomwright/scripts/test-automate-next-step.sh", name: "coordinator_model"}
requires: []
lanes:
  - "loomwright/evals/coordinator-model/**"
  - "loomwright/scripts/automate-next-step.sh"
  - "loomwright/scripts/test-automate-next-step.sh"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "docs/evidence/coordinator-model-ab.md"
  - "changelog.d/as10-coordinator-model-ab.md"
external_requires:
  - "claude CLI with `claude plugin eval` (--model, --runs, --scaffold, --allow-tools, --json, --no-publish, --output-dir)"
  - "live model access to claude-haiku-5-5 and claude-sonnet-5-5 for the A/B runs (owner's subscription)"
  - "jq"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/automate-loop/SKILL.md` (protocol context for the coordinator loop the evals drive) |

## Implementation Notes (for the worker)
- **Eval design.** Each case stages ONE existing golden case (`loomwright/scripts/fixtures/automate-golden/<case>/`: `input.md`, `next-step.results`, `gh.stub`, `tree/`, `setup`) into a scratch git repo through the case's scaffold. The scaffold reads the fixtures in place and never copies them into the eval dir.
  - The model plays the coordinator: it runs `automate-next-step.sh`, does what each instruction says, and answers each `spawn` with the canned report the fixture's `next-step.results` `call: --result …` lines carry. It must never really spawn a phase.
  - Pick 3–5 cases that between them cover `spawn`, `ask` (non-interactive and interactive), `park` and `done`.
  - Graders:
    - (1) parity: the normalised run file equals `expected.md` byte for byte, using the same normalisation as leg G.
    - (2) wrong questions: no ask-tool call unless the driver printed `do: ask`.
    - (3) skipped instructions: every printed instruction was answered.
- **Running it.** Use `--eval-dir evals/coordinator-model --runs 3 --model <id> --scaffold --allow-tools Bash --ablation none --no-publish --output-dir <scratch> --json <scratch>/<model>-run<k>.json`. `--no-publish` is required, because publishing to claude.ai is outward-facing. Keep results out of the repo.
  - Tokens: prefer item 03's `read-token-ledger.sh --per-item … --projects-dir …`. Where an eval child's transcript cannot be keyed that way, use the eval JSON's usage, and label every figure with its source.
- **Applying the setting.** The driver resolves and reports `coordinator_model`. No launch site in this item's Touches starts a coordinator with `--model`. If the A/B picks a cheaper model, the evidence must name the follow-up: wiring `automate-lanes.sh`'s lane spawn and the owner's own launch. Do not edit `automate-lanes.sh`, `commands/automate.md` or `ARCHITECTURE_CONTRACTS.md` here.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): `claude plugin eval` has no prior suite in this repo, and its script/command grader shape is unverified | MEDIUM | probe `claude plugin eval init --bare` plus `--help` first. If no deterministic grader type exists, the parity grader is an LLM grader fed the output of a `diff` the scaffold or case writes, and the AC5 mutation control proves it fails on a wrong expectation |
| Feasibility (Phase 2.5): the A/B spends real tokens (3 runs × 2 models × cases) and can trip the subscription weekly cap mid-run | HIGH | keep the suite small (3–5 cases, bounded `max_turns`), consider `--max-cost-usd`, run Haiku first. If the cap trips, record the partial runs honestly in the evidence and never claim parity from a partial set |
| Feasibility (Phase 2.5): the setting is reported but not applied at any launch site in Touches | MEDIUM | the default stays `session` unless the evidence qualifies a cheaper model. The evidence names the launch-site follow-up explicitly |
| Changing `ns_base()` touches every instruction, so a test or lane consumer that asserts an exact instruction key set could go red | MEDIUM | run `test-automate-next-step.sh`, `test-automate-lanes.sh`, `test-supervisor-next-step.sh` and `test-automate-golden.sh` (all four via `bash scripts/ci-local.sh`) before hand-back |
| The valve ledger breaks the driver's "exit 2 ⇒ nothing written" contract and the snapshot-based exit-2 legs, or writes on a re-print and breaks leg I | HIGH | the ledger is the ONE named exception (AC4): append only when a `--result` is processed (accepted, or refused for its shape), never on a usage error or a re-print. Exclude only that file from `snapshot()`, update §"Writers and failures" in the same change, and pin "a refusal appends exactly one line, nothing else changes" |
| The eval reports read as a green model when a run was partial or a grader no-oped | MEDIUM | AC5 mutation control. Report `<passed>/<total>` per model per run, never only an aggregate |
| `.supervisor/` is gitignored, so the ledger and the source requirement are not committed | LOW | expected: the ledger is runtime state. The evidence file is the committed record |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-20-coordinator-model-ab.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-20T09:46:09Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/632
- **Branch:** feature/coordinator-model-ab
- **Files changed:** 20
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 1
- **Heal reason:** needs_human
- **Heal remaining issues:** 3
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** coordinator_model setting (closed list, default session), the one-directional escalate-on-failure valve ledger, a claude plugin eval A/B suite and the evidence doc shipped. Haiku 5.5 and Sonnet 5.5 each scored 9/12 parity with 0 wrong questions; every failure is one sandbox-broken case (mktemp -d refused), so the default stays session. Iteration 1 fixed 3 findings (stale-lock valve wedge, AC6 Opus run recorded 3/4, bad --root counted). Iteration 2 NEEDS_HUMAN: AC6's "single passing run on the chosen model" is unmet for an environment reason (owner decision: amend AC6 or hold the merge); MEDIUM advisory: the valve counts session-era FAILs; CI ci red on e6f7410 from an unrelated test-ci-slot.sh (P) race, failed job re-run. Driver suite 184/0, golden 65/0, ground truth 2/2.

## Not verified
- **eval case non-interactive-escalated-park under the claude plugin eval OS sandbox** — validation-gate's mktemp -d is refused there; root cause not established; it fails parity for both models alike (subtask 1)
- **bash scripts/ci-local.sh full pool** — FAIL after 2425s: six exit-124 timeouts at load average about 46 (test-automate-next-step.sh passes standalone); W19 reads this checkout's untracked .supervisor/requirements; test-automate-lanes J3/J4/K1b in a lane checkout; not re-run on a clean base (subtask 1)
- **eval suite passing run on the chosen model (session)** — the A/B measured only the two candidate ids; a later Opus run scored 3/4 (same sandbox case) (subtask 1)
- **PR body links to the evidence file and the 06 supersession statement** — no PR opened by the worker; the Supervisor's PR body links both (subtask 1)
