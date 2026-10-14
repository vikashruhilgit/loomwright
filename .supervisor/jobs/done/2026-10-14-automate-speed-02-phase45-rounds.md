# Supervisor Job: Phase 4.5 spends its rounds on new defects — pin mutations by script once, CI read once per iteration, workers run `ci-local.sh --affected`

## Environment
- **Project:** loomwright lane clone `L2` (`~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-14-041009/L2`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (lane L1 of the same wave edits `loomwright/skills/automate-loop/**` + `automate-helpers.sh` in parallel — disjoint from these lanes)
- **Source requirement:** .supervisor/requirements/automate-speed/02-phase45-rounds-on-new-defects.md
- **Base commit:** 1908111687788abfaa4b838902494b5d6d642ebf

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq + git + gh, the same stack as `verify-provides.sh`, `wait-for-checks.sh`, `ci-run-probe.sh` |
| 2 | Dependency Availability | GO | Every reader the scope says to reuse exists: `wait-for-checks.sh` (+ `wait-for-checks-line.sh` `wfc_line_parse`), `ci-run-probe.sh`, `wrap-external-text.sh`, `run-self-tests.sh`'s watchdog idiom |
| 3 | Architecture Fit | GO | Two new standalone scripts called from existing prose seams (Phase 3 deterministic gate, Phase 4.5 iteration); no new schema key, no new result-block field |
| 4 | Scope vs Supervisor Capability | CAUTION | ~19 files; the requirement's `## Touches` misses five surfaces the wiring needs (parallel-path gate in `execute-manager.md`, the drain fix-worker prompts in `review-heal/SKILL.md`, the token-budget pair, the seam test that pins the reviewer's Pin-mutations paragraph) — see Risk Assessment |
| 5 | Hard Blockers | CAUTION | (a) Requirement scope 1 says "a `not_held` sends the worker a retry, like an outputs gap", but an outputs gap goes to a HUMAN adjudication checkpoint today (`async-orchestration` §"Scope Expansion Adjudication": `The Execute Manager **NEVER picks an option itself**`) — resolved below as ONE bounded automatic re-spawn. (b) The `## Pin mutations` rows in today's briefs (PR #533's included) are free prose, not machine-applicable — resolved by a two-form grammar; prose rows read `unverified` and fall to the D1 reviewer fallback. (c) The drain never fetches a failing check's log (only `automate-helpers.d/escalation.sh` reads `--log-failed`) — the new CI reader fetches it itself. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Make Phase 4.5's LLM rounds go to new defects: a script (`run-pin-mutations.sh`) checks every `## Pin mutations` row once per code state (Phase 3 gate + cached re-use in Phase 4.5), a script (`phase45-ci-read.sh`) turns each red required check into one BLOCKING finding with its log tail once per Phase 4.5 iteration, and every worker/fix-worker prompt names `bash scripts/ci-local.sh --affected` instead of a hand list.

**Problem Statement:**
The owner needs Phase 4.5's expensive review rounds spent on finding and fixing new defects.
Currently, since 6e8c757 the reviewer re-runs every pin mutation on every iteration (PR #533: 16 rows, ~32 suite runs per review, 7.5 → 10 min), Phase 4.5 never reads a red required check (PR #533's `CI` was red on every push and the drain spent 2h11m on it), and workers run hand-typed suite lists that miss CI-only gates (`check-locale-prefix.sh`). This causes every item since 2026-10-12 to max `self_heal_rounds=3`.
Success looks like: mechanical checks run once per code state by a script; a red required check reaches the same iteration's fix worker; workers run the project's own affected plan, which includes every static CI gate.

## Acceptance Criteria
- [ ] 1. Given a brief whose `## Pin mutations` rows (two-form grammar, below) all turn their pins red, when `run-pin-mutations.sh <brief> --root <checkout>` runs, then every row prints `held` and it exits 0; a row whose mutant stays green prints `not_held` and the run exits 1; a row whose mutation does not apply, whose unmutated pin fails, whose pin file is not found, or whose wording is not one of the two forms prints `unverified (<reason>)` and the run exits 2 (any `not_held` ⇒ 1 wins over `unverified`). A brief with no `## Pin mutations` section prints one `pin-mutations: none` line, exit 0.
- [ ] 2. Given any row, when its mutant is built, then it is validated BEFORE the mutated run — non-empty, differs from the original, and `bash -n` clean for a `.sh` target (`jq empty` for a `.json` target); an invalid mutant reads `unverified (invalid_mutant: <why>)`, never `held`. The run happens in a `mktemp -d` copy of the WORKING TREE (tracked + untracked non-ignored files, so uncommitted worker edits are included), with `HOME` relocated into the scratch dir and a per-run watchdog (no `timeout(1)`); the user's checkout, index and `git worktree list` are byte-identical before and after, and the scratch dir is gone at exit (EXIT trap).
- [ ] 3. Given `--cache <file>` and a second run where neither a row's mutation target file nor its pin test file changed (content hash) and the row text is identical, when the script runs, then that row is NOT re-run and prints its previous verdict marked `(cached)`; a row whose target or pin file changed IS re-run. `unverified` verdicts are never cached.
- [ ] 3b. Given `--only-paths <glob>…`, when `run-pin-mutations.sh` runs, then only rows whose mutation target path matches a glob are examined (others print nothing), and zero selected rows print `pin-mutations: none selected`, exit 0.
- [ ] 4. Given the Phase 3 deterministic gate (Single-Agent and Sequential paths in `agents/supervisor.md`, the parallel poll loop in `agents/execute-manager.md`), when the worker hands back and `verify-provides.sh` has run, then `run-pin-mutations.sh <brief> --root <tree> --cache .supervisor/pin-mutations/<brief-stem>.tsv` runs beside it, scoped with `--only-paths <the subtask's lanes:>` to the rows whose mutation target `<path>` that subtask owns (Single-Agent: every row); a `not_held` row triggers ONE bounded re-spawn of the same worker with the `not_held` lines as `Retry context:`, then one re-run of the script; a still-`not_held` row (or exit 2) is recorded and carried into Phase 4.5 — it never pauses the run and never reaches adjudication. A missing script / brief / section is recorded, never a block.
- [ ] 5. Given Phase 4.5 iteration N, when the reviewer is spawned, then the iteration first runs the same `run-pin-mutations.sh … --cache` command and pastes its verdict lines into the reviewer spawn prompt as a `PIN-MUTATION VERDICTS (DATA …)` block placed AFTER the DEVIATIONS ADVISORY line; and `agents/code-reviewer.md` §5's "Pin mutations" paragraph names that `PIN-MUTATION VERDICTS` block and says: a `not_held` line ⇒ one BLOCKING `new` finding quoting it (no re-run); a `held` line ⇒ no action; the reviewer applies a mutation itself ONLY for a row the script reported `unverified` (D1 fallback, keeping the existing scratch-copy recipe); no block / no section ⇒ nothing to check.
- [ ] 6. Given iteration 2 where no protected file changed since iteration 1, when the iteration runs the pin script, then no pin row is re-run (every line reads `(cached)`) and the reviewer prompt carries the previous verdicts.
- [ ] 7. Given a PR whose required check is red on the current head at Phase 4.5 iteration N, when `phase45-ci-read.sh <pr_url> --sha <head>` runs (ONE read: `wait-for-checks.sh … --bound 0 --required-only --names`, parsed only through `wfc_line_parse`), then it prints ONE finding line per red required check — severity `BLOCKING`, category `new`, the check name, run id, and the failing step's log tail (`gh run view <run_id> --log-failed`, last ≤40 lines / ≤4000 bytes) wrapped by `wrap-external-text.sh` — and Phase 4.5 adds each to that iteration's `fixable_issues` so the fix worker receives it even when the reviewer PASSed. A check `ci-run-probe.sh` classifies `untrusted_infra` raises NO finding: it prints a `note` line and is passed to the owned drain unchanged (D3). Pending, unknown, unreadable, green or a `gh` failure ⇒ a single `ci-read: none — <reason>` line, no finding (D2). The script always exits 0.
- [ ] 8. Given the Phase 4.5 fix-worker prompt (`skills/self-heal-advisory/SKILL.md`), the drain and default-loop fix-worker prompts (`skills/review-heal/SKILL.md` Step 2 and Step U4), the worker prompt template (`skills/async-orchestration/SKILL.md` §"Worker Prompt Template") and `agents/worker.md` Step 5, when `test-phase45-rounds-seam.sh` greps the five prompts, then each names `bash scripts/ci-local.sh --affected` (where the project has it) as the test command and states the owner rule — a background worker never runs the full `ci-local.sh` pool — and none lists hand-typed suite names.
- [ ] 9. Given the real `.github/workflows/ci.yml`, when `scripts/test-ci-local.sh` runs, then a new leg asserts every `bash scripts/check-*.sh` line of the `static` job appears as an `early:` entry of `ci-local.sh --affected --list` (so a change that breaks `check-locale-prefix.sh` runs that gate under `--affected`); mutation control — excluding `scripts/check-locale-prefix.sh` from the early-set derivation in `ci-local.sh` — turns that leg red.
- [ ] 10. Given `skills/supervisor-readiness/SKILL.md` §"Pin mutations", when `loomwright/scripts/test-phase45-rounds-seam.sh` greps it, then it states the two machine-applicable mutation forms (`` delete `<literal>` in `<path>` `` and `` flip `<A>` → `<B>` in `<path>` ``), that the Pin cell's first backticked token is the pin's test file, and that any other wording is left to the reviewer's D1 fallback.
- [ ] 11. Given this repo, when Validation 1–3 are run, then `docs/evidence/automate-speed-02-phase45-rounds.md` records: (1) `<passed>/<total>` for `test-run-pin-mutations.sh`, `test-phase45-ci-read.sh`, `test-ci-local.sh` and the seam tests named in Touched-file invariants; (2) both mutation controls (skip the "must fail mutated" re-run ⇒ the `not_held` leg red; drop `check-locale-prefix.sh` from the early set ⇒ the drift leg red) with the red output; (3a) `run-pin-mutations.sh` on PR #533's brief `.supervisor/jobs/done/2026-10-13-verified-rule-checks.md` — all 16 verdict lines + wall-clock (expected: mostly `unverified (not_machine_applicable)`, its rows are prose), (3b) the same 16 rows transcribed into the two-form grammar in a fixture brief, run against the current tree — 16 verdict lines + wall-clock, (3c) `phase45-ci-read.sh` against PR #533 at `b62b67d` (the real red `CI` from `check-locale-prefix.sh`) — the finding line(s) printed.
- [ ] 12. Given the CLAUDE.md bimodal-failure invariant, when the new scripts' tests and `scripts/check-test-hermetic.sh` run, then `run-pin-mutations.sh` fails CLOSED on its verdict (any doubt is `unverified`/exit 2, never `held`) and `phase45-ci-read.sh` fails SAFE (always exit 0; doubt ⇒ no finding); both new scripts ship a hermetic `test-*.sh` whose first executable line sources `hermetic-test-env.sh`, stubbing `gh` on `PATH` (no network).

## Touched-file invariants

> Grounded at base `1908111687788abfaa4b838902494b5d6d642ebf`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/agents/code-reviewer.md`** — keep the three needles `test-closed-enum-pins-seam.sh` pins inside the paragraph that starts `**Pin mutations (same EXECUTION DIRECTIVE gate).**` — `archive HEAD | tar -x -C "$SCRATCH/tree"`, `run the row's pin once unmutated`, `**Green on its mutant ⇒ a BLOCKING \`new\` finding**` — they now describe the D1 `unverified`-row fallback; keep the gate phrasing `test-execution-directive-seam.sh` pins (`without the EXECUTION DIRECTIVE, do not author or run new adversarial repro scripts;`). pinned by: `loomwright/scripts/test-closed-enum-pins-seam.sh` (PART 4), `loomwright/scripts/test-execution-directive-seam.sh`. Budget: `check-token-budget.sh` reads `code-reviewer` at 205 tokens headroom — any growth over it raises `.agents["code-reviewer"].budget` in `loomwright/docs/prompt-token-budgets.json` AND the mirrored row in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", same commit.
- **`loomwright/skills/self-heal-advisory/SKILL.md`** — keep the spawn-prompt line order the seam tests pin: HOUSE-RULES ADVISORY → `**BRIEF-CONFORMANCE ADVISORY (` → DEVIATIONS ADVISORY consecutively (`test-brief-conformance-seam.sh` `BRIEF_LINE_RE`, `test-deviations-advisory-seam.sh`), so the new PIN-MUTATION VERDICTS block goes AFTER the DEVIATIONS line, never between; keep `**EXECUTION DIRECTIVE (every iteration — Phase 4.5 only):**` after ANTI-OVERLAP (`test-execution-directive-seam.sh` `DIRECTIVE_PREFIX`); keep the post-fix order `release-refold.sh` → `guard-finalize-publish.sh" write-marker` → `git push  # update PR (regular push, NEVER --force)` (`test-release-refold.sh` `seam_heal`); keep `fixable_issues = [i for i in review.issues if at_floor(i)] + rule_findings` as the one list the fix worker gets (CI findings are appended to it, not a second list); every line that still says `tests locally` keeps `the waiter matches itself and never exits` within 3 lines (`test-no-self-matching-wait.sh` `TESTS_ANCHOR`/`PHRASE`, ≥3 anchors repo-wide). pinned by: those five tests.
- **`loomwright/skills/review-heal/SKILL.md`** — keep Step 2's `Address ONLY these new review findings at or above the fix floor` and Step U4's `Address ONLY these required-check failures and VALIDATED bot findings` prompts intact apart from the test-command sentence; keep the waiter phrase rule above. reuse/mirror: the drain names `scripts/ci-local.sh` as a PROJECT command, not a plugin script — `dispatch-pr-review.sh`'s `DRAIN_SCRIPTS=` drift guard (`Adding a script call to the drain prose without adding it here fails test-dispatch-pr-review.sh`) must stay green; if it counts the new mention, write it so it does not resolve to `${CLAUDE_PLUGIN_ROOT}/scripts/`. Budget: `review-pr` preloads this skill, 809 headroom. pinned by: `loomwright/scripts/test-no-self-matching-wait.sh`, `loomwright/scripts/test-dispatch-pr-review.sh`.
- **`loomwright/agents/supervisor.md`** — keep Single-Agent step 3's `**Deterministic gate (zero-token, no reviewer spawn):**` wording, its `verify-provides.sh` call and the rule `Disk gap → adjudication` (the pin gate is a SEPARATE, non-pausing check beside it, never folded into the adjudication flow); keep the anchor-not-line-number convention (`cited by anchor, not line number`). Budget: `supervisor` reads 108 tokens headroom — raise its budget + the ARCHITECTURE_CONTRACTS row with any growth.
- **`loomwright/agents/execute-manager.md`** — keep the `--- v12 outputs_verified gate` block and `# Disk wins. Record the disagreement (a /dreaming signal, not a second gate).`; the new pin call sits after `verify-provides.sh` in the same poll-loop step and reuses the crash-retry shape `retry once in same worktree` for its single re-spawn; update the §"Tool call tracking" accounting (today `the ONE \`verify-provides.sh\` Bash call`, `+1 Bash per subtask on the happy path`) to count the pin Bash call, plus at most one re-spawn Task and one re-run on a `not_held`. Budget: 3870 headroom (preloads `async-orchestration`).
- **`loomwright/agents/worker.md`** — Step 5 must still contain the literal `pre-push command` with `the waiter matches itself and never exits` within 3 lines (`test-no-self-matching-wait.sh` worker check: `anchors "$W" "pre-push command"`), but reworded so the full pre-push run belongs to the foreground session / FINALIZE: a background worker runs the affected check (`bash scripts/ci-local.sh --affected` where the project has it) and never the full pre-push pool — no two lines may give opposite orders; keep it project-generic (the plugin runs in user repos): name `bash scripts/ci-local.sh --affected` as the example "where the project has it". Budget: 872 headroom.
- **`loomwright/skills/async-orchestration/SKILL.md`** — §"Worker Prompt Template" `4. Run tests if test infrastructure exists` gains the `--affected` wording; §"Subagent Spawn Contracts" `Retry context:` field is the carrier for the pin re-spawn (it already reads `from a previous outputs_verified gate gap or worker crash/timeout` — extend that list). Budget via `execute-manager`.
- **`loomwright/skills/supervisor-readiness/SKILL.md`** — keep the §"Pin mutations" table header `| Pin | Mutation (one line, applied to the code the pin protects) |` and the authoring-rule bullets Plan Reviewer Criterion 19 cites (`one row per new or changed pin`); the grammar sentence is additive. Budget via `launch-pad` (4197 headroom).
- **`loomwright/scripts/test-closed-enum-pins-seam.sh`** — keep the hermetic first executable line and the `ok`/`no` counters; keep every existing PART 4 needle (the `**Pin mutations (same EXECUTION DIRECTIVE gate).**` paragraph grep, `archive HEAD | tar -x -C "$SCRATCH/tree"`, `run the row's pin once unmutated`, `**Green on its mutant ⇒ a BLOCKING \`new\` finding**`) and ADD the D1 needle (the reviewer runs a mutation ONLY for an `unverified` row) and a `PIN-MUTATION VERDICTS` needle beside them, never in their place; keep PART 5's fixture hint-leak check green.
- **`scripts/test-ci-local.sh`** — keep the hermetic first executable line (`hermetic-test-env.sh`, `scripts/check-test-hermetic.sh`) and the `ok`/`no` counters; the new drift leg reads the REAL `.github/workflows/ci.yml` but must not take a CI slot or write a pass stamp (verify `--affected --list` runs nothing — header: `--list      print the planned gate/test list, the early set (\`early:\` lines) and the content`); if `--list` cannot run hermetically in CI, copy the real ci.yml into the existing fixture repo instead.
- **`scripts/ci-local.sh`** — expected UNCHANGED (the early set is already derived: `The early set is DERIVED, never hand-listed`); edit only if the drift leg finds a real gap.
- **`AGENT_GUIDELINES.md`** — keep the §"Pre-push: one command" bullets (`While iterating, run \`bash scripts/ci-local.sh --affected\``); add the background-worker rule there in one sentence, no restated gate list.

## Closed enumerations touched

> Sibling grep at base `1908111`: `grep -rnF 'outputs_gap | 0 (immediate)' loomwright/docs/` → 1 hit (`loomwright/docs/FAILURE_ESCALATION.md` §"Escalation Summary"); `grep -nF 'retry once in same worktree' loomwright/agents/execute-manager.md` → 1 hit (its failure table).

- **New retry path `Pin mutation not_held`** (sibling: `Inter-subtask gap / outputs_gap`) — must be named in:
  - `loomwright/docs/FAILURE_ESCALATION.md` — §"Escalation Summary" table (`| Execute Manager | Inter-subtask gap / outputs_gap | 0 (immediate) |`) — extend with `| Worker | Pin mutation not_held | 1 (automatic re-spawn) | recorded, carried to Phase 4.5 as BLOCKING (never adjudication) |`.
  - `loomwright/agents/execute-manager.md` — failure table row `| Worker crash/timeout | Record error, retry once in same worktree, then escalate |` — extend with a `Pin mutation not_held` row (one re-spawn in the same worktree, then record and carry forward).
- **Verdicts `held` / `not_held` / `unverified`** — a new closed set owned by `run-pin-mutations.sh`'s header; prose references it, never restates a different set.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-run-pin-mutations.sh` — held leg (all rows red ⇒ exit 0) | make the mutated-run verdict always `not_held` in `run-pin-mutations.sh` ⇒ held leg red |
| `loomwright/scripts/test-run-pin-mutations.sh` — `not_held` leg (Validation 2) | skip the "must fail mutated" re-run (treat the mutated pin as red without running it) ⇒ `not_held` leg red |
| `loomwright/scripts/test-run-pin-mutations.sh` — `unverified` mutation-does-not-apply leg | ignore the "exactly one matching line" check (apply to zero lines) ⇒ leg red |
| `loomwright/scripts/test-run-pin-mutations.sh` — `unverified` unmutated-pin-fails leg | delete the unmutated pre-run ⇒ leg red |
| `loomwright/scripts/test-run-pin-mutations.sh` — invalid-mutant leg (empty / unchanged / `bash -n`) | delete the `bash -n` mutant check ⇒ syntax-broken mutant reads `held` ⇒ leg red |
| `loomwright/scripts/test-run-pin-mutations.sh` — cache leg (second run all `(cached)`, no pin executed) | drop the content-hash comparison (always re-run) ⇒ execution counter > 0 ⇒ leg red |
| `loomwright/scripts/test-run-pin-mutations.sh` — cache-invalidation leg (target changed ⇒ re-run) | key the cache on row text only ⇒ stale `(cached)` ⇒ leg red |
| `loomwright/scripts/test-run-pin-mutations.sh` — no-leak leg (status / worktree list identical, scratch gone) | delete the EXIT-trap `rm -rf` of the scratch dir ⇒ leg red |
| `loomwright/scripts/test-run-pin-mutations.sh` — exit precedence (`not_held` + `unverified` ⇒ 1) | let `unverified` set exit 2 after a `not_held` ⇒ leg red |
| `loomwright/scripts/test-phase45-ci-read.sh` — red required check ⇒ one BLOCKING finding with wrapped log tail | delete the `--log-failed` fetch ⇒ finding lacks log tail ⇒ leg red |
| `loomwright/scripts/test-phase45-ci-read.sh` — `untrusted_infra` ⇒ note, no finding (D3) | ignore the `ci-run-probe.sh` verdict ⇒ finding emitted ⇒ leg red |
| `loomwright/scripts/test-phase45-ci-read.sh` — pending / unknown ⇒ `ci-read: none` (D2) | treat `required=pending` as red ⇒ leg red |
| `loomwright/scripts/test-phase45-ci-read.sh` — single read, no wait | flip `--bound 0` → `--bound 60` in `loomwright/scripts/phase45-ci-read.sh` |
| `scripts/test-ci-local.sh` — static-gate drift leg | exclude `scripts/check-locale-prefix.sh` from the early-set derivation in `ci-local.sh` ⇒ leg red |
| `loomwright/scripts/test-closed-enum-pins-seam.sh` — reviewer consumes verdicts as DATA, runs mutations only for `unverified` rows | delete the "ONLY for a row the script reported `unverified`" sentence from `code-reviewer.md` ⇒ seam red |
| `loomwright/scripts/test-phase45-rounds-seam.sh` — readiness two-form grammar sentence (AC 10) | delete the two-form grammar sentence from `loomwright/skills/supervisor-readiness/SKILL.md` ⇒ seam red |
| `loomwright/scripts/test-run-pin-mutations.sh` — `--only-paths` leg (rows outside the globs print nothing; zero selected rows ⇒ `pin-mutations: none selected`, exit 0) | make the glob-match predicate in `run-pin-mutations.sh` always true ⇒ leg red |
| `loomwright/scripts/test-phase45-rounds-seam.sh` — each worker / fix-worker template names `ci-local.sh --affected`; Phase 3 + Phase 4.5 call `run-pin-mutations.sh`; Phase 4.5 calls `phase45-ci-read.sh` and appends to `fixable_issues` | delete the `--affected` sentence from the Phase 4.5 fix-worker prompt in `self-heal-advisory/SKILL.md` ⇒ seam red |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Pin-mutation script + Phase 4.5 CI read + `--affected` worker command | all | 15 modify, 7 create | `skills/self-heal-advisory/SKILL.md`, `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/run-pin-mutations.sh"}
  - {kind: "symbol", path: "loomwright/scripts/run-pin-mutations.sh", name: "not_held"}
  - {kind: "symbol", path: "loomwright/scripts/run-pin-mutations.sh", name: "--cache"}
  - {kind: "file", path: "loomwright/scripts/test-run-pin-mutations.sh"}
  - {kind: "file", path: "loomwright/scripts/phase45-ci-read.sh"}
  - {kind: "symbol", path: "loomwright/scripts/phase45-ci-read.sh", name: "--log-failed"}
  - {kind: "file", path: "loomwright/scripts/test-phase45-ci-read.sh"}
  - {kind: "file", path: "loomwright/scripts/test-phase45-rounds-seam.sh"}
  - {kind: "symbol", path: "loomwright/agents/code-reviewer.md", name: "PIN-MUTATION VERDICTS"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "phase45-ci-read.sh"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "run-pin-mutations.sh"}
  - {kind: "symbol", path: "loomwright/agents/supervisor.md", name: "run-pin-mutations.sh"}
  - {kind: "symbol", path: "loomwright/agents/execute-manager.md", name: "run-pin-mutations.sh"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "ci-local.sh --affected"}
  - {kind: "symbol", path: "loomwright/agents/worker.md", name: "ci-local.sh --affected"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "ci-local.sh --affected"}
  - {kind: "file", path: "changelog.d/automate-speed-02-phase45-rounds.md"}
  - {kind: "file", path: "docs/evidence/automate-speed-02-phase45-rounds.md"}
requires: []
lanes:
  - "loomwright/scripts/run-pin-mutations.sh"
  - "loomwright/scripts/test-run-pin-mutations.sh"
  - "loomwright/scripts/phase45-ci-read.sh"
  - "loomwright/scripts/test-phase45-ci-read.sh"
  - "loomwright/scripts/test-phase45-rounds-seam.sh"
  - "loomwright/scripts/test-closed-enum-pins-seam.sh"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/agents/worker.md"
  - "loomwright/agents/supervisor.md"
  - "loomwright/agents/execute-manager.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/skills/supervisor-readiness/SKILL.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/FAILURE_ESCALATION.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "scripts/ci-local.sh"
  - "scripts/test-ci-local.sh"
  - "AGENT_GUIDELINES.md"
  - "changelog.d/automate-speed-02-phase45-rounds.md"
  - "docs/evidence/automate-speed-02-phase45-rounds.md"
external_requires:
  - "gh (authenticated) for phase45-ci-read.sh at runtime; stubbed on PATH in tests"
  - "jq"
```

### Design notes for the worker (decided here; do not re-open)
- **`run-pin-mutations.sh <brief> [--root <checkout>] [--cache <file>] [--only-paths <glob>…] [--timeout <secs>]`** (default timeout 300 per test run). Parses the brief's `## Pin mutations` table (heading outside a fence; ends at the next `#`/`##` heading; reuse the awk table idiom of `build-floor.sh` — `n = split($0, c, "|")` — no shared helper exists). Per row: Pin cell's FIRST backticked token = the pin's test file (resolved as written under `--root`, else by a UNIQUE suffix match over `git ls-files`; zero/many ⇒ `unverified (pin_not_found)`); only `*.sh` pins run (`bash <file>`), anything else ⇒ `unverified (unsupported_pin_runner)`. Mutation cell grammar, exactly two forms: `` delete `<literal>` in `<path>` `` (remove the ONE line containing the literal) and `` flip `<A>` → `<B>` in `<path>` `` (`->` accepted; replace the ONE occurrence of A, which must sit on exactly one line, once); zero or several matches ⇒ `unverified (mutation_does_not_apply: <n> matches)`; other wording ⇒ `unverified (not_machine_applicable)`. Literals are matched with `index()`/fixed strings, NEVER as a regex or through `sed`/`perl` interpolation (lesson fa32a308). Order per row: copy working tree into `mktemp -d` (`git ls-files -z --cached --others --exclude-standard`, existing files only), `git init` + commit the copy (pins may need a repo), run the pin unmutated (non-zero ⇒ `unverified (pin_red_unmutated)`; run each distinct pin file unmutated ONCE per invocation), build + validate the mutant, run the pin mutated: non-zero ⇒ `held`, zero ⇒ `not_held`; timeout ⇒ `unverified (timeout)`. Watchdog: the background + TERM/KILL idiom of `run-self-tests.sh` (`no \`timeout(1)\` (absent on stock macOS)`).
- **Output (stable, one line per row, then a summary):** `pin-mutation <n>: <held|not_held|unverified (<reason>)>[ (cached)] — <pin file> :: <mutation cell, trimmed>`; last line `pin-mutations: <h> held, <x> not_held, <u> unverified (<c> cached)`. Exit 0 / 1 / 2 per AC 1. Usage errors and an unreadable brief ⇒ exit 2 with one `pin-mutations: unverified (<reason>)` line.
- **Cache (`--cache <file>`):** TSV `row_key<TAB>verdict<TAB>target_hash<TAB>pin_hash`, `row_key` = sha of the trimmed row text, hashes via `git hash-object` of the files in the working tree; written atomically (temp + mv); `held`/`not_held` only. Path convention used by both callers: `.supervisor/pin-mutations/<brief basename without .md>.tsv` (gitignored by `.supervisor/*`). Honest limit (header): a pin whose result depends on files other than its target and its own test file is not re-run when only those change.
- **`phase45-ci-read.sh <pr_url> [--sha <sha>] [--max-probes N]`** — `--sha` default = the PR's `headRefOid`. ONE `wait-for-checks.sh <pr_url> --sha <sha> --bound 0 --required-only --names` call, parsed only via `wait-for-checks-line.sh`'s `wfc_line_parse` (never split on spaces). `required=red` ⇒ for each `red_names` entry `name@run_id`: `ci-run-probe.sh --repo <o/r> --check <name> --run-id <run_id>` (bounded by `--max-probes`, default 5; beyond the bound ⇒ finding without probe); `untrusted_infra` ⇒ `note<TAB><name><TAB>untrusted_infra — passed to the drain (D3)`; else a finding as ONE JSON line built with `jq -n --arg` (`{"severity":"BLOCKING","category":"new","file":"ci","check":…,"run_id":…,"description":"required check <name> failed on <sha>","log_tail":<wrapped text>}`), log tail from `gh run view <run_id> --log-failed` (run id `-` or a failed fetch ⇒ `"log_tail":"(log unavailable)"`). Anything else ⇒ `ci-read: none — required=<state>` / `— <reason>`. Always exit 0. If `wait-for-checks.sh` cannot read checks for a past `--sha` (Validation 3c), add the smallest read it needs (or read `gh api repos/<o>/<r>/commits/<sha>/check-runs` filtered to the required contexts from `drain-gh-read.sh required-checks`) and say so in the evidence file.
- **Row scoping (`--only-paths <glob>…`):** keeps only rows whose mutation target path matches one of the given `lanes:` globs (same literal-prefix/glob reading as `lanes:`); other rows print nothing for that call. Rows that test a sibling's code are therefore left to Phase 4.5, which runs after integration over every row.
- **Phase 3 placement:** Single-Agent step 3 (and the Sequential path's "same deterministic gate"): after the `verify-provides.sh` result is handled and before step 3b, run the pin script; `not_held` ⇒ ONE re-spawn of the worker (same spawn template, `Retry context:` = the `not_held` lines verbatim as data), then ONE re-run; any result after that is recorded via Context-Keeper as a `pin_mutations:` decision and the run continues. Parallel path: the same in `execute-manager.md`'s poll loop, re-spawning in the same worktree.
- **Phase 4.5 placement:** at the top of each iteration, BEFORE the reviewer spawn, run the pin script with the same `--cache`; after the reviewer returns and BEFORE `fixable_issues` is built, run `phase45-ci-read.sh <pr_url> --sha <current head>` once (placed after the review, not before it: right after a push the new head's checks are almost always pending, and the review takes 7–10 min) and append each finding to `fixable_issues`; a CI finding makes the iteration a fix iteration even on a reviewer PASS. Each `note` line (D3) is recorded in the Phase 4.5 output and the `## Outcome` summary, never a finding and never an escalation reason.
- **Prompts:** the fix-worker / worker test sentence becomes: "Run `bash scripts/ci-local.sh --affected` (the project's affected plan, which includes every static CI gate) where the project has it, else the project's own targeted check — never the full `ci-local.sh` pool from a background worker." Keep the waiter phrase lines next to any `tests locally` anchor that remains.
- **FINALIZE / PR body:** the evidence file `docs/evidence/automate-speed-02-phase45-rounds.md` is the record; FINALIZE's PR body links to it. The `/automate` merge GATE's `validation-gate` reads the PR body for the running-system step (3) — that copy is the engine's / owner's step, not the worker's.
- **Release:** changelog fragment only (`changelog.d/automate-speed-02-phase45-rounds.md`); never hand-edit version files — `bash scripts/check-version-bump.sh` must pass.

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/self-heal-advisory/SKILL.md`, `skills/review-heal/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope beyond the requirement's `## Touches`: `execute-manager.md` (parallel-path gate), `review-heal/SKILL.md` (drain fix-worker prompts the requirement's scope 3 names), `prompt-token-budgets.json` + `ARCHITECTURE_CONTRACTS.md` (supervisor 108 / code-reviewer 205 headroom), `test-closed-enum-pins-seam.sh` (pins the reviewer paragraph), two new scripts + their tests (Feasibility (Phase 2.5)) | HIGH | All in `lanes:`; lane L1 of this wave touches only `skills/automate-loop/**`, `automate-helpers.sh`, `docs/LANE_GATES.md` — disjoint. Budget raises use measured + ~10% with the mirrored row in the same commit |
| "Retry like an outputs gap" conflicts with today's outputs-gap handling (human adjudication) (Feasibility (Phase 2.5)) | MEDIUM | Decided: ONE bounded automatic re-spawn, then record and carry to Phase 4.5 where `not_held` is BLOCKING; never adjudication, never a pause |
| PR #533's pin rows are prose, so Validation 3 on that brief yields mostly `unverified` (Feasibility (Phase 2.5)) | MEDIUM | AC 11 (3b) transcribes the 16 rows into the grammar and runs them for real; D1 fallback keeps the reviewer covering prose rows, so no coverage is lost |
| The installed plugin, not this branch, runs this item's own Phase 3/4.5 — the new gates do not police this PR | LOW | Pins + seam tests + Validation evidence; re-measure per Validation 4 after release |
| A cached `held` survives a change in a file the pin reads that is neither its target nor its test file | LOW | Honest limit in the script header; Phase 4.5 re-runs on any target/test change, and the reviewer still reads the diff |
| New `gh run view --log-failed` read and a new external-text surface (Feasibility (Phase 2.5) finding (c)) | MEDIUM | `phase45-ci-read.sh` falls back to `"log_tail":"(log unavailable)"` on any failure and still exits 0; the tail is capped (≤40 lines / ≤4000 bytes) and wrapped by `wrap-external-text.sh` as DATA before any prompt sees it; tests stub `gh` for both the failure and an instruction-like log line |
| Mutation literals interpolated through sed/perl produce silently-invalid mutants (lesson fa32a308) | MEDIUM | Fixed-string matching only; every mutant validated (non-empty, differs, `bash -n`); invalid ⇒ `unverified`, AC 2 |
| Fix-worker prompt edits trip `test-no-self-matching-wait.sh` / `test-dispatch-pr-review.sh` drift guards | MEDIUM | Touched-file invariants list both; worker runs `bash scripts/ci-local.sh --affected` plus those tests by name |
| Self-heal lessons: a PASS is not drain-clean and a max-iteration ESCALATED's last fix is unreviewed (lesson 7c40ad9b) | LOW | The CI read is exactly the cheap signal that closes part of that gap; no claim beyond it |

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-14-automate-speed-02-phase45-rounds.md
```

## Plan Review: PASS (attempt 3/3)
- Deferred (LOW, below fix floor): review-heal invariant quotes the two-line DRAIN_SCRIPTS drift comment as one string — use the single-line anchor `prose without adding it here fails test-dispatch-pr-review.sh`; the `--bound 0` → `--bound 60` pin row lacks a trailing "⇒ leg red (the stubbed `wait-for-checks.sh` records a non-zero bound)".

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-14T06:33:38Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/538
- **Branch:** feature/automate-speed-02-phase45-rounds
- **Files changed:** 22
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 2
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** run-pin-mutations.sh (Phase 3 gate + cached Phase 4.5 reuse, --budget, --only-paths) and phase45-ci-read.sh (one red-CI read per iteration → BLOCKING finding) shipped with worker/fix-worker prompts on ci-local.sh --affected; 3 heal iterations fixed 6 findings (2 HIGH, 4 MEDIUM), all reproduced; the iteration-3 fix 7d8fbde is unreviewed; ground_truth 2/2; risk high_risk=true (advisory).

## Not verified
- **Supervisor Phase 3 / Phase 4.5 prose wiring (pin gate, PIN-MUTATION VERDICTS, CI read)** — seam-tested only; the installed plugin, not this branch, ran this item's own Phase 3/4.5 (subtask 1)
- **execute-manager parallel-path pin re-spawn** — needs a multi-subtask parallel run (subtask 1)
