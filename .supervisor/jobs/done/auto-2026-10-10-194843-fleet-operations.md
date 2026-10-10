# Supervisor Job: Fleet operations — wave close (fleet closeout + operator wave plan) and stamped policy answers for routine lane questions

## Environment
- **Project:** lane clone `L1` of `ai-agent-manager` (`<primary>-lanes/automate-2026-10-10-194230/L1`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (lane clone; origin = vikashruhilgit/loomwright)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/parallel-automate/21-fleet-operations.md
- **Base commit:** 4e0f255753ee225d11f0bd7d82c15434a0ba9d44

> **Warning (1):** this checkout is lane `L1` of the `--parallel 3` wave `automate-2026-10-10-194230`. Sibling lanes L2 (`churn-ledger/01`, touches `.agent/rules/process.json`) and L3 (`twin-loop/07`, touches `loomwright/docs/RULES_BASELINE.md`) run at the same time in their own clones. **Do not edit `.agent/rules/*` or `loomwright/docs/RULES_BASELINE.md`.** This PR carries a `changelog.d/` fragment and NO version bump (lane PRs never bump; the bump is the wave branch's last commit).

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + `jq` + markdown, the repo's existing surface. |
| 2 | Dependency Availability | GO | `jq`, `git`, `gh` present. No new dependency. |
| 3 | Architecture Fit | GO | Extends `automate-lanes.sh` (lane lifecycle) and the existing `rules-check.sh` stamp valve. Adds no merge path (owner decision 2026-10-10: the operator runs the wave-branch merges). |
| 4 | Scope vs Supervisor Capability | CAUTION | Large: two parts plus amendments in one PR (owner decision 2026-10-10). Split into 3 subtasks (context-bound + genuine-parallelism). |
| 5 | Hard Blockers | CAUTION | Requirement Scope 7 asks for the `automate-followups/22` sweep dry-run, but no sweep exists on `main` (22 is parked into the pending `39-engine-hygiene`). The fleet closeout reports `sweep: unavailable` instead. |

**Overall Verdict:** CAUTION (2 findings carried into Risk Assessment)

## Task
**Goal:** Close a `--parallel` wave without hand steps beyond the owner's merges, and stop routine lane questions from reaching the owner. (A) Add a stepwise, resumable **fleet closeout** in the coordinator, a lane-side finalize after the closeout, and a read-only **wave plan** that prints the operator's wave-branch integration commands. (B) Add a **gate catalog** with stable gate codes, a human-stamped **policy** (project policy through the existing `rules-check.sh` stamp valve, plus a per-wave owner answer set), applied by the lane's relay hook as an exact lookup. Add a policy digest and a batched inbox to `lane-status`, and remove the one-item queue confirm inside a lane.

**Owner decisions (2026-10-10, Launch Pad Phase 2, recorded in run `automate-2026-10-10-194230-L1` `## Progress`):**
1. **Part S: operator merges.** Nothing in the engine merges into `wave/*`. Part S ships as docs plus a READ-ONLY `wave-plan` subcommand that prints the exact commands. A guard test proves no lane subcommand merges or pushes a lane branch.
2. **Scope 3 (release lane) and Scope 4 (stamped release command) are dropped**, superseded by the 2026-10-06 amendment: the bump is the wave branch's last commit, run by the operator. `wave-plan` prints `bash scripts/bump-version.sh` as that step only when the repo has that file. Otherwise it prints `# run this project's release step`.
3. **One PR for A + B**, with Validation labelled by part. Running-system steps that need a real two-lane wave go under "Not verified".

**Problem Statement:** A `--parallel` coordinator owner needs the wave to close itself after they merge. Today a merged wave leaves lane clones, an unreleased `automate-lanes:<run_id>` lock (no line releases it; only the 1800 s reclaim does), an unchecked parent Queue and lane run files never stamped `## Status: done`. Lanes also relay every routine formality: S1 v2 relayed 15 questions in 2 h, 8 of them routine, and S3 waves relayed 29 and about 40, roughly a third routine. Success: after the owner merges the wave PR, `fleet-closeout` (re-run on each `--resume`) closes out every lane, removes the clones, checks off the parent Queue, reports leaks and releases the lock. A stamped policy answers the catalogued routine gates, and only real decisions reach the owner, batched.

## Acceptance Criteria

### Part A — wave close + fleet closeout
- [ ] **A1 (lane finalize).** Given a lane whose `lane-convert-ready` re-run took it to `done / awaiting_go` and branch mode is ON, when that re-run completes, then it also runs `automate-helpers.sh finalize-empty <the lane's run file>` inside the lane: the run file reads `## Status: done`, and its `trail-pr --reason done` meta push goes through the evidence gate. The output carries one `lane-convert-ready: finalize — <finalize-empty line>` line. With branch mode OFF, finalize is NOT run (it would open a trail PR) and the line reads `lane-convert-ready: finalize skipped — metadata mode off`. A `done/awaiting_go` lane already `## Status: done` is a no-op (`finalize-empty: skipped — not paused`).
- [ ] **A2 (fleet closeout — new subcommand `fleet-closeout <parent_runfile>`).** It runs in the coordinator's primary checkout and is stepwise and idempotent: each call performs every step it can, prints ONE line per lane and per step (`fleet-closeout: <step> — <detail>`), and stops at the first step that must wait. Steps, in order:
  1. **pull:** `meta-sync.sh pull --branch <mode branch>` (branch mode only; failure ⇒ `fleet-closeout: pull FAILED — <reason>`, exit 2, nothing else runs).
  2. **per lane**, read `lane-status`:
     - `merged` and the lane run file is not `## Status: done` and no live lane process and no live watcher ⇒ **backstop**: run `lane-convert-ready <lane_dir>` (the existing sanctioned coordinator→lane closeout path: `closeout --no-trail` + A1 finalize + pushes). This replaces the requirement's `lane-launch --resume` backstop — see Risk Assessment.
     - Not yet merged (`awaiting_merge`, `ready_for_release`, `escalated`) ⇒ `waiting — <lane> <state>`.
     - `gone` ⇒ `human — <lane> gone (PR closed unmerged): lane-remove <lane_dir> --abandon` (never auto-abandoned).
     - A `.meta-push-failed` marker in the lane ⇒ `human — <lane> meta-push-failed: <reason>`.
  3. **parent check-off:** for each lane whose run file reads `## Status: done` and whose item is still `- [ ]` in the parent `## Queue`: `queue-checkoff <parent_runfile> <item>` (no reason argument) + one `progress-append` line `fleet closeout: <lane> <item> done (PR <url>)`.
  4. **primary sync:** `git pull --ff-only` when the primary is on its base branch with no tracked modification (same refusal set as `closeout`'s `_sync_primary`: a refusal is a `skipped — <reason>` line, never a reset).
  5. **lane removal:** `lane-remove <lane_dir>` for each closed-out lane (no `--stop`: a live watcher or `claude -p` refuses, re-checked on the next call — never an in-session wait). The refusal text is printed as `waiting — <lane> <refusal>`.
  6. **after the last lane is removed:** `rmdir` the `<primary>-lanes/<run_id>/` directory only when empty. Otherwise print `kept <dir> — contents: <names>` (salvage and `L<n>.*` logs are kept by design). Then `lane-status <parent_runfile> --leaks` with its first line appended to the parent `## Progress` (`fleet closeout leaks: <first line>`). Then `sweep: unavailable (automate-followups/22 not shipped)`. Then **main health**: read the `ci` check conclusion of `origin/<base>` HEAD via `gh` — `failure` ⇒ append `wave_paused: main_red after <sha>` to the parent Progress and print it (no revert, no block). Then, when the parent Queue has no `- [ ]` left, `run-lock.sh release --owner "automate-lanes:<run_id>"` and print `fleet-closeout: wave closed — lock released`.
- [ ] **A3 (no new merge path).** `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` resolves to the same five surfaces CLAUDE.md §"Failure-Mode Invariants" lists. `git diff origin/main -- loomwright/scripts/automate-helpers.sh` shows no change inside `gate_eval`. `git grep -nE 'gh pr merge|gate-eval' loomwright/scripts/automate-lanes.sh` shows no executable use (the allowlist/denylist lines that NAME the tokens are pre-existing and allowed).
- [ ] **A4 (wave plan, Part S — new subcommand `wave-plan <parent_runfile> [--wave-branch <name>]`).** READ-ONLY: it executes no git mutation, no push and no `gh` write. For every lane of the current wave in planner order (`## Current`'s `- wave: <k> | items: …` line, else the lane table order), it prints the operator's commands:
  - `git fetch origin`
  - `git checkout -b <wave-branch, default wave/<run_id>-w<k>> origin/<base>`
  - one `git merge --no-ff <exact head sha> -m "Merge lane <L> (<item>) PR #<n>"` per lane, the sha read from `gh pr view <pr> --json headRefOid`; an unreadable sha prints `# <lane>: head unreadable — resolve before integrating` and that lane is skipped
  - `bash scripts/ci-local.sh`
  - the release step (owner decision 2)
  - `git push -u origin <wave-branch>` + `gh pr create --base <base> --head <wave-branch>`

  It then prints the Part S conflict rules (resolve a marker-only conflict in the merge commit; anything larger stops integration and goes to the owner; never rewrite or push a lane branch; a lane broken on the wave branch is fixed on its own PR and its new head re-merged). A guard test asserts that a `wave-plan` run leaves every ref (`git for-each-ref`) and the working tree byte-identical, and that no lane subcommand contains an executable `git push` to a lane branch or a `git merge` outside a printed string.
- [ ] **A5 (single-item path unchanged).** A sequential (no `--parallel`) run never calls `fleet-closeout` or `wave-plan`. Existing groups Y, Z, AB and AC of `test-automate-lanes.sh` and every closeout group of `test-automate-trail.sh` pass with no edit to existing assertions.

### Part B — gate catalog + stamped policy answers
- [ ] **B1 (catalog).** `loomwright/scripts/lane-policy.sh catalog` prints the ONE authoritative gate table (TSV `code<TAB>policy<TAB>labels-joined-by-|<TAB>purpose`). `loomwright/docs/LANE_GATES.md` mirrors it in a markdown table, and `test-lane-policy.sh` fails when the two differ. The catalog covers every engine `AskUserQuestion` gate. `policy: allowed` gates are exactly:
  - `AUT-RESUME` (Continue | Start new | Archive)
  - `AUT-QUEUE` (Process | Stop)
  - `AUT-SUMMARY` (Keep summary | Drop summary — LOW/INFO summary drafts only)
  - `LP-SAVE` (Save and exit | Refine further | Edit sections | Discard — asked ONLY on a Plan Review PASS with zero issues)
  - `SUP-CHILDREN` (proceed anyway | investigate | abort)

  Every other gate is `human-only`: Plan Review FAIL / NEEDS_HUMAN / any MEDIUM-or-higher finding, an output gap / adjudication, pre-flight OVERLAP / SUPERSEDED, per-finding dismissed drafts and fix-now, closeout leftovers, Launch Pad clarification / NO-GO / executable-acceptance stamp / memory facts, Supervisor INIT config, and anything that merges, deletes or pushes. Exact labels are the catalog's. `(Recommended)` is stripped before comparison. Every code is at most 12 characters (the `AskUserQuestion` `header` limit documented in `commands/dreaming.md`), and `test-lane-policy.sh` asserts that `lane-policy.sh catalog` contains no longer code.
- [ ] **B2 (gates say who they are).** The engine prose asks each `policy: allowed` gate with `header` = its code and the catalog's exact labels:
  - `skills/automate-loop/SKILL.md` §4 step 4 resume (`AUT-RESUME`), §2 queue confirm (`AUT-QUEUE`), and the summary-draft question in §6 "Dismissed-findings decision step" plus the PICK-time ask (`AUT-SUMMARY`, summary drafts only)
  - `agents/launch-pad.md` Phase 6 PASS-with-zero-issues options (`LP-SAVE`; a PASS carrying notes keeps NO code ⇒ human)
  - the children-unsettled ask in `skills/async-orchestration/SKILL.md` (`SUP-CHILDREN`)

  Human-only gates carry no code. A question whose `header` is not a catalog code is ALWAYS human.
- [ ] **B3 (stamp valve — reuse, not a second valve).**
  - `rules-check.sh` gains a read-only `--stamp-state` mode. In the MODE precedence chain it sits in the read-only tier, below `--gate-state` and above `--no-cmd`: it executes nothing, never prompts and writes no stamp. It exits immediately AFTER the single existing `LIVE_HASH` assignment and BEFORE the `--if-stamped` resolution, so it reuses that one hash (no second computation). It compares the hash against `_rc_read_stamp_hash "$STAMP_KEY"` and prints exactly one line, `stamp<TAB>match|mismatch|absent`; exit 0. The two earlier exits (no `jq`, and no `.agent/rules/*.json`) also handle `--stamp-state`: each prints `stamp<TAB>absent` and NO `Checks passed` line. `test-rules-check.sh` covers match, mismatch, absent, both early exits, and "executes no check".
  - The project policy file is `.agent/lane-policy.json` (tracked): `{"schema_version":1,"answers":{"<code>":"<label>",…}}`.
  - It counts as stamped ONLY when ALL hold:
    - (i) a selected must-rule with id `lane-policy` exists (`rules-check.sh --list-selected`)
    - (ii) that rule's `binds` array contains `.agent/lane-policy.json` (read from `.agent/rules/*.json` with `jq` as DATA only — the `check` is never run)
    - (iii) `--stamp-state` prints `match`

  Editing the policy file, the rule, or deleting the stamp ⇒ not stamped ⇒ project policy ignored and reported (`lane-policy: project policy ignored — <reason>`), never partially applied.
- [ ] **B4 (per-wave policy).** `lane-policy.sh wave-set <parent_runfile> <code>=<label> …` writes `.supervisor/automate/<run_id>.wave-policy.json` (`{"schema_version":1,"run_id":…,"answers":{…},"set_at":…}`) and one parent `## Progress` line `wave policy: <code>=<label>, …`. It refuses (exit 1, nothing written) a code that is not `policy: allowed` or a label that is not one of that code's catalog labels. The coordinator calls it ONLY from the owner's own answers to an `AskUserQuestion` at wave planning. SKILL §14 states this, plus the honest limit that the file is not owner-authenticated (same trust level as `lane-answer`'s pending file).
- [ ] **B5 (resolve + carry).** `lane-policy.sh resolve <parent_runfile> [--root <primary>]` prints one JSON object: `{"policy_sha": <sha256 of the canonical merged answers>, "sources": [...], "answers": {code: label}}`. It merges the stamped project policy and the wave policy (wave wins per code), keeps only `policy: allowed` codes with valid labels, and reports and drops anything else. `lane-create` (in the primary, before launch) writes the result into the lane's `lane.json` as a `policy` key. An empty result writes `"policy": null`. `lane.json`'s other keys are byte-unchanged in meaning.
- [ ] **B6 (decide + apply in the lane).** `lane-policy.sh decide <question_json> [--policy-json <file>]` prints a JSON object `{"0":"<label>",…}` when EVERY question in the call has a catalog code whose policy is `allowed`, whose options' labels (with `(Recommended)` stripped) equal the catalog labels as a set, and whose code has a policy answer. Otherwise it prints `human`. It is an exact lookup — never a model judgement, never a partial answer. `relay-hook`, before recording a question and deferring:
  - calls `decide` against the lane's `lane.json` `policy`
  - on an answer: validates it with `_lanes_validate_answers`, writes `inbox/questions/<id>.json` (as today) AND `inbox/answers/<id>.json` with `source: "policy"`, `policy_sha`, `gate`, `via: "policy"`, `at`, and returns the same `allow` + `updatedInput` shape the answered branch returns today (no defer, no resume)
  - appends one lane run-file `## Progress` line `policy answer: <code> → <label> (policy_sha <first 12>)` via `automate-helpers.sh progress-append` (fail-SAFE: a failed append never blocks the answer)
  - on `human` or any error: behaviour is byte-identical to today (question file + defer)
- [ ] **B7 (visible + batched).**
  - `lane-status <parent_runfile>` adds one `policy: <n> answered by policy[ since <first at>] — last <code> → <label> <at>` line per lane that has policy answers, and a header line `policy: none answered` when no lane has any.
  - New `lane-status <parent_runfile> --inbox` prints every lane's pending HUMAN questions (a questions file with no answers file) in ONE list, oldest `asked_at` first: `<asked_at> <lane> <tool_use_id> <header> — <question>` plus its option labels.
  - Removing the stamp turns policy answering off at the next `lane-create` (already-created lanes keep the policy carried at creation — documented honest limit).
- [ ] **B8 (remove the one-item queue confirm at the source).** In SKILL §2 "`--limit N`" / the queue-confirm rule: inside a lane (`lane-info` exits 0) whose source is the `lane-backlog.md` that `lane-create` wrote, the Queue confirm is NOT asked. The lane appends `skipped AUT-QUEUE: lane backlog written by lane-create from the owner's --parallel command` to `## Progress`. Every other run still asks (or skips under `--non-interactive-fallback`) exactly as today.
- [ ] **B9 (tests — `test-lane-policy.sh`, new).** Cases:
  - an allowed gate with a stamped policy is applied and recorded `source: policy`
  - a human-only code in the policy is ignored and reported
  - unstamped (rule missing / binds missing / `--stamp-state` mismatch / absent) ⇒ every question goes to the human
  - an unknown header ⇒ `human`
  - a label not in the catalog ⇒ `wave-set` refuses
  - a multi-question call with one human question ⇒ `human`
  - the two drifted v2 resume phrasings (`Resume` / `Start new (Recommended)` vs `Resume?` / `Start new run (Recommended)`) both map to `human` today (no code), and the coded `AUT-RESUME` form maps to the policy answer
  - **replay fixture:** the 15 S1 v2 questions (reconstructed fixture, the 8 routine coded per B1, the 7 real decisions human-only or uncoded) with a policy covering the routine codes send exactly 7 to `human`
  - **mutation control:** make `decide` honour a `human-only` code ⇒ a test FAILS. The mutant is gated non-empty + differs + `bash -n`, and the reverted hunk and failing test name are recorded in `WORKER_RESULT` and the PR body
  - the `--stamp-state` read-only mode executes no check (a check that would write a marker file leaves none)
- [ ] **B10 (no policy ⇒ unchanged).** With no `.agent/lane-policy.json` and no wave policy, `lane.json` carries `"policy": null` and the inbox round trip of `test-automate-lanes.sh` passes unchanged.

### Shared
- [ ] **S1a (script headers + dispatch — Subtask 2).** The `automate-lanes.sh` and `automate-helpers.sh` usage headers list `fleet-closeout` and `wave-plan`. `automate-helpers.sh` dispatches both to `automate-lanes.sh` like the other lane subcommands. `loomwright/scripts/fixtures/automate-helpers-help.golden` is regenerated in the same change (`bash loomwright/scripts/automate-helpers.sh --help > loomwright/scripts/fixtures/automate-helpers-help.golden`), so `test-automate-helpers-dispatch.sh` stays green.
- [ ] **S1b (docs — Subtask 3).**
  - `skills/automate-loop/SKILL.md` §14: replace "Wave end, until item 21 Part A lands" with the wave-close flow (owner merges per `wave-plan` → `lane-convert-ready` per lane → `fleet-closeout` on each `--resume`). Add `wave-plan` and `fleet-closeout` to the per-wave loop. Add a "Policy answers" subsection (B3–B7).
  - Amend "The coordinator never answers a lane question on its own" to say a stamped/owner-set policy answer is the owner's pre-given answer, applied by the lane's own hook.
  - Add the §1.5 rows for `fleet-closeout` / `wave-plan` / `lane-policy.sh`, and bump the skill `version`/`lastUpdated` (+ the `SKILLS_INDEX.md` row).
  - `commands/automate.md` §"Lanes" names both subcommands and the policy.
  - `docs/result-schemas/automate-run.md` documents the new `## Progress` lines (`policy answer:`, `wave policy:`, `skipped AUT-QUEUE:`, `fleet closeout …`, `wave_paused: main_red …`) and the answer file's `source: policy` + `policy_sha` + `gate` fields.
  - `changelog.d/21-fleet-operations.md` exists. NO version files are touched.
- [ ] **S2 (CI green).** `bash scripts/ci-local.sh` passes on the branch (full loop + root gates: doc-currency, citation drift, token budget, skills-index sync, command sync). The PR body pastes base and branch `<passed>/<total>` and `SKIP` counts.

## Outcomes Rubric
- After the owner merges, the wave closes from the coordinator's `--resume` alone: lanes closed out and removed, parent Queue checked off, leaks reported, lock released.
- No code path merges or pushes a lane branch; the merge-executor invariant grep is unchanged.
- A policy answer exists only for a catalogued `allowed` gate, from a stamped project policy or an owner-set wave policy, and is recorded `source: policy` with its sha.
- Unstamped, malformed, or human-only policy entries fail toward asking the human, and a mutation control proves it.
- A question with no catalog code is always human.
- The one-item lane queue confirm is gone and the run file says why.
- Every new run-file line and answer-file field is documented where the schema lives.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `4e0f255753ee225d11f0bd7d82c15434a0ba9d44`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/automate-lanes.sh`**
  - keep: fail-CLOSED refusals with their exact text shapes (`lane-convert-ready: refused — $L — $1`); observation fails SAFE with exit 0 except the snapshot (`The ONE exception to observation's exit 0`); `set -uo pipefail` with NO `set -e`; the standalone guard `if [ "${BASH_SOURCE[0]}" = "$0" ]; then lanes_main "$@"; exit $?; fi`; relay-hook outside a lane emits `{}` (`[ -s "$root/.supervisor/lane.json" ] || { echo '{}'; return 0; }`); the PermissionRequest deny branch unchanged; the coordinator writes into a lane ONLY through the three listed exceptions in the header `Files` block (add none — policy answers are written by the lane's OWN hook).
  - reuse: `die`, `now_utc`, `_lane_ctx`, `_lanes_validate_answers`, `_lanes_meta_extras`/`_lanes_meta_trail`, `lanes_proc_alive`, `_lanes_live_watchers`, the `lanes_main` case dispatch, and the `jq -n --arg` construction for every JSON write (lesson a7e4fb1c: never shell-templated JSON).
  - mirror: the answer file shape `{answers: $a, note: …, source: "human", via: $via, at: $at}` (add `source: "policy"`, `policy_sha`, `gate` for the policy writer; the human writer stays byte-identical); the `updatedInput` allow shape of the answered branch (`permissionDecision: "allow"`).
  - pinned by: `test-automate-lanes.sh` groups Y, Z, AB, AC (`lane-convert-ready`), its inbox round-trip group, and `test-no-fixed-sleep-race.sh` (it greps this file).
- **`loomwright/scripts/rules-check.sh`**
  - keep: the precedence chain (`--list-selected` > `--list-gateable` > `--gate-state` > `--no-cmd` > …); the read-only modes execute nothing and write no stamp; the load-bearing comparison `if [ -n "$_rc_stamped_hash" ] && [ "$_rc_stamped_hash" = "$LIVE_HASH" ]; then MODE="execute"` stays byte-unchanged; `RULES_CHECK_STAMP_FILE` is spelled out exactly once.
  - reuse: `_rc_read_stamp_hash "$STAMP_KEY"` and the one `LIVE_HASH` computation (`--stamp-state` exits right after that assignment; it must not compute a second hash).
  - pinned by: `test-rules-check.sh` (cases h / M-hash) and `rules-gate-verdict.sh` (consumer of `--gate-state` — unchanged).
- **`loomwright/scripts/automate-helpers.sh`**
  - keep: `gate_eval` byte-unchanged (A3); the lane subcommands are delegated, never re-implemented (`delegated to automate-lanes.sh`).
  - pinned by: `test-automate-helpers.sh`, and `test-automate-helpers-dispatch.sh` (its `--help` output is compared byte-for-byte to `fixtures/automate-helpers-help.golden`: "ADDING A SUBCOMMAND? Regenerate the golden in the same change").
- **`loomwright/scripts/test-rules-check.sh`** — keep every existing case (including h / M-hash) byte-unchanged; add the `--stamp-state` cases as new cases.
- **`loomwright/docs/prompt-token-budgets.json`** — keep: edited ONLY if `bash scripts/check-token-budget.sh` shows the `launch-pad` row breached after the `LP-SAVE` clause (headroom 1653 at base). Otherwise leave it untouched. Any raise follows the file's own note convention, with the mirror row in `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets". Pinned by: `scripts/check-token-budget.sh`.
- **`loomwright/scripts/test-automate-lanes.sh`** — keep every existing assertion byte-unchanged (A5); add new groups after the last one and register them in the group index at the top of the file.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Policy core: gate catalog, `lane-policy.sh` (catalog/wave-set/resolve/decide), `rules-check.sh --stamp-state`, tests | B1, B3, B4, B5 (resolve only), B6 (`decide` only), B9, part of S2 | 2 modify, 3+ create (incl. fixtures) | `unit-testing`, `error-handling`, `quality-checklist` | LAUNCHABLE |
| 2 | Lane integration + wave close: relay-hook policy apply, lane-create carry, lane-status digest/inbox, lane-convert-ready finalize, `fleet-closeout`, `wave-plan`, helper dispatch, tests | A1, A2, A3, A4, A5, B5 (carry), B6 (apply), B7, B10, S1a, part of S2 | 4 modify, 0 create | `unit-testing`, `error-handling`, `quality-checklist` | BLOCKED (by #1) |
| 3 | Docs + gate codes in engine prose + changelog fragment | B2, B8, S1b | 8 modify, 1 create | `quality-checklist` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/lane-policy.sh"}
  - {kind: "file", path: "loomwright/scripts/test-lane-policy.sh"}
  - {kind: "file", path: "loomwright/docs/LANE_GATES.md"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "lp_decide"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "lp_resolve"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "lp_wave_set"}
  - {kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "lp_catalog"}
  - {kind: "symbol", path: "loomwright/scripts/rules-check.sh", name: "--stamp-state"}
  - {kind: "symbol", path: "loomwright/docs/LANE_GATES.md", name: "AUT-QUEUE"}
requires: []
lanes:
  - "loomwright/scripts/lane-policy.sh"
  - "loomwright/scripts/test-lane-policy.sh"
  - "loomwright/scripts/rules-check.sh"
  - "loomwright/scripts/test-rules-check.sh"
  - "loomwright/docs/LANE_GATES.md"
  - "loomwright/scripts/fixtures/lane-policy/**"
external_requires:
  - "jq >= 1.6"

# Subtask 2
provides:
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_fleet_closeout"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "lanes_wave_plan"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "fleet-closeout"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "wave-plan"}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "source: \"policy\""}
  - {kind: "symbol", path: "loomwright/scripts/automate-lanes.sh", name: "--inbox"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "fleet-closeout"}
  - {kind: "symbol", path: "loomwright/scripts/automate-helpers.sh", name: "wave-plan"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/lane-policy.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "lp_decide"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/lane-policy.sh", name: "lp_resolve"}
lanes:
  - "loomwright/scripts/automate-lanes.sh"
  - "loomwright/scripts/test-automate-lanes.sh"
  - "loomwright/scripts/automate-helpers.sh"
  - "loomwright/scripts/fixtures/automate-helpers-help.golden"
external_requires:
  - "gh CLI (stubbed via LOOMWRIGHT_GH_BIN in tests)"

# Subtask 3
provides:
  - {kind: "file", path: "changelog.d/21-fleet-operations.md"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "fleet-closeout"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "AUT-QUEUE"}
  - {kind: "symbol", path: "loomwright/skills/automate-loop/SKILL.md", name: "Policy answers"}
  - {kind: "symbol", path: "loomwright/commands/automate.md", name: "fleet-closeout"}
  - {kind: "symbol", path: "loomwright/docs/result-schemas/automate-run.md", name: "policy answer:"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "LP-SAVE"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "SUP-CHILDREN"}
requires:
  - {from: "1", kind: "file", path: "loomwright/docs/LANE_GATES.md"}
lanes:
  - "loomwright/skills/automate-loop/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/commands/automate.md"
  - "loomwright/docs/result-schemas/automate-run.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "changelog.d/21-fleet-operations.md"
external_requires: []
```

**Exact-name mandate:** the names above are literal. `fleet-closeout` / `wave-plan` are the subcommand spellings, dispatched from both `automate-lanes.sh` and `automate-helpers.sh`. `lp_decide` / `lp_resolve` / `lp_wave_set` / `lp_catalog` are the `lane-policy.sh` functions behind the subcommands `decide` / `resolve` / `wave-set` / `catalog`. `--stamp-state` is the `rules-check.sh` flag. The gate codes are exactly `AUT-RESUME`, `AUT-QUEUE`, `AUT-SUMMARY`, `LP-SAVE`, `SUP-CHILDREN`. `Policy answers` is a `###` heading under SKILL §14.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
Subtask 1 ──→ Subtask 3
```
2 and 3 are unordered relative to each other and share NO lane.

### File Overlap Matrix
| A | B | Overlap |
|---|---|---|
| 1 | 2 | none |
| 1 | 3 | none |
| 2 | 3 | none |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2, Subtask 3 (parallel)
- **Recommended workers:** 2

## Skill References

| Skill | Why |
|---|---|
| `skills/unit-testing/SKILL.md` | Static, hermetic `test-*.sh` structure (PATH/env stubs, no network) |
| `skills/error-handling/SKILL.md` | Fail-CLOSED gates vs fail-SAFE observation in the same script |
| `skills/quality-checklist/SKILL.md` | Pre/post gates |
| `skills/rules/SKILL.md` §8 / §8.1 | The stamp valve B3 reuses (do not invent a second valve) |
| `skills/automate-loop/SKILL.md` §14 | Lane contract the new subcommands extend |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope is large: two parts plus amendments in one PR (Feasibility 4) | HIGH | Three subtasks with disjoint lanes; Phase 4.5 integrated review is the cross-part lens |
| No sweep exists for Scope 7's dry-run (Feasibility 5) | MEDIUM | `fleet-closeout` prints `sweep: unavailable (automate-followups/22 not shipped)`; the PR body lists it as a deferred dependency on `39-engine-hygiene` |
| Backstop deviates from the requirement's `lane-launch --resume` (A2 step 2) | MEDIUM | `lane-convert-ready`'s re-run already runs `closeout --no-trail` inside the lane, as the sanctioned coordinator exception (automate-followups/38, which landed after the requirement text). It is token-free, needs no headless session and no launch authority. The PR body states the deviation and why |
| A policy answer applied for a human-only gate | HIGH | Codes are checked against the catalog at `wave-set`, at `resolve` and again at `decide`; B9's mutation control proves a human-only code is never honoured |
| Policy model-writable inside the lane (`lane.json`) | MEDIUM | Honest limit, documented in SKILL §14: the lane deny list is a tripwire, not a sandbox. Only `allowed` gates can ever be answered, so the worst case is a routine formality answered with one of its own labels |
| `rules-check.sh` stamp key is per-clone (`git_common_dir`), so a lane cannot verify the project policy itself | MEDIUM | Verification runs in the PRIMARY at `lane-create` (`resolve`). The lane only reads the carried result |
| The stamp valve hashes the WHOLE selected must-rule set: editing any must-rule (including sibling lane L2's concurrent change to `.agent/rules/process.json`) turns project policy answers OFF until a human re-runs `/rules check --confirm`. The `lane-policy` rule is selected only with `enforcement: must` and a non-null `check`; the confirm runs every must-check, and a stamped failing countable check blocks the merge gate (`rules-gate-verdict.sh` condition 7) | LOW | Fail-closed by design. SKILL §14 "Policy answers" documents the rule: id `lane-policy`, `enforcement: must`, a check that always passes on a valid file (e.g. `jq -e .schema_version .agent/lane-policy.json`), `binds: [".agent/lane-policy.json"]`, and that any must-rule edit needs a re-confirm |
| Token budget: `agents/launch-pad.md` headroom 1653, `agents/supervisor.md` headroom 335 | MEDIUM | No edit to `agents/supervisor.md` (the children ask lives in `skills/async-orchestration/SKILL.md`); the `LP-SAVE` addition stays one short clause; run `scripts/check-token-budget.sh` |
| Restated lists drift (house rule: restating copy updated in the same change) | MEDIUM | The catalog has ONE authority (`lane-policy.sh catalog`) with a drift test against `LANE_GATES.md`; SKILL/automate.md point at it instead of restating it |
| Doc-currency / citation drift / skills-index sync | LOW | Descriptive anchors or pinned citations only; bump the skill version in both `SKILL.md` and `SKILLS_INDEX.md`; `ci-local.sh` covers the root gates |
| A mutation control with an invalid mutant (lesson fa32a308) | MEDIUM | Gate the mutant on non-empty + differs + `bash -n` |
| Sibling lanes L2 (`.agent/rules/process.json`) and L3 (`RULES_BASELINE.md`) | LOW | Neither file is in any lane here; tests build their own rule stores in temp dirs |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound — `automate-lanes.sh` (2099 lines) plus its 1469-line test is one worker's full context; the policy core (new files plus `rules-check.sh`) and the docs/prose are separable. Subtasks 2 and 3 are genuine-parallelism once 1 has fixed the names.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/auto-2026-10-10-194843-fleet-operations.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-10-10T16:34:17Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/464
- **Branch:** feature/pa21-fleet-operations
- **Files changed:** 19
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** 3 subtasks merged (policy core; lane integration + wave close; docs/gate codes) plus 2 FINALIZE CI fixes (vendor-coupling reuse, pipefail grep-q). ci-local PASS 147/147 + 15 gates (base 4e0f255 also PASS). Phase 4.5 code review PASS on the first review (consistency_audit; 7 dismissed: 4 MEDIUM, 3 LOW). rubric_score 7/7. ground_truth 2/2. rules gate: none. Risk: high_risk true (advisory). children_check: skipped (owner).

## Not verified
- **automate-lanes.sh relay-hook and lane-create calling decide/resolve** — Subtask 2 implements the integration (subtask 1)
- **a real two-lane wave with a stamped policy** — needs a live multi-lane wave (subtask 1)
- **a real two-item wave with owner merges; gh check-runs response shape** — stubbed in tests (subtask 2)
- **finalize-empty identity unset under a real crashed lock** — scratch repro only (fix-vendor)
