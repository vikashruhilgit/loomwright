# Supervisor Job: The loop proposes — findings become candidate work items

## Environment
- **Project:** ~/Documents/work/AI/loomwright-stateloop (worktree; primary checkout is ai-agent-manager)
- **CLAUDE.md:** ✓ Found (fresh, 2026-09-05)
- **Git:** branch `automate/invention-base` @ 94e91ec (== origin/main); one tracked modification carried in (`.supervisor/postmortem/results.jsonl`, +1 postmortem line for PR #194 — legitimate evidence, see Risk 6)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **jq:** ✓ /usr/bin/jq 1.7.1-apple
- **main CI:** ✓ green at 94e91ec
- **`.supervisor/floor/floor.json`:** regenerated at this HEAD before the run — `repo_head: 94e91ec`, `generated_at_epoch: 1788692013`, 235 classified entries, `convention_mismatch: 109`
- **Blockers:** 0 | **Warnings:** 1 (carried-in tracked modification)

## Feasibility
**GO.** Every dependency the requirement names was verified present on this checkout, and independently re-verified by Plan Review:
- `loomwright/scripts/build-floor.sh` exists with the discipline to mirror: `set -uo pipefail` (`:48`, no `set -e`), `command -v jq` skip-guard (`:62`), terminal `exit 0` (`:1088`).
- The postmortem detail surface carries every field the proposer needs per entry: `class`, `flow_stage`, `round`, `line`, `index`, `self_heal_miss`, `evidence`, plus `class_distribution`.
- **Per-input mtimes exist at `surfaces.<name>.mtime_epoch` on 9 surfaces — there is no top-level `inputs` key.** An implementation that looks for one will find nothing and silently treat every basis as fresh.
- `.gitignore:78` is `.supervisor/*` — proposals are machine-local by construction.
- Vendor-coupling ratchet is `scripts/check-vendor-coupling.sh` (**repo root, NOT `loomwright/scripts/`**). **Baseline BEFORE: 610 references / 78 files / 0 breaches / 405 scanned.**

**Do not hard-code ledger counts.** The requirement quotes 233 entries / 107 `convention_mismatch` (frozen 2026-09-06 morning); the live ledger reads 235 / 109. AC1 requires counts to be *recomputed from `floor.json` and matched*, never matched against either frozen table.

## Task
**Goal:** Add `propose-work.sh` — a deterministic, advisory, jq-based reader that turns the already-aggregated `floor.json` ledger into candidate requirement files under `.supervisor/requirements/proposed/`, each citing the ledger evidence it rests on, for a human to promote or delete.

**Problem context:** The learning loop records and never proposes. 109 recorded `convention_mismatch` entries have produced 3 rules. Every item this system has executed was human-typed — `/automate`'s three intake sources are all human-seeded. This is the intake half of a mill that invents its own work.

**Hard boundary:** it proposes; it never queues, ranks, scores, dispatches, or merges. The human gate sits at dequeue, not at write.

**Stated thresholds (fixed here so they are not invented at implementation time):**
- **Emission threshold:** a `(class, flow_stage)` pair is emitted at **≥ 10** entries. Configurable via one named variable at the top of the script; no score, no rank, no top-N.
- **Staleness threshold:** `floor.json` older than **24h** (by `generated_at_epoch`) ⇒ propose nothing, name the age, exit 0. **This DOES interact with AC1b's live-basis arm — a present-but-stale `floor.json` correctly emits nothing, so AC1b must treat that as a loud skip, not a failure.** AC1b below is three-outcome for exactly this reason.
- **`flow_stage: unknowable`:** a `(class, unknowable)` pair clears the threshold (18 entries today) but yields an unactionable candidate. Such a proposal MUST name what `unknowable` means — that the flow stage could not be attributed — so a human is never handed a candidate they cannot act on.

## Acceptance Criteria

**Emission (each requires a NON-EMPTY emission — an assertion that passes on zero output is not evidence):**
- [ ] AC1a **(hermetic, gates CI)** Given the committed golden fixture `loomwright/scripts/fixtures/propose-work/floor-golden.json`, the script emits ≥1 proposal for `convention_mismatch`, and every count quoted inside that proposal is independently recomputed from the fixture by the test and matches. The fixture is stamped fresh relative to the 24h threshold at test time (do not bake an absolute epoch that ages into staleness). **The test harness itself hard-fails with a named reason if `jq` is unavailable — only the script under test may skip.** Otherwise AC1a degrades into the same silent CI skip AC1b was split off to prevent.
- [ ] AC1b **(live basis, local-only — THREE outcomes, not two)** Against the real `.supervisor/floor/floor.json`:
      - **present AND fresh (< 24h)** ⇒ assert ≥1 `convention_mismatch` proposal with recomputed-and-matching counts;
      - **present BUT stale (≥ 24h)** ⇒ SKIP LOUDLY naming the age (this is AC5's correct behaviour, not a failure);
      - **absent** ⇒ SKIP LOUDLY naming the absence.
      A two-outcome "present ⇒ must assert" reading goes deterministically red the day after `floor.json` is generated, with no code defect. Rationale for the split from AC1a: `.gitignore:78` is `.supervisor/*`, so `floor.json` does not exist on a fresh clone or CI runner, while `loomwright/scripts/test-*.sh` IS auto-globbed by `.github/workflows/ci.yml:72` — AC1 alone would exercise the fail-safe skip path in CI and assert nothing. **AC1a is what actually gates CI.**
- [ ] AC2 Every emitted proposal carries a `## Evidence` section citing ≥3 distinct ledger entries (each with `class`, `flow_stage`, `round`, source `line`, and the `evidence` string) plus the `generated_at_epoch` it read — asserted by parsing the emitted file, not by reading the script.
- [ ] AC3 Given a synthetic `floor.json` in which class X is below threshold **and sibling class Y is above it**, no proposal is emitted for X, a proposal IS emitted for Y (the positive control that proves the run was capable of emitting at all), and the run names X as below-threshold.

**Suppression:**
- [ ] AC4a Given a `proposed/` already containing a file covering the same evidence set, the second run emits nothing new and reports the suppression with its basis.
- [ ] AC4b **(Scope 4, second arm)** Given a requirement file carrying `## Status: done` that covers the same evidence set, the candidate is suppressed and the run reports the suppression naming that file as the basis. **Done-stamped requirement files DO exist in the working store** (24 of them in the primary checkout), **but `git ls-files .supervisor/requirements/` is empty — none are committed**, because `.gitignore:78` is `.supervisor/*`. So there is no reproducible positive case on a fresh clone or CI runner, and driving this AC off the live store would make it pass on the author's machine and never run in CI. It MUST be driven by the committed fixture `loomwright/scripts/fixtures/propose-work/done-requirement.md` against a temp requirements root, **with a mutation control that deletes the supersession check and asserts AC4b then FAILS.**

**Fail-safe arms (each must be reached by an assertion that FAILS when the guard is deleted):**
- [ ] AC5 Given a `floor.json` older than 24h, the script proposes nothing, names the age, and exits 0.
- [ ] AC6 Given `jq` absent, a missing `floor.json`, and a malformed `floor.json` (three separate cases), the script skips with a named reason and exits 0 in each.

**Determinism and blast radius:**
- [ ] AC7 **Two INDEPENDENT runs into two SEPARATE empty output directories**, against the same `floor.json`, both required to emit ≥1 proposal, compared byte-for-byte. **Do NOT satisfy this by re-running into an already-populated dir** — AC4a suppression means run 2 cannot alter on-disk content whether or not generation is deterministic, which makes the assertion a tautology satisfied by a script containing `$RANDOM` or unsorted `jq` iteration. **Mutation control: remove the sort before emission and assert AC7 then FAILS.**
- [ ] AC8 No file outside `.supervisor/requirements/proposed/` is created or modified — asserted by hashing **the filesystem tree rooted at the repo root, excluding `.git/` and `.supervisor/requirements/proposed/`** before and after, not by reading the code. **Not a git-tracked-tree hash:** `.supervisor/*` is gitignored, so a git reading renders both the intended writes and any stray `.supervisor/` write invisible and the assertion passes with the mechanism deleted. Include a mutation control that removes the write-path guard and asserts this test then FAILS. **All synthetic fixtures and temp copies are materialised OUTSIDE the repo root (`mktemp -d`)** — staging them anywhere under the repo makes AC8 fail on the test's own scratch files.
- [ ] AC9 No emitted proposal contains a score, rank, priority, or ordering field — asserted by grepping the emitted files, on a run that emitted ≥1 proposal.

**Contract surface:**
- [ ] AC10 **(Scope 6)** `.supervisor/requirements/proposed/README.md` is created by the script and states, in its text, that `proposed/` is deliberately NOT an `/automate --folder` target and that promotion is a human moving a file out of it — asserted by grepping the emitted README, so a future session cannot mistake `proposed/` for a backlog. **The same contract sentence MUST also appear in `propose-work.sh`'s own header comment** — the README lives only in a gitignored, must-be-generated file, so without this a fresh clone carries no record of the contract at all. (It stays out of `provides:` deliberately: declaring a gitignored runtime artifact would make `outputs_verified` fail on a file legitimately absent from the diff.)

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | `propose-work.sh` + its self-test + fixtures | create: script, test, 5 fixtures; runtime-emitted (gitignored): `proposed/README.md`; modify only if the ratchet moves: `vendor-coupling-manifest.json`, plus the release lockstep surfaces | LAUNCHABLE |

```yaml
# Subtask 1 — propose-work.sh + self-test + fixtures
provides:
  - {kind: "file", path: "loomwright/scripts/propose-work.sh"}
  - {kind: "file", path: "loomwright/scripts/test-propose-work.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/propose-work/floor-golden.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/propose-work/floor-below-threshold.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/propose-work/floor-stale.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/propose-work/floor-malformed.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/propose-work/done-requirement.md"}
requires: []
lanes:
  - "loomwright/scripts/propose-work.sh"
  - "loomwright/scripts/test-propose-work.sh"
  - "loomwright/scripts/fixtures/propose-work/**"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "jq >= 1.6"
```

## Parallelism Analysis
single-agent (no fan-out)

- Recommended workers: 1
- **`context-bound` plausibly FIRES on its lines arm, and the single subtask is chosen anyway — deliberately.** The threshold is *>12 files OR >800 changed lines*. The files arm is clear (~6). The lines arm is not: the comparable self-test `loomwright/scripts/test-build-floor.sh` is 2,929 lines and `build-floor.sh` is 1,088, so a mirror-discipline script plus a 10-AC self-test with mutation controls is unlikely to land under 800 changed lines.
- **Why no split regardless:** every candidate cut writes the same two files. The only coherent cut is by AC group (emission/determinism vs the negative and fail-safe arms) and both halves edit `propose-work.sh` *and* `test-propose-work.sh` — a `file-conflict` split by construction, strictly worse than one subtask.
- **Context mitigation:** build the self-test AC-by-AC, running it after each AC lands, rather than authoring it in one pass. If the worker exhausts context, stop at a green partial suite and record which ACs remain — do not stub an AC to appear complete.

## Skill References
- `quality-checklist` — pre/post-task gates
- `context-setup` — CLAUDE.md + repo conventions
- `unit-testing` — assertion discipline for the 10-AC self-test
- `commit` — conventional commit format

## Risk Assessment

1. **Vacuous tests (HIGHEST — this repo's recorded failure class).** Several ACs are worded to forbid implementation-reading assertions, because an assertion that reads the implementation passes with the mechanism deleted. **Mutation-control every negative-path assertion** — AC3, AC5, AC6, AC8, AC9. An AC that still passes when its guard is removed is not evidence. AC8 carries an explicit mutation control for exactly this reason.
2. **Assertions that pass on empty output.** "Byte-identical on re-run" (AC7) and "contains no rank field" (AC9) are both satisfied by emitting nothing; "no proposal for the below-threshold class" (AC3) is satisfied if the run emitted nothing for an unrelated reason. Every such AC now carries a non-empty-emission precondition or a positive control — preserve those preconditions; do not simplify them away.
3. **`exit 0` + `set -uo pipefail` can silently swallow a real failure.** The *script* must be fail-SAFE (advisory reader, never breaks its caller); the *self-test* must NOT inherit that leniency. Known local traps: `producer | grep -q` returns 141 under `pipefail` even on match; `local x="$(...)"` discards the command's status; `... || echo 0` appends a second line. Each makes an assertion vacuous while everything stays green.
4. **Staleness basis is per-surface, not top-level** (`surfaces.<name>.mtime_epoch`; there is no top-level `inputs`). Test both arms of the 24h threshold, and stamp fixtures relative to test-run time so they do not age into staleness.
5. **Absent evidence must be omitted, never defaulted** — `build-floor.sh`'s rule, paraphrased not quoted (its own wording at `:23` is "OMITTED rather than defaulted" and at `:77` "unreadable => null, never a plausible default"). A fabricated count inside a proposal is the exact failure this item exists to reduce.
6. **Carried-in working-tree modification.** `.supervisor/postmortem/results.jsonl` has one uncommitted appended line (a `/pr-postmortem` record for PR #194) present before this job started. It is legitimate evidence, not worker output. It will ride along in this PR's diff — do not revert it, and do not treat it as part of this change when reviewing.
7. **Determinism (AC7).** No run timestamps, no `$RANDOM`, no hash-order iteration, no unsorted `jq` object emission. Sort every collection before emitting.
8. **Release-surface obligation.** Re-run `bash scripts/check-vendor-coupling.sh` after the change and **report the delta whatever it is** against the baseline (610 refs / 78 files / 0 breaches). If it moves, classify the new files explicitly with allowances regenerated via `--print-allowances`, never hand-typed.
9. **No new agent, no new hook** (requirement non-goal) — agent/command/skill/hook counts stay unchanged, no `prompt-token-budgets.json` entry. `loomwright/scripts/test-*.sh` is auto-globbed by `.github/workflows/ci.yml:72`, so the new self-test needs no registration but WILL gate CI — which is why AC1a exists as the hermetic, fixture-backed arm.

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Base Branch:** main

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Outcomes Rubric

- The loop proposes its own work for the first time, and every proposal shows its evidence.
- Nothing is ranked, scored, or queued; the human decides at dequeue.
- A stale or unreadable basis yields silence with a named reason, never a plausible-looking proposal.
- One reader, one input file; no raw surface is parsed a second time.
- Byte-identical on re-run; provably writes nothing else.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-06-findings-to-proposals.md
