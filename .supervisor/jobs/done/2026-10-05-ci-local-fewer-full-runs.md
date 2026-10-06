# Supervisor Job: ci-local.sh — keep every run's log (--last), add a mapped --affected inner-loop check (parallel-automate/09)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes-v2/s3-d
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/parallel-automate/09-ci-local-fewer-full-runs.md
- **Base commit:** 3217da0a7fa49a315d60625321be2ae6b20637b9

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + git; same stack as `scripts/ci-local.sh` today |
| 2 | Dependency Availability | GO | Reuses `loomwright/scripts/ci-slot.sh dir` (item 08's shared state dir) and `loomwright/scripts/run-self-tests.sh` (the pool runner); both on main |
| 3 | Architecture Fit | GO | Extends the one pre-push command; `ci.yml` and the remote `ci` job untouched |
| 4 | Scope vs Supervisor Capability | GO | 5 files, one domain, one worker |
| 5 | Hard Blockers | GO | none |

**Overall Verdict:** GO

## Task
**Goal:** Make a lane run the full suite once per push: every `ci-local.sh` run keeps its transcript (readable later with `--last`), and a new `--affected` mode runs only the suites mapped from the changed files while iterating — never stamping a pass.

**Problem Statement:**
Lane lead sessions need to check their work between pushes without starting a full suite each time, because at 5–10 lanes every avoidable full run is CPU the other lanes wait for.
Currently, a run's output is gone once the tool call returns (sessions re-ran the suite only to read it) and the only inner-loop alternative is hand-picking one suite. In S1 v2 each lane started `ci-local.sh` 6 times for 2–4 pushes.
Success looks like: at most one full run per push (plus reruns after a failure), past results read with `--last`, and `--affected` covering the iteration loop.

## Acceptance Criteria
- [ ] AC1 — Given any `ci-local.sh` invocation that actually runs the pool (no flag, `--force`, or `--affected`), when it starts, then it writes the complete transcript (everything it prints, stdout + stderr, including the runner's FAIL banners) to `<state>/runs/<key>-<YYYYmmddTHHMMSSZ>-<pid>[-affected].log` where `<state>` is the directory `bash loomwright/scripts/ci-slot.sh dir` prints (item 08's repo-keyed shared dir, already used for `pass/`), and prints the log path as its FIRST output line and again as its LAST output line (also on FAIL and on a TERM/INT exit). The log is created before the slot acquire (so a run TERMed while queued still names it). A cached PASS found BEFORE the slot acquire and `--list` write no log and run nothing; a waiter that ends on the post-slot cache re-check (arm Q) ends its log with the verdict line `ci-local: PASS (cached) …`, which `--last` reports as PASS. Every finished log's last content line is a verdict line: `ci-local: PASS …`, `ci-local: PASS (cached) …`, `ci-local: FAIL …`, or (affected runs) the affected marker.
- [ ] AC2 — Given saved logs, when `ci-local.sh --last` runs, then it prints the newest FULL-run log (never an `-affected` log) whose key equals the current content key, followed by a one-line verdict `ci-local --last: PASS|FAIL <log path>` read from the log's own final verdict line; when no full-run log matches the current key it prints the newest full-run log overall with `ci-local --last: stale-key (log key <k>, current key <k>) <path>`; with no logs at all it says so and exits 1. A selected log with no verdict line (interrupted by TERM/INT, or still being written by a run in another checkout sharing the repo-keyed `runs/` dir) is reported as `ci-local --last: INCOMPLETE <path>` with exit 1 — never as PASS. `--last` runs no gate and writes nothing outside its own temp dir (no log, no stamp, no slot ticket). Exit: 0 PASS, 1 FAIL / INCOMPLETE / stale-key / none.
- [ ] AC3 — Given more than 20 logs in `<state>/runs/`, when a new log is created, then the oldest are deleted so at most 20 remain (ordered newest-first by the name-embedded timestamp, ties by `ls -t` mtime order; portable to BSD + GNU — no `stat -f`/`-c`, no GNU-only `date`/`sort` flags).
- [ ] AC4 — Given a working tree, when `ci-local.sh --affected` runs, then the changed set is: files differing between `git merge-base origin/main HEAD` and the working tree (tracked, staged or not) plus untracked non-ignored files (fallback when `origin/main` is absent: say so and use `HEAD`); each changed path maps: `loomwright/scripts/<x>.sh` ⇒ `loomwright/scripts/test-<x>.sh` when it exists; any `test-*.sh` under `scripts/`, `loomwright/scripts/` or `loomwright/scripts/adapters/*/` ⇒ itself (if it still exists); root `scripts/<x>.sh` ⇒ `scripts/test-<x>.sh` when it exists; PLUS every `scripts/check-*.sh` and `scripts/validate-version.sh` gate line `ci.yml` names (the cheap static gates — deliberately included so version drift is caught while iterating; `test-check-*.sh` lines run only when a changed file maps to them) (with its `--self-test` argument, via the same wrapper mechanism the full run uses, the vendor-coupling gate still on the temp index). The deduped plan runs through `loomwright/scripts/run-self-tests.sh` under a shared CI slot exactly like a full run.
- [ ] AC5 — Given `--affected`, when any changed file has no mapped suite, then it is listed under a `not covered by --affected:` heading (deleted files included); when nothing changed it still runs the cheap `check-*` gates and says the changed set was empty.
- [ ] AC6 — Given `--affected` on any outcome (PASS or FAIL), then it NEVER creates, touches or removes a pass stamp in `<state>/pass/`, and its LAST line before the log-path line is exactly `affected-only — not a pre-push gate; run ci-local.sh before pushing`. `--affected` combined with `--list` prints the affected plan (changed files, mapped suites, uncovered files) and runs nothing; `--affected`/`--last`/`--force` conflicting combinations exit 2 with a usage message.
- [ ] AC7 — Given no flag, when `ci-local.sh` runs, then the gate list, plan order, cache key, stamp rule, slot behaviour and exit codes are byte-for-byte the same as on base (the only additions are the two log-path lines and the transcript file); every existing arm of `scripts/test-ci-local.sh` still passes unmodified except where an assertion pins exact first/last output lines.
- [ ] AC8 — Given the docs, then `AGENT_GUIDELINES.md` §"Pre-push: one command" says: while iterating use `bash scripts/ci-local.sh --affected` (or the one suite you touched); before each push, ONE full `ci-local.sh`; to see a past result use `--last`, never a re-run; and `loomwright/agents/worker.md` Step 5 item 2 says the same in shipped-plugin-neutral words (the project's affected-only / single-suite check while iterating, the project's pre-push command once before a push, read a saved result instead of re-running) — naming NO repo-local path such as `scripts/ci-local.sh`; `ci-local.sh --help` (its header) documents `--affected` and `--last`.
- [ ] AC9 — Given the change, then `changelog.d/parallel-automate-09-ci-local-fewer-full-runs.md` exists as a valid fragment (`<!-- bump: minor -->`, headline, prose body) and NO version file (`plugin.json`, `marketplace.json`, `CHANGELOG.md`) is edited (parallel-wave rule: lanes write fragments only).

## Outcomes Rubric
- `scripts/ci-local.sh` handles `--affected` and `--last` in its argument `case` and documents both in its header comment block.
- `scripts/ci-local.sh` writes run logs under a `runs/` directory of the `ci-slot.sh dir` state dir and prunes them to 20.
- `scripts/ci-local.sh` contains the exact string `affected-only — not a pre-push gate; run ci-local.sh before pushing`.
- `scripts/test-ci-local.sh` has new arms covering: --affected maps a changed script to its suite, lists an unmapped change, never writes a pass stamp; --last finds the newest log for the key and reports stale-key after the tree changes; pruning keeps 20.
- `AGENT_GUIDELINES.md` mentions both `--affected` and `--last` in its Pre-push section, and `loomwright/agents/worker.md` does not contain the string `scripts/ci-local.sh`.
- `changelog.d/parallel-automate-09-ci-local-fewer-full-runs.md` exists and no change touches `CHANGELOG.md` or either `plugin.json`/`marketplace.json`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | ci-local.sh run logs + --last + --affected, tests, guideline/worker wording, changelog fragment | AC1–AC9 | 4 modify, 1 create | `skills/ci-cd/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "scripts/ci-local.sh"}
  - {kind: "symbol", path: "scripts/ci-local.sh", name: "--affected"}
  - {kind: "symbol", path: "scripts/ci-local.sh", name: "--last"}
  - {kind: "symbol", path: "scripts/ci-local.sh", name: "affected-only — not a pre-push gate; run ci-local.sh before pushing"}
  - {kind: "file", path: "scripts/test-ci-local.sh"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "--affected"}
  - {kind: "file", path: "changelog.d/parallel-automate-09-ci-local-fewer-full-runs.md"}
requires: []
lanes:
  - "scripts/ci-local.sh"
  - "scripts/test-ci-local.sh"
  - "AGENT_GUIDELINES.md"
  - "loomwright/agents/worker.md"
  - "changelog.d/parallel-automate-09-ci-local-fewer-full-runs.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
external_requires:
  - "git >= 2.30 (merge-base, ls-files -o --exclude-standard, diff --name-only)"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | none | NO |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/ci-cd/SKILL.md`, `skills/unit-testing/SKILL.md` |

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.
  - id: documentation-wording-that-carries-a-contract-a-heading-a-gate-greps-for-a-sentence-that-states-a-guarantee-is-treated-as-an-interface-renaming-it-is-a-change-to-that-interface-and-its-consumers-move-with-it
  - enforcement: advisory
- A count or version claim lives in exactly ONE authoritative machine-readable place … prose says 'see hooks.json', never restating a literal count.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory

## Implementation Notes (for the worker)
- **Do not break the heading `### Pre-push: one command`** in `AGENT_GUIDELINES.md` — `CLAUDE.md` cites it by name (house rule: contract wording is an interface). Edit the bullets under it.
- **Transcript capture:** wrap the existing run so every stdout/stderr line goes to both the terminal and the log (e.g. `exec > >(tee -a "$log") 2>&1` after the log path is known, or an explicit `tee` around the runner call). The log must end with a parseable verdict line (`ci-local: PASS …` / `ci-local: FAIL …` / the affected marker) so `--last` can classify it without re-running. Make sure the EXIT trap still prints the log path and that a `tee` child is flushed/reaped before exit; test-ci-local arm (T) (TERM while queued must exit within seconds) must stay green.
- **Log name** `<key>-<YYYYmmddTHHMMSSZ>-<pid>.log` (full key so `--last` can match on prefix; pid avoids same-second collision); `-affected` suffix before `.log` for affected runs. The key's existing `<tree>-<base>-<OS>` form is unchanged.
- **Root vs loomwright test globs:** `--affected` must build its plan from the same sources the full plan uses (ci.yml gate lines, `scripts/test-*.sh`, `loomwright/scripts/test-*.sh`, `loomwright/scripts/adapters/*/test-*.sh`) so it can never schedule a file the full run would not.
- **Tests:** new arms in `scripts/test-ci-local.sh` drive the fixture repo already built there (`build_fixture`), sandboxed `XDG_STATE_HOME`. Needed arms: (AF1) change a fixture `loomwright/scripts/<x>.sh` ⇒ `--affected` runs its `test-<x>.sh` + the `check-*` gates and NOT the other tests; (AF2) an unmapped change (e.g. a README) is listed under `not covered by --affected:`; (AF3) `--affected` on a green tree leaves `pass/` empty — MUTATION CONTROL: assert a mutated copy that stamps is detected (the Validation step 4 failure this item must catch); (LA1) after a full run `--last` prints that log and PASS; (LA2) change the tree ⇒ `--last` says `stale-key`; (LA3) `--last` never prints an `-affected` log; (PR) seed 25 logs ⇒ after one run 20 remain and the newest survives; (LG) first and last output line of a run are the log path; (IN) a log cut off without a verdict line (e.g. a run TERMed while queued) ⇒ `--last` says INCOMPLETE, exit 1; (QC) a waiter ending on the post-slot cache hit leaves a log whose verdict `--last` reports as PASS. Update the header's arm list.
- **Worker prompt budget:** `loomwright/agents/worker.md` has ~824 tokens headroom (`bash scripts/check-token-budget.sh`). Keep the wording change to one short sentence; if the budget gate fails, raise `.agents.worker.budget` in `loomwright/docs/prompt-token-budgets.json` to measured+10% and add the mirror row note in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" per CLAUDE.md "Adding or Modifying Agents" (both in this subtask's lanes for that reason only).
- **Shipped-plugin neutrality:** `worker.md` is installed into arbitrary user projects — no `scripts/ci-local.sh` path in it; `scripts/check-vendor-coupling.sh` and `scripts/check-shared-prefix.sh` must stay green.
- **Pre-push:** run `bash scripts/ci-local.sh` once at the end (it is this repo's pre-push command); report the Validation numbers asked for in the source requirement (base vs branch `<passed>/<total>`, an `--affected` wall-clock on a one-file change, and `--last` output).

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Prior churn (postmortem ledger): `AGENT_GUIDELINES.md` (17 entries), `loomwright/agents/worker.md` (10), `scripts/ci-local.sh` (1); recurring classes drain_churn, convention_mismatch, execution_bug; self_heal_miss seen — source "Prior churn (postmortem ledger)" | HIGH | Keep the guideline/worker edits minimal and contract-neutral; run the worker suite (`test-*` that grep worker.md) and `check-token-budget.sh`, `check-shared-prefix.sh`, `check-doc-currency.sh` before handing back |
| `tee`/process-substitution changes signal and exit-code behaviour (bash 3.2 on macOS): a TERM could leave an orphan `tee`, or `$?` could report tee's status | HIGH | Capture the runner's exit code explicitly (not through a pipe), reap the tee child in the cleanup trap, keep arm (T) green; validate with `bash scripts/test-ci-local.sh`, not an inline paste |
| `--affected` mapping misses a suite whose name differs from the script (honest limit stated in the requirement) | MEDIUM | Final message always says it is not a pre-push gate; the full run before push stays mandatory; uncovered files are listed |
| Log directory grows across lanes sharing one repo-keyed state dir | LOW | Prune to 20 at every log creation |
| Worker prompt token budget (824 headroom) | LOW | One sentence; raise budget per convention only if the gate fails |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-05-ci-local-fewer-full-runs.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-05T17:17:24Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/392
- **Branch:** feature/parallel-automate-09-ci-local-fewer-full-runs
- **Files changed:** 5
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Resumed inline from Phase 4 after the original session died mid-pre-push run. Full ci-local first failed 2/143 (locale-prefix) → worker fix 4dbcfa9 → PASS 143/143. Phase 4.5 iteration 1 FAIL (HIGH: prune deleted in-flight logs) → fix 1b89a49 → iteration 2 PASS. Rubric 6/6; ground truth 2/2; rules gate none. 6 dismissed findings (2 distinct MEDIUM, 1 MEDIUM AC3-deviation, LOW nits) posted as marker comment.
